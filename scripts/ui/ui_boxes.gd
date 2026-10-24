class_name UIBoxes
extends Control
## The six UI boxes, the game's window frames (ui.c, UI_BOX_DATA[6]; specs/text.md §2.4), in the
## 320 x 240 HUD. Every window of the original is one of these slots with its own contents:
## the message box, the dialogue box, menus, shops. A new window is a slot plus a `render` callable
## (see docs/ui.md):
##
##   boxes.create_animated(1, 0, UIBoxes.FEATURE_HALF_FILL, Rect2i(-130, 42, 262, 59), from_rect,
##           Callable(), my_render)        # opens with the outline animation
##   boxes.create_static(2, 1, 0, rect, my_tick, my_render)    # open at once
##   boxes.remove_animated(1, to_rect) / boxes.remove_static(2)
##
## Each game frame (GameLoop.frame) runs the original's object pass: the tick of every open box
## (tickUIBox), then its render step (renderUIBoxAnimated / renderUIBoxStatic). What that step
## decided is drawn in _draw. Box i is on ordering-table layer 6 - i, so box 5 is in front.

## playSound(0, id): 0 when an animated box opens, 1 when its closing animation starts.
signal sound(id: int)
## The slot became free (removeStaticUIBox).
signal closed(id: int)

const COUNT := 6
## UIBoxData.state.
const STATE_CLOSED := 0
const STATE_OPEN := 1
const STATE_OPENING := 2
const STATE_CLOSING := 3
## Used by the menus (tickUIBox ticks it like an open box).
const STATE_MENU := 4
## UIBoxData.features bits (renderUIBoxStatic).
const FEATURE_TITLE := 1
const FEATURE_HALF_FILL := 2
const FEATURE_SCROLL_BAR := 4
## Line colour words (renderUIBoxBorder, renderUIBoxStatic; low byte = red).
const BLACK := 0x020202
const LIGHT := 0xFAD990
const MID := 0xC59F4A
const SCROLL := 0xA08769
const OUTLINE := 0x808080
## UI_BOX_COLORS (ui.c:63): the fill colour by UIBoxData.color.
const COLORS: Array[Color] = [Color8(0, 0, 0), Color8(0x2D, 0x38, 0x40), Color8(0, 0, 0), Color8(0, 0, 0), Color8(0, 0, 0)]
const SCROLL_TRACK := Color8(0x35, 0x4B, 0x5C)
const SCROLL_BAR := Color8(0x5B, 0x70, 0x80)
## ETCDAT/SYSTEM_W.TIM: page (320, 0), image from v 128 (asset porter etctim/08_system_w).
const TEXTURE := "etctim/08_system_w"
## BOX_BORDER_CORNERS_U / _V (ui.c:55): 4 x 4 corners at v + 0x80 in the page, palette (0x60, 0x1EC) = p4.
const CORNERS_U := [0x78, 0x7C, 0x78, 0x7C]
const CORNERS_V := [0x10, 0x10, 0x14, 0x14]
const CORNER_PALETTE := 4
## renderUIBox (script_textbox.c:996): the "next" arrow, 16 x 12 at u 0x4C + 16 * frame, v 0xB7
## (image v 0x37), palette (96, 500) = p12, semi-transparency mode 1.
const ARROW_PALETTE := 12
const ARROW_V := 0xB7 - 128
## drawn: what the render step of this frame decided.
const DRAWN_NOTHING := -1
const DRAWN_STATIC := 99


## UIBoxData (include/dw/ui.h:10).
class Box:
	var start := Rect2i()
	var final := Rect2i()
	var frame := 0
	var state := STATE_CLOSED
	## The scroll bar of FEATURE_SCROLL_BAR: rows scrolled, rows shown, rows in all.
	var row_offset := 0
	var visible_rows := 1
	var total_rows := 1
	var features := 0
	var color := 0
	## TickFunction: func(id), once per game frame while the box is open (state 1 or 4).
	var tick := Callable()
	## RenderFunction, drawing part: func(canvas: CanvasItem, id) draws the contents in front of the
	## frame, in the screen coordinates of PsxDraw / TextArea.render_string, back to front.
	var render := Callable()
	## RenderFunction, counting part: func(id), once per game frame where the original calls the
	## render function (an open box; not while it animates). Counters like TEXTBOX_OPEN_TIMER go here.
	var on_render := Callable()
	## addObject(0x1a4, id) with renderUIBoxAnimated (true) or renderUIBoxStatic (false).
	var registered := false
	var animated := false
	var drawn := DRAWN_NOTHING
	## The "next" arrow's timer this frame (-1 = not shown); set by show_next_arrow.
	var arrow := -1


var boxes: Array[Box] = []
## TEXTBOX_OPEN_TIMER (script_interp.c:209), uint8: counted by the text boxes, picks the arrow frame.
var textbox_open_timer := 0

var _corners: Texture2D
var _arrow: PsxTexture
var _additive: Control


