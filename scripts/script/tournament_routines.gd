class_name TournamentRoutines
extends MenuRoutines
## Builtin routines 0x06 (start tournament), 0x12 (the tournament schedule board, with
## TournamentBoard), 0x16 (medal check), 0x21 (Beetle Cup registration). Specs/tournament_entry.md
## §4.6, §4.8, §4.9, §4.10, §5.2.

const START_TOURNAMENT := 0x06
const SCHEDULE := 0x12
const CHECK_MEDALS := 0x16
const REGISTER_BEETLE := 0x21

var routines: Array = [START_TOURNAMENT, SCHEDULE, CHECK_MEDALS, REGISTER_BEETLE]

## setInputRepeatMask(0xf000) while the board is open (dget.c:681): the d-pad repeats.
const BOARD_REPEAT := Pad.DIRECTIONS
## initTournamentSchedule's lines (MAPHEAD 0x4D8): 2 "Do you want to enter?", 3 the over-levelled
## "... is going to enter", 4 "Enter / Don't enter" (dget.c:704-716).
const LINE_ENTER := 2
const LINE_OVERLEVELED := 3
const LINE_CHOICE := 4
## trigger.h:828 TRIGGER_TOURNAMENT_OVERLEVELED.
const TRIGGER_OVERLEVELED := 40
## dget.c:727-728: registered for the next day.
const TOMORROW_BIT := 0x80

## trigger.h:827 TRIGGER_TOURNAMENT_REGISTERED; script_interp.c:1801.
const TRIGGER_REGISTERED := 37
## tournament.c:103; script_interp.c:1802.
const TRIGGER_REMINDER_DAY := 38
## tournament.c:112; script_interp.c:1803.
const TRIGGER_REMINDER_EVENING := 39

## script_interp.c:1804 (DAY != 0x16; calendar day).
const DAY_BEETLE_LAND := 0x16
## script_interp.c:1805 (value 2 if not DAY 0x16).
const DAY_BEETLE_TOMORROW := 0x95

## script_common.c:3026 (unlockMedal: 0x16C + medal).
const TRIGGER_MEDAL_BASE := 0x16C
## script_common.c:3027 (medal < 0x13).
const MEDAL_COUNT := 0x13
## tournament.c:255 (showMapHeadTextbox(result, 0xFF, 0, 0x4DB)).
const SECTION_MEDALS := 0x4DB

## pstat.h:263-265 (script values).
const SCRIPT_VALUE_DAY := 2
const SCRIPT_VALUE_CUP := 3
const SCRIPT_VALUE_PARTNER_TYPE := 4

var cups: TournamentCups
var board: TournamentBoard


func configure(routine_host: ScriptRoutines) -> void:
	super.configure(routine_host)
	cups = TournamentCups.new(game_state, data)
	board = TournamentBoard.new(textboxes, data, game_state)


func start(routine: int) -> bool:
	match routine:
		SCHEDULE:
			# initTournamentSchedule state 0: already registered, nothing (dget.c:668-669).
			return not game_state.is_trigger_set(TRIGGER_REGISTERED)
		REGISTER_BEETLE:
			_start_0x21()
			return false
		CHECK_MEDALS:
			if cups == null or cups.medal_condition() == -1:
				return false
			return true
		START_TOURNAMENT:
			return true
		_:
			return false


func tick(routine: int) -> void:
	match routine:
		SCHEDULE:
			_tick_0x12()
		CHECK_MEDALS:
			_tick_0x16()
		START_TOURNAMENT:
			_tick_0x06()


