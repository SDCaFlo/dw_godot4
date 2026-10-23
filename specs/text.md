# Text renderer (port spec)

Status (2026-10-23):
- **done:** the font, the text area, `renderString`, the UI boxes, the message box (the care's "<name> is sick" uses it), the text boxes and the dialogue box with pages and choices, the pad as the original reads it. A debug player (`D`) shows the map's script texts.
- **next:** the event-script interpreter, which drives the dialogue box through `ScriptContext`.

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
| every function of `script_textbox.c`: `drawString2`, `showTextbox`, `showTextboxReady`, `registerTextbox`, `createTextbox`, `closeTextbox`, `closeBox`, `closeAllTextboxes`, `triggerBoxCloseFlag`, `clearTextboxLineCount`, `getVRAMModeCoords`, `initializeTextbox`, `tickTextboxHandling`, `drawTextboxStrings`, `flipIdleTextboxPage`, `advanceTextbox`, `tickConfirmDialogue`, `tickSelectionDialogue`, `tickBackgroundDialogue`, `scriptShowSelection`, `setupDialogueBox`, `setupBoxOrigin`, `tickScriptDialogueBox`, `renderScriptDialogueBox`, `renderDialogueSelectionCursor`, `scriptSetTextboxSize`, `tickCustomSizedTextbox`, `renderCustomSizedTextbox`; `getSpeakerName`, `intToStringSJIS` (`script_value.c`); `setDialogueOwner`, `setFreshDialogue`, `isXPressedAfterDialogue` (`script_common.c`) | the text boxes and the dialogue box | `TextBoxes` (same names in snake case) |
| `pollInputGame` (`main.c:4035`), `processInput`, `isKeyDown`, `setInputRepeatMask` (`script_common.c:1261`) | the pad | `Pad` (`GameLoop.pad`) |

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
- **Sub-state 5:** the confirm button closes the box back to the tamer, frees the tamer, puts the partner back in state 1, the camera follows again, and game time runs.
  - The button is ✕ on the US pad, read from `POLLED_INPUT`: **held**, not newly pressed (§2.8).
  - So ✕ held down when the box appears closes it on the frame after it opens. This can happen while the box is still opening.

### 2.6 Dialogue text (`showTextbox`, `drawString2`; `script_textbox.c:1054`, `:644`)

**`showTextbox(box, speaker)`** reads a script text at `SCRIPT_POINTER` into line buffers.
- **Line buffers:** `TEXTBOX_LINES_PTR`, one buffer of `TEXTBOX_LINE_SIZE` bytes (64, EU 80) per text-area row; vram mode 2 uses the second half of each buffer.
- **Where it writes:** the box's rows, on the back page of a double-buffered box (`(backPage ^ 1) × vramRows`).
- **Speaker line:** with a speaker (≠ `0xFF`) the first line is `01 c`, the name, then `01 01 0D 00`. The colour c is:
  - tamer (`0xFD`): 6;
  - partner (`0xFC`): 10;
  - special speakers (≥ `0xC8`): 5;
  - NPCs: 7.
- **The name** comes from `getSpeakerName` (`script_value.c:60`):
  - `0xFD`: `DIGIMON_NAME(0)`, which holds the player's name (the savegame's `playerName`);
  - `0xFC`: the partner's name;
  - below `0xC8`: the name of the Digimon type of the entity with that script id;
  - `0xC8` + n: `SPECIAL_SPEAKERS[n]` (Sign, Box, …).
- **Codes copied as they are** (code + 1 byte): `01` colour, `02`, `0C`, `0E`, `0F`; `03` takes 3 bytes.
- **Codes expanded** (code + 1 byte):
  - `04 p`: script value p as 3 full-width digits, leading zeros dropped (`intToStringSJIS(…, 3, 1)`);
  - `05` / `06`: the tamer's / partner's name;
  - `07 p` / `08 p` / `09 p` / `11 p` / `12 p`: the name of the Digimon / technique / item / BGM / tournament whose id is script value p;
  - `0A`: money, 6 digits; leading zeros become full-width spaces (flag 0);
  - `0B`: merit, 4 digits, the same way;
  - `10`: `SHOP_VARIABLE`, 5 digits, leading zeros dropped;
  - `13` / `14` / `15`: tournaments won / tournament wins / tournaments lost, 3 digits, leading zeros dropped.
