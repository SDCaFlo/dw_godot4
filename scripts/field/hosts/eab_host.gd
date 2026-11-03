class_name EabHost
extends Node
## Machinedramon's build-up and spawn on Mt. Infinity (specs/map_events.md §3.3, §4.3.2; eab.c). Its
## EabScene is the logic, ticked as an object of the field's frame (tick_objects); routine 0x33 loads
## (load_scene), routine 0x28 starts the build-up (start_buildup), the tamer's state 18 starts the spawn and
## waits for it (start_spawn, result). The host does what the scene's events say (entities, the map
## layer, the camera, the sounds) and draws it: EabView (rings, backdrop, particle lines, flash), a
## PartnerWireframe on entity 2 (ENTITY1_WIREFRAME_TOTAL) and a BattleFxView for the nine flashes.

const WIREFRAME_SCENE := preload("res://scenes/field/partner_wireframe.tscn")
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
## readVBALLSection(5, 0x73) (script_interp.c:1845): Machinedramon's sound set into slot 5.
const VAB_SLOT := 5
const VBALL_DIGIMON := 0x73
## loadMapSounds2(0x15) (script_interp.c:1846).
const MAP_SOUNDS := 0x15
## EAB_tick(ENTITY_TABLE[2], ...) (tamer.c:1722, :1726); EAB_setEntitiesVisible skips it (eab.c:503).
const SPAWN_ENTITY := 2
## WIREFRAME_COLOR_MIN / MAX (model.c:89, :91): EAB never changes them.
const WIRE_GREY_MIN := 0x37
const WIRE_GREY_MAX := 0xFF

var field_map: FieldMap
var entities: FieldEntities
var sound: Node
var data: Node
## The map layer's nodes (Field.map_layer_nodes): setMapLayerEnabled hides them.
var map_layer_nodes := Callable()
## The 3D views' parent (the world SubViewport).
var world: Node
## The field's background layer (the backdrop and the lines, behind the models).
var background: Node

var scene := EabScene.new()
var view: EabView
var wireframe: PartnerWireframe
var fx_view: BattleFxView

## MAIN_D_801353F0.entity (the build-up's, script entity 5) and EAB_D_800617E8.entity (entity 2).
var _buildup_entity: Node3D
var _spawn_entity: Node3D
## EAB_D_80061A04: per entity, 1 when EAB_setEntitiesVisible(0) took it off the map.
var _taken_off := {}
## EAB_D_800619E4: the viewpoint saved at phase 1.
var _saved_view := {}


## Makes the views.
func start() -> void:
	view = EabView.new()
	view.name = "EabView"
	add_child(view)
	view.attach(world, background)
	wireframe = WIREFRAME_SCENE.instantiate()
	add_child(wireframe)
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.fx = scene.fx
	fx_view.projector = field_map
	if world != null:
		world.add_child(fx_view)


## Routine 0x33 (script_interp.c:1841-1846): the ring model (the file request), Machinedramon's
## sounds into slot 5, the map's sound set 0x15. The REL load has nothing to port.
func load_scene() -> void:
	view.load_model(field_map.map_name if field_map != null else "")
	if sound == null:
		return
	var vball = data.digimon_sounds(VBALL_DIGIMON).get("vball") if data != null else null
	if vball != null:
		sound.load_bank(VAB_SLOT, "sound/VBALL/set_%02d" % int(vball))
	sound.load_map_sounds(MAP_SOUNDS)


## Routine 0x28 (script_interp.c:1853-1856): EAB_startBuildup on the script's entity. isSoundLoaded(0, 8)
## waits for a load the port has done at once.
func start_buildup(entity: Node3D) -> void:
	_buildup_entity = entity
	scene.start_buildup()
	_run_events()


## tamerTickMachinedramonSpawn's sub-state 0 (tamer.c:1722): EAB_tick(ENTITY_TABLE[2], 0).
func start_spawn() -> void:
	_spawn_entity = entities.entity(SPAWN_ENTITY) if entities != null else null
	if _spawn_entity == null:
		return
	_set_inputs()
	scene.start_spawn()
	_run_events()
	_attach_wireframe()


## EAB_tick(entity, 1): the spawn's frame, -1 once over (or never started).
func result() -> int:
	return scene.result() if _spawn_entity != null else -1


func is_running() -> bool:
	return scene.buildup_active or scene.spawn_active or scene.rings.any(func(r): return int(r["timer"]) >= 0) \
			or scene.particles.any(func(p): return int(p["timer"]) >= 0)


## The objects' frame: the scene's tick, its events, then what the C draws.
func tick_objects() -> void:
	if not is_running():
		return
	_set_inputs()
	scene.tick()
	_run_events()
	if not scene.view.is_empty() and field_map != null:
		field_map.set_view({"eye": scene.view["eye"], "ref": scene.view["ref"],
				"projection": _saved_view.get("projection", field_map.viewport_distance()),
				"offset": _saved_view.get("offset", Vector2i(field_map.drawing_offset().round()))})
	_draw_frame()


