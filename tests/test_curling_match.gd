extends SceneTree
## Curling's match (CurlingMatch, CurlingAi, CurlingWorld; step C3) against specs/curling.md §2.5-2.8,
## with a fake world. Acceptance checks written by the reviewer from kar.c (frame counts traced through
## KAR_tick's order: KAR_tickMatchState first, then the HUD calls, KAR_checkStonesStopped last); the
## AI's angles and powers come from a model of the C with PsxMath's libgte. Don't change them to make
## the code pass.
##   godot --headless --path . -s res://tests/test_curling_match.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false
var data: Node
var curling: Dictionary


class FakeWorld:
	extends CurlingWorld
	var locations := {0: Vector3i(-400, 0, 1400), 1: Vector3i(0, 0, 1600), 2: Vector3i(0x190, 0, 0x578), 3: Vector3i(0x190, 0, 0x578)}
	var yaws := {0: 0, 1: 0, 2: 0, 3: 0}
	var bones := {}
	var anims: Array = []
	var log: Array = []
	var strings: Array = []
	var colors: Array = []
	var flags: Array = []
	var sounds: Array = []
	var pstats := {0x7A: 0}
	var sync := -1
	var box := 0
	var camera_wait := 0
	var _waited := 0
	var masks := {}

	func location(slot: int) -> Vector3i:
		return locations[slot]

	func set_location_xz(slot: int, x: int, z: int) -> void:
		locations[slot] = Vector3i(x, locations[slot].y, z)

	func yaw(slot: int) -> int:
		return yaws[slot]

	func set_yaw(slot: int, v: int) -> void:
		yaws[slot] = v

	func start_animation(slot: int, id: int) -> void:
		anims.append([slot, id])

	func bone_translation(slot: int, bone: int) -> Vector3i:
		return bones.get(Vector2i(slot, bone), Vector3i.ZERO)

	func camera_move_to(x: int, z: int, speed: int) -> int:
		log.append(["move_to", x, z, speed])
		if _waited < camera_wait:
			_waited += 1
			return 0
		_waited = 0
		return 1

	func camera_move_by_diff(from: Vector3i, to: Vector3i) -> void:
		log.append(["by_diff", from, to])

	func camera_move_by_offset(dx: int, dy: int) -> void:
		log.append(["by_offset", dx, dy])

	func set_map_objects_flag(start: int, count: int, flag: int) -> void:
		flags.append([start, count, flag])

	func box_state() -> int:
		return box

	func create_box(final: Rect2i, start: Rect2i) -> void:
		log.append(["create_box", final, start])
		box = 1

	func remove_box() -> void:
		log.append(["remove_box"])
		box = 0

	func clear_text_area() -> void:
		log.append(["clear_text_area"])

	func draw_string(text: String, x: int, y: int) -> void:
		if text != "":
			strings.append([text, x, y])

	func set_text_color(c: int) -> void:
		colors.append(c)

	func localize(ref: Variant) -> String:
		return "" if ref == null else str(ref["text"]["en_us"])

	func play_sound(bank: int, id: int) -> int:
		sounds.append([bank, id])
		return masks.get(Vector2i(bank, id), 0)

	func stop_sound_mask(mask: int) -> void:
		log.append(["stop_sound", mask])

	func read_pstat(i: int) -> int:
		return pstats.get(i, 0)

	func write_pstat(i: int, v: int) -> void:
		pstats[i] = v

	func set_sync_bit(v: int) -> void:
		sync = v


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	curling = data.curling()
	_start_and_prompt()
	_demo()
	_ready_prompt()
	_stone_choice()
	_aiming()
	_camera_to_stone()
	_power_and_throw()
	_sliding_to_tally()
	_tally()
	_turn_order()
	_end_of_turns()
	_opponent_turn()
	_finish()
	_hint_box()
	_held_stone()
	_sprites()
	_ai()
	data.free()
	print("%s: curling match checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [what, got, want])


func _new() -> Array:
	var w := FakeWorld.new()
	var pad := Pad.new()
	var m := CurlingMatch.new(curling, w, pad)
	return [m, w, pad]


func _tick(m: CurlingMatch, pad: Pad, pressed := 0, held := 0) -> void:
	pad.polled = pressed | held
	pad.polled_previous = held
	m.tamer_tick()


func _wait_all(m: CurlingMatch, row: int) -> void:
	for i in 5:
		m.stones.place(row, i, 0, CurlingStones.STATE_WAITING, Vector3i(-0x2BC if row == 0 else 0x2BC, i * 0xAA - 0x50, 0))


# --- KAR_start, state 0, the yes / no prompt -----------------------------------------------------------

func _start_and_prompt() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	w.pstats[0x7A] = 1
	m.start()
	_eq([m.state, m.opponent, w.sync, m.active], [0, 3, 0, true], "start: state 0, opponent pstat 0x7A + 2, sync bit 0")
	_eq(m.last_stone.state, 0, "start: last_stone is the C's zeroed bss")
	_tick(m, pad)
	_eq(m.state, 1, "state 0 -> 1")
	_eq([w.locations[0], w.locations[3]], [Vector3i(-0x190, 0, 0x578), Vector3i(0x190, 0, 0x578)], "state 0: the spots")
	_eq([w.yaws[0], w.yaws[3]], [0, 0], "state 0: facing up the rink")
	_eq(w.anims, [[0, 0], [3, 0]], "state 0: animation 0")
	_check(w.log.has(["clear_text_area"]), "state 0: clearTextArea")
	_eq(w.flags, [[25, 1, 1], [19, 4, 1], [16, 3, 1], [13, 3, 1]], "ring markers hidden outside states 0xB / 0xD")
	_tick(m, pad)  # hint 0 -> 1: the US string at y 0xDD
	_tick(m, pad)  # hint 1 -> 2 (NULL: nothing), then box 0 opens, hint 3
	_eq(w.strings, [["Start GameExplain Game", 0, 0xDD]], "prompt: one string, at y 0xDD (the NULL draws nothing)")
	_check(w.log.has(["create_box", Rect2i(-130, 42, 262, 59), Rect2i(75, -5, 10, 10)]), "prompt: box 0 opens from (75, -5)")
	_eq(m.hint, 3, "prompt: cursor on Start Game")
	_tick(m, pad, Pad.DOWN)
	_eq([m.hint, w.sounds.back()], [4, [0, 2]], "prompt: down -> Explain Game, sound (0, 2)")
	_tick(m, pad, Pad.UP)
	_eq(m.hint, 3, "prompt: up toggles back")
	_tick(m, pad, Pad.CROSS)
	_eq(w.box, 0, "prompt: confirm closes the box")
	_eq(m.state, 1, "prompt: still state 1 until the box is closed")
	_tick(m, pad)
	_eq([m.state, m.hint], [3, 0], "prompt: Start Game -> state 3")


# --- the explanation round ---------------------------------------------------------------------------------

func _demo() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.start()
	for i in 3:
		_tick(m, pad)
	_tick(m, pad, Pad.DOWN)
	_tick(m, pad, Pad.CROSS)
	w.log.clear()
	_tick(m, pad)
	_eq([m.state, m.hint], [2, 0], "explain -> state 2")
	_check(w.log.has(["clear_text_area"]), "explain: clearTextArea")
	var types := []
	for i in 5:
		types.append(m.stones.rows[0].stones[i].type)
	_eq(types, [0, 1, 2, 3, 3], "explain: setupMatch(1), types min(i, 3)")
	for i in 60:
		_tick(m, pad)
	_eq(m.state, 2, "state 2: 60 frames (timer 360 < 0x169)")
	_tick(m, pad)
	_eq([m.state, m.timer], [4, 0], "state 2 -> 4 on the 61st frame")
	_tick(m, pad)
	var plan: int = m.stones.rows[0].plan_stone
	_eq([m.state, m.hint, m.stones.rows[0].plan_power], [5, 1, 0x7D0], "state 4: hint 1, the demo's power 0x7D0")
	_check(plan >= 0 and plan < 5, "state 4: the demo's stone rand() % 5")
	_eq(m.stones.rows[0].stones[plan].angle, -940, "state 4: the demo's angle ratan2(-0xC1C, 0x190)")


# --- state 3: the ready prompt blinks 48 frames, then 61 frames --------------------------------------------

func _ready_prompt() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var pad: Pad = t[2]
	m.start()
	for i in 3:
		_tick(m, pad)
	_tick(m, pad, Pad.CROSS)
	_tick(m, pad)
	_eq([m.state, m.ready_timer], [3, 1], "state 3, and the ready prompt counted that frame")
	for i in 107:
		_tick(m, pad)
	_eq(m.state, 3, "state 3: 107 more frames")
	_tick(m, pad)
	_eq([m.state, m.timer], [5, 0], "state 3 -> 5 on the 108th: readyTimer reaches 0x30, then 61 frames of +6")


# --- state 5: choosing a stone ----------------------------------------------------------------------------

func _stone_choice() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	_wait_all(m, 1)
	m.stones.place(0, 1, 3, CurlingStones.STATE_WAITING, Vector3i(-0x2BC, 0xAA - 0x50, 0))
	m.state = 5
	m.row = 0
	m.selected = 0
	_tick(m, pad, Pad.DOWN)
	_eq(m.selected, 1, "state 5: down")
	var cursor := m.sprites.filter(func(s: Dictionary) -> bool: return s["u"] == 0 and s["v"] == 0x28)
	_eq(cursor.size(), 1, "state 5: the stone cursor")
	if cursor.size() == 1:
		_eq([cursor[0]["x"], cursor[0]["y"]], [-0x78, 30 - 0x2D], "state 5: cursor at x -0x78, y stone * 30 - 0x2D")
	_tick(m, pad, Pad.DOWN)
	_tick(m, pad, Pad.UP)
	_eq(m.selected, 1, "state 5: down, up")
	w.anims.clear()
	_tick(m, pad, Pad.CROSS)
	var s: CurlingStones.Stone = m.stones.rows[0].stones[1]
	_eq([m.state, m.aim, w.yaws[0], s.state], [6, -0x400, 0, 0], "beginAiming: state 6, aim -0x400, facing 0, the stone held")
	_eq(w.anims, [[0, 0x23]], "beginAiming: the tamer's animation 0x23")
	_eq(s.model, 2, "beginAiming: a pegged stone shows the plain model (row 0: 2)")


# --- state 6: aiming -----------------------------------------------------------------------------------------

func _aiming() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	m.stones.place(0, 0, 0, CurlingStones.STATE_HELD, Vector3i(-400, 0, 1400))
	m.state = 6
	m.aim = -0x400
	_tick(m, pad, Pad.RIGHT)
	for i in 39:
		_tick(m, pad, 0, Pad.RIGHT)
	_eq([m.aim, m.aim_turn, w.yaws[0]], [-394, 35, -630], "aim: right held 40 frames accelerates (+1 a frame) and stops past -0x18F")
	var scrolls := w.log.filter(func(e: Array) -> bool: return e[0] == "by_offset")
	_eq(scrolls.size(), 31, "aim scroll: the camera follows (+8) once |aimTurn| >= 10")
	if scrolls.size() > 0:
		_eq(scrolls[0], ["by_offset", 8, 0], "aim scroll: right moves the camera +8")
	_tick(m, pad)
	_eq(m.aim_turn, 0, "aim: released")
	_tick(m, pad, Pad.LEFT)
	_tick(m, pad, 0, Pad.LEFT)
	_tick(m, pad, 0, Pad.LEFT)
	_eq([m.aim, m.aim_turn, w.yaws[0]], [-400, -3, -624], "aim: left")
	w.anims.clear()
	_tick(m, pad, Pad.CROSS)
	_eq([m.state, w.anims], [7, [[0, 0x24]]], "confirm: beginThrow, animation 0x24")
	m.state = 6
	m.aim = -0x5B6
	_tick(m, pad, Pad.LEFT)
	_eq(m.aim, -0x5B6 - 1, "aim: left turns while aim >= -0x5B6")
	_tick(m, pad, 0, Pad.LEFT)
	_eq(m.aim, -0x5B6 - 1, "aim: and stops below")


# --- state 7: the camera to the stone -------------------------------------------------------------------------

func _camera_to_stone() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	m.stones.place(0, 2, 0, CurlingStones.STATE_HELD, Vector3i(-380, -180, 1350))
	m.state = 7
	m.selected = 2
	m.aim_turn = 5
	w.camera_wait = 2
	_tick(m, pad)
	_tick(m, pad)
	_eq(m.state, 7, "state 7: until the camera arrives")
	_tick(m, pad)
	_eq([m.state, m.aim_turn], [8, 0], "state 7 -> 8")
	_eq(w.log.filter(func(e: Array) -> bool: return e[0] == "move_to"), [["move_to", -380, 1350, 0x14], ["move_to", -380, 1350, 0x14], ["move_to", -380, 1350, 0x14]], "state 7: tickCameraMoveTo(stone x, z, 0x14)")


# --- states 8, 9, 0xA: power, the throw -------------------------------------------------------------------------

func _power_and_throw() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	var s := m.stones.place(0, 1, 0, CurlingStones.STATE_HELD, Vector3i(-380, -180, 1350))
	m.state = 8
	m.selected = 1
	m.aim = -400
	w.yaws[0] = -624
	w.masks[Vector2i(8, 0)] = 0x55
	for i in 9:
		_tick(m, pad)
	_eq([m.state, m.power], [8, 900], "state 8: power +0x64 a frame")
	_tick(m, pad, Pad.CROSS)
	_eq([m.state, m.power, s.angle, s.rotation.y], [9, 1000, -400, -624], "confirm: state 9, the angle is the aim, the stone's spin the tamer's yaw")
	w.anims.clear()
	_tick(m, pad)
	_eq([m.state, s.speed, m.timer, m.slide_sound, m.cam_prev], [0xA, 1600, 0, 0x55, s.pos], "state 9: speed = power + 0x258, the slide sound")
	_eq(w.anims, [[0, 0x25]], "state 9: the throw animation 0x25")
	_eq(w.sounds.back(), [8, 0], "state 9: playSound2(8, 0)")
	for i in 3:
		_tick(m, pad)
	_eq([m.state, s.state], [0xA, CurlingStones.STATE_HELD], "state 0xA: 3 frames")
	_tick(m, pad)
	_eq([m.state, s.state], [0xB, CurlingStones.STATE_ICE], "state 0xA -> 0xB on the 4th: the stone on the ice")
	# The gauge runs out: 30 frames.
	t = _new()
	m = t[0]
	w = t[1]
	pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	m.stones.place(0, 1, 0, CurlingStones.STATE_HELD, Vector3i(-380, -180, 1350))
	m.state = 8
	m.selected = 1
	w.locations[0] = Vector3i(-100, 0, 100)
	for i in 29:
		_tick(m, pad)
	_eq([m.state, m.power], [8, 2900], "state 8: 29 frames")
	_tick(m, pad)
	_eq([m.state, m.power, w.locations[0], w.anims.back()], [6, 0, Vector3i(-0x190, 0, 0x578), [0, 0]], "state 8: at 0xBB8 back to aiming, at the spot, animation 0")


# --- 0xB -> 0xC -> 0xD ----------------------------------------------------------------------------------------------

func _sliding_to_tally() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	_wait_all(m, 1)
	var s := m.stones.place(0, 1, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -0x6B6))
	m.state = 0xB
	m.row = 0
	m.selected = 1
	m.slide_sound = 0x55
	m.cam_prev = Vector3i(0, 0, -1000)
	_tick(m, pad)
	_check(w.log.has(["by_diff", Vector3i(0, 0, -1000), Vector3i(0, 0, -0x6B6)]), "state 0xB: moveCameraByDiff(the last place, the stone)")
	_eq([m.state, m.cam_prev], [0xC, s.pos], "state 0xB -> 0xC when every stone stopped")
	_tick(m, pad)
	_check(w.log.has(["stop_sound", 0x55]), "state 0xC: the slide sound stops")
	_eq([s.ring, m.stones.rows[0].thrown, m.stones.rows[1].thrown], [1, 1, 0], "state 0xC: rings, thrown recounted")
	_eq([m.throw_order[0], m.tally_index, m.tally_last, m.state], [s, 0, -1, 0xD], "state 0xC: registerThrownStone, then 0xD")


