class_name GazeCamera
extends Camera3D
## La cabeza de Kaiser.
##
## Kaiser está paralizado: no camina, solo mueve la cabeza. La cabeza del
## jugador se copia casi uno a uno, en grados: girar 20° la cabeza gira 20° la
## cámara. Si la sostiene contra un borde, empieza a girar sobre sí mismo, así
## puede terminar de dar la vuelta (360°) girando la cabeza.

@export_group("Sensibilidad")
## Multiplicador del giro. 1.0 = uno a uno con la cabeza. Más alto = menos cuello.
@export var gain := 1.5
## Grados de zona muerta: por debajo no se mueve, así no tiembla quieto.
@export var dead_zone := 0.5
## Cuánto gira la cabeza como máximo sin empezar el giro completo.
@export var max_yaw := 38.0
@export var max_pitch := 22.0
## Escapes por si la cámara quedara al revés en tu setup.
@export var invert_x := false
@export var invert_y := false
## Suavizado del movimiento (más alto, más seco).
@export var smoothing := 15.0

@export_group("Giro completo")
## Grados de cabeza a partir de los cuales la cabeza sigue girando.
@export var edge_threshold := 15.0
## Segundos que hay que sostenerlo para que arranque el giro.
@export var edge_delay := 0.3
@export var edge_speed := 90.0
## Grados extra de cabeza que hacen falta para llegar a la velocidad máxima.
@export var edge_ramp := 12.0

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
var _edge_time := 0.0


## [param head] es la pose del jugador en grados (X = giro, Y = cabeceo).
## [param can_look] es false si no hay lectura confiable de la cabeza.
## [param can_turn] además exige que nada tape la cara.
func follow(head: Vector2, can_look: bool, can_turn: bool, delta: float) -> void:
	var yaw_target := 0.0
	var pitch_target := 0.0

	if can_look:
		var hx := head.x * (-1.0 if invert_x else 1.0)
		var hy := head.y * (-1.0 if invert_y else 1.0)
		# Con zoom el campo visual se cierra: el mismo giro mueve menos la
		# imagen, que es justo lo que hace falta para apuntar fino.
		var precision := lerpf(1.0, zoom_fov / base_fov, zoom_level)
		yaw_target = clampf(_beyond_dead_zone(hx) * gain * precision, -max_yaw, max_yaw)
		pitch_target = clampf(_beyond_dead_zone(hy) * gain * precision, -max_pitch, max_pitch)
		_turn_if_edge(hx, can_turn and zoom_level < 0.2, delta)
	else:
		_edge_time = maxf(_edge_time - 2.0 * delta, 0.0)

	var rate := 1.0 - exp(-smoothing * delta)
	_yaw = lerpf(_yaw, yaw_target, rate)
	_pitch = lerpf(_pitch, pitch_target, rate)
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
	_edge_time = 0.0


## Rumbo actual en grados, para el HUD de depuración.
func heading_degrees() -> int:
	return int(fposmod(heading + _yaw, 360.0))


## Quita la zona muerta sin cambiar la escala: 5° con zona de 1.5° son 3.5°.
func _beyond_dead_zone(degrees: float) -> float:
	return signf(degrees) * maxf(absf(degrees) - dead_zone, 0.0)


func _turn_if_edge(yaw: float, allowed: bool, delta: float) -> void:
	if not allowed or absf(yaw) <= edge_threshold:
		_edge_time = maxf(_edge_time - 2.0 * delta, 0.0)
		return

	_edge_time += delta
	if _edge_time > edge_delay:
		var push := clampf((absf(yaw) - edge_threshold) / edge_ramp, 0.0, 1.0)
		heading += signf(yaw) * push * edge_speed * delta
