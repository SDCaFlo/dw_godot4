class_name ArenaHud
extends Control
## The arena's HUD (specs/arena.md §4.6, step 5), the root of scenes/arena/arena_hud.tscn: its children
## are the pieces, one C object each (the arena's own ArenaHudPiece ones and the battle's StartText,
## EntityNumbers and FinisherChargeup, which take the match as their session), back to front in the
## ordering table's layers. The Arena makes it for a tournament (in the field's HUD slot, behind the
## UI boxes the time-out window uses), gives it each match, its events and a tick per frame.

var session: Object
## The tournament (ArenaSession): the bracket view and the scenes read it.
var tournament: Object
var world: BattleWorld
var text_area: TextArea
var boxes: UIBoxes
var data: Node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_share()


func pieces() -> Array[BattleHudPiece]:
	var out: Array[BattleHudPiece] = []
	for c in get_children():
		if c is BattleHudPiece:
			out.append(c)
	return out


func _share() -> void:
	var numbers := get_node_or_null("EntityNumbers")
	if numbers != null:
		numbers.follows = true
	for piece in pieces():
		piece.session = session
		if "tournament" in piece:
			piece.tournament = tournament
		piece.world = world
		piece.text_area = text_area
		piece.boxes = boxes
		piece.data = data


## The tournament (once, before its first frame).
func set_tournament(t: Object) -> void:
	tournament = t
	_share()


## The current match (a new one each round of the tournament).
func set_match(m: Object) -> void:
	session = m
	_share()


func on_visual(kind: String, args: Array) -> void:
	for piece in pieces():
		piece.on_visual(kind, args)


func tick(pressed: int) -> void:
	for piece in pieces():
		piece.tick(pressed)
