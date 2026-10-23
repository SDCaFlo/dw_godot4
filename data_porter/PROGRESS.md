# Data porter progress

Update this file whenever a table or group changes status. Status values: `todo`, `investigating` (reading the decomp), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-22

## Groups

| Group | Status | Spec | Output | Notes |
|---|---|---|---|---|
| Text | done | `specs/text.md` | `output/text/` | 24 files, 50 blocks, 1240 strings, all languages (`ja`, `en_us`, `en_eu` + release overrides); 79/79 checks. Strings that some releases define as C literals (`MAIN_D_801346B8`, `STR_MONEY_HELD`) are read with the C reader (`c_text`) |
| Moves | done | `specs/moves.md` | `output/moves/` | `MOVE_DATA[122]`, `TYPE_FACTORS[7][7]`, `MOVE_LEARN_CHANCES[58][3]` (`item.c`), names from `MOVE_NAMES`; 24/24 checks. Only release difference: Full Potential `unk3` in jp. Open: range 2 vs 3 (effect data), ids 0x71–0x79 |
| Digimon | todo | `specs/digimon.md` | `output/digimon/` | `DIGIMON_DATA[180]` (`main.c:254`; names via `DIGIMON_PARA_NAME` → `text/main/main.json`; the `name` field doesn't exist in EU, `params.h:19`), `RAISE_DATA` (`include/dw/partner.h`). The C reader already lays it out with a macro hook |
| Evolution | todo | `specs/evolution.md` | `output/evolution/` | `EVOLUTION_REQS`, `EVOLUTION_PATHS`, `EVOLUTION_STATS_GAINS`, `EVOLUTION_ITEM_TARGET`; evolution teaches the weakest technique of the element block (`evl.c:1418`, see `specs/moves.md`) |
| Items & cards | todo | `specs/items.md` | `output/items/` | `ITEM_PARA[128]` (names via `ITEM_PARA_NAME`, descriptions `ITEM_DESCS`), `ITEM_FUNCTIONS`, `CARD_DATA[66]`, `CARD_PRICES`, shops |
| Systems | todo | `specs/systems.md` | `output/systems/` | `FLEE_CHANCES`, `HEALING_VALUES`, `BIRDRA_TRANSPORT_TARGETS`, tournaments, training, … (to be listed while investigating) |
| Constants & lookups | todo | — | — | Only when a system needs them (math tables, UI layouts, fonts) |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Package / CLI (`dwdata list`, `convert`) | done | Same pattern as `asset_porter/dwporter` |
| C initializer + constant parser | done | `cdata.py`: structs / typedefs / enums / object-like `#define`s, initializers per release (brace elision, designators, zero fill, width conversion), string literals, macro hooks, `sizeof`. Not yet: function-pointer tables (`ITEM_FUNCTIONS`), function-like `#define` expansion, bit-field layout, PSY-Q `Gs*` types |
| YAML text reader | done | `textyaml.py`, strict subset |
| Decomp index (releases, binaries, symbols, references) | done | `decomp.py`, `cpp.py`; scope detection is heuristic (column-0 braces) |
| Table writer (schema, records, `used_by`, `godot`) + `catalog.json` | done | `output.py` |
| Human reports | done (text, moves) | `output/<group>/report.md`; future groups add their own |
| Unit tests | done (text, moves) | 21 tests: YAML reader, `#if` evaluator, C reader, text and moves converters (synthetic + real data) |
| Godot `GameData` autoload | todo | `scripts/data/game_data.gd`, runtime loading + mod overrides; first user: text |

## Log

- 2026-10-22 — C reader and Moves group done. `cdata.py` reads tables per release on their C types. It also reads DIGIMON_DATA and ITEM_PARA, with a hook for the name macros. `groups/moves.py` (3 tables, 24/24 checks), `specs/moves.md`. Text now reads the C-literal strings (79/79). Findings: the id ranges the code tests (techniques 0x00–0x39, finishers 0x3a–0x70, Counter 0x2d, generic 0x79); `unk3` = 2 flags (needs target, shared 110-tick cooldown); the evolution element blocks confirm the element ids. Decision: records hold US values, other releases as `release_values`.
- 2026-10-22 — Skeleton and Text group done. `dwdata` package (CLI, `output.py`, `textyaml.py`, `cpp.py`, `decomp.py`), `groups/text.py`, `specs/text.md`, tests. `convert text`: 24 tables, 78/78 checks. Findings: `shop/script_menu.c` is linked into main; a few strings are C literals for some releases (recorded as `c_definitions`); no `INCLUDE_ASM` left in the decomp. Decisions: both porters stay stand-alone (cross-checks allowed); all languages kept.
- 2026-10-22 — Folder, `CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` created. Decision: values copied from the decomp (trusted source), output gitignored (game content), JSON as the master format for Godot and modding.
