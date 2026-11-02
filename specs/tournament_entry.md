# Tournament entry (step 4e-3)

Status (2026-11-01): **coded**, steps 1-6 on branch `feat/4e-3-tournament-entry` ("As built" at the end). Acceptance tests: §7, gates removed. `PLANS.md` 5e-4 "4e-3".

What this step covers, all in the field: you register at the arena's desk, the game reminds you or tells you that you missed it, it draws your opponents, and it records the result. The arena battles themselves are 4e-4 (`STD_REL`). Until 4e-4 is done, an arena **stand-in** returns a result (§5.4).

- **Builtin 0x12, the tournament board** (`initTournamentSchedule`, `dget/dget.c:664`): the 5-day schedule, cup info on START, then registration.
- **The registration tick** (`updateTournamentRegistration`, `main/tournament.c:42`), run every field frame: the reminder (MAPHEAD 0x4D9) and the missed-it scene (0x4DA). It also gates `updateMapLightState`.
- **Builtin 0x06, the start** (`scriptStartTournament` `tournament.c:128`, `startTournament` `main/utils2.c:577`): the 7-opponent draw, the arena run (stand-in), then the counters, the cup-won trigger and script value 0xFF.
- **Builtin 0x16, the medal check** (`checkTournamentMedalConditions` `tournament.c:168`, `scriptCheckTournamentMedal` `:242`), plus its pre-check in `CALL_ROUTINE` (`script_interp.c:1662`).
- **Builtin 0x21, the Beetle Cup registration** (`script_interp.c:1800`). The port already has it, but with the cup id as a literal and a wrong comment (§4.8).

Read first: `specs/shops.md` §3 (routine nodes, `MenuRoutines`, the MAPHEAD lines, `SCRIPT_TEXTBOX_MODE`), `specs/text.md` §2 (`TextBoxes`, `drawString2` control codes, `renderString`), `specs/scenes.md`, `specs/content.md` §4, `docs/porting_checklist.md`.

## 0. Where it is used

| Script | Map | Section | Builtins | What |
|---|---|---|---|---|
| 168 | 208 ROOM13, 223 ROOM19 (Arena Lobby) | 0x51 → `JUMP_TO_FILE` 213:0x51; 0x36 → 213:0x36 | — | the desk and the stairs, both in script 213 |
| 213 | (jumped to from 168) | 0x51 (the receptionist, entity 5) | 0x12 at 1276 (after `SET_PSTAT 254 = 5`) | "Do you wanna enter the tournament?" → the board |
| 213 | | 0x36 (the stairs down) | 0x06 at 4146 | not registered / tomorrow / before 10:00 → refused; trigger 40 → maybe −1 Tamer level; then the tournament, +6 h, `WARP_TO` 223 or 208 section 0x3D |
| 102 | 106 BETL02 (Beetle Land) | 0x51 / 0x33 | 0x21 at 1888, 0x06 at 2514 | the Beetle Cup: register, then fight on the spot |
| 126 | 131 GIAS06B (Gear Savanna) | 0x51 | 0x16 at 1226, 1242 (after the card pack, 0x0E) | the card-collection medal |
| 209 | none (debug script) | 0x05 | 0x16, 0x12, 0x06 | test menu; has sections 0x0A / 0x0B |

`ACTIVE_MAP_SCRIPT` while 213 runs is 213 (`JUMP_TO_FILE`; port `ScriptContext.active_script_id`). Scripts 168, 213, 102 and 209 all carry the **cup data** in section 0x0A and a Digimon list in section 0x0B, each with offsets relative to its own script. The C always reads the active script's copy (§4.1).

**The four copies hold the same values** (checked 2026-11-01: requirements, the three lists, section 0x0B and the info text of all 23 cups). So the port doesn't read script bytes in its logic: the asset porter turns the cup data into a table, `scripts/tournament_cups.json` (§5.2), which checks that the copies stay equal. `GameData` gives each tournament its cup data as the component `cup`, and the logic reads only that. **Decided 2026-11-01 (the user):** the tournament information is data, not logic.

## 1. What the player sees

