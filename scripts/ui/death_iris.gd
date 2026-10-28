class_name DeathIris
extends ColorRect
## Fullscreen Iris transition shader for battle loss, sickness collapse, and reincarnation.
## Matches PSX murd.c MURD_renderIris and dooa.c DOOA_renderIrisWindow:
## In murd.c: lerp(0xC8, 0, start=0, end=35, t) - radius contracts from ~200 down to 0 onto the partner entity.

const DURATION_FRAMES := 35
const MAX_RADIUS := 400.0

var active := false
var timer := 0
var center := Vector2(0.5, 0.5)
var radius := MAX_RADIUS
var contracting := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size = Vector2(320, 240)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var mat := ShaderMaterial.new()
	var code := """shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius_pixels = 400.0;
uniform vec2 screen_size = vec2(320.0, 240.0);

void fragment() {
	vec2 diff = (UV - center) * screen_size;
	if (length(diff) > radius_pixels) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		COLOR = vec4(0.0, 0.0, 0.0, 0.0);
	}
}
"""
	var shader := Shader.new()
	shader.code = code
	mat.shader = shader
	material = mat


func start_iris_in(screen_center: Vector2 = Vector2(0.5, 0.5)) -> void:
	contracting = true
	center = screen_center
	timer = 0
	active = true
	visible = true
	_update_shader(MAX_RADIUS)


func start_iris_out(screen_center: Vector2 = Vector2(0.5, 0.5)) -> void:
	contracting = false
	center = screen_center
	timer = 0
	active = true
	visible = true
	_update_shader(0.0)


func hide_iris() -> void:
	active = false
	visible = false
	_update_shader(MAX_RADIUS)


func tick() -> bool:
	if not active:
		return true

	timer += 1
	var progress := clampf(float(timer) / float(DURATION_FRAMES), 0.0, 1.0)
	var r := (1.0 - progress) * MAX_RADIUS if contracting else progress * MAX_RADIUS
	_update_shader(r)

	if timer >= DURATION_FRAMES:
		active = false
		if not contracting:
			visible = false
		return true
	return false


func _update_shader(r: float) -> void:
	radius = r
	if material is ShaderMaterial:
		material.set_shader_parameter("center", center)
		material.set_shader_parameter("radius_pixels", radius)
		material.set_shader_parameter("screen_size", Vector2(320.0, 240.0))