# --- KAR_tickScoreTally ------------------------------------------------------------------------------------------------

func _tally_setup() -> Array:
	var t := _new()
	var m: CurlingMatch = t[0]
	m.opponent = 2
	var a := m.stones.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -0x6B6))
	a.ring = 1
	a.prev_ring = 0
	var b := m.stones.place(1, 0, 0, CurlingStones.STATE_ICE, Vector3i(0x190, 0, -0x90E))
	b.ring = 0x13
	b.prev_ring = 0x13
	m.stones.rows[0].thrown = 1
	m.stones.rows[1].thrown = 1
	m.throw_order[0] = b
	m.throw_order[1] = a
	m.tally_index = 1
	m.tally_last = -1
	m.state = 0xD
	t.append(a)
	return t


func _tally() -> void:
	var t := _tally_setup()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	var a: CurlingStones.Stone = t[3]
	for i in 11:
		_tick(m, pad)
	_eq(a.state, 1, "tally: 11 frames before the first blink")
	_tick(m, pad)
	_eq(a.state, 101, "tally: the 12th frame hides it (state + 100)")
	for i in 70:
		_tick(m, pad)
	_eq([a.state, m.state], [1, 0xD], "tally: the 8th toggle on frame 82")
	_tick(m, pad)
	_eq(m.state, 0xF, "tally: frame 83, the unchanged stone adds its points and the tally ends -> 0xF")
	_eq([m.stones.rows[0].score, m.stones.rows[1].score], [2, -2], "tally: GOOD +2, BAD -2")
	_eq(w.sounds, [[8, 5]], "tally: (8, 5) for the new ring, none for the unchanged one")
	_eq(w.log.filter(func(e: Array) -> bool: return e[0] == "move_to"), [["move_to", 0, -0x6B6, 5]], "tally: the camera to the changed stone, speed 5")
	_eq(m.blink, 2, "tally: blink carries over (the C never resets it there)")
	# Skipping with confirm.
	t = _tally_setup()
	m = t[0]
	pad = t[2]
	a = t[3]
	for i in 14:
		_tick(m, pad)
	_eq(a.state, 101, "tally: hidden on frame 14")
	_tick(m, pad, Pad.CROSS)
	_eq([m.state, a.state, m.stones.rows[0].score, m.stones.rows[1].score], [0xF, 1, 2, -2], "tally: confirm recomputes the scores and restores the states")
	_eq([m.blink, m.blinks, m.skip, m.tally_sub], [0, 0, 0, 0], "tally: confirm clears the timers")


