class_name Room
extends Node3D
## El cuarto donde está Kaiser: ambiente, paredes y desorden.
##
## El desorden es puramente decorativo: se reparte con una semilla fija para que
## el cuarto sea siempre el mismo, y nunca tapa a CHILI, la puerta ni los remedios.

const HALF_SIZE := 12.0
const WALL_HEIGHT := 5.0
const CLUTTER_COUNT := 48
const SEED := 7

## Zonas que quedan despejadas: (ángulo, distancia, margen en grados).
var _clear_zones: Array[Vector3] = []


func build(clear_zones: Array[Vector3]) -> void:
	_clear_zones = clear_zones
	_build_environment()
	_build_walls()
	_build_clutter()


## Repisa para el frasco. Vive acá porque es mueble, no un objeto agarrable.
func add_shelf(at: Vector3, yaw_degrees: float) -> void:
	var shelf := Node3D.new()
	shelf.position = at
	shelf.rotation_degrees.y = yaw_degrees
	add_child(shelf)
	var wood := Shapes.material(Color(0.2, 0.15, 0.1))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(1.6, 0.08, 0.55)), wood, Vector3(0, 1.0, 0))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(0.07, 1.0, 0.07)), wood, Vector3(-0.7, 0.5, 0))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(0.07, 1.0, 0.07)), wood, Vector3(0.7, 0.5, 0))


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.05, 0.07, 0.09)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.25, 0.3, 0.35)
	env.ambient_light_energy = 0.6
	env.fog_enabled = true
	env.fog_light_color = Color(0.12, 0.16, 0.18)
	env.fog_density = 0.04
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_walls() -> void:
	var floor_mat := Shapes.material(Color(0.18, 0.15, 0.13))
	var wall_mat := Shapes.material(Color(0.22, 0.24, 0.24))
	var span := HALF_SIZE * 2.0
	Shapes.add_mesh(self, Shapes.box(Vector3(span, 0.2, span)), floor_mat, Vector3(0, -0.1, 0))
	Shapes.add_mesh(self, Shapes.box(Vector3(span, WALL_HEIGHT, 0.3)), wall_mat,
		Vector3(0, WALL_HEIGHT / 2.0, -HALF_SIZE + 1.0))
	Shapes.add_mesh(self, Shapes.box(Vector3(span, WALL_HEIGHT, 0.3)), wall_mat,
		Vector3(0, WALL_HEIGHT / 2.0, HALF_SIZE - 1.0))
	Shapes.add_mesh(self, Shapes.box(Vector3(0.3, WALL_HEIGHT, span)), wall_mat,
		Vector3(-HALF_SIZE + 1.0, WALL_HEIGHT / 2.0, 0))
	Shapes.add_mesh(self, Shapes.box(Vector3(0.3, WALL_HEIGHT, span)), wall_mat,
		Vector3(HALF_SIZE - 1.0, WALL_HEIGHT / 2.0, 0))


func _build_clutter() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mats := [
		Shapes.material(Color(0.2, 0.17, 0.14)),
		Shapes.material(Color(0.16, 0.18, 0.18)),
		Shapes.material(Color(0.24, 0.2, 0.16)),
	]
	var placed := 0
	var attempts := 0
	while placed < CLUTTER_COUNT and attempts < 800:
		attempts += 1
		var yaw := rng.randf_range(-180.0, 180.0)
		var distance := rng.randf_range(3.0, 9.5)
		if not _is_clear(yaw, distance):
			continue
		var mat: Material = mats[rng.randi() % mats.size()]
		var piece := _random_piece(rng, mat, yaw, distance)
		piece.rotation_degrees.y = rng.randf_range(0.0, 90.0)
		placed += 1


func _is_clear(yaw: float, distance: float) -> bool:
	for zone in _clear_zones:
		if Shapes.angle_gap(yaw, zone.x) < zone.z and distance < zone.y + 0.8:
			return false
	return true


func _random_piece(rng: RandomNumberGenerator, mat: Material, yaw: float, distance: float) -> MeshInstance3D:
	match rng.randi() % 3:
		0:
			var size := Vector3(
				rng.randf_range(0.4, 1.0),
				rng.randf_range(0.4, 0.9),
				rng.randf_range(0.4, 0.9))
			return Shapes.add_mesh(self, Shapes.box(size), mat,
				Shapes.polar(yaw, distance, size.y / 2.0))
		1:
			var height := rng.randf_range(0.7, 1.0)
			return Shapes.add_mesh(self,
				Shapes.cylinder(rng.randf_range(0.28, 0.42), height), mat,
				Shapes.polar(yaw, distance, height / 2.0))
		_:
			var tall := rng.randf_range(1.4, 2.2)
			return Shapes.add_mesh(self, Shapes.box(Vector3(0.5, tall, 0.5)), mat,
				Shapes.polar(yaw, distance, tall / 2.0))
