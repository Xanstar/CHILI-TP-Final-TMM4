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

## Los tres remedios: nombre, modelo y lugar. Se crean en el _ready.
## Van apoyados sobre la repisa del lavabo, que es el único mueble bajo del
## baño: así quedan dentro del espacio jugable y a la vista desde el spawn.
##
## Los modelos son GLB con licencia CC0 (ver assets/remedies/*/LICENSE.txt) y
## tienen el pivote en la base, así que apoyarlos es poner y = DECK_Y. "size"
## los agranda: un frasco de tamaño real a metro y medio de distancia no se ve.
## Los lugares salen de dev/probe_deck, que mapea la mesada: la izquierda y la
## derecha del bowl están libres, y el frente también.
const DECK_Y := 0.345

const REMEDIES := [
	{
		"name": "Botiquín",
		"model": "res://assets/remedies/first-aid-kit/first-aid-kit.glb",
		"size": 0.55,
		"at": Vector3(0.70, DECK_Y, 0.42), "yaw": 12.0,
	},
	{
		"name": "Frasco",
		"model": "res://assets/remedies/pill-bottle/pill-bottle.glb",
		"size": 1.8,
		"at": Vector3(1.08, DECK_Y, 0.12), "yaw": -25.0,
	},
	{
		"name": "Paño",
		"model": "res://assets/remedies/bath-towel/bath-towel.glb",
		"size": 0.55,
		"at": Vector3(1.46, DECK_Y, 0.42), "yaw": -8.0,
	},
]

const ENDING_DELAY := 10.0
## Segundos con la cara detectada antes de arrancar solos. No hay tecla de
## inicio: si no, el juego podría quedarse esperando algo que nadie va a tocar.
const AUTO_START_AFTER := 1.2

## Spawn por defecto: los eligió el jugador caminando por el mapa en una versión
## anterior. Se pueden pisar con `user://positions.cfg`.
const DEFAULT_PLAYER_POS := Vector3(0.115139, 0.65, -1.574154)
const DEFAULT_CHILI_POS := Vector3(-0.65542, 0.65, 2.147936)
## Altura del piso del baño en coordenadas del mundo: CHILI se apoya acá.
const FLOOR_Y := -0.49
const CONFIG_PATH := "user://positions.cfg"

