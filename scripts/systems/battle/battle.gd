class_name Battle
extends RefCounted
## The field battle's rules (specs/battle.md §2): btl/battle_setup.c, btl/battle_main.c and the
## battle parts of main/battle_tick.c, ported function by function under the C names. The world is
## reached only through `world` (BattleWorld); the techniques through `effects` (EffectHost).
## The C's blocking loops are phases (BattleFlow, battle_flow.gd); this class holds the state and
## the per-frame rules they call.
##
## Fighter i is fighters[i] (0 the partner, 1..enemy_count the enemies); its entity is
## fighters[i].entity. Visual and HUD events go out through `visual(kind, args)`.

signal visual(kind: String, args: Array)

# Animation ids (the model contract).
const ANIM_DISTRACTED := 0x13
const ANIM_IDLE := 0x21
const ANIM_IDLE_WEAK := 0x22
const ANIM_WALK_WEAK := 0x23
const ANIM_WALK := 0x24
const ANIM_BLOCK := 0x25
const ANIM_HIT_FRONT := 0x28
const ANIM_HIT_BACK := 0x29
const ANIM_VICTORY := 0x2A
const ANIM_FAINT := 0x2B
const ANIM_GET_UP := 0x2C
const ANIM_MOVE := 0x2E
# Tamer animations.
const TAMER_IDLE := 1
const TAMER_RUN := 3
const TAMER_THROW := 6
const TAMER_FINISHER := 0xA
const TAMER_CHEER := 0xB
const TAMER_POINT := 0xE

## Commands (BTL_SHOUTS order + 8-11).
const CMD_RUN := 1
const CMD_ATTACK := 2
const CMD_YOUR_CALL := 3
const CMD_MODERATE := 4
const CMD_DISTANCE := 5
const CMD_DEFENSIVE := 6
const CMD_CHANGE := 7
const CMD_TECHNIQUE_0 := 8
const CMD_FINISHER := 11

## The combat area for the fighters' moves (0x118 x 0xC8 screen pixels around the start's centre).
const AREA_W := 0x118
const AREA_H := 0xC8
## Ranges (MOVE_DATA.range).
const RANGE_MELEE := 1
const RANGE_AREA := 3
const RANGE_SELF := 4
## The generic technique of effect 0x179 (the aura projectile).
const GENERIC_TECHNIQUE := 0x79

var world: BattleWorld
var effects: EffectHost
var data: Node
var pad_pressed := 0

var fighters: Array[BattleFighter] = []
var enemy_count := 0
## GAME_STATE: 3 loading, 2 set up / ending, 1 fighting.
var game_state := 2
var frame_count := 1
var flee_timer := 0
var no_ai := false
## FINISHING_ENTITY (an entity id, -1 none).
var finishing_entity := -1
var finisher_timer := 0
var finisher_aura := false
var has_taken_damage := false
## FLEE_DISABLED[0]: a battle you can't run from (trigger 1); [1]: the shared technique cooldown.
var no_escape := false
var shared_cooldown := 0
var tamerless := false
var saved_charge_mode := 0
var death_countdown := 0
var countdown_shown := false
var toggle_lifebar := false
## INITIAL_COMBAT_STATS: per fighter [hp, mp, off, def, speed, brains].
var initial_stats: Array = []
var predefined := false

# PlayerData (combat.h).
var command_delay := 0
var current_command := CMD_YOUR_CALL
var buffered_command := CMD_YOUR_CALL
var hovered_command := 0
var available_commands: Array[int] = []
var finisher_chargeup := 0
var chargeup_time := -1
var recent_targets: Array[int] = [0xFF, 0xFF]
var recent_index := 0
var change_target := false
var used_moves: Array[int] = []
var hit_count := 0
var blocked_count := 0
var statused_count := 0
## unk2: hits that took at least 20 % of the partner's max HP.
var big_hit_count := 0
var starting_hp := 0
## unk25 per fighter: frames since its HP bar last changed (shown while < 21).
var bar_timers: Array[int] = [0xFF, 0xFF, 0xFF, 0xFF]
## The enemy HP bars BTL_renderEnemyHPBars drew this frame (the HUD draws these).
var bars_shown: Array[bool] = [false, false, false, false]
var tamer_idle_timer := 0

var _moves := {}
var _techniques := {}


func _init(battle_world: BattleWorld, effect_host: EffectHost, game_data: Node) -> void:
	world = battle_world
	effects = effect_host
	data = game_data


# --- data -----------------------------------------------------------------------------------------

func move(technique: int) -> Dictionary:
	if not _moves.has(technique):
		_moves[technique] = data.move(technique) if technique >= 0 and technique != 0xFF else {}
	return _moves[technique]


func _move_int(technique: int, field: String) -> int:
	var m := move(technique)
	if not m.has(field):
		return 0
	var v = m[field]
	return int(v["id"]) if v is Dictionary else int(v)


func power(t: int) -> int:
	return _move_int(t, "power")


func mp_cost(t: int) -> int:
	return _move_int(t, "mp_cost")


func move_range(t: int) -> int:
	return _move_int(t, "range")


func element(t: int) -> int:
	return _move_int(t, "element")


func is_finisher(t: int) -> bool:
	return move(t).get("category", "") == "finisher"


func is_counter(t: int) -> bool:
	return move(t).get("counter", false)


func needs_target(t: int) -> bool:
	return move(t).get("flags", {}).get("needs_target", false)


func has_shared_cooldown(t: int) -> bool:
	return move(t).get("flags", {}).get("shared_cooldown", false)


func digimon_of(entity: int) -> Dictionary:
	var type := world.digimon_type(entity)
	return data.digimon(type) if type >= 0 else {}


func level_of(entity: int) -> int:
	return int(digimon_of(entity).get("level", {}).get("id", 0))


func elements_of(entity: int) -> Array:
	var out := []
	for e in digimon_of(entity).get("elements", []):
		out.append(int(e["id"]))
	while out.size() < 3:
		out.append(0xFF)
	return out


func type_factor(attack_element: int, defender_element: int) -> int:
	return data.type_factor(attack_element, defender_element)


## entityGetTechFromAnim (utils2.c:333): the technique of an animation (0x2E + slot).
func technique_of(entity: int, anim: int) -> int:
	if anim == 0xFF or anim < ANIM_MOVE:
		return 0xFF
	var type := world.digimon_type(entity)
	var key := type * 256 + anim
	if _techniques.has(key):
		return _techniques[key]
	var d := digimon_of(entity)
	var result := 0xFF
	var overrides: Dictionary = d.get("anim_technique", {})
	if overrides.has(str(anim)):
		result = int(overrides[str(anim)])
	else:
		var slots: Array = d.get("c", {}).get("moves", [])
		var k := anim - ANIM_MOVE
		if k < slots.size():
			result = int(slots[k])
	_techniques[key] = result
	return result


## An equipped move as the battle reads it: an animation id stays; a technique key (the partner's
## stats, specs/game_state.md) becomes 0x2E + the technique's slot in the Digimon's list, or 0xFF
## when the Digimon doesn't have it.
func anim_of_move(m: Variant, entity: int) -> int:
	if m == null:
		return 0xFF
	if not m is String:
		return int(m)
	var id := int(data.id_of("moves/move_data", m))
	var slots: Array = digimon_of(entity).get("c", {}).get("moves", [])
	var k := slots.find(id)
	if k < 0:
		k = slots.find(float(id))
	return ANIM_MOVE + k if k >= 0 else 0xFF


func fighter_technique(f: BattleFighter, anim: int) -> int:
	return technique_of(f.entity, anim)


# --- helpers -------------------------------------------------------------------------------------

func fighter_at(entity: int) -> BattleFighter:
	for f in fighters:
		if f.entity == entity:
			return f
	return null


## BTL_getFighterSlot.
func fighter_slot(entity: int) -> int:
	for i in fighters.size():
		if fighters[i].entity == entity:
			return i
	return -1


## BTL_isFighterDefeated.
func is_defeated(slot: int) -> bool:
	if slot < 0 or slot >= fighters.size():
		return true
	var f := fighters[slot]
	return f.hp() - f.hp_damage <= 0


func is_partner(f: BattleFighter) -> bool:
	return f == fighters[0]


func _emit(kind: String, args: Array = []) -> void:
	visual.emit(kind, args)


func distance_squared(a: int, b: int) -> int:
	var pa := world.location(a)
	var pb := world.location(b)
	return (pa.x - pb.x) * (pa.x - pb.x) + (pa.z - pb.z) * (pa.z - pb.z)


func _radius(entity: int) -> int:
	return int(digimon_of(entity).get("radius", 0))


func look_at(entity: int, target: int) -> void:
	world.look_at_location(entity, world.location(target))


# --- animations (main/btl.c) ----------------------------------------------------------------------

## startBattleIdleAnimation: 0x22 when weak (HP <= max / 5) or poisoned, else 0x21.
func start_idle(f: BattleFighter) -> void:
	var weak := f.has(BattleFighter.POISONED) or f.hp() <= PsxMath.div(f.max_hp(), 5)
	world.start_animation(f.entity, ANIM_IDLE_WEAK if weak else ANIM_IDLE)


## handleBattleIdle: idle unless walking slowly already; the finisher's user is left alone.
func battle_idle(f: BattleFighter) -> void:
	if not no_ai or f.entity != finishing_entity:
		var anim := world.animation_id(f.entity)
		if anim != ANIM_IDLE and anim != ANIM_IDLE_WEAK:
			start_idle(f)


## BTL_startWalkingAnimation.
func start_walking(f: BattleFighter) -> void:
	var weak := f.has(BattleFighter.POISONED) or f.hp() <= PsxMath.div(f.max_hp(), 5)
	world.start_animation(f.entity, ANIM_WALK_WEAK if weak else ANIM_WALK)


## BTL_setWalking.
func set_walking(f: BattleFighter) -> void:
	var anim := world.animation_id(f.entity)
	if anim != ANIM_WALK and anim != ANIM_WALK_WEAK:
		start_walking(f)


# --- set-up (BTL_initializeCombat, battle_setup.c:43) ----------------------------------------------

