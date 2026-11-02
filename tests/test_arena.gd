extends SceneTree
## Step 4e-4, the arena (specs/arena.md): the acceptance checks, written from the C by the reviewer.
## The expected values are the spec's §3-4, not the port's: the bracket traces and the participant and
## opponent results come from a transcription of std_main.c:2949-3735 / std_setup.c:279-389 run outside
## the port (reviewer's scratch, 2026-11-01) and were checked by hand on the cases marked so.
## Don't change them to make the code pass; when one looks wrong, report it with the C line.
##   godot --headless --path . -s res://tests/test_arena.gd
## Steps 2-7 are built, so every check runs (DW_STEP_4E_4=<n> still limits them to steps 2..n). Step 1's checks are
## data_porter/tests/test_arena_fields.py and asset_porter/tests/test_arena_assets.py. Exits 1 if a check fails.
##
## Classes are loaded by path, so this file parses before they exist.

const TOURNAMENT := "res://scripts/systems/arena/arena_tournament.gd"
const BRACKET := "res://scripts/systems/arena/arena_bracket.gd"
const ARENA_BATTLE := "res://scripts/systems/arena/arena_battle.gd"
const MATCH := "res://scripts/systems/arena/arena_match.gd"
const CAMERA := "res://scripts/systems/arena/arena_camera.gd"
const SESSION := "res://scripts/systems/arena/arena_session.gd"
## The battle tests' stub world (entities that animate by frames and walk forward).
const BATTLE_TEST := "res://tests/test_battle.gd"

const AGUMON := 3
const METALGREYMON := 12
const OGREMON := 0x22
const LEOMON := 0x30
const ETEMON := 0x2A
const MEGADRAMON := 0x36
const PANJYAMON := 0x3F
const GIGADRAMON := 0x40
const METALETEMON := 0x41
## The 7 drawn opponents of the participant cases (Patamon .. Bakemon, levels 3 3 4 4 4 4 4).
const SEVEN := [0x1F, 0x20, 0x21, 0x22, 0x23, 0x24, 0x25]


## A scripted randomLimit: returns the next value, records the limit it was asked for.
## DG Dimension's run (spec §4.8): test_efe's stub fighters, and a log of the screen_fade hook.
const EFE_TEST := preload("res://tests/test_efe.gd")
class FadeLog extends EFE_TEST.StubContext:
	var handled := false
	var fades: Array = []
	var loads := 0

	func on_load_moves() -> void:
		loads += 1

	func screen_fade(level: int) -> bool:
		fades.append(level)
		return handled


class Rolls:
	var values: Array
	var limits: Array = []
	var bad := false

	func _init(v: Array) -> void:
		values = v.duplicate()

	func roll(limit: int) -> int:
		limits.append(limit)
		if values.is_empty():
			bad = true
			return 0
		var v: int = values.pop_front()
		if v < 0 or v >= limit:
			bad = true
		return v


var _failed := 0
var _checks := 0
var _step := 0
var _pending: Array[String] = []
var data: Node


func _initialize() -> void:
	# Steps 2-7 are built (spec §6): every check runs; DW_STEP_4E_4 can still limit them.
	_step = int(OS.get_environment("DW_STEP_4E_4")) if OS.get_environment("DW_STEP_4E_4").is_valid_int() else 7
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: porter output missing")
		data.free()
		quit(0)
		return
	_eq(data.id_of("digimon/digimon_data", "dw1:agumon"), AGUMON, "Agumon's id")
	_eq(data.id_of("digimon/digimon_data", "dw1:metalgreymon"), METALGREYMON, "MetalGreymon's id")
	_eq(data.id_of("digimon/digimon_data", "dw1:gigadramon"), GIGADRAMON, "Gigadramon's id")

	if _gate(2, "ArenaTournament, ArenaBracket"):
		_test_stand_in()
		_test_participants()
		_test_opponent()
		_test_result()
		_test_bracket_run()
		_test_bracket_intro()
	if _gate(3, "ArenaBattle, ArenaMatch, ArenaCamera"):
		PsxMath.setup(data)
		_test_arena_commands()
		_test_arena_rules()
		_test_arena_damage()
		_test_end_condition()
		_test_timer_and_heal()
		_test_camera()
		_test_whole_match()
	if _gate(4, "ArenaSession, the arena scene"):
		_test_session()
	if _gate(5, "the arena HUD"):
		_test_hud_pieces()
	if _gate(6, "the bracket view and the scenes"):
		_test_bracket_drawn()
		_test_scenes()
		_test_scenes_session()
		_test_bracket_view()
		_test_scene_view()
	if _gate(7, "the effects in the arena"):
		_test_arena_effects()

	data.free()
	var state := "OK" if _failed == 0 else "FAILED %d" % _failed
	if not _pending.is_empty():
		state += "; PENDING (DW_STEP_4E_4=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: arena checks (%d run)" % [state, _checks])
	quit(1 if _failed else 0)


func _gate(step: int, what: String) -> bool:
	if _step >= step:
		return true
	_pending.append("step %d: %s" % [step, what])
	return false


func _check(cond: bool, msg: String) -> void:
	_checks += 1
	if not cond:
		_failed += 1
		print("FAIL: ", msg)


func _eq(got: Variant, want: Variant, msg: String) -> void:
	_check(got == want, "%s: got %s, want %s" % [msg, str(got), str(want)])


func _script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		_check(false, "missing " + path)
		return null
	return load(path)


## Numbers as ints (JSON gives floats), nested arrays too; null stays null.
func _ints(v: Variant) -> Variant:
	if v is Array:
		var out := []
		for x in v:
			out.append(_ints(x))
		return out
	if v is float or v is int:
		return int(v)
	return v


func _tournament(rolls: Rolls) -> Object:
	var s := _script(TOURNAMENT)
	if s == null:
		return null
	var t: Object = s.new(data)
	if rolls != null:
		t.roll = rolls.roll
	return t


# --- step 2: ArenaTournament --------------------------------------------------------------------

func _test_stand_in() -> void:
	# STD_tournamentMain (std_setup.c:530-540), through the Digimon's arena_stand_in.
	var t := _tournament(null)
	if t == null:
		return
	_eq(t.stand_in(GIGADRAMON), MEGADRAMON, "stand-in 0x40")
	_eq(t.stand_in(PANJYAMON), LEOMON, "stand-in 0x3F")
	_eq(t.stand_in(METALETEMON), ETEMON, "stand-in 0x41")
	_eq(t.stand_in(AGUMON), AGUMON, "no stand-in")
	_eq(t.stand_in(MEGADRAMON), MEGADRAMON, "a stand-in fights as itself")


## [rolls, partner, expected] (STD_setupParticipants, std_main.c:3464-3536). Cases 1 and 2 checked by hand.
const PARTICIPANT_CASES := [
	[[5, 0, 1, 2, 3, 4, 5, 6, 10, 90, 10, 90, 10], AGUMON,
		{"player_slot": 5, "participants": [31, 32, 33, 34, 35, 3, 36, 37], "round1": [0, 3, 4, 7],
		 "round2": [0, 7], "opponents": [35, 37, 31]}],
	[[1, 6, 5, 4, 3, 2, 1, 0, 99, 0, 99, 0, 99], AGUMON,
		{"player_slot": 1, "participants": [31, 3, 32, 33, 34, 35, 36, 37], "round1": [1, 2, 5, 6],
		 "round2": [2, 6], "opponents": [31, 32, 36]}],
	[[6, 3, 3, 3, 3, 3, 3, 3, 0, 0, 0, 0, 0], METALGREYMON,
		{"player_slot": 6, "participants": [34, 31, 32, 37, 33, 35, 12, 36], "round1": [0, 2, 4, 6],
		 "round2": [0, 4], "opponents": [36, 33, 34]}],
]


func _test_participants() -> void:
	for c in PARTICIPANT_CASES:
		var rolls := Rolls.new(c[0])
		var t := _tournament(rolls)
		if t == null:
			return
		var seven := SEVEN.duplicate()
		var got: Dictionary = t.setup_participants(c[1], seven)
		var want: Dictionary = c[2]
		for k in want:
			_eq(_ints(got.get(k)), want[k], "participants (slot %d): %s" % [want["player_slot"], k])
		_eq(rolls.limits, [8, 7, 7, 7, 7, 7, 7, 7, 100, 100, 100, 100, 100], "participants: the rolls asked")
		_check(not rolls.bad and rolls.values.is_empty(), "participants: every scripted roll used once, in range")
		_eq(seven, SEVEN, "participants: the input list isn't changed")


