class_name DeathRoutines
extends MenuRoutines
## Builtins 29 (0x1D, the reincarnation egg panel: DOO2_openEggBox, DOO2_tickEggInput) and 47
## (0x2F, lostAllLives: techniques forgotten after the last life). specs/death_reincarnation.md §6.
## Child node of ScriptRoutines (scenes/script/death_routines.tscn).

const BUILTIN_EGG_SELECT := 29
const BUILTIN_LOST_ALL_LIVES := 47

var routines: Array = [BUILTIN_EGG_SELECT, BUILTIN_LOST_ALL_LIVES]

## showMapHeadTextbox(7, 0xFF, 0, 0x4D8): "{move} has been forgotten!".
const SECTION_ALERT := 0x4D8
const LINE_FORGOTTEN_MOVE := 7
const PSTAT_FORGOTTEN_MOVE := 0xF3
const PSTAT_REMAINING_FORGOTTEN := 0xF4
## DOO2_openEggBox: playSound(8, 4).
const SOUND_OPEN := 4

## The DOOA sequence whose egg slot the panel sets (DOOA_REINCARNATION_SEQ.eggSlot); set by the field.
var dooa: DooaScene
var egg_select_box := EggSelectBox.new()
var _sound: Node


func configure(routine_host: ScriptRoutines) -> void:
	super(routine_host)
	_sound = routine_host.sound
	egg_select_box.boxes = textboxes.boxes if textboxes != null else null
	egg_select_box.pad = textboxes.pad if textboxes != null else null


func start(routine: int) -> bool:
	if routine == BUILTIN_EGG_SELECT:
		_open_egg_box()
	return true


func tick(routine: int) -> void:
	match routine:
		BUILTIN_LOST_ALL_LIVES:
			_lost_all_lives()
		BUILTIN_EGG_SELECT:
			_tick_egg_input()


# --- Builtin 47: lostAllLives (script_common.c:2456) -------------------------------------------

## Step 0: the number to forget, (10 - tamer level) * 2 % of the learnt techniques (the C counts
## hasMove for ids 0-0x39: the moves of category `technique`), rounded; none: the routine ends.
## Step 2: one of them at random (randomLimit over the pool in id order) is unlearnt and named;
## step 3, after ✕: the next one, or the box closes.
func _lost_all_lives() -> void:
	match ctx.state_2:
		0:
			var n := _technique_pool().size()
			n = (10 - int(game_state.state["tamer"]["level"])) * 2 * (n * 100) / 100
			if n % 100 >= 50:
				n += 100
			n /= 100
			if n == 0:
				ctx.active_instruction = 0
				return
			ctx.write_pstat(PSTAT_REMAINING_FORGOTTEN, n)
			ctx.state_2 = 2
		2:
			var pool := _technique_pool()
			if pool.is_empty():
				textboxes.close_all_textboxes()
				ctx.active_instruction = 0
				return
			var move: int = pool[Rng.random_limit(pool.size())]
			game_state.unlearn_move(move)
			ctx.write_pstat(PSTAT_FORGOTTEN_MOVE, move)
			textboxes.show_maphead_textbox(LINE_FORGOTTEN_MOVE, ScriptContext.OWNER_NONE, 0, SECTION_ALERT)
			_then(3)
		3:
			var n: int = ctx.read_pstat(PSTAT_REMAINING_FORGOTTEN) - 1
			if n == 0:
				textboxes.close_all_textboxes()
				ctx.active_instruction = 0
				return
			ctx.write_pstat(PSTAT_REMAINING_FORGOTTEN, n)
			ctx.state_2 = 2


## The learnt techniques' ids, ascending (the C's pool).
func _technique_pool() -> Array:
	var pool := []
	for key in game_state.state["partner"]["learned_moves"]:
		var move: Dictionary = data.move(key)
		if move.get("category") == "technique":
			pool.append(int(move["id"]))
	pool.sort()
	return pool


# --- Builtin 29: DOO2_openEggBox (doo2.c:721), DOO2_tickEggInput (:739) ------------------------

## Egg slot 0, box 3 opens with the eggs, the sounds stop and the panel's sound plays.
func _open_egg_box() -> void:
	if dooa != null:
		dooa.egg_slot = 0
	egg_select_box.open(0)
	if _sound != null:
		_sound.stop_sound()
		_sound.play_sound(8, SOUND_OPEN)


## The panel moves the slot (the box's tick, EggSelectBox); the routine ends once ✕ closed the box.
func _tick_egg_input() -> void:
	if dooa != null:
		dooa.egg_slot = egg_select_box.selected_egg
	if egg_select_box.boxes == null or egg_select_box.boxes.boxes[EggSelectBox.BOX_ID].state == UIBoxes.STATE_CLOSED:
		ctx.active_instruction = 0
