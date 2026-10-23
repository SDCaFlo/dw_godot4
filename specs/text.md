# Text renderer (port spec)

Status (2026-10-23):
- **done:** the font, the text area, `renderString`, the UI boxes, the message box. The care's "<name> is sick" uses them.
- **next:** the dialogue box (§2.6–2.7).

How the original puts text on screen:
- the font (glyph bitmaps in the C code);
- the text area in VRAM that strings are drawn into;
- the rectangles copied from it to the screen;
- the UI boxes (window frames);
- the message box (awards, "<name> is sick");
- the dialogue box of the event scripts: lines, pages, the "next" arrow, choices.

The event-script interpreter that feeds the dialogue box is the next step (`PLANS.md`); this step ports what it calls. String data: `data_porter/specs/text.md` (menus, battle text), `asset_porter/specs/scn.md` (script text).

All `file:line` references are in `external-resources/dw_decomp/src/main/`; the US version unless noted.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `GLYPH_DATA`, `CHAR_TO_GLYPH_TABLE` (`font.c:41–1488`, per release) | the font: 11 rows × 12 px per glyph, the Shift-JIS code of each | data porter `font/*` tables (§4), `PsxFont` |
| `FONT_CLUT` (`font.c:1491`), `TEXT_COLORS` (`utils.c:45`) | 16 font colours; the tint per `renderString` colour | `font/clut`, `font/text_colors` |
| `convertAsciiToJis`, `CHAR_MAPPING_*` (`sjis.c:11–99`) | ASCII → full-width Shift-JIS (US strings are ASCII) | `font/ascii`, `PsxFont.encode` |
| `initializeFontCLUT`, `clearTextArea`, `clearTextSubArea`, `setTextColor`, `drawGlyph`, `drawString` (`font.c:1503–1763`) | drawing into the text area | `TextArea` (`clear_all`, `clear`, `set_text_color`, `draw_glyph`, `draw_string`) |
| `renderString` (`utils2.c:247`), `initStringFT4` (`utils.c:206`) | a rectangle of the text area on screen, tinted, with a shadow | `TextArea.render_string` |
| `drawLine2P`, `drawLine3P` (`line.c`), `GsSortBoxFill`, `renderSelectionCursor` (`utils2.c:232`) | flat lines and boxes | `PsxDraw` |
| `createStaticUIBox`, `createAnimatedUIBox`, `renderUIBoxStatic`, `renderUIBoxAnimated`, `renderUIBoxAnim`, `renderUIBoxBorder`, `removeStaticUIBox`, `removeAnimatedUIBox`, `tickUIBox`, `isUIBoxAvailable` (`ui.c`, the last asm only) | window frames, the open / close animation | `UIBoxes` |
| `renderUIBox` (`script_textbox.c:996`) | the blinking "next" arrow | `UIBoxes.show_next_arrow` |
| `tamerTickAwardSomething`, `renderAwardSomethingTextbox`, `tamerSetState` (`tamer.c:1751`, `:1351`, `:1359`) | the message box (awards, sickness) | `Tamer.tick_award_something` (state 20) with a `MessageBox` |
| `getEntityScreenPos` (`utils.c:176`) | an entity's bone on screen | `Tamer.screen_position` |
| `partnerTickIdle` (`partner.c:733`) | the partner waits (state 11) | `Partner.tick_idle` |
| `drawString2`, `showTextbox`, `registerTextbox`, `createTextbox`, `tickTextboxHandling`, `drawTextboxStrings`, `flipIdleTextboxPage`, `advanceTextbox`, `tickConfirmDialogue`, `tickSelectionDialogue`, `scriptShowSelection`, `setupDialogueBox`, `scriptSetTextboxSize`, `renderScriptDialogueBox` (`script_textbox.c`) | the dialogue box | `DialogueBox` |

## 2. Original behaviour

### 2.1 The font (`font.c`)

- **Glyphs per release:** US 79, JP 992 (kana and kanji included), EU 188.
  - Each glyph has 11 rows of a `uint16_t`. Bits 15…4 are pixels 0…11 from the left; **a 0 bit is ink**. Bits 3…0 are unused.
  - US glyphs also store an advance width (`GlyphData.width`, `font.c:37`). EU widths are 8 or 12 px by code range (`font.c:1611–1618`). JP glyphs are a fixed 12 px.