## The inputs from entity 2 (EAB_tickSpawn reads entity->posData, its bone 0, its animation).
func _set_inputs() -> void:
	var e := _spawn_entity
	if e == null:
		if _buildup_entity != null:
			scene.location = _psx(_buildup_entity.position)
		return
	scene.location = _psx(e.position)
	scene.yaw = int(e.get("direction"))
	var digimon := e as FieldDigimon
	scene.bone0 = _psx(digimon.bone_position(0)) if digimon != null else scene.location
	var animator = e.get("animator")
	if animator is PsxAnimator:
		scene.anim_id = animator.anim_id
		scene.anim_ended = animator.frame == animator.frame_count
	else:
		scene.anim_id = -1
		scene.anim_ended = false


static func _psx(p: Vector3) -> Vector3i:
	return Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z))


func _run_events() -> void:
	for ev in scene.events:
		var name: String = ev[0] if ev is Array else ev
		match name:
			"buildup_entity_hidden":
				_set_on_map(_buildup_entity, false)
			"sound", "sound2":
				if sound != null:
					sound.play_sound(int(ev[1]), int(ev[2]))
			"stop_sound":
				if sound != null:
					sound.stop_sound()
			"entity_on_map":
				_set_on_map(_spawn_entity, true)
			"animation":
				if _spawn_entity != null:
					_spawn_entity.call("start_animation", int(ev[1]))
			"hide_entities":
				_set_entities_visible(false)
			"show_entities":
				_set_entities_visible(true)
			"map_layer_off":
				MapLayer.set_enabled(_layer_nodes(), false)
			"map_layer_on":
				MapLayer.set_enabled(_layer_nodes(), true)
			"save_view":
				_saved_view = field_map.view() if field_map != null else {}
			"restore_view":
				# stand-in: the saved viewpoint is the map's own (script 184 moves no camera before).
				if field_map != null:
					field_map.restore_map_view()
			"vab":
				if _spawn_entity != null and "sound_slot" in _spawn_entity:
					_spawn_entity.set("sound_slot", int(ev[1]))
	scene.events.clear()


## isOnMap, with the node shown or hidden (renderDigimon / renderTamer skip an entity off the map).
static func _set_on_map(e: Node3D, on: bool) -> void:
	if e == null:
		return
	e.set("on_map", on)
	e.visible = on


## EAB_setEntitiesVisible (eab.c:497-517): off, every entity but 2 on the map goes off it and is
## remembered; on, every entity but 2 gets what was remembered.
func _set_entities_visible(enabled: bool) -> void:
	if entities == null:
		return
	var table := entities.table()
	if not enabled:
		_taken_off.clear()
		for i in table.size():
			var e: Node3D = table[i]
			if i != SPAWN_ENTITY and e != null and e.get("on_map") != false:
				_set_on_map(e, false)
				_taken_off[i] = 1
			else:
				_taken_off[i] = 0
	else:
		for i in table.size():
			var e: Node3D = table[i]
			if i == SPAWN_ENTITY or e == null:
				continue
			if int(_taken_off.get(i, 0)) == 1:
				_set_on_map(e, true)
			else:
				e.set("on_map", false)


func _layer_nodes() -> Array:
	return map_layer_nodes.call() if map_layer_nodes.is_valid() else []


func _draw_frame() -> void:
	var spawn_at := scene.location
	var buildup_at := _psx(_buildup_entity.position) if is_instance_valid(_buildup_entity) else spawn_at
	if field_map != null:
		view.draw_frame(scene, buildup_at, spawn_at, field_map.world_to_screen, field_map.drawing_offset())
	else:
		view.draw_frame(scene, buildup_at, spawn_at, Callable(), Vector2.ZERO)
	fx_view.draw_frame()
	# renderDigimon (model.c:2922): entity 2 in wireframe while ENTITY1_WIREFRAME_TOTAL isn't 16.
	if wireframe.is_attached():
		wireframe.set_share(scene.wireframe_total)
		if wireframe.share != PartnerWireframe.TOTAL:
			wireframe.roll_greys(WIRE_GREY_MIN, WIRE_GREY_MAX)
	if not is_running():
		wireframe.detach()
		view.clear()


## The wireframe on entity 2's model (its sidecar and glTF), as DeathHost's on the partner.
func _attach_wireframe() -> void:
	var digimon := _spawn_entity as FieldDigimon
	if digimon == null or data == null or digimon.digimon == "":
		return
	var slot := digimon.get_node_or_null("Model")
	if slot == null or slot.get_child_count() == 0:
		return
	var model := slot.get_child(slot.get_child_count() - 1) as Node3D
	var mmd: String = data.digimon_file(digimon.digimon).get("mmd", "")
	if mmd == "":
		return
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var sidecar: Variant = Content.load_json(rel.get_basename() + ".json")
	var gltf: Variant = Content.load_json(rel)
	if sidecar is Dictionary and gltf is Dictionary:
		wireframe.attach(model, sidecar, gltf)
