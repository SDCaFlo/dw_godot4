extends BattleHudPiece
## A won battle's end boxes (main/battle_ui.c: createPostBattleStatsBox, createBitsBox,
## createFinalBalanceBox and their renders; battle_hud.c:245-530 the end text): box 0 the stats
## with their gains (grows from the partner), box 1 the bits and the text (from the tamer), box 2
## the final balance. The counting is BattleRewards' (the session's END_BOX phase); this piece
## opens the boxes, draws them and types the text (BTL_tickBattleEndText), and answers the
## session's hooks (boxes_open, text_done).

const STATS_RECT := Rect2i(-88, -78, 176, 96)
const BALANCE_RECT := Rect2i(-88, -13, 176, 31)
const LABELS := ["STR_STAT_LABEL_HP", "STR_STAT_LABEL_MP", "STR_STAT_LABEL_OFFENSE", "STR_STAT_LABEL_DEFENSE",
		"STR_STAT_LABEL_SPEED", "STR_STAT_LABEL_BRAINS"]
const BITS_ROW := 72
const ROW_STEP := 13
const BAR_WIDTH := 50
const BAR_GAINED := [Color8(0x69, 0xC2, 0xFF), Color8(0, 0x5A, 0x96)]
const BAR_PLAIN := [Color8(0x78, 0x78, 0x78), Color8(0x28, 0x28, 0x28)]
## The "+" before a gain: BI_IN palette 11 (CLUT row 491), u 96, v 180.
const PLUS_CLUT := 491
## The end text (BTL_initializeBattleEndText(0x60, 2, (-78, 54, 156, 24))): text-area rows from 0x60,
## two rows shown; a #W waits 60 frames.
const TEXT_ROW := 0x60
const TEXT_RECT := Rect2i(-78, 54, 156, 24)
const VISIBLE_ROWS := 2
const WAIT_FRAMES := 0x3C
## BTL_appendCommandLearnedText's texts per brains threshold, and the lines each takes.
const COMMAND_TEXTS := {500: ["BTL_STR_SET_TECHNIQUE", 2], 400: ["BTL_STR_PUT_UP_WITH_IT", 2],
		300: ["BTL_STR_MOVE_AWAY_CHANGE_TARGET", 3], 200: ["BTL_STR_KEEP_IT_DOWN", 2], 100: ["BTL_STR_GO_ALL_THE_WAY", 2]}

var rewards: BattleRewards
## STAT_BOX_HAS_GAIN.
var has_gain: Array[bool] = [false, false, false, false, false, false]
var balance := false
var _opened := false
## The end text: BTL_END_BOX_TEXTBUFFER, its cursor and pen, the rows (BATTLE_END_*).
var text := ""
var cursor := 0
var typing := false
var pen := Vector2i.ZERO
var v := TEXT_ROW
var rows_shown := 0
var rows_drawn := 0
var line_count := 0
var wait_timer := WAIT_FRAMES


func on_visual(kind: String, args: Array) -> void:
	match kind:
		"end_box":
			open(args[0])
		"final_balance":
			# createFinalBalanceBox: from where the bits box started.
			balance = true
			boxes.create_animated(2, 1, 0, BALANCE_RECT, boxes.boxes[1].start, Callable(), _render_balance)
		"end_box_close":
			for id in 3:
				if boxes.boxes[id].state != UIBoxes.STATE_CLOSED:
					boxes.remove_animated(id)


## handleBattleEndBox's boxes: the text, then createPostBattleStatsBox and createBitsBox.
func open(battle_rewards: BattleRewards) -> void:
	rewards = battle_rewards
	balance = false
	_opened = false
	_build_text()
	for i in 6:
		has_gain[i] = rewards.gains[i] != 0
	text_area.clear_all()
	for i in LABELS.size():
		text_area.draw_string(data.text(LABELS[i]), 0, i * 12)
	MenuDraw.draw_digits(text_area)
	var partner := world.screen_position(battle.fighters[0].entity, 1)
	boxes.create_animated(0, 0, 2, STATS_RECT, Rect2i(partner.x - 5, partner.y - 5, 10, 10), Callable(), _render_stats)
	var tamer := world.screen_position(BattleSession.TAMER, 1)
	boxes.create_animated(1, 0, 2, Rect2i(-88, 18, 176, 66 if text != "" else 31),
			Rect2i(tamer.x - 5, tamer.y - 5, 10, 10), _tick_bits_box, _render_bits)
	text_area.draw_string(data.text("STR_BITS"), 0, BITS_ROW)


