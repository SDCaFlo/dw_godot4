# Data porter progress

Update this file whenever a table or group changes status. Status values: `todo`, `investigating` (reading the decomp), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-22

## Groups

| Group | Status | Spec | Output | Notes |
|---|---|---|---|---|
| Text | done | `specs/text.md` | `output/text/` | 24 files, 50 blocks, 1240 strings, all languages (`ja`, `en_us`, `en_eu` + release overrides); 78/78 checks. Open: text of strings defined as C literals for some releases (`MAIN_D_801346B8`, `STR_MONEY_HELD`) comes with the C parser |
| Digimon | todo | `specs/digimon.md` | `output/digimon/` | `DIGIMON_DATA[180]` (names via `DIGIMON_PARA_NAME` → `text/main/main.json`), `RAISE_DATA` (`include/dw/partner.h`) |
| Evolution | todo | `specs/evolution.md` | `output/evolution/` | `EVOLUTION_REQS`, `EVOLUTION_PATHS`, `EVOLUTION_STATS_GAINS`, `EVOLUTION_ITEM_TARGET` |
| Moves | todo | `specs/moves.md` | `output/moves/` | `MOVE_DATA[122]` (`item.c:124`), names = `MOVE_NAMES` index (`text/main/item.json`), effect ids |
| Items & cards | todo | `specs/items.md` | `output/items/` | `ITEM_PARA[128]` (names via `ITEM_PARA_NAME`, descriptions `ITEM_DESCS`), `ITEM_FUNCTIONS`, `CARD_DATA[66]`, `CARD_PRICES`, shops |
| Systems | todo | `specs/systems.md` | `output/systems/` | `FLEE_CHANCES`, `HEALING_VALUES`, `BIRDRA_TRANSPORT_TARGETS`, tournaments, training, … (to be listed while investigating) |
| Constants & lookups | todo | — | — | Only when a system needs them (math tables, UI layouts, fonts) |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Package / CLI (`dwdata list`, `convert`) | done | Same pattern as `asset_porter/dwporter` |
| C initializer + constant parser | todo | Brace initializers, `#define`, `enum`, struct definitions, `#if VERSION_…` branches (`cpp.py` already evaluates the conditions); stdlib only |
| YAML text reader | done | `textyaml.py`, strict subset |
| Decomp index (releases, binaries, symbols, references) | done | `decomp.py`, `cpp.py`; scope detection is heuristic (column-0 braces) |
| Table writer (schema, records, `used_by`, `godot`) + `catalog.json` | done | `output.py` |
| Human reports | done (text) | `output/text/report.md`; future groups add their own |
| Unit tests | done (text) | 14 tests: reader, `#if` evaluator, text converter (synthetic + real data) |
| Godot `GameData` autoload | todo | `scripts/data/game_data.gd`, runtime loading + mod overrides; first user: text |

## Log

- 2026-10-22 — Skeleton and Text group done. `dwdata` package (CLI, `output.py`, `textyaml.py`, `cpp.py`, `decomp.py`), `groups/text.py`, `specs/text.md`, tests. `convert text`: 24 tables, 78/78 checks. Findings: `shop/script_menu.c` is linked into main; a few strings are C literals for some releases (recorded as `c_definitions`); no `INCLUDE_ASM` left in the decomp. Decisions: both porters stay stand-alone (cross-checks allowed); all languages kept.
- 2026-10-22 — Folder, `CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` created. Decision: values copied from the decomp (trusted source), output gitignored (game content), JSON as the master format for Godot and modding.
