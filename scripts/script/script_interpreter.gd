class_name ScriptInterpreter
extends RefCounted
## The event-script interpreter (script_interp.c, script_value.c; specs/script.md): sections start
## with call_section (callScriptSection), and tick_script (tickScript) runs once per game frame
## before the objects: the text boxes' frame, the waiting instruction, then instructions until one
## waits or the script ends.
##
## Each opcode reads its arguments exactly as the C does. Opcodes whose system isn't ported yet
## read their bytes, do what can be done without that system (scriptPauseGame, ...), and are
## reported once through `unported`; their waits finish at once (specs/script.md §3).

## An opcode (or builtin routine) the port can't execute yet; reported once per name.
signal unported(op: int, name: String)
## The script has ended (IS_SCRIPT_PAUSED set and cleaned up).
signal ended
## Routine 0x35's wait saw the ending's sync bit (case 53, script_interp.c:516-520): MAIN_STATE = 3, the
## game loop ends after this frame (main.c:3522: cleanupGame, the credits, the title).
signal game_ended

## The longjmp codes of the instruction handlers (tickScript, script_interp.c:600-632).
const NEXT := 1
const STOP := 2
const MAP_CHANGE := 3

## StackEntry.smth[0] (returnFromScriptFile).
const LINK := 1
const MAP_SETUP := 3
const AFTER_MAP_CHANGE := 4
## SCRIPT_STATE.stack[8].
const STACK_SIZE := 8
const MAP_ENTRY_SECTION := 0xFE
## The 22 SCRIPT_MOVEMENT slots; 0xFF = free.
const MOVEMENT_SLOTS := 0x16
const FREE := 0xFF
## Movement slot types (tickScriptedMovement, specs/script.md §2.7): 0 turn to an entity
## (ENTITY_LOOK_AT_ENTITY, a talk's turn), 1 set the rotation (ENTITY_SET_ROTATION), 2-5 walk to a
## point or an entity, without or with the camera, 6-7 the camera slot's pans to a point or an
## entity, 8-11 moves (slides) to a point or an entity, 12 a door's move (slot 11), 13 a map
## sprite's move (slots 12-21; specs/map_objects.md), 14-15 moves on one axis.
const MOVE_LOOK_AT := 0
const MOVE_SET_ROTATION := 1
const MOVE_WALK_TO := 2
const MOVE_WALK_TO_ENTITY := 3
const MOVE_WALK_TO_WITH_CAMERA := 4
const MOVE_WALK_TO_ENTITY_WITH_CAMERA := 5
const MOVE_CAMERA_TO := 6
const MOVE_CAMERA_TO_ENTITY := 7
const MOVE_TO := 8
const MOVE_TO_ENTITY := 9
const MOVE_TO_WITH_CAMERA := 10
const MOVE_TO_ENTITY_WITH_CAMERA := 11
const MOVE_ROTATE_DOOR := 12
const MOVE_OBJECT_TO := 13
const MOVE_TO_AXIS := 14
const MOVE_TO_AXIS_WITH_CAMERA := 15
## The camera's movement slot (WAIT_FOR_ENTITY 0xC8).
const CAMERA_SLOT := 10
## ROTATE_3D_OBJECT's slot, and MOVE_OBJECT_TO's first (its slot argument adds to it).
const DOOR_SLOT := 11
const OBJECT_SLOT := 12
## entityCheckCollision results that end a walk to an entity: entities 0-8 (col < 9).
const WALK_HIT_LIMIT := 9
## CALL_DIGIMON_ROUTINE 0: the toilet scene (partner state 6).
const ROUTINE_TOILET := 0
## CALL_DIGIMON_ROUTINE 2 and 10: an evolution (partner state 13) into script value 5 (Sukamon's
## saved Digimon) or 0xFE (specs/evolution.md §2.6).
const ROUTINE_EVOLVE_BACK := 2
## CALL_DIGIMON_ROUTINE 3 / 4 / 7 / 9: the death and lives scenes (specs/death_reincarnation.md §2).
const ROUTINE_DYING := 3
const ROUTINE_REBIRTH := 4
const ROUTINE_COLLAPSE := 7
const ROUTINE_BATTLE_LOSS := 9
## CALL_DIGIMON_ROUTINE 5 / 6: the opening (tamer state 15) and the ending (16), partner state 11
## (partner.c:1166-1175).
const ROUTINE_OPENING := 5
const ROUTINE_ENDING := 6
## CALL_ROUTINE 0x35's wait (case 53).
const ROUTINE_START_ENDING := 0x35
## CALL_DIGIMON_ROUTINE 8: Machinedramon's spawn (tamer state 18, partner state 11; partner.c:1189).
const ROUTINE_MACHINEDRAMON := 8
## CALL_ROUTINE 0x28: EAB_startBuildup on the entity of script id 5 (script_interp.c:1855).
const BUILDUP_SCRIPT_ID := 5
const ROUTINE_EVOLVE := 10
## CALL_DIGIMON_ROUTINE 1: curling (KAR_start, tamer state 12, partner state 11; partner.c:1146).
const ROUTINE_CURLING := 1
const PSTAT_SUKAMON_BACKUP := 5
const PSTAT_EVOLUTION := 0xFE
## callDigimonRoutine's last case (partner.c:1139-1213).
const ROUTINE_LAST := 10
## tickLookAtEntity's turn per frame (rotateEntity speed).
const LOOK_AT_SPEED := 0x200
## setTrigger(0x2C) skips scriptPauseGame's turn to each other (TRIGGER_44 in trigger.h).
const TRIGGER_NO_TURN := 0x2C
const MONEY_MAX := 999999
const MERIT_MAX := 9999
const OP_WAIT_FOR_ENTITY := 0x4A
const OP_START_BATTLE := 0x66
## START_BATTLE: the predefined battle's flag and enemies (script values 0xFA, 0xFB-0xFD), the
## outcome (0xFF), the battle-loss section of script 0, the won battle's camera pan back (slot 10).
const PSTAT_PREDEFINED := 0xFA
const PSTAT_OUTCOME := 0xFF
const SECTION_BATTLE_LOST := 0x4DE
const BATTLE_CAMERA_SLOT := 10
const COUNTER_MAX := 0x270F
const OP_ENTITY_WALK_TO := 0x4E
## A frame that runs this many instructions is a loop the original would hang in.
const MAX_PER_FRAME := 20000

## SCRIPT_OP_* names (include/dw/script.h:21-125).
const NAMES := {
	0x10: "SET_SELECTION", 0x11: "UNUSED_11", 0x12: "UNUSED_12", 0x13: "JUMP_AND_LINK", 0x14: "JUMP_TO_FILE_AND_LINK",
	0x15: "JUMP_RETURN", 0x16: "JUMP_TO", 0x17: "JUMP_TO_FILE", 0x18: "SWITCH", 0x19: "IF", 0x1A: "SHOW_TEXTBOX",
	0x1B: "SET_DIALOG_OWNER", 0x1C: "SET_TRIGGER", 0x1D: "UNSET_TRIGGER", 0x1E: "SET_PSTAT", 0x1F: "ADD_TO_PSTAT",
	0x20: "REDUCE_PSTAT", 0x21: "STORE_MAP_ID", 0x22: "STORE_DIGIMON_TYPE", 0x23: "SET_INVENTORY_SIZE",
	0x24: "STORE_RANDOM", 0x25: "STORE_DATE", 0x26: "SET_TEXTBOX_SIZE", 0x27: "FADEOUT_HUD", 0x28: "GIVE_ITEM",
	0x29: "REMOVE_ITEM", 0x2A: "ADD_MONEY", 0x2B: "REDUCE_MONEY", 0x2C: "COMPARE_DATE", 0x2D: "LEARN_MOVE",
	0x2E: "UNUSED_2E", 0x2F: "GIVE_CARD", 0x30: "TAKE_CARD", 0x31: "SET_MERIT", 0x32: "ADD_MERIT", 0x33: "REDUCE_MERIT",
	0x34: "SET_STAT", 0x35: "ADD_STAT", 0x36: "REDUCE_STAT", 0x37: "ADVANCE_TO_DATE_AT", 0x38: "ADD_MINUTES_TO_DATE_AT",
	0x39: "ADD_MINUTES_TO_DATE_AT_2", 0x3A: "UNUSED_3A", 0x3B: "UNUSED_3B", 0x3C: "UNUSED_3C", 0x3D: "UNUSED_3D",
	0x3E: "UNUSED_3E", 0x3F: "STORE_DIGIMON_VALUE", 0x46: "LOAD_DIGIMON", 0x47: "SET_DIGIMON", 0x48: "UNLOAD_ENTITY",
	0x49: "CALL_DIGIMON_ROUTINE", 0x4A: "WAIT_FOR_ENTITY", 0x4B: "WARP_TO", 0x4C: "ENTITY_LOOK_AT_ENTITY",
	0x4D: "ENTITY_SET_ROTATION", 0x4E: "ENTITY_WALK_TO", 0x4F: "MOVE_CAMERA_TO", 0x50: "MOVE_CAMERA_TO_ENTITY",
	0x51: "ENTITY_WALK_TO_ENTITY", 0x52: "ENTITY_WALK_TO_WITH_CAMERA", 0x53: "ENTITY_WALK_TO_ENTITY_WITH_CAMERA",
	0x54: "RESET_ENTITY_ORIGIN", 0x55: "SET_TEXTBOX_ORIGIN", 0x56: "PLAY_ANIMATION", 0x57: "SET_OBJ_VISIBILITY",
	0x58: "TELEPORT", 0x5A: "PLAY_SOUND", 0x5B: "UNUSED_5B", 0x5C: "UNUSED_5C", 0x5D: "SET_BGM", 0x5E: "STOP_BGM",
	0x5F: "UNUSED_5F", 0x64: "CALL_ROUTINE", 0x65: "REMOVE_CONDITION", 0x66: "START_BATTLE", 0x67: "DELAY",
	0x68: "SET_TEXTBOX_MODE", 0x69: "DEAL_DAMAGE", 0x6A: "SET_AUTOTALK", 0x6B: "DATA", 0x6C: "ENTITY_MOVE_TO",
	0x6D: "ENTITY_MOVE_TO_ENTITY", 0x6E: "ENTITY_MOVE_TO_WITH_CAMERA", 0x6F: "ENTITY_MOVE_TO_ENTITY_WITH_CAMERA",
	0x70: "ROTATE_3D_OBJECT", 0x71: "MOVE_OBJECT_TO", 0x72: "ENTITY_MOVE_TO_AXIS", 0x73: "ENTITY_MOVE_TO_AXIS_WITH_CAMERA",
	0x74: "SPAWN_ITEM", 0x75: "SPAWN_CHEST", 0x76: "SPAWN_BOULDER", 0x77: "MOVE_BOULDER", 0x78: "DESPAWN_BOULDER",
	0x79: "UNLOAD_DIGIMON", 0x7A: "COPY_PSTAT", 0x7B: "SECTION_ON_EXIT", 0x7C: "SET_RECT_IMPASSABLE",
	0x7D: "SPAWN_SPRITE_AT_LOCATION", 0x7E: "SPAWN_SPRITE_AT_ENTITY", 0xFB: "SET_SCRIPT", 0xFC: "UNUSED_FC",
	0xFD: "UNUSED_FD", 0xFE: "END_SECTION", 0xFF: "END_SCRIPT",
}
## The entity opcodes (specs/npc.md §2.2): ported, but run as unported without an entity table.
const NPC_OPS := [0x46, 0x47, 0x48, 0x4C, 0x4D, 0x54, 0x56, 0x6A, 0x79]
## Opcodes whose system isn't ported (and NPC_OPS without an entity table): [bytes the C reads
## after the opcode, scriptPauseGame first, the handler ends the frame (longjmp 2)].
const UNPORTED := {
	0x46: [1, false, false], 0x47: [3, true, false], 0x48: [1, true, false],
	0x4C: [3, true, false], 0x4D: [3, true, false],
	0x54: [1, true, false], 0x56: [3, false, false], 0x57: [3, false, false], 0x5A: [3, false, false],
	0x5D: [1, false, false], 0x5E: [1, false, false], 0x66: [1, false, false], 0x6A: [3, false, false],
	0x70: [3, true, false], 0x71: [9, true, false],
	0x74: [5, false, false], 0x75: [11, false, false], 0x76: [1, false, false], 0x77: [5, false, true],
	0x78: [1, false, false], 0x79: [1, false, false], 0x7C: [7, false, false], 0x7D: [9, false, false],
	0x7E: [3, false, false],
}
## CALL_ROUTINE builtins whose system isn't ported, and whether the C ends the frame after
## setting them up (script_interp.c:1661-1891). Ported ones are in _call_routine.
const ROUTINE_WAITS := [0x00, 0x01, 0x02, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0E, 0x12, 0x13, 0x14, 0x15, 0x16,
		0x17, 0x18, 0x1D, 0x20, 0x25, 0x2F, 0x30, 0x32, 0x35, 0x36, 0x37]

