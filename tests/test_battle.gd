extends SceneTree
## The battle logic (scripts/systems/battle/: Battle, BattleSession, BattleRewards,
## BattleStartText) against specs/battle.md §2, on a stub world (entities that play animations by
## frames and walk forward), with values worked out from the C:
##   godot --headless --path . -s res://tests/test_battle.gd
## Exits 1 if a check fails.

## Stub entities: id -> {type, location, yaw, anim, playing, frame, frames, on_map, on_screen,
## double, held, stats, record}.
class StubWorld extends BattleWorld:
	var entities := {}
	var sounds: Array = []
	var music: Array = []
	var money := 0
	var learned: Array = []
	var condition := 0
	var discipline := 50
	var tiredness := 0
	var triggers := []
	var values := {}
	var items: Array = []
	var waypoints := {"x": [], "y": [], "start_tile": [50, 50], "current": 0, "count": 0, "active": 0}
	var drops: Array = []
	var fades := 0
	const LOOPS := [0x21, 0x22, 0x23, 0x24, 1, 3, 0xA]

	func add(id: int, type: int, location: Vector3i, base := {}, record := {}) -> void:
		var b := {"max_hp": 100, "max_mp": 100, "offense": 100, "defense": 100, "speed": 100, "brains": 100,
				"moves": [null, null, null, null], "moves_prio": [0, 0, 0, 0]}
		b.merge(base, true)
		var current := {"hp": int(b["max_hp"]), "mp": int(b["max_mp"]), "charge_mode": 0, "is_hit": 0,
				"efe_sub_effect": -1, "unk1": -1, "vab_id": 4}
		entities[id] = {"type": type, "location": location, "yaw": 0, "anim": -1, "playing": false, "frame": 0,
				"frames": 0, "on_map": true, "on_screen": true, "double": false, "held": false,
				"stats": {"base": b, "current": current}, "record": record, "scale": Vector3i(4096, 4096, 4096)}

	# The effect context.
	func entity_present(id: int) -> bool:
		return entities.has(id)

	func is_on_map(id: int) -> bool:
		return entities.has(id) and entities[id]["on_map"]

	func is_on_screen(id: int) -> bool:
		return entities.has(id) and entities[id]["on_screen"]

	func digimon_type(id: int) -> int:
		return entities[id]["type"] if entities.has(id) else -1

	func current_hp(id: int) -> int:
		return int(entities[id]["stats"]["current"]["hp"]) if entities.has(id) else 0

	func is_hit(id: int) -> bool:
		return entities.has(id) and int(entities[id]["stats"]["current"]["is_hit"]) != 0

	func set_hit(id: int, value: bool) -> void:
		if entities.has(id):
			entities[id]["stats"]["current"]["is_hit"] = 1 if value else 0

	func location(id: int) -> Vector3i:
		return entities[id]["location"] if entities.has(id) else Vector3i.ZERO

	func rotation_y(id: int) -> int:
		return entities[id]["yaw"] if entities.has(id) else 0

	func bone_matrix(id: int, bone: int) -> PackedInt32Array:
		if not entities.has(id):
			return PsxMath.identity()
		var m := PsxMath.rot_matrix_yxz(Vector3i(0, rotation_y(id), 0))
		return PsxMath.trans_matrix(m, location(id) - Vector3i(0, height(id) * mini(bone, 4) / 4, 0))

	func world_screen_matrix() -> PackedInt32Array:
		return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, 3000))

	func play_sound(bank: int, id: int) -> void:
		sounds.append([bank, id])

	# The battle world.
	func stats(id: int) -> Dictionary:
		return entities[id]["stats"]

	func npc_record(id: int) -> Dictionary:
		return entities[id]["record"] if entities.has(id) else {}

	func partner_condition() -> int:
		return condition

	func partner_discipline() -> int:
		return discipline

	func partner_tiredness() -> int:
		return tiredness

	func set_partner_condition_bit(bit: int) -> void:
		condition |= bit

	func start_animation(id: int, anim: int) -> void:
		if not entities.has(id):
			return
		var e: Dictionary = entities[id]
		e["anim"] = anim
		e["playing"] = true
		e["frame"] = 1
		e["frames"] = 30 if anim >= 0x25 else 20
		e["held"] = false

	func animation_id(id: int) -> int:
		return entities[id]["anim"] if entities.has(id) else -1

	func animation_playing(id: int) -> bool:
		return entities.has(id) and entities[id]["playing"]

	func set_animation_playing(id: int, playing: bool) -> void:
		if entities.has(id):
			entities[id]["playing"] = playing

	func animation_frame(id: int) -> int:
		return entities[id]["frame"] if entities.has(id) else 0

	func animation_frame_count(id: int) -> int:
		return entities[id]["frames"] if entities.has(id) else 0

	func set_step_held(id: int, held: bool) -> void:
		if entities.has(id):
			entities[id]["held"] = held

	func set_double_speed(id: int, on: bool) -> void:
		if entities.has(id):
			entities[id]["double"] = on

	func set_rotation_y(id: int, vy: int) -> void:
		if entities.has(id):
			entities[id]["yaw"] = vy & 0xFFF

	## The forward step of a walking animation: 20 units (40 at double speed).
	func _step(id: int) -> Vector3i:
		var e: Dictionary = entities[id]
		if not (e["anim"] in [0x23, 0x24, 3]) or not e["playing"]:
			return Vector3i.ZERO
		var a: float = e["yaw"] * TAU / 4096.0
		var n := 40.0 if e["double"] else 20.0
		return Vector3i(roundi(-sin(a) * n), 0, roundi(-cos(a) * n))

	func check_collision(id: int, _source: int, w: int, _h: int) -> int:
		var next := location(id) + _step(id)
		if w != 0 and (absi(next.x) > 1200 or absi(next.z) > 1200):
			return HIT_AREA
		return FREE

	func is_off_screen(id: int, _w: int, _h: int) -> bool:
		var p := location(id)
		return absi(p.x) > 1500 or absi(p.z) > 1500

	func screen_position(id: int, _bone: int) -> Vector2i:
		return Vector2i(location(id).x / 10, location(id).z / 10)

	func set_scale(id: int, scale: Vector3i) -> void:
		if entities.has(id):
			entities[id]["scale"] = scale

	func set_on_map(id: int, on: bool) -> void:
		if entities.has(id):
			entities[id]["on_map"] = on

	func trigger(id: int) -> bool:
		return id in triggers

	func script_value(id: int) -> int:
		return values.get(id, 0)

	func inventory_items() -> Array:
		return items

	func map_record() -> Dictionary:
		return {}

	func play_music(font: int, variant: int) -> void:
		music.append([font, variant])

	func has_move(t: int) -> bool:
		return t in learned

	func learn_move(t: int) -> void:
		learned.append(t)

	func add_money(n: int) -> void:
		money = mini(money + n, 999999)

	func tamer_waypoints() -> Dictionary:
		return waypoints

	func exit_flee_point() -> Vector3i:
		return Vector3i(0, 0, 3000)

	func fade_to_black(_frames: int) -> void:
		fades += 1

	func spawn_drop(entity: int, item: int) -> void:
		drops.append([entity, item])

	## After each game frame: the animations advance (twice at double speed), walkers move.
	func advance() -> void:
		for id in entities:
			var e: Dictionary = entities[id]
			for k in (2 if e["double"] else 1):
				if not e["playing"]:
					break
				if not e["held"]:
					e["location"] += _step(id)
				if e["frame"] >= e["frames"]:
					if e["anim"] in LOOPS:
						e["frame"] = 1
					else:
						e["playing"] = false
				else:
					e["frame"] += 1
			e["on_screen"] = not is_off_screen(id, 320, 240)


