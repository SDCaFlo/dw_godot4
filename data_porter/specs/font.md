# Font (`src/main/font.c`, `sjis.c`, `utils.c` → `output/font/`)

The game's own font: the glyph bitmaps and their Shift-JIS codes for each release, the 16 colours of the text area, the tint per `renderString` colour, and the ASCII map US strings go through. Converter: `dwdata/groups/font.py` (`python -m dwdata convert font`). How the renderer uses it: `../../specs/text.md` (port spec of the text renderer).

## 1. Source

| Symbol | Where | C type | Releases |
|---|---|---|---|
| `CHAR_TO_GLYPH_TABLE` | `font.c:43` (EU), `:265` (JP), `:1391` (US) | `uint16_t[NUM_GLYPHS]` | 188 / 992 / 79 entries (`NUM_GLYPHS`, `font.c:8–14`) |
| `GLYPH_DATA` | `font.c:69` (EU), `:391` (JP), `:1406` (US) | `GlyphData[NUM_GLYPHS]` (`font.c:34`: `uint16_t pixelData[11]`, US also `uint16_t width`) | same |
| `FONT_CLUT` | `font.c:1491` | `uint16_t[16]` | all the same |
| `TEXT_COLORS` | `utils.c:45` | `RGB8[17]`, EU `RGB8[18]` (`include/dw/graphics.h:8`) | EU adds one entry |
| `CHAR_MAPPING_NORMAL`, `CHAR_MAPPING_SPECIAL` | `sjis.c:11`, `:17` | `Ascii2ShiftJIS[3]`, `[33]` (`shiftJIS`, `ascii`) | all the same |
| `GLYPH_WIDTH` | `include/dw/font.h:9–13` | `#define` | 8 in EU (unused there: `drawGlyph` returns the width), 12 otherwise |

All four JP releases (jp, jp_trial, jp_bombom, jp_rev1) compile the same JP font.

## 2. Original usage

