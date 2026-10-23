class_name MessageBox
extends RefCounted
## A text window: a UI box showing rows of the text area, with the blinking "next" arrow, that
## grows from a point on screen and shrinks back to one (specs/text.md §2.5).
##
## The defaults are the tamer's award / sickness box (tamerTickAwardSomething and
## renderAwardSomethingTextbox, tamer.c:1751 / 1351): box 1, rect (-130, 42, 262, 59), half-dark
## fill, the text-area rows 120-155. Another window sets its own slot, rect and strings:
##
##   var box := MessageBox.new(ui_boxes, text_area)
##   text_area.clear(Rect2i(0, 120, 256, 36)); text_area.draw_string("Hello", 0, 120)
##   box.open(Rect2i(-5, -5, 10, 10))      # grows from the screen centre
##   ...
##   box.close(Rect2i(-5, -5, 10, 10))
##
## The caller decides when to close (the tamer on the confirm button); `arrow` false hides the arrow.

var boxes: UIBoxes
var text_area: TextArea
var box_id := 1
var rect := Rect2i(-130, 42, 262, 59)
## UI_BOX_COLORS index.
var color := 0
var features := UIBoxes.FEATURE_HALF_FILL
## The renderString calls drawn inside the box, in the C's argument order:
## [color, x, y, w, h, u, v, shadow] (screen x / y relative to the centre, like the rect).
var strings: Array = [[0, -125, 45, 240, 36, 0, 120, false]]
var arrow := true


func _init(ui_boxes: UIBoxes, area: TextArea) -> void:
	boxes = ui_boxes
	text_area = area


## isUIBoxAvailable(box_id): the slot can take a new box.
func is_available() -> bool:
	return boxes.is_available(box_id)


## True from open() until the closing animation has ended.
func is_shown() -> bool:
	return boxes.boxes[box_id].registered


## createAnimatedUIBox(box_id, color, features, rect, from, NULL, render).
func open(from: Rect2i) -> void:
	boxes.create_animated(box_id, color, features, rect, from, Callable(), _render, _on_render)


## removeAnimatedUIBox(box_id, to).
func close(to = null) -> void:
	boxes.remove_animated(box_id, to)


## renderAwardSomethingTextbox, counting part: renderUIBox(box) with the timer, then
## ++TEXTBOX_OPEN_TIMER.
func _on_render(id: int) -> void:
	if arrow:
		boxes.show_next_arrow(id, boxes.textbox_open_timer)
	boxes.textbox_open_timer = (boxes.textbox_open_timer + 1) & 0xFF


## renderAwardSomethingTextbox, drawing part: the strings (the arrow, added after them, is drawn
## below them by UIBoxes).
func _render(canvas: CanvasItem, _id: int) -> void:
	for s in strings:
		text_area.render_string(canvas, s[0], s[1], s[2], s[3], s[4], s[5], s[6], s[7])
