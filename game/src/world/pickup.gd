class_name Pickup
extends Node3D
## Un remedio: se puede mirar, agarrar con la mano derecha y entregar.

enum State { ROOM, HAND, DELIVERED }

## Transform local dentro de la pata de Kaiser cuando lo lleva.
const IN_HAND_POSITION := Vector3(0.1, -0.24, -0.5)
const IN_HAND_SCALE := 0.5

var item_name := ""
var state := State.ROOM
## Dónde vive cuando no lo tiene nadie.
var home := Vector3.ZERO
var home_yaw := 0.0

var _material: StandardMaterial3D


func setup(display_name: String, mesh: Mesh, color: Color, at: Vector3, yaw: float) -> void:
	item_name = display_name
	home = at
	home_yaw = yaw
	position = at
	rotation_degrees.y = yaw

	_material = Shapes.material(color, color, 0.25)
	Shapes.add_mesh(self, mesh, _material)
	Shapes.add_light(self, Vector3(0, 0.6, 0.5), color, 0.5, 2.2)


func is_available() -> bool:
	return state == State.ROOM


## Brillo: bajo si está tirado, alto si lo estás mirando, máximo si lo podés agarrar.
func set_highlight(energy: float) -> void:
	_material.emission_energy_multiplier = energy


func attach_to(hand: Node3D) -> void:
	state = State.HAND
	reparent(hand, false)
	position = IN_HAND_POSITION
	rotation = Vector3.ZERO
	scale = Vector3.ONE * IN_HAND_SCALE


func detach_to(parent: Node) -> void:
	state = State.ROOM
	reparent(parent, false)
	position = home
	rotation = Vector3(0.0, deg_to_rad(home_yaw), 0.0)
	scale = Vector3.ONE


func deliver() -> void:
	state = State.DELIVERED
	visible = false