- **`drawGlyph(code, x, y)`** (`font.c:1544`):
  - returns early if x or y is outside 0 … 243 (`TEXT_DRAW_LIMIT`);
  - byte-swaps the code (strings store the high byte first);
  - **JP / EU:** returns at once for the full-width space `0x8140` (EU returns 8, JP draws nothing);
  - writes the code into the last table entry, then searches the table from the start. **A code not in the table stops at the last entry and draws its glyph**: × in US (the entry's own code is `0x817E`), a crossed box in JP / EU (code `0x0000`);
  - draws 11 rows × 12 px into the text area: bit 15 − x of a row is pixel x, **a 0 bit is ink** (`(rowData & 0x8000) == 0`) and gets the colour index of `setTextColor`, the other pixels get 0;
  - **advance:** US returns `GlyphData.width`; EU returns 8 or 12 by code range (`font.c:1611–1618`); JP returns nothing and `drawString` adds 12.
- **`drawString(str, x, y)`**:
  - US (`font.c:1728`): an ASCII byte goes through `convertAsciiToJis` (`sjis.c:63`), except `.` → `0x8142` and `'` → `0x8175` (「); a byte with the high bit set starts a 2-byte Shift-JIS code;
  - JP / EU (`font.c:1709`): 2-byte codes only.
- **`convertAsciiToJis(c)`** (`sjis.c:63`): digits and letters by offset from `CHAR_MAPPING_NORMAL` (`0`→`0x824F`, `A`→`0x8260`, `a`→`0x8281`); punctuation from `CHAR_MAPPING_SPECIAL`; 0 outside 0x20–0x7E. Also used by the US battle-end box (`battle_hud.c:467`) and `drawString2` (`script_textbox.c`), **without** `drawString`'s overrides.
- **`initializeFontCLUT`** (`font.c:1503`): loads `FONT_CLUT` to VRAM (208, 488); the text area's 4-bit pixels index it.
- **`renderString`** (`utils2.c:247`): the text quad's colour is `TEXT_COLORS[color]`; the PSX multiplies texels by colour / 128, so 0x80 shows the font colours unchanged.

## 3. Mapping

`output/font/<table>.json` in the common table shape (`../CLAUDE.md`).

| Table | Records |
|---|---|
| `font/en_us` (US), `font/ja` (jp_rev1), `font/en_eu` (EU) | one per glyph, in table order: `index`, `line`, `code`, `code_hex`, `char`, `rows` (the 11 `pixelData` values), `bitmap` (rows as text, `#` = ink), `width`, `sentinel` (last entry), `placeholder` (`0xFFFF`), `c` (the raw record), `release_values` (JP releases that differ; none) |
| `font/clut` | the 16 `FONT_CLUT` entries: `raw`, `rgb5`, `stp`, `rgb8` (`(v << 3) \| (v >> 2)`, like the asset porter's PNGs), `transparent` (raw 0) |
| `font/text_colors` | the 18 entries of the longest release: `rgb`, `tint` (rgb / 0x80), `releases` (entry 17 only in EU) |
| `font/ascii` | ASCII 0x20–0x7E: `code` (`convertAsciiToJis`), `draw_string_code` (with US `drawString`'s overrides), `glyph` (index in `en_us` / `en_eu`, null = drawn as the sentinel); the raw `CHAR_MAPPING_*` arrays in `c` |

- **`char`** is the code decoded as **cp932** (Microsoft's Shift-JIS). It matches the decomp's text YAML; Python's `shift_jis` differs on `0x8160` (〜 vs ～) and `0x817C` (− vs －). Null for the placeholder and the code 0 of the JP / EU sentinel.
- **EU accented letters:** the EU font draws accented Latin letters (à, é, ñ, ß, …) and a few punctuation marks at katakana codes, from `0x8340`; some of these slots are blank. For those, `char` is the code's Shift-JIS meaning (a katakana), not the shape (see `en_eu.png`). The en_eu text in the YAML uses none of them.
- **`width`:** US from the data (4–12 px); EU from the range rule (8 or 12; the space `0x8140` never reaches the table); JP 12.
- **Reports:** `report.md` (counts, the US glyphs as bitmaps, the palette, the tints, the ASCII map, the text characters without a glyph) and `en_us.png`, `ja.png`, `en_eu.png` (glyph sheets: 16 per row in table order, 2×).

## 4. Godot usage

- `GameData.font(language = "")` → the glyph records of `font/<language>` (current language by default); `GameData.font_clut()`, `GameData.text_colors()`, `GameData.font_ascii()`.
- Users: `PsxFont` and `TextArea` (`../../specs/text.md` §3). They look codes up like `drawGlyph`: the first match, else the last glyph.
- **Modding:** glyph bitmaps, widths, palette and tints can be changed. Keep each table's last entry as the fallback glyph. A new character needs a code that strings can produce: a Shift-JIS code that the language's text encodes to.

## 5. Verification

The converter checks (52):

- the code the spec reproduces is still in the C text, compared with whitespace collapsed:
  - the sentinel search;
  - the EU width rule;
  - the JP / EU space;
  - `drawString`'s overrides;
  - the clipping;
  - the ink bit test;
  - every `convertAsciiToJis` range and both return formulas;
- every table parses in every release; the sizes match the US symbol map where it gives one;
- `GlyphData` has `pixelData` (+ `width` in US);
- the table sizes are 79 / 992 / 188, and every JP release has the same font;
- per language:
  - the unused bits 3…0 are 1 in every row;
  - every code decodes;
  - the widths are 1–12;
  - the codes are unique;
  - `0xFFFF` placeholders appear only at slot 60 (JP / EU);
- `FONT_CLUT[0]` is transparent; `TEXT_COLORS` differs between releases only by extra entries at the end;
- `convertAsciiToJis` gives a code for every ASCII 0x20–0x7E, and `drawString`'s `.` override equals it (only `'` differs);
- **every character of each language's text has a glyph, except a known list** (`KNOWN_MISSING`). This runs over every string of the text YAML, as its language's main release draws it. Left out first:
  - the control codes (`#C1 #R #W`, `{C1}`, bare ASCII in `ja`);
  - printf specifiers (filled in before drawing);
  - line breaks;
  - the JP / EU space.

  A change in either direction fails. The known list (all drawn as the sentinel glyph):
  - en_us `%` in "…reduced by N%!" (`BTL_STR_MP_BONUS_PERCENT`, drawn by the battle-end box: US shows × there);
  - en_us `&` in the finisher name "Dark Network & Concert Crush";
  - kana in the US build's leftover JP strings: `SAVE_LABELS` に / が / を, `SAVE_MESSAGES` "スロット１のメモリーカードに", the naming screen's hiragana row (`HIRAGANA_KA_ROW`, en_us "かきくけと", en_eu "かきくけこ").

Tests: `tests/test_font.py` (synthetic decomp with the three fonts, the coverage check failing on a new character, used low bits failing, the width and ASCII rules, real data). `tests/test_cross_asset_porter.py` checks that every Shift-JIS code of the US event scripts' text (asset porter output) has a US glyph.

## 6. Open questions

- **Placeholder slot 60** (JP / EU, code `0xFFFF`) holds an `i`-like glyph. No string can reach it. Maybe a removed character.
- **Leftover JP strings in US:** `drawMainMenuStrings` references the kana strings in US too. Whether a US screen really shows them (as ×) isn't traced.
- **EU accented letters:** which code draws which letter isn't mapped (`char` keeps the Shift-JIS meaning). It is needed only for text the YAML doesn't contain.
- **NUL bytes in script text:** 22 text tokens of the US scripts carry `00` bytes after their text (e.g. `script_026`). `drawString2` stops at the first one; the asset porter's tokens keep them.