## [type, cup, rolls, base] (STD_initializeOpponent, std_setup.c:279-389, US: current = base after the caps).
## Cases 1 and 2 checked by hand.
const OPPONENT_CASES := [
	[AGUMON, 0, [30, 30, 30, 30, 30, 30, 3, 2, 1, 0, 0, 0],
		{"max_hp": 1000, "max_mp": 1000, "offense": 100, "defense": 100, "speed": 100, "brains": 100,
		 "moves": [46, 47, 51, 53]}],
	[METALGREYMON, 2, [0, 60, 30, 0, 0, 60, 12, 0, 5, 1, 11, 2, 10, 3, 9, 4, 8, 6, 7, 0, 9],
		{"max_hp": 6500, "max_mp": 3500, "offense": 650, "defense": 350, "speed": 500, "brains": 650,
		 "moves": [47, 49, 48, 60]}],
	[GIGADRAMON, 22, [60, 60, 60, 60, 60, 60, 12, 11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1, 0, 0, 3],
		{"max_hp": 6125, "max_mp": 6125, "offense": 612, "defense": 612, "speed": 612, "brains": 612,
		 "moves": [46, 47, 48, 59]}],
	# The caps (999 / 9999), every roll 0.
	[GIGADRAMON, 22, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		{"max_hp": 9999, "max_mp": 9999, "offense": 999, "defense": 999, "speed": 999, "brains": 999,
		 "moves": [58, 46, 47, 59]}],
	# Level 4 (x2).
	[OGREMON, 6, [30, 30, 30, 30, 30, 30, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
		{"max_hp": 4000, "max_mp": 4000, "offense": 400, "defense": 400, "speed": 400, "brains": 400,
		 "moves": [56, 46, 47, 57]}],
]


func _test_opponent() -> void:
	for c in OPPONENT_CASES:
		var rolls := Rolls.new(c[2])
		var t := _tournament(rolls)
		if t == null:
			return
		var got: Dictionary = t.initialize_opponent(c[0], c[1])
		var label := "opponent %d cup %d" % [c[0], c[1]]
		var base: Dictionary = got.get("base", {})
		var cur: Dictionary = got.get("current", {})
		for k in c[3]:
			_eq(_ints(base.get(k)), c[3][k], "%s: %s" % [label, k])
		_eq(_ints(cur.get("hp")), c[3]["max_hp"], label + ": current hp = max")
		_eq(_ints(cur.get("mp")), c[3]["max_mp"], label + ": current mp = max")
		_eq(_ints(cur.get("charge_mode")), 0, label + ": charge mode 0")
		_check(not rolls.bad and rolls.values.is_empty(), label + ": every scripted roll used once, in range")
	# The roll order: six stat rolls of 61, the shuffle of the usable list, the self list's shuffle and
	# its dead 1-in-10 roll (Agumon at cup 0: Muscle Charge is the only self technique it can afford).
	var r := Rolls.new([30, 30, 30, 30, 30, 30, 3, 2, 1, 0, 0, 0])
	var t := _tournament(r)
	if t != null:
		t.initialize_opponent(AGUMON, 0)
		_eq(r.limits, [61, 61, 61, 61, 61, 61, 4, 4, 4, 4, 1, 10], "opponent: the rolls asked")


func _test_result() -> void:
	# STD_tournamentMain (std_setup.c:609-613): won -> matches played, else played - 1.
	var s := _script(TOURNAMENT)
	if s == null:
		return
	_eq(s.result(1, 3), 3, "result: three wins")
	_eq(s.result(-1, 1), 0, "result: lost the first")
	_eq(s.result(-1, 2), 1, "result: lost the second")
	_eq(s.result(-1, 3), 2, "result: lost the final")


# --- step 2: ArenaBracket -----------------------------------------------------------------------

## A won tournament: player slot 5, round-1 winners [0, 3, 5, 6], round 2 [3, 6]; brackets shown with
## STD_MATCH_RESULT 0 (the first), then 1, 1 and the champion's bracket (1).
const BRACKET_PLAYER := 5
const BRACKET_ROUND1 := [0, 3, 5, 6]
const BRACKET_ROUND2 := [3, 6]
const BRACKET_RESULTS := [0, 1, 1, 1]
const SLOT_KEYS := ["x", "y", "frame", "row", "facing", "state", "timer", "timer2", "hit", "mode", "loser"]

## [bracket, frame, slot, from, to]
const BRACKET_CHANGES := [[0, 41, 0, 0, 1], [0, 41, 1, 0, 1], [0, 67, 0, 1, 2], [0, 67, 1, 1, 2], [0, 108, 0, 2, 3], [0, 108, 1, 2, 3], [0, 121, 0, 3, 4], [0, 121, 1, 3, 4], [0, 152, 0, 4, 6], [0, 152, 1, 4, 5], [0, 177, 1, 5, 6], [0, 196, 0, 6, 0], [0, 237, 2, 0, 1], [0, 237, 3, 0, 1], [0, 263, 2, 1, 2], [0, 263, 3, 1, 2], [0, 304, 2, 2, 3], [0, 304, 3, 2, 3], [0, 317, 2, 3, 4], [0, 317, 3, 3, 4], [0, 348, 2, 4, 5], [0, 348, 3, 4, 6], [0, 373, 2, 5, 6], [0, 391, 3, 6, 0], [0, 432, 4, 0, 1], [0, 432, 5, 0, 1], [0, 458, 4, 1, 2], [0, 458, 5, 1, 2], [0, 480, 4, 2, 6], [0, 480, 5, 2, 6], [1, 1, 5, 6, 0], [1, 42, 6, 0, 1], [1, 42, 7, 0, 1], [1, 68, 6, 1, 2], [1, 68, 7, 1, 2], [1, 109, 6, 2, 3], [1, 109, 7, 2, 3], [1, 122, 6, 3, 4], [1, 122, 7, 3, 4], [1, 153, 6, 4, 6], [1, 153, 7, 4, 5], [1, 178, 7, 5, 6], [1, 196, 6, 6, 0], [1, 237, 0, 0, 1], [1, 237, 3, 0, 1], [1, 263, 0, 1, 2], [1, 263, 3, 1, 2], [1, 304, 0, 2, 3], [1, 304, 3, 2, 3], [1, 319, 0, 3, 4], [1, 319, 3, 3, 4], [1, 350, 0, 4, 5], [1, 350, 3, 4, 6], [1, 375, 0, 5, 6], [1, 407, 3, 6, 0], [1, 448, 5, 0, 1], [1, 448, 6, 0, 1], [1, 474, 5, 1, 2], [1, 474, 6, 1, 2], [1, 496, 5, 2, 6], [1, 496, 6, 2, 6], [2, 1, 5, 6, 0], [2, 42, 3, 0, 1], [2, 42, 5, 0, 1], [2, 68, 3, 1, 2], [2, 68, 5, 1, 2], [2, 90, 3, 2, 7], [2, 90, 5, 2, 7]]
## [bracket, frames, match, fade, round1, round2, slots [x, y, frame, row, facing, state, timer, timer2, hit, mode, loser]]
const BRACKET_FINALS := [[0, 480, 3, 128, [0, 3, 5, 6], [3, 6], [[-110, 1, 0, 3, 1, 0, 0, 0, 1, 3, 0], [-92, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1], [-61, 27, 3, 1, 1, 6, 24, 0, 1, 3, 1], [-43, 1, 0, 3, 0, 0, 0, 0, 1, 3, 0], [9, 1, 0, 1, 1, 6, 89, 22, 0, 0, 0], [46, 1, 0, 1, 0, 6, 89, 22, 0, 0, 0], [77, 27, 0, 1, 1, 0, 0, 0, 0, 0, 0], [114, 27, 0, 1, 0, 0, 0, 0, 0, 0, 0]]], [1, 496, 6, 128, [0, 3, 5, 6], [3, 5], [[-110, 1, 3, 3, 1, 6, 24, 0, 1, 3, 1], [-92, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1], [-61, 27, 3, 1, 1, 6, 24, 0, 1, 3, 1], [-76, -25, 0, 5, 1, 0, 0, 0, 1, 3, 0], [9, 27, 3, 1, 1, 6, 89, 22, 0, 0, 0], [28, -25, 0, 3, 1, 6, 89, 22, 0, 0, 0], [95, -25, 0, 3, 0, 6, 89, 22, 1, 0, 0], [114, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1]]], [2, 90, 7, 128, [0, 3, 5, 6], [3, 5], [[-110, 1, 3, 3, 1, 6, 24, 0, 1, 3, 1], [-92, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1], [-61, 27, 3, 1, 1, 6, 24, 0, 1, 3, 1], [-76, -51, 0, 5, 1, 7, 0, 22, 1, 0, 0], [9, 27, 3, 1, 1, 6, 89, 22, 0, 0, 0], [61, -51, 0, 5, 0, 7, 0, 22, 0, 0, 0], [95, 1, 3, 3, 0, 6, 89, 22, 1, 0, 0], [114, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1]]], [3, 61, 7, 0, [0, 3, 5, 6], [3, 5], [[-110, 1, 3, 3, 1, 6, 24, 0, 1, 3, 1], [-92, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1], [-61, 27, 3, 1, 1, 6, 24, 0, 1, 3, 1], [-76, -25, 3, 5, 1, 7, 61, 22, 1, 0, 0], [9, 27, 3, 1, 1, 6, 89, 22, 0, 0, 0], [-7, -72, 0, 5, 0, 7, 61, 22, 0, 0, 0], [95, 1, 3, 3, 0, 6, 89, 22, 1, 0, 0], [114, 27, 3, 1, 0, 6, 24, 0, 1, 3, 1]]]]
## per bracket: [frame, bank, id]
const BRACKET_SOUNDS := [[[46, 8, 5], [46, 8, 5], [108, 8, 1], [108, 8, 1], [152, 8, 3], [172, 8, 4], [242, 8, 5], [242, 8, 5], [304, 8, 1], [304, 8, 1], [348, 8, 3], [368, 8, 4], [437, 8, 5], [437, 8, 5]], [[47, 8, 5], [47, 8, 5], [109, 8, 1], [109, 8, 1], [153, 8, 3], [173, 8, 4], [242, 8, 5], [242, 8, 5], [304, 8, 1], [304, 8, 1], [350, 8, 3], [370, 8, 4], [453, 8, 5], [453, 8, 5]], [[47, 8, 5], [47, 8, 5]], []]


func _test_bracket_run() -> void:
	var s := _script(BRACKET)
	if s == null:
		return
	var b: Object = s.new(data, BRACKET_PLAYER, BRACKET_ROUND1.duplicate(), BRACKET_ROUND2.duplicate())
	var heard: Array = []
	var frame_ref := [0]
	b.sound.connect(func(bank: int, id: int) -> void: heard.append([frame_ref[0], bank, id]))
	var changes: Array = []
	for n in BRACKET_RESULTS.size():
		b.begin()
		heard.clear()
		var prev: Array = []
		for sl in b.slots:
			prev.append(int(sl["state"]))
		var f := 0
		while not b.finished:
			f += 1
			frame_ref[0] = f
			b.frame(BRACKET_RESULTS[n])
			for i in 8:
				var st := int(b.slots[i]["state"])
				if st != prev[i]:
					changes.append([n, f, i, prev[i], st])
					prev[i] = st
			if f > 5000:
				_check(false, "bracket %d never finished" % n)
				return
		var want: Array = BRACKET_FINALS[n]
		_eq(f, want[1], "bracket %d: frames until finished" % n)
		_eq(int(b.match), want[2], "bracket %d: match" % n)
		_eq(int(b.fade), want[3], "bracket %d: fade" % n)
		_eq(_ints(b.round1), want[4], "bracket %d: round-1 winners" % n)
		_eq(_ints(b.round2), want[5], "bracket %d: round-2 winners" % n)
		for i in 8:
			var row := []
			for k in SLOT_KEYS:
				row.append(int(b.slots[i][k]))
			_eq(row, want[6][i], "bracket %d: slot %d at the end" % [n, i])
		_eq(heard, BRACKET_SOUNDS[n], "bracket %d: sounds" % n)
	_eq(changes, BRACKET_CHANGES, "bracket: every slot state change (bracket, frame, slot, from, to)")
	_eq(b.projectiles.size(), 0, "bracket: no projectile left")


func _test_bracket_intro() -> void:
	# STD_addBracketIntro / STD_tickBracketIntro (std_main.c:3672-3702).
	var s := _script(BRACKET)
	if s == null:
		return
	var b: Object = s.new(data, BRACKET_PLAYER, BRACKET_ROUND1.duplicate(), BRACKET_ROUND2.duplicate())
	b.begin_intro()
	_eq([b.intro_timer, b.fade, b.intro_overlay, b.intro_title], [0, 0x80, 0x80, 0x80], "intro: start")
	for i in 100:
		b.intro_frame()
	_eq([b.intro_timer, b.fade, b.intro_overlay, b.intro_title], [100, 0x80, 0x80, 0x80], "intro: frame 100")
	for i in 5:
		b.intro_frame()
	_eq([b.intro_timer, b.fade, b.intro_overlay, b.intro_title], [105, 88, 88, 88], "intro: frame 105")
	for i in 16:
		b.intro_frame()
	# STD_tickFrames(0x78) runs 0x79 frames (i <= count, std_main.c:6185).
	_eq([b.intro_timer, b.fade, b.intro_overlay, b.intro_title], [120, 0, 8, 0], "intro: frame 121")


# --- step 3: ArenaBattle, ArenaMatch, ArenaCamera ----------------------------------------------

const GABUMON := 17
const KOROMON := 2
const METEORMON := 0x71
## Heat Laser (5): an area technique with the shared cooldown (MOVE_DATA unk3 & 2); Agumon's anim
## 0x31, Gabumon's 0x2F.
const HEAT_LASER_AGUMON := 0x31
const HEAT_LASER_GABUMON := 0x2F


## The battle tests' stub world (test_battle.gd StubWorld).
func _stub() -> Object:
	var base: Script = load(BATTLE_TEST).StubWorld
	var w: Object = base.new()
	w.data = data
	return w


## Partner Agumon (entity 1), opponent Gabumon (entity 2) 700 units away; the tamer off screen.
func _arena_world(partner := {}, enemy := {}, enemy_type := GABUMON) -> Object:
	var w := _stub()
	var p := {"max_hp": 800, "max_mp": 400, "offense": 300, "defense": 200, "speed": 200, "brains": 150,
			"moves": [0x2E, null, null, 0x35], "moves_prio": [0, 0, 0, 0]}
	p.merge(partner, true)
	var e := {"max_hp": 600, "max_mp": 300, "offense": 150, "defense": 100, "speed": 100, "brains": 100,
			"moves": [0x2E, null, null, null], "moves_prio": [0, 0, 0, 0]}
	e.merge(enemy, true)
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, AGUMON, Vector3i(0, 0, -200), p)
	w.add(2, enemy_type, Vector3i(0, 0, -900), e)
	return w


