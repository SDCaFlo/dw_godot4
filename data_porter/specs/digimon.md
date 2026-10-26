# Digimon (`DIGIMON_DATA`, `RAISE_DATA`, … → `output/digimon/`)

Per-Digimon data: size, type, level, elements, drops and technique slots for all 180 Digimon; care data for the 66 that can be the partner; model file names and sound banks. Converter: `dwdata/groups/digimon.py` (`python -m dwdata convert digimon`).

## 1. Source

| Table | Where | C type | US symbol size |
|---|---|---|---|
| `DIGIMON_DATA` | `src/main/main.c:254` | `DigimonPara[180]` (`include/dw/params.h:18`), 52 bytes, 32 in EU | 9360 |
| `RAISE_DATA` | `src/main/partner_impl.c:40` | `RaiseData[66]` (`include/dw/partner.h:6`), 28 bytes | 1848 |
| `SLEEP_PATTERN` | `src/main/partner_impl.c:184` | `SleepPattern[8]` (struct in the same file, `:175`) | 48 |
| `ITEM_TAKE_DISTANCE` | `src/main/partner_impl.c:195` | `int8_t[66]` | 66 |
| `PTR_DIGIMON_FILE_NAMES` | `src/main/model.c:2508` | `char *[180]` → `char STR_DIGIMON_FILE_NAME_*[]` (`model.c:93…`) | — |
| `DIGIMON_VBALL_SOUND_ID` | `src/main/sound.c:127` | `uint8_t[NUM_DIGIMON]` | — |
| `DIGIMON_VLALL_SOUND_ID` | `src/main/sound.c:58` | `uint8_t[NUM_PARTNER_DIGIMON]` | 66 |
| names | `text/main/main.yaml` → `DIGIMON_NAMES` (same index) | see `specs/text.md` | |
| `TRN_TRAINING_ANIM_IDS` | `src/trn/trn_reward.c:55` | `int8_t[67][2]` (trn overlay) | 134 |

- `NUM_DIGIMON` = 180 and `NUM_PARTNER_DIGIMON` = 66 (`params.h:7–8`). Ids 0–65 can be the partner; 0 is the tamer ("main character").
- **Names:** `DIGIMON_PARA_NAME(STR_DIGIMON_NAME_X)` embeds the name in the record as `char name[20]`, except in EU, where the struct has no `name` field (`params.h:19`) and the code uses `DIGIMON_NAMES[type]` instead (`params.h:103–108`). The converter expands the macro to the string id for non-EU releases and to nothing for EU. The parse check proves the layout: no excess or missing values in any release.
- **Release differences** (all `jp` vs later):
  - drop items of 105 Gururumon, 106 Saberdramon, 107 Soulmon and 111 Tentomon (item and chance)
  - one technique slot of 148 SkullGreymon (slot 0: 44 in jp, 48 in later releases)

## 2. Original usage

`digimon_data.json` → `used_by` lists all 167 functions that read `DIGIMON_DATA`, with the fields each reads. The main ones:

### DIGIMON_DATA

- **`boneCount`**: number of model nodes animated / drawn (`anim.c:149`, `:222`; menu view `game_menu.c:3986`).
- **`radius`, `height`** (world units, 100 = one tile):
  - collision box: half radius and half height (`aabb.c:61–66`)
  - drop shadow size (`drop_shadow.c:40–41`)
  - bubble / marker height above the head (`bubble.c:456`, `btl.c:528`)
  - melee contact (`(radius_a + radius_b)²`, `battle_main.c:1265`)
  - ranged preferred distance (`battle_main.c:1349`, see `specs/moves.md`)
- **`type`**: 1–3, 0 for the tamer and some NPCs.
  - It picks the flee chance: `FLEE_CHANCES[(partner.type - 1) * 3 + enemy.type - 1]`, a 3 × 3 table in `btl.c:104`. The partner's type 0xff skips the test (`btl.c:328–330`).
  - The menu draws the type icon at `(type - 1) * 12` (`game_menu.c:2520`, `:2528`).
  - Names: 1 Data, 2 Vaccine, 3 Virus (labels, §3).