## `entity_ids`: the partner's entity first, then the enemies'.
func initialize_combat(entity_ids: Array) -> void:
	fighters.clear()
	for e in entity_ids:
		var f := BattleFighter.new()
		f.entity = int(e)
		f.stats = world.stats(f.entity)
		f.resolve_move = anim_of_move.bind(f.entity)
		fighters.append(f)
	enemy_count = fighters.size() - 1
	death_countdown = 0
	countdown_shown = false
	finisher_aura = false
	chargeup_time = -1
	saved_charge_mode = fighters[0].charge_mode()
	finishing_entity = -1
	shared_cooldown = 0
	finisher_timer = 0
	flee_timer = 0
	toggle_lifebar = false
	frame_count = 1
	recent_index = 0
	change_target = false
	no_ai = false
	has_taken_damage = false
	tamerless = world.trigger(2)
	recent_targets = [0xFF, 0xFF]
	used_moves.clear()
	blocked_count = 0
	hit_count = 0
	big_hit_count = 0
	statused_count = 0
	bar_timers = [0xFF, 0xFF, 0xFF, 0xFF]
	for f in fighters:
		f.set_hit(false)
		f.target = BattleFighter.NO_TARGET
		f.hp_damage = 0
		f.mp_damage = 0
		f.flags = 0
		f.move_range = 0
		f.flat_timer = 0
		f.invulnerable_timer = 0
		f.cooldown = 0
		f.finisher_progress = 0
		f.status_fx = -1
		f.active_effect_slot = -1
		f.speed_buffer = 100
		f.band_frames = 0
		f.collided_while_distancing = 0
		var brain := f.brains()
		if brain < 400:
			f.buffs_remaining = brain / 100 + 1
		elif brain < 600:
			f.buffs_remaining = 4
		else:
			f.buffs_remaining = 5
		f.buff_prio_timer = brain / 10 + 5
		f.finisher_goal = 3000 - f.speed()
		f.blocked.clear()
	_set_up_commands()
	initial_stats.clear()
	for f in fighters:
		var b := f.base()
		initial_stats.append([int(b["max_hp"]), int(b["max_mp"]), int(b["offense"]), int(b["defense"]),
				int(b["speed"]), int(b["brains"])])
	var partner := fighters[0]
	if world.partner_condition() & 0x60:
		var b := partner.base()
		for key in ["offense", "defense", "speed", "brains"]:
			b[key] = int(b[key]) - int(b[key]) / 5
	starting_hp = partner.hp()
	_emit("command_menu", [true])


## The command list by brains (battle_setup.c:120-175, systems/battle_command_lists).
func _set_up_commands() -> void:
	var partner := fighters[0]
	var count: int = data.battle_commands(partner.brains())
	var record := {}
	for r in data.system("battle_command_lists"):
		if int(r["count"]) == count:
			record = r
	available_commands.clear()
	for c in record.get("commands", [0xB, 1, 3]):
		available_commands.append(int(c))
	for pair in record.get("technique_slots", []):
		if partner.move_anim(int(pair[0])) != BattleFighter.NO_MOVE:
			available_commands.append(int(pair[1]))
	for c in record.get("after", []):
		available_commands.append(int(c))
	hovered_command = available_commands.size() - 1
	current_command = CMD_YOUR_CALL
	buffered_command = CMD_YOUR_CALL


# --- the frame (BTL_battleMain's loop body) --------------------------------------------------------

## One fighting frame's logic (§2.5 steps 1-4); the objects (tamer, entities, effects, HUD) tick after.
func fight_frame() -> void:
	tick_partner_ai()
	tick_enemy_ai()
	tick_fighter_states()


# --- the partner's AI (BTL_tickPartnerAI, battle_main.c:306) --------------------------------------

func tick_partner_ai() -> void:
	var f := fighters[0]
	var partner := f.entity
	var free := not (f.flags & (BattleFighter.CONFUSED | BattleFighter.STUNNED | BattleFighter.FLATTENED | BattleFighter.DEAD)) \
			and f.flat_timer == 0
	if command_delay == 0:
		current_command = buffered_command
	elif free:
		command_delay -= 1
	if not no_ai:
		if f.hp() > f.hp_damage and f.brains() < 301:
			if frame_count % ((f.brains() / 2 + 1) * 20) == 0:
				if 70 - world.partner_discipline() > Rng.random_limit(100):
					f.flags |= BattleFighter.SENILE
					f.senile_timer = 100
		if f.cooldown >= 2:
			f.cooldown -= 1
		if not f.has(BattleFighter.SENILE):
			increase_speed_buffer(f)
	if f.flags & (BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BLOCKING | BattleFighter.DEAD):
		return
	if f.hp() == 0:
		faint(f, 0)
		return
	var enemies := remaining_enemies(partner)
	if enemies.is_empty():
		battle_idle(f)
		f.move_range = -1
		reset_flatten(0)
		remove_status_effects(f)
		f.flags = BattleFighter.BUSY
		return
	if no_ai:
		return
	if free:
		match current_command:
			CMD_CHANGE:
				if f.target != BattleFighter.NO_TARGET and change_target:
					if enemies.size() == 2:
						f.target = enemies[1] if f.target == enemies[0] else enemies[0]
					elif enemies.size() == 3:
						if recent_targets[0] == 0xFF and recent_targets[1] == 0xFF:
							f.target = nearest_enemy(partner, [1, 1, 1, 1])
							recent_targets[recent_index] = f.target
							recent_index = (recent_index + 1) & 1
						else:
							var i := 1
							while i < 4:
								if f.target != i and recent_targets[(recent_index + 1) & 1] != i:
									break
								i += 1
							recent_targets[recent_index] = f.target
							recent_index = (recent_index + 1) & 1
							f.target = i
					change_target = false
					return
			8, 9, 10:
				var slot := current_command - CMD_TECHNIQUE_0
				if is_move_usable(f, slot):
					if f.target != BattleFighter.NO_TARGET and is_defeated(f.target):
						select_target(f, f.target, false)
					if f.move_anim(slot) != f.queued_anim or f.move_range <= 0:
						setup_queued_move(f, slot)
					apply_charge_requirement(f, fighter_technique(f, f.queued_anim))
					return
			CMD_FINISHER:
				if f.target != 0 and is_defeated(f.target):
					select_target(f, f.target, false)
				if f.move_anim(3) != f.queued_anim or f.move_range <= 0:
					setup_queued_move(f, 3)
				return
		if current_command != CMD_ATTACK and current_command != CMD_MODERATE:
			f.set_charge_mode(saved_charge_mode)
	if f.has(BattleFighter.FLATTENED) and frame_count % 100 == 0:
		f.target = enemies[Rng.random_limit(enemies.size())]
	if f.has(BattleFighter.BUSY):
		return
	if current_command == CMD_RUN:
		f.move_range = 1
		f.flags |= BattleFighter.BUSY
	if f.has(BattleFighter.FLATTENED):
		f.queued_anim = 0
		select_target(f, f.target, false)
		f.move_range = 2
		world.set_flat_sprite(partner, 0)
		f.flags |= BattleFighter.BUSY
		return
	if f.has(BattleFighter.STUNNED):
		return
	if f.has(BattleFighter.CONFUSED):
		select_confused_move(f, 0)
		return
	if f.flags & (BattleFighter.ON_CHARGEUP | BattleFighter.ON_COOLDOWN | BattleFighter.SENILE):
		return
	if not f.has(BattleFighter.RETARGETED):
		select_target(f, f.target, false)
	var result := -1
	match current_command:
		CMD_ATTACK, CMD_MODERATE:
			var usable := usable_moves(0)
			if not usable.has(1):
				f.cooldown = 0x50
				f.flags |= BattleFighter.ON_CHARGEUP
				return
			if current_command == CMD_ATTACK:
				result = select_move_by_power(0, usable)
				f.set_charge_mode(0)
			else:
				result = select_move_by_mp(0, usable)
				f.set_charge_mode(2)
	if result == -1:
		select_partner_move(f, 0)
	else:
		setup_queued_move(f, result)


# --- the enemies' AI (BTL_tickEnemyAI, battle_main.c:515) -----------------------------------------

func tick_enemy_ai() -> void:
	if frame_count % 20 == 0:
		for f in fighters:
			if f.buff_prio_timer != 0:
				f.buff_prio_timer -= 1
	var partner := fighters[0]
	for i in range(1, enemy_count + 1):
		var f := fighters[i]
		if not no_ai:
			if f.hp() > f.hp_damage and f.brains() < 301:
				if frame_count % ((f.brains() / 2 + 1) * 20) == 0:
					if (300 - f.brains()) / 4 > Rng.random_limit(100):
						f.flags |= BattleFighter.SENILE
						f.senile_timer = 100
			if not f.has(BattleFighter.SENILE):
				increase_speed_buffer(f)
			if f.cooldown >= 2:
				f.cooldown -= 1
		if f.flags & (BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BLOCKING | BattleFighter.DEAD):
			continue
		if f.hp() == 0:
			faint(f, i)
			continue
		if f.hp() <= f.hp_damage:
			battle_idle(f)
			f.move_range = -1
			reset_flatten(i)
			remove_status_effects(f)
			f.flags &= ~BattleFighter.STATUSES
			continue
		if partner.hp() == 0:
			battle_idle(f)
			reset_flatten(i)
			f.flags &= ~(BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BLOCKING)
			f.flags |= BattleFighter.BUSY
			f.move_range = -1
			continue
		if no_ai:
			return
		if f.has(BattleFighter.BUSY):
			continue
		if f.has(BattleFighter.FLATTENED):
			f.queued_anim = 0
			f.target = 0
			f.move_range = 2
			world.start_animation(f.entity, ANIM_WALK_WEAK)
			world.set_flat_sprite(f.entity, 0)
			f.flags |= BattleFighter.BUSY
			continue
		if f.has(BattleFighter.STUNNED):
			continue
		if f.has(BattleFighter.CONFUSED):
			select_confused_move(f, i)
			continue
		if f.flags & (BattleFighter.SENILE | BattleFighter.ON_CHARGEUP | BattleFighter.ON_COOLDOWN):
			continue
		if f.flat_timer == 0:
			var anim := f.move_anim(3)
			if anim != BattleFighter.NO_MOVE:
				var t := fighter_technique(f, anim)
				if is_finisher(t) and f.finisher_progress == f.finisher_goal:
					f.target = 0
					setup_queued_move(f, 3)
					f.finisher_progress = 0
					continue
		if not f.has(BattleFighter.RETARGETED):
			f.target = 0
		# Bone 1 off a 200 x 160 screen box: keep away (mode 2), else a random mode 0 / 1.
		var screen := world.screen_position(f.entity, 1)
		if absi(screen.x) > 100 or absi(screen.y) > 80:
			f.set_charge_mode(2)
		else:
			f.set_charge_mode(Rng.random_limit(2))
		select_enemy_move(f, i)