func _arena_battle(w: Object, camera: Object = null) -> Object:
	var s := _script(ARENA_BATTLE)
	if s == null:
		return null
	var b: Object = s.new(w, null, data)
	b.camera = camera
	b.initialize_combat([1, 2])
	return b


func _camera(w: Object) -> Object:
	var s := _script(CAMERA)
	if s == null:
		return null
	var c: Object = s.new(w, 1)
	c.opponent = 2
	return c


func _test_arena_commands() -> void:
	# STD_initializeCombat (std_main.c:4210-4256): 0xB first, no Run (1) and no Change (7).
	var cases := [[50, [11, 3]], [150, [11, 2, 3]], [250, [11, 4, 2, 3]], [350, [11, 5, 4, 2, 3]],
			[450, [11, 6, 5, 4, 2, 3]]]
	for c in cases:
		var bc := _arena_battle(_arena_world({"brains": c[0]}))
		if bc == null:
			return
		_eq(_ints(bc.available_commands), c[1], "commands at brains %d" % c[0])
		_eq(bc.hovered_command, c[1].size() - 1, "hovered at brains %d" % c[0])
		_eq([bc.current_command, bc.buffered_command], [3, 3], "command at brains %d" % c[0])
	# Brains >= 500: the equipped techniques, slot 2 first (0xA, 9, 8), then Your Call.
	var b := _arena_battle(_arena_world({"brains": 550, "moves": [0x2E, null, 0x2F, 0x35]}))
	_eq(_ints(b.available_commands), [11, 6, 5, 10, 8, 3], "commands at brains 550")
	_eq(b.disable_hitting, false, "STD_DISABLE_HITTING starts 0")
	_eq(b.p2_aoe_timer, 0, "P2_AOE_TIMER starts 0")
	_eq(b.no_escape, false, "FLEE_DISABLED[0] is never read: the opponent pays its MP")


func _scene_log(cam: Object) -> Array:
	var log: Array = []
	cam.scene_requested.connect(func(kind: String) -> void: log.append(kind))
	return log


func _test_arena_rules() -> void:
	# The partner idles when its HP <= its damage buffer (STD_tickPartnerAI).
	var w := _arena_world()
	var b := _arena_battle(w)
	if b == null:
		return
	var f: BattleFighter = b.fighters[0]
	f.set_hp(100)
	f.hp_damage = 100
	b.tick_partner_ai()
	_eq([f.move_range, f.flags], [-1, BattleFighter.BUSY], "partner: HP <= buffer -> idle")
	# Every target the partner picks is the opponent (fighter 1).
	for site in 4:
		f.target = BattleFighter.NO_TARGET
		b._partner_retarget(f, site)
		_eq(f.target, 1, "partner retarget site %d -> 1" % site)

	# A faint (std_main.c:3780-3784, 4350-4355): the win / lose camera if the other one lives,
	# and STD_DISABLE_HITTING.
	w = _arena_world()
	var cam := _camera(w)
	b = _arena_battle(w, cam)
	var scenes := _scene_log(cam)
	b.fighters[0].set_hp(0)
	b.tick_partner_ai()
	_eq(b.disable_hitting, true, "partner faint: hitting disabled")
	_eq(scenes, ["lose"], "partner faint: the lose scene")
	_eq(cam.state, 8, "partner faint: STD_startCameraIntro's state 8")
	w = _arena_world()
	cam = _camera(w)
	b = _arena_battle(w, cam)
	scenes = _scene_log(cam)
	b.fighters[1].set_hp(0)
	b.tick_enemy_ai()
	_eq([b.disable_hitting, scenes], [true, ["win"]], "opponent faint: hitting disabled, the win scene")
	w = _arena_world()
	cam = _camera(w)
	b = _arena_battle(w, cam)
	scenes = _scene_log(cam)
	b.fighters[0].hp_damage = b.fighters[0].hp()
	b.fighters[1].set_hp(0)
	b.tick_enemy_ai()
	_eq([b.disable_hitting, scenes], [true, []], "opponent faint with the partner going down: no scene")

	# The opponent's priorities (std_main.c:4327-4330).
	w = _arena_world()
	b = _arena_battle(w)
	b.tick_enemy_ai()
	_eq(_ints(w.stats(2)["base"]["moves_prio"]), [30, 30, 30, 0], "opponent priorities 30 30 30 0")

	# STD_applyPartnerStatsToFighter: 0 once hitting is disabled; no level-under-3 rule.
	w = _arena_world({"speed": 100}, {"speed": 999}, KOROMON)
	b = _arena_battle(w)
	var acc := int(data.move(2)["accuracy"])
	var x := acc / 2 * (999 - 100 / 10) / 999
	_eq(b.hit_chance(1, b.fighters[1], 2), clampi(acc - x, 0, 100), "hit chance: a level-2 defender by the formula")
	b.disable_hitting = true
	_eq(b.hit_chance(1, b.fighters[1], 2), 0, "hit chance: 0 when hitting is disabled")

	# STD_tickDigimonSenile (std_main.c:4860): idles, clears SENILE | TRANSFORMING at 0.
	w = _arena_world()
	b = _arena_battle(w)
	f = b.fighters[0]
	f.flags |= BattleFighter.SENILE | BattleFighter.BUSY
	f.senile_timer = 3
	b.tick_senile_state(f)
	b.tick_senile_state(f)
	_check(w.animation_id(1) in [0x21, 0x22], "senile: idles (not the distracted 0x13)")
	_eq(f.senile_timer, 1, "senile: timer")
	b.tick_senile_state(f)
	_eq(f.flags & (BattleFighter.SENILE | BattleFighter.BUSY), 0, "senile: cleared at 0")

	# STD_tickDigimonAttackRanged (5104): past 100 frames it idles, past 160 it gives up.
	w = _arena_world()
	b = _arena_battle(w)
	f = b.fighters[1]
	f.flags |= BattleFighter.BUSY
	f.band_frames = 101
	b.tick_ranged_attack(f, 0, 2)
	_eq([f.band_frames, f.flags & BattleFighter.BUSY], [102, BattleFighter.BUSY], "ranged: idling past 100")
	f.band_frames = 160
	b.tick_ranged_attack(f, 0, 2)
	_eq([f.band_frames, f.flags & BattleFighter.BUSY], [0, 0], "ranged: gives up past 160")

	# STD_selectMoveTarget (6660) and STD_startQueuedMove's two timers (6644-6650).
	w = _arena_world({"moves": [HEAT_LASER_AGUMON, null, null, 0x35]}, {"moves": [HEAT_LASER_GABUMON, null, null, null]})
	b = _arena_battle(w)
	var p: BattleFighter = b.fighters[0]
	var o: BattleFighter = b.fighters[1]
	p.queued_anim = HEAT_LASER_AGUMON
	o.queued_anim = HEAT_LASER_GABUMON
	_eq([b.is_move_on_cooldown(p), b.is_move_on_cooldown(o)], [false, false], "area lock: none")
	b.shared_cooldown = 5
	_eq([b.is_move_on_cooldown(p), b.is_move_on_cooldown(o)], [true, false], "area lock: the partner's timer")
	b.shared_cooldown = 0
	b.p2_aoe_timer = 5
	_eq([b.is_move_on_cooldown(p), b.is_move_on_cooldown(o)], [false, true], "area lock: the opponent's timer")
	b.p2_aoe_timer = 0
	p.flags |= BattleFighter.ATTACKING
	w.start_animation(1, HEAT_LASER_AGUMON)
	_eq(b.is_move_on_cooldown(o), true, "area lock: the other fighter's area technique runs")
	p.flags &= ~BattleFighter.ATTACKING
	w.start_animation(1, 0x21)
	b.start_queued_move(o, 0)
	_eq([b.p2_aoe_timer, b.shared_cooldown], [0x6E, 0], "opponent's area technique: P2_AOE_TIMER 0x6E")
	b.tick_fighter_states()
	_eq(b.p2_aoe_timer, 0x6D, "STD_tickBattle counts P2_AOE_TIMER down")

	# STD_updateFighterStatusVisuals: the confusion ends on the other fighter.
	w = _arena_world()
	b = _arena_battle(w)
	for i in 2:
		var g: BattleFighter = b.fighters[i]
		g.flags |= BattleFighter.CONFUSED
		g.target = BattleFighter.NO_TARGET
		b.clear_confusion(g)
		_eq([g.target, g.flags & BattleFighter.CONFUSED], [1 - i, 0], "confusion ends: fighter %d targets %d" % [i, 1 - i])

	# STD_selectEnemyMove keeps the charge mode when nothing is usable.
	w = _arena_world({}, {"moves": [null, null, null, null]})
	b = _arena_battle(w)
	b.fighters[1].set_charge_mode(1)
	b.select_enemy_move(b.fighters[1], 1)
	_eq(b.fighters[1].charge_mode(), 1, "no usable technique: charge mode kept")
	# STD_selectPartnerMove's MP weights index keys[keys[i]] (6474).
	_eq(b._mp_weight_slot([2, 0, 1], 0), 1, "the MP weight slot: keys[keys[i]]")

	# No 0x71 scale back after the flatten (STD_applyMoveResult).
	w = _arena_world({}, {}, METEORMON)
	b = _arena_battle(w)
	f = b.fighters[1]
	f.flags |= BattleFighter.FLATTENED
	f.flat_timer = 1
	b.tick_status_effects()
	_eq(w.entities[2]["scale"], Vector3i(0x1000, 0x1000, 0x1000), "flatten ends: 0x71 stays at 0x1000")


func _test_arena_damage() -> void:
	# STD_renderFighterStatusBars (std_hud.c:1016): both fighters drain every frame; MP floor 0.
	var w := _arena_world()
	var b := _arena_battle(w)
	if b == null:
		return
	b.fighters[0].hp_damage = 50
	b.fighters[1].hp_damage = 50
	b.fighters[1].set_mp(10)
	b.fighters[1].mp_damage = 30
	b.bar_timers[1] = 0xFF
	b.apply_damage_buffers()
	_eq([b.fighters[0].hp(), b.fighters[0].hp_damage], [793, 43], "partner drains")
	_eq([b.fighters[1].hp(), b.fighters[1].hp_damage], [593, 43], "opponent drains (no bar gate)")
	_eq([b.fighters[1].mp(), b.fighters[1].mp_damage], [0, 0], "opponent MP floored at 0")