- **Glyph lookup** (`drawGlyph`, `:1603–1609`):
  - the code is compared with `CHAR_TO_GLYPH_TABLE` (Shift-JIS codes, byte-swapped from the string);
  - the last entry is overwritten with the code first, as a sentinel.
  - **Quirk kept:** an unknown code draws the last glyph's pixels. In US that is ×, `0x817E`; in JP / EU a crossed box (the entry's code is 0).
  - The US text has a few characters without a glyph, drawn as ×: `%` in "…reduced by N%!", `&` in "Dark Network & Concert Crush", and the kana of leftover JP strings (`data_porter/specs/font.md` §5).
- **US characters** (all full-width Shift-JIS):
  - A–Z, a–z, 0–9 (`0x8260`…, `0x8281`…, `0x824F`…) and the space `0x8140`;
  - punctuation: 。`0x8142` (drawn as a period), ？ `0x8148`, ！ `0x8149`, 」 `0x8176`, 「 `0x8175`, ， `0x8143`, ＼ `0x815F`, ： `0x8146`, ； `0x8147`, ＋ `0x817B`, － `0x817C`, ＝ `0x8181`;
  - the button symbols ○ `0x819B`, □ `0x81A0`, △ `0x81A2`, × `0x817E`.
  - **ASCII bytes** (`drawString`, `:1738–1749`) go through `convertAsciiToJis` (`sjis.c:63`); `.` becomes `0x8142` and `'` becomes `0x8175`.
  - **Two-byte codes** (high bit set) are Shift-JIS.
- **Space:** JP / EU skip the full-width space `0x8140` (EU advances 8). US draws it as a glyph (entry 62 is `0x8140`).
- **Clipping:** a glyph is drawn only if x and y are below 244 (`TEXT_DRAW_LIMIT`, area 256 − cell 12).
- **Quirk kept, cell position:** `LoadImage` gets x / 4 in 16-bit VRAM words (`font.c:1696`), so a glyph lands on the multiple of 4 at or left of x. Narrow advances (5 px punctuation, 6 px `f`) are rounded down that way. `clearTextSubArea` cuts x and the width to words too.

### 2.2 The text area (`font.c:1503–1541`)

- **The area:** 256 × 256 4-bit pixels at VRAM (704, 256) (`TEXT_VRAM_X/Y`).
- **Pixels:** each pixel is a colour index into `FONT_CLUT` (16 colours at VRAM 208, 488).
- **Drawing:**
  - `setTextColor(c)` sets the index `c` (0–15) that ink pixels get;
  - `drawGlyph` writes a 12 × 11 cell at (x, y); non-ink pixels become 0, i.e. transparent;
  - `clearTextArea` / `clearTextSubArea` set a rectangle to 0;
  - lines are 12 px apart.
- **`FONT_CLUT`:** index 0 is transparent; the other 15 colours are 15-bit BGR.
- **Usage:** code that shows text first draws strings into rows of the area, then puts rectangles of it on screen:
  - the message box uses rows 120–155 (`0x78`, `0x84`, `0x90`);
  - the dialogue box uses rows 0–95;
  - menus use their own rows.

### 2.3 On screen (`renderString`, `utils2.c:247`)

`renderString(color, x, y, w, h, u, v, layer, shadow)` draws the text-area rectangle (u, v, w, h) at screen (x, y). Screen coordinates are relative to the screen centre, like the clock.

- **Texture:** page (704, 256), 4-bit, palette `FONT_CLUT` (`initStringFT4`).
- **Tint:** `TEXT_COLORS[color]`, 0x80 = 1.0. Colour 0 is (0x80, 0x80, 0x80), so the font colours stay as they are.
- **Shadow:** with `shadow`, a black copy 1 px down-right is drawn behind it.

### 2.4 UI boxes (`ui.c`)

Six boxes (`UI_BOX_DATA[6]`). Box `i` draws on ordering-table layer `6 − i`.

