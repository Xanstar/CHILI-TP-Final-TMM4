class_name Room
extends Node3D
## El baño donde está Kaiser: paredes con azulejos, piso, bañera, lavabo,
## espejo, botiquín y decoración.
##
## El botiquín es donde viven los remedios: se colocan dentro de él para que
## tenga sentido que Kaiser los encuentre ahí.

const HALF_SIZE := 12.0
const WALL_HEIGHT := 5.0
const CLUTTER_COUNT := 48
const SEED := 7

var _clear_zones: Array[Vector3] = []
var _medicine_cabinet: Node3D = null


func build(clear_zones: Array[Vector3]) -> void:
	_clear_zones = clear_zones
	_ensure_texture()
	_build_environment()
	_build_floor()
	_build_walls()
	_build_fixtures()
	_build_clutter()


## Coloca el botiquín y devuelve su posición para que los remedios se pongan ahí.
func medicine_cabinet_position() -> Vector3:
	if _medicine_cabinet != null:
		return _medicine_cabinet.position + Vector3(0, 1.2, 0.3)
	return Vector3(0, 1.2, 0)


## Repisa para el frasco. Vive acá porque es mueble, no un objeto agarrable.
func add_shelf(at: Vector3, yaw_degrees: float) -> void:
	var shelf := Node3D.new()
	shelf.position = at
	shelf.rotation_degrees.y = yaw_degrees
	add_child(shelf)
	var wood := Shapes.material(Color(0.35, 0.25, 0.15))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(1.6, 0.08, 0.55)), wood, Vector3(0, 1.0, 0))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(0.07, 1.0, 0.07)), wood, Vector3(-0.7, 0.5, 0))
	Shapes.add_mesh(shelf, Shapes.box(Vector3(0.07, 1.0, 0.07)), wood, Vector3(0.7, 0.5, 0))


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.1, 0.12)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.45, 0.5)
	env.ambient_light_energy = 0.7
	env.fog_enabled = true
	env.fog_light_color = Color(0.15, 0.18, 0.2)
	env.fog_density = 0.03
	var world := WorldEnvironment.new()
	world.environment = env
	add_child(world)


func _build_floor() -> void:
	_place("floor_tiled", Vector3(0, 0, 0), 0.0, 12.0)


func _build_walls() -> void:
	var span := HALF_SIZE * 2.0
	# Paredes con azulejos.
	_place("wall_tiled_straight", Vector3(0, 0, -HALF_SIZE + 1.0), 0.0, 12.0)
	_place("wall_tiled_straight", Vector3(0, 0, HALF_SIZE - 1.0), 180.0, 12.0)
	_place("wall_tiled_straight", Vector3(-HALF_SIZE + 1.0, 0, 0), 90.0, 12.0)
	_place("wall_tiled_straight", Vector3(HALF_SIZE - 1.0, 0, 0), -90.0, 12.0)
	# Esquinas.
	_place("wall_tiled_corner_inner", Vector3(-HALF_SIZE + 1.0, 0, -HALF_SIZE + 1.0), 0.0, 1.0)
	_place("wall_tiled_corner_inner", Vector3(HALF_SIZE - 1.0, 0, -HALF_SIZE + 1.0), 90.0, 1.0)
	_place("wall_tiled_corner_inner", Vector3(HALF_SIZE - 1.0, 0, HALF_SIZE - 1.0), 180.0, 1.0)
	_place("wall_tiled_corner_inner", Vector3(-HALF_SIZE + 1.0, 0, HALF_SIZE - 1.0), 270.0, 1.0)


func _build_fixtures() -> void:
	# Botiquín: ahí viven los remedios. Cerca del centro para que se vea.
	_medicine_cabinet = _place("cabinet_bathroom", Vector3(-2.5, 1.2, -2.0), -20.0, 1.0)
	# Espejo y lavabo cerca del botiquín.
	_place("mirror", Vector3(-3.5, 1.5, -1.5), -20.0, 1.0)
	# Bañera en una esquina (más cerca).
	_place("bath", Vector3(5.0, 0, -5.0), 45.0, 1.0)
	# Toalla.
	_place("towel_stacked", Vector3(-2.0, 1.0, -0.5), -20.0, 1.0)
	# Estante con cosas.
	_place("wall_shelf", Vector3(-4.0, 1.5, -3.0), -20.0, 1.0)
	_place("container_bathroom_A_blue", Vector3(-4.0, 1.7, -3.0), -20.0, 1.0)
	# Planta y patito.
	_place("plant", Vector3(4.0, 0, 4.0), 0.0, 1.0)
	_place("ducky", Vector3(4.5, 0.5, -4.5), 0.0, 1.0)
	# Alfombra.
	_place("mat", Vector3(0, 0.01, 1.5), 0.0, 1.0)
	# Luces.
	Shapes.add_light(self, Vector3(0, 4.0, 0), Color(1.0, 0.95, 0.85), 2.0, 15.0)
	Shapes.add_light(self, Vector3(-2.5, 2.5, -2.0), Color(1.0, 0.9, 0.7), 1.0, 6.0)


func _build_clutter() -> void:
	# Menos desorden: un baño está más ordenado que un cuarto abandonado.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	var mats := [
		Shapes.material(Color(0.6, 0.6, 0.65)),
		Shapes.material(Color(0.5, 0.55, 0.5)),
	]
	var placed := 0
	var attempts := 0
	while placed < 12 and attempts < 200:
		attempts += 1
		var yaw := rng.randf_range(-180.0, 180.0)
		var distance := rng.randf_range(4.0, 9.0)
		if not _is_clear(yaw, distance):
			continue
		var mat: Material = mats[rng.randi() % mats.size()]
		var height := rng.randf_range(0.3, 0.6)
		Shapes.add_mesh(self, Shapes.box(Vector3(
			rng.randf_range(0.3, 0.6),
			height,
			rng.randf_range(0.3, 0.6))),
			mat, Shapes.polar(yaw, distance, height / 2.0))
		placed += 1


func _is_clear(yaw: float, distance: float) -> bool:
	for zone in _clear_zones:
		if Shapes.angle_gap(yaw, zone.x) < zone.z and distance < zone.y + 0.8:
			return false
	return true


func _place(model_name: String, at: Vector3, yaw_degrees: float, scale: float) -> Node3D:
	var scene := load("res://assets/bathroom/%s.gltf" % model_name) as PackedScene
	if scene == null:
		push_warning("Room: no pude cargar %s" % model_name)
		return null
	var instance := scene.instantiate()
	instance.position = at
	instance.rotation_degrees.y = yaw_degrees
	instance.scale = Vector3.ONE * scale
	_fix_materials(instance)
	add_child(instance)
	return instance


## El importador de Godot no vincula la textura del GLTF. Se la asigna a mano.
func _fix_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh != null:
			for i in mesh.get_surface_count():
				var mat := mesh.surface_get_material(i)
				if mat is StandardMaterial3D:
					var smat := mat as StandardMaterial3D
					if smat.albedo_texture == null:
						smat.albedo_texture = _texture
	# Also check material_override
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.material_override is StandardMaterial3D:
			var smat := mi.material_override as StandardMaterial3D
			if smat.albedo_texture == null:
				smat.albedo_texture = _texture
	for child in node.get_children():
		_fix_materials(child)


var _texture: Texture2D = null


func _ensure_texture() -> void:
	if _texture == null:
		_texture = load("res://assets/bathroom/tiny_treats_texture_1.png") as Texture2D
