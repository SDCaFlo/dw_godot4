# Battle effects — `efe` (`ETCHI/EFEDAT.EFE`)

Format: `dwporter/formats/efe.py`. Family: `dwporter/families/efe.py` (`python -m dwporter convert efe`).

The visual (and sound) part of every battle technique: a small effect model (TMD) with its texture (TIM), UV animations, and a bytecode script run by the battle effect VM (`src/btl/battle_effect.c`; same engine copied in `std/std_effect.c` and `vs/vs_effect.c`).

## On disc

`ETCHI/EFEDAT.EFE`, `FILE_OFFSET_TABLE` (`file_table_us.c`) size `0x262000` = 122 slots of 10 sectors (`0x5000` bytes).

- `getEFEDATEntry(id)` (`src/main/efe.c:1043`): sector = file start + (id − 256) · 10. Effect id = technique id + 0x100 (`btl.c:476`: `DIGIMON_DATA[type].moves[...] + 0x100`), so **slot N = technique N** (`MOVE_NAMES[N]`, `text/main/item.yaml`).
- Slot 121 is all `0xCD` (unused build-tool fill; `MOVE_NAMES[121]` is NULL). Slot 110 holds a slightly different build of effect 344 (= slot 88): its header says 344, so a request for effect 366 fails the loader's id check (`isLoaded = -3`); it is a stale leftover.

### Slot

| Offset | Content |
|---|---|
| 0 | `EfeFileHeader` (13 × i32, 0x34 bytes): startScript, initScript, uvAnims, uvAnimsEnd, subEffects, tmdStart, tmdEnd, timStart, timEnd, dataEnd, unk28, numSubEffects, effectId. All offsets are relative to `base` = slot + 0x34 (`EFE_SCRIPT_HEAD`). |
| base + 0 | data area: effect instances and variables (`EfeInstance`, values addressed by scripts with scope 1) |
| base + first code | scripts (int16 bytecode) up to uvAnims |
| uvAnims … uvAnimsEnd | `EfeUvAnim` × TMD objects (32 bytes; reset at load) |
| subEffects | `EfeSubEffect` × numSubEffects (28 bytes; pointers, zeroed at load) |
| tmdStart … tmdEnd | TMD (empty when equal) |
| timStart … timEnd | TIM (empty when equal) |
| dataEnd … 0x5000 | rest of the slot |

### Loading (`BTL_setupLoadedEFEFile`, `battle_effect.c:1688`)

- TIM → free effect texture slot `i` (0–15): image at page `0x19 + i/8` (x = 576 + …, y = 256), y offset `(i % 8) · 32`; CLUT at `x = 128 + (i/4)·16`, `y = 488 + (i%4)·6` (the TIM's own VRAM position is ignored).
- TMD → `updateTMDTextureData(tmd, page, 0, offsetY, clutPage − 0x7A08)` (`graphics.c:156`): TSB page bits = page, CBA += delta, UV v += offsetY; for slot 0 (page 0x19, offset 0, CLUT (128, 488)) the delta is 0. The converter exports with slot 0.
- Then `initScript` runs (4 instructions per frame) and the effect id is registered; `BTL_startEFE` later runs `startScript`.

### Script VM (`BTL_runEFEScript`, `battle_effect.c:5341`)

Each instruction starts with an int16 word: low byte = opcode, high byte = flags. Operands are int16 words; code/data offsets are relative to `base`; "scope" 0 = the current effect instance, ≠ 0 = `base`. Value size from flags `(w >> 8) & 0xF`: 4 = int32, 2 = int16, else int8.

| Op | Name | Size | Operands / flags |
|---|---|---|---|
| 0 | LOAD_IMMEDIATE | 6 | value → register |
| 1 | LOAD_VARIABLE | 6 | offset, scope (size flag) |
| 2 | LOAD_RANDOM | 2 | rand() → register |
| 3 | LOAD_INDEXED | 10 | table, –, index offset, index scope (size flags: element `(w>>8)&0xF`, index `w>>12`) |
| 4 | VARIABLE_OPERATOR | 6 | offset, scope; size `(w>>8)&0xF`, operator `w>>12`: set, add, sub, mul, div, mod, shl, shr (with the register) |
| 5, 6, 8 | STOP | 2 | end of script |
| 7 | BRANCH_IF | 10 | offset, scope, target if false, –; compare `w>>12`: ==, !=, <, <=, >, >= against the register |
| 9 | JUMP | 4 | target |
| 10 | PUSH_IMMEDIATE | 6 | value |
| 11 | PUSH_VARIABLE | 6 | offset, scope (size flag) |
| 12 | PUSH_ADDRESS | 6 | offset, scope |
| 13 | CALL | 6 | target (returns after the 6 bytes) |
| 14 | BUILTIN | 2 | built-in id = `w >> 8` (97 functions, `BTL_EFE_SUB_OPCODES`: draw TMD, sprites, particles, flashes, sounds, hit checks, vector maths…), arguments popped from the data stack |
| 15 | RETURN | 2 | pop call stack (end when empty) |
| 16 | POP_TO_VARIABLE | 6 | offset, scope |
| 17 | SPAWN_SUB_EFFECT | 12 | count, instance table offset, –, stride, – ; continues after the 12 bytes in the new sub-effect |

Sub-effect scripts get their entry points from two `PUSH_ADDRESS` (scope 1) right before `BUILTIN 2` (`initializeSubEffectInstructions`); UV keyframe tables from the address pushed right before `BUILTIN 1` (`initializeUVAnim`: i32 count, then {i16 frames, i8 du, i8 dv}).

The disassembler follows the control flow from initScript, startScript, calls, branches, jumps and sub-effect entries; bytes in the script area it does not reach are reported as gaps (raw).

## Godot representation

`output/efe/<slot>_<technique>/`:

| File | Content |
|---|---|
| `effect.json` | identity (slot span), header, technique, sections, data area (raw hex), instructions (offset, op, name, flags, operands, raw), entry points, gaps (raw), UV anim records and keyframe tables, sub-effect records (raw), rest of the slot (raw) |
| `effect.txt` | readable script listing (human check) |
| `model.gltf` / `.bin` / `model_tex/` + `model.json` | the TMD, textured from the TIM placed in effect texture slot 0 (TMD sidecar as in `tmd_files`) |
| `texture.png` (+ `.pN.png`) + `texture.json` | the TIM (sidecar records the runtime placement) |

## Verification

- File size = 122 slots; header offsets ascending inside the slot (`uvAnims ≤ uvAnimsEnd ≤ subEffects ≤ tmdStart ≤ tmdEnd ≤ timStart ≤ timEnd = dataEnd ≤ 0x5000`); effect id = 256 + slot (except the known slot 110; slot 121 = fill).
- uvAnimsEnd − uvAnims = 32 · TMD objects; tmdStart − subEffects = 28 · numSubEffects.
- TMD parses and ends at tmdEnd; TIM parses and ends at timEnd; texture covered by the loaded TIM.
- Every traced instruction has a known opcode / built-in id; all jump targets inside the script area; gaps are small.

## Open questions

- `unk28` (values 3–7) is not read by the battle loader.
- Built-in argument counts (stack effects) are not decoded; the listing shows the stack pushes before each built-in.
- Sounds (`BUILTIN 28 playEFESound`) use the currently loaded VBALL/VLALL banks (`specs/sound.md`).