## Los finales. El texto es lo último que se lee: tiene que describir lo que
## acaba de pasar en pantalla.
const ENDINGS := {
	&"ayuda": "CHILI respira.\n\nTus patas ya no son las mismas.",
	&"contemplacion": "Te ves reflejado en la pantalla apagada.\n\nYa no sos el que vino a cazar monstruos.",
	&"oscuridad": "Las luces volvieron.\n\nYa estaba adentro.\n\nYa es tarde.",
	&"perdida": "Mientras mirabas para otro lado,\nCHILI dejó de moverse.",
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
## Energía por segundo que gasta la puerta cerrada: con la batería llena (1.0)
## aguanta 1 / 0.08 = 12,5 s. Con la puerta abierta se recarga a 0.05 por segundo.
@export var door_energy_drain := 0.08
## Segundos de oscuridad antes de que CHILI infecte.
@export var blackout_duration := 3.0
## Segundos de luz con CHILI delante antes de que caiga el final. Sin este
## respiro, el cartel del final tapa justo la imagen del susto.
@export var blackout_beat := 1.6
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
@onready var camera: GazeCamera = $Camera
@onready var kaiser: KaiserBody = $Camera/Kaiser
@onready var hud: Hud = $Hud

var remedies: Array[Pickup] = []

# --- estado del juego ---
var running := false
var finished := false
## Qué final se disparó (vacío mientras se juega).
var ending := &""
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

## Ya hay un final en camino: se espera el respiro y no se dispara otro.
var _ending_queued := false

var _last_remedy: Pickup = null
var _time_without_remedy := 100.0
var _time_without_chili := 100.0
var _grabbed_at := -10.0
var _door_time := 0.0
var _bait := 0.0
var _bait_at := 2.0
var _flash := 0.0
var _saved_player_pos := DEFAULT_PLAYER_POS
var _saved_chili_pos := DEFAULT_CHILI_POS
## Rumbo con el que arranca la cabeza: mirando a la puerta.
var _spawn_heading := 0.0
var _time := 0.0
## Tiempo con la cara a la vista, para el arranque automático.
var _start_timer := 0.0
## Pose de la cabeza con la que se calibró, en grados.
var _head_offset := Vector2.ZERO


func _ready() -> void:
	room.build(_clear_zones())
	_load_positions()
	_build_layout()
	_apply_spawn()
	chili.build()
	kaiser.build()
	hud.build()
	hud.set_debug_visible(show_debug_hud)
	hud.show_hint(_start_hint())

	EyeInput.grab.connect(_on_grab)

	# CHILI empieza visible en la puerta por unos segundos.
	chili.visible = true
	chili_at_door = true
	_place_chili()
	_chili_stay_timer = 0.0
	_chili_next_appear = 0.0

	# Arranque inmediato: solo para pruebas headless y para grabar la demo.
	if Cli.has_flag("--auto"):
		_calibrate()


func _process(delta: float) -> void:
	_time += delta
	_update_camera(delta)
	_update_focus(delta)
	# No hay tecla para calibrar: el juego lo hace solo cuando ve una cara
	# estable. Así nadie queda trabado esperando una instrucción.
	if not running and not finished and EyeInput.tracking:
		_start_timer += delta
		if _start_timer > AUTO_START_AFTER:
			_calibrate()
	if running and not finished:
		_update_rules(delta)
	_update_views(delta)
	_update_hud()
	_update_door_toggle(delta)


# ============================================================
#  ENTRADA
# ============================================================

## Fija el cero de la cabeza y vuelve a mirar al frente. Se llama solo, cuando
## hay cara estable: no hay tecla ni espera.
func _calibrate() -> void:
	_head_offset = EyeInput.head
	EyeInput.calibrate_blink()
	camera.recenter(_spawn_heading)
	if not running:
		running = true
		hud.hide_hint()
	print("[Main] calibrado: ", _head_offset)


## El gesto lo detecta EyeInput: palma abierta y después puño, con la mano derecha.
## También se puede agarrar directo con puño si se está mirando un remedio.
func _on_grab() -> void:
	if not running or finished or _ending_queued:
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
	var looking_at_door := _angle_to(room.glb_door, Vector3(0, 1.0, 0)) < 30.0
	if not looking_at_door or not EyeInput.hand:
		return
	if EyeInput.gesture == "Closed_Fist" and not door_closed:
		_toggle_door()
	elif EyeInput.gesture == "Open_Palm" and door_closed:
		_toggle_door()


## Abre o cierra la puerta. La dispara el gesto de la mano mirando la puerta.
func _toggle_door() -> void:
	door_closed = not door_closed
	room.set_door_closed(door_closed)
	_door_toggle_cooldown = 0.5
	_notify("Puerta cerrada" if door_closed else "Puerta abierta")


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
	var obstructed := EyeInput.hand_obstructs() or EyeInput.zoom_hand
	var can_look := EyeInput.tracking and not obstructed
	var can_turn := can_look and not (EyeInput.hand and carried == null)
	camera.follow(EyeInput.head - _head_offset, can_look, can_turn, delta)


## Qué está mirando el jugador. Se recalcula cada frame y de acá salen el
## agarre, la entrega, el brillo de los remedios y el texto del HUD.
func _update_focus(delta: float) -> void:
	_time_without_remedy += delta
	_time_without_chili += delta

	var in_sight := _remedy_in_sight()
	if in_sight != null:
		looked_remedy = in_sight
		_last_remedy = in_sight
		_time_without_remedy = 0.0
	else:
		looked_remedy = null
	# Lock-on: el más cercano dentro de un cono más ancho, para no exigir
	# precisión de francotirador con la cabeza.
	targeted_remedy = _closest_remedy(remedy_angle + 5.0)

	var chili_angle := _angle_to(chili, Vector3(0, 0.5, 0))
	if chili.visible and chili_angle < focus_angle:
		_time_without_chili = 0.0

	if chili.visible and chili_angle < focus_angle:
		focus = Focus.CHILI
	elif room.glb_door != null and _angle_to(room.glb_door, Vector3(0, 1.0, 0)) < 30.0:
		focus = Focus.DOOR
	elif in_sight != null:
		focus = Focus.ITEM
	else:
		focus = Focus.OTHER


func _update_rules(delta: float) -> void:
	# Con un final ya disparado no quedan reglas: se deja ver la escena.
	if _ending_queued:
		return
	var eyes_closed := EyeInput.eyes_closed_time > eyes_closed_delay and not EyeInput.hand

	# 1. CHILI aparece en la puerta periódicamente.
	_chili_appear_timer += delta
	if not chili_at_door and not chili_inside and _chili_appear_timer >= _chili_next_appear:
		chili_at_door = true
		chili.visible = true
		# Colocar CHILI en el pasillo, donde quedó guardado.
		_place_chili()
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

	# 2b. Medicar a CHILI: si llevás un objeto y lo mirás, lo curás.
	if carried != null and (focus == Focus.CHILI or _time_without_chili < chili_memory) \
			and EyeInput.hand and EyeInput.palm_ready and (_time - _grabbed_at) > 0.4:
		_cure_chili()

	# 2c. Cerrar los ojos hace que CHILI se vaya, pero acelera la infección.
	if eyes_closed and chili_at_door:
		chili_at_door = false
		chili.visible = false
		_chili_next_appear = randf_range(chili_appear_min, chili_appear_max)
		contagion += contagion_rate * 3.0 * delta
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
			# Mientras estaba oscuro se metió adentro. Vuelve la luz y está ahí,
			# a un metro tuyo: el contagio se va a 1 y no hay salida.
			chili_inside = true
			chili.visible = true
			_place_chili_in_front()
			contagion = 1.0
			_finish_later(&"oscuridad", blackout_beat)

	# 5. Finales. Uno solo por partida: el primero que llega gana.
	if not _ending_queued:
		if contagion >= 1.0:
			_end(&"contemplacion")
		elif gravity >= 1.0:
			_end(&"perdida")
		elif delivered >= remedies.size():
			_end(&"ayuda")

## Darle un remedio a CHILI: lo cura, lo espanta y cuenta como entrega.
func _cure_chili() -> void:
	carried.deliver()
	carried = null
	delivered += 1
	gravity = maxf(gravity - cure_per_delivery, 0.0)
	contagion = maxf(contagion - 0.25, 0.0)
	chili_at_door = false
	chili.visible = false
	_chili_next_appear = randf_range(chili_appear_min, chili_appear_max)
	_flash = 1.0
	_notify("Medicaste a CHILI")


func _drop() -> void:
	carried.detach_to(self)
	_notify("Dejaste: " + carried.item_name)
	carried = null


## Cierra la partida con el cartel del final. Espera un poco para que se vea lo
## que acaba de pasar en la escena.
func _end(kind: StringName) -> void:
	if finished:
		return
	finished = true
	ending = kind
	hud.show_ending(ENDINGS[kind])
	print("[Main] FINAL: ", kind)
	await get_tree().create_timer(ENDING_DELAY).timeout
	get_tree().reload_current_scene()


## Programa el final con un respiro de suspenso. Uno solo por partida: si ya
## hay uno en camino, se ignora.
func _finish_later(kind: StringName, delay: float) -> void:
	if finished or _ending_queued:
		return
	_ending_queued = true
	await get_tree().create_timer(delay).timeout
	_end(kind)


# ============================================================
#  VISTAS (empujar el estado a la escena)
# ============================================================

func _update_views(delta: float) -> void:
	chili.gravity = gravity
	chili.apply(delta, _bait, _flash)
	camera.set_zoom(EyeInput.zoom_hand and EyeInput.zoom_gesture == "Open_Palm",
		fascination, delta)
	zoom = camera.zoom_level

	for remedy in remedies:
		remedy.set_highlight(_highlight_for(remedy))

	# El personaje es estático: no se mueve con la mano.
	# (Futuro: mirar un objeto + puño = moverse hacia él.)
	pass

	kaiser.apply(delta, contagion, EyeInput.hand, EyeInput.gesture == "Closed_Fist")

	hud.set_vignette(fascination * 0.4 + contagion * 0.9)
	# El párpado sigue al parpadeo, no a la mecánica: se cierra de verdad.
	hud.set_eyelids(EyeInput.blink)
	hud.set_status(_status_text())
	hud.set_target(_target_text())

	# Puerta: visual de abierta/cerrada.
	if room.glb_door != null:
		room.set_door_closed(door_closed)

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
	# Sin palma abierta no hay nada que esperar: el brillo máximo es la señal
	# de "ya podés cerrar el puño".
	var ready := EyeInput.palm_ready
	if remedy.state == Pickup.State.HAND:
		return 0.8
	if remedy == looked_remedy:
		return 3.0 if ready else 1.6
	if remedy == targeted_remedy:
		# En la mira: se ve que está disponible, aunque no esté centrado.
		return 1.2 if ready else 0.7
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


## Lo que dice el HUD según lo que tenés delante. Todo se hace con gestos, así
## que el cartel enseña el gesto y no una tecla.
func _target_text() -> String:
	if not running or finished:
		return ""
	if carried != null:
		return "llevás %s — mirá a CHILI y abrí la mano" % carried.item_name
	if looked_remedy != null:
		return "%s — palma abierta y puño" % looked_remedy.item_name
	if targeted_remedy != null:
		return "%s — palma abierta y puño" % targeted_remedy.item_name
	if room.glb_door != null and _angle_to(room.glb_door, Vector3(0, 1.0, 0)) < 30.0:
		return "puerta cerrada — palma abierta" if door_closed else "puerta abierta — puño"
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
	return """cabeza: %+.1f° %+.1f°   párpados: %.2f/%.2f   ojos cerrados: %.1fs
foco: %s   rumbo: %d°   cámara: %s
mano der: %s%s   mano izq: %s   zoom: %.2f
fascinación: %.2f   contagio: %.2f
gravedad CHILI: %.2f   entregados: %d/%d   en la mano: %s""" % [
		head.x, head.y, EyeInput.blink_l, EyeInput.blink_r, EyeInput.eyes_closed_time,
		Focus.keys()[focus], camera.heading_degrees(),
		"leyendo" if EyeInput.tracking else "sin lectura",
		hand_text, palm_text, zoom_text, zoom,
		fascination, contagion,
		gravity, delivered, remedies.size(), carried_text,
	]


# ============================================================
#  ARMADO
# ============================================================

func _build_layout() -> void:
	chili.visible = false

	for data in REMEDIES:
		var remedy := Pickup.new()
		add_child(remedy)
		remedy.setup(
			data["name"],
			load(data["model"]),
			data["at"],
			data["yaw"],
			data["size"])
		remedies.append(remedy)


## Zonas que el desorden tiene que respetar: hoy no hay desorden, el baño ya
## viene amueblado en el GLB.
func _clear_zones() -> Array[Vector3]:
	return []


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


## El cartel de arranque. No hay tecla: cuando la cámara ve una cara, el juego
## se calibra solo. El texto solo pide lo único que hace falta.
func _start_hint() -> String:
	return "Ponete frente a la cámara\ny mirá al frente"


## Nada de esto se muestra en pantalla: es para depurar en la consola.
func _notify(text: String) -> void:
	print("[Main] ", text)


## Lee los spawn guardados. Si el archivo no existe, quedan los valores por
## defecto: el juego nunca arranca sin posiciones. Los lugares los eligió el
## jugador con las teclas P y C en una versión anterior, y quedaron fijos.
func _load_positions() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.READ)
	if file == null:
		print("[POS] sin ", CONFIG_PATH, ": uso los spawn por defecto")
		return
	while not file.eof_reached():
		var line := file.get_line().strip_edges()
		var parts := line.split("=", true, 1)
		if parts.size() != 2:
			continue
		var value: Variant = str_to_var(parts[1])
		if not value is Vector3:
			continue
		match parts[0]:
			"player":
				_saved_player_pos = value
			"chili":
				_saved_chili_pos = value
	file.close()
	print("[POS] cargado: jugador=", _saved_player_pos, " chili=", _saved_chili_pos)


