# Text (`text/**/*.yaml` → `output/text/`)

The in-game strings of every release: Digimon, technique and item names, item descriptions, menus, save screens, map names, BGM names, tournaments, battle messages, minigame dialogue. Converter: `dwdata/groups/text.py` (`python -m dwdata convert text`).

## 1. Source

- `dw_decomp/text/<dir>/<name>.yaml`: 24 files, 50 blocks, 1240 strings. `text/example.yaml` documents the format and is skipped, since it isn't game text.
- Each file belongs to `src/<dir>/<name>.c`, which includes the generated `<text/<dir>/<name>.h>` (e.g. `src/main/item.c:24`). The generator (`tools/gen_text.py`) isn't part of the resource, so its rules below come from `example.yaml`'s comments and from how the C files use the generated macros.
- The binary a file belongs to comes from `config/us/<binary>.yaml`. `src/shop/script_menu.c` is linked into **main** (`config/us/main.yaml:132`); every other folder is its own binary.
- Releases come from `include/dw/version.h`: `jp`, `jp_trial`, `jp_bombom`, `us`, `jp_rev1`, `eu`. Their regions map to the YAML language keys: NTSCJ → `ja`, NTSCU → `en_us`, PAL → `en_eu`.

### File format

| Construct | Meaning (C side) |
|---|---|
| `BLOCK:` with language keys directly | one string `char BLOCK[]`, macro `BLOCK_TEXT` (`STR_IS_SICK` in `item.yaml`) |
| `BLOCK: strings: {ID: {...}}` | named strings `char ID[]`, all emitted by `BLOCK_TEXT` |
| `BLOCK: entries: [...]` | array `char *BLOCK[]` (`BLOCK_TEXT`) plus the named strings it points to (`BLOCK_STRINGS`). **The index is the array index the code uses** (`MOVE_NAMES[move]`, `battle_hud.c:388`) |
| entry `name:` | C name of the string. A list means one name per line (`lines` option) |
| entry without `name` | the same text as an earlier entry: the generator points both slots to one string |
| entry `NULL` | NULL pointer slot (end of `MOVE_NAMES`) |
| `ja`, `en_us`, `en_eu` | the text per language. `NULL` means the string does not exist in that release |
| `ja@jp`, `ja@jp_trial`, `ja@jp_bombom` | override for that one release (11 + 2 + 2 occurrences) |
| `storage: {default: embedded, eu: named}` | how strings are stored per release: named symbols, literals, or embedded in another table |
| `macro: DIGIMON_PARA_NAME` | embedding macro: `DIGIMON_PARA_NAME(STR_DIGIMON_NAME_AGUMON)` puts the text inside `DIGIMON_DATA` (`main.c:254`); the same for `ITEM_PARA_NAME` (`item.c:747`), `ITEM_MENU_LABEL` (`inventory.c:92`) and `STAT_LABEL` |
| `lines: {eu: 2}` | strings per entry in that release; missing lines point to `empty` (`ITEM_DESCS`: EU item descriptions are 2 lines) |
| `named: [eu]` | the entry is a named string in that release even where its block stores literals |

Scalars are always text (`en_us: 20`, `"Yes"`). Double-quoted strings use YAML escapes; only `\0` occurs (padding: `"Listens to #C1! #W\0\0…"`, `"BackOK\0"`).

## 2. Original usage

- **Lookup:** code indexes arrays by game id (`MOVE_NAMES[move]` in `BTL_appendMoveLearnedText`, `battle_hud.c:388`; `game_menu.c:equipMove`, `drawDigimonMovesText`; `main_menu.c:drawMoveName`) or uses named strings directly (`strcat(BTL_END_BOX_TEXTBUFFER, BTL_STR_LEARNED)`). Names embedded through a macro live inside their table's records (`DIGIMON_DATA[i].name`), so the Digimon / item converters will resolve `DIGIMON_PARA_NAME(STR_…)` to these records.
- **Encoding:** the original is Shift-JIS (the YAML is UTF-8). In **US**, strings mix ASCII and 2-byte SJIS: `drawString` (`font.c:1728`) turns each ASCII byte into a full-width glyph with `convertAsciiToJis` (`sjis.c:63`; `.` → 0x8142, `'` → 0x8175) and draws 2-byte codes as they are (`△ × □ ｛｝`, kana). Glyph width comes from the font data (`drawGlyph` returns `*p`, `font.c:1704`). In **JP / EU**, strings are 2-byte only (`drawString`, `font.c:1709`). EU glyphs are 8 or 12 px wide (`font.c:1611`), JP glyphs a fixed 12 px. The YAML writes EU text as ASCII and the generator stores it full-width (example.yaml: "en_eu: en_us text in full width").
- **Control codes** (battle-end box, `BTL_drawBattleEndText`, `battle_hud.c:393`):
  - US: `#C<c>` sets the colour (`setTextColor(<c>)`), `#R` breaks the line, `#W` breaks the line and waits `BATTLE_END_WAIT_FRAMES`, and an ASCII `'0'` ends the text (`battle_hud.c:442–466`).
  - JP / EU: single-byte `C<c>`, `R`, `W`, `0` placed between 2-byte glyphs (`battle_hud.c:405–425`). The YAML writes them bare in `ja` (`C1の命令を聞く…W`) and as `{C1}`, `{R}`, `{W}` in `en_eu`.
  - Found in the output: en_us `#C1` ×6, `#C7` ×7, `#R` ×9, `#W` ×5; en_eu `{C1}`, `{C7}`, `{R}`, `{W}` (`manifest.json` → `control_codes`).
