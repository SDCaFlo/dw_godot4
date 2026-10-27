class_name BattleSession
extends RefCounted
## One battle from START_BATTLE's call to its outcome (specs/battle.md §2.1-2.6, §2.14-2.15): the
## C's blocking loops (loadBattleData, BTL_handleBattleIntro, BTL_battleMain,
## BTL_deinitializeCombat, BTL_handleVictorySequence, handleBattleEndBox) as phases, one original
## frame per frame() call, each doing one pass of its loop and then the objects (the tamer's battle
## tick, the effects, the HUD's ticks, the damage the HP bars apply).

enum Phase { LOADING, INTRO, INTRO_BURST, FIGHT, VICTORY_WAIT, VICTORY_POSE, END_BOX, ENEMIES_UP, ENEMIES_LEAVE,
		MENU_CLOSE, DONE }
enum Box { OPEN, STATS, BALANCE, BITS, TEXT }

## The loading's CD time, fixed (specs/battle.md §9, decided 2026-10-26).
const LOAD_FRAMES := 40
const PARTNER := 1
const TAMER := 0
## Enemy repel / bell (handleBattleStart).
const ITEM_REPEL := 0x23
const ITEM_BELL := 0x24
## The command menu's slide steps (BTL_COMMAND_MENU_SLIDE_X / Y: 7 each).
const MENU_STEPS := 7
## The death countdown's end (BTL_isBattleFinished: DEATH_COUNTDOWN >= 0xab).
const COUNTDOWN_END := 0xAB
## The end box's text: frames per text before it moves on without a press (the HUD's pages, 5d-4).
const TEXT_FRAMES := 60

var battle: Battle
var world: BattleWorld
var effects: EffectHost
var data: Node
var rewards: BattleRewards
var start_text: BattleStartText
## TAMER_ITEM: the item thrown to the partner (§2.18).
var thrown: BattleThrownItem

var phase := Phase.LOADING
var outcome := 1
## The fighters' entities: the partner, then the enemies.
var entity_ids: Array[int] = []
var predefined := false
var talked := -1
## The flee bubbles shown: {entity: 0 joins / 1 runs off}.
var bubbles := {}
## The hooks the HUD may set (5d-4): the end boxes have opened / the end text is through.
var boxes_open := func() -> bool: return true
var end_text_done := Callable()

var _timer := 0
var _loading_slots: Array = []
var _runners: Array[int] = []
var _intro_result := -1
var _intro_wp := -1
var _all_off := false
var _text_done := false
var _victory_ready := false
var _victory_partner := false
var _box := Box.OPEN
var _menu_x := 0
var _menu_y := 0
var _menu_active := false
var _pressed := 0


func _init(battle_world: BattleWorld, effect_host: EffectHost, game_data: Node) -> void:
	world = battle_world
	effects = effect_host
	data = game_data
	battle = Battle.new(world, effects, data)
	rewards = BattleRewards.new(battle)
	start_text = BattleStartText.new(data)
	thrown = BattleThrownItem.new(data)


func is_done() -> bool:
	return phase == Phase.DONE


# --- the start (main/btl.c) -----------------------------------------------------------------------

## startBattle's head: handleBattleStart + loadBattleData up to the loading wait.
func begin(talked_entity: int) -> void:
	talked = talked_entity
	battle.game_state = 1
	handle_battle_start(talked_entity)
	# In the C a battle always has an enemy: the Digimon talked to (it never flees) or a key fight's
	# list. Without one (a bad talked-to id, an empty list) nothing could end it: say so.
	if entity_ids.size() < 2 or not world.entity_present(entity_ids[1]):
		battle.visual.emit("debug", ["no enemy in this battle (talked to %d, fighters %s)" % [talked_entity, entity_ids]])
	_load_data()


