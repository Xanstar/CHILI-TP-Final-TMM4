class_name MouseInput
extends RefCounted
## Control de reemplazo: mouse y teclado imitan al tracker de la cara.
##
## Existe para poder jugar (y grabar la demo) sin cámara, sin Python y sin
## MediaPipe. Devuelve exactamente el mismo formato que un paquete del tracker,
## así el juego no sabe de dónde viene la entrada.

## Cuánto aleja el mouse la mirada del centro. Bajo a propósito: con 1.0 la
## cabeza se iría al borde con cualquier movimiento.
const GAZE_SCALE := 0.5
const MAX_GAZE := 0.85
const ZOOM_KEY := KEY_CTRL


func read(viewport: Viewport) -> Dictionary:
	if not DisplayServer.window_is_focused():
		# Sin foco la posición del mouse no significa nada: si no, al cambiar de
		# ventana la cabeza se iría sola hasta el borde.
		return _neutral_frame()

	var size := viewport.get_visible_rect().size
	var gaze := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0:
		# Mouse a la izquierda = mirar a la izquierda. La Y de la ventana crece
		# hacia abajo y la de la mirada hacia arriba, por eso se invierte.
		var offset := (viewport.get_mouse_position() - size * 0.5) / (size * 0.5)
		gaze = Vector2(-offset.x, -offset.y) * GAZE_SCALE
		gaze = gaze.limit_length(MAX_GAZE)

	var grabbing := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var palm_open := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var zooming := Input.is_key_pressed(ZOOM_KEY)

	var gesture := "None"
	if grabbing:
		gesture = "Closed_Fist"
	elif palm_open:
		gesture = "Open_Palm"

	return {
		"face": true,
		"gaze_x": gaze.x,
		"gaze_y": gaze.y,
		"blink_l": 0.0,
		"blink_r": 0.0,
		"hand": grabbing or palm_open,
		"gesture": gesture,
		"zoom_hand": zooming,
		"zoom_gesture": "Open_Palm" if zooming else "None",
	}


func _neutral_frame() -> Dictionary:
	return {
		"face": true,
		"gaze_x": 0.0,
		"gaze_y": 0.0,
		"blink_l": 0.0,
		"blink_r": 0.0,
		"hand": false,
		"gesture": "None",
		"zoom_hand": false,
		"zoom_gesture": "None",
	}