var ctx: ScriptContext
## The builtin routines ported as nodes (shops, menus, ...; specs/shops.md §3); null: none.
var routines: ScriptRoutines
var files: ScriptFiles
var textboxes: TextBoxes
var game_state: Node
var data: Node
var clock: Clock
var care: Care
var tamer: Tamer
var partner: Partner
## The camera (specs/camera.md): the camera slot's pans and the "with camera" moves; null: the pans
## end at once, the moves move no camera.
var field: FieldMap
## POLLED_INPUT for moveCameraByDiff's updateDrawingOffsets.
var pad: Pad
## The sound (SoundSystem, the "Sound" autoload; specs/sound.md): PLAY_SOUND, SET_BGM, STOP_BGM.
## Without it those opcodes are skipped and reported, as before the sound was ported.
var sound: Node
## The items on the ground and the chests (specs/map_items.md): SPAWN_ITEM, SPAWN_CHEST. Without
## them those opcodes are skipped and reported.
var map_items: MapItems
var map_chests: MapChests
## The map props (specs/map_events.md §4.1.2): dirt cart, dirt pile, boulder, boxes, gearbox, pedestal.
## Without them the routines and opcodes stay unported.
var map_props: MapProps
## The screen fade (specs/map_events.md §4.2.2): fadeToWhite, fadeFromWhite.
var fade: Fade
## The screen effects (specs/map_events.md §4.2.2): shake, ninjamon, mood bubble.
var map_effects: MapEffects
## Machinedramon's build-up and spawn (EabHost); null: routines 0x33 / 0x28 and digimon routine 8 unported.
var eab: EabHost
## The ending (EndingHost); null: routines 0x34 / 0x35 and digimon routines 5 / 6 unported.
var ending: EndingHost
## Curling (CurlingHost); null: digimon routine 1 unported.
var curling: CurlingHost
## A waiting builtin's tick ended the frame (longjmp 2).
var _wait_ended_frame := false
## The field's battles (BattleHost, specs/battle.md §5.3): start_battle(talked_entity),
## battle_done() and battle_outcome(). Without it START_BATTLE is skipped and reported.
var battles: Object
## The entity table (the NPCs, specs/npc.md); null: only the tamer and the partner.
var entities: FieldEntities
## Field hooks for the map change (step 2): func(map, exit, show_name) -> bool done, called every
## frame of scriptTickChangeMap; SET_SCRIPT's loadMap(map); returnFromScriptFile's setupMap().
var tick_map_change := Callable()
var load_map := Callable()
var setup_map := Callable()
## SCRIPT_MOVEMENT[22]: type per slot (FREE = 0xFF), and the slot's fields (id, target, x, z,
## speed): an opcode sets some of them, the others keep what the slot had (the C's struct).
var movement: Array = []
var movement_args: Array = []
## PREVIOUS_CAMERA_POS, PREVIOUS_CAMERA_POS_INITIALIZED and MOVE_TO_DELTA_X / Z: one set for every
## slot (specs/script.md §2.7, kept): the walks with the camera, the moves' "started" and delta.
var _previous_camera_pos := Vector3.ZERO
var _previous_camera_pos_initialized := false
var _move_to_delta := Vector2i.ZERO
## A ported scene (CALL_DIGIMON_ROUTINE 0) cleared the sync bit and will set it again; any other
## clear is a scene not ported yet, whose waits end at once.
var _sync_scene := false
## tickLookAtEntity's HAS_ROTATION_DATA / ROTATION_DATA per entity (0-9): the target point taken
## on the first frame of a turn.
var _has_rotation_data: Array = []
var _rotation_data: Array = []

var _reported := {}
## SCRIPT_MAP_CHANGE_SHOW_NAME.
var _show_map_name := 1


func _init(script_ctx: ScriptContext, script_files: ScriptFiles, text_boxes: TextBoxes) -> void:
	ctx = script_ctx
	files = script_files
	textboxes = text_boxes
	if textboxes != null and textboxes.files == null:
		textboxes.files = files
	ctx.pause_game = pause_game
	ctx.is_paused = true
	movement.resize(MOVEMENT_SLOTS)
	movement.fill(FREE)
	movement_args.resize(MOVEMENT_SLOTS)
	movement_args.fill({})
	_has_rotation_data.resize(10)
	_has_rotation_data.fill(false)
	_rotation_data.resize(10)
	_rotation_data.fill(Vector2i.ZERO)


# --- starting a section (script_interp.c:2235-2273) --------------------------------------------------

## getScript(id): the script becomes the loaded one (MAPHEAD stays separate).
func load_script(id: int) -> PackedByteArray:
	if id != ScriptFiles.MAPHEAD:
		ctx.active_script_id = id
	return files.script(id)


## callScriptSection(script, section, isEvent). Returns false if the section doesn't exist (the C
## would run from a NULL pointer).
func call_section(script_id: int, section: int, is_event := 0) -> bool:
	ctx.code = load_script(script_id)
	ctx.code_id = script_id
	var at := ScriptFiles.section(ctx.code, section)
	ctx.section_is_event = is_event
	ctx.section = section
	ctx.textbox_close_mode = 0
	ctx.dialogue_owner = ScriptContext.OWNER_TAMER
	ctx.saved_pstat0 = ctx.read_pstat(0)
	ctx.active_instruction = 0
	ctx.map_change = 0
	ctx.map_setup_pending = 0
	ctx.took_over = 0
	ctx.is_paused = false
	ctx.sync_bit = 1
	_sync_scene = false
	movement.fill(FREE)
	textboxes.initialize_textbox()
	if at < 0:
		push_warning("ScriptInterpreter: script %d has no section 0x%X" % [script_id, section])
		ctx.is_paused = true
		return false
	ctx.pointer = at
	return true


## runMapHeadScript (script_interp.c:2235): the map's MAPHEAD section, and one tickScript at once.
func run_map_head(map_id: int) -> void:
	if call_section(ScriptFiles.MAPHEAD, map_id, 1):
		tick_script()


# --- one frame (script_interp.c:390) -------------------------------------------------------------------

## tickScript. Returns IS_SCRIPT_PAUSED.
func tick_script() -> bool:
	if ctx.is_paused:
		return true
	textboxes.tick_textbox_handling()
	_tick_scripted_movements()
	if ctx.map_change == 0x4B:
		var done := true
		if tick_map_change.is_valid():
			done = tick_map_change.call(ctx.script_param_1, ctx.state_2, _show_map_name)
		if done:
			ctx.took_over = 0
			pause_game(0xFF)
			ctx.map_change = 0
	_tick_waiting_instruction()
	if _wait_ended_frame:
		_wait_ended_frame = false
		return ctx.is_paused
	if ctx.map_change != 0 or ctx.active_instruction != 0:
		return ctx.is_paused
	var count := 0
	while true:
		var op := ctx.next_byte()
		var result := execute(op)
		count += 1
		if result == MAP_CHANGE:
			textboxes.close_all_textboxes()
			game_state.set_script_value(0, ctx.saved_pstat0)
			if not tick_map_change.is_valid():
				# The field's map change comes with step 2: the script can't go on on this map.
				_report(op, "map change (%s)" % NAMES.get(op, "?"))
				ctx.stack.clear()
				ctx.is_paused = true
				break
			ctx.map_change = 0x4B
			return ctx.is_paused
		if result != NEXT:
			break
		if count >= MAX_PER_FRAME:
			push_error("ScriptInterpreter: %d instructions in one frame (script %d, offset %d): a loop" % [count, ctx.code_id, ctx.pointer])
			break
	if ctx.is_paused:
		_end()
	return ctx.is_paused


## The waiting instruction's part of tickScript (script_interp.c:415-591).
func _tick_waiting_instruction() -> void:
	match ctx.active_instruction:
		ScriptContext.OP_DELAY:
			if textboxes.delay_frames == 0:
				ctx.active_instruction = 0
		ScriptContext.OP_CALL_ROUTINE:
			# The ported builtins tick until they end (ACTIVE_INSTRUCTION = 0); the others end at once.
			if routines != null and routines.handles(ctx.script_param_1):
				routines.tick(ctx.script_param_1)
			elif ctx.script_param_1 == 0x32 and map_props != null:
				# case 50 (script_interp.c:506-509)
				if map_props.move_pedestal():
					ctx.active_instruction = 0
			elif ctx.script_param_1 == ROUTINE_START_ENDING and ending != null:
				# case 53 (script_interp.c:516-520): the sync bit ends the game, then the frame.
				if ctx.sync_bit == 1:
					ctx.active_instruction = 0
					_wait_ended_frame = true
					game_ended.emit()
			else:
				ctx.active_instruction = 0
		OP_WAIT_FOR_ENTITY:
			if _wait_done():
				ctx.active_instruction = 0
		OP_START_BATTLE:
			if battles.battle_done():
				ctx.active_instruction = 0
				_after_battle(battles.battle_outcome())


