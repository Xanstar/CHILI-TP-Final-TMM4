extends Node
# Autoload "EyeInput" de la rama legacy.
#
# Es un adaptador: el juego original (Godot/juego3d.gd) espera la interfaz vieja
# (gaze normalizado entre -1 y 1, blink promedio, palma_lista), pero el tracker
# nuevo manda la pose en grados (head_yaw, head_pitch) y el parpadeo por ojo.
#
# Asi el juego original queda intacto y se lleva igual las mejoras de camara:
#   - pose por landmarks, en grados, sin blendshapes
#   - parpadeo por EAR, por ojo
#   - "sin cara" ya no cuenta como "ojos cerrados"
#   - manos con fallback por geometria, desde el tracker
#
#  - mano DERECHA: agarrar (palma abierta y despues puno) y abrir la mano para
#    entregar.
#  - mano IZQUIERDA: zoom (palma abierta).

signal agarrar

@export var palma_min := 0.3   # segundos de palma abierta antes de poder agarrar
@export var puno_min := 0.1    # segundos de puno cerrado para confirmar
@export var enfriar := 0.8     # espera despues de agarrar
# Grados de cabeza que equivalen a 1.0 de mirada. El juego multiplica por
# giro_x (90) y giro_y (60), asi que estos divisores dan un mapeo uno a uno.
@export var yaw_por_unidad := 90.0
@export var pitch_por_unidad := 60.0
# Suavizado de la mirada: mas alto, mas seco.
@export var suavizado := 0.35

var udp := PacketPeerUDP.new()
var face := false
var gaze := Vector2.ZERO
var blink := 0.0
var eyes_closed_time := 0.0
var hand := false              # mano derecha a la vista
var gesture := "None"          # gesto de la mano derecha
var zoom_hand := false         # mano izquierda a la vista
var zoom_gesture := "None"     # gesto de la mano izquierda
var palma_lista := false       # true cuando la palma derecha lleva abierta el tiempo suficiente

var _sin_datos := 0.0
var _palma_t := 0.0
var _sin_palma := 0.0
var _puno_t := 0.0
var _espera := 0.0


func _ready():
	if udp.bind(4242, "127.0.0.1") != OK:
		push_warning("EyeInput: no pude escuchar el puerto 4242.")


func _process(delta):
	# --- datos que llegan de Python ---
	while udp.get_available_packet_count() > 0:
		var d = JSON.parse_string(udp.get_packet().get_string_from_utf8())
		if typeof(d) != TYPE_DICTIONARY:
			continue
		_sin_datos = 0.0
		face = d.get("face", false)
		hand = d.get("hand", false)
		gesture = d.get("gesture", "None")
		zoom_hand = d.get("zoom_hand", false)
		zoom_gesture = d.get("zoom_gesture", "None")
		if face:
			# Grados a la escala que espera el juego. Se recorta a +-1.5 para
			# que un giro exagerado no mande la cabeza al infinito.
			var objetivo := Vector2(
				clampf(d.get("head_yaw", 0.0) / yaw_por_unidad, -1.5, 1.5),
				clampf(d.get("head_pitch", 0.0) / pitch_por_unidad, -1.5, 1.5))
			gaze = gaze.lerp(objetivo, suavizado)
			blink = (d.get("blink_l", 0.0) + d.get("blink_r", 0.0)) / 2.0

	# si Python se cierra, no nos quedamos con el ultimo valor
	_sin_datos += delta
	if _sin_datos > 1.0:
		face = false
		hand = false
		zoom_hand = false

	# --- ojos cerrados ---
	# Solo cuenta con los dos ojos cerrados y con cara a la vista. Antes, perder
	# la camara contaba como "ojos cerrados" y el juego lo penalizaba.
	if face and blink > 0.6:
		eyes_closed_time += delta
	else:
		eyes_closed_time = 0.0

	# --- gesto de agarrar (mano derecha): palma abierta y despues puno ---
	if hand and gesture == "Open_Palm":
		_palma_t += delta
		_sin_palma = 0.0
	else:
		_sin_palma += delta
		if _sin_palma > 1.0:
			_palma_t = 0.0   # paso mucho tiempo: hay que volver a abrir la mano

	if hand and gesture == "Closed_Fist":
		_puno_t += delta
	else:
		_puno_t = 0.0

	_espera = maxf(_espera - delta, 0.0)
	palma_lista = hand and _palma_t >= palma_min

	if _puno_t >= puno_min and _palma_t >= palma_min and _espera <= 0.0:
		_palma_t = 0.0
		_puno_t = 0.0
		_espera = enfriar
		agarrar.emit()
