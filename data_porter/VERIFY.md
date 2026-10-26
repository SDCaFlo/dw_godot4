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

## Font (`output/font/`)

Run `python -m dwdata convert font`: it should print `6 tables, 52/52 checks passed`. Then open the glyph sheets `output/font/en_us.png`, `ja.png` and `en_eu.png` (16 glyphs per row, in table order, 2×) and `report.md`.

- **US sheet:** A–Z, a–z, 0–9, then the space, 。, ? ! 」 「 , \ : ; + − =, and ○ □ × △. Compare the letters with the game's menus: narrow lowercase (`i`, `l` are 4 px wide in `report.md`), 12 px capitals.
- **JP sheet:** punctuation, digits and Latin letters, hiragana, katakana, then kanji. The last cell is a crossed box: what JP shows for a character it doesn't have.
- **EU sheet:** after Z come accented letters (à, é, ñ, ß, …) at katakana codes, then the lowercase letters and the button symbols.
- **`report.md` → "Text characters without a glyph":** US `%` (shown as × in "…reduced by N%!" after a battle, if you remember that message) and `&`; the rest are JP leftovers.
- **JSON spot check:** `en_us.json` → `records[0]` is `Ａ` (`0x8260`, width 12) with its `bitmap`; `records[78]` is × with `sentinel: true`. `ascii.json` → `'` has `code` `0x8166` but `draw_string_code` `0x8175` (US `drawString` draws an apostrophe as 「).

## Moves (`output/moves/`)

Run `python -m dwdata convert moves`: it should print `4 tables, 32/32 checks passed`. Then open `output/moves/report.md`. It has one row per technique, with MP shown the way the menus show it (mp_cost × 3), plus the element factor grid and the learn chances.

- **Known techniques:** compare 3–4 techniques with the in-game technique menu (Digimon menu → techniques: power, MP, range icon, status icon):
  - Spit Fire (2): power 66, MP 30, ranged, fire, no status
  - Static Elect (12): melee, air, stun 15 %
  - Megaton Punch (46): battle
  - Poop Spd Toss (50): filth
- **Element names:** ids 0–7 should be the fire techniques, 8–15 air (thunder, wind), 16–23 ice (and water), 24–31 mech, 32–39 earth (insects, plants), 40–48 battle, 49–57 filth (48 and 57 are the second Dynamite Kick and Horizontal Kick ids). Check that the menu icon colours of a few techniques match these names. The names are labels (`specs/moves.md` §3).
- **Finishers (58–112):** their power is the base of the finisher formula, and they cost no MP in battle even if `mp` shows a value. Pepper Breath (59) is Agumon's finisher.
- **Buff techniques** (range `self`): Aqua Magic (21), Full Potential (30), Mass Morph (34), Muscle Charge (41), War Cry (42). Release differences under the table should list only Full Potential (`unk3` = 0 in jp).
- **Element factors:** the fire row should be strong against earth, ice and filth (20) and weak against air (5), if that matches what you know of the game.
- **Training learning** (`output/moves/training_learning.json`): `records[0]` (fire) lists Spit Fire, Heat Laser, Fire Tower, Magma Bomb, Red Inferno … in that order; `weights` starts `[0, 15, 10], [25, 13, 8]`. In the game, a Brains session crossing 150 Brains may teach Agumon (who knows Spit Fire) Heat Laser.
- **JSON spot check:** in `output/moves/move_data.json`, `records[2]` is Spit Fire with `name.text` in the three languages and `c` holding the raw C values. `used_by` lists `BTL_calculateDamage` (`src/btl/battle_main.c`) with fields `power`, `special`.

## Digimon (`output/digimon/`)

Run `python -m dwdata convert digimon`: it should print `7 tables, 40/40 checks passed`. Then open `output/digimon/report.md` (one row per Digimon, then partner care data and sleep cycles).

- **Known Digimon:** Agumon (3) is a Rookie, Vaccine, elements fire and battle. Its first techniques are Spit Fire and Fire Tower; it drops Sm.Recovery (50 %). Compare 2–3 Digimon you know with the game's Digimon menu (level, type icon, techniques).
- **Type names:** Gabumon (17) shows `data`, Agumon `vaccine`, Betamon (4) `virus`. If the menu icons say otherwise, the type labels are swapped (`specs/digimon.md` §3).
- **Partner care:** Agumon's favourite food is Meat, hunger hours 1, 5, 9, 13, 17, 21, sleep cycle 1 (19:00–04:00). Check the active-time label in the Digimon menu if you remember it.
- **Care properties** (`output/digimon/raise_data.json`):
  - `records[3].first_technique` is slot 0, Spit Fire: a new game's Agumon knows Spit Fire;
  - `records[17]` (Gabumon) is slot 2, Sonic Jab (43). If you ever started with Gabumon, he should know Sonic Jab;
  - `eats_poop` is true only for Numemon (11) and Sukamon (39);
  - `raises_virus_bar` is false only for Sukamon. In the game, Numemon and Sukamon eat poop piles near you.
