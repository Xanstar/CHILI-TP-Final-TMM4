extends Node3D
## Herramienta de diagnóstico: comprueba que los remedios estén apoyados sobre
## la repisa del lavabo.
##
##     godot --headless --path game res://dev/probe_surface.tscn
##
## Levanta la escena real (así los valores son los que ve el jugador) y, para
## cada remedio, castea un rayo hacia abajo y compara con su base. No forma
## parte del juego.

const SINK_NODE := "Sink_001_Bathtube_0"
const TOLERANCE := 0.02


func _ready() -> void:
	var game: Game = load("res://main.tscn").instantiate()
	add_child(game)
	await get_tree().process_frame

	var tris := _sink_triangles(game)
	if tris.is_empty():
		print("no encontré ", SINK_NODE)
		get_tree().quit()
		return

	var failures := 0
	for remedy: Pickup in game.remedies:
		var at := remedy.global_position
		var half := _half_height(remedy)
		var bottom := at.y - half
		var surface := _top_at(tris, at.x, at.z)
		var gap := bottom - surface
		var ok := absf(gap) <= TOLERANCE
		if not ok:
			failures += 1
		print("%-7s base y=%.3f  repisa y=%.3f  diferencia %+.3f  %s" % [
			remedy.item_name, bottom, surface, gap, "OK" if ok else "FLOJA"])
	print("REMEDIOS: %s" % ("OK" if failures == 0 else "%d mal ubicados" % failures))
	get_tree().quit()


## La mitad de la altura de la malla visible: es lo que hay entre el centro del
## remedio y el objeto que tiene debajo.
func _half_height(remedy: Pickup) -> float:
	for child in remedy.get_children():
		if child is MeshInstance3D:
			return (child as MeshInstance3D).get_aabb().size.y * 0.5 * remedy.scale.y
	return 0.0


func _sink_triangles(game: Game) -> Array:
	var sink := _find(game, SINK_NODE) as MeshInstance3D
	if sink == null:
		return []
	var arrays := sink.mesh.surface_get_arrays(0)
	var verts := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
	var indices := arrays[Mesh.ARRAY_INDEX] as PackedInt32Array
	var xf := sink.global_transform
	var out := []
	var i := 0
	while i + 2 < indices.size():
		var a := xf * verts[indices[i]]
		var b := xf * verts[indices[i + 1]]
		var c := xf * verts[indices[i + 2]]
		i += 3
		out.append({
			"box": AABB(a, Vector3.ZERO).expand(b).expand(c),
			"a": a, "b": b, "c": c,
		})
	return out


## Y de la cara más alta del lavabo justo arriba/abajo del punto (x, z).
func _top_at(tris: Array, x: float, z: float) -> float:
	var best := -9.0
	var from := Vector3(x, 2.0, z)
	var down := Vector3(0, -1, 0)
	for tri in tris:
		var box: AABB = tri["box"]
		if x < box.position.x or x > box.end.x:
			continue
		if z < box.position.z or z > box.end.z:
			continue
		var hit: Variant = Geometry3D.ray_intersects_triangle(
			from, down, tri["a"], tri["b"], tri["c"])
		if hit != null:
			best = maxf(best, (hit as Vector3).y)
	return best


func _find(node: Node, wanted: StringName) -> Node:
	if node.name == wanted:
		return node
	for c in node.get_children():
		var hit := _find(c, wanted)
		if hit != null:
			return hit
	return null