func _wait_done() -> bool:
	var id := ctx.wait_for_entity_id
	if id == 0x19:
		return _sync_bit_set()
	if id == 0x1A:
		return true   # TRN_LOADING_COMPLETE: no training loader yet
	if id == 0xFF:
		return _sync_bit_set() and movement.all(func(t): return t == FREE)
	return id >= MOVEMENT_SLOTS or movement[id] == FREE


## getScriptSyncBit. SOME_SCRIPT_SYNC_BIT is set again by the scene a CALL_DIGIMON_ROUTINE starts
## (partner.c:586, :679, :783, :817; tamer.c:1676, :1692): the toilet (routine 0) is ported; for the
## others the bit is set at once, reported.
func _sync_bit_set() -> bool:
	if ctx.sync_bit == 0 and not _sync_scene and not _death_scene_running():
		_report(OP_WAIT_FOR_ENTITY, "WAIT_FOR_ENTITY on the sync bit (partner / tamer scenes)")
		ctx.sync_bit = 1
	return ctx.sync_bit != 0


## The death scenes set the bit across a map change (the change's callScriptSection set it, and
## script 212's WAIT_FOR_ENTITY 0xD5 clears it again): the tamer in state 17 / 19 (MURD), the
## partner in state 8 / 14 (DOOA) set it when they end (tamer.c:1711, :1744; partner.c:679, :817).
func _death_scene_running() -> bool:
	if tamer != null and (tamer.state == Tamer.STATE_SICKNESS_LOST_LIFE or tamer.state == Tamer.STATE_BATTLE_LOST_LIFE):
		return true
	return partner != null and (partner.state == Partner.STATE_DYING or partner.state == Partner.STATE_REBIRTH)


## tickScriptedMovements / tickScriptedMovement (script_interp.c:2821, :2275): every slot in use.
## The doors and the map sprites (types 12, 13) move through the field; without one they end at
## once, as a slot whose entity is gone.
func _tick_scripted_movements() -> void:
	for slot in MOVEMENT_SLOTS:
		if movement[slot] == FREE:
			continue
		var type: int = movement[slot]
		var actor := _actor(slot)
		var args: Dictionary = movement_args[slot]
		var done := true
		if type == MOVE_CAMERA_TO or type == MOVE_CAMERA_TO_ENTITY:
			done = _tick_camera_slot(type, args)
		elif type == MOVE_ROTATE_DOOR:
			done = field == null or field.tick_rotate_door(int(args["id"]), int(args["target"]))
		elif type == MOVE_OBJECT_TO:
			done = field == null or field.overlays.tick_move_to(int(args["id"]), slot - OBJECT_SLOT,
					int(args["target"]), int(args["x"]), int(args["z"]))
		elif actor != null:
			match type:
				MOVE_LOOK_AT:
					done = tick_look_at_entity(slot, int(args["target"]))
				MOVE_SET_ROTATION:
					actor.set_direction(int(args["angle"]))
				MOVE_WALK_TO, MOVE_WALK_TO_WITH_CAMERA:
					done = _tick_walk_to(slot, actor, FREE, args["x"], args["z"], type == MOVE_WALK_TO_WITH_CAMERA)
				MOVE_WALK_TO_ENTITY, MOVE_WALK_TO_ENTITY_WITH_CAMERA:
					done = _tick_walk_to(slot, actor, int(args.get("target", 0)), 0, 0,
							type == MOVE_WALK_TO_ENTITY_WITH_CAMERA)
				MOVE_TO, MOVE_TO_WITH_CAMERA:
					done = _tick_move_to(actor, FREE, args["x"], args["z"], args["speed"], type == MOVE_TO_WITH_CAMERA)
				MOVE_TO_ENTITY, MOVE_TO_ENTITY_WITH_CAMERA:
					done = _tick_move_to(actor, int(args.get("target", 0)), 0, 0, args["speed"],
							type == MOVE_TO_ENTITY_WITH_CAMERA)
				MOVE_TO_AXIS, MOVE_TO_AXIS_WITH_CAMERA:
					done = _tick_move_to_axis(actor, args["x"], args["target"], args["speed"],
							type == MOVE_TO_AXIS_WITH_CAMERA)
		if done:
			# The walkers go back to animation 0 (startAnimationTamer(0) / partnerStartAnimation(0)
			# / scriptNPCStartAnimation(id, 0)); the moves keep theirs.
			if slot < 10 and type < MOVE_TO and actor != null:
				actor.start_animation(0)
			movement[slot] = FREE


## Sets a slot's type and some of its fields; the others keep their values (the C's struct).
func _set_movement(slot: int, type: int, args: Dictionary) -> void:
	movement[slot] = type
	movement_args[slot] = movement_args[slot].merged(args, true)


## tickEntityWalkTo(id, 0xFF, x, z, 0) (tamer.c:991) as the scenes call it: turn to the point; done
## on its tile. The walk itself is the animation's root motion (the actor's script state checks no
## walls).
static func tick_entity_walk_to(actor: Node3D, x: int, z: int) -> bool:
	var from := FieldMap.model_tile(int(actor.position.x), int(-actor.position.z))
	actor.look_at_psx(x, z)
	return from == FieldMap.model_tile(x, z)


## tickEntityWalkTo(scriptId, targetId, x, z, useCamera) for the callers outside the scripts (the
## training stations, specs/training.md §2.6): true when there, or when there is no such entity.
func tick_walk_to(script_id: int, target_id: int, x: int, z: int, use_camera := false) -> bool:
	var slot := script_id_to_entity_id(script_id)
	var actor := _actor(slot) if slot != FREE else null
	if actor == null:
		return true
	return _tick_walk_to(slot, actor, target_id, x, z, use_camera)


## tickEntityWalkTo(id, target, x, z, useCamera) for a slot: to the point, or to the target entity's
## location (taken every frame), ending on its tile or when the walker's next step hits an entity
## 0-8. With the camera, the camera moves by the walker's motion since the previous tick.
func _tick_walk_to(slot: int, actor: Node3D, target_id: int, x: int, z: int, use_camera: bool) -> bool:
	if slot >= 2 and entities != null:
		# NPC_IS_WALKING_TOWARDS while it walks (tamer.c:1012, :1048).
		entities.walking_towards[slot - 2] = 1
	var from := actor.position
	var to := Vector2i(x, z)
	if target_id != FREE:
		var target := _entity_for_script_id(target_id)
		if target == null:
			return true
		to = Vector2i(int(target.position.x), int(-target.position.z))
	if not _previous_camera_pos_initialized and use_camera:
		_previous_camera_pos = from
		_previous_camera_pos_initialized = true
	var from_tile := FieldMap.model_tile(int(from.x), int(-from.z))
	actor.look_at_psx(to.x, to.y)
	if use_camera:
		_move_camera_by_diff(_previous_camera_pos, from)
		_previous_camera_pos = from
	var col := -1
	if target_id != FREE:
		col = _walker_collision(actor)
	if from_tile == FieldMap.model_tile(to.x, to.y) or (col != -1 and col < WALK_HIT_LIMIT):
		_previous_camera_pos_initialized = false
		if slot >= 2 and entities != null:
			entities.walking_towards[slot - 2] = 0
		return true
	return false


## entityCheckCollision(NULL, walker, 0, 0): the entity (0-9) or the map (10) the walker's next
## step hits, -1 none.
func _walker_collision(actor: Node3D) -> int:
	if actor is FieldDigimon:
		return actor.check_collision()
	if actor == tamer and entities != null:
		return entities.tamer_collision(false, false, false)
	return -1


## tickEntityMoveTo (tamer.c:1114): the first frame (PREVIOUS_CAMERA_POS_INITIALIZED clear) takes
## the delta, (target - position) / speed per axis; then the entity slides by it through walls, each
## axis done when it reached or passed (x, z), and set to it. The entity-target forms take the delta
## from the target but compare with (x, z) = (0, 0) (the C's quirk; no uses).
func _tick_move_to(actor: Node3D, target_id: int, x: int, z: int, speed: int, use_camera: bool) -> bool:
	speed = _speed(speed)
	if not _previous_camera_pos_initialized:
		var to := Vector2i(x, z)
		if target_id != FREE:
			var target := _entity_for_script_id(target_id)
			if target == null:
				return true
			to = Vector2i(int(target.position.x), int(-target.position.z))
		_move_to_delta = Vector2i((to.x - int(actor.position.x)) / speed, (to.y - int(-actor.position.z)) / speed)
		_previous_camera_pos_initialized = true
		_previous_camera_pos = actor.position
	else:
		actor.position.x += _move_to_delta.x
		actor.position.z -= _move_to_delta.y
		var done_x := false
		var done_z := false
		if _move_to_delta.x < 0:
			if x >= int(actor.position.x):
				actor.position.x = x
				done_x = true
		elif x <= int(actor.position.x):
			actor.position.x = x
			done_x = true
		if _move_to_delta.y < 0:
			if int(-actor.position.z) <= z:
				actor.position.z = -z
				done_z = true
		elif int(-actor.position.z) >= z:
			actor.position.z = -z
			done_z = true
		if done_x and done_z:
			_previous_camera_pos_initialized = false
			return true
	if use_camera:
		_move_camera_by_diff(_previous_camera_pos, actor.position)
		_previous_camera_pos = actor.position
	return false


## tickEntityMoveToAxis (tamer.c:1192): the same on one PSX axis (0 x, 1 y, 2 z) to `value`, with
## the delta in MOVE_TO_DELTA_X.
func _tick_move_to_axis(actor: Node3D, value: int, axis: int, speed: int, use_camera: bool) -> bool:
	speed = _speed(speed)
	if not _previous_camera_pos_initialized:
		_move_to_delta.x = (value - _psx_axis(actor, axis)) / speed
		_previous_camera_pos = actor.position
		_previous_camera_pos_initialized = true
	else:
		_set_psx_axis(actor, axis, _psx_axis_exact(actor, axis) + _move_to_delta.x)
		var now := _psx_axis(actor, axis)
		if (_move_to_delta.x < 0 and now <= value) or (_move_to_delta.x >= 0 and now >= value):
			_set_psx_axis(actor, axis, value)
			_previous_camera_pos_initialized = false
			return true
	if use_camera:
		_move_camera_by_diff(_previous_camera_pos, actor.position)
		_previous_camera_pos = actor.position
	return false


## The moves' int8 speed; the scripts use 1-99 (a 0 would divide by zero in the C).
static func _speed(speed: int) -> int:
	speed = ((speed & 0xFF) ^ 0x80) - 0x80
	return speed if speed != 0 else 1


## A PSX axis (0 x, 1 y, 2 z) of an entity's Godot position (x, -y, -z).
static func _psx_axis_exact(actor: Node3D, axis: int) -> float:
	if axis == 0:
		return actor.position.x
	return -actor.position.y if axis == 1 else -actor.position.z


