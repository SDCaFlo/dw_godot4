# Clock (port spec)

Status: implemented 2026-10-23 (`scripts/core/game_loop.gd`, `scripts/core/rng.gd`, `scripts/systems/clock.gd`, `clock_hud.gd`, the fade in `scripts/field/field_map.gd`; test `tests/test_clock.gd`; human checks in `VERIFY.md`).

The game clock: time passing on the field, its effects on the partner and the day, the day / evening / night change of the maps, and the clock HUD. State fields are in `specs/game_state.md` (`clock`, `partner.care`, `script`).

## 1. C functions reproduced

| C (`external-resources/dw_decomp/`) | What | Godot |
|---|---|---|
| `gameLoop` `VSync(3)` (`src/main/main.c:3958`) | the game runs at 20 frames per second (NTSC) | `GameLoop` autoload: `frame` signal at 20 Hz |
| `addClock` (`clock.c:90`) | adds the clock and playtime objects when play starts | the field scene's `Clock` node |
| `tickGameClock` (`clock.c:96–172`) | one game frame of the clock | `Clock.tick_game_clock()` |
| `tickPlaytime` (`clock.c:174`) | playtime, real minutes | `Clock.tick_playtime()` |
| `advanceToTime` (`clock.c:194`) | jump to an hour (sleeping, scripts) | `Clock.advance_to_time(hour, minute)` |
| `stopGameTime` / `startGameTime` (`clock.c:300–308`) | `IS_GAMETIME_RUNNING` | `Clock.running` |
| `dailyPStatTrigger` (`script_common.c:1399`) | once per new day | `Clock.daily_update()` |
| `addTamerLevel` (`tamer.c:1309`) | chance to change the tamer level | `Clock.add_tamer_level(chance, amount)` |
| `randomLimit` (`math.c:5`) | `(limit * rand()) >> 15` | `Rng.random_limit(limit)` |
| `updateTimeOfDay` (`map.c:4301`) | palette for the current hour, on map load / time jumps | `Clock.time_of_day()` + `FieldMap.set_time_of_day` |
| `renderMap` hour check (`map.c:3967–3980`), `initializeDaytimeTransition` (`map.c:4500`), `tickDaytimeTransition` (`map.c:4527`) | fade to the next palette at 16:00, 20:00, 06:00 | `Clock` starts it, `FieldMap.start_daytime_transition()` / `tick_daytime_transition()` |
| `renderGameClock`, `updateMinuteHand`, `initializeClockData` sprite set-up (`clock.c:212–298`) | the clock HUD | `ClockHud` |

## 2. Original behaviour

### 2.1 Game clock tick (`tickGameClock`, every game frame)

1. `LAST_HANDLED_FRAME = CURRENT_FRAME`.
2. Nothing else happens when the game isn't in the normal field state (`GAME_STATE != 0`), while fishing, when the map layer is off (menus), or when game time is stopped (`IS_GAMETIME_RUNNING == 0`, e.g. during scripts).
3. Speed = script value 0 (`PSTAT_TIME_SPEED`, `pstat.h:261`):
   - **3:** reset to 0 while time runs (`clock.c:109–111`); the speed is then read again (now 0), so the tick goes on at normal speed. The `timeSpeed == 3` return after it (`:115`) can only be reached when `IS_GAMETIME_RUNNING` is neither 0 nor 1, which no code sets.
   - **0 (normal):** frame + 1.
   - **1 (double):** frame + 2, kept even.
   - **2 (half):** a sub-frame counter; the frame advances every second tick.
4. A minute passes when `CURRENT_FRAME % 20 == 0` (at half speed: only on the ticks that advanced the frame).
   - **Every 60 minutes (new hour):** `evoTimer + 1`, `remainingLifetime − 1`, sub-frame counter reset.
   - **Every 24 hours (new day):**
     - `age + 1`, `DAY + 1`, `HOUR = 0`, `CURRENT_FRAME = 0`;
     - the daily update (§2.3);
     - `remainingLifetime` clamped at 0.
   - **Every 30 days (new year):** `DAY = 0`, `YEAR + 1`, then the tamer level may change:
     - happiness exactly 100: 5 % chance of +1;
     - happiness below 0: 10 % chance of −1.
5. `YEAR` wraps at 100.
6. The minute hand turns (`MINUTE * 0x6000`: 6° per minute), and the music is updated (`updateBGM`, not ported yet).

### 2.2 Playtime (`tickPlaytime`, every frame, also while game time is stopped)

- `PLAYTIME_FRAMES + 1`; every 1,200 frames (one real minute) `PLAYTIME_MINUTES + 1`.
- At 60 minutes: `PLAYTIME_HOURS + 1`, minutes and frames reset.
- Hours are capped at 999, and at 999 the minutes stay at 59.

### 2.3 Daily update (`dailyPStatTrigger`)

- **Card shop stock** (`script.card_shop`): re-rolled as 6 random card ids 1–64, never card 4 (`randomLimit(0x40) + 1`, retried on 4).
  - **Quirk kept:** the duplicate check compares with the slot being filled, not the other slots, so duplicates are possible.
- **Counters:** script values 0x1C–0x1F + 1, unless they are 0xFF.
- **Tournament day:** script value 2 loses bit 7 (unless it is 0xFF).

### 2.4 Time jump (`advanceToTime(hour, minute)`)

