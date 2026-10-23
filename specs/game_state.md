# Game state (design)

What the game remembers while it runs and in a savegame, how the original stores it, and how the Godot `GameState` autoload (`scripts/state/game_state.gd`, planned) holds it. Every field below is backed by the decomp (`file:line`, paths relative to `external-resources/dw_decomp/`).

Status: spec written 2026-10-23. Implementation is the next step (`PLANS.md`, milestone "living field").

## 1. Source: what a savegame is

The original defines the game state by what it writes to the memory card:

| What | Where |
|---|---|
| Save record `SavegamePayload` (0xF00 bytes incl. VS data) | `src/main/main_menu.c:88–138` |
| Memory-card file `SaveFile` (header, icon, `saves[2]`) | `main_menu.c:140–150` |
| Globals → record: `writeSavegame` | `main_menu.c:5071–5134` |
| Record → globals: `loadSavegame` | `main_menu.c:5016–5069` |
| New-game record: `initializeDefaultSavegame` | `main_menu.c:4911–4960` |
| Checksum: byte sum of the first 0x4E4 bytes + the 0xA00 VS bytes | `createSavegameChecksum`, `main_menu.c:5004` |
| Structs: `PartnerPara` (`include/dw/params.h:34`), `Stats` (`entity.h:63–88`), `Inventory` (`item.h:39`), `PoopPile` (`partner.h:24`), `ScriptState` (`script.h:158`), entities (`entity.h:99–131`) | |

Anything not in that list does not survive a save: dropped items, NPC positions, the script call stack, battle state, the 221 script values beyond index 34 (§2.5).

## 2. Original handling

### 2.1 Boot modes (`MAIN_STATE`, `main.c:3201`, `:3438–3496`)

| Value | Meaning | Set by |
|---|---|---|
| 0 | new game: intro scene, movie 1, partner Agumon (3), or Gabumon (0x11) if script value 0xFE ≠ 0, start map 0xCC | default record, title menu (`main_menu.c:3632`) |
| 1 | continue a normal save at `currentScreen` | `openSaveMachine` (`main_menu.c:5277`), title menu |
| 2 | save made after the ending: movie 2, continue in File City | `gameClearSave` (`main_menu.c:5322`) |
| 3 | leave the game loop (`main.c:3522`), then movie 3 and back to the title | the ending (not traced here) |

The mode is saved (`mainState`), so loading a game-clear save replays movie 2.

### 2.2 Clock (`include/dw/clock.h`, `src/main/clock.c`)

- `CURRENT_FRAME` counts frames of the day: one game minute = 20 frames (one real second at the 20 fps main loop), `CURRENT_FRAME = HOUR * 1200 + MINUTE * 20` (`clock.c:207`). A day is 28,800 frames (24 real minutes).
- `MINUTE`, `HOUR`, `DAY`, `YEAR`; `LAST_HANDLED_FRAME` (`clock.c:100`); playtime `PLAYTIME_FRAMES / MINUTES / HOURS`.
- New game: year 0, day 0, 08:00, `CURRENT_FRAME = LAST_HANDLED_FRAME = 0x2580` (9,600 = 8 × 1,200).
- The clock logic (speed modes, `clock.c:120–147`) is ported in the clock step, not here.

### 2.3 Partner

- `PARTNER_ENTITY` (`entity.h:111`): `digimonEntity.entity.type` (Digimon id), `stats` (`Stats`), `learnedMoves[2]` (bit field by technique id), `unk1`, `unk2`, `name[20]`, `lives`.
- `Stats` = `BaseStats` (`off`, `def`, `speed`, `brain`, `movesPrio[4]`, `moves[4]` = the 4 equipped techniques, `hp`, `mp` = maxima) + `CurrentStats` (`currentHP`, `currentMP`, `unk1`, `efeSubEffect`, `isHit`, `vabId`, `chargeMode`, `field7_0x57`).
- `PARTNER_PARA` (`params.h:34–100`): the care state: `condition` bits (`params.h:10–16`: sleepy 0, tired 1, hungry 2, poopy 3, unhappy 4, injured 5, sick 6), sleep times, tiredness, discipline, happiness, hunger / energy / food / weight, poop, sickness / injury timers, lifetime and age, training boost, care mistakes, battles, evolution timer, fish caught, stat upgrade counters (one named `buggedUpgradeBrainsCounter`), Sukamon backup stats, and 12 `unused` fields.
- Learned techniques: `hasMove(id)` tests bit `id % 32` of `learnedMoves[id / 32]` (`utils2.c:311`). `learnMove` sets technique 0x2C and 0x30 (the two Dynamite Kick ids) both through bit 44 (`utils2.c:320–323`).
- New game record: partner type 0x72 (placeholder, replaced at boot by mode 0), lives 3, `remainingLifetime` 0x120 (288), `age` 3; names from `MAIN_D_801346C4` ("Player") and `MAIN_D_8013468C` ("Digimon").

