"""Puente entre la camara y el juego.

Lee la cara y las manos con MediaPipe y manda por UDP un JSON por cuadro con la
pose de la cabeza, el parpadeo y los gestos de cada mano. El juego escucha en el
puerto 4242 (ver game/src/input/eye_input.gd).

La camara manda la POSE DE LA CABEZA, no la direccion de los ojos: los
blendshapes de mirada son muy ruidosos y no distinguen "miro de reojo" de "giro
la cabeza". Con landmarks, girar la cabeza mueve la nariz respecto de las
esquinas de los ojos, y de ahi sale un angulo en grados (la cuenta vive en
pose.py).

    python tracker.py                 # con ventana de la camara
    python tracker.py --no-preview    # solo manda datos
    python tracker.py --fake          # sin camara, datos sinteticos

Los modelos .task tienen que estar en models/ (al lado de este archivo).
"""

from __future__ import annotations

import argparse
import json
import math
import socket
import time
from dataclasses import dataclass
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

from pose import head_pose

MODELS = Path(__file__).parent / "models"

# Frame de la cara que se analiza siempre.
FACE_MODEL = MODELS / "face_landmarker.task"
HAND_MODEL = MODELS / "gesture_recognizer.task"

# Si una mano tapa la cara, se sostiene la ultima pose este tiempo.
FACE_GRACE = 1.5


@dataclass
class Config:
    host: str = "127.0.0.1"
    port: int = 4242
    camera: int = 0
    preview: bool = True
    mirror_hands: bool = False
    hand_every: int = 1
    fake: bool = False


