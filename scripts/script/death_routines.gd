class_name DeathRoutines
extends MenuRoutines
## Builtins 29 (0x1D, egg selection, DOO2_tickEggInput) and 47 (0x2F, lostAllLives move unlearning).
## Specs: specs/death_reincarnation.md §6.
## Child node of ScriptRoutines (scenes/script/death_routines.tscn).

const EggSelectBox := preload("res://scripts/ui/egg_select_box.gd")

const BUILTIN_EGG_SELECT := 29       # 0x1D
const BUILTIN_LOST_ALL_LIVES := 47   # 0x2F

var routines: Array = [BUILTIN_EGG_SELECT, BUILTIN_LOST_ALL_LIVES]

const SECTION_ALERT := 0x4D8
const LINE_FORGOTTEN_MOVE := 7
const PSTAT_FORGOTTEN_MOVE := 0xF3
const PSTAT_REMAINING_FORGOTTEN := 0xF4

## Selected egg slot (0..3), set by UI in Phase 2 or test scripts.
var selected_egg := 0

var egg_select_box: EggSelectBox


func _ready() -> void:
	egg_select_box = EggSelectBox.new()


func configure(routine_host: ScriptRoutines) -> void:
	super(routine_host)
	if egg_select_box != null:
		egg_select_box.boxes = textboxes.boxes if textboxes != null else null
		egg_select_box.pad = textboxes.pad if textboxes != null else null


func start(routine: int) -> bool:
	match routine:
		BUILTIN_LOST_ALL_LIVES:
			return _start_lost_all_lives()
		BUILTIN_EGG_SELECT:
			return _start_egg_select()
	return false


func tick(routine: int) -> void:
	match routine:
		BUILTIN_LOST_ALL_LIVES:
			_tick_lost_all_lives()
		BUILTIN_EGG_SELECT:
			_tick_egg_select()


# --- Builtin 47: lostAllLives (script_common.c:2456) -------------------------------------------

func _start_lost_all_lives() -> bool:
	var learned: Array = game_state.state["partner"]["learned_moves"]
	var count := learned.size()
	var tamer_level: int = clampi(int(game_state.state["tamer"].get("level", 0)), 0, 10)
	var prod: int = (10 - tamer_level) * 2 * count
	if prod % 100 >= 50:
		prod += 100
	var n: int = prod / 100
	if n == 0 or learned.is_empty():
		ctx.active_instruction = 0
		return false

	ctx.write_pstat(PSTAT_REMAINING_FORGOTTEN, n)
	_unlearn_next_move()
	return true


func _tick_lost_all_lives() -> void:
	if ctx.state_2 == 3:
		var n: int = ctx.read_pstat(PSTAT_REMAINING_FORGOTTEN) - 1
		if n <= 0:
			textboxes.close_all_textboxes()
			ctx.active_instruction = 0
			return
		ctx.write_pstat(PSTAT_REMAINING_FORGOTTEN, n)
		_unlearn_next_move()


func _unlearn_next_move() -> void:
	var learned: Array = game_state.state["partner"]["learned_moves"]
	if learned.is_empty():
		textboxes.close_all_textboxes()
		ctx.active_instruction = 0
		return

	var rand_idx := randi() % learned.size()
	var move_key: String = learned[rand_idx]
	var move_id: int = data.id_of("moves/move_data", move_key)
	game_state.unlearn_move(move_key)
	ctx.write_pstat(PSTAT_FORGOTTEN_MOVE, move_id)
	textboxes.show_maphead_textbox(LINE_FORGOTTEN_MOVE, ScriptContext.OWNER_NONE, 0, SECTION_ALERT)
	_then(3)


# --- Builtin 29: DOO2_tickEggInput (doo2.c:739) ------------------------------------------------

func _start_egg_select() -> bool:
	if egg_select_box == null:
		egg_select_box = EggSelectBox.new(textboxes.boxes if textboxes != null else null,
				textboxes.pad if textboxes != null else null)
	egg_select_box.open(selected_egg)
	return true


func _tick_egg_select() -> void:
	if egg_select_box == null:
		ctx.active_instruction = 0
		return

	egg_select_box.tick()
	if egg_select_box.confirmed:
		selected_egg = egg_select_box.selected_egg
		ctx.active_instruction = 0