# --- fighter states (BTL_tickFighterStates, battle_main.c:648) -------------------------------------

func tick_fighter_states() -> void:
	if shared_cooldown > 0:
		shared_cooldown -= 1
	for i in fighters.size():
		var f := fighters[i]
		add_finisher_progress(f, 1)
		var target := -1
		if f.target != BattleFighter.NO_TARGET and f.target < fighters.size():
			target = f.target
		if f.has(BattleFighter.ATTACKING):
			tick_attack_state(f, i)
		elif f.flags & (BattleFighter.KNOCKED_BACK | BattleFighter.BLOCKING):
			tick_hit_state(f, i)
		elif f.move_range != -1:
			if f.has(BattleFighter.FLATTENED):
				tick_flat_state(f, target)
			elif f.has(BattleFighter.STUNNED):
				if world.animation_id(f.entity) != ANIM_IDLE_WEAK:
					world.start_animation(f.entity, ANIM_IDLE_WEAK)
				world.set_animation_playing(f.entity, false)
			elif f.has(BattleFighter.CONFUSED):
				tick_confused_state(f, target, i)
			elif f.has(BattleFighter.SENILE):
				tick_senile_state(f)
			elif f.has(BattleFighter.ON_CHARGEUP):
				tick_charge_state(f, target)
			elif f.has(BattleFighter.ON_COOLDOWN):
				tick_cooldown_state(f, target)
			else:
				tick_queued_move(f, target, i)
	tick_attack_hits()
	tick_status_effects()


func _target_entity(target: int) -> int:
	return fighters[target].entity if target >= 0 and target < fighters.size() else -1


## BTL_tickAttackState: an attack is held while another fighter counters it.
func tick_attack_state(f: BattleFighter, index: int) -> void:
	var e := f.entity
	if not world.animation_playing(e) and world.animation_frame(e) != world.animation_frame_count(e):
		var countered := false
		for i in fighters.size():
			if i == index:
				continue
			var other := fighters[i]
			if is_counter(technique_of(other.entity, world.animation_id(other.entity))) and other.target == index:
				countered = true
				break
		if countered:
			return
		world.set_animation_playing(e, true)
	tick_fighter_action(index)


## BTL_tickHitState.
func tick_hit_state(f: BattleFighter, index: int) -> void:
	tick_fighter_action(index)
	if not world.animation_playing(f.entity):
		f.invulnerable_timer -= 1
		if f.invulnerable_timer == 0:
			world.set_animation_playing(f.entity, true)


func tick_flat_state(f: BattleFighter, target: int) -> void:
	if no_ai:
		battle_idle(f)
		return
	if not handle_partner_move_command(f, target):
		tick_ranged_attack(f, target, GENERIC_TECHNIQUE)
		if f.has(BattleFighter.ATTACKING):
			world.set_flat_sprite(f.entity, 2)


func tick_confused_state(f: BattleFighter, target: int, index: int) -> void:
	if no_ai:
		battle_idle(f)
		return
	if f.flags & (BattleFighter.ON_COOLDOWN | BattleFighter.ON_CHARGEUP):
		confused_rotate(f)
		set_walking(f)
		world.collision_grace(f.entity, -1, AREA_W, AREA_H)
		if f.cooldown < 2:
			f.flags &= ~BattleFighter.ON_COOLDOWN
			f.cooldown = 0
		return
	if target < 0:
		confused_rotate(f)
		if tick_melee_attack(f, -1):
			world.collision_grace(f.entity, -1, AREA_W, AREA_H)
		if f.has(BattleFighter.ATTACKING):
			return
		if Rng.random_limit(100) >= 5:
			return
		battle_idle(f)
		start_queued_move(f, -1)
		return
	match f.move_range:
		1:
			if tick_melee_attack(f, target):
				world.collision_grace(f.entity, _target_entity(target), AREA_W, AREA_H)
		2, 3:
			tick_ranged_attack(f, target, fighter_technique(f, f.queued_anim))
		4:
			battle_idle(f)
			start_queued_move(f, target)


func tick_senile_state(f: BattleFighter) -> void:
	f.senile_timer -= 1
	if f.senile_timer == 0:
		f.flags &= ~(BattleFighter.BUSY | BattleFighter.SENILE)
		return
	if world.animation_id(f.entity) != ANIM_DISTRACTED:
		world.start_animation(f.entity, ANIM_DISTRACTED)


func tick_charge_state(f: BattleFighter, target: int) -> void:
	if no_ai:
		battle_idle(f)
		return
	var commanded := handle_partner_move_command(f, target)
	var te := _target_entity(target)
	if f.cooldown != 0:
		if not commanded:
			match f.charge_mode():
				0:
					maintain_target_distance(f, target)
				1:
					battle_idle(f)
					if te >= 0:
						look_at(f.entity, te)
					f.collided_while_distancing = 0
				2:
					set_walking(f)
					back_away(f, target)
		if f.cooldown < 2:
			f.flags &= ~(BattleFighter.BUSY | BattleFighter.ON_CHARGEUP)
			f.cooldown = 0
		return
	if commanded:
		return
	match f.charge_mode():
		0:
			battle_idle(f)
			if te >= 0:
				look_at(f.entity, te)
			f.collided_while_distancing = 0
			if f.speed_buffer > 0:
				f.flags &= ~BattleFighter.ON_CHARGEUP
		1:
			maintain_target_distance(f, target)
			var t := fighter_technique(f, f.queued_anim)
			if f.speed_buffer == 100 or f.speed_buffer >= power(t):
				f.flags &= ~BattleFighter.ON_CHARGEUP
		2:
			set_walking(f)
			back_away(f, target)
			if f.speed_buffer == 100:
				f.flags &= ~BattleFighter.ON_CHARGEUP


func tick_cooldown_state(f: BattleFighter, target: int) -> void:
	if no_ai:
		battle_idle(f)
		return
	match f.charge_mode():
		0, 1:
			maintain_target_distance(f, target)
		2:
			set_walking(f)
			back_away(f, target)
	if f.cooldown < 2:
		f.flags &= ~(BattleFighter.BUSY | BattleFighter.ON_COOLDOWN)
		f.cooldown = 0


func tick_queued_move(f: BattleFighter, target: int, _index: int) -> void:
	if no_ai and finishing_entity != f.entity:
		battle_idle(f)
		return
	if handle_partner_move_command(f, target):
		return
	match f.move_range:
		1:
			if tick_melee_attack(f, target):
				world.collision_grace(f.entity, _target_entity(target), AREA_W, AREA_H)
		2, 3:
			tick_ranged_attack(f, target, fighter_technique(f, f.queued_anim))
		4:
			battle_idle(f)
			start_queued_move(f, target)


## BTL_handlePartnerMoveCommand: Run, Defensive and Distance move the partner themselves.
func handle_partner_move_command(f: BattleFighter, target: int) -> bool:
	if no_ai or not is_partner(f):
		return false
	var te := _target_entity(target)
	match current_command:
		CMD_RUN:
			set_walking(f)
			move_toward_location(f, world.location(0), 0, 0)
			if world.is_off_screen(f.entity, 0x140, 0xF0):
				world.start_animation(f.entity, ANIM_IDLE)
				world.set_step_held(f.entity, true)
			f.collided_while_distancing = 0
			return true
		CMD_DEFENSIVE:
			battle_idle(f)
			if te >= 0:
				look_at(f.entity, te)
			f.collided_while_distancing = 0
			return true
		CMD_DISTANCE:
			if te < 0:
				return true
			var reach := longest_reach(te) + 0x9C400
			var anim := world.animation_id(f.entity)
			if anim >= ANIM_WALK_WEAK and anim < 0x25:
				reach += 0x27100
			if distance_squared(f.entity, te) < reach:
				set_walking(f)
				back_away(f, target)
			else:
				f.collided_while_distancing = 0
				battle_idle(f)
				look_at(f.entity, te)
			return true
	return false


## BTL_tickMeleeAttack: walk to contact, then start. Returns true when the step was blocked.
func tick_melee_attack(f: BattleFighter, target: int) -> bool:
	var e := f.entity
	world.set_step_held(e, false)
	var orig := world.rotation_y(e)
	var te := _target_entity(target)
	if te >= 0:
		var contact := _radius(e) + _radius(te)
		if distance_squared(e, te) <= contact * contact:
			battle_idle(f)
			if no_ai:
				if finishing_entity != e:
					return false
				if finisher_timer > 0:
					finisher_timer -= 1
					look_at(e, te)
					return false
			else:
				var t := fighter_technique(f, f.queued_anim)
				if is_finisher(t):
					_start_finisher(f, t, false)
					return false
			if is_move_on_cooldown(f):
				return false
			world.start_animation(e, f.queued_anim)
			f.flags |= BattleFighter.ATTACKING
			setup_move_execution(f, target)
			return false
		if not no_ai:
			set_walking(f)
			look_at(e, te)
		else:
			if finishing_entity != e:
				return false
			if finisher_timer > 0:
				finisher_timer -= 1
				look_at(e, te)
				return false
			world.start_animation(e, f.queued_anim)
			f.flags |= BattleFighter.ATTACKING
			setup_move_execution(f, target)
			return false
	else:
		set_walking(f)
	if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
		return false
	world.set_rotation_y(e, orig)
	return true


## The finisher's wind-up (BTL_tickMeleeAttack / BTL_startQueuedMove): the AI stops, the aura
## shows, the partner's charge-up gauge opens, 80 frames.
func _start_finisher(f: BattleFighter, technique: int, look: bool) -> void:
	no_ai = true
	finishing_entity = f.entity
	if is_partner(f):
		initialize_finisher_chargeup()
	if look and f.target >= 0 and f.target < fighters.size():
		look_at(f.entity, fighters[f.target].entity)
	world.start_animation(f.entity, f.queued_anim)
	world.set_animation_playing(f.entity, false)
	finisher_aura = true
	_emit("finisher_aura", [f.entity, true, technique])
	finisher_timer = 0x50


