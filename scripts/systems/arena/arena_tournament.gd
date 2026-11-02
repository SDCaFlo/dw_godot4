class_name ArenaTournament
extends RefCounted
## Arena tournament logic (specs/arena.md §3.1, §4.3, §5.2). Pure logic:
## opponent setup, bracket participant generation, stand-in lookup and final result.

## std_setup.c:353 ANIM_MOVE (0x2E).
const ANIM_MOVE := 0x2E
## std_setup.c:352 (0xF = 15 moves).
const OPPONENT_MOVE_SCAN := 0xF
## std_setup.c:392 (0x10 = 16 raw moves).
const OPPONENT_RAW_MOVES := 0x10
## std_setup.c:315-320: each stat is base ± (0x1E - randomLimit(0x3D)) %.
const SPREAD := 0x1E
const SPREAD_ROLL := 0x3D
## std_setup.c:325-342: the caps (>= 0x3E8 -> 0x3E7, >= 0x2710 -> 0x270F).
const STAT_CAP := 0x3E7
const HP_MP_CAP := 0x270F
## std_setup.c:387 (randomLimit(0xa) == 0): the self / Counter list's roll; its result is overwritten (moves[3] = 0xff, :391).
const SELF_ROLL := 0xA

var game_data: Node
var roll: Callable = Callable(Rng, "random_limit")


func _init(p_game_data: Node) -> void:
	game_data = p_game_data


## STD_tournamentMain (std_setup.c:530-540): returns the stand-in type if defined, else type.
func stand_in(type: int) -> int:
	var d: Dictionary = game_data.digimon(type)
	var stand: Variant = d.get("arena_stand_in")
	if stand is Dictionary and stand.has("id"):
		return int(stand["id"])
	return type


## STD_setupParticipants (std_main.c:3464-3540).
func setup_participants(partner_type: int, opponents: Array) -> Dictionary:
	var player_slot: int = roll.call(8)
	var pool := [0] + opponents.duplicate()
	for i in range(1, 8):
		var j: int = roll.call(7) + 1
		var tmp = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp

	var participants: Array[int] = []
	var p_idx := 1
	for i in range(8):
		if i == player_slot:
			participants.append(partner_type)
		else:
			participants.append(int(pool[p_idx]))
			p_idx += 1

	var round1: Array[int] = []
	for i in range(4):
		var a_type: int = participants[i * 2]
		var b_type: int = participants[i * 2 + 1]
		var lvl_a: int = int(game_data.digimon(a_type).get("level", {}).get("id", 0))
		var lvl_b: int = int(game_data.digimon(b_type).get("level", {}).get("id", 0))
		var chance: int = game_data.tournament_win_chance(lvl_a, lvl_b)
		var r: int = roll.call(100)
		if r < chance:
			round1.append(i * 2)
		else:
			round1.append(i * 2 + 1)

	var round2: Array[int] = [0, 0]
	if player_slot < 4:
		if player_slot < 2:
			round2[0] = round1[1]
		else:
			round2[0] = round1[0]
		var a_type: int = participants[round1[2]]
		var b_type: int = participants[round1[3]]
		var lvl_a: int = int(game_data.digimon(a_type).get("level", {}).get("id", 0))
		var lvl_b: int = int(game_data.digimon(b_type).get("level", {}).get("id", 0))
		var chance: int = game_data.tournament_win_chance(lvl_a, lvl_b)
		var r: int = roll.call(100)
		if r < chance:
			round2[1] = round1[2]
		else:
			round2[1] = round1[3]
	else:
		var a_type: int = participants[round1[0]]
		var b_type: int = participants[round1[1]]
		var lvl_a: int = int(game_data.digimon(a_type).get("level", {}).get("id", 0))
		var lvl_b: int = int(game_data.digimon(b_type).get("level", {}).get("id", 0))
		var chance: int = game_data.tournament_win_chance(lvl_a, lvl_b)
		var r: int = roll.call(100)
		if r < chance:
			round2[0] = round1[0]
		else:
			round2[0] = round1[1]
		if player_slot < 6:
			round2[1] = round1[3]
		else:
			round2[1] = round1[2]

	var opp_list: Array[int] = [0, 0, 0]
	if player_slot % 2 == 0:
		opp_list[0] = participants[player_slot + 1]
	else:
		opp_list[0] = participants[player_slot - 1]

	match player_slot / 2:
		0:
			opp_list[1] = participants[round1[1]]
			opp_list[2] = participants[round2[1]]
		1:
			opp_list[1] = participants[round1[0]]
			opp_list[2] = participants[round2[1]]
		2:
			opp_list[1] = participants[round1[3]]
			opp_list[2] = participants[round2[0]]
		3:
			opp_list[1] = participants[round1[2]]
			opp_list[2] = participants[round2[0]]

	return {
		"player_slot": player_slot,
		"participants": participants,
		"round1": round1,
		"round2": round2,
		"opponents": opp_list,
	}


