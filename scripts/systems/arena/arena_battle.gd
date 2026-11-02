class_name ArenaBattle
extends Battle
## The arena's battle rules (specs/arena.md §4.5, §5.2): std_main.c's copy of btl's battle, 1 on 1.
## Only what the arena's C changes is here, as overrides of Battle's hooks and of the functions whose
## STD version differs throughout; everything else is Battle (btl), which std copies line for line.
## Fighter 0 is the partner (entity 1), fighter 1 the opponent.

## STD_initializeCombat (std_main.c:4210-4256): the field list without these.
const ARENA_DROPS := [Battle.CMD_RUN, Battle.CMD_CHANGE]
## STD_tickEnemyAI (std_main.c:4327-4330): the opponent's priorities, every frame.
const OPPONENT_PRIORITIES := [30, 30, 30, 0]
## STD_tickEnemyAI (std_main.c:4422): 1 in 10 keeps away (charge mode 2).
const KEEP_AWAY_ROLL := 10
## STD_startQueuedMove (std_main.c:6646, :6648): the area-technique lock.
const AREA_LOCK := 0x6E
## STD_tickDigimonAttackRanged (std_main.c:5110, :5114): trying for 100 frames, idling until 160.
const RANGED_TRY := 100
const RANGED_GIVE_UP := 160
## STD_selectRandomCamera's end cameras (mode 5: the win / lose letters).
const CAMERA_END := 5

## The match's camera (STD_selectRandomCamera, STD_setRandomViewpoint); null: no camera calls.
var camera: ArenaCamera
## STD_DISABLE_HITTING: set by a faint, every later hit misses.
var disable_hitting := false
## P2_AOE_TIMER: the opponent's area-technique lock (the partner's is shared_cooldown).
var p2_aoe_timer := 0


## STD_initializeCombat (std_main.c:4124): btl's set-up, plus the arena's own fields. FLEE_DISABLED[0]
## is written 1 there (4161) but never read in std, so no_escape stays false.
func initialize_combat(entity_ids: Array) -> void:
	super(entity_ids)
	p2_aoe_timer = 0
	disable_hitting = false
	no_escape = false
	tamerless = false


## STD_initializeCombat (4210-4256): the field's command list of the same brain band, without Run and
## Change (the arena's lists are those, in the same order).
func _set_up_commands() -> void:
	var partner := fighters[0]
	var count: int = data.battle_commands(partner.brains())
	var record := {}
	for r in data.system("battle_command_lists"):
		if int(r["count"]) == count:
			record = r
	available_commands.clear()
	for c in record.get("commands", []):
		if not int(c) in ARENA_DROPS:
			available_commands.append(int(c))
	for pair in record.get("technique_slots", []):
		if partner.move_anim(int(pair[0])) != BattleFighter.NO_MOVE:
			available_commands.append(int(pair[1]))
	for c in record.get("after", []):
		if not int(c) in ARENA_DROPS:
			available_commands.append(int(c))
	hovered_command = available_commands.size() - 1
	current_command = CMD_YOUR_CALL
	buffered_command = CMD_YOUR_CALL


# --- the hooks ------------------------------------------------------------------------------------

## STD_tickPartnerAI (std_main.c:3783-3787) / STD_tickEnemyAI (4352-4357): the end camera if the
## other fighter still stands, then no more hits.
func _on_fighter_fainted(f: BattleFighter, index: int) -> void:
	if index == 0:
		if not _all_enemies_dead():
			_select_random_camera(f.entity, CAMERA_END, 0)
	elif fighters[0].hp() > fighters[0].hp_damage:
		_select_random_camera(f.entity, CAMERA_END, 0)
	disable_hitting = true


## STD_tickPartnerAI (std_main.c:3792): also idle once the partner's HP is covered by its damage buffer.
func _partner_gives_up(f: BattleFighter) -> bool:
	return f.hp() <= f.hp_damage


