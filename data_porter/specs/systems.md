# Systems (remaining game-rule tables → `output/systems/`)

The tables left after the topic groups (text, moves, Digimon, items, evolution), each used by one system. Converter: `dwdata/groups/systems.py` (`python -m dwdata convert systems`). Each section below is one output table.

**Scope:** every initialized C table in `src/` was listed. Tables kept here decide game rules or content.

Left out:
- Rendering, effect, camera and UI-layout tables (UVs, colours, sprites, particle state, menu layouts): `BTL_*` effects, `DOOA_*` / `DOO2_*` / `EVL_*` / `ENDI_*` / `EAB_*` scene data, `EVO_CHART_BOXES`, …. They belong to the asset / UI work.
- Uninitialized (`*_bss_*`) buffers.
- Tables already covered by the asset porter: `DOOR_MAPDATA`, `MAP_SOUND_PARA`, `MOV_MOVIES`.
- Pointer arrays whose strings are already in the text output (`TAMER_LEVEL_TITLES`, `MEDAL_DESCRIPTIONS`, `SPECIAL_SPEAKERS`). `MEDAL_NAMES` is used here for the medal table.
- Training gym gains: they are constants inside the `trn_reward.c` functions, not tables (open questions).

All tables are the same in every release, except the pointer lists `TOURNAMENT_GRADES`, `MAP_NAME_PTR` and `BGM_TRACK_NAMES` (other string ids per release) and `BIRDRA_TRANSPORT_TARGETS` (one trigger differs in jp: `script_common.c:614`). `release_values` lists them.

## Battle

### `battle_ai` (`TARGET_ATTACKER_CHANCE[4]`, `BTL_YOUR_CALL_POWER/MP/WIDE_PRIO[4]`, `src/btl/battle_main.c:300–303`)

- **Fighting style** (`stats.current.chargeMode`, set by the commands and the AI): 0 attacks as soon as the charge gauge is > 0, 1 waits until the gauge reaches the technique's power, 2 waits for a full gauge and backs away (`BTL_applyChargeRequirement`, `:2400`; `BTL_tickChargeState`, `:1130`).
- **Retargeting:** when the partner is hit, it turns to the attacker if `randomLimit(100) < TARGET_ATTACKER_CHANCE[style] − discipline` (`BTL_retargetAfterHit`, `:1979`). The chances are 70 / 40 / 30, and 0 for style 3.
- **"Your call"** (`BTL_selectPartnerMove`, `:3420–3560`): the partner ranks its 3 techniques and gives the ones ranked 0 / 1 / 2 the weights below. It then picks by weight, with bonuses for elements and for area techniques against 2+ enemies.

  | Rank | By power (style 0) | By MP cost (style 2) | Area by distance |
  |---|---|---|---|
  | 0 | 50 | 50 | 10 |
  | 1 | 20 | 20 | 5 |
  | 2 | 5 | 10 | 0 |

- The arena (`std`) and versus (`vs`) overlays have their own copies; the converter checks they are equal.

### `battle_commands` (`BRAIN_TO_COMMAND_MAP[5]`, `battle_setup.c:31`; `STD_BRAIN_TO_COMMAND_MAP[5]`, `std_main.c:736`)

- `numCommands = MAP[brain / 100]` below brain 500; from 500, 9 in field battles and 7 in the arena (`battle_setup.c:124–128`, `std_main.c:4220–4225`).
- Field: 3 / 4 / 5 / 7 / 8 / 9. Arena: 2 / 3 / 4 / 5 / 6 / 7.
- The arena always has one command fewer: the field list adds command 1 second (`battle_setup.c:132`), and the arena never adds it, so the partner can't run away in tournaments.
- At 9 (field) / 7 (arena), the partner's equipped techniques become direct commands 8–10.

### `flee_chances` (`FLEE_CHANCES[12]`, `src/main/btl.c:104`)

At battle start, each extra enemy joins if the roll is below `FLEE_CHANCES[(partner.type − 1) * 3 + enemy.type − 1]` (`btl.c:305–330`). The Enemy repel adds 20 to the roll and the Enemy bell subtracts 50 (`specs/items.md`).

