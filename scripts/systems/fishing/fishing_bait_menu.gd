class_name FishingBaitMenu
extends RefCounted
## Fishing's bait menu, logic (FISH_openBaitMenu / _tickBaitMenu / _closeBaitMenu /
## _isBaitMenuVisible, fish.c:1119-1404; specs/fishing.md §2.9): the inventory's food items, 2 per
## row, in UI box 3. The view (step F5) draws the box, the icons, names and counts; `tick` is the
## box's tick function.

## The box (fish.c:1363-1383): 9 rows shown; it grows from a 10 × 10 square at the tamer's screen
## point to (-0x98, -0x68, 0x132, 0xB6), colour 0, features 2 (6 with a scroll bar).
const BOX_ID := 3
const VISIBLE_ROWS := 9
const BOX_RECT := Rect2i(-0x98, -0x68, 0x132, 0xB6)
const COLUMNS := 2
const SLOTS := 30
const EMPTY := 0xFF
## A direction held 11 frames with the pad unchanged repeats every frame (MAIN_D_801351D8 >= 0xB).
const REPEAT_AFTER := 0xB
## playSound(0, 2) on every move, choice and cancel.
const SOUND := Vector2i(0, 2)

## menu.shown.
var shown := false
## menu.boxId: -1 until opened (FISH_initBaitMenu).
var box_id := -1
var total_rows := 0
var column := 0
var cursor_row := 0
var row_offset := 0
## menu.lastRow: the row the view redraws into the text area after a scroll (-1 none).
var last_row := -1
var visible_rows := VISIBLE_ROWS
## menu.items[30]: inventory slots, -1 empty.
var items: Array[int] = []
## menu.selectedItem: the chosen slot, -1 cancelled.
var selected := -1
## MAIN_D_801351D8: frames the pad stayed the same (counted while the box ticks).
var unchanged_frames := 0
## The box's opening / closing animation (UI_BOX_DATA state 2 or 3) also counts as visible. The
## view sets it from UIBoxes; the logic alone has no animation.
var box_animating := Callable()
var play_sound := Callable()
## The tamer's screen point (getEntityScreenPos(ENTITY_TABLE[0], 1)), for the box's start rect.
var start_rect := Rect2i()
signal opened
signal closed


## FISH_openBaitMenu (fish.c:1318): the food slots of `inventory` (30 item types, 0xFF empty);
## false when there are none (the box doesn't open).
func open(inventory: Array, is_food: Callable, tamer_screen: Vector2i) -> bool:
	last_row = -1
	column = 0
	cursor_row = 0
	row_offset = 0
	visible_rows = VISIBLE_ROWS
	items = []
	for i in SLOTS:
		var t := int(inventory[i]) if i < inventory.size() else EMPTY
		if t == EMPTY or not is_food.call(t):
			continue
		items.append(i)
	total_rows = (items.size() + 1) / 2
	while items.size() < SLOTS:
		items.append(-1)
	if total_rows <= 0:
		return false
	start_rect = Rect2i(tamer_screen.x - 5, tamer_screen.y - 5, 10, 10)
	box_id = BOX_ID
	shown = true
	opened.emit()
	return true


## The features of the box: 6 (half fill + scroll bar) when the rows don't fit, else 2.
func features() -> int:
	return 6 if total_rows > visible_rows else 2


## FISH_tickBaitMenu (fish.c:1154).
func tick(pad: Pad) -> void:
	if pad.polled == pad.polled_previous:
		unchanged_frames += 1
	else:
		unchanged_frames = 0
	if not shown:
		return
	last_row = -1
	var pressed := pad.polled & ~pad.polled_previous
	var repeat := unchanged_frames >= REPEAT_AFTER
	if pressed & Pad.UP or (repeat and pad.polled & Pad.UP):
		_sound()
		cursor_row = maxi(cursor_row - 1, 0)
		if cursor_row < row_offset:
			row_offset = cursor_row
			last_row = row_offset
	if pressed & Pad.DOWN or (repeat and pad.polled & Pad.DOWN):
		_sound()
		cursor_row += 1
		if cursor_row >= total_rows:
			cursor_row = total_rows - 1
		if cursor_row >= row_offset + visible_rows:
			row_offset = cursor_row - visible_rows + 1
			last_row = row_offset + visible_rows - 1
	if pressed & Pad.LEFT or (repeat and pad.polled & Pad.LEFT):
		_sound()
		column -= 1
		if column < 0:
			column = 1
	if pressed & Pad.RIGHT or (repeat and pad.polled & Pad.RIGHT):
		_sound()
		column += 1
		if column >= COLUMNS:
			column = 0
	if pressed & Pad.CONFIRM:
		_sound()
		var slot := items[column + cursor_row * COLUMNS]
		if slot != -1:
			selected = slot
			close()
	if pressed & Pad.CANCEL:
		_sound()
		selected = -1
		close()


## FISH_closeBaitMenu (fish.c:1144): back to its start rect.
func close() -> void:
	if shown:
		shown = false
		closed.emit()


## FISH_isBaitMenuVisible (fish.c:1119).
func is_visible() -> bool:
	if box_id <= 0:
		return false
	if box_animating.is_valid() and box_animating.call():
		return true
	return shown


func _sound() -> void:
	if play_sound.is_valid():
		play_sound.call(SOUND.x, SOUND.y)