# --- 0xF: the turn change -------------------------------------------------------------------------------------------------

func _turn(thrown0: int, thrown1: int, score0: int, score1: int) -> CurlingMatch:
	var t := _new()
	var m: CurlingMatch = t[0]
	var pad: Pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	_wait_all(m, 1)
	for i in thrown0:
		m.stones.place(0, i, 0, CurlingStones.STATE_ICE, Vector3i(-100 * i, 0, -1000))
	for i in thrown1:
		m.stones.place(1, i, 1, CurlingStones.STATE_ICE, Vector3i(100 * i, 0, -1200))
	m.stones.rows[0].thrown = thrown0
	m.stones.rows[1].thrown = thrown1
	m.stones.rows[0].score = score0
	m.stones.rows[1].score = score1
	m.state = 0xF
	m.row = 0
	m.selected = 0
	m.power = 500
	_tick(m, pad)
	return m


func _turn_order() -> void:
	var m := _turn(1, 1, 2, -2)
	_eq([m.state, m.row, m.selected, m.timer, m.power], [0x10, 1, 1, 0, 0], "turn: equal counts, the tamer leads: the opponent")
	var s: CurlingStones.Stone = m.stones.rows[0].stones[0]
	_eq([m.last_stone.pos, m.last_stone.ring, m.last_stone.type], [s.pos, s.ring, s.type], "turn: the tamer's stone copied to last_stone")
	_check(m.last_stone != s, "turn: last_stone is a copy")
	_eq(_turn(2, 2, 1, 3).row, 0, "turn: equal counts, the tamer trails: the tamer")
	_eq(_turn(2, 2, 3, 3).row, 1, "turn: a tie: the opponent")
	_eq(_turn(1, 0, 0, 0).row, 1, "turn: fewer thrown first (opponent)")
	_eq(_turn(1, 2, 0, 5).row, 0, "turn: fewer thrown first (tamer)")
	_eq(_turn(5, 5, 0, 5).row, 1, "turn: both done: row 1")