## `with_effects`: a real EffectHost (the techniques' effects make the hits; without one nothing hits).
func _match(w: Object, with_effects := false) -> Object:
	var s := _script(MATCH)
	if s == null:
		return null
	var cam := _camera(w)
	return s.new(w, EffectHost.new(w) if with_effects else null, data, cam)


func _faint(w: Object, id: int, done: bool) -> void:
	w.start_animation(id, 0x2B)
	w.set_animation_playing(id, not done)


func _test_end_condition() -> void:
	# STD_checkEndCondition (std_main.c:4038-4103), US: nothing while a damage buffer is non-zero.
	var w := _arena_world()
	var m := _match(w)
	if m == null:
		return
	m.begin_fight(1, 2)
	var b: Object = m.battle
	_eq(m.check_end_condition(), 0, "end: both fighting")
	b.fighters[0].hp_damage = 5
	_faint(w, 2, true)
	b.fighters[1].set_hp(0)
	_eq(m.check_end_condition(), 0, "end: a damage buffer -> 0")
	b.fighters[0].hp_damage = 0
	_eq(m.check_end_condition(), 1, "end: the opponent down -> 1")
	b.fighters[0].set_hp(0)
	_faint(w, 1, true)
	_eq(m.check_end_condition(), 2, "end: both down -> 2")
	w = _arena_world()
	m = _match(w)
	m.begin_fight(1, 2)
	_faint(w, 1, true)
	_eq(m.check_end_condition(), -1, "end: the partner down, the opponent standing -> -1")
	m.battle.fighters[1].set_hp(0)
	_faint(w, 2, false)
	_eq(m.check_end_condition(), 0, "end: both down, the opponent still falling -> 0")
	# The time-out: the damage taken decides.
	for c in [[300, 100, -1], [100, 300, 1], [200, 200, 2]]:
		w = _arena_world()
		m = _match(w)
		m.begin_fight(1, 2)
		m.timer = 0
		m.battle.fighters[0].set_hp(800 - c[0])
		m.battle.fighters[1].set_hp(600 - c[1])
		_eq(m.check_end_condition(), c[2], "time-out: damage %d vs %d" % [c[0], c[1]])
		_eq(_ints(m.damage), [c[0], c[1]], "time-out: STD_DAMAGE")


func _test_timer_and_heal() -> void:
	# STD_tickFighterCounter (2920): BATTLE_FRAME_COUNT +1 a frame while active, the timer -1 every 20.
	var w := _arena_world()
	var m := _match(w)
	if m == null:
		return
	m.begin_fight(1, 2)
	_eq(m.timer, 99, "timer starts at 99 (STD_addFighterCounter(0x63))")
	m.timer_active = true
	m.battle.frame_count = 1
	for i in 19:
		m.tick_fighter_counter()
	_eq([m.battle.frame_count, m.timer], [20, 98], "timer: -1 at frame 20")
	w.start_animation(2, 0x2B)
	for i in 20:
		m.tick_fighter_counter()
	_eq(m.timer, 98, "timer: held while a fighter faints")
	# STD_deinitializeCombat (4574-4590): the stats back, +1/5 HP and MP, capped; the charge mode.
	w = _arena_world()
	m = _match(w)
	m.begin_fight(1, 2)
	var p: BattleFighter = m.battle.fighters[0]
	p.base()["offense"] = 500
	p.set_hp(100)
	p.set_mp(390)
	p.set_charge_mode(2)
	_eq(m.deinitialize(0, 1), 1, "deinitialize: the partner won")
	_eq([int(p.base()["offense"]), p.hp(), p.mp(), p.charge_mode()], [300, 260, 400, 0], "after a match")


func _test_camera() -> void:
	var w := _arena_world()
	var c := _camera(w)
	if c == null:
		return
	# STD_setCameraOrbit (2224): partner b = (0, 0, -200), opponent a = (300, 0, -900).
	w.entities[2]["location"] = Vector3i(300, 0, -900)
	c.min_distance = 1000
	c.set_camera_orbit()
	var dist := int(sqrt(300 * 300 + 700 * 700))
	var d := dist * 500 / 200
	_eq(c.translation, Vector3i(150 + d * -700 / dist, -1000, -200 - 350 - d * 300 / dist), "orbit: translation")
	_eq(c.rotation, Vector3i(PsxMath.atan(d, -700) + 0x800, 0x1000 - PsxMath.atan(300, -700) + 0x800, 0), "orbit: rotation")
	_eq(c.close, false, "orbit: not close")
	# STD_setCameraYXZ (2266): over the midpoint, 0x1F40 up, looking down.
	c.set_camera_yxz()
	_eq([c.translation, c.rotation], [Vector3i(150, -0x1F40, -550), Vector3i(-0x400, 0, 0)], "top-down camera")
	# STD_setChampionCamera (2526): Agumon's radius / height.
	var ag: Dictionary = data.digimon(AGUMON)
	c.set_champion_camera()
	_eq([c.state, c.eye, c.ref, c.viewport_distance], [11, Vector3i(0, -0xC8, -(int(ag["radius"]) * 2 + 0x320)),
			Vector3i(0, -int(ag["height"]) * 2 / 3, 0), 0x200], "champion camera")
	# State 10 (STD_applyRotatingCamera) turns 2 a frame (no pad 2 in the port).
	c.state = 10
	c.rotation = Vector3i(0, 0xFFF, 0)
	c.tick()
	_eq(c.rotation.y, 1, "rotating camera: +2, masked")
	# STD_setRandomViewpoint does nothing in state 7.
	c.state = 7
	for i in 30:
		c.set_random_viewpoint(1, 2)
	_eq(c.state, 7, "random viewpoint: never from state 7")


func _test_whole_match() -> void:
	# A whole match on the stub world (X pressed now and then skips the intros), to DONE.
	Rng.set_seed(4)
	var w := _arena_world({"offense": 900, "max_hp": 2000}, {"max_hp": 100})
	var m := _match(w, true)
	if m == null:
		return
	m.begin(1, 2, 0)
	var n := 0
	while not m.is_done() and n < 20000:
		m.frame(Pad.CONFIRM if n % 10 == 0 else 0)
		w.advance()
		n += 1
	_check(m.is_done(), "whole match: ends (%d frames)" % n)
	_eq(m.result, 1, "whole match: the strong partner wins")
	# Without the effects nothing hits: the timer runs out on equal damage, a draw, which loses.
	Rng.set_seed(4)
	w = _arena_world({"offense": 900, "max_hp": 2000}, {"max_hp": 100})
	m = _match(w)
	m.begin(1, 2, 0)
	n = 0
	while not m.is_done() and n < 20000:
		m.frame(Pad.CONFIRM if n % 10 == 0 else 0)
		w.advance()
		n += 1
	_eq([m.is_done(), m.timer, m.is_draw, m.result], [true, 0, true, -1], "whole match: a time-out draw loses")
	# No ✕ at all and the partner's moves as technique keys, as GameState holds them (specs/game_state.md):
	# the intro walk ends on the first technique's pose (STD_tickCameraChase, 2695-2700), which the
	# camera must find from the key; the match reaches the fight on its own.
	Rng.set_seed(4)
	var key: String = data.key_of("moves/move_data", 2)
	w = _arena_world({"moves": [key, null, null, null]})
	m = _match(w, true)
	m.begin(1, 2, 0)
	n = 0
	while m.phase != m.Phase.FIGHT and n < 3000:
		m.frame(0)
		w.advance()
		n += 1
	_check(m.phase == m.Phase.FIGHT, "no presses, key moves: the intros end and the fight starts (%d frames)" % n)


# --- step 4: ArenaSession (STD_tournamentMain) -------------------------------------------------

## A stub tournament: the partner (entity 1) and the opponents spawned into slots 0-2 (entities
## 2-4, STD_initializeOpponent's ENTITY_TABLE[slot + 2]) with the stats ArenaTournament made.
class TournamentStub:
	var w: Object
	var spawned: Array = []
	var removed := 0
	var fades: Array = []

	func spawn(slot: int, type: int, stats: Dictionary) -> int:
		var e := slot + 2
		w.add(e, type, Vector3i(0, 0, -900), stats["base"])
		w.stats(e)["current"].merge(stats["current"], true)
		spawned.append([slot, type])
		return e

	func remove() -> void:
		removed += 1
		for e in [2, 3, 4]:
			w.entities.erase(e)

	func fade(kind: String, frames: int) -> void:
		fades.append([kind, frames])


func _session(w: Object, stub: TournamentStub) -> Object:
	var s := _script(SESSION)
	if s == null or not s.can_instantiate():
		_check(false, "ArenaSession doesn't load")
		return null
	var cam := _camera(w)
	var session: Object = s.new(w, EffectHost.new(w), data, cam)
	session.spawn_opponent = stub.spawn
	session.remove_opponents = stub.remove
	session.fader = stub.fade
	return session


func _run_session(session: Object, w: Object, limit: int) -> int:
	var n := 0
	while not session.is_done() and n < limit:
		session.frame(Pad.CONFIRM if n % 10 == 0 else 0)
		w.advance()
		n += 1
	return n


func _test_session() -> void:
	# The opening (std_setup.c:541-556): fadeToBlack(5), STD_tickFrames(5) (6 frames), then
	# fadeFromBlack(5) and the bracket intro for STD_tickFrames(0x78) (0x79 frames).
	Rng.set_seed(7)
	var w := _stub()
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, AGUMON, Vector3i(0, 0, 0), {"max_hp": 9999, "max_mp": 400, "offense": 999, "defense": 999,
			"speed": 999, "brains": 150, "moves": [0x2E, null, null, 0x35], "moves_prio": [0, 0, 0, 0]})
	var stub := TournamentStub.new()
	stub.w = w
	var session := _session(w, stub)
	if session == null:
		return
	# Grade D (cup 0); the seven drawn: Gigadramon (stand-in Megadramon) and six Rookies.
	session.begin(0, [GIGADRAMON, 0x1F, 0x20, 0x03, 0x11, 0x1F, 0x20], 0)
	var n := 0
	while session.phase != session.Phase.BRACKET and n < 400:
		session.frame(0)
		w.advance()
		n += 1
	# The phase turns BRACKET in the call that runs the bracket's first frame: after 6 + 0x79 = 127.
	_eq(n, 128, "tournament: the bracket's first frame is the 128th")
	_eq(stub.fades.slice(0, 2), [["out", 5], ["in", 5]], "tournament: fade out 5, fade in 5")
	_eq(int(session.bracket.player_slot), int(session.participants["player_slot"]), "tournament: the bracket's player slot")
	_check(not w.is_on_map(1), "tournament: the partner hidden under the bracket (STD_addBracket)")
	var played := _run_session(session, w, 60000)
	_check(session.is_done(), "tournament: ends (%d frames)" % played)
	_eq(session.result, 3, "tournament: a strong partner wins all three (result 3)")
	_eq(stub.spawned.size(), 3, "tournament: three opponents")
	var want: Array = []
	for i in 3:
		want.append([i, session.tournament.stand_in(int(session.participants["opponents"][i]))])
	_eq(stub.spawned, want, "tournament: opponent i in slot i, as its stand-in")
	_check(not GIGADRAMON in stub.spawned.map(func(x: Array) -> int: return x[1]), "tournament: Gigadramon never fights as itself")
	_eq(stub.removed, 3, "tournament: removeMapEntities after each match")
	_check(session.champion_done, "tournament: the champion scene ran")
	_check(["out", 1] in stub.fades, "tournament: STD_deinitializeTournament's fadeToBlack(1)")

	# A weak partner loses its first match: result 0, no champion.
	Rng.set_seed(7)
	w = _stub()
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, AGUMON, Vector3i(0, 0, 0), {"max_hp": 10, "max_mp": 0, "offense": 1, "defense": 1, "speed": 1,
			"brains": 1, "moves": [0x2E, null, null, null], "moves_prio": [0, 0, 0, 0]})
	stub = TournamentStub.new()
	stub.w = w
	session = _session(w, stub)
	session.begin(4, [0x2A, 0x2A, 0x2A, 0x2A, 0x2A, 0x2A, 0x2A], 0)
	played = _run_session(session, w, 60000)
	_check(session.is_done(), "tournament lost: ends (%d frames)" % played)
	_eq([session.result, stub.spawned.size(), session.champion_done], [0, 1, false], "tournament lost: result 0, one match")


