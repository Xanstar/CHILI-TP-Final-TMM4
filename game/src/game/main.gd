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
## Van apoyados sobre la repisa del lavabo, que es el único mueble bajo del
## baño: así quedan dentro del espacio jugable y a la vista desde el spawn.
## La repisa está a y = DECK_Y; cada "at" sube lo que mide el objeto, así no
## flotan ni se hunden.
enum Remedy { CYLINDER, CAPSULE, BOX }

## Altura de la repisa del lavabo, medida sobre el GLB con dev/probe_surface.gd.
const DECK_Y := 0.345

const REMEDIES := [
	{
		"name": "Venda", "shape": Remedy.CYLINDER,
		"color": Color(0.9, 0.9, 0.85),
		"at": Vector3(0.75, DECK_Y + 0.13, 0.42), "yaw": 20.0,
	},
	{
		"name": "Frasco", "shape": Remedy.CAPSULE,
		"color": Color(0.9, 0.55, 0.1),
		"at": Vector3(1.42, DECK_Y + 0.16, 0.46), "yaw": -15.0,
	},
	{
		"name": "Paño", "shape": Remedy.BOX,
		"color": Color(0.3, 0.6, 0.7),
		"at": Vector3(1.05, DECK_Y + 0.035, 0.145), "yaw": 0.0,
	},
]

const ENDING_DELAY := 10.0

## Spawn por defecto: los eligió el jugador caminando por el mapa y apretando
## P (jugador) y C (CHILI). Se pueden pisar con `user://positions.cfg`.
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
## Segundos que se puede mantener la puerta cerrada antes del apagón.
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
var _p_pressed := false
var _c_pressed := false
var _saved_player_pos := DEFAULT_PLAYER_POS
var _saved_chili_pos := DEFAULT_CHILI_POS
## Rumbo con el que arranca la cabeza: mirando a la puerta.
var _spawn_heading := 0.0
var _time := 0.0
## Se descarta el primer movimiento del mouse después de capturarlo: el salto
## inicial es enorme y marea.
var _skip_motion := false
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
	EyeInput.source_changed.connect(_on_source_changed)
	camera.set_free_look(not EyeInput.uses_camera())

	# CHILI empieza visible en la puerta por unos segundos.
	chili.visible = true
	chili_at_door = true
	_place_chili()
	_chili_stay_timer = 0.0
	_chili_next_appear = 0.0

	# Arranque sin Enter: solo para pruebas headless y para grabar la demo.
	if Cli.has_flag("--auto"):
		_calibrate()


func _process(delta: float) -> void:
	_time += delta
	_update_camera(delta)
	_update_focus(delta)
	# Si el jugador no calibra a mano, lo hacemos solos después de un par de
	# segundos con la cabeza quieta: el juego no debería quedar muerto.
	if not running and not finished and EyeInput.tracking and _time > 2.0:
		_calibrate()
	if running and not finished:
		_update_rules(delta)
	_update_views(delta)
	_update_hud()
	_update_door_toggle(delta)
	_update_movement(delta)
	# Tecla P: guardar posición del jugador (spawn).
	if Input.is_key_pressed(KEY_P) and not _p_pressed:
		_p_pressed = true
		_saved_player_pos = camera.global_position
		_save_positions()
		print("[POS] jugador guardado:", _saved_player_pos)
	if not Input.is_key_pressed(KEY_P):
		_p_pressed = false
	# Tecla C: guardar posición de CHILI (se apoya en el piso, no en los ojos).
	if Input.is_key_pressed(KEY_C) and not _c_pressed:
		_c_pressed = true
		_saved_chili_pos = Vector3(camera.global_position.x, FLOOR_Y, camera.global_position.z)
		_save_positions()
		chili.visible = true
		_place_chili()
		print("[POS] chili guardado:", _saved_chili_pos)
	if not Input.is_key_pressed(KEY_C):
		_c_pressed = false


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
			KEY_E:
				_interact()
			KEY_ESCAPE:
				# Primero suelta el mouse; si ya está suelto, sale del juego.
				if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
					Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				else:
					get_tree().quit()


## Modo sin cámara: el mouse gira la cabeza. Solo se usa cuando no hay tracker.
func _input(event: InputEvent) -> void:
	if EyeInput.uses_camera():
		return
	if event is InputEventMouseMotion:
		if _skip_motion:
			_skip_motion = false
			return
		camera.look(event.relative)
	elif event is InputEventMouseButton and event.pressed:
		# Un click dentro de la ventana vuelve a capturar el mouse.
		if Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			_skip_motion = true


# ============================================================
#  ENTRADA
# ============================================================

## Mirar al centro y apretar Enter: fija el cero de la cabeza y vuelve al frente.
func _calibrate() -> void:
	_head_offset = EyeInput.head
	EyeInput.calibrate_blink()
	# Con mouse no hay cero que fijar: la mirada se queda donde está.
	if EyeInput.uses_camera():
		camera.recenter(_spawn_heading)
	if not running:
		running = true
		hud.hide_hint()
	print("[Main] calibrado: ", _head_offset)


func _on_source_changed() -> void:
	camera.set_free_look(not EyeInput.uses_camera())
	_skip_motion = true
	if not running:
		hud.show_hint(_start_hint())


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


