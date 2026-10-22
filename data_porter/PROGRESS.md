# Data porter progress

Update this file whenever a table or group changes status. Status values: `todo`, `investigating` (reading the decomp), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-22

## Groups

| Group | Status | Spec | Output | Notes |
|---|---|---|---|---|
| Text | todo | `specs/text.md` | `output/text/` | `text/**/*.yaml` (`en_us`, also `ja`): names, descriptions, menus, battle shouts, tournaments, BGM names |
| Digimon | todo | `specs/digimon.md` | `output/digimon/` | `DIGIMON_DATA[180]`, `RAISE_DATA` (`include/dw/partner.h`) |
| Evolution | todo | `specs/evolution.md` | `output/evolution/` | `EVOLUTION_REQS`, `EVOLUTION_PATHS`, `EVOLUTION_STATS_GAINS`, `EVOLUTION_ITEM_TARGET` |
| Moves | todo | `specs/moves.md` | `output/moves/` | `MOVE_DATA[122]`, technique names, effect ids |
| Items & cards | todo | `specs/items.md` | `output/items/` | `ITEM_PARA[128]`, `ITEM_FUNCTIONS`, `CARD_DATA[66]`, `CARD_PRICES`, shops |
| Systems | todo | `specs/systems.md` | `output/systems/` | `FLEE_CHANCES`, `HEALING_VALUES`, `BIRDRA_TRANSPORT_TARGETS`, tournaments, training, … (to be listed while investigating) |
| Constants & lookups | todo | — | — | Only when a system needs them (math tables, UI layouts, fonts) |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Package / CLI (`dwdata list`, `convert`) | todo | Same pattern as `asset_porter/dwporter` |
| C initializer + constant parser | todo | Brace initializers, `#define`, `enum`, struct definitions; stdlib only |
| YAML text reader | todo | The decomp's `text/*.yaml` subset (blocks, `strings`, `entries`, `NULL`, variants) |
| Table writer (schema, records, `used_by`, `godot`) + `catalog.json` | todo | |
| Human reports | todo | Readable sheets (e.g. one card per Digimon) for `VERIFY.md` |
| Unit tests | todo | |
| Godot `GameData` autoload | todo | `scripts/data/game_data.gd`, runtime loading + mod overrides |

## Log

- 2026-10-22 — Folder, `CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` created. Decision: values copied from the decomp (trusted source), output gitignored (game content), JSON as the master format for Godot and modding.
