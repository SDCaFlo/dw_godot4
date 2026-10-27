class_name BattleHost
extends Node
## The field's battles (specs/battle.md §5.2-5.3): START_BATTLE asks it for a battle
## (start_battle), the field runs only its frame() while one is active, and the script waits until
## battle_done(). It owns the BattleSession, its world on the field (FieldBattleWorld) and the
## effect engine (EffectHost), and applies startBattle's tail (tamer.c:832-870, advanceBattleTime:
## the care and the 20 minutes).

signal message(text: String)

const HUD_SCENE := preload("res://scenes/battle/battle_hud.tscn")
## The shared effects and emitters drawn in 3D (specs/battle_effects.md §7.3).
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
const VISUALS_VIEW_SCENE := preload("res://scenes/battle/fx/battle_visuals_view.tscn")

var world: Node
var field_map: FieldMap
var camera: Camera3D
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var care: Care
var clock: Clock
var menu_host: MenuHost
var map_items: MapItems
## The map's objects a technique may hide (Field.map_layer_nodes).
var map_layer_nodes := Callable()
var fade: Node
## The windows the HUD and the inventory draw on.
var text_area: TextArea
var boxes: UIBoxes
## Where the battle HUD goes in the field's HUD (behind the UI boxes); made by the field.
var hud_slot: Control

var session: BattleSession
var battle_world: FieldBattleWorld
var effects: EffectHost
var hud: BattleHud
var fx_view: BattleFxView
## The battle visuals' view (statuses, auras, items, buffs; BattleVisuals).
var visuals_view: BattleVisualsView
## GAME_STATE != 0: the field runs only the battle.
var active := false

var _done := false
var _outcome := 1
var _pad_previous := 0
var _tamer_state := 0
var _partner_state := 0
var _phase := -1


## startBattle's head: the battle takes the field (camera follow off, the △ menu closed, game time
## stopped), then handleBattleStart / loadBattleData through the session.
func start_battle(talked_entity: int) -> void:
	_done = false
	active = true
	_tamer_state = tamer.state
	_partner_state = partner.state
	tamer.camera_follow = false
	if clock != null:
		clock.running = false
	# The battle moves the tamer by his animations (his script state) and the partner itself.
	tamer.set_state(Tamer.STATE_SCRIPT)
	partner.set_state(Partner.STATE_SCRIPT)
	battle_world = FieldBattleWorld.new()
	battle_world.data = GameData
	battle_world.entities = entities
	battle_world.field_map = field_map
	battle_world.camera = camera
	battle_world.game_state = GameState
	battle_world.sound = Sound
	battle_world.fader = func(frames: int) -> void:
		if fade != null and fade.has_method("fade_to_black"):
			fade.fade_to_black(frames)
	battle_world.drop_spawner = func(at: Vector3i, item: int) -> void:
		if map_items != null:
			map_items.spawn(item, FieldMap.model_tile(at.x, at.z), at.y)
	battle_world.map_sound_loader = func() -> void:
		Sound.load_map_sounds(int(GameData.map(GameState.state["world"]["screen"]).get("sound_bank", 0)))
	battle_world.tamer = tamer
	battle_world.map_layer_nodes = map_layer_nodes
	_setup_items()
	PsxMath.setup(GameData)
	effects = EffectHost.new(battle_world)
	effects.world = world
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.host = effects
	world.add_child(fx_view)
	visuals_view = VISUALS_VIEW_SCENE.instantiate()
	visuals_view.visuals = effects.ctx.visuals
	effects.ctx.visuals.view = visuals_view
	world.add_child(visuals_view)
	session = BattleSession.new(battle_world, effects, GameData)
	session.battle.visual.connect(_on_visual)
	_hook_items()
	_start_hud()
	_pad_previous = GameLoop.pad.polled if GameLoop.pad != null else 0
	_phase = -1
	session.begin(talked_entity)


