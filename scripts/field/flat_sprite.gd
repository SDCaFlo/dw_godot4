class_name FlatSprite
extends MeshInstance3D
## A flattened Digimon (renderFlatDigimon, model.c:2735): while its entity's `flat_sprite` isn't -1
## the model isn't drawn (renderDigimon skips every bone, model.c:2907) and this shows instead: a
## square as tall as the Digimon standing in its facing plane (x = 0 in its own space, so turned and
## squashed with it), textured with the 15 x 15 picture its own texture keeps at (0xE0 / 0xF0,
## 0x60 / 0x70) in palette 15 (the model's CLUT + 0x3C0), drawn opaque (colour 0 see-through).
## Sprites 0 and 1 are the two frames of the flattened Digimon, swapped every 10 frames of the
## entity's flatTimer counter; 2 and 3 are still pictures. The battle sets it
## (FieldBattleWorld.set_flat_sprite, specs/battle.md §2.13).
## A component of scenes/field/digimon.tscn, beside the drop shadow.

## alltim/<id>_<file>: the Digimon's ALLTIM texture (256 x 128), palette 15.
const TEXTURE := "alltim/%03d_%s.p15.png"
const PALETTE_SIZE := Vector2(256, 128)
const SWAP_FRAMES := 10

## The entity it stands for (its `flat_sprite`, `digimon`, its Model); null: the parent.
@export var entity: Node3D

## entity->flatTimer: renderFlatDigimon's own frame counter (sprites 0 / 1).
var flat_timer := 0

var _material: StandardMaterial3D
var _loaded_for := ""
var _height := 0
var _frame := -1
## The model was hidden by this (shown again when the sprite goes).
var _hid_model := false


func _ready() -> void:
	if entity == null:
		entity = get_parent() as Node3D
	cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	visible = false


func _process(_delta: float) -> void:
	if entity == null:
		return
	var sprite := int(entity.get("flat_sprite")) if entity.get("flat_sprite") != null else -1
	var model := entity.get_node_or_null("Model") as Node3D
	if sprite == -1:
		if _hid_model and model != null:
			model.visible = true
		_hid_model = false
		visible = false
		return
	if model != null and model.visible:
		model.visible = false
		_hid_model = true
	if not _load():
		visible = false
		return
	# Once per game frame, as the C's render: sprites 0 / 1 swap every 10 counts.
	var loop := get_node_or_null("/root/GameLoop")
	var game_frame: int = int(loop.get("frame_count")) if loop != null else _frame + 1
	if game_frame != _frame:
		_frame = game_frame
		if sprite < 2:
			if flat_timer % SWAP_FRAMES == 0:
				sprite = (sprite + 1) & 1
				entity.set("flat_sprite", sprite)
			flat_timer += 1
	var u := 0xE0 if sprite % 2 == 0 else 0xF0
	var v := 0x60 if sprite < 2 else 0x70
	_material.uv1_offset = Vector3(u / PALETTE_SIZE.x, v / PALETTE_SIZE.y, 0)
	visible = true


## The quad (height x height, its base on the ground) and the Digimon's texture.
func _load() -> bool:
	var key := str(entity.get("digimon"))
	if key == _loaded_for:
		return _material != null
	_loaded_for = key
	_material = null
	var data := get_node_or_null("/root/GameData")
	if data == null or key == "":
		return false
	var id: int = data.id_of("digimon/digimon_data", key)
	var file: String = data.digimon_file(id).get("file_name", "")
	var texture := Content.load_texture(TEXTURE % [id, file]) if file != "" else null
	if texture == null:
		return false
	_height = int(data.digimon(id).get("height", 0))
	var quad := QuadMesh.new()
	# renderFlatDigimon's corners: (0, -h, ∓h/2) at the top, (0, 0, ∓h/2) at the ground, in the
	# entity's space; u runs from the PSX's -z (Godot +z) to its +z.
	quad.size = Vector2(_height, _height)
	quad.orientation = PlaneMesh.FACE_X
	quad.center_offset = Vector3(0, _height / 2.0, 0)
	mesh = quad
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.albedo_texture = texture
	_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	_material.alpha_scissor_threshold = 0.5
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.uv1_scale = Vector3(15.0 / PALETTE_SIZE.x, 15.0 / PALETTE_SIZE.y, 1)
	material_override = _material
	return true