- **Fixed-width layouts:** many menu strings are space-padded rows drawn as one text (`MENU_LABELS`: `"      Disc.      Life  Vir. HPMPnight"`, map names centred with spaces). The spaces are layout, so keep them.
- **Release-specific text in C:** a few strings are C literals for some releases instead of YAML text: `MAIN_D_801346B8` is `" is in"` in US and `"）は"` in JP (`main_menu.c:635/638`), and `STR_MONEY_HELD` is `"Ｂｉｔｓ"` in EU (`battle_ui.c:77`). The output records where these are defined (`c_definitions`), but not their text yet (see open questions).

## 3. Mapping

`output/text/<dir>/<name>.json`, one per YAML file (name = path without `text/` and `.yaml`), in the common table shape (`CLAUDE.md`).

- `records`: one block per YAML key, in file order: `block`, `line`, `kind` (`strings` / `entries` / `text`), `options` (as written), `c` (owning file, binary, macros, `placed_at` lines, `array` + US `symbol` for entries), `used_by` (references to the array), `count`, and `strings` or `entries`.
- String / entry: `index` (entries), `id` (first name, or null), `line`, `null_entry`, `text`, `variants`, `release_text`, `lines`, `line_ids`, `named`, `same_as`, `symbol`, `used_by`, `c_definitions`.
- **`variants` is lossless:** every language key exactly as written (null = `NULL`, missing key = not written; lists for multi-line entries).
- **`text`** is the value each language's main release uses, i.e. its newest build: `ja` → jp_rev1, `en_us` → us, `en_eu` → eu.
  - Lookup order for a release: `<lang>@<release>`, then `<lang>`, then (en_eu only) `en_us`.
  - The value is cut at the first NUL, as C would read it.
  - Multi-line entries are joined with `\n`, with trailing empty lines dropped; the padded lines stay in `lines`.
  - `release_text` lists the other releases where the text differs (e.g. `ja@jp` overrides).
- **`same_as`:** for each language, the earlier named entry in the block with the same text.
- **`used_by`:**
  - Every reference in `src/**/*.c` to the string's names, with the enclosing function, data initializer or `#define`, and the releases that compile the line (evaluated from `#if VERSION_…`; `unknown` lists releases that depend on macros like `__MWERKS__`).
  - A reference only counts in the binary that defines the name. Overlays may also reference main strings they don't define themselves.
  - `extern` declarations are skipped.
- `output/text/report.md`: a readable sheet with one table per block (id | ja | en_us | en_eu) and the control codes found.

## 4. Godot usage (planned)

- `GameData` (`scripts/data/game_data.gd`, not written yet) loads every `text/**.json` and builds an index id → string record.
  - `GameData.text(id, language = "en_us")` for named strings.
  - `GameData.text_entry("main/item", "MOVE_NAMES", move_id)` for arrays.
  - Tables like Digimon and items will carry their name's string id, resolved through the same index.
- The language setting picks one of `ja`, `en_us`, `en_eu`. `release_text` matters only to reproduce an older JP build.
- **Text renderer:** the Godot UI must interpret the control codes (§2) and map button glyphs (`△ × □`, `｛｝` = bits icon) to its own font or icons. US ASCII is drawn full-width by the original; a Godot font may draw it narrow.
- **Modding:** text can be changed freely. Keep the array length and indices of `entries` blocks (the code indexes them by game id), and keep the row widths of space-padded layout strings unless the UI that draws them is changed too.

## 5. Verification

The converter checks:

- the decomp exists, and every release maps to a language;
- each file parses (strict YAML subset: duplicate keys, unknown escapes, tabs and unsupported syntax are errors);
- the format is valid: known block and entry keys, `ja` and `en_us` present, `@release` suffixes name a release of that language, line lists fit the `lines` option, no more names than lines;
- the owning C file includes the generated header, and every block's macro (`_TEXT`, `_STRINGS` or the embedding macro) is placed in it;
- a C name has only one text per binary and release;
- every unnamed entry repeats an earlier named entry in every language where it exists;
- every string referenced by code exists (as YAML text, or as a C definition) in every release that compiles the reference. This check confirms the lookup order of §3, including the en_eu → en_us fallback.

Tests: `tests/test_textyaml.py`, `tests/test_cpp.py`, `tests/test_text.py` (synthetic decomp, plus a real-data test skipped when `dw_decomp` is missing).

## 6. Open questions

- **Generator not available:** the fallback (missing `en_eu` → `en_us`) and the "unnamed entry = earlier entry with the same text" rule are inferred from `example.yaml` and confirmed only by the checks above.
- **C-defined strings** (`MAIN_D_801346B8`, `STR_MONEY_HELD`): their text is not extracted yet. The C table parser should pick up `char X[] = "…";` literals.
- **`en_eu: "Help#NrFrAlAt"`** (`game_menu.yaml:22`): `#N` isn't one of the codes above; this is a menu row, so it may be drawn by a different routine. Not checked.
- **Other renderers:** `drawString2` (`script_textbox.c:644`, event dialogue), the kar/fish dialogue drawers and the HUD text of `renderString` may interpret more codes than the battle-end box. Check them when the UI is ported.
- **`ja` control letters:** bare `C`/`R`/`W` in `ja` text are codes only for renderers that parse them. Ordinary JP text uses full-width letters, so there are no clashes in practice. Not verified string by string.
- **`ja@jp`** overrides target the first JP release. The `ja` text is used by jp_trial, jp_bombom and jp_rev1 unless they have their own override.
