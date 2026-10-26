# Training

Status (2026-10-26): steps 5e-4d-1 and 4d-2 coded; 4d-3 specced in §7, approved 2026-10-26 (`PLANS.md` 5e-4), its logic coded (the box, textures and spot rect are the UI part). Code:
- `Training` (`scripts/systems/training.gd`), `TrainingStatsBox` (`scripts/ui/training_stats_box.gd`), `TrainingBrainsBox` (`scripts/ui/training_brains_box.gd`);
- `scenes/script/training_routines.tscn` (`scripts/script/training_routines.gd`) with its stations, scenes in `scenes/training/` on the scripts of `scripts/training/` (`TrainingStation`; `HpBoulderStation`, `OffenseStation`, `SpeedStation`, `DefenseStation`, `MpStation`, `BrainsStation`);
- 4d-3 logic: `SlotMachine` (`scripts/systems/slot_machine.gd`), `SlotSession` (`scripts/systems/slot_session.gd`, held by `Training.slot_session`), the stations' `start_slot_session` / `start_slot_spin`, data `systems/slot_machine` (`GameData.slot_machine()`);
- `CloudFX` (`scripts/field/cloud_fx.gd`), `ParticleFX` (`scripts/field/particle_fx.gd`);
- `MapOverlays.store_positions` / `load_positions` / `move` / `move_with_limit`;
- `Tamer.STATE_TRAINING`, `Tamer.STATE_NONE`, `Partner.STATE_TRAINING`;
- `ScriptInterpreter.tick_walk_to`, `ScriptInterpreter.actor`;
- `ScriptRoutines.tick_objects` (from `Field._frame` after the pans);
- data: `digimon/training_animations`, `moves/training_learning` (`GameData.training_animation`, `training_learning`, `training_learn_weight`);
- the debugger's State tab edits the partner's base stats.

Tests: `tests/test_training.gd`. Checks: VERIFY "Training".

