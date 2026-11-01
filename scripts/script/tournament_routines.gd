class_name TournamentRoutines
extends MenuRoutines
## Builtin routines 0x06 (start tournament), 0x16 (medal check), 0x21 (Beetle Cup registration)
## and later 0x12 (the tournament schedule board). Specs/tournament_entry.md §4.8, §4.9, §4.10, §5.2.

const START_TOURNAMENT := 0x06
const CHECK_MEDALS := 0x16
const REGISTER_BEETLE := 0x21

var routines: Array = [START_TOURNAMENT, CHECK_MEDALS, REGISTER_BEETLE]

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


func configure(routine_host: ScriptRoutines) -> void:
	super.configure(routine_host)
	cups = TournamentCups.new(game_state, data)


func start(routine: int) -> bool:
	match routine:
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
		CHECK_MEDALS:
			_tick_0x16()
		START_TOURNAMENT:
			_tick_0x06()


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
