class_name Game
extends Node3D
## Punto de entrada.
##
## Kaiser está paralizado en el medio de un cuarto. Solo puede mover la cabeza
## y levantar la pata derecha (la mano). CHILI, el bicho, se muere en
## el piso de enfrente: hay que mirarlo de cerca, agarrar los tres remedios y
## entregárselos. Pero mirarlo también contagia, y la puerta siempre está ahí.
##
## Este archivo es el orquestador: lee la entrada, decide el estado del juego y
## empuja ese estado a la escena. Nada de geometría ni de dibujo acá.

enum Focus { OTHER, ITEM, DOOR, CHILI, EYES_CLOSED, NO_SIGNAL }

## Los tres remedios: nombre, forma, color y lugar. Se crean en el _ready.
enum Remedy { CYLINDER, CAPSULE, BOX }

const REMEDIES := [
	{
		"name": "Venda", "shape": Remedy.CYLINDER,
		"color": Color(0.9, 0.9, 0.85),
		"yaw": 55.0, "distance": 4.0, "height": 0.8,
	},
	{
		"name": "Frasco", "shape": Remedy.CAPSULE,
		"color": Color(0.9, 0.55, 0.1),
		"yaw": 70.0, "distance": 4.0, "height": 1.3,
	},
	{
		"name": "Paño", "shape": Remedy.BOX,
		"color": Color(0.3, 0.6, 0.7),
		"yaw": 85.0, "distance": 4.0, "height": 1.0,
	},
]

const CHILI_YAW := 0.0
const CHILI_DISTANCE := 2.6
const DOOR_YAW := 144.0
const DOOR_DISTANCE := 9.0
const ENDING_DELAY := 10.0
## El frasco vive sobre una repisa, así que necesita mueble.
const SHELF_REMEDY := 1

const ENDINGS := {
	&"contemplacion": "Te ves reflejado en la pantalla apagada.\n\nYa no sos el que vino a cazar monstruos.",
	&"abandono": "Saliste.\n\nCHILI te sigue, arrastrándose.",
	&"perdida": "Mientras mirabas para otro lado,\nCHILI dejó de moverse.",
	&"ayuda": "CHILI respira.\n\nTus patas ya no son las mismas.",
}

@export_group("Mirada")
## Grados de apertura: qué tan lejos del centro sigue contando como "estás mirando".
@export var focus_angle := 15.0
@export var remedy_angle := 15.0
## Segundos que se recuerda el último remedio mirado.
@export var remedy_memory := 2.0
## Segundos: si mirabas a CHILI hace menos que esto, cuenta como que lo mirás.
@export var chili_memory := 2.0
## Segundos con los dos ojos cerrados para que cuente como "ojos cerrados".
## Es más largo que un parpadeo a propósito: parpadear no penaliza.
@export var eyes_closed_delay := 0.5

@export_group("CHILI")
## Por segundo, solo.
@export var gravity_rate := 0.004
## Por segundo, mirándolo.
@export var contagion_rate := 0.012
## Cuánto más contagia mirarlo con zoom (0 = nada).
@export var contagion_zoom_bonus := 0.6
@export var cure_per_delivery := 0.25

@export_group("Puerta")
## Segundos mirando la puerta para irse.
@export var door_hold := 4.0

@export_group("Escena")
@export var show_debug_hud := false

@onready var room: Room = $Room
@onready var chili: Chili = $Chili
@onready var door: Door = $Door
@onready var camera: GazeCamera = $Camera
@onready var kaiser: KaiserBody = $Camera/Kaiser
@onready var hud: Hud = $Hud

var remedies: Array[Pickup] = []

# --- estado del juego ---
var running := false
var finished := false
var focus := Focus.OTHER
var gravity := 0.35
var contagion := 0.0
var fascination := 0.0
var zoom := 0.0
## Posición Z de la cámara: la mano izquierda la mueve adelante/atrás.
var _camera_z := 0.0
var chase := 0.0
var delivered := 0
var carried: Pickup = null
var looked_remedy: Pickup = null
var targeted_remedy: Pickup = null
## Cuánto se acercó CHILI a tu espacio (0 = en su lugar, 1 = encima tuyo).
var _creep := 0.0