1. **Arena Lobby, the receptionist:** "I'm glad you came. Do you wanna enter the tournament?" (In-Training partners are refused by the script.) Yes → the board.
2. **The board:** box 1, title "Tournament" (US). Box 2 is a 5 × 6 grid: columns are today and the next 4 days (day of the month at the top), rows are the cups held that day as grade letters. The letter colours:
   - **3:** can't enter;
   - **1:** can enter;
   - **7:** can enter but over-levelled (the partner is in the cup's "too strong" list).

   Only today (before 10:00) and tomorrow can be entered.
   - ←→↑↓ move, with wrap and repeat.
   - START opens the cup's info (box 3, 7 lines, grows from the cell); START / ✕ / △ closes it.
   - ✕ on an enterable cell picks it.
   - △ leaves.
3. **After picking:** box 3 shows the info (static), and the dialogue asks "Do you want to enter? - Grade D - ?" (line 2), or for an over-levelled partner, "<partner> is going to enter - X -? Are you sure?" (line 3). Then the tamer chooses Enter / Don't enter.
4. **Enter:** registered (triggers 37, 38, 39; day; partner type).
5. **Reminders:** in the field, from 12:00 the partner reminds you once: "You're entered in today's - X - Tournament, right?" (0x4D9). It does it again once from 20:00. If the day has passed or it is 23:01 or later, it's "Darn! I forgot that we entered today's - X - Tournament!" (0x4DA), and the registration is cancelled. The partner changing species also cancels it, silently.
6. **The stairs:** the script refuses "not registered" / "tomorrow" / "before ten". For an over-levelled entry, a 30 % chance of "Tamer Level went down!". Then builtin 0x06: the opponents are drawn and the arena runs (4e-4; stand-in now). The cup is won or lost, 6 hours pass, and you're back in the lobby.
7. **Medals:** where a script calls builtin 0x16 (Gear Savanna after a card pack; script 209), the first fully met tournament condition gives its medal, if it isn't owned yet, and names it. That is at most one medal per call (§4.10).

## 2. The C code

| C (US) | What | Port |
|---|---|---|
| `getCupDataJumpTable` (`tournament.c:146`), `getCupDataJumpTableEntry` (`:157`) | cup `id`'s five data pointers in section 0x0A of `ACTIVE_MAP_SCRIPT` | `TournamentCups` §4.1 |
| `isTournamentEnabled` (`dget.c:350`) | the cup is held at all (roster progress) | §4.2 |
| `tournamentCheckEligible` (`dget.c:429`), `tournamentCheckFair` (`dget.c:331`) | partner type in list 3 (eligible) / list 2 (over-levelled; the C's "fair" is a misnomer) | §4.2 |
| `fillEnabledTournamentTable` (`dget.c:101`) | the 30-byte board table with its 0x80 / 0x40 bits | §4.3 |
| `buildScheduleLabels` (`:147`), `buildScheduleEntries` (`:201`), `renderTournamentTextbox` (`:448`), `tickTournamentSchedule` (`:468`), `renderTournamentSchedule` (`:555`) | boxes 1 and 2 | `TournamentBoard` §4.4 |
| `initTournamentInfo` (`:285`), `tickTournamentInfo` (`:631`), `renderTournamentInfo` (`:644`) | box 3 | §4.5 |
| `initTournamentSchedule` (`:664`) | builtin 0x12's states | §4.6 |
| `updateTournamentRegistration` (`tournament.c:42`), `minutesOfDay` (`:123`); called from `gameLoop` (`main.c:3941`) before `tickScript` | the field tick | §4.7 |
| `dailyPStatTrigger` (`script_common.c:1432–1436`) | clears bit 0x80 of script value 2 at the day change | already in `Clock` (`clock.gd:182`) |
| `script_interp.c:1800–1813` | builtin 0x21 | §4.8 |
| `scriptStartTournament` (`tournament.c:128`), `startTournament` (`utils2.c:577`), `reinitializeAfterTournament` (`map.c:5445`) | builtin 0x06 | §4.9 |
| `checkTournamentMedalConditions` (`tournament.c:168`), `scriptCheckTournamentMedal` (`:242`), `script_interp.c:1662–1665`, `unlockMedal` / `hasMedal` (`script_common.c:3026 / 3033`) | builtin 0x16 | §4.10 |
| `checkArenaMap` (`script_common.c:3091`) | loads `DGET_REL` on maps 0xD0 / 0xDF | nothing to port (the porter's `maps.arena` exists; the board code is always loaded) |

**Data:**
- `TOURNAMENT_SCHEDULE[180]`, `TOURNAMENT_GRADES[23]`, `TOURNAMENT_MEDAL_IDS[6]`: already in `systems/tournament_schedule`, `systems/tournaments` (`grade`), `systems/tournament_medals`.
- The cup data (§4.1) is script bytes in the original. In the port it is the asset porter's `scripts/tournament_cups` table, the tournament entity's `cup` component (§5.2).

**Text:** MAPHEAD section 0x4D8 (8 entries):
- 0: "Is it OK? / Yes No"
- 1: "Tournament Schedule"
- 2: "Do you want to enter? - {tournament_name 3}- ?"
- 3: "{partner} is going to enter - {tournament_name 3}-? Are you sure?"
- 4: "Enter / Don't enter"
- 5: "Penalty"
- 6: "You can't enter yet…"
- 7: "{move_name 243} was not passed on."

The other sections:
- 0x4D9: the reminder.
- 0x4DA: the missed-it scene.
- 0x4DB: the medal category names, entries 0–5: Grade, Version, Character, Special, Total, Trading card.
- The US box-1 title is the C literal `"Tournament"` (`dget.c:459`).

## 3. The values

Status per `docs/porting_checklist.md` §1.

| What | C source | Value | Status |
|---|---|---|---|
| Registered trigger | `trigger.h:827`, `TRIGGER_TOURNAMENT_REGISTERED` | 37 (0x25) | ported |
| Reminder triggers (before / from 20:00) | `tournament.c:103–112`; set `dget.c:724–725`, `script_interp.c:1802–1803` | 38 (0x26), 39 (0x27) | ported |
| Over-levelled trigger | `trigger.h:828`; `dget.c:705 / 708` | 40 | ported |
| Roster triggers | `dget.c:371, 381, 397, 407`; `utils2.c:605, 618` | 200 + Digimon id; the full scan is 200…311 (`TRIGGER_OGRE_FORTRESS_OPENED`…`< TRIGGER_WARUSEADRAMON_BEATEN`; `startTournament` uses `i < 0x70`, the same range) | ported (base constant with its C name) |
| Grade A won (`reqType` 1) | `dget.c:392` | trigger 18 | ported: as the cup-0x03 record's `won_trigger` (§5.2) |
| Script values | `pstat.h:263–265` | 2 = day (bit 0x80 = "tomorrow"), 3 = cup id (0xFF = none), 4 = partner type at registration; 254 = the box origin's entity; 0xFF = result | ported |
| Minutes of day | `tournament.c:123` | `MINUTE + HOUR * 60` | ported |
| Today enterable until | `dget.c:125` | `minutes <= 600` (10:00 inclusive) | ported |
| Reminders from | `tournament.c:70` | `minutes >= 0x2D0` (12:00) | ported |
| Second reminder from | `tournament.c:102` | `minutes >= 0x4B0` (20:00) | ported |
| Too late from | `tournament.c:74` | `minutes >= 0x565` (23:01) | ported |
| Missed / reminder sections | `tournament.c:97, 116` | `callScriptSection(0, 0x4DA, 1)`, `(0, 0x4D9, 1)` | ported |
| Board table | `tournament.h:6`, `dget.c:671–672` | 30 bytes, 0xFF-filled; cell = `[column * 6 + row]` | ported |
| Board days shown | `dget.c:109` | 5, from `DAY`; schedule day `day % 30` | ported |
| Bits | `dget.c:138, 141` | 0x80 eligible, 0x40 over-levelled, id `& 0x3F` | ported |
| Input repeat while the board is open | `dget.c:681`, `:697` | mask 0xF000 (d-pad), 0 after | ported |
| Box 1 | `dget.c:165–168` (US) | flags 0xE1, rect (−54, −98, 108, 20), origin = entity `pstat 254`; `registerTextbox(1, 8, 2, 0, 0)`; line 1 of 0x4D8 | ported |
| Box 1 line cut | `dget.c:174` | `TEXTBOX_LINES_PTR[0x210] = 0x0D` (US, 64-byte lines: row 8, byte 16) | ported |
| Box 1 US title | `dget.c:458–459` | `drawString("Tournament", 0, row 8 × 12)`; `renderString(0, x + 6, y + 3, 0x54, 0xC, 0, uvY, 5, 1)` | ported |
| Day header | `dget.c:176–197` (US) | row 9: `01 01`, then 5 × `intToStringSJIS(day % 30 + 1, 2, 0)`; a full-width space (`81 40`) after the first if it is < 10 | ported |
| Box 2 | `dget.c:221–225` | flags 0xE1, rect (−0x82, −0x3E, 0x104, 0x7C), `registerTextbox(2, 10, 6, 0, 1)`; cursor (0, 0) | ported |
| Grid cells | `dget.c:229–268` (US) | per column: `01 c`, c = 3 (no bits) / 7 (0x40) / 1 (only 0x80), then the grade. US grades are 1-byte ASCII ("D", `script_common.yaml:340`), copied as they are. A 2-byte grade gets `0F 00` before and after it (JP), or only after it (EU). An empty cell is `01 01 81 40`. A row ends with `terminateString`: `01 01 0D 00`, the last row (15) with `01 01 00 00` (`script_common.c:2905`) | ported |
| Grid lines | `dget.c:568–572` | vertical at x = 0x34 + 0x33 i (i < 5): (2, 0x13) and (0x16, 0x64); horizontal (3, 0x14, 0xFE); all box 2 | ported |
| Cursor | `dget.c:574–576` | (box x + 4 + col × 51 + 3, box y + 3 + row × 16 + 0x16), 0x2A × 0xD, layer 4 | ported |
| Header text | `dget.c:597–603` (US) | `renderString(0, x + 0xC + 0x33 i, y + 2, 0x10, 0xC, 0x10 i, 0x6C, 4, 1)` | ported |
| Row text | `dget.c:606–624` (US) | rows at y + 0x18 + 0x10 r, v = 0x78 + 0xC r; cells at x + 0x14 + 0x33 i, u = 0xC i, 0xC × 0xC | ported |
| Board sounds | `dget.c:480–549` | △ 4; pick 3; refused 0xB; move 2; START on a cup 3, on empty 0xB (bank 0) | ported |
| Board key order | `dget.c:479–551` | cancel, confirm, left, right, up, down, START; one per frame | ported |
| Box 3 from the board | `dget.c:303–317` | flags 0xC1; origin (cell x, cell y, 0x2A, 0xD); rect (−0x7E, −0x31, 0xFC, 0x63); `registerTextbox(3, 0, 7, 0, 0)` | ported |
| Box 3 after picking | `dget.c:297–317` | flags 0xE1; origin entity `pstat 254`; rect (−0x7E, −0x4F, 0xFC, 0x63); `registerTextbox(3, 8, 7, 0, 0)` | ported |
| Box 3 text | `dget.c:319–327` | the cup's entry 0 (+2: past the `SHOW_TEXTBOX` op) through `showTextboxReady(3, 0xFF)` | ported |
| Box 3 render | `dget.c:651–659` | 7 rows: `renderString(0, x + 6, y + 3 + 13 i, 0xF0, 0xC, 0, uvY + 12 i, 3, 1)` | ported |
| Box 3 closes (board mode only) | `dget.c:633–640` | box 3 state 1, after-dialogue, START / ✕ / △; sound 3 | ported |
| Register as "tomorrow" | `dget.c:727–728` | column ≠ 0 → `(DAY + 1) \| 0x80` | ported |
| 0x21 values | `script_interp.c:1801–1812` | triggers 37–39; value 2 = 0x16 if `DAY == 0x16` else 0x95; value 3 = 0x16; value 4 = partner type | ported (cup id from data, §5.2) |
| Opponents | `utils2.c:586, 625–657` | 7 | ported |
| Pool buffer | `utils2.c:596` | 0x70 bytes, not cleared | ported (open question §8.1) |
| Cup with the unfiltered pool | `utils2.c:603` | cup 0x16: the list is taken whole, no trigger test | ported: `systems/tournaments.open_pool` |
| Rounds to win | `utils2.c:665–669` | 2 for cup 5 (Grade R), else 3 | ported: `rounds_to_win` |
| Cup won trigger | `utils2.c:674` | cup id + 15 | ported: `won_trigger` |
| Counter limits | `utils2.c:673, 679, 680` | `enforceStatsLimits` 0x11 won, 0x12 wins, 0x13 lost | ported (`script_stat_limits`) |
| After the tournament | `utils2.c:663–664`, `map.c:5445–5455` | tamer state 0, partner state 1; unset trigger 37 | ported; the `addObject` calls are port-only no-ops (the port never removed the clock / map / poop objects) |
| Medal ids | `tournament.c:37–39` | 0, 1, 2, 3, 4, 0xC | data (`systems/tournament_medals`) |
| Medal groups | `tournament.c:173–209` | triggers 15 + 0..5, 21 + 0..4, 26 + 0..6, 33 + 0..3 | ported: data `cups` (§5.2) |
| Total wins medal | `tournament.c:213` | `TOURNAMENT_WINS >= 100` | ported: data `min_wins` |
| Card medal | `tournament.c:218–225` | cards 0..0x41 each ≥ 1, and trigger 50 | ported: data `all_cards`, `trigger` |
| Medal trigger | `script_common.c:3026–3036` | 0x16C + medal, only `medal < 0x13` | ported |
| Medal box | `tournament.c:252–255` | `showMapHeadTextbox(result, 0xFF, 0, 0x4DB)`; state 1, next state 0, mode 1 | ported |
| Wait for the arena | none | routine 0x06 waits until the arena node says it's done | **port-only:** `STD_tournamentMain` runs its own frame loop inside the call; the port can't block a frame |
| The arena | `utils2.c:661–662` | `loadDynamicLibrary(STD_REL)`, `STD_tournamentMain({cup, opponents[7]})` → rounds won | **stand-in** until 4e-4 (§5.4) |

## 4. Behaviour

### 4.1 The cup data (section 0x0A of the active script)

`getCupDataJumpTable(0x0A, id)`:
- `section = getScriptSection(script, 0x0A)`;
- the cup's table is at `script + u16(section + id * 4 + 2)`. Section 0x0A is 23 `JUMP_TO`s, 4 bytes each, and the u16 is the target.

`getCupDataJumpTableEntry(table, k)` = `script + u16(table + k * 4 + 2)`. Each cup has five entries:

| k | Points to | Read as (after +2, past the opcode) |
|---|---|---|
| 0 | a `SHOW_TEXTBOX` | the 7-line cup info (box 3) |
| 1 | a `DATA` (op 0x6B) | `minTriggers, minWins, reqType` |
| 2 | a `DATA` | Digimon ids, ending at a byte ≥ 0xFE: over-levelled |
| 3 | a `DATA` | Digimon ids: eligible |
| 4 | a `DATA` | Digimon ids: the opponent pool. A first byte ≥ 0xFE means "the whole roster" |

Section 0x0B (+2) is one more Digimon list (`reqType` 2).

A cup can share another's entry: cup 0x16's info is the Humanoid Cup's text (script 213: both point at 10648). The table keeps that: both records carry the same text.

In the port these bytes become the `cup` record (§5.2): `requirement` from entry 1, the lists from entries 2–4 (each up to its first byte ≥ 0xFE), `opponents = null` when entry 4's first byte is ≥ 0xFE, and `info` from entry 0.

### 4.2 Is it held, can the partner enter (`dget.c:331–446`)

**`is_enabled(id)` (`isTournamentEnabled`)**, with the record's names in brackets:
- `minTriggers == 0` (`requirement.min_roster`) → true.
- `count` is computed from list 4 (`opponents`):
  - if its first byte is < 0xFE: the number of its ids with `200 + id` set;
  - otherwise (`opponents == null`): the number of triggers set in 200…311.
- `count < minTriggers` → false.
- Then by `reqType` (`requirement.also.type`):
  - **0** (`none`): true.
  - **1** (`won`): trigger 18, i.e. Grade A won: the `won_trigger` of `also.tournament` (3).
  - **2** (`count`): the number of section 0x0B ids (`also.list`) with `200 + id` set must be ≥ `minWins` (`also.min`).
  - **any other value** (`count_until`, `also.until` = `reqType`): count the list-4 ids with `200 + id` set, **stopping at the first id > `reqType`** (`while ((t = *p++) <= reqType)`); the count must be ≥ `minWins`. The loop stops at the first larger id, even if smaller ones come after it (lists are not sorted, e.g. the Dino Cup's starts 3, 4, 8, 5). Keep this.
- Otherwise false.

**`is_eligible(id)`:** the partner's type (`PARTNER_ENTITY.type`) is in list 3.

**`is_overleveled(id)`** (`tournamentCheckFair`): the partner's type is in list 2.

### 4.3 The board table (`fillEnabledTournamentTable`)

- For `j` in 0..4, with `day = DAY + j`: copy the ids of `TOURNAMENT_SCHEDULE[(day % 30) * 6 …]` up to 0xFF, keeping only `is_enabled` ones, packed into `buf[j * 6 …]`.
- Then for the columns `start..1`, where `start = 0` if `minutes <= 600`, else 1. For each cell up to the first 0xFF: `|= 0x80` if eligible, `|= 0x40` if over-levelled.
- Columns 2–4 never get bits: they are shown in colour 3 and can't be picked.

### 4.4 The board (boxes 1 and 2)

**Building (`buildScheduleLabels`, `buildScheduleEntries`):** boxes, rects and lines as in §3.
- Row 9 holds the day header.
- Rows 10–15 hold the grid, one row per slot, 5 cells each. The last row is terminated with `terminateString(…, 1)`, the others with 0.
- Then `box[2].pageReady = 1` and `writeCount++`, so the rows are drawn without the text reveal.

**Tick (`tickTournamentSchedule`, box 2's tick):** only when box 3 is closed, box 2 is open (state 1) and `isXPressedAfterDialogue`. One key per frame, in this order:
- **△:** `state_2 = 3`, sound 4.
- **✕:** if the cell isn't empty and has bit 0x80 or 0x40: `value 3 = id & 0x3F`, `state_2 = 3`, sound 3. Else sound 0xB.
- **← / →:** the column, wrapping 0↔4; **↑ / ↓:** the row, wrapping 0↔5. Sound 2 each.
- **START:** on a non-empty cell, `initTournamentInfo(0)` and sound 3; else sound 0xB.

**Render (`renderTournamentSchedule`, `renderTournamentTextbox`):** as in §3, every frame while the box is drawn.

### 4.5 The cup info (box 3, `initTournamentInfo(arg)`)

- `MAIN_D_801353B0 = arg`. The board's tick closes box 3 only when it is 0.
- The flags, rect, origin and text row depend on `arg` (§3).
- The cup is the selected cell's id `& 0x3F`.
- The text: `SCRIPT_POINTER` is saved, set to entry 0 + 2, `showTextboxReady(3, 0xFF)` runs, then the pointer is restored. `ACTIVE_INSTRUCTION = CALL_ROUTINE` (the routine keeps waiting).
- In the port, the text comes from the record's `info.raw` (the `SHOW_TEXTBOX` instruction's bytes). The routine points the script context's code at those bytes, sets the pointer to 2, calls `show_textbox_ready(3, 0xFF)`, and restores both, as the C does with `SCRIPT_POINTER`.

### 4.6 Builtin 0x12 (`initTournamentSchedule`)

`CALL_ROUTINE` sets `state_2 = 0` and mode 0 (the interpreter does this already).

| State | Does |
|---|---|
| 0 | trigger 37 set → `ACTIVE_INSTRUCTION = 0` (nothing). Else: the 30-byte table (0xFF), `value 3 = 0xFF`, `fillEnabledTournamentTable`, `triggerBoxCloseFlag(0)`, repeat mask 0xF000, boxes 1 and 2; → 2 |
| 1 | free the table; `ACTIVE_INSTRUCTION = 0` |
| 2 | wait (the boxes and the text boxes move it on) |
| 3 | mask 0; `triggerBoxCloseFlag(2)`, `(1)`. If `value 3 == 0xFF` → 1. Else `initTournamentInfo(1)`. If over-levelled: line 3 of 0x4D8, owner `value 254`, box 0, and set trigger 40. Otherwise line 2 and unset trigger 40. Then → 2, next 4, mode 1 |
| 4 | `showMapheadSelection(4, 0xFD, 2, …, 0x4D8)`: the tamer chooses; → 2, next 5, mode 2 (Enter → 5, Don't enter → 6) |
| 5 | `triggerBoxCloseFlag(3)`; set triggers 37, 38, 39; value 2 = `DAY`, or `(DAY + 1) \| 0x80` if column ≠ 0; value 4 = partner type; → 1 |
| 6 | `triggerBoxCloseFlag(3)`; → 1 |

### 4.7 The registration tick (`updateTournamentRegistration`, every field frame, before the script)

Only while trigger 37 is set. The first test that fails ends the frame's tick, **and the map's light update is skipped on those frames**:

1. The partner's type ≠ value 4 → unset 37, return.
2. Value 2 has bit 0x80 (registered for tomorrow) → return.
3. `flag = (DAY != value 2)`.
4. `minutes < 720` → return.
5. `minutes >= 1381` → `flag = 1`.
6. A script is running (`IS_SCRIPT_PAUSED == 0`) → return.
7. The tamer's state ≠ 0, or the partner's state ≠ 1, or any of UI boxes 0–5 has state ≠ 0 → return.
8. `flag` → `callScriptSection(0, 0x4DA, 1)`, unset 37, return.
9. `minutes < 1200`:
   - trigger 38 unset → return;
   - otherwise unset it.

   From 1200 on, the same with 39.
10. `callScriptSection(0, 0x4D9, 1)`.

Then (step 10 falls through, or 37 wasn't set) `updateMapLightState()`. The port's `MapSession.update_map_light_state` moves here: `Field._frame` calls the registration tick where it calls the light update today (`field.gd:322`), and the tick calls the light update on the C's paths only.

**Quirks kept** (they're the C's):
- While registered for tomorrow, and on the registration day before 12:00, File City's lights don't update.
- Registering for tomorrow on day 29 stores 30, which `DAY` (0–29) never equals: at 12:00 the next day comes the missed-it scene.

### 4.8 Builtin 0x21 (the Beetle Cup at Beetle Land)

This builtin doesn't wait.
- Set triggers 37, 38, 39.
- Value 2 = 0x16 if `DAY == 0x16`, else 0x95. 0x95 is "tomorrow" with day 0x15, a C oddity, kept.
- Value 3 = the cup 0x16.
- Value 4 = the partner's type.

Script 102 then runs builtin 0x06 at once. The cup id comes from data (`registered_by_builtin_0x21`, §5.2). The day 0x16 is a calendar day, not a record id, so it stays a constant with its C line. Fix the existing comment ("the arena's daily setup") in `script_interpreter.gd:1392`.

### 4.9 Builtin 0x06 (`scriptStartTournament` + `startTournament`)

| State | C | Port |
|---|---|---|
| 0 | → 2 | same |
| 2 | `closeBox(0)`; `startTournament()` (runs the whole arena); `ACTIVE_INSTRUCTION = 0` | `closeBox(0)`; the draw; `stopBGM`; `arena.start(cup, opponents)`; → 7 (**port-only** wait state) |
| 7 | — | when `arena.finished`: the bookkeeping below; `ACTIVE_INSTRUCTION = 0` |

**The draw** (`utils2.c:592–657`), with `id = value 3`. Build `pool` from list 4:
- **first byte < 0xFE:**
  - cup with `open_pool`: every listed id;
  - otherwise: the listed ids with `200 + id` set.
- **otherwise:** every `i < 0x70` with `200 + i` set.

Then, by `count`:
- **`count == 7`:** the first 7.
- **`count < 7`:**
  - all of them;
  - then `pool[random_limit(count)]` until there are 7.
- **`count > 7`:**
  - remove the partner's type (its first occurrence, `count--`);
  - then 7 times: `k = random_limit(count) + 1`, take the k-th entry that isn't 0xFF, mark it 0xFF, `count--`.

In the `≤ 7` cases the partner's own type is **not** removed. `Rng.random_limit` is the C's `randomLimit`.

**After** (`utils2.c:663–681`):
- `reinitializeAfterTournament`: tamer state 0, partner state 1.
- Unset trigger 37.
- Read `id = value 3` again.
- If `result == rounds_to_win(id)`: `tournaments_won + 1` (limit 0x11), set `won_trigger(id)`. Otherwise `tournaments_lost + 1`.
- `tournament_wins += result` (limit 0x12); `tournaments_lost` limit 0x13.
- Value 0xFF = `result`.

Script 213 then advances the clock 6 h and warps.

**Quirk kept** (found 2026-11-01 in step 1's data): the Beetle Cup's `won_trigger` is 0x16 + 15 = 37, the registered trigger. Winning it clears 37 (`:664`), then sets it again (`:674`). The partner stays registered (values 2–4 still name the Beetle Cup), and the registration tick (§4.7) plays the missed-it scene (0x4DA) on a later day at 12:00. To compare with the real game (§8.4).

### 4.10 Builtin 0x16 (the medal check)

- **At `CALL_ROUTINE`** (`script_interp.c:1662`): if `check_medal_conditions() == -1`, the builtin is a no-op (no wait). Otherwise it waits like the others.
- **State 0:**
  - `r = check_medal_conditions()`; `-1` → `ACTIVE_INSTRUCTION = 0`.
  - Otherwise `unlockMedal(medal[r])`, then line `r` of 0x4DB in box 0 (owner 0xFF), state 1, next 0, mode 1.
  - After ✕, the text box sets state 0 again and it re-checks. The condition just rewarded is still the first one met, and its medal is now owned, so the re-check gives -1 and the builtin ends. **One medal per call**: a later medal comes on a later call, once an earlier condition is no longer fully met.
- **`check_medal_conditions`:** the conditions are tested in order 0..5, and the **first fully met** one is returned.
  - Condition 4 is `tournament_wins >= 100`.
  - Condition 5 is every card ≥ 1 and trigger 50.
  - If that medal is already owned → -1, without testing the later ones (`systems.md` "Quirk to keep").


## 5. Godot design

### 5.1 The data

Logic reads properties, not cup ids (`specs/content.md` §4).

**a. Data porter (`systems/tournaments`, `systems/tournament_medals`).** New fields, each with its C check:

| Table.field | Value | Derived from (the converter checks this C text) |
|---|---|---|
| `tournaments.won_trigger` | id + 15 | `utils2.c:674` `setTrigger(id + 15)`; equals `TRIGGER_D_RANK_CUP_WON` (15) + id |
| `tournaments.rounds_to_win` | 2 for id 5, else 3 | `utils2.c:666–669` `if (id != 5) expected = 3; else expected = 2;` |
| `tournaments.open_pool` | true for id 0x16, else false | `utils2.c:603` `if (id != 0x16)` |
| `tournaments.registered_by_builtin_0x21` | true for id 0x16, else false | `script_interp.c:1810` `writePStat(3, 0x16)` |
| `tournament_medals.cups` | conditions 0–3: tournament ids [0..5], [6..10], [11..17], [18..21]; absent on 4, 5 | `tournament.c:173–209`: base triggers 15 / 21 / 26 / 33 (`trigger.h:805–818`), counts 6 / 5 / 7 / 4; id = trigger − 15 |
| `tournament_medals.min_wins` | 100 on condition 4 | `tournament.c:213` |
| `tournament_medals.all_cards`, `.trigger` | true and 50 on condition 5 | `tournament.c:218–225` (`i < 0x42`, `TRIGGER_BEATEN_GAME_ONCE` = 50); the converter checks 0x42 = the number of `items/card_data` records |

Also in `data_porter/specs/systems.md`: the fields, and line 265's "not traced" pointing to this spec.

**b. Asset porter (`scripts` family): `output/scripts/tournament_cups.json`.** It is made from script 168's sections 0x0A / 0x0B, with the reading of §4.1. One record per cup (23, index = tournament id):

```
{"id": 0,
 "requirement": {"c_values": [0, 0, 0], "min_roster": 0, "also": {"type": "none"}},
 "overleveled": [12, 13, ...], "eligible": [3, 4, ...], "opponents": [3, 4, 17, ...],
 "info": {"raw": "1a00817c...", "text": "- Grade D -\nContest featuring\n...", "offset": 3342},
 "source": {"script": 168, "cup_table": 3322, "entries": [3342, 10002, 10084, 10124, 10528]}}
```

- **`requirement.also`, by `reqType` (`c_values[2]`):**
  - 0 → `{"type": "none"}`;
  - 1 → `{"type": "won", "tournament": 3}`;
  - 2 → `{"type": "count", "list": <section 0x0B ids>, "min": minWins}`;
  - ≥ 3 → `{"type": "count_until", "until": reqType, "min": minWins}`.

  For `won`, the converter reads `case 1: return isTriggerSet(TRIGGER_GRADE_A_CUP_WON)` in `dget.c` and `TRIGGER_GRADE_A_CUP_WON` = 18 in `trigger.h`, and checks 18 − 15 = 3.
- **`opponents`:** `null` when entry 4's first byte is ≥ 0xFE (Grade R).
- **Lists:** Digimon ids in script order, up to the first byte ≥ 0xFE. Numeric ids are the `dw1` aliases.
- **`info.raw`:** the `SHOW_TEXTBOX` instruction's bytes, which the box reads from byte 2. **`info.text`:** the disassembler's text, for people.
- **Checks:**
  - 23 cups;
  - scripts 213, 102 and 209 give the same values (requirement, lists, `info.raw`) as 168;
  - every list id < 0x70;
  - the `reqType` mapping above.

  The family's spec (`asset_porter/specs/scn.md`) and `PROGRESS.md` get a section.

**c. `GameData`:**
- `tournament_cup(ref) -> Dictionary`: that record by tournament id or key, loaded with `Content.load_json("scripts/tournament_cups.json")`; `{}` when missing.
- The tournament entity view gets it as the component `cup` (`_components_tournament`). A pack-added tournament brings its own `components.cup`.

### 5.2 Code

Every class names the C function each method ports. Constants carry their C line (`## dget.c:125`) or status.

**`scripts/systems/tournament_cups.gd`** (`class_name TournamentCups`, `RefCounted`, headless): the logic of §4.2, 4.3, 4.9 (draw, counters) and 4.10, on the `cup` records.

```
const ROSTER_TRIGGER := 200        # dget.c:371 TRIGGER_OGRE_FORTRESS_OPENED
const ROSTER_SIZE := 0x70          # utils2.c:617; dget.c:385 (200..311)
const BOARD_DAYS := 5              # dget.c:109
const BOARD_SLOTS := 6             # dget.c:111
const ELIGIBLE := 0x80             # dget.c:138
const OVERLEVELED := 0x40          # dget.c:141
const ID_MASK := 0x3F
const EMPTY := 0xFF
const TODAY_UNTIL := 600           # dget.c:125
const OPPONENTS := 7               # utils2.c:586
func _init(game_state: Node, game_data: Node)
func is_enabled(id: int) -> bool                                    # isTournamentEnabled
func is_eligible(id: int, digimon_type: int) -> bool                # tournamentCheckEligible
func is_overleveled(id: int, digimon_type: int) -> bool             # tournamentCheckFair
func fill_board(day: int, minutes: int, digimon_type: int) -> PackedByteArray   # 30 bytes
func draw_opponents(id: int, digimon_type: int) -> Array            # 7 Digimon ids
func finish(id: int, result: int) -> void                           # utils2.c:664-681, without reinitializeAfterTournament
func medal_condition() -> int                                       # checkTournamentMedalConditions
func medal_of(condition: int) -> int                                # TOURNAMENT_MEDAL_IDS[condition]
```

- `finish` caps the counters with `data.script_stat_limit(0x11 / 0x12 / 0x13)`.
- `draw_opponents` uses `Rng.random_limit`.
- **An empty pool** (port-only, §8.1): a list cup draws from its whole list (as an open pool), with a `push_warning`; Grade R (no list: the roster) gives 7 × 0xFF. Decided 2026-11-02 (was 7 × 0xFF, which gave the arena ghost opponents).

**`scripts/systems/tournament_registration.gd`** (`class_name TournamentRegistration`, `RefCounted`): §4.7.

```
signal section_requested(section: int)
const SECTION_REMINDER := 0x4D9    # tournament.c:116
const SECTION_MISSED := 0x4DA      # tournament.c:97
var script_paused: Callable        # -> bool: IS_SCRIPT_PAUSED != 0
var tamer_state: Callable          # -> int
var partner_state: Callable        # -> int
var partner_type: Callable         # -> int
var boxes_closed: Callable         # -> bool: UI boxes 0-5 all in state 0
func _init(game_state: Node)
func tick() -> bool                # updateTournamentRegistration; true = updateMapLightState runs
```

The clock comes from `game_state.state.clock` (`day`, `hour`, `minute`).

**`scripts/field/hosts/tournament_host.gd`** (+ `scenes/field/hosts/tournament_host.tscn`, under `Systems`):
- owns the `TournamentRegistration` and fills its callables from the field's parts;
- connects `section_requested` to `interpreter.call_section(0, section, 1)`, as `CareHost` does;
- `tick()`: `Field._frame` calls it where it calls `map_session.update_map_light_state()` today (`field.gd:322`). It calls that light update when the registration's `tick()` returns true.

Also fix the stale comment at `map_session.gd:117`.

**`scripts/script/tournament_routines.gd`** (`class_name TournamentRoutines extends MenuRoutines`) + `scenes/script/tournament_routines.tscn`, a child of `ScriptRoutines` in `field.tscn`:
- `var routines: Array = [0x06, 0x12, 0x16, 0x21]`.
- `var cups: TournamentCups` and `var board: TournamentBoard`, made in `configure`.
- `start(0x16)` returns false when `cups.medal_condition() == -1` (`script_interp.c:1662`).
- `start(0x21)` does §4.8 and returns false.
- The states use the C's numbers: 0x12's 0–6 and 0x06's 0 / 2 / 7, where 7 is the port-only wait.
- **0x06** calls `host.sound.music.stop_bgm()` when there is a sound system (`utils2.c:660`), then `host.arena.start(cup, opponents)`. When `host.arena.finished`:
  - `cups.finish(id, host.arena.result)`;
  - the tamer's state 0 and the partner's state 1 through `host.interpreter.tamer / .partner` when set (`map.c:5453–5454`);
  - `ACTIVE_INSTRUCTION = 0`.
- **Remove** the 0x21 branch from `ScriptInterpreter._call_routine`.

**`ScriptRoutines.arena: Node`:** set by the field's host after `configure`, like `interpreter`.

**`scripts/field/arena_stand_in.gd`** (`class_name ArenaStandIn extends Node`) + `scenes/field/arena_stand_in.tscn` under `Systems`: §5.4.

```
@export var stand_in_result := 0
var finished := false
var result := 0
var last_cup := -1
var last_opponents: Array = []
func start(cup: int, opponents: Array) -> void
```

**`scripts/ui/tournament_board.gd`** (`class_name TournamentBoard`, `RefCounted`, like `KeeperMenu`): boxes 1–3 on `TextBoxes`, §4.4–4.5.
- `var table: PackedByteArray` (`DGET_BUFFER`);
- `var column := 0`, `var row := 0` (`TOURNAMENT_SELECTED_COLUMN / ROW`);
- `var info_from_board := 0` (`MAIN_D_801353B0`);
- `open(table, owner)`: `buildScheduleLabels` + `buildScheduleEntries`;
- `open_info(arg, cup_record)`: `initTournamentInfo`;
- the box ticks and renders.

Sounds go out through `textboxes.sound.emit(id)`, as `ItemMenu._sound`.

**Wiring rules** (`specs/scenes.md` §3): references through exports or the hosts' `configure`, no tree lookups, autoloads injected.

### 5.3 The day header and the font

- `intToStringSJIS(n, 2, 0)` is `TextBoxes.int_to_string_sjis(n, 2, 0)`.
- The US grade letters are ASCII, drawn by `drawString2` through `convertAsciiToJis`.
- Nothing new in the text renderer.

### 5.4 The arena stand-in

**`ArenaStandIn`** (stand-in until 4e-4):
- `start(cup, opponents)` keeps them in `last_cup` / `last_opponents`.
- It logs "arena not ported (4e-4): cup <name>, opponents <names>" (`push_warning`).
- It sets `result = stand_in_result` and `finished = true` in the same call. The routine resets `finished` before calling `start`.
- After it, the field's music stays stopped until the script's next music command; `reinitializeAfterTournament` doesn't restart it either. 4e-4 rechecks this.

The debugger's **Partner** tab gets:
- a "Tournament result" spin box (0–3) bound to `stand_in_result`;
- a "Registration" label: the cup, the day (with "tomorrow"), triggers 37–40.

## 6. Order of work

Each step lists the files it owns; it changes no other file. Each has a complexity and a model (`docs/agent_workflow.md`). All suites and the scans pass after every step. A step is done when its gate in the acceptance tests passes (§7).

| Step | What | Files | Complexity · Model |
|---|---|---|---|
| 1 | Data porter fields §5.1a + checks + spec + `PROGRESS.md` | `data_porter/dwdata/groups/systems.py`, `data_porter/specs/systems.md`, `data_porter/PROGRESS.md` | **Low** · Gemini 3.8 Flash (High): values from listed C lines, the acceptance test decides |
| 2 | Asset porter `tournament_cups` §5.1b + checks + spec + `PROGRESS.md`; `GameData.tournament_cup` and the `cup` component §5.1c | `asset_porter/dwporter/families/scripts.py`, `asset_porter/specs/scn.md`, `asset_porter/PROGRESS.md`, `scripts/data/game_data.gd` | **Low** · Gemini 3.8 Flash (High): a byte reading fully given in §4.1, the tests decide |
| 3 | `TournamentCups` | `scripts/systems/tournament_cups.gd` | **Low** · Gemini 3.8 Flash (High): logic only, all in §3–4 |
| 4 | `TournamentRegistration`, `TournamentHost`, the `Field._frame` change | `scripts/systems/tournament_registration.gd`, `scripts/field/hosts/tournament_host.gd`, `scenes/field/hosts/tournament_host.tscn`, `scenes/field/field.tscn`, `scripts/field/field.gd`, `scripts/field/hosts/map_session.gd` (comment) | **Medium** · Claude Sonnet 5.5 (Medium): several systems wired, the frame order |
| 5 | `TournamentRoutines` (0x06, 0x12's states, 0x16, 0x21), `ArenaStandIn`, `ScriptRoutines.arena`, the debugger rows; 0x21 out of the interpreter | `scripts/script/tournament_routines.gd`, `scenes/script/tournament_routines.tscn`, `scripts/field/arena_stand_in.gd`, `scenes/field/arena_stand_in.tscn`, `scripts/script/script_routines.gd`, `scenes/field/field.tscn`, `scripts/field/hosts/script_host.gd`, `scripts/script/script_interpreter.gd`, `scripts/debug/partner_tab.gd` | **Medium** · Claude Sonnet 5.5 (Medium) |
| 6 | `TournamentBoard`: boxes 1–3, the rows, the lines, the cursor, the US title and header | `scripts/ui/tournament_board.gd` | **Hard** · Claude Opus 5.5 (Medium): the `renderString` / text-area layout needs interpretation (row 8 cut, header packing) and only the screen judges it |
| 7 | VERIFY "Tournament entry", `PLANS.md`, this spec's "As built", the gates removed | `VERIFY.md`, `PLANS.md`, `specs/tournament_entry.md`, the three test files | main session |

Steps 5 and 6 are tested together: 0x12's checks need both, so gate 6 holds them and gate 5 holds the rest of the routines. Step 5 may use a stub board meanwhile, which step 6 replaces.

## 7. Tests (acceptance checks)

Written by the main session before the steps (`docs/porting_checklist.md` §6). The implementer doesn't change them; a check that looks wrong is reported with its C line. `DW_STEP_4E_3=<n>` runs the checks of steps 1..n; the others print PENDING.

- **`data_porter/tests/test_tournament_fields.py`** (step 1): the §5.1a fields on the real decomp.
- **`asset_porter/tests/test_tournament_cups.py`** (step 2): the table on the real dump.
- **`tests/test_tournament.gd`** (steps 2–6), headless, with the real data:
  - **step 2:** `GameData.tournament_cup` and the `cup` component;
  - **step 3:** `TournamentCups` (enabled, eligible, over-levelled, board, draw, finish, medals);
  - **step 4:** `TournamentRegistration` (§4.7, with fake callables);
  - **step 5:** builtins 0x06 (with `ArenaStandIn`), 0x16, 0x21 through the interpreter, and 0x21 gone from it;
  - **step 6:** builtin 0x12 end to end (board, info box, choice, registration), the row bytes, the cursor, the repeat mask.

`tests/test_rules.gd`, `tests/exit_scan.tscn` and every other suite stay green.

Not in the suite (VERIFY, in game): the board's look (lines, cursor, colours, title), the reminder scenes in the field, the tamer / partner states after the tournament.

## 8. Open questions

1. **An empty pool.** For a list-based cup with none of its roster triggers set, `count` is 0, and `pool[randomLimit(0)] = pool[0]` reads the array's old memory (`allocateArray` doesn't clear) 7 times. **Decided 2026-11-01 (port-only):** 7 × 0xFF, with a warning. **Changed 2026-11-02 (the user):** a list cup draws from its whole list instead (the arena got 0xFF opponents: a ghost with stats and no model, found in play from a debugger save with no roster); Grade R keeps 7 × 0xFF. Still open: which roster triggers are set at a new game?
2. **Box 1's line cut** (`TEXTBOX_LINES_PTR[0x210] = 0x0D`, row 8 byte 16) and the US `drawString("Tournament")` both write row 8. The visible result should be "Tournament"; to compare with the real game.
3. **Music after the stand-in** (§5.4): to recheck with 4e-4's real flow.
4. **Winning the Beetle Cup re-registers** (§4.9): does the real game show "Darn! I forgot…" a day after winning the Beetle Cup at Beetle Land?

## As built (2026-11-01)

- **Who did what:** spec, acceptance tests and reviews in the main session (Claude Opus 5.5). Steps 1-5 by Gemini 3.8 Flash (High) through the `agy` CLI (steps 4-5 rated Medium, run on Flash by the user's choice), each reviewed and fixed before its commit. Step 6 (Hard) in the main session.
- **Step 1** (`f6fbd0c`): the data porter fields, each checked against the C text (systems 116/116 checks).
- **Step 2** (`5eb2367`): `scripts/tournament_cups.json` from script 168, the copies in 213 / 102 / 209 checked equal; `GameData.tournament_cup` and the `cup` component. The converter reads `dget.c` / `trigger.h` for its "Grade A won" check, so it needs the decomp: `PLANS.md` "Later: setting up the port on another machine".
- **Step 3** (`eb8678e`): `TournamentCups`. A missing `won_trigger` sets nothing (no `id + 15` fallback).
- **Step 4** (`234d823`): `TournamentRegistration`, `TournamentHost` (an inline node under `Systems`, like `CareHost`); `Field._frame` calls it where it called the light update.
- **Step 5** (`9d1405e`): builtins 0x06 / 0x16 / 0x21 in `TournamentRoutines`, `ArenaStandIn`, the Partner tab rows. The arena reaches the routines through `ScriptHost.arena` only.
- **Step 6:** `TournamentBoard` (boxes 1-3) and 0x12's states in `TournamentRoutines`. 0x12's `start` returns false while trigger 37 is set (the C's state 0 ends at once). The board's texts follow the C per language (US, EU, JP branches of `dget.c`); only US is checked. The info box reads the cup's `info.raw` with the script context's code pointed at it (the C's `SCRIPT_POINTER` swap).
- **To check in the game** (VERIFY "Tournament entry"): the board's look against the original; §8.2 (the title row), §8.4 (the Beetle Cup's re-registration).