## handleBattleStart (btl.c:209): who fights, and the flee bubbles.
func handle_battle_start(id: int) -> void:
	entity_ids = [PARTNER]
	bubbles.clear()
	battle.no_escape = world.trigger(1)
	predefined = world.script_value(0xFA) == 1
	battle.predefined = predefined
	if predefined:
		var slots := []
		for k in 3:
			var v := world.script_value(0xFB + k)
			slots.append(v)
			if v != 0xFF:
				bubbles[v] = 0
				entity_ids.append(v)
		for i in range(2, 10):
			if i in slots:
				continue
			if world.entity_present(i) and not world.is_on_screen(i):
				world.set_on_map(i, false)
			if world.is_invisible(i):
				continue
			bubbles[i] = 1
		return
	entity_ids.append(id)
	var concave: bool = world.map_record().get("concave", false)
	var items := world.inventory_items()
	for i in range(2, 10):
		if not world.entity_present(i) or not world.is_on_map(i):
			continue
		if i == id:
			bubbles[i] = 0
			continue
		if not world.is_on_screen(i):
			world.set_on_map(i, false)
			continue
		if entity_ids.size() - 1 == 3:
			bubbles[i] = 1
			continue
		if concave:
			var npc_tile := world.tile(i)
			if world.path_blocked(world.tile(TAMER), npc_tile) or world.path_blocked(world.tile(PARTNER), npc_tile):
				bubbles[i] = 1
				continue
		var chance := Rng.random_limit(100)
		var has_repel := ITEM_REPEL in items
		var has_bell := ITEM_BELL in items
		if has_repel or has_bell:
			chance += -50 if has_bell else 20
		if battle.no_escape:
			chance = 0
		var joins := false
		var partner_type := _digimon_type_class(PARTNER)
		if partner_type != 0xFF:
			joins = chance < data.flee_chance(partner_type, _digimon_type_class(i))
		else:
			joins = Rng.random_limit(100) < 0x46
		if joins:
			entity_ids.append(i)
		bubbles[i] = 0 if joins else 1


## DIGIMON_DATA[type].type (Data / Vaccine / Virus).
func _digimon_type_class(entity: int) -> int:
	var t := world.digimon_type(entity)
	return int(data.digimon(t).get("type", {}).get("id", 0xFF)) if t >= 0 else 0xFF


## loadBattleData's head (btl.c:358): the music, the animations, the partner's run-in.
func _load_data() -> void:
	var first := entity_ids[1] if entity_ids.size() > 1 else -1
	var variant := 1
	if first >= 0 and int(battle.digimon_of(first).get("battle_music", 1)) == 3:
		variant = 3
	elif talked >= 2 and talked < 10:
		variant = 0 if predefined else int(battle.digimon_of(talked).get("battle_music", 1))
	elif predefined:
		variant = 0
	world.play_music(0x21, variant)
	world.start_animation(TAMER, Battle.TAMER_IDLE)
	for i in range(2, 10):
		if not world.is_invisible(i):
			world.start_animation(i, Battle.ANIM_IDLE)
	battle.game_state = 3
	if not predefined:
		world.start_animation(PARTNER, Battle.ANIM_WALK)
	_emit_bubbles()
	phase = Phase.LOADING
	_timer = 0


func _emit_bubbles() -> void:
	for e in bubbles:
		battle.visual.emit("flee_bubble", [e, bubbles[e]])


## The loading frames: the enemies look at the partner, which runs up to the tamer.
func _frame_loading() -> void:
	if not predefined:
		for i in range(1, entity_ids.size()):
			world.look_at_location(entity_ids[i], world.location(PARTNER))
		world.partner_run_in()
	_timer += 1
	if _timer >= LOAD_FRAMES:
		_finish_loading()