## BTL_tickRangedAttack: keep the technique's distance band, then start.
func tick_ranged_attack(f: BattleFighter, target: int, technique: int) -> void:
	if f.band_frames > 0x50:
		start_queued_move(f, target)
		f.band_frames = 0
		return
	if no_ai and f.entity == finishing_entity:
		start_queued_move(f, target)
		return
	var te := _target_entity(target)
	if te < 0:
		return
	var dist := distance_squared(f.entity, te)
	var radii := _radius(f.entity) + _radius(te)
	var total := _move_int(technique, "distance_squared") + radii * radii
	if dist > total + total * 3 / 10:
		set_walking(f)
		move_toward_location(f, world.location(te), AREA_W, AREA_H)
		f.band_frames += 1
		return
	if dist < total - total * 3 / 10:
		set_walking(f)
		back_away(f, target)
		f.band_frames += 1
		return
	f.band_frames = 0
	battle_idle(f)
	if f.has(BattleFighter.FLATTENED):
		if frame_count % 40 == 0:
			start_queued_move(f, target)
		else:
			look_at(f.entity, te)
	else:
		start_queued_move(f, target)


## BTL_moveTowardLocation.
func move_toward_location(f: BattleFighter, target: Vector3i, w: int, h: int) -> void:
	var facing := world.rotation_y(f.entity)
	world.look_at_location(f.entity, target)
	if world.check_collision(f.entity, -1, w, h) != BattleWorld.FREE:
		world.set_rotation_y(f.entity, facing)
		world.collision_grace(f.entity, -1, w, h)


## BTL_getMoveWithHighestDistance.
func longest_reach(entity: int) -> int:
	var f := fighter_at(entity)
	var best := 0
	if f == null:
		return 0
	for i in 4:
		var anim := f.move_anim(i)
		if anim != BattleFighter.NO_MOVE:
			best = maxi(best, _move_int(technique_of(entity, anim), "distance_squared"))
	return best


## BTL_backAwayFromTarget.
func back_away(f: BattleFighter, target: int) -> void:
	var e := f.entity
	var te := _target_entity(target)
	var orig := world.rotation_y(e)
	if te >= 0:
		look_at(e, te)
	var away := (world.rotation_y(e) + 0x800) & 0xFFF
	if f.collided_while_distancing == 0:
		world.set_rotation_y(e, away)
		var hit := world.check_collision(e, -1, AREA_W, AREA_H)
		if hit != BattleWorld.FREE:
			f.collided_while_distancing = 1
			find_unblocked_rotation(e, hit, orig)
		return
	world.set_rotation_y(e, orig)
	var target_rot := world.rotation_y(te) if te >= 0 else -1
	if orig == target_rot:
		world.set_rotation_y(e, (orig + 0x400) & 0xFFF)
		if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
			return
		world.set_rotation_y(e, (orig + 0xC00) & 0xFFF)
		if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
			return
		world.set_rotation_y(e, orig)
		var hit := world.check_collision(e, -1, AREA_W, AREA_H)
		if hit != BattleWorld.FREE:
			find_unblocked_rotation(e, hit, orig)
		return
	var ccw := PsxMath.s16(orig - away)
	if ccw < 0:
		ccw = (ccw + 0x1000) & 0xFFF
	var cw := PsxMath.s16(away - orig)
	if cw < 0:
		cw = (cw + 0x1000) & 0xFFF
	if ccw - cw < 0:
		world.set_rotation_y(e, (orig + 0xFEC) & 0xFFF if ccw > 20 else (orig + 0x1000 - ccw) & 0xFFF)
	else:
		world.set_rotation_y(e, (orig + 20) & 0xFFF if cw > 20 else (orig + cw) & 0xFFF)
	if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
		return
	world.set_rotation_y(e, orig)
	var hit := world.check_collision(e, -1, AREA_W, AREA_H)
	if hit != BattleWorld.FREE:
		find_unblocked_rotation(e, hit, orig)


## BTL_findUnblockedRotation (battle_main.c:1756).
func find_unblocked_rotation(e: int, hit: int, orig: int) -> void:
	if hit != BattleWorld.HIT_AREA:
		world.set_rotation_y(e, orig)
		world.collision_grace(e, -1, AREA_W, AREA_H)
		return
	var base_index := world.rotation_y(e) / 1024
	var base_rot: int = [0, 1024, 2048, 3072][base_index]
	var cand: Array[int] = [base_rot, (base_rot + 0x400) & 0xFFF, 0]
	var i := 0
	while i < 2:
		world.set_rotation_y(e, cand[i])
		if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
			break
		i += 1
	var offset := 0xC00 if i == 0 else (0x400 if i == 1 else 0x800)
	var j := 0
	while j < 3:
		cand[j] = (base_rot + offset + j * 0x200) & 0xFFF
		world.set_rotation_y(e, cand[j])
		var blocked := world.check_collision(e, -1, AREA_W, AREA_H) != BattleWorld.FREE
		if i < 2 and blocked:
			break
		if i >= 2 and blocked:
			break
		j += 1
	if i >= 2 and j == 3:
		world.set_rotation_y(e, (orig + 0x800) & 0xFFF)
		if world.check_collision(e, -1, AREA_W, AREA_H) == BattleWorld.FREE:
			return
	if j != 3:
		world.set_rotation_y(e, orig)
		world.collision_grace(e, -1, AREA_W, AREA_H)
		return
	world.set_rotation_y(e, (cand[0] + Rng.random_limit(0x400)) & 0xFFF)
	if world.check_collision(e, -1, AREA_W, AREA_H) != BattleWorld.FREE:
		world.set_rotation_y(e, orig)
		world.collision_grace(e, -1, AREA_W, AREA_H)


## BTL_tickFighterAction (battle_main.c:1509): the end of an action.
func tick_fighter_action(index: int) -> void:
	var f := fighters[index]
	var e := f.entity
	world.set_step_held(e, world.check_collision(e, -1, AREA_W, AREA_H) != BattleWorld.FREE)
	if no_ai and finishing_entity == e and finisher_timer > 0:
		return
	if f.flags & (BattleFighter.FLATTENED | BattleFighter.ATTACKING) == (BattleFighter.FLATTENED | BattleFighter.ATTACKING):
		f.flat_attack_timer -= 1
		match f.flat_attack_timer:
			0x1C:
				_emit("aura_projectile", [e])
			0xA:
				world.set_flat_sprite(e, 0)
			0:
				world.set_animation_playing(e, false)
	if world.animation_playing(e):
		return
	if finishing_entity == e:
		no_ai = false
		finishing_entity = -1
	f.collided_while_distancing = 0
	if f.has(BattleFighter.ATTACKING):
		if index == 0:
			hit_count += 1
		f.flags &= ~BattleFighter.RETARGETED
		f.flags |= BattleFighter.ON_COOLDOWN
		f.cooldown = 0x28
		add_finisher_progress(f, f.finisher_goal * 2 / 50)
	if f.invulnerable_timer <= 0:
		if f.has(BattleFighter.FLATTENED):
			world.set_flat_sprite(e, 0)
		if not f.has(BattleFighter.ATTACKING):
			f.set_hit(false)
		if f.has(BattleFighter.BLOCKING):
			f.flags &= ~BattleFighter.BLOCKING
			f.blocked.clear()
		else:
			f.flags &= ~(BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BUSY | BattleFighter.BLOCKING)
	if not f.has(BattleFighter.KNOCKED_BACK):
		if f.flat_timer == -1:
			f.flat_timer = 0x41
	else:
		f.senile_timer = 0
		f.flags &= ~BattleFighter.SENILE


## BTL_confusedRotate: 20 % of the frames a turn of up to ± 0x200.
func confused_rotate(f: BattleFighter) -> void:
	if Rng.random_limit(10) >= 8:
		var rot := world.rotation_y(f.entity) + Rng.random_limit(0x400) - 0x200
		world.set_rotation_y(f.entity, rot + 0x1000 if rot < 0 else rot % 4096)


## BTL_maintainTargetDistance.
func maintain_target_distance(f: BattleFighter, target: int) -> void:
	var anim := world.animation_id(f.entity)
	if anim >= ANIM_WALK_WEAK and anim < 0x25:
		maintain_distance_range(f, target, 0x27100, 0x4E200)
	else:
		maintain_distance_range(f, target, 0, 0x75300)


## BTL_maintainDistanceRange.
func maintain_distance_range(f: BattleFighter, target: int, near: int, far: int) -> void:
	var te := _target_entity(target)
	if te < 0:
		return
	var dist := distance_squared(f.entity, te)
	var contact := _radius(f.entity) + _radius(te) + 0xC8
	contact *= contact
	if dist < contact + near:
		set_walking(f)
		back_away(f, target)
	elif dist > contact + far:
		set_walking(f)
		move_toward_location(f, world.location(te), AREA_W, AREA_H)
	else:
		f.collided_while_distancing = 0
		battle_idle(f)
		look_at(f.entity, te)


## BTL_increaseSpeedBuffer.
func increase_speed_buffer(f: BattleFighter) -> void:
	if f.speed_buffer < 100:
		if frame_count % 2 == 0:
			f.speed_buffer += f.speed() / 100 + 1
		if f.speed_buffer >= 0x65:
			f.speed_buffer = 100


## BTL_faintDigimon.
func faint(f: BattleFighter, index: int) -> void:
	f.set_hit(true)
	f.flags |= BattleFighter.DEAD
	world.start_animation(f.entity, ANIM_FAINT)
	reset_flatten(index)
	remove_status_effects(f)
	f.flags &= ~(BattleFighter.STATUSES | BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BLOCKING)
	f.flags |= BattleFighter.BUSY
	f.move_range = -1
	reset_fighter_action(f)


## BTL_resetFlatten.
func reset_flatten(index: int) -> void:
	var f := fighters[index]
	world.set_flat_sprite(f.entity, -1)
	f.flags &= ~BattleFighter.FLATTENED
	f.flat_timer = 0
	var s := int(digimon_of(f.entity).get("battle_scale", 0x1000))
	world.set_scale(f.entity, Vector3i(s, s, s))


# --- choosing and starting a technique (§2.10) ----------------------------------------------------

