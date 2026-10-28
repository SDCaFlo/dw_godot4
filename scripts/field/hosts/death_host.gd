class_name DeathHost
extends Node
## Coordinates death cutscenes, lives loss, hospital recovery, and reincarnation
## (specs/death_reincarnation.md; src/murd/murd.c, src/dooa/dooa.c).
##
## Features:
## 1. Iris transition onto partner on life loss / collapse.
## 2. MurdBox presentation with heart blink/loss animation.
## 3. Hospital warp to Centar Clinic (Map 213) or Jijimon's House (Map 205 / 218) with recovery states.
## 4. Partner reincarnation cutscene and sync_bit completion for ScriptInterpreter routines 3, 4, 7, 9.

const MAP_JIJIMON_HOUSE_EARLY := 218   # ROOM08
const MAP_JIJIMON_HOUSE_LATE := 205    # ROOM10
const MAP_CLINIC := 213                # Centar Clinic (Centarumon)

const TRIGGER_JIJIMON_EXTENDED := 0xDC
const TRIGGER_CLINIC_OPEN := 0xD6

const MurdBox := preload("res://scripts/ui/murd_box.gd")
const DeathIris := preload("res://scripts/ui/death_iris.gd")

## Injected field dependencies
var field_map: FieldMap
var camera: Camera3D
var tamer: Tamer
var partner: Partner
var clock: Clock
var fade: Fade
var script_ctx: ScriptContext
var interpreter: ScriptInterpreter
var boxes: UIBoxes
var game_state: Node

var murd_box: MurdBox
var iris: DeathIris

## Active scene execution state
var is_active := false
var scene_phase := 0
var scene_timer := 0
var routine_id := 0


func _init() -> void:
	murd_box = MurdBox.new()
	iris = DeathIris.new()


func configure(p_boxes: UIBoxes, p_fade: Fade, p_tamer: Tamer, p_partner: Partner,
		p_ctx: ScriptContext, p_interp: ScriptInterpreter, p_camera: Camera3D, p_gs: Node = null) -> void:
	boxes = p_boxes
	fade = p_fade
	tamer = p_tamer
	partner = p_partner
	script_ctx = p_ctx
	interpreter = p_interp
	camera = p_camera
	game_state = p_gs if p_gs != null else (p_ctx.game_state if p_ctx != null else null)
	if murd_box != null:
		murd_box.boxes = boxes


## Start MURD or DOOA cutscene for the given routine
func start_scene(routine: int) -> void:
	routine_id = routine
	is_active = true
	scene_phase = 0
	scene_timer = 0

	# Disable camera follow on player during cutscene
	if tamer != null:
		tamer.camera_follow = false

	# Center iris on partner's screen position
	var screen_center := Vector2(0.5, 0.5)
	if camera != null and partner != null:
		var pos_2d := camera.unproject_position(partner.global_position)
		var vp_size := get_viewport().get_visible_rect().size
		if vp_size.x > 0 and vp_size.y > 0:
			screen_center = Vector2(pos_2d.x / vp_size.x, pos_2d.y / vp_size.y)

	match routine:
		ScriptInterpreter.ROUTINE_COLLAPSE, ScriptInterpreter.ROUTINE_BATTLE_LOSS:
			# If 0 lives left, collapse routes to murd with 0 hearts, then dissolution
			# If lives > 0, routes to murd with remaining hearts, then hospital warp
			iris.start_iris_in(screen_center)
			scene_phase = 1
		ScriptInterpreter.ROUTINE_DYING:
			# Natural death: particle dissolution begins
			scene_phase = 10
		ScriptInterpreter.ROUTINE_REBIRTH:
			# Egg hatching into baby
			scene_phase = 20


func tick() -> void:
	if not is_active:
		return

	scene_timer += 1
	match scene_phase:
		# 1: Iris closing in on partner
		1:
			if iris.tick():
				# Phase 2: Open MurdBox
				scene_phase = 2
				scene_timer = 0
				var current_lives: int = int(_get_game_state().state["partner"].get("lives", 0)) if _get_game_state() != null else 0
				murd_box.open(current_lives)
		# 2: MurdBox ticking (heart blinking/fade)
		2:
			murd_box.tick()
			# At frame 60, finish MurdBox and proceed
			if scene_timer >= 60:
				murd_box.close()
				var current_lives: int = int(_get_game_state().state["partner"].get("lives", 0)) if _get_game_state() != null else 0
				if current_lives == 0:
					# 0 lives: dissolve and rebirth sequence
					scene_phase = 10
					scene_timer = 0
				else:
					# Remaining lives: fade to white / black, then warp to recovery map
					scene_phase = 3
					scene_timer = 0
		# 3: Recovery map warp (Centar Clinic or Jijimon's House)
		3:
			_warp_to_recovery_hospital()
			scene_phase = 4
			scene_timer = 0
		# 4: Wait after warp, set sync bit
		4:
			if scene_timer >= 10:
				_finish_scene()

		# 10..15: Reincarnation dissolution cutscene
		10:
			if scene_timer >= 40:
				_warp_to_recovery_hospital()
				scene_phase = 11
				scene_timer = 0
		11:
			if scene_timer >= 10:
				_finish_scene()

		# 20: Rebirth baby hatching
		20:
			if scene_timer >= 20:
				_finish_scene()


func _warp_to_recovery_hospital() -> void:
	var target_map := determine_death_map()
	if tamer != null and tamer.change_map.is_valid():
		tamer.change_map.call(target_map, 1)


func _finish_scene() -> void:
	is_active = false
	if iris != null:
		iris.visible = false
	if tamer != null:
		tamer.camera_follow = true
	# Set script sync bit to release WAIT_FOR_ENTITY in section 0x4DE / script 212
	if script_ctx != null:
		script_ctx.sync_bit = 1


## Selects destination map according to PSX decompilation (murd.c:781, dooa.c:1734):
## If trigger 0xDC (Centarumon clinic) or 0xD6 (Clinic open) is set, or prosperity (pstat 1) >= 50:
##   target = 0xCD (205, Jijimon's House late)
## Else:
##   target = 0xDA (218, Jijimon's House early)
func determine_death_map() -> int:
	var gs := _get_game_state()
	if gs == null:
		return MAP_JIJIMON_HOUSE_EARLY
	var clinic_open: bool = gs.is_trigger_set(TRIGGER_CLINIC_OPEN) or gs.is_trigger_set(TRIGGER_JIJIMON_EXTENDED)
	var prosperity := int(gs.script_value(1))
	if clinic_open or prosperity >= 50:
		return MAP_JIJIMON_HOUSE_LATE
	return MAP_JIJIMON_HOUSE_EARLY


func _get_game_state() -> Node:
	if game_state != null:
		return game_state
	if script_ctx != null and script_ctx.game_state != null:
		return script_ctx.game_state
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	return null