# --- 0x10: the end of the turns ------------------------------------------------------------------------------------------------

func _end_of_turns() -> void:
	for c in [[4, 2, [8, 7], 8], [2, 2, [8, 8], 7]]:
		var t := _new()
		var m: CurlingMatch = t[0]
		var w: FakeWorld = t[1]
		var pad: Pad = t[2]
		m.opponent = 2
		m.stones.rows[0].thrown = 5
		m.stones.rows[1].thrown = 5
		m.stones.rows[0].score = c[0]
		m.stones.rows[1].score = c[1]
		m.state = 0x10
		_tick(m, pad)
		_eq([m.state, m.hint, m.timer, w.sounds.back()], [0x13, 1, c[3], c[2]], "0x10: all thrown, %d to %d" % [c[0], c[1]])
		_check(w.log.has(["clear_text_area"]), "0x10: clearTextArea")
	for c in [[1, 0x11], [0, 5]]:
		var t := _new()
		var m: CurlingMatch = t[0]
		var pad: Pad = t[2]
		m.opponent = 2
		m.stones.rows[0].thrown = 1
		m.state = 0x10
		m.row = c[0]
		_tick(m, pad)
		_eq(m.state, c[1], "0x10: row %d's turn" % c[0])


# --- 0x11: the opponent's turn ------------------------------------------------------------------------------------------------