- **States:** 0 closed, 1 open, 2 opening, 3 closing, 4 used by menus.
- **Each frame:** the object pass runs the box's tick function while it is open (state 1 or 4, `tickUIBox`), then its render function (`renderUIBoxAnimated` or `renderUIBoxStatic`).
- **Static box** (`createStaticUIBox`): open at once.
- **Animated box** (`createAnimatedUIBox`):
  - **Opening:** grows from a start rect (e.g. a 10 × 10 square at the speaker on screen) to the final rect as an outline in `0x808080` (`renderUIBoxAnim`: frame `f` is `start + f × (final − start) / 4`, truncated). It draws frames 0, 1, 2, 3, 4 (**five** frames: `frame++` until it is above 4), then it is open.
  - **Sounds:** sound 0 when it is created; sound 1 on the first closing frame.
  - **Closing** (`removeAnimatedUIBox`): shrinks back to its start rect (or a new target), drawing frames 4 … 0, then the slot is freed (`removeStaticUIBox`). Only the outline is drawn, not the contents.
  - The frame counter isn't reset by `createAnimatedUIBox`; it is 0 in a free slot.
- **`isUIBoxAvailable(id)`** (asm only, `game_menu.s`): true when the box is open (state 1) or its frame counter is 0 (free, or a static box); false while it animates.
- **Open box** (`renderUIBoxStatic`):
  - **Contents first:** the box's own render function draws its contents.
  - **Border** (`renderUIBoxBorder`):
    - corners: four 4 × 4 corner sprites from `system_w` (page (320, 0); u `0x78` / `0x7C`, v `0x90` / `0x94`, i.e. image pixel (u, v − 128); palette `(0x60, 0x1EC)` = CLUT row 492 = `p4`);
    - edges: three lines on each edge. **Colour words have red in the low byte** (`line.c:51`), so black `0x020202`, light blue `0xFAD990` = RGB (0x90, 0xD9, 0xFA), blue `0xC59F4A` = RGB (0x4A, 0x9F, 0xC5).
  - **Inner lines:** black at x + 3 and x + w − 4.
  - **Features** (bits):
    - 1: a title rule at y + 13–15;
    - 4: a scroll bar (track `(0x35, 0x4B, 0x5C)`, bar `(0x5B, 0x70, 0x80)` sized `visibleRows / totalRows`, placed by `rowOffset`);
    - 2: a semi-transparent fill.
  - **Fill:** `UI_BOX_COLORS[color]`, colour 0 black or 1 (0x2D, 0x38, 0x40), at (x + 4, y + 3, w − 8, h − 3).
  - **Draw order:** all of a box is on one ordering-table layer, and the layer draws its primitives in reverse order of adding. The fill (added last) is drawn first, then the scroll bar, the title rule, the inner lines, the border, the corners, and the contents (added first) on top.
- **"Next" arrow** (`renderUIBox`):
  - **Sprite:** 16 × 12 from `system_w` (u `0x4C + 16 × (TEXTBOX_OPEN_TIMER / 4 % 3)`, v `0xB7`).
    - `GetTPage(0, 1, 320, 128)` gives page (320, 0), since only bit 8 of y counts, so the pixel is (u, `0xB7` − 128).
    - Palette `(96, 500)` = `p12`.
    - Semi-transparency mode 1 (additive).
  - **Place:** at (box.x + 239, box.y + 43).
  - **Animation:** it cycles 3 frames every 4 frames.

### 2.5 The message box (tamer state 20, `tamerTickAwardSomething`)

Used for medals, tamer-level changes and "<name> is sick" (`tickSicknessMechanics`, `specs/care.md` §2.7).

- **Before:** the caller clears the text area and draws its lines at (0, 120), (0, 132), (0, 144) (`drawString`), then calls `tamerSetState(20)` (state 20, sub-state 0).
  - The sickness message (`partner_impl.c:1898`) draws the name in colour 10 at (0, 120), and " is sick" in colour 1 at `strlen(name) / 2 × GLYPH_WIDTH`.
  - The name is full-width Shift-JIS (the naming screen writes 2-byte codes), so that is 12 px per character. **Quirk kept:** US glyphs are narrower, so a gap is left after the name (e.g. the text starts 7 × 12 = 84 px after the start of "Digimon", which is drawn 52 px wide).
  - `item.c:3058` (sickness from an item) has a US branch that draws the joined string instead, with no gap.
- **Sub-state 0:**
  - game time stops, the tamer idles, the partner waits (state 11), the camera stops following;
  - medal / level texts are drawn here when pending.