## STD_tickPartnerAI (std_main.c:3851, 3858, 3880, 3908): the target is always the opponent.
func _partner_retarget(f: BattleFighter, _site: int) -> void:
	f.target = 1


## STD_tickPartnerAI case 11 (std_main.c:3862).
func _after_finisher_command(f: BattleFighter) -> void:
	apply_charge_requirement(f, fighter_technique(f, f.queued_anim))


func _before_enemy_ai(f: BattleFighter) -> void:
	var prio: Array = f.base()["moves_prio"]
	for k in 4:
		prio[k] = OPPONENT_PRIORITIES[k]


## STD_tickEnemyAI (std_main.c:4422-4426).
func _enemy_charge_mode(_f: BattleFighter) -> int:
	if Rng.random_limit(KEEP_AWAY_ROLL) == 0:
		return 2
	return Rng.random_limit(2)


## STD_startQueuedMove (std_main.c:6644-6649): the partner's lock or the opponent's.
func _start_shared_cooldown(f: BattleFighter) -> void:
	if is_partner(f):
		shared_cooldown = AREA_LOCK
	else:
		p2_aoe_timer = AREA_LOCK


## STD_setupMoveExecution (std_main.c:6718-6719): the opponent.
func _default_target(f: BattleFighter) -> int:
	f.target = 1
	return fighters[1].entity


## STD_setupMoveExecution (std_main.c:6786-6807): a cut to a fighter camera, unless the camera is on an area
## technique's fighter (3) or a viewpoint (6, whose second test can never pass).
func _after_move_execution(f: BattleFighter, technique: int) -> void:
	if camera == null:
		return
	if camera.state == ArenaCamera.STATE_ENTITY:
		if move_range(technique_of(camera.focused, world.animation_id(camera.focused))) == RANGE_AREA:
			return
	if camera.state == ArenaCamera.STATE_VIEWPOINT:
		if camera.state != ArenaCamera.STATE_ENTITY:
			return
		if not is_partner(f):
			return
	var r := move_range(technique)
	var n := 2 if r == RANGE_MELEE or r == RANGE_SELF else 5
	_select_random_camera(f.entity, Rng.random_limit(n), r)


## STD_applyMoveResult: the flatten's end keeps the flatten's last scale (no 0x71 restore).
func _restore_scale_after_flatten(_f: BattleFighter) -> void:
	pass


## STD_selectEnemyMove (std_main.c:6348): the charge mode stays.
func _no_usable_enemy_move(_f: BattleFighter) -> void:
	pass


## STD_selectPartnerMove (std_main.c:6478): weights[keys[keys[i]]].
func _mp_weight_slot(keys: Array, i: int) -> int:
	return keys[keys[i]]


# --- the overrides --------------------------------------------------------------------------------

## STD_tickBattle (std_main.c:4431): btl's fighter states with the opponent's lock, the senile and
## status ticks of std, then the camera's timer and its periodic cut.
func tick_fighter_states() -> void:
	if shared_cooldown > 0:
		shared_cooldown -= 1
	if p2_aoe_timer > 0:
		p2_aoe_timer -= 1
	_tick_fighters()
	tick_attack_hits()
	tick_status_effects()
	if camera == null:
		return
	if camera.state != ArenaCamera.STATE_LOOK_AT and camera.state != ArenaCamera.STATE_FIXED:
		if camera.timer != 0:
			camera.timer -= 1
			if camera.timer == 0:
				camera.state = ArenaCamera.STATE_ORBIT
		if frame_count % 600 == 0 and Rng.random_limit(2) == 1:
			camera.state = ArenaCamera.STATE_VIEWPOINT
			camera.set_random_viewpoint(1, 4)
			camera.timer = Rng.random_limit(0x29) + 0x3C
	for f in fighters:
		if f.flags & (BattleFighter.ATTACKING | BattleFighter.KNOCKED_BACK):
			return
		if camera.timer != 0 or camera.state == ArenaCamera.STATE_LOOK_AT or camera.state == ArenaCamera.STATE_FIXED:
			return
	camera.state = ArenaCamera.STATE_ORBIT


