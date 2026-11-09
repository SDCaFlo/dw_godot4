extends Node
## Curling in the real field scene (specs/curling.md §7, step C4) on FRZL17 (map 136): with pstat 113
## set (the Mojyamon's or ROOM20's script does it) the warp in starts the match by script 131's section
## 0x33 (CALL_DIGIMON_ROUTINE 1: tamer state 12, partner state 11, the script waits on the sync bit);
## the throwers at their spots; the yes / no prompt in UI box 0; Start Game; the tamer picks, aims,
## sets the power and throws; the stone slides with the slide sound; the tally; the opponent
## (Penguinmon, pstat 0x7A = 0) takes its turn with its hint box; back to the tamer's choice.
## Acceptance checks written by the reviewer; don't change them to make the code pass.
##   godot --headless --fixed-fps 60 --path . res://tests/curling_scan.tscn
## Exits 1 if a check fails.

const START_MAP := "FRZL17"
## WARP_TO screen=136 exit=1 (script 206, the Mojyamon's and ROOM20's warps).
const START_EXIT := 1
const TIMEOUT := 9000
const SEED := 3
## Pstat 113: the warp came from the curling's hosts (script 129 section 6, script 191 section 6);
## pstat 122 (0x7A): the opponent, 0 Penguinmon.
const PSTAT_CURLING := 113
const PSTAT_OPPONENT := 0x7A
## The tamer's and the partner's states while curling (callDigimonRoutine 1, partner.c:1146).
const TAMER_CURLING := 12
const PARTNER_IDLE := 11
const LAST_PHASE := 6

var _field: Node
var _phase := 0
var _phase_frame := 0
var _start_frame := 0
var _failed: Array[String] = []
var _reached := 0
var _sounds: Array = []
var _scroll_before := Vector2.ZERO
var _z_before := 0


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	Rng.set_seed(SEED)
	GameState.new_game("dw1:agumon")
	GameState.set_script_value(PSTAT_CURLING, 1)
	GameState.set_script_value(PSTAT_OPPONENT, 0)
	_field.map_session.partner.load_digimon(GameData, "dw1:agumon")
	Sound.played.connect(func(slot: int, value: int, _mask: int) -> void: _sounds.append([slot, value]))
	_field.map_session.debug_change_map(START_MAP, START_EXIT)
	_start_frame = GameLoop.frame_count


func _host() -> CurlingHost:
	return _field.curling_host


func _next(phase: int) -> void:
	_reached = maxi(_reached, phase)
	_phase = phase
	_phase_frame = GameLoop.frame_count