## BTL_isMoveUsable.
func is_move_usable(f: BattleFighter, slot: int) -> bool:
	var anim := f.move_anim(slot)
	if anim == BattleFighter.NO_MOVE:
		return false
	var t := fighter_technique(f, anim)
	if is_counter(t) or is_finisher(t):
		return false
	if move_range(t) == RANGE_SELF and f.buffs_remaining == 0:
		return false
	if f.target == BattleFighter.NO_TARGET and needs_target(t):
		return false
	var mp := mp_cost(t) * 3
	if is_partner(f):
		var brain := f.brains()
		if brain >= 700:
			if brain == 999:
				mp -= mp / 5
			elif brain >= 900:
				mp -= mp * 15 / 100
			elif brain >= 800:
				mp -= mp / 10
			else:
				mp -= mp / 20
		if world.partner_condition() & 0x60:
			mp += mp / 2
	return f.mp() >= mp


## BTL_getUsableMoves / BTL_hasAffordableMoves: [usable 0/1 per slot].
func usable_moves(index: int) -> Array:
	var f := fighters[index]
	var out := []
	for i in 4:
		out.append(1 if is_move_usable(f, i) else 0)
	return out


## BTL_setupQueuedMove.
func setup_queued_move(f: BattleFighter, slot: int) -> void:
	f.band_frames = 0
	f.queued_anim = f.move_anim(slot)
	var t := fighter_technique(f, f.queued_anim)
	f.move_range = move_range(t)
	apply_charge_requirement(f, t)
	f.flags |= BattleFighter.BUSY


## BTL_applyChargeRequirement.
func apply_charge_requirement(f: BattleFighter, technique: int) -> void:
	match f.charge_mode():
		0:
			if f.speed_buffer <= 0:
				f.flags |= BattleFighter.ON_CHARGEUP
		1:
			if f.speed_buffer != 100 and f.speed_buffer < power(technique):
				f.flags |= BattleFighter.ON_CHARGEUP
		2:
			if f.speed_buffer < 100:
				f.flags |= BattleFighter.ON_CHARGEUP


## BTL_startQueuedMove.
func start_queued_move(f: BattleFighter, target: int) -> void:
	var e := f.entity
	var te := _target_entity(target)
	var t := fighter_technique(f, f.queued_anim)
	if no_ai:
		if finishing_entity != e:
			return
		if finisher_timer > 0:
			finisher_timer -= 1
			if te >= 0:
				look_at(e, te)
			return
	else:
		if is_finisher(t):
			_start_finisher(f, t, true)
			return
	if is_move_on_cooldown(f):
		return
	if te >= 0:
		var anim := world.animation_id(te)
		if anim == ANIM_HIT_FRONT or anim == ANIM_HIT_BACK:
			return
		if te != e:
			look_at(e, te)
	if has_shared_cooldown(t):
		shared_cooldown = 0x6E
	world.start_animation(e, f.queued_anim)
	f.flags |= BattleFighter.ATTACKING
	if not f.has(BattleFighter.FLATTENED):
		setup_move_execution(f, target)
	else:
		f.flat_attack_timer = 0x1E


## BTL_isMoveOnCooldown.
func is_move_on_cooldown(f: BattleFighter) -> bool:
	return has_shared_cooldown(fighter_technique(f, f.queued_anim)) and shared_cooldown > 0


## BTL_setupMoveExecution (battle_main.c:2494).
func setup_move_execution(f: BattleFighter, target: int) -> void:
	var t := fighter_technique(f, f.queued_anim)
	var attacker := f.entity
	var targeted := _target_entity(target)
	if f.move_range != RANGE_SELF:
		if targeted < 0 and needs_target(t):
			if not is_partner(f):
				targeted = fighters[0].entity
				f.target = 0
			else:
				for i in range(1, enemy_count + 1):
					if not is_defeated(i):
						f.target = i
						targeted = fighters[i].entity
	else:
		targeted = attacker
	remove_move_effect(f)
	if is_partner(f):
		if not is_finisher(t):
			var cost := mp_cost(t) * 3
			if world.partner_condition() & 0x60:
				cost += cost / 2
			var brain := f.brains()
			if brain >= 700:
				if brain == 999:
					cost = cost * 4 / 5
				elif brain >= 900:
					cost = cost * 17 / 20
				elif brain >= 800:
					cost = cost * 9 / 10
				else:
					cost = cost * 19 / 20
			f.mp_damage += cost
	else:
		if not is_finisher(t) and not no_escape:
			f.set_mp(f.mp() - mp_cost(t) * 3)
		if move(t).get("category", "") == "technique":
			if not t in used_moves and used_moves.size() < 12:
				used_moves.append(t)
	f.current()["unk1"] = t + 0x100
	var slot := 0
	while slot < 3 and f.queued_anim != f.move_anim(slot):
		slot += 1
	f.current()["efe_sub_effect"] = effects.start(f.effect_slot[slot], attacker, targeted) if effects != null else -1
	f.active_effect_slot = f.effect_slot[slot]
	if move_range(t) == RANGE_SELF and f.buffs_remaining != 0:
		f.buffs_remaining -= 1
	f.speed_buffer = maxi(f.speed_buffer - power(t), -0x9B)


## BTL_removeMoveEffect.
func remove_move_effect(f: BattleFighter) -> void:
	if f.active_effect_slot != -1 and effects != null:
		effects.stop(f.active_effect_slot, int(f.current().get("efe_sub_effect", -1)))
	f.current()["efe_sub_effect"] = -1
	f.active_effect_slot = -1


## BTL_addFinisherProgress: only for a fighter whose slot 3 holds a finisher.
func add_finisher_progress(f: BattleFighter, amount: int) -> void:
	if not is_finisher(fighter_technique(f, f.move_anim(3))):
		return
	f.finisher_progress = mini(f.finisher_progress + amount, f.finisher_goal)


# --- targets and the AI's choices -----------------------------------------------------------------

## BTL_getRemainingEnemies: the living fighters other than `self_entity` (slots).
func remaining_enemies(self_entity: int) -> Array[int]:
	var out: Array[int] = []
	for i in fighters.size():
		if fighters[i].entity != self_entity and not is_defeated(i):
			out.append(i)
	return out


## BTL_getNearestEnemy.
func nearest_enemy(self_entity: int, flags: Array) -> int:
	var best := 0xFF
	var best_dist := -1
	for i in fighters.size():
		if i < flags.size() and int(flags[i]) == 1 and fighters[i].entity != self_entity and not is_defeated(i):
			var d := distance_squared(self_entity, fighters[i].entity)
			if best_dist < 0 or d < best_dist:
				best_dist = d
				best = i
	return best


## BTL_calculateTargetScore: HP % plus the inverted element factor times Def %.
func target_score(self_entity: int, other_entity: int) -> int:
	var f := fighter_at(self_entity)
	var mult := type_factor(elements_of(self_entity)[0], elements_of(other_entity)[0])
	match mult:
		20: mult = 2
		15: mult = 5
		5: mult = 15
		2: mult = 20
	return PsxMath.s16(f.hp() * 100 / maxi(f.max_hp(), 1) + mult * (f.defense() * 100 / 999) / 10)


## BTL_getWeakestEnemy: [score, slot].
func weakest_enemy(f: BattleFighter) -> Array:
	var best := 1000
	var choice := 0xFF
	var score := 0
	for i in fighters.size():
		var other := fighters[i]
		if other.entity != f.entity and not is_defeated(i):
			if f.target == BattleFighter.NO_TARGET or other.entity != _target_entity(f.target):
				score = target_score(f.entity, other.entity)
				if score < best:
					best = score
					choice = i
	return [score, choice]


## BTL_selectFighterTarget (battle_main.c:3686).
func select_target(f: BattleFighter, target: int, after_hit: bool) -> void:
	if (after_hit and is_partner(f)) or not is_partner(f):
		if target != BattleFighter.NO_TARGET:
			if not is_partner(f):
				if world.npc_record(f.entity).get("targets_partner", false) or Rng.random_limit(100) >= 0x47:
					f.target = 0
					return
			if is_defeated(target):
				return
			f.flags |= BattleFighter.RETARGETED
			f.target = target
		else:
			f.target = 0
		return
	if current_command == CMD_CHANGE:
		if f.target != BattleFighter.NO_TARGET and not is_defeated(f.target):
			return
	var brain := f.brains()
	if brain >= 300:
		var afflicted: Array[int] = []
		for i in fighters.size():
			if fighters[i].entity != f.entity and not is_defeated(i) and fighters[i].flags & BattleFighter.STATUSES:
				afflicted.append(i)
		if afflicted.size() >= 2:
			f.target = afflicted[Rng.random_limit(afflicted.size())]
			return
		if afflicted.size() == 1:
			f.target = afflicted[0]
			return
		var weakest := weakest_enemy(f)
		if f.target == BattleFighter.NO_TARGET or is_defeated(f.target):
			f.target = weakest[1]
			return
		var current := target_score(f.entity, fighters[f.target].entity)
		if weakest[1] == 0xFF:
			return
		if current - int(weakest[0]) < 0x28:
			return
		f.target = weakest[1]
		return
	if brain >= 150:
		if f.target != BattleFighter.NO_TARGET and not is_defeated(f.target):
			return
		f.target = weakest_enemy(f)[1]
		return
	f.target = nearest_enemy(f.entity, [1, 1, 1, 1])


## BTL_retargetAfterHit.
func retarget_after_hit(f: BattleFighter, caster_slot: int) -> void:
	if is_partner(f):
		var chance: int = int(_battle_ai_retarget(f.charge_mode())) - world.partner_discipline()
		if chance <= Rng.random_limit(100) and not is_defeated(f.target):
			return
	select_target(f, caster_slot, true)


func _battle_ai_retarget(mode: int) -> int:
	for r in data.system("battle_ai"):
		if r.has("style") and int(r["style"]) == mode:
			return int(r["retarget_chance"])
	return 0


func _your_call(rank: int, column: String) -> int:
	for r in data.system("battle_ai"):
		if r.has("rank") and int(r["rank"]) == rank:
			return int(r[column])
	return 0


## BTL_calculateElementBonus.
func element_bonus(attack_element: int, defender_element: int) -> int:
	match type_factor(attack_element, defender_element):
		20: return 10
		15: return 7
		10: return 5
		5: return 3
		2: return 1
	return 0


## BTL_getHighestScoredMove / BTL_getLowestScoredMove: the best slot, or -1 on a tie; marks the
## tied slots in `flags`.
static func best_scored(values: Array, flags: Array, count: int, highest: bool) -> int:
	var best: int = values[0]
	for i in range(1, count):
		if (highest and best < values[i]) or (not highest and best > values[i]):
			best = values[i]
	var hits := 0
	var out := -1
	for i in count:
		if best == values[i]:
			hits += 1
			out = i
			flags[i] = 1
		else:
			flags[i] = -1
	return -1 if hits >= 2 else out


