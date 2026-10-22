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
| `etctim` | `ETCDAT/ETCTIM.BIN` | done | 9 | 41/41 | `specs/stacked_tim.md` | Packed TIMs at their header VRAM positions; 3/9 users found in code; entry 6 = `ITEM.TIM` |
| `stdtim` | `STDDAT/STDTIM.BIN` | done | 6 | 28/28 | `specs/stacked_tim.md` | Tournament graphics; 4/6 users found in code |
| | `*.TIM` (ETCDAT, ETCHI, ETCNA, STDDAT, GRADE) | todo | | | | Standalone TIMs; need a family per use or a generic one. `ITEM.TIM` duplicates `etctim` entry 6 |
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
| Unit tests | done | `tests/test_tim.py`, 13 tests |
| Godot import of `output/` | todo | Decide `.gdignore` for `output/scan/`, and how Godot loads sidecars |

## Log

- 2026-10-21 — Core created (TIM, PNG, CLI, sidecars, scan). `card_all` done: 66 assets, 465/465 checks.
- 2026-10-21 — `alltim` done: 180 Digimon textures, 1083/1083 checks. Added `dwporter/data/digimon.py` (type → file name, display name, model path). Found the game overrides the TIM's VRAM position at load time.
- 2026-10-21 — `etctim` (9 assets, 41/41) and `stdtim` (6 assets, 28/28) done with shared `stacked_tim.py`. Unlike ALLTIM, these load at their header VRAM positions; users matched via `GetTPage`/`GetClut` constants (7 of 15 so far).