## loadBattleData's tail and BTL_battleMain's head: sound banks, the techniques' effects, the
## set-up, the intro.
func _finish_loading() -> void:
	var entries := []
	var keys := []
	for i in entity_ids.size():
		var e := entity_ids[i]
		var s := world.stats(e)
		if i != 0:
			s["current"]["vab_id"] = i + 4
			world.load_digimon_sounds(i + 4, world.digimon_type(e))
		s["current"]["unk1"] = -1
		s["current"]["efe_sub_effect"] = -1
		for j in 4:
			var anim := battle.anim_of_move(s["base"]["moves"][j], e)
			if anim == 0xFF:
				continue
			var t := battle.technique_of(e, anim)
			if t == 0xFF:
				s["base"]["moves"][j] = null
			else:
				entries.append({"technique": t, "caster": i})
				keys.append([i, j])
	var slots: Array[int] = effects.load_moves(entries) if effects != null else []
	_loading_slots = []
	for i in entity_ids.size():
		_loading_slots.append([-1, -1, -1, -1])
	for k in keys.size():
		_loading_slots[keys[k][0]][keys[k][1]] = slots[k] if k < slots.size() else -1
	battle.game_state = 2
	world.set_combat_area()
	battle.initialize_combat(entity_ids)
	for i in battle.fighters.size():
		battle.fighters[i].effect_slot.assign(_loading_slots[i])
	battle.battle_idle(battle.fighters[0])
	_menu_active = true
	_begin_intro()


# --- the intro (BTL_handleBattleIntro, battle_setup.c:207) ----------------------------------------

func _begin_intro() -> void:
	var partner := battle.fighters[0]
	battle.start_idle(partner)
	world.look_at_location(PARTNER, world.location(entity_ids[1]))
	start_text.start()
	_runners.clear()
	for i in range(2, 10):
		if world.is_invisible(i) or i in entity_ids:
			continue
		world.start_animation(i, Battle.ANIM_WALK)
		world.set_double_speed(i, true)
		world.look_at_location(i, _flee_point(i))
		_runners.append(i)
	_timer = 0
	_text_done = false
	_all_off = _runners.is_empty()
	var wp := world.tamer_waypoints()
	_intro_wp = int(wp["count"]) - 1
	wp["active"] = 0
	world.start_animation(TAMER, Battle.TAMER_RUN)
	world.play_sound(0, 0x10)
	phase = Phase.INTRO


func _flee_point(entity: int) -> Vector3i:
	var f: Array = world.npc_record(entity).get("flee", [0, 0, 0])
	return Vector3i(int(f[0]), int(f[1]), int(f[2]))


func _start_tile() -> Vector2i:
	var st: Array = world.tamer_waypoints()["start_tile"]
	return Vector2i(int(st[0]), int(st[1]))


func _waypoint(i: int) -> Vector2i:
	var wp := world.tamer_waypoints()
	return Vector2i(int(wp["x"][i]), int(wp["y"][i]))


func _frame_intro() -> void:
	if not (_timer < 0xC8 or not _all_off or not _text_done):
		_end_intro()
		return
	if world.animation_id(TAMER) != Battle.TAMER_IDLE:
		var here := world.tile(TAMER)
		if _intro_wp >= 0:
			var goal := _waypoint(_intro_wp)
			world.look_at_tile(TAMER, goal)
			if here == goal:
				_intro_wp -= 1
				world.tamer_waypoints()["count"] = int(world.tamer_waypoints()["count"]) - 1
			_intro_result = world.check_collision(TAMER, PARTNER, 0x136, 0xE6)
		else:
			world.look_at_tile(TAMER, _start_tile())
			if here == _start_tile():
				_intro_result = BattleWorld.HIT_AREA
			else:
				_intro_result = world.check_collision(TAMER, PARTNER, 0x12C, 0xDC)
	if _intro_result == BattleWorld.HIT_AREA and world.animation_id(TAMER) != Battle.TAMER_IDLE:
		world.start_animation(TAMER, Battle.TAMER_IDLE)
		world.look_at_location(TAMER, world.location(PARTNER))
		_timer = 0xC6
	_timer += 1
	var all_off := true
	for r in _runners:
		if not world.is_off_screen(r, 0x140, 0xF0):
			all_off = false
			break
	if all_off:
		_all_off = true
	_text_done = start_text.finished
	world.partner_collision()
	world.look_at_location(PARTNER, world.location(entity_ids[1]))
	_objects()


func _end_intro() -> void:
	var wp := world.tamer_waypoints()
	if _intro_wp != -1:
		wp["count"] = _intro_wp + 1
		wp["active"] = int(wp["count"]) - 1
	else:
		wp["current"] = 0
		wp["count"] = 0
		wp["active"] = 0
	if world.animation_id(TAMER) != Battle.TAMER_IDLE:
		world.start_animation(TAMER, Battle.TAMER_IDLE)
		world.look_at_location(TAMER, world.location(PARTNER))
	for r in _runners:
		world.set_on_map(r, false)
		world.set_double_speed(r, false)
	start_text.start_burst()
	world.play_sound(0, 0x11)
	phase = Phase.INTRO_BURST