- **Other bytes:** a character, copied with the byte after it (2-byte Shift-JIS) and counted as one column. Every script text is full-width.
- **Name columns:** each copied name adds `strlen / 2` columns.
- **`0D b`:** ends a line (the widest line so far is kept). If the next byte is `00`:
  - the page ends: the pointer skips 2 more bytes, and the `0D` becomes the terminator `00`;
  - if the next instruction is not another `SHOW_TEXTBOX`, this is the last page (`pageReady = 1`).
- **After the text:** `writeCount++`, and `ACTIVE_INSTRUCTION = SHOW_TEXTBOX`.
- **Returns:** the widest line in columns, for the choice cursor.
- **`showTextboxReady`:** sets `pageReady = 1` first.

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

- **Glyph codes:** `drawString2` draws ASCII through `convertAsciiToJis` **without** `drawString`'s `.` / `'` overrides. Names copied from the data (US Digimon, technique, item names) are ASCII, so their `'` is drawn as `0x8166`, which the US font lacks: it draws ×. Script texts themselves are full-width.
- **Positions:** relative to the x given (`x + pos`), clipped by `drawGlyph`.
- **The full-width space** (`0x8140`) only clears its 12-px cell (EU: 8, and advances 8).
- **US advance:** `pos +=` the glyph's width, or 12 when `DRAW_STRING2_IS_FIXED_WIDTH` is set (the naming screen, `script_menu.c:1213`).
- **Quirk kept:** for the full-width space the US code doesn't set the advance, so it moves by the previous glyph's width (`adv` is not reassigned, `script_textbox.c:780–804`).
- **Returns** 1 at `00` (end of text), 0 at `0D` (end of line).

### 2.7 The text boxes and the dialogue box (`script_textbox.c`)

**Text boxes** (`TEXTBOX_DATA`, `TextBoxData` in `include/dw/ui.h:24`): six entries, paired with the UI box of the same id. Each entry holds:
- `rect`, `origin`, `tick`, `render`;
- `flags`: bits 0–3 the wanted UI state (1 open); bits 4–5 the UI features; bit 6 close animated; bit 7 open animated;
- its text-area rows: `vramRow`, `vramRows`, `vramMode` (0 full width; 1 and 2 the left and right halves, `getVRAMModeCoords`), `doubleBuffered`, `backPage`;
- the counters `writeCount` (texts written into the line buffers), `renderCount`, `flipCount`, `writeRow`;
- the states `registered` (1 = all lines drawn), `pageReady` (the last page), `idle`.

**Functions:**
- **`createTextbox(id, flags, rect, origin, tick, render)`** closes an open entry first, sets the fields, and `setFreshDialogue()` (the confirm button must be released before input counts, `isXPressedAfterDialogue`).
- **`registerTextbox(id, row, rows, double, mode)`** sets the rows, zeroes the counters, `registered = 1`, `idle = 1`, `setTextColor(1)`, and clears its rows of the text area (both pages).
- **`tickTextboxHandling`** runs once per frame from `tickScript`, before the objects' tick pass (`script_interp.c:400`), while `ACTIVE_INSTRUCTION ≠ 0xFF`. For each entry with rows:
  - **a new text** (`registered = 1` and `writeCount ≠ renderCount`): `writeRow` is the back page (double-buffered: its rows are cleared) or 0; `registered = 0`;
  - **drawing:** the first entry with `registered = 0` draws its next line (`drawTextboxStrings`: **one line per frame** in mode 0, two in modes 1 and 2). At the text's end: `writeCount = renderCount = 1`, `flipCount = 0`, `registered = 1`;
  - **opening:** if the wanted state (`flags & 0xF`) is 1, the UI box is closed and all lines are drawn (`registered = 1`), the UI box opens: features `(flags >> 4) & 3`, colour 1 without features, else 0; animated from `origin` if bit 7;
  - **closing:** if the wanted state is not 1 and the UI box is open, `closeTextbox`;
  - then `DELAY_FRAMES` and `AUTOCLOSE_FRAMES` count down, `TEXTBOX_OPEN_TIMER++`, and the arrow flag (`MAIN_D_80134F94`) is reset.
