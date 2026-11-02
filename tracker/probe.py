"""Prueba en vivo de la deteccion y la pose de la cabeza.

Abre la camara, espera a que haya una cara y recorre seis fases guiadas por la
ventana de preview (frente, izquierda, derecha, arriba, abajo, ojos cerrados).

Guarda un JSON con todas las lecturas y un PNG anotado por fase, para poder
revisar despues si el problema es de deteccion (no hay cara) o de la cuenta
(los angulos no se mueven).

    python tracker/probe.py
    python tracker/probe.py --camera 1 --seconds 3
    python tracker/probe.py --no-preview
"""

from __future__ import annotations

import argparse
import json
import statistics
import sys
import tempfile
import time
from pathlib import Path

import cv2
import mediapipe as mp
import numpy as np
from mediapipe.tasks import python as mp_python
from mediapipe.tasks.python import vision

sys.path.insert(0, str(Path(__file__).parent))
from pose import EYE_CORNER_A, EYE_CORNER_B, NOSE_TIP, head_pose  # noqa: E402

MODELS = Path(__file__).parent / "models"
FACE_MODEL = MODELS / "face_landmarker.task"

# (clave, texto en pantalla, segundos de grabacion)
PHASES = [
    ("frente", "MIRA AL FRENTE, cara relajada", 2.5),
    ("izquierda", "GIRA LA CABEZA A TU IZQUIERDA", 2.5),
    ("derecha", "GIRA LA CABEZA A TU DERECHA", 2.5),
    ("arriba", "MIRA HACIA ARRIBA", 2.5),
    ("abajo", "MIRA HACIA ABAJO", 2.5),
    ("cerrados", "CIERRA LOS DOS OJOS", 2.5),
]

WAIT_FACE_SECONDS = 25.0
LEAD_IN_SECONDS = 1.2


def open_camera(index: int) -> cv2.VideoCapture:
    for backend in (cv2.CAP_MSMF, cv2.CAP_DSHOW, cv2.CAP_ANY):
        capture = cv2.VideoCapture(index, backend)
        if capture.isOpened():
            print(f"camara {index} abierta con {capture.getBackendName()}")
            return capture
        capture.release()
    raise SystemExit(f"no pude abrir la camara {index}")


def detect(landmarker, frame, timestamp: int) -> dict:
    image = mp.Image(image_format=mp.ImageFormat.SRGB,
                     data=cv2.cvtColor(frame, cv2.COLOR_BGR2RGB))
    result = landmarker.detect_for_video(image, timestamp)
    if not result.face_landmarks:
        return {"face": False}

    landmarks = result.face_landmarks[0]
    height, width = frame.shape[:2]
    angles = head_pose(landmarks, height, width)
    shapes = {}
    if result.face_blendshapes:
        shapes = {s.category_name: s.score for s in result.face_blendshapes[0]}

    span = abs(landmarks[EYE_CORNER_B].x - landmarks[EYE_CORNER_A].x)
    read = {
        "face": True,
        "yaw": angles["head_yaw"] if angles else None,
        "pitch": angles["head_pitch"] if angles else None,
        "span": span,
        "blink_l": shapes.get("eyeBlinkLeft"),
        "blink_r": shapes.get("eyeBlinkRight"),
        "matrix": None,
    }
    if result.facial_transformation_matrixes:
        matrix = np.asarray(result.facial_transformation_matrixes[0])
        read["matrix"] = [round(float(v), 4) for v in matrix[:3, :3].reshape(-1)]
    return read


def draw(frame, read: dict, prompt: str, countdown: float) -> np.ndarray:
    view = cv2.flip(frame, 1)
    height = view.shape[0]
    cv2.rectangle(view, (0, 0), (view.shape[1], 74), (0, 0, 0), -1)
    cv2.putText(view, prompt, (12, 32), cv2.FONT_HERSHEY_SIMPLEX, 0.8, (60, 230, 255), 2)
    if countdown > 0:
        cv2.putText(view, f"en {countdown:.0f}...", (12, 64),
                    cv2.FONT_HERSHEY_SIMPLEX, 0.7, (255, 255, 255), 2)
    if not read.get("face"):
        cv2.putText(view, "SIN CARA", (12, height - 20), cv2.FONT_HERSHEY_SIMPLEX,
                    0.8, (60, 60, 255), 2)
        return view

    yaw = read["yaw"] or 0.0
    pitch = read["pitch"] or 0.0
    cv2.putText(view, f"yaw {yaw:+.1f}   pitch {pitch:+.1f}", (12, height - 20),
                cv2.FONT_HERSHEY_SIMPLEX, 0.8, (0, 255, 0), 2)
    return view


def median(values) -> float | None:
    clean = [v for v in values if v is not None]
    return round(statistics.median(clean), 2) if clean else None


def summarize(phase_key: str, records: list[dict]) -> dict:
    faces = [r for r in records if r.get("face")]
    rate = len(faces) / len(records) if records else 0.0
    matrix = None
    for record in faces:
        if record.get("matrix"):
            matrix = record["matrix"]
            break
    return {
        "fase": phase_key,
        "cuadros": len(records),
        "deteccion": round(rate, 2),
        "yaw": median([r.get("yaw") for r in faces]),
        "pitch": median([r.get("pitch") for r in faces]),
        "ojo_izq": median([r.get("blink_l") for r in faces]),
        "ojo_der": median([r.get("blink_r") for r in faces]),
        "span": median([r.get("span") for r in faces]),
        "matriz": matrix,
    }