## One game frame of the battle (BTL_battleTickFrame's loop body for the session's phase).
func frame() -> void:
	if not active:
		return
	var polled: int = GameLoop.pad.polled if GameLoop.pad != null else 0
	var pressed := polled & ~_pad_previous
	_pad_previous = polled
	session.frame(pressed)
	# Debug: the help line names each phase the battle enters (a battle stuck in one shows it).
	if session.phase != _phase:
		_phase = session.phase
		message.emit("battle: %s" % BattleSession.Phase.keys()[_phase])
	# The inventory object (tickInventoryUI): not while the tamer runs away.
	var inventory := _inventory()
	if inventory != null and session.battle.current_command != Battle.CMD_RUN:
		inventory.tick()
	if hud != null:
		hud.tick(pressed)
	if fx_view != null:
		fx_view.draw_frame()
	if visuals_view != null:
		visuals_view.draw_frame()
	battle_world.end_frame()
	if session.is_done():
		_finish()


func battle_done() -> bool:
	return _done


func battle_outcome() -> int:
	return _outcome


## startBattle's tail (tamer.c:846-870) and advanceBattleTime.
func _finish() -> void:
	active = false
	_outcome = session.outcome
	_unhook_items()
	if hud != null:
		hud.queue_free()
		hud = null
	if fx_view != null:
		fx_view.queue_free()
		fx_view = null
	if visuals_view != null:
		effects.ctx.visuals.remove_all()
		effects.ctx.visuals.view = null
		visuals_view.queue_free()
		visuals_view = null
	battle_world.restore_view()
	var values: Dictionary = GameState.state["partner"]["care"]
	tamer.set_state(_tamer_state)
	partner.set_state(_partner_state)
	match _outcome:
		-1:
			values["happiness"] = int(values["happiness"]) - 0x1E
			values["discipline"] = int(values["discipline"]) - 0x14
			partner.set_state(-1)
		0:
			values["happiness"] = int(values["happiness"]) - 10
			values["discipline"] = int(values["discipline"]) - 6
			values["tiredness"] = int(values["tiredness"]) + 2
			if care != null:
				care.handle_post_battle_tiredness()
		_:
			Sound.music.force_update_bgm()
			partner.set_state(Partner.STATE_NORMAL)
			values["happiness"] = int(values["happiness"]) + 2
			if care != null:
				care.handle_post_battle_tiredness()
			values["battles"] = int(values["battles"]) + 1
	if care != null:
		care.tick_condition_boundaries()
	advance_battle_time(_outcome)
	_done = true
	message.emit("battle over: %s" % {-1: "lost", 0: "ran away", 1: "won"}.get(_outcome, str(_outcome)))


## advanceBattleTime (tamer.c:872): 20 minutes and 400 frames; an hour's turn ages the partner and
## its timers; hunger and poop move; a won battle may start the daytime fade.
func advance_battle_time(outcome: int) -> void:
	var c: Dictionary = GameState.state["clock"]
	var v: Dictionary = GameState.state["partner"]["care"]
	c["minute"] = int(c["minute"]) + 20
	c["frame"] = int(c["frame"]) + 400
	var condition := int(v["condition"])
	if int(c["minute"]) > 59:
		c["hour"] = int(c["hour"]) + 1
		c["minute"] = int(c["minute"]) - 60
		v["remaining_lifetime"] = maxi(int(v["remaining_lifetime"]) - 1, 0)
		if condition & 1:
			v["sickness_counter"] = int(v["sickness_counter"]) + 1
			v["missed_sleep_hours"] = int(v["missed_sleep_hours"]) + 1
		if condition & 0x40:
			v["sickness_tries"] = int(v["sickness_tries"]) + 1
		if condition & 0x20:
			v["injury_timer"] = int(v["injury_timer"]) + 1
		if condition & 0x40:
			v["sickness_timer"] = int(v["sickness_timer"]) + 1
		if int(c["hour"]) > 0x17:
			c["day"] = int(c["day"]) + 1
			c["hour"] = 0
			c["frame"] = int(c["minute"]) * 20
			if int(c["day"]) > 0x1D:
				c["day"] = 0
				c["year"] = (int(c["year"]) + 1) % 100
	if condition & 4:
		v["starvation_timer"] = int(v["starvation_timer"]) - 40
		var threshold := int(GameData.raise_data(GameState.state["partner"]["digimon"]).get("energy_threshold", 0)) \
				if GameData.has_method("raise_data") else 0
		if int(v["starvation_timer"]) < 1 and int(v["energy_level"]) < threshold:
			v["care_mistakes"] = int(v["care_mistakes"]) + 1
	else:
		v["food_level"] = int(v["food_level"]) - 20
	if condition & 8:
		v["pooping_timer"] = int(v["pooping_timer"]) - 400
	else:
		v["poop_level"] = int(v["poop_level"]) - 2
	if clock != null:
		clock.minute_passed.emit()
		if outcome == 1 and not GameData.map(GameState.state["world"]["screen"]).get("no_time_of_day", false):
			match int(c["hour"]):
				0x10:
					clock.initialize_daytime_transition(0)
				0x14:
					clock.initialize_daytime_transition(1)
				6:
					clock.initialize_daytime_transition(2)
		clock.running = true


