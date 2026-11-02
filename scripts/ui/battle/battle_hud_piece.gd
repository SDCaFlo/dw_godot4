class_name BattleHudPiece
extends Control
## One piece of the battle HUD (specs/battle.md §4, §5.2): one C object, drawn from the battle's
## state. The BattleHud hands it the battle and calls `on_visual` for every event of the battle
## (`Battle.visual`), then `tick` once per game frame, after the battle's frame. A mod can replace
## the scene of a piece in scenes/battle/battle_hud.tscn as long as it keeps this API.

## The battle's session (BattleSession), or the arena's match (ArenaMatch: specs/arena.md §4.6),
## which gives the pieces it reuses the same fields (`battle`, `start_text`, start_text_state()).
var session: Object
var world: BattleWorld
var text_area: TextArea
var boxes: UIBoxes
var data: Node


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# The text and windows' upscaling filter (PsxUiFilter, ISSUES.md D-3).
	material = PsxUiFilter.material()


var battle: Battle:
	get:
		return session.get("battle") if session != null else null


## A battle event (`Battle.visual(kind, args)`): the piece takes the kinds it draws.
func on_visual(_kind: String, _args: Array) -> void:
	pass


## Once per game frame. `pressed`: the buttons newly pressed this frame.
func tick(_pressed: int) -> void:
	queue_redraw()