- **`level`**: 0 for the tamer / NPCs, 1–5 for the stages. It drives:
  - hit chance: defenders below level 3 are always hit (`battle_main.c:1927`)
  - Counter chance: `speed / level` % (`battle_main.c:2170`)
  - sleep times (`setSleepTimes`, `partner_impl.c:624–656`): levels 1–2 sleep after 3 / 7 (+0–1) hours awake; level 3+ use the sleep pattern
  - hunger (`setFoodTimer`, `partner_impl.c:669–738`): level 1 every 2 h, level 2 every 3 h, level 3+ at the `hungerTimes` hours
  - training gains: ×0.9 for levels 1–2, ×1.0 Rookie, ×1.1 Champion, ×1.2 Ultimate (`trn_reward.c:674–682`)
  - an Ultimate evolution without an evolution item adds 96 to the remaining lifetime (`evl.c:1415`)
  - Names come from the evolution chart labels of the menu (`text/main/game_menu.yaml` `MAIN_D_80123AE4` / `MAIN_D_80123B10` / `MAIN_D_80123B20`): Fresh, In-Training, Rookie, Champion, Ultimate (ja 幼年期 ×2, 成長期, 成熟期, 完全体).
- **`special[3]`**: the Digimon's elements, the same ids as the technique elements (`specs/moves.md`); 0xff = empty slot.
  - Damage takes `TYPE_FACTORS[move element][e]` for each of the 3, with 10 for an empty slot (`battle_main.c:1998`).
  - Technique learning matches them (`battle_ui.c:244`).
  - Evolution teaches the weakest technique of the block of `special[0]` (`evl.c:1418`).
- **`dropItem`, `dropChance`**: after a won battle, each defeated enemy drops `dropItem` if `dropChance > randomLimit(100)` (`battle_ui.c:200–201`).
- **`moves[16]`**: technique ids by slot. Slot `k` is the animation `0x2e + k`, and `entityGetTechFromAnim` reads `moves[anim - 0x2e]` (`utils2.c:341`). The partner's 4 equipped moves are stored as animation ids.
  - New partner (`partner_impl.c:499–522`): slots 1–2 are emptied. Slot 3 (the finisher) is the last slot holding a finisher id (0x3a–0x70). Agumon (3) starts with slot 0 and learns Spit Fire (2); Gabumon (17) starts with slot 2 and learns 0x2b.
  - After evolution, slot 0 is the technique evolution taught (`evl.c:1450–1459`).
  - A list ends with 0xff. Sixteen ids have all slots 0 instead (NPCs, unused ids). The output gives them an empty list (`no_technique_list`).
- **`padding`**: 0 everywhere.

### RAISE_DATA (partners, ids 0–65)

- **`hungerTimes[8]`**: hours of the day the partner gets hungry (level 3+), -1 = unused. `setFoodTimer` picks the next one after the current hour (the jp code differs slightly: `partner_impl.c:686–737`).
- **`energyCap`**: food can't raise energy above it (`addEnergy`, `item.c:2974`).
- **`energyThreshold`**:
  - energy at birth / evolution (`partner_impl.c:486`)
  - at or above it the partner is full (trigger 0x280, `:1546`)
  - a hunger call that ends with energy below it is a care mistake (`:1526`)
  - also tested by training and scripts (`trn_reward.c:774`, `script_interp.c:852`)
- **`energyUsage`**: energy lost every 1200 frames (`partner_impl.c:1510`) and per training session (`trn_reward.c:782`).
- **`poopTimer`**: start value of `PARTNER_PARA.poopLevel` (`partner_impl.c:475`, `:595`). After using the toilet or pooping in the wild, **US sets it to twice the value**, every other release to the value (`partner_impl.c:1734–1740`, `:1763–1769`).
- **`unk2`**: 1200 for all partners but two that have 0; not read by any code.
- **`poopSize`**: size of the pile on the map (`partner_impl.c:1287`) and the weight lost per poop, `(randomLimit(4) + poopSize) / 4` (`:1751`).
- **`favoriteFood`** (item id): eating it gives ×1.4 energy and +2 happiness (`item.c:2904`). When the partner isn't hungry, it may refuse its favourite food: if the roll is below 2, `refusedFavFood` is set (`partner_impl.c:1482–1490`).
- **`sleepCycle`** (index into `SLEEP_PATTERN`): sleep and wake-up times for level 3+ (`setSleepTimes`). The menu shows an "active time" label for cycles 0–4 and a separate one for 5 (`game_menu.c:2522–2534`).
- **`favoredRegion`**: compared with the 4 + 4 region bytes of the current map (`map.c:4183–4197`).
  - A match in the first 4 sets `partnerAreaResponse = 1` (a place it likes); in the second 4, `= 2` (a place it dislikes).
  - The response scales sleep recovery: ×1.2 for 1, ×0.8 for 2 (`partner_impl.c:1354–1357`).
