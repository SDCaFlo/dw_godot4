# Data porter progress

Update this file whenever a table or group changes status. Status values: `todo`, `investigating` (reading the decomp), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-22

## Groups

| Group | Status | Spec | Output | Notes |
|---|---|---|---|---|
| Text | done | `specs/text.md` | `output/text/` | 24 files, 50 blocks, 1240 strings, all languages (`ja`, `en_us`, `en_eu` + release overrides); 79/79 checks. Strings that some releases define as C literals (`MAIN_D_801346B8`, `STR_MONEY_HELD`) are read with the C reader (`c_text`) |
| Moves | done | `specs/moves.md` | `output/moves/` | `MOVE_DATA[122]`, `TYPE_FACTORS[7][7]`, `MOVE_LEARN_CHANCES[58][3]` (`item.c`), names from `MOVE_NAMES`; 24/24 checks. Only release difference: Full Potential `unk3` in jp. Open: range 2 vs 3 (effect data), ids 0x71–0x79 |
| Digimon | done | `specs/digimon.md` | `output/digimon/` | `DIGIMON_DATA[180]`, `RAISE_DATA[66]`, `SLEEP_PATTERN[8]`, `ITEM_TAKE_DISTANCE[66]`, `PTR_DIGIMON_FILE_NAMES[180]`, VBALL / VLALL sound ids; 31/31 checks; agrees with the asset porter's tables. jp differs in 4 drops and SkullGreymon's slot 0. Open: `unk2`, `checkEatDistance` units |
| Evolution | done | `specs/evolution.md` | `output/evolution/` | `EVOLUTION_REQS`, `EVOLUTION_PATHS`, `EVOLUTION_STATS_GAINS`, `EVOLUTION_ITEM_TARGET`; 21/21 checks; selection constants checked in code. Open: WereGarurumon (62) looks cut in US, map 1 of the Kunemon rule |
| Items & cards | done | `specs/items.md` | `output/items/` | `ITEM_PARA` + `ITEM_FUNCTIONS` + `ITEM_CLUT_DATA`, effects from the handlers' switches, `HEALING_VALUES`, built-in inventories, sort orders, recycle list, `CARD_DATA` + `CARD_PRICES`, shop maps / shopkeepers; 38/38 checks. Open: whether the opening scripts replace the default savegame's inventory, repel / bell roll meaning, shop stock (scripts) |
| Systems | done | `specs/systems.md` | `output/systems/` | 18 tables: battle AI / commands / flee / stat gains / music, tournaments (names, grades, schedule, win chances, medals), maps, toilets, Birdramon transport, training spots, fishing, Mojyamon trades, babies, jukebox, versus; 57/57 checks; maps and toilets equal the US executable bytes. Open: training gains are code constants, `isTournamentEnabled`, Birdramon `unk_0x1` |
| Constants & lookups | skipped by design | — | — | Rendering / effect / UI-layout tables (UVs, colours, particle state, menu layouts) are left to the asset / UI work (see `specs/systems.md` scope) |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| Package / CLI (`dwdata list`, `convert`) | done | Same pattern as `asset_porter/dwporter` |
| C initializer + constant parser | done | `cdata.py`: structs / typedefs / enums / object-like `#define`s, initializers per release (brace elision, designators, zero fill, width conversion), string literals, macro hooks, `sizeof`, function-pointer tables, `switch` cases as data. Not yet: function-like `#define` expansion, bit-field layout, PSY-Q `Gs*` types |
| YAML text reader | done | `textyaml.py`, strict subset |
| Decomp index (releases, binaries, symbols, references) | done | `decomp.py`, `cpp.py`; scope detection is heuristic (column-0 braces) |
| Table writer (schema, records, `used_by`, `godot`) + `catalog.json` | done | `output.py` |
| Shared C-table helpers | done | `tables.py` (load + checks, size vs symbols, release diffs, `used_by` with fields) |
| Human reports | done (all groups) | `output/<group>/report.md` |
| Unit tests | done | 43 tests: YAML reader, `#if` evaluator, C reader (incl. switch cases, function pointers), the six converters (synthetic + real data), cross-checks with the asset porter and the US executable |
| Godot `GameData` autoload | done | `scripts/data/game_data.gd`: lazy table loading, every accessor named in the tables' `godot.access`, text by id / entry / name ref in 3 languages, mod folders. Test `tests/test_game_data.gd` (31 checks, headless). First user: the field HUD's map name (`L` switches language) |