var _last_remedy: Pickup = null
var _time_without_remedy := 100.0
var _time_without_chili := 100.0
var _grabbed_at := -10.0
var _door_time := 0.0
var _bait := 0.0
var _bait_at := 2.0
var _flash := 0.0
var _time := 0.0
## Pose de la cabeza con la que se calibró, en grados.
var _head_offset := Vector2.ZERO


func _ready() -> void:
	_build_layout()
	room.build(_clear_zones())
	var shelf := REMEDIES[SHELF_REMEDY]
	room.add_shelf(Shapes.polar(shelf["yaw"], shelf["distance"], 0.0), shelf["yaw"])
	chili.build()
	door.build()
	kaiser.build()
	hud.build()
	hud.set_debug_visible(show_debug_hud)
	hud.show_hint(_start_hint())

	EyeInput.grab.connect(_on_grab)
	EyeInput.source_changed.connect(_on_source_changed)

	# Arranque sin Enter: solo para pruebas headless y para grabar la demo.
	if Cli.has_flag("--auto"):
		_calibrate()


func _process(delta: float) -> void:
	_time += delta
	_update_camera(delta)
	# Si el jugador no calibra a mano, lo hacemos solos después de un par de
	# segundos con la cabeza quieta: el juego no debería quedar muerto.
	if not running and not finished and EyeInput.tracking and _time > 2.0:
		_calibrate()
	if running and not finished:
		_update_rules(delta)
	_update_views(delta)
	_update_hud()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_accept"):
		_calibrate()
		return
	if event is InputEventKey and event.pressed and not event.echo:
		match event.keycode:
			KEY_F1:
				hud.toggle_debug()
			KEY_F2:
				EyeInput.toggle_source()


# ============================================================
#  ENTRADA
# ============================================================

## Mirar al centro y apretar Enter: fija el cero de la cabeza y vuelve al frente.
func _calibrate() -> void:
	_head_offset = EyeInput.head
	EyeInput.calibrate_blink()
	camera.recenter()
	if not running:
		running = true
		hud.hide_hint()
	print("[Main] calibrado: ", _head_offset)


func _on_source_changed() -> void:
	if not running:
		hud.show_hint(_start_hint())


## El gesto lo detecta EyeInput: palma abierta y después puño, con la mano derecha.
## También se puede agarrar directo con puño si se está mirando un remedio.
func _on_grab() -> void:
	if not running or finished:
		return
	if carried != null:
		_notify("Ya tenés algo en la mano")
		return
	var target: Pickup = _first_available(looked_remedy)
	if target == null and _time_without_remedy < remedy_memory:
		target = _first_available(_last_remedy)
	# Lock-on: si no está mirando de frente, agarra el más cercano en rango.
	if target == null:
		target = _first_available(targeted_remedy)
	if target == null:
		_notify("No estás mirando ningún remedio")
		return
	carried = target
	carried.attach_to(camera)
	_grabbed_at = _time


# ============================================================
#  REGLAS
# ============================================================

func _update_camera(delta: float) -> void:
	var obstructed := EyeInput.hand_obstructs() or (
		EyeInput.uses_camera() and EyeInput.zoom_hand)
	# Cerrar los ojos ya no frena la cabeza: la pose se lee igual de bien y al
	# abrirlos otra vez no hay salto. Los ojos cerrados son otra mecánica.
	var can_look := EyeInput.tracking and not obstructed
	# Girar sobre sí mismo es más exigente: con una mano cerca de la cara la
	# lectura de los bordes se vuelve falsa y la cabeza se iría sola.
	var can_turn := can_look \
		and not (EyeInput.uses_camera() and EyeInput.hand and carried == null)
	camera.follow(EyeInput.head - _head_offset, can_look, can_turn, delta)


