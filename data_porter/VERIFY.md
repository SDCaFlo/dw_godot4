# Verifying the data porter output (human checks)

The converter runs its own checks on every run (`python -m dwdata convert all`: every group must end with `N/N checks passed`) and `python -m unittest discover -s tests -t .` must pass. Those prove the values were parsed and linked correctly. What they cannot prove is that they *mean* what the spec says; that is what these checks are for. Compare with what you know of the game, a wiki, or the game itself.

Sections are added as groups are converted (see `PROGRESS.md`).

## General checks for any table

- Open the table's JSON: field names are readable, references show names next to ids (`"moves": [{"id": 46, "name": "Spit Fire"}]`), nothing looks like garbage (huge numbers, negative counts, names in the wrong place).
- Pick 2–3 records you know (e.g. Agumon, Spit Fire, Meat) and compare them with the game.
- Open `output/catalog.json`: every table has a purpose line and a spec.

## Text (`output/text/`)

The input is the decomp's `text/<dir>/<name>.yaml`; the output is **JSON**: one `output/text/<dir>/<name>.json` per YAML file (e.g. `text/main/item.yaml` → `output/text/main/item.json`), plus `output/text/report.md` (a readable sheet of the same strings) and `output/text/manifest.json` (checks and counts). No YAML is written.

Run `python -m dwdata convert text`: it should print `24 tables, 79/79 checks passed`. Then open `output/text/report.md` (one section per source file, titled with its YAML path such as `## text/main/item.yaml`; one table per block, columns ja | en_us | en_eu; — = the string doesn't exist in that release). The block names below (`DIGIMON_NAMES`, …) are the section titles in the report and the `block` field of the records in the JSON.

- **Digimon names** (`output/text/main/main.json`, block `DIGIMON_NAMES`): index 3 is Agumon / アグモン. Indices follow the game's Digimon ids (0 = "main character", 1 = Botamon). EU differences such as `HerculesKabuterimon` and `Waregarurumon` appear in the en_eu column.
- **Technique names** (`output/text/main/item.json`, block `MOVE_NAMES`): index 2 is Spit Fire. Unnamed rows show `= STR_…` (the same text as an earlier entry, e.g. the second Dynamite Kick). The last row is `NULL`.
- **Item names and descriptions** (`output/text/main/item.json`, blocks `ITEM_NAMES`, `ITEM_DESCS`): Meat shows "Makes Digimon a bit full". EU descriptions split in two show ⏎ (e.g. "Protects from changes to ⏎ status").
- **Battle messages** (`output/text/btl/battle_effect.json`): en_us keeps codes such as `#C1`, `#R`, `#W`, and en_eu keeps `{C1}`, `{R}`, `{W}`. `Listens to #C1! #W` must not show the `\0` padding in the report (it stays only in `variants` of the JSON).
- **Map names** (`output/text/main/map.json`): en_us names are centred with spaces (shown in backticks); en_eu names are not.
- **Strings defined in C** (`text/main/main_menu.yaml` → `MAIN_D_801346B8`): en_us shows `` ` is in` `` and ja `）は`, taken from `src/main/main_menu.c:635/638` (`c_text` in the JSON). `STR_MONEY_HELD` (`battle_ui`) shows `Ｂｉｔｓ` in en_eu.
- **JSON spot check:** in `output/text/main/item.json`, `records[0].used_by` should list the functions that draw technique names (`BTL_appendMoveLearnedText`, `drawMoveName`, …). In `output/text/main/main.json`, Agumon's `used_by` should point to `DIGIMON_DATA` (`src/main/main.c`).
- Compare a few strings you remember from the game, ideally a menu label and an item description, in the language of your copy.

## Moves (`output/moves/`)

Run `python -m dwdata convert moves`: it should print `3 tables, 24/24 checks passed`. Then open `output/moves/report.md`. It has one row per technique, with MP shown the way the menus show it (mp_cost × 3), plus the element factor grid and the learn chances.

- **Known techniques:** compare 3–4 techniques with the in-game technique menu (Digimon menu → techniques: power, MP, range icon, status icon):
  - Spit Fire (2): power 66, MP 30, ranged, fire, no status
  - Static Elect (12): melee, air, stun 15 %
  - Megaton Punch (46): battle
  - Poop Spd Toss (50): filth
- **Element names:** ids 0–7 should be the fire techniques, 8–15 air (thunder, wind), 16–23 ice (and water), 24–31 mech, 32–39 earth (insects, plants), 40–48 battle, 49–57 filth (48 and 57 are the second Dynamite Kick and Horizontal Kick ids). Check that the menu icon colours of a few techniques match these names. The names are labels (`specs/moves.md` §3).
- **Finishers (58–112):** their power is the base of the finisher formula, and they cost no MP in battle even if `mp` shows a value. Pepper Breath (59) is Agumon's finisher.
- **Buff techniques** (range `self`): Aqua Magic (21), Full Potential (30), Mass Morph (34), Muscle Charge (41), War Cry (42). Release differences under the table should list only Full Potential (`unk3` = 0 in jp).
- **Element factors:** the fire row should be strong against earth, ice and filth (20) and weak against air (5), if that matches what you know of the game.
- **JSON spot check:** in `output/moves/move_data.json`, `records[2]` is Spit Fire with `name.text` in the three languages and `c` holding the raw C values. `used_by` lists `BTL_calculateDamage` (`src/btl/battle_main.c`) with fields `power`, `special`.

## Reporting a problem

Note the table, the record id and what you expected vs. saw. The table's `source` says which decomp file and line the value came from.