static func _psx_axis(actor: Node3D, axis: int) -> int:
	return int(_psx_axis_exact(actor, axis))


static func _set_psx_axis(actor: Node3D, axis: int, value: float) -> void:
	if axis == 0:
		actor.position.x = value
	elif axis == 1:
		actor.position.y = -value
	else:
		actor.position.z = -value


## moveCameraByDiff (map.c:5124): the camera moves by the screen motion between two Godot points,
## with the pad as it is.
func _move_camera_by_diff(from: Vector3, to: Vector3) -> void:
	if field != null:
		field.scroll_by(field.screen_motion(from, to), pad.polled if pad != null else 0)


## tickCameraMoveTo / tickCameraMoveToEntity (map.c:5100, :5114): CAMERA_TARGET set every frame (the
## point at the tamer's height, or the entity's location; an id with no entity keeps the old one),
## then checkCameraMovement. Without a field the pan ends at once.
func _tick_camera_slot(type: int, args: Dictionary) -> bool:
	if field == null:
		return true
	if type == MOVE_CAMERA_TO:
		var y := tamer.position.y if tamer != null else 0.0
		field.pan_target = Vector3(int(args["x"]), y, -int(args["z"]))
	else:
		var entity := _entity_for_script_id(int(args["id"]))
		if entity != null:
			field.pan_target = entity.position
	return field.check_pan(int(args["speed"]))


## tickLookAtEntity (tamer.c:1058): the first frame takes the target's position, then the entity
## turns 0x200 per frame (rotateEntity) the shorter way to it.
func tick_look_at_entity(entity_id: int, target_script_id: int) -> bool:
	var actor := _actor(entity_id)
	if not _has_rotation_data[entity_id]:
		var target := _entity_for_script_id(target_script_id)
		if target == null:
			return true
		_rotation_data[entity_id] = Vector2i(int(target.position.x), int(-target.position.z))
		_has_rotation_data[entity_id] = true
		return false
	var to: Vector2i = _rotation_data[entity_id]
	var turned := FieldDigimon.rotate_entity(actor.direction, to.x - int(actor.position.x), to.y - int(-actor.position.z), LOOK_AT_SPEED)
	actor.set_direction(turned[0])
	if turned[1]:
		_has_rotation_data[entity_id] = false
	return turned[1]


## ENTITY_TABLE[slot], for the training stations (slot 2 = NPC_ENTITIES[0]).
func actor(slot: int) -> Node3D:
	return _actor(slot)


## The entity a movement slot moves: 0 the tamer, 1 the partner, 2-9 the NPCs.
func _actor(slot: int) -> Node3D:
	if slot == 0:
		return tamer
	if slot == 1:
		return partner
	if entities != null and slot < 10:
		return entities.entity(slot)
	return null


## getEntityFromScriptId (script_interp.c:644, scriptIdToEntityId); null when there is none.
func entity_for_script_id(script_id: int) -> Node3D:
	return _entity_for_script_id(script_id)


## getEntityFromScriptId; null when there is none.
func _entity_for_script_id(script_id: int) -> Node3D:
	var id := script_id_to_entity_id(script_id)
	return _actor(id) if id != FREE else null


## scriptSetEntityWalking (script_interp.c:879): the walk animation and the script state.
func set_entity_walking(script_id: int, anim: int) -> void:
	if script_id == ScriptContext.OWNER_TAMER:
		if tamer != null:
			tamer.start_animation(anim + 2)
			tamer.set_state(Tamer.STATE_SCRIPT)
	elif script_id == ScriptContext.OWNER_PARTNER:
		if partner != null:
			partner.start_animation((anim + 1) << 1)
			partner.set_state(Partner.STATE_SCRIPT)
	else:
		_npc_start_animation(script_id, (anim + 1) << 1)


## scriptStartAnimation (script_interp.c:893): PLAY_ANIMATION.
func script_start_animation(script_id: int, anim: int) -> void:
	if script_id == ScriptContext.OWNER_TAMER:
		if tamer != null:
			tamer.start_animation(anim)
			tamer.set_state(Tamer.STATE_SCRIPT)
	elif script_id == ScriptContext.OWNER_PARTNER:
		if partner != null:
			partner.start_animation(anim)
			partner.set_state(Partner.STATE_SCRIPT)
	else:
		_npc_start_animation(script_id, anim)


## scriptNPCStartAnimation (overworld.c:1802) on the first NPC with that script id, then the
## setActiveAnim(0xC) quirk (specs/npc.md §2.6): the C passes the script id 0xC and a leftover
## animId, so the animated NPC keeps its frame and the NPC with script id 12 gets NPC_ACTIVE_ANIM
## = the leftover. Without the animated NPC the leftover is the animation id; with it, it is
## unknown (§6: left unchanged).
func _npc_start_animation(script_id: int, anim: int) -> void:
	if entities == null:
		return
	var slot := entities.npc_slot_for_script_id(script_id)
	if slot >= 0:
		entities.npcs[slot].start_animation(anim)
		return
	var gated := entities.npc_slot_for_script_id(0xC)
	if gated >= 0:
		# setActiveAnim stores an int8.
		entities.active_anim[gated] = ((anim & 0xFF) ^ 0x80) - 0x80


## The end of tickScript once the script paused (script_interp.c:634-642).
func _end() -> void:
	textboxes.close_all_textboxes()
	game_state.set_script_value(0, ctx.saved_pstat0)
	if ctx.took_over == 1:
		set_movement_enabled(-1, false)
		if tamer != null:
			tamer.camera_follow = true
		if clock != null:
			clock.running = true
	ended.emit()


# --- the field (script_interp.c:2727, overworld.c:1869) ------------------------------------------------

## scriptPauseGame(owner): the first time in a section the script takes over the field.
func pause_game(owner: int) -> void:
	if ctx.took_over == 0:
		ctx.took_over = 1
		set_movement_enabled(0, true)
		set_movement_enabled(1, true)
		if tamer != null:
			tamer.camera_follow = false
		game_state.set_script_value(0, 3)
		textboxes.text_area.clear_all()
		if clock != null:
			clock.running = false
		# An event section (an NPC talk): the NPC and the tamer turn to each other (type 0).
		if ctx.section_is_event != 0 and not game_state.is_trigger_set(TRIGGER_NO_TURN):
			var npc := script_id_to_entity_id(ctx.section)
			if npc != FREE:
				_set_movement(npc, MOVE_LOOK_AT, {"id": ctx.section, "target": ScriptContext.OWNER_TAMER})
				_set_movement(0, MOVE_LOOK_AT, {"id": ScriptContext.OWNER_TAMER, "target": ctx.section})
	game_state.clear_trigger(TRIGGER_NO_TURN)
	if owner < ScriptContext.OWNER_SPECIAL:
		var entity := script_id_to_entity_id(owner)
		if entity != FREE:
			set_movement_enabled(entity, true)


## setMovementEnabled(id, enabled): enabled = the script moves it (tamer state 6, partner 11);
## -1 = the tamer, the partner and the NPCs.
func set_movement_enabled(id: int, enabled: bool) -> void:
	if (id == 0 or id == -1) and tamer != null:
		tamer.set_state(Tamer.STATE_STILL if enabled else Tamer.STATE_FREE)
	if (id == 1 or id == -1) and partner != null:
		partner.set_state(Partner.STATE_IDLE if enabled else Partner.STATE_NORMAL)
	# The NPCs: MAP_DIGIMON_TABLE[].stopAnim, their AI state cleared when taken.
	if entities != null:
		if id == -1:
			entities.set_stop_anim(-1, enabled)
		elif id >= 2:
			entities.set_stop_anim(id - 2, enabled)


## scriptIdToEntityId (script_value.c:131): 0 the tamer, 1 the partner, 2-9 the NPC entities,
## 0xFF none.
func script_id_to_entity_id(script_id: int) -> int:
	if entities != null:
		return entities.script_id_to_entity_id(script_id)
	if script_id == ScriptContext.OWNER_TAMER:
		return 0
	if script_id == ScriptContext.OWNER_PARTNER:
		return 1
	return FREE


# --- instructions --------------------------------------------------------------------------------------

## One instruction (the opcode is read): its handler's longjmp code.
func execute(op: int) -> int:
	if op >= 0xFB and op <= 0xFF:
		return _op_fb_ff(op)
	if op >= 0x10 and op < 0x28:
		return _op_10_27(op)
	if op >= 0x28 and op < 0x40:
		return _op_28_3f(op)
	if op >= 0x46 and op < 0x59:
		return _op_46_58(op)
	if op >= 0x5A and op < 0x60:
		return _op_5a_5f(op)
	if op >= 0x64 and op < 0x7F:
		return _op_64_7e(op)
	# Outside every range: the script pauses (UNUSED_11 / 12's alignment byte gets here).
	ctx.is_paused = true
	return STOP


func _op_fb_ff(op: int) -> int:
	match op:
		0xFF, 0xFE:
			return return_from_script_file()
		0xFB:
			ctx.pointer += 1
			ctx.current_script_id = _u16()
			ctx.current_screen_id = _u16()
			ctx.stack.append({"type": MAP_SETUP})
			ctx.map_setup_pending = 1
			if sound != null:
				sound.music.reset_bgm()
			if load_map.is_valid():
				load_map.call(ctx.current_screen_id)
			return NEXT
	# UNUSED_FC / FD: no case, the function returns without a longjmp: the frame ends.
	return STOP


