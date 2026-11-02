extends Node
## Autoload "EyeInput": la única fuente de entrada del juego.
##
## Junta dos orígenes posibles y los expone igual:
##   - CAMERA: los paquetes UDP que manda tracker.py con la mirada y las manos.
##   - MOUSE: mouse y teclado, para jugar cuando no hay cámara.
##
## El resto del juego nunca consulta el origen, solo lee [member gaze],
## [member hand], [member zoom_hand] y escucha [signal grab].

signal grab
signal source_changed

enum Source { CAMERA, MOUSE }

const PORT := 4242
## Segundos sin paquetes antes de dar la lectura por perdida.
const STALE_AFTER := 1.0
## Segundos sin cámara antes de pasar solo a mouse y teclado.
const FALLBACK_AFTER := 3.0
## Qué tan rápido alcanza la mirada su valor nuevo (más alto, más seco).
const GAZE_SMOOTHING := 18.0
const BLINK_CLOSED := 0.6

const PALM_HOLD := 0.3
const FIST_HOLD := 0.1
const GRAB_COOLDOWN := 0.8

var source := Source.CAMERA

## Hay una cara en cámara.
var face := false
## Mirada relativa, en unidades del tracker. Positivo X = hacia su izquierda.
var gaze := Vector2.ZERO
## 0 = ojos abiertos, 1 = cerrados.
var blink := 0.0
var eyes_closed_time := 0.0

## Mano derecha a la vista.
var hand := false
var gesture := "None"
## Mano izquierda a la vista (zoom).
var zoom_hand := false
var zoom_gesture := "None"
## La palma derecha lleva abierta el tiempo suficiente como para elegir.
var palm_ready := false

var _udp := UdpTracker.new()
var _mouse := MouseInput.new()
var _time := 0.0
var _last_frame_at := 0.0
var _palm_time := 0.0
var _palm_missing := 0.0
var _fist_time := 0.0
var _cooldown := 0.0
var _armed := true


func _ready() -> void:
	# Leer la entrada antes que nadie: el juego decide con datos frescos.
	process_priority = -100
	if _udp.open(PORT) != OK:
		push_warning("EyeInput: no pude escuchar el puerto %d." % PORT)
	if Cli.has_flag("--mouse"):
		source = Source.MOUSE


func _process(delta: float) -> void:
	_time += delta

	var frame := _udp.poll()
	if not frame.is_empty():
		_last_frame_at = _time
		_ingest(frame, delta)
		# Si volvieron los paquetes, la cámara manda otra vez.
		if source != Source.CAMERA:
			set_source(Source.CAMERA)
	elif source == Source.CAMERA:
		_watch_for_stall(delta)
	else:
		_ingest(_mouse.read(get_viewport()), delta)

	_update_grab(delta)


## Cambiar entre cámara y mouse en caliente (F2).
func toggle_source() -> void:
	set_source(Source.MOUSE if source == Source.CAMERA else Source.CAMERA)


func set_source(new_source: Source) -> void:
	if new_source == source:
		return
	source = new_source
	_last_frame_at = _time if new_source == Source.CAMERA else -1000.0
	face = new_source == Source.MOUSE
	hand = false
	gesture = "None"
	zoom_hand = false
	zoom_gesture = "None"
	palm_ready = false
	_palm_time = 0.0
	_fist_time = 0.0
	_cooldown = 0.0
	_armed = true
	print("[EyeInput] entrada: %s" % ("cámara" if new_source == Source.CAMERA else "mouse"))
	source_changed.emit()


## Con cámara, una mano abierta delante de la cara ensucia la lectura de mirada.
## Con mouse no existe ese problema: el control es el mouse mismo.
func hand_obstructs() -> bool:
	return source == Source.CAMERA and hand and gesture != "Closed_Fist"


func uses_camera() -> bool:
	return source == Source.CAMERA


func _ingest(frame: Dictionary, delta: float) -> void:
	face = frame.get("face", false)
	hand = frame.get("hand", false)
	gesture = frame.get("gesture", "None")
	zoom_hand = frame.get("zoom_hand", false)
	zoom_gesture = frame.get("zoom_gesture", "None")

	if face:
		var target := Vector2(frame.get("gaze_x", 0.0), frame.get("gaze_y", 0.0))
		# Suavizado independiente del framerate.
		gaze = gaze.lerp(target, 1.0 - exp(-GAZE_SMOOTHING * delta))
		blink = (frame.get("blink_l", 0.0) + frame.get("blink_r", 0.0)) * 0.5
		eyes_closed_time = 0.0 if blink <= BLINK_CLOSED else eyes_closed_time + delta
	else:
		eyes_closed_time += delta


func _watch_for_stall(delta: float) -> void:
	var silent := _time - _last_frame_at
	if silent > FALLBACK_AFTER:
		push_warning("EyeInput: sin datos de la cámara, paso a mouse y teclado.")
		set_source(Source.MOUSE)
	elif silent > STALE_AFTER:
		# Se cortó el paquete: no nos quedamos con la última pose congelada.
		face = false
		hand = false
		gesture = "None"
		zoom_hand = false
		zoom_gesture = "None"
		eyes_closed_time += delta


func _update_grab(delta: float) -> void:
	if hand and gesture == "Open_Palm":
		_palm_time += delta
		_palm_missing = 0.0
	else:
		_palm_missing += delta
		# Pasó demasiado tiempo sin palma: hay que volver a abrir la mano.
		if _palm_missing > 1.0:
			_palm_time = 0.0

	if hand and gesture == "Closed_Fist":
		_fist_time += delta
	else:
		_fist_time = 0.0
		_armed = true

	_cooldown = maxf(_cooldown - delta, 0.0)
	palm_ready = hand and _palm_time >= PALM_HOLD

	# Palma abierta y después puño. El puño tiene que soltarse antes del
	# siguiente agarre, si no un solo gesto dispararía varias veces.
	if _armed and palm_ready and _fist_time >= FIST_HOLD and _cooldown <= 0.0:
		_armed = false
		_palm_time = 0.0
		_fist_time = 0.0
		_cooldown = GRAB_COOLDOWN
		grab.emit()
