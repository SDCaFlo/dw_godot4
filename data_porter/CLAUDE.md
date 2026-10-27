# data_porter

Tooling that converts the **game data defined in the decompiled C code** (tables, constants, text) into Godot-friendly JSON, and documents how the original code used each piece of data so it can be reimplemented correctly in Godot.

Sibling of `../asset_porter/` (which converts the **disc files**: textures, models, maps, sound, movies). Both write generated, gitignored output that the game loads at runtime.

Status: package, CLI, writer, decomp index, C table reader and all groups (**Text**, **Font**, **Moves**, **Digimon**, **Items**, **Evolution**, **Systems**) are implemented (Python 3, standard library only), and the Godot `GameData` autoload loads this output. Progress per table and group is tracked in `PROGRESS.md`; read it first and update it (tables + log line) whenever a table or group changes status.

## Why a separate tool

- Input is source code, not binary files: C array/struct initializers, `#define`/`enum` constants and the `text/**/*.yaml` string tables of `dw_decomp`.
- The decomp is the trusted source; values are copied from it, not read back from the executable.
- The output is game content (stats, rules, dialogue) owned by the original rights holders: it is **generated locally and never committed** (`output/` is gitignored), exactly like the asset porter's output.

## Usage

Run from this folder:

```
python -m dwdata list                    # data groups
python -m dwdata convert all             # or some of: text font moves digimon items evolution systems
python -m unittest discover -s tests -t .   # real-data test skipped if the decomp is missing
```

Defaults: input `../../external-resources/dw_decomp/`, output `output/` (gitignored, `.gdignore`: Godot never imports it); override with `--input` / `--output`. `convert` exits non-zero if any verification check fails. Python 3, standard library only.

## Code layout

| Path | Role |
|---|---|
| `dwdata/__main__.py` | CLI |
| `dwdata/paths.py` | Default paths |
| `dwdata/source.py` | `SourceText`: a decomp file with its identity (path, size, sha1) |
| `dwdata/output.py` | `GroupWriter`: table JSON in the common shape, group `manifest.json` (checks), `catalog.json` merge, Markdown reports |
| `dwdata/textyaml.py` | Strict reader for the YAML subset of `text/**/*.yaml` (all scalars stay text, `NULL` = None, line numbers kept) |
| `dwdata/cpp.py` | `#if` evaluation per release (`VERSION_IS`, `VERSION_REGION_IS`, `VERSION_EQUAL_OR_NEWER/OLDER`, `defined`); `ConditionTracker` follows `#if/#elif/#else/#endif` |
| `dwdata/decomp.py` | `Decomp`: releases (`version.h`), C file → binary (`config/us/*.yaml`), US symbols (`symbols*.txt`), identifier references in `src/**/*.c` with enclosing function / data / macro and compiling releases |
| `dwdata/cdata.py` | C data reader. `CIndex.table(c_file, name, hooks)` returns a table per release, laid out on its C type: structs / typedefs / enums / `#define`s of `include/dw/*.h` and the file, `#if VERSION_…` applied, brace elision, zero fill, width conversion, `sizeof` with PSX alignment, function-pointer tables (symbols without casts). `hooks` expand macros such as `DIGIMON_PARA_NAME(...)`. `CIndex.switch_cases(c_file, function, variable, release)` reads the cases of a `switch` as data (constant assignments + other statements as text), for effects written as code. Unsupported C raises `CError` |
| `dwdata/tables.py` | Helpers for C-table groups: `load` (parse in every release + check), `size_check` (against `symbols.txt`), `diffs` (release differences), `used_by` (references with the fields read), `source`, `enum`, `text_ref`, `keys` / `name_base` (content keys) |
| `dwdata/groups/` | One converter per group (`NAME`, `SOURCE_GLOB`, `SPEC`, `PURPOSE`, `convert()` with `out.check(...)` for every assumption), registered in `groups/__init__.py`. Existing: `text.py`, `font.py`, `moves.py`, `digimon.py`, `items.py`, `evolution.py`, `systems.py`. Groups take names from the text YAML directly (`text.load_file`), so they don't depend on run order |
| `specs/` | One spec per group (`text.md`, `font.md`, `moves.md`, `digimon.md`, `items.md`, `evolution.md`, `systems.md`) |
| `tests/` | `unittest` tests; `test_cross_asset_porter.py` compares names, file names and sizes with `../asset_porter/dwporter/data`, and maps / toilets with the asset porter's reading of the US executable |

The decomp has no `INCLUDE_ASM` left, so references are taken from C only; `asm/` is not read.

