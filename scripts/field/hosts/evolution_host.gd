class_name EvolutionHost
extends Node
## The evolution scene (specs/evolution_scene.md §5; scenes/field/hosts/evolution_host.tscn). Its child
## EvolutionScene is the logic (the loading, then the EvlSequence), ticked as an object of the field's
## frame (tick_objects, A1); partner state 13 starts it and reads its timer. The host wires the
## sequence to the field and draws what it reports, each view a scene a mod may replace:
## - the camera moves through FieldMap's view hook (the sequence's view callables);
## - the other entities and the map layer are hidden at the hand-over (B10, B11) and back at the end;
## - the flashes (BattleFxView with the sequence's BattleFx);
## - the map background's darkening (BackgroundDark at map_fade / 255) and the tamer's and the NPCs'
##   palette banks (PaletteFade, B4);
## - the bodies (J): `wireframe` (PartnerWireframe) on the old model, each broken bone in outlines
##   (PARTNER_WIREFRAME_SUB), then on the new model filling in (PARTNER_WIREFRAME_TOTAL); the
##   partner's root scale while it grows.
## - the shard sets (E): built from the broken bone's pose, drawn by EvlShardsView.
## The sparks, rings and the brighten come with the later steps of the spec.

const BACKGROUND_DARK_SCENE := preload("res://scenes/field/death/background_dark.tscn")
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
const SHARDS_SCENE := preload("res://scenes/field/evolution/evl_shards.tscn")
## Entities 2, 3, 4 are the second palette bank's (evl.c:391-395, EVL_fadeClutBank1: (32, 488) 48 x 24).
const BANK1_ENTITIES := [2, 3, 4]
## WIREFRAME_COLOR_MIN / MAX (model.c:89, :91): the evolution never changes them (J2).
const WIRE_GREY_MIN := 0x37
const WIRE_GREY_MAX := 0xFF

var camera: Camera3D
var field_map: FieldMap
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var evolution: Evolution
var game_state: Node
var data: Node
var sound: Node
var bubbles: ConditionBubbles
## The map layer's nodes (Field.map_layer_nodes): setMapLayerEnabled hides them.
var map_layer_nodes := Callable()
## The world SubViewport: the 3D views go in it.
var world: Node

@onready var evolution_scene: EvolutionScene = $EvolutionScene
@onready var wireframe: PartnerWireframe = $PartnerWireframe
## Made in start(): the field adds the background darkening to its background layer; the flashes go
## into the world here.
var background_dark: ColorRect
var fx_view: BattleFxView
var shards_view: EvlShardsView

## Each other entity's `visible` before the hand-over (EVL_D_80068938).
var _shown := {}
## The palette factor last applied to each entity (PaletteFade).
var _fades := {}
## A sequence is running (its views are drawn until it has ended).
var _active := false
var _skeleton_of: Node3D
var _skeleton: Skeleton3D


## Hands the scene its references and makes the views.
func start() -> void:
	background_dark = BACKGROUND_DARK_SCENE.instantiate()
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.projector = field_map
	shards_view = SHARDS_SCENE.instantiate()
	if world != null:
		world.add_child(fx_view)
		world.add_child(shards_view)
	if partner == null:
		return
	evolution_scene.partner = partner
	evolution_scene.evolution = evolution
	evolution_scene.game_state = game_state
	evolution_scene.data = data
	evolution_scene.sound = sound
	evolution_scene.bubbles = bubbles
	evolution_scene.sequence_started.connect(_on_sequence_started)
	partner.evolution_scene = evolution_scene


## The sequence's wiring to the field (its views and the hand-over / end).
func _on_sequence_started(sequence: EvlSequence) -> void:
	if field_map != null:
		sequence.get_view = field_map.view
		sequence.set_view = field_map.set_view
		sequence.restore_view = field_map.restore_map_view
	sequence.bone_position = _bone_position
	sequence.hand_over.connect(_on_hand_over)
	sequence.ended.connect(_on_ended)
	sequence.applied.connect(_on_applied)
	sequence.bone_broken.connect(_on_bone_broken.bind(sequence))
	fx_view.fx = sequence.fx
	_attach_wireframe()
	_active = true


## The object's frame (A1): the scene's tick, then what the C draws that frame.
func tick_objects() -> void:
	if evolution_scene == null or partner == null:
		return
	evolution_scene.tick()
	var sequence := evolution_scene.sequence
	if sequence == null or not _active:
		return
	_draw_frame(sequence)
	if sequence.timer == -1:
		_active = false
		wireframe.detach()
		partner.scale = Vector3.ONE
		shards_view.clear()


