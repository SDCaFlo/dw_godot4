extends SceneTree
## NPCs (scripts/field/npc.gd, field_entities.gd, the interpreter's entity opcodes) against
## specs/npc.md §2, with MAYO04A's entity list from the asset porter and actors without models:
##   godot --headless --path . -s res://tests/test_npc.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var gs: Node
var interp: ScriptInterpreter
var ctx: ScriptContext
var boxes: UIBoxes
var pad: Pad
var files: ScriptFiles
var map: FieldMap
var ents: FieldEntities
var tamer: Tamer
var partner: Partner
var talks := []


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	var mayo = Content.load_json("maps/MAYO04A/map.json")
	if not data.available() or mayo == null:
		print("SKIP: porter output missing")
		quit(0)
		return false
	_setup()
	_slots(mayo)
	_set_and_unload(mayo)
	_models()
	_collision(mayo)
	_autotalk(mayo)
	_turns(mayo)
	_movement_enabled(mayo)
	_animations()
	_teardown()
	print("%s: NPC checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _setup() -> void:
	gs = load("res://scripts/state/game_state.gd").new()
	gs.data = data
	gs.new_game()
	boxes = UIBoxes.new()
	var area := TextArea.new(data, "en_us")
	ctx = ScriptContext.new()
	ctx.game_state = gs
	ctx.data = data
	pad = Pad.new()
	var tb := TextBoxes.new(boxes, area, ctx, pad, data, gs)
	files = ScriptFiles.new()
	interp = ScriptInterpreter.new(ctx, files, tb)
	interp.game_state = gs
	interp.data = data
	map = FieldMap.new()
	map._collision.resize(100 * 100)
	map._collision.fill(0)
	tamer = Tamer.new()
	tamer.field = map
	partner = Partner.new()
	partner.field = map
	partner.tamer = tamer
	ents = FieldEntities.new()
	ents.tamer = tamer
	ents.partner = partner
	ents.npc_factory = func(slot: int) -> Npc:
		var npc := Npc.new()
		npc.slot = slot
		npc.entities = ents
		npc.field = map
		npc.tamer = tamer
		npc.talk = func(n: Npc): talks.append(n.script_id())
		return npc
	partner.entities = ents
	interp.tamer = tamer
	interp.partner = partner
	interp.entities = ents


func _teardown() -> void:
	ents.remove_map_entities()
	ents.clear_map_digimon()
	tamer.free()
	partner.free()
	map.free()
	boxes.free()
	gs.free()
	data.free()


## A synthetic script: section `id` at the code, loaded as script 500; `is_event` like a talk.
func _run(code: Array, frames := 1, id := 1, is_event := 0) -> void:
	var bytes := PackedByteArray([8, 0, id & 0xFF, id >> 8, 8, 0, 0xFF, 0xFF])
	bytes.append_array(PackedByteArray(code))
	files._cache[500] = bytes
	interp.call_section(500, id, is_event)
	for i in frames:
		_frame()


func _frame(buttons := 0) -> void:
	pad.poll(buttons)
	pad.process()
	interp.tick_script()
	boxes.step()


func _load(mayo: Dictionary) -> void:
	ents.remove_map_entities()
	ents.clear_map_digimon()
	ents.load_map_digimon(mayo["digimon"], bool(mayo["map_entry"]["has_digimon"]))


## clearMapDigimon + loadMapDigimon (overworld.c:1156, :1026).
func _slots(mayo: Dictionary) -> void:
	_load(mayo)
	var types := []
	var ids := []
	for s in ents.slots:
		types.append(int(s["type"]))
		ids.append(int(s["script_id"]))
	_eq([types, ids], [[162, 86, 86, 80, 80, -1, -1, -1], [5, 6, 7, 8, 9, -1, -1, -1]],
			"MAYO04A's list fills slots 0-4 (Etemon, 2 Aruraumon, 2 Goburimon; script ids 5-9)")
	_eq([ents.slots[2]["waypoints"].size(), ents.slots[2]["ai_sections"]], [2, [1, 1, -1, -1, -1, -1, -1, -1]],
			"the slot keeps the AI data (waypoints, AI sections) for step 3b")
	ents.load_map_digimon([], false)
	ents.clear_map_digimon()
	ents.load_map_digimon(mayo["digimon"], false)
	_eq(int(ents.slots[0]["type"]), -1, "a map without the flag 0x80 loads no Digimon")


## SET_DIGIMON / UNLOAD_ENTITY (overworld.c:1093, :1142).
func _set_and_unload(mayo: Dictionary) -> void:
	_load(mayo)
	# SET_DIGIMON type 80 (Goburimon), slot 0 (Etemon's): the wrong type does nothing.
	_run([0x47, 80, 0, 1, 0xFE, 0])
	_eq(ents.npcs[0], null, "SET_DIGIMON with another type than the slot's: nothing appears")
	# SET_DIGIMON 162, 0, autotalk 1: placed at the map position and rotation.
	_run([0x47, 162, 0, 1, 0xFE, 0])
	var npc: Npc = ents.npcs[0]
	_eq([npc != null, Vector3i(npc.position) if npc else null, npc.direction if npc else null, npc.autotalk() if npc else null, npc.on_map if npc else null],
			[true, Vector3i(296, 1000, -1865), 512, 1, true], "SET_DIGIMON places the slot's NPC (position, rotation, autotalk)")
	_run([0x47, 162, 0, 0, 0xFE, 0])
	_eq([ents.npcs[0] != npc, ents.npcs[0].autotalk()], [true, 0], "SET_DIGIMON again replaces the entity")
	_eq([ents.script_id_to_entity_id(0xFD), ents.script_id_to_entity_id(0xFC), ents.script_id_to_entity_id(5),
			ents.script_id_to_entity_id(9)], [0, 1, 2, 0xFF], "scriptIdToEntityId: tamer, partner, NPC on the map, NPC not placed")
	# UNLOAD_ENTITY 5: gone, the slot data stays; SET_DIGIMON brings it back.
	_run([0x48, 5, 0xFE, 0])
	_eq([ents.npcs[0], ents.script_id_to_entity_id(5), int(ents.slots[0]["type"])], [null, 0xFF, 162], "UNLOAD_ENTITY removes the entity, not the slot")
	_run([0x47, 162, 0, 1, 0xFE, 0])
	_eq(ents.npcs[0] != null, true, "then SET_DIGIMON places it again")


## LOAD_DIGIMON / UNLOAD_DIGIMON (script_interp.c:2561, :2645).
func _models() -> void:
	ents.loaded_models.fill(-1)
	var code := []
	for t in 9:
		code.append_array([0x46, 10 + t])
	code.append_array([0xFE, 0])
	_run(code)
	_eq(ents.loaded_models, [10, 11, 12, 13, 14, 15, 16, 17], "8 model slots: a 9th LOAD_DIGIMON does nothing")
	_run([0x79, 12, 0xFE, 0])
	_eq(ents.loaded_models[2], -1, "UNLOAD_DIGIMON frees the type's slot")


## entityCheckCollision for the tamer (map.c:3400, :3763) and the NPCs.
func _collision(mayo: Dictionary) -> void:
	_load(mayo)
	ents.set_digimon(86, 1, 0)
	var npc: Npc = ents.npcs[1]
	npc.radius = 100
	tamer.radius = 100
	# The NPC at (275, 1755); the tamer 201 units to its left, facing +x (0xC00), standing.
	tamer.position = Vector3(275 - 201, 0, -1755)
	tamer._set_direction(0xC00)
	tamer.step = 0.0
	_eq(ents.tamer_collision(false, true), -1, "1 unit apart: free")
	_eq(ents.tamer_collision(true, true), 3, "✕ newly pressed while standing reaches 50 further: the NPC (entity 3)")
	_eq(ents.tamer_collision(true, false), -1, "no reach while walking")
	tamer.position.x = 275 - 200
	_eq(ents.tamer_collision(false, true), 3, "touching squares collide (edges included)")
	tamer.position.x = 275 - 251
	_eq(ents.tamer_collision(true, true), -1, "51 apart: out of the reach")
	tamer.position.x = 275 - 210
	tamer.step = 15.0
	_eq(ents.tamer_collision(false, false), 3, "his next step (the frame's forward motion) runs into it")
	npc.on_screen = false
	_eq(ents.tamer_collision(false, false), -1, "an NPC off screen doesn't collide (isInvisible)")
	npc.on_screen = true
	tamer.step = 0.0
	# The partner probes NPCs too (entities 2-9), and turns along them.
	partner.radius = 120
	partner.position = Vector3(275, 0, -(1755 - 221))
	partner._set_direction(0x800)
	partner.step = 10.0
	_eq(partner.probe(partner.direction), 3, "the partner's step into an NPC: entity 3")
	partner.step = 0.0


## NPCEntityTickOverworld's collision and autotalk (overworld.c:1306-1343).
func _autotalk(mayo: Dictionary) -> void:
	_load(mayo)
	ents.set_digimon(86, 1, 1)
	var npc: Npc = ents.npcs[1]
	npc.radius = 100
	tamer.radius = 100
	tamer.state = Tamer.STATE_FREE
	tamer.position = Vector3(275 - 205, 0, -1755)
	npc._set_direction(0x400)
	npc.step = 0.0
	talks.clear()
	npc.tick()
	_eq([talks, ents.collision_state[1]], [[], -1], "a standing NPC never probes the tamer (its step is 0)")
	npc.step = 10.0
	npc.tick()
	_eq([talks, npc.step_blocked, ents.collision_state[1]], [[6], true, 0], "walking into the free tamer with autotalk 1: its section, its step held")
	talks.clear()
	tamer.state = Tamer.STATE_STILL
	npc.step = 10.0
	npc.tick()
	_eq(talks, [], "not while the tamer isn't free")
	tamer.state = Tamer.STATE_FREE
	ents.slots[1]["autotalk"] = 0
	npc.step = 10.0
	npc.tick()
	_eq(talks, [], "autotalk 0: only the tamer's ✕ talks (US)")
	ents.active_anim[1] = 4
	ents.collision_state[1] = -1
	npc.step = 10.0
	npc.tick()
	_eq(ents.collision_state[1], -1, "NPC_ACTIVE_ANIM set: only the animation ticks")
	ents.active_anim[1] = 0


## The turn to each other at a talk and ENTITY_LOOK_AT_ENTITY / SET_ROTATION (tamer.c:1058, :1105).
func _turns(mayo: Dictionary) -> void:
	var steps := []
	var vy := 0
	for i in 3:
		var r := ScriptInterpreter.rotate_entity(vy, 100, 0, 0x200)
		steps.append(r)
		vy = r[0]
	_eq(steps, [[0xE00, false], [0xC00, false], [0xC00, true]], "rotateEntity: 0x200 per frame the short way (0 -> 0xC00 over 0xE00), done on the angle")
	_eq(ScriptInterpreter.rotate_entity(0x100, 0, 100, 0x200), [0x800 - 0x800 + 0x300, false],
			"rotateEntity from 0x100 towards 0x800: +0x200")
	_load(mayo)
	ents.set_digimon(162, 0, 0)
	var npc: Npc = ents.npcs[0]
	tamer.position = Vector3(296 - 300, 0, -1865)
	tamer._set_direction(0x800)
	npc._set_direction(0)
	# An NPC talk: section 5 (Etemon's script id) as an event; DELAY 30 keeps it running.
	_run([0x1B, 5, 0x67, 0, 30, 0, 0xFE, 0], 1, 5, 1)
	_eq([interp.movement[0], interp.movement[2]], [ScriptInterpreter.MOVE_LOOK_AT, ScriptInterpreter.MOVE_LOOK_AT],
			"a talk's scriptPauseGame: the tamer and the NPC get turn slots towards each other")
	for i in 6:
		_frame()
	_eq([tamer.direction, npc.direction, interp.movement[0], interp.movement[2]], [0xC00, 0x400, 0xFF, 0xFF],
			"they face each other (tamer +x 0xC00, the NPC -x 0x400), the slots free")
	_force_end()
	gs.set_trigger(ScriptInterpreter.TRIGGER_NO_TURN)
	_run([0x1B, 5, 0x67, 0, 30, 0, 0xFE, 0], 1, 5, 1)
	_eq([interp.movement[0], gs.is_trigger_set(ScriptInterpreter.TRIGGER_NO_TURN)], [0xFF, false], "trigger 44 skips the turn and is cleared")
	_force_end()
	# ENTITY_SET_ROTATION 5, 0x200: done in one frame (then animation 0).
	_run([0x4D, 5, 0, 2, 0x67, 0, 30, 0, 0xFE, 0], 2)
	_eq(npc.direction, 0x200, "ENTITY_SET_ROTATION turns the NPC at once")
	_force_end()
	# ENTITY_WALK_TO on an NPC: slot 2, NPC_IS_WALKING_TOWARDS while it walks.
	_run([0x4E, 5, 0xE8, 0x03, 0, 0, 0, 0, 0x67, 0, 30, 0, 0xFE, 0], 2)
	_eq([interp.movement[2], ents.walking_towards[0]], [ScriptInterpreter.MOVE_WALK_TO, 1], "ENTITY_WALK_TO on an NPC: slot 2, walking towards")
	npc.position = Vector3(1000, 0, 0)
	_frame()
	_eq([interp.movement[2], ents.walking_towards[0]], [0xFF, 0], "on the point's tile it is done")
	_force_end()
	# RESET_ENTITY_ORIGIN: the map position becomes where it stands.
	_run([0x54, 5, 0xFE, 0])
	_eq([ents.slots[0]["position"][0], ents.slots[0]["position"][2]], [1000, 0], "RESET_ENTITY_ORIGIN keeps where the NPC stands")


## setMovementEnabled for the NPCs (overworld.c:1869).
func _movement_enabled(mayo: Dictionary) -> void:
	_load(mayo)
	ents.set_digimon(162, 0, 0)
	ents.set_digimon(86, 1, 0)
	ents.slots[0]["look_at_tamer_state"] = 2
	# SET_DIALOG_OWNER 5: scriptPauseGame(5) takes that NPC (stopAnim, AI state cleared).
	_run([0x1B, 5, 0x67, 0, 30, 0, 0xFE, 0])
	_eq([ents.slots[0]["stop_anim"], ents.slots[0]["look_at_tamer_state"], ents.slots[1]["stop_anim"]], [1, 0, 0],
			"the speaking NPC stops, its AI state cleared; the others keep their frame")
	for i in 32:
		_frame()
	_eq([ctx.is_paused, ents.slots[0]["stop_anim"]], [true, 0], "the end of the script frees every NPC")


## PLAY_ANIMATION (script_interp.c:1526) and the setActiveAnim(0xC) quirk (specs/npc.md §2.6).
func _animations() -> void:
	var list := []
	for i in 8:
		list.append({"type": 80, "follow_mode": 1, "position": [i * 300, 0, 0], "rotation": [0, 0, 0],
				"tracking_range": 0, "script_id": 5 + i, "current_hp": 100, "ai_sections": [0], "waypoints": [[0, 0, 0]]})
	ents.remove_map_entities()
	ents.clear_map_digimon()
	ents.load_map_digimon(list, true)
	ents.set_digimon(80, 0, 0)
	ents.set_digimon(80, 7, 0)
	# PLAY_ANIMATION on NPC 5 (on the map): it plays; the slot-7 NPC (script id 12) unchanged.
	_run([0x56, 0, 5, 9, 0xFE, 0])
	_eq([ents.active_anim[0], ents.active_anim[7]], [0, 0], "PLAY_ANIMATION on an NPC: NPC_ACTIVE_ANIM isn't set for it (the C's bug); slot 7 left unchanged (§6)")
	# PLAY_ANIMATION on script id 30 (no such NPC): the leftover animation id goes to slot 7.
	_run([0x56, 0, 30, 9, 0xFE, 0])
	_eq(ents.active_anim[7], 9, "no NPC of that id: the slot-7 NPC (script id 12) gets NPC_ACTIVE_ANIM = the animation")
	ents.active_anim[7] = 0
	# The tamer and the partner: their script states.
	_run([0x56, 0, 0xFD, 8, 0x56, 0, 0xFC, 6, 0x67, 0, 30, 0, 0xFE, 0])
	_eq([tamer.state, tamer._script_animation, partner.state], [Tamer.STATE_SCRIPT, 8, Partner.STATE_SCRIPT],
			"PLAY_ANIMATION: the tamer's state 10 with the animation, the partner's state 12")
	_force_end()


func _force_end() -> void:
	ctx.is_paused = true
	ctx.map_change = 0
	ctx.stack.clear()
	interp.textboxes.close_all_textboxes()
	for i in UIBoxes.COUNT:
		if boxes.boxes[i].registered:
			boxes.remove_static(i)
	interp.set_movement_enabled(-1, false)


func _eq(got, expected, what: String) -> void:
	_checks += 1
	if str(got) != str(expected):
		_failed += 1
		push_error("FAIL %s: got %s, expected %s" % [what, got, expected])
