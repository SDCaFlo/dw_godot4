# Event-script interpreter (port spec)

Status (2026-10-23):
- **done:** step 1 of §3.1, the core: `ScriptFiles`, `ScriptInterpreter`, `systems/script_stat_limits`, `tests/test_script.gd`;
- **done:** step 2, the entry points: map entry through MAPHEAD, warp cells (tamer state 5), trigger cells 51–109, the toilet cell, `WARP_TO` / `TELEPORT` with the fade and the map name, the previous-map rules (`change_map_previous`). `SECTION_ON_EXIT` and the collapse `0x4DE` moved to step 3: they need the entity opcodes;
- **done ahead of step 4:** `ENTITY_WALK_TO` for the tamer and the partner (movement type 2, §2.7), for the walk-out exits;
- **done:** step 3, the NPCs (`specs/npc.md`, option A): `LOAD` / `SET` / `UNLOAD_DIGIMON`, `UNLOAD_ENTITY`, `SET_AUTOTALK`, `PLAY_ANIMATION`, `ENTITY_LOOK_AT_ENTITY`, `ENTITY_SET_ROTATION`, `RESET_ENTITY_ORIGIN`, `ENTITY_WALK_TO` on NPCs, movement types 0–2, talking and the turn to each other;
- **next:** step 3b (the NPCs' AI) or step 4 (scripted movement and the camera).

The original's bytecode interpreter: how a script section starts, how each frame runs instructions until one waits, the call stack, the conditions, and what each instruction changes. It runs the map setup (music, NPCs), every NPC talk, trigger cells, cutscenes, shops, battles and the new game. The script files and their instruction layouts are documented in `asset_porter/specs/scn.md`; the text and choice instructions in `specs/text.md` §2.6–2.7.

All `file:line` references are in `external-resources/dw_decomp/src/main/`; the US version unless noted.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `initializeScripts`, `getScript`, `getScriptSection`, `setMapHeadActive` (`script_interp.c:2190`, `:647`, `:671`, `:2181`) | the script files and their sections | `ScriptFiles` (§3) |
| `callScriptSection`, `runMapHeadScript` (`script_interp.c:2244`, `:2235`) | start a section | `ScriptInterpreter.call_section`, `run_map_head` |
| `tickScript` (`script_interp.c:390`) | one frame of the script | `ScriptInterpreter.tick_script` |
| `scriptInstruction10to27`, `28to3F`, `46to58`, `5Ato5F`, `64to7E`, `FBtoFF` (`script_interp.c:692–2178`, `:2833`) | the instructions | one method per opcode (§2.5) |
| `scriptIfInstruction`, `scriptCompareValue`, `scriptCompareSignedValue` (`script_interp.c:907–1060`); `scriptCompareStat`, `scriptCompareCard`, `scriptCompareMove`, `scriptCompareCondition`, `scriptCompareItemCount`, `scriptCompareMoney`, `scriptCompareDate` (`script_value.c:152–386`) | IF and its conditions | `ScriptInterpreter` |
| `pushScriptStack`, `popScriptStack`, `returnFromScriptFile` (`script_interp.c:2368`, `:2383`, `:2684`) | the call stack and the end of a section | `ScriptInterpreter` |
| `scriptPauseGame` (`script_interp.c:2727`) | a script takes over the field | `ScriptInterpreter.pause_game` |
| `getStatsPointer`, `enforceStatsLimits`, `scriptUpdateEnergyBoundaries` (`script_value.c:208`, `:356`; `script_interp.c:846`) | the stats scripts change | `ScriptInterpreter` on `GameState` |
| `dateToSeconds`, `secondsToDate`, `dailyPStatTrigger` (`script_interp.c:2514`, `:2546`; `script_common.c:1399`) | dates in script values, the daily values | `ScriptInterpreter`, `Clock` (new day) |
| `giveItem`, `removeItem`, `getItemCount`, `setInventorySize` (`item.c:2562`, `:2616`, `:2549`, `:2388`) | the inventory | `GameState` helpers |
| `checkMapInteraction` (`tamer.c:660`), `changeMap` (`map.c:5326`), `scriptTickChangeMap` (`map.c:5277`) | when scripts start; map changes from scripts | the field (§3) |

The bytes are the original's: the interpreter runs on each script's bytes, rebuilt from the asset porter's output (§3), with the same pointer arithmetic as the C.

## 2. Original behaviour

### 2.1 Scripts and sections

- **Two files** (`asset_porter/specs/scn.md`):
  - `MAPHEAD.SCN`, script 0, always in RAM. Its section n is the setup of map n, and it has global sections (`0x4D9`–`0x4E4`: tournaments, item use, collapse, toilet …);
  - `DG.SCN`, scripts 1–222, one per map group. `getScript(id)` loads one into `MAP_SCRIPT_BUFFER`, unless it is already loaded (`ACTIVE_MAP_SCRIPT`).
- **A script** starts with `u16 code_start` and a section table of `u16 id, u16 offset` pairs ended by `0xFFFF`. `getScriptSection(script, id)` returns the **first** entry with that id, or NULL (a few tables list an id twice; the later entry is never found).
- **Offsets** in jumps, choices and tables are from the start of the script (`ACTIVE_SCRIPT`). `SCRIPT_POINTER` points into it.
- **`CURRENT_SCRIPT_ID`** is the DG script of the current map. MAPHEAD's map sections set it with `SET_SCRIPT`.

### 2.2 Starting a section

**`callScriptSection(script, section, isEvent)`:**
- loads the script and points at the section;
- resets: `SCRIPT_SECTION_IS_EVENT`, `SCRIPT_SECTION`, `TEXTBOX_CLOSE_MODE = 0`, the dialogue owner = the tamer (`0xFD`), `ACTIVE_INSTRUCTION = 0`, the map change and pause flags, `IS_SCRIPT_PAUSED = 0`, the sync bit, the 22 movement slots (§2.7), and the text boxes (`initializeTextbox`);
- saves script value 0 (`MAIN_D_80134FE7`) to restore it at the end;
- notes the entity talked to (`TALKED_TO_ENTITY`, the battle's opponent).

It does **not** reset the call stack.

**Where sections start:**

| Event | Call | `file:line` |
|---|---|---|
| map change (warp cell, script warp) and game start / load | `runMapHeadScript(map)` = `callScriptSection(0, map, 1)` and one `tickScript` at once | `map.c:5397`, `main.c:3455–3483` |
| talking to an NPC: touching it and pressing ✕ (`CHANGED_INPUT`), or touching it when its autotalk is 1 | `callScriptSection(CURRENT_SCRIPT_ID, npc.scriptId, 1)` | `tamer.c:669–679`, `overworld.c:1318` |
| tamer on a trigger cell 51–79 | `callScriptSection(CURRENT_SCRIPT_ID, cell, 0)` | `tamer.c:703` |
| trigger cell 80–109 and ✕ (`CHANGED_INPUT`) | the same | `tamer.c:707` |
| cell 120 (toilet) while the partner is poopy | `callScriptSection(0, 0x4E2, 0)` | `tamer.c:689` |
| the partner collapses | `callScriptSection(0, 0x4DE, 0)` | `partner_impl.c:1912`, `:1943` |
| items, tournaments, game over | sections `0x4DD`, `0x4D9`, `0x4DA`, `0x4E4` of MAPHEAD | `item.c:2263`, `tournament.c:97`, `script_common.c:3059` |

All of these but the map change require `IS_SCRIPT_PAUSED == 1`, meaning no script is running.
- Trigger cells are checked only while the tamer is free (state 0; the `return` at `tamer.c:684` comes after the NPC check).
- NPC talk by ✕ has no tamer-state check. The autotalk path of `overworld.c:1325` requires state 0.

### 2.3 One frame (`tickScript`)

`gameLoop` (`main.c:3933`) calls it after the pad is read and before the objects tick, while `IS_SCRIPT_PAUSED == 0`:
1. `tickTextboxHandling` (`specs/text.md` §2.7) and `tickScriptedMovements` (§2.7);
2. a map change started by a script (`WARP_TO`, `TELEPORT`, fleeing a battle) runs `scriptTickChangeMap` until it is done, then `scriptPauseGame(0xFF)`;
3. **the waiting instruction** (`ACTIVE_INSTRUCTION`) may finish:
   - `DELAY`: when `DELAY_FRAMES` (counted down by `tickTextboxHandling`) is 0;
   - `CALL_ROUTINE`: the builtin's own tick (shops, menus, …; `script_interp.c:421–561`) sets it to 0 when done;
   - `WAIT_FOR_ENTITY`: when the movement slot is free (§2.7);
   - `SHOW_TEXTBOX`, `SET_SELECTION`: the text boxes clear it (`specs/text.md` §2.7);
4. if something still waits (or a map change runs), the frame ends;
5. otherwise **instructions run one after another in this frame**, until one waits or the script ends. Each instruction ends with a `longjmp`:
   - `1`: run the next instruction now;
   - `2`: stop for this frame (a wait was set up, or the script paused);
   - `3`: start a map change (`closeAllTextboxes`, restore script value 0).
   
   An opcode outside the handled ranges (`0x10–0x3F`, `0x46–0x58`, `0x5A–0x5F`, `0x64–0x7E`, `0xFB–0xFF`) pauses the script;
6. **when the script has paused** (it ended): `closeAllTextboxes`, script value 0 restored. If the script had taken over the field (`scriptPauseGame`), movement comes back, the camera follows the tamer and game time runs.

### 2.4 The call stack and the end of a section

`SCRIPT_STATE.stack[8]` (`StackEntry`: pointer, script id, type, arg), `SCRIPT_STACK_OFFSET`. Not checked for overflow.

| Type | Pushed by | On `END_SECTION` / `END_SCRIPT` (`returnFromScriptFile`) |
|---|---|---|
| 1 | `JUMP_AND_LINK`, `JUMP_TO_FILE_AND_LINK` | skipped (only `JUMP_RETURN` pops it back) |
| 3 | `SET_SCRIPT` | `readMapTFS`, `setupMap` (the map is set up: entities, tamer at the exit); then the DG script's section `0xFE` runs if it has one |
| 4 | `WARP_TO`, `TELEPORT`, `SECTION_ON_EXIT`, fleeing | after the map change: the section in its arg of the new map's script, or MAPHEAD's start if 0xFF; the frame ends |
| 0 (empty stack) | — | the script pauses (it ended) |

`JUMP_RETURN` pops one entry (whatever its type) and goes back to its script and pointer.

### 2.5 Instructions

The argument layouts are in `include/dw/script.h` (and `asset_porter/specs/scn.md`). `_` is a padding byte the C skips. "Pause" means the instruction calls `scriptPauseGame(0xFF)` first (§2.6).

**Flow** (no wait unless noted):
- `JUMP_TO offset`; `JUMP_AND_LINK offset` (push type 1); `JUMP_TO_FILE script, section`; `JUMP_TO_FILE_AND_LINK`; `JUMP_RETURN`.
- `SWITCH pstat, count, offsets[count]`: value = script value, clamped to count − 1; jump to `offsets[value]`.
- `IF`: §2.8.
- `END_SECTION`, `END_SCRIPT`: `returnFromScriptFile` (§2.4).
- `SET_SCRIPT script, map`: sets `CURRENT_SCRIPT_ID` and `CURRENT_SCREEN_ID`, pushes type 3, stops the music, `loadMap(map)`.
- `SECTION_ON_EXIT section`: pushes type 4 with the section; restores script value 0.
- **Quirk kept:** `UNUSED_11` and `UNUSED_12` (307 uses) don't skip their alignment byte. The `00` after them then runs as opcode 0, outside every range, so **they end the script** without unwinding the stack. `DATA` (`0x6B`) is the same: its case is empty, so reaching it would run its bytes as instructions. In the data it always follows an end or a jump.

**Script values, triggers, money** (`GameState`):
- `SET_PSTAT p, v`; `ADD_TO_PSTAT` (at most 255); `REDUCE_PSTAT` (at least 0); `COPY_PSTAT from, to`;
- `STORE_MAP_ID p` (the current screen); `STORE_DIGIMON_TYPE p` (the partner's type id); `STORE_DIGIMON_VALUE p_in, p_out` (`DIGIMON_DATA[value].type`); `STORE_RANDOM p, max` (`randomLimit(max + 1)`); `STORE_DATE p` (year, day, hour, minute into p … p + 3);
- `SET_TRIGGER t`, `UNSET_TRIGGER t`;
- `ADD_MONEY` (at most 999,999), `REDUCE_MONEY` (at least 0), s32 amounts;
- `SET_MERIT` / `ADD_MERIT` (at most 9,999). **Quirk kept:** `REDUCE_MERIT v` sets merit to −v, which the check then makes 0, so it **clears** merit (`script_interp.c:1175`).

**Partner and inventory:**
- `GIVE_ITEM item, amount`: `giveItem`, which adds to an existing stack (at most 99; a full stack of 99 fails) or fills the first empty slot. On failure trigger 0 is **set**, on success cleared;
- `REMOVE_ITEM item, amount`; `SET_INVENTORY_SIZE n`;
- `GIVE_CARD c` (at most 9), `TAKE_CARD c` (at least 0);
- `LEARN_MOVE m` (`learnMove`, with its shared pairs); `REMOVE_CONDITION mask`;
- `SET_STAT s, v`, `ADD_STAT`, `REDUCE_STAT`, on the stat of `getStatsPointer`:
  - stats 0–22: offense, defense, speed, brains, max HP, max MP, HP, MP, tiredness, happiness, discipline, energy, virus bar, lifetime, merit, battles started, battles fled, tournaments won, tournament wins, tournaments lost, weight, tamer level, lives;
  - `SET` and `ADD` cap at `STATS_LIMIT_ARRAY[s]` (`script_value.c:36`), or max HP / MP for HP and MP. **Quirk kept:** the array has 22 entries, so stat 22 (lives) reads past it, into the next symbol `MULTIPLE_OF_10` (right after it in RAM, `config/us/symbols.txt`): the low half of its first value, **1**. File City's "Life three" section (script 164) sets lives to 3 and gets 1;
  - `REDUCE` stops at 0, or −100 for happiness (stat 9), and doesn't cap;
  - after each: `scriptUpdateEnergyBoundaries` (energy at most `energyCap`; a hungry partner whose energy reaches `energyThreshold` stops being hungry: food timer set, starvation timer 0); tamer level and lives are written back;
- `DEAL_DAMAGE p`: pause; HP −= max HP × value / 100, leaving at least 1 HP; the damage number shows over the partner.

**Dates** (script values as year, day, hour, minute; `dateToSeconds` counts minutes, 30 days a year):
- `COMPARE_DATE p, trigger, cmp, y, d, h, m`: sets or clears the trigger by comparing the stored date with the given one;
- `ADVANCE_TO_DATE_AT p`: if the stored date is later, `skipHours` up to it (the care's hours, `specs/care.md`). Then the clock is set to it (frame = hour × 1200 + minute × 20), with `dailyPStatTrigger` on a new day;
- `ADD_MINUTES_TO_DATE_AT p, s32` / `…_2` (subtracts, at least 0): changes the stored date (capped at year 25, day 14, 23:59).

**Text** (`specs/text.md` §2.6–2.7):
- `SHOW_TEXTBOX`, `SET_SELECTION` (wait), `SET_DIALOG_OWNER`, `SET_TEXTBOX_SIZE` (pause), `SET_TEXTBOX_MODE`, `SET_TEXTBOX_ORIGIN x, y, z` (the next box grows from that world point);
- `FADEOUT_HUD box`: `closeBox(box)`, then the frame ends.

**Waits:**
- `DELAY frames`;
- `WAIT_FOR_ENTITY id`: waits until the entity's movement slot is free. 0xFF waits for all slots (and the sync bit); 0xC8–0xD4 are the camera and object slots 10–21; 0xC9 / 0xD5 the sync bit; 0xD6 the training loader;
- `CALL_ROUTINE n`: the builtin n (`script_interp.c:1658–1891`). It may finish at once (e.g. 0x0C removes the item in script value 0xFE, 0x1E / 0x1F / 0x38 the shop value), or wait for a menu (shops 0x01, 0x02, 0x08, 0x0E, item keeper 0x0B, jukebox 0x09, Birdramon 0x0A, training 0x07, tournaments 0x06 / 0x12 / 0x16, naming 0x20, new game 0x32, save 0x30, …).

**Entities and movement** (all pause; §2.7):
- `LOAD_DIGIMON type`, `SET_DIGIMON type, slot, autotalk` (an NPC of the map's entity list appears), `UNLOAD_ENTITY id`, `UNLOAD_DIGIMON type`, `SET_AUTOTALK id, v`, `CALL_DIGIMON_ROUTINE n` (`partner.c:1139`);
- `PLAY_ANIMATION id, anim` (no pause; the tamer goes to state 10, the partner to 12);
- `ENTITY_LOOK_AT_ENTITY`, `ENTITY_SET_ROTATION`, `ENTITY_WALK_TO`, `ENTITY_WALK_TO_ENTITY`, `…_WITH_CAMERA`, `ENTITY_MOVE_TO`, `ENTITY_MOVE_TO_ENTITY`, `…_WITH_CAMERA`, `ENTITY_MOVE_TO_AXIS`, `…_WITH_CAMERA`, `MOVE_CAMERA_TO`, `MOVE_CAMERA_TO_ENTITY`, `RESET_ENTITY_ORIGIN`;
- objects: `SET_OBJ_VISIBILITY`, `ROTATE_3D_OBJECT` (doors), `MOVE_OBJECT_TO`, `SPAWN_BOULDER`, `MOVE_BOULDER` (waits), `DESPAWN_BOULDER`, `SET_RECT_IMPASSABLE`, `SPAWN_SPRITE_AT_LOCATION`, `SPAWN_SPRITE_AT_ENTITY`;
- items on the map: `SPAWN_ITEM item, x, z`, `SPAWN_CHEST`.

**Map changes:**
- `WARP_TO map, exit, section`: pause; push type 4 with the section; map change (with the map name unless script value 6 says otherwise, `consumeMapChangeShowName`);
- `TELEPORT p`: the same with the map and exit in script values p, p + 1, section 0xFF.

**Sound and battle:**
- `PLAY_SOUND bank, sound`, `SET_BGM bgm` (with `handleMusicOverride`: script value 245 picks the day / night variant or a fixed track), `STOP_BGM`;
- `START_BATTLE`: counts the battle, runs it, and writes the outcome to script value 0xFF:
  - lost (−1): items lost, a life lost, then MAPHEAD section `0x4DE`;
  - fled (0): counted, then back to the previous map (push type 4);
  - won: the camera returns to the tamer (`WAIT_FOR_ENTITY` on slot 10), unless trigger 1 is set.

### 2.6 A script takes over the field (`scriptPauseGame(owner)`)

The first time in a section:
- the tamer and the partner can't move: `setMovementEnabled(0, 1)` / `(1, 1)` (`overworld.c:1869`) set the tamer to state 6 and the partner to state 11; at the end of the script `setMovementEnabled(−1, 0)` sets them back to 0 and 1 (and frees the NPCs' animations);
- the camera stops following, game time stops;
- script value 0 = 3, the text area is cleared;
- for an event section (an NPC talk) unless trigger 44 is set, the NPC and the tamer turn to each other (movement slots type 0).

Every call clears trigger 44. An owner below `0xC8` (an NPC) is allowed to move.

### 2.7 Scripted movement (`SCRIPT_MOVEMENT[22]`, `tickScriptedMovement`, `script_interp.c:2275`)

- **Slots:** 0 the tamer, 1 the partner, 2–9 the NPCs (`scriptIdToEntityId`: `0xFD` → 0, `0xFC` → 1, else the NPC with that script id), 10 the camera, 11 a door, 12–21 moving objects.
- **Ticks:** each slot with a type ticks every frame: look at, set rotation, walk to (a point or an entity, optionally with the camera), move to, move along an axis, camera to point or entity, door rotation, object move.
- **Done:** the slot is freed (type 0xFF); the walkers (types below 8) go back to their idle animation.
- `WAIT_FOR_ENTITY` waits on these slots.
- **When:** `tickScript` ticks every slot (`tickScriptedMovements`, `script_interp.c:2821`) right after the text boxes and before the map change step (`:404`), only while the script runs (`IS_SCRIPT_PAUSED` returns first). So a walk started before `WARP_TO` goes on through the whole fade out. The slots are freed only by `callScriptSection` (`:2268`). After a warp, the new map's MAPHEAD section (`runMapHeadScript`) frees them, so a walk never carries over to the next map.
- **`ENTITY_WALK_TO` id, x, z, anim, unused** (`script_interp.c:1438`, 7 bytes: u8, s16, s16, u8, u8):
  - `scriptPauseGame(0xFF)` first;
  - `scriptSetEntityWalking(id, anim)` (`:879`):
    - the tamer (`0xFD`): animation `anim + 2` (0 → 2 run, 1 → 3 walk), tamer state 10;
    - the partner (`0xFC`): animation `(anim + 1) << 1` (0 → 2 walk, 1 → 4 run), partner state 12;
    - an NPC: its animation `(anim + 1) << 1` (step 3);
  - slot `scriptIdToEntityId(id)` gets type 2 with the point (x, z); none if the id has no entity.
- **The tick `tickEntityWalkTo(id, 0xFF, x, z, 0)`** (`tamer.c:991`), each frame:
  - `entityLookAtLocation` turns the entity to the point (`rotation.vy = _atan(dz, dx)`);
  - done when the entity's tile (`getModelTile`, `map_collision.c:148`) is the point's tile.
  - The movement itself is the animation's root motion. Tamer state 10 and partner state 12 tick nothing but the animation (`tamer.c:454-505`; `partner.c:246`), so no walls are checked: the tamer runs straight off the map through an exit.
  - When done, `tickScriptedMovement` starts animation 0 on it (`:2353`). The state stays 10 / 12 until the script gives the field back (`setMovementEnabled`).
- **Where it matters:** 121 of the 159 trigger-cell sections that warp are walk-outs: `ENTITY_WALK_TO` the tamer, then `WARP_TO` (e.g. Green Gym → Jijimon's house, section 0x33 of script 108). Without the walk the tamer stands through the fade.

### 2.8 IF (`scriptIfInstruction`)

The conditions follow one after another, each `u8 op, _, args` (`asset_porter/specs/scn.md` has the kinds):
- kind (`op & 0x38`): 0 trigger (set if `op & 7 == 0`, else not set), 8 script value compare, 0x20 partner stat / card count / knows move / condition / item count / money;
- comparisons (`op & 7`): 0 `==`, 1 `!=`, 2 `>=`, 3 `<=`, 4 `>`, 5 `<`; stat 9 (happiness) compares signed;
- combining: `op & 0x80` AND with the result so far, `op & 0x40` OR, else the condition replaces it;
- kind 0x10 jumps to its offset if the result is true, 0x18 if false; otherwise the next condition;
- `0x19` ends the IF: the script goes on after it.

### 2.9 Daily values (`dailyPStatTrigger`, `script_common.c:1399`)

At boot and on each new day (clock, training, `ADVANCE_TO_DATE_AT`):
- the card shop's 6 cards are rolled again: `1 + randomLimit(64)`, never 4. **Quirk kept:** the duplicate check compares with the slot being filled (`smth[i]`) instead of each earlier slot, so duplicates are possible;
- script values 0x1C–0x1F count up (unless 0xFF);
- script value 2 loses bit 7 (unless 0xFF).

## 3. Godot design

- **`ScriptFiles`** (`scripts/script/script_files.gd`): `script(id) -> PackedByteArray` (MAPHEAD = 0, DG 1–222), rebuilt from the asset porter's script JSON (`raw` of each instruction at its `offset`, plus the header and padding: the exact bytes), cached; `section(bytes, id) -> int` (first match, −1).
- **`ScriptInterpreter`** (`scripts/script/script_interpreter.gd`): `tickScript` on a `ScriptContext` (the class the text boxes already use, extended with the stack, `CURRENT_SCRIPT_ID`, the section and its flags, the map-change state).
  - One method per opcode, named after `script.h`, reading its arguments as the C does.
  - The `longjmp` codes become return values of the opcode methods: `NEXT`, `STOP`, `MAP_CHANGE`.
  - It owns the `TextBoxes` call (`tick_textbox_handling` at the start of `tick_script`).
  - Field hooks for step 2: `load_map` (`SET_SCRIPT`), `setup_map` (the type-3 return), `tick_map_change` (`scriptTickChangeMap`). Without `tick_map_change`, a map change is reported and ends the script, since it can't go on on the old map.
- **Not yet ported opcodes** read their arguments exactly as the C does, call `scriptPauseGame` first where the C does, and then do nothing, so the script goes on as in the original with that system missing.
  - Each is reported once (signal `unported(op, name)`; the field's help line shows it, `reported()` lists them).
  - Waits whose system is missing finish at once: movement slots are free, builtin routines end, and the sync-bit wait (set again by partner and tamer scenes, `partner.c:586` …) ends with a report.
  - `UNPORTED` in the interpreter holds, per opcode, the bytes the C reads; the real-script test checks them against the asset porter's instruction sizes.
  - Ported builtins: `0x03`–`0x05`, `0x11` (nothing), `0x0C` / `0x0D` (remove the item in script value 0xFE), `0x10`, `0x19`, `0x1E` / `0x1F` / `0x38` (shop value), `0x21` (the arena's daily values).
- **Actors:** in step 1 the interpreter reaches the tamer and the partner directly (`tamer`, `partner`: `setMovementEnabled`, `scriptIdToEntityId`). The NPC step adds one interface for every entity (screen position, start animation, movement ticks).
- **Debug** (`scripts/debug/script_debug.gd`, key `D`): runs the current map's script sections one after another (NPC sections below 0x33 as events), until their entry points exist.
- **The field:** `field.gd` creates the interpreter, ticks it on `GameLoop.frame` before the objects (where the text boxes' tick runs now), and starts sections from the events of §2.2 as their systems exist.
  - **Map entry** goes through MAPHEAD, as in the original (decided 2026-10-23, option A of the discussion below): `_enter(map, exit)` becomes `run_map_head(map)`. `SET_SCRIPT` calls back into the field to load the map, and the type-3 return places the tamer and runs section `0xFE`.
  - This replaces the field's direct `load_map` for normal map changes. The debug keys (`[` / `]`) go through it too. The editor preview stays a plain map with no scripts.
- **Map changes** (step 2), as in the original:
  - warp cells give the tamer state 5 (`tamerTickChangeMap`), and script warps run `scriptTickChangeMap`. Both fade to black over 20 frames, with the map name at frame 10;
  - at frame 20 the field runs `changeMap` (unload, the previous-map fix-ups as a map property, `run_map_head`), then fades in. The tamer runs with no wall checks through the fade out (only the walk state checks walls) and stands on the new map (`setupTamerOnWarp`: animation 0);
  - **port-only:** the screen stays black for `Fade.LOAD_FRAMES` (20) frames before the fade in. On the PSX `changeMap` blocks while the map is read from the CD; the port loads it in one frame, so without the hold the change felt too fast and the frames after the load's hitch swallowed the fade in;
  - the fix-ups (`map.c:5334-5366`, ten `(current, target)` pairs that set another previous screen, sometimes another previous exit) are the data porter's `change_map_previous` on the source map's record (`systems/maps`: `to`, `previous_screen`, `previous_exit` or null), checked against the C's text;
  - implemented in `field.gd`: `_begin` (the start), `_script_load_map` / `_script_setup_map` (the hooks), `_change_map`, `_check_map_interaction`, `_tick_script_map_change`; the tamer's `tick_change_map` (state 5); the name is `scripts/ui/map_name.gd` (`renderMapName` per release);
  - the field scene stays and only the map inside it is swapped, at the black frame. If loading hitches, the target map is loaded in a background thread from the start of the fade, but still swapped at frame 20.
  - **Facts behind the choice** (all 255 MAPHEAD map sections checked): each starts with `SET_SCRIPT` for its own map, with nothing before it. The script never chooses the map; it sets the music, values and triggers, and decides the NPCs (157 IFs on triggers, story values and the date). The maps' `0xFE` sections spawn items and chests, set map objects and blocked areas, and sometimes play a first-visit scene.
  - **Rejected:** loading the map in the field and running the section after it (two paths, a different order); precomputing what each section does (NPCs depend on the state).
- **Care stand-in:** the collapse script `0x4DE` (`specs/care.md` §3.3) runs for real once its opcodes are ported. Until then the current stand-in stays.
- **Data:** `STATS_LIMIT_ARRAY` (`script_value.c:36`) is the data porter table `systems/script_stat_limits` (done), with the out-of-range read documented. Later, for the debug views: the trigger names of `include/dw/trigger.h` as `systems/triggers`.
- **Daily values** (§2.9) are `Clock.daily_update` (already ported with the clock); `ADVANCE_TO_DATE_AT` calls it.

### 3.1 Order of work

1. **Core** (this step):
   - `ScriptFiles`, `ScriptInterpreter` with flow, IF, SWITCH, the stack and `returnFromScriptFile`;
   - script values, triggers, money, merit, items, cards, stats, dates, moves, conditions;
   - text and `DELAY`; the unported reporting;
   - a debug key that runs any section of the current map's script, replacing the dialogue player.
2. **Entry points** (done):
   - map entry through MAPHEAD (`SET_SCRIPT`, section `0xFE`);
   - trigger cells 51–109, the toilet cell 120 (section `0x4E2` runs; its `CALL_DIGIMON_ROUTINE` 0, the partner's toilet scene, comes with step 3);
   - `WARP_TO` / `TELEPORT` with the fade and the map name.
3. **NPCs** (own spec `specs/npc.md`, option A: they stand between talks; their AI is 3b):
   - `SECTION_ON_EXIT` (already decoded; its sections need this step's opcodes);
   - `CALL_DIGIMON_ROUTINE` moved out (`specs/npc.md` §2.9): the toilet scene (0) needs step 4's camera pan; the collapse (7) and the battle loss (9) are the `MURD` / `DOOA` scenes, their own system with the collapse script `0x4DE`;
   - `LOAD` / `SET` / `UNLOAD_DIGIMON`, `UNLOAD_ENTITY`;
   - talking and autotalk; `SET_AUTOTALK`, `PLAY_ANIMATION`, `CALL_DIGIMON_ROUTINE`;
   - the tamer's collision with NPCs (`specs/partner.md` §5).
4. **Scripted movement:** the 22 slots, `WAIT_FOR_ENTITY`, the camera moves (`createCameraMovement` / `tickCameraMovement`, `MOVE_CAMERA_TO*`), and the partner's toilet scene (`CALL_DIGIMON_ROUTINE` 0, `tickPartnerToilet`), which needs the camera pan. Done early: the slot ticks and type 2 (`ENTITY_WALK_TO`) for the tamer and the partner.
5. **With their systems:** the builtins (shops, naming, new game, item keeper, jukebox, Birdramon, training, tournaments, save), `START_BATTLE`, items and chests on the map, map objects, sounds and music, `DEAL_DAMAGE`'s number.
6. **Death and lives** (own spec later; after step 5's battles, since the battle loss shares it): `CALL_DIGIMON_ROUTINE` 7 (the collapse, `tamerTickSicknessLostLife`) and 9 (the battle loss, `tamerTickBattleLostLife`): the `MURD` scene (lives box, iris; `src/murd/murd.c`) and `DOOA` (`src/dooa/dooa.c`); the collapse script `0x4DE` then replaces the care stand-in; dying (3 / 4) if it belongs there.

## 4. Data

- **Scripts:** the asset porter's `scripts/` output (`MAPHEAD/script.json`, `DG/script_NNN.json`, `index.json`). Its checks already guarantee lossless bytes and valid targets.
- **New data porter tables** (group `systems`): `script_stat_limits` (`STATS_LIMIT_ARRAY[22]`, the stat names of `script.h:128–150`), `triggers` (the names in `trigger.h`).
- **State:** `GameState` already holds the triggers, script values, cards, money, merit and counters. New helpers: `give_item`, `remove_item`, `item_count`, `set_inventory_size` (`item.c`), the stat accessors of `getStatsPointer`. The stack and values 35–255 stay runtime-only (`specs/game_state.md` §2.5).

## 5. Verification

`tests/test_script.gd` (done, 48 checks):
- **Synthetic scripts:**
  - jumps and the stack (link / return; END with an empty stack pauses);
  - SWITCH clamping;
  - IF with AND / OR / jump-if-true / jump-if-false and each comparison; signed happiness;
  - the caps (script values 255 / 0, money 999,999, merit 9,999, `REDUCE_MERIT` clearing, stat limits, happiness −100);
  - `GIVE_ITEM` stacking, a full stack, trigger 0;
  - dates (`COMPARE_DATE`, `ADD_MINUTES`, the cap);
  - `UNUSED_12` ending the script;
  - an unported opcode skipping exactly its arguments, reported once; `WARP_TO` before step 2 ending the script;
  - `DELAY` (the next instruction on the 4th frame for 3), a text waiting for ✕;
  - `scriptPauseGame` and the end of a script (tamer 6 / partner 11 / time stopped / script value 0 = 3, then all back);
  - `ENTITY_WALK_TO`: the tamer's run animation and state 10, the partner's state 12, the slot turning the actor each frame and freeing on the point's tile (animation 0, `WAIT_FOR_ENTITY` ends), an NPC id reported; Green Gym's walk-out walking during `WARP_TO`;
  - map entry: `run_map_head` loads the map (`SET_SCRIPT`), sets it up at the section's end, runs the map's `0xFE` section; `WARP_TO` goes on in the new map's section after the field's map change;
- **The real scripts** (about 15 s):
  - every section of every DG script (1269) and every MAPHEAD map setup (255, with the map's `0xFE` section after it) runs to its end;
  - it plays like a player: ✕ for texts; at a choice the options in turn on each visit, then △, so menus that come back ("let me rethink", Mr. Handy's menu) are left;
  - no pointer leaves its script;
  - the opcode sizes the interpreter reads equal the asset porter's instruction sizes;
  - the only sections that need their caller's dialogue box are the arena registration jump tables (section 0xA of scripts 102, 168, 209, 213). They start with a text and no `SET_DIALOG_OWNER`; called on their own they would wait forever in the original too.
- **Findings:** the unported instructions of the real scripts are, besides the entity, movement, sound and battle opcodes, about 30 builtin routines (the test prints the list) and the sync-bit wait.

`VERIFY.md`, Scripts:
- run sections of the current map (debug key) and compare the dialogue and its flow with the game;
- the unported list shows what is still missing;
- map changes: warp cells, script warps, the fade and the map name (`VERIFY.md`, Map changes).

## 6. Open questions

- **`MAIN_D_80134FEC`** (set by `SET_SCRIPT`, cleared after the map setup) and **`SOME_SCRIPT_SYNC_BIT`**: what else reads them isn't traced yet.
- **Duplicate section ids** (e.g. script 4 lists 0x6 twice): the second can never be reached; whether they mean something isn't known.
- **The stack** isn't reset by `callScriptSection` and isn't bounded. A script that pauses through `UNUSED_12` with entries still on the stack leaves them for the next section (kept as in the C; the interpreter warns above 8 entries). There are 136 `JUMP_AND_LINK` against 14 `JUMP_RETURN`: most links are unwound by `END_SECTION`.
- **`START_BATTLE` unported:** the script goes on as if nothing happened, without writing the outcome (script value 0xFF). Sections that read it take whatever value it had.
- **Builtin routines** that finish at once but set up UI (`0x0F` the shop's bits box, `0x1C` Monochromon's mood bubble, …) are documented with their systems.