func _op_10_27(op: int) -> int:
	match op:
		ScriptContext.OP_SET_SELECTION:
			ctx.text_owner_mode = 1
			textboxes.script_show_selection()
			return STOP
		0x11, 0x12:
			pass
		0x13:
			ctx.pointer += 1
			var target := _u16()
			_push({"type": LINK, "pointer": ctx.pointer, "script": ctx.code_id})
			ctx.pointer = target
		0x14:
			ctx.pointer += 1
			var script := _u16()
			var section := _u16()
			_push({"type": LINK, "pointer": ctx.pointer, "script": ctx.code_id})
			_jump_to_file(script, section)
		0x15:
			ctx.pointer += 1
			var entry := _pop()
			_use_script(int(entry.get("script", ctx.code_id)))
			ctx.pointer = int(entry.get("pointer", ctx.pointer))
		0x16:
			ctx.pointer += 1
			ctx.pointer = _u16()
		0x17:
			ctx.pointer += 1
			var script := _u16()
			var section := _u16()
			_jump_to_file(script, section)
		0x18:
			var value := ctx.read_pstat(ctx.next_byte())
			var count := _u16()
			if value >= count:
				value = (count - 1) & 0xFF
			ctx.pointer = ctx.u16_at(ctx.pointer + (value << 1))
		0x19:
			ctx.pointer += 1
			return script_if()
		ScriptContext.OP_SHOW_TEXTBOX:
			ctx.pointer += 1
			textboxes.show_textbox(0, ScriptContext.OWNER_NONE if ctx.text_owner_mode == 2 else ctx.dialogue_owner)
			return STOP
		ScriptContext.OP_SET_DIALOG_OWNER:
			var owner := ctx.next_byte()
			ctx.text_owner_mode = 0
			if textboxes.boxes.boxes[0].state != UIBoxes.STATE_OPEN:
				ctx.dialogue_owner = (owner - 1) & 0xFF
			textboxes.set_dialogue_owner(owner)
		0x1C:
			ctx.pointer += 1
			game_state.set_trigger(_u16())
		0x1D:
			ctx.pointer += 1
			game_state.clear_trigger(_u16())
		0x1E, 0x1F, 0x20:
			ctx.pointer += 1
			var pstat := ctx.next_byte()
			var value := ctx.next_byte()
			if op == 0x1F:
				value = mini(ctx.read_pstat(pstat) + value, 0xFF)
			elif op == 0x20:
				value = maxi(ctx.read_pstat(pstat) - value, 0)
			game_state.set_script_value(pstat, value)
		0x21:
			game_state.set_script_value(ctx.next_byte(), ctx.current_screen_id)
		0x22:
			game_state.set_script_value(ctx.next_byte(), _partner_type())
		0x23:
			game_state.set_inventory_size(ctx.next_byte())
		0x24:
			ctx.pointer += 1
			var pstat := ctx.next_byte()
			var max_value := ctx.next_byte()
			game_state.set_script_value(pstat, Rng.random_limit(max_value + 1))
		0x25:
			var pstat := ctx.next_byte()
			var c: Dictionary = game_state.state["clock"]
			for i in 4:
				game_state.set_script_value((pstat + i) & 0xFF, int(c[["year", "day", "hour", "minute"][i]]))
		ScriptContext.OP_SET_TEXTBOX_SIZE:
			pause_game(0xFF)
			ctx.text_owner_mode = 2
			textboxes.script_set_textbox_size()
		0x27:
			textboxes.close_box(ctx.next_byte())
			return STOP
	return NEXT


func _op_28_3f(op: int) -> int:
	match op:
		0x28:
			ctx.pointer += 1
			var item := ctx.next_byte()
			var amount := ctx.next_byte()
			# giveItem's failure sets trigger 0 (the script then says the bag is full).
			if game_state.give_item(item, amount):
				game_state.clear_trigger(0)
			else:
				game_state.set_trigger(0)
		0x29:
			ctx.pointer += 1
			var item := ctx.next_byte()
			var amount := ctx.next_byte()
			if item != 0xFF:
				game_state.remove_item(item, amount)
		0x2A, 0x2B:
			ctx.pointer += 1
			var amount := _s32()
			var money := int(game_state.state["money"]) + (amount if op == 0x2A else -amount)
			game_state.state["money"] = clampi(money, 0, MONEY_MAX)
			game_state.changed.emit("money")
		0x2C:
			script_compare_date()
		0x2D:
			game_state.learn_move(ctx.next_byte())
		0x2E:
			ctx.next_byte()
		0x2F, 0x30:
			var card := ctx.next_byte()
			var count: int = game_state.card_count(card)
			if op == 0x2F and count < 9:
				game_state.set_card_count(card, count + 1)
			elif op == 0x30 and count != 0:
				game_state.set_card_count(card, count - 1)
		0x31, 0x32, 0x33:
			ctx.pointer += 1
			var value := _u16()
			var merit := int(game_state.state["merit"])
			match op:
				0x31:
					merit = _s16(value)
				0x32:
					merit = _s16(merit + value)
				0x33:
					# Quirk kept: MERIT = -value, which the check then clears (script_interp.c:1175).
					merit = _s16(-value)
			if op == 0x33:
				merit = maxi(merit, 0)
			elif merit >= MERIT_MAX + 1:
				merit = MERIT_MAX
			game_state.state["merit"] = merit
			game_state.changed.emit("merit")
		0x34, 0x35, 0x36:
			var stat := ctx.next_byte()
			var value := _u16()
			var current := get_stat(stat)
			var result := 0
			match op:
				0x34:
					result = enforce_stats_limits(stat, _s16(value))
				0x35:
					result = enforce_stats_limits(stat, _s16(current + value))
				0x36:
					result = current - _s16(value)
					result = maxi(result, -100 if stat == 9 else 0)
			set_stat(stat, _s16(result))
			if care != null:
				care.update_energy_boundaries()
		0x37:
			advance_to_date_at(ctx.next_byte())
		0x38, 0x39:
			var pstat := ctx.next_byte()
			var minutes := _u16() | (_u16() << 16)
			minutes = minutes - 0x100000000 if minutes >= 0x80000000 else minutes
			var date := date_to_minutes(ctx.read_pstat(pstat), ctx.read_pstat(pstat + 1), ctx.read_pstat(pstat + 2), ctx.read_pstat(pstat + 3))
			var total := date + minutes if op == 0x38 else maxi(date - minutes, 0)
			if total < 0:
				total += 0x100000000   # secondsToDate takes a uint32: the cap applies
			var parts := minutes_to_date(total)
			for i in 4:
				game_state.set_script_value((pstat + i) & 0xFF, parts[i])
		0x3A, 0x3B, 0x3C:
			ctx.pointer += 3
		0x3D, 0x3E:
			ctx.next_byte()
		0x3F:
			ctx.pointer += 1
			var digimon := ctx.read_pstat(ctx.next_byte())
			var out := ctx.next_byte()
			var type = data.digimon(digimon).get("type", {})
			game_state.set_script_value(out, int(type.get("id", 0)) if type is Dictionary else int(type))
	return NEXT


func _op_46_58(op: int) -> int:
	if entities == null and op in NPC_OPS:
		return _unported_op(op)
	match op:
		0x46:
			entities.load_model(ctx.next_byte())
		0x47:
			pause_game(0xFF)
			var type := ctx.next_byte()
			var slot := ctx.next_byte()
			entities.set_digimon(type, slot, ctx.next_byte())
		0x48:
			pause_game(0xFF)
			var id := ctx.next_byte()
			if not entities.unload_entity(id):
				_report(op, "UNLOAD_ENTITY of an entity not on the map")
		0x4C:
			pause_game(0xFF)
			ctx.pointer += 1
			var id := ctx.next_byte()
			var target := ctx.next_byte()
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_LOOK_AT, {"id": id, "target": target})
		0x4D:
			pause_game(0xFF)
			var id := ctx.next_byte()
			var angle := _s16(_u16())
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_SET_ROTATION, {"id": id, "angle": angle})
		0x49:
			pause_game(0xFF)
			call_digimon_routine(ctx.next_byte())
		0x4F:
			pause_game(0xFF)
			var speed := ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			_set_movement(CAMERA_SLOT, MOVE_CAMERA_TO, {"x": x, "z": z, "speed": speed})
		0x50:
			pause_game(0xFF)
			ctx.pointer += 1
			var id := ctx.next_byte()
			_set_movement(CAMERA_SLOT, MOVE_CAMERA_TO_ENTITY, {"id": id, "speed": ctx.next_byte()})
		0x51, 0x53:
			# ENTITY_WALK_TO_ENTITY and its camera form.
			pause_game(0xFF)
			var id := ctx.next_byte()
			var anim := ctx.next_byte()
			var target := ctx.next_byte()
			set_entity_walking(id, anim)
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_WALK_TO_ENTITY if op == 0x51 else MOVE_WALK_TO_ENTITY_WITH_CAMERA,
						{"id": id, "target": target})
		0x52:
			pause_game(0xFF)
			var id := ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			var anim := ctx.next_byte()
			ctx.next_byte()
			set_entity_walking(id, anim)
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_WALK_TO_WITH_CAMERA, {"id": id, "x": x, "z": z})
		0x54:
			pause_game(0xFF)
			entities.reset_entity_origin(ctx.next_byte())
		0x56:
			ctx.pointer += 1
			var id := ctx.next_byte()
			script_start_animation(id, ctx.next_byte())
		OP_WAIT_FOR_ENTITY:
			var id := ctx.next_byte()
			ctx.active_instruction = OP_WAIT_FOR_ENTITY
			ctx.wait_for_entity_id = _wait_slot(id)
			return STOP
		OP_ENTITY_WALK_TO:
			pause_game(0xFF)
			var id := ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			var anim := ctx.next_byte()
			ctx.next_byte()
			set_entity_walking(id, anim)
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_WALK_TO, {"id": id, "x": x, "z": z})
		0x4B:
			pause_game(0xFF)
			ctx.script_param_1 = ctx.next_byte()
			ctx.state_2 = ctx.next_byte()
			var section := ctx.next_byte()
			consume_map_change_show_name()
			_push({"type": AFTER_MAP_CHANGE, "arg": section})
			return MAP_CHANGE
		0x55:
			ctx.pointer += 1
			ctx.textbox_origin = [_s16(_u16()), _s16(_u16()), _s16(_u16())]
		0x57:
			# SET_OBJ_VISIBILITY _, instance, flag: setMapObjectsFlag sets the whole flag.
			if field == null:
				return _unported_op(op)
			ctx.pointer += 1
			var instance := ctx.next_byte()
			field.overlays.set_flag(instance, ctx.next_byte())
		0x58:
			pause_game(0xFF)
			var pstat := ctx.next_byte()
			ctx.script_param_1 = ctx.read_pstat(pstat)
			ctx.state_2 = ctx.read_pstat(pstat + 1)
			consume_map_change_show_name()
			_push({"type": AFTER_MAP_CHANGE, "arg": 0xFF})
			return MAP_CHANGE
		_:
			return _unported_op(op)
	return NEXT


## scriptInstruction5Ato5F (script_interp.c:1557).
func _op_5a_5f(op: int) -> int:
	match op:
		0x5B, 0x5C, 0x5F:
			ctx.next_byte()
		_ when sound == null:
			return _unported_op(op)
		0x5A:
			# PLAY_SOUND bank, sound (skipOnePollTwoScriptBytes): playSound.
			ctx.pointer += 1
			var bank := ctx.next_byte()
			var value := ctx.next_byte()
			sound.play_sound(bank, value)
		0x5D:
			sound.music.play_bgm(ctx.next_byte())
		0x5E:
			# STOP_BGM x: resetBGM; the byte isn't used.
			ctx.next_byte()
			sound.music.reset_bgm()
	return NEXT


