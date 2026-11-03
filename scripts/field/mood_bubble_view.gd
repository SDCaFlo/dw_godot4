class_name MoodBubbleView
extends Control
## Monochromon's mood bubble on screen (renderMonochromonMoodBubble, script_common.c:1220;
## specs/map_events.md S10, S11, §4.2.3): MapEffects.bubble_draws, one GsSortSprite per render
## object, at the entity's condition-FX point (translateConditionFXToEntity, effect_common.c:307)
## projected by worldPosToScreenPos, raised by the draw's offset and scaled by its scale.
##
## The faces are the shop map's VRAM (asset porter maps/<NAME>/mood/faces: GCAN11's 4bpp page
## (640, 0), u = mood · 32, CLUT (0, 486)). Attribute 0x50000000: semi-transparent at rate 1, so the
## STP texels add (an additive child layer) and the others draw opaque. A map without the strip
## draws nothing. stand-in: drawn in the HUD, over the 3D world (the C sorts it at OT depth >> 4),
## as the condition bubbles are.

const TEXTURE := "maps/%s/mood/faces"
const SCALE_ONE := 4096.0

var effects: MapEffects
var field: FieldMap
var data: Node

var _faces: PsxTexture
var _faces_of := "-"
var _additive: Control


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	material = PsxUiFilter.material()
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.material = PsxUiFilter.material("add")
	_additive.draw.connect(_draw_faces.bind(true))
	add_child(_additive)


## Once per game frame, after MapEffects.tick.
func refresh() -> void:
	queue_redraw()
	_additive.queue_redraw()


func _draw() -> void:
	_draw_faces(false)


func _draw_faces(additive: bool) -> void:
	if effects == null or field == null or effects.bubble_draws.is_empty():
		return
	if field.map_name != _faces_of:
		_faces_of = field.map_name
		var rel := TEXTURE % field.map_name
		_faces = PsxTexture.load_masked(rel) if Content.exists(rel + ".png") else null
	if _faces == null:
		return
	var canvas: CanvasItem = _additive if additive else self
	var region := Rect2(effects.bubble.u, 0, MoodBubble.SIZE, MoodBubble.SIZE)
	for rect in sprite_rects():
		canvas.draw_texture_rect_region(_faces.stp if additive else _faces.base, rect, region)


## The screen rects of this frame's draws: GsSortSprite puts the pivot (16, 16) on (screen.x,
## screen.y − offset), the sprite scaled by scale / 4096.
func sprite_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	if effects == null or field == null or effects.bubble_entity == null:
		return rects
	var p := fx_point(effects.bubble_entity)
	var r := field.world_to_screen(Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z)))
	var screen := field.drawing_offset() + Vector2(r["screen"])
	for d in effects.bubble_draws:
		var factor: float = d["scale"] / SCALE_ONE
		var anchor := screen - Vector2(0, d["offset"])
		rects.append(Rect2(anchor - Vector2(MoodBubble.PIVOT) * factor, Vector2(MoodBubble.SIZE, MoodBubble.SIZE) * factor))
	return rects


## translateConditionFXToEntity (effect_common.c:307): CONDITION_FX_OFFSETS[type]'s offset through
## its bone's world matrix (Godot space). The tamer (not a FieldDigimon): his position (stand-in; no
## script shows him a bubble).
func fx_point(entity: Node3D) -> Vector3:
	if not entity is FieldDigimon or data == null:
		return entity.global_position
	var digimon: FieldDigimon = entity
	var entry: Dictionary = data.condition_fx_offset(digimon.digimon)
	var o: Dictionary = entry.get("offset", {})
	var bone := int(entry.get("bone", 0))
	var offset := Content.psx_to_godot([int(o.get("x", 0)), int(o.get("y", 0)), int(o.get("z", 0))])
	return digimon.bone_position(bone) + digimon.bone_basis(bone) * offset