func _opponent_turn() -> void:
	for c in [[0, 0, 6], [3, 1, 5], [0, 2, 4]]:
		var t := _new()
		var m: CurlingMatch = t[0]
		var pad: Pad = t[2]
		m.opponent = 2
		_wait_all(m, 1)
		for i in 5:
			m.stones.place(1, i, [0, 1, 2, 3, 0][i], CurlingStones.STATE_WAITING, Vector3i.ZERO)
		m.stones.rows[0].score = c[0]
		m.stones.rows[1].score = c[1]
		m.state = 0x11
		m.row = 1
		m.power = 300
		_tick(m, pad)
		_eq([m.state, m.hint, m.timer, m.power], [0x13, 1, c[2], 0], "0x11: page %d for %d to %d" % [c[2], c[0], c[1]])
		_eq([m.stones.rows[1].plan_stone, m.stones.rows[1].plan_power, m.stones.rows[1].stones[3].angle], [3, 1430, -1108], "0x11: Penguinmon's clear shot at the centre")


# --- 0x13 and KAR_finishMatch ----------------------------------------------------------------------------------------------------

func _finish() -> void:
	for c in [[12, 3, 2], [5, 3, 1], [4, 4, 0], [2, 6, 0]]:
		var t := _new()
		var m: CurlingMatch = t[0]
		var w: FakeWorld = t[1]
		var pad: Pad = t[2]
		m.opponent = 2
		m.active = true
		m.stones.rows[0].score = c[0]
		m.stones.rows[1].score = c[1]
		m.state = 0x13
		m.hint = 0
		m.timer = 8
		_tick(m, pad)
		_eq([m.state, m.active, w.pstats.get(0x79)], [0x14, false, c[2]], "finish %d to %d: pstat 0x79 = %d" % [c[0], c[1], c[2]])
		_eq([w.yaws[2], w.yaws[1], w.yaws[0]], [0x800, 0x800, 0x800], "finish: all face the camera")
		_eq(w.anims, [[0, 2], [1, 2], [2, 2]], "finish: animation 2")
		_eq([w.sync, w.colors.back() if not w.colors.is_empty() else -1], [1, 1], "finish: sync bit, text colour 1")
	var t := _new()
	var m: CurlingMatch = t[0]
	var pad: Pad = t[2]
	m.state = 0x13
	m.hint = 0
	m.timer = 4
	m.power = 300
	_tick(m, pad)
	_eq([m.state, m.timer, m.power], [5, 0, 0], "0x13: a mid-match page -> state 5")


