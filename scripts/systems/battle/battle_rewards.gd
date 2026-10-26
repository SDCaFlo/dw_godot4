class_name BattleRewards
extends RefCounted
## A won battle's rewards (main/battle_ui.c, specs/battle.md §2.15): stat gains, drops, injury,
## technique learning and the end box's texts; then the boxes' counting (the stats box adds the
## gains to the partner's starting stats, the bits box counts the bits into the money).

## INITIAL_COMBAT_STATS order.
const STATS := ["max_hp", "max_mp", "offense", "defense", "speed", "brains"]
## Brain thresholds for the new commands (BTL_appendCommandLearnedText) and the MP discount
## (BTL_appendMPBonusText).
const COMMAND_THRESHOLDS := [500, 400, 300, 200, 100]
const MP_THRESHOLDS := [999, 900, 800, 700]
const MP_DISCOUNTS := {999: 20, 900: 15, 800: 10, 700: 5}

var battle: Battle
var data: Node

## STATS_GAINS.
var gains: Array[int] = [0, 0, 0, 0, 0, 0]
## Per enemy (1-3): the dropped item id, or -1.
var drops: Array[int] = []
var bits := 0
var injured := false
var learned := -1
## The end box's text, as [kind, args] entries for the HUD (kinds: drop, injured, command, mp_bonus,
## learned).
var texts: Array = []
## POST_BATTLE_STATS_TIMER and SHOULD_SKIP_BIT_COUNTING.
var stats_timer := 0
var skip := false


func _init(battle_logic: Battle) -> void:
	battle = battle_logic
	data = battle_logic.data


## handleBattleEndBox's first half (battle_ui.c:297-335): everything decided before the boxes open.
func compute() -> void:
	var w := battle.world
	bits = 0
	for i in range(1, battle.enemy_count + 1):
		bits += int(w.npc_record(battle.fighters[i].entity).get("bits", 0))
	stats_gains_and_drops()
	for i in range(1, battle.enemy_count + 1):
		if drops[i - 1] >= 0:
			texts.append(["drop", [w.digimon_type(battle.fighters[i].entity), drops[i - 1]]])
	if not (w.partner_condition() & 0x20):
		if battle.has_taken_damage:
			handle_injury()
		if injured:
			texts.append(["injured", [w.digimon_type(battle.fighters[0].entity)]])
	_command_text()
	_mp_bonus_text()
	move_learning()
	stats_timer = 100
	skip = false


## battleStatsGainsAndDrops (battle_ui.c:127).
func stats_gains_and_drops() -> void:
	var initial := battle.initial_stats
	var enemies := battle.enemy_count
	var factors: Array = data.system("stat_gain_factors")
	var factor := int(factors[enemies - 1]["factor"]) if enemies - 1 < factors.size() else 10
	for stat in 6:
		gains[stat] = 0
		var enemy_stat: int = initial[1][stat]
		var partner_stat: int = initial[0][stat]
		for i in range(1, enemies + 1):
			enemy_stat = maxi(enemy_stat, initial[i][stat])
		var den := partner_stat * 10
		if den == 0:
			den = 10
		if enemy_stat >= partner_stat:
			gains[stat] = PsxMath.div(den + enemy_stat * factor - 1, den)
		elif Rng.random_limit(100) < PsxMath.div(enemy_stat * factor * 100, den):
			gains[stat] = 1
	var partner := battle.fighters[0]
	var lost := starting_lost()
	for i in 6:
		if gains[i] != 0:
			continue
		var chance := 0
		match i:
			0:
				chance = PsxMath.div(lost * 100, partner.max_hp())
			1, 2:
				chance = battle.hit_count * 10
			3:
				chance = battle.big_hit_count * 10
			4:
				chance = battle.blocked_count * 10 + PsxMath.div(lost * 50, partner.max_hp())
			5:
				chance = battle.hit_count * 5 + battle.big_hit_count * 5
		if Rng.random_limit(100) < chance:
			gains[i] = 1
	drops.clear()
	var no_drops: bool = battle.world.map_record().get("no_battle_drops", false)
	for i in 3:
		var drop := -1
		if i < enemies and not no_drops:
			var d := battle.digimon_of(battle.fighters[i + 1].entity)
			var chance := int(d.get("drop", {}).get("chance", 0))
			if chance > Rng.random_limit(100):
				drop = int(d["drop"]["item"]["id"])
		drops.append(drop)