func _op_64_7e(op: int) -> int:
	if entities == null and op in NPC_OPS:
		return _unported_op(op)
	match op:
		0x6A:
			ctx.pointer += 1
			var slot := script_id_to_entity_id(ctx.next_byte())
			var value := ctx.next_byte()
			if slot != FREE and slot >= 2:
				entities.slots[slot - 2]["autotalk"] = value
		0x79:
			entities.unload_model(ctx.next_byte())
		0x6C, 0x6E:
			# ENTITY_MOVE_TO and its camera form; the C sets type 0xB (an entity target) for the camera
			# form, not 10 (no uses).
			pause_game(0xFF)
			var id := ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			var speed := ctx.next_byte()
			ctx.next_byte()
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_TO if op == 0x6C else MOVE_TO_ENTITY_WITH_CAMERA,
						{"id": id, "x": x, "z": z, "speed": speed})
		0x6D, 0x6F:
			pause_game(0xFF)
			var id := ctx.next_byte()
			var target := ctx.next_byte()
			var speed := ctx.next_byte()
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_TO_ENTITY if op == 0x6D else MOVE_TO_ENTITY_WITH_CAMERA,
						{"id": id, "target": target, "speed": speed})
		0x72, 0x73:
			# ENTITY_MOVE_TO_AXIS id, value, axis (int8), speed, and its camera form.
			pause_game(0xFF)
			var id := ctx.next_byte()
			var value := _s16(_u16())
			var axis := ctx.next_byte()
			var speed := ctx.next_byte()
			var slot := script_id_to_entity_id(id)
			if slot != FREE:
				_set_movement(slot, MOVE_TO_AXIS if op == 0x72 else MOVE_TO_AXIS_WITH_CAMERA,
						{"id": id, "x": value, "target": ((axis & 0xFF) ^ 0x80) - 0x80, "speed": speed})
		0x70, 0x71, 0x7C, 0x7D, 0x7E:
			if field == null:
				return _unported_op(op)
			return _op_map_object(op)
		ScriptContext.OP_CALL_ROUTINE:
			return _call_routine(ctx.next_byte())
		0x65:
			game_state.set_condition(ctx.next_byte(), false)
		OP_START_BATTLE when battles != null:
			return _start_battle()
		ScriptContext.OP_DELAY:
			ctx.pointer += 1
			textboxes.delay_frames = _u16()
			ctx.active_instruction = ScriptContext.OP_DELAY
			return STOP
		ScriptContext.OP_SET_TEXTBOX_MODE:
			ctx.pointer += 1
			var mode := ctx.next_byte()
			var frames := ctx.next_byte()
			ctx.textbox_close_mode = mode
			if mode == 2:
				textboxes.autoclose_frames = frames
		0x69:
			pause_game(0xFF)
			deal_damage(ctx.read_pstat(ctx.next_byte()))
		0x6B:
			pass
		0x7A:
			ctx.pointer += 1
			var value := ctx.read_pstat(ctx.next_byte())
			game_state.set_script_value(ctx.next_byte(), value)
		0x7B:
			_push({"type": AFTER_MAP_CHANGE, "arg": ctx.next_byte()})
			game_state.set_script_value(0, ctx.saved_pstat0)
		0x74 when map_items != null:
			# SPAWN_ITEM item, x, z (spawnItem: the two shorts are the tile), at the tamer's height
			var item := ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			map_items.spawn(item, Vector2i(x, z), int(-tamer.position.y) if tamer != null else 0)
		0x75 when map_chests != null:
			# SPAWN_CHEST item, x, y, z, rotation, trigger (spawnChest)
			var item := ctx.next_byte()
			var x := _s16(_u16())
			var y := _s16(_u16())
			var z := _s16(_u16())
			var rotation := _s16(_u16())
			map_chests.spawn(item, Vector3i(x, y, z), rotation, _u16())
		0x76 when map_props != null:
			# SPAWN_BOULDER (script_interp.c:2129)
			ctx.next_byte()
			map_props.spawn_boulder()
		0x77 when map_props != null:
			# MOVE_BOULDER (script_interp.c:2133): byte, two signed shorts, ends the frame (longjmp 2)
			ctx.next_byte()
			var x := _s16(_u16())
			var z := _s16(_u16())
			map_props.move_boulder(x, z)
			return STOP
		0x78 when map_props != null:
			# DESPAWN_BOULDER (script_interp.c:2138)
			ctx.next_byte()
			map_props.despawn_boulder()
		_:
			return _unported_op(op)
	return NEXT


## The map-object opcodes (specs/map_objects.md §2.4-2.7; script_interp.c:2062-2175).
func _op_map_object(op: int) -> int:
	match op:
		0x70:
			# ROTATE_3D_OBJECT door, _, target (int8): slot 11 type 12.
			pause_game(0xFF)
			var door := ctx.next_byte()
			ctx.next_byte()
			_set_movement(DOOR_SLOT, MOVE_ROTATE_DOOR, {"id": door, "target": _s8(ctx.next_byte())})
		0x71:
			# MOVE_OBJECT_TO slot, instance, speed (unused), steps (int8), _, x, y: slot 12 + slot
			# type 13.
			pause_game(0xFF)
			var slot := ctx.next_byte() + OBJECT_SLOT
			var instance := ctx.next_byte()
			var speed := ctx.next_byte()
			var steps := _s8(ctx.next_byte())
			ctx.next_byte()
			var x := _s16(_u16())
			var y := _s16(_u16())
			if slot < MOVEMENT_SLOTS:
				_set_movement(slot, MOVE_OBJECT_TO, {"id": instance, "speed": speed, "target": steps, "x": x, "z": y})
			else:
				_report(op, "MOVE_OBJECT_TO slot %d" % (slot - OBJECT_SLOT))
		0x7C:
			# SET_RECT_IMPASSABLE _, x, z, w, h: setImpassableRect's arguments are int8.
			ctx.next_byte()
			var x := _s8(_u16())
			var z := _s8(_u16())
			var w := _s8(ctx.next_byte())
			field.set_impassable_rect(x, z, w, _s8(ctx.next_byte()))
		0x7D:
			# SPAWN_SPRITE_AT_LOCATION count, x, y, z, instance (no uses).
			var count := ctx.next_byte()
			var p := [_s16(_u16()), _s16(_u16()), _s16(_u16())]
			var instance := _s16(_u16())
			field.overlays.place_at(Vector2i(field.background_pixel(Content.psx_to_godot(p)).round()), instance, count)
		0x7E:
			# SPAWN_SPRITE_AT_ENTITY id, node (int8), instance: the node's world position.
			var id := ctx.next_byte()
			var node := _s8(ctx.next_byte())
			var instance := ctx.next_byte()
			var entity := _entity_for_script_id(id)
			if entity == null or not entity.has_method("bone_position"):
				_report(op, "SPAWN_SPRITE_AT_ENTITY of an entity not on the map")
			else:
				var pixel := Vector2i(field.background_pixel(entity.bone_position(node)).round())
				field.overlays.place_at(pixel, instance)
	return NEXT


## An opcode whose system isn't ported: its bytes, scriptPauseGame if the C does it, reported.
func _unported_op(op: int) -> int:
	var spec: Array = UNPORTED.get(op, [0, false, false])
	if spec[1]:
		pause_game(0xFF)
	ctx.pointer += spec[0]
	_report(op, NAMES.get(op, "0x%02X" % op))
	return STOP if spec[2] else NEXT


func _report(op: int, report_name: String) -> void:
	if not _reported.has(report_name):
		_reported[report_name] = true
		unported.emit(op, report_name)


## The unported reports so far.
func reported() -> PackedStringArray:
	return PackedStringArray(_reported.keys())


## WAIT_FOR_ENTITY's id -> movement slot (script_interp.c:1331-1400).
func _wait_slot(id: int) -> int:
	if id == 0xFF:
		return 0xFF
	if id >= 0xC8 and id <= 0xD4 and id != 0xC9:
		return {0xC8: 0xA, 0xCA: 0xB, 0xCB: 0xC, 0xCC: 0xD, 0xCD: 0xE, 0xCE: 0xF, 0xCF: 0x10, 0xD0: 0x11,
				0xD1: 0x12, 0xD2: 0x13, 0xD3: 0x14, 0xD4: 0x15}[id]
	if id == 0xC9:
		return 0x19
	if id == 0xD5:
		ctx.sync_bit = 0
		return 0x19
	if id == 0xD6:
		return 0x1A
	return script_id_to_entity_id(id)


# --- CALL_DIGIMON_ROUTINE (partner.c:1137) ----------------------------------------------------------

## callDigimonRoutine: routine 0 starts the toilet scene (partner state 6, specs/care.md §2.16),
## routines 2 and 10 an evolution (state 13, EVOLUTION_TARGET from a script value); each clears the
## sync bit, which the scene sets when done. The other routines' scenes aren't ported: reported,
## the bit stays set.
func call_digimon_routine(routine: int) -> void:
	if routine == ROUTINE_TOILET and partner != null:
		partner.set_state(Partner.STATE_TOILET)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	if (routine == ROUTINE_EVOLVE_BACK or routine == ROUTINE_EVOLVE) and partner != null and care != null:
		care.evolution_target = game_state.script_value(
				PSTAT_SUKAMON_BACKUP if routine == ROUTINE_EVOLVE_BACK else PSTAT_EVOLUTION)
		partner.set_state(Partner.STATE_EVOLVING)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# 3: the natural death (partnerTickDying), 4: the rebirth (partnerTickDying2), both with the DOOA
	# scene (specs/death_reincarnation.md §2, §7).
	if (routine == ROUTINE_DYING or routine == ROUTINE_REBIRTH) and partner != null:
		partner.set_state(Partner.STATE_DYING if routine == ROUTINE_DYING else Partner.STATE_REBIRTH)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# 7: no life left (tamerTickSicknessLostLife: MURD then DOOA), 9: a life lost
	# (tamerTickBattleLostLife: MURD); the partner is still (state 12), both stop walking.
	if (routine == ROUTINE_COLLAPSE or routine == ROUTINE_BATTLE_LOSS) and partner != null and tamer != null:
		tamer.set_state(Tamer.STATE_SICKNESS_LOST_LIFE if routine == ROUTINE_COLLAPSE else Tamer.STATE_BATTLE_LOST_LIFE)
		partner.set_state(Partner.STATE_SCRIPT)
		var tamer_anim: int = tamer.animation_id()
		if tamer_anim == 2 or tamer_anim == 3:
			tamer.start_animation(0)
		var partner_anim: int = partner.animator.anim_id if partner.animator != null else 0
		if partner_anim > 1 and partner_anim < 5:
			partner.start_animation(Partner.ANIM_IDLE)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# 5 / 6: the opening (tamerTickOpening) and the ending (tamerTickEnding).
	if (routine == ROUTINE_OPENING or routine == ROUTINE_ENDING) and partner != null and tamer != null \
			and (routine == ROUTINE_OPENING or ending != null):
		tamer.set_state(Tamer.STATE_OPENING if routine == ROUTINE_OPENING else Tamer.STATE_ENDING)
		partner.set_state(Partner.STATE_IDLE)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# 8: Machinedramon's spawn (tamerTickMachinedramonSpawn waits for EAB_tick, then sets the bit).
	if routine == ROUTINE_MACHINEDRAMON and partner != null and tamer != null and eab != null:
		tamer.set_state(Tamer.STATE_MACHINEDRAMON_SPAWN)
		partner.set_state(Partner.STATE_IDLE)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# 1: curling (partner.c:1146): KAR_start, tamer state 12, partner state 11, the sync bit cleared;
	# KAR_finishMatch sets it again.
	if routine == ROUTINE_CURLING and partner != null and tamer != null and curling != null:
		curling.start()
		tamer.set_state(Tamer.STATE_CURLING)
		partner.set_state(Partner.STATE_IDLE)
		ctx.sync_bit = 0
		_sync_scene = true
		return
	# Routines past 10 aren't cases of the C's switch: nothing happens (the gyms call 214).
	if routine > ROUTINE_LAST:
		return
	_report(0x49, "CALL_DIGIMON_ROUTINE %d" % routine)