class Tracker:
    """Una lectura de camara, un diccionario con todo lo que el juego necesita."""

    def __init__(self, config: Config) -> None:
        self.config = config
        self._started = time.time()
        self._last_timestamp = -1
        self._frame_index = 0

        self._face = vision.FaceLandmarker.create_from_options(
            vision.FaceLandmarkerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=str(FACE_MODEL)),
                running_mode=vision.RunningMode.VIDEO,
                output_face_blendshapes=True,
                num_faces=1,
            )
        )
        self._hands = vision.GestureRecognizer.create_from_options(
            vision.GestureRecognizerOptions(
                base_options=mp_python.BaseOptions(model_asset_path=str(HAND_MODEL)),
                running_mode=vision.RunningMode.VIDEO,
                num_hands=2,
            )
        )

        self._last_face: dict | None = None
        self._last_face_at = 0.0
        self._last_hands = {"hand": False, "gesture": "None",
                            "zoom_hand": False, "zoom_gesture": "None"}

    def read(self, frame) -> dict:
        """Analiza un cuadro y devuelve el estado listo para mandar."""
        timestamp = self._timestamp()
        face = self._read_face(frame, timestamp)
        hands = self._read_hands(frame, timestamp)

        # Si una mano tapa la cara, MediaPipe pierde la cara un instante:
        # se sostiene la ultima pose para que la cabeza no pegue saltos.
        if face is None and hands["hand"] and self._last_face is not None:
            if time.time() - self._last_face_at < FACE_GRACE:
                face = self._last_face

        payload = {
            "face": face is not None,
            "hand": hands["hand"],
            "gesture": hands["gesture"],
            "zoom_hand": hands["zoom_hand"],
            "zoom_gesture": hands["zoom_gesture"],
        }
        if face is not None:
            payload.update(face)

        self._frame_index += 1
        return payload

    def overlay(self, frame, payload: dict) -> None:
        """Dibuja el estado sobre el cuadro de la ventana de depuracion."""
        if payload["face"]:
            text = (f"cabeza  yaw {payload['head_yaw']:+5.1f} deg   "
                    f"pitch {payload['head_pitch']:+5.1f} deg   "
                    f"parpadeo {payload['blink_l']:.2f}/{payload['blink_r']:.2f}")
        else:
            text = "sin cara"
        hands = f"derecha: {payload['gesture']}    izquierda: {payload['zoom_gesture']}"
        cv2.putText(frame, text, (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)
        cv2.putText(frame, hands, (10, 65), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 200, 255), 2)

    def close(self) -> None:
        self._face.close()
        self._hands.close()

    def _timestamp(self) -> int:
        # MediaPipe exige tiempos estrictamente crecientes.
        now = int((time.time() - self._started) * 1000)
        if now <= self._last_timestamp:
            now = self._last_timestamp + 1
        self._last_timestamp = now
        return now

    def _read_face(self, frame, timestamp: int) -> dict | None:
        image = mp.Image(image_format=mp.ImageFormat.SRGB,
                         data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
        result = self._face.detect_for_video(image, timestamp)
        if not result.face_landmarks or not result.face_blendshapes:
            return None

        landmarks = result.face_landmarks[0]
        height, width = frame.shape[:2]
        angles = head_pose(landmarks, height, width)
        if angles is None:
            return None

        shapes = {s.category_name: s.score for s in result.face_blendshapes[0]}
        face = {
            # 0 = abierto, 1 = cerrado. Se manda cada ojo por separado: el
            # juego decide que un parpadeo rapido no es "ojos cerrados".
            "blink_l": shapes["eyeBlinkLeft"],
            "blink_r": shapes["eyeBlinkRight"],
            **angles,
        }
        self._last_face = face
        self._last_face_at = time.time()
        return face

    def _read_hands(self, frame, timestamp: int) -> dict:
        state = {"hand": False, "gesture": "None", "zoom_hand": False, "zoom_gesture": "None"}
        if self._frame_index % max(self.config.hand_every, 1) != 0:
            # Se reutiliza la ultima lectura de manos para ahorrar cuadros.
            return self._last_hands

        # El cuadro se espeja para que "derecha" e "izquierda" sean las del
        # jugador y no las de la imagen.
        mirrored = cv2.cvtColor(cv2.flip(frame, 1), cv2.COLOR_BGR2RGB)
        image = mp.Image(image_format=mp.ImageFormat.SRGB, data=mirrored)
        result = self._hands.recognize_for_video(image, timestamp)

        for i, _landmarks in enumerate(result.hand_landmarks):
            side = "Right"
            if i < len(result.handedness) and result.handedness[i]:
                side = result.handedness[i][0].category_name
            gesture = "None"
            if i < len(result.gestures) and result.gestures[i]:
                gesture = result.gestures[i][0].category_name

            is_right = side == "Right"
            if self.config.mirror_hands:
                is_right = not is_right

            if is_right:
                state["hand"] = True
                state["gesture"] = gesture
            else:
                state["zoom_hand"] = True
                state["zoom_gesture"] = gesture

        self._last_hands = state
        return state


class FakeSource:
    """Datos sinteticos: sirve para probar el juego sin camara ni modelos."""

    def __init__(self) -> None:
        self._started = time.time()

    def read(self, frame=None) -> dict:
        t = time.time() - self._started
        return {
            "face": True,
            # Barrido lento a los costados y un cabeceo mas rapido.
            "head_yaw": 28.0 * math.sin(t * 0.6),
            "head_pitch": 12.0 * math.sin(t * 0.9),
            "blink_l": 0.0,
            "blink_r": 0.0,
            "hand": False,
            "gesture": "None",
            "zoom_hand": False,
            "zoom_gesture": "None",
        }

    def overlay(self, frame, payload: dict) -> None:
        cv2.putText(frame, "modo fake", (10, 30), cv2.FONT_HERSHEY_SIMPLEX, 0.7, (0, 255, 0), 2)

    def close(self) -> None:
        pass


def parse_args() -> Config:
    parser = argparse.ArgumentParser(description="Tracker de mirada y manos para CHILI.")
    parser.add_argument("--host", default="127.0.0.1", help="destino UDP (default 127.0.0.1)")
    parser.add_argument("--port", type=int, default=4242, help="puerto UDP (default 4242)")
    parser.add_argument("--camera", type=int, default=0, help="indice de camara (default 0)")
    parser.add_argument("--no-preview", action="store_true", help="no abrir la ventana de la camara")
    parser.add_argument("--mirror-hands", action="store_true",
                        help="invertir manos si el juego toma derecha por izquierda")
    parser.add_argument("--hand-every", type=int, default=1,
                        help="analizar las manos cada N cuadros (subilo si va lento)")
    parser.add_argument("--fake", action="store_true", help="datos sinteticos, sin camara")
    args = parser.parse_args()
    return Config(
        host=args.host,
        port=args.port,
        camera=args.camera,
        preview=not args.no_preview,
        mirror_hands=args.mirror_hands,
        hand_every=args.hand_every,
        fake=args.fake,
    )


def main() -> int:
    config = parse_args()
    sender = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    destination = (config.host, config.port)

    capture = None
    if config.fake:
        source = FakeSource()
        print("Modo fake: mandando datos sinteticos.")
    else:
        source = Tracker(config)
        capture = cv2.VideoCapture(config.camera)
        if not capture.isOpened():
            print(f"No pude abrir la camara {config.camera}.")
            return 1
        print(f"Camara {config.camera} abierta. Mandando a {config.host}:{config.port}.")
    print("q en la ventana para salir, Ctrl+C en la consola para cortar.")

    try:
        while True:
            frame = None
            if capture is not None:
                ok, frame = capture.read()
                if not ok:
                    print("Se corto la imagen de la camara.")
                    return 1

            payload = source.read(frame)
            sender.sendto(json.dumps(payload).encode(), destination)

            if config.preview:
                if frame is None:
                    frame = np.zeros((480, 640, 3), dtype=np.uint8)
                view = cv2.flip(frame, 1)
                source.overlay(view, payload)
                cv2.imshow("CHILI - tracker", view)
                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
    except KeyboardInterrupt:
        pass
    finally:
        source.close()
        if capture is not None:
            capture.release()
        cv2.destroyAllWindows()
        sender.close()

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
