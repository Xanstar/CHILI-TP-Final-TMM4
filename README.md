# CHILI — versión de respaldo (rama `legacy/original-camara`)

Este es el **juego original** de
[`SofiaDiaz-dm/TP-Final---TMM4`](https://github.com/SofiaDiaz-dm/TP-Final---TMM4)
(commit `207f9dd`), tal como estaba: el cuarto hecho con primitivas, el HUD
propio, los cuatro finales y `Godot/juego3d.gd` de un solo archivo.

La diferencia con el original es una sola: **la cámara funciona**. Se reemplazó
el tracker por el de la versión nueva, que lee la cabeza por landmarks (en
grados), el parpadeo por EAR y las manos por geometría, y trae argumentos de
línea de comandos. `Godot/eye_input.gd` es un adaptador que traduce el protocolo
nuevo a lo que el juego viejo espera (`gaze` normalizado), así que el resto del
juego no se tocó.

También se corrigió el arranque: `project.godot` apuntaba a una escena de prueba
vacía y F5 no abría el juego.

## Cómo jugar

```bash
python tracker/tracker.py     # en una terminal
godot --path Godot            # en otra
```

En Windows alcanza con `run-game.bat`.

| Acción | Gesto |
| --- | --- |
| Mirar / girar la cabeza | girar la cabeza (sostener en el borde gira 360°) |
| Agarrar un objeto | palma derecha abierta y después puño |
| Entregar | abrir la mano mirando a CHILI |
| Zoom | palma izquierda abierta |
| Calibrar | mirar al frente y apretar `Enter` |
| Mostrar datos | `F1` |

El juego viejo conserva sus teclas propias (`Enter` y `F1`): solo se sacaron las
que se habían agregado en la versión nueva.

## Qué NO tiene esta rama

- El baño GLB: acá el cuarto sigue hecho con primitivas.
- Los remedios con modelos 3D reales: siguen siendo figuras de color.
- El apagón nuevo, el lock-on de remedios y el final de los tres remedios
  restaurado.
- El refactor en módulos (`game/src/...`).

Si querés eso, está la rama principal. El detalle de **todos** los cambios está
en [`CAMBIOS.md`](../../blob/main/CAMBIOS.md) de esa rama.

## Pruebas

```bash
python tracker/test_pose.py
godot --headless --path Godot --import
```

## Créditos

- MediaPipe y sus modelos: Google, Apache 2.0.
- El resto del código y los assets: los del repositorio original.
