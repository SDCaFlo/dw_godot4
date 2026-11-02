extends SceneTree
## Step 4e-4, the arena (specs/arena.md): the acceptance checks, written from the C by the reviewer.
## The expected values are the spec's §3-4, not the port's: the bracket traces and the participant and
## opponent results come from a transcription of std_main.c:2949-3735 / std_setup.c:279-389 run outside
## the port (reviewer's scratch, 2026-11-01) and were checked by hand on the cases marked so.
## Don't change them to make the code pass; when one looks wrong, report it with the C line.
##   godot --headless --path . -s res://tests/test_arena.gd
## Gate: DW_STEP_4E_4=<n> runs steps 2..n (unset: steps 2-4, which are built). Step 1's checks are
## data_porter/tests/test_arena_fields.py and asset_porter/tests/test_arena_assets.py; steps 3-7 get
## their checks here before each is built. Exits 1 if a check fails.
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
	# Steps 2-4 are built (spec §6): their checks run by default; DW_STEP_4E_4 can still limit or extend them.
	_step = int(OS.get_environment("DW_STEP_4E_4")) if OS.get_environment("DW_STEP_4E_4").is_valid_int() else 4
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
