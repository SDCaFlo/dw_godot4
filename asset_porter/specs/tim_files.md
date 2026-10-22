# tim_files — standalone `.TIM` files

All 51 `*.TIM` files on the disc except `CHDAT/ALLTIM.TIM` (see `alltim.md`). Converter: `dwporter/families/tim_files.py` (`python -m dwporter convert tim_files`); the per-file table (`FILES`) holds description, loader, code references, TIM count, embedded copies and path-table index.

## On disc

| Folder | Files |
|---|---|
| `ETCDAT/` | `BI_IN`, `BTLCOMND`, `DEFEFF`, `EX`, `FEEL_EF`, `FISHING`, `FISHING2`, `FI_INFO`, `ITEM`, `SBOY`, `SLOT`, `SPOT256`, `SYSTEM_W`, `TAMA` |
| `ETCHI/` | `LIFE`, `OP` |
| `ETCNA/` | `IWA1`, `TAKA`, `TITLE2`, `TITLE256` |
| `STDDAT/` | `16TAISEN`, `B_TOGI`, `E_TOGI`, `T_TOGI`, `TAISEN1`, `TAISEN2`, `TAISEN_F`, `TIME` |
| `STDDAT/GRADE/` | 23 tournament title cards (`GRADEA`–`GRADES`, `CAPV1`–`CAPVO`, `FR`, `GP`, ...) |

- Every file is one TIM, except `STDDAT/T_TOGI.TIM` = 4 TIMs back to back (packed like `stacked_tim.md`). Sizes match `FILE_OFFSET_TABLE`; no trailing data.
- 9 `ETCDAT` files are also embedded, byte for byte, in `ETCDAT/ETCTIM.BIN` (`also_in`).
- See `tim.md` for the TIM format.

## Original handling

All loaders upload at the TIM header position, so `vram` in the sidecar is the real placement.

| Loader | Where | Files |
|---|---|---|
| `loadTIMFile(path, buf)` | `dw_decomp/src/main/file.c:98` | `FI_INFO`, `SBOY`, `SYSTEM_W`, `TITLE2`, `TITLE256`, `16TAISEN`, `TAISEN1/2/_F`, `TIME`, `GRADE/*` |
| `loadTextureFile(path, &tpage, &clut)` | `dw_decomp/src/main/file.c:53` (also returns `GetTPage`/`GetClut` of the header position) | `LIFE` (`murd.c:778`), `OP` (`script_interp.c:1849`), `IWA1` (`map_object.c:624`) |
| `STD_loadArenaTIMToVRAM(path, count)` / `VS_loadArenaTIMToVRAM` | `dw_decomp/src/std/std_setup.c:618`, counts `STD_ARENA_COUNTS.timCount = {4, 1}` (`std_setup.c:132`), `VS_ARENA_TIM_COUNTS = {4, 1, 1}` (`vs_scene.c:166`) | `T_TOGI` (4), `B_TOGI` (1), `E_TOGI` (1, VS only) |
| Inline `readFile` + `LoadImage` | `dw_decomp/src/dooa/dooa.c:536` | `TAMA` (eggs) |
| Fishing overlay path table | `dw_decomp/src/fish/fish.c:911`, `:930` | `FISHING`, `FISHING2` (same VRAM, alternatives) |
| `loadStackedTIMFile` via `ETCTIM.BIN` only | — | `BI_IN`, `BTLCOMND`, `DEFEFF`, `FEEL_EF`, `ITEM`, `SPOT256` |
| `EFEX_PATH_ARRAY` (table populated, never read, per decomp comment) | `dw_decomp/src/main/efe_table.c:9` | `EX` |
| None found | — | `SLOT` (slot machine symbols), `TAKA` (chest texture; `TAKA.TMD` is `CHEST_TMD`, `map_object.c:77`) |

Path tables (`table` in metadata):

- `STD_GRADES[23]` (`dw_decomp/src/std/std_setup.c:210`), loaded with `loadTIMFile(STD_GRADES[arg[0]])` at `std_setup.c:269`: index = tournament id. Order: `GRADED, GRADEC, GRADEB, GRADEA, GRADES, GRADER, CAPV1, CAPV2, CAPV3, CAPV4, CAPVO, FR, GP, TW, CO, NT, MT, DT, DY, WI, AN, HU, BT`.
- `STD_ARENA_TIMS` / `VS_ARENA_TIMS`: index = arena / stage (`T_TOGI` 0, `B_TOGI` 1, `E_TOGI` 2).

## Godot representation

- `output/tim_files/<FOLDER>/<NAME>.png` (+ `.p<N>.png` per extra palette); multi-TIM files get `_<NN>`: `output/tim_files/STDDAT/T_TOGI_00.png` … `_03`.
- Port mapping:
  - `loadTIMFile(PATH)` / `loadTextureFile(PATH)` → texture `<FOLDER>/<NAME>`.
  - `STD_GRADES[id]` → `STDDAT/GRADE/<STD_GRADES order[id]>`.
  - Arena `id` → `STDDAT/<arena>_NN` textures.
- `ETCDAT` files embedded in `ETCTIM.BIN` are exported in both families; pick either (identical pixels and VRAM). Their `also_in` field links them.

## Metadata

Sidecar: common keys + `tim`, `vram`, and

```json
"file": {"description": "...", "loader": "loadTIMFile", "code_refs": ["..."], "identified_by": "code",
         "tim_index": 0, "tim_count": 1, "also_in": null, "table": {"name": "STD_GRADES", "index": 3}}
```

## Verification (run on every conversion)

- Every standalone `.TIM` on disc (outside `CHDAT`) is listed in `FILES`, and vice versa.
- Per file: size equals the table size, expected TIM count, each TIM valid and packed, rest of file zero.
- `also_in` copies are byte-identical.

Current result: 54 assets from 51 files, 271/271 checks.

## Open questions

- `SLOT.TIM` and `TAKA.TIM` have no loader in the decomp; `TAKA` is probably referenced through `TAKA.TMD` (check when the TMD format is done). `SLOT` may belong to a not-yet-decompiled overlay or be unused.
- `EX.TIM` is only listed in the unused `EFEX_PATH_ARRAY`.
- `OP.TIM` usage (script command at `script_interp.c:1849`) is not mapped to a specific scene yet.
- Tournament names for each `STD_GRADES` index are not resolved yet.
