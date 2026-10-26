# Training

Status (2026-10-25): spec written for step 5e-4d-1 (`PLANS.md` 5e-4). Not coded yet.

The gyms: the partner trains a stat at a station, the stats it gains count up in a box, and an hour passes. Builtin 0x07 of `CALL_ROUTINE` runs it. This spec ports the shared core and one station end to end, **HP at the Green Gym** (TRAI00, map 0x70, the "Boulder Moving" station). It also adds the field pieces a station needs. Later steps add the rest:
- **4d-2:** the other five stations (Offense, Speed, Defense, MP, Brains), including the Brains "new orders" box and move learning (`TRN_tryLearnMove`);
- **4d-3:** the slot-machine bonus ("Bonus Try", value 0xF6 = 1: `trn_slots.c`);
- **4d-4:** the TRN2 stations of maps 0x63, 0x6B, 0x6C and 0xA5 (`src/trn2/`).

## 1. The C code

| C (US) | What |
|---|---|
| `CALL_ROUTINE` 0x07 (`script_interp.c:1682–1727`), its tick (`:459–463`), `isTrainingComplete` (`tamer.c:1342`) | the stat's setup by map; the routine waits until `TRAINING_COMPLETE` (§2.1) |
| `CALL_ROUTINE` 0x27 `loadTrainingLibrary` (`map.c:5457`) | the training overlay; `TRAINING_COMPLETE` = 0 |
| `TRN_setupHpTraining`, `TRN_tickHpTraining` (`trn/trn_hp.c:58`, `:79`) | the HP station (§2.2) |
| `TRN_awardHpTrainingGains`, `TRN_calculateTrainingMultiplier`, `TRN_advanceTrainingTime`, `TRN_saveTrainingStartTime`, `TRN_statGainsAreZero`, `TRN_createCloudFXLine` (`trn/trn_reward.c:151`, `:594`, `:721`, `:101`, `:203`, `:127`) | gains, the hour that passes, dust (§2.3–2.4, §2.6) |
| `TRN_saveBaseStats`, `TRN_applyBaseStats`, `TRN_createPostTrainingStatsBox`, `TRN_tickPostTrainingStatsBox`, `TRN_renderPostTrainingStatsBox`, `TRN_closeUIBox` (`trn/trn_hud.c:142–343`) | the stats box (§2.5) |
| `tamerTickTraining` (`tamer.c:1610`), partner state 10 (`partner.c:244`: `handleConditionBubble` only) | the tamer and partner while a station runs (§2.6) |
| `tickEntityWalkTo` (`tamer.c:991`), `createCameraMovement` (`map.c:4844`), `startAnimation` | already ported: `ScriptInterpreter._tick_walk_to`, `FieldMap` pans (`specs/camera.md` §2.3), `FieldDigimon.start_animation` |
| `storeMapObjectPosition`, `loadMapObjectPosition`, `moveMapObjectsWithLimit` (`overworld.c:790`, `:832`, `:844`) | the station's equipment: map overlay instances moved (§2.6) |
| `createCloudFX`, `tickCloudFX`, `renderCloudFX`, `removeAllCloudFX` (`efe.c:714`, `:733`, `:744`, `:702`; tables `:91–120`) | dust clouds (§2.6) |
| `callDigimonRoutine` (`partner.c:1139`) | 214, called before 0x07, is not a case: nothing happens |
| Data | `digimon_data.level`; `raise_data.training_type`, `energy_threshold`, `energy_usage`; item `passive: training_boost` (Trn. manual); the care fields (`GameState.partner.care`: `tiredness`, `energy_level`, `happiness`, `discipline`, `train_boost_flag` / `value`, `upgrade_*_counter`, …); the stat labels `STR_STAT_LABEL_*` (`text/main/ui.yaml`); `etctim/02_defeff` (the dust, VRAM 768,384, CLUT 192,488); `etctim/00_bi_in` (the "+" of the box, VRAM 896,384, CLUT 256,491) |

## 2. Behaviour

### 2.1 How a gym runs a station

