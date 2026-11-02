class_name MouseInput
extends RefCounted
## Control de reemplazo: mouse y teclado imitan al tracker de la cabeza.
##
## Existe para poder jugar (y grabar la demo) sin cámara, sin Python y sin
## MediaPipe. Devuelve exactamente el mismo formato que un paquete del tracker,
## así el juego no sabe de dónde viene la entrada.
##
## Los grados se imitan con el borde de la ventana: mover el mouse al borde
## equivale a girar la cabeza el ángulo máximo.

## Grados de giro que representa tener el mouse en el borde lateral.
const YAW_RANGE_DEG := 30.0
## Grados de cabeceo con el mouse en el borde superior o inferior.
const PITCH_RANGE_DEG := 18.0
## Zona muerta alrededor del centro, para poder apuntar fino.
const DEAD_ZONE := 0.03
const ZOOM_KEY := KEY_CTRL


func read(viewport: Viewport) -> Dictionary:
	if not DisplayServer.window_is_focused():
		# Sin foco la posición del mouse no significa nada: si no, al cambiar de
		# ventana la cabeza se iría sola hasta el borde.
		return _frame(Vector2.ZERO, false, "None")

	var size := viewport.get_visible_rect().size
	var head := Vector2.ZERO
	if size.x > 1.0 and size.y > 1.0:
		# La Y de la ventana crece hacia abajo y la de la cabeza hacia arriba.
		# Con X pasa al revés: mover el mouse a la izquierda gira a la izquierda.
		var offset := (viewport.get_mouse_position() - size * 0.5) / (size * 0.5)
		head = Vector2(-_dead_zone(offset.x), -_dead_zone(offset.y)) \
			* Vector2(YAW_RANGE_DEG, PITCH_RANGE_DEG)

	var grabbing := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	var palm_open := Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT)
	var zooming := Input.is_key_pressed(ZOOM_KEY)

	var gesture := "None"
	if grabbing:
		gesture = "Closed_Fist"
	elif palm_open:
		gesture = "Open_Palm"

	return _frame(head, grabbing or palm_open, gesture, zooming)


func _frame(head: Vector2, hand: bool, gesture: String, zooming := false) -> Dictionary:
	return {
		"face": true,
		"head_yaw": head.x,
		"head_pitch": head.y,
		"blink_l": 0.0,
		"blink_r": 0.0,
		"hand": hand,
		"gesture": gesture,
		"zoom_hand": zooming,
		"zoom_gesture": "Open_Palm" if zooming else "None",
		"hand_depth": 0.5,
	}


## Deja el centro quieto y mantiene el resto proporcional, sin saltos.
func _dead_zone(value: float) -> float:
	return signf(value) * maxf(absf(value) - DEAD_ZONE, 0.0) / (1.0 - DEAD_ZONE)
