# Windows and text in the HUD

How to put a window or text on screen the way the original does. The pieces are in `scripts/ui/`; what they reproduce is in `specs/text.md`.

## The pieces

| Piece | What it is | Original |
|---|---|---|
| `TextArea` | the 256 × 256 area strings are drawn into, then shown in rectangles | text area in VRAM, `font.c` |
| `PsxFont` | the game's font of a language (`GameData.font`) | `GLYPH_DATA`, `drawGlyph` |
| `UIBoxes` | six window slots: frame, fill, open / close animation, scroll bar, "next" arrow | `UI_BOX_DATA[6]`, `ui.c` |
| `MessageBox` | a text window on one slot: rows of the text area, the arrow, open from / close to a point | the tamer's award box |
| `PsxDraw` | lines, boxes, sprites, the selection cursor | `drawLine2P`, `GsSortBoxFill`, `renderSelectionCursor` |
| `TextBoxes` | the event scripts' text boxes and the dialogue box: pages, the arrow, choices | `TEXTBOX_DATA`, `script_textbox.c` |
| `GameLoop.pad` (`Pad`) | the pad read once per game frame: `is_held`, `is_changed`, `is_key_down` | `POLLED_INPUT`, `CHANGED_INPUT`, `isKeyDown` |

In the field, `field.gd` makes one `TextArea`, one `UIBoxes` and one `TextBoxes` (`_text_area`, `_boxes`, `_textboxes`) and hands them to the systems that show text.

**Buttons.** Use the same reading as the original code you port:
- `pad.is_held(Pad.CONFIRM)` is true every frame the button is down (`POLLED_INPUT`);
- `pad.is_changed(Pad.DOWN)` is true on the frame it went down, plus the d-pad repeat (`CHANGED_INPUT`);
- `pad.is_key_down(Pad.CONFIRM)` is true once per press, and again only after a release (`isKeyDown`). `pad.set_repeat_mask(Pad.UP | Pad.DOWN)` makes held keys repeat, as menus do.

The buttons are `Pad.CONFIRM` (✕), `Pad.CANCEL` (△), `Pad.UP`, `Pad.DOWN`, `Pad.LEFT` and `Pad.RIGHT`.

**Coordinates.** The screen is 320 × 240, and coordinates are relative to its centre (160, 120), as in the C: the message box's rect (−130, 42, 262, 59) is the strip near the bottom. Text-area coordinates (u, v, rows) are 0–255.

**Frames.** Everything advances once per game frame (`GameLoop.frame`, 20 Hz), never per Godot frame.

## The upscaling filter

The PSX bitmaps are drawn at the window's resolution through `PsxUiFilter` (ISSUES.md D-3): a canvas shader that upscales each texel like an emulator's 2D filter (Scale4x), switched globally (`PsxUiFilter.set_enabled`, the global shader parameter `psx_ui_filter`). A new node that draws PSX textures sets `material = PsxUiFilter.material()` in `_ready` (`PsxUiFilter.material("add")` for its additive child, instead of a `CanvasItemMaterial` with `BLEND_MODE_ADD`), as `UIBoxes`, `ClockHud`, `StatusBars`, `ConditionBubbles` and `MapName` do. Drawing on `UIBoxes` (message boxes, `TextArea`) is filtered already.

## A new message box

Draw the text into rows of the text area that nobody else uses at that moment, then open a `MessageBox`:

```gdscript
var box := MessageBox.new(boxes, text_area)
box.box_id = 2                                  # a free slot (0 = dialogue, 1 = the tamer's box)
box.rect = Rect2i(-100, -60, 200, 33)           # where it ends up
box.strings = [[0, -95, -57, 180, 24, 0, 200, false]]   # renderString: colour, x, y, w, h, u, v, shadow
text_area.clear(Rect2i(0, 200, 256, 24))
text_area.set_text_color(1)
text_area.draw_string("Hello", 0, 200)
text_area.draw_string("Second line", 0, 212)    # rows are 12 px apart
box.open(Rect2i(-5, -5, 10, 10))                # grows from a 10 x 10 point (e.g. tamer.screen_rect())
```

Close it on the confirm button, polled once per game frame:

```gdscript
func tick() -> void:                            # connected to GameLoop.frame
	if box.is_shown() and GameLoop.pad.is_key_down(Pad.CONFIRM):
		box.close(Rect2i(-5, -5, 10, 10))
```

