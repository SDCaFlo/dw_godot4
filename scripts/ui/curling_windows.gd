class_name CurlingWindows
extends RefCounted
## The contents of curling's box 0 (specs/curling.md §2.7, §5.3; step C5): the yes / no prompt
## (KAR_tickYesNoPrompt's renderString and renderSelectionCursor, US, kar.c:2075-2077) and the hint
## box (KAR_tickHintBox's renderString and renderUIBox, kar.c:2130-2133). The C draws them from the
## tamer's tick while box 0 is open (state 1); here they are box 0's render callables, which UIBoxes
## calls for an open box. The logic (CurlingMatch) holds the state: `state` says which window it is,
## `hint` its row or page.

## renderString(0, -0x7C, 0x30, 0x52, 0xD, 0, 0xDC, 6, 1) and (0, -0x7C, 0x3D, 0x5C, 0xD, 0x53, 0xDC,
## 6, 1) (US, kar.c:2075-2076): "Start Game" and "Explain Game" from the text area's row 0xDC (the
## one string, drawn at text y 0xDD by KAR_tickYesNoPrompt, kar.c:2044), shadowed.
const PROMPT_X := -0x7C
const PROMPT_ROWS: Array[Array] = [[0x30, 0x52, 0xD, 0], [0x3D, 0x5C, 0xD, 0x53]]
const PROMPT_V := 0xDC
## renderSelectionCursor(finalX + 6, finalY + 7 + (hint - 3) * 13, 0x5E, 0xD, 6) (US, kar.c:2077).
const CURSOR_DX := 6
const CURSOR_DY := 7
const CURSOR_STEP := 13
const CURSOR_W := 0x5E
const CURSOR_H := 0xD
## The prompt's first row (`hint` 3 "Start Game", 4 "Explain Game", kar.c:2050-2066).
const PROMPT_FIRST := 3
## renderString(0, finalX + 4, finalY + 2, 0xFC, 0x34, 0, (hint - 1) * 52, 6, 1) (kar.c:2131-2132):
## box `hint` of the page, 4 lines 13 apart in the text area.
const HINT_DX := 4
const HINT_DY := 2
const HINT_W := 0xFC
const HINT_H := 0x34
const HINT_STEP := 52
## `hint` -1: the hint box is closing (kar.c:2127).
const HINT_CLOSED := -1
## renderString's colour 0 (TEXT_COLORS[0]), shadow 1.
const TEXT_COLOR := 0

var boxes: UIBoxes
var text_area: TextArea
## The match whose box 0 this is (CurlingHost.match).
var curling: CurlingMatch


## Box 0's drawing part: the prompt in match state 1, else the hint box (back to front: the C adds
## its primitives at the head of layer 6, so the last added is drawn first).
func render(canvas: CanvasItem, id: int) -> void:
	if curling == null or text_area == null:
		return
	var final := boxes.boxes[id].final
	if curling.state == CurlingMatch.ST_PROMPT:
		PsxDraw.selection_cursor(canvas, final.position.x + CURSOR_DX,
				final.position.y + CURSOR_DY + (curling.hint - PROMPT_FIRST) * CURSOR_STEP, CURSOR_W, CURSOR_H)
		for k in range(PROMPT_ROWS.size() - 1, -1, -1):
			var r: Array = PROMPT_ROWS[k]
			text_area.render_string(canvas, TEXT_COLOR, PROMPT_X, r[0], r[1], r[2], r[3], PROMPT_V, true)
	elif curling.hint != HINT_CLOSED:
		text_area.render_string(canvas, TEXT_COLOR, final.position.x + HINT_DX, final.position.y + HINT_DY, HINT_W, HINT_H,
				0, (curling.hint - 1) * HINT_STEP, true)


## Box 0's counting part: the hint box's renderUIBox(0) (kar.c:2133), the "next" arrow from
## TEXTBOX_OPEN_TIMER (script_textbox.c:1005).
func on_render(id: int) -> void:
	if curling == null or curling.state == CurlingMatch.ST_PROMPT or curling.hint == HINT_CLOSED:
		return
	boxes.show_next_arrow(id, boxes.textbox_open_timer)