## The session's hook: boxes 0 and 1 have opened (then box 2).
func boxes_open() -> bool:
	var b := boxes.boxes
	if balance:
		return b[2].state == UIBoxes.STATE_OPEN
	var open := b[0].state == UIBoxes.STATE_OPEN and b[1].state == UIBoxes.STATE_OPEN
	if open and not _opened:
		_opened = true
		# handleBattleEndBox: two steps of the text once the boxes are open.
		if text != "":
			for i in 2:
				_draw_text(true)
	return open


## BTL_isEndBoxTextFinished.
func text_done() -> bool:
	return wait_timer == 0 and line_count == rows_drawn


# --- the end text (battle_hud.c:245-470) -------------------------------------------------------------

## The BTL_append*Text calls in handleBattleEndBox's order, from BattleRewards' texts.
func _build_text() -> void:
	text = ""
	line_count = 0
	cursor = 0
	typing = false
	pen = Vector2i(0, TEXT_ROW)
	v = TEXT_ROW
	rows_shown = 0
	rows_drawn = 0
	wait_timer = WAIT_FRAMES
	for t in rewards.texts:
		var args: Array = t[1]
		match t[0]:
			"drop":
				text += _s("BTL_STR_YELLOW") + _name(data.digimon(int(args[0]))) + _s("BTL_STR_DROPPED") \
						+ _name(data.item(int(args[1]))) + _s("BTL_STR_WHITE_WAIT")
				line_count += 2
			"injured":
				text += _s("BTL_STR_YELLOW") + _name(data.digimon(int(args[0]))) + _s("BTL_STR_WAS_INJURED")
				line_count += 2
			"command":
				var c: Array = COMMAND_TEXTS.get(int(args[0]), ["", 0])
				text += _s(c[0]) + _s("BTL_STR_LISTENS_TO")
				line_count += c[1]
			"mp_bonus":
				text += _s("BTL_STR_MP_CONSUMPTION_BONUS") + _s("BTL_STR_REDUCED_BY") + str(int(args[0])) \
						+ _s("BTL_STR_MP_BONUS_PERCENT")
				line_count += 4
			"learned":
				text += _s("BTL_STR_YELLOW") + _name(battle.move(int(args[0]))) + _s("BTL_STR_LEARNED")
				line_count += 2


func _s(id: String) -> String:
	return data.text(id).replace("\u0000", "")


func _name(record: Dictionary) -> String:
	return data.localize(record.get("name")).strip_edges() if not record.is_empty() else ""


## BTL_drawBattleEndText, US: with `flag`, the codes (#C colour, #W wait, #R new row), then one glyph
## (or one new row) per call; without it nothing. The C stops at '0' (its test of the end): read as
## the buffer's end.
func _draw_text(flag: bool) -> void:
	while flag:
		if cursor >= text.length():
			return
		var c := text[cursor]
		if c == "#" and cursor + 1 < text.length():
			cursor += 1
			match text[cursor]:
				"C":
					cursor += 1
					if cursor < text.length():
						text_area.set_text_color(text[cursor].hex_to_int())
					cursor += 1
				"W", "R":
					if text[cursor] == "W":
						wait_timer = WAIT_FRAMES
					pen = Vector2i(0, pen.y + 0xC)
					cursor += 1
					rows_shown += 1
					rows_drawn += 1
					return
			continue
		pen.x = text_area.draw_string(c, pen.x, pen.y & 0xFF)
		cursor += 1
		return


## BTL_tickBattleEndText (from tickBitBox once the bits are counted and box 2 is open).
func _tick_text(pressed: int) -> void:
	if wait_timer != 0:
		wait_timer -= 1
	if text == "":
		if pressed & (Pad.CONFIRM | Pad.CANCEL):
			wait_timer = 0
		return
	if rows_shown == VISIBLE_ROWS:
		if wait_timer == 0:
			# BTL_scrollBattleEndText
			v += 0xC
			rows_shown -= 1
	else:
		_draw_text(typing)
		if wait_timer != 0:
			typing = false
	if pressed & (Pad.CONFIRM | Pad.CANCEL):
		if wait_timer != 0:
			wait_timer = 0
		else:
			typing = true