var _failed := 0
var _checks := 0
var data: Node


func _init() -> void:
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: no data porter output")
		data.free()
		quit(0)
		return
	PsxMath.setup(data)
	_test_formulas()
	_test_setup()
	_test_statuses()
	_test_start_text()
	_test_win()
	_test_run()
	_test_loss()
	data.free()
	print("%s: battle checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])


## The animation id of a Digimon's first technique of `category`, or null.
func _anim_of(type: int, category: String) -> Variant:
	for m in data.digimon(type).get("moves", []):
		if data.move(int(m["move"]["id"])).get("category", "") == category:
			return int(m["anim"])
	return null


## A world with the tamer at the origin, the partner (Agumon, 3) in front, an enemy (Gabumon,
## 17) 800 units further.
func _world(partner := {}, enemy := {}) -> StubWorld:
	var w := StubWorld.new()
	w.data = data
	var p := {"max_hp": 800, "max_mp": 400, "offense": 300, "defense": 200, "speed": 200, "brains": 150,
			"moves": [_anim_of(3, "technique"), null, null, _anim_of(3, "finisher")], "moves_prio": [0, 0, 0, 0]}
	p.merge(partner, true)
	var e := {"max_hp": 60, "max_mp": 300, "offense": 40, "defense": 30, "speed": 30, "brains": 20,
			"moves": [_anim_of(17, "technique"), null, null, null], "moves_prio": [10, 0, 0, 0]}
	e.merge(enemy, true)
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, 3, Vector3i(0, 0, -200), p)
	w.add(2, 17, Vector3i(0, 0, -900), e, {"bits": 25, "targets_partner": false, "flee": [0, 0, -3000]})
	return w