**TRAI00 (script 108).** A station is a trigger cell, for example section 81 for HP.
- `CALL_ROUTINE 0x27`, then the station's title: "Boulder Moving", or "Boulder Moving, revision" once trigger 0xDB is set.
- Begin / Explain / Quit, then Normal / Bonus Try / Quit.
- **Normal:** `FADEOUT_HUD 0`, value 0xFE = the stat (0 HP, 1 Offense, 2 Speed, 3 Defense, 4 MP, 5 Brains), value 0xF6 = 0, `CALL_DIGIMON_ROUTINE 214` (nothing), `CALL_ROUTINE 0x07`.
- **Bonus Try:** the same with value 0xF6 = 1, after the "Slot Game" help text.

The other gyms (GIAS09, ICSA03, BETL03 / 04) do the same for their stats.

**Builtin 0x07 (`script_interp.c:1682`)**, before the routine waits:
- On maps 0x6B, 0x6C, 0xA5 and 0x63, `TRN2_setup…Training(map)` for stats 0–4 (4d-4).
- Everywhere else, `TRN_setup…Training(map)` for stats 0–5.

Then `ACTIVE_INSTRUCTION` = `CALL_ROUTINE`, `SCRIPT_TEXTBOX_MODE` = 0. Unlike the shops' builtins, `SCRIPT_STATE_2` is not reset.

**Its tick** ends the routine when `isTrainingComplete()`. That function returns 1 once `TRAINING_COMPLETE` is 1, and sets it back to 0.

A setup only starts its station on its own map. `TRN_setupHpTraining` acts for 0x70 only. On any other map no station starts, `TRAINING_COMPLETE` stays 0, and the script waits for good. The scripts call each stat only where its station is.

### 2.2 HP: "Boulder Moving" (`trn_hp.c`)

**Setup (map 0x70):**
- the station's point = (0x58C, 0, −0x6D0);
- the boulder = map overlay instances 0x53…0x62 (16);
- the station object is added;
- `slots` = value 0xF6;
- a Fresh or In-Training partner (`level < 3`) gets `upgrade_hp_counter` + 1;
- `TRAINING_COMPLETE` = 0.

For every map, the start time is saved (`TRN_saveTrainingStartTime`: frame, hour, minute) and the state is 0.

**The station object's tick**, one state a frame:
- **0:**
  - the boulder's 16 positions are saved;
  - tamer state 8; partner state 10, animation 4 (walk);
  - the camera moves to the point over 10 frames;
  - `playSound(8, 9)`;
  - counter = 0; → 1. (Slots, 4d-3: the slot session starts.)
- **1:** the partner (0xFC) walks to the point (`tickEntityWalkTo(0xFC, 0xFF, x, z, 0)`). When it is there:
  - animation 0x1B (pushing);
  - rotation y = 0xA00;
  - `playSound(8, 0)`;
  - → 2. (Slots: the reels start spinning.)
