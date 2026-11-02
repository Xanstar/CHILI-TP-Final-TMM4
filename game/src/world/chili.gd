class_name Chili
extends Node3D
## CHILI: el bicho que se muere en el piso.
##
## No decide nada: solo se dibuja según la gravedad que le pasa el juego y se
## arrastra hacia la puerta cuando Kaiser quiere irse.

## Tamaño del cuerpo (0 = sano, 1 = crítico). Lo escribe el juego.
var gravity := 0.35

var base_position := Vector3.ZERO

var _skin: StandardMaterial3D
var _lump: MeshInstance3D
var _ears: Array[MeshInstance3D] = []
var _spots: Array[MeshInstance3D] = []
var _spot_material: StandardMaterial3D
var _light: OmniLight3D
var _time := 0.0


func build() -> void:
	base_position = position
	_skin = Shapes.material(Color(0.9, 0.88, 0.85))

	Shapes.add_mesh(self, Shapes.sphere(0.28), _skin, Vector3(0, 0.28, 0))
	Shapes.add_mesh(self, Shapes.sphere(0.17), _skin, Vector3(0, 0.58, 0.1))

	var eye := Shapes.material(Color.BLACK)
	Shapes.add_mesh(self, Shapes.sphere(0.025), eye, Vector3(-0.065, 0.62, 0.25))
	Shapes.add_mesh(self, Shapes.sphere(0.025), eye, Vector3(0.065, 0.62, 0.25))

	for side in [-1.0, 1.0]:
		_ears.append(Shapes.add_mesh(self, Shapes.capsule(0.045, 0.4), _skin,
			Vector3(side * 0.07, 0.85, 0.08)))

	_lump = Shapes.add_mesh(self, Shapes.sphere(0.1), Shapes.material(Color(0.35, 0.25, 0.3)),
		Vector3(0.22, 0.25, 0.15))

	_spot_material = Shapes.material(Color(0.3, 0.7, 0.2), Color(0.3, 0.9, 0.2), 0.5)
	var spot_positions := [
		Vector3(-0.1, 0.35, 0.24), Vector3(0.08, 0.2, 0.26), Vector3(0.0, 0.42, 0.24),
		Vector3(-0.18, 0.2, 0.2), Vector3(0.15, 0.4, 0.2), Vector3(0.0, 0.14, 0.24),
	]
	for spot_at in spot_positions:
		var spot := Shapes.add_mesh(self, Shapes.sphere(0.035), _spot_material, spot_at)
		spot.visible = false
		_spots.append(spot)

	_light = Shapes.add_light(self, Vector3(0, 1.2, 0.6), Color(0.75, 0.9, 0.85), 0.8, 3.5)


## [param bait] = destello de tentación, [param flash] = fogonazo de la entrega.
func apply(delta: float, bait: float, flash: float) -> void:
	_time += delta
	var sick := clampf(gravity, 0.0, 1.0)

	_skin.albedo_color = Color(0.9, 0.88, 0.85).lerp(Color(0.45, 0.3, 0.4), sick)
	_lump.scale = Vector3.ONE * (0.5 + sick * 1.8)
	for ear in _ears:
		ear.rotation.z = -signf(ear.position.x) * deg_to_rad(sick * 60.0)

	var visible_spots := int(sick * _spots.size() + 0.5)
	for i in _spots.size():
		_spots[i].visible = i < visible_spots

	_spot_material.emission_energy_multiplier = 0.4 + bait * 2.0
	_light.light_energy = 0.8 + bait * 2.5 + flash * 4.0
	rotation.z = sin(_time * 28.0) * 0.03 * sick * (1.0 + bait * 2.0)


## Se arrastra hacia [param target] una fracción [param amount] del camino.
func pull_towards(target: Vector3, amount: float, delta: float) -> void:
	position = base_position.lerp(target, amount * 0.85)
	if amount > 0.02:
		var direction := target - base_position
		rotation.y = lerp_angle(rotation.y, atan2(direction.x, direction.z), 4.0 * delta)
	else:
		rotation.y = lerp_angle(rotation.y, 0.0, 4.0 * delta)