func _update_rules(delta: float) -> void:
	var eyes_closed := EyeInput.eyes_closed_time > eyes_closed_delay and not EyeInput.hand

	# 1. Qué remedio está mirando. Con la palma abierta la elección queda fija,
	#    así no se pierde mientras levanta la mano.
	var holding_choice := EyeInput.hand and EyeInput.palm_ready and carried == null
	if eyes_closed or carried != null:
		looked_remedy = null
	elif holding_choice:
		looked_remedy = _first_available(looked_remedy)
	else:
		looked_remedy = _remedy_in_sight()
		if looked_remedy != null:
			_last_remedy = looked_remedy
			_time_without_remedy = 0.0
	_time_without_remedy += delta

	# Objetivo de lock-on: el remedio más cercano dentro de un rango amplio.
	# No hace falta mirarlo de frente para que se marque como objetivo.
	targeted_remedy = _closest_remedy(20.0)

	# 2. Qué está mirando en general.
	var new_focus := Focus.OTHER
	if not EyeInput.tracking:
		new_focus = Focus.NO_SIGNAL
	elif eyes_closed:
		new_focus = Focus.EYES_CLOSED
	elif looked_remedy != null:
		new_focus = Focus.ITEM
	elif _angle_to(door, Vector3(0, 1.8, 0)) < focus_angle:
		new_focus = Focus.DOOR
	elif _angle_to(chili, Vector3(0, 0.4, 0)) < focus_angle:
		new_focus = Focus.CHILI
	if new_focus != focus:
		focus = new_focus
		print("[Main] foco: ", Focus.keys()[focus])

	_time_without_chili += delta
	if focus == Focus.CHILI:
		_time_without_chili = 0.0

	# 3. El mundo no espera: CHILI empeora solo, el doble si cierra los ojos.
	gravity += gravity_rate * (2.0 if focus == Focus.EYES_CLOSED else 1.0) * delta
	gravity = minf(gravity, 1.0)

	# 3b. CHILI se acerca si no lo mirás o si cerrás los ojos: FNAF.
	var creeping := focus != Focus.CHILI or focus == Focus.EYES_CLOSED
	if creeping:
		_creep = move_toward(_creep, 1.0, 0.015 * delta)
	else:
		_creep = move_toward(_creep, 0.0, 0.03 * delta)
	if delivered > 0:
		_creep = move_toward(_creep, 0.0, 0.05 * delta)
	_creep = clampf(_creep, 0.0, 1.0)

	# Si CHILI se acercó mucho y no lo mirás, el contagio sube rápido.
	if _creep > 0.8 and focus != Focus.CHILI:
		contagion += contagion_rate * 2.0 * delta
		contagion = minf(contagion, 1.0)

	# 4. Mirarlo fascina... y contagia. Apartar la vista frena el contagio.
	if focus == Focus.CHILI:
		fascination = move_toward(fascination, 1.0, 0.35 * delta)
		contagion += contagion_rate * (0.3 + 0.7 * fascination) \
			* (1.0 + zoom * contagion_zoom_bonus) * delta
	else:
		fascination = move_toward(fascination, 0.0, 0.8 * delta)

	# 5. Abrir la mano con algo: si miraba a CHILI se lo entrega, si no lo deja.
	if carried != null and EyeInput.hand and EyeInput.palm_ready \
			and (_time - _grabbed_at) > 0.4:
		if focus == Focus.CHILI or _time_without_chili < chili_memory:
			_deliver()
		else:
			_drop()

	# 6. Irse: sostener la mirada en la puerta. CHILI lo sigue.
	if focus == Focus.DOOR:
		_door_time += delta
		chase = move_toward(chase, 1.0, delta / door_hold)
	else:
		_door_time = maxf(_door_time - 2.0 * delta, 0.0)
		chase = move_toward(chase, 0.0, 0.1 * delta)

	# 7. Tentación: CHILI llama la atención cada vez más seguido.
	_bait_at -= delta
	if _bait_at <= 0.0:
		_bait = 1.0
		_bait_at = randf_range(1.0, 2.5) * (1.4 - gravity * 0.6)
	_bait = move_toward(_bait, 0.0, 3.0 * delta)
	_flash = move_toward(_flash, 0.0, 1.5 * delta)

	# 8. Finales.
	if contagion >= 1.0:
		_end(&"contemplacion")
	elif gravity >= 1.0:
		_end(&"perdida")
	elif delivered >= remedies.size():
		_end(&"ayuda")
	elif _door_time >= door_hold:
		_end(&"abandono")


