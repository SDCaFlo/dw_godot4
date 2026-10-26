class_name TrainingBrainsBox
extends RefCounted
## Box 2 of the Brains training (TRN_awardBrainsTrainingGains, TRN_renderNewOrdersBox,
## TRN_tryLearnMove, TRN_renderMoveLearnedBox; trn/trn_reward.c:551-592, :806-882;
## specs/training.md §6.8): the new orders the partner now listens to, or the technique it
## mastered. Their lines are drawn into the text area from row 0x78, below the stats box's labels,
## and the box shows them (createMenuBox: colour 1, grown from the tamer).

const BOX := 2
const ORDERS_RECT := Rect2i(-0x58, 0x12, 0xB0, 0x30)
const MASTERED_RECT := Rect2i(-0x58, 0x12, 0xB0, 0x23)
const LINE_Y := 0x78
const SECOND_Y := 0x84
## "New orders!" goes under the orders, one line lower after the two-line 300 order.
const NEW_ORDERS_Y := 0x84
const NEW_ORDERS_LOW_Y := 0x94
const ORDER_COLOR := 7
const NEW_ORDERS_COLOR := 1
const NEW_ORDERS_TEXT := "TRN_D_8008F140"
const MASTERED_TEXT := "TRN_D_8008F19C"
## The text drawn from (-78, 24): renderString(…, u 0, v 120).
const TEXT_X := -78
const TEXT_Y := 24
const GLYPH := 12

var boxes: UIBoxes
var text_area: TextArea
var data: Node
## func(bone: int) -> Rect2i: the 10 x 10 rect around the tamer's bone on screen (centred coords).
var tamer_rect := Callable()

## MAIN_D_80135392: the mastered technique's name length (strlen).
var name_length := 0
var _mastered := false


## The new orders (`orders`: Training.new_orders), each over the last at row 0x78, then
## "New orders!", then the box.
func show_orders(orders: Array) -> void:
	var y := NEW_ORDERS_Y
	for lines in orders:
		text_area.set_text_color(ORDER_COLOR)
		text_area.draw_string(data.text(lines[0]), 0, LINE_Y)
		if lines.size() > 1:
			text_area.draw_string(data.text(lines[1]), 0, SECOND_Y)
			y = NEW_ORDERS_LOW_Y
	text_area.set_text_color(NEW_ORDERS_COLOR)
	text_area.draw_string(data.text(NEW_ORDERS_TEXT), 0, y)
	_mastered = false
	_open(ORDERS_RECT)


## The technique's name and "was mastered!", in the text colour already set, then the box.
func show_mastered(move: int) -> void:
	var move_name: String = data.text_entry("main/item", "MOVE_NAMES", move)
	text_area.draw_string(move_name, 0, LINE_Y)
	name_length = move_name.length()
	text_area.draw_string(data.text(MASTERED_TEXT), 0, SECOND_Y)
	_mastered = true
	_open(MASTERED_RECT)


## createMenuBox(2, …): nothing while the box is open or still animating.
func _open(rect: Rect2i) -> void:
	var b: UIBoxes.Box = boxes.boxes[BOX]
	if b.state == UIBoxes.STATE_OPEN or b.frame != 0:
		return
	var start: Rect2i = tamer_rect.call(1) if tamer_rect.is_valid() else Rect2i(-5, -5, 10, 10)
	boxes.create_animated(BOX, 1, UIBoxes.FEATURE_HALF_FILL, rect, start, Callable(), render)


## The Brains station's end: an open box 2 closes towards the tamer's bone 0.
func close() -> void:
	if boxes.boxes[BOX].state == UIBoxes.STATE_OPEN:
		boxes.remove_animated(BOX, tamer_rect.call(0) if tamer_rect.is_valid() else null)


## TRN_renderNewOrdersBox / TRN_renderMoveLearnedBox. The second fits the JP text (a name in
## 12-pixel glyphs, then "を" and "おぼえた"); with the US font it cuts the lines as the C does.
func render(canvas: CanvasItem, _id: int) -> void:
	if not _mastered:
		text_area.render_string(canvas, 0, TEXT_X, TEXT_Y, 240, 48, 0, LINE_Y)
		return
	var w := (name_length / 2) * GLYPH
	text_area.render_string(canvas, 3, TEXT_X, TEXT_Y, w, GLYPH, 0, LINE_Y)
	text_area.render_string(canvas, 0, w + TEXT_X, TEXT_Y, GLYPH, GLYPH, 0, SECOND_Y)
	text_area.render_string(canvas, 0, TEXT_X, TEXT_Y + GLYPH, 48, GLYPH, GLYPH, SECOND_Y)
