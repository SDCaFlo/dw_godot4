class_name DeathIris
extends ColorRect
## Fullscreen Iris transition shader for battle loss, sickness collapse, and reincarnation.
## Matches PSX murd.c MURD_renderIris and dooa.c DOOA_renderIrisWindow:
## In murd.c: lerp(0xC8, 0, start=0, end=35, t) - radius contracts from ~200 down to 0 onto the partner entity.

const DURATION_FRAMES := 35

var active := false
var timer := 0
var center := Vector2(0.5, 0.5)
var radius := 1.0
var contracting := true


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	visible = false

	var mat := ShaderMaterial.new()
	var code := """shader_type canvas_item;
uniform vec2 center = vec2(0.5, 0.5);
uniform float radius = 1.0;
uniform vec4 border_color : source_color = vec4(0.8, 0.8, 0.8, 1.0);
uniform float border_thickness = 0.01;

void fragment() {
	vec2 uv = UV;
	// Aspect ratio correction (4:3)
	vec2 diff = uv - center;
	diff.x *= 4.0 / 3.0;
	float dist = length(diff);
	if (dist > radius) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else if (dist > radius - border_thickness) {
		COLOR = border_color;
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
	_update_shader(1.0)


func start_iris_out(screen_center: Vector2 = Vector2(0.5, 0.5)) -> void:
	contracting = false
	center = screen_center
	timer = 0
	active = true
	visible = true
	_update_shader(0.0)


func tick() -> bool:
	if not active:
		return true

	timer += 1
	var progress := clampf(float(timer) / float(DURATION_FRAMES), 0.0, 1.0)
	var r := 1.0 - progress if contracting else progress
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
		material.set_shader_parameter("radius", radius)