### 2.4 Tamer, world, counters

- `TAMER_ENTITY` (`entity.h:104`): `tamerLevel`, `raisedCount` (new game: 0, 1); position; the player's name is `DIGIMON_NAME(0)` (the tamer's entry of the name table).
- Auto-walk state: `TAMER_WAYPOINT_X/Y[30]`, previous / start tile, current, count, active (`main_menu.c:5121–5129`).
- Map: `CURRENT_SCREEN`, `PREVIOUS_SCREEN` (map ids, `systems/maps`), `CURRENT_EXIT`, `PREVIOUS_EXIT` (spawn index). New game: screen 0xCC, exit 9.
- `NPC_ENTITIES[8].isOnMap` (`npcMaps`): presence flags of the 8 NPC slots.
- `WORLD_POOP[100]` (`partner_impl.c:284`): `{map, x, y, size}`, x / y in collision tiles, `map = 0xFF` / `size = 0` = empty slot. The partner can eat poop (`partner.c:694`); piles are drawn when `map == CURRENT_SCREEN` (`partner_impl.c:548`).
- `MONEY` (bits; the record also mirrors it in `SAVED_STATE.money`), `MERIT`, `BATTLES_STARTED`, `BATTLES_FLED`, `TOURNAMENTS_WON`, `TOURNAMENT_WINS`, `TOURNAMENTS_LOST` (`script.h:248–253`). New game: money 50,000.
- `INVENTORY` (`item.h:43`): `types[30]` (item ids, 0xFF = empty), `amounts[30]`, `names[30]`, `size` (usable slots; new game 30 with `DEFAULT_INVENTORY_TYPES / AMOUNTS`, `items/inventories`). `names[i]` is the VRAM slot of the item's name texture (`inventory.c:599`: x = (n & 1)·0x60, y = (n / 2)·0xC), a drawing cache.

### 2.5 Script state (`ScriptState`, `script.h:158–164`; `SCRIPT_STATE_PTR = &SCRIPT_STATE`, `script_interp.c:2200`)

| Bytes | C field | Content | Access |
|---|---|---|---|
| 0–5 | `smth[0..5]` | card shop stock: 6 card ids, 0xFF = none | `hasAnyCardToBuy`, `shopFillSellCardList` (`shop/script_menu.c:1296–1385`); new game 0x3A + i (cards 58–63) |
| 6–83 | `smth[6 + k]` | recycle shop stock: count (≤ 99) per `RECYCLABLE_ITEMS[k]` slot (78) | `fillRecycleShopItemList` (`script_menu.c:1385`), `script_common.c` |
| 84–211 | `smth[0x54 + item]` | item keeper (stored items): count (≤ 99) per item id (128) | `itemKeeperFillItemList` (`script_menu.c:1536`) |
| 212–244 | `cards[33]` | card collection: 4 bits per card (count 0–15), card `id` in `cards[id / 2]`, low nibble for even ids | `getCardAmount` / `setCardAmount` (`script_interp.c:2483–2510`) |
| 245–344 | `triggers[100]` | 800 trigger flags, trigger t = bit `t % 8` of `triggers[t / 8]` | `getTriggerOffset`, `setTrigger`, `unsetTrigger`, `isTriggerSet` (`script_interp.c:2430–2770`); named ones in `include/dw/trigger.h` |
| 345–600 | `pstats[256]` | script values ("PStats"), one byte each | `readPStat` / `writePStat` (`script_interp.c:2722`, `:2775`) |
| 601–664 | `stack[8]` | script call stack (runtime) | `script_interp.c` |