func _init() -> void:
	for i in COUNT:
		boxes.append(Box.new())


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	# The text and windows' upscaling filter (PsxUiFilter, ISSUES.md D-3).
	material = PsxUiFilter.material()
	_corners = Content.load_texture("%s.p%d.png" % [TEXTURE, CORNER_PALETTE])
	_arrow = PsxTexture.load_palette(TEXTURE, ARROW_PALETTE)
	# Mode-1 texels add to the screen: a child canvas with an additive material.
	_additive = Control.new()
	_additive.mouse_filter = MOUSE_FILTER_IGNORE
	_additive.set_anchors_preset(Control.PRESET_FULL_RECT)
	_additive.material = PsxUiFilter.material("add")
	_additive.draw.connect(_draw_additive)
	add_child(_additive)
	var loop := get_node_or_null("/root/GameLoop")
	if loop != null:
		loop.frame.connect(step)


# --- ui.c ----------------------------------------------------------------------------------------

## createStaticUIBox (ui.c:194): open at once.
func create_static(id: int, color: int, features: int, rect: Rect2i, tick := Callable(), render := Callable(), on_render := Callable()) -> void:
	var b := boxes[id]
	b.state = STATE_OPEN
	b.color = color
	b.features = features
	b.render = render
	b.on_render = on_render
	b.tick = tick
	b.final = rect
	b.registered = true
	b.animated = false


## removeStaticUIBox (ui.c:209).
func remove_static(id: int) -> void:
	var b := boxes[id]
	b.state = STATE_CLOSED
	b.frame = 0
	b.registered = false
	closed.emit(id)


## createAnimatedUIBox (ui.c:216): grows from `start` to `rect` as an outline (frames 0-4), then
## is open. The frame counter isn't reset: it is 0 for a free slot.
func create_animated(id: int, color: int, features: int, rect: Rect2i, start: Rect2i, tick := Callable(), render := Callable(), on_render := Callable()) -> void:
	var b := boxes[id]
	sound.emit(0)
	b.state = STATE_OPENING
	b.color = color
	b.features = features
	b.start = start
	b.final = rect
	b.render = render
	b.on_render = on_render
	b.tick = tick
	b.registered = true
	b.animated = true


## removeAnimatedUIBox (ui.c:259): shrinks back to its start rect, or to `target`, then is free.
func remove_animated(id: int, target = null) -> void:
	var b := boxes[id]
	if target is Rect2i:
		b.start = target
	b.state = STATE_CLOSING


## isUIBoxAvailable (game_menu.c, asm only): true when the box is open (state 1) or its frame
## counter is 0 (free, or a static box); false while it animates.
func is_available(id: int) -> bool:
	var b := boxes[id]
	if b.state == STATE_OPEN:
		return true
	return b.frame == 0


## One game frame: tickUIBox of every box (ui.c:111), then its render function.
func step() -> void:
	for i in COUNT:
		var b := boxes[i]
		if b.registered and (b.state == STATE_OPEN or b.state == STATE_MENU) and b.tick.is_valid():
			b.tick.call(i)
	for i in COUNT:
		var b := boxes[i]
		b.drawn = DRAWN_NOTHING
		b.arrow = -1
		if not b.registered:
			continue
		if b.animated:
			_render_animated(i)
		else:
			_render_static(i)
	queue_redraw()
	if _additive != null:
		_additive.queue_redraw()


## renderUIBoxAnimated (ui.c:234): frames 0-4 while opening, 4-0 while closing, then the open box
## or a free slot.
func _render_animated(id: int) -> void:
	var b := boxes[id]
	if b.state == STATE_OPENING or b.state == STATE_CLOSING:
		var current := 0
		if b.state == STATE_OPENING:
			current = b.frame
			b.frame += 1
		else:
			b.frame -= 1
			current = b.frame
		# renderUIBoxAnim (ui.c:324): the closing sound on its first frame.
		if b.state == STATE_CLOSING and b.frame == 4:
			sound.emit(1)
		b.drawn = current
		if b.frame > 4:
			b.state = STATE_OPEN
		if b.frame == 0:
			remove_static(id)
	else:
		_render_static(id)


## renderUIBoxStatic (ui.c:120): the contents' render function, then the frame.
func _render_static(id: int) -> void:
	var b := boxes[id]
	b.drawn = DRAWN_STATIC
	if b.on_render.is_valid():
		b.on_render.call(id)


## renderUIBox (script_textbox.c:996) for this frame: the "next" arrow at the box's (239, 43),
## its frame from `timer` (TEXTBOX_OPEN_TIMER / 4 % 3). Call from the box's on_render.
func show_next_arrow(id: int, timer: int) -> void:
	boxes[id].arrow = timer


## The interpolated outline of renderUIBoxAnim (ui.c:340-345) at `frame` (0 = start, 4 = final).
static func anim_rect(start: Rect2i, final: Rect2i, frame: int) -> Rect2i:
	var x0 := start.position.x + frame * (final.position.x - start.position.x) / 4
	var y0 := start.position.y + frame * (final.position.y - start.position.y) / 4
	var x1 := start.end.x + frame * (final.end.x - start.end.x) / 4
	var y1 := start.end.y + frame * (final.end.y - start.end.y) / 4
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


