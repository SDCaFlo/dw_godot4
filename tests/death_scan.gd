extends Node
## Plays the death and lives scenes in the real field scene (specs/death_reincarnation.md; the
## autoloads, MAPHEAD 0x4DE, the map change, script 212):
##   godot --headless --fixed-fps 60 --path . res://tests/death_scan.tscn
## Each case starts free on MAYO01, sets up the partner, starts section 0x4DE as its trigger does
## (START_BATTLE's loss, tickSicknessMechanics, tickDeathCondition), presses ✕ for the text boxes and
## waits until the script is over and the tamer free. Prints what happened; exits 1 if a case fails.
## The step 6-2 checks (specs/death_scene.md §7: the look of DOOA, in the two cases that run it) are
## the reviewer's acceptance checks: with DW_STEP_6_2=1 they fail a case, else they print PENDING.

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
## Step 6-2: the checks done this case (name -> true) and the failed ones.
var _seen_62 := {}
var _failed_62: Array[String] = []
var _enforce_62 := OS.get_environment("DW_STEP_6_2") == "1"


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
	_seen_62 = {}
	_failed_62 = []
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
			if case[3] != "battle":
				_track_6_2(death, partner)
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
	var fade: Fade = _field.care_host.fade
	if fade.progress != 0:
		line += ", SCREEN BLACK (fade %d)" % fade.progress
	var ok: bool = partner.visible and tamer.visible and not _field.death_host.iris.visible and _iris_seen and not _early_text 			and fade.progress == 0 and not _field.death_host.darken.visible
	var death_map: String = _screen()
	ok = ok and death_map in ["ROOM08", "ROOM10"]
	if case[3] != "battle":
		_end_6_2(_field.death_host, partner)
		for name in ["centred", "outlines", "shards on the floor", "the baby at the origin"]:
			if not _seen_62.has(name):
				_failed_62.append(name + " (never reached)")
		if not _failed_62.is_empty():
			line += ", 6-2 %s: %s" % ["FAILED" if _enforce_62 else "PENDING", ", ".join(_failed_62)]
			ok = ok and not _enforce_62
	match case[3]:
		"battle":
			ok = ok and int(p["lives"]) == 2
		_:
			# A rebirth: a Fresh Digimon with 3 lives.
			ok = ok and int(p["lives"]) == 3 and str(p["digimon"]) in ["dw1:botamon", "dw1:punimon", "dw1:poyomon", "dw1:yuramon"]
	_finish(line, not ok)


## Step 6-2 (specs/death_scene.md §7), sampled once per DOOA frame.
func _track_6_2(death: DeathHost, partner: Partner) -> void:
	var dooa := death.dooa
	var f := dooa.frame
	if dooa.sequence == DooaScene.DISSOLVE:
		if f == 0x63 and not _seen_62.has("centred"):
			# D11: the camera looks at the partner's centre: it projects to the drawing offset.
			_seen_62["centred"] = true
			var h := int(GameData.digimon(GameState.state["partner"]["digimon"]).get("height", 0))
			var want := Vector2(160, PsxMath.lerp_int(120, 120 + PsxMath.lerp_int(0, 20, 0, 200, h), 50, 100, 99))
			var field_map: FieldMap = _field.map_session.field_map
			var got := FieldMap.unproject(field_map.camera, partner.global_position + Vector3(0, h / 2.0, 0))
			if got.distance_to(want) > 1.5:
				_failed_62.append("centred (the partner at %s, want %s)" % [got, want])
		if f == 0x8D and not _seen_62.has("outlines"):
			_seen_62["outlines"] = true
			var wire: Variant = death.get("wireframe")
			if wire == null or wire.get("share") != 0:
				_failed_62.append("outlines (no wireframe at share 0 at 0x8D)")
		if f == 0x135 and not _seen_62.has("shards on the floor"):
			_seen_62["shards on the floor"] = true
			var shards: Variant = dooa.get("shards")
			var list: Array = shards.get("shards") if shards != null else []
			if list.is_empty() or not list.all(func(x): return x["center"].y == 0):
				_failed_62.append("shards on the floor (%d shards at 0x135)" % list.size())
		if f >= 0x185:
			_check_no_egg(death, "the dialogue")
	elif dooa.sequence == DooaScene.REBIRTH:
		if f >= 0 and f < 100:
			_check_no_egg(death, "rebirth frame %d" % f)
		if f >= 202 and not _seen_62.has("the baby at the origin"):
			_seen_62["the baby at the origin"] = true
			if not partner.visible or partner.position.length() > 0.5:
				_failed_62.append("the baby at the origin (at %s, %s)" % [partner.position, "shown" if partner.visible else "hidden"])


## G: no egg until the rebirth's threshold rises (frame 100); the old stand-in egg never.
func _check_no_egg(death: DeathHost, when: String) -> void:
	if _seen_62.has("egg early"):
		return
	var egg: Variant = death.get("egg")
	var stand_in: Variant = death.get("_egg")
	var shown: bool = (egg != null and egg.visible and int(egg.call("shown_faces")) > 0) 			or (stand_in != null and is_instance_valid(stand_in) and stand_in.visible)
	if shown:
		_seen_62["egg early"] = true
		_failed_62.append("an egg during %s" % when)


## After the rebirth nothing of the scene is left, and the baby isn't squashed.
func _end_6_2(death: DeathHost, partner: Partner) -> void:
	var wire: Variant = death.get("wireframe")
	var egg: Variant = death.get("egg")
	var shards: Variant = death.dooa.get("shards")
	var left := []
	if wire != null and wire.get("share") != 16:
		left.append("wireframe")
	if egg != null and egg.visible:
		left.append("egg")
	if shards != null and not (shards.get("shards") as Array).is_empty():
		left.append("shards")
	if not partner.scale.is_equal_approx(Vector3.ONE):
		left.append("the partner's scale %s" % partner.scale)
	if not left.is_empty():
		_failed_62.append("left after the rebirth: " + ", ".join(left))


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