## STD_tickDigimonSenile (std_main.c:4860).
func tick_senile_state(f: BattleFighter) -> void:
	f.senile_timer -= 1
	if f.senile_timer == 0:
		f.flags &= ~(BattleFighter.BUSY | BattleFighter.SENILE)
	else:
		battle_idle(f)


## STD_tickDigimonAttackRanged (std_main.c:5104).
func tick_ranged_attack(f: BattleFighter, target: int, technique: int) -> void:
	if f.band_frames > RANGED_TRY:
		battle_idle(f)
		f.band_frames += 1
		if f.band_frames > RANGED_GIVE_UP:
			f.flags &= ~BattleFighter.BUSY
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
	elif dist < total - total * 3 / 10:
		set_walking(f)
		back_away(f, target)
		f.band_frames += 1
	else:
		f.band_frames = 0
		battle_idle(f)
		if f.has(BattleFighter.FLATTENED):
			if frame_count % 40 == 0:
				start_queued_move(f, target)
			else:
				look_at(f.entity, te)
		else:
			start_queued_move(f, target)


## STD_selectMoveTarget (std_main.c:6660): an area technique waits for its fighter's lock and for
## the other fighter's running area technique.
func is_move_on_cooldown(f: BattleFighter) -> bool:
	if not has_shared_cooldown(fighter_technique(f, f.queued_anim)):
		return false
	if is_partner(f):
		if shared_cooldown > 0:
			return true
	elif p2_aoe_timer > 0:
		return true
	for other in fighters:
		if other == f or not other.has(BattleFighter.ATTACKING):
			continue
		if has_shared_cooldown(technique_of(other.entity, world.animation_id(other.entity))):
			return true
	return false


## STD_applyPartnerStatsToFighter (std_main.c:5913) = BTL_calculateHitChance without the
## level-under-3 rule, and 0 once a fighter fainted.
func hit_chance(attacker: int, defender: BattleFighter, technique: int) -> int:
	if disable_hitting:
		return 0
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


## STD_tickAttackHits (std_main.c:5765-5771): instead of btl's retarget, a hit may cut to a viewpoint on the hit
## fighter. The skip test (camera 6 and 3 at once) can never pass.
func retarget_after_hit(f: BattleFighter, _caster_slot: int) -> void:
	if camera == null:
		return
	var idx := Rng.random_limit(4)
	camera.set_random_viewpoint(f.entity, idx)


## STD_updateFighterStatusVisuals (std_main.c:6954): the confusion ends on the other fighter.
func clear_confusion(f: BattleFighter) -> void:
	reset_fighter_action(f)
	f.target = 1 if is_partner(f) else 0
	f.flags &= ~BattleFighter.CONFUSED
	f.confusion_timer = 0
	if not (f.flags & (BattleFighter.STUNNED | BattleFighter.FLATTENED)) and f.flat_timer == 0:
		f.flags &= ~BattleFighter.BUSY
		remove_status_visual(f, 2)
		if f.has(BattleFighter.POISONED):
			add_status_visual(f, 1)


## STD_renderFighterStatusBars (std_hud.c:1016), for both fighters in their objects' order: the HP
## buffer drains, the MP buffer at once, MP floored at 0.
func apply_damage_buffers() -> void:
	for f in fighters:
		if f.hp() == 0:
			f.hp_damage = 0
		if f.hp_damage != 0:
			damage_tick(f)
		f.set_mp(maxi(f.mp() - f.mp_damage, 0))
		f.mp_damage = 0


## STD_areAllEnemyDigimonDead (std_main.c:4626).
func _all_enemies_dead() -> bool:
	for i in range(1, enemy_count + 1):
		if fighters[i].hp() - fighters[i].hp_damage > 0:
			return false
	return true


func _select_random_camera(entity: int, mode: int, sub: int) -> void:
	if camera != null:
		camera.select_random_camera(entity, mode, sub)
