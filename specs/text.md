# Text renderer (port spec)

Status: spec 2026-10-23, not implemented yet.

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
| `FONT_CLUT` (`font.c:1491`), `TEXT_COLORS` (`utils.c:45`) | 16 font colours; the tint per `renderString` colour | `font/palette` |
| `convertAsciiToJis`, `CHAR_MAPPING_*` (`sjis.c:11–99`) | ASCII → full-width Shift-JIS (US strings are ASCII) | `font/ascii` |
| `initializeFontCLUT`, `clearTextArea`, `clearTextSubArea`, `setTextColor`, `drawGlyph`, `drawString` (`font.c:1503–1763`) | drawing into the text area | `TextArea` |
| `renderString` (`utils2.c:247`), `initStringFT4` (`utils.c:206`) | a rectangle of the text area on screen, tinted, with a shadow | `TextArea.render_string` (HUD draw) |
| `createStaticUIBox`, `createAnimatedUIBox`, `renderUIBoxStatic`, `renderUIBoxAnimated`, `renderUIBoxAnim`, `renderUIBoxBorder`, `removeStaticUIBox`, `removeAnimatedUIBox` (`ui.c`) | window frames, the open / close animation | `UIBoxes` |
| `renderUIBox` (`script_textbox.c:996`) | the blinking "next" arrow | `UIBoxes.render_next_arrow` |
| `tamerTickAwardSomething`, `renderAwardSomethingTextbox` (`tamer.c:1751`, `:1351`) | the message box (awards, sickness) | `MessageBox` (tamer state 20) |
| `drawString2`, `showTextbox`, `registerTextbox`, `createTextbox`, `tickTextboxHandling`, `drawTextboxStrings`, `flipIdleTextboxPage`, `advanceTextbox`, `tickConfirmDialogue`, `tickSelectionDialogue`, `scriptShowSelection`, `setupDialogueBox`, `scriptSetTextboxSize`, `renderScriptDialogueBox` (`script_textbox.c`) | the dialogue box | `DialogueBox` |

## 2. Original behaviour

### 2.1 The font (`font.c`)

- **Glyphs per release:** US 79, JP 992 (kana and kanji included), EU 188.
  - Each glyph has 11 rows of a `uint16_t`. Bits 15…4 are pixels 0…11 from the left; **a 0 bit is ink**. Bits 3…0 are unused.
  - US glyphs also store an advance width (`GlyphData.width`, `font.c:37`). EU widths are 8 or 12 px by code range (`font.c:1611–1618`). JP glyphs are a fixed 12 px.
- **Glyph lookup** (`drawGlyph`, `:1603–1609`):
  - the code is compared with `CHAR_TO_GLYPH_TABLE` (Shift-JIS codes, byte-swapped from the string);
  - the last entry is overwritten with the code first, as a sentinel.
  - **Quirk kept:** an unknown code draws the last glyph's pixels. In US that is ×, `0x817E`.
- **US characters** (all full-width Shift-JIS):
  - A–Z, a–z, 0–9 (`0x8260`…, `0x8281`…, `0x824F`…) and the space `0x8140`;
  - punctuation: 。`0x8142` (drawn as a period), ？ `0x8148`, ！ `0x8149`, 」 `0x8176`, 「 `0x8175`, ， `0x8143`, ＼ `0x815F`, ： `0x8146`, ； `0x8147`, ＋ `0x817B`, － `0x817C`, ＝ `0x8181`;
  - the button symbols ○ `0x819B`, □ `0x81A0`, △ `0x81A2`, × `0x817E`.
  - **ASCII bytes** (`drawString`, `:1738–1749`) go through `convertAsciiToJis` (`sjis.c:63`); `.` becomes `0x8142` and `'` becomes `0x8175`.
  - **Two-byte codes** (high bit set) are Shift-JIS.