# --- step 5: the arena's HUD (specs/arena.md §4.6) ---------------------------------------------
# Each arena piece lists what it draws this frame in `prims`, in drawing order (the ordering table's
# layers back to front, a layer's primitives in reverse of the C's AddPrim): {"image", "palette",
# "uv": Rect2i, "pts": [4 points, C order: top-left, top-right, bottom-left, bottom-right]} for a
# POLY_FT4, {"fill": Color, "rect": Rect2i} for a POLY_F4 / GsBOXF.

const HUD_SCENE := "res://scenes/arena/arena_hud.tscn"


## A POLY_FT4's corners as a rect (axis-aligned ones only).
func _prim_rect(p: Dictionary) -> Rect2i:
	if p.has("rect"):
		return p["rect"]
	var pts: Array = p["pts"]
	return Rect2i(Vector2i(pts[0]), Vector2i(pts[3]) - Vector2i(pts[0]))


func _hud(w: Object) -> Array:
	if not ResourceLoader.exists(HUD_SCENE):
		_check(false, "missing " + HUD_SCENE)
		return []
	var m := _match(w)
	var text_area := TextArea.new(data)
	var hud: Node = load(HUD_SCENE).instantiate()
	hud.text_area = text_area
	hud.data = data
	hud.world = w
	root.add_child(hud)
	hud.set_match(m)
	# The arena passes the match's events to its HUD.
	m.visual.connect(hud.on_visual)
	m.begin_fight(1, 2)
	return [hud, m]


func _test_hud_pieces() -> void:
	var w := _arena_world()
	var hm := _hud(w)
	if hm.is_empty():
		return
	var hud: Node = hm[0]
	var m: Object = hm[1]
	for name in ["StatusBars", "FinisherGauge", "CommandMenu", "Timer", "IntroStats", "PlayerMarker", "Timeout",
			"StartText", "EntityNumbers", "FinisherChargeup"]:
		_check(hud.get_node_or_null(name) != null, "the arena HUD has %s" % name)
	_check(hud.get_node("EntityNumbers").follows, "the arena's numbers follow their fighter (GAME_STATE 4)")

	# STD_renderCounterDigits(-0xD, -0x61, 2, 42, 3) (std_main.c:2867): added the two side pieces, the
	# digits (buf[1] then buf[0], least significant right, 14 apart), then the frame; drawn reversed.
	hud.on_visual("timer", [true])
	m.timer = 42
	hud.tick(0)
	var t: Array = hud.get_node("Timer").prims
	var want := [
		[Rect2i(0, 0x78, 0x42, 0x1D), Rect2i(-0x21, -0x68, 0x42, 0x1D)],
		[Rect2i(2 * 12, 0x30, 12, 15), Rect2i(-0xD + 14, -0x61, 12, 15)],
		[Rect2i(4 * 12, 0x30, 12, 15), Rect2i(-0xD, -0x61, 12, 15)],
		[Rect2i(0x88, 0x30, 8, 0x12), Rect2i(0x14, -0x63, 8, 0x12)],
		[Rect2i(0x78, 0x30, 8, 0x12), Rect2i(-0x1C, -0x63, 8, 0x12)],
	]
	var got := []
	for p in t:
		got.append([p["uv"], _prim_rect(p)])
	_eq(got, want, "timer 42: frame, units, tens, the two side pieces")
	_eq(t[0]["image"], "tim_files/STDDAT/TIME", "the timer's frame: TIME.TIM (GetTPage(1, 0, 0x2C0, 0))")
	_eq(t[1]["image"], "stdtim/02_time_up", "the timer's digits: STDTIM page (832, 0)")
	m.timer = 7
	hud.tick(0)
	_eq(hud.get_node("Timer").prims.size(), 4, "timer 7: one digit")

	# STD_renderCommandMenu(0) (std_main.c:1750), 5 commands, hovered 4, fighting (GAME_STATE 4).
	var b: Object = m.battle
	b.available_commands.assign([11, 5, 4, 2, 3])
	b.hovered_command = 4
	b.game_state = 4
	m.menu_blink = 0
	hud.tick(0)
	var cm: Array = hud.get_node("CommandMenu").prims
	var labels := cm.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "label")
	var icons := cm.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "icon")
	var cursor := cm.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "cursor")
	_eq(labels.size(), 5, "command menu: 5 labels")
	_eq(icons.size(), 4, "command menu: 4 icons (commands 1-4)")
	_eq(cursor.size(), 1, "command menu: the cursor while fighting")
	if cursor.size() == 1:
		_eq([cursor[0]["uv"], _prim_rect(cursor[0])], [Rect2i(0x3D, 0xE0, 0x16, 0x16), Rect2i(-143, 0x44, 0x16, 0x16)],
				"cursor: hovered 4 of an even count, at TOP")
	# Layout 3 = [0, 1, 2, 1, 3]: label u / w from STD_COMMAND_LABEL_U / W; x from -0x8F, 0xB / 0xE wide.
	var lwant := {0: [Rect2i(0, 0xE0, 11, 31), Rect2i(-143, 0x44, 11, 0x20)],
			1: [Rect2i(11, 0xE0, 14, 31), Rect2i(-132, 0x44, 14, 0x20)],
			4: [Rect2i(39, 0xE0, 11, 31), Rect2i(-90, 0x44, 11, 0x20)]}
	for i in lwant:
		var p: Dictionary = labels.filter(func(q: Dictionary) -> bool: return q["index"] == i)[0]
		_eq([p["uv"], _prim_rect(p)], lwant[i], "command label %d" % i)
	# Icons: x = base - i * 0xE (base -84); even count: odd i from TOP + 0xD to BOTTOM - 3.
	var i1: Dictionary = icons.filter(func(q: Dictionary) -> bool: return q["index"] == 1)[0]
	_eq([i1["uv"], _prim_rect(i1)], [Rect2i(0x80, 0xC0, 0x10, 0xF), Rect2i(-98, 0x51, 0x10, 0x10)],
			"command icon 1 (Distance)")
	var i2: Dictionary = icons.filter(func(q: Dictionary) -> bool: return q["index"] == 2)[0]
	_eq(_prim_rect(i2), Rect2i(-112, 0x47, 0x10, 0x10), "command icon 2: even i from TOP + 3")
	m.menu_blink = 1
	b.hovered_command = 2
	hud.tick(0)
	i2 = hud.get_node("CommandMenu").prims.filter(func(q: Dictionary) -> bool: return q.get("kind", "") == "icon" and q["index"] == 2)[0]
	_eq(i2["uv"].position.x, 0x60 + 0x10, "the hovered icon blinks (u + 0x10)")

	# STD_renderFighterStatusBars(1) (std_hud.c:1016): x0 0x24, the HP number at x0 + 0x49, y0 - 3.
	hud.on_visual("status_bars", [true])
	hud.tick(0)
	var bars: Array = hud.get_node("StatusBars").prims
	var hp_frame := bars.filter(func(p: Dictionary) -> bool: return p.get("fighter", -1) == 1 and p.get("kind", "") == "frame" and p["bar"] == 0)
	_check(hp_frame.size() == 1 and _prim_rect(hp_frame[0]).position == Vector2i(0x24, -0x64), "the opponent's HP frame at (0x24, -0x64)")
	var fills := bars.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "fill" and p["fighter"] == 0 and p["bar"] == 0)
	_check(fills.size() == 1 and _prim_rect(fills[0]).size.x == 50, "the partner's HP fill: 50 at full HP")

	# STD_renderFighterHPBar(0) only (std_hud.c:1092-1093): the full gauge and the ready icon after 5 frames.
	b.fighters[0].finisher_progress = b.fighters[0].finisher_goal
	b.fighters[1].finisher_progress = b.fighters[1].finisher_goal
	for k in 6:
		hud.tick(0)
	var g: Array = hud.get_node("FinisherGauge").prims
	var icon := g.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "ready")
	var box := g.filter(func(p: Dictionary) -> bool: return p.has("fill"))
	_check(icon.size() == 1 and _prim_rect(icon[0]) == Rect2i(-0x56, -0x4B, 0x25, 9), "the ready icon at (-0x56, -0x4B)")
	_check(box.size() == 1 and _prim_rect(box[0]) == Rect2i(-0x58, -0x4C, 0x29, 0xB), "the ready box at (-0x58, -0x4C)")
	var segs := g.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == "segment")
	_eq(segs.size(), 8, "full gauge: 8 segments")
	if segs.size() == 8:
		var s0: Dictionary = segs.filter(func(p: Dictionary) -> bool: return p["index"] == 0)[0]
		_eq(_prim_rect(s0).position, Vector2i(0 - 0x8D, -0x4F), "segment 0 at SEGMENT_X[0] - 0x8D")
	_check(g.all(func(p: Dictionary) -> bool: return p.get("fighter", 0) == 0), "only the partner's gauge is drawn")

	# STD_renderIntroStats (2009) / STD_renderIntroStatBar (1731) / STD_renderIntroStatNumber (2034).
	m.intro_stats_active = true
	m.intro_stats_entity = 1
	m.intro_stats.assign([500, 300, 100, 90, 80, 70])
	var s1: Dictionary = w.stats(1)
	s1["current"]["hp"] = 500
	s1["current"]["mp"] = 300
	s1["base"].merge({"offense": 100, "defense": 90, "speed": 80, "brains": 70}, true)
	hud.on_visual("intro_stats", [1, true])
	hud.tick(0)
	var st: Array = hud.get_node("IntroStats").prims
	var widths := [0, 0, 0, 0, 0, 0]
	for p in st.filter(func(q: Dictionary) -> bool: return q.get("kind", "") == "bar"):
		widths[int(p["stat"])] = _prim_rect(p).size.x
	_eq(widths, [5, 3, 10, 9, 8, 7], "intro stat bars: value * 100 / limit")
	var d0 := st.filter(func(q: Dictionary) -> bool: return q.get("kind", "") == "digit" and q["stat"] == 0)
	var d0r := []
	for p in d0:
		d0r.append(_prim_rect(p))
	d0r.sort_custom(func(a: Rect2i, c: Rect2i) -> bool: return a.position.x < c.position.x)
	_eq(d0r, [Rect2i(64, -28, 12, 12), Rect2i(76, -28, 12, 12), Rect2i(88, -28, 12, 12)], "the HP number 500 at 52 + (3 - i) * 12")
	m.intro_stats[0] = 400
	hud.tick(0)
	_check(hud.get_node("IntroStats").prims.filter(func(q: Dictionary) -> bool: return q.get("kind", "") == "digit").is_empty(),
			"no numbers while a stat still counts")

	# STD_renderTimeoutText (5617): "TIME UP" from the STDTIM page.
	hud.on_visual("timeout_text", [true])
	hud.tick(0)
	var tt: Array = hud.get_node("Timeout").prims
	_check(tt.size() >= 1 and tt[0]["uv"] == Rect2i(0, 8, 0x90, 0x18) and _prim_rect(tt[0]) == Rect2i(-0x48, -0xC, 0x90, 0x18),
			"TIME UP at (-0x48, -0xC)")

	# The 1P / 2P markers only for the same Digimon (STD_initializeCombat 4140).
	_check(hud.get_node("PlayerMarker").prims.is_empty(), "no player markers for two different Digimon")
	hud.free()


