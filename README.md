# CHILI

Kaiser está paralizado en el medio de un cuarto y solo puede mover la cabeza y
levantar una pata. CHILI, el bicho, se está muriendo en el piso de enfrente: hay
que mirarlo de cerca para ver el detalle, agarrar los tres remedios y
entregárselos. Pero mirarlo fascina, y fascinarse contagia.

Se juega **con los ojos y las manos**: una cámara lee hacia dónde mirás y qué
hacen tus manos. No hay mouse ni teclado. Sin cámara no hay juego.

> **¿Venís del repo original?** Todo lo que cambió respecto de
> `SofiaDiaz-dm/TP-Final---TMM4` está en [CAMBIOS.md](CAMBIOS.md): cambios de
> código, estructura, escenario y narrativa, commit por commit.
>
> Si preferís una versión más parecida al trabajo original, existe la rama
> [`legacy/original-camara`](https://github.com/Xanstar/CHILI-TP-Final-TMM4/tree/legacy/original-camara):
> el juego de antes tal cual, pero con las mejoras de cámara de este repo.

## Estructura

```
game/                  Proyecto Godot 4.6 (abrí esta carpeta)
  main.tscn            Escena de entrada
  src/
    input/             De dónde viene la entrada
      eye_input.gd     Autoload: única fuente de entrada del juego
      udp_tracker.gd   Escucha los paquetes de Python
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
  assets/
    bathroom/          El baño (GLB de itch.io, ver README)
    remedies/          Botiquín, frasco y paño (GLB CC0 de Grab3D)
  dev/
    smoke.tscn         Prueba de humo sin ventana
    probe_surface.tscn Comprueba que los remedios no floten
    probe_deck.tscn    Mapa de la repisa: dónde se puede apoyar algo
    remedy_shot.tscn   Primer plano de los remedios, para revisarlos
    blackout_shot.tscn Cómo se ve el apagón, frame por frame
    door_shot.tscn     Cómo abre la puerta
tracker/
  tracker.py           Cámara -> UDP: cabeza, parpadeo y gestos
  pose.py              Geometría de la cabeza (landmarks -> grados)
  test_pose.py         Prueba de esa geometría, sin cámara
  probe.py             Prueba en vivo: detección y pose, con ventana guía
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

Todo se juega con la cámara. No hay teclado ni mouse: si el tracker no está
mandando datos, el juego no tiene entrada.

| Acción | Gesto |
| --- | --- |
| Mirar / girar la cabeza | girar la cabeza (llegar al borde gira el cuerpo) |
| Elegir un remedio | palma derecha abierta, apuntándolo con la mirada |
| Agarrar | cerrar el puño después de la palma |
| Entregar | abrir la mano mirando a CHILI con el remedio en la mano |
| Abrir / cerrar la puerta | palma o puño mirando la puerta |
| Zoom | palma izquierda abierta |
| Arrancar | ponerse frente a la cámara: espera sola y calibra |

El brillo de cada remedio dice si ya podés agarrarlo: al máximo, la palma ya
lleva el tiempo suficiente y el puño agarra.

Al arrancar, la cabeza queda mirando a la puerta. El rumbo se calcula desde el
spawn del jugador, así no hay que torcer el cuello para encontrarla.

### Dónde arranca cada cosa

Los dos spawn viven en `user://positions.cfg` (en Windows,
`%APPDATA%\Godot\app_userdata\CHILI\positions.cfg`) y quedaron fijos con los
valores que se eligieron caminando por el mapa durante el desarrollo. Si el
archivo no existe, se usan los valores por defecto de `main.gd`.

Los tres remedios están apoyados sobre la repisa del lavabo, dentro del baño y a
la vista desde el spawn. La altura sale de `DECK_Y` en `main.gd`: si alguien
mueve un objeto, `dev/probe_surface.tscn` avisa si quedó flotando.

Si no llega ningún paquete, el juego se queda esperando la cámara: no hay modo
alternativo. Cuando el tracker vuelve, la entrada vuelve sola.

### Banderas

```bash
godot --path game -- --auto      # arrancar sin esperar la calibración
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

Para probar el juego sin cámara está `python tracker/tracker.py --fake`: manda
datos sintéticos por el mismo protocolo, sin abrir la webcam.

## Cómo se gana

Hay cuatro finales, y solo uno es bueno:

- **ayuda** — entregar los tres remedios. CHILI respira; tus patas ya no son
  las mismas.
- **pérdida** — CHILI se apaga solo mientras mirás para otro lado.
- **contemplación** — el contagio llega al máximo de tanto mirarlo.
- **oscuridad** — cerrar la puerta gasta la energía, se apaga la luz y, cuando
  vuelve, CHILI ya está adentro, a un metro tuyo: el contagio se va al máximo.

Los primeros 20 segundos de cada partida no hay tutorial: la lista de la esquina
derecha son los remedios que faltan, y el brillo de cada objeto dice si lo podés
agarrar.

## Prueba de humo

```bash
godot --headless --path game res://dev/smoke.tscn
godot --headless --path game res://dev/probe_surface.tscn
python tracker/test_pose.py
```

La primera levanta la escena real y ejercita agarrar, soltar y entregar un
remedio, además de comprobar que un parpadeo no dispara el estado "ojos
cerrados" y que los ángulos de la cabeza llegan con el signo correcto. La
segunda mide la repisa del lavabo y confirma que ningún remedio quedó flotando.
La última prueba la geometría de la cabeza sin cámara ni MediaPipe.

Si la cámara no te detecta bien, corré `python tracker/probe.py`: abre la
cámara, te guía por seis posiciones con una ventana y guarda un JSON con las
lecturas y un PNG por fase. Sirve para saber si el problema es de detección
(no hay cara) o de la cuenta (los ángulos no se mueven).

## Créditos y licencias

- **El baño** (`game/assets/bathroom`) es un GLB descargado de itch.io. Antes de
  publicar el juego, revisá la licencia del pack original: el repo no la incluye.
- **Los tres remedios** (`game/assets/remedies`) son modelos de
  [Grab3D](https://grab3d.com), **CC0 1.0** (dominio público, sin atribución).
  Cada carpeta trae su `LICENSE.txt` y su `manifest.json` con el origen.
- **MediaPipe** y sus modelos (`tracker/models`) son de Google, con licencia
  Apache 2.0.
- El código del juego no tiene licencia todavía: si el repo va a ser público,
  conviene agregar un `LICENSE`.
