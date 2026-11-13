extends Node3D
## Toma de referencia de los remedios tal como los ve el jugador al arrancar.
## Usa una cámara propia en el spawn, así la imagen no depende de dónde haya
## quedado la cámara del juego.
##
##     godot --path game res://dev/remedy_shot.tscn \
##         --fixed-fps 30 --quit-after 6 --write-movie shot.png

## Pedido a mano: los mismos valores que imprime `_apply_spawn`.
const EYE := Vector3(0.115139, 0.65, -1.574154)
const HEADING := 173.8


func _ready() -> void:
	var game: Game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	var shot := Camera3D.new()
	shot.fov = game.camera.fov
	add_child(shot)
	shot.global_position = EYE
	shot.rotation_degrees = Vector3(0.0, HEADING, 0.0)
	shot.current = true
	print("[SHOT] cámara del jugador en ", EYE)