# --- CALL_ROUTINE (script_interp.c:1658-1891) -------------------------------------------------------

func _call_routine(routine: int) -> int:
	ctx.script_param_1 = routine
	if routines != null and routines.handles(routine):
		# The C's setup of a waiting builtin (step 0, mode 0); a builtin with its own setup
		# (0x20, initializeNamingBuffer) sets its step in start(). The frame ends.
		var state_2 := ctx.state_2
		var textbox_mode := ctx.textbox_mode
		ctx.state_2 = 0
		ctx.textbox_mode = 0
		if routines.start(routine):
			ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
			return STOP
		ctx.state_2 = state_2
		ctx.textbox_mode = textbox_mode
		return NEXT
	match routine:
		0x03, 0x04, 0x05, 0x11:
			pass
		0x0C:
			var item := ctx.read_pstat(0xFE)
			if item != 0xFF:
				game_state.remove_item(item, 1)
		0x0D:
			var item := ctx.read_pstat(0xFE)
			if item != 0xFF:
				game_state.remove_item(item, 0x63)
		0x10:
			textboxes.trigger_box_close_flag(2)
			return STOP
		0x13 when map_props != null:
			# setDirtCartModel (script_interp.c:1753-1756)
			map_props.set_dirt_cart_model(ctx.read_pstat(0xFE))
			return STOP
		0x14 when map_props != null:
			# decreaseDirtPileSize (script_interp.c:1757-1759)
			map_props.decrease_dirt_pile()
			return STOP
		0x19:
			ctx.saved_pstat0 = ctx.read_pstat(0xFE)
		0x1A when map_props != null:
			# loadDirtCartModel (script_interp.c:1777-1779)
			map_props.load_dirt_cart()
		0x1B when map_props != null:
			# loadDirtPileModel (script_interp.c:1780-1782)
			map_props.load_dirt_pile()
		0x1C when map_effects != null:
			# createMonochromonMoodBubble (script_interp.c:1783-1785)
			map_effects.create_mood_bubble()
		0x1E:
			ctx.shop_variable = 0
		0x1F:
			ctx.shop_variable += ctx.read_pstat(0xF4) + (ctx.read_pstat(0xF3) << 8)
		0x22 when map_effects != null:
			# createMeramonShake (script_interp.c:1814-1816)
			map_effects.start_meramon_shake()
		0x26 when map_effects != null:
			# createNinjamonEffect (script_interp.c:1838-1840)
			map_effects.start_ninjamon()
		0x29 when map_props != null:
			# spawnGearbox (script_interp.c:1870-1872)
			map_props.spawn_gearbox()
		0x2A when map_props != null:
			# somethingToyTown (script_interp.c:1873-1875). Its readMapTFS(0x92) rereads the Robot
			# House's own TFS (routine 0x2A runs only in OMOC03's script 140): nothing changes on screen
			# (specs/map_events.md §3.5, §8.1).
			map_props.set_box(_s8(ctx.read_pstat(0xFE)), game_state.is_trigger_set(350))
		0x2B when map_props != null:
			# spawnToyTownBoxes (script_interp.c:1876-1878)
			map_props.spawn_toy_town_boxes()
		0x2C when map_props != null:
			# openToyTownBox (script_interp.c:1879-1881)
			map_props.open_box(_s8(ctx.read_pstat(0xFE)))
		0x28 when eab != null:
			# EAB_startBuildup(ENTITY_TABLE[scriptIdToEntityId(5)]) (script_interp.c:1853-1856)
			eab.start_buildup(_entity_for_script_id(BUILDUP_SCRIPT_ID))
		0x34 when ending != null:
			# OP.TIM, ENDI_REL, loadMapSounds2(0x14) (script_interp.c:1848-1852)
			ending.load_scene()
		0x35 when ending != null and tamer != null:
			# isSoundLoaded(0, 8), tamerSetState(0x10), the sync bit cleared, the wait (script_interp.c:1858-1864)
			tamer.set_state(Tamer.STATE_ENDING)
			ctx.sync_bit = 0
			ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
			ctx.textbox_mode = 0
			return STOP
		0x33 when eab != null:
			# BOSS_EFE.TMD, EAB_REL, readVBALLSection(5, 0x73), loadMapSounds2(0x15) (script_interp.c:1841-1846)
			eab.load_scene()
		0x2D when fade != null:
			# fadeToWhite (script_interp.c:1882-1884)
			fade.fade_to_white(ctx.read_pstat(0xFE))
		0x2E when fade != null:
			# fadeFromWhite (script_interp.c:1885-1887)
			fade.fade_from_white(ctx.read_pstat(0xFE))
		0x31 when map_props != null:
			# spawnAngemonPedestal (script_interp.c:1888-1890)
			map_props.spawn_pedestal()
		0x32 when map_props != null:
			# moveAngemonPedestal setup (script_interp.c:1770-1774)
			ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
			ctx.textbox_mode = 0
			return STOP
		0x38:
			game_state.set_script_value(0xF3, (ctx.shop_variable / 256) & 0xFF)
			game_state.set_script_value(0xF4, ctx.shop_variable & 0xFF)
		0x37:
			# setLoopCountToOne(script value 0xFE) (overworld.c:1821): the entity's looping
			# animation plays to its end; then the frame ends (longjmp).
			var entity := _entity_for_script_id(ctx.read_pstat(0xFE))
			var animator = entity.get("animator") if entity != null else null
			if animator is PsxAnimator:
				animator.finish_loop()
			return STOP
		0x15:
			# resetMapObjectAnimation(script value 0xF7, count script value 0xF8), then the frame ends.
			if field == null:
				_report(ScriptContext.OP_CALL_ROUTINE, "CALL_ROUTINE 0x15")
				return STOP
			field.overlays.reset_animation(ctx.read_pstat(0xF7), ctx.read_pstat(0xF8))
			return STOP
		_:
			_report(ScriptContext.OP_CALL_ROUTINE, "CALL_ROUTINE 0x%02X" % routine)
			# A waiting builtin ends the frame; with its system missing it doesn't wait.
			return STOP if routine in ROUTINE_WAITS else NEXT
	return NEXT


# --- the stack and the end of a section (script_interp.c:2368-2720) ------------------------------------

func _push(entry: Dictionary) -> void:
	if ctx.stack.size() >= STACK_SIZE:
		push_warning("ScriptInterpreter: the script stack has more than %d entries (the C writes past it)" % STACK_SIZE)
	ctx.stack.append(entry)


## popScriptStack: an empty stack gives type 0.
func _pop() -> Dictionary:
	return ctx.stack.pop_back() if not ctx.stack.is_empty() else {"type": 0}


## returnFromScriptFile (script_interp.c:2684): END_SECTION / END_SCRIPT.
func return_from_script_file() -> int:
	while true:
		var entry := _pop()
		var type := int(entry.get("type", 0))
		if type == 0:
			break
		if type == MAP_SETUP:
			if setup_map.is_valid():
				setup_map.call()
			ctx.map_setup_pending = 0
			var script := load_script(ctx.current_script_id)
			var at := ScriptFiles.section(script, MAP_ENTRY_SECTION)
			if at >= 0:
				ctx.code = script
				ctx.code_id = ctx.current_script_id
				ctx.pointer = at
				return NEXT
		elif type == AFTER_MAP_CHANGE:
			var arg := int(entry.get("arg", 0xFF))
			if arg != 0xFF:
				_use_script(ctx.current_script_id)
				ctx.pointer = ScriptFiles.section(ctx.code, arg)
				if ctx.pointer < 0:
					ctx.is_paused = true
			else:
				_set_map_head_active()
			return STOP
	ctx.is_paused = true
	return STOP


## setMapHeadActive (script_interp.c:2181): MAPHEAD at code_start - 2 (its last table entry).
func _set_map_head_active() -> void:
	_use_script(ScriptFiles.MAPHEAD)
	ctx.pointer = ctx.code.decode_u16(0) - 2 if ctx.code.size() >= 2 else 0


func _use_script(id: int) -> void:
	ctx.code = load_script(id)
	ctx.code_id = id


func _jump_to_file(script: int, section: int) -> void:
	_use_script(script)
	ctx.pointer = ScriptFiles.section(ctx.code, section)
	if ctx.pointer < 0:
		push_warning("ScriptInterpreter: JUMP_TO_FILE to a missing section %d:0x%X" % [script, section])
		ctx.is_paused = true


# --- IF (script_interp.c:907) ---------------------------------------------------------------------------

func script_if() -> int:
	var result := 0
	while true:
		var cond_op := ctx.next_byte()
		ctx.pointer += 1
		if cond_op == 0x19:
			return NEXT
		var cond := 0
		match cond_op & 0x38:
			0x00:
				var trigger_set := 1 if game_state.is_trigger_set(_u16()) else 0
				cond = int(trigger_set == 1) if cond_op & 7 == 0 else int(trigger_set == 0)
			0x08:
				var value := ctx.read_pstat(ctx.next_byte())
				cond = compare(cond_op, value, ctx.next_byte())
			0x10:
				var target := _u16()
				if result != 1:
					continue
				ctx.pointer = target
				return NEXT
			0x18:
				var target := _u16()
				if result != 0:
					continue
				ctx.pointer = target
				return NEXT
			0x20:
				match cond_op & 7:
					0:
						cond = _compare_stat()
					1:
						var card := ctx.next_byte()
						var cmp := ctx.next_byte()
						cond = compare(cmp, game_state.card_count(card), _u16())
					2:
						var move := ctx.next_byte()
						var negate := ctx.next_byte()
						var has := 1 if game_state.has_move(move) else 0
						cond = has if negate == 0 else int(has == 0)
					3:
						var mask := ctx.next_byte()
						var negate := ctx.next_byte()
						var any := int(game_state.state["partner"]["care"]["condition"]) & mask != 0
						cond = int(any) if negate == 0 else int(not any)
					4:
						var item := ctx.next_byte()
						var cmp := ctx.next_byte()
						cond = compare(cmp, game_state.item_count(item), _u16())
					5:
						ctx.pointer += 1
						var cmp := ctx.next_byte()
						cond = compare(cmp, int(game_state.state["money"]), _s32())
		if cond_op & 0x80:
			result = 1 if result == 1 and cond == 1 else 0
		elif cond_op & 0x40:
			result = 0 if result != 1 and cond != 1 else 1
		else:
			result = cond
	return NEXT