- The save copies only the first **0x17C (380) bytes** (`main_menu.c:5058`, `:5120`): everything up to and including **script values 0–34**. Values 35–255 and the stack are session-only: `initializeScripts` zeroes the whole struct at boot (`script_interp.c:2203`), so after loading they are 0.
- Before saving, US and later run `recalculatePPandArena` (`main.c:3902`):
  - **PP:** script value 1 = prosperity points. For each Digimon 3–58 of level ≥ 3 whose trigger `0xC8 + id` is set (recruited to File City), add 1 for ids 0x0B, 0x27, 0x35 (Numemon, Sukamon, Nanimon), else level − 2.
  - **Arena:** if script value 3 ≥ 0x17, triggers 0x25–0x27 are cleared.
  
  `writeSavegame` also writes script value 0 = 0 while saving if it was 3 (`main_menu.c:5079–5083`), and restores it after.

### 2.6 Not part of the game state

The VS mode's registered Digimon (`battleRegistrationData[40]`, `vs.h:32`) are in the same record but belong to the VS mode (later). The memory-card header, icon, checksum, padding and `unknown4E1[0x1B]` are file format, not state.

## 3. Godot design

### 3.1 `GameState` autoload

`scripts/state/game_state.gd`, autoload `GameState`, after `GameData`. It holds the state in sections, as plain dictionaries / arrays like the rest of the port (typed wrappers were declined). Game systems read and change it directly or through small helpers (§3.4); each change that the UI must follow emits `changed(section)`.

### 3.2 Fields

Content references are **keys** (`specs/content.md` §2): `dw1:agumon`, `dw1:meat`, `dw1:mayo01`, `dw1:phoenixmon`. Numbers keep the original units (frames, PSX world units, collision tiles). Names are snake_case of the C names; unused / unknown fields are kept with their C name so nothing the original saves is lost.

| Section.field | C origin | Notes |
|---|---|---|
| `boot_mode` | `MAIN_STATE` | 0–3 (§2.1) |
| `clock.year / day / hour / minute` | `YEAR`, `DAY`, `HOUR`, `MINUTE` | |
| `clock.frame`, `clock.last_handled_frame` | `CURRENT_FRAME`, `LAST_HANDLED_FRAME` | 20 frames per minute |
| `clock.playtime.{frames, minutes, hours}` | `PLAYTIME_*` | |
| `tamer.name` | `DIGIMON_NAME(0)` | text as typed |
| `tamer.level`, `tamer.raised_count` | `TAMER_ENTITY.tamerLevel / raisedCount` | |
| `tamer.position` | `TAMER_ENTITY…location` | PSX `[x, y, z]` |
| `tamer.waypoints.{x[30], y[30], previous_tile, start_tile, current, count, active}` | `TAMER_WAYPOINT_*` etc. | auto-walk |
| `partner.digimon` | `PARTNER_ENTITY…type` | key |
| `partner.name`, `partner.lives` | `PARTNER_ENTITY.name / lives` | |
| `partner.position` | `PARTNER_ENTITY…location` | PSX `[x, y, z]` |
| `partner.learned_moves` | `learnedMoves[2]` | sorted technique keys; learning one of a `learned_with` group learns the group (`moves/move_data`, replaces the 0x2C / 0x30 literal) |
| `partner.unk1`, `partner.unk2` | `PARTNER_ENTITY.unk1 / unk2` | raw |
| `partner.stats.base.{offense, defense, speed, brains, max_hp, max_mp}` | `BaseStats` | |
| `partner.stats.base.moves[4]`, `.moves_prio[4]` | `moves`, `movesPrio` | technique keys / null (0xFF); raw priorities |
| `partner.stats.current.{hp, mp, unk1, efe_sub_effect, is_hit, vab_id, charge_mode, unk_0x57}` | `CurrentStats` | |
| `partner.care.<field>` | every `PartnerPara` field | snake_case (`timesBeingSick` → `times_being_sick`, `buggedUpgradeBrainsCounter` kept as is in snake_case), `condition` as the raw bit mask with named constants (`GameState.CONDITION_SLEEPY` …) |
| `world.screen`, `world.previous_screen` | `CURRENT_SCREEN`, `PREVIOUS_SCREEN` | map keys |
| `world.exit`, `world.previous_exit` | `CURRENT_EXIT`, `PREVIOUS_EXIT` | spawn index |
| `world.npc_on_map[8]` | `NPC_ENTITIES[i].isOnMap` | raw |
| `world.poop[100]` | `WORLD_POOP` | `{map: key, x, y, size}` or null (empty slot); fixed 100 slots, as the code indexes them |
| `money`, `merit` | `MONEY`, `MERIT` | |
| `counters.{battles_started, battles_fled, tournaments_won, tournament_wins, tournaments_lost}` | `BATTLES_STARTED` … | |
| `inventory.size`, `inventory.slots[30]` | `INVENTORY` | `{item: key, amount}` or null; `names` is not kept (drawing cache) |
| `script.triggers` | `triggers[100]` | sorted list of set trigger numbers (0–799) |
| `script.values[256]` | `pstats` | only 0–34 are saved (§2.5) |
| `script.cards` | `cards[33]` | `{card key: count}` (0–15), absent = 0 |
| `script.item_keeper` | `smth[0x54 + item]` | `{item key: count}` (≤ 99) |
| `script.recycle_stock[78]` | `smth[6 + k]` | count per `RECYCLABLE_ITEMS` slot; by slot, not item, because item 0x54 has two slots |
| `script.card_shop[6]` | `smth[0..5]` | card keys / null |