- **`closeTextbox(id, target)`** (UI box not closed or closing): `removeAnimatedUIBox` if flag bit 6, else `removeStaticUIBox` (no animation); then `clearTextboxLineCount` frees its rows.
- **`triggerBoxCloseFlag`** clears the wanted state; **`closeBox`** does that and `closeTextbox`; **`closeAllTextboxes`** closes every entry with a wanted state.
- **`flipIdleTextboxPage(id)`**, double-buffered only: returns 1 (busy) while lines are being drawn. On an idle entry with a text it shows the new page (`backPage ^= 1`, `flipCount++`, `idle = 0`, `TEXTBOX_OPEN_TIMER = 0`); if that isn't the last page, `ACTIVE_INSTRUCTION = 0` (the script goes on and writes the next page into the back page).
- **`advanceTextbox(id)`** (confirm):
  - last page with no newer page: `idle = 1`, `pageReady = 0`, `ACTIVE_INSTRUCTION = 0`, returns 1;
  - otherwise it flips to the waiting page and returns 0.

**The dialogue box** (box 0):
- **`setupDialogueBox(owner)`:**
  - rect (−130, 42, 262, 59), flags `0x21`: open, features 2 (half-dark fill, colour 0), no closing animation;
  - `0x80` (grows from the speaker) when `setupBoxOrigin` finds the speaker on screen: `getEntityScreenPos(entity of the script id, 1)` as a 10 × 10 rect; owner `0xFF` has none;
  - `registerTextbox(0, 0, 4, 1, 0)`: two pages of 4 rows (text-area rows 0–47 and 48–95), so with a speaker line 3 text lines per page.
