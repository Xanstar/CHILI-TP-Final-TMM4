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