## Pone al jugador en su spawn y lo deja mirando a la puerta. Si no, la puerta
## arranca a la espalda y hay que torcer el cuello para encontrarla.
func _apply_spawn() -> void:
	camera.position = _saved_player_pos
	var to_door := room.glb_door.global_position - _saved_player_pos
	_spawn_heading = rad_to_deg(atan2(-to_door.x, -to_door.z))
	camera.recenter(_spawn_heading)
	print("[POS] spawn del jugador: ", camera.position, " rumbo: %.1f°" % _spawn_heading)


## CHILI vive en el pasillo, del otro lado de la puerta, donde lo ubicó el
## jugador con la tecla C. Se le fuerza la altura del piso para que no flote.
func _place_chili() -> void:
	chili.position = Vector3(_saved_chili_pos.x, FLOOR_Y, _saved_chili_pos.z)
	chili.base_position = chili.position
	chili.rotation_degrees.y = 180.0


## El golpe del apagón: CHILI aparece parado delante de la cámara, mirándote.
## Se calcula desde el rumbo actual, así el jugador no puede quedar mirando
## para el otro lado justo cuando vuelve la luz.
func _place_chili_in_front(distance := 1.3) -> void:
	var forward := -camera.global_transform.basis.z
	forward.y = 0.0
	if forward.length_squared() < 0.001:
		forward = Vector3(0.0, 0.0, 1.0)
	forward = forward.normalized()
	chili.position = Vector3(
		camera.position.x + forward.x * distance,
		FLOOR_Y,
		camera.position.z + forward.z * distance)
	chili.base_position = chili.position
	# El modelo mira hacia +Z con giro 0: para que encare al jugador, la
	# dirección tiene que ser la opuesta a la de la cámara.
	chili.rotation_degrees.y = rad_to_deg(atan2(-forward.x, -forward.z))
