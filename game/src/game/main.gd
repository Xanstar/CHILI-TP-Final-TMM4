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
		"yaw": -15.0, "distance": 3.0, "height": 0.8,
	},
	{
		"name": "Frasco", "shape": Remedy.CAPSULE,
		"color": Color(0.9, 0.55, 0.1),
		"yaw": -30.0, "distance": 3.0, "height": 1.3,
	},
	{
		"name": "Paño", "shape": Remedy.BOX,
		"color": Color(0.3, 0.6, 0.7),
		"yaw": 0.0, "distance": 3.0, "height": 1.0,
	},
]

const DOOR_YAW := 0.0
const DOOR_DISTANCE := 2.0
const ENDING_DELAY := 10.0

const ENDINGS := {
	&"contemplacion": "Te ves reflejado en la pantalla apagada.\n\nYa no sos el que vino a cazar monstruos.",
	&"oscuridad": "Las luces se apagaron.\n\nCHILI está adentro.\n\nYa es tarde.",
	&"perdida": "Mientras mirabas para otro lado,\nCHILI dejó de moverse.",
	&"escape": "Saliste.\n\nCHILI te sigue, arrastrándose.",
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
## Segundos que se puede mantener la puerta cerrada antes del apagón.
@export var door_energy_drain := 0.08
## Segundos de oscuridad antes de que CHILI infecte.
@export var blackout_duration := 3.0
## Segundos que tarda CHILI en aparecer en la puerta.
@export var chili_appear_min := 8.0
@export var chili_appear_max := 15.0
## Segundos que CHILI se queda en la puerta si está abierta.
@export var chili_stay_open := 6.0
## Segundos que CHILI se queda si la puerta está cerrada (bloqueado).
@export var chili_stay_closed := 4.0

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

# --- puerta y energía ---
var door_closed := false
var energy := 1.0
var lights_on := true
var _door_toggle_cooldown := 0.0

# --- CHILI en la puerta ---
var chili_at_door := false
var chili_inside := false
var _chili_appear_timer := 0.0
var _chili_stay_timer := 0.0
var _chili_next_appear := 10.0

# --- apagón ---
var _blackout_timer := 0.0
var _blackout_active := false

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
	chili.build()
	door.build()
	kaiser.build()
	hud.build()
	hud.set_debug_visible(show_debug_hud)
	hud.show_hint(_start_hint())

	EyeInput.grab.connect(_on_grab)
	EyeInput.source_changed.connect(_on_source_changed)

	# CHILI empieza fuera del baño.
	chili.visible = false
	_chili_next_appear = randf_range(chili_appear_min, chili_appear_max)

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
	_update_door_toggle(delta)


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

func _update_door_toggle(delta: float) -> void:
	_door_toggle_cooldown = maxf(_door_toggle_cooldown - delta, 0.0)
	if _door_toggle_cooldown > 0.0:
		return
	var looking_at_door := _angle_to(door, Vector3(0, 1.0, 0)) < 25.0
	if not looking_at_door or not EyeInput.hand:
		return
	if EyeInput.gesture == "Closed_Fist" and not door_closed:
		door_closed = true
		door.set_closed(true)
		_door_toggle_cooldown = 0.5
		_notify("Puerta cerrada")
	elif EyeInput.gesture == "Open_Palm" and door_closed:
		door_closed = false
		door.set_closed(false)
		_door_toggle_cooldown = 0.5
		_notify("Puerta abierta")


func _set_lights(on: bool) -> void:
	# Oscurecer el ambiente.
	var env := (get_node_or_null("Room") as Room)
	if env != null:
		# Buscar el WorldEnvironment.
		for child in env.get_children():
			if child is WorldEnvironment:
				var we := child as WorldEnvironment
				if we.environment != null:
					we.environment.ambient_light_energy = 0.7 if on else 0.02
					we.environment.fog_density = 0.03 if on else 0.15
	# Apagar/encender las luces OmniLight.
	for node in get_tree().get_nodes_in_group("lights"):
		if node is OmniLight3D:
			(node as OmniLight3D).light_energy = (node as OmniLight3D).light_energy if on else 0.0
	# Buscar luces en la escena.
	for child in get_children():
		_toggle_lights_recursive(child, on)


func _toggle_lights_recursive(node: Node, on: bool) -> void:
	if node is OmniLight3D:
		(node as OmniLight3D).visible = on
	for child in node.get_children():
		_toggle_lights_recursive(child, on)


func _update_camera(delta: float) -> void:
	var obstructed := EyeInput.hand_obstructs() or (
		EyeInput.uses_camera() and EyeInput.zoom_hand)
	var can_look := EyeInput.tracking and not obstructed
	var can_turn := can_look \
		and not (EyeInput.uses_camera() and EyeInput.hand and carried == null)
	camera.follow(EyeInput.head - _head_offset, can_look, can_turn, delta)


func _update_rules(delta: float) -> void:
	var eyes_closed := EyeInput.eyes_closed_time > eyes_closed_delay and not EyeInput.hand

	# 1. CHILI aparece en la puerta periódicamente.
	_chili_appear_timer += delta
	if not chili_at_door and not chili_inside and _chili_appear_timer >= _chili_next_appear:
		chili_at_door = true
		chili.visible = true
		# Colocar CHILI justo afuera de la puerta.
		chili.position = door.position + Vector3(0, 0, -1.5)
		chili.rotation_degrees.y = 180.0
		_chili_stay_timer = 0.0
		_chili_appear_timer = 0.0

	if chili_at_door:
		_chili_stay_timer += delta
		var stay_time := chili_stay_open if not door_closed else chili_stay_closed
		if _chili_stay_timer >= stay_time:
			chili_at_door = false
			chili.visible = false
			_chili_next_appear = randf_range(chili_appear_min, chili_appear_max)

	# 2. Si la puerta está abierta y CHILI está en la puerta → contagio.
	if chili_at_door and not door_closed:
		contagion += contagion_rate * 2.0 * delta
		contagion = minf(contagion, 1.0)

	# 3. Energía: se drena cuando la puerta está cerrada.
	if door_closed:
		energy -= door_energy_drain * delta
		energy = maxf(energy, 0.0)
	else:
		energy = move_toward(energy, 1.0, 0.05 * delta)

	# 4. Apagón: si la energía llega a 0 con la puerta cerrada.
	if energy <= 0.0 and door_closed and not _blackout_active:
		_blackout_active = true
		_blackout_timer = blackout_duration
		lights_on = false
		_set_lights(false)

	if _blackout_active:
		_blackout_timer -= delta
		if _blackout_timer <= 0.0:
			_blackout_active = false
			lights_on = true
			_set_lights(true)
			# CHILI se metió adentro → infección instantánea → game over.
			chili_inside = true
			chili.visible = true
			chili.position = camera.position + Vector3(0, -0.3, -1.0)
			contagion = 1.0
			_end(&"oscuridad")

	# 5. Finales.
	if contagion >= 1.0 and not finished:
		_end(&"contemplacion")
	if gravity >= 1.0 and not finished:
		_end(&"perdida")

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
	hud.set_target(_target_text())

	# Puerta: visual de abierta/cerrada.
	door.set_closed(door_closed)

	# Luces.
	if _blackout_active:
		_set_lights(false)
	elif lights_on:
		_set_lights(true)

	# Tentación.
	_bait_at -= delta
	if _bait_at <= 0.0:
		_bait = 1.0
		_bait_at = randf_range(1.0, 2.5) * (1.4 - gravity * 0.6)
	_bait = move_toward(_bait, 0.0, 3.0 * delta)
	_flash = move_toward(_flash, 0.0, 1.5 * delta)

	chili.apply(delta, _bait, _flash)


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
	if _blackout_active:
		return "APAGÓN"
	if EyeInput.eyes_closed_time > eyes_closed_delay:
		return "ojos cerrados"
	if _creep > 0.7:
		return "CHILI se acerca..."
	if chili_at_door and not door_closed:
		return "CHILI está en la puerta"
	return ""


func _target_text() -> String:
	if not running or finished:
		return ""
	if door_closed:
		return "puerta cerrada"
	var looking_at_door := _angle_to(door, Vector3(0, 1.0, 0)) < 25.0
	if looking_at_door:
		if door_closed:
			return "puerta cerrada — puño para abrir"
		else:
			return "puerta abierta — puño para cerrar"
	return ""
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
	if _blackout_active:
		return "APAGÓN"
	if _creep > 0.7:
		return "CHILI se acerca..."
	if chili_at_door and not door_closed:
		return "CHILI está en la puerta"
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
	chili.visible = false
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