## BTL_getRandomUsableMove.
static func random_usable(flags: Array) -> int:
	var picked := []
	for i in 4:
		if i < flags.size() and int(flags[i]) == 1:
			picked.append(i)
	return picked[Rng.random_limit(picked.size())] if not picked.is_empty() else 0


func _score_moves(index: int, flags: Array, by: String) -> Array:
	var f := fighters[index]
	var out := []
	for i in 3:
		if int(flags[i]) == 1:
			var t := fighter_technique(f, f.move_anim(i))
			match by:
				"power": out.append(power(t))
				"mp": out.append(mp_cost(t) * 3)
				"effective": out.append(type_factor(element(t), elements_of(_target_entity(f.target))[0]))
		else:
			out.append(1000 if by == "mp" else -1)
	return out


## BTL_selectMoveByPower: strongest, else most effective, else random.
func select_move_by_power(index: int, flags: Array) -> int:
	var result := best_scored(_score_moves(index, flags, "power"), flags, 3, true)
	if result != -1:
		return result
	result = best_scored(_score_moves(index, flags, "effective"), flags, 3, true)
	if result != -1:
		return result
	return random_usable(flags)


## BTL_selectMoveByMpCost: cheapest, else most effective, else random.
func select_move_by_mp(index: int, flags: Array) -> int:
	var result := best_scored(_score_moves(index, flags, "mp"), flags, 3, false)
	if result != -1:
		return result
	result = best_scored(_score_moves(index, flags, "effective"), flags, 3, true)
	if result != -1:
		return result
	return random_usable(flags)


## BTL_sortScoresDescending / Ascending + BTL_calculateScoreRanks: [keys, groups].
static func sort_scores(values: Array, descending: bool) -> Array:
	var v := values.duplicate()
	var keys := [0, 1, 2]
	for i in v.size():
		var best_value: int = v[i]
		var best := i
		for j in range(i, v.size()):
			if (descending and best_value < v[j]) or (not descending and best_value > v[j]):
				best = j
				best_value = v[j]
		var t = v[i]
		v[i] = v[best]
		v[best] = t
		t = keys[i]
		keys[i] = keys[best]
		keys[best] = t
	var groups := [0, 0, 0]
	var group := 0
	for i in range(1, v.size()):
		if v[i] != v[i - 1]:
			group += 1
		groups[i] = group
	return [keys, groups, v]


## BTL_selectPartnerMove ("Your Call", battle_main.c:3415).
func select_partner_move(f: BattleFighter, index: int) -> void:
	var flags := usable_moves(index)
	if not flags.has(1):
		set_fighter_cooldown(f)
		return
	var weights := [0, 0, 0]
	var keys := [0, 1, 2]
	var groups := [0, 0, 0]
	match f.charge_mode():
		0:
			var values := []
			for i in 3:
				values.append(-1 if int(flags[i]) == 0 else power(fighter_technique(f, f.move_anim(i))))
			var sorted := sort_scores(values, true)
			keys = sorted[0]
			groups = sorted[1]
			for i in 3:
				if f.move_anim(keys[i]) == BattleFighter.NO_MOVE:
					weights[keys[i]] += 5
				elif int(flags[keys[i]]) != 0:
					weights[keys[i]] = _your_call(groups[i], "by_power")
		1:
			for i in 3:
				if f.move_anim(i) == BattleFighter.NO_MOVE:
					weights[i] += 5
				if int(flags[i]) != 0:
					weights[i] += 0x14
		2:
			var values := []
			for i in 3:
				values.append(10000 if int(flags[i]) == 0 else mp_cost(fighter_technique(f, f.move_anim(i))) * 3)
			var sorted := sort_scores(values, false)
			keys = sorted[0]
			groups = sorted[1]
			for i in 3:
				if f.move_anim(keys[i]) == BattleFighter.NO_MOVE:
					weights[keys[i]] += 5
				elif int(flags[keys[i]]) != 0:
					weights[keys[i]] = _your_call(groups[i], "by_mp")
	var own_element: int = elements_of(f.entity)[0]
	var i := 0
	while i < 3:
		if f.move_anim(i) == BattleFighter.NO_MOVE:
			i += 1
			continue
		if int(flags[i]) == 0:
			weights[i] = 0
			i += 1
			continue
		var t := fighter_technique(f, f.move_anim(i))
		if move_range(t) == RANGE_SELF:
			weights[i] += f.buff_prio_timer + element_bonus(element(t), own_element)
			i += 1
			continue
		weights[i] += element_bonus(element(t), elements_of(_target_entity(f.target))[0])
		if move_range(t) != RANGE_AREA:
			i += 1
			continue
		var count := count_living_enemies()
		match f.charge_mode():
			0:
				if f.brains() >= 0xC8 and count >= 2:
					weights[i] += count * 10
			1:
				if f.brains() >= 0xC8 and count >= 2:
					weights[i] += count * 15
			2:
				if f.brains() >= 0xC8 and count >= 2:
					weights[i] += count * 15
				elif f.hp() * 100 / maxi(f.max_hp(), 1) < 0x1F:
					# Quirk kept (specs/battle.md §2.10): this re-ranking reuses the outer `i`, so
					# it leaves the outer loop.
					var values := [-1, -1, -1]
					values[i] = -1 if int(flags[i]) == 0 else _move_int(t, "distance_squared")
					var sorted := sort_scores(values, true)
					keys = sorted[0]
					groups = sorted[1]
					i = 0
					while i < 3:
						if f.move_anim(i) != BattleFighter.NO_MOVE and int(flags[i]) != 0:
							weights[keys[i]] = _your_call(groups[i], "wide")
						i += 1
		i += 1
	var total: int = weights[0] + weights[1] + weights[2]
	var pick := Rng.random_limit(total)
	var running := 0
	var k := 0
	while k < 3:
		if weights[k] != 0:
			running += weights[k]
			if pick < running:
				break
		k += 1
	if k < 3 and f.move_anim(k) != BattleFighter.NO_MOVE:
		setup_queued_move(f, k)
	else:
		f.cooldown = 0x50
		f.flags |= BattleFighter.ON_CHARGEUP


## BTL_countLivingEnemies.
func count_living_enemies() -> int:
	var n := 0
	for i in range(1, enemy_count + 1):
		if not is_defeated(i):
			n += 1
	return n


## BTL_selectConfusedMove: 70 % no target, else a random living one; a random usable technique.
func select_confused_move(f: BattleFighter, index: int) -> void:
	var flags := []
	if Rng.random_limit(10) < 7:
		f.target = BattleFighter.NO_TARGET
	else:
		var enemies := remaining_enemies(f.entity)
		f.target = enemies[Rng.random_limit(enemies.size())] if not enemies.is_empty() else BattleFighter.NO_TARGET
	flags = usable_moves(index)
	if not flags.has(1):
		set_fighter_cooldown(f)
	else:
		setup_queued_move(f, random_usable(flags))


## BTL_setFighterCooldown.
func set_fighter_cooldown(f: BattleFighter) -> void:
	f.cooldown = 0x50
	f.flags |= BattleFighter.ON_CHARGEUP


## BTL_selectEnemyMove (battle_main.c:3804).
func select_enemy_move(f: BattleFighter, index: int) -> void:
	var flags := usable_moves(index)
	if not flags.has(1):
		f.set_charge_mode(2)
		set_fighter_cooldown(f)
		return
	var weights := []
	for i in 4:
		weights.append(f.move_prio(i))
	var other_alive := false
	for j in range(1, enemy_count + 1):
		if j != index and fighters[j].hp() - fighters[j].hp_damage > 0:
			other_alive = true
			break
	for i in 4:
		if f.move_anim(i) == BattleFighter.NO_MOVE:
			continue
		if int(flags[i]) == 0:
			weights[i] = 0
			continue
		var t := fighter_technique(f, f.move_anim(i))
		if other_alive and not world.npc_record(f.entity).get("targets_partner", false) and move_range(t) == RANGE_AREA:
			weights[i] += 0x14
		if move_range(t) == RANGE_SELF:
			weights[i] += f.buff_prio_timer
	var total := 0
	for w in weights:
		total += w
	var pick := Rng.random_limit(total)
	var running := 0
	var k := 0
	while k < 4:
		if weights[k] != 0:
			running += weights[k]
			if pick < running:
				break
		k += 1
	if k < 4 and f.move_anim(k) != BattleFighter.NO_MOVE:
		setup_queued_move(f, k)
	else:
		f.cooldown = 0x50
		f.flags |= BattleFighter.ON_CHARGEUP


# --- hits and damage (BTL_tickAttackHits, battle_main.c:2084) -------------------------------------

## BTL_getAttackTech: the technique of an attack object.
func attack_technique(attack: Dictionary) -> int:
	if int(attack.get("effect_id", 0)) == 0x179:
		return GENERIC_TECHNIQUE
	var caster := int(attack["caster"])
	var slot := fighter_slot(caster)
	if slot < 0:
		return 0xFF
	var f := fighters[slot]
	var i := 0
	while i < 4 and int(attack["effect"]) != f.effect_slot[i]:
		i += 1
	return technique_of(caster, f.move_anim(i) if i < 4 else BattleFighter.NO_MOVE)


## BTL_applyBuffMove: Off / Def / Speed up by the technique's fractions (move_data.buff).
func apply_buff_move(f: BattleFighter, slot: int, technique: int) -> bool:
	var buff: Dictionary = move(technique).get("buff", {})
	if buff.is_empty():
		return false
	var keys := {"off": ["offense", 3], "def": ["defense", 4], "speed": ["speed", 5]}
	for stat in ["off", "def", "speed"]:
		if not buff.has(stat):
			continue
		var key: String = keys[stat][0]
		var value := PsxMath.s16(int(f.base()[key]) * int(buff[stat][0]) / int(buff[stat][1]))
		f.base()[key] = mini(int(f.base()[key]) + value, 999)
		_emit("number", [f.entity, slot, 0xB, value, keys[stat][1]])
	return true