## scriptCompareStat (script_value.c:183): stat 9 (happiness) signed.
func _compare_stat() -> int:
	var stat := ctx.next_byte()
	var cmp := ctx.next_byte()
	var value := _u16()
	if stat != 9:
		return compare(cmp, get_stat(stat) & 0xFFFF, value)
	return compare(cmp, get_stat(stat), _s16(value))


## scriptCompareValue / scriptCompareSignedValue (script_interp.c:1001, :1030).
static func compare(op: int, lhs: int, rhs: int) -> int:
	match op & 7:
		0:
			return int(lhs == rhs)
		1:
			return int(lhs != rhs)
		2:
			return int(lhs >= rhs)
		3:
			return int(lhs <= rhs)
		4:
			return int(lhs > rhs)
		5:
			return int(lhs < rhs)
	return 0


# --- stats (script_value.c:208-373) ---------------------------------------------------------------------

## getStatsPointer: where each SCRIPT_STAT_* lives in the game state.
const STAT_PATHS := [
	["partner", "stats", "base", "offense"], ["partner", "stats", "base", "defense"],
	["partner", "stats", "base", "speed"], ["partner", "stats", "base", "brains"],
	["partner", "stats", "base", "max_hp"], ["partner", "stats", "base", "max_mp"],
	["partner", "stats", "current", "hp"], ["partner", "stats", "current", "mp"],
	["partner", "care", "tiredness"], ["partner", "care", "happiness"], ["partner", "care", "discipline"],
	["partner", "care", "energy_level"], ["partner", "care", "virus_bar"], ["partner", "care", "remaining_lifetime"],
	["merit"], ["counters", "battles_started"], ["counters", "battles_fled"], ["counters", "tournaments_won"],
	["counters", "tournament_wins"], ["counters", "tournaments_lost"], ["partner", "care", "weight"],
	["tamer", "level"], ["partner", "lives"],
]


func get_stat(stat: int) -> int:
	var node = _stat_parent(stat)
	return _s16(int(node[STAT_PATHS[stat].back()])) if node != null else 0


func set_stat(stat: int, value: int) -> void:
	var node = _stat_parent(stat)
	if node == null:
		return
	var path: Array = STAT_PATHS[stat]
	# Tamer level and lives go through a 16-bit copy into a byte (TMP_TAMER_LEVEL, TMP_LIVES).
	node[path.back()] = value & 0xFF if stat >= 21 else value
	game_state.changed.emit(path[0])


func _stat_parent(stat: int):
	if stat < 0 or stat >= STAT_PATHS.size():
		return null
	var node = game_state.state
	var path: Array = STAT_PATHS[stat]
	for i in path.size() - 1:
		node = node[path[i]]
	return node


## enforceStatsLimits (script_value.c:356): HP / MP at most their max, others at their table cap.
func enforce_stats_limits(stat: int, value: int) -> int:
	var cap := 0
	if stat == 6:
		cap = get_stat(4)
	elif stat == 7:
		cap = get_stat(5)
	else:
		cap = data.script_stat_limit(stat)
	return cap if cap < value else value


## DEAL_DAMAGE: HP -= max HP * percent / 100, keeping at least 1. The damage number over the
## partner (addEntityText) comes with the entity texts.
func deal_damage(percent: int) -> void:
	var damage := get_stat(4) * percent / 100
	var hp := get_stat(6)
	if hp - _s16(damage) < 1:
		damage = hp - 1
	set_stat(6, _s16(hp - damage))


# --- dates (script_interp.c:2514-2560, script_value.c:152) ---------------------------------------------

## dateToSeconds: minutes, with 30-day years.
static func date_to_minutes(year: int, day: int, hour: int, minute: int) -> int:
	return minute + hour * 60 + day * 24 * 60 + year * 30 * 24 * 60


## secondsToDate: [year, day, hour, minute], capped at year 25, day 14, 23:59.
static func minutes_to_date(total: int) -> Array:
	if total >= 255 * 43200:
		total = 59 + 23 * 60 + 14 * 1440 + 25 * 43200
	var minute := total % 60
	total /= 60
	var hour := total % 24
	total /= 24
	return [(total / 30) & 0xFF, total % 30, hour, minute]


## scriptCompareDate (script_value.c:152): sets the trigger when the stored date compares true.
func script_compare_date() -> void:
	var pstat := ctx.next_byte()
	var trigger := _u16()
	var cmp := ctx.next_byte()
	var year := ctx.next_byte()
	var day := ctx.next_byte()
	var hour := ctx.next_byte()
	var minute := ctx.next_byte()
	ctx.pointer += 1
	var now := date_to_minutes(ctx.read_pstat(pstat), ctx.read_pstat(pstat + 1), ctx.read_pstat(pstat + 2), ctx.read_pstat(pstat + 3))
	if compare(cmp, now, date_to_minutes(year, day, hour, minute)) != 0:
		game_state.set_trigger(trigger)
	else:
		game_state.clear_trigger(trigger)


## ADVANCE_TO_DATE_AT (script_interp.c:1227): the hours up to the stored date pass (skipHours),
## then the clock is set to it; a new day runs dailyPStatTrigger.
func advance_to_date_at(pstat: int) -> void:
	var y := ctx.read_pstat(pstat)
	var d := ctx.read_pstat(pstat + 1)
	var h := ctx.read_pstat(pstat + 2)
	var m := ctx.read_pstat(pstat + 3)
	var c: Dictionary = game_state.state["clock"]
	var target := date_to_minutes(y, d, h, m)
	var now := date_to_minutes(int(c["year"]) & 0xFF, int(c["day"]) & 0xFF, int(c["hour"]) & 0xFF, int(c["minute"]) & 0xFF)
	if now < target and care != null:
		care.skip_hours((target - now) / 60)
	var previous_day := int(c["day"])
	c["year"] = y
	c["day"] = d
	c["hour"] = h
	c["minute"] = m
	c["frame"] = h * 1200 + m * 20
	if d != previous_day and clock != null:
		clock.daily_update()
	game_state.changed.emit("clock")


## consumeMapChangeShowName (script_interp.c:860): script value 6 says whether the next script map
## change shows the map name, then is cleared.
func consume_map_change_show_name() -> void:
	match ctx.read_pstat(6):
		0:
			_show_map_name = 1 if ctx.section_is_event == 0 else 0
		1:
			_show_map_name = 1
		2:
			_show_map_name = 0
	game_state.set_script_value(6, 0)


# --- reading ---------------------------------------------------------------------------------------------

func _u16() -> int:
	var v := ctx.u16_at(ctx.pointer)
	ctx.pointer += 2
	return v


## skipOneReadInteger / pollNextInt: lo + (hi << 16), as an int32.
func _s32() -> int:
	var v := _u16() | (_u16() << 16)
	return v - 0x100000000 if v >= 0x80000000 else v


static func _s16(v: int) -> int:
	v &= 0xFFFF
	return v - 0x10000 if v >= 0x8000 else v


static func _s8(v: int) -> int:
	v &= 0xFF
	return v - 0x100 if v >= 0x80 else v


func _partner_type() -> int:
	return data.id_of("digimon/digimon_data", game_state.state["partner"]["digimon"]) if game_state != null else 0


# --- START_BATTLE (script_interp.c:1897-1957; specs/battle.md §2.17) ---------------------------------

## The opcode's head: the counter, the predefined enemies' script ids turned into entity ids, the
## music stopped, the battle started; the script waits for its end (startBattle's call).
func _start_battle() -> int:
	ctx.next_byte()
	var counters: Dictionary = game_state.state["counters"]
	if int(counters["battles_started"]) < COUNTER_MAX:
		counters["battles_started"] = int(counters["battles_started"]) + 1
	if ctx.read_pstat(PSTAT_PREDEFINED) != 0:
		for v in range(0xFB, 0xFE):
			var id := ctx.read_pstat(v)
			if id != 0xFF:
				game_state.set_script_value(v, script_id_to_entity_id(id))
	if sound != null:
		sound.music.stop_bgm()
	battles.start_battle(ctx.talked_to_entity)
	ctx.active_instruction = OP_START_BATTLE
	return STOP


## The opcode's tail: the outcome into script value 0xFF, then by outcome (-1 lost, 0 ran, 1 won).
func _after_battle(outcome: int) -> void:
	game_state.set_script_value(PSTAT_OUTCOME, outcome & 0xFF)
	var counters: Dictionary = game_state.state["counters"]
	match outcome:
		-1:
			# handleItemLoss, a life lost, and script 0's battle-loss section (step 6's scenes).
			if battles.has_method("item_loss"):
				battles.item_loss()
			var p: Dictionary = game_state.state["partner"]
			p["lives"] = int(p["lives"]) - 1
			if int(p["lives"]) == 0:
				p["care"]["remaining_lifetime"] = 0
			ctx.code = load_script(0)
			ctx.code_id = 0
			var at := ScriptFiles.section(ctx.code, SECTION_BATTLE_LOST)
			if at >= 0:
				ctx.pointer = at
			else:
				ctx.is_paused = true
		0:
			# Back to the previous map, without its name (the stack entry {4, 0xff}, longjmp 3).
			if int(counters["battles_fled"]) < COUNTER_MAX:
				counters["battles_fled"] = int(counters["battles_fled"]) + 1
			var world: Dictionary = game_state.state["world"]
			ctx.script_param_1 = int(data.id_of("systems/maps", world["previous_screen"])) if data != null else 0
			ctx.state_2 = int(world["previous_exit"])
			world["previous_exit"] = int(world["exit"])
			_show_map_name = 0
			_push({"type": AFTER_MAP_CHANGE, "arg": 0xFF})
			textboxes.close_all_textboxes()
			game_state.set_script_value(0, ctx.saved_pstat0)
			if tick_map_change.is_valid():
				ctx.map_change = 0x4B
			else:
				_report(OP_START_BATTLE, "map change after running away")
				ctx.stack.clear()
				ctx.is_paused = true
		_:
			if game_state.is_trigger_set(1):
				set_movement_enabled(-1, true)
				textboxes.initialize_textbox()
				return
			# The camera pans back to the tamer: slot 10, type 7, entity 0xFD, speed 10.
			_set_movement(BATTLE_CAMERA_SLOT, MOVE_CAMERA_TO_ENTITY, {"id": ScriptContext.OWNER_TAMER, "speed": 10})
			ctx.active_instruction = OP_WAIT_FOR_ENTITY
			ctx.wait_for_entity_id = BATTLE_CAMERA_SLOT
			textboxes.initialize_textbox()