| Partner \ enemy | Data | Vaccine | Virus |
|---|---|---|---|
| Data | 60 | 70 | 100 |
| Vaccine | 80 | 60 | 100 |
| Virus | 90 | 100 | 30 |

Entries 9–11 are 0 and unused (checked).

### `stat_gain_factors` (`STAT_GAIN_ENEMY_FACTORS[4]`, `src/main/battle_ui.c:73`)

After a won battle, for each stat (`battleStatsGainsAndDrops`, `battle_ui.c:126–163`):

- `e` = the best enemy's starting stat, `p` = the partner's, `f = FACTORS[enemies − 1]` (10 / 12 / 16 for 1 / 2 / 3 enemies).
- If `e ≥ p`: gain = `ceil(e * f / (p * 10))`.
- Otherwise: 1 point with chance `e * f * 100 / (p * 10)` %.

### `enemy_music` (`ENEMY_MUSIC_MAPPING[48]`, `btl.c:95`)

Enemies 0x43–0x6f play battle theme `MAPPING[type − 0x43]` (1 or 2, 0 for the last 3); other enemies play 1, and scripted battles 0 (`loadBattleData`, `btl.c:360–376`).

## Arena

### `tournaments` (`TOURNAMENT_NAMES[23]`, `TOURNAMENT_GRADES[23]`, `src/main/script_common.c:507/533`; `STD_GRADES[23]`, `STD_OPPONENT_BASE_STATS[24]`, `src/std/std_setup.c:210/158`)

Per tournament id:
- `name` and `grade` (the schedule board letter, `dget.c:243`) as text
- `grade_image` (`\STDDAT\GRADE\*.TIM`)
- `opponent_base_stat`
- `days` held (from the schedule)

Opponents (`STD_initializeOpponent`, `std_setup.c:279–345`), for base `b`:
- each stat is `b ± 30 %` (Off, Def, Speed, Brain) or `10 b ± 30 %` (HP, MP)
- ×1 for Rookies, ×2 for Champions, ×2.5 for Ultimates
- capped at 999 / 9999

Grade R (5) and Beetle Cup (22) appear on no schedule day. The last base-stat entry (index 23) belongs to no tournament (`source.unused`).

### `tournament_schedule` (`TOURNAMENT_SCHEDULE[180]`, `script_common.c:585`)

30 days × 6 slots. Day = `DAY % 30`; 0xff ends a day; `isTournamentEnabled` then filters the list (`fillEnabledTournamentTable`, `dget/dget.c:101–140`). The tournament board shows 5 days from today.

### `tournament_win_chances` (`STD_WIN_CHANCES[4][3]`, `std_main.c:1445`)

The other participants' matches are simulated: A beats B if `randomLimit(100) < CHANCES[A.level − 3][B.level − 3]` (`STD_setupParticipants`, `std_main.c:3486–3516`).

| A \ B | Rookie | Champion | Ultimate |
|---|---|---|---|
| Rookie | 50 | 20 | 5 |
| Champion | 80 | 50 | 15 |
| Ultimate | 95 | 85 | 50 |

Row 4 (level 6) is all 0.

### `tournament_medals` (`TOURNAMENT_MEDAL_IDS[6]`, `src/main/tournament.c:37`; names `MEDAL_NAMES`, `game_menu.c:1011`)

`checkTournamentMedalConditions` (`tournament.c:167–240`) returns a condition, and the matching medal is unlocked:

- 0: the 6 Grade cups won (`TRIGGER_D_RANK_CUP_WON + 0..5`)
- 1: the 5 Version cups (`TRIGGER_VERSION_1_CUP_WON + 0..4`)
- 2: the 7 type cups (`TRIGGER_FIRE_CUP_WON + 0..6`)
- 3: the 4 special cups (`TRIGGER_DINO_CUP_WON + 0..3`)
- 4: 100 tournament wins
- 5: all 66 cards and the game beaten once

