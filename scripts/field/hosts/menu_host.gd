class_name MenuHost
extends Node
## The field's menus (specs/game_menu.md, specs/scenes.md §4.3): the △ menu scene, opened when the
## tamer asks for it and ticked by the field's frame order (Field._frame). While it is open
## (IS_IN_MENU) the field skips the partner's and the NPCs' ticks and the condition bubbles.

## A line for the help line (the menu's screens not ported yet).
signal message(text: String)

const GAME_MENU_SCENE := preload("res://scenes/ui/game_menu.tscn")
const INVENTORY_SCENE := preload("res://scenes/ui/inventory.tscn")
const DIGIMON_SCREEN_SCENE := preload("res://scenes/ui/digimon_screen.tscn")
const PLAYER_SCREEN_SCENE := preload("res://scenes/ui/player_screen.tscn")

## Set by the field before start.
var tamer: Tamer
var partner: Partner
var care: Care
var clock: Clock
var fade: Fade
var boxes: UIBoxes
var text_area: TextArea
var script_ctx: ScriptContext
## The pad (GameLoop.pad).
var pad: Pad
## The item rules (specs/inventory.md §4).
var item_use: ItemUse

## null without the game data (no UI boxes).
var menu: GameMenu
var inventory: Inventory
var digimon_screen: DigimonScreen
var player_screen: PlayerScreen
## The screens' model view (renderDigiviceEntity), over the UI boxes.
var digivice: DigiviceView
## The medal model's view (renderDigiviceMedals: MEDAL_VIEW, projection 0x400, the field's lights).
var medal_view: DigiviceView


func start() -> void:
	if boxes == null:
		return
	menu = GAME_MENU_SCENE.instantiate()
	menu.boxes = boxes
	menu.text_area = text_area
	menu.tamer = tamer
	menu.partner = partner
	menu.care = care
	menu.clock = clock
	menu.pad = pad
	add_child(menu)
	menu.unported.connect(func(what: String): message.emit("menu: %s not ported yet" % what))
	tamer.open_menu = try_open
	tamer.care = care
	inventory = INVENTORY_SCENE.instantiate()
	inventory.boxes = boxes
	inventory.text_area = text_area
	inventory.tamer = tamer
	inventory.item_use = item_use
	inventory.pad = pad
	add_child(inventory)
	menu.items_chosen.connect(inventory.draw_text)
	menu.open_inventory.connect(inventory.open)
	inventory.back.connect(menu.reopen)
	inventory.use_item.connect(start_feeding)
	if partner != null:
		partner.item_use = item_use
	digivice = DigiviceView.new()
	digivice.name = "DigiviceView"
	boxes.add_child(digivice)
	digimon_screen = DIGIMON_SCREEN_SCENE.instantiate()
	digimon_screen.boxes = boxes
	digimon_screen.text_area = text_area
	digimon_screen.tamer = tamer
	digimon_screen.partner = partner
	digimon_screen.pad = pad
	digimon_screen.digivice = digivice
	add_child(digimon_screen)
	menu.open_digimon_screen.connect(digimon_screen.open)
	digimon_screen.back.connect(func():
		digimon_screen.close()
		menu.digimon_screen_back())
	medal_view = DigiviceView.new()
	medal_view.name = "MedalView"
	medal_view.eye = [-1050, 220, -10000]
	medal_view.target = [-1050, 220, 0]
	medal_view.projection = 0x400
	medal_view.own_light = false
	boxes.add_child(medal_view)
	player_screen = PLAYER_SCREEN_SCENE.instantiate()
	player_screen.boxes = boxes
	player_screen.text_area = text_area
	player_screen.tamer = tamer
	player_screen.partner = partner
	player_screen.pad = pad
	player_screen.digivice = digivice
	player_screen.medal_view = medal_view
	add_child(player_screen)
	menu.open_player_screen.connect(player_screen.open)
	player_screen.back.connect(func():
		player_screen.close()
		menu.player_screen_back())


## startFeedingItem (game_menu.c:2228): if the tamer's hands are free, he holds the item, stands
## (state 6), the partner comes to take it (state 5); the menu goes, time runs.
func start_feeding(item: String) -> void:
	if tamer.held_item != "" or partner == null:
		return
	tamer.held_item = item
	tamer.set_state(Tamer.STATE_STILL)
	partner.set_state(Partner.STATE_FEED)
	menu.hand_over()


## tamerTickWalkingState's △ (tamer.c:515): no script runs, no protected fade, box 0 free.
func try_open() -> bool:
	if menu == null or partner == null:
		return false
	if script_ctx != null and not script_ctx.is_paused:
		return false
	if fade != null and fade.protection:
		return false
	if not menu.box_free():
		return false
	menu.open()
	return true


## IS_IN_MENU.
func is_open() -> bool:
	return menu != null and menu.is_open


## The menu object (tickTriangleMenu), after the NPCs, then the inventory object.
func tick() -> void:
	if menu != null:
		menu.tick()
	if inventory != null:
		inventory.tick()


## The menu's "Sleep" without opening it (the debug key Z, the care panel): only when the menu could
## open and Sleep is enabled (the partner is sleepy), then option 6's code. False when refused.
func menu_sleep() -> bool:
	if menu == null or partner == null or menu.is_disabled(GameMenu.SLEEP) \
			or partner.state != Partner.STATE_NORMAL or tamer.state != Tamer.STATE_FREE:
		return false
	menu.choose(GameMenu.SLEEP)
	return true
