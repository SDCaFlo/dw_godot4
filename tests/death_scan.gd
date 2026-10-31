extends Node
## Plays the death and lives scenes in the real field scene (specs/death_reincarnation.md; the
## autoloads, MAPHEAD 0x4DE, the map change, script 212):
##   godot --headless --fixed-fps 60 --path . res://tests/death_scan.tscn
## Each case starts free on MAYO01, sets up the partner, starts section 0x4DE as its trigger does
## (START_BATTLE's loss, tickSicknessMechanics, tickDeathCondition), presses ✕ for the text boxes and
## waits until the script is over and the tamer free. Prints what happened; exits 1 if a case fails.

const START_MAP := "MAYO01"
const TIMEOUT := 4000
## [name, lives before the loss, lifetime, how it starts].
const CASES := [
	["a life lost in battle", 3, 200, "battle"],
	["the last life lost to sickness", 1, 200, "sickness"],
	["the natural death", 2, 0, "natural"],
]

var _field: Node
var _index := -1
## 0 entering the start map, 1 the scene runs.
var _phase := 0
var _start_frame := 0
var _maps: Array = []
var _states: Array = []
var _routines := []
var _unported := []
var _results := []
var _failed := false
var _was_dark := false
var _iris_seen := false
## A dialogue box opened while MURD or DOOA still ran (the script didn't wait for the scene).
var _early_text := false


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	_field.scripts.interpreter.unported.connect(func(_op, what): _unported.append("%s (script %d at %d)" % [what,
			_field.scripts.script_ctx.code_id, _field.scripts.script_ctx.pointer]))
	_next()


func _next() -> void:
	_index += 1
	if _index >= CASES.size():
		for line in _results:
			print(line)
		get_tree().quit(1 if _failed else 0)
		return
	_phase = 0
	_maps = []
	_states = []
	_unported = []
	_was_dark = false
	_iris_seen = false
	_early_text = false
	GameState.new_game("dw1:agumon")
	_field.map_session.partner.load_digimon(GameData, "dw1:agumon")
	_field.map_session.debug_change_map(START_MAP, 0)
	_start_frame = GameLoop.frame_count


func _process(_delta: float) -> void:
	if _index >= CASES.size():
		return
	var case: Array = CASES[_index]
	var tamer: Tamer = _field.map_session.tamer
	var partner: Partner = _field.map_session.partner
	var ctx: ScriptContext = _field.scripts.script_ctx
	var death: DeathHost = _field.death_host
	var frames := GameLoop.frame_count - _start_frame
	if frames > TIMEOUT:
		_finish("%s: stuck on %s (maps %s, tamer %d/%d, partner %d/%d, script paused %s at 0x%02X, MURD %d/%d, DOOA %d/%d)" % [
				case[0], _screen(), _maps, tamer.state, tamer.sub_state, partner.state, partner.sub_state, ctx.is_paused,
				ctx.active_instruction, death.murd.timer, death.murd.phase, death.dooa.frame, death.dooa.phase], true)
		return
	match _phase:
		0:
			if frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if _screen() != START_MAP or not ctx.is_paused or tamer.state != Tamer.STATE_FREE \
					or _field.care_host.fade.in_current <= 0x13:
				return
			_begin(case)
			_start_frame = GameLoop.frame_count
			_phase = 1
		1:
			if _maps.is_empty() or _maps[-1] != _screen():
				_maps.append(_screen())
			var s := "%d/%d" % [tamer.state, partner.state]
			if _states.is_empty() or _states[-1] != s:
				_states.append(s)
			_was_dark = _was_dark or death.dooa.darkness > 0 or death.murd.darkness > 0
			_iris_seen = _iris_seen or death.iris.visible
			var text_open: bool = _field.scripts.textboxes.entries[0].flags & TextBoxes.FLAG_OPEN != 0
			if text_open and (death.murd.active or (death.dooa.sequence == DooaScene.DISSOLVE and death.dooa.frame >= 0)):
				_early_text = true
			# The text boxes; a choice takes its second answer ("I'll keep his name", "Okay").
			if ctx.active_instruction == ScriptContext.OP_SET_SELECTION:
				if frames % 8 == 0:
					GameLoop.press("pad_down")
				elif frames % 8 == 4:
					GameLoop.press("pad_cross")
			elif frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if frames > 60 and ctx.is_paused and tamer.state == Tamer.STATE_FREE and _screen() != START_MAP:
				_check_end(case, frames)


func _begin(case: Array) -> void:
	var p: Dictionary = GameState.state["partner"]
	p["lives"] = case[1]
	p["care"]["remaining_lifetime"] = case[2]
	var interpreter: ScriptInterpreter = _field.scripts.interpreter
	var care: Care = _field.care_host.care
	match case[3]:
		"battle":
			# START_BATTLE lost (script_interp.c:1919): a life less, script 0's section 0x4DE.
			p["lives"] = int(p["lives"]) - 1
			interpreter.call_section(0, 0x4DE)
		"sickness":
			# tickSicknessMechanics (partner_impl.c:1907) after 12 hours sick: a life less, 0x4DE.
			GameState.set_script_value(0xFF, 0)
			p["lives"] = int(p["lives"]) - 1
			care._call_script(Care.SCRIPT_COLLAPSE)
		"natural":
			care.tick_death_condition()


func _check_end(case: Array, frames: int) -> void:
	var p: Dictionary = GameState.state["partner"]
	var partner: Partner = _field.map_session.partner
	var tamer: Tamer = _field.map_session.tamer
	var line := "%s: %d frames, maps %s, tamer / partner states %s, partner %s (%s, %d lives, lifetime %d), dark %s, iris %s%s" % [
			case[0], frames, _maps, _states, p["digimon"], "shown" if partner.visible else "HIDDEN", p["lives"],
			p["care"]["remaining_lifetime"], _was_dark, str(_iris_seen) + (", TEXT DURING THE SCENE" if _early_text else ""),
			", unported: " + ", ".join(_unported) if not _unported.is_empty() else ""]
	var ok: bool = partner.visible and tamer.visible and not _field.death_host.iris.visible and _iris_seen and not _early_text
	var death_map: String = _screen()
	ok = ok and death_map in ["ROOM08", "ROOM10"]
	match case[3]:
		"battle":
			ok = ok and int(p["lives"]) == 2
		_:
			# A rebirth: a Fresh Digimon with 3 lives.
			ok = ok and int(p["lives"]) == 3 and str(p["digimon"]) in ["dw1:botamon", "dw1:punimon", "dw1:poyomon", "dw1:yuramon"]
	_finish(line, not ok)


func _finish(line: String, failed: bool) -> void:
	_results.append(("FAIL " if failed else "ok   ") + line)
	_failed = _failed or failed
	if failed:
		var ctx: ScriptContext = _field.scripts.script_ctx
		ctx.is_paused = true
		ctx.map_change = 0
		ctx.stack.clear()
		_field.scripts.textboxes.close_all_textboxes()
		_field.map_session.tamer.set_state(Tamer.STATE_FREE)
	_next()


func _screen() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
