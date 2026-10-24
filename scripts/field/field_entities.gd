class_name FieldEntities
extends RefCounted
## The field's entity table (specs/npc.md §3.1): ENTITY_TABLE[10] (0 the tamer, 1 the partner,
## 2-9 the NPCs), the 8 map Digimon slots (MAP_DIGIMON_TABLE with the NPC_ENTITIES fields that
## outlive an entity: script id, autotalk, stats), the 8 loaded-model slots, and the per-slot
## arrays of overworld.c (NPC_ACTIVE_ANIM, NPC_IS_WALKING_TOWARDS, NPC_COLLISION_STATE).

const NPC_SLOTS := 8
const MODEL_SLOTS := 8
const ENTITY_COUNT := 10
const NONE := 0xFF
const OWNER_TAMER := 0xFD
const OWNER_PARTNER := 0xFC

var tamer: Node3D
var partner: Node3D
## ENTITY_TABLE[2 + slot]: the NPC entities (null: none).
var npcs: Array = []
## MAP_DIGIMON_TABLE + NPC_ENTITIES per slot (see _empty_slot).
var slots: Array = []
## LOADED_DIGIMON_MODELS: Digimon types, -1 free.
var loaded_models: Array = []
var active_anim: Array = []
var walking_towards: Array = []
var collision_state: Array = []
## func(slot: int) -> Npc: creates an NPC entity for SET_DIGIMON (the field: model, node, tick).
var npc_factory := Callable()


func _init() -> void:
	npcs.resize(NPC_SLOTS)
	slots.resize(NPC_SLOTS)
	loaded_models.resize(MODEL_SLOTS)
	loaded_models.fill(-1)
	active_anim.resize(NPC_SLOTS)
	walking_towards.resize(NPC_SLOTS)
	collision_state.resize(NPC_SLOTS)
	collision_state.fill(-1)
	clear_map_digimon()


## ENTITY_TABLE as an array of 10 (null where empty).
func table() -> Array:
	return [tamer, partner] + npcs


func entity(index: int) -> Node3D:
	if index == 0:
		return tamer
	if index == 1:
		return partner
	if index >= 2 and index < ENTITY_COUNT:
		return npcs[index - 2]
	return null


## isInvisible (utils2.c:367): no entity, off screen or not on the map.
static func is_invisible(e: Node3D) -> bool:
	return e == null or e.get("on_screen") == false or e.get("on_map") == false


## scriptIdToEntityId (script_value.c:131): 0 the tamer, 1 the partner, 2-9 the first NPC
## entity with that script id, else 0xFF.
func script_id_to_entity_id(script_id: int) -> int:
	if script_id == OWNER_TAMER:
		return 0
	if script_id == OWNER_PARTNER:
		return 1
	for i in NPC_SLOTS:
		if npcs[i] != null and script_id == int(slots[i]["script_id"]):
			return i + 2
	return NONE


## getEntityFromScriptId (tamer.c:1249); null when there is none (garbage in the C).
func entity_from_script_id(script_id: int) -> Node3D:
	var index := script_id_to_entity_id(script_id)
	return entity(index) if index != NONE else null


# --- the map's slots (overworld.c:1026-1222) ------------------------------------------------------

func _empty_slot() -> Dictionary:
	return {
		"type": -1, "follow_mode": 0, "position": [0, 0, 0], "rotation": [0, 0, 0], "tracking_range": 0,
		"script_id": -1, "autotalk": 0, "current_hp": 0, "record": {},
		"ai_sections": [-1, -1, -1, -1, -1, -1, -1, -1], "waypoints": [], "active_section": 0,
		"animation": 0, "stop_anim": 0, "look_at_tamer_state": 0, "has_waypoint_target": 0,
		"waypoint_wait_timer": 0, "target_angle": 0, "cc_diff": 0, "cw_diff": 0,
	}


## clearMapDigimon (overworld.c:1156): every slot empty, no NPC entity, NPC_ACTIVE_ANIM 0.
func clear_map_digimon() -> void:
	for i in NPC_SLOTS:
		slots[i] = _empty_slot()
		npcs[i] = null
		active_anim[i] = 0


## loadMapDigimon (overworld.c:1026): the map's entity list into the slots, only for maps with the
## flag 0x80 (has_digimon). `list` is the asset porter's map.json "digimon".
func load_map_digimon(list: Array, has_digimon: bool) -> void:
	if not has_digimon:
		return
	for i in mini(list.size(), NPC_SLOTS):
		var d: Dictionary = list[i]
		var s: Dictionary = slots[i]
		s["type"] = int(d["type"])
		s["follow_mode"] = int(d["follow_mode"])
		s["position"] = _ints(d["position"])
		s["rotation"] = _ints(d["rotation"])
		s["tracking_range"] = int(d["tracking_range"])
		s["script_id"] = int(d["script_id"])
		s["current_hp"] = int(d["current_hp"])
		s["record"] = d
		s["animation"] = 0
		var sections := _ints(d["ai_sections"])
		while sections.size() < 8:
			sections.append(-1)
		s["ai_sections"] = sections
		var points := []
		for p in d["waypoints"]:
			points.append(_ints(p))
		s["waypoints"] = points
		s["active_section"] = 0


## The C's int16 values (JSON numbers come as floats).
static func _ints(values: Array) -> Array:
	var out := []
	for v in values:
		out.append(int(v))
	return out


## removeMapEntities (overworld.c:1181): the NPC entities go, every model is unloaded, the AI state
## cleared.
func remove_map_entities() -> void:
	for i in NPC_SLOTS:
		if npcs[i] != null:
			_remove_npc(i)
	loaded_models.fill(-1)
	clear_map_ai_table(-1)