func _frame_burst() -> void:
	if start_text.finished:
		battle.game_state = 1
		phase = Phase.FIGHT
		_frame_fight()
		return
	_objects()


# --- the fight (BTL_battleMain's loop) ------------------------------------------------------------

func _frame_fight() -> void:
	if is_battle_finished():
		_deinitialize()
		return
	battle.fight_frame()
	world.partner_waypoint_trail()
	_objects()
	battle.frame_count += 1


## BTL_isBattleFinished (battle_setup.c:331).
func is_battle_finished() -> bool:
	var partner := battle.fighters[0]
	if battle.flee_timer >= 0x29 and partner.hp() - partner.hp_damage > 0:
		return true
	var anim := world.animation_id(PARTNER)
	if anim == Battle.ANIM_GET_UP:
		battle.death_countdown = 0
		if not world.animation_playing(PARTNER):
			partner.flags &= ~BattleFighter.DEAD
			partner.set_hit(false)
			if battle.no_ai:
				if battle.finisher_aura:
					battle.finisher_aura = false
					battle.visual.emit("finisher_aura", [battle.finishing_entity, false, -1])
				battle.no_ai = false
				battle.finishing_entity = -1
			for i in battle.fighters.size():
				var f := battle.fighters[i]
				f.cooldown = 0
				f.flags &= ~(BattleFighter.BUSY | BattleFighter.RETARGETED | BattleFighter.ON_CHARGEUP
						| BattleFighter.ON_COOLDOWN | BattleFighter.SENILE)
				if not f.has(BattleFighter.DEAD) or f.hp() - f.hp_damage > 0:
					f.move_range = 0
	if anim == Battle.ANIM_FAINT and not world.animation_playing(PARTNER):
		if not thrown.active():
			battle.death_countdown += 1
		if battle.death_countdown == 0x14:
			battle.countdown_shown = true
			battle.visual.emit("countdown", [true])
		return battle.death_countdown >= COUNTDOWN_END
	for i in range(1, battle.fighters.size()):
		var e := battle.fighters[i].entity
		if world.animation_id(e) != Battle.ANIM_FAINT or world.animation_playing(e):
			return false
	return partner.hp() - partner.hp_damage > 0


# --- the objects of a battle frame (BTL_battleTickFrame) -------------------------------------------

func _objects() -> void:
	tamer_tick_battle()
	tick_thrown_item()
	if effects != null:
		effects.tick()
	battle.tick_finisher_chargeup()
	if phase == Phase.INTRO:
		start_text.tick_assemble()
	elif phase == Phase.INTRO_BURST:
		start_text.tick_burst()
	_tick_command_menu()
	battle.apply_damage_buffers()
	if effects != null:
		effects.draw()


## BTL_tickCommandMenu's slide: down 7 steps then across 7 while open; back while closing.
func _tick_command_menu() -> void:
	if _menu_active:
		if _menu_y < MENU_STEPS:
			_menu_y += 1
		elif _menu_x < MENU_STEPS:
			_menu_x += 1
	else:
		if _menu_x != 0:
			_menu_x -= 1
		elif _menu_y != 0:
			_menu_y -= 1


func command_menu_steps() -> Vector2i:
	return Vector2i(_menu_x, _menu_y)


## BTL_COMMAND_MENU_ACTIVE == 1 (the partner's status bars slide with it).
func command_menu_active() -> bool:
	return _menu_active


# --- items in battle (§2.18) ----------------------------------------------------------------------

## startThrowingItem (main.c:4236): the tamer throws, the item leaves the bag and rides his hand.
func throw_item(item: Variant) -> void:
	if thrown.active():
		return
	world.start_animation(TAMER, Battle.TAMER_THROW)
	thrown.start(item, world.bone_location(TAMER, BattleThrownItem.HAND_BONE))
	world.remove_item(item)
	world.show_thrown_item(item, thrown.location)


