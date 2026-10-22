# Event scripts — `scripts` (`SCN/MAPHEAD.SCN`, `SCN/DG.SCN`)

Format: `dwporter/formats/scn.py`. Family: `dwporter/families/scripts.py` (`python -m dwporter convert scripts`).

The SCN files hold the bytecode of the game's script interpreter: map setup (music, NPCs), dialogue, choices, cutscene movement, shops, item/money/stat changes, triggers, warps, battles. Opcodes and their arguments are documented in `dw_decomp/include/dw/script.h`; this spec adds what the files look like and what the converter checks.

## On disc

| File | `FILE_OFFSET_TABLE` (`file_table_us.c`) | Content |
|---|---|---|
| `SCN/MAPHEAD.SCN` | line 755, size `0x606E` | one script: section N = setup of map N |
| `SCN/DG.SCN` | line 754, size `0xC4800` | 0x800-byte offset table + 222 scripts, each padded to a 0x800 sector |

### DG.SCN

- `u32 offsets[]` at 0: script `i` = bytes `[offsets[i], offsets[i + 1])`. `offsets[0] = 0x800` (the table is one sector, 512 entries); 223 entries are used (222 scripts + end = file size); the rest of the sector is build-tool leftovers (zeros and 36 source names such as `\SCN\MAP133.SCN`), kept as raw hex.
- Script 0 is a copy of MAPHEAD.SCN plus padding; the game never reads it (`getScript(0)` returns the MAPHEAD buffer).
- Each script is followed by padding up to its sector end. The padding is leftover bytes from the tool that built the file (mostly copies of the start of the script), never executed. It is kept as raw bytes.

### Script

| Offset | Content |
|---|---|
| 0 | `u16 code_start` (= end of the section table) |
| 2 | section table: `u16 id, u16 offset` pairs, ended by `u16 0xFFFF` |
| code_start | instructions until `END_SCRIPT` (0xFF + alignment byte) |

`getScriptSection` (`script_interp.c:671`) looks up a section by id. Instruction offsets (jumps, selections, switch tables, IF jumps) are relative to the start of the script.

### Instructions

One opcode byte, then the arguments of `script.h` (`_` = padding byte). 16-bit values are 2-byte aligned (MIPS `lhu`), which is why so many opcodes have a padding byte. Variable-length instructions:

