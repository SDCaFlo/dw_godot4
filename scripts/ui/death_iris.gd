class_name DeathIris
extends ColorRect
## The death scenes' iris and the map background's darkening (scenes/field/death/death_iris.tscn,
## its shader death_iris.gdshader): MURD_renderIris / DOOA_renderIrisWindow close a window on the
## partner, fadeoutCLUT1 darkens the background. A view: DeathHost sets it every frame from the
## MURD and DOOA objects. It sits in the background canvas layer (field.tscn's Background), whose
## scale follows the render scale, so it keeps the PSX size of 320 x 240.

## The window's radius at its widest: 2 * lerp(200, 0, ...) pixels (the C's right = scale * 256 / 4096
## with scale = lerp(...) << 12 / 128).
const MAX_RADIUS := 400.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	position = Vector2.ZERO
	size = Vector2(FieldMap.SCREEN)
	visible = false


## The window around `center` (PSX screen pixels) with `radius`, the background `darkness` (0-255).
func show_iris(center: Vector2, radius: float, darkness: int) -> void:
	var mat := material as ShaderMaterial
	if mat != null:
		mat.set_shader_parameter("center", center)
		mat.set_shader_parameter("radius", radius)
		mat.set_shader_parameter("darkness", darkness / 255.0)
	visible = true


func hide_iris() -> void:
	visible = false