# --- step 6: the bracket view and the scenes (specs/arena.md §4.7) -----------------------------

const SCENES := "res://scripts/systems/arena/arena_scenes.gd"
const ICONS_A := "stdtim/00_digimon_icons_a"
const ICONS_B := "stdtim/01_digimon_icons_b"


## What the projectiles' and hit flashes' ticks draw this frame, from the state before it
## (std_main.c:3582-3600, 3603-3670): both tick before STD_updateBracket (a render).
func _test_bracket_drawn() -> void:
	var s := _script(BRACKET)
	if s == null:
		return
	var b: Object = s.new(data, BRACKET_PLAYER, BRACKET_ROUND1.duplicate(), BRACKET_ROUND2.duplicate())
	var shots := 0
	var flashes := 0
	var bad := 0
	for n in BRACKET_RESULTS.size():
		b.begin()
		var f := 0
		while not b.finished and f < 5000:
			f += 1
			var d := 1 if int(b.match) < 5 else 3
			var want_p := []
			var ids: Array = b.projectiles.keys()
			ids.sort()
			for id in ids:
				var p: Dictionary = b.projectiles[id]
				var facing := int(b.slots[id]["facing"])
				want_p.append({"slot": int(id), "x": int(p["x"]) + (d if facing == 1 else -d), "y": int(p["y"]),
						"flag": int(p["flag"]), "facing": facing})
			var want_f := []
			var fl: Array = b.flashes.duplicate()
			fl.sort()
			for idx in fl:
				var sl: Dictionary = b.slots[idx]
				if int(sl["timer"]) % 5 == 4:
					want_f.append({"slot": int(idx), "x": int(sl["x"]), "y": int(sl["y"])})
			b.frame(BRACKET_RESULTS[n])
			if _ints(b.drawn_projectiles) != want_p or _ints(b.drawn_flashes) != want_f:
				bad += 1
				if bad <= 3:
					print("  bracket %d frame %d: drawn %s %s, want %s %s" % [n, f, b.drawn_projectiles, b.drawn_flashes, want_p, want_f])
			shots += want_p.size()
			flashes += want_f.size()
	_eq(bad, 0, "bracket: the projectiles / flashes drawn each frame (their ticks, before the update)")
	_check(shots > 0 and flashes > 0, "bracket: some projectiles (%d) and flashes (%d) were drawn" % [shots, flashes])


func _scenes() -> Object:
	var s := _script(SCENES)
	if s == null:
		return null
	return s.new(data)


func _locs(sc: Object, from: int, to: int) -> Array:
	var out := []
	for i in range(from, to):
		out.append(sc.objects[i]["location"])
	return out


func _test_scenes() -> void:
	var sc := _scenes()
	if sc == null:
		return
	# Versus / Draw (std_hud.c:1138-1219): from x 1000, object i after timer > 5i, -200 a frame.
	sc.add_versus()
	_eq(sc.active, "versus", "versus: up")
	_eq(_locs(sc, 0, 4), [Vector3i(1000, 0x78, 0x280), Vector3i(1000, 0x78, 0x280), Vector3i(1000, 0x78, 0x280),
			Vector3i(1000, 0x78, 0x280)], "versus: the start")
	for k in 6:
		sc.tick()
	_eq(_locs(sc, 0, 4).map(func(v: Vector3i) -> int: return v.x), [-200, 800, 1000, 1000], "versus: x after 6 frames")
	sc.tick()
	_eq(_locs(sc, 0, 2).map(func(v: Vector3i) -> int: return v.x), [-273, 600], "versus: object 0 clamped to -273")
	for k in 0x50 - 7:
		sc.tick()
	_check(not sc.versus_finished(), "versus: not finished at 0x50")
	sc.tick()
	_check(sc.versus_finished(), "versus: finished at 0x51")
	_eq(_locs(sc, 0, 4).map(func(v: Vector3i) -> int: return v.x), [-273, -86, 94, 272], "versus: every letter at its target")
	sc.remove_versus()
	_eq(sc.active, "", "versus: removed")

	# Win (std_effect.c:1516-1574, the tables std_hud.c:1227-1240).
	sc.add_win()
	_eq(_locs(sc, 0, 4), [Vector3i(-0xFA, 0, -0x30C), Vector3i(-0x32, 0, -0x30C), Vector3i(0x64, 0, -0x30C),
			Vector3i(0x104, 0, -0x30C)], "win: the start")
	for k in 60:
		sc.tick()
	_eq(sc.objects[0]["location"], Vector3i(-0xFA, 0, -0x30C), "win: object 0 waits while timer <= 0x3C")
	sc.tick()
	_eq([sc.objects[0]["location"], sc.objects[0]["rotation"]], [Vector3i(51, 0, -730), Vector3i(204, 3123, 0)],
			"win: object 0's first step (FIRST_X[1] = curve[15] - 0xE6, ROT_X/Y[1])")
	_eq(sc.objects[1]["location"], Vector3i(-0x32, 0, -0x30C), "win: object 1 waits until timer > 0x42")
	for k in 19:
		sc.tick()
	_eq([sc.objects[0]["location"], sc.objects[0]["rotation"]], [Vector3i(-210, 0, 220), Vector3i(0, 0, 0)],
			"win: object 0 at rest after 20 steps (z 0xDC, FIRST_X[0x14] = curve[4] - 0xE6)")
	_eq([sc.objects[3]["location"], sc.objects[3]["rotation"]], [Vector3i(35, 0, -680), Vector3i(409, 3174, 0)],
			"win: object 3 after 2 steps (LAST_X[2] = 0x118 - curve[14])")
	for k in 200:
		sc.tick()
	_eq(sc.timer, 0xA0, "win: the timer stops at 0xA0")
	sc.remove_result()

	# Lose (std_effect.c:1401-1509): 32 swaps with randomLimit(0x20), then the wipe and the drop.
	var vals := []
	for i in 32:
		vals.append((i * 7 + 3) % 32)
	var rolls := Rolls.new(vals)
	sc.roll = rolls.roll
	sc.add_lose()
	var order := range(32)
	for i in 32:
		var j: int = vals[i]
		var t: int = order[i]
		order[i] = order[j]
		order[j] = t
	_eq(_ints(sc.wipe_order), order, "lose: the wipe order (swapByte(&order[i], &order[randomLimit(0x20)]))")
	_check(rolls.limits.size() == 32 and rolls.limits.all(func(l: int) -> bool: return l == 0x20), "lose: 32 rolls of 0x20")
	_eq(_locs(sc, 4, 8), [Vector3i(0, -0x2BC, 0xDC), Vector3i(0, -0x2BC, 0xDC), Vector3i(0, -0x2BC, 0xDC),
			Vector3i(0, -0x2BC, 0xDC)], "lose: the letters at (0, -0x2BC, 0xDC)")
	for k in 61:
		sc.tick()
	_eq(_locs(sc, 4, 8).map(func(v: Vector3i) -> int: return v.y), [-692, -700, -700, -700], "lose: object 4 drops first (step 0 = 1)")
	for k in 9:
		sc.tick()
	_check(_ints(sc.wipe_heights).all(func(h: int) -> bool: return h == 0), "lose: no column before step 0 reaches 0xB (frame 70)")
	sc.tick()
	var hw := []
	for i in 32:
		hw.append(0x3C if order.find(i) < 8 else 0)
	_eq(_ints(sc.wipe_heights), hw, "lose: frame 71, group 0's columns +0x3C")
	for k in 3:
		sc.tick()
	hw = []
	for i in 32:
		var g: int = order.find(i) / 8
		hw.append(0xF0 if g == 0 else (0x3C if g == 1 else 0))
	_eq(_ints(sc.wipe_heights), hw, "lose: frame 74, group 0 at 0xF0, group 1 starts")
	for k in 115 - 74:
		sc.tick()
	_eq(_locs(sc, 4, 8).map(func(v: Vector3i) -> int: return v.y), [100, 100, 100, 100], "lose: frame 115, all at DROP_Y[0x16]")
	sc.tick()
	_eq([sc.objects[4]["rotation"].x, sc.objects[7]["rotation"].x, sc.objects[4]["location"].y], [5, 5, 100],
			"lose: frame 0x74, the tilt starts, y held")
	for k in 128 - 116:
		sc.tick()
	_eq([sc.objects[5]["location"].y, sc.objects[5]["rotation"].x], [108, 882], "lose: frame 0x80, all drop again from step 1, + 0x320")
	sc.tick()
	_eq([sc.objects[6]["location"].y, sc.objects[6]["rotation"].x], [132, 1024], "lose: frame 0x81")
	sc.tick()
	_eq([sc.objects[6]["location"].y, sc.objects[6]["rotation"].x], [172, 1024], "lose: frame 0x82, the tilt held")
	sc.remove_result()

	# Champion (std_hud.c:1273-1396, std_effect.c:1259-1311).
	sc.load_champion()
	sc.init_champion()
	_eq(sc.active, "champion", "champion: up")
	_eq([sc.objects[0]["location"], sc.objects[4]["location"], sc.objects[5]["location"], sc.objects[8]["location"]],
			[Vector3i(-0x2F8, 0xC8, 0x7BC), Vector3i(40, 0xC8, 0x7BC), Vector3i(0xBE, 0xC8, 0x7BC), Vector3i(0x2E4, 0xC8, 0x7BC)],
			"champion: the letters' places")
	_eq(sc.objects[3]["scale"], Vector3i(0x1000, 0x2000, 0x1000), "champion: scale (1, 2, 1)")
	_check(range(9).all(func(i: int) -> bool: return not sc.objects[i]["visible"]), "champion: the letters start hidden (GsDOFF)")
	_eq(_ints(sc.columns), [224, 224, 224, 224, 224, 224, 224, 224, 224], "champion: the columns from (0x378, 0) = page u 224")
	_eq([sc.podium, sc.podium_y], [true, -0x1E], "champion: the podium at y -0x1E")
	sc.champion_letters(1)
	_eq([sc.objects[0]["rotation"].y, sc.objects[0]["visible"], sc.objects[1]["rotation"].y], [0x200, false, 0], "champion: timer 1")
	for t in range(2, 6):
		sc.champion_letters(t)
	_eq([sc.objects[0]["rotation"].y, sc.objects[0]["visible"], sc.objects[1]["rotation"].y, sc.objects[1]["visible"]],
			[0xA00, true, 0x200, false], "champion: timer 5, letter 0 shown, letter 1 starts")
	for t in range(6, 20):
		sc.champion_letters(t)
	_eq(sc.objects[0]["rotation"].y, 0x600, "champion: timer 19, letter 0 still spinning")
	sc.champion_letters(20)
	_eq(sc.objects[0]["rotation"].y, 0, "champion: timer 0x14, letter 0 still")
	for t in range(21, 61):
		sc.champion_letters(t)
	_check(sc.objects[8]["visible"], "champion: letter 8 shown at 45")
	_eq(int(sc.columns[0]), 224, "champion: column 0 waits until 0x3D")
	sc.champion_letters(61)
	_eq(int(sc.columns[0]), 216, "champion: column 0 from 0x376 at 0x3D")
	for t in range(62, 71):
		sc.champion_letters(t)
	_eq([int(sc.columns[0]), int(sc.columns[8])], [144, 208], "champion: timer 70, column 0 from 0x364, column 8 (from timer 69) from 0x374")
	sc.champion_letters(71)
	sc.champion_letters(72)
	_eq(int(sc.columns[0]), 224, "champion: column 0 back to 0x378 at step 10, then still")
	sc.champion_rise()
	_eq([sc.objects[2]["location"].y, sc.podium_y], [0xC8 + 0x32, -0x1E - 0x19], "champion: rising")
	for k in 8:
		sc.champion_rise()
	_eq([sc.objects[2]["location"].y, sc.podium_y], [0x258, -0x1E - 0x19 * 9], "champion: the letters stop at 0x258, the podium goes on")
	sc.remove_champion()
	_eq([sc.active, sc.podium], ["", false], "champion: removed")

	# STD_offsetTMDObjectUVs (std_hud.c:1105): the UV word += (0x30 << 8) + (8 - i) * -24.
	var s: Script = _script(SCENES)
	_eq(s.champion_uv(152, 0, 8), Vector2i(152, 48), "champion uv: letter 8, v + 0x30")
	_eq(s.champion_uv(152, 0, 0), Vector2i(216, 47), "champion uv: letter 0, u - 192 borrows from v")
	_eq(s.champion_uv(247, 47, 0), Vector2i(55, 95), "champion uv: letter 0, (247, 47)")