# --- KAR_tickHintBox -----------------------------------------------------------------------------------------------------------------

func _hint_box() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	var pad: Pad = t[2]
	m.opponent = 2
	m.state = 0x13
	m.timer = 4
	m.hint = 1
	_tick(m, pad)
	_check(w.log.has(["create_box", Rect2i(-130, 42, 262, 59), Rect2i(0, 0, 10, 10)]), "hint: box 0 opens from (0, 0) for pages >= 4")
	_eq(m.line_index, 0, "hint: lineIndex 0")
	for i in 4:
		_tick(m, pad)
	var lines: Array = curling["hints"]["penguinmon"]["lines"]
	var want := []
	for n in 4:
		var text := w.localize(lines[0x28 + n])
		if text != "":
			want.append([text, 0, n * 13 + 1])
	_eq(w.strings.slice(0, want.size()), want, "hint: page 4's lines, one a frame, at y n * 13 + 1")
	_eq(w.colors.slice(0, 4), [7, 1, 1, 1], "hint: the name in colour 7, the lines in colour 1")
	_eq(m.line_index, 4, "hint: lineIndex stops at boxes * 4")
	_tick(m, pad, Pad.CROSS)
	_eq([m.hint, w.box, w.sounds.back()], [-1, 0, [0, 3]], "hint: confirm past the last box closes it, sound (0, 3)")
	_tick(m, pad)
	_eq([m.hint, m.state], [0, 5], "hint: closed -> state 5")
	t = _new()
	m = t[0]
	w = t[1]
	pad = t[2]
	m.opponent = 2
	_wait_all(m, 0)
	m.stones.rows[0].plan_stone = 2
	m.state = 5
	m.row = 0
	m.hint = 1
	_tick(m, pad)
	_check(w.log.has(["create_box", Rect2i(-130, 42, 262, 59), Rect2i(0x4B, -5, 10, 10)]), "hint: pages < 4 open from (0x4B, -5)")