def main() -> int:
    config = parse_args()
    capture = open_camera(config.camera)
    width = int(capture.get(cv2.CAP_PROP_FRAME_WIDTH))
    height = int(capture.get(cv2.CAP_PROP_FRAME_HEIGHT))
    print(f"resolucion: {width}x{height}")

    landmarker = vision.FaceLandmarker.create_from_options(
        vision.FaceLandmarkerOptions(
            base_options=mp_python.BaseOptions(model_asset_path=str(FACE_MODEL)),
            running_mode=vision.RunningMode.VIDEO,
            output_face_blendshapes=True,
            output_facial_transformation_matrixes=True,
            num_faces=1,
        )
    )

    out_dir = Path(config.out) if config.out else Path(tempfile.gettempdir()) / "chili-probe"
    out_dir.mkdir(parents=True, exist_ok=True)
    print(f"resultados en {out_dir}")

    started = time.time()
    last_ts = -1

    def stamp() -> int:
        nonlocal last_ts
        now = int((time.time() - started) * 1000)
        last_ts = max(last_ts + 1, now)
        return last_ts

    # Calentar la camara: los primeros cuadros salen oscuros o fuera de foco.
    for _ in range(12):
        capture.read()

    if not wait_for_face(capture, landmarker, stamp, config.preview):
        print("NO SE DETECTO NINGUNA CARA EN 25 SEGUNDOS.")
        print("Revisa luz, que la cara entre completa en el cuadro y que la camara no este tapada.")
        capture.release()
        landmarker.close()
        return 2

    report = {"resolucion": [width, height], "fases": []}
    for key, prompt, seconds in PHASES:
        records = run_phase(capture, landmarker, stamp, prompt, seconds, config.preview, out_dir, key)
        report["fases"].append(summarize(key, records))
        if config.preview:
            cv2.destroyAllWindows()

    (out_dir / "probe.json").write_text(
        json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    capture.release()
    landmarker.close()
    print_table(report)
    print(f"\nJSON: {out_dir / 'probe.json'}")
    return 0


def wait_for_face(capture, landmarker, stamp, preview: bool) -> bool:
    deadline = time.time() + WAIT_FACE_SECONDS
    while time.time() < deadline:
        ok, frame = capture.read()
        if not ok:
            continue
        read = detect(landmarker, frame, stamp())
        if read.get("face"):
            print("cara detectada, arrancamos")
            return True
        if preview:
            view = draw(frame, read, "ACERCATE, NO TE VEO", 0.0)
            cv2.imshow("CHILI - prueba de camara", view)
            cv2.waitKey(1)
    return False


def run_phase(capture, landmarker, stamp, prompt, seconds, preview, out_dir, key) -> list[dict]:
    print(f"fase: {prompt}")
    records = []
    best = None
    best_span = 0.0

    lead_in = time.time() + LEAD_IN_SECONDS
    while time.time() < lead_in:
        ok, frame = capture.read()
        if not ok:
            continue
        read = detect(landmarker, frame, stamp())
        if preview:
            cv2.imshow("CHILI - prueba de camara",
                       draw(frame, read, prompt, lead_in - time.time()))
            if cv2.waitKey(1) & 0xFF == ord("q"):
                return records

    deadline = time.time() + seconds
    while time.time() < deadline:
        ok, frame = capture.read()
        if not ok:
            continue
        read = detect(landmarker, frame, stamp())
        records.append(read)
        if read.get("face") and (read.get("span") or 0.0) > best_span:
            best_span = read.get("span") or 0.0
            best = frame.copy()
        if preview:
            cv2.imshow("CHILI - prueba de camara", draw(frame, read, prompt, 0.0))
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break

    if best is not None:
        cv2.imwrite(str(Path(out_dir) / f"{key}.png"), cv2.flip(best, 1))
    return records


def print_table(report: dict) -> None:
    print("\n%-12s %8s %10s %10s %8s %8s" % (
        "fase", "detecc.", "yaw", "pitch", "palo izq", "palo der"))
    for phase in report["fases"]:
        print("%-12s %7.0f%% %10s %10s %8s %8s" % (
            phase["fase"], phase["deteccion"] * 100,
            _fmt(phase["yaw"]), _fmt(phase["pitch"]),
            _fmt(phase["ojo_izq"]), _fmt(phase["ojo_der"])))


def _fmt(value) -> str:
    return "-" if value is None else f"{value:+.2f}"


def parse_args():
    parser = argparse.ArgumentParser(description="Prueba en vivo de la camara.")
    parser.add_argument("--camera", type=int, default=0, help="indice de camara")
    parser.add_argument("--seconds", type=float, default=None,
                        help="segundos por fase (default 2.5)")
    parser.add_argument("--out", default=None, help="carpeta de resultados")
    parser.add_argument("--no-preview", action="store_true", help="sin ventana")
    args = parser.parse_args()
    args.preview = not args.no_preview
    if args.seconds:
        for i, (key, prompt, _) in enumerate(PHASES):
            PHASES[i] = (key, prompt, args.seconds)
    return args


if __name__ == "__main__":
    raise SystemExit(main())