func _deliver() -> void:
	carried.deliver()
	_notify("Le diste: " + carried.item_name)
	carried = null
	delivered += 1
	gravity = maxf(gravity - cure_per_delivery, 0.0)
	_flash = 1.0


func _drop() -> void:
	carried.detach_to(self)
	_notify("Dejaste: " + carried.item_name)
	carried = null


func _end(kind: StringName) -> void:
	finished = true
	hud.show_ending(ENDINGS[kind])
	print("[Main] FINAL: ", kind)
	await get_tree().create_timer(ENDING_DELAY).timeout
	get_tree().reload_current_scene()


# ============================================================
#  VISTAS (empujar el estado a la escena)
# ============================================================

func _update_views(delta: float) -> void:
	chili.gravity = gravity
	chili.apply(delta, _bait, _flash)
	# CHILI se acerca cuando no lo mirás (solo si no está yendo a la puerta).
	if chase < 0.1:
		var base_pos := chili.base_position
		var toward := camera.global_position + Vector3(0, -0.3, 0)
		chili.position = base_pos.lerp(toward, _creep * 0.7)
	chili.pull_towards(door.position, chase, delta)

	camera.set_zoom(EyeInput.zoom_hand and EyeInput.zoom_gesture == "Open_Palm",
		fascination, delta)
	zoom = camera.zoom_level

	# Movimiento con la mano izquierda: cerca = adelante, lejos = atrás.
	# Sin mano, vuelve al centro suavemente.
	var target_z := 0.0
	if EyeInput.zoom_hand:
		target_z = lerpf(1.0, -1.3, EyeInput.hand_depth)
	_camera_z = lerpf(_camera_z, target_z, 3.0 * delta)
	camera.position.z = _camera_z

	kaiser.apply(delta, contagion, EyeInput.hand, EyeInput.gesture == "Closed_Fist")

	hud.set_vignette(fascination * 0.4 + contagion * 0.9)
	# El párpado sigue al parpadeo, no a la mecánica: se cierra de verdad.
	hud.set_eyelids(EyeInput.blink)
	hud.set_status(_status_text())

	# Objetivo de lock-on: qué remedio está en la mira.
	var target_text := ""
	if running and not finished and carried == null and targeted_remedy != null:
		target_text = targeted_remedy.item_name
		if looked_remedy == targeted_remedy:
			target_text += "  —  " + ("agarrable" if EyeInput.palm_ready else "miralo")
	elif running and not finished and carried != null:
		if focus == Focus.CHILI or _time_without_chili < chili_memory:
			target_text = "dárselo a CHILI — abrí la mano"
		else:
			target_text = "mirá a CHILI para dárselo"
	hud.set_target(target_text)

	for remedy in remedies:
		remedy.set_highlight(_highlight_for(remedy))
	door.set_urgency(_door_time / door_hold)


func _highlight_for(remedy: Pickup) -> float:
	if remedy.state == Pickup.State.HAND:
		return 0.8
	if remedy == looked_remedy:
		# El brillo máximo es la señal de "ahora podés agarrarlo".
		return 3.0 if EyeInput.palm_ready else 1.6
	if remedy == targeted_remedy:
		# En la mira: se ve que está disponible, aunque no esté centrado.
		return 1.2 if EyeInput.palm_ready else 0.7
	return 0.25


## Aviso corto arriba de la pantalla. Cada problema dice lo suyo, en vez de
## apagar todo y dejar al jugador adivinando qué pasó.
func _status_text() -> String:
	if finished or EyeInput.hand:
		return ""
	if not running:
		if not EyeInput.tracking:
			return "sin cámara — acercate al centro"
		return "mirá al frente — arranca solo"
	if not EyeInput.tracking:
		return "sin cámara — el juego sigue con la última pose"
	if EyeInput.eyes_closed_time > eyes_closed_delay:
		return "ojos cerrados"
	if _creep > 0.7:
		return "CHILI se acerca..."
	return ""


func _update_hud() -> void:
	var pending := PackedStringArray()
	for remedy in remedies:
		if remedy.state != Pickup.State.DELIVERED:
			pending.append(remedy.item_name)
	hud.set_pending(pending, running and not finished)
	hud.set_debug(_debug_text())


