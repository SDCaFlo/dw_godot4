@tool
class_name DropShadow
extends MeshInstance3D
## An entity's drop shadow (renderDropShadow, drop_shadow.c:19; specs/drop_shadow.md): the
## ETCDAT/SPOT256.TIM spot subtracted from the ground in a square of ±radius around the entity, in
## world axes. Shown while the entity's model is drawn (on the map, on screen) and its cell isn't
## blocked (getTileTrigger != -1).

## The texture: ETCDAT/SPOT256.TIM, the 63 x 63 cell at (64, 0) (UV (0x40, 0x80) of page
## (832, 256), palette row 0x1E7); colour 0x30 of 0x80, subtracted.
const TEXTURE := "tim_files/ETCDAT/SPOT256.png"
const CELL := Rect2(64, 0, 63, 63)
const COLOR := 0x30 / 128.0
## Over the ground, so it doesn't fight with what lies there.
const LIFT := 0.5

## The shader (a mod may replace it): the PSX's subtraction in its gamma values.
const _SHADER := preload("res://shaders/drop_shadow.gdshader")

## The entity it lies under (its `field`, `radius`, `on_map`, `on_screen`); null: the parent.
@export var entity: Node3D

static var _material: ShaderMaterial

## PLAYER_SHADOW_ENABLED (model.c, the tamer's: renderDigimon skips the shadow while 0; ENDI clears it).
var enabled := true

var _radius := -1


## The shadow material, shared by the entities and the items on the ground (MapItems).
static func material() -> ShaderMaterial:
	if _material != null:
		return _material
	_material = ShaderMaterial.new()
	_material.shader = _SHADER
	_material.set_shader_parameter("tex", Content.load_texture(TEXTURE))
	_material.set_shader_parameter("region", Vector4(CELL.position.x / 128.0, CELL.position.y / 128.0,
			CELL.size.x / 128.0, CELL.size.y / 128.0))
	_material.set_shader_parameter("color_scale", COLOR)
	return _material


func _ready() -> void:
	if entity == null:
		entity = get_parent() as Node3D
	top_level = true
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if mesh == null:
		var quad := QuadMesh.new()
		quad.orientation = PlaneMesh.FACE_Y
		mesh = quad
	material_override = material()
	visible = false


func _process(_delta: float) -> void:
	update()


## Follows the entity: its position and radius, and whether renderDropShadow draws this frame.
func update() -> void:
	if entity == null:
		return
	var radius := int(entity.get("radius"))
	if radius != _radius and mesh is QuadMesh:
		_radius = radius
		(mesh as QuadMesh).size = Vector2(radius * 2, radius * 2)
	global_position = entity.global_position + Vector3(0, LIFT, 0)
	visible = shown()


## renderDigimon draws the entity (on the map, on screen) and getTileTrigger isn't -1.
func shown() -> bool:
	if not enabled:
		return false
	var value: Variant = entity.get("field")
	if not is_instance_valid(value) or not value is FieldMap:
		return false
	var field: FieldMap = value
	if field.map_name == "" or entity.get("on_map") == false or entity.get("on_screen") == false:
		return false
	return field.tile_trigger(entity.position) != -1