## tickThrownItem / renderThrownItem: on landing, the item's function (battle branches), the item
## particles, the hands free again.
func tick_thrown_item() -> void:
	if not thrown.active():
		return
	var landed := thrown.tick(world.animation_id(TAMER), world.animation_frame(TAMER),
			world.bone_location(TAMER, BattleThrownItem.HAND_BONE), world.location(PARTNER))
	if not landed:
		world.show_thrown_item(thrown.item, thrown.location)
		return
	var item = thrown.item
	thrown.clear()
	world.show_thrown_item(null, Vector3i.ZERO)
	world.use_item(item)
	battle.visual.emit("item_particles", [PARTNER])


## tamerTickBattle (battle_tick.c:235).
func tamer_tick_battle() -> void:
	var pressed := _pressed
	if battle.game_state == 1:
		if battle.current_command != Battle.CMD_RUN:
			if not battle.tamerless and pressed & Pad.CANCEL:
				world.open_inventory()
			world.look_at_location(TAMER, world.location(PARTNER))
			if not world.inventory_open():
				var anim := world.animation_id(TAMER)
				if not battle.no_ai or battle.finishing_entity != PARTNER:
					if anim == Battle.TAMER_THROW or anim == Battle.TAMER_POINT:
						if not world.animation_playing(TAMER):
							world.start_animation(TAMER, Battle.TAMER_IDLE)
					elif anim != Battle.TAMER_IDLE:
						world.start_animation(TAMER, Battle.TAMER_IDLE)
				elif anim != Battle.TAMER_FINISHER:
					world.start_animation(TAMER, Battle.TAMER_FINISHER)
		if pressed & Pad.SELECT:
			battle.toggle_lifebar = not battle.toggle_lifebar
		handle_commands(pressed)
	if world.animation_id(TAMER) == Battle.TAMER_IDLE:
		battle.tamer_idle_timer += 1
	else:
		battle.tamer_idle_timer = 0
	if battle.tamer_idle_timer >= 0xAB:
		world.start_animation(TAMER, Battle.TAMER_IDLE)
		battle.tamer_idle_timer = 0


## handleCommands (battle_tick.c:54).
func handle_commands(pressed: int) -> void:
	if battle.tamerless or world.inventory_open():
		return
	var partner := battle.fighters[0]
	if battle.current_command == Battle.CMD_RUN:
		if battle.flee_timer == 0x14 and partner.hp() - partner.hp_damage > 0:
			world.fade_to_black(0x14)
		handle_fleeing()
		battle.flee_timer += 1
		return
	var count := battle.available_commands.size()
	if pressed & Pad.LEFT:
		world.play_sound(0, 2)
		battle.hovered_command += 1
		if battle.no_escape and battle.hovered_command == 1:
			battle.hovered_command += 1
		if battle.hovered_command > count - 1:
			battle.hovered_command = 2 if battle.no_escape else 1
	if pressed & Pad.RIGHT:
		world.play_sound(0, 2)
		battle.hovered_command -= 1
		if battle.no_escape and battle.hovered_command == 1:
			battle.hovered_command -= 1
		if battle.hovered_command <= 0:
			battle.hovered_command = count - 1
	if pressed & Pad.CONFIRM:
		world.play_sound(0, 3)
		if battle.remaining_enemies(PARTNER).is_empty():
			return
		if world.animation_id(TAMER) != Battle.TAMER_POINT:
			world.start_animation(TAMER, Battle.TAMER_POINT)
		battle.buffered_command = battle.available_commands[battle.hovered_command]
		# The discipline delay is computed and then overwritten with 0 in the US release (§2.6).
		battle.command_delay = 0
		match battle.buffered_command:
			Battle.CMD_RUN:
				battle.current_command = Battle.CMD_RUN
				if world.tile(TAMER) == _start_tile():
					world.look_at_location(TAMER, world.exit_flee_point())
				world.start_animation(TAMER, Battle.TAMER_RUN)
			Battle.CMD_CHANGE:
				battle.change_target = true
		battle.visual.emit("shout", [battle.buffered_command])
	if pressed & Pad.SQUARE:
		if partner.finisher_progress == partner.finisher_goal:
			battle.buffered_command = Battle.CMD_FINISHER
			world.play_sound(0, 3)
			battle.command_delay = 0
			battle.current_command = Battle.CMD_FINISHER
			battle.visual.emit("shout", [battle.buffered_command])


