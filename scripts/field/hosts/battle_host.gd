class_name BattleHost
extends Node
## The field's battles (specs/battle.md §5.2-5.3): START_BATTLE asks it for a battle
## (start_battle), the field runs only its frame() while one is active, and the script waits until
## battle_done(). It owns the BattleSession, its world on the field (FieldBattleWorld) and the
## effect engine (EffectHost), and applies startBattle's tail (tamer.c:832-870, advanceBattleTime:
## the care and the 20 minutes).

signal message(text: String)

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
var fade: Node

var session: BattleSession
var battle_world: FieldBattleWorld
var effects: EffectHost
## GAME_STATE != 0: the field runs only the battle.
var active := false

var _done := false
var _outcome := 1
var _pad_previous := 0
var _tamer_state := 0
var _partner_state := 0


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
	battle_world.inventory_opener = func() -> void:
		message.emit("battle: items in battle come with the battle HUD (5d-4)")
	PsxMath.setup(GameData)
	effects = EffectHost.new(battle_world)
	effects.world = world
	session = BattleSession.new(battle_world, effects, GameData)
	session.battle.visual.connect(_on_visual)
	_pad_previous = GameLoop.pad.polled if GameLoop.pad != null else 0
	session.begin(talked_entity)


## One game frame of the battle (BTL_battleTickFrame's loop body for the session's phase).
func frame() -> void:
	if not active:
		return
	var polled: int = GameLoop.pad.polled if GameLoop.pad != null else 0
	var pressed := polled & ~_pad_previous
	_pad_previous = polled
	session.frame(pressed)
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


## The battle's visual events: the HUD and effects scenes take them in 5d-4 / 5d-5; for now the
## help line shows the shouts and the damage.
func _on_visual(kind: String, args: Array) -> void:
	match kind:
		"shout":
			message.emit("command %d" % int(args[0]))
		"number":
			if int(args[2]) == 0:
				message.emit("entity %d: %d damage" % [int(args[0]), int(args[3])])