func _debug_text() -> String:
	var head := EyeInput.head - _head_offset
	var hand_text := EyeInput.gesture if EyeInput.hand else "ninguna"
	var palm_text := " (lista)" if EyeInput.palm_ready else ""
	var zoom_text := EyeInput.zoom_gesture if EyeInput.zoom_hand else "ninguna"
	var carried_text := carried.item_name if carried != null else "-"
	var source_text := "cámara" if EyeInput.uses_camera() else "mouse"
	return """cabeza: %+.1f° %+.1f°   párpados: %.2f/%.2f   ojos cerrados: %.1fs
entrada: %s   foco: %s   rumbo: %d°
mano der: %s%s   mano izq: %s   zoom: %.2f
fascinación: %.2f   contagio: %.2f
gravedad CHILI: %.2f   entregados: %d/%d   en la mano: %s
[Enter] recalibrar   [F1] ocultar esto   [F2] cámara/mouse""" % [
		head.x, head.y, EyeInput.blink_l, EyeInput.blink_r, EyeInput.eyes_closed_time,
		source_text, Focus.keys()[focus], camera.heading_degrees(),
		hand_text, palm_text, zoom_text, zoom,
		fascination, contagion,
		gravity, delivered, remedies.size(), carried_text,
	]


# ============================================================
#  ARMADO
# ============================================================

func _build_layout() -> void:
	chili.position = Shapes.polar(CHILI_YAW, CHILI_DISTANCE, 0.0)
	door.position = Shapes.polar(DOOR_YAW, DOOR_DISTANCE, 0.0)
	door.rotation_degrees.y = DOOR_YAW

	for data in REMEDIES:
		var remedy := Pickup.new()
		add_child(remedy)
		remedy.setup(
			data["name"],
			_mesh_for(data["shape"]),
			data["color"],
			Shapes.polar(data["yaw"], data["distance"], data["height"]),
			data["yaw"])
		remedies.append(remedy)


## Zonas que el desorden tiene que respetar: (ángulo, distancia, margen).
func _clear_zones() -> Array[Vector3]:
	var zones: Array[Vector3] = []
	for data in REMEDIES:
		zones.append(Vector3(data["yaw"], data["distance"], 8.0))
	zones.append(Vector3(CHILI_YAW, 99.0, 12.0))
	zones.append(Vector3(DOOR_YAW, 99.0, 12.0))
	return zones


func _mesh_for(shape: Remedy) -> Mesh:
	match shape:
		Remedy.CYLINDER:
			return Shapes.cylinder(0.16, 0.2)
		Remedy.CAPSULE:
			return Shapes.capsule(0.1, 0.4)
		_:
			return Shapes.box(Vector3(0.5, 0.08, 0.36))


# ============================================================
#  UTILIDADES
# ============================================================

func _angle_to(target: Node3D, offset: Vector3) -> float:
	var forward := -camera.global_transform.basis.z
	var toward := (target.global_position + offset - camera.global_position).normalized()
	return rad_to_deg(forward.angle_to(toward))


func _remedy_in_sight() -> Pickup:
	var closest: Pickup = null
	var best := remedy_angle
	for remedy in remedies:
		if remedy.is_available():
			var angle := _angle_to(remedy, Vector3.ZERO)
			if angle < best:
				best = angle
				closest = remedy
	return closest


func _closest_remedy(range_degrees: float) -> Pickup:
	var closest: Pickup = null
	var best := range_degrees
	for remedy in remedies:
		if remedy.is_available():
			var angle := _angle_to(remedy, Vector3.ZERO)
			if angle < best:
				best = angle
				closest = remedy
	return closest


func _first_available(candidate: Pickup) -> Pickup:
	return candidate if candidate != null and candidate.is_available() else null


func _start_hint() -> String:
	var control := "la cabeza" if EyeInput.uses_camera() else "el mouse"
	return "Poné %s mirando al frente\ny apretá ENTER para empezar" % control


## Nada de esto se muestra en pantalla: es para depurar en la consola.
func _notify(text: String) -> void:
	print("[Main] ", text)