func starting_lost() -> int:
	return battle.starting_hp - battle.fighters[0].hp()


## handleBattleInjury: injured when randomLimit(100) < tiredness - HP %.
func handle_injury() -> void:
	var partner := battle.fighters[0]
	var ratio := PsxMath.div(100 * partner.hp(), partner.max_hp())
	var chance := battle.world.partner_tiredness() - ratio
	if Rng.random_limit(100) < chance:
		injured = true
		battle.world.set_partner_condition_bit(0x20)


## BTL_appendCommandLearnedText: the highest threshold the brains cross now.
func _command_text() -> void:
	var old: int = battle.initial_stats[0][5]
	var total := old + gains[5]
	if total < 100:
		return
	for threshold in COMMAND_THRESHOLDS:
		if total >= threshold:
			if old < threshold:
				texts.append(["command", [threshold]])
			return


## BTL_appendMPBonusText.
func _mp_bonus_text() -> void:
	var old: int = battle.initial_stats[0][5]
	var total := old + gains[5]
	if total < 700:
		return
	for threshold in MP_THRESHOLDS:
		if total >= threshold:
			if old < threshold:
				texts.append(["mp_bonus", [MP_DISCOUNTS[threshold]]])
			return


## battleMoveLearning (battle_ui.c:223): one of the enemies' techniques, of an element of the
## partner's and in its list, each kept with MOVE_LEARN_CHANCES %.
func move_learning() -> void:
	var w := battle.world
	var partner := battle.fighters[0]
	var d := battle.digimon_of(partner.entity)
	var elements := battle.elements_of(partner.entity)
	var slots: Array = d.get("c", {}).get("moves", [])
	var candidates := []
	for t in battle.used_moves:
		if w.has_move(t):
			continue
		var j := elements.find(battle.element(t))
		if j < 0:
			continue
		if not t in slots:
			continue
		if data.learn_chance(t, j) > Rng.random_limit(100):
			candidates.append(t)
	if candidates.is_empty():
		return
	learned = candidates[Rng.random_limit(candidates.size())]
	w.learn_move(learned)
	texts.append(["learned", [learned]])


## tickPostBattleStatsBox + renderPostBattleStatsBox's counting: after 100 frames one point a
## frame into the starting stats (sound 0x16); ✕ / △ adds them all at once. Returns true when done.
func tick_stats(pressed: int) -> bool:
	if stats_timer > 0:
		stats_timer -= 1
	if pressed & (Pad.CONFIRM | Pad.CANCEL):
		skip = true
	var initial: Array = battle.initial_stats[0]
	if skip:
		for i in 6:
			if gains[i] != 0:
				initial[i] = mini(initial[i] + gains[i], 9999 if i < 2 else 999)
				gains[i] = 0
		stats_timer = 0
	else:
		for i in 6:
			if gains[i] > 0 and stats_timer == 0:
				battle.world.play_sound(0, 0x16)
				gains[i] -= 1
				initial[i] = mini(initial[i] + 1, 9999 if i < 2 else 999)
				break
	return not gains.any(func(g): return g != 0) and stats_timer == 0


## tickBitBox: one bit a frame (sound 0x16), or all with ✕ / △; money capped at 999,999; sound
## 0x17 at the end. Returns true when counted.
func tick_bits(pressed: int) -> bool:
	if bits == 0:
		return true
	if pressed & (Pad.CONFIRM | Pad.CANCEL):
		skip = true
	var w := battle.world
	if skip:
		w.add_money(bits)
		bits = 0
	else:
		w.play_sound(0, 0x16)
		bits -= 1
		w.add_money(1)
	if bits == 0:
		w.play_sound(0, 0x17)
	return bits == 0