- **`trainingType`** (0–4): per gym stat, a factor 8–11 (×0.8–×1.1) of the training gain (`trn_reward.c:603–671`). Type 4 always gets ×0.8.
- **`defaultWeight`**: weight at birth / evolution (`partner_impl.c:488`, `:613`, `evl.c:1411`).
- **`viewX/Y/Z`**: model position in the Digimon menu's 3D view (`game_menu.c:3989`).

### Other tables

- **`SLEEP_PATTERN[8]`**: `sleepyHour:sleepyMinute`, `wakeupHour:wakeupMinute`, `awakeHours`, `sleepyHours`.
  - Patterns 0–5 are fixed day cycles: sleep at 16, 19, 22, 2, 7 or 10 o'clock, for 9 hours.
  - Patterns 6 and 7 have no times. They are the Fresh / In-Training cycles: only `sleepyHours` (1 or 3) is used.
- **`ITEM_TAKE_DISTANCE`**: read as `[type - 1]` (`partner.c:434–456`), the distance `checkEatDistance` allows when the tamer gives the partner an item. Entry 65 (Digimon 66) is never read.
- **`PTR_DIGIMON_FILE_NAMES`**: pointers to 4-letter file names (`AGUM`). The model is `CHDAT\MMD<id / 30>\<name>.MMD`: the loaders start from the string `"CHDAT\\MMD0\\"` (`model.c:2695`) and then patch its folder digit, `path[9] = digiType / 30 + '0'` (`:3409`, `:3445`, `:3631`), so ids 0–29 are in `MMD0`, 30–59 in `MMD1` … 150–179 in `MMD5`. The model-only variant is `CHDAT\TMD<id / 30>\<name>.TMD` the same way (`:3680–3682`; no `TMD` folders exist on the US disc). These are the files the asset porter converts (`mmd_files/MMD<n>/<name>.gltf`). Before 2026-10-23 the output wrote `MMD0` for every id; the converter now checks the `path[9]` lines and the cross-check test compares the paths with the asset porter's `mmd_path`.
- **`DIGIMON_VBALL_SOUND_ID`**: bank of the Digimon's sounds in `VBALL` (7 sectors per bank, `sound.c:702`, `sound_async.c:227`).
- **`TRN_TRAINING_ANIM_IDS[type]`** (`trn_off.c:121`, `:136`, `:151`, `:210`): the Offense stations start animation `[0]` (a technique animation, 0x2e–0x35) for each strike and count `[1]` frames to the hit. Entry 0 (the tamer) is 0, 0; entry 66 isn't a partner.
- **`DIGIMON_VLALL_SOUND_ID`**: the partner's voice bank in `VLALL` (15 sectors per bank, `sound.c:681–686`). Only ids 1–65 read it; the others use bank 15.

## 3. Mapping

`output/digimon/digimon_data.json`, `raise_data.json`, `sleep_patterns.json`, `item_take_distance.json`, `file_names.json`, `sound_ids.json` and `training_animations.json`, in the common table shape, plus `report.md`.

- The records hold the US values; `release_values` lists what other releases change (C names). Each record keeps its raw C values in `c`.
- `digimon_data` record:
  - `id`, `name` (from `DIGIMON_NAMES`), `partner` (id < 66), `line`
  - readable fields: `bone_count`, `radius`, `height`; `type`, `level` and `elements` as `{id, name}`; `drop {item {id, name}, chance}`
  - `moves`: `[{slot, anim, move {id, name}}]`, without the 0xff slots; `no_technique_list` when all slots are 0
  - `padding`
- `raise_data`:
  - `hunger_hours` (without the -1 padding); `favorite_food {id, name}`; `sleep_cycle {id, summary}`; `view {x, y, z}`
  - the other fields renamed to snake_case
  - **Care properties** (`../specs/content.md` §4, `../specs/care.md` §4): the care code names Digimon by literal id in `partner_impl.c`. The porter turns each rule into a property and checks that the C text is still there (whitespace collapsed):

    | Property | C rule | dw1 values |
    |---|---|---|
    | `first_technique {slot, anim, move}` | `initializePartner` (`:499–506`): `if (type == 3) { …moves[0] = 0x2e; learnMove(2); }`, the same for `0x11` with `0x30` / `0x2b` | Agumon slot 0 Spit Fire, Gabumon slot 2 Sonic Jab (0x2B); null for the others |
    | `eats_poop` | `tickPoopDetection` (`:1697`): returns unless type is `0xb` or `0x27` | Numemon, Sukamon |
    | `raises_virus_bar` | `createPoopPile` (`:1319`): `if (type != 0x27) virusBar++` | false for Sukamon only |
    | `praise_pat_low` | `tamerTickPraiseScold` (`tamer.c:1625`): `if ((DIGIMON_DATA[type].level < 4) \|\| (type == 0xd) \|\| (type == 0x1b) \|\| (type == 0x38))` → animation 0x26, else 0x27 | true below Champion and for Mamemon, MetalMamemon, Digitamamon (`../specs/game_menu.md` §2.5) |

    `slot` is the technique slot the starter has equipped (battle animation `anim` = 0x2e + slot). A second check confirms that slot holds the technique the starter learns.