- **2**, every frame:
  - the partner's root motion is held (`animFlag |= 2`);
  - when `counter % 120 == 0` and `counter < 0x4B1`, it is released for that frame and the boulder moves (+1, −2): one push;
  - the boulder shakes, +2 x on even counters and −2 on odd;
  - every 10 frames, `playSound(8, 0)`;
  - three dust lines (§2.6): `(counter, 0xF, 0x550, −0x604, 0x64, −0x32, 8)`, `(counter, 0x14, 0x5B5, −0x667, 0x32, −0x32, 6)`, `(counter, 0x12, 0x514, −0x525, 0x14, −0x32, 4)`;
  - counter + 1.

  **The end:** counter ≥ 1200 (a minute), or △ held (`POLLED_INPUT & CANCEL`), with `slots` = 0. (Slots: the session's result ≥ 0.) Then:
  - counter = (counter % 1200) / 120: the pushes, 0–9;
  - `playSound(8, 0xA)`;
  - animation 0x12;
  - `TRN_awardHpTrainingGains(partner type, 0, r)` with `r` = 10 (slots: the result);
  - the camera moves back to the tamer over 10 frames;
  - → 3.
- **3:** when the box has counted all the gains (`TRN_statGainsAreZero`): wait = 0, → 4.
- **4:** wait + 1; at 20: animation 4 (walk), → 5.
- **5:**
  - counter − 1; while it is > 0, the boulder moves back (−1, +2), one push per frame;
  - the partner walks back to the tamer (`tickEntityWalkTo(0xFC, 0xFD, 0, 0, 0)`).

  When it is there and counter ≤ 0:
  - the base stats are applied (`TRN_applyBaseStats`, §2.5);
  - box 1 closes;
  - partner state 1;
  - the boulder's positions are put back (`loadMapObjectPosition`, which also clears their flag bit 0x10);
  - tamer state 0;
  - all the dust is removed;
  - the object is removed; `TRAINING_COMPLETE` = 1.

How long the partner pushes doesn't change the gains, only how far the boulder moves.

### 2.3 The gains (`TRN_awardHpTrainingGains(type, b, c)`)

**HP:** base HP 80, Offense 2; tiredness + 10, energy − 1, happiness − 1. `v = multiplier(type, mode 0, b)`.
- **HP** = `80 × v × train_boost_value / 100` if `train_boost_flag & 0x10`, else `80 × v / 10`; then `× c / 10`.
- **Offense** = the same with flag bit 0x01 and base 2.
- **Tiredness 100:** both are 1.
- **Cap:** HP ≥ 1000 becomes 999.
- **Then:**
  - the base stats are saved (`TRN_saveBaseStats`);
  - the gains = [HP, 0, Offense, 0, 0, 0] (order HP, MP, Offense, Defense, Speed, Brains);
  - the stats box opens (§2.5);
  - `TRN_advanceTrainingTime(10, 1, 1)` (§2.4).

All the arithmetic is C `int16` with truncating division.

**The multiplier (`TRN_calculateTrainingMultiplier(type, mode, flag)`):**

1. `num` from the Digimon's `training_type` (`tt`) and the mode (the stat: 0 HP, 1 MP, 2 Offense, 3 Defense, 4 Speed, 5 Brains):

   | mode | 10 when tt is | 9 | 11 | else |
   |---|---|---|---|---|
   | 0, 3 | 0, 1 | 2 | 3 | 8 |
   | 1, 5 | 0, 3 | 1 | 2 | 8 |
   | 2, 4 | 0, 2 | 3 | 1 | 8 |

2. `den` = 10.
3. By level: `num × 9` (levels 1–2), `× 10` (3), `× 11` (4), `× 12` (higher); `den × 10`.
4. **Only when `flag` = 0** (each × 6 / 5):
   - trigger 0xDB set, for modes 0, 3, 4;
   - trigger 0xFB set, for modes 2, 1, 5;
   - the stat's upgrade counter ≥ 10: `upgrade_hp_counter`, `upgrade_mp_counter`, `upgrade_off_counter` for modes 0–2, and `upgrade_defense_counter`, `upgrade_speed_counter`, `upgrade_brain_counter` for modes 3–5.
5. **Trn. manual** in the inventory (`getItemCount(0x21) > 0`; the port tests the item's `passive: training_boost`): × 11 / 10.
6. **Result:** `num × 10 / den` (unsigned 32-bit, then `int16`).

   Example: a Rookie with tt 0 at HP, no bonus: 10 × 10 × 10 / 100 = 10, so HP + 80, Offense + 2.

Triggers 0xDB and 0xFB are the gyms' "revision" upgrades (the title "…, revision" reads 0xDB).

### 2.4 The hour that passes (`TRN_advanceTrainingTime(tired, energy, happy)`)

**The partner first:**
- tiredness + `tired`, energy − `energy`, happiness − `happy`;
- tiredness ≥ 70: happiness − 3, discipline − 3.

**The clock:**
- frame = the saved start frame + 1200; hour = the saved start hour + 1. The minute stays where it is now (the clock ran during the session).
- **Hour ≥ 24:**
  - age + 1, day + 1, `dailyPStatTrigger` (`Clock.daily_update`), hour − 24, frame − 0x7080;
  - day ≥ 31 → day 0, year + 1; year ≥ 100 → 0.
- The clock hands follow (`updateMinuteHand`: the HUD clock reads the state).
- Every 4th hour (`hour % 4 == 0`) with happiness < 80: lifetime − `((happiness − 80) / −50 + 1)`.
- Hours 16 / 20 / 6 start the daytime transition evening / night / day (`Clock.initialize_daytime_transition`).

**The hourly care:**
- sleepy (condition bit 0x01): `sickness_counter` + 1, `missed_sleep_hours` + 1;
- hungry (0x04): `starvation_timer` − 120, and if it is ≤ 0 with energy < `raise_data.energy_threshold`, care mistakes + 1. Not hungry: `food_level` − 60;
- energy − `raise_data.energy_usage`;
- poopy (0x08): `pooping_timer` − 1200, else `poop_level` − 6;
- lifetime − 1 (not below 0), `evo_timer` + 1;
- injured (0x20): `injury_timer` + 1; sick (0x40): `sickness_timer` + 1;
- `tickConditionBoundaries` (`Care.tick_condition_boundaries`).

The fields are C `int16` / `uint8` as `GameState` stores them, with no other clamping than the boundaries.

### 2.5 The stats box (box 1)

**`TRN_saveBaseStats` / `TRN_applyBaseStats`:** the six base stats are copied into `INITIAL_COMBAT_STATS[0]` (order HP, MP, Offense, Defense, Speed, Brains) and back.

The box counts the gains into that copy, and the station applies it to the partner only at its end (§2.2, state 5).

**`TRN_createPostTrainingStatsBox`:**
- `done` = 0;
- "gained" = the gain ≠ 0, per stat;
- the text area is cleared, and the six labels are drawn at rows 0–5 (y = i × 12, `STR_STAT_LABEL_*`);
- row 7: the JP "所持金" (not drawn in US: an unused leftover);
- row 20 (y 240): the digits `renderNumber` reads (`MenuDraw.draw_digits`);
- delay = 100;
- box 1 is animated, colour 0, features 2, to (−94, −78, 188, 96), from the partner's bone 1 on screen (a 10 × 10 rect).

**Tick (`TRN_tickPostTrainingStatsBox`):**
- delay − 1 while > 0;
- **✕ or △ pressed alone** (`POLLED_INPUT == CONFIRM` or `== CANCEL`), and neither held in the previous frame: `done` = 1;
- when `done`: every gain is added at once (HP / MP capped at 9999, the others at 999, for positive gains), the gains become 0, and delay = 0.

**Render (`TRN_renderPostTrainingStatsBox`).** It also counts: when delay = 0, the first stat with a positive gain moves one point per frame (gain − 1, stat + 1, with the caps) and plays `playSound(0, 0x16)`.

It then draws, in the C's add order (the port draws in reverse, as for the other boxes):
- per stat with a gain ≠ 0: the "+" at (130, 9 + i × 13), BI_IN (u 96, v 180, 12 × 12, CLUT 256,491); the gain in 3 digits, colour 5, at (142, …);
- each stat in 4 digits, colour 0, at (68, 9 + i × 13);
- a vertical divider at x 122 (0xFAD990) and 123 (0x020202), from y 2 to h − 3;
- the labels: text colour 4, at (10, 9 + i × 13), 48 × 12, from row i;
- **per stat, a bar** at (66, 20 + i × 13 − 2), height 2:
  - the filled part `stat × 50 / 9999` (HP, MP) or `/ 999` wide: (0x69, 0xC2, 0xFF) when gained, else (0x78, 0x78, 0x78);
  - over a 50-wide back: (0, 0x5A, 0x96) when gained, else (0x28, 0x28, 0x28);
  - an inset: dark 0x020202 from (64, y) up to (64, y − 3) and across to (117, y − 3); light 0x666666 from (117, y − 2) down to (117, y) and back to (65, y).

All positions are relative to box 1's final rect.

### 2.6 The field pieces a station uses

- **Tamer state 8 (`tamerTickTraining`):** sub-state 0 starts animation 10 → 1; in sub-state 1 the tamer turns to the partner every frame (`entityLookAtLocation`).
- **Partner state 10:** only `handleConditionBubble`. No walking, care ticks or collision: the station moves it.
- **Walking (`tickEntityWalkTo`):** as the interpreter's `ENTITY_WALK_TO` (target 0xFF: a point; 0xFD: the tamer). The station calls the same code.
- **The camera (`createCameraMovement(point, 10)`):** the `FieldMap` pan, ported.
- **Map objects:**
  - `storeMapObjectPosition(start, count)` / `loadMapObjectPosition`: the instances' x / y saved and put back; loading also clears flag bit 0x10;
  - `moveMapObjectsWithLimit(start, count, dx, dy, …)`: each instance + (dx, dy). The station ignores its "reached the limit" result.
- **Dust:**
  - **`TRN_createCloudFXLine(a, b, x, z, dx, dz, n)`:** when `a % b == 0`, `d = (min(a, 1200) / 120) × b`. Then for n clouds, `r = randomLimit(100)`, a cloud at (x + d − r, 0, z + d − r), then x + dx, z + dz.
  - **`createCloudFX`:** one of 60 slots, state 0 at (x, z). Each frame the state + 1; at 14 the slot is freed.
  - **Drawn (`renderCloudFX`)** as the world sprite of `renderSprite` (as the condition bubbles):
    - at (x, `CLOUD_FX_Y[state]`, z);
    - DEFEFF u `CLOUD_FX_U[state]`, v 0, 32 × 32, anchor (16, 16);
    - colour `CLOUD_FX_COLOR[state]` (0x80 → 0x40);
    - scale `CLOUD_FX_SCALE[state]` / 0x1000;
    - additive (attribute 0x50000000).
  - **`removeAllCloudFX`** frees every slot.
- **Sounds:** `playSound(8, n)` is the map's own set (slot 8, ESALL), which the port already loads.

## 3. Godot design

- **`Training`** (`scripts/systems/training.gd`, RefCounted logic): the C's training state and functions:
  - `TRAINING_COMPLETE`, `is_training_complete()`;
  - the start time;
  - `multiplier(type, mode, flag)`, `award_hp_gains(type, b, c)`;
  - `advance_time(tired, energy, happy)`;
  - `save_base_stats` / `apply_base_stats`, the copy and the gains;
  - `gains_are_zero()`, `cloud_line(…)`.

  It uses `GameState`, `GameData`, the `Clock` and `Care`. Tested headless.
- **`TrainingStatsBox`** (`scripts/ui/training_stats_box.gd`): box 1's create / tick / render on `UIBoxes`, `TextArea`, `MenuDraw`, reading and writing `Training`'s copy and gains.
- **`TrainingRoutines`** (`scenes/script/training_routines.tscn` + `scripts/script/training_routines.gd`, on `MenuRoutines`' host):
  - routines 0x07 and 0x27;
  - `start(0x07)` does the C's setup: it finds the **station** for (current map, value 0xFE) among its child nodes (below) and starts it. If none matches, nothing starts and the routine waits, as in the C. It returns true (wait).
  - `tick(0x07)`: `Training.is_training_complete()` → `ACTIVE_INSTRUCTION` = 0.
  - 0x27 clears `TRAINING_COMPLETE` and doesn't wait.
  - `SCRIPT_STATE_2` isn't reset for 0x07; the interpreter's common setup sets it to 0, which the C doesn't. 0x07 has no steps of its own, so this changes nothing.
- **Stations** are scenes, children of `TrainingRoutines` (`scenes/training/hp_boulder.tscn`, script `scripts/training/hp_boulder.gd`, `class_name HpBoulderStation`, on a base `TrainingStation`):
  - exported `map` (0x70), `stat` (0), `point`, `overlay_start` / `overlay_count`, the dust lines;
  - `start(slots)` (the setup), `tick()` (the states of §2.2).

  A station is ticked by the field each frame after the script and the camera pan (`Field._frame`, as the C's object list runs it after `tickScript`). A mod adds a station for another map as another child scene. The later steps (4d-2, 4d-4) are more stations.
- **The field side:**
  - `Tamer.STATE_TRAINING` (8) and `Partner.STATE_TRAINING` (10);
  - `MapOverlays.store_positions(start, count)` / `load_positions(…)` / `move(start, count, dx, dy)`;
  - **`CloudFX`** (`scripts/field/cloud_fx.gd`, a node of the field's HUD layer like the condition bubbles): 60 slots, `create(x, z)`, `tick()`, `remove_all()`, its draw;
  - `ScriptInterpreter.tick_walk_to(…)`, public for the stations;
  - the field gives the stations the partner, tamer, `FieldMap`, overlays, `CloudFX`, `Sound` and the pad.
- **"Bonus Try" until 4d-3:** with value 0xF6 = 1, the station runs as Normal (the timer and △, `r` = 10). It is noted in VERIFY. The slot session replaces this in 4d-3.
- **Data:**
  - the constants of the C stay code, with their C references: the HP gains and costs, the multiplier tables, the triggers 0xDB / 0xFB, 1200 / 120 frames, the cloud tables;
  - the station's map, point and overlay range are the scene's exports, not id checks in the logic;
  - the Trn. manual is found by its `passive` property;
  - no porter change.

## 4. Tests (`tests/test_training.gd`)

- **Multiplier:**
  - each (mode, training type) cell of the table;
  - the level factors;
  - × 6 / 5 for 0xDB, 0xFB and the counters, only with `flag` = 0;
  - the manual's × 11 / 10;
  - the truncation (e.g. a Champion with tt 3 at HP and the manual: 11 × 11 × 11 × 10 / 1000 = 13).
- **HP gains:**
  - a Rookie tt 0: +80 / +2;
  - boost flag 0x10 with value 15: HP 80 × 10 × 15 / 100 = 120;
  - tiredness 100: 1 / 1;
  - the 999 cap;
  - only HP and Offense are gained.
- **The hour:**
  - start 10:23 → 11:xx, care deltas (tiredness, energy, happiness, food − 60, poop − 6, energy − usage, lifetime − 1, evo timer + 1);
  - tiredness 70 → happiness / discipline − 3;
  - 23:xx → 0:xx with age + 1, day + 1 and the card shop re-rolled;
  - day 30 → 0, year + 1;
  - hour 16 starts the evening transition.
- **The box:**
  - nothing for 100 frames, then one point per frame, the first positive gain first, sound 0x16;
  - ✕ alone finishes at once, ✕ held from before doesn't;
  - the caps;
  - the partner's stats are unchanged until `apply_base_stats`.
- **The routine:**
  - 0x07 with value 0xFE = 0 on map 0x70 starts the HP station and waits;
  - on another map, it waits and nothing starts;
  - when the station sets `TRAINING_COMPLETE`, the script goes on;
  - 0x27 clears it.
- **The HP station**, with a stub walker that arrives at once:
  - the states 0 → 5;
  - the boulder's moves (+1, −2 every 120 frames; the shake);
  - △ ends state 2;
  - dust lines at their counters;
  - the boulder put back;
  - tamer / partner states back to 0 / 1;
  - `TRAINING_COMPLETE`.
- **Dust:** 60 slots, freed at state 14, `remove_all`.

VERIFY gets a "Training" section: TRAI00's HP station in the game.

## 5. Open points

- **The clock during a session:** the minute keeps whatever the clock reached while the partner trained, because only the hour and frame are reset. The port does the same. Whether the clock runs during a script in the port as in the original, `specs/clock.md` decides already.
- **`TRN_D_8008F320`, the HP point,** is set by the setup only on map 0x70. The other TRN maps (0x4E, 0x77) have no HP station.
- **The partner's model needs animations 0x1B and 0x12.** If a model lacks one, the port's `start_animation` behaviour applies (to check with the Digimon whose models are converted).
- **△ to stop** is `POLLED_INPUT & CANCEL_BUTTON`: held, not pressed. The tests use the port's `Pad.CANCEL`.