## handleFleeing (battle_tick.c:189): back along the waypoints, then out of the map entry.
func handle_fleeing() -> void:
	var wp := world.tamer_waypoints()
	var i := int(wp["count"]) - 1
	var here := world.tile(TAMER)
	if i >= 0:
		var goal := _waypoint(i)
		world.look_at_tile(TAMER, goal)
		if here == goal:
			wp["count"] = int(wp["count"]) - 1
		return
	world.look_at_tile(TAMER, _start_tile())
	if here == _start_tile():
		world.look_at_location(TAMER, world.exit_flee_point())
		world.set_step_held(TAMER, true)


# --- the end (BTL_deinitializeCombat, battle_main.c:739) ------------------------------------------

func _deinitialize() -> void:
	var partner := battle.fighters[0]
	partner.set_charge_mode(battle.saved_charge_mode)
	battle.game_state = 2
	for f in battle.fighters:
		battle.remove_move_effect(f)
	battle.visual.emit("clear_effects", [])
	world.close_inventory()
	for i in battle.fighters.size():
		var f := battle.fighters[i]
		battle.reset_flatten(i)
		battle.remove_status_effects(f)
		if i != 0:
			var init: Array = battle.initial_stats[i]
			f.set_hp(init[0])
			f.set_mp(init[1])
			f.base()["offense"] = init[2]
			f.base()["defense"] = init[3]
			f.base()["speed"] = init[4]
			f.base()["brains"] = init[5]
		f.flags = 0
	if partner.hp() != 0 and battle.current_command != Battle.CMD_RUN:
		world.start_animation(TAMER, Battle.TAMER_IDLE)
		world.start_animation(PARTNER, Battle.ANIM_IDLE)
		world.stop_music()
		world.stop_sounds()
		world.play_sound(0, 0x15)
		world.reload_map_sounds()
		_timer = 0
		phase = Phase.VICTORY_WAIT
	else:
		reset_stats_after_combat()
		battle.remove_death_countdown()
		battle.visual.emit("clear_numbers", [])
		_close_menu()


## resetStatsAfterCombat: the partner's base stats back from INITIAL_COMBAT_STATS[0] (which holds
## the gains after a win).
func reset_stats_after_combat() -> void:
	var b := battle.fighters[0].base()
	var init: Array = battle.initial_stats[0]
	for k in BattleRewards.STATS.size():
		b[BattleRewards.STATS[k]] = init[k]


func _frame_victory_wait() -> void:
	_objects()
	_timer += 1
	if _timer >= 0x29:
		world.play_sound(0, 0x18)
		world.start_animation(TAMER, Battle.TAMER_CHEER)
		world.start_animation(PARTNER, Battle.ANIM_VICTORY)
		_victory_ready = false
		_victory_partner = false
		phase = Phase.VICTORY_POSE


func _frame_victory_pose() -> void:
	if _victory_ready and _victory_partner:
		_begin_end_box()
		return
	if not world.animation_playing(PARTNER):
		_victory_partner = true
		battle.start_idle(battle.fighters[0])
	if not world.animation_playing(TAMER):
		_victory_ready = true
		world.start_animation(TAMER, Battle.TAMER_IDLE)
	_objects()


# --- the end box (handleBattleEndBox, battle_ui.c:297) --------------------------------------------

func _begin_end_box() -> void:
	rewards.compute()
	battle.game_state = 2
	battle.visual.emit("end_box", [rewards])
	_box = Box.OPEN
	_timer = 0
	phase = Phase.END_BOX


