extends Node
## Autoload "EyeInput": la única fuente de entrada del juego.
##
## Junta dos orígenes posibles y los expone igual:
##   - CAMERA: los paquetes UDP que manda tracker.py con la cabeza y las manos.
##   - MOUSE: mouse y teclado, para jugar cuando no hay cámara.
##
## El resto del juego nunca consulta el origen, solo lee [member head],
## [member hand], [member zoom_hand] y escucha [signal grab].
##
## El parpadeo y el estado "ojos cerrados" son cosas distintas a propósito:
## [member blink] es el párpado (visual, dura un instante) y
## [member eyes_closed_time] es la mecánica (mirar con los ojos cerrados un rato).
## Un parpadeo normal no llega a penalizar nada.

signal grab
signal source_changed

enum Source { CAMERA, MOUSE }

const PORT := 4242
## Segundos sin paquetes antes de dar la lectura por perdida.
const STALE_AFTER := 1.0
## Segundos sin cámara antes de pasar solo a mouse y teclado.
const FALLBACK_AFTER := 3.0
## Qué tan rápido alcanza la pose su valor nuevo (más alto, más seco).
const HEAD_SMOOTHING := 8.0
## Lo mismo para los párpados: más rápido, porque un parpadeo dura poco.
const BLINK_SMOOTHING := 25.0
## Por encima de esto un ojo cuenta como cerrado.
const EYES_CLOSED := 0.6
## Segundos sin cara antes de dar la lectura por perdida. Un poco de gracia para
## no parpadear entre "sigue" y "se perdió" cuando la cara se sale un instante.
const TRACKING_GRACE := 0.4

const PALM_HOLD := 0.15
const FIST_HOLD := 0.05
const GRAB_COOLDOWN := 0.5

var source := Source.CAMERA

## Hay una cara en cámara: hay lectura de cabeza confiable.
var tracking := false
var _raw_tracking := false
var _tracking_missing := 0.0
## Pose de la cabeza en grados: X = giro (+ a su izquierda), Y = cabeceo (+ arriba).
var head := Vector2.ZERO
## Párpados por separado, 0 = abierto y 1 = cerrado.
var blink_l := 0.0
var blink_r := 0.0
## El párpado promedio: 0 = abierto y 1 = cerrado. Es solo el efecto visual.
var blink := 0.0
## Segundos seguidos con LOS DOS ojos cerrados. Solo esto es mecánica.
var eyes_closed_time := 0.0
## Baseline de parpadeo calibrado: ojos abiertos del usuario.
var _blink_baseline_l := 0.0
var _blink_baseline_r := 0.0
var _blink_calibrated := false

## Mano derecha a la vista.
var hand := false
var gesture := "None"
## Mano izquierda a la vista (zoom).
var zoom_hand := false
var zoom_gesture := "None"
## Tamaño de la mano izquierda en la imagen: proxy de distancia a la cámara.
## 0 = lejos/pequeña, 1 = cerca/grande.
var hand_depth := 0.0
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
		set_source(Source.MOUSE)


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
	tracking = new_source == Source.MOUSE
	_raw_tracking = tracking
	_tracking_missing = 0.0
	head = Vector2.ZERO
	blink_l = 0.0
	blink_r = 0.0
	blink = 0.0
	eyes_closed_time = 0.0
	hand = false
	gesture = "None"
	zoom_hand = false
	zoom_gesture = "None"
	hand_depth = 0.0
	palm_ready = false
	_fist_time = 0.0
	_cooldown = 0.0
	_armed = true
	# Sin cámara no hay cabeza que seguir: el mouse pasa a manejar la mirada y
	# se captura para que no se escape del borde de la ventana.
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if new_source == Source.MOUSE \
		else Input.MOUSE_MODE_VISIBLE
	print("[EyeInput] entrada: %s" % ("cámara" if new_source == Source.CAMERA else "mouse"))
	source_changed.emit()


## Con cámara, una mano abierta delante de la cara ensucia la lectura de mirada.
## Con mouse no existe ese problema: el control es el mouse mismo.
func hand_obstructs() -> bool:
	return source == Source.CAMERA and hand and gesture != "Closed_Fist"