# --- KAR_renderScene's held stone ------------------------------------------------------------------------------------------------------

func _held_stone() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	m.opponent = 2
	w.bones[Vector2i(0, 9)] = Vector3i(-380, -300, 1350)
	var s := m.stones.place(0, 1, 0, CurlingStones.STATE_HELD, Vector3i.ZERO)
	s.rotation = Vector3i(1, 2, 3)
	m.row = 0
	m.selected = 1
	m.update_held_stone()
	_eq([s.pos, s.rotation], [Vector3i(-380, -180, 1350), Vector3i.ZERO], "held: the tamer's bone 9 + 0x78 y")
	var p := m.stones.place(1, 0, 0, CurlingStones.STATE_HELD, Vector3i.ZERO)
	p.rotation = Vector3i(0, 0x123, 0)
	m.row = 1
	m.selected = 0
	w.locations[2] = Vector3i(0x190, -7, 0x578)
	m.update_held_stone()
	_eq([p.pos, p.rotation], [Vector3i(0x190 - 0x50, -7, 0x578), Vector3i(0, 0x123, 0)], "held: Penguinmon's location - 0x50 x, rotation kept")
	m.opponent = 3
	w.bones[Vector2i(3, 4)] = Vector3i(0x190, -200, 0x578)
	m.update_held_stone()
	_eq([p.pos, p.rotation], [Vector3i(0x190, -80, 0x578), Vector3i.ZERO], "held: MetalMamemon's bone 4 + 0x78 y")


# --- the HUD's sprites -----------------------------------------------------------------------------------------------------------------------

func _find(m: CurlingMatch, u: int, v: int) -> Array:
	return m.sprites.filter(func(s: Dictionary) -> bool: return s["u"] == u and s["v"] == v)


func _sprites() -> void:
	var t := _new()
	var m: CurlingMatch = t[0]
	var pad: Pad = t[2]
	m.opponent = 3
	_wait_all(m, 0)
	m.stones.place(0, 0, 0, CurlingStones.STATE_HELD, Vector3i(-380, -180, 1350))
	m.stones.rows[0].score = 12
	m.stones.rows[1].score = -2
	m.state = 8
	m.power = 900
	_tick(m, pad)
	var at := func(list: Array) -> Array:
		return list.map(func(s: Dictionary) -> Array: return [s["x"], s["y"], s["clut_x"]])
	_eq(at.call(_find(m, 0x60, 0x18)), [[-0x69, -0x3E, 0x10], [0x68, -0x3E, 0x10]], "score: the ones (2 and |-2 % 10|)")
	_eq(at.call(_find(m, 0x50, 0x18)), [[-0x79, -0x3E, 0x10]], "score: row 0's tens (1)")
	_eq(at.call(_find(m, 0, 0x40)), [[0x58, -0x3E, 0x10]], "score: a negative score's tens is the minus sign")
	_eq(at.call(_find(m, 0x30, 0x18)), [[-41, -0x32, 0x70], [-44, -0x32, 0x70], [-47, -0x32, 0x70], [-50, -0x32, 0x70]], "gauge: power 1000, bars 4..1 at frame x + 3i - 3")
	_eq(at.call(_find(m, 0, 0x18)), [[-0x32, -0x32, 0x70]], "gauge: row 0's frame")
	_eq(_find(m, 0xB0, 0x18).size(), 1, "plates: MetalMamemon's plate 2")
	_eq(_find(m, 0x90, 0x18).size(), 0, "plates: not Penguinmon's")