**Quirk to keep:** the conditions are tested in that order and the first one that is fully met is returned. If you already own its medal, the function returns -1 without testing the later conditions. So a later medal is only given if every earlier condition is unmet, or its medal isn't owned yet.

## World

### `maps` (`MAP_ENTRIES[255]`, `src/main/map.c:458`; `MAP_NAME_PTR[70]`, `:381`; `ARENA_MAPS[2]`, `script_common.c:257`)

Per map id:
- file name and image counts (see `asset_porter/specs/map.md`)
- `sound_bank` = `flags & 0x1f` (`map.c:4214`)
- `no_time_of_day` = `flags & 0x40` (`map.c:3968`, `:4311`, `tamer.c:954`)
- `wild_digimon` = `flags & 0x80` (`overworld.c:1036`); bit 0x20 is set nowhere
- `doors_id` (`DOOR_MAPDATA`, asset porter)
- `toilet` = `toiletId − 1` (`partner.c:542`)
- `name` = `MAP_NAME_PTR[loadingName]` (area name on entry, save screens, Birdramon menu)
- `arena`: map 208 or 223, where entering loads the tournament overlay (`checkArenaMap`, `script_common.c:3091`)
- `light_objects` (`../../specs/map_objects.md` §2.4): `MAP_LIGHT_UPDATE_DATA[1]` (`script_common.c:267`, `updateMapLightState`, `utils2.c:553`) on its map: `{start, count, mode, trigger}` (TWNB04, map 0xB7: instances 0x31–0x32, mode 1 = hidden from 7:00 to 18:59, trigger 0xFFFF → null), each entry `{start, count, mode, trigger, c}`; a check keeps the C's hours (7 ≤ hour < 0x13). `snow` (`{instances: 0x23, random_x_from: 0x14}`): the maps whose first 0x23 object instances are snow (`loadMapObjects`, `overworld.c:364`: ids 0x58–0x60, 0x84–0x87), from the C's literal ids with a check against its text
- `change_map_previous`: the fix-ups of `changeMap` (`map.c:5334-5366`), on the map they leave from: `[{to, previous_screen, previous_exit}]` (`previous_exit` null when the C keeps the warp's). Leaving this map for `to` stores `previous_screen` as the previous map, not this one. Ten pairs, from the C's literal ids (constant `CHANGE_MAP_PREVIOUS`); a check compares them with the C text (`CHANGE_MAP_EVIDENCE`, whitespace collapsed). Used by the field's `_change_map` (`../../specs/script.md` §3)

`DEATH_MAP` / `DEATH_MAP_EXIT` are runtime values (-1, set by `setDeathMap`), so they aren't output.

**Cross-check:** `tests/test_cross_asset_porter.py` compares the 255 entries, their names and the toilets with the asset porter's reading of the US executable bytes. They are identical.

### `toilets` (`TOILET_DATA[10]`, `src/main/toilet_data.c:4`)

Per toilet: the x / z point the partner walks to first (`posX1/Y1`, `walk_to`; it walks back there after) and the toilet itself (`posX2/Y2`, `camera_to`: the camera pans to it and the partner squats there), as used by `tickPartnerToilet` (`partner.c:540–590`, `specs/care.md` §2.16), plus the maps that use it.

### `birdramon_transport` (`BIRDRA_TRANSPORT_TARGETS[6]`, `script_common.c:611`)

A destination is listed once its `trigger` is set (`birdraFillTargetList`, `script_menu.c:1729`) and is selectable when it costs ≤ your bits.

Choosing one writes the map to `PSTAT_247` and `unk_0x1` (9 for five destinations, 0 for one) to `PSTAT_248`, then runs script section 0x4e3 (`tickBirdraTransport`, `:1027–1036`). The output calls that second value `entrance`; its exact use is in the script.

### `training_spots` (`TRN_TRAINING_SPOTS[8]`, `src/trn/trn_hud.c:130`, with one `TrainingSpot[]` per gym)

Per gym map (7 gyms, -1 ends the list): the x / y / z position of each stat's equipment (stat 0 HP, 1 MP, 2 Off, 3 Def, 4 Speed, 5 Brain; -1 ends), used for the training HUD (`TRN_getTrainingSpotScreenPos`, `trn_hud.c:376–400`). The `trn2` overlay has the same list (checked).

## Minigames and misc

### `fishing` (`FISH_KIND_INFO[7]`, `FISH_BITE_CHANCE[200]`, `FISH_BAIT_CHANCES[6]`, `FISHING_MAP_DATA[2]`, `src/fish/fish.c`)

- **Kinds 0–5:**
  - `unk0` is the item you catch: Digianchovy … Digiseabass (62–67)
  - size range `lo`–`hi` (`FISH_spawnFish`, `:2699`)
  - frames between moves (`:2735`)
  - `bait`: the item that attracts it (-1 = none needed, `:2757`)
  - Kind 6 is Seadramon.
- **Bite chance:** `FISH_BITE_CHANCE[(depth − 0x26) * 6 + kind]` %, for line depths 0x26–0x46 (`FISH_findFishToBite`, `:3080–3089`); Seadramon bites at 20 %. The last 2 values are unused. US computes the same index in another way (`rowOff`, `:3043–3056`).
- **Snagged items** (`FISH_BAIT_CHANCES`; the name is the decomp's):
  - While `rod.itemTaken` is set (`:3215`), every 20 frames a 1000 / 10000 roll makes the line get stuck.
  - Then `r = 0..99` picks the first entry with `r ≤ threshold`, and that item is given: "something got stuck" (`FISH_tickRod`, `:3991–4004`, `:4367–4379`).
  - Items: Sm. recovery 35 %, Various 28 %, Restore 20 %, Omni Disk 10 %, Auto Pilot 5 %, Coral charm 2 %.
- **Fishing maps** (8 and 6): kept as written; their pointer fields are C symbols (fishing spots, water tests, Seadramon waypoints).

### `mojyamon_trades` (`MOJYAMON_ITEMS_GIVE/GET[12]`, `src/shop/script_menu.c:230/235`)

4 sets of 3 trades: set = `PSTAT_249`, trade `i` = `GIVE[set * 3 + i]` → `GET[set * 3 + i]` (`mojyaTradeFillItemList`, `:1758–1784`). Set 3 is empty (zeros).

### `babies` (`BABY_IDS`, `script_common.c:253`; `REINCARNATE_BABY_TYPE[4]`, `src/dooa/dooa.c:209`)

- `isPartnerBaby` treats the 4 Fresh and 4 In-Training Digimon as babies (`script_common.c:1440`).
- Reincarnation egg slot 0–3 gives Botamon, Punimon, Poyomon or Yuramon (`DOOA_tickRebirth`, `dooa.c:1073–1103`).
- Checked against the Digimon levels.

### `jukebox` (`BGM_TRACK_NAMES[63]`, `script_common.c:363`)

The jukebox list. US shows the Mt. Panorama theme at index 45, where the other releases show Mt. Infinity (`script_common.c:409–413`).

- **`font`, `variant`:** what each track plays, `MAIN_D_801303B8[track × 2]` / `[track × 2 + 1]` (`shop/script_menu.c:211`, 64 pairs, the first 63 used). `tickJukeboxMenu` calls `playMusic(font, variant)` (`:2421`). `jukeboxFillTitleList` finds the track now playing by comparing the pair with `ACTIVE_BGM_FONT` / `ACTIVE_BGM_TRACK` (`:1660`).
- **`unlock_trigger`:** 50 for track 0x3E, null for the others. `jukeboxFillTitleList` lists track 0x3E only when `TRIGGER_50` (the game beaten once) is set (`:1643–1655`). The converter checks that code text and `#define TRIGGER_50 50`, so a decomp change fails a check. Godot reads the property, not the id (`../specs/town_services.md`).
- **Checks:** 63 names, 64 pairs, every used font in `playMusic`'s range 1–0x21.

### `versus` (`VS_DEMO_DIGIMON[48]`, `vs_demo.c:81`; `VS__BATTLE_COUNTS[4]`, `vs_select.c:133`; stat bar limits)

- The demo picks two fighters from the 48 listed (`VS_loadDemoFighters`, `:180–193`).
- Matches can be 1, 3 or 5.
- Stat bars max out at 9999 / 9999 / 999 / 999 / 999 / 999 (the arena and versus copies are checked equal).

### `script_stat_limits` (`STATS_LIMIT_ARRAY[22]`, `script_value.c:36`; the `SCRIPT_STAT_*` ids, `include/dw/script.h:128–150`)

- **The stats** scripts change with `SET_STAT` / `ADD_STAT` / `REDUCE_STAT` and compare in `IF` (`getStatsPointer`, `script_value.c:208`): 23 ids, named from `script.h`.
- **The caps** (`enforceStatsLimits`, `script_value.c:356`): `SET` / `ADD` keep the value at most `limit`; HP / MP use the max HP / MP instead; `REDUCE` doesn't cap (`../../specs/script.md` §2.5).
- **Quirk kept:** the array has 22 entries for 23 stats. Stat 22 (lives) reads past it, into `MULTIPLE_OF_10`, the next symbol in RAM. Its first value is 1, so the record has limit 1 and `read_past_the_array`. The converter checks that the two symbols are adjacent in `config/us/symbols.txt`.

## Mapping

Every table is in the common shape. Ids are resolved to names: Digimon, items, text strings (`{string_id, text, file}`) and maps. Raw C records are kept in `c` where the record isn't the raw value itself. Records hold the US values; release differences are under `release_values`.

## Godot usage

`GameData.system(name)` returns the records of any of these tables (one-record tables: `system("fishing")[0]`), with helpers where an index is computed: `flee_chance(partner_type, enemy_type)`, `battle_commands(brain, arena)`, `enemy_music(digimon_id)`, `tournament(id)`, `tournaments_on_day(day)` (day % 30, before `isTournamentEnabled`), `tournament_win_chance(level_a, level_b)`, `map(id)`, `map_id(file)`, `toilet(id)`, `training_spots(map)`, `script_stat_limit(stat)`. Lookups that find nothing return `-1` or `{}`. The formulas above are ported with the system that uses them (battle, arena, care, fishing, menus).

## Verification

The converter checks:

- the code still uses each table as documented (exact source lines: indexes, thresholds, flags);
- every table parses in every release, and each table's size equals its US symbol size where one is given;
- the std / vs / trn2 copies equal the main tables, except the arena command table, which is documented as different;
- every string id resolves to text, and every grade image to a path;
- maps: the toilet and name indexes are in range;
- babies are Fresh / In-Training, and the reincarnation eggs give Fresh Digimon;
- the `FLEE_CHANCES` padding is 0;
- the script stats are ids 0 … n − 1, one more than `STATS_LIMIT_ARRAY` has, and `MULTIPLE_OF_10` follows the array directly.

Tests: `tests/test_systems.py` (real data), `tests/test_cross_asset_porter.py` (maps and toilets equal the US executable bytes).

## Open questions

- **Training gains** per gym are constants in `trn_reward.c` / `trn2_reward.c` functions (`x = 80; y = 2; …`), scaled by `RAISE_DATA.trainingType`, level, items and boosts (`specs/digimon.md`, `specs/items.md`). They are code, not tables. Extract them when training is ported (`switch_cases` doesn't apply; they are plain assignments).
- **Grade R and Beetle Cup** are on no schedule day; how they open (scripts, triggers) isn't traced.
- **`BIRDRA_TRANSPORT_TARGETS.unk_0x1`** (9 / 0) is passed to the script as `PSTAT_248`; read section 0x4e3 of the script to name it.
- **`isTournamentEnabled`** (`dget.c`) decides which scheduled tournaments are really open (Digimon level, progress); not traced.
- **Map bit 0x20** is set on no map.
