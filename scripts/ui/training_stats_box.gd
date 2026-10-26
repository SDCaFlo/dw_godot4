class_name TrainingStatsBox
extends RefCounted
## The stats box after a training session (TRN_createPostTrainingStatsBox,
## TRN_tickPostTrainingStatsBox, TRN_renderPostTrainingStatsBox; trn/trn_hud.c:162-335;
## specs/training.md §2.5): box 1 with the six stats, their bars and the gains, which count into
## Training's copy of the stats one point a frame (✕ or △ adds them all at once).

const BOX := 1
const RECT := Rect2i(-94, -78, 188, 96)
const DELAY := 100
const LABELS := ["STR_STAT_LABEL_HP", "STR_STAT_LABEL_MP", "STR_STAT_LABEL_OFFENSE", "STR_STAT_LABEL_DEFENSE",
		"STR_STAT_LABEL_SPEED", "STR_STAT_LABEL_BRAINS"]
const COUNT_SOUND := 0x16
## setEntityTextDigit(prim, 256, 491) on BI_IN: the "+" (u 96, v 180 on tpage 896,256).
const PLUS_TEXTURE := "etctim/00_bi_in"
const PLUS_PALETTE := 11
const PLUS_REGION := Rect2(96, 52, 12, 12)
const BAR_WIDTH := 50
const ROW_STEP := 13
## The bar colours: gained (light, dark) and not (light, dark).
const BAR_GAINED := [Color8(0x69, 0xC2, 0xFF), Color8(0, 0x5A, 0x96)]
const BAR_PLAIN := [Color8(0x78, 0x78, 0x78), Color8(0x28, 0x28, 0x28)]
const DIVIDER_LIGHT := 0xFAD990
const DIVIDER_DARK := 0x020202
const INSET_DARK := 0x020202
const INSET_LIGHT := 0x666666

var training: Training
var boxes: UIBoxes
var text_area: TextArea
var pad: Pad
var data: Node
## The box grows from here: func() -> Vector2i, the partner's bone 1 on screen (centred coords).
var origin := Callable()

## MAIN_D_80135394: ✕ / △ finishes the count.
var done := false
## MAIN_D_80135398: the stat was gained (its bar is blue).
var gained: Array[bool] = [false, false, false, false, false, false]
## MAIN_D_8013539E: frames before the count starts.
var delay := 0
var _plus: PsxTexture


## TRN_createPostTrainingStatsBox.
func create() -> void:
	done = false
	for i in Training.STATS.size():
		gained[i] = training.gains[i] != 0
	text_area.clear_all()
	for i in LABELS.size():
		text_area.draw_string(data.text(LABELS[i]), 0, i * 12)
	MenuDraw.draw_digits(text_area)
	delay = DELAY
	var at: Vector2i = origin.call() if origin.is_valid() else Vector2i.ZERO
	boxes.create_animated(BOX, 0, 2, RECT, Rect2i(at.x - 5, at.y - 5, 10, 10), tick, render, count)


## TRN_closeUIBox(1).
func close() -> void:
	if boxes.boxes[BOX].state != UIBoxes.STATE_CLOSED:
		boxes.remove_animated(BOX)


## TRN_tickPostTrainingStatsBox: ✕ or △ pressed alone adds every gain at once.
func tick(_id := 0) -> void:
	if delay > 0:
		delay -= 1
	if pad != null and (pad.polled == Pad.CONFIRM or pad.polled == Pad.CANCEL):
		if not (pad.polled_previous & Pad.CONFIRM) and not (pad.polled_previous & Pad.CANCEL):
			done = true
	if not done:
		return
	for i in Training.STATS.size():
		if training.gains[i] == 0:
			continue
		training.base[i] += training.gains[i]
		if training.gains[i] > 0 and training.base[i] > Training.stat_cap(i):
			training.base[i] = Training.stat_cap(i)
		training.gains[i] = 0
	delay = 0


## The counting part of TRN_renderPostTrainingStatsBox (each game frame): one point of the first
## positive gain, with its sound.
func count(_id := 0) -> void:
	if delay != 0:
		return
	for i in Training.STATS.size():
		if training.gains[i] > 0:
			boxes.sound.emit(COUNT_SOUND)
			training.gains[i] -= 1
			training.base[i] = mini(training.base[i] + 1, Training.stat_cap(i))
			return


## TRN_renderPostTrainingStatsBox's drawing, in reverse of the C's adds: the bars (back, then
## inset, then the filled part), the labels, the divider, the values, the gains and their "+".
func render(canvas: CanvasItem, _id: int) -> void:
	var box: Rect2i = boxes.boxes[BOX].final
	var bx := box.position.x
	var by := box.position.y
	for i in range(Training.STATS.size() - 1, -1, -1):
		var y := by + 20 + i * ROW_STEP
		var colours: Array = BAR_GAINED if gained[i] else BAR_PLAIN
		PsxDraw.box(canvas, Rect2i(bx + 66, y - 2, BAR_WIDTH, 2), colours[1])
		PsxDraw.line3(canvas, INSET_LIGHT, bx + 117, y - 2, bx + 117, y, bx + 65, y)
		PsxDraw.line3(canvas, INSET_DARK, bx + 64, y, bx + 64, y - 3, bx + 117, y - 3)
		var width := training.base[i] * BAR_WIDTH / Training.stat_cap(i)
		PsxDraw.box(canvas, Rect2i(bx + 66, y - 2, width, 2), colours[0])
	for i in range(Training.STATS.size() - 1, -1, -1):
		text_area.render_string(canvas, 4, bx + 10, by + 9 + i * ROW_STEP, 48, 12, 0, i * 12, false)
	PsxDraw.line2(canvas, DIVIDER_DARK, bx + 123, by + 2, bx + 123, by + box.size.y - 3)
	PsxDraw.line2(canvas, DIVIDER_LIGHT, bx + 122, by + 2, bx + 122, by + box.size.y - 3)
	for i in range(Training.STATS.size() - 1, -1, -1):
		MenuDraw.number(canvas, text_area, 0, bx + 68, by + 9 + i * ROW_STEP, 4, training.base[i])
	for i in range(Training.STATS.size() - 1, -1, -1):
		if training.gains[i] == 0:
			continue
		var y := by + 9 + i * ROW_STEP
		MenuDraw.number(canvas, text_area, 5, bx + 142, y, 3, training.gains[i])
		_draw_plus(canvas, bx + 130, y)


func _draw_plus(canvas: CanvasItem, x: int, y: int) -> void:
	if _plus == null:
		_plus = PsxTexture.load_palette(PLUS_TEXTURE, PLUS_PALETTE)
	if _plus == null:
		return
	canvas.draw_texture_rect_region(_plus.base, Rect2(PsxDraw.CENTRE + Vector2(x, y), PLUS_REGION.size), PLUS_REGION)