## Log

- 2026-10-22 — Godot `GameData` autoload done (`scripts/data/game_data.gd`, `tests/test_game_data.gd`, checked with Godot 4.3 headless on a copy of the project). Every table's `godot.status` is now `implemented`. Findings: Godot's JSON parser returns every number as a float (accessors returning numbers convert to int); the NUL padding of text `variants` can't live in a Godot string and is read as `\0`; ten string ids are defined in two blocks for different releases, merged per language. The field HUD shows the map name from `systems/maps` in the chosen language.
- 2026-10-22 — Systems group done: 18 tables, 57/57 checks, `specs/systems.md`. Every initialized C table was listed; rendering / UI / buffer tables are out of scope by design. Findings: arena battles have one command fewer than field battles (no running away); fighting styles of `chargeMode`; medal conditions are tested in order and an owned medal blocks the later ones; the fishing "bait" table is the items a stuck line gives. Cross-check: the 255 maps, their names and the 10 toilets read from C equal the US executable bytes (asset porter's reader). The data side is complete; next is the Godot `GameData` autoload.
- 2026-10-22 — Evolution group done: 4 tables, 21/21 checks, `specs/evolution.md`. Findings: the 4-point requirement score (care, weight, stats — Rookies: highest stat —, one bonus) and the "raised" priority; Rookie/Champion pick by stat average, with a carry-over quirk in the C code; fixed Fresh targets, Numemon fallback, Sukamon virus bar, special evolutions; scale vs gain stat application; Electo ring and Moon mirror can never work (targets of level 0); WereGarurumon looks cut from the US data. Infrastructure: hex literals of signed fields are reported, not failed; `decomp.py` finds functions whose header spans several lines.
- 2026-10-22 — Items group done: 8 tables, 38/38 checks, `specs/items.md`. The C reader gained function-pointer tables and `switch_cases` (item effects are switches in the handlers). Findings: `itemColor` = where an item can be used (field / battle / both / none); sell = price / 2; five passive items (Trn. manual, Rest pillow, Enemy repel / bell, Health shoe) have no case, their effects are inventory checks elsewhere; food training-boost bits mapped to stats; card roll chances 1 / 4 / 15 / 30 / 50 %; the built-in inventories look like test data. Digimon spec: favoured region scales sleep recovery ×1.2 / ×0.8.
- 2026-10-22 — Digimon group done: 6 tables, 31/31 checks, `specs/digimon.md`. Shared helpers moved to `tables.py` (moves output unchanged). Findings: EU's `DigimonPara` has no name (32 bytes instead of 52); 16 ids (tamer, NPCs) have all-zero technique slots; US doubles the poop timer after the toilet / wild poop; partner care rules per level (sleep, hunger, training factors). Cross-check test: names, file names, bones and sizes match `asset_porter/dwporter/data`.
- 2026-10-22 — C reader and Moves group done. `cdata.py` reads tables per release on their C types. It also reads DIGIMON_DATA and ITEM_PARA, with a hook for the name macros. `groups/moves.py` (3 tables, 24/24 checks), `specs/moves.md`. Text now reads the C-literal strings (79/79). Findings: the id ranges the code tests (techniques 0x00–0x39, finishers 0x3a–0x70, Counter 0x2d, generic 0x79); `unk3` = 2 flags (needs target, shared 110-tick cooldown); the evolution element blocks confirm the element ids. Decision: records hold US values, other releases as `release_values`.
- 2026-10-22 — Skeleton and Text group done. `dwdata` package (CLI, `output.py`, `textyaml.py`, `cpp.py`, `decomp.py`), `groups/text.py`, `specs/text.md`, tests. `convert text`: 24 tables, 78/78 checks. Findings: `shop/script_menu.c` is linked into main; a few strings are C literals for some releases (recorded as `c_definitions`); no `INCLUDE_ASM` left in the decomp. Decisions: both porters stay stand-alone (cross-checks allowed); all languages kept.
- 2026-10-22 — Folder, `CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` created. Decision: values copied from the decomp (trusted source), output gitignored (game content), JSON as the master format for Godot and modding.