- **Sub-state 4:** when UI box 1 is free, an animated box opens:
  - final rect (−130, 42, 262, 59);
  - start rect: a 10 × 10 square at the tamer's screen position;
  - features 2, colour 0;
  - sound 7.
- **The box draws:**
  - `renderString(0, −125, 45, 240, 36, 0, 120, 5, 0)`: the three rows of the text area;
  - the "next" arrow;
  - `TEXTBOX_OPEN_TIMER + 1` per frame.
- **Start rect:** `getEntityScreenPos(tamer, 1)`: the tamer's bone 1 through the camera, relative to the screen centre; the box grows from (x − 5, y − 5, 10, 10).
- **Sub-state 5:** the confirm button (✕ on the US pad, `POLLED_INPUT`: newly pressed this frame) closes the box back to the tamer, frees the tamer, puts the partner back in state 1, the camera follows again, and game time runs. This can happen while the box is still opening.

### 2.6 Dialogue text (`showTextbox`, `drawString2`; `script_textbox.c:1054`, `:644`)

**`showTextbox`** copies a script text into line buffers (`TEXTBOX_LINES_PTR`, one per text-area row):
- **Speaker line:** with a speaker it starts with a name line, coloured:
  - tamer (`0xFD`): colour 6;
  - partner (`0xFC`): 10;
  - special speakers (≥ `0xC8`): 5;
  - NPCs: 7.
- **Values are expanded:** numbers, names (tamer, partner, Digimon, technique, item, BGM, tournament), money, merit and so on (codes `04`–`15`, `asset_porter/specs/scn.md` "Text").
- **Lines end** at `0D`; `0D 00` ends the page.
- **Returned:** the widest line in characters, for the choice cursor.

**`drawString2`** draws one line buffer into the text area:

| Byte(s) | US effect |
|---|---|
| `00` | end of text |
| `0D` | end of line |
| `01 c` | text colour c |
| `02 x` | skipped |
| `03 a b c` | skipped |
| `0C _` | clear to the next multiple of 8 cells (96 px) |
| `0E _` | clear to the next multiple of 11 cells (132 px) |
| `0F _` | 6 px blank |
| `16 _` | clear 105 px from x − 6, then x = 105 |
| `17 _` / `18 _` / `19 _` / `1A _` / `1B _` / `1C _` | clear and jump to x = 105 / 96 / 156 / 180 / 160 / 100 |
| ASCII byte | `convertAsciiToJis`, then the glyph |
| other byte pair | a Shift-JIS glyph |

- **The full-width space** (`0x8140`) only clears its 12-px cell.
- **US advance:** `pos +=` the glyph's width, or 12 when `DRAW_STRING2_IS_FIXED_WIDTH` is set.
- **Quirk kept:** for the full-width space the US code doesn't set the advance, so it moves by the previous glyph's width (`adv` is not reassigned, `script_textbox.c:780–804`).

### 2.7 The dialogue box (`setupDialogueBox`, `tickTextboxHandling`, `renderScriptDialogueBox`)