- `item_take_distance`: `index` (C index), `digimon {id = index + 1, name}`, `distance`.
- `file_names`: `symbol`, `file_name`, and the `mmd` / `tmd` paths.
- `training_animations`: `id`, `digimon {id, key, name}`, `strike_anim`, `hit_frame`, `c`.
- `sound_ids`: `vball`, and `vlall` (null where the code doesn't read it; the raw array is under `raw`).
- **Labels:** type names (Data / Vaccine / Virus) are the game's names, not from the decomp: the menu draws them as icons. They fit known Digimon: Gabumon 1, Agumon 2, Betamon 3. Level names come from the menu text (§2). Element names: see `specs/moves.md`.

## 4. Godot usage

- `GameData.digimon(id)`, `GameData.raise_data(id)`, `GameData.sleep_pattern(id)`, `GameData.digimon_file(id)` (links to the asset porter's model names), `GameData.digimon_sounds(id)`, `GameData.training_animation(digimon)` (the Offense stations; a Digimon without a record uses 0x2e / 10).
- Systems that use them:
  - field and battle: collision size, shadow, markers
  - battle: elements, type, level, drops, technique slots
  - partner care: hunger, energy, poop, sleep, weight, favourite food
  - training: training type
  - menus: view position, sleep / type icons
- **Modding:**
  - Values can change within their C types.
  - Keep 180 records with their ids (maps, scripts, evolution and the asset files use them) and 66 partner records.
  - Keep technique lists ending with 0xff, the finisher in one of the slots, and the element block of `special[0]` (evolution relies on it).

## 5. Verification

The converter checks:

- the decomp exists, and the structs `DigimonPara` (EU without `name`), `RaiseData` and `SleepPattern` have the mapped fields in every release;
- every table parses in every release with no issues (layout, unknown macros, values that don't fit their field, zero fill);
- each table's size equals its US symbol size, where `symbols.txt` gives one;
- there are 180 entries in `DIGIMON_DATA`, `DIGIMON_NAMES`, `PTR_DIGIMON_FILE_NAMES` and `DIGIMON_VBALL_SOUND_ID`, and 66 in `RAISE_DATA`, `ITEM_TAKE_DISTANCE` and `DIGIMON_VLALL_SOUND_ID`;
- `DIGIMON_DATA`:
  - the embedded name of each record is `DIGIMON_NAMES[id]`;
  - type, level and elements are known values;
  - slots hold technique ids or 0xff;
  - the drop item is an item id and the drop chance ≤ 100;
  - padding is 0;
- `RAISE_DATA`: hunger hours are ascending hours, then -1; the sleep cycle is a `SLEEP_PATTERN` index; the favourite food is an item id;
- every file name pointer resolves to a string;
- `TRN_TRAINING_ANIM_IDS` has 67 entries, technique animations with a hit frame > 0 (entry 0 aside);
- the care rules behind `first_technique`, `eats_poop` and `raises_virus_bar` are still in `partner_impl.c`, and each starter's equipped slot holds the technique it learns.

Tests: `tests/test_digimon.py` (real data when `dw_decomp` is present), `tests/test_cross_asset_porter.py` (names, file names, bone counts, radius and height match `asset_porter/dwporter/data`).

## 6. Open questions

- **`unk2`** in `RaiseData` (1200 or 0) isn't read anywhere. It may be a default for another timer.
- **`partnerAreaResponse`** may have other effects besides sleep recovery. Only `partner_impl.c:1354` was traced.
- **`checkEatDistance`** units: the item-take distance is passed through unchanged. Read that function when the partner is ported.
- **Ids 114–127** (empty name at 114, NPC characters): their use by scripts is a scripts topic.
- **`ORIGINAL_DIGIMON_TYPES[180]`** (`effect_common.c:249`), `DIGIMON_SKELETONS` (`model.c:2310`) and `TOURNAMENT_SCHEDULE[180]` (`script_common.c:585`) are also indexed by Digimon id. The first is runtime state set to -1; the skeletons are in the asset porter; the tournament table belongs to Systems.