## handleItemLoss (script_common.c:1327): 30 % of the item stacks are lost; the recyclable ones go
## to the recycle shop's stock (capped at 99). Script value 0xC8 = the stacks lost.
func item_loss() -> void:
	var slots: Array = GameState.state["inventory"]["slots"]
	var size := mini(int(GameState.state["inventory"]["size"]), slots.size())
	var filled := func() -> Array:
		var out := []
		for k in size:
			if slots[k] != null:
				out.append(k)
		return out
	var lose: int = filled.call().size() * 30 / 100
	GameState.set_script_value(0xC8, lose)
	var recyclable: Array = GameData.recyclable_items()
	var stock: Array = GameState.state["script"]["recycle_stock"]
	for n in lose:
		var pool: Array = filled.call()
		if pool.is_empty():
			break
		var slot: int = pool[Rng.random_limit(pool.size())]
		var item := int(GameData.id_of("items/item_data", slots[slot]["item"]))
		for r in recyclable.size():
			if int(recyclable[r]["item"]["id"]) == item and r < stock.size():
				stock[r] = mini(int(stock[r]) + int(slots[slot]["amount"]), 0x63)
				break
		GameState.remove_item(item, 0x63)


## The battle's visual events: the HUD takes its own (the battle visuals take theirs in the
## session: BattleVisuals.on_visual).
func _on_visual(kind: String, args: Array) -> void:
	if kind == "debug":
		message.emit("battle: %s" % args[0])
		push_warning("BattleHost: %s" % args[0])
	if hud != null:
		hud.on_visual(kind, args)


# --- the HUD (specs/battle.md §4, §5.2) -------------------------------------------------------------

func _start_hud() -> void:
	hud = HUD_SCENE.instantiate()
	hud.session = session
	hud.world = battle_world
	hud.text_area = text_area
	hud.boxes = boxes
	hud.data = GameData
	if hud_slot != null:
		hud_slot.add_child(hud)
	session.boxes_open = hud.end_boxes_open
	session.end_text_done = hud.end_text_done


# --- items in battle (specs/battle.md §2.18) --------------------------------------------------------

func _inventory() -> Inventory:
	return menu_host.inventory if menu_host != null else null


func _item_use() -> ItemUse:
	return menu_host.item_use if menu_host != null else null


## The world's inventory and item calls: △ opens the inventory (addInventoryUI), the item lands
## through ItemUse with the battle set (GAME_STATE 1).
func _setup_items() -> void:
	battle_world.inventory_is_open = func() -> bool:
		var inventory := _inventory()
		return inventory != null and inventory.active
	battle_world.inventory_opener = func() -> void:
		var inventory := _inventory()
		if inventory != null:
			inventory.open()
	battle_world.inventory_closer = func() -> void:
		var inventory := _inventory()
		if inventory != null:
			inventory.close_all()
	battle_world.item_user = func(item: Variant) -> void:
		var item_use := _item_use()
		if item_use != null:
			item_use.apply(item)


func _hook_items() -> void:
	var inventory := _inventory()
	if inventory != null:
		# BTL_initializeCombat draws the inventory's names into the text area (drawInventoryText).
		inventory.draw_text()
		var battle := session.battle
		inventory.game_mode = func() -> int: return battle.game_state
		inventory.throw_item.connect(session.throw_item)
	if _item_use() != null:
		_item_use().battle = session.battle


func _unhook_items() -> void:
	var inventory := _inventory()
	if inventory != null:
		inventory.close_all()
		inventory.game_mode = func() -> int: return 0
		if inventory.throw_item.is_connected(session.throw_item):
			inventory.throw_item.disconnect(session.throw_item)
	if _item_use() != null:
		_item_use().battle = null
	if session.thrown.active():
		session.thrown.clear()
		tamer.clear_held_item()