- **Space:** JP / EU skip the full-width space `0x8140` (EU advances 8). US draws it as a glyph (entry 62 is `0x8140`).
- **Clipping:** a glyph is drawn only if x and y are below 244 (`TEXT_DRAW_LIMIT`, area 256 − cell 12).

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
- **Static box** (`createStaticUIBox`): open at once.
- **Animated box** (`createAnimatedUIBox`):
  - **Opening:** grows from a start rect (e.g. a 10 × 10 square at the speaker on screen) to the final rect over 4 frames, as an outline (`renderUIBoxAnim`: frame `f` is `start + f × (final − start) / 4`). Then it is open.
  - **Sounds:** sound 0 when it opens, sound 1 when the closing animation starts.
  - **Closing** (`removeAnimatedUIBox`): shrinks back to its start rect (or a new target), then closes.
- **Open box** (`renderUIBoxStatic`):
  - **Contents first:** the box's own render function draws its contents.
  - **Border** (`renderUIBoxBorder`):
    - corners: four 4 × 4 corner sprites from `system_w` (page (320, 0); u `0x78` / `0x7C`, v `0x90` / `0x94`, i.e. image pixel (u, v − 128); palette `(0x60, 0x1EC)` = CLUT row 492 = `p4`);
    - edges: lines in black `0x020202`, gold `0xFAD990` and brown `0xC59F4A`; three lines on each edge.
  - **Inner lines:** black at x + 3 and x + w − 4.
  - **Features** (bits):
    - 1: a title rule at y + 13–15;
    - 4: a scroll bar;
    - 2: a semi-transparent fill.
  - **Fill:** `UI_BOX_COLORS[color]`, colour 0 black or 1 (0x2D, 0x38, 0x40), at (x + 4, y + 3, w − 8, h − 3).
- **"Next" arrow** (`renderUIBox`):
  - **Sprite:** 16 × 12 from `system_w` (u `0x4C + 16 × (TEXTBOX_OPEN_TIMER / 4 % 3)`, v `0xB7`).
    - `GetTPage(0, 1, 320, 128)` gives page (320, 0), since only bit 8 of y counts, so the pixel is (u, `0xB7` − 128).
    - Palette `(96, 500)` = `p12`.
    - Semi-transparency mode 1 (additive).
  - **Place:** at (box.x + 239, box.y + 43).
  - **Animation:** it cycles 3 frames every 4 frames.

### 2.5 The message box (tamer state 20, `tamerTickAwardSomething`)

Used for medals, tamer-level changes and "<name> is sick" (`tickSicknessMechanics`, `specs/care.md` §2.7).

- **Before:** the caller clears the text area and draws its lines at (0, 120), (0, 132), (0, 144) (`drawString`). The sickness message draws the name in colour 10 and " is sick" in colour 1 after it.
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
- **Sub-state 5:** the confirm button (✕ on the US pad) closes the box back to the tamer, frees the tamer and partner, the camera follows again, and game time runs.

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