## entityGetTechFromAnim (utils2.c:333): the technique of an animation (0x2E + slot).
func _technique_of(type: int, anim: int) -> int:
	if anim == 0xFF or anim < ANIM_MOVE:
		return 0xFF
	var d: Dictionary = game_data.digimon(type)
	var overrides: Dictionary = d.get("anim_technique", {})
	if overrides.has(str(anim)):
		return int(overrides[str(anim)])
	var slots: Array = d.get("c", {}).get("moves", [])
	var k := anim - ANIM_MOVE
	if k < slots.size():
		return int(slots[k])
	return 0xFF


## STD_initializeOpponent (std_setup.c:279-398).
func initialize_opponent(type: int, cup: int) -> Dictionary:
	var base_stat: int = int(game_data.tournament(cup).get("opponent_base_stat", 0))
	var level_id: int = int(game_data.digimon(type).get("level", {}).get("id", 0))
	var mul := 1
	var div := 1
	match level_id:
		3:
			mul = 1
			div = 1
		4:
			mul = 2
			div = 1
		5:
			mul = 25
			div = 10
		_:
			# port-only: C leaves mul / div unset for other levels
			mul = 1
			div = 1

	var off: int = mul * (base_stat + base_stat * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div
	var def: int = mul * (base_stat + base_stat * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div
	var speed: int = mul * (base_stat + base_stat * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div
	var brains: int = mul * (base_stat + base_stat * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div
	var hp: int = mul * (base_stat * 10 + (base_stat * 10) * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div
	var mp: int = mul * (base_stat * 10 + (base_stat * 10) * (SPREAD - roll.call(SPREAD_ROLL)) / 100) / div

	off = mini(off, STAT_CAP)
	def = mini(def, STAT_CAP)
	speed = mini(speed, STAT_CAP)
	brains = mini(brains, STAT_CAP)
	hp = mini(hp, HP_MP_CAP)
	mp = mini(mp, HP_MP_CAP)

	var list_a: Array[int] = []
	var list_b: Array[int] = []

	for i in range(OPPONENT_MOVE_SCAN):
		var anim: int = i + ANIM_MOVE
		var tech: int = _technique_of(type, anim)
		if tech == 0xFF:
			continue
		var m_data: Dictionary = game_data.move(tech)
		if m_data.is_empty():
			continue
		if m_data.get("category") == "finisher":
			continue
		var mp_cost: int = int(m_data.get("mp_cost", 0))
		if mp / 10 < mp_cost * 3:
			continue
		var is_counter: bool = m_data.get("counter", false)
		var is_self: bool = int(m_data.get("range", {}).get("id", 0)) == 4
		if is_self or is_counter:
			list_a.append(i)
		list_b.append(i)

	var moves: Array = [null, null, null, null]
	var nb: int = list_b.size()
	if nb != 0:
		for i in range(nb):
			var r: int = roll.call(nb)
			var tmp: int = list_b[i]
			list_b[i] = list_b[r]
			list_b[r] = tmp
		for i in range(3):
			if i < nb:
				moves[i] = list_b[i] + ANIM_MOVE
			else:
				moves[i] = null
	else:
		moves[0] = ANIM_MOVE
		moves[1] = null
		moves[2] = null

	var na: int = list_a.size()
	if na != 0:
		for i in range(na):
			var r: int = roll.call(na)
			var tmp: int = list_a[i]
			list_a[i] = list_a[r]
			list_a[r] = tmp
		if roll.call(SELF_ROLL) == 0:
			moves[3] = list_a[0] + ANIM_MOVE

	moves[3] = null
	var raw_moves: Array = game_data.digimon(type).get("c", {}).get("moves", [])
	for i in range(mini(OPPONENT_RAW_MOVES, raw_moves.size())):
		var raw_tech: int = int(raw_moves[i])
		if raw_tech != 0xFF:
			var rm_data: Dictionary = game_data.move(raw_tech)
			if rm_data.get("category") == "finisher":
				moves[3] = i + ANIM_MOVE
				break

	return {
		"base": {
			"max_hp": hp,
			"max_mp": mp,
			"offense": off,
			"defense": def,
			"speed": speed,
			"brains": brains,
			"moves": moves,
		},
		"current": {
			"hp": hp,
			"mp": mp,
			"charge_mode": 0,
		},
	}


## STD_tournamentMain (std_setup.c:609-613).
static func result(match_result: int, played: int) -> int:
	if match_result == 1:
		return played
	return played - 1