func _draw_frame(sequence: EvlSequence) -> void:
	# fadeoutCLUT1 (B1, B2): the map background's darkening.
	background_dark.color = Color(0, 0, 0, sequence.map_fade / 255.0)
	# The overlay sprites share the background's palette rows (fadeoutCLUT1, specs/evolution_scene.md B2).
	if field_map != null and field_map.overlays != null:
		field_map.overlays.set_fade(sequence.map_fade)
	# The palette banks (B4): bank 0 the tamer's, bank 1 entities 2-4.
	_fade(tamer, sequence.bank0_factor)
	for i in BANK1_ENTITIES:
		_fade(entities.entity(i) if entities != null else null, sequence.bank1_factor)
	fx_view.draw_frame()
	# The bodies (J1, J5, J7): renderDigimon's TOTAL / SUB, the greys of the objects in outlines (J2).
	if wireframe.is_attached():
		wireframe.set_share(sequence.wireframe_total, sequence.wireframe_sub)
		wireframe.roll_greys(WIRE_GREY_MIN, WIRE_GREY_MAX)
	# The shard sets (E7, E8): every non-black texel blends from the brighten's first non-start frame.
	shards_view.draw(sequence.shards, wireframe.bone_materials, sequence.brighten_t > EvlSequence.BRIGHTEN_FROM)
	# The growth (J3, J6): the partner's root scale, 4096 = 1.
	partner.scale = Vector3(sequence.scale) / float(EvlSequence.SCALE_ONE)


## A palette factor on an entity's materials; 1 gives its own back.
func _fade(entity: Node3D, factor: float) -> void:
	if entity == null or not is_instance_valid(entity) or _fades.get(entity, 1.0) == factor:
		return
	if factor >= 1.0:
		PaletteFade.clear(entity)
		_fades.erase(entity)
	else:
		_fades[entity] = factor
		PaletteFade.apply(entity, factor)


## State 0's end (evl.c:396-408): EVL_setOtherEntitiesVisible(0), setMapLayerEnabled(0). Every entity
## but the partner is hidden, each one's `visible` remembered (B10).
func _on_hand_over() -> void:
	_shown.clear()
	if entities != null:
		for e in entities.table():
			if e != null and e != partner:
				_shown[e] = e.visible
				e.visible = false
	MapLayer.set_enabled(_layer_nodes(), false)


## State 3 (evl.c:571-572): the others back as they were, the map layer on.
func _on_ended() -> void:
	for e in _shown:
		if is_instance_valid(e):
			e.visible = _shown[e]
	_shown.clear()
	MapLayer.set_enabled(_layer_nodes(), true)


func _layer_nodes() -> Array:
	return map_layer_nodes.call() if map_layer_nodes.is_valid() else []


## posData[bone].posMatrix.workm.t as PSX ints from the partner model's skeleton (D7: the current
## pose); a bone the model doesn't have reads bone 0 (F9, effect_common.c:341-343).
func _bone_position(bone: int) -> Vector3i:
	var skeleton := _partner_skeleton()
	if skeleton == null:
		return Vector3i(roundi(partner.position.x), roundi(-partner.position.y), roundi(-partner.position.z))
	# The porter names the joints bone_<i> after the PSX bones (asset_porter/specs/mmd.md).
	var index := skeleton.find_bone("bone_%d" % bone)
	if index < 0:
		index = skeleton.find_bone("bone_0")
	var world_point := skeleton.global_transform * skeleton.get_bone_global_pose(maxi(index, 0)).origin
	return Vector3i(roundi(world_point.x), roundi(-world_point.y), roundi(-world_point.z))


## EVL_buildShardSet (evl.c:440): the broken bone's object in this frame's pose (E2, E3).
func _on_bone_broken(bone: int, sequence: EvlSequence) -> void:
	var posed := wireframe.posed_bone(bone)
	if not posed.is_empty():
		sequence.shards.build(bone, posed["object"], posed["vertices"], posed["normals"])


## EVL_applyEvolution's new model (J5): the wireframe moves onto it.
func _on_applied() -> void:
	_attach_wireframe()


## The wireframe on the partner's current model (its sidecar and glTF), as DeathHost's.
func _attach_wireframe() -> void:
	var model := _partner_model()
	if model == null or data == null:
		return
	var mmd: String = data.digimon_file(partner.digimon).get("mmd", "")
	if mmd == "":
		return
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var sidecar: Variant = Content.load_json(rel.get_basename() + ".json")
	var gltf: Variant = Content.load_json(rel)
	if sidecar is Dictionary and gltf is Dictionary:
		wireframe.attach(model, sidecar, gltf)


func _partner_model() -> Node3D:
	var slot := partner.get_node_or_null("Model")
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(slot.get_child_count() - 1) as Node3D


## The Skeleton3D of the partner's current model.
func _partner_skeleton() -> Skeleton3D:
	var model := _partner_model()
	if model == null:
		return null
	if model != _skeleton_of or not is_instance_valid(_skeleton):
		_skeleton_of = model
		var found := model.find_children("*", "Skeleton3D", true, false) if model != null else []
		_skeleton = found[0] as Skeleton3D if not found.is_empty() else null
	return _skeleton
