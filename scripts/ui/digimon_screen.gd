class_name DigimonScreen
extends Node
## The Digimon screen (tickDigimonMenu / renderDigimonMenu, game_menu.c:1705, :1822;
## specs/status_screens.md §2, §3): box 1, the window of the △ menu's DIGIMON, with the Status and
## Techniques tabs (child nodes `Status` and `Techniques`). The root of scenes/ui/digimon_screen.tscn,
## opened by GameMenu (its state 3) through the MenuHost.

## △ in a shown tab: back to the △ menu (TRIANGLE_MENU_STATE 4).
signal back

## STATUS_VIEW_LABELS / TECH_VIEW_LABELS (game_menu.c:948, :959), the text ids.
const STATUS_LABELS := ["MAIN_D_801238A0", "MAIN_D_801238B0", "MAIN_D_801238D8", "MAIN_D_80123900",
		"MAIN_D_80123914", "MAIN_D_80123920", "MAIN_D_80123938", "MAIN_D_8012394C"]
const TECH_LABELS := ["MAIN_D_80123958", "MAIN_D_80123970", "MAIN_D_80123990", "MAIN_D_801239AC",
		"MAIN_D_80134240", "MAIN_D_801239C4", "MAIN_D_801239D0", "MAIN_D_801239DC", "MAIN_D_801239E8",
		"MAIN_D_801239F4"]
## The window (tickTriangleMenu state 3): box 1.
const BOX := 1
const RECT := Rect2i(-0x96, -0x59, 300, 0xBE)
const TAB_STATUS := 0
const TAB_TECHNIQUES := 1

## Set by the host.
var boxes: UIBoxes
var text_area: TextArea
var tamer: Tamer
var partner: Partner
var pad: Pad
var sound: Node
var game_state: Node
var data: Node
var digivice: DigiviceView

## DIGIMON_MENU_STATE (the tab), MENU_STATE, MENU_SUB_STATE.
var tab := TAB_STATUS
var menu_state := 0
var sub_state := 0
var is_open := false

@onready var status_tab: DigimonStatusTab = $Status
@onready var techniques_tab: DigimonTechniquesTab = $Techniques


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")
	status_tab.screen = self
	techniques_tab.screen = self


## tickTriangleMenu state 3 once box 0 is closed: box 1 opens from the tamer, the tab labels drawn.
func open() -> void:
	var start := tamer.screen_rect() if tamer != null else Rect2i(-5, -5, 10, 10)
	boxes.create_animated(BOX, 1, 0, RECT, start, tick_box, draw_box, update_box)
	text_area.clear_all()
	text_area.draw_string(data.text(STATUS_LABELS[0]), 0, 0)
	tab = TAB_STATUS
	menu_state = 0
	sub_state = 0
	is_open = true


## Back (tickTriangleMenu state 4 closes the box): the model goes.
func close() -> void:
	_current_tab().leave()
	is_open = false


func _current_tab() -> Node:
	return status_tab if tab == TAB_STATUS else techniques_tab


# --- tickDigimonMenu (game_menu.c:1705) ----------------------------------------------------------

func tick_box(_id: int) -> void:
	if tab != TAB_TECHNIQUES or menu_state == 1:
		if pad.is_changed(Pad.RIGHT) and menu_state != 0 and tab + 1 < 2:
			_set_tab(tab + 1)
		if pad.is_changed(Pad.LEFT) and menu_state != 0 and tab > 0:
			_set_tab(tab - 1)
		if pad.is_key_down(Pad.CANCEL):
			if menu_state == 1:
				_current_tab().leave()
				back.emit()
			play_sound(4)
		if tab == TAB_TECHNIQUES and pad.is_key_down(Pad.CONFIRM):
			if menu_state == 1:
				menu_state = 2
			play_sound(3)
	elif menu_state == 6:
		techniques_tab.tick_grid()
	elif menu_state == 8 and pad.is_key_down(Pad.CANCEL):
		menu_state = 9
		sub_state = 0
		play_sound(4)
	# The field's tamer and partner are drawn in the window instead (isOnScreen = 0).
	if tamer != null:
		tamer.visible = false
	if partner != null:
		partner.visible = false


func _set_tab(value: int) -> void:
	_current_tab().leave()
	tab = value
	menu_state = 0
	sub_state = 0
	play_sound(2)


## The render function's counting part: the strings, the state changes.
func update_box(_id: int) -> void:
	_current_tab().update()


## renderDigimonMenu (game_menu.c:1822): the tab, then the tab bar.
func draw_box(canvas: CanvasItem, _id: int) -> void:
	_current_tab().draw(canvas)
	var colors := [1, 1]
	colors[tab] = 0
	# The tabs first, their labels over them (the C adds the labels first: drawn last).
	MenuDraw.menu_tab(canvas, -0x91, 0x4C, colors[0] == 0)
	MenuDraw.menu_tab(canvas, -0x46, 0x40, colors[1] == 0)
	text_area.render_string(canvas, colors[0], -0x8A, -0x65, 0x3C, 0xC, 0, 0, true)
	text_area.render_string(canvas, colors[1], -0x3F, -0x65, 0x30, 0xC, 0x3C, 0, true)


# --- the state the tabs read -----------------------------------------------------------------------

func partner_state() -> Dictionary:
	return game_state.state["partner"]


func digimon_name() -> String:
	return data.localize(data.digimon(partner_state()["digimon"]).get("name")).strip_edges()


func playtime_frames() -> int:
	return int(game_state.state["clock"]["playtime"]["frames"])


## EQUIPPED_MOVES[slot]: the technique id in stats.base.moves[slot] (a technique key), -1 for none.
func equipped(slot: int) -> int:
	var key = partner_state()["stats"]["base"]["moves"][slot]
	return data.id_of("moves/move_data", key) if key != null else -1


func set_equipped(slot: int, id: int) -> void:
	var moves: Array = partner_state()["stats"]["base"]["moves"]
	moves[slot] = data.key_of("moves/move_data", id) if id >= 0 else null
	game_state.changed.emit("partner")


func has_move(id: int) -> bool:
	return game_state.has_move(id)


func move_name(id: int) -> String:
	return data.localize(data.move(id).get("name")).strip_edges()


## DIGIMON_DATA[type].moves: the technique ids the partner's Digimon can use.
func digimon_moves() -> Array:
	var out := []
	for entry in data.digimon(partner_state()["digimon"]).get("moves", []):
		var move = entry.get("move")
		if move != null:
			out.append(int(move["id"]))
	return out


func play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)
