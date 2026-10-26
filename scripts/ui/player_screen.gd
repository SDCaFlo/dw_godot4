class_name PlayerScreen
extends Node
## The Player screen (tickPlayerMenu / renderPlayerMenu, game_menu.c:1860, :2131;
## specs/status_screens.md §2, §4): box 1, the window of the △ menu's PLAYER, with the Info, Chart,
## Medals and Cards tabs (child nodes `Info`, `Chart`, `Medals`, `Cards`). The root of
## scenes/ui/player_screen.tscn, opened by GameMenu (its state 5) through the MenuHost.

## △ in a shown tab: back to the △ menu (TRIANGLE_MENU_STATE 6).
signal back

## PLAYER_VIEW_LABELS / CARD_CHART_LABELS (game_menu.c:987, :996), the text ids.
const PLAYER_LABELS := ["MAIN_D_80123A18", "MAIN_D_80123A3C", "MAIN_D_80123A60", "MAIN_D_80123A7C", "MAIN_D_80123A98"]
const CARD_CHART_LABELS := ["MAIN_D_80123AB0", "MAIN_D_80123AD0", "MAIN_D_80123AE4", "MAIN_D_80123B10", "MAIN_D_80123B20"]
const BOX := 1
const RECT := Rect2i(-0x96, -0x59, 300, 0xBE)
const TAB_INFO := 0
const TAB_CHART := 1
const TAB_MEDALS := 2
const TAB_CARDS := 3
## The footer's button glyph colours (US).
const FOOTER_GLYPH1 := 0xF
const FOOTER_GLYPH2 := 7
## The tab labels' text-area cells (US) and tab widths (renderPlayerMenu).
const TABS := [[-0x89, 0x3C, 0x00, -0x91, 0x4C], [-0x3E, 0x3C, 0x3C, -0x46, 0x4C], [0xD, 0x24, 0x78, 5, 0x34],
		[0x40, 0x24, 0x9C, 0x38, 0x34]]

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
var medal_view: DigiviceView

## PLAYER_MENU_STATE (the tab), MENU_STATE, MENU_SUB_STATE.
var tab := TAB_INFO
var menu_state := 0
var sub_state := 0
var is_open := false

@onready var info_tab: PlayerInfoTab = $Info
@onready var chart_tab: PlayerChartTab = $Chart
@onready var medals_tab: PlayerMedalsTab = $Medals
@onready var cards_tab: PlayerCardsTab = $Cards


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")
	for t in _tabs():
		t.screen = self


func _tabs() -> Array:
	return [info_tab, chart_tab, medals_tab, cards_tab]


func _current_tab() -> Node:
	return _tabs()[tab]


## tickTriangleMenu state 5 once box 0 is closed.
func open() -> void:
	var start := tamer.screen_rect() if tamer != null else Rect2i(-5, -5, 10, 10)
	boxes.create_animated(BOX, 1, 0, RECT, start, tick_box, draw_box, update_box)
	text_area.clear_all()
	text_area.draw_string(data.text(PLAYER_LABELS[0]), 0, 0)
	tab = TAB_INFO
	menu_state = 0
	sub_state = 0
	is_open = true


func close() -> void:
	_current_tab().leave()
	is_open = false


# --- tickPlayerMenu (game_menu.c:1860) ---------------------------------------------------------

func tick_box(_id: int) -> void:
	if menu_state < 2:
		if pad.is_changed(Pad.RIGHT) and tab + 1 < 4:
			_set_tab(tab + 1)
		if pad.is_changed(Pad.LEFT) and tab > 0:
			_set_tab(tab - 1)
		if pad.is_key_down(Pad.CANCEL):
			_current_tab().leave()
			back.emit()
			play_sound(4)
		if pad.is_key_down(Pad.CONFIRM) and menu_state == 1 and tab != TAB_INFO:
			menu_state = 2
			play_sound(3)
			medals_tab.selector = 0
			medals_tab.selected = 0
			cards_tab.selected = 0
	else:
		if pad.is_key_down(Pad.CANCEL) and menu_state == 2:
			play_sound(4)
			menu_state = 1
			chart_tab.selected_digimon = -1
		match tab:
			TAB_CHART:
				chart_tab.tick()
			TAB_MEDALS:
				# US: the medal cursor in every state from 2 (the other releases only in 2).
				medals_tab.tick()
			TAB_CARDS:
				cards_tab.tick()
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


func update_box(_id: int) -> void:
	_current_tab().update()


## renderPlayerMenu (game_menu.c:2131): the tab, then the tab bar (the tabs under their labels).
func draw_box(canvas: CanvasItem, _id: int) -> void:
	_current_tab().draw(canvas)
	for i in 4:
		MenuDraw.menu_tab(canvas, TABS[i][3], TABS[i][4], i == tab)
	for i in 4:
		text_area.render_string(canvas, 0 if i == tab else 1, TABS[i][0], -0x65, TABS[i][1], 0xC, TABS[i][2], 0, true)


# --- shared --------------------------------------------------------------------------------------

func playtime_frames() -> int:
	return int(game_state.state["clock"]["playtime"]["frames"])


## hasDigimonRaised (script_common.c:3019): trigger 0x200 + id.
func has_raised(digimon_id: int) -> bool:
	return game_state.is_raised(digimon_id)


## hasMedal (script_common.c:3033): trigger 0x16C + medal.
func has_medal(medal: int) -> bool:
	return game_state.is_trigger_set(0x16C + medal)


## getCardAmount: the collection's count of card `id`.
func card_amount(id: int) -> int:
	var key := str(data.card(id).get("key", ""))
	return int(game_state.state["script"]["cards"].get(key, 0))


func digimon_name(id: int) -> String:
	return data.localize(data.digimon(id).get("name")).strip_edges()


func play_sound(value: int) -> void:
	if sound != null:
		sound.play_sound(0, value)
