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
| MMD (Digimon models) | todo | | | Game-specific; compare with DW1ModelConverter |
| MAP / TFS (maps) | todo | | | Game-specific |
| EFE, ATR, SCN | todo | | | Game-specific |
| VHB (sound banks) | todo | | | Game-specific |
| STR (FMV) | blocked | | | Dump is missing data; re-dump in raw mode first |

## Families (disc files)

| Family | Source | Status | Assets | Checks | Spec | Notes |
|---|---|---|---|---|---|---|
| `card_all` | `CARD/CARD.ALL` | done | 66 | 465/465 | `specs/card_all.md` | 66 card images, 0x7000-byte slots |
| | `CHDAT/ALLTIM.TIM` | todo | | | | 180 stacked TIMs (scan) |
| | `ETCDAT/ETCTIM.BIN` | todo | | | | 9 TIMs (scan) |
| | `STDDAT/STDTIM.BIN` | todo | | | | 6 TIMs (scan) |
| | `*.TIM` (ETCDAT, ETCHI, ETCNA, STDDAT, GRADE) | todo | | | | Standalone TIMs; need a family per use or a generic one |
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
| Digimon raise data | `RAISE_DATA` (`include/dw/partner.h`) | todo | |
| Items, moves, evolution tables | `dw_decomp/src/main/*.c` | todo | |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| CLI (`list`, `convert`, `scan`) | done | |
| Identity sidecars + `manifest.json` | done | `dwporter/assets.py` |
| Verification checks (fail = non-zero exit) | done | |
| Unit tests | done | `tests/test_tim.py`, 8 tests |
| Godot import of `output/` | todo | Decide `.gdignore` for `output/scan/`, and how Godot loads sidecars |

## Log

- 2026-10-21 — Core created (TIM, PNG, CLI, sidecars, scan). `card_all` done: 66 assets, 465/465 checks.