## A whole won tournament: the scenes the session and its matches add.
func _test_scenes_session() -> void:
	Rng.set_seed(7)
	var w := _stub()
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, AGUMON, Vector3i(0, 0, 0), {"max_hp": 9999, "max_mp": 400, "offense": 999, "defense": 999,
			"speed": 999, "brains": 150, "moves": [0x2E, null, null, 0x35], "moves_prio": [0, 0, 0, 0]})
	var stub := TournamentStub.new()
	stub.w = w
	var session := _session(w, stub)
	if session == null:
		return
	var events := []
	session.visual.connect(func(kind: String, args: Array) -> void:
		if kind in ["scene", "podium"]:
			events.append([kind, args[0]]))
	var seen := {}
	session.begin(0, [GIGADRAMON, 0x1F, 0x20, 0x03, 0x11, 0x1F, 0x20], 0)
	var n := 0
	while not session.is_done() and n < 60000:
		session.frame(Pad.CONFIRM if n % 10 == 0 else 0)
		w.advance()
		n += 1
		if session.scenes != null:
			seen[session.scenes.active] = true
	_check(session.scenes != null, "the session owns ArenaScenes")
	_eq(events.filter(func(e: Array) -> bool: return e == ["scene", "win"]).size(), 3,
			"one win scene per match (the camera's signal connected once per match)")
	_check(seen.has("win") and seen.has("champion"), "the win and champion scenes ran (%s)" % str(seen.keys()))
	_check(["podium", true] in events and ["podium", false] in events, "the podium up and down")
	if session.scenes != null:
		_eq([session.scenes.podium_y, session.scenes.objects[0]["location"].y], [-0x1E - 0x19 * 0x50, 0x258],
				"champion: the podium rose 0x50 frames, the letters to 0x258")
		_eq(session.scenes.active, "", "no scene left at the end")


func _hud_session() -> Array:
	if not ResourceLoader.exists(HUD_SCENE):
		_check(false, "missing " + HUD_SCENE)
		return []
	Rng.set_seed(7)
	var w := _stub()
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, AGUMON, Vector3i(0, 0, 0), {"max_hp": 9999, "max_mp": 400, "offense": 999, "defense": 999,
			"speed": 999, "brains": 150, "moves": [0x2E, null, null, 0x35], "moves_prio": [0, 0, 0, 0]})
	var stub := TournamentStub.new()
	stub.w = w
	var session := _session(w, stub)
	if session == null:
		return []
	var hud: Node = load(HUD_SCENE).instantiate()
	hud.text_area = TextArea.new(data)
	hud.data = data
	hud.world = w
	root.add_child(hud)
	hud.set_tournament(session)
	session.visual.connect(hud.on_visual)
	session.begin(0, [GIGADRAMON, 0x1F, 0x20, 0x03, 0x11, 0x1F, 0x20], 0)
	# The stub too: the session's callables don't keep it alive.
	return [hud, session, w, stub]


func _kinds(prims: Array, kind: String) -> Array:
	return prims.filter(func(p: Dictionary) -> bool: return p.get("kind", "") == kind)


func _test_bracket_view() -> void:
	var hs := _hud_session()
	if hs.is_empty():
		return
	var hud: Node = hs[0]
	var session: Object = hs[1]
	var w: Object = hs[2]
	var view: Node = hud.get_node_or_null("BracketView")
	_check(view != null, "the arena HUD has BracketView")
	_check(hud.get_node_or_null("Scenes") != null, "the arena HUD has Scenes")
	if view == null:
		hud.free()
		return
	_check(view.get_index() < hud.get_node("StatusBars").get_index(), "the bracket behind the HUD pieces")
	while session.phase != session.Phase.BRACKET_INTRO:
		session.frame(0)
		w.advance()
	session.frame(0)
	hud.tick(0)
	# STD_renderBracketIntro (std_main.c:3704): STD_drawBracket, the overlay (layer 3), the title (layer 2).
	var p: Array = view.prims
	_eq(p.map(func(q: Dictionary) -> String: return q.get("kind", "")), ["box", "picture", "overlay", "title"],
			"intro: box, picture, overlay, title (no sprites)")
	if p.size() == 4:
		_eq([p[0]["rect"], p[0]["fill"], p[0]["semi"], p[0].get("abr", -1)],
				[Rect2i(-0xA0, -0x78, 0x140, 0xF0), Color8(0x20, 0x20, 0x20), true, -1], "the box fill: grey 0x20, semi mode 0")
		_eq([p[1]["image"], p[1]["palette"], p[1]["uv"], _prim_rect(p[1]), p[1]["color"], p[1].get("abr", -1)],
				["stdtim/05_bracket", 0, Rect2i(0, 0x78, 0xFF, 0x87), Rect2i(-0x80, -0x61, 0xFF, 0x87), BattleHudDraw.grey(0), 1],
				"the bracket picture at fade 0x80: grey 0, additive")
		_eq([p[2]["rect"], p[2]["fill"], p[2].get("abr", -1)], [Rect2i(-0xA0, -0x78, 0x140, 0xF0), BattleHudDraw.grey(0x80), 2],
				"the overlay: white x 0x80, subtractive")
		_eq([p[3]["image"], p[3]["palette"], p[3]["uv"], _prim_rect(p[3]), p[3]["color"], p[3].get("abr", -1)],
				["tim_files/STDDAT/GRADE/GRADED", 0, Rect2i(0, 0, 0xFF, 0x80), Rect2i(-0x80, -0x40, 0xFF, 0x80), BattleHudDraw.grey(0x80), -1],
				"the title: Grade D's picture, opaque while fade = 0x80")
	while session.phase != session.Phase.BRACKET:
		session.frame(0)
		w.advance()
	hud.tick(0)
	p = view.prims
	_eq(p.map(func(q: Dictionary) -> String: return q.get("kind", "")).slice(0, 10),
			["box", "picture", "sprite", "sprite", "sprite", "sprite", "sprite", "sprite", "sprite", "sprite"],
			"bracket: box, picture, the 8 sprites")
	var sprites := _kinds(p, "sprite")
	_eq(sprites.map(func(q: Dictionary) -> int: return q["index"]), [7, 6, 5, 4, 3, 2, 1, 0], "bracket: slot 0 drawn last (added first)")
	_check(p[1].get("abr", -1) == -1 and p[1]["color"] == BattleHudDraw.grey(0x80), "bracket: the picture opaque at fade 0")
	var types: Array = session.participants["participants"]
	var b: Object = session.bracket
	for q in sprites:
		var i: int = q["index"]
		var t := int(types[i])
		var rec: Dictionary = data.digimon(t)
		var cell: Dictionary = rec["bracket_sprite"]
		var sl: Dictionary = b.slots[i]
		var u := (int(cell["u"]) + (int(sl["frame"]) & 1) * 16) & 0xFF
		var v := (int(cell["v"]) + (int(sl["frame"]) / 2) * 16) & 0xFF
		var sw := 15 if u == 0xF0 else 16
		var sh := 15 if v == 0xF0 else 16
		var x := int(sl["x"])
		var y := int(sl["y"])
		var pts := [Vector2i(x, y), Vector2i(x + sw, y), Vector2i(x, y + sh), Vector2i(x + sw, y + sh)]
		if int(sl["facing"]) == 1:
			pts = [pts[1], pts[0], pts[3], pts[2]]
		_eq([q["image"], q["palette"], q["uv"], q["pts"]],
				[ICONS_A if int(cell["page"]) == 0x380 else ICONS_B, int(rec["bracket_sprite_clut"]), Rect2i(u, v, sw, sh), pts],
				"bracket sprite of slot %d (type 0x%X)" % [i, t])
	# The projectiles (layer 4) and the hit flashes (layer 3), from the bracket's drawn lists.
	var shot := false
	var flash := false
	var n := 0
	var cluts: Array = data.system("arena")[0]["bracket"]["projectile_cluts"]
	while not (shot and flash) and n < 20000 and not session.is_done():
		session.frame(0)
		w.advance()
		# As Arena.frame: the HUD gets each match.
		if session.current_match != null and hud.session != session.current_match:
			hud.set_match(session.current_match)
		hud.tick(0)
		n += 1
		if session.bracket == null or not session.phase in [session.Phase.BRACKET, session.Phase.CHAMPION_BRACKET]:
			continue
		p = view.prims
		var dp: Array = session.bracket.drawn_projectiles
		var df: Array = session.bracket.drawn_flashes
		var pr := _kinds(p, "projectile")
		var fr := _kinds(p, "flash")
		if not dp.is_empty() and not shot:
			shot = true
			var want := 0
			for d in dp:
				want += 1 + int(d["flag"])
			_eq(pr.size(), want, "projectiles: one prim each, two with flag")
			var d0: Dictionary = dp[0]
			var icon := int(data.digimon(int(types[int(d0["slot"])]))["bracket_icon"])
			var q0: Dictionary = pr.filter(func(q: Dictionary) -> bool: return q["index"] == int(d0["slot"]))[0]
			_eq([q0["image"], q0["palette"], q0["uv"], _prim_rect(q0).size],
					[ICONS_B, int(cluts[icon - 1]), Rect2i(icon * 8 - 8, 0xC0, 8, 8), Vector2i(8, 8) if int(d0["facing"]) != 1 else Vector2i(-8, 8)],
					"projectile: icon %d's cell and palette" % icon)
			_check(p.find(pr[0]) > p.find(sprites[0]) if not sprites.is_empty() else true, "projectiles over the sprites")
		if not df.is_empty() and not flash:
			flash = true
			_eq(fr.size(), df.size(), "hit flashes: one prim each")
			_eq([fr[0]["image"], fr[0]["palette"], fr[0]["uv"], _prim_rect(fr[0])],
					[ICONS_B, 0, Rect2i(0, 0xC8, 16, 16), Rect2i(int(df[0]["x"]), int(df[0]["y"]), 16, 16)], "hit flash: icons_b (0, 0xC8)")
	_check(shot and flash, "the bracket drew a projectile and a flash")
	hud.free()