# --- CurlingAi -----------------------------------------------------------------------------------------------------------------------------------

func _ai_setup(opponent: int, obstacles: Array) -> Array:
	var t := _new()
	var m: CurlingMatch = t[0]
	var w: FakeWorld = t[1]
	m.opponent = opponent
	w.locations[2] = Vector3i(0x190, 0, 0x578)
	w.bones[Vector2i(3, 4)] = Vector3i(0x190, -200, 0x578)
	for i in 5:
		m.stones.place(1, i, [0, 1, 2, 3, 0][i], CurlingStones.STATE_WAITING, Vector3i.ZERO)
	for i in obstacles.size():
		m.stones.place(2, i, 0, CurlingStones.STATE_ICE, obstacles[i])
	return t


func _ai() -> void:
	var m: CurlingMatch = _ai_setup(2, [])[0]
	var ai := m.ai
	_eq(ai.compute_throw_power(2, 30, 0, -0x6A4), 1430, "power: weight 30 to the centre, Penguinmon")
	_eq(ai.compute_throw_power(3, 35, -0x190, -0x8FC), 2342, "power: weight 35, MetalMamemon")
	_eq(ai.compute_throw_power(2, 25, 0x190, -0x8FC), 1384, "power: weight 25 to the BAD ring")
	_eq(ai.find_clear_shot_angle(2, 0, -0x6A4), -1108, "clear shot: Penguinmon, empty ice")
	m = _ai_setup(2, [Vector3i(200, 0, -300)])[0]
	_eq(m.ai.find_clear_shot_angle(2, 0, -0x6A4), -1, "clear shot: Penguinmon, blocked: -1")
	m = _ai_setup(3, [Vector3i(200, 0, -300)])[0]
	_eq(m.ai.find_clear_shot_angle(3, 0, -0x6A4), 931, "clear shot: MetalMamemon, blocked: the angle from the target to the stone")
	m = _ai_setup(3, [Vector3i(200, 0, 1600)])[0]
	_eq(m.ai.find_clear_shot_angle(3, 0, -0x6A4), -1108, "clear shot: a stone behind the thrower doesn't count")
	var bank := CurlingStones.Stone.new()
	bank.pos = Vector3i(100, 0, -1800)
	_eq(m.ai.aim_bank_shot(3, bank, 0x190, -0x8FC), -1381, "bank shot off the left wall")
	_eq(m.ai.find_unused_stone_of_type(3), 3, "findUnusedStoneOfType(3)")
	_eq(m.ai.aim_at_random_stone(m.last_stone), -1108, "aimAtRandomStone: no tamer stone on the ice: the centre")
	# KAR_chooseOpponentShot's branches.
	m = _ai_setup(2, [])[0]
	m.ai.choose(2, m.last_stone)
	_eq([m.stones.rows[1].plan_stone, m.stones.rows[1].plan_power, m.stones.rows[1].stones[3].angle], [3, 1430, -1108], "Penguinmon, clear: plan row 1 (pegged first)")
	m = _ai_setup(2, [Vector3i(200, 0, -300)])[0]
	m.ai.choose(2, m.last_stone)
	_eq([m.stones.rows[1].plan_stone, m.stones.rows[1].plan_power, m.stones.rows[1].stones[1].angle], [1, 0x960, -1108], "Penguinmon, blocked, not trailing: the random stone, power 0x960")
	m = _ai_setup(3, [])[0]
	m.ai.choose(3, m.last_stone)
	_eq([m.stones.rows[1].plan_stone, m.stones.rows[1].plan_power, m.stones.rows[1].stones[3].angle], [3, 1935, -1163], "MetalMamemon's first stone: the GOOD ring on the left")
	m = _ai_setup(3, [Vector3i(0, 0, -600)])[0]
	m.ai.choose(3, m.last_stone)
	_eq([m.stones.rows[1].plan_stone, m.stones.rows[1].plan_power, m.stones.rows[1].stones[3].angle], [3, 1530, -1108], "MetalMamemon's first stone, left blocked: the centre")
