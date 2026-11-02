class_name Hud
extends CanvasLayer
## Toda la interfaz: viñeta de contagio, negro de ojos cerrados, lista de
## remedios pendientes, mensajes del centro y el panel de depuración (F1).
##
## No sabe nada del juego: solo recibe valores ya calculados.

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float fuerza : hint_range(0.0, 1.0) = 0.0;
void fragment() {
	vec2 uv = UV - vec2(0.5);
	float d = length(uv * vec2(1.0, 0.8));
	float v = smoothstep(0.2, 0.7, d);
	COLOR = vec4(0.04, 0.1, 0.02, v * fuerza);
}
"""

var debug_visible := false

var _vignette: ShaderMaterial
var _blind: ColorRect
var _ending_background: ColorRect
var _center: Label
var _debug: Label
var _pending: Label


func build() -> void:
	_vignette = _add_vignette()
	_blind = _add_full_rect(Color(0, 0, 0, 0))
	_ending_background = _add_full_rect(Color.BLACK)
	_ending_background.visible = false

	_center = Label.new()
	add_child(_center)
	_center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_center.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_center.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_center.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_center.add_theme_font_size_override("font_size", 28)

	_debug = Label.new()
	_debug.position = Vector2(12, 8)
	_debug.add_theme_font_size_override("font_size", 15)
	_debug.visible = debug_visible
	add_child(_debug)

	_pending = Label.new()
	add_child(_pending)
	_pending.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_pending.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	_pending.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_pending.offset_right = -16.0
	_pending.offset_top = 10.0
	_pending.add_theme_font_size_override("font_size", 18)
	_pending.visible = false


func show_hint(text: String) -> void:
	_center.text = text
	_center.visible = true


func hide_hint() -> void:
	_center.visible = false
	_center.text = ""


func show_ending(text: String) -> void:
	_ending_background.visible = true
	_center.text = text
	_center.visible = true
	_pending.visible = false


## 0 = nada, 1 = verde cerrado por todos lados.
func set_vignette(amount: float) -> void:
	_vignette.set_shader_parameter("fuerza", clampf(amount, 0.0, 1.0))


## 0 = ojos abiertos, 1 = pantalla en negro.
func set_blind(amount: float) -> void:
	_blind.color = Color(0, 0, 0, clampf(amount, 0.0, 1.0))


func set_pending(names: PackedStringArray, visible: bool) -> void:
	_pending.text = "\n".join(names)
	_pending.visible = visible and not names.is_empty()


func set_debug(text: String) -> void:
	_debug.text = text


func set_debug_visible(value: bool) -> void:
	debug_visible = value
	_debug.visible = value


func toggle_debug() -> void:
	set_debug_visible(not debug_visible)


func _add_full_rect(color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# Los rectángulos se agregan antes que los textos: mandarlos al frente ahora
	# deja los labels siempre arriba, sin pelear con el orden del árbol.
	rect.move_to_front()
	return rect


func _add_vignette() -> ShaderMaterial:
	var rect := ColorRect.new()
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := Shader.new()
	shader.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = shader
	rect.material = mat
	add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return mat