- **`setDialogueOwner(owner)`** (`script_common.c:2959`): when the owner changes, `scriptPauseGame(owner)` and `setupDialogueBox(owner)`. `SET_DIALOG_OWNER p` sets the owner to p − 1 first (while box 0 isn't open), so the box is always set up again.
- **Showing** (`renderScriptDialogueBox`):
  - four `renderString(0, x + 5, y + 4 + 13 i, 252, 12, 0, (vramRow + backPage × 4 + i) × 12, 6, shadow)`;
  - the choice cursor while a choice is active;
  - the "next" arrow when the arrow flag is set.
- **Waiting** (`tickScriptDialogueBox` → `tickConfirmDialogue`, while the UI box is open):
  - nothing while a page is flipping or being drawn;
  - mode 0 (`TEXTBOX_CLOSE_MODE`, set by `SET_TEXTBOX_MODE`) sets the arrow flag;
  - nothing until the confirm button was released since the box was created;
  - mode 0: confirm (`isKeyDown`, the box open) advances (sound 3);
  - mode 1 advances at once;
  - mode 2 advances when `AUTOCLOSE_FRAMES` reaches 0.
- **Choices** (`SET_SELECTION n targets…`, `scriptShowSelection`):
  - **the option list:** `DIALOGUE_SELECTION` holds `count = n`, `current = 0`, `pointer` (the target table), and `endPointer`, the script after the text;
  - **the cursor:** its width is `showTextbox`'s widest line × `GLYPH_WIDTH` + 2 (US at most 240); its y offset is 13 with a speaker line, 0 without;
  - `tickSelectionDialogue`:
    - up / down (`isKeyDown` `0x1000` / `0x4000`) move the cursor, wrapping (sound 2);
    - confirm picks (sound 3), and the script jumps to `target[current]`;
    - cancel without trigger `0x31`: in a script choice it continues after the text (sound 4); in a builtin routine's choice it picks the last option. With trigger `0x31` it plays sound 11;
  - `renderDialogueSelectionCursor`: `renderSelectionCursor(x − 1, y + offset + 13 × current − 2, width, 13, 6)` (US; JP / EU without the − 2), not while the box is idle.
- **Builtin routines** (`CALL_ROUTINE`, `SCRIPT_TEXTBOX_MODE`): 1 waits for a confirm, 2 for a choice (`SCRIPT_STATE_2 = next + current`), 3 for the page to be shown (`tickBackgroundDialogue`).
- **Custom size** (`SET_TEXTBOX_SIZE origin cols rows`, `scriptSetTextboxSize`):
  - a box of `cols × 12 + 10` by `rows × 13 + 7`, centred, with `rows` rows;
  - confirm advances, and closes the box after the last page;
  - cancel draws the rest of the text at once and closes the box (sound 4).

### 2.8 Pad input (`pollInputGame`, `processInput`; `main.c:4035`, `script_common.c:1261`)

Once per frame, before the script and the objects (`gameLoop`, `main.c:3933`):
- **`POLLED_INPUT`:** `PadRead`: the buttons **held** now. `POLLED_INPUT_PREVIOUS` is last frame's.
- **`CHANGED_INPUT`:** newly pressed buttons. The d-pad (`0xF000F000`) also repeats: on the 6th frame held, then every 2 frames (`GAME_INPUT_REPEAT_TIMER`: counts to 5, then steps back by 2).
- **`processInput` / `isKeyDown(key)`:**
  - a held key counts once (`INPUT_FRESH_MASK`: set when released, cleared by `isKeyDown`);
  - keys in `INPUT_REPEAT_MASK` (set by menus, e.g. `0x5000` up / down) also repeat: on the 8th frame held, then every 2 frames (`INPUT_REPEAT_COUNTER` counts to 6, then alternates 6 / 8).
- **US buttons:** ✕ confirm `0x40`, △ cancel `0x10`, up `0x1000`, right `0x2000`, down `0x4000`, left `0x8000`. JP swaps confirm (○ `0x20`) and cancel (✕ `0x40`).

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
- **Pad** (`scripts/core/pad.gd`): §2.8.
  - `GameLoop` polls it at the start of every game frame from the Godot actions (`ui_accept` ✕, `ui_cancel` △, the arrows). A tap shorter than a frame still counts for one frame.
  - It gives `is_held` (`POLLED_INPUT`), `is_changed` (`CHANGED_INPUT`) and `is_key_down` (`isKeyDown`), with the same repeats.
  - The tamer's message box closes on a held ✕ (`is_held`), as the C does.
- **`TextBoxes`** (`scripts/ui/text_boxes.gd`): §2.6–2.7, the whole of `script_textbox.c`, on the shared `UIBoxes` and `TextArea`. Box 0 is the dialogue box.
  - Its line buffers hold the C's bytes: names copied from the data are ASCII in US (`PsxFont.to_bytes`), typed names (tamer, partner) and all JP / EU text full-width.
  - Signal `sound(id)`.
- **`ScriptContext`** (`scripts/script/script_context.gd`): the interpreter's globals the text boxes use:
  - the script bytes (`code`) and the pointer, `active_instruction`, `textbox_mode`, `dialogue_owner`, `textbox_close_mode`;
  - `read_pstat`, triggers;
  - callables for the entity type and screen position of a script id, and `scriptPauseGame`.
  
  The interpreter will own it.
- **Debug player** (`scripts/debug/dialogue_debug.gd`, key `D`): plays the current map's script texts on the real script bytes, one run of text instructions at a time, and stops game time while it plays.
  - It executes `SET_DIALOG_OWNER`, `SHOW_TEXTBOX`, `SET_SELECTION`, `SET_TEXTBOX_SIZE` and `SET_TEXTBOX_MODE` as the interpreter does. Any other instruction ends the run and closes the boxes.
  - Speakers are named from the map's Digimon (`script_id` → type). Map NPCs aren't spawned, so their boxes open without growing.
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
  - a held confirm closes the box and frees everyone;
- **Pad:**
  - held / changed / `isKeyDown`, which takes a key once until it is released;
  - the `CHANGED_INPUT` d-pad repeat on frames 1, 6, 8, 10;
  - the `isKeyDown` repeat mask on frames 1, 8, 10, 12;
- **`drawString2`:**
  - the colour code, ASCII and full-width;
  - `0D` returns 0 and `00` returns 1;
  - the full-width-space quirk (ａ, space, Ａ lands at 16);
  - `0C` to 96, `17` to 105, `0F` 6 px;
  - fixed width;
  - `intToStringSJIS` with and without leading zeros;
- **`showTextbox`:**
  - the speaker line (colour 10, the full-width partner name);
  - the lines on the back page, the last `0D` turned into the terminator;
  - the widest line, `pageReady`, the pointer after the text;
  - codes `04` (script value) and `05` (tamer name);
- **Dialogue pages:**
  - one line a frame, then the box opens;
  - page 1 flips and lets the script go on, page 2 is written to the back page;
  - the arrow;
  - confirm shows page 2, a held confirm doesn't repeat, confirm ends the text;
  - `closeAllTextboxes` closes at once;
- **Choice:**
  - the cursor width;
  - down / down (wrap) / up (wrap) with sound 2;
  - confirm jumps to the option's target;
  - cancel continues after the text (sound 4);
- **Debug player:** the first text of MAYO04A plays and ends;
- **Drawing:** a box drawn by the engine without errors;
- the test prints how many checks ran (a script error would stop a test function early);
- `tests/test_care.gd`: the sickness message in the text area (colour 10 from x 0, colour 1 from `len × 12`).

`VERIFY.md`, "Text and windows":
- the "<name> is sick" box (debug panel: "injured 12h");
- the font compared with the game: letters, the gap after the name, the frame colours;
- dialogues from the map's script (`D`): the speaker's name in colour, colour codes, pages, the arrow, choices.

## 6. Open questions

- **Control codes `02` and `03`** are skipped by `drawString2`. What reads them (the text reveal?) isn't traced.
- **`DRAW_STRING2_IS_FIXED_WIDTH`** is set by the naming screen (`script_menu.c:1213`); the port keeps the flag for it.
- **`TEXTBOX_ORIGIN_X/Y/Z`:** some scripts set a world position for the next box's origin (`setupBoxOrigin`). It comes with the interpreter.
- **`SET_DIALOG_OWNER` while box 0 is open** sets the box up again: `createTextbox` closes it at once and it opens again (static or growing) once the next text is drawn. This is what the C does; whether it flickers in the game isn't checked.
- **Names by id:**
  - code `11` (BGM) reads `systems/jukebox`, which is `BGM_TRACK_NAMES` as the C lists it. Its US slot 45 is Mt. Panorama's theme, where the other releases list Mt. Infinity's, so the text block order would be wrong there;
  - code `12` (tournament) uses the `TOURNAMENT_NAMES` block order, which equals `script_common.c:507`.
- **Ordering:** text area rows used by menus and battle (`renderString` callers) are documented when those systems are ported.
- **`TEXT_COLORS`** has 18 entries in one release and 17 in the others (`utils.c:45–47`); the per-release lists are exported.
- **The gap after the name** in "<name> is sick" (§2.5) follows from the C code. Whether the US game shows it can only be checked against the game.
- **The "next" arrow's layer:** its additive texels are drawn above the box's text, not below it (§3, not 1:1). That matters only where they overlap.