func _process(_delta: float) -> void:
	if _phase < 0 or _field == null:
		return
	var tamer: Tamer = _field.map_session.tamer
	var host := _host()
	var m: CurlingMatch = host.match if host != null else null
	var frames := GameLoop.frame_count - _start_frame
	var in_phase := GameLoop.frame_count - _phase_frame
	if frames > TIMEOUT:
		_fail("stuck in phase %d (tamer state %d, match state %s)" % [_phase, tamer.state, str(m.state) if m != null else "none"])
		_done()
		return
	match _phase:
		0:
			# No button presses: the prompt would take them.
			if _screen() != START_MAP or tamer.state != TAMER_CURLING or m == null:
				if frames > 1500:
					_fail("the match didn't start on arrival (screen %s, tamer state %d)" % [_screen(), tamer.state])
					_done()
				return
			_check(_field.map_session.partner.state == PARTNER_IDLE, "routine 1: the partner's state 11")
			_check(_field.scripts.script_ctx.sync_bit == 0, "routine 1: the script waits on the sync bit")
			_check(m.opponent == 2, "the opponent: slot pstat 0x7A + 2 = 2 (Penguinmon)")
			_check(not GameData.curling_map("dw1:frzl17").is_empty(), "FRZL17 has curling")
			_next(1)
		1:
			var box: UIBoxes.Box = _field.scripts.boxes.boxes[0]
			if m.hint != 3 or box.state != UIBoxes.STATE_OPEN:
				if in_phase > 200:
					_fail("no yes / no prompt (hint %d, box 0 state %d)" % [m.hint, box.state])
					_done()
				return
			var w: CurlingWorld = host.world
			_check(w.location(0).x == -0x190 and w.location(0).z == 0x578, "state 0: the tamer at (-0x190, 0x578): %s" % w.location(0))
			_check(w.location(2).x == 0x190 and w.location(2).z == 0x578, "state 0: Penguinmon at (0x190, 0x578): %s" % w.location(2))
			var drawn := false
			for y in range(0xDD, 0xDD + 12):
				for x in 0x52:
					if _field.scripts.text_area.pixel(x, y) != 0:
						drawn = true
			_check(drawn, "the prompt's string is in the text area at y 0xDD")
			GameLoop.press("pad_cross")
			_next(2)
		2:
			if m.state != 5:
				if in_phase > 400:
					_fail("Start Game didn't reach state 5 (state %d)" % m.state)
					_done()
				return
			_check(m.row == 0, "the tamer throws first")
			GameLoop.press("pad_cross")
			_next(3)
		3:
			if m.state != 6:
				if in_phase > 60:
					_fail("confirm didn't start aiming (state %d)" % m.state)
					_done()
				return
			if in_phase < 3:
				return
			_check(tamer.animation_id() == 0x23, "beginAiming: the tamer's animation 0x23 (%d)" % tamer.animation_id())
			var s: CurlingStones.Stone = m.stones.rows[0].stones[m.selected]
			var bone := tamer.bone_position(9)
			var want := Vector3i(roundi(bone.x), roundi(-bone.y) + 0x78, roundi(-bone.z))
			_check((s.pos - want).abs() <= Vector3i(1, 1, 1), "the held stone at the tamer's bone 9 + 0x78 (%s, want %s)" % [s.pos, want])
			_scroll_before = _field.map_session.field_map.scroll
			GameLoop.press("pad_cross")
			_next(4)
		4:
			if m.state != 8:
				if in_phase > 300:
					_fail("the camera didn't reach the stone (state %d)" % m.state)
					_done()
				return
			_check(_field.map_session.field_map.scroll != _scroll_before, "state 7: the camera moved to the stone")
			if m.power < 0x7D0:
				return
			_sounds.clear()
			GameLoop.press("pad_cross")
			_next(5)
		5:
			var s: CurlingStones.Stone = m.stones.rows[0].stones[m.selected]
			if m.state == 0xB and _z_before == 0:
				_z_before = s.pos.z
				_check(s.state == CurlingStones.STATE_ICE and s.speed > 0, "the stone slides")
				_check(_sounds.has([8, 0]), "the slide sound (playSound2(8, 0))")
				return
			if m.state == 0xB and in_phase < 200:
				return
			# thrown++ is state 0xC's (kar.c:3039), the frame after KAR_checkStonesStopped sets it.
			if _z_before != 0 and m.state >= 0xD:
				_check(m.stones.rows[0].thrown == 1, "one stone thrown")
				_next(6)
			elif in_phase > 2000:
				_fail("the throw didn't end (state %d)" % m.state)
				_done()
		6:
			# The opponent's turn: its hint boxes take ✕; then back to the tamer.
			if m.state == 0x13 and _field.scripts.boxes.boxes[0].state == UIBoxes.STATE_OPEN and in_phase % 8 == 0:
				GameLoop.press("pad_cross")
			if m.stones.rows[1].thrown == 1 and m.row == 0 and m.state == 5:
				_check(m.stones.rows[0].thrown == 1, "the tamer's turn again after the opponent's stone")
				_reached = LAST_PHASE + 1
				_done()
			elif in_phase > 4000:
				_fail("the opponent's turn didn't end (state %d, row %d, thrown %d / %d)" % [m.state, m.row,
						m.stones.rows[0].thrown, m.stones.rows[1].thrown])
				_done()


func _check(ok: bool, what: String) -> void:
	if not ok:
		_failed.append(what)


func _fail(what: String) -> void:
	_failed.append(what)


func _done() -> void:
	_phase = -1
	if _reached <= LAST_PHASE and _failed.is_empty():
		_failed.append("stopped before the end (phase %d)" % _reached)
	for line in _failed:
		print("FAIL: ", line)
	print("%s: curling scan (%s; reached phase %d)" % ["OK" if _failed.is_empty() else "FAILED %d" % _failed.size(), START_MAP, _reached])
	get_tree().quit(1 if not _failed.is_empty() else 0)


func _screen() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