## initTournamentSchedule (dget.c:664). State 2 waits: the board's tick (box 2) moves it to 3, the
## text boxes move it to SCRIPT_NEXT_STATE_2 (mode 1) or + the choice (mode 2).
func _tick_0x12() -> void:
	match ctx.state_2:
		0:
			var clock: Dictionary = game_state.state["clock"]
			var day := int(clock["day"])
			var minutes := int(clock["minute"]) + int(clock["hour"]) * 60
			game_state.set_script_value(SCRIPT_VALUE_CUP, TournamentCups.EMPTY)
			var table := cups.fill_board(day, minutes, _partner_type())
			textboxes.trigger_box_close_flag(0)
			textboxes.pad.set_repeat_mask(BOARD_REPEAT)
			board.open(table, _owner(), day)
			ctx.state_2 = 2
		1:
			ctx.active_instruction = 0
		2:
			pass
		3:
			textboxes.pad.set_repeat_mask(0)
			textboxes.trigger_box_close_flag(TournamentBoard.GRID_BOX)
			textboxes.trigger_box_close_flag(TournamentBoard.TITLE_BOX)
			var cup: int = game_state.script_value(SCRIPT_VALUE_CUP)
			if cup == TournamentCups.EMPTY:
				ctx.state_2 = 1
				return
			board.open_info(1)
			if cups.is_overleveled(cup, _partner_type()):
				textboxes.show_maphead_textbox(LINE_OVERLEVELED, _owner(), 0, TournamentBoard.SECTION)
				game_state.set_trigger(TRIGGER_OVERLEVELED)
			else:
				textboxes.show_maphead_textbox(LINE_ENTER, _owner(), 0, TournamentBoard.SECTION)
				game_state.clear_trigger(TRIGGER_OVERLEVELED)
			ctx.state_2 = 2
			ctx.next_state_2 = 4
			ctx.textbox_mode = 1
		4:
			textboxes.show_maphead_selection(LINE_CHOICE, ScriptContext.OWNER_TAMER, 2, false, TournamentBoard.SECTION)
			ctx.state_2 = 2
			ctx.next_state_2 = 5
			ctx.textbox_mode = 2
		5:
			textboxes.trigger_box_close_flag(TournamentBoard.INFO_BOX)
			game_state.set_trigger(TRIGGER_REGISTERED)
			game_state.set_trigger(TRIGGER_REMINDER_DAY)
			game_state.set_trigger(TRIGGER_REMINDER_EVENING)
			var value := int(game_state.state["clock"]["day"])
			if board.column != 0:
				value = (value + 1) | TOMORROW_BIT
			game_state.set_script_value(SCRIPT_VALUE_DAY, value)
			game_state.set_script_value(SCRIPT_VALUE_PARTNER_TYPE, _partner_type())
			ctx.state_2 = 1
		6:
			textboxes.trigger_box_close_flag(TournamentBoard.INFO_BOX)
			ctx.state_2 = 1


## script_interp.c:1800-1813 (builtin 0x21: the Beetle Cup registration at Beetle Land).
func _start_0x21() -> void:
	game_state.set_trigger(TRIGGER_REGISTERED)
	game_state.set_trigger(TRIGGER_REMINDER_DAY)
	game_state.set_trigger(TRIGGER_REMINDER_EVENING)
	var day: int = int(game_state.state["clock"]["day"]) if game_state.state.has("clock") else 0
	var day_val: int = DAY_BEETLE_LAND if day == DAY_BEETLE_LAND else DAY_BEETLE_TOMORROW
	game_state.set_script_value(SCRIPT_VALUE_DAY, day_val)
	game_state.set_script_value(SCRIPT_VALUE_CUP, _cup_for_builtin_0x21())
	game_state.set_script_value(SCRIPT_VALUE_PARTNER_TYPE, _partner_type())


func _cup_for_builtin_0x21() -> int:
	if data == null:
		return 0
	for rec in data.records("systems/tournaments"):
		if rec.get("registered_by_builtin_0x21", false):
			return int(rec.get("id", 0))
	return 0


func _partner_type() -> int:
	if game_state == null or not game_state.state.has("partner"):
		return 0
	var partner_ref: String = str(game_state.state["partner"].get("digimon", ""))
	return data.id_of("digimon/digimon_data", partner_ref) if data != null else 0


## scriptCheckTournamentMedal (tournament.c:242-263).
func _tick_0x16() -> void:
	match ctx.state_2:
		0:
			var result := cups.medal_condition()
			if result == -1:
				ctx.active_instruction = 0
				return
			var medal := cups.medal_of(result)
			if medal >= 0 and medal < MEDAL_COUNT:
				game_state.set_trigger(TRIGGER_MEDAL_BASE + medal)
			textboxes.show_maphead_textbox(result, 0xFF, 0, SECTION_MEDALS)
			ctx.state_2 = 1
			ctx.next_state_2 = 0
			ctx.textbox_mode = 1
		1:
			pass


## scriptStartTournament (tournament.c:128-144) and startTournament (utils2.c:577-682).
func _tick_0x06() -> void:
	match ctx.state_2:
		0:
			ctx.state_2 = 2
		1:
			pass
		2:
			textboxes.close_box(0)
			var cup: int = game_state.script_value(SCRIPT_VALUE_CUP)
			var opponents: Array = cups.draw_opponents(cup, _partner_type())
			if host.sound != null and "music" in host.sound and host.sound.music != null:
				host.sound.music.stop_bgm()
			if host.arena == null:
				push_warning("TournamentRoutines: arena is missing")
				cups.finish(game_state.script_value(SCRIPT_VALUE_CUP), 0)
				_reinitialize_after_tournament()
				ctx.active_instruction = 0
				return
			host.arena.finished = false
			host.arena.start(cup, opponents)
			ctx.state_2 = 7
		7:
			if host.arena != null and host.arena.finished:
				var result: int = int(host.arena.result)
				cups.finish(game_state.script_value(SCRIPT_VALUE_CUP), result)
				_reinitialize_after_tournament()
				ctx.active_instruction = 0


## reinitializeAfterTournament (map.c:5445-5455): tamer state 0, partner state 1.
func _reinitialize_after_tournament() -> void:
	if host.interpreter != null:
		if host.interpreter.tamer != null:
			host.interpreter.tamer.set_state(0)
		if host.interpreter.partner != null:
			host.interpreter.partner.set_state(1)