## Output

```
output/
  catalog.json                  index: every table -> group, file, one-line purpose, spec, C symbols, keyed; per group: check counts
  pack.json                     the dw1 content pack manifest (../specs/content.md)
  text/manifest.json            sources (sha1), checks, counts, control codes found
  text/report.md                human sheet: every block as a table (id | ja | en_us | en_eu)
  text/<dir>/<name>.json        one table per text/<dir>/<name>.yaml (e.g. text/main/item.json)
  font/en_us.json, ja.json,     the game's glyphs per language (font.c: code, 11 x 12 px rows, width);
       en_eu.json               clut.json, text_colors.json, ascii.json; en_us.png / ja.png / en_eu.png glyph sheets
  moves/move_data.json          MOVE_DATA (122 techniques); type_factors.json, learn_chances.json; report.md, manifest.json
  digimon/digimon_data.json     DIGIMON_DATA (180); raise_data.json, sleep_patterns.json, item_take_distance.json,
                                file_names.json, sound_ids.json; report.md, manifest.json
  items/item_data.json          ITEM_PARA + handler + icon palette (128); item_effects.json, healing_values.json,
                                inventories.json, sort_orders.json, recyclable_items.json, card_data.json, shops.json
  evolution/requirements.json   EVOLUTION_REQS (63); paths.json, stat_gains.json, item_targets.json
  systems/                      27 tables: battle_ai, battle_commands, battle_command_lists, battle_hud, item_throw,
                                psx_math, flee_chances, stat_gain_factors, enemy_music,
                                tournaments, tournament_schedule, tournament_win_chances, tournament_medals, maps,
                                toilets, birdramon_transport, training_spots, slot_machine, fishing, mojyamon_trades, babies,
                                jukebox, versus, script_stat_limits, new_game, naming, movies
```

Every table file has the same shape:

| Key | Content |
|---|---|
| `table` | name (snake_case) and one-line purpose |
| `source` | decomp files and lines the values come from (`src/main/main.c:254 DIGIMON_DATA[180]`), C type / struct (`include/dw/*.h`), plus `sha1` of the source text it was parsed from |
| `schema` | per field: name, C name, type, unit, meaning, allowed values (enums with names), reference to another table (`"ref": "moves/move_data"`) |
| `records` | the values; references carry the resolved name next to the id (`{"id": 46, "name": "Spit Fire"}`); index = original array index |
| `used_by` | C functions that read/write the table (`file:line`); text: the strings each uses, C tables: the struct fields each reads. What they compute is in the spec |
| `godot` | how the Godot side accesses it (`GameData.digimon(id)`) |

Nothing from the source may be dropped: unknown or unused fields keep their C name and raw value (`unk_0x12`) instead of being removed.

## Specs

Location: `specs/<group>.md`. Existing: `text.md`, `font.md`, `moves.md`, `digimon.md`, `items.md`, `evolution.md`, `systems.md` (its scope section lists what was left out and why). Each spec must contain:

1. **Source:** the C symbols, struct definitions and text files, with `file:line`.
2. **Original usage:** the functions that use the data and what they do with it — formulas, checks, timings — with `file:line`. This is the part that tells how to write the Godot logic; quote the C condition when it is subtle.
3. **Mapping:** how each C field becomes a JSON field (renames, unit conversions, flag bits split into booleans, ids resolved to names), and anything not mapped one-to-one.
4. **Godot usage:** which Godot system uses it and through which `GameData` accessor; what a modder can change safely (and what the code assumes, e.g. array sizes).
5. **Verification:** the checks the converter runs.
6. **Open questions:** anything not confirmed from code, clearly marked.

Write specs from evidence in the decomp, not from guesses. Update the spec before changing converter behaviour.

## Godot side

The `GameData` autoload (`../scripts/data/game_data.gd`, registered in `project.godot`) loads `output/` at runtime:

- **Folder:** env `DW_DATA_OUTPUT` or the `dw/data/output_dir` project setting (default `res://data_porter/output`), like the asset loader `Content` (`DW_PORTER_OUTPUT`).
- **Tables:** `table("digimon/digimon_data")` (whole file), `records(name)`, `record(name, index)`, `find(name, field, value)` / `find_all` (a reference field matches on its id). Loaded on first use, cached; `reload()` drops the cache.
- **Accessors:** the one each table names in its `godot.access` (`digimon(id)`, `move(id)`, `item(id)`, `map(id)`, `battle_commands(brain, arena)`, …). They return the record (or `{}`), or an int for factor / chance lookups (`-1` = not in the table). A table's `godot.access` must name a function that exists.
- **Text:** `text(id)`, `text_entry(table, block, index)`, `localize(name_ref)` in `GameData.language` (`dw/data/language`, `set_language()` → `language_changed`).
- **Content registry** (`../specs/content.md`): this output is the `dw1` pack; pack folders in env `DW_DATA_PACKS` (`;`-separated) or `dw/data/packs` are merged over it per record (add / patch / remove by `key`, `id` or `index`). Accessors take a numeric id or a key (`digimon(3)` = `digimon("dw1:agumon")`); `id_of`, `key_of`, `entity(kind, ref)` (all components of a Digimon, technique, item, map, card), `cards_of(digimon)`, `changed_by(table, ref)`, `packs()`.
- Numbers inside records are floats (Godot's JSON parser); the NUL padding of text `variants` reads as `\0`.
- **Test:** `../tests/test_game_data.gd` (`godot --headless --path .. -s res://tests/test_game_data.gd`, exits 1 on failure). In `-s` mode the autoload name isn't registered, so the test instantiates the script.

JSON stays the master format; Godot resources (`.tres`) may be generated later for the editor.

Game **logic** (evolution checks, battle maths, care timers) is not data: it is ported to GDScript when each system is built, each function commenting the C function it reproduces. The specs say where that logic lives and what data it reads.

## Workflow for a new table / group

1. Find the symbol in the decomp (`src/**/*.c`, `include/dw/*.h`, `config/us/symbols.txt`) and every function that reads it (`grep`).
2. Read the struct definition and the using code; note units, flags, enums, sentinel values (`0xFF` = none, …).
3. Write / extend `specs/<group>.md`.
4. Implement the converter (parse → validate → map → write JSON with the shape above), register it, add tests.
5. Run it, review the output (and the human report), record findings in the spec.
6. Update `PROGRESS.md`, `VERIFY.md` and `catalog.json`.

## Folder links

Paths are relative to this folder.

| What | Path | Notes |
|---|---|---|
| Decompiled code (input) | `../../external-resources/dw_decomp/` | Read its `RESOURCE_DEFINITION.md` first. `include/dw/*.h` structs/constants, `src/**/*.c` tables and logic, `text/**/*.yaml` strings (`en_us`), `config/us/symbols.txt` addresses. |
| Output | `output/` | Generated, gitignored, not imported by Godot. |
| Asset porter (disc files) | `../asset_porter/` | Its `dwporter/data/` holds a few tables generated from the decomp for its own use (Digimon types, skeletons, technique names); this tool becomes the general home for such data. |
| Godot project | `../` | Consumes `output/` at runtime. |
| Project overview | `../../CLAUDE.md` | |

## Decisions

- **Both porters stay stand-alone.** The asset porter keeps its own `dwporter/data/*.py` tables; this tool doesn't feed them, though cross-checking between the two is fine.
- **All languages and releases are kept.** `variants` holds every key as written; `text` gives `ja` (jp_rev1), `en_us` (us) and `en_eu` (eu).
- **Constants inside selection code are checked, not copied.** When logic (e.g. evolution timing, special evolutions) relies on literal ids or thresholds, the spec documents them with `file:line` and the converter checks the exact code text is still there, so a decomp change fails a check instead of silently diverging.
- **Effects written as code become data when they are constant.** A handler's `switch` cases are read as values (`switch_cases`); any other statement is kept as C text next to them, and the rules around them go in the spec. Parallel C arrays with the same index (`ITEM_PARA`, `ITEM_FUNCTIONS`, `ITEM_CLUT_DATA`) may be merged into one table, with every symbol listed in `source`.
- **C tables: US values in the records, other releases as differences.** Each table is read for every release; records hold the US values, and `release_values` lists what another release changes (C field names). Each record also keeps its raw C values (`c`), next to readable names, enums as `{id, name}` and derived values (`mp` = mpCost × 3).

- **Content architecture** (`../specs/content.md`): this output is the `dw1` content pack (`output/pack.json`). Entity records (Digimon, techniques, items, cards, maps, tournaments) carry a `key` right after `id` (`tables.keys`, §2 rule, checked unique; tables marked `"keyed": true` in `catalog.json`). Property flags that replace the original id-range rules (§4) are added per system when it is ported. Both are additions; the lossless fields stay.

## Rules

- Never write into `external-resources/`.
- Never commit generated output; only the converter, specs, tests and docs.
- Keep every value and field of the source (lossless); keep original indices as ids.
- Point the user to `VERIFY.md` after changes.