Runtime-only (not saved, like the original): the script stack, script values 35–255, dropped items, NPC positions, battle state.

### 3.3 Savegames

- **File:** JSON, `user://saves/slot_<nn>.json`, one save per file, with:
  - `format: 1`, `game: "dw1"`, `packs` (the loaded pack ids, `GameData.packs()`);
  - a small `preview` for the load menu (player name, partner name, area name, playtime), like `SaveSlotPreview` (`main_menu.c:79`);
  - the `state` object of §3.2.
- **Load:** the inverse. Unknown keys of packs that aren't loaded are reported, not dropped silently. Script values 35–255 and the stack start at 0.
- **Before saving:** the original pre-save steps (§2.5: PP / arena recalculation, script value 0) are ported with the systems they belong to. The PP rule needs a property instead of the literal ids 0x0B / 0x27 / 0x35 (`specs/content.md` §4: e.g. a `prosperity` value per Digimon, derived by the data porter, checked against the C rule).
- **No checksum.** JSON files are meant to be readable; a broken file fails to parse and is reported.
- **Original memory-card saves:** not read. The layout above is complete enough to import one later (idea in `PLANS.md`).

### 3.4 API (sketch)

```
GameState.new_game(partner := "dw1:agumon")    # §2.1 / initializeDefaultSavegame defaults
GameState.save(slot) / load(slot) / saves() -> [{slot, preview}]
GameState.is_trigger_set(t) / set_trigger(t) / clear_trigger(t)    # isTriggerSet, setTrigger, unsetTrigger
GameState.script_value(i) / set_script_value(i, v)                 # readPStat / writePStat (byte: v & 0xFF)
GameState.card_count(card) / set_card_count(card, n)               # getCardAmount / setCardAmount (0–15)
GameState.has_move(move) / learn_move(move)                        # hasMove / learnMove (+ learned_with)
GameState.has_condition(flag) / set_condition(flag, on)
signal changed(section)
```

Each helper names the C function it reproduces. Value ranges follow the C types (a byte stays 0–255, a trigger is a bit), so ported code behaves the same.

## 4. Verification (planned tests)

- New game: every field equals `initializeDefaultSavegame` plus the mode-0 boot (§2.1); the default inventory equals `items/inventories` `default_savegame`.
- Save → load round trip gives the same state; script values 35–255 come back 0.
- Trigger / card / script value helpers against the C bit layout (e.g. card 1 in the high nibble of byte 0; trigger 9 = bit 1 of byte 1).
- `learn_move("dw1:dynamite_kick_44")` also learns `dw1:dynamite_kick_48`.
- A save written with a pack loaded and read without it reports the missing keys.

## 5. Open questions

- `npcMaps` / `isOnMap` values other than 0 / 1 (`model.c:2890` tests 2).
- What the new-game intro scripts set on top of the default record (money 50,000 and the full default inventory look like test values; `data_porter/specs/items.md` §6). To be seen when the scripts run.
- `partner.unk1 / unk2`, `CurrentStats.unk1`, `field7_0x57`: not traced.
- The meaning of script values and of most triggers comes with the script interpreter; only the uses above are known here.
