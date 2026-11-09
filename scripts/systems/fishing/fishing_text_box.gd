class_name FishingTextBox
extends RefCounted
## Fishing's message box, logic (FISH_showTextBox / _tickTextBox / _closeTextBox / _isTextBoxVisible,
## fish.c:1416-1557; specs/fishing.md §2.9): UI box 2, up to 4 lines. The view (step F5) draws the
## lines into the text area and the box on UIBoxes; `tick` is the box's tick function.

## createStaticUIBox(2, 0, 2, (-0x82, 0x2A, 0x106, 0x3B)) (fish.c:1532-1537).
const BOX_ID := 2
const BOX_RECT := Rect2i(-0x82, 0x2A, 0x106, 0x3B)
## ✕ closes it after 10 frames, △ at once; framesOpen stops at 0x64 (fish.c:1462-1471).
const CONFIRM_AFTER := 10
const FRAMES_MAX := 0x64
## playSound(0, 3) when it closes.
const CLOSE_SOUND := Vector2i(0, 3)
const LINES := 4

## box.shown.
var shown := false
## box.boxId: -1 until the first message (FISH_initTextBox).
var box_id := -1
## view.lines: the strings, "" for an empty line (NULL in the C).
var lines: Array[String] = ["", "", "", ""]
## view.scrollTo: where the camera pans while the box shows.
var scroll_to := Vector3i.ZERO
## view.isScrolling: set by the box's tick, taken by the rod's (FISH_scrollViewToTarget).
var is_scrolling := false
## view.framesOpen.
var frames_open := 0
## TEXTBOX_OPEN_TIMER: the "next" arrow's frame.
var open_timer := 0
## Emitted by show and close, for the view (draw the lines / create or remove box 2).
signal opened
signal closed
## playSound.
var play_sound := Callable()


## FISH_showTextBox (fish.c:1502): closes the last box, clears the pad for this frame, shows the
## lines in box 2.
func show(new_lines: Array, target: Vector3i, pad: Pad) -> void:
	close()
	if pad != null:
		pad.polled = 0
	scroll_to = target
	for i in LINES:
		lines[i] = str(new_lines[i]) if i < new_lines.size() and new_lines[i] != null else ""
	frames_open = 0
	box_id = BOX_ID
	shown = true
	open_timer = 0
	opened.emit()


## FISH_tickTextBox (fish.c:1452): the box's tick.
func tick(pad: Pad) -> void:
	if not shown:
		return
	is_scrolling = true
	var pressed := pad.polled & ~pad.polled_previous
	if (frames_open >= CONFIRM_AFTER and pressed & Pad.CONFIRM) or pressed & Pad.CANCEL:
		pad.polled = 0
		close()
		if play_sound.is_valid():
			play_sound.call(CLOSE_SOUND.x, CLOSE_SOUND.y)
	if frames_open < FRAMES_MAX:
		frames_open += 1
	open_timer = (open_timer + 1) & 0xFF


## FISH_closeTextBox (fish.c:1441).
func close() -> void:
	if shown:
		closed.emit()
	shown = false


## FISH_shutdownTextBox (fish.c:1551).
func shutdown() -> void:
	close()
	box_id = -1


## FISH_isTextBoxVisible (fish.c:1416): a static box doesn't animate, so it is visible while shown.
func is_visible() -> bool:
	return box_id > 0 and shown