- **`PsxFont`** (`scripts/text/psx_font.gd`): the glyph table of a language from `GameData` (§4), as `code → glyph`.
  - **Language → release:** `en_us` → US, `ja` → JP (jp_rev1), `en_eu` → EU.
  - **Encoding a Godot string:** ASCII through `font/ascii` (US) and the rest to Shift-JIS (`String` → Shift-JIS through the glyph table's `char`). This gives the codes `drawGlyph` expects.
- **`TextArea`** (`scripts/text/text_area.gd`): the 256 × 256 text area as an `Image` of colour indices, shown through a palette texture.
  - **Methods:** `clear(rect)`, `set_text_color(c)`, `draw_glyph(code, x, y) -> width`, `draw_string(text, x, y)`, `draw_string2(bytes, x, y) -> done`.
  - **Drawing it** (`render_string`): any `Control` can draw a rectangle of the area tinted by `TEXT_COLORS`, with the shadow.
  - **One area:** one shared instance, as the original has one area; callers own rows as the original does.
- **`UIBoxes`** (`scripts/text/ui_boxes.gd`), a HUD control:
  - the six boxes, opening / closing, border, fill, features, ticked on `GameLoop.frame`;
  - each box has a `render` callable for its contents;
  - the "next" arrow.
- **`MessageBox`:** the tamer's state 20 (§2.5), with `show(lines)` for its callers. It replaces the care's help-line stand-in for "<name> is sick" (`specs/care.md` §3.3).
- **`DialogueBox`** (`scripts/text/dialogue_box.gd`): §2.6–2.7 on box 0, fed with script-text bytes. The interpreter (next step) calls it as the original's opcodes do (`SHOW_TEXTBOX`, `SET_SELECTION`, `SET_TEXTBOX_SIZE`). Until then a debug key shows a text from the current map's script, to check the box.
- **Sounds** (0, 1, 2, 3, 4, 7, 11): named calls, silent until audio.
- **Pad buttons:** confirm = ✕ (`ui_accept`), cancel = △ (`ui_cancel`).
- **Not 1:1:**
  - the PSX ordering table becomes child order per box layer;
  - `renderSelectionCursor`'s fill box (`utils2.c:232`) is drawn as a filled rect with the same colour and semi-transparency.

## 4. Data (data porter, new group `font`)

From `src/main/font.c`, `src/main/sjis.c` and `src/main/utils.c`, per release:

| Table | Records | Fields |
|---|---|---|
| `font/en_us`, `font/ja`, `font/en_eu` | one per glyph, in table order | `index`, `code` (Shift-JIS), `char` (Unicode, decoded with Python's `shift_jis`; null if it doesn't decode), `rows` (11 × u16 as written), `width` (US: from the data; EU: the `drawGlyph` range rule, checked against the C text; JP: 12) |
| `font/palette` | `font_clut` (16 raw 15-bit colours, RGB), `text_colors` (`TEXT_COLORS`, per release) | |
| `font/ascii` | ASCII 0x20–0x7E → Shift-JIS (`convertAsciiToJis`), with `drawString`'s `.` / `'` overrides | |

**Checks:**
- the table sizes (79 / 992 / 188, `NUM_GLYPHS`);
- every glyph's bits 3…0 are 1 (unused);
- the codes are unique except the last entry (sentinel);
- `char` decodes for every code but the sentinel;
- every ASCII character of the `en_us` text (YAML, and the US script texts of the asset porter) has a glyph;
- the EU width rule and the `.` / `'` overrides are still in the C text.

**Godot:** `GameData.font(language)`, `GameData.font_palette()`, `GameData.font_ascii()`.

## 5. Verification

`tests/test_text.gd`:
- **Encoding:** "A" → `0x8260`, "." → `0x8142`, an unknown character → the last glyph;
- **Glyphs:** the pixels of "A" written to the area match its rows; colour index from `set_text_color`; a 12-px advance for "A" (US width);
- **`draw_string2`:** colour code, tab stops (`0C`, `0E`, `0F`, `16`–`1C`), end of line / text, the full-width-space advance quirk;
- **`showTextbox`:** a script text with a speaker gives the name line in the speaker's colour and the widest line;
- **Boxes:** the open animation (4 frames, interpolated rects), close back to the start rect, the arrow's frame from the timer;
- **Dialogue:** two pages, confirm flips then ends; choices wrap; cancel picks the last option.

`VERIFY.md`, Text section:
- the "<name> is sick" box (debug panel: toggle sick, then wait an hour at ×60);
- a dialogue from the map's script (debug key) with the speaker's name in colour, the paging arrow, and a choice;
- the font compared with the game: letters, the 12 px grid, the shadow.

## 6. Open questions

- **Control codes `02` and `03`** are skipped by `drawString2`. What reads them (the text reveal?) isn't traced.
- **`DRAW_STRING2_IS_FIXED_WIDTH`:** who sets it (US only) isn't traced; the port keeps the flag.
- **Ordering:** text area rows used by menus and battle (`renderString` callers) are documented when those systems are ported.
- **`TEXT_COLORS`** has 18 entries in one release and 17 in the others (`utils.c:45–47`); the per-release lists are exported.