func _session(w: StubWorld) -> BattleSession:
	var host := EffectHost.new(w)
	return BattleSession.new(w, host, data)


## Runs a session until it ends (or `limit` frames); `press(frame) -> int` gives the pad.
func _run(s: BattleSession, w: StubWorld, limit: int, press := Callable()) -> int:
	var n := 0
	while not s.is_done() and n < limit:
		s.frame(press.call(n) if press.is_valid() else 0)
		w.advance()
		n += 1
	return n


# --- formulas -------------------------------------------------------------------------------------

func _test_formulas() -> void:
	var w := _world()
	var b := Battle.new(w, null, data)
	b.initialize_combat([1, 2])
	var spit_fire := 2
	# BTL_calculateDamage: m = sum of the factors over Gabumon's elements; diff clamp; 90..110 %.
	var m := 0
	for e in b.elements_of(2):
		m += data.type_factor(b.element(spit_fire), e) if e != 0xFF else 10
	var pw := b.power(spit_fire)
	Rng.set_seed(7)
	var r := Rng.random_limit(0x15) + 0x5A
	var expected := clampi(m * (pw + clampi(300 - 30, -500, 500) * pw / 500) / 30 * r / 100, 1, 9999)
	Rng.set_seed(7)
	_eq(b.calculate_damage(1, 2, spit_fire), expected, "technique damage")
	# A finisher by the partner: (off + power) * m / 30, the charge-up from 41, then 90..110 %.
	var finisher: int = b.technique_of(1, _anim_of(3, "finisher"))
	m = 0
	for e in b.elements_of(2):
		m += data.type_factor(b.element(finisher), e) if e != 0xFF else 10
	b.finisher_chargeup = 60
	Rng.set_seed(3)
	r = Rng.random_limit(0x15) + 0x5A
	expected = clampi((300 + b.power(finisher)) * m / 30 * 60 / 40 * r / 100, 1, 9999)
	Rng.set_seed(3)
	_eq(b.calculate_damage(1, 2, finisher), expected, "partner finisher damage with charge-up")
	# Hit chance branches.
	var enemy := b.fighters[1]
	w.start_animation(2, Battle.ANIM_WALK)
	var acc := int(data.move(spit_fire)["accuracy"])
	_eq(b.hit_chance(1, enemy, spit_fire), clampi(acc - acc / 2 * (30 - 300 / 10) / 999, 0, 100), "hit chance")
	enemy.flags |= BattleFighter.BLOCKING
	_eq(b.hit_chance(1, enemy, spit_fire), 0, "a blocking defender")
	_eq(b.hit_chance(1, enemy, finisher), 100, "a finisher always hits")
	_eq(enemy.has(BattleFighter.BLOCKING), false, "a finisher breaks the block")
	enemy.flags |= BattleFighter.STUNNED
	_eq(b.hit_chance(1, enemy, spit_fire), 100, "a stunned defender")
	enemy.flags = 0
	enemy.speed_buffer = 0
	_eq(b.hit_chance(1, enemy, spit_fire), 100, "an empty speed buffer")
	# damageTick: 900 / 80 / 6 / 1 a frame.
	var f := b.fighters[0]
	f.set_hp(2000)
	f.hp_damage = 1087
	Battle.damage_tick(f)
	_eq([f.hp(), f.hp_damage], [2000 - 900 - 80 - 6 - 1, 100], "damageTick steps")
	# MP cost with the brain discount and sickness.
	f.base()["brains"] = 999
	f.set_mp(1000)
	var cost := b.mp_cost(spit_fire) * 3
	_eq(b.is_move_usable(f, 0), true, "usable with MP")
	f.set_mp(cost - cost / 5 - 1)
	_eq(b.is_move_usable(f, 0), false, "not usable below the discounted cost")
	f.set_mp(cost - cost / 5)
	_eq(b.is_move_usable(f, 0), true, "usable at the discounted cost (brain 999: -20 %)")
	_eq(b.is_move_usable(f, 3), false, "a finisher is no usable technique")
	# Buffs: Muscle Charge raises Offense by 3/10.
	f.base()["offense"] = 300
	_eq(b.apply_buff_move(f, 0, 0x29), true, "a buff technique")
	_eq(int(f.base()["offense"]), 390, "Offense + 30 %")
	# Your Call's sort ranks.
	_eq(Battle.sort_scores([5, 50, 50], true), [[1, 2, 0], [0, 0, 1], [50, 50, 5]], "descending sort with groups")


