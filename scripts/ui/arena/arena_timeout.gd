extends ArenaHudPiece
## The time-out (STD_tickBattleResultScreen's objects, std_main.c:4641-4730, 5617-5650): "TIME UP"
## (STD_renderTimeoutText: the STDTIM page (832, 0) palette 0, u 0, v 8, 0x90 x 0x18 at (-0x48, -0xC),
## layer 5), then the damage window (STD_addTimeoutWindow: UI box 0 opening from (-10, -10, 20, 20)
## to (-132, -27, 264, 54); the text area holds "Dealt" / "Damage" and the two names, each centred
## in 120 px; STD_renderTimeoutWindow: the names, "Damage" and both damages (the opponent's taken
## under the partner, as the C draws STD_DAMAGE[1] at x + 42 and STD_DAMAGE[0] at x + 174)).
## The US release's STD_STR_DEALT / STD_STR_DAMAGE are Japanese literals (std_main.c:734, 1493):
## drawn through the US font as the C does.

const PAGE := "stdtim/02_time_up"
const CLUT := 480
const DEALT := "与えた"
const DAMAGE := "ダメージ"
const WINDOW := Rect2i(-132, -27, 264, 54)
const WINDOW_START := Rect2i(-10, -10, 20, 20)

var _text_shown := false
var _window := false


func on_visual(kind: String, args: Array) -> void:
	match kind:
		"timeout_text":
			_text_shown = bool(args[0])
		"timeout_window":
			if bool(args[0]):
				_open_window()
			else:
				_close_window()
	shown = _text_shown or _window


func build() -> void:
	if _text_shown:
		var p := ft4(PAGE, CLUT, 0, 8, 0x90, 0x18, -0x48, -0xC)
		p["kind"] = "time_up"
		prims.append(p)


## STD_addTimeoutWindow (4698): the text area, then the animated box (its render draws the rest).
func _open_window() -> void:
	# removeObject(0x1A2): the TIME UP text goes when the window opens.
	_text_shown = false
	_window = true
	if text_area != null:
		text_area.clear_all()
		text_area.draw_string(DEALT, 6, 0)
		text_area.draw_string(DAMAGE, 0, 12)
		var pn: String = session.partner_name()
		var on: String = session.opponent_name()
		text_area.draw_string(pn, (120 - pn.length() * 6) / 2, 24)
		text_area.draw_string(on, (120 - on.length() * 6) / 2, 36)
	if boxes != null:
		boxes.create_animated(0, 0, 2, WINDOW, WINDOW_START, Callable(), _render_window)


func _close_window() -> void:
	if _window and boxes != null and boxes.boxes[0].state != UIBoxes.STATE_CLOSED:
		boxes.remove_animated(0)
	_window = false


## STD_renderTimeoutWindow (5632): at the box's final place.
func _render_window(canvas: CanvasItem, id: int) -> void:
	if text_area == null:
		return
	var r: Rect2i = boxes.boxes[id].final
	var x := r.position.x
	var y := r.position.y
	text_area.render_string(canvas, 0, x + 6, y + 6, 120, 12, 0, 24, true)
	text_area.render_string(canvas, 0, x + 138, y + 6, 120, 12, 0, 36, true)
	text_area.render_string(canvas, 0, x + 108, y + 24, 48, 24, 0, 0, true)
	var dmg: Array = session.damage
	_damage_digits(canvas, int(dmg[1]), x + 42, y + 30)
	_damage_digits(canvas, int(dmg[0]), x + 174, y + 30)


## STD_renderIntroStatNumber(x + (48 - digits * 12) / 2, y, digits, value): centred in 48 px.
func _damage_digits(canvas: CanvasItem, value: int, x: int, y: int) -> void:
	var count := BattleHudDraw.digits(value, 4).size()
	var tex := BattleHudDraw.texture(PAGE, 0)
	for p in digit_prims(value, count, x + (48 - count * 12) / 2, 12,
			func(d: int, dx: int) -> Dictionary: return ft4(PAGE, CLUT, d * 12, 32, 12, 12, dx, y)):
		BattleHudDraw.rect(canvas, tex, p["uv"].position.x, p["uv"].position.y, 12, 12, p["pts"][0].x, p["pts"][0].y, 12, 12)