func _frame_end_box() -> void:
	match _box:
		Box.OPEN:
			if boxes_open.call():
				_box = Box.STATS
		Box.STATS:
			if rewards.tick_stats(_pressed):
				battle.visual.emit("final_balance", [])
				_box = Box.BALANCE
		Box.BALANCE:
			if boxes_open.call():
				_box = Box.BITS
		Box.BITS:
			if rewards.tick_bits(_pressed):
				rewards.skip = false
				_timer = 0
				_box = Box.TEXT
		Box.TEXT:
			_timer += 1
			var done := false
			if end_text_done.is_valid():
				done = end_text_done.call()
			else:
				done = _timer >= rewards.texts.size() * TEXT_FRAMES or _pressed & (Pad.CONFIRM | Pad.CANCEL)
			if done:
				_finish_end_box()
				return
	_objects()


func _finish_end_box() -> void:
	for i in range(1, battle.enemy_count + 1):
		if rewards.drops[i - 1] >= 0:
			world.spawn_drop(battle.fighters[i].entity, rewards.drops[i - 1])
	reset_stats_after_combat()
	battle.visual.emit("end_box_close", [])
	for i in range(1, battle.fighters.size()):
		world.start_animation(battle.fighters[i].entity, Battle.ANIM_GET_UP)
	phase = Phase.ENEMIES_UP if battle.no_escape else Phase.ENEMIES_LEAVE


func _frame_enemies_up() -> void:
	for i in range(1, battle.fighters.size()):
		if world.animation_playing(battle.fighters[i].entity):
			_objects()
			return
	for f in battle.fighters:
		world.start_animation(f.entity, Battle.ANIM_IDLE)
	_close_menu()


func _frame_enemies_leave() -> void:
	var off := 0
	for i in range(1, battle.fighters.size()):
		var e := battle.fighters[i].entity
		if not world.animation_playing(e) and world.animation_id(e) == Battle.ANIM_GET_UP:
			world.start_animation(e, Battle.ANIM_WALK)
			world.set_double_speed(e, true)
			world.look_at_location(e, _flee_point(e))
		if world.is_off_screen(e, 0x140, 0xF0):
			off += 1
	if off == battle.enemy_count:
		_close_menu()
		return
	_objects()


func _close_menu() -> void:
	_menu_active = false
	battle.visual.emit("command_menu", [false])
	phase = Phase.MENU_CLOSE


func _frame_menu_close() -> void:
	if _menu_x == 0 and _menu_y == 0:
		_finish()
		return
	_objects()


## BTL_deinitializeCombat's tail and BTL_battleMain's result.
func _finish() -> void:
	battle.visual.emit("status_bars", [false])
	for i in range(2, 10):
		if not world.entity_present(i):
			continue
		if battle.no_escape:
			if not i in entity_ids:
				world.set_on_map(i, not world.is_on_screen(i))
		elif world.is_on_screen(i):
			world.set_double_speed(i, false)
			world.set_on_map(i, false)
		else:
			world.set_on_map(i, true)
	world.stop_music()
	world.stop_sounds()
	if effects != null:
		effects.unload_all()
	if battle.fighters[0].hp() == 0:
		battle.current_command = 0
		outcome = -1
	elif battle.current_command == Battle.CMD_RUN:
		battle.current_command = 0
		outcome = 0
	else:
		outcome = 1
	phase = Phase.DONE


# --- the frame ------------------------------------------------------------------------------------

## One original frame. `pressed`: the pad buttons newly pressed this frame (POLLED_INPUT &
## ~POLLED_INPUT_PREVIOUS).
func frame(pressed: int) -> void:
	_pressed = pressed
	battle.pad_pressed = pressed
	match phase:
		Phase.LOADING:
			_frame_loading()
		Phase.INTRO:
			_frame_intro()
		Phase.INTRO_BURST:
			_frame_burst()
		Phase.FIGHT:
			_frame_fight()
		Phase.VICTORY_WAIT:
			_frame_victory_wait()
		Phase.VICTORY_POSE:
			_frame_victory_pose()
		Phase.END_BOX:
			_frame_end_box()
		Phase.ENEMIES_UP:
			_frame_enemies_up()
		Phase.ENEMIES_LEAVE:
			_frame_enemies_leave()
		Phase.MENU_CLOSE:
			_frame_menu_close()