## BTL_calculateHitChance (battle_main.c:1922).
func hit_chance(attacker: int, defender: BattleFighter, technique: int) -> int:
	if level_of(defender.entity) < 3:
		return 100
	if defender.flags & (BattleFighter.STUNNED | BattleFighter.FLATTENED | BattleFighter.SENILE):
		return 100
	if world.partner_condition() & 0x40:
		return 100
	if defender.speed_buffer <= 0:
		return 100
	if world.animation_id(defender.entity) >= ANIM_MOVE:
		return 100
	if is_finisher(technique):
		if defender.has(BattleFighter.BLOCKING):
			defender.flags &= ~BattleFighter.BLOCKING
			defender.invulnerable_timer = 0
		return 100
	if defender.has(BattleFighter.BLOCKING):
		return 0
	var accuracy := _move_int(technique, "accuracy")
	var attacker_f := fighter_at(attacker)
	var x := accuracy / 2 * (defender.speed() - (attacker_f.speed() / 10 if attacker_f != null else 0)) / 999
	var anim := world.animation_id(defender.entity)
	if anim == ANIM_IDLE or anim == ANIM_IDLE_WEAK:
		x = x * 6 / 5
	return clampi(PsxMath.s16(accuracy - x), 0, 100)


## BTL_calculateDamage (battle_main.c:1988).
func calculate_damage(attacker: int, defender: int, technique: int) -> int:
	var sum := 0
	for e in elements_of(defender):
		sum += type_factor(element(technique), e) if e != 0xFF else 10
	var a := fighter_at(attacker)
	var off := a.offense() if a != null else 0
	var d := fighter_at(defender)
	var def := d.defense() if d != null else 0
	if is_counter(technique):
		def = def * 3 / 10
	var dmg := 0
	var pw := power(technique)
	if is_finisher(technique):
		dmg = (off + pw) * sum / 30
	else:
		var diff := clampi(off - def, -500, 500)
		dmg = sum * (pw + diff * pw / 500) / 30 * (Rng.random_limit(0x15) + 0x5A) / 100
	if is_finisher(technique):
		if attacker == fighters[0].entity:
			if finisher_chargeup >= 0x29:
				dmg = dmg * finisher_chargeup / 40
		else:
			dmg = dmg * (Rng.random_limit(0x65) + 0x64) / 100
		dmg = dmg * (Rng.random_limit(0x15) + 0x5A) / 100
	return clampi(dmg, 1, 9999)


## BTL_addBlockedAttack: true for a new (effect, sub-effect) pair.
func add_blocked_attack(f: BattleFighter, attack: Dictionary) -> bool:
	var pair := [int(attack["effect"]), int(attack["sub_effect"])]
	if pair in f.blocked:
		return false
	if f.blocked.size() < BattleFighter.BLOCKED - 1:
		f.blocked.append(pair)
	return true


## BTL_tickAttackHits: one attack object a living fighter a frame.
func tick_attack_hits() -> void:
	for i in fighters.size():
		var f := fighters[i]
		if f.has(BattleFighter.DEAD) or effects == null:
			continue
		var attack := effects.pop_attack_object(f.entity)
		if attack.is_empty():
			continue
		if flee_timer >= 0x13:
			continue
		var e := f.entity
		var t := attack_technique(attack)
		var caster := int(attack["caster"])
		var caster_slot := fighter_slot(caster)
		var own := technique_of(e, world.animation_id(e))
		if is_counter(own) and f.target >= 0 and f.target < fighters.size() and fighters[f.target].entity == caster:
			f.set_hit(false)
			continue
		if apply_buff_move(f, i, t):
			f.set_hit(false)
			continue
		remove_move_effect(f)
		f.flags &= ~(BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING | BattleFighter.BUSY)
		var chance := hit_chance(caster, f, t)
		if e == finishing_entity:
			if i == 0:
				remove_finisher_chargeup()
			if finisher_aura:
				finisher_aura = false
				_emit("finisher_aura", [e, false, -1])
			no_ai = false
			finishing_entity = -1
		var pos: Vector3i = attack["position"]
		if Rng.random_limit(100) < chance:
			retarget_after_hit(f, caster_slot)
			var dmg := calculate_damage(caster, e, t)
			has_taken_damage = true
			if i == 0 and dmg * 100 / maxi(f.max_hp(), 1) >= 0x14:
				big_hit_count += 1
			f.hp_damage = mini(f.hp_damage + dmg, 0x270F)
			f.flags |= BattleFighter.KNOCKED_BACK
			hit_reaction(f, pos, t)
			bar_timers[i] = 0
			_emit("number", [e, i, 0, dmg, 0])
			f.invulnerable_timer = _move_int(t, "iframes")
			world.set_animation_playing(e, false)
			apply_move_status(f, t)
			continue
		if not f.has(BattleFighter.BLOCKING) and move_range(t) == RANGE_MELEE and not is_counter(own):
			var countered := false
			for j in 4:
				if f.mp() < 0xA5:
					break
				var anim := f.move_anim(j)
				if anim != BattleFighter.NO_MOVE and is_counter(technique_of(e, anim)):
					if Rng.random_limit(100) < f.speed() / maxi(level_of(e), 1):
						f.queued_anim = anim
						f.target = caster_slot
						f.move_range = 1
						start_queued_move(f, caster_slot)
						world.set_animation_playing(caster, false)
						countered = true
						f.set_hit(false)
						break
			if countered:
				continue
		if add_blocked_attack(f, attack):
			_emit("particles", [0, 2, pos, e, 0x11])
		if not (f.has(BattleFighter.BLOCKING) and f.invulnerable_timer > 0):
			if move_range(t) == RANGE_MELEE:
				var chip := calculate_damage(caster, e, t) * (Rng.random_limit(0x15) + 0xA) / 100
				f.hp_damage = mini(f.hp_damage + maxi(chip, 1), 0x270F)
				bar_timers[i] = 0
				_emit("number", [e, i, 0, maxi(chip, 1), 0])
			add_finisher_progress(f, f.finisher_goal * 3 / 50)
			if caster_slot >= 0:
				var cf := fighters[caster_slot]
				add_finisher_progress(cf, cf.finisher_goal * 4 / 50)
			if i == 0:
				blocked_count += 1
			world.look_at_location(e, Vector3i(pos.x, 0, pos.z))
			f.flags |= BattleFighter.BLOCKING
			world.start_animation(e, ANIM_BLOCK)
			world.set_animation_playing(e, false)
		f.invulnerable_timer = 3
		f.set_hit(false)


## BTL_handleHitReaction: front (0x28) or back (0x29) by the hit's angle against the facing.
func hit_reaction(f: BattleFighter, attack_position: Vector3i, technique: int) -> void:
	var e := f.entity
	var loc := world.location(e)
	var d := Vector3i(loc.x - attack_position.x, 0, loc.z - attack_position.z)
	var ang := PsxMath.s16(PsxMath.atan(-d.z, -d.x))
	var rot := world.rotation_y(e)
	if f.has(BattleFighter.FLATTENED):
		world.set_rotation_y(e, ang)
		world.set_flat_sprite(e, 3)
		world.start_animation(e, ANIM_HIT_FRONT)
		return
	var front := false
	if rot >= 0x400 and rot < 0xC00:
		front = rot - 0x400 <= ang and rot + 0x400 >= ang
	elif rot >= 0 and rot < 0x400:
		front = (ang >= 0 and ang <= rot + 0x400) or (ang >= rot + 0xC00 and ang < 0x1000)
	else:
		front = (rot - 0x400 <= ang and ang < 0x1000) or (ang >= 0 and rot - 0xC00 >= ang)
	if front:
		world.set_rotation_y(e, ang)
	else:
		world.set_rotation_y(e, PsxMath.atan(d.z, d.x))
	world.start_animation(e, ANIM_HIT_FRONT if front else ANIM_HIT_BACK)
	_emit("particles", [element(technique), 1, attack_position, e, _move_int(technique, "iframes") + 0x10])


## damageTick (utils.c:93): the damage buffer drains into HP in steps.
static func damage_tick(f: BattleFighter) -> void:
	var hp := f.hp()
	if f.hp_damage > 999:
		hp -= 900
		f.hp_damage -= 900
	if f.hp_damage > 99:
		hp -= 80
		f.hp_damage -= 80
	if f.hp_damage > 9:
		hp -= 6
		f.hp_damage -= 6
	if f.hp_damage > 0:
		hp -= 1
		f.hp_damage -= 1
	if hp <= 0:
		hp = 0
		f.hp_damage = 0
	f.set_hp(hp)


## The HP bars' draws (BTL_renderEnemyHPBars, BTL_renderPartnerStatusBars) apply the damage: an
## enemy's only while its bar is shown; the partner's MP buffer at once.
func apply_damage_buffers() -> void:
	var partner := fighters[0]
	if partner.hp() == 0:
		partner.hp_damage = 0
	if partner.hp_damage != 0:
		damage_tick(partner)
	partner.set_mp(partner.mp() - partner.mp_damage)
	partner.mp_damage = 0
	bars_shown.fill(false)
	for i in range(1, enemy_count + 1):
		var f := fighters[i]
		if not toggle_lifebar:
			if bar_timers[i] >= 0x15:
				continue
		elif bar_timers[i] >= 0x15 and f.has(BattleFighter.DEAD):
			continue
		bars_shown[i] = true
		if f.hp() == 0:
			f.hp_damage = 0
		if not f.has(BattleFighter.KNOCKED_BACK) and f.hp_damage == 0:
			bar_timers[i] = mini(bar_timers[i] + 1, 0xFF)
		damage_tick(f)


# --- statuses (§2.12) -----------------------------------------------------------------------------

## BTL_applyMoveStatus.
func apply_move_status(f: BattleFighter, technique: int) -> void:
	if f.has(BattleFighter.PROTECTED):
		return
	var chance := _move_int(technique, "status_chance")
	if chance == 0:
		return
	if Rng.random_limit(100) < chance:
		match _move_int(technique, "status"):
			1:
				if not f.has(BattleFighter.POISONED):
					f.flags |= BattleFighter.POISONED
					f.poison_timer = 100
					add_poison_visual(f)
			2:
				if not f.has(BattleFighter.CONFUSED):
					f.flags |= BattleFighter.CONFUSED
					f.confusion_timer = Rng.random_limit(0x65) + 200
					add_confusion_visual(f)
					reset_fighter_action(f)
			3:
				if not f.has(BattleFighter.STUNNED):
					f.flags |= BattleFighter.STUNNED
					f.stun_timer = Rng.random_limit(0x29) + 200
					add_stun_visual(f)
					reset_fighter_action(f)
			4:
				if not f.has(BattleFighter.FLATTENED):
					f.flat_timer = -1
					remove_status_effects(f)
					reset_fighter_action(f)
		if f == fighters[0]:
			statused_count += 1