# --- set-up ---------------------------------------------------------------------------------------

func _test_setup() -> void:
	var expected := {50: [11, 1, 3], 150: [11, 1, 2, 3], 250: [11, 1, 4, 2, 3], 350: [11, 1, 7, 5, 4, 2, 3],
			450: [11, 1, 7, 6, 5, 4, 2, 3]}
	for brain in expected:
		var w := _world({"brains": brain})
		var b := Battle.new(w, null, data)
		b.initialize_combat([1, 2])
		_eq(b.available_commands, expected[brain], "commands at brain %d" % brain)
		_eq(b.hovered_command, b.available_commands.size() - 1, "hovering Your Call at %d" % brain)
	var w := _world({"brains": 600, "moves": [_anim_of(3, "technique"), null, 0x30, null]})
	var b := Battle.new(w, null, data)
	b.initialize_combat([1, 2])
	_eq(b.available_commands, [11, 1, 7, 6, 5, 10, 8, 3], "brain 500+: the equipped techniques")
	var f := b.fighters[0]
	_eq([f.buffs_remaining, f.buff_prio_timer, f.finisher_goal], [5, 65, 2800], "buffs, priority, finisher goal")
	w = _world({"offense": 300, "brains": 100})
	w.condition = 0x20
	b = Battle.new(w, null, data)
	b.initialize_combat([1, 2])
	_eq(int(b.fighters[0].base()["offense"]), 240, "injured: Offense - 1/5")
	_eq(b.initial_stats[0][2], 300, "the starting stats keep the real Offense")


# --- statuses -------------------------------------------------------------------------------------

