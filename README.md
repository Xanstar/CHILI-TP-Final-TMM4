# CHILI

Kaiser está paralizado en el medio de un cuarto y solo puede mover la cabeza y
levantar una pata. CHILI, el bicho, se está muriendo en el piso de enfrente: hay
que mirarlo de cerca para ver el detalle, agarrar los tres remedios y
entregárselos. Pero mirarlo fascina, y fascinarse contagia.

Se juega **con los ojos y las manos**, sin mouse ni teclado: una cámara lee
hacia dónde mirás y qué hacen tus manos. Si no hay cámara, hay un modo mouse
para poder jugarlo y grabarlo igual.

## Estructura

```
game/                  Proyecto Godot 4.6 (abrí esta carpeta)
  main.tscn            Escena de entrada
  src/
    input/             De dónde viene la entrada
      eye_input.gd     Autoload: única fuente de entrada del juego
      udp_tracker.gd   Escucha los paquetes de Python
      mouse_input.gd   Reemplazo con mouse y teclado
    game/
      main.gd          Orquestador: reglas, estados y finales
      gaze_camera.gd   La cabeza de Kaiser (mirada, giro de 360°, zoom)
    world/
      room.gd          El cuarto, las paredes y el desorden
      chili.gd         CHILI y su deterioro
      door.gd          La salida
      pickup.gd        Un remedio
      kaiser_body.gd   Las patas y el contagio
    core/
      shapes.gd        Fábrica de mallas, materiales y luces
      cli.gd           Banderas de línea de comandos
    ui/
      hud.gd           Viñeta, negro, lista de remedios y finales
  dev/
    smoke.tscn         Prueba de humo sin ventana
tracker/
  tracker.py           Cámara -> UDP: cabeza, parpadeo y gestos
  pose.py              Geometría de la cabeza (landmarks -> grados)
  test_pose.py         Prueba de esa geometría, sin cámara
  models/              Modelos de MediaPipe
```

La regla es simple: **`main.gd` decide, los demás dibujan o leen**. Ningún actor
del mundo sabe nada del estado del juego; reciben valores ya calculados.

## Instalación

1. Godot 4.6 (o posterior). El proyecto está pensado para la versión estándar,
   no hace falta la de C#.
2. Python 3.10–3.12 con las dependencias del tracker:

```bash
python -m venv .venv
.venv\Scripts\pip install -r tracker/requirements.txt
```

## Jugar

```bash
python tracker/tracker.py          # en una terminal
godot --path game                  # en otra
```

En Windows hay dos atajos que hacen todo:

- `run-game.bat` — abre el tracker y el juego.
- `open-editor.bat` — abre solo el editor de Godot.

### Si algo no abre

Doble click sobre `game/project.godot` **no** funciona: Windows no sabe con qué
programa abrirlo salvo que hayas instalado Godot con instalador. Usá
`open-editor.bat`, o esta línea con las rutas completas:

```bat
set GODOT=%LOCALAPPDATA%\Programs\Godot\Godot_v4.6.3-stable_win64.exe
"%GODOT%" --editor --path game
```

`run-game.bat` avisa si falta Python, `mediapipe` o Godot en lugar de cerrarse
sin decir nada.

### Controles

| Acción | Con cámara | Con mouse |
| --- | --- | --- |
| Mirar / girar la cabeza | girar la cabeza | mover el mouse |
| Elegir un remedio | palma derecha abierta | click derecho |
| Agarrar | puño después de la palma | click izquierdo |
| Entregar | abrir la mano mirando a CHILI | click derecho mirando a CHILI |
| Zoom | palma izquierda abierta | `Ctrl` |
| Calibrar | `Enter` | `Enter` |
| Mostrar datos | `F1` | `F1` |
| Cambiar cámara/mouse | `F2` | `F2` |

El juego arranca con `Enter`: poné la cabeza mirando al frente y confirmá el cero.

Si no llega ningún paquete en 3 segundos, pasa solo a mouse y teclado. Si el
tracker arranca después, vuelve a la cámara sin que hagas nada.

### Banderas

```bash
godot --path game -- --mouse     # forzar el modo mouse
godot --path game -- --auto      # arrancar sin Enter (para grabar)
python tracker/tracker.py --no-preview     # sin ventana de cámara
python tracker/tracker.py --fake           # datos sintéticos, sin cámara
python tracker/tracker.py --help
```

## El protocolo

El tracker manda un JSON por paquete UDP a `127.0.0.1:4242`:

```json
{
  "face": true,
  "head_yaw": 12.4,
  "head_pitch": -3.1,
  "blink_l": 0.02,
  "blink_r": 0.05,
  "hand": true,
  "gesture": "Closed_Fist",
  "zoom_hand": false,
  "zoom_gesture": "None"
}
```

- `head_yaw`: giro de la cabeza en grados. Positivo = hacia la izquierda del
  jugador. `head_pitch`: cabeceo en grados, positivo = mentón arriba.
- Los ángulos salen de la geometría de la cara (nariz contra esquinas de los
  ojos), no de blendshapes: así "miro de reojo" y "giro la cabeza" no se
  confunden, y el signo no depende de cómo esté espejada la imagen.
- `blink_l` / `blink_r`: 0 = abierto, 1 = cerrado, cada ojo por separado. El
  juego usa el párpado solo como efecto visual; penalizar exige que los dos
  ojos queden cerrados más de medio segundo.
- `gesture` / `zoom_gesture`: `"None"`, `"Open_Palm"`, `"Closed_Fist"`, etc.
- Si `face` es `false`, el resto de los campos de la cara no vienen. Eso es "sin
  cámara", que no es lo mismo que "ojos cerrados".

Para probar el juego sin Python alcanza con `--mouse`: no necesita el protocolo.

## Cómo se gana

Hay cuatro finales, y tres de ellos son malos:

- **ayuda** — entregar los tres remedios antes de que CHILI se apague.
- **pérdida** — CHILI se muere solo mientras mirás para otro lado.
- **contemplación** — el contagio llega al máximo de tanto mirarlo.
- **abandono** — sostener la mirada en la puerta hasta irse.

Los primeros 20 segundos de cada partida no hay tutorial: la lista de la esquina
derecha son los remedios que faltan, y el brillo de cada objeto dice si lo podés
agarrar.

## Prueba de humo

```bash
godot --headless --path game res://dev/smoke.tscn
python tracker/test_pose.py
```

La primera levanta la escena real y ejercita agarrar, soltar y entregar un
remedio, además de comprobar que un parpadeo no dispara el estado "ojos
cerrados" y que los ángulos de la cabeza llegan con el signo correcto. La
segunda prueba la geometría de la cabeza sin cámara ni MediaPipe.
