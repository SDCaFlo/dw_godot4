extends SceneTree
## Step 4e-4, the arena (specs/arena.md): the acceptance checks, written from the C by the reviewer.
## The expected values are the spec's §3-4, not the port's: the bracket traces and the participant and
## opponent results come from a transcription of std_main.c:2949-3735 / std_setup.c:279-389 run outside
## the port (reviewer's scratch, 2026-11-01) and were checked by hand on the cases marked so.
## Don't change them to make the code pass; when one looks wrong, report it with the C line.
##   godot --headless --path . -s res://tests/test_arena.gd
## Gate: DW_STEP_4E_4=<n> runs steps 2..n (unset: everything PENDING). Step 1's checks are
## data_porter/tests/test_arena_fields.py and asset_porter/tests/test_arena_assets.py; steps 3-7 get
## their checks here before each is built. Exits 1 if a check fails.
##
## Classes are loaded by path, so this file parses before they exist.

const TOURNAMENT := "res://scripts/systems/arena/arena_tournament.gd"
const BRACKET := "res://scripts/systems/arena/arena_bracket.gd"

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
	_step = int(OS.get_environment("DW_STEP_4E_4")) if OS.get_environment("DW_STEP_4E_4").is_valid_int() else 0
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