| Opcode | Layout |
|---|---|
| `0x10 SET_SELECTION` | `u8 count, u16 targets[count]`, then an embedded `0x1A, _` and a text (the choices, one per line). `scriptShowSelection` (`script_textbox.c:1017`) skips `(count + 1) * 2` bytes to reach the text; the extra `+2` after the text is a runtime pointer skip, not data. |
| `0x18 SWITCH` | `u8 pstat, u16 count, u16 offsets[count]` |
| `0x19 IF` | `_`, then conditions (below), ended by `0x19, _` |
| `0x1A SHOW_TEXTBOX` | `_`, text |
| `0x6B DATA` | `_`, bytes until and including `0xFF`; not executed (the interpreter's case is empty), read as data. The next instruction may start at an odd offset. |
| `0xFE END_SECTION`, `0xFF END_SCRIPT` and the unused `0x11`, `0x12`, `0xFC`, `0xFD` | opcode + one alignment byte |

IF conditions (`scriptIfInstruction`, `script_interp.c:907`), each `u8 op, _, args`. `op & 0x38` = kind, `op & 7` = comparison or sub-kind, `op & 0x80` = AND with the previous result, `op & 0x40` = OR, else replace:

| Kind | Args | Meaning |
|---|---|---|
| 0x00 | `u16 trigger` | trigger set (`op & 7 == 0`) / not set |
| 0x08 | `u8 pstat, u8 value` | compare pstat with value |
| 0x10 | `u16 offset` | jump if the result is true |
| 0x18 | `u16 offset` | jump if the result is false |
| 0x20 + 0 | `u8 stat, u8 cmp, u16 value` (s16 for stat 9) | partner stat |
| 0x20 + 1 | `u8 card, u8 cmp, u16 value` | card count |
| 0x20 + 2 | `u8 move, u8 negate` | knows move |
| 0x20 + 3 | `u8 mask, u8 negate` | partner condition |
| 0x20 + 4 | `u8 item, u8 cmp, u16 value` | item count |
| 0x20 + 5 | `_, u8 cmp, u32 value` | money |

Comparisons: 0 `==`, 1 `!=`, 2 `>=`, 3 `<=`, 4 `>`, 5 `<` (`scriptCompareValue`).

### Text

`showTextbox` (`script_textbox.c:1054`) reads 2-byte units: a Shift-JIS character (the US text is full-width Shift-JIS, e.g. `82 76` = "Ｗ") or a control code + one byte:

| Code | Meaning |
|---|---|
| `01 c` | text colour c |
| `02 x` | ignored by the renderer |
| `03 a b c` | 4 bytes, skipped by the renderer |
| `04 p` | number in pstat p |
| `05 _` / `06 _` | tamer / partner name |
| `07 p` / `08 p` / `09 p` | Digimon / move / item name from pstat p |
| `0A _` / `0B _` / `10 _` | money / merit / shop value |
| `11 p` / `12 p` | BGM / tournament name from pstat p |
| `13 _` / `14 _` / `15 _` | tournaments won / tournament wins / tournaments lost |
| `0C _` / `0E _` | tab to the next 8 / 11 columns (`drawString2`) |
| `16 _`–`1C _` | fixed tab stops (US `drawString2`) |
| `0D _` | end of line; if followed by `00 _` the text ends (the `00 _` pair is consumed) |

Dialogue owner (`SET_DIALOG_OWNER`, speaker ids): `0xFD` tamer, `0xFC` partner, `0xC8`+ special speakers (`text/main/script_value.yaml` `SPEAKERS`: Sign, Box, Betamon, Coelamon, Tanemon, Palmon), `< 0xC8` the NPC with that script id.

## Original handling

- `initializeScripts` (`script_interp.c:2190`): MAPHEAD.SCN → `MAPHEAD_SCRIPT_BUFFER` (0x61A8 bytes); the first 0x2000 bytes of DG.SCN → `SCRIPT_OFFSET_TABLE`.
- `getScript(id)` (`script_interp.c:647`): id 0 = MAPHEAD; otherwise reads `[table[id], table[id + 1])` of DG.SCN into `MAP_SCRIPT_BUFFER` (0x4000 bytes).
- `runMapHeadScript(map)` → `callScriptSection(0, map, 1)`: MAPHEAD section = map id. Each starts with `SET_SCRIPT (0xFB) script, map`, which sets `CURRENT_SCRIPT_ID` (DG script) and loads the map. The converter derives map → script from these instructions (not assumed).
- `callScriptSection(CURRENT_SCRIPT_ID, section, …)` from `tamer.c:checkMapInteraction`: trigger cells 51–79 (on enter) and 80–109 (on confirm) run the section with that id; talking to an NPC runs the section = its script id (`NPC_ENTITIES[i].scriptId`, from `SET_DIGIMON`). MAPHEAD also has global sections (e.g. 0x4DA–0x4E4 for tournaments, item use, death).
- `tickScript` (`script_interp.c:390`) dispatches by opcode range; waiting instructions (textbox, delay, movement, routines) park in `ACTIVE_INSTRUCTION`.

## Godot representation

`output/scripts/`:

| File | Content |
|---|---|
| `MAPHEAD/script.json`, `DG/script_<id>.json` | one script: identity (source span), header, sections, instructions (`offset`, `op`, `name`, named `args`, `raw` hex; texts as tokens + display string), padding (raw hex), map links |
| `MAPHEAD/script.txt`, `DG/script_<id>.txt` | readable listing (human check) |
| `index.json` | DG offset table (raw), map id → MAPHEAD section → DG script, per-script summary (sections, instruction and text counts) |
| `manifest.json` | checks, code refs |

A Godot script interpreter can run the JSON directly: jumps are script offsets (build an offset → instruction index map); `raw` keeps the exact bytes.

## Metadata

- Per script JSON: `asset_id` (`SCN/DG.SCN@0x<offset>` or `SCN/MAPHEAD.SCN@0x0`), `source` (span = the script's bytes including its sector padding, sha1 of span and file), `script_id`, `maps` (MAPHEAD sections that select this script), `header` (`code_start`, `table_end`, sections), `instructions` (each with `offset`, `size`, `raw` hex; `nonzero_pads` only when an alignment byte is not zero), `padding` (offset, size, raw hex). Header bytes + instruction `raw` + padding rebuild the span exactly.
- `index.json`: the used DG table entries, the rest of the table sector as raw hex (`padding_hex`, with the leftover `\SCN\MAPnnn.SCN` names it contains), map links, per-script summary.

## Verification

- File sizes match the file table; DG table monotonic, sector-aligned, ends at the file size, unused entries zero; every DG script fits `MAP_SCRIPT_BUFFER` (0x4000), MAPHEAD fits its buffer.
- DG script 0 starts with MAPHEAD.SCN byte for byte.
- Every script: `code_start` = end of the section table; disassembles to `END_SCRIPT` with no unknown opcode; header + instruction bytes + padding = the script bytes (lossless round trip).
- Every section, jump, selection, switch and IF target lands on an instruction start of the same script; every `JUMP_TO_FILE*` target (script, section) and `SET_SCRIPT` script exists.
- Padding bytes (`_`) inside instructions are zero (count reported); every text decodes as Shift-JIS.

## Open questions

- Control code `03` (3 data bytes) and `02` are skipped by `drawString2`; their meaning in the text-reveal code is not checked.
- What reads `DATA` (0x6B) blocks is not traced yet (they look like id lists).
- `SET_SELECTION`'s runtime `+2` skip points `DIALOGUE_SELECTION.endPointer` two bytes into the next instruction; only used when a selection is cancelled.