func _test_scene_view() -> void:
	var hs := _hud_session()
	if hs.is_empty():
		return
	var hud: Node = hs[0]
	var session: Object = hs[1]
	var view: Node = hud.get_node_or_null("Scenes")
	if view == null:
		_check(false, "the arena HUD has Scenes")
		hud.free()
		return
	_check(view.get_index() > hud.get_node("BracketView").get_index() and view.get_index() < hud.get_node("StatusBars").get_index(),
			"the scenes between the bracket and the HUD pieces (layer 4)")
	var sc: Object = session.scenes
	sc.add_versus()
	for k in 10:
		sc.tick()
	hud.tick(0)
	_eq(view.projection(), 0x200, "versus: projection 0x200")
	for i in 4:
		var node: Node3D = view.object_node("versus", i)
		_check(node != null and node.visible and node.position == Content.psx_to_godot([sc.objects[i]["location"].x,
				sc.objects[i]["location"].y, sc.objects[i]["location"].z]), "versus: DRAW object %d placed" % i)
	sc.remove_versus()
	# GsSortObject4J's drop rule (libgte.s GsTMDfastTF3L: cfc2 $31, bltz). FLAG bit 17 when
	# SZ3 * 2 <= h; SX2 out of -0x400..0x3FF; SZ3 < 0.
	var ls := PsxMath.identity()
	ls[11] = 175
	_check(PsxMath.rtp_flag_error(ls, Vector3i.ZERO, 0x15E), "GTE: SZ 175, h 0x15E overflows")
	ls[11] = 176
	_check(not PsxMath.rtp_flag_error(ls, Vector3i.ZERO, 0x15E), "GTE: SZ 176, h 0x15E projects")
	ls[11] = 0x15E
	_check(PsxMath.rtp_flag_error(ls, Vector3i(0x400, 0, 0), 0x15E) and not PsxMath.rtp_flag_error(ls, Vector3i(0x3FF, 0, 0), 0x15E)
			and not PsxMath.rtp_flag_error(ls, Vector3i(-0x400, 0, 0), 0x15E), "GTE: SX2 limited to -0x400..0x3FF")
	ls[11] = -10
	_check(PsxMath.rtp_flag_error(ls, Vector3i.ZERO, 0x15E), "GTE: SZ below 0")
	var lw := PsxMath.trans_matrix(PsxMath.identity(), Vector3i(-0xFA, 0, -0x30C))
	_eq(PsxMath.translation(PsxMath.gs_mul_coord0(PackedInt32Array(view.SCENE_MATRIX), lw)), Vector3i(-0xFB, 0, 219),
			"WIN W: GsGetLws translation (0x1004 * -0x30C >> 12) + 1000 = 219")
	# STD_addWinScene: the letters at z -0x30C (SZ 175 at the front faces, z -45 / -43) until timer 0x3C.
	# Counted from WIN_LOSE.TMD's sidecar with the GTE's integer maths.
	sc.add_win()
	sc.tick()
	hud.tick(0)
	var held := []
	for i in 4:
		held.append(view.dropped_polygons("result", i).size())
	_eq(held, [19, 5, 14, 5], "win, timer 1: the polygons libgs drops (W I N !)")
	for k in 0x3C:
		sc.tick()
	hud.tick(0)
	_eq(view.dropped_polygons("result", 1).size(), 5, "win, timer 0x3D: I still held")
	for k in 0xA0 - 0x3D:
		sc.tick()
	hud.tick(0)
	held = []
	for i in 4:
		held.append(view.dropped_polygons("result", i).size())
	_eq(held, [0, 0, 0, 0], "win, timer 0xA0: the letters at z 0xDC, all drawn")
	sc.remove_result()
	var rolls := Rolls.new(range(32))
	sc.roll = rolls.roll
	sc.add_lose()
	for k in 71:
		sc.tick()
	hud.tick(0)
	_eq(view.projection(), 0x15E, "lose: projection 0x15E")
	var cols := _kinds(view.prims, "wipe")
	_eq(cols.size(), 32, "lose: 32 columns")
	if cols.size() == 32:
		_eq([cols[5]["rect"], cols[5]["fill"], cols[5]["semi"]], [Rect2i(10 * 5 - 0xA0, -0x78, 10, int(sc.wipe_heights[5])), Color.BLACK, true],
				"lose: column 5, black, semi mode 0")
	var vis := []
	for i in 8:
		var node: Node3D = view.object_node("result", i)
		vis.append(node != null and node.visible)
	_eq(vis, [false, false, false, false, true, true, true, true], "lose: WIN_LOSE objects 4-7 only")
	_check(view.object_node("versus", 0) == null or not view.object_node("versus", 0).visible, "lose: the DRAW letters hidden")
	sc.remove_result()
	sc.load_champion()
	sc.init_champion()
	hud.tick(0)
	var src: Image = view.champion_source
	var img: Image = view.champion_image
	_check(src != null and img != null, "champion: the page copy")
	if src != null and img != null:
		_eq(img.get_pixel(32 + 24 * 3, 48 + 5), src.get_pixel(224, 5), "champion: column 3 copied from (0x378, 0)")
		for t in range(1, 62):
			sc.champion_letters(t)
		hud.tick(0)
		_eq(img.get_pixel(32 + 7, 48 + 9), src.get_pixel(216 + 7, 9), "champion: column 0 from 0x376 at 0x3D")
		_eq(img.get_pixel(32 + 24 * 8, 48), src.get_pixel(224, 0), "champion: column 8 still from 0x378")
	_eq(view.projection(), 0x200, "champion: projection 0x200")
	_check(view.object_node("champion", 0).visible and view.object_node("champion", 8).visible, "champion: letters 0 and 8 shown by timer 61")
	hud.free()


# --- step 7: the effects in the arena (spec §4.8) ---------------------------------------------------

## DG Dimension (technique 29, the only effect calling builtin 92) run as test_efe runs it, user
## MetalGreymon, target Agumon. Returns the renderScreenFade draw calls' values, in order.
func _run_dg_dimension(ctx: Object) -> Array:
	const DG_DIMENSION := 29
	var move: Dictionary = data.move(DG_DIMENSION)
	ctx.data = data
	var radii := int(data.digimon(METALGREYMON)["radius"]) + int(data.digimon(AGUMON)["radius"])
	var reach := int(sqrt(float(int(move.get("distance_squared", 0)) + radii * radii)))
	ctx.entities = {
		1: {"type": METALGREYMON, "location": Vector3i.ZERO, "yaw": PsxMath.atan(-reach, 0), "hp": 100,
				"hit": false, "on_map": true, "on_screen": true},
		2: {"type": AGUMON, "location": Vector3i(0, 0, -reach), "yaw": PsxMath.atan(reach, 0), "hp": 100,
				"hit": false, "on_map": true, "on_screen": true}}
	var host := EffectHost.new(ctx)
	Rng.set_seed(DG_DIMENSION)
	var slots := host.load_moves([{"technique": DG_DIMENSION, "caster": 0}])
	if slots[0] < 0:
		_check(false, "DG Dimension's effect loads")
		return []
	var fx: EfeEffect = host.slots[slots[0]]
	fx.record_draws = true
	host.start(slots[0], 1, 2)
	var drawn := []
	for frame in 600:
		host.tick()
		host.draw()
		for victim in [1, 2]:
			while not host.pop_attack_object(victim).is_empty():
				pass
			ctx.set_hit(victim, false)
		for c in fx.draw_calls:
			if c[0] == "renderScreenFade":
				drawn.append(int(c[1]))
		if not fx.is_running():
			break
	host.unload_all()
	return drawn


## ArenaWorld's side (palette_factor, the fixed view) needs the autoloads: tests/arena_scan.gd checks it.
func _test_arena_effects() -> void:
	PsxMath.setup(data)
	# The hooks' defaults are btl's (BTL_renderScreenFade draws its quad; BTL_loadMoveEFE reads nothing).
	var base := BattleEffectContext.new()
	_check(base.has_method("screen_fade") and base.has_method("on_load_moves"),
			"BattleEffectContext has the screen_fade and on_load_moves hooks")
	if not base.has_method("screen_fade"):
		return
	_eq(base.call("screen_fade", 0x80), false, "btl: the fade is the quad (screen_fade false)")

	# E2's place: EffectHost.load_moves calls on_load_moves first, once, also for an empty list.
	var log := FadeLog.new()
	log.data = data
	var host := EffectHost.new(log)
	host.load_moves([])
	_eq(log.loads, 1, "EffectHost.load_moves calls on_load_moves (STD_loadMoveEFE: downloadSomeImage), also for no moves")

	# Builtin 92 goes through the hook: drawn when it returns false, not drawn when true.
	var btl := FadeLog.new()
	var btl_drawn := _run_dg_dimension(btl)
	_eq(btl.loads, 1, "one on_load_moves per load_moves")
	# 57 calls in its draw script (16, 40 ... 232, 108, then 255), and one more with 0 in its tick script
	# on the frame it ends (corrected 2026-11-02: the first scan saw only the draw pass).
	_eq(btl.fades.size(), 58, "DG Dimension calls builtin 92 58 times")
	_eq(btl.fades.back() if not btl.fades.is_empty() else -1, 0, "its last call is 0, from the tick script as it ends")
	_eq(btl_drawn, btl.fades.slice(0, 57), "btl: the draw pass's calls are renderScreenFade draws, with their values")
	var arena := FadeLog.new()
	arena.handled = true
	var arena_drawn := _run_dg_dimension(arena)
	_eq(arena.fades, btl.fades, "the arena's hook gets the same values")
	_eq(arena_drawn, [], "and no renderScreenFade quad is drawn when the hook handles it")