var _pressed := 0


func tick(pressed: int) -> void:
	_pressed = pressed
	queue_redraw()


## tickBitBox's text part (the bits themselves are counted by BattleRewards).
func _tick_bits_box(_id: int) -> void:
	if rewards == null or boxes.boxes[2].state != UIBoxes.STATE_OPEN or rewards.bits != 0:
		return
	_tick_text(_pressed)


# --- the boxes' renders ------------------------------------------------------------------------

## renderPostBattleStatsBox's drawing, back to front: the bars, the labels, the divider, the values,
## the gains with their "+".
func _render_stats(canvas: CanvasItem, _id: int) -> void:
	if rewards == null:
		return
	var box: Rect2i = boxes.boxes[0].final
	var bx := box.position.x
	var by := box.position.y
	var values: Array = battle.initial_stats[0]
	for i in range(5, -1, -1):
		var y := by + 20 + i * ROW_STEP
		var colours: Array = BAR_GAINED if has_gain[i] else BAR_PLAIN
		PsxDraw.box(canvas, Rect2i(-22, y - 2, BAR_WIDTH, 2), colours[1])
		PsxDraw.line3(canvas, 0x666666, bx + 117, y - 2, bx + 117, y, bx + 65, y)
		PsxDraw.line3(canvas, 0x020202, bx + 64, y, bx + 64, y - 3, bx + 117, y - 3)
		var cap := 9999 if i < 2 else 999
		PsxDraw.box(canvas, Rect2i(-22, y - 2, int(values[i]) * BAR_WIDTH / cap, 2), colours[0])
	for i in range(5, -1, -1):
		text_area.render_string(canvas, 4, bx + 10, by + 9 + i * ROW_STEP, 48, 12, 0, i * 12, false)
	PsxDraw.line2(canvas, 0x020202, bx + 123, by + 2, bx + 123, by + box.size.y - 3)
	PsxDraw.line2(canvas, 0xFAD990, bx + 122, by + 2, bx + 122, by + box.size.y - 3)
	for i in range(5, -1, -1):
		MenuDraw.number(canvas, text_area, 0, bx + 68, by + 9 + i * ROW_STEP, 4, int(values[i]))
	for i in range(5, -1, -1):
		if rewards.gains[i] == 0:
			continue
		var y := by + 9 + i * ROW_STEP
		MenuDraw.number(canvas, text_area, 5, bx + 142, y, 2, rewards.gains[i])
		BattleHudDraw.rect(canvas, BattleHudDraw.page_896(PLUS_CLUT), 96, BattleHudDraw.row(180), 12, 12, bx + 130, y, 12, 12)


## renderBitBox: the end text and its rule, the label, the bits left. (BIT_TEXT, the text area at
## (156, 240), is empty in the US release.)
func _render_bits(canvas: CanvasItem, _id: int) -> void:
	if rewards == null:
		return
	if text != "":
		text_area.render_string(canvas, 0, TEXT_RECT.position.x, TEXT_RECT.position.y, TEXT_RECT.size.x,
				TEXT_RECT.size.y, 0, v, false)
		PsxDraw.line2(canvas, 0x121212, -85, 51, 85, 51)
		PsxDraw.line2(canvas, 0x8E8E8E, -86, 50, 84, 50)
	text_area.render_string(canvas, 4, -78, 28, 48, 12, 0, BITS_ROW, false)
	MenuDraw.number(canvas, text_area, 2, -18, 28, 5, rewards.bits)


## renderFinalBalance: the label and the money.
func _render_balance(canvas: CanvasItem, _id: int) -> void:
	var box: Rect2i = boxes.boxes[2].final
	text_area.render_string(canvas, 0, box.position.x + 10, box.position.y + 10, 36, 12, 0, BITS_ROW, false)
	MenuDraw.number(canvas, text_area, 0, box.position.x + 58, box.position.y + 10, 6, world.money_held())
