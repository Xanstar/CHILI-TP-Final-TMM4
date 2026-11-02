extends Node
## Prueba de humo, sin ventana.
##
## Levanta la escena real y ejercita el ciclo de un remedio: agarrar, dejar,
## agarrar y entregar. Sirve para verificar que el refactor no rompió nada antes
## de abrir el editor.
##
##     godot --headless res://dev/smoke.tscn

var _failures := 0


func _ready() -> void:
	_check_input()

	var game: Game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	game.running = true
	var remedy: Pickup = game.remedies[0]

	_expect(game.remedies.size() == 3, "hay 3 remedios")
	_expect(remedy.state == Pickup.State.ROOM, "el remedio arranca en el cuarto")

	# Agarrar mirándolo.
	game.looked_remedy = remedy
	game.call("_on_grab")
	_expect(game.carried == remedy, "agarró el remedio mirado")
	_expect(remedy.state == Pickup.State.HAND, "el remedio está en la mano")
	_expect(remedy.get_parent() == game.camera, "el remedio cuelga de la cámara")

	# No se puede llevar dos cosas.
	game.call("_on_grab")
	_expect(game.carried == remedy, "no agarra un segundo remedio")

	# Soltarlo lo devuelve a su lugar.
	game.call("_drop")
	_expect(game.carried == null, "soltar vacía la mano")
	_expect(remedy.state == Pickup.State.ROOM, "el remedio volvió al cuarto")
	_expect(remedy.position.is_equal_approx(remedy.home), "volvió a su posición")

	# Entregarlo lo saca del mundo y cura.
	var gravity_before: float = game.gravity
	game.looked_remedy = remedy
	game.call("_on_grab")
	game.call("_deliver")
	_expect(game.delivered == 1, "cuenta la entrega")
	_expect(remedy.state == Pickup.State.DELIVERED, "el remedio quedó entregado")
	_expect(not remedy.visible, "el remedio entregado no se ve")
	_expect(game.gravity < gravity_before, "entregar baja la gravedad")

	print("SMOKE: %s" % ("OK" if _failures == 0 else "%d fallas" % _failures))
	get_tree().quit(0 if _failures == 0 else 1)


func _expect(condition: bool, description: String) -> void:
	if not condition:
		_failures += 1
		printerr("  FALLA: ", description)


## Parpadeo y "ojos cerrados" tienen que ser mecánicas separadas.
## Se alimenta EyeInput a mano para no depender de una cámara.
func _check_input() -> void:
	var step := 1.0 / 60.0

	# Un parpadeo: los párpados se cierran, la mecánica no se activa.
	EyeInput._ingest(_face_frame(1.0, 1.0), step)
	_expect(EyeInput.blink > 0.3, "el párpado se cierra en un parpadeo")
	_expect(EyeInput.eyes_closed_time == 0.0, "un parpadeo no acumula ojos cerrados")

	# Sostener los dos ojos cerrados sí es el estado "ojos cerrados".
	for i in 120:
		EyeInput._ingest(_face_frame(1.0, 1.0), step)
	_expect(EyeInput.eyes_closed_time > 1.0, "cerrar los dos ojos acumula tiempo")

	# Un guiño (un ojo solo) no cuenta.
	for i in 120:
		EyeInput._ingest(_face_frame(1.0, 0.0), step)
	_expect(EyeInput.eyes_closed_time == 0.0, "un guiño no es ojos cerrados")

	# Sin cara no es "ojos cerrados" ni debe arrastrar el estado.
	for i in 120:
		EyeInput._ingest(_face_frame(1.0, 1.0), step)
	# La gracia de seguimiento es 0.4 s: hay que superarla para que se pierda.
	for i in 30:
		EyeInput._ingest({"face": false}, step)
	_expect(not EyeInput.tracking, "sin cara se pierde el seguimiento")
	_expect(EyeInput.eyes_closed_time == 0.0, "sin cara no es ojos cerrados")

	# La pose llega con signo positivo cuando la cabeza gira a la izquierda.
	EyeInput._ingest(_face_frame(0.0, 0.0, 20.0), step)
	_expect(EyeInput.head.x > 0.0, "girar a la izquierda da ángulo positivo")
	EyeInput._ingest(_face_frame(0.0, 0.0, -20.0), step * 30.0)
	_expect(EyeInput.head.x < 0.0, "girar a la derecha da ángulo negativo")


func _face_frame(left: float, right: float, yaw := 0.0) -> Dictionary:
	return {
		"face": true,
		"head_yaw": yaw,
		"head_pitch": 0.0,
		"blink_l": left,
		"blink_r": right,
	}