- **Placeholders:** the tamer (0) and NPC ids such as Jijimon or the Market Manager show `— (all slots 0)` instead of techniques.
- **Release differences** under the first table: only jp changes (four drop items, SkullGreymon's first slot).
- **Files:** `output/digimon/file_names.json` → `records[3].mmd` is `CHDAT/MMD0/AGUM.MMD`, the file the asset porter converts to Agumon's model; `records[30].mmd` (Tokomon) is `CHDAT/MMD1/TOKO.MMD` (folder = id / 30). The DW Data dock's **Check assets** shows whether every one of them has a model (`../docs/dw_data_dock.md`).
- **Training animations** (`output/digimon/training_animations.json`): `records[3]` (Agumon) strikes with animation 51 (0x33, technique slot 5) and hits at frame 12. At the Green Gym's Tree Striking, the sparks should come when the blow lands.
- **JSON spot check:** `output/digimon/digimon_data.json` → `records[3].moves[0]` is `{"slot": 0, "anim": 46, "move": {"id": 2, "name": "Spit Fire"}}`; `used_by` has around 170 functions, with the fields each reads.

## Items (`output/items/`)

Run `python -m dwdata convert items`: it should print `8 tables, 40/40 checks passed`. Then open `output/items/report.md` (one row per item with its effect, then the cards).

- **Shop prices:** compare a few prices with a shop you remember: Meat 50, Sm. recovery 100, MP Floppy 300, Off. Disk 500. Selling should pay half.
- **Where items can be used:** Various (8) and the disks (15–21) are `battle`, Bandage (13) and food are `field`, the recovery items are `both`. In the game, battle-only items can't be used in the field menu.
- **Food effects:** Meat energy +12 / weight +1; Supercarrot gives a training boost to Off, Brain, MP (`train_boost` in `item_effects.json`); Moldy Meat sicknessChance 100. Compare with what you know of the game.
- **Passive items** (33–37: Trn. manual, Rest pillow, Enemy repel, Enemy bell, Health shoe) show `passive: …` instead of an effect. In `item_data.json` they carry the property `passive`: `training_boost`, `sleep_boost`, `battle_repel`, `battle_lure`, `walking_heal`; no other item has it.
- **Cards:** card prices 5000 / 1500 / 500 / 100 / 50 by rarity; card 1 (Phoenixmon) is rarity 0 (5000). Compare a card price with the card shop.
- **Inventories:** `inventories.json` holds the two built-in inventories (boot, default savegame). Both are full of high-end items; if you know what a new game starts with, note whether it matches (`specs/items.md` §6).
- **JSON spot check:** `item_data.json` → `records[38]` is Meat with its description, `handler` = `handleFood`, `c` = the raw C record; `item_effects.json` lists each item's `case` line in `item.c`.

## Evolution (`output/evolution/`)

Run `python -m dwdata convert evolution`: it should print `4 tables, 21/21 checks passed`. Then open `output/evolution/report.md` (requirements, paths, stat gains, evolution items).

- **Requirements you know:** Greymon (5) needs Off / Def / Speed / Brain 100, at most 1 care mistake, weight 30 ± 5, and one of discipline 90 / 35 techniques. Compare 2–3 Digimon with a guide or your memory of the game.
- **Rookies:** Agumon (3) shows `highest` for HP, MP, Off: a Koromon whose highest stat is one of those becomes Agumon.
- **Paths:** Agumon → Greymon, Meramon, Birdramon, Centarumon, Monochromon, Tyrannomon; Numemon → Monzaemon; Sukamon → Etemon.
- **Stat gains:** Numemon shows `scale ×0.8`, Sukamon `scale ×0.5`, Greymon `gain` with HP 2000.
- **Evolution items:** Grey Claws → Greymon, Fireball → Meramon. Electo ring and Moon mirror show `never works` (confirmed: they were never implemented in the game).
- **JSON spot check:** `requirements.json` → `records[5].bonus` has `discipline: 90` and `techs: 35`; `paths.json` → `records[58]` (Phoenixmon, id 59) has `ignored_values: [-2, 0]`.

## Systems (`output/systems/`)

Run `python -m dwdata convert systems`: it should print `20 tables, 73/73 checks passed`. Then open `output/systems/report.md`.

- **Tournaments:** names and grade letters (Grade D … Beetle Cup) match the arena board; Grade D is held on most days, Grade S on days 6, 13, 20, 27 of the month. If you remember the schedule, compare.
- **Battle commands:** field battles: 3 commands below brain 100 up to 9 from brain 500; arena: one fewer (no running away). Does that match what you remember of the command menu?
- **Flee chances:** a Virus partner keeps away other Virus enemies the most (30).
- **Maps:** `maps.json` → `records[0]` is `MAYO01` (Native Forest, toilet 0). Map names in the report match the area names shown when entering.
- **Birdramon transport:** 6 destinations, 1000–2500 bits.
- **Training spots:** Green Gym lists one spot per stat.
- **Slot machine** (`slot_machine.json`, the training Bonus Try): three reels of 13 symbols, each reel holding all of 1-7 (symbols 1-6 are HP, MP, Offense, Defense, Speed, Brains; 7 is the jackpot); an assist draw of 10 entries (five 0, four 1, one 2); payouts 100 / 40 / 20 / 5.
- **Fishing:** fish kinds are Digianchovy … Digiseabass; a stuck line gives Sm. recovery most of the time (35 %).
- **Script stat limits** (`script_stat_limits.json`): offense … brains 999, max HP / MP 9999, happiness and tiredness 100, weight 99, tamer level 10. Lives (22) shows limit 1 with `read_past_the_array`: the C reads past the table. If you know a scene where a Digimon sets your lives to 3 (File City has a "Life three" one), the game should give you 1.
- **Mojyamon trades:** e.g. Digimushrm → Med. recovery, Supercarrot → Omnipotent.

## Content keys and the `dw1` pack (`../specs/content.md`)

- `output/pack.json` exists with `"id": "dw1"`.
- Keys read like the names you know: `digimon_data.json` → `records[3].key` is `dw1:agumon`, `records[129]` (the NPC Greymon) `dw1:npc_greymon`; `move_data.json` → `records[2]` `dw1:spit_fire`; `item_data.json` → `records[38]` `dw1:meat`; `maps.json` → `records[0]` `dw1:mayo01`; `tournaments.json` → `records[0]` `dw1:grade_d`; `card_data.json` → `records[1]` `dw1:phoenixmon` (cards are keyed by the Digimon they show, in their own namespace).
- Suffixes only where names are shared: the two Dynamite Kicks are `dw1:dynamite_kick_44` / `_48`; the two YAKA25 map entries `dw1:yaka25_65` / `_232`. The `… keys: unique and well formed` checks in each manifest list all of them.
- If a key looks wrong or unhelpful, say so now: keys will go into savegames and packs, so they should not change later.

## Godot `GameData` (`scripts/data/game_data.gd`)

Run after `convert all`, from `dw_godot/`, with Godot 4.7: `godot --headless --path . -s res://tests/test_game_data.gd`. It should print `OK: GameData checks` (Agumon, Spit Fire, Meat, type factors, battle commands, flee chances, maps, text by id in en_us and ja, lookups by key, entity views, a test pack merged over dw1). The two `ERROR` lines it prints are expected: they are the test's bad pack and foreign key being rejected.

- **In the game:** run the project (F5). The help line shows the area name from the data porter, e.g. `Native Forest (MAYO04A, en_us)`. Press `L`: the name switches to `迷わずの森 (…, ja)`, then `en_eu`. Walk through a warp or use `[` / `]`: the name follows the map. If the Japanese name shows as boxes, the font has no kana (the menus will get their own font later).
- **Packs:** the test already builds one (in `user://test_game_data_pack`: Meat's price patched, Metal Banana removed, a "Super Meat" item and a "Testmon" Digimon added). To try one by hand, make a folder with `pack.json` = `{"id": "mypack", "depends": ["dw1"]}` and `items/item_data.json` = `{"records": [{"key": "dw1:meat", "patch": {"price": 80}}]}`, list the folder in the `dw/data/packs` project setting (or `DW_DATA_PACKS`), and `GameData.item("dw1:meat").price` returns 80 while everything else is unchanged.
- **Missing output:** rename `data_porter/output` and run: the field still works and shows the asset porter's map name, and the test prints `SKIP`. Code that asks for a table anyway gets `{}` and one error per table naming `python -m dwdata convert all`.

## Reporting a problem

Note the table, the record id and what you expected vs. saw. The table's `source` says which decomp file and line the value came from.