## BTL_resetFighterAction.
static func reset_fighter_action(f: BattleFighter) -> void:
	f.cooldown = 0
	f.senile_timer = 0
	f.flags &= ~(BattleFighter.ON_CHARGEUP | BattleFighter.ON_COOLDOWN | BattleFighter.SENILE)


## BTL_addStatusEffectVisual / BTL_removeStatusEffectVisual (kind 1 poison, 2 confusion, 3 stun).
func add_status_visual(f: BattleFighter, kind: int) -> void:
	if f.status_fx == -1:
		f.status_fx = kind
		_emit("status", [f.entity, kind, true])


func remove_status_visual(f: BattleFighter, kind: int) -> void:
	if f.status_fx != -1:
		_emit("status", [f.entity, kind, false])
		f.status_fx = -1


func add_poison_visual(f: BattleFighter) -> void:
	if not (f.flags & (BattleFighter.CONFUSED | BattleFighter.STUNNED | BattleFighter.FLATTENED)) and f.flat_timer == 0:
		add_status_visual(f, 1)


func add_confusion_visual(f: BattleFighter) -> void:
	if not (f.flags & (BattleFighter.STUNNED | BattleFighter.FLATTENED)) and f.flat_timer == 0:
		if f.has(BattleFighter.POISONED):
			remove_status_visual(f, 1)
		add_status_visual(f, 2)


func add_stun_visual(f: BattleFighter) -> void:
	if not f.has(BattleFighter.FLATTENED) and f.flat_timer == 0:
		if f.has(BattleFighter.CONFUSED):
			remove_status_visual(f, 2)
		if f.has(BattleFighter.POISONED):
			remove_status_visual(f, 1)
		add_status_visual(f, 3)


## BTL_removeStatusEffects.
func remove_status_effects(f: BattleFighter) -> void:
	if f.has(BattleFighter.STUNNED):
		remove_status_visual(f, 3)
	if f.has(BattleFighter.CONFUSED):
		remove_status_visual(f, 2)
	if f.has(BattleFighter.POISONED):
		remove_status_visual(f, 1)


func clear_confusion(f: BattleFighter) -> void:
	reset_fighter_action(f)
	select_target(f, f.target, false)
	f.flags &= ~BattleFighter.CONFUSED
	f.confusion_timer = 0
	if not (f.flags & (BattleFighter.STUNNED | BattleFighter.FLATTENED)) and f.flat_timer == 0:
		f.flags &= ~BattleFighter.BUSY
		remove_status_visual(f, 2)
		if f.has(BattleFighter.POISONED):
			add_status_visual(f, 1)


func clear_stun(f: BattleFighter) -> void:
	reset_fighter_action(f)
	world.set_animation_playing(f.entity, true)
	f.flags &= ~BattleFighter.STUNNED
	f.stun_timer = 0
	if f.has(BattleFighter.FLATTENED) or f.flat_timer != 0:
		return
	remove_status_visual(f, 3)
	if f.has(BattleFighter.CONFUSED):
		add_status_visual(f, 2)
	if f.has(BattleFighter.POISONED):
		add_status_visual(f, 1)


func clear_poison(f: BattleFighter) -> void:
	f.flags &= ~BattleFighter.POISONED
	f.poison_timer = 0
	if not (f.flags & (BattleFighter.CONFUSED | BattleFighter.STUNNED | BattleFighter.FLATTENED)) and f.flat_timer == 0:
		remove_status_visual(f, 1)


## BTL_healFlatten.
func heal_flatten(f: BattleFighter) -> void:
	if f.flat_timer >= 0x42:
		f.flat_timer = 0x41
	if f.flat_timer != 0 and not f.has(BattleFighter.FLATTENED):
		f.flags |= BattleFighter.FLATTENED
		if f.flat_timer >= 4:
			world.set_flat_sprite(f.entity, 0)
		f.flat_timer = 0x41


## BTL_removeDeathCountdown (handleRestore): the countdown's digit goes; the count itself restarts
## when the partner gets up (BTL_isBattleFinished).
func remove_death_countdown() -> void:
	if countdown_shown:
		countdown_shown = false
		_emit("countdown", [false])


## BTL_healStatusEffect (the curing items): the partner's statuses, with the buff rings.
func heal_status_effect(show: bool) -> void:
	var f := fighters[0]
	var kind := 0
	if f.has(BattleFighter.POISONED):
		kind = 0
	if f.has(BattleFighter.CONFUSED):
		kind = 2
	if f.has(BattleFighter.STUNNED):
		kind = 1
	if f.has(BattleFighter.FLATTENED):
		kind = 3
	if f.flags & BattleFighter.STATUSES and show:
		_emit("buff_rings", [kind, f.entity])
	if f.has(BattleFighter.POISONED):
		clear_poison(f)
	if f.has(BattleFighter.CONFUSED):
		clear_confusion(f)
	if f.has(BattleFighter.STUNNED):
		clear_stun(f)
	if f.has(BattleFighter.FLATTENED):
		heal_flatten(f)


## BTL_applyFlattenScale (battle_main.c:2673): the squash-and-stretch as the timer falls.
static func flatten_scale(t: int, scale: Vector3i) -> Vector3i:
	if t >= 0x40:
		return scale
	var stretch := func(angle: int) -> Vector3i:
		var s := PsxMath.sin512(angle)
		return Vector3i(0x1000 - s / 2, s + 0x1000, 0x1000 - s / 2)
	var squash := func(angle: int) -> Vector3i:
		var s := PsxMath.sin512(angle)
		return Vector3i(s / 2 + 0x1000, 0x1000 - s / 2, s / 2 + 0x1000)
	if t >= 0x30:
		return stretch.call((0x40 - t) << 4)
	if t >= 0x20:
		return squash.call((0x30 - t) << 4)
	if t >= 0x18:
		return stretch.call((0x20 - t) << 5)
	if t >= 0x10:
		return squash.call((0x18 - t) << 5)
	if t >= 0xC:
		return stretch.call((0x10 - t) << 6)
	if t >= 8:
		return squash.call((0xC - t) << 6)
	if t >= 6:
		return stretch.call((8 - t) << 7)
	if t >= 4:
		var v := 0x1000 - ((6 - t) << 11)
		return Vector3i(v, v, v)
	if t >= 0:
		var v := (4 - t) << 10
		return Vector3i(v, v, v)
	return scale


## BTL_tickStatusEffects (battle_main.c:2771).
func tick_status_effects() -> void:
	for i in fighters.size():
		var f := fighters[i]
		if f.has(BattleFighter.DEAD):
			continue
		var e := f.entity
		if f.has(BattleFighter.POISONED):
			if not no_ai:
				f.poison_timer -= 1
			if f.poison_timer == 0:
				f.poison_timer = 100
				var dmg := f.max_hp() * (Rng.random_limit(3) + 1) / 100
				f.hp_damage = mini(f.hp_damage + dmg, 0x270F)
				if i != 0:
					bar_timers[i] = 0
				_emit("number", [e, i, 0xC, dmg, 0])
		if f.has(BattleFighter.CONFUSED):
			if not no_ai and f.confusion_timer != 0:
				f.confusion_timer -= 1
			if f.confusion_timer == 0 and not fighters[0].has(BattleFighter.ATTACKING):
				clear_confusion(f)
		if f.has(BattleFighter.STUNNED):
			if not no_ai:
				f.stun_timer -= 1
			if f.stun_timer == 0:
				clear_stun(f)
		if f.flat_timer <= 0:
			continue
		if not no_ai or f.flat_timer < 0x42:
			f.flat_timer -= 1
		if f.flat_timer < 0x40:
			world.set_scale(e, flatten_scale(f.flat_timer, Vector3i(0x1000, 0x1000, 0x1000)))
		if f.has(BattleFighter.FLATTENED):
			match f.flat_timer:
				0x40:
					if f.flags & (BattleFighter.KNOCKED_BACK | BattleFighter.ATTACKING):
						f.flat_timer += 1
					else:
						world.start_animation(e, ANIM_IDLE_WEAK)
						f.move_range = -1
						f.flags |= BattleFighter.BUSY
						f.set_hit(true)
				3:
					world.set_flat_sprite(e, -1)
				0:
					f.flags &= ~(BattleFighter.FLATTENED | BattleFighter.BUSY)
					f.set_hit(false)
					if f.has(BattleFighter.STUNNED):
						add_status_visual(f, 3)
						f.move_range = 0
					if f.has(BattleFighter.CONFUSED):
						add_status_visual(f, 2)
					if f.has(BattleFighter.POISONED):
						add_status_visual(f, 1)
					f.move_range = 0
					reset_fighter_action(f)
					var s := int(digimon_of(e).get("battle_scale", 0x1000))
					if s != 0x1000:
						world.set_scale(e, Vector3i(s, s, s))
		else:
			match f.flat_timer:
				0x40:
					world.start_animation(e, ANIM_IDLE_WEAK)
					f.move_range = -1
					f.flags |= BattleFighter.BUSY
					f.set_hit(true)
				3:
					world.set_flat_sprite(e, 0)
				0:
					f.flags |= BattleFighter.FLATTENED
					f.flat_timer = Rng.random_limit(0x51) + 0xE0
					f.set_hit(false)
					f.flags &= ~BattleFighter.BUSY


# --- the partner's finisher charge-up (command_menu.c:360-452) ------------------------------------

func initialize_finisher_chargeup() -> void:
	finisher_chargeup = 0
	chargeup_time = 0x50
	fighters[0].finisher_progress = 0
	if hovered_command == 0:
		hovered_command = available_commands.size() - 1
	buffered_command = CMD_YOUR_CALL
	current_command = CMD_YOUR_CALL
	_emit("chargeup", [true])


## BTL_tickFinisherChargeup: L1 / R1 presses add 2 (up to 80) for 80 frames.
func tick_finisher_chargeup() -> void:
	if chargeup_time < 0:
		return
	chargeup_time -= 1
	if finisher_chargeup < 0x50 and pad_pressed & (Pad.L1 | Pad.R1):
		finisher_chargeup += 2
	if chargeup_time == 0:
		remove_finisher_chargeup()


func remove_finisher_chargeup() -> void:
	if chargeup_time != -1:
		chargeup_time = -1
		_emit("chargeup", [false])
