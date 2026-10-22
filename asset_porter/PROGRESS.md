# Asset porter progress

Update this file whenever a format or family changes status. Status values: `todo`, `investigating` (reading the decomp / scanning), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-21

## Formats (parsers / exporters)

| Format | Status | Code | Spec | Notes |
|---|---|---|---|---|
| TIM (texture) | done | `dwporter/formats/tim.py` | `specs/tim.md` | 4/8/16/24bpp, multi-palette, STP mask |
| PNG (export) | done | `dwporter/exporters/png.py` | — | Indexed, RGBA, grey; stdlib only |
| TMD (model) | done | `dwporter/formats/tmd.py` | `specs/tmd.md` | Layout checked against `ilen` for every packet; all 66 files parse |
| glTF (export) | done | `dwporter/exporters/gltf.py`, `dwporter/models.py` | `specs/tmd.md` | Axis flip, winding, nearest-filtered texture pages, PSX data in `extras` |
| VRAM simulation | done | `dwporter/formats/vram.py` | `specs/tmd.md` | Builds textures like the GPU (page + CLUT) from the TIMs the game has loaded |
| MMD (Digimon models + animations) | done | `dwporter/formats/mmd.py`, `dwporter/models.py` | `specs/mmd.md` | TMD + animation table; exact port of the game's momentum animation (20 fps); RotMatrix order decoded from libgte asm |
| MAP / TFS (maps) | done | `dwporter/formats/map.py` | `specs/map.md` | Pre-rendered backgrounds + 3D camera (projection verified), collision, objects, entities, doors |
| EFE, ATR, SCN | todo | | | Game-specific |
| VHB (sound banks) | todo | | | Game-specific |
| STR (FMV) | blocked | | | Dump is missing data; re-dump in raw mode first |

## Families (disc files)

| Family | Source | Status | Assets | Checks | Spec | Notes |
|---|---|---|---|---|---|---|
| `card_all` | `CARD/CARD.ALL` | done | 66 | 465/465 | `specs/card_all.md` | 66 card images, 0x7000-byte slots |
| `alltim` | `CHDAT/ALLTIM.TIM` | done | 180 | 1083/1083 | `specs/alltim.md` | One texture per digimon type, 0x4800-byte slots; palettes are per polygon; types 62/114 have no model |
| `etctim` | `ETCDAT/ETCTIM.BIN` | done | 9 | 49/49 | `specs/stacked_tim.md` | = 9 ETCDAT `.TIM` files concatenated (entries named after them); 3/9 drawers found in code |
| `stdtim` | `STDDAT/STDTIM.BIN` | done | 6 | 28/28 | `specs/stacked_tim.md` | Tournament graphics; 4/6 users found in code |
| `tim_files` | 51 standalone `*.TIM` (ETCDAT, ETCHI, ETCNA, STDDAT, GRADE) | done | 54 | 271/271 | `specs/tim_files.md` | Loader + code refs per file; T_TOGI has 4 TIMs; 9 ETCDAT files are also inside ETCTIM.BIN; SLOT/TAKA/EX have no loader |
| `tmd_files` | 66 `*.TMD` (DOOR, ETCDAT, ETCHI, ETCNA, STDDAT) | done | 66 | 221/221 | `specs/tmd.md` | glTF + texture pages; 22 field/effect/arena/result models textured, 1 untextured, 43 use map textures (bound when maps are done) |
| `mmd_files` | 178 `CHDAT/MMD*/*.MMD` | done | 178 | 1071/1071 | `specs/mmd.md` | Rigid bone hierarchy, 4,843 animations (loops, sounds, texture moves as events), textures from the ALLTIM slot; matches DW1ModelConverter within 1 unit / <1° |
| `maps` | 241 `MAP/MAP*/*.MAP` + `.TFS` | done | 241 | 1252/1252 | `specs/map.md` | Backgrounds per time of day, sprites, textured doors, `overview.png` for human checks; GIAS06B/ICSA05 sprites need VRAM loaded by events |
| | `ETCHI/EFEDAT.EFE` | todo | | | | Effects |
| | `STDDAT/*.ATR` | todo | | | | |
| | `SCN/*.SCN` | todo | | | | |
| | `SOUND/VHB/*.VHB` | todo | | | | |
| | `MMM.DAT` | todo | | | | 27 MB, unknown |
| | `MOVIE/*.STR` | blocked | | | | See STR above |
| | `*_REL.BIN`, `SLUS_010.32` | — | | | | Code; data tables come from the decomp, not converted here |