# --- drawing -------------------------------------------------------------------------------------

func _draw() -> void:
	for i in COUNT:
		var b := boxes[i]
		if b.drawn == DRAWN_STATIC:
			draw_box(self, b)
			if b.arrow >= 0:
				_draw_arrow(self, b, false)
			if b.render.is_valid():
				b.render.call(self, i)
		elif b.drawn >= 0:
			var r := anim_rect(b.start, b.final, b.drawn)
			PsxDraw.line3(self, OUTLINE, r.position.x, r.position.y, r.end.x, r.position.y, r.end.x, r.end.y)
			PsxDraw.line3(self, OUTLINE, r.end.x, r.end.y, r.position.x, r.end.y, r.position.x, r.position.y)


func _draw_additive() -> void:
	for b in boxes:
		if b.drawn == DRAWN_STATIC and b.arrow >= 0:
			_draw_arrow(_additive, b, true)


func _draw_arrow(canvas: CanvasItem, b: Box, stp: bool) -> void:
	if _arrow == null:
		return
	var u := b.arrow / 4 % 3 * 16 + 0x4C
	PsxDraw.sprite(canvas, _arrow, Rect2(u, ARROW_V, 16, 12), b.final.position.x + 0xEF, b.final.position.y + 0x2B, stp)


## renderUIBoxStatic's frame (ui.c:138-191) for any canvas. The C adds the fill last, so the
## ordering table draws it first: fill, scroll bar, title rule, inner lines, border, corners.
func draw_box(canvas: CanvasItem, b: Box) -> void:
	var r := b.final
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	PsxDraw.box(canvas, Rect2i(x + 4, y + 3, w - 8, h - 3), COLORS[b.color], b.features & FEATURE_HALF_FILL != 0)
	if b.features & FEATURE_SCROLL_BAR:
		var h25 := h - 25
		var row_height := h25 * b.visible_rows / maxi(b.total_rows, 1)
		var span := b.total_rows - b.visible_rows
		var bar_top := y + 14 + ((h25 - row_height) * b.row_offset / span if span != 0 else 0)
		PsxDraw.box(canvas, Rect2i(x + w - 12, y + 14, 6, h - 24), SCROLL_TRACK)
		PsxDraw.box(canvas, Rect2i(x + w - 11, bar_top + 1, 4, row_height - 1), SCROLL_BAR)
		PsxDraw.line3(canvas, SCROLL, x + w - 12, bar_top + row_height, x + w - 12, bar_top, x + w - 6, bar_top)
		PsxDraw.line3(canvas, BLACK, x + w - 7, bar_top, x + w - 7, bar_top + row_height, x + w - 13, bar_top + row_height)
		PsxDraw.line3(canvas, SCROLL, x + w - 6, y + 14, x + w - 6, y + h - 10, x + w - 12, y + h - 10)
		PsxDraw.line3(canvas, BLACK, x + w - 13, y + h - 10, x + w - 13, y + 13, x + w - 6, y + 13)
	if b.features & FEATURE_TITLE:
		PsxDraw.line2(canvas, BLACK, x + 3, y + 15, x + w - 3, y + 15)
		PsxDraw.line2(canvas, LIGHT, x + 3, y + 14, x + w - 3, y + 14)
		PsxDraw.line2(canvas, BLACK, x + 3, y + 13, x + w - 3, y + 13)
	PsxDraw.line2(canvas, BLACK, x + w - 4, y + 3, x + w - 4, y + h - 3)
	PsxDraw.line2(canvas, BLACK, x + 3, y + 3, x + 3, y + h - 3)
	draw_border(canvas, r)


## renderUIBoxBorder (ui.c:267): three lines on each edge, then the four corner sprites on top.
func draw_border(canvas: CanvasItem, r: Rect2i) -> void:
	var x := r.position.x
	var y := r.position.y
	var w := r.size.x
	var h := r.size.y
	var y1 := y + h - 3
	for edge in [[x + w - 3, LIGHT], [x + w - 2, MID], [x + w - 1, BLACK], [x, BLACK], [x + 1, MID], [x + 2, LIGHT]]:
		PsxDraw.line2(canvas, edge[1], edge[0], y + 4, edge[0], y1)
	for edge in [[y + h - 3, BLACK], [y + h - 2, LIGHT], [y + h - 1, BLACK], [y, BLACK], [y + 1, LIGHT], [y + 2, BLACK]]:
		PsxDraw.line2(canvas, edge[1], x + 4, edge[0], x + w - 4, edge[0])
	if _corners == null:
		return
	for i in 4:
		var px := x if i % 2 == 0 else x + w - 4
		var py := y if i < 2 else y + h - 4
		canvas.draw_texture_rect_region(_corners, Rect2(PsxDraw.CENTRE + Vector2(px, py), Vector2(4, 4)),
				Rect2(CORNERS_U[i], CORNERS_V[i], 4, 4))
