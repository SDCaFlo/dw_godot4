class_name BattleHud
extends Control
## The battle HUD (specs/battle.md §4, §5.2), the root of scenes/battle/battle_hud.tscn: its
## children are the pieces (BattleHudPiece), one C object each, back to front in the ordering
## table's layers (the numbers at 14, the partner's bars at 10, the flee bubbles at 8, the
## layer-7 objects, the start text at 5-6). The BattleHost makes it for a battle and frees it
## after; it is a Control in the field's HUD, behind the UI boxes the end boxes open.

var session: BattleSession
var world: BattleWorld
var text_area: TextArea
var boxes: UIBoxes
var data: Node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	for piece in pieces():
		piece.session = session
		piece.world = world
		piece.text_area = text_area
		piece.boxes = boxes
		piece.data = data


func pieces() -> Array[BattleHudPiece]:
	var out: Array[BattleHudPiece] = []
	for c in get_children():
		if c is BattleHudPiece:
			out.append(c)
	return out


func on_visual(kind: String, args: Array) -> void:
	for piece in pieces():
		piece.on_visual(kind, args)


func tick(pressed: int) -> void:
	for piece in pieces():
		piece.tick(pressed)


func _end_boxes() -> Node:
	return get_node_or_null("EndBoxes")


## BattleSession's hook: UI_BOX_DATA[0] and [1] (then [2]) have opened.
func end_boxes_open() -> bool:
	var e := _end_boxes()
	return e.boxes_open() if e != null else true


## BattleSession's hook: BTL_isEndBoxTextFinished.
func end_text_done() -> bool:
	var e := _end_boxes()
	return e.text_done() if e != null else true
