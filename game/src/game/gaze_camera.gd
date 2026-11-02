class_name GazeCamera
extends Camera3D
## La cabeza de Kaiser.
##
## Kaiser está paralizado: no camina, solo mueve la cabeza. La mirada mueve la
## cabeza dentro de un rango corto, y si la sostiene contra un borde empieza a
## girar sobre sí mismo, así puede terminar de dar la vuelta (360°) mirando.

@export_group("Sensibilidad")
## Grados de giro por unidad de mirada.
@export var yaw_per_gaze := 90.0
@export var pitch_per_gaze := 60.0
## Cuánto gira la cabeza solo con mover los ojos.
@export var max_yaw := 38.0
@export var max_pitch := 22.0
@export var invert_x := false
@export var invert_y := false

@export_group("Giro completo")
## Valor de mirada a partir del cual la cabeza sigue girando.
@export var edge_threshold := 0.45
## Segundos que hay que sostener la mirada en el borde para que empiece a girar.
@export var edge_delay := 0.5
@export var edge_speed := 90.0

@export_group("Zoom")
@export var base_fov := 75.0
## Campo visual con el zoom al máximo.
@export var zoom_fov := 38.0
@export var zoom_speed := 2.5

## 0 = sin zoom, 1 = al máximo.
var zoom_level := 0.0
## Giro acumulado sobre sí mismo, en grados.
var heading := 0.0

var _yaw := 0.0
var _pitch := 0.0
var _yaw_target := 0.0
var _pitch_target := 0.0
var _edge_time := 0.0


## [param can_look] es false si no hay lectura confiable de la mirada.
## [param can_turn] además exige que nada tape la cara.
func follow(gaze: Vector2, can_look: bool, can_turn: bool, delta: float) -> void:
	var precision := lerpf(1.0, zoom_fov / base_fov, zoom_level)

	if can_look:
		var gx := gaze.x * (-1.0 if invert_x else 1.0)
		var gy := gaze.y * (-1.0 if invert_y else 1.0)
		_yaw_target = clampf(gx * yaw_per_gaze * precision, -max_yaw, max_yaw)
		_pitch_target = clampf(gy * pitch_per_gaze * precision, -max_pitch, max_pitch)
		_turn_if_edge(gx, can_turn and zoom_level < 0.2, delta)
	else:
		_edge_time = maxf(_edge_time - 2.0 * delta, 0.0)

	_yaw = lerpf(_yaw, _yaw_target, 5.0 * delta)
	_pitch = lerpf(_pitch, _pitch_target, 5.0 * delta)
	rotation_degrees = Vector3(_pitch, heading + _yaw, 0.0)


## La mano izquierda abierta (o Ctrl) acerca la imagen y afina el pulso:
## el campo visual se cierra y la fascinación lo cierra todavía más.
func set_zoom(held: bool, fascination: float, delta: float) -> void:
	zoom_level = move_toward(zoom_level, 1.0 if held else 0.0, zoom_speed * delta)
	fov = lerpf(base_fov, zoom_fov, zoom_level) * lerpf(1.0, 0.7, fascination)


## Volver a mirar al frente: se usa al calibrar.
func recenter() -> void:
	heading = 0.0
	_yaw = 0.0
	_pitch = 0.0
	_yaw_target = 0.0
	_pitch_target = 0.0
	_edge_time = 0.0


## Rumbo actual en grados, para el HUD de depuración.
func heading_degrees() -> int:
	return int(fposmod(heading + _yaw, 360.0))


func _turn_if_edge(gx: float, allowed: bool, delta: float) -> void:
	if allowed and absf(gx) > edge_threshold:
		_edge_time += delta
		if _edge_time > edge_delay:
			var push := minf(absf(gx) - edge_threshold, 0.3) / 0.3
			heading += signf(gx) * push * edge_speed * delta
	else:
		_edge_time = maxf(_edge_time - 2.0 * delta, 0.0)