func uses_camera() -> bool:
	return source == Source.CAMERA


## Calibra el parpadeo con los ojos abiertos del usuario. Se llama en Enter.
func calibrate_blink() -> void:
	# Solo calibrar si los ojos parecen abiertos (blink < 0.3).
	if blink_l < 0.3 and blink_r < 0.3:
		_blink_baseline_l = blink_l
		_blink_baseline_r = blink_r
		_blink_calibrated = true
		print("[EyeInput] parpadeo calibrado: %.2f / %.2f" % [blink_l, blink_r])


func _ingest(frame: Dictionary, delta: float) -> void:
	_raw_tracking = frame.get("face", false)
	hand = frame.get("hand", false)
	gesture = frame.get("gesture", "None")
	zoom_hand = frame.get("zoom_hand", false)
	zoom_gesture = frame.get("zoom_gesture", "None")
	hand_depth = clampf(frame.get("hand_depth", 0.0), 0.0, 1.0)

	if _raw_tracking:
		_tracking_missing = 0.0
		tracking = true
		var target := Vector2(frame.get("head_yaw", 0.0), frame.get("head_pitch", 0.0))
		head = head.lerp(target, _approach(HEAD_SMOOTHING, delta))

		var left := clampf(frame.get("blink_l", 0.0), 0.0, 1.0)
		var right := clampf(frame.get("blink_r", 0.0), 0.0, 1.0)
		var rate := _approach(BLINK_SMOOTHING, delta)
		blink_l = lerpf(blink_l, left, rate)
		blink_r = lerpf(blink_r, right, rate)
		# Promedio: un guiño entorna la pantalla a medias, no la tapa entera.
		blink = (blink_l + blink_r) * 0.5
		# Calibracion: ajusta al baseline del usuario para no leer ojos pequenos
		# como cerrados.
		if _blink_calibrated:
			var denom_l := 1.0 - _blink_baseline_l
			var denom_r := 1.0 - _blink_baseline_r
			if denom_l > 0.01:
				blink_l = clampf((blink_l - _blink_baseline_l) / denom_l, 0.0, 1.0)
			if denom_r > 0.01:
				blink_r = clampf((blink_r - _blink_baseline_r) / denom_r, 0.0, 1.0)
			blink = (blink_l + blink_r) * 0.5
		# Los dos ojos tienen que estar cerrados: un guiño o un parpadeo no
		# es quedarse mirando a oscuras.
		if minf(blink_l, blink_r) > EYES_CLOSED:
			eyes_closed_time += delta
		else:
			eyes_closed_time = 0.0
	else:
		# Sin cara no es "ojos cerrados": es que no hay lectura. Se apagan los
		# párpados y la mecánica, sin castigar al jugador por una cámara caída.
		# Un poco de gracia para no parpadear entre "sigue" y "se perdió".
		_tracking_missing += delta
		if _tracking_missing > TRACKING_GRACE:
			tracking = false
		_release_eyes(delta)


## Suavizado exponencial que no depende del framerate.
func _approach(rate: float, delta: float) -> float:
	return 1.0 - exp(-rate * delta)


## Vuelve los párpados a abiertos cuando no hay datos que leer.
func _release_eyes(delta: float) -> void:
	blink_l = move_toward(blink_l, 0.0, 4.0 * delta)
	blink_r = move_toward(blink_r, 0.0, 4.0 * delta)
	blink = (blink_l + blink_r) * 0.5
	eyes_closed_time = 0.0


func _watch_for_stall(delta: float) -> void:
	var silent := _time - _last_frame_at
	if silent > FALLBACK_AFTER:
		push_warning("EyeInput: sin datos de la cámara, paso a mouse y teclado.")
		set_source(Source.MOUSE)
	elif silent > STALE_AFTER:
		# Se cortó el paquete: no nos quedamos con la última pose congelada.
		_raw_tracking = false
		_tracking_missing += delta
		if _tracking_missing > TRACKING_GRACE:
			tracking = false
		hand = false
		gesture = "None"
		zoom_hand = false
		zoom_gesture = "None"
		hand_depth = 0.0
		_release_eyes(delta)


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