## Abre o cierra la puerta. La usan el gesto de la mano y la tecla E.
func _toggle_door() -> void:
	door_closed = not door_closed
	room.set_door_closed(door_closed)
	_door_toggle_cooldown = 0.5
	_notify("Puerta cerrada" if door_closed else "Puerta abierta")


## Una sola tecla para jugar sin cámara: agarra el remedio que estás mirando,
## se lo da a CHILI si lo estás mirando, o abre/cierra la puerta.
func _interact() -> void:
	if not running or finished or _ending_queued:
		return
	if carried != null:
		if focus == Focus.CHILI or _time_without_chili < chili_memory:
			_cure_chili()
		else:
			_notify("Mirá a CHILI para darle el remedio")
		return
	# Un remedio en la mira gana sobre la puerta: si no, cerrar la puerta desde
	# lejos robaría el agarre.
	if looked_remedy != null or targeted_remedy != null:
		_on_grab()
		return
	if room.glb_door != null and _angle_to(room.glb_door, Vector3(0, 1.0, 0)) < 30.0:
		_toggle_door()
		return
	_on_grab()


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
	if not EyeInput.uses_camera():
		# Sin cámara la mirada la maneja el mouse (ver _input).
		return
	var obstructed := EyeInput.hand_obstructs() or (
		EyeInput.uses_camera() and EyeInput.zoom_hand)
	var can_look := EyeInput.tracking and not obstructed
	var can_turn := can_look \
		and not (EyeInput.uses_camera() and EyeInput.hand and carried == null)
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
#  MOVIMIENTO WASD (temporal, para calibrar posiciones)
# ============================================================

var _move_speed := 3.0

func _update_movement(delta: float) -> void:
	var input := Vector3.ZERO
	if Input.is_key_pressed(KEY_W):
		input.z -= 1.0
	if Input.is_key_pressed(KEY_S):
		input.z += 1.0
	if Input.is_key_pressed(KEY_A):
		input.x -= 1.0
	if Input.is_key_pressed(KEY_D):
		input.x += 1.0
	if input.length() > 0.0:
		input = input.normalized()
		var forward := -camera.global_transform.basis.z
		forward.y = 0.0
		forward = forward.normalized()
		var right := camera.global_transform.basis.x
		right.y = 0.0
		right = right.normalized()
		var movement := (forward * -input.z + right * input.x) * _move_speed * delta
		camera.position += movement
		camera.position.y = 0.65


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
	# Sin cámara se agarra con E, así que no hay gesto que esperar: si está en
	# la mira, ya se puede levantar.
	var ready := EyeInput.palm_ready or not EyeInput.uses_camera()
	if remedy.state == Pickup.State.HAND:
		return 0.8
	if remedy == looked_remedy:
		# El brillo máximo es la señal de "ahora podés agarrarlo".
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


## Lo que dice el HUD según lo que tenés delante. Respeta el mismo orden que
## `_interact`, así el cartel nunca promete algo distinto de lo que hace la tecla.
func _target_text() -> String:
	if not running or finished:
		return ""
	var action := "E o puño" if EyeInput.uses_camera() else "E"
	if carried != null:
		return "llevás %s — mirá a CHILI y apretá %s" % [carried.item_name, action]
	if looked_remedy != null:
		return "%s — %s para agarrar" % [looked_remedy.item_name, action]
	if targeted_remedy != null:
		return "%s — apretá %s para agarrar" % [targeted_remedy.item_name, action]
	if room.glb_door != null and _angle_to(room.glb_door, Vector3(0, 1.0, 0)) < 30.0:
		return ("puerta cerrada — %s para abrir" % action) if door_closed \
			else ("puerta abierta — %s para cerrar" % action)
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

	for data in REMEDIES:
		var remedy := Pickup.new()
		add_child(remedy)
		remedy.setup(
			data["name"],
			_mesh_for(data["shape"]),
			data["color"],
			data["at"],
			data["yaw"])
		remedies.append(remedy)


## Zonas que el desorden tiene que respetar: hoy no hay desorden, el baño ya
## viene amueblado en el GLB.
func _clear_zones() -> Array[Vector3]:
	return []


## Las medidas importan: la mitad de la altura es lo que se suma a DECK_Y para
## que el objeto quede apoyado y no flotando.
func _mesh_for(shape: Remedy) -> Mesh:
	match shape:
		Remedy.CYLINDER:
			return Shapes.cylinder(0.13, 0.26)
		Remedy.CAPSULE:
			return Shapes.capsule(0.09, 0.32)
		_:
			return Shapes.box(Vector3(0.36, 0.07, 0.18))


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
	if EyeInput.uses_camera():
		return "Poné la cabeza mirando al frente\ny apretá ENTER para empezar"
	return "Mové el mouse para mirar\ny apretá ENTER para empezar\n" \
		+ "E agarra, entrega y abre la puerta"


## Nada de esto se muestra en pantalla: es para depurar en la consola.
func _notify(text: String) -> void:
	print("[Main] ", text)


## Guarda las posiciones elegidas por el jugador en un archivo.
func _save_positions() -> void:
	var file := FileAccess.open(CONFIG_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("No pude guardar posiciones")
		return
	file.store_line("player=%s" % _saved_player_pos)
	file.store_line("chili=%s" % _saved_chili_pos)
	file.close()
	print("[POS] guardado en ", CONFIG_PATH)


## Lee los spawn guardados con P y C. Si el archivo no existe, quedan los
## valores por defecto: el juego nunca arranca sin posiciones.
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
