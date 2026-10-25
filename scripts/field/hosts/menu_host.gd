class_name MenuHost
extends Node
## The field's menus (specs/game_menu.md, specs/scenes.md §4.3): the △ menu scene, opened when the
## tamer asks for it and ticked by the field's frame order (Field._frame). While it is open
## (IS_IN_MENU) the field skips the partner's and the NPCs' ticks and the condition bubbles.

## A line for the help line (the menu's screens not ported yet).
signal message(text: String)

const GAME_MENU_SCENE := preload("res://scenes/ui/game_menu.tscn")

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

## null without the game data (no UI boxes).
var menu: GameMenu


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


## The menu object (tickTriangleMenu), after the NPCs.
func tick() -> void:
	if menu != null:
		menu.tick()


## The menu's "Sleep" without opening it (the debug key Z, the care panel): only when the menu could
## open and Sleep is enabled (the partner is sleepy), then option 6's code. False when refused.
func menu_sleep() -> bool:
	if menu == null or partner == null or menu.is_disabled(GameMenu.SLEEP) \
			or partner.state != Partner.STATE_NORMAL or tamer.state != Tamer.STATE_FREE:
		return false
	menu.choose(GameMenu.SLEEP)
	return true
