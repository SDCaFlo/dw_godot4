# Asset porter progress

Update this file whenever a format or family changes status. Status values: `todo`, `investigating` (reading the decomp / scanning), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-21

## Formats (parsers / exporters)

| Format | Status | Code | Spec | Notes |
|---|---|---|---|---|
| TIM (texture) | done | `dwporter/formats/tim.py` | `specs/tim.md` | 4/8/16/24bpp, multi-palette, STP mask |
| PNG (export) | done | `dwporter/exporters/png.py` | — | Indexed, RGBA, grey; stdlib only |
| TMD (model) | todo | | | Reference: PSXPrev `TMDParser.cs`, `TMDHelper.cs` |
| glTF (export) | todo | | | Reference: PSXPrev `glTF2Exporter.cs` |
| MMD (Digimon models) | todo | | | Game-specific; compare with DW1ModelConverter. Textures come from `alltim`; polygons pick CLUT rows, patched by `updateTMDTextureData` |
| MAP / TFS (maps) | todo | | | Game-specific |
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
| | `DOOR/*.TMD`, other `*.TMD` | todo | | | | Needs TMD format |
| | `CHDAT/**/*.MMD` | todo | | | | 178 models; needs MMD format |
| | `MAP/**/*.MAP`, `*.TFS` | todo | | | | 242 maps |
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
| Digimon raise data | `RAISE_DATA` (`include/dw/partner.h`) | todo | |
| Items, moves, evolution tables | `dw_decomp/src/main/*.c` | todo | |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| CLI (`list`, `convert`, `scan`) | done | |
| Identity sidecars + `manifest.json` | done | `dwporter/assets.py` |
| Verification checks (fail = non-zero exit) | done | |
| Unit tests | done | `tests/test_tim.py`, 14 tests |
| Godot import of `output/` | todo | Decide `.gdignore` for `output/scan/`, and how Godot loads sidecars |

## Log

- 2026-10-21 — Core created (TIM, PNG, CLI, sidecars, scan). `card_all` done: 66 assets, 465/465 checks.
- 2026-10-21 — `alltim` done: 180 Digimon textures, 1083/1083 checks. Added `dwporter/data/digimon.py` (type → file name, display name, model path). Found the game overrides the TIM's VRAM position at load time.
- 2026-10-21 — `etctim` (9 assets, 41/41) and `stdtim` (6 assets, 28/28) done with shared `stacked_tim.py`. Unlike ALLTIM, these load at their header VRAM positions; users matched via `GetTPage`/`GetClut` constants (7 of 15 so far).
- 2026-10-21 — `tim_files` done: all 51 standalone TIMs (54 assets, 271/271), loaders and path tables (`STD_GRADES`, arena tables) recorded. Found ETCTIM.BIN = 9 ETCDAT TIMs concatenated; `etctim` entries renamed after them (49/49). All TIM data on the disc outside maps/models is now converted.