## Game data from the decomp (not disc files)

| Data | Source | Status | Notes |
|---|---|---|---|
| Text / strings | `dw_decomp/text/**/*.yaml` | todo | `en_us` |
| Digimon type table (file + display names) | `PTR_DIGIMON_FILE_NAMES`, `DIGIMON_NAMES` | done | `dwporter/data/digimon.py`, generated from the decomp |
| Skeletons, bone counts, radius/height | `DIGIMON_SKELETONS`, `DIGIMON_DATA` | done | `dwporter/data/skeletons.py`, generated from the decomp, verified against `SLUS_010.32` |
| Digimon raise data | `RAISE_DATA` (`include/dw/partner.h`) | todo | |
| Items, moves, evolution tables | `dw_decomp/src/main/*.c` | todo | |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| CLI (`list`, `convert`, `scan`) | done | |
| Identity sidecars + `manifest.json` | done | `dwporter/assets.py` |
| Verification checks (fail = non-zero exit) | done | |
| Unit tests | done | `tests/test_tim.py`, 27 tests |
| Human verification guide | done | `VERIFY.md` |
| Godot import of `output/` | todo | Decide `.gdignore` for `output/scan/`, and how Godot loads sidecars |

## Log

- 2026-10-21 — Core created (TIM, PNG, CLI, sidecars, scan). `card_all` done: 66 assets, 465/465 checks.
- 2026-10-21 — `alltim` done: 180 Digimon textures, 1083/1083 checks. Added `dwporter/data/digimon.py` (type → file name, display name, model path). Found the game overrides the TIM's VRAM position at load time.
- 2026-10-21 — `etctim` (9 assets, 41/41) and `stdtim` (6 assets, 28/28) done with shared `stacked_tim.py`. Unlike ALLTIM, these load at their header VRAM positions; users matched via `GetTPage`/`GetClut` constants (7 of 15 so far).
- 2026-10-21 — `tim_files` done: all 51 standalone TIMs (54 assets, 271/271), loaders and path tables (`STD_GRADES`, arena tables) recorded. Found ETCTIM.BIN = 9 ETCDAT TIMs concatenated; `etctim` entries renamed after them (49/49). All TIM data on the disc outside maps/models is now converted.
- 2026-10-22 — TMD parser, glTF exporter and VRAM simulation done. `tmd_files`: all 66 TMDs (221/221). Texture bindings from code + UV coverage; 43 models (doors, map props) wait for map textures. Winding verified against stored normals.
- 2026-10-22 — `mmd_files` done: 178 Digimon models with skeletons and 4,843 animations (1071/1071). Animation = exact port of anim.c; RotMatrix = Rx·Ry·Rz confirmed from the libgte assembly; cross-checked against DW1ModelConverter. Output JSON made compact (all families, 477 MB → 163 MB for MMD).
- 2026-10-22 — MMD glTF now declares a skin (all bones as joints): animations were wrong in Blender as a plain node hierarchy; fixed and confirmed by the user. Verified in Godot 4.4.1 headless: poses match the data, no stale bones when switching animations.
- 2026-10-22 — `maps` done: 241 field maps (MAP_ENTRIES/DOOR_MAPDATA/TOILET_DATA read from the executable). Camera projection derived from GsSetRefView2 and verified by projecting collision onto backgrounds. Doors textured per map. Added VERIFY.md (human checks).
- 2026-10-22 — First consumer in Godot: `scenes/field/field.tscn` loads maps + the tamer from `output/` at runtime (`asset_porter/.gdignore` keeps the editor from importing it). Camera projection matches `map.json` to <0.001 px; root motion, collision and warps (110–119) work on real maps.
