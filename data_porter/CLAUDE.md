# data_porter

Tooling that converts the **game data defined in the decompiled C code** (tables, constants, text) into Godot-friendly JSON, and documents how the original code used each piece of data so it can be reimplemented correctly in Godot.

Sibling of `../asset_porter/` (which converts the **disc files**: textures, models, maps, sound, movies). Both write generated, gitignored output that the game loads at runtime.

Status: **planned** — folder, docs and tracking files exist; no code yet. Progress per table and group is tracked in `PROGRESS.md`; read it first and update it (tables + log line) whenever a table or group changes status.

## Why a separate tool

- Input is source code, not binary files: C array/struct initializers, `#define`/`enum` constants and the `text/**/*.yaml` string tables of `dw_decomp`.
- The decomp is the trusted source; values are copied from it, not read back from the executable.
- The output is game content (stats, rules, dialogue) owned by the original rights holders: it is **generated locally and never committed** (`output/` is gitignored), exactly like the asset porter's output.

## Usage (planned)

Run from this folder:

```
python -m dwdata list                    # data groups
python -m dwdata convert text            # or: convert all
python -m unittest discover -s tests -t .
```

Defaults: input `../../external-resources/dw_decomp/`, output `output/` (gitignored, `.gdignore`: Godot never imports it); override with `--input` / `--output`. `convert` exits non-zero if any verification check fails. Python 3, standard library only.

## Output

```
output/
  catalog.json            index: every table -> group, file, one-line purpose, spec, C symbol
  text/<file>.json        string tables from text/**/*.yaml
  digimon/ evolution/ moves/ items/ systems/ ...   one JSON per table
```

Every table file has the same shape:

| Key | Content |
|---|---|
| `table` | name (snake_case) and one-line purpose |
| `source` | decomp files and lines the values come from (`src/main/main.c:254 DIGIMON_DATA[180]`), C type / struct (`include/dw/*.h`), plus `sha1` of the source text it was parsed from |
| `schema` | per field: name, C name, type, unit, meaning, allowed values (enums with names), reference to another table (`"ref": "moves/move_data"`) |
| `records` | the values; references carry the resolved name next to the id (`{"id": 46, "name": "Spit Fire"}`); index = original array index |
| `used_by` | C functions that read/write the table (`file:line`) with one line on what each computes |
| `godot` | how the Godot side accesses it (`GameData.digimon(id)`) |

Nothing from the source may be dropped: unknown or unused fields keep their C name and raw value (`unk_0x12`) instead of being removed.

## Specs

Location: `specs/<group>.md` (`text.md`, `digimon.md`, `evolution.md`, `moves.md`, `items.md`, `systems.md`, …). Each spec must contain:

1. **Source:** the C symbols, struct definitions and text files, with `file:line`.
2. **Original usage:** the functions that use the data and what they do with it — formulas, checks, timings — with `file:line`. This is the part that tells how to write the Godot logic; quote the C condition when it is subtle.
3. **Mapping:** how each C field becomes a JSON field (renames, unit conversions, flag bits split into booleans, ids resolved to names), and anything not mapped one-to-one.
4. **Godot usage:** which Godot system uses it and through which `GameData` accessor; what a modder can change safely (and what the code assumes, e.g. array sizes).
5. **Verification:** the checks the converter runs.
6. **Open questions:** anything not confirmed from code, clearly marked.

Write specs from evidence in the decomp, not from guesses. Update the spec before changing converter behaviour.

## Godot side (planned)

A `GameData` autoload (`scripts/data/game_data.gd`) loads `output/` at runtime (path override like `PorterAssets`: env `DW_DATA_OUTPUT` / project setting) and offers typed accessors. Mods override individual JSON files from a mod folder. JSON stays the master format; Godot resources (`.tres`) may be generated later for the editor.

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

## Rules

- Never write into `external-resources/`.
- Never commit generated output; only the converter, specs, tests and docs.
- Keep every value and field of the source (lossless); keep original indices as ids.
- Point the user to `VERIFY.md` after changes.