- **Box:** `setupDialogueBox(owner)`, box 0:
  - rect (−130, 42, 262, 59), flags `0x21` (+ `0x80` animated, growing from the speaker's screen position);
  - `registerTextbox(0, row 0, 4 rows, double-buffered, mode 0)`: two pages of 4 rows in the text area (rows 0–47 and 48–95).
- **Each frame** (`tickTextboxHandling`): when a box has a new text, the back page is cleared and its lines are drawn into it, two lines per frame (`drawTextboxStrings`). Then the box opens if it isn't open.
- **Showing** (`renderScriptDialogueBox`): four `renderString(0, x + 5, y + 4 + 13 i, 252, 12, 0, page row + 12 i, 6, shadow)` lines. A choice draws its cursor; the "next" arrow shows while the box waits for the button.
- **Waiting** (`tickConfirmDialogue`):
  - the confirm button flips to the next page or ends the text (sound 3);
  - mode 1 closes without a button;
  - mode 2 closes after `AUTOCLOSE_FRAMES`.
- **Choices** (`tickSelectionDialogue`, `scriptShowSelection`):
  - up / down move the cursor, wrapping (sound 2);
  - confirm picks (sound 3);
  - cancel picks the last option, or leaves the choice (sound 4) unless trigger `0x31` is set (then sound 11).
  - The cursor is `renderSelectionCursor` at (x − 1, y + offset + 13 × current − 2), as wide as the widest choice × 12 + 2 (at most 240).
- **Custom size** (`scriptSetTextboxSize`): `cols × 12 + 10` by `rows × 13 + 7`, centred. Cancel shows the whole text at once.

## 3. Godot design

Everything is in `scripts/ui/`, built to be reused by every window that comes later (dialogue, menus, shops). How to make a new window: `docs/ui.md`.

- **`PsxFont`** (`psx_font.gd`): the glyph table of a language from `GameData` (§4).
  - **Language → release:** `en_us` → US, `ja` → JP (jp_rev1), `en_eu` → EU.
  - **`glyph_index(code)`:** `drawGlyph`'s search, with the last glyph as the fallback.
  - **`advance(code)`:** what `drawGlyph` returns; `glyph_width` is `GLYPH_WIDTH`.
  - **`encode(text, draw_string)`:** a Godot string to the codes `drawGlyph` gets. ASCII goes through `font/ascii` (with US `drawString`'s overrides, or without them for `drawString2`); other characters through the glyphs' `char`. A character the font lacks gets 0, which draws the fallback glyph.
- **`TextArea`** (`text_area.gd`): the 256 × 256 area as colour indices (`pixels`), and a texture with the font palette built from the changed rows.
  - **Methods:** `clear_all`, `clear(rect)`, `set_text_color`, `draw_glyph(code, x, y)`, `draw_string(text, x, y)`, `draw_codes`, `set_language`.
  - **`render_string(canvas, color, x, y, w, h, u, v, shadow)`:** any `CanvasItem` draws a rectangle of the area, tinted by `TEXT_COLORS`, with the shadow.
  - **One area:** `field.gd` makes one and hands it to its users (the care, the tamer's message box), as the original has one; callers own rows.
- **`PsxDraw`** (`psx_draw.gd`): `line2` / `line3` (colour words as the C writes them), `box` (optionally half transparent), `sprite`, in screen coordinates relative to the centre.
- **`UIBoxes`** (`ui_boxes.gd`): a HUD `Control` with the six `UI_BOX_DATA` slots and the C API:
  - `create_static`, `create_animated`, `remove_static`, `remove_animated`, `is_available`;
  - `step()` once per game frame: the tick pass, then the render pass;
  - `_draw` draws what the step decided, box 0 behind box 5;
  - `draw_box` / `draw_border` draw a frame on any canvas;
  - signals `sound(id)` and `closed(id)`; `textbox_open_timer` is `TEXTBOX_OPEN_TIMER`.
  - **A box's contents are callables.** `tick(id)` is the C tick function. The C render function both draws and counts, so in Godot it is split: `render(canvas, id)` draws in `_draw`, and `on_render(id)` runs once per game frame where the C calls the render function. `show_next_arrow(id, timer)` is called from `on_render`.
- **`MessageBox`** (`message_box.gd`): a reusable text window on a box slot. It has `rect`, `color`, `features`, `strings` (`renderString` arguments), `arrow`, and `open(from)` / `close(to)` / `is_available()` / `is_shown()`. Its defaults are the tamer's award box.
- **Tamer state 20:** `Tamer.tick_award_something()` reproduces `tamerTickAwardSomething` with a `MessageBox`. `Tamer.tick()` runs on `GameLoop.frame` before the partner. The medal and level texts (sub-states 1–3) come with those systems.
- **Pad:** `GameLoop.pad_pressed(action)` is `POLLED_INPUT`: true in the one game frame after the button went down. Confirm = ✕ (`ui_accept`), cancel = △ (`ui_cancel`).
- **`DialogueBox`** (next): §2.6–2.7 on box 0, fed with script-text bytes. The interpreter calls it as the original's opcodes do (`SHOW_TEXTBOX`, `SET_SELECTION`, `SET_TEXTBOX_SIZE`). Until then a debug key will show a text from the current map's script, to check the box.
- **Sounds** (0, 1, 2, 3, 4, 7, 11): `UIBoxes.sound` and comments at the C calls; silent until audio.
- **Not 1:1:**
  - the PSX ordering table becomes draw order within `UIBoxes._draw`; other HUD nodes (clock, bars) keep their node order;
  - the additive texels (the arrow's STP texels) are drawn on an additive child canvas above the boxes, not between the box's own primitives.

## 4. Data (data porter group `font`, done)

`data_porter/specs/font.md`, from `src/main/font.c`, `sjis.c` and `utils.c`:

| Table | Records |
|---|---|
| `font/en_us`, `font/ja`, `font/en_eu` | one per glyph, in table order: `code` (Shift-JIS), `char` (cp932), `rows` (11 × u16 as written), `bitmap`, `width` (US: from the data; EU: the `drawGlyph` range rule; JP: 12), `sentinel` / `placeholder` |
| `font/clut` | `FONT_CLUT`: raw 15-bit colours, `rgb8`, `transparent` |
| `font/text_colors` | `TEXT_COLORS`: `rgb`, `tint`, the releases that have each entry |
| `font/ascii` | ASCII 0x20–0x7E → `code` (`convertAsciiToJis`) and `draw_string_code` (US `drawString`'s `.` / `'` overrides) |

**Godot:** `GameData.font(language)`, `GameData.font_clut()`, `GameData.text_colors()`, `GameData.font_ascii()`.

The checks (`data_porter/specs/font.md` §5) include the coverage of each language's text: every character has a glyph except a known list. A cross test does the same for the US event-script texts.

## 5. Verification

`tests/test_text.gd` (done):
- **Encoding:**
  - `A.'z0 ` gives `0x8260 0x8142 0x8175 0x829A 0x824F 0x8140`;
  - `'` without the override is `0x8166`;
  - `&` (`0x8195`) and a character with no code fall back to glyph 78 (×);
  - the US widths are 12 / 8 / 4, the EU space is 8, JP advances by 12;
- **Glyphs:**
  - Ａ written to the area matches its rows in colour 3;
  - x 5 lands on the cell at x 4;
  - clipping at 244 and at negative x;
  - `clearTextSubArea` works in 4-pixel words;
  - the tints;
- **Boxes:**
  - opening draws frames 0–4, then the box is open;
  - not available while animating;
  - tick and render run only while open;
  - the interpolated rect of frame 2 is (−67, 18, 135, 35);
  - closing draws frames 4–0, plays sound 1, shrinks to the new target and frees the slot;
  - static boxes;
  - the colour-word byte order;
- **Message box and tamer state 20:**
  - the arrow frame changes every 4 timer counts over 3 frames, with the timer read before `++`;
  - sub-states 0 → 4 → 5;
  - confirm closes the box and frees everyone;
  - a press is seen by one game frame;
- **Drawing:** a box drawn by the engine without errors;
- `tests/test_care.gd`: the sickness message in the text area (colour 10 from x 0, colour 1 from `len × 12`).

Still to come with the dialogue box:
- **`draw_string2`:** colour code, tab stops (`0C`, `0E`, `0F`, `16`–`1C`), end of line / text, the full-width-space advance quirk;
- **`showTextbox`:** a script text with a speaker gives the name line in the speaker's colour and the widest line;
- **Dialogue:** two pages, confirm flips then ends; choices wrap; cancel picks the last option.

`VERIFY.md`, Text section:
- the "<name> is sick" box (debug panel: "injured 12h");
- the font compared with the game: letters, the gap after the name, the frame colours;
- later: a dialogue from the map's script (debug key) with the speaker's name in colour, the paging arrow, and a choice.

## 6. Open questions

- **Control codes `02` and `03`** are skipped by `drawString2`. What reads them (the text reveal?) isn't traced.
- **`DRAW_STRING2_IS_FIXED_WIDTH`:** who sets it (US only) isn't traced; the port keeps the flag.
- **Ordering:** text area rows used by menus and battle (`renderString` callers) are documented when those systems are ported.
- **`TEXT_COLORS`** has 18 entries in one release and 17 in the others (`utils.c:45–47`); the per-release lists are exported.
- **The gap after the name** in "<name> is sick" (§2.5) follows from the C code. Whether the US game shows it can only be checked against the game.
- **The "next" arrow's layer:** its additive texels are drawn above the box's text, not below it (§3, not 1:1). That matters only where they overlap.
