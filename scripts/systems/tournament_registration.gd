class_name TournamentRegistration
extends RefCounted
## Tournament registration field tick (updateTournamentRegistration, main/tournament.c:42).
## Checks daily reminders (0x4D9) and missed tournament notifications (0x4DA), gating map light updates.

signal section_requested(section: int)

## tournament.c:116 callScriptSection(0, 0x4D9, 1)
const SECTION_REMINDER := 0x4D9
## tournament.c:97 callScriptSection(0, 0x4DA, 1)
const SECTION_MISSED := 0x4DA

## trigger.h:827 TRIGGER_TOURNAMENT_REGISTERED
const TRIGGER_REGISTERED := 37
## tournament.c:103 TRIGGER_38
const TRIGGER_REMIND_DAY := 38
## tournament.c:109 TRIGGER_39
const TRIGGER_REMIND_EVENING := 39

## pstat.h:263 PSTAT_TOURNAMENT_DAY
const VALUE_DAY := 2
## pstat.h:265 PSTAT_TOURNAMENT_DIGIMON
const VALUE_DIGIMON := 4

## tournament.c:62 value & 0x80
const TOMORROW_BIT := 0x80
## tournament.c:70 minutes < 0x2D0 (12:00)
const MINUTES_NOON := 720
## tournament.c:102 minutes < 0x4B0 (20:00)
const MINUTES_EVENING := 1200
## tournament.c:74 minutes >= 0x565 (23:01)
const MINUTES_TOO_LATE := 1381

## tournament.c:86 partnerGetState() != 1
const PARTNER_STATE_NORMAL := 1

var script_paused: Callable        # -> bool: IS_SCRIPT_PAUSED != 0
var tamer_state: Callable          # -> int
var partner_state: Callable        # -> int
var partner_type: Callable         # -> int
var boxes_closed: Callable         # -> bool: UI boxes 0-5 all in state 0

var game_state: Node


func _init(p_game_state: Node) -> void:
	game_state = p_game_state


## updateTournamentRegistration (tournament.c:42).
## Returns true on paths where updateMapLightState() is reached; false on early returns.
func tick() -> bool:
	if game_state == null or not game_state.is_trigger_set(TRIGGER_REGISTERED):
		return true

	var clock: Dictionary = game_state.state["clock"]
	var minutes: int = int(clock["minute"]) + int(clock["hour"]) * 60
	var day: int = int(clock["day"])

	# Step 1: partner type != value 4 -> unset 37, return
	var current_partner_type: int = int(partner_type.call()) if partner_type.is_valid() else 0
	var reg_partner_type: int = int(game_state.script_value(VALUE_DIGIMON))
	if current_partner_type != reg_partner_type:
		game_state.clear_trigger(TRIGGER_REGISTERED)
		return false

	# Step 2: value 2 has bit 0x80 (registered for tomorrow) -> return
	var reg_day_value: int = int(game_state.script_value(VALUE_DAY))
	if (reg_day_value & TOMORROW_BIT) != 0:
		return false

	# Step 3: flag = (DAY != value 2)
	var flag: bool = (day != reg_day_value)

	# Step 4: minutes < 720 -> return
	if minutes < MINUTES_NOON:
		return false

	# Step 5: minutes >= 1381 -> flag = 1
	if minutes >= MINUTES_TOO_LATE:
		flag = true

	# Step 6: a script is running (IS_SCRIPT_PAUSED == 0) -> return
	var paused: bool = bool(script_paused.call()) if script_paused.is_valid() else true
	if not paused:
		return false

	# Step 7: tamer state != 0, partner state != 1, or UI boxes 0-5 state != 0 -> return
	var tamer: int = int(tamer_state.call()) if tamer_state.is_valid() else 0
	if tamer != 0:
		return false

	var partner: int = int(partner_state.call()) if partner_state.is_valid() else PARTNER_STATE_NORMAL
	if partner != PARTNER_STATE_NORMAL:
		return false

	var boxes_ok: bool = bool(boxes_closed.call()) if boxes_closed.is_valid() else true
	if not boxes_ok:
		return false

	# Step 8: flag -> callScriptSection(0, 0x4DA, 1), unset 37, return
	if flag:
		section_requested.emit(SECTION_MISSED)
		game_state.clear_trigger(TRIGGER_REGISTERED)
		return false

	# Step 9: minutes < 1200: check/clear trigger 38; else check/clear trigger 39
	if minutes < MINUTES_EVENING:
		if not game_state.is_trigger_set(TRIGGER_REMIND_DAY):
			return false
		game_state.clear_trigger(TRIGGER_REMIND_DAY)
	else:
		if not game_state.is_trigger_set(TRIGGER_REMIND_EVENING):
			return false
		game_state.clear_trigger(TRIGGER_REMIND_EVENING)

	# Step 10: callScriptSection(0, 0x4D9, 1)
	section_requested.emit(SECTION_REMINDER)
	return true