func _test_statuses() -> void:
	var w := _world()
	var b := Battle.new(w, null, data)
	b.initialize_combat([1, 2])
	var e := b.fighters[1]
	e.flags |= BattleFighter.POISONED
	e.poison_timer = 1
	Rng.set_seed(11)
	var r := Rng.random_limit(3) + 1
	Rng.set_seed(11)
	b.tick_status_effects()
	_eq([e.hp_damage, e.poison_timer], [60 * r / 100, 100], "a poison tick")
	e.flags = BattleFighter.STUNNED
	e.stun_timer = 1
	b.tick_status_effects()
	_eq(e.has(BattleFighter.STUNNED), false, "the stun ends")
	# The flatten: -1 -> 0x41 (at the action's end), the stop at 0x40, flat at 0.
	e.flags = 0
	e.flat_timer = 0x41
	b.tick_status_effects()
	_eq([e.flat_timer, w.animation_id(2), e.has(BattleFighter.BUSY)], [0x40, Battle.ANIM_IDLE_WEAK, true],
			"the flatten stops the fighter at 0x40")
	for k in 0x40:
		b.tick_status_effects()
	_eq(e.has(BattleFighter.FLATTENED), true, "flattened at 0")
	_eq(e.flat_timer >= 0xE0 and e.flat_timer <= 0x130, true, "flat for 224-304 frames")
	b.no_ai = true
	var t := e.flat_timer
	b.tick_status_effects()
	_eq(e.flat_timer, t, "no flatten timer during a finisher")


# --- the start text ---------------------------------------------------------------------------------

func _test_start_text() -> void:
	var text := BattleStartText.new(data)
	Rng.set_seed(1)
	text.start()
	var frames := 0
	while not text.finished and frames < 400:
		text.tick_assemble()
		frames += 1
	_eq(text.finished, true, "the start text assembles")
	text.start_burst()
	var burst := 0
	while not text.finished and burst < 400:
		text.tick_burst()
		burst += 1
	_eq(text.finished, true, "the burst leaves the screen")
	print("start text: %d frames to assemble, %d to burst" % [frames, burst])


# --- whole battles ----------------------------------------------------------------------------------

func _test_win() -> void:
	var w := _world()
	var s := _session(w)
	Rng.set_seed(42)
	s.begin(2)
	_eq(s.entity_ids, [1, 2], "the talked-to enemy fights")
	_eq(w.music[0], [0x21, int(data.digimon(17)["battle_music"])], "the enemy's battle music")
	var frames := _run(s, w, 6000)
	_eq(s.outcome, 1, "a strong partner wins (in %d frames)" % frames)
	_eq(int(w.stats(2)["current"]["hp"]), 60, "the enemy's HP is restored after the battle")
	_eq(w.money, 25, "the bits are counted into the money")
	var gained := false
	for k in 6:
		if s.battle.initial_stats[0][k] != [800, 400, 300, 200, 200, 150][k]:
			gained = true
	_eq(int(w.stats(1)["base"]["max_hp"]), s.battle.initial_stats[0][0], "the partner's stats are the starting stats plus the gains")
	print("win: %d frames, gains applied: %s, stats %s" % [frames, gained, s.battle.initial_stats[0]])
	# BTL_deinitializeCombat: an NPC on screen leaves the map, one off screen stays on it (the
	# defeated enemy ran off screen to its flee point).
	_eq([w.entities[2]["on_screen"], w.entities[2]["on_map"]], [false, true], "the defeated enemy ran off and stays on the map")


func _test_run() -> void:
	var w := _world()
	var s := _session(w)
	Rng.set_seed(5)
	s.begin(2)
	var press := func(n: int) -> int:
		if s.phase == BattleSession.Phase.FIGHT and s.battle.current_command != Battle.CMD_RUN:
			s.battle.hovered_command = 1
			return Pad.CONFIRM
		return 0
	_run(s, w, 3000, press)
	_eq(s.outcome, 0, "running away ends the battle with 0")
	_eq(w.fades, 1, "the screen fades at FLEE_TIMER 20")


func _test_loss() -> void:
	# A partner without MP can't attack (a hit would cancel the enemy's slower Fire Tower each time).
	var w := _world({"max_hp": 30, "max_mp": 0, "offense": 1, "defense": 1, "speed": 1},
			{"max_hp": 5000, "offense": 900, "defense": 900, "speed": 300})
	var s := _session(w)
	Rng.set_seed(9)
	s.begin(2)
	_run(s, w, 8000)
	_eq(s.outcome, -1, "a weak partner loses")
	_eq(int(w.stats(1)["current"]["hp"]), 0, "the partner fainted")