`box.arrow = false` hides the "next" arrow. `features` and `color` choose the fill (`UIBoxes.FEATURE_HALF_FILL`, colour 0 black or 1 blue-grey) and a title rule (`FEATURE_TITLE`).

## A window with your own contents (menus, shops)

Any window is a slot with a `render` callable. It draws on the canvas it gets, in screen coordinates, back to front, in front of the frame:

```gdscript
var rows := ["Meat     50", "Fish    120", "Disk    500"]
var current := 0

func open_shop() -> void:
	text_area.clear(Rect2i(0, 160, 256, 36))
	for i in rows.size():
		text_area.draw_string(rows[i], 0, 160 + 12 * i)
	var b: UIBoxes.Box = boxes.boxes[3]
	b.total_rows = rows.size()                  # scroll bar (FEATURE_SCROLL_BAR)
	b.visible_rows = 3
	boxes.create_static(3, 1, UIBoxes.FEATURE_TITLE | UIBoxes.FEATURE_SCROLL_BAR,
			Rect2i(-120, -80, 240, 70), _shop_tick, _shop_render)

func _shop_tick(_id: int) -> void:              # once per game frame while the box is open
	var pad: Pad = GameLoop.pad
	if pad.is_key_down(Pad.DOWN):
		current = (current + 1) % rows.size()
	elif pad.is_key_down(Pad.UP):
		current = (current - 1 + rows.size()) % rows.size()
	elif pad.is_key_down(Pad.CANCEL):
		boxes.remove_static(3)

func _shop_render(canvas: CanvasItem, _id: int) -> void:
	PsxDraw.selection_cursor(canvas, -116, -62 + 13 * current - 2, 200, 13)
	for i in rows.size():
		text_area.render_string(canvas, 0, -112, -62 + 13 * i, 200, 12, 0, 160 + 12 * i, true)
```

- `create_animated(id, color, features, rect, from, tick, render, on_render)` opens with the outline animation, and `remove_animated(id, to)` closes with it. A static box opens and closes at once.
- `on_render(id)` runs once per game frame while the original would call the box's render function. Counters go there, such as `boxes.textbox_open_timer` and `boxes.show_next_arrow(id, timer)`. `render` may be called more often (it is Godot's `_draw`), so it must not change state.
- Wait for `boxes.is_available(id)` before opening an animated box on a slot that may still be closing. `boxes.closed` tells you when a slot is free.
- `boxes.sound` emits the original's sound calls (0 open, 1 close).

## Script dialogue

Event-script text goes through `TextBoxes` (`specs/text.md` §2.6–2.7), not `MessageBox`: it pages, waits for ✕, offers choices and fills in names and values. The interpreter drives it through a `ScriptContext` (`scripts/script/script_context.gd`), which holds the script bytes, the pointer, `active_instruction` and the dialogue owner:

```gdscript
textboxes.set_dialogue_owner(owner)             # SET_DIALOG_OWNER: sets box 0 up for the speaker
ctx.pointer = offset_of_the_text
textboxes.show_textbox(0, ctx.dialogue_owner)   # SHOW_TEXTBOX: waits while ctx.active_instruction != 0
textboxes.script_show_selection()               # SET_SELECTION: ctx.pointer jumps to the chosen target
textboxes.tick_textbox_handling()               # once per game frame, before the UI boxes' frame
```

The interpreter (`scripts/script/script_interpreter.gd`, `specs/script.md`) does all of this for the event scripts; `D` in the field runs the current map's script sections through it (`scripts/debug/script_debug.gd`).

## Text

- `text_area.draw_string(text, x, y)` draws a Godot string in the current language's font. US ASCII becomes the full-width glyphs as in the original (`.` → 。's glyph, `'` → 「's). A character the font doesn't have draws the fallback glyph (× in US).
- `set_text_color(index)` picks one of the 16 font colours (`GameData.font_clut()`). `render_string`'s colour is a tint on top (`GameData.text_colors()`, 0 = none).
- The text area is shared: the tamer's box uses rows 120–155 and the dialogue box rows 0–95. Pick free rows for a new window.
- `GameData.set_language()` switches the font of new text (`text_area.set_language`, connected in `field.gd`).