- **If the target is earlier in the day than now:** a new day starts first (`DAY + 1`, `age + 1`, daily update, year rollover at 30 days, but no tamer-level roll).
- Then `HOUR = hour % 24`, `MINUTE = minute`, `CURRENT_FRAME = HOUR * 1200 + MINUTE * 20`.
- **Quirk kept:** the comparison uses `hour` before the `% 24`, so a target of 24 or more never starts a new day. `advanceToTime(25, 0)` at 10:00 gives 01:00 of the same day. Callers that add hours must wrap them first.
- The palette is set for the new hour (`updateTimeOfDay`).

### 2.5 Time of day and the background palettes

- **`updateTimeOfDay`** (map load, time jumps):
  - maps with the "no time of day" flag (`MAP_ENTRIES.flags & 0x40`, `systems/maps.no_time_of_day`) always use palette 0;
  - otherwise: hours 16–19 evening (palette 1), hours 20–5 night (palette 2), else day (palette 0).
  
  `CURRENT_TIME_OF_DAY` is 0 for evening, 1 for night, 2 for day (the transition targets below). Map lights are scaled too (evening: green / blue × 0.7; night: × 0.5); the port has no map lighting yet.
- **On the hour** (`renderMap`), on maps with a time of day, at the first frame of an hour (`CURRENT_FRAME % 1200 == 0`):
  - hour 16 starts the fade day → evening;
  - hour 20 starts evening → night;
  - hour 6 starts night → day.

  The fade doesn't start if `CURRENT_TIME_OF_DAY` is already the target, or while the partner or tamer is in certain states (partner 8 / 0xD, tamer 0x11 / 0x13: not ported yet).
- **The fade** (`tickDaytimeTransition`): 25 frames, palette colours moved from A towards B by 1/6 (frames 0–4), 1/5, 1/4, 1/3, 1/2 (frames 20–24) of the difference, then B. It works on the 5-bit palette channels.
  
  **Port:** the backgrounds are converted per palette (`background_<p>.png`), so the port cross-fades the two pictures with the same weights. Integer rounding of the 5-bit channels is not reproduced.

### 2.6 HUD (`renderGameClock`)

- **Texture:** `ETCDAT/FI_INFO.TIM` (VRAM 896,448, palettes from row 496; asset porter `etctim/04_fi_info`, `p<n>` = palette row 496 + n). Texture coordinates map to the image as x = u, y = v − 192.
- **Positions:** relative to the screen centre (160, 120). The clock's x offset is −135 while time runs; it slides by 50 per frame to −220 (off screen) while time is stopped.

| Part | Rect in the texture (u, v, w, h) | Palette | Screen (x, y) |
|---|---|---|---|
| left bell | 192, 224, 16, 16 | 497 | off − 2, −90 |
| right bell | 192, 240, 16, 16 | 497 | off + 34, −90 |
| top icon (day / night, 4 frames) | `CLOCK_TEXCOORD_U/V[night][frame]`, 32 × 16 | 498 | off + 8, −100 |
| face | 208, 215, 48, 40 | 496 | off, −88 |
| minute hand (sprite, pivot 3, 13) | 120, 192, 8, 16 | 499 | pivot at off + 23, −66; rotated 6° per minute |
| hour marker | 203, 216, 6, 6 | 497 | off + `HOUR_POINT_X[h]`, `HOUR_POINT_Y[h]` − 88 |

- **Top icon:** "night" is hour < 6 or ≥ 17; frame = (`CURRENT_FRAME` % 16) / 4.
- **Status bars** (`renderStatusBars`): drawn with the clock; they belong to the care step.

## 3. Godot design

- **`GameLoop`** (autoload, `scripts/core/game_loop.gd`) turns Godot's variable frame rate into the original's 20 Hz game frames. It emits `frame` once per game frame, at most a few per Godot frame so a slow frame doesn't snowball. The clock, and later the partner and care, run on it, like the original's tick objects.
- **`Clock`** (`scripts/systems/clock.gd`), a node of the field scene (`addClock` happens when play starts):
  - `active`: the field is in normal play, standing in for `GAME_STATE`, fishing and the map layer;
  - `running`: `IS_GAMETIME_RUNNING`, not saved, true at start;
  - `subframe_count`: `SUBFRAME_COUNT`;
  - `current_time_of_day`: `CURRENT_TIME_OF_DAY`.
  
  It reads and writes `GameState.state` (`clock`, `partner.care`, `tamer.level`, `script`).
- **`Rng`** (`scripts/core/rng.gd`): `random_limit(n)` like `randomLimit`, on a Godot `RandomNumberGenerator`. The PSX `rand()` sequence is not reproduced, since its seed differs per run anyway. Tests can seed it.
- **`ClockHud`** (`scripts/systems/clock_hud.gd`), in the field HUD, draws §2.6 with the real texture.
- **The field scene:**
  - sets `GameState` `world.screen` / `exit` when entering a map;
  - applies `updateTimeOfDay` on map load;
  - runs the fades;
  - debug key `T` jumps one hour ahead (`advance_to_time`).

## 4. Verification

`tests/test_clock.gd`:
- speeds 0 / 1 / 2: frames per minute; speed 3 is reset to 0;
- hour, day and year rollovers and their effects on `evo_timer`, `remaining_lifetime`, `age`, the tamer level (seeded rolls), year wrap at 100;
- the daily update: card shop (never card 4), script values 0x1C–0x1F, value 2;
- `advance_to_time` across midnight;
- time-of-day hours, and maps without a time of day;
- the fade weights;
- playtime rollover and the 999-hour cap;
- nothing ticks while inactive or stopped, except playtime.

## 5. Open questions

- `updateBGM` (music by time and map) comes with audio.
- The partner / tamer states that block a fade come with the partner port.
- Map lights scale with the time of day (§2.5); the port has no field lighting yet.