As built:
- **Checked in the real field** (a movie of TRAI00, section 81): Agumon walks to the boulder and pushes it while the dust rises; △ ends the push; the box counts HP +80 / Offense +2; it walks back; the clock goes 8:02 → 9:02.
- **A box ticks only once it is open:** the box's 100-frame delay starts after its 5-frame opening, in the C as here.
- **The finish flag stays set:** once ✕ / △ finished the count, `MAIN_D_80135394` stays set until the next box. Any gain left is added at once.
- **The station's animations clear the held step:** `startAnimation` sets `animFlag = 1` (`anim.c:231`), which clears the held root motion. The station's `partner_animation` does that; the port's `start_animation` doesn't, for the other systems' sake.
- **`CALL_DIGIMON_ROUTINE` past 10** (the gyms' 214) is no longer reported as unported: it isn't a case of the C's switch.
- **4d-2, checked in the real field** (movies of TRAI00 sections 0x52–0x56, GIAS09 0x53 / 0x55, MIST05 Cherrymon): every station runs to the end with the gains of §6.2, and the tamer is free after the script. Tree Striking and Striking Special strike with the partner's technique animation, with the flash and the spark burst at the hit. The glove punches and knocks the partner back with dust. The fall pours on the partner. The Classroom's lesson and Cherrymon's loop play. Brains 95 → 103 opens "Give it all you got! / New orders!" under the stats box, and both close at the end.
- **`_sin` takes 512 units per turn** (`math.c:13`, 4096 = 1), not 4096 like the GTE's angles: the burst grows to `d` = 31, about 390 world units for a 6400-unit direction. The first draft used 4096, and the movie showed the particles packed together.
- **The flash** is built once as a 128 × 128 texture from SPOT256's quarter (u 64, v 64), mirrored four ways, and drawn as one rect. Drawing the quarters with negative rect sizes broke into tiles under the UI filter.
- **The session's shared states** (the box counted, then 20 frames) are one helper, `TrainingStation.gains_counted`; the stations' state numbers after the award differ from the C's where two C states became one (Offense 4–5 → 4, Speed 3–4 → 3, Defense 12–13 → 12, MP 5–6 → 5, Brains 4–5 → 4).
- **Without Spit Fire known**, a Brains session at a technique threshold teaches Agumon Sonic Jab, not Heat Laser: fire's first candidate is then Spit Fire with weight 0. `initializePartner` normally teaches Spit Fire, so the game's usual case is Heat Laser.
- **The tamer's walk at the Classroom** (state −1) plays his animation 2 with its root motion, as in `STATE_SCRIPT`.
- **4d-3 logic, as built:**
  - **The machine takes its data and sound from its owner:** `SlotMachine.data` (the `GameData` node: the autoload's name isn't there in `-s` tests) and `sound` (a `Callable` taking the `playSound(8, id)` id). It reads the reels, the assist draw, the symbols (`stat` names, `jackpot`) and the payouts (with their sounds) from `systems/slot_machine`. A match pays `own_stat` when the symbol's `stat` is `Training.MODE_NAMES[stat]`; the jackpot symbol is the one the table marks.
  - **`rows(i)`** gives the four render rows as numbers: `symbol`, `u`, `top` (before clipping), `y`, `v`, `h` and `visible`. A row can be `visible` with `h` = 0 (y = −10, the C draws it likewise); the box skips an `h` of 0 or less. `reel_x(i)` gives the window's x.
  - **`closing()`** (state 6) tells the box to run `remove_animated(3, spot rect)` and `close_box(0)`; the machine's own part of state 6 is `result = payout`.
  - **The session ticks after the station** (`TrainingRoutines.tick_objects`), as the C's object list does: the frame the session sets its result, the station sees it on the next. `SlotSession.box` is duck-typed (`open(machine, mode)`, `is_free()`) and **unset in production**: without it the machine is never ticked and a Bonus Try would wait for ever. The UI part sets `training.slot_session.box` in `TrainingRoutines.configure`, where a comment marks the place.
  - **The mapping of the stat to the mode** is `Training.STAT_MODES` / `mode_of_stat` (the script stat 0xFE → the multiplier's mode), and the data's mode names are `Training.MODE_NAMES`.
  - **Defense** ends at the point on `(not slots and counter ≥ 1200) or slot_result_ready()`; the other stations call `session_over()`, which now includes the slot result. The −2 abort (`TRN_func_800888A0`) is not ported; a comment marks its place in states 1 of HP, Offense and Speed.
- **4d-3 UI, as built:**
  - **`TrainingSlotsBox`** (`scripts/ui/training_slots_box.gd`) is the session's box, set in `TrainingRoutines.configure`. `open` loads the map's strips and calls `create_animated(3, 0, FEATURE_HALF_FILL, SLOTS_UI_START, spot rect, tick, render)`. `is_free` is box 3's state 0.
  - **Its tick** reads ✕ as `POLLED_INPUT & ~POLLED_INPUT_PREVIOUS`. It checks `closing()` *before* `machine.tick`, as the C's state 6 case: the frame the machine enters state 6 it is still open; on the next it shrinks back to the spot (recomputed) and `close_box(0)` closes the help text, while the machine sets its result.
  - **The spot rect** is `spot_rect_for(training_spots(map), mode, project)`: the spot whose `stat` is `Training.MODE_NAMES[mode]`, through `FieldMap.unproject` of the field camera, then −(160, 120) − (8, 6), 16 × 16. With no spot, or with no camera in the tree (headless tests), it is (−8, −8, 16, 16).
  - **The textures** are `maps/<NAME>/training/slots_p3.png` / `slots_p4.png` through `Content` (`load_strip`), split by their `.stp.png` masks into opaque and STP texels (a `PsxTexture`). A map without them gives null: the box and its frame draw, the reels don't, and nothing is reported.
  - **The draw order and blending:** `render` (on `UIBoxes`, after the frame) draws per reel, from reel 2 to 0, the rows from 3 to 0, then the window's opaque texels. Two child layers of `UIBoxes` follow it: additive (the symbols' STP texels, none in the original) and subtractive (the windows' STP texels, all of them). Each window is 32 × 64 from u 0xE0 8 × 32, tinted 0x40 / 0x80 = 0.5, with Godot's `blend_sub` (screen − 0.5 × texel). The layers draw after every box, not just box 3: nothing else is open during a Bonus Try. `UIBoxes.step` now redraws all its children, so a layer clears when the box closes.
  - **Seen in a test render of TRAI00** (frames, not kept): the outline grows from the boulder's spot, the three reels spin with the symbols on their light squares, and the window shades each reel's top and bottom (the light 0xF7 symbol background measured 120 at the edges, about 223 near the pay line). The box shrinks back to the boulder, the help text closes, and the stats box counts HP +40 for a payout of 5. The help text shows a cross glyph ("Use ✕"), not △ (§7.9).

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

## 6. Step 4d-2: the other stations

The eight stations still missing outside TRN2: five at the Green Gym, two at Gear Savanna, one at Misty Trees. They reuse the core of §2–§5. This part adds their scenes, their gains, the hit sparks, the Brains boxes and move learning, and two data tables.

### 6.1 The C code

| C (US) | What |
|---|---|
| `TRN_setupOffenseTraining`, `TRN_tickOffenseTraining` (`trn/trn_off.c:43`, `:98`) | Offense: Tree Striking (0x70), Striking Special (0x4E) (§6.3) |
| `TRN_setupSpeedTraining`, `TRN_tickSpeedTraining` (`trn/trn_speed.c:35`, `:62`) | Speed: Running (0x70), Savanna Course (0x4E) (§6.4) |
| `TRN_setupDefenseTraining`, `TRN_tickDefenseTraining` (`trn/trn_def.c:67`, `:100`) | Defense: Punching Glove (0x70) (§6.5) |
| `TRN_setupMpTraining`, `TRN_tickMpTraining` (`trn/trn_mp.c:150`, `:60`) | MP: Waterfall (0x70) (§6.6) |
| `TRN_setupBrainsTraining`, `TRN_tickBrainsTraining` (`trn/trn_brain.c:37`, `:71`) | Brains: Classroom (0x70), The Teachings of the Forest (0x77) (§6.7) |
| `TRN_award{Offense,Speed,Defense,Mp,Brains}TrainingGains` (`trn/trn_reward.c:234`, `:308`, `:374`, `:422`, `:474`) | the gains (§6.2) |
| `TRN_renderNewOrdersBox`, `TRN_tryLearnMove`, `TRN_renderMoveLearnedBox` (`trn/trn_reward.c:806`, `:811`, `:877`); `TRN_TRAINING_ANIM_IDS`, `TRN_D_8008F14C`, `TRN_D_8008F184` (`:55`, `:77`, `:87`) | Brains: new orders, move learning (§6.8) |
| `createParticleFX`, `tickParticleFX`, `renderParticleFX`, `initializeParticleFX` (`efe.c:370`, `:463`, `:536`, `:350`); `renderParticleFlash` (`efe.c:1055`); `renderFXParticle`, `addFXPrim`, `lerp` (`effect_common.c:761`, `:537`, `:278`) | the hit sparks (§6.9) |
| `moveMapObjects`, `moveMapObjectsWithLimit`, `setMapObjectsFlag`, `resetMapObjectAnimation`, `getDrawPosition` (`overworld.c`) | the equipment (§6.10) |
| `createMenuBox` (`game_menu.c:1684`), `entityLookAtLocation`, `playSound2` / `thunkStopSoundMask` | already ported: `GameMenu._create_menu_box`, `FieldDigimon.look_at_psx`, `SoundSystem.play_sound` (returns the voice mask) / `stop_sound_mask` |
| The scripts | TRAI00 (script 108), GIAS09 (script 75), MIST05 (script 115, Cherrymon's "Please train" choice) |

### 6.2 What value 0xFE means, and the gains

**Value 0xFE is not the multiplier's mode.** Builtin 0x07 (`script_interp.c:1705–1722`) maps it as **0 HP, 1 Offense, 2 Speed, 3 Defense, 4 MP, 5 Brains**. `TRN_calculateTrainingMultiplier` numbers its modes 0 HP, 1 MP, 2 Offense, 3 Defense, 4 Speed, 5 Brains (§2.3). The two only agree for HP.

The scripts set 0xFE so: TRAI00 sections 0x51 HP (Boulder Moving), 0x52 MP 4 (Waterfall), 0x53 Offense 1 (Tree Striking), 0x54 Defense 3 (Punching Glove), 0x55 Speed 2 (Running), 0x56 Brains 5 (Classroom); GIAS09 Offense 1 (Striking Special) and Speed 2 (Savanna Course); MIST05 Brains 5.

**The gains.** Each award takes `(type, b, c)`: `b` is the station's instance id (0 at the Green Gym, 6 at Gear Savanna, 9 at Misty Trees), `c` the slot result (10 without slots). `b` is also the multiplier's `flag`: away from the Green Gym, the revision triggers and the upgrade counters give nothing.

Each gain is `base × v / 10`, or `base × v × train_boost_value / 100` when its boost bit is set (§2.3), then `× c / 10`.

| Award | mode | b | gains (stat, base, boost bit) | tired / energy / happy | tiredness 100 | cap 999 |
|---|---|---|---|---|---|---|
| Offense | 2 | 0 | Offense 8 (0x01), Speed 2 (0x04) | 9 / 1 / 1 | Speed 1, Offense 1 | none |
| | | 6 | HP 10 (0x10), Offense 8 (0x01) | 9 / 1 / 1 | HP 1, Offense 1 | none |
| Speed | 4 | 0, 6 | HP 10 (0x10), Speed 8 (0x04) | 8 / 1 / 1 | both 1 | HP |
| Defense | 3 | 0 | Defense 8 (0x02), Brains 2 (0x08) | 9 / 1 / 1 | both 1 | none |
| MP | 1 | 0 | MP 80 (0x20), Defense 2 (0x02) | 7 / 1 / 1 | both 1 | MP |
| Brains | **1** | 0 | MP 10 (0x20), Brains 8 (0x08) | 6 / 1 / 1 | MP 1, Brains 1 | both |
| | **1** | 9 | Brains 15 (0x08) | 6 / 1 / 1 | Brains 1 | both |

- **Any other `b`:** every base is 0 and so are the costs. Only the stations above call the awards.
- **Brains is computed as MP** (mode 1). It gets the bonus of trigger 0xFB and of `upgrade_mp_counter` ≥ 10, never `upgrade_brain_counter`, which the Classroom still increments. The port keeps the C.
- **After the gains**, as for HP: the base stats are saved, the gains set, the stats box opened, and an hour passes (`advance_time(tired, energy, happy)`).
- **Brains then checks its thresholds** (§6.8).

**The setups.** A Fresh or In-Training partner (level < 3) gets the stat's upgrade counter + 1 at the Green Gym only:

| Station | Counter |
|---|---|
| Offense | `upgrade_off_counter` |
| Speed | `upgrade_speed_counter` |
| Defense | `upgrade_defense_counter` |
| MP | `upgrade_mp_counter` |
| Brains | `upgrade_brain_counter` |

Every setup sets `TRAINING_COMPLETE` = 0 for its maps; the Speed setup always does. All save the start time and set state 0, as in §2.2.

**The end of a session**, unless a station says otherwise: counter (`MAIN_D_8013537A`) ≥ 1200, or △ held (`POLLED_INPUT & CANCEL`), with `slots` = 0. (Slots: the session's result ≥ 0, 4d-3.)

**Shared states.** After its award, every station:
1. waits for the box to count the gains (`gains_are_zero`), then wait = 0;
2. counts wait to 20;
3. does its own finish.

All say "→ 4" etc. below for their own numbers.

### 6.3 Offense (`trn_off.c`)

**Setup.**

| | 0x70 Tree Striking (instance 0) | 0x4E Striking Special (instance 6) |
|---|---|---|
| point (F320) | (−0x3D6, −0xA14) | (−0x527, 0xCD9) |
| unused (F330) | (−0x12F, −0xA1A) | (−0x527, 0xB85) |
| sparks (F340, x y z) | (−0x44C, −0x258, −0xB22), (−0x44C, −0x1F4, −0xB22), (−0x44C, −0x190, −0xB22) | (−0x4B0, −0xC8, 0xDAC), (−0x514, −0xC8, 0xDAC), (−0x578, −0xC8, 0xDAC) |
| overlays | 0x64 × 8 (the tree) | 0x2B × 0x1E |
| rotation at the point | 0x200 | 0x800 |

`TRN_TRAINING_ANIM_IDS[partner type]` gives the partner's strike: `[0]` its animation (0x2E–0x35: one of its technique animations), `[1]` the frame of the hit (8–0x1E).

**Tick:**
- **0:**
  - the overlays' positions are saved;
  - tamer state 8; camera follow off; partner state 10, animation 4;
  - the camera moves to the point over 10 frames;
  - `playSound(8, 9)`; counter = 0; → 1.
- **1:**
  - (Slots: if the session was aborted, −2, the partner gets animation 4, the camera returns to the tamer and the state is 4: `TRN_func_800888A0(4)`.)
  - The partner walks to the point. There: the strike animation, held root motion (`animFlag |= 2`), hit counter = 0, the rotation, → 2 (instance 0) or → 7 (instance 6).
- **2** (Tree Striking), every frame:
  - hit counter + 1, counter + 1, root motion held;
  - at the hit frame: three sparks (§6.9) at the three points, hit counter = 0, `playSound(8, 5)`, → 3.
- **3**, every frame: hit counter + 1, counter + 1. The tree shakes:
  - hit counter < 4: (−4, +2);
  - < 7: (+4, −2);
  - otherwise, on even counters (`(100 − h) / 20`, `−(100 − h) / 50`), on odd ones the opposite.

  At hit counter ≥ 0x29: hit counter = 0, the strike animation again, → 2.

  **The end** (tested in state 3 only, so after a hit):
  - `TRN_awardOffenseTrainingGains(type, 0, r)`;
  - animation 0x12;
  - the overlays' positions back;
  - `playSound(8, 0xA)`;
  - the camera to the tamer; → 4.
- **7** (Striking Special), every frame: counter + 1, hit counter + 1. At the hit frame:
  - the three sparks; `playSound(8, 0x10)`;
  - overlays 0x27 × 4 hidden (flag 1), the station's 0x2B × 0x1E shown (flag 0);
  - their animation reset: `resetMapObjectAnimation(0x2B, 0x2B)`. The C passes the start as the count, so 0x2B–0x55 are reset. The port does the same.
  - hit counter = 0, → 8.
- **8:** counter + 1, hit counter + 1:
  - at 0x2E: 0x27 × 4 shown again, the station's overlays hidden, the strike animation again, hit counter = 0, → 7;
  - **the end** (tested in state 8): the same flags put back, `TRN_awardOffenseTrainingGains(type, 6, r)`, animation 0x12, the camera to the tamer, `playSound(8, 0xA)`, → 4, wait = 0.
- **4, 5:** the shared states; at 20, animation 2 (walk), → 6.
- **6:** the partner walks back to the tamer. There:
  - the base stats applied; box 1 closed;
  - partner state 1; tamer state 0; camera follow on;
  - counter = 0; the object removed; `TRAINING_COMPLETE` = 1.

### 6.4 Speed (`trn_speed.c`)

**Setup:**
- point: (0x2D, −0x184) at 0x70 (instance 0), (0x32, −0x11F) at 0x4E (instance 6);
- no overlays.

**Tick:**
- **0:**
  - tamer state 8; camera follow off; partner state 10, animation 4;
  - the camera to the point; `playSound(8, 9)`; counter = 0; → 1.
- **1:**
  - (Slots: `TRN_func_800888A0(4)`.)
  - The partner walks to the point. There: rotation 0xC00 (instance 0) or 0 (instance 6), animation 4 (it runs on with the animation's root motion), → 2.
- **2:** counter + 1.
  - **The wrap:** when the partner is off screen (`isOnScreen == 0`) on a counter divisible by 60, it is put back at the start of the course: x = −0xBB8 (instance 0) or z = 0x7D0 (instance 6), the other coordinate kept. Then animation 4 again.
  - **The end:** `TRN_awardSpeedTrainingGains(type, instance, r)`, animation 0x12, `playSound(8, 0xA)`, the camera to the tamer, → 3.
- **3, 4:** the shared states; at 20, animation 4, → 5.
- **5:** the partner walks back to the tamer. There:
  - the base stats applied; box 1 closed;
  - partner state 1; camera follow on; counter = 0; the object removed; `TRAINING_COMPLETE` = 1.

  **The tamer isn't set back to state 0** here. The script's end does it (`setMovementEnabled(−1, false)`, as for every script).

### 6.5 Defense (`trn_def.c`)

**Setup (0x70 only):**
- point (−0x33B, −0x662);
- sparks at (−0x384, −0x1F4, −0x7D0), (−0x3B6, −0x1F4, −0x76C), (−0x3B6, −0x1F4, −0x834);
- the glove = overlays 0x47 × 0xD;
- the counter; `TRAINING_COMPLETE` = 0.

`saved` below is the first overlay's saved x (`TRN_D_8008F368[0]`).

**Tick.** In states 2–10, △ held sets counter = 1200 first. "Moves to L" is `moveMapObjectsWithLimit(start, count, dx, 0, L, 0)`: + dx every frame, done when the first overlay's x reaches L (≥ for dx > 0, ≤ for dx < 0).
- **0:**
  - the overlays' positions saved;
  - tamer state 8; camera follow off; partner state 10, animation 4;
  - the camera to the point; `playSound(8, 9)`; counter = 0; → 1.
- **1:** the partner walks to the point. There: rotation 0x400, animation 0x25, → 2.
- **2:** counter + 1; the glove moves +0x32 to saved + 0x64. Done: three sparks; the punch's sound `mask = playSound2(8, 4)`; → 3.
- **3:** counter + 1; the knock-back:
  - the partner x + 0x64, rotation 0x400, animation 0x25 again;
  - a cloud at (partner x, 0, partner z − 0x64);
  - the glove moves −0x32 to saved + 0x32; done → 4.
- **4:** the same knock-back; the glove moves +0x32 to saved + 0x5A; done → 5.
- **5–9:** counter + 1; the glove swings:
  - 5: −0x1E to + 0x3C;
  - 6: +0x14 to + 0x5A;
  - 7: −0xA to + 0x46;
  - 8: +5 to + 0x5A;
  - 9: −4 to + 0. Done: the positions put back, animation 4, → 10.
- **10:** the partner walks back to the point. There:
  - **the end** if counter ≥ 1200 with `slots` = 0 (slots: result ≥ 0):
    - `TRN_awardDefenseTrainingGains(type, 0, r)`;
    - animation 0x12; `playSound(8, 0xA)`;
    - the punch sound stopped (`thunkStopSoundMask(mask)`);
    - the camera to the tamer; → 12.
  - otherwise: rotation 0x400, animation 0x25, → 2 (another punch).
- **12, 13:** the shared states; at 20, animation 4, → 14.
- **14:** the partner walks back to the tamer. There:
  - the base stats applied; box 1 closed; the positions put back;
  - tamer state 0; camera follow on; partner state 1;
  - counter = 0; the object removed; `TRAINING_COMPLETE` = 1.

A session is whole punches: △ only takes effect when the partner is back at the point.

### 6.6 MP (`trn_mp.c`)

**Setup (0x70 only):**
- the approach (F330) (0x290, 0x2EE), then the point (F320) (0x2AC, 0x868);
- the splash = overlays 0xA4 × 8;
- the waterfall's two looks: 0x93 × 0x10 (calm) and 0xA3 × 0x18 (pouring on the partner). The ranges overlap: 0xA4–0xAB belong to both.
- the counter; `TRAINING_COMPLETE` = 0.

**Tick:**
- **0:**
  - the overlays 0xA4 × 8 saved;
  - tamer state 8; partner state 10, animation 4 (camera follow is not touched);
  - the camera to the point; `playSound(8, 9)`; counter = 0; → 1.
- **1:** the partner walks to the approach; → 2.
- **2:** it walks to the point. There:
  - 0x93 × 0x10 hidden, 0xA3 × 0x18 shown;
  - the splash moves by (0, `head − 0x14`), where `head` is the background pixel y of the partner's head (`getDrawPosition` of (x, y − `digimon_data.height`, z));
  - rotation 0; animation 0; the waterfall's sound `mask = playSound2(8, 2)`; → 3.
- **3:** counter + 1. **The end:**
  - `TRN_awardMpTrainingGains(type, 0, r)`;
  - the two looks put back (0x93 shown, 0xA3 hidden);
  - the splash's positions put back;
  - the camera to the tamer; animation 2; `playSound(8, 0xA)`; the sound stopped; → 4.
- **4:** the partner walks to the approach; there animation 0x12, → 5.
- **5, 6:** the shared states. At 20 the session ends where the partner is:
  - the base stats applied; box 1 closed;
  - tamer state 0; partner state 1;
  - counter = 0; the object removed; `TRAINING_COMPLETE` = 1.

  The partner doesn't walk back: in state 1 it follows the tamer on its own.

### 6.7 Brains (`trn_brain.c`)

**Setup:**

| | 0x70 Classroom (instance 0) | 0x77 The Teachings of the Forest (instance 9) |
|---|---|---|
| the tamer's place (F358) | (−0x5AC, 0x61B) | (−0x564, 0x3C4) |
| the partner's place (F320) | (−0x4E1, 0x3F3) | (−0x5E3, 0x2CE) |
| counter | `upgrade_brain_counter` | none |

Both set `TRAINING_COMPLETE` = 0.

**Tick:**
- **0:**
  - tamer state −1 (no case in `tamerTick`: the tamer does nothing on his own), tamer animation 2;
  - partner state 10, animation 0;
  - `playSound(8, 9)`; the camera to the tamer's place; counter = 0; → 1.
- **1:** the tamer walks to his place (`tickEntityWalkTo(0xFD, 0xFF, …)`). There: tamer animation 0, he looks at the partner, partner animation 2, → 2.
- **2:** the partner walks to its place. There:
  - **instance 0:** each looks at the other; tamer animation 9, partner animation 0x16;
  - **instance 9:** the tamer looks at the partner, the partner at the map's first NPC (`NPC_ENTITIES[0]`, Cherrymon), the NPC at the partner; partner animation 0x16, NPC animation 0x1E;
  - → 3.
- **3:** counter + 1:
  - instance 0: every 30 frames `playSound(8, 3)` and tamer animation 9 again; the tamer's root motion held;
  - instance 9: the NPC's animation 0x1E again whenever it has played to its end (`animFrame ≥ frameCount`); every 60 frames `playSound(8, 0x12)`;
  - every 35 frames, partner animation 0x16 again.

  **The end:**
  - `TRN_awardBrainsTrainingGains(type, 0, r)` (`b` is 0 for both instances: see the open points);
  - partner animation 0x12; the camera to the tamer;
  - the first NPC's animation 0 (on TRAI00 as well, whatever that NPC is);
  - → 4; `playSound(8, 0xA)`.
- **4, 5:** the shared states. At 20 the session ends:
  - the base stats applied; box 1 closed;
  - box 2, if open (state 1), closes towards the tamer's screen position (a 10 × 10 rect);
  - tamer state 0; partner state 1;
  - counter = 0; the object removed; `TRAINING_COMPLETE` = 1.

  Nobody walks back.

### 6.8 New orders and move learning (`TRN_awardBrainsTrainingGains`, `TRN_tryLearnMove`)

Brains before the gain is `base`, after it `total = base + gain`. `MAIN_D_80135388` = 0, then 1 when a box opens (nothing reads it).

**New orders.** For each threshold crossed (`base < T ≤ total`), in this order, a line is drawn in the text area at y 0x78 (row 10) in text colour 7:

| T | Text (`text/trn/trn_reward`) |
|---|---|
| 100 | `TRN_D_8008F0D8` "Give it all you got!" |
| 200 | `TRN_D_8008F0F0` "Take it easy!" |
| 300 | `TRN_D_8008F100` "Get back!", and `TRN_D_8008F10C` "Change target!" at y 0x84 |
| 400 | `TRN_D_8008F11C` "Hang in there!" |
| 500 | `TRN_D_8008F12C` "Technique mastered." |

A later one is drawn over an earlier one (same row). When any was drawn:
- `TRN_D_8008F140` "New orders!" is drawn in text colour 1 at y 0x84, or at 0x94 after the 300 one;
- box 2 opens: `createMenuBox(2, −0x58, 0x12, 0xB0, 0x30, features 2)` (colour 1, grown from the tamer, no tick);
- it renders `renderString(0, −78, 24, 240, 48, u 0, v 120)`: the text area's rows from y 120, 240 × 48, at (−78, 24).

**Otherwise, a move may be learnt.** It is tried when `total` crosses 150, 250, 350, 450, 550, 650, 750, 800, 850, 900 or 950, or when `total` is 999. `TRN_tryLearnMove(type)`:
1. For each of the partner's 3 elements `i` (`digimon_data.special`; 0xFF skipped):
   - walk its 8 moves in training order, `TRN_D_8008F14C[element × 8 + k]` for k = 0–7;
   - skip a move the partner has (`hasMove`);
   - the first one in the partner's 16-slot move list is the candidate `moveId[i]`, with weight `TRN_D_8008F184[k][i]`.
2. The best weight wins; on a tie the lower `i` is kept. No candidate: weight −1.
3. `r = randomLimit(100)`. If `best > r`:
   - `learnMove(move)` (`GameState.learn_move`, which also learns the moves sharing its flag);
   - the move's name is drawn at y 0x78 and "was mastered!" (`TRN_D_8008F19C`) at 0x84, both in the current text colour (there is no `setTextColor` before them);
   - the name's length `len` is kept;
   - box 2 opens: `createMenuBox(2, −0x58, 0x12, 0xB0, 0x23, 2)`.

   The box renders (`TRN_renderMoveLearnedBox`):
   - `renderString(3, −78, 24, (len / 2) × 12, 12, 0, 120)`: the name;
   - `renderString(0, (len / 2) × 12 − 78, 24, 12, 12, 0, 132)`: the second line's first 12 pixels, after the name;
   - `renderString(0, −78, 36, 48, 12, 12, 132)`: its next 48 pixels, on the line below.

   These sizes fit the JP text: a name in 12-pixel glyphs, then "を", and "おぼえた" below. With the US proportional font they cut the text. The port draws what the C draws (open point).

The weights (`TRN_D_8008F184[k][i]`, in %, by the move's rank `k` and the element's slot `i`):

| k | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 |
|---|---|---|---|---|---|---|---|---|
| first element (`i` 0) | 0 | 25 | 22 | 20 | 18 | 15 | 12 | 10 |
| second | 15 | 13 | 11 | 9 | 8 | 7 | 6 | 5 |
| third | 10 | 8 | 7 | 5 | 2 | 0 | 0 | 0 |

The first move of the first element has weight 0, so training never teaches it.

### 6.9 The hit sparks (`createParticleFX(kind, mode, pos, entity, lifetime)`)

Four slots. The stations call `createParticleFX(0, 0, point, NULL, 0)`. The port takes the effect as the C has it with `entity` = null. The entity parts (`addEntityParticleFX`, mode 1's ring of clouds) are battle effects and are not ported here.

- **Create:**
  - the first free slot, or nothing;
  - per flash `i` (2 in mode 0): x / y / z offsets of `rand() % 200 − 100`, and a size of `rand() % 170 + 250` (mode 1 adds a third flash, size `rand() % 200 + 300`);
  - timer: 0x13 (mode 0), 0x16 (1), 0xE (2);
  - colour by kind: 0 and 1 (0xFF, 0x6E, 0x46); 2 (0xC8, 0xC8, 0x64); 3 (0xCC, 0, 0x88); 4 (0x32, 0x32, 0xFF); 5 (0x96, 0x96, 0x96); 6 (0xFF, 0x6E, 0x6E). Any other kind or mode: nothing;
  - state 0; `endFrame` = lifetime + 4.
- **Tick:** state + 1, `endFrame` − 1. The slot is freed once state ≥ timer and `endFrame` < 0.
- **The particles** (`initializeParticleFX`, once): 50 directions. Each is the vector (0, 0, (`rand() % 150 + 250`) × 16) turned by three random angles (`((rand() & 0x7F) − 0x40) × 4096 / 64` each, `RotMatrixZYX`).
- **Render**, each frame:
  - **in state 2 only, the flashes:**
    - each at position + its offsets, through `worldPosToScreenPos`;
    - `scale = size × (VIEWPORT_DISTANCE × 8) / depth`; drawn when `depth >> 4` is in (0x20, 0x1000);
    - `renderParticleFlash`: the 64 × 64 texture at SPOT256 (u 64, v 64, its palette, CLUT 0,487) is one quarter, mirrored into the four quarters around the point;
    - each quarter is `(scale × 63 >> 10) + 1` pixels on a side (the PSX splits quads larger than 1024 × 512 into cells; that size doesn't occur here);
    - colour × 0x80 / 0x80, additive.
  - **while state < timer, the burst:**
    - colour = `lerp(c, 0, 0, timer, state)` per channel;
    - `d = _sin(lerp(0, 0x6E, 0, timer, state)) >> 7` (`_sin`, `math.c:13`: 512 units per turn, 4096 = 1; so `d` grows to 31);
    - each particle at position + (`d × direction >> 9`);
    - drawn by `renderFXParticle`: DEFEFF u 0, v 32, 15 × 15, palette 1 (CLUT 192,489), additive, a quad of `0x28 × VIEWPORT_DISTANCE / depth` pixels centred on the point (`addFXPrim`, drawn when `(depth >> 4) − 0x37` is in (0x20, 0x1000)).
  - `lerp(a, b, t0, t1, t)` is `a + (b − a)(t − t0) / (t1 − t0)` with the C's remainder correction (`effect_common.c:278`), ported as it is.

### 6.10 The field pieces

- **`MapOverlays`:**
  - `move_with_limit(start, count, dx, dy, limit_x, limit_y) -> bool`, the C's test on the first instance;
  - the stations use `set_flag` and `reset_animation`, which exist.
- **`FieldMap.background_pixel`:** `getDrawPosition`, exists.
- **`Tamer`:**
  - `STATE_NONE` (−1), whose tick does nothing;
  - the stations start his animations with `start_animation`.
- **`ScriptInterpreter.actor(slot)`:** made public, for the first NPC (slot 2).
- **The stations' helpers** (`TrainingStation`): `tamer_animation`, `walk_tamer`, `npc(0)`, `look_at`, `sparks(points)`, `play_loop(id) -> mask` / `stop_loop(mask)`, `set_camera_follow`.
- **Order:** the sparks are ticked with the clouds (`ScriptRoutines.tick_objects` → `ParticleFX.tick`) and drawn in the HUD layer like them.

### 6.11 Godot design

- **`Training`** gets:
  - the five awards (`award_offense_gains(digimon, b, c)` …), sharing one `_award(values, tired, energy, happy)`;
  - `STAT_*`, the 0xFE values, beside `MODE_*`;
  - the Brains thresholds.
- **`TrainingBrainsBox`** (`scripts/ui/training_brains_box.gd`): box 2's "new orders" and "mastered" contents and its render. `Training.award_brains_gains` asks it to open.
- **`TrainingStation`** gets the helpers of §6.10. `stat` now holds the 0xFE value; `HpBoulderStation` keeps 0 (`Training.STAT_HP`).
- **The scenes** (`scenes/training/`, scripts in `scripts/training/`), all children of `TrainingRoutines`:

  | Scene | Class |
  |---|---|
  | `offense_tree.tscn`, `offense_savanna.tscn` | `OffenseStation` |
  | `speed_running.tscn`, `speed_savanna.tscn` | `SpeedStation` |
  | `defense_glove.tscn` | `DefenseStation` |
  | `mp_waterfall.tscn` | `MpStation` |
  | `brains_classroom.tscn`, `brains_forest.tscn` | `BrainsStation` |

  **The C's instance id becomes exported settings**, read as properties, never compared as ids:
  - Offense: `strike_states` (tree / special) and `award_variant` (0 / 6);
  - Speed: `wrap_axis` and `wrap_value`; its award variant;
  - Brains: `with_npc`.

  The points, overlay ranges, rotations and sounds are exports with the C's values.
- **`ParticleFX`** (`scripts/field/particle_fx.gd`, a Control in the HUD like `CloudFX`): 4 slots, `create(kind, mode, pos)`, `tick()`, and its draw (the SPOT256 flash quarters and the DEFEFF particles, additive). `ScriptHost` creates and wires it like the clouds.
- **Data (data porter, two new tables):**
  - **`digimon/training_animations.json`** (`TRN_TRAINING_ANIM_IDS`, 67 records keyed by Digimon): `{digimon, strike_anim, hit_frame}`. Read with `GameData.training_animation(digimon)`. A Digimon without a record (a mod's) strikes with 0x2E and hits at frame 10, the table's most common values.
  - **`moves/training_learning.json`** (`TRN_D_8008F14C`, `TRN_D_8008F184`): per element, its 8 moves in training order; and the 8 × 3 weights. Read with `GameData.training_learning()`. A mod's element without a list learns nothing here.

  Both get checks (sizes against `symbols.txt`, every move id known, each element's 8 moves of that element), their sections in the data porter's specs and their PROGRESS lines.
- **Unchanged:** the C's constants (gains, costs, thresholds, counters, the shake and glove tables) stay code, with their references.

### 6.12 Tests (`tests/test_training.gd`, more cases)

- **The awards:**
  - each row of §6.2 (a Rookie with tt 0);
  - the boost bits; tiredness 100 per variant; the caps; the costs;
  - `flag` = 6 / 9 dropping the 0xDB / 0xFB bonuses;
  - Brains reading `upgrade_mp_counter`.
- **The routine:** value 0xFE 1–5 on 0x70 starts the matching station; 1 and 2 on 0x4E; 5 on 0x77; 4 on 0x4E starts nothing.
- **Each station**, with the stub walker:
  - **Offense:** the strike at the hit frame (from the data); three sparks; the shake values; the end only in state 3 / 8; the 0x27 / 0x2B flags and the reset range.
  - **Speed:** the wrap only off screen, on multiples of 60; the tamer left in state 8.
  - **Defense:** the glove's limits in order; the knock-back of + 0x64 and its clouds; △ ending only back at the point; the loop sound stopped.
  - **MP:** the two looks swapped and back; the splash moved by the head's pixel; no walk back.
  - **Brains:** the tamer walks first; the animations; the NPC loop (instance 9); box 2 closed at the end.
- **The Brains boxes:**
  - each threshold; the 300 case's two lines and "New orders!" at 0x94;
  - the learn thresholds and 999;
  - `try_learn_move` with a set seed: candidates, weights, ties, known moves skipped, no candidate.
- **The sparks:** slots, timers, colours, freeing, the burst's `lerp`.

VERIFY "Training" gets the eight stations, the Brains boxes and a learnt move.

### 6.13 Open points

- **The "mastered" box in US:** its render sizes come from the JP text. A movie will show what the US box looks like; the port keeps the C either way.
- **The teaching at Misty Trees** passes `b` = 0 to the award (`trn_brain.c:143`), not 9. It gives MP 10 + Brains 8 with the Green Gym's bonuses, and the award's "Brains 15" case is never used. The port keeps the C.
- **Speed's tamer** stays in state 8 until the script's end. The script ends right after builtin 0x07, so nothing shows.
- **Camera follow** (`CAMERA_FOLLOW_PLAYER`) only matters while the tamer is in state 0. It is set and cleared as in the C.
- **NPC 0 on TRAI00** gets animation 0 at the Classroom's end. Which NPC that is depends on the map's load order; the port uses the same first NPC.
- **Animation ids** 0x16, 0x1E, 0x25, 0x12 and the strike animations must exist in the models. A missing one behaves as `start_animation` does today.

## 7. Step 4d-3: the slot machine ("Bonus Try")

Spec approved 2026-10-26. With value 0xF6 = 1 ("Bonus Try"), a station runs with a slot machine in box 3. The station ends when the machine has paid out, not after a minute or on △, and the payout is the awards' `c`: × 0.5, × 2, × 4 or × 10.

### 7.1 The C code

| C (US) | What |
|---|---|
| `TRN_startSlotSessionIfEnabled(stat)`, `TRN_func_800888A0` (`trn/trn_reward.c:108`, `:116`) | the station starts the session when value 0xF6 = 1; the abort check (§7.6) |
| `TRN_startSlotSession`, `TRN_getSlotSessionResult` (`trn/trn_slots.c`), `TRN_tickSlotSession` (`trn/trn_hud.c:345`) | the session object (0xFDC): opens the machine, waits for its payout and for box 3 to close (§7.2) |
| `TRN_createSlotMachineBox`, `TRN_startSlotSpin`, `TRN_getSlotMachineResult`, `TRN_tickSlotMachine`, `TRN_chooseReelStop`, `TRN_renderSlotMachine` (`trn/trn_slots.c`) | the machine in box 3 (§7.3–7.5) |
| `TRN_getTrainingSpotScreenPos` (`trn/trn_hud.c:374`), `TRN_TRAINING_SPOTS` | where box 3 grows from and shrinks to: the station's spot on screen (§7.2) |
| Data | `TRN_D_8008F1AC[3][13]` (the reels, `trn_hud.c:80`); `TRN_D_8008F2CC[10]` (the assist draw); `SLOTS_UI_START` {−82, −87, 164, 90}; `TRN_SLOT_SPRITE1` / `2`; the textures in the gym map's VRAM (§7.5) |
| The stations | `trn_hp.c:95–129`, `trn_off.c:113–229`, `trn_speed.c:76–110`, `trn_def.c:120–243`, `trn_mp.c:77–109`, `trn_brain.c:87–143` (§7.6) |
| Script | TRAI00 (script 108) and the other gyms: Bonus Try is `SET_TEXTBOX_MODE 1`, the "Slot Game / Use △ to match three pictures." box, value 0xF6 = 1, builtin 0x07, `SET_TEXTBOX_MODE 0`. The help box stays open during the session; the machine closes it (`closeBox(0)`) |

`MAIN_D_80135370` = value 0xF6, read by every setup (§2.1). Below:
- `slots` is that flag;
- `stat` is the **multiplier's mode** (0 HP, 1 MP, 2 Offense, 3 Defense, 4 Speed, 5 Brains);
- ✕ is `CONFIRM_BUTTON` (US 0x40), pressed this frame (`POLLED_INPUT & ~POLLED_INPUT_PREVIOUS`).

### 7.2 The session (`MAIN_D_801353A0[4]`: result, state, stat, payout)

- **Start** (`TRN_startSlotSession(stat)`): result = −1, state 0, the stat kept; the session object is added.
- **Its tick:**
  - **0:** the machine box opens (`TRN_createSlotMachineBox(stat)`, §7.3); → 1.
  - **1:** payout = the machine's result; once it isn't −1, → 2.
  - **2:** once box 3 is free (`UI_BOX_DATA[3].state == 0`, after its closing animation): result = payout; the object is removed.
- **`TRN_getSlotSessionResult()`** is that result: −1 until the box has closed, then 5, 20, 40 or 100.

**Box 3's start rect** (`TRN_getTrainingSpotScreenPos(map, stat)`):
- The spot is the station's entry in `systems/training_spots` (already ported, `GameData.training_spots(map)`). Its (x, 0, z) is projected to the screen in centred coordinates (`worldPosToScreenPos`).
- The rect is (x − (0xA8 − `DRAWING_OFFSET_X`), y − (0x7E − `DRAWING_OFFSET_Y`), 16, 16). With the usual offset (160, 120), that is (x − 8, y − 6, 16, 16).
- Without a spot for (map, stat), it is {−8, −8, 16, 16}.

The position is computed again when the box closes, so the box shrinks back to where the camera now shows the spot.

### 7.3 The machine (`SlotMachine TRN_SLOT_MACHINE`)

**Opening** (`TRN_createSlotMachineBox(stat)`):
- result = payout = −1, state 0, `stat` kept, `autoStart` = −1;
- `assist` = `TRN_D_8008F2CC[rand() % 10]`: 0 five times in ten, 1 four times, 2 once;
- per reel: `reelPos` = `rand() % 13`; `scrollY`, `spinSpeed`, `settling` = 0;
- `createAnimatedUIBox(3, colour 0, features 2 (half fill), SLOTS_UI_START, start rect, tick, render)`. It plays `playSound(0, 0)`; `UIBoxes` already does.

**`TRN_startSlotSpin()`**: `autoStart` = 0. The station calls it when the partner reaches its point.

**The tick** runs as box 3's tick, so only while the box is open.

- **0 (waiting):** on ✕ or `autoStart` ≥ 0:
  - state 1;
  - every `spinSpeed` = 0x400 and every `stopSteps` = 0;
  - `playSound(8, 6)`.

  ✕ can start it early, before the partner has arrived.
- **1–4 (spinning; state − 1 = the number of reels told to stop so far).** For each reel `i`:
  1. `settling[i]` = 0; `scrollY[i]` += `spinSpeed[i] >> 6` (16 pixels a frame). A value of exactly 0x20 becomes 0x1F.
  2. If `scrollY[i]` ≥ 0x20: − 0x20, and `reelPos[i]` = (`reelPos[i]` + 12) % 13 (the next symbol comes in). If the reel is stopping (`i < state − 1`):
     - `stopSteps[i]` > 0 → − 1;
     - else `scrollY[i]` = 0, `spinSpeed[i]` = 0, `playSound(8, 8)`.

     A stopping reel therefore stops on the next symbol plus `stopSteps`.
  3. If `i == state − 1` and ✕: `TRN_chooseReelStop(i)` (§7.4).
  4. **Settling** (only used by the render): if `scrollY[i] + (spinSpeed[i] >> 6)` ≥ 0x20 (with 0x20 → 0x1F), `settling[i]` + 1 when either:
     - the reel stops on that step (`i < state − 1` and `stopSteps[i]` ≤ 0);
     - it is the reel told to stop this frame, with `stopSteps[i]` ≤ 0.

  After the reels:
  - if state < 4 and ✕: `playSound(8, 7)`, state + 1;
  - if all three speeds are 0: `resultTimer` = 0, state + 1 (→ 5).

  The first ✕ after the start stops reel 0, the next reel 1, the next reel 2.
- **5 (the payout):**
  - **On its first frame** (`resultTimer` = 0), take `s` = the symbol on the line of each reel (`TRN_D_8008F1AC[i][reelPos[i]]`):
    - three 7s: payout 100, `playSound(8, 0xC)`;
    - three of a kind where `s − 1 == stat` (the station's own stat): payout 40 (0x28), `playSound(8, 0xB)`;
    - any other three of a kind: payout 20 (0x14), `playSound(8, 0xB)`;
    - anything else: payout 5, `playSound(8, 0xD)`.
  - **Afterwards**, at `resultTimer` ≥ 30 (0x1E) or on ✕: state 6.
  - `resultTimer` + 1 every frame.
- **6:**
  - box 3 shrinks back to the spot (`removeAnimatedUIBox(3, spot rect)`, §7.2);
  - the script's text box 0 closes (`closeBox(0)`);
  - result = payout.

  The box is now closing, so the tick doesn't run again.

The symbols: 1 HP, 2 MP, 3 Offense, 4 Defense, 5 Speed, 6 Brains (`s − 1` is the multiplier's mode), 7 the jackpot.

### 7.4 Stopping a reel (`TRN_chooseReelStop(i)`): the assist

Terms used below:
- `next(i, j)` = `TRN_D_8008F1AC[i][(reelPos[i] + 13 − j) % 13]`, the symbol `j` steps ahead. Without help, the reel stops on `next(i, 1)`.
- `target[i]` (`targetSymbol`) records what reel `i` aims at.
- `stopSteps[i]` is how many more symbols it rolls before stopping.

**Assist 0 (honest; half the sessions):**
- **Reels 0 and 1:** `target[i]` = `next(i, 1)`.
- **Reel 2:** if `target[0] == target[1]` and `next(2, 1) == target[0]`, `stopSteps[2]` = `rand() % 2 + 1`. **The machine skips the match**, so an honest session never wins when reel 2 would land on it.

**Assist 1 (help with the first symbol; 4 in 10):**
- **Reel 0, *shift*:** `j` = 0 if `scrollY[0] == 0`, else 1; `target[0]` = `next(0, j)`. Where the reel stops doesn't change.
- **Reel 1:** if `target[0] == 7`, *shift* on reel 1. Otherwise take the first `j` in 1–2 with `next(1, j) == target[0]`:
  - found: `stopSteps[1]` = `j − 1` and `target[1]` = `target[0]` (the reel rolls on to the match);
  - not found: `stopSteps[1]` = 0 and `target[1]` = −2.
- **Reel 2**, only if `target[0] == target[1]`:
  - if they aren't 7: the same search for `target[0]` on reel 2 (match, or −2);
  - if they are 7 and `next(2, 1)` is 7: `stopSteps[2]` = `rand() % 2 + 1`, so the jackpot is skipped.

**Assist 2 (the jackpot; 1 in 10):**
- **Reel 0, *scan*:** take the first `j` in 1–2 with `next(0, j) == 7`:
  - found: `stopSteps[0]` = `j − 1` and `target[0]` = 7;
  - not found: `stopSteps[0]` = 0 and `target[0]` = −1.
- **Reel 1:** if `target[0] == 7`, *scan* on reel 1; else `target[1]` = −2.
- **Reel 2:** if `target[0]` and `target[1]` are both 7, *scan* on reel 2; else `target[2]` = −3.

The C shares *shift* and *scan* between the reels with `goto`; the port writes them as two helpers that take the reel. `targetSymbol` isn't reset when the box opens, but every path for reels 0 and 1 sets it before reel 2 reads it.

### 7.5 The render (`TRN_renderSlotMachine`, box 3 open; layer 6 − 3)

All positions are centred PSX screen coordinates. The three reels are at x = −41, 0, 41 (`41 × i − 41`). For each reel:
- **The window** (`TRN_SLOT_SPRITE2`):
  - u 0xE0, v 0xD8, 8 × 32 texels;
  - scaled × 4 across and × 2 down (`scalex` 0x4000, `scaley` 0x2000) around (`mx` 4, `my` 0), so 32 × 64 pixels at (x − 16, −0x4A);
  - colour 0x40 (half), semi-transparent mode 2, which is **subtractive**: screen − texel for texels with the STP bit, the others drawn opaque.

  It darkens the reel's strip. **Every colour of palette 4 has the STP bit** (0xFFFF … 0x8000, white to black; asset porter): the whole window subtracts. Its column is index 0 (white) on the top and bottom rows and 15 (0x8000, black) in the middle, so at colour 0x40 the edges lose half of white and the pay line nothing.
- **The symbols** (`TRN_SLOT_SPRITE1`):
  - 32 × 32, u = (symbol − 1) × 32, v 0xD8, centred on x (`mx` 0x10);
  - colour 0x80, semi-transparent mode 1 (additive, for STP texels). **No colour of palette 3 has the STP bit**: the symbols are drawn opaque, index 0 (0x0000) transparent. Each symbol is an icon on a light (0x7BDE) square.
  - The seven pictures, u = (symbol − 1) × 32: HP heart, MP ring, Offense, Defense, Speed arrows, Brains bulb, and **the poop icon** (symbol 7, the jackpot; `jackpot` in the data).

  There are four rows, `k` = 0–3, each showing symbol `TRN_D_8008F1AC[i][(reelPos[i] + 11 + k) % 13]`:
  - **Position:** the first row's y = `scrollY[i]` − 0x7A, then + `spinSpeed[i] >> 6` (− 1 when `scrollY + step` is exactly 0x20). When `settling[i]` ≠ 0, + 2 instead of the step. Each next row is + 0x20.
  - **Clipping** to the window, y −0x4A … −0xA:
    - a row starting above the window (y < −0x4A) is drawn at −0x4A, with v = 0x8E − y and h = 0x20 − (v − 0xD8);
    - a row reaching below it (y + 0x20 ≥ −9) gets h = 0x20 − (y + 0x2A);
    - any other row is drawn whole.
  - A row is drawn only if y < −9 and y + 0x20 ≥ −0x49.

  Row `k` = 2 is `reelPos[i]`, centred in the window: the pay line.
- **Draw order:** the window is sorted before the symbols, on the same layer. By the ordering-table rule (I-17), the symbols added after the window are drawn first, and the window then subtracts over them. The port follows that (§7.7 "4d-3 UI, as built").

**The textures are in the gym map's VRAM**, not in ETCTIM:
- `tpage` 0x2B / 0x4B: the 4 bpp page at (704, 0), with semi-transparency rates 1 / 2;
- the symbols use CLUT (48, 486), the map's 4 bpp palette 3; the window uses CLUT (64, 486), palette 4;
- the texels are u 0–0xE7, v 0xD8–0xF7: VRAM (704, 216)–(762, 248).

Each map loads the strip itself:
- TRAI00 with its 4 bpp image 1 (704, 0, 256 tall);
- GIAS09 with its image 0;
- MIST05 with its image 2 (704, 216, 32 tall).

The CLUT rows come from each map's image 0 (`loadMapImage2`, see the asset porter's `specs/map.md`). MIST05's image 1 (704, 0, 200 tall) stops above row 216. The three maps' strips and both palettes are byte-identical (asset porter check, informational).

### 7.6 The stations

Every station already has the hooks (`slots`, §3). With slots:
- **State 0**, after its own work: `TRN_startSlotSessionIfEnabled(mode)`, with the station's multiplier mode (HP 0, MP 1, Offense 2, Defense 3, Speed 4, Brains 5).
- **When the partner reaches its point** (state 1 for HP / Offense / Speed / Defense, state 2 for MP / Brains): `TRN_startSlotSpin()`.
- **The session's end:** the session result is ≥ 0, instead of "1200 frames or △". `r` (the awards' `c`) is the session result, not 10.
  - HP: the pushes are still `(counter % 1200) / 120`.
  - Offense: in its state 3 or 8, as without slots.
  - Defense: the result is checked in state 10, back at the point. △ still sets the counter to 1200, which does nothing with slots.
  - Speed, MP, Brains: in their session state.
- **`TRN_func_800888A0(4)`** (state 1 of HP, Offense and Speed) would end a session whose result is −2: partner animation 4, the camera back to the tamer, state 4. **No code sets −2**: the result is −1 or the payout. The port leaves it out and notes it.

Every award multiplies by `c / 10` (§2.3, §6.2):
- c = 5 halves the gains and 100 gives × 10;
- the award caps (999) still apply;
- a Rookie at HP with the jackpot gets 80 × 10 = 800 HP.

### 7.7 Godot design

- **`SlotMachine`** (`scripts/systems/slot_machine.gd`, `RefCounted`; logic only, tested headless):
  - **State:** that of §7.3: `state`, `reel_pos`, `scroll_y`, `spin_speed`, `stop_steps`, `target`, `settling`, `assist`, `stat`, `auto_start`, `result_timer`, `payout`, `result`.
  - **Methods:**
    - `open(stat)`, `start_spin()`;
    - `tick(confirm_pressed)`, which returns the sounds played this frame (or calls a `sound` callable, like the stations);
    - `choose_reel_stop(i)`, `line_symbol(i)`;
    - `rows(i)`: the four rows' symbols and y, for the render and the tests.
  - It reads the reels and the assist draw from data (below), and draws its random numbers with `Rng`.
- **`TrainingSlotsBox`** (`scripts/ui/training_slots_box.gd`), built like `TrainingStatsBox`:
  - box 3 on `UIBoxes`: `create_animated(3, 0, FEATURE_HALF_FILL, SLOTS_UI_START, spot rect, tick, render)`;
  - its tick runs `SlotMachine.tick` with the pad's ✕;
  - at state 6 it calls `remove_animated(3, spot rect)` and closes text box 0 (`TextBoxes.close_box(0)`);
  - it draws the windows on a subtractive layer (`PsxUiFilter.material("sub")`), and the symbols as a base layer plus an additive STP layer, like `CloudFX`.
- **The session** (`TRN_tickSlotSession`): `Training.slot_session`, or a small `SlotSession` in `training.gd`, with `start(mode)`, `tick()` (states 0–2 of §7.2) and `result()`. `TrainingRoutines` ticks it after the running station, as the C's object list does.
- **`TrainingStation`:**
  - `start_slot_session()`, called in each station's state 0, and `start_slot_spin()`, called on arrival;
  - with slots, `session_over()` returns `slot_result() >= 0`, and `result()` returns the session result;
  - `slot_mode` is the station's multiplier mode, taken from its `stat` through `Training`'s mapping (no new id checks);
  - Defense's state 10 uses the same helpers.
- **The spot rect:** `GameData.training_spots(map)` → the spot of `slot_mode` → `FieldMap.unproject` → centred → (x − 8, y − 6, 16, 16). The −8 / −6 come from the C's `0xA8 / 0x7E − DRAWING_OFFSET`. Without a spot: (−8, −8, 16, 16).
- **Data (data porter, one new table): `systems/slot_machine.json`**:
  - `reels`: `TRN_D_8008F1AC`, 3 × 13 symbol ids;
  - `assist_draw`: `TRN_D_8008F2CC`, 10 entries;
  - `symbols`: 1–6 with their stat (the mode names of `training_spots`), 7 the jackpot;
  - `payouts`: jackpot 100, own stat 40, other match 20, none 5 (from `TRN_tickSlotMachine`).

  The table gets:
  - checks: sizes from `symbols.txt`, every symbol is 1–7, each reel has all seven;
  - a spec section, plus PROGRESS and VERIFY lines;
  - a reader, `GameData.slot_machine()`.

  The logic reads `symbols[s].stat` and `payouts`, never "s − 1 == stat" or the numbers.
- **Textures (asset porter, maps family):**
  - **Which maps:** those that load the TRN library (`loadTrainingLibrary`, `map.c:5459`): 0x70, 0x4E and 0x77, kept as a list with that reference.
  - **What:** the map's composed 4 bpp VRAM page (704, 0), rows 216–247 (u 0–255, v 0xD8–0xF7), built the way the GPU does from the map's 4 bpp images in load order (`vram.py`).
  - **Outputs:** `maps/<NAME>/training/slots_p3.png` (CLUT (48, 486)) and `slots_p4.png` (CLUT (64, 486)), both indexed, each with its `.stp.png` mask. The sidecar keeps the VRAM rect, tpage and CLUT ids.
  - **Check:** whether the three maps' strips are equal, reported but not required.
  - **Docs:** the asset porter's `specs/map.md`, PROGRESS and VERIFY get the outputs.

  Godot loads them from the current map's folder through `Content`. If a map has none (a mod's gym), the box draws without symbols rather than failing.
- **Unchanged:** the stations' scenes, the stats and Brains boxes, and the awards. The help text box is the script's own; box 3 closes it at state 6.

### 7.8 Tests (`tests/test_training.gd`, plus the data and asset porter tests)

- **`SlotMachine`, with a set seed:**
  - opening: the positions and the assist draw;
  - ✕ or `start_spin` starts it, with sound 6;
  - 16 pixels a frame, and the 0x20 → 0x1F rule;
  - ✕ stops reels 0, 1 and 2 in order: sound 7 for each press, sound 8 for each stop;
  - a reel stops on the next symbol plus `stop_steps`.
- **`choose_reel_stop`**, for each assist and reel from a set position:
  - assist 0's skip on reel 2;
  - assist 1's match search (found at 1 or 2; not found gives −2), and its 7s case;
  - assist 2's scan (−1, −3).
- **Payouts**, each with its sound:
  - three 7s: 100;
  - the station's own stat: 40 (HP three of a kind at HP; MP three of a kind at HP gives 20);
  - a mismatch: 5;
  - state 6 comes at 30 frames or on ✕.
- **The render rows:** the four rows' symbols and y, the clipping cases, and the settling + 2.
- **The session:** −1 until box 3 has closed, then the payout.
- **The stations** (stub walker, as in 4d-2):
  - with slots, HP doesn't end at 1200 frames or on △;
  - it ends when the result is set, with gains × c / 10 for c = 5, 20, 40, 100 (HP 800 for the jackpot, and the 999 cap);
  - Defense ends only back at the point;
  - the spin starts on arrival;
  - without slots nothing changes (the 4d-2 tests stay).
- **The spot rect:** the spot of (0x70, HP); without a spot, (−8, −8, 16, 16).
- **Data porter:** the table's records and checks.
- **Asset porter:** the strip's size, CLUTs and VRAM sidecar, on a fixture map.

VERIFY "Training" gets a Bonus Try item:
- the box flies out of the station;
- ✕ stops the reels one by one;
- the payout sounds play;
- the box flies back and the help text closes;
- the gains are × c / 10.

### 7.9 Open points

- **"Use △ to match three pictures."** The US text says △, but the US code stops the reels with `CONFIRM_BUTTON` (0x40, ✕). The port follows the code; this needs checking on the original. In the port's field, the line draws a cross-like glyph ("Use ✕"), while the script listing shows △: which glyph the font gives that character should be checked too.
- **The honest machine skips a match on reel 2** (assist 0, `stopSteps` = 1–2). It looks deliberate: a payout stays rare unless the session draws an assist. The port keeps it.
- **The −2 abort** (`TRN_func_800888A0`) is dead code (§7.6).
- **The window's draw order** against the symbols (§7.5): by the ordering-table rule, the subtractive window goes over the symbols, and the port draws it so. Still to compare with the original on hardware or an emulator.
- **Defense with slots:** △ still sets the counter, which only matters without slots.