## clearMapAITable (overworld.c:1207): one slot or (-1) all.
func clear_map_ai_table(index: int) -> void:
	for i in NPC_SLOTS:
		if index == -1 or index == i:
			slots[i]["look_at_tamer_state"] = 0
			slots[i]["has_waypoint_target"] = 0
			slots[i]["active_section"] = 0


## scriptLoadModel (script_interp.c:2561): the first free model slot; none free: nothing.
func load_model(type: int) -> void:
	var i := loaded_models.find(-1)
	if i >= 0:
		loaded_models[i] = type


## scriptUnloadModel (script_interp.c:2645): the first slot with that type is freed.
func unload_model(type: int) -> void:
	var i := loaded_models.find(type)
	if i >= 0:
		loaded_models[i] = -1


## scriptSetDigimon (overworld.c:1093): the slot's NPC appears if `type` is the map's type for it.
func set_digimon(type: int, slot: int, autotalk: int) -> bool:
	if slot < 0 or slot >= NPC_SLOTS or type != int(slots[slot]["type"]):
		return false
	if npcs[slot] != null:
		_remove_npc(slot)
	var npc: Node3D = npc_factory.call(slot) if npc_factory.is_valid() else null
	if npc == null:
		return false
	npcs[slot] = npc
	var s: Dictionary = slots[slot]
	npc.place(s["position"], int(s["rotation"][1]))
	npc.start_animation(int(s["animation"]))
	s["autotalk"] = autotalk
	walking_towards[slot] = 0
	npc.on_map = true
	npc.update_on_screen()
	return true


## scriptUnloadEntity (overworld.c:1142): the entity of that script id leaves (its slot data
## stays for a later SET_DIGIMON). False when there is none.
func unload_entity(script_id: int) -> bool:
	var index := script_id_to_entity_id(script_id)
	if index == NONE:
		return false
	var e := entity(index)
	e.on_map = false
	if index >= 2:
		_remove_npc(index - 2)
	return true


func _remove_npc(slot: int) -> void:
	var npc: Node = npcs[slot]
	npcs[slot] = null
	if is_instance_valid(npc):
		if npc.is_inside_tree():
			npc.queue_free()
		else:
			npc.free()


## setMovementEnabled's NPC part (overworld.c:1887, :1900): stopAnim, and the AI state cleared
## when the script takes the NPC. `slot` -1: all.
func set_stop_anim(slot: int, enabled: bool) -> void:
	for i in NPC_SLOTS:
		if slot == -1 or slot == i:
			slots[i]["stop_anim"] = 1 if enabled else 0
			if enabled:
				clear_map_ai_table(slot)


## The first NPC entity with that script id (scriptNPCStartAnimation's search), or -1.
func npc_slot_for_script_id(script_id: int) -> int:
	for i in NPC_SLOTS:
		if npcs[i] != null and int(slots[i]["script_id"]) == script_id:
			return i
	return -1


## resetEntityOrigin (overworld.c:1829): the NPC's map position becomes where it stands, its
## waypoints move with it (AI sections not 0, up to the first -1).
func reset_entity_origin(script_id: int) -> void:
	var slot := npc_slot_for_script_id(script_id)
	if slot < 0:
		return
	var s: Dictionary = slots[slot]
	var npc: Node3D = npcs[slot]
	var x := int(npc.position.x)
	var z := int(-npc.position.z)
	var dx: int = x - int(s["position"][0])
	var dz: int = z - int(s["position"][2])
	s["position"][0] = x
	s["position"][2] = z
	var sections: Array = s["ai_sections"]
	var points: Array = s["waypoints"]
	for j in 8:
		if int(sections[j]) == 0:
			continue
		if int(sections[j]) == -1:
			break
		if j < points.size():
			points[j][0] = int(points[j][0]) + dx
			points[j][2] = int(points[j][2]) + dz


# --- the tamer's entityCheckCollision (map.c:3400, the tamer branch of :3763) -----------------------

## checkMapInteraction's entityCheckCollision(partner, tamer, 0, 0): his next step against the map
## (10) and the entities (the partner is the source); -1 free. `confirm_now`: ✕ newly pressed this
## frame (POLLED_INPUT & ~POLLED_INPUT_PREVIOUS), which reaches 50 further while he stands.
func tamer_collision(confirm_now: bool, standing: bool) -> int:
	if tamer == null:
		return -1
	var vy: int = tamer.direction
	var angle := (vy - 0x800) * PI / 0x800
	var step: float = tamer.step
	var dx := float(int(sin(angle) * step))
	var dz := float(int(cos(angle) * step))
	if vy == 0x400 or vy == 0xC00:
		dz = 0.0
	if vy == 0 or vy == 0x800:
		dx = 0.0
	var x: float = tamer.position.x + dx
	var z: float = -tamer.position.z + dz
	if tamer.field != null and tamer.field.blocked(int(x), int(z), int(signf(dx)), int(signf(dz)), tamer.radius):
		return 10
	var r: int = tamer.radius
	var left := x - r
	var right := x + r
	var near := z - r
	var far := z + r
	if confirm_now and standing:
		if vy > 0 and vy < 0x800:
			left -= 50
		if vy > 0x800 and vy < 0x1000:
			right += 50
		if vy < 0x400 or vy > 0xC00:
			near -= 50
		if vy > 0x400 and vy < 0xC00:
			far += 50
	var t := table()
	for i in ENTITY_COUNT:
		var other: Node3D = t[i]
		if other == null or other == tamer or other == partner or is_invisible(other):
			continue
		var o: int = other.radius
		var ox := other.position.x
		var oz := -other.position.z
		# The 4 edges of his square, then entityIsInEntity: any overlap, edges included.
		if right >= ox - o and left <= ox + o and far >= oz - o and near <= oz + o:
			return i
	return -1
