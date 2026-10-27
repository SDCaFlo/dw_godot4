extends BattleHudPiece
## The finisher's charge-up gauge (command_menu.c:360-452: BTL_initializeFinisherChargeup,
## BTL_renderFinisherChargeup): a 46 x 12 frame over the partner's head with a 4-px bar per 8
## points of Battle.finisher_chargeup (L1 / R1 presses). Placed once, when the wind-up starts; it
## goes after its last frame (BTL_removeFinisherChargeup in the render at time 0).

## Page (960, 256), BTLCOMND palette 2.
const CLUT := 498
const V := 0xE0

var shown := false
var at := Vector2i.ZERO
var _closing := false


func on_visual(kind: String, args: Array) -> void:
	if kind != "chargeup":
		return
	if bool(args[0]):
		shown = true
		_closing = false
		var f := battle.fighters[0]
		var loc := world.location(f.entity)
		var p := world.project(Vector3i(loc.x, -world.height(f.entity) - 0x64, loc.z))
		# The GTE's screen position minus (0xB7, 0x8C), in the centred coordinates.
		at = Vector2i(clampi(p.x - (0xB7 - 0xA0), -0x64, 0x64), clampi(p.y - (0x8C - 0x78), -0x64, 0x64))
	else:
		# The C draws the frame it is removed in.
		_closing = true


func tick(_pressed: int) -> void:
	if _closing and not shown:
		_closing = false
	elif _closing:
		shown = false
	queue_redraw()


func _draw() -> void:
	if not (shown or _closing) or battle == null:
		return
	var tex := BattleHudDraw.page_960(CLUT, V)
	# The bars go into the layer after the frame: drawn under it.
	for i in battle.finisher_chargeup / 8:
		BattleHudDraw.rect(self, tex, 0x88, BattleHudDraw.row(V), 4, 6, at.x + 3 + i * 4, at.y + 3, 4, 6)
	BattleHudDraw.rect(self, tex, 0x58, BattleHudDraw.row(V), 46, 12, at.x, at.y, 0x2E, 0xC)
