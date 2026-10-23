# Partner care (port spec)

Status:
- **Implemented 2026-10-23:**
  - the care rules: `scripts/systems/care.gd`, class `Care`;
  - partner states 1 / 3 / 7 (`scripts/field/partner.gd`) and the tamer's state, camera follow and scene animations (`tamer.gd`);
  - the fade (`scripts/field/fade.gd`);
  - test `tests/test_care.gd`; human checks in `VERIFY.md`;
  - the visuals: `scripts/systems/condition_bubbles.gd`, `status_bars.gd`, `psx_texture.gd`, `scripts/field/poop_piles.gd`.
- **Next:** the debug panel (§3.5).

The partner's needs as time runs on the field:
- hunger and energy, sleep, tiredness, poop, sickness and injury, unhappiness, lifetime;
- the condition bubbles over its head and the happiness / discipline bars;
- the two care scenes that need no menu: falling asleep (with a debug stand-in for the menu's "Sleep") and pooping in the wild.

State fields are `GameState.partner.care` (`specs/game_state.md`, every `PartnerPara` field in snake_case), data is the Digimon's `care` component (`raise_data`, `sleep_patterns`, `data_porter/specs/digimon.md`). The partner's movement and animations are `specs/partner.md`; the clock is `specs/clock.md`.

All `file:line` references are in `external-resources/dw_decomp/src/main/` unless another folder is given; the code is the US version (`VERSION_IS(US)` / `VERSION_EQUAL_OR_NEWER(JP_TRIAL)` branches taken).

## 1. C functions reproduced

| C | What | Godot (`Care` unless noted) |
|---|---|---|
| `partnerTickOverworld` (`partner.c:213`) | per frame: state dispatch, then `tickConditionBoundaries` | `Partner.tick()` |
| `partnerTickNormal` (`partner.c:268`) | collision, walking, `tickConditions`, `tickPoopingMechanic`, `tickPoopDetection`, `handleConditionBubble` | `Partner.tick()` state 1 |
| `tickConditions` (`partner_impl.c:2059`) | the care tick: gates, then the mechanics below in this order | `tick_conditions()` |
| `tickDeathCondition` (`:1917`) | lifetime 0 → death script | `tick_death_condition()` (script stubbed) |
| `tickSleepMechanics` (`:913`) | sleepiness, bedtime shifts, missed nights | `tick_sleep_mechanics()` |
| `tickSicknessMechanics` (`:1832`) | getting sick, sickness / injury timers, sick too long | `tick_sickness_mechanics()` |
| `tickTirednessMechanics` (`:1388`) | map effects, tired condition | `tick_tiredness_mechanics()` |
| `tickHungerMechanics` (`:1494`) | food, energy, hunger calls, starvation | `tick_hunger_mechanics()` |
| `tickUnhappinessMechanics` (`:1042`) | becoming unhappy, stat loss | `tick_unhappiness_mechanics()` |
| `tickConditionBoundaries` (`:868`) | clamps | `tick_condition_boundaries()` |
| `tickPoopingMechanic` (`:1656`) | poop level, pooping timer | `tick_pooping_mechanic()` |
| `tickPoopDetection` (`:1688`) | poop eaters find a pile | `tick_poop_detection()` |
| `handleConditionBubble` (`:1551`) + `bubble.c` | which bubble, and the bubble animation | `handle_condition_bubble()`, `ConditionBubble` |
| `renderStatusBars` (`:2153`, called from `renderGameClock`, `clock.c:290`) | happiness / discipline bars | `StatusBars` |
| `initializePartner` (`:450`) care part | new-partner care reset, first technique | `initialize_partner()` |
| `setSleepTimes`, `setFoodTimer`, `resetPartnerPara` (`:618`, `:664`, `:593`) | schedules | same names |
| `partnerTickSleep` (`partner.c:278`), `sleepRegen` (`:1331`), `handleSleeping` (`:1158`) | the sleep scene, recovery, waking up | `Partner` state 3, `sleep_regen()`, `handle_sleeping()` |
| `tickWildPoop` (`partner.c:593`), `createPoopPile` (`:1242`), `handleWildPoop` (`:1757`), `handlePoopWeightLoss` (`:1745`), `renderPoop` (`:529`) | pooping on the ground, the piles | `Partner` state 7, same names, `PoopPiles` |
| `skipHours` (`:1990`), `handleToilet` (`:1730`), `handleEatingPoop` (`:1774`), `handlePraiseScold` (`:1113`), `partnerHandleFoodFeed` (`:1615`), `partnerWillRefuseItem` (`:1431`), `handlePostBattleTiredness` (`:2040`) | state changes whose scenes come later | same names, ported as functions now (§3.4) |

## 2. Original behaviour

### 2.1 When the care tick runs

- **Order in a frame:** objects tick in the order they were added (`tickObjects`, `world_object.c:82`). The partner is added by `initializePartner` before `addClock` (`main.c:3451–3456`, `:3462–3467`), so the partner ticks first.
  - `LAST_HANDLED_FRAME` was set by the clock's previous tick, just before it advanced `CURRENT_FRAME` (`specs/clock.md` §2.1).
  - So `CURRENT_FRAME != LAST_HANDLED_FRAME` means "the clock advanced on its last tick". Every `CURRENT_FRAME % n == 0` test sees the new frame.
  - At double speed (frame + 2) odd multiples are skipped. At half speed the care tick runs only on the ticks that advanced the frame.
- **`tickConditions` gates** (`:2072`): only on the field (`GAME_STATE == 0`), in the normal partner state (1), while game time runs (`IS_GAMETIME_RUNNING`), when the frame advanced, and outside a fade to black (`FADE_PROTECTION`, set by `fadeToBlack` while warping, `fade.c:84`).
  - Inside, most mechanics repeat the `CURRENT_FRAME != LAST_HANDLED_FRAME` test; it is always true there.
- **Not gated by `tickConditions`:**
  - `tickPoopingMechanic` runs in state 1 when the frame advanced and the tamer is in state 0.
  - `handleConditionBubble` runs every frame in states 1 and 10.
  - `tickConditionBoundaries` runs every field frame in every state.
- **Units:** 20 frames = 1 game minute; 200 = 10 minutes; 1200 = 1 hour; 4800 = 4 hours; 28,800 = 1 day.

### 2.2 `tickConditions` (`:2059`), in this order

1. `tickDeathCondition`, `tickSleepMechanics`, `tickSicknessMechanics`, `tickTirednessMechanics`, `tickHungerMechanics`, `tickUnhappinessMechanics`, `tickConditionBoundaries`.
2. `areaEffectTimer + 1`, back to 0 above 28,800 (it counts frames on the current map: `setupPartnerOnWarp` resets it, `:865`).
3. `trainBoostTimer − 1`; at ≤ 0 the boost flag and timer are 0.
4. **Lifetime:** every 4 hours (`CURRENT_FRAME % 4800 == 0`) with happiness < 80, `remainingLifetime −= (happiness − 80) / −50 + 1` (C division, truncated), not below 0.
   - Happiness 50: −1; 0: −2; −30: −3; −100: −4.
   - The clock also takes 1 per hour (`specs/clock.md` §2.1).
5. **The rest needs no daytime fade running.** `isInDaytimeTransition()` (`map.c:4607`) returns 1 when the fade is *finished* (`DAYTIME_TRANSITION_FRAME >= 25`); despite its name, `if (!isInDaytimeTransition()) return` stops here while a fade runs.
6. **Immortal hour:** after waking up (`handleSleeping` sets `HAS_IMMORTAL_HOUR`, `IMMORTAL_HOUR = HOUR`), nothing below runs during that hour. The first tick in another hour clears it.
7. **Evolution:** the evolution target is computed from `evoTimer` and the level (`data_porter/specs/evolution.md`). The virus bar ≥ 16 turns the partner into Sukamon. A target starts the evolution scene (partner state 13). **Comes with the evolution step**; the care step leaves `EVOLUTION_TARGET` at −1.

### 2.3 Boundaries (`tickConditionBoundaries`, `:868`)

| Field | Range |
|---|---|
| happiness | −100 … 100 |
| discipline | 0 … 100 |
| tiredness | 0 … 100 |
| energy_level | 0 … `raise.energy_cap` |
| weight | 1 … 99 |

### 2.4 Hunger and energy (`tickHungerMechanics`, `:1494`; `setFoodTimer`, `:664`)

- **`food_level`** is the number of game minutes until the next hunger call:
  - −1 every minute (frame % 20), while not hungry.
  - −3 every hour while `tiredness_hunger_timer` ≥ 50 (§2.6).
- **Hunger call:** when `food_level` ≤ 0, the partner becomes hungry (condition bit 2), `starvation_timer = 180`, and the bubble logic runs once.
- **While hungry:** `starvation_timer` −1 every 10 frames, so the call lasts 1,800 frames (1.5 game hours).
- **Call expires** (`starvation_timer` ≤ 0):
  - `setFoodTimer` sets the next call, `starvation_timer = 0`, hungry cleared;
  - a care mistake if `energy_level < raise.energy_threshold` (the partner wasn't fed enough).
- **Energy:**
  - `energy_level −= raise.energy_usage` every hour, not below 0.
  - **At 0:**
    - weight −1 every 10 minutes (frame % 200; not below 1);
    - `empty_stomach_timer` +1 every minute.
  - **At or above `energy_threshold`:** trigger 0x280 is set ("full"; read by scripts, never cleared here).
- **`setFoodTimer` (next hunger hour):**
  - **Fresh (level 1):** every 2 hours: `HOUR / 2 * 2 + 2`, wrapped at 24.
  - **In-Training (level 2):** every 3 hours: `HOUR / 3 * 3 + 3`, wrapped at 24.
  - **Other levels:** from `raise.hunger_hours` (the list without the −1 padding; US loop `:699–736`):
    - if the stored `next_hunger_hour ≥ HOUR`: the first listed hour greater than the stored one;
    - otherwise: the first listed hour greater than `HOUR`;
    - if there is none: the first listed hour greater than `HOUR`, else the first hour of the list (wrap to the next day).
    
    The first rule reads the *previous* call's hour. Agumon (1, 5, 9, 13, 17, 21) called at 13 and expiring at 14:30 gets 17. Called at 21, it gets 1 the next day.
  - **Then** `food_level` = minutes from now to that hour:
    - `(next − HOUR) * 60 − MINUTE` if `HOUR ≤ next`;
    - else `(24 − HOUR + next) * 60 − MINUTE`.
    
    `next == HOUR` would give ≤ 0 (hungry at once). The dw1 data never gets there:
    - the Fresh / In-Training steps are always later than `HOUR`;
    - the list fallbacks pick an hour after `HOUR`, or the first hour of the list when `HOUR` is past all of them, which is earlier with the dw1 lists (3–8 hours each).
    
    A pack's one-hour list would hit it at that hour; the port keeps the formula.

### 2.5 Sleep (`tickSleepMechanics`, `:913`; `setSleepTimes`, `:618`)

- **Schedule** (`setSleepTimes`):
  - **Levels 1 and 2:** sleepy `3` (Fresh) or `7` (In-Training) hours + `randomLimit(1)` from now, on the hour. Wake-up is sleepy + `SLEEP_PATTERN[cycle].sleepyHours`.
    - **Quirk kept:** `randomLimit(1)` is always 0.
    - `hours_awake_default` is the awake time, `hours_asleep_default` = sleepy hours.
  - **Level 3+:** the times of `SLEEP_PATTERN[raise.sleep_cycle]` (e.g. Agumon's cycle 1: sleepy 19:00, awake 04:00; 15 hours awake, 9 asleep).
  - **Also:** `time_awake_today = hours_awake_default * 6` (tens of minutes), `sickness_counter = 0`, `tiredness_sleep_timer = 0`.
- **Tiredness brings bedtime forward:**
  - **Every minute:** `tiredness_sleep_timer += tiredness * 3 / 10`.
  - **Every 10 minutes, while not sleepy and with the timer ≥ 180:**
    - `time_awake_today − 1` and the timer back to 0;
    - the sleepy time is moved earlier: `hoursLate = ceil((hours_awake_default * 6 − time_awake_today) / 6)`;
    - `sleepy_hour = wakeup_hour − hours_asleep_default − hoursLate` (+24 if negative);
    - `sleepy_minute = (time_awake_today % 6) * 10`.
- **Becoming sleepy:** when not sleepy at the start of the tick and `HOUR` is in `[sleepy_hour, wakeup_hour)`, wrapping over midnight. Only hours are compared; `sleepy_minute` isn't read here.
  - While sleepy, the menu's "Sleep" is enabled (`setSleepDisabled(0)`, `game_menu.c:2223`); otherwise disabled.
- **While sleepy:**
  - **Happiness / discipline loss:**
    - Fresh: −1 / −1 every 10 minutes;
    - In-Training: −1 / −1 every 15 minutes;
    - others: −2 / −4 every hour.
  - **Every hour not equal to `sleepy_hour`:** `sickness_counter + 1`, `missed_sleep_hours + 1`.
- **Missed night:** sleepy, and the wake-up hour has come without sleeping (`:980–986`, quoted). The partner wakes up by itself:
  - the schedule moves on: Fresh / In-Training wake + awake hours, others the pattern again;
  - `time_awake_today` and `tiredness_sleep_timer` reset, sleepy cleared;
  - a care mistake, the condition animation updated, and `addTamerLevel(1, −1)`.
  ```c
  (sleepy < wakeup && sleepy < HOUR && wakeup <= HOUR) ||
  (wakeup < sleepy && HOUR < sleepy && wakeup <= HOUR)
  ```

### 2.6 Tiredness (`tickTirednessMechanics`, `:1388`)

- **Map effect:** every 1,200 frames on the same map (`area_effect_timer % 1200 == 0`, > 0), by the map's area response (§2.12):
  - liked (1): happiness +1, tiredness −2;
  - disliked (2): happiness −1, tiredness +1.
- **`sub_tiredness`:** at ≥ 60 it adds 1 to tiredness and resets. Nothing in the decomp increases it: dead code, kept.
- **`tiredness_hunger_timer`:** +1 per tick while tiredness ≥ 50, else 0. At ≥ 50 ticks it speeds up hunger (§2.4).
- **Tired condition (bit 1):** tiredness ≥ 80; happiness −2 every 100 frames while it lasts. Cleared below 80.
- **Where tiredness comes from:** training (`trn_reward.c:725`), battles (`tamer.c:858`, `handlePostBattleTiredness`), sickness, the map. Sleep and items lower it.

### 2.7 Sickness and injury (`tickSicknessMechanics`, `:1832`)

`wasSick` = the sick bit at the start of the tick.
- **Sick from missed sleep:** `sickness_counter ≥ 10`, hourly, not sick:
  - `sickness_tries + 1`, `chance = (sickness_tries − 10) * 5 + (tiredness − 50)`, stored in a `uint8_t`;
  - sick if `randomLimit(100) < chance`.
  - **Quirk kept:** a negative chance wraps to 256 + chance. Down to −156 that is ≥ 100, so the partner gets sick for sure. E.g. 1st try at tiredness 0: −95 → 161. A positive chance is a normal percentage.
  - **Getting sick:** bit 6, `times_being_sick + 1`, `sickness_timer = 1`, happiness −20, `sickness_counter = 0`.
- **Sick from a disliked map:** `area_effect_timer > 12,000` (10 hours on the map), hourly, area response 2, not sick → sick (no happiness loss), `area_effect_timer = 0`.
- **While sick, hourly:** happiness −10, discipline −5, tiredness +5.
- **`if (!wasSick && sickness_timer > 0) sickness_timer = 0`:** clears a timer left from an earlier sickness. It also resets the 1 set by getting sick in this tick. Both ways of getting sick above happen on hourly frames, though, and the hourly increment below follows, so the timer ends at 1.
- **Hourly:** sick → `sickness_timer + 1`; injured → `injury_timer + 1`.
- **Immortal hour:** the rest is skipped.
- **Injury turns into sickness:** `injury_timer ≥ 12`, not sick, tamer state 0 → sick, injury cleared.
- **Message:** if the partner became sick in this tick, the tamer waits (state 0x14) and the text box shows "<name> is sick" (`IS_SICK_TEXT`, `MAIN_D_801225A0`).
- **Sick too long:** `sickness_timer ≥ 12`, partner state not 8, tamer state 0, lifetime not 0, no script running (`IS_SCRIPT_PAUSED == 1`):
  - `lives − 1`, script value 0xFF = 0, script section 0x4DE runs (the partner collapses);
  - `sickness_timer = 0`.

### 2.8 Death (`tickDeathCondition`, `:1917`)

Not in the immortal hour, with lifetime ≤ 0, partner state not 8, tamer state 0 and no script running: natural death (`IS_NATURAL_DEATH = 1`, used by rebirth), script value 0xFF = 0, lifetime 0, script section 0x4DE.

### 2.9 Unhappiness (`tickUnhappinessMechanics`, `:1042`)

- **Becoming unhappy:** no condition at all (`condition == 0`), happiness < 0, every 10 minutes. Unhappy (bit 4) if `randomLimit(100) < |happiness| − discipline`.
- **While unhappy:**
  - happiness +1 every 15 frames;
  - every 15 minutes (frame % 300) the base stats lose 2 % each: `x −= x * 2 / 100`, not below 1. Current HP / MP are capped at the new maximum.
- **Recovering:** at happiness ≥ 0 the bit clears. The current animation finishes its loop (`loopCount = 1`) and the butterfly goes away (§2.11).

### 2.10 Poop (`tickPoopingMechanic`, `:1656`; `tickWildPoop`, `partner.c:593`; `createPoopPile`, `:1242`)

- **Only with the tamer in state 0** (walking freely).
- **Filling up:** `poop_level − 1` every 10 minutes while not poopy. `raise.poop_timer` is the start value in tens of minutes (Agumon 24: 4 hours).
- **Needs the toilet:** at ≤ 0 the partner is poopy (bit 3). `pooping_timer = (discipline + 20) * 1200 / 100` frames (discipline 50: 840 frames, 42 game minutes).
- **Accident:** the timer goes −1 per frame. At ≤ 0:
  - partner state 7 (pooping in the wild), timer −1;
  - `ITEM_SCOLD_FLAG = 1`: a scold right after it counts more (`handlePraiseScold`).
- **The wild-poop scene (state 7):**
  - **Sub-state 0:** run animation (4); tamer state 6 (stands still) facing the partner; the camera stops following.
  - **1:** the partner faces the tamer and runs to him, through walls (no collision call in this state, §6). Once no longer far (`getPartnerTamerCloseness() > 0`: near or close), the poop animation (10).
  - **2:** at its end, `createPoopPile` on the partner's tile, `handleWildPoop`, animation 12.
  - **3:** at its end, tamer state 0, partner state 1, camera follows, `addTamerLevel(1, −1)`.
- **`handleWildPoop`:**
  - poopy cleared, care mistake + 1, happiness −10, discipline −5;
  - `poop_level = 2 * poop_timer`: the US doubles it, other releases don't (`:1763–1769`);
  - `handlePoopWeightLoss`: weight −= `(randomLimit(4) + raise.poop_size) / 4`, not below 1.
- **`createPoopPile(tile)`:**
  - **Tile:** the tile in front of the partner by its rotation. The ranges overlap, so diagonals step on both axes:
    - y − 1 for 0–0x300 or ≥ 0xD00;
    - x + 1 for 0x100–0x6FF;
    - y + 1 for 0x500–0xB00;
    - x − 1 for 0x900–0xF00.
  - **Slots** of `world.poop[100]`:
    - a pile already on that tile of this map moves the new one one tile in a random direction, and the search starts over;
    - otherwise the first free slot takes `{map: current, x, y, size: raise.poop_size}`.
  - **16 piles per map at most:** the 17th overwrites a pile of this map from the slot `CURRENT_POOP_ID` on (a rotating index, wraps at 100). With all 100 slots in use, slot `CURRENT_POOP_ID` is overwritten.
  - **Then:** `virus_bar + 1` (not for Sukamon, §4), and a cloud effect at the pile (`createCloudFX`; later with effects).
- **Drawing** (`renderPoop`): every pile of the current map is the model `ETCNA/UNTI.TMD` at the tile centre, at the partner's height, scaled `size / 10`.
- **Poop eaters** (`tickPoopDetection`, `:1688`): Numemon (0xB) and Sukamon (0x27) walk to a pile the tamer stands near: within 200 units of its centre, 300 for size ≥ 11. They eat it (partner state 9, `handleEatingPoop`: HP / MP / weight by size, a chance to cure). **Comes with evolution**: no partner can be one yet.

### 2.11 Condition bubbles (`handleConditionBubble`, `:1551`; `bubble.c`)

- **Choosing** (every frame in states 1 and 10):
  - **Order:** each condition sets the candidate when its bubble isn't the one showing (`CONDITION_BUBBLE_TYPE`); later ones override: sick (bubble 2), injured (6), poopy (1), hungry (0), tired (4), sleepy (3).
  - So the candidate is the highest-priority condition (sleepy highest) other than the one showing.
  - **Butterfly:** with only "unhappy" (`condition == 0x10`) and no bubble candidate, the bubble is removed and a butterfly circles the partner (`setButterfly`, `butterfly.c`).
  - **Showing:** otherwise a new candidate replaces the bubble once the current one has shown for ≥ 50 frames (`CONDITION_BUBBLE_TIMER`). The butterfly goes away, unhappy is cleared and the animation finishes its loop.
  - **Timer:** +1 per frame; at ≥ 60 the showing type is forgotten (−1), so the top condition can show again.
  - **Result:**
    - one condition: a bubble every ~61 frames (3 seconds);
    - two or more: the two highest alternate every 50 frames.
- **A bubble** (`addConditionBubble`, `tickConditionBubble`, `renderConditionBubble`; 3 slots):
  - **Position:** starts at the partner's height − `DIGIMON_DATA.height` + 20.
  - **Frames 0–9:** grows (scale 0 → 0x6000 = 1.5) and rises 65 units.
  - **Frames 10–49:** bobs ±12 units on a sine (`lerp(0, 512, 0, 20, frame)` as angle).
  - **Frame 50:** a burst sprite 230 units higher, at scale 0xF000; removed after frame 50.
  - **On screen:** kept below the screen top.
  - **Sprites:** the bubble sprite (32 × 32) behind an icon (16 × 16, the Z's 8 × 8), animated per icon:
    - hungry: 19-frame cycle;
    - poopy: 13;
    - injured: 20;
    - tired: 13, with a u / height table;
    - sick: 2 frames of 20;
    - sleepy: a sequence of 1–3 Z's (`CONDITION_ICON_SLEEPY`, durations 10, 4, 4, 8, 1, 1, then back 5 entries).
- **Texture:** `CONDITION_SPRITES` are tpage 0x3F / 0x5F (VRAM 960, 256), u 0x80–0xF0, v 0x80–0xBF. Palettes are rows 481–484 at x 272. That is ETCTIM entry 3 `feel_ef` (VRAM 960,384, CLUT 272,480; asset porter `etctim/03_feel_ef`, `specs/stacked_tim.md`):
  - pixel = (u, v − 128);
  - palette row = CLUT y − 480 (`.p<n>.png`).
- **Visibility:**
  - bubbles aren't drawn in menus;
  - bubbles and the butterfly are removed when the partner leaves states 1 / 10 (`partnerTick`, `partner.c:191`).

### 2.12 Area response (`loadMapSetup`, `map.c:4179–4200`)

- **Where it comes from:** the map setup holds 4 liked and 4 disliked region bytes (asset porter `specs/map.md`, setup).
- **Rule:** with the partner's `raise.favored_region`, the entries are tested in the order liked[0], disliked[0], liked[1], disliked[1]…; the first match gives 1 (liked) or 2 (disliked), else 0.
- **What it changes:**
  - tiredness and happiness on the map (§2.6);
  - sickness after 10 hours (§2.7);
  - sleep recovery (×1.2 / ×0.8, §2.13);
  - the blinking happiness icon of the bars (§2.14).

### 2.13 The sleep scene (`partnerTickSleep`, `partner.c:278`; `sleepRegen`, `handleSleeping`)

Started from the menu's "Sleep" (partner state 3, `game_menu.c:2178–2186`), only enabled while sleepy.

| Sub-state | What happens |
|---|---|
| 0 | game time stops; the camera stops following; the partner walks (2) towards the tamer unless close; tamer state 6 |
| 1 | both face each other; when close: sound 15, tamer animation 8, partner idle |
| 2 | at the end of the tamer's animation: partner animation 11 (lying down) |
| 3 | at its end: animation 9 (asleep) |
| 4 | 5 frames before its end: fade to black over 40 frames |
| 5 | when black: `sleepRegen`, `handleSleeping`, then the save prompt (main menu object 5000) |
| 6 | when the prompt closes: fade in, idle, `updateTimeOfDay` |
| 7 | when the fade is nearly done: partner state 1, tamer state 0, camera follows, special evolutions (mode 2), game time runs |

- **`sleepRegen`:**
  - **Hours slept:** `hoursSlept` = hours from now to `wakeup_hour` (+24 past midnight), +1 if `MINUTE > 0` and `HOUR ≠ sleepy_hour`.
  - **Factor:** `factor = hoursSlept * 100 / hours_asleep_default`; ×1.2 with a Rest Pillow (item 0x22) in the inventory; ×1.2 on a liked map, ×0.8 on a disliked one.
  - **HP / MP:** each + `factor * (max * (randomLimit(10) + 70) / 100) / 100`, capped at the maximum.
  - **Tiredness:** − `factor * (tiredness * (randomLimit(20) + 80) / 100) / 100`, not below 0.
  - **Weight:** − `raise.default_weight / 10`, not below 1.
- **`handleSleeping`:**
  - **Time:** `advanceToTime(wakeup_hour, wakeup_minute)` (a new day if earlier, `specs/clock.md` §2.4); `evo_timer += hours_asleep_default`; lifetime −= hours slept.
  - **Next schedule:** like a missed night (§2.5), then `setFoodTimer`.
  - **Resets:** `starvation_timer = 0`, hungry and sleepy cleared, `time_awake_today` / `tiredness_sleep_timer` / `sickness_counter` reset, "Sleep" disabled.
  - **Immortal hour:** the wake-up hour.
  - **Poopy:** a pile on the partner's tile; poopy cleared; `poop_level = poop_timer` (not doubled); no care mistake.
  - **Quirk kept:** "hungry → weight − 1" comes after hungry was cleared, so it never applies.
  - **Sick:** `sickness_timer +=` hours slept, happiness −20, discipline −10, tiredness +10.
  - **Injured:** `injury_timer +=` hours slept, −10 / −5 / +5.

### 2.14 Status bars (`renderStatusBars`, `:2153`)

- **When:** drawn with the clock (`renderGameClock`, `clock.c:290`).
- **Slide:** `STATUS_UI_OFFSET_X` (x from the screen centre, like the clock) moves 50 per frame towards 75 while game time runs, and towards 240 (off screen right) while it is stopped.
- **Texture:** page 5 (VRAM 320, 0); `system_w` (ETCTIM entry 8, VRAM 320,128, CLUT 96,488; asset porter `etctim/08_system_w`):
  - pixel = (u, v − 128);
  - palettes: CLUT (96, 500) = `p12`, (96, 503) = `p15`, (96, 498) = `p10`.

| Part | Rect (u, v, w, h) | Palette | Screen (x, y) from the centre |
|---|---|---|---|
| happiness frame | 0, 236, 75, 8 | p12 | off, 85 |
| discipline frame | 0, 236, 75, 8 | p12 | off, 97 |
| happiness icon | 64 (≥ 0) or 97 (< 0), 244, 11, 11 | p15 | off + 3, 83 |
| discipline icon | 22 (≥ 50) or 33 (< 50), 244, 11, 11 | p10 | off + 3, 95 |
| happiness dots | 232, 151 / 153, 2, 2 | p15 | off + 18 + 2i, 88 |
| discipline dots | 232, 151 / 153, 4 wide, 2 | p15 | off + 18 + 2i, 100 |

- **Happiness:**
  - **≥ 0:** 25 background dots (v 151), then `happiness / 4` dots at v 153;
  - **< 0:** `(happiness + 100) / 4` dots at v 151, no background.
  - **Blinking:** on frames where `PLAYTIME_FRAMES % 10 < 5` the icon's u moves +11 on a disliked map, −11 on a liked one.
- **Discipline:**
  - **≥ 50:** 25 background dots, then `(discipline − 50) / 2` dots at v 153;
  - **< 50:** `discipline / 2` at v 151.
  - **Quirk kept:** the discipline dots are 4 wide at a step of 2, so they overlap.
- **Layer:** the higher z (14) is drawn behind the lower (13): background dots behind the value.

### 2.15 A new partner (`initializePartner`, `:450`)

- **On a new game:** the boot calls it for Agumon (3), or Gabumon (0x11) when script value 0xFE is set (`main.c:3446–3451`).
- **It sets:**
  - condition 0, the sleep schedule, `missed_sleep_hours = 0`;
  - `poop_level = poop_timer`, `pooping_timer = −1`, `virus_bar = 0`, `tiredness = 0`;
  - discipline 50, happiness 50, `unused3` 50;
  - the food timer, `energy_level = energy_threshold`, lifetime 360, `weight = default_weight`;
  - training boost, care mistakes, battles, `evo_timer`, sickness / injury / area timers all 0;
  - lives 3, the immortal hour cleared.
- **First technique:**
  - Agumon: slot 0 = Spit Fire, learns technique 2;
  - Gabumon: slot 0 = 0x30, learns 0x2B.
  
  Slots 1–2 are emptied; slot 3 is the last finisher in the technique list (ids 0x3A–0x70).
- **Not set here:** stats (HP, MP, offense…). The intro scripts give them.
- **Quirk:** loading a game (boot modes 1 / 2) calls `initializePartner` too (`main.c:3462`, `:3480`), before the map's head script. How the saved `PARTNER_PARA` survives that isn't traced (§5).

## 3. Godot design

### 3.1 Nodes and the tick

- **`Care`** (`scripts/systems/care.gd`, class `Care`): the care rules, one method per C function (names in §1). It reads and writes `GameState.state.partner.care`, `partner.stats`, `clock`, `world.poop` and `script`, and reads `GameData` through the partner's `care` component. It owns no state of its own except the non-saved globals:
  - `CONDITION_BUBBLE_TYPE / TIMER`;
  - the butterfly flag;
  - `ITEM_SCOLD_FLAG`, `CURRENT_POOP_ID`;
  - the immortal hour (`HAS_IMMORTAL_HOUR`, `IMMORTAL_HOUR`), which the original doesn't save either.
- **`Partner`** (`specs/partner.md`) gets `state` / `sub_state` (`PARTNER_STATE`, `PARTNER_SUB_STATE`, not saved, 1 after loading) and dispatches like `partnerTickOverworld`:
  - **1 (normal):** collision, walking, then `Care.tick_conditions()`, `tick_pooping_mechanic()`, `tick_poop_detection()`, `handle_condition_bubble()`;
  - **3 (sleep), 7 (wild poop):** the scenes of §2.13 / §2.10;
  - **every frame:** `tick_condition_boundaries()`.
  
  Other states come with their systems.
- **`Tamer`** gets a minimal `state` (0 free, 6 standing still; other values as their systems arrive). The tamer ignores input outside state 0. `tamerGetState() == 0` checks read it.
- **Order per game frame:** the partner (and so care) ticks **before** the clock, as in the original (§2.1): the field connects `Partner.tick` to `GameLoop.frame` before the `Clock`. "The frame advanced" is `clock.frame != clock.last_handled_frame`.
- **Gates** (§2.1):
  - `GAME_STATE == 0` / `FADE_PROTECTION`: `Clock.active` (false while warping);
  - `IS_GAMETIME_RUNNING`: `Clock.running`;
  - the daytime fade: `FieldMap.is_in_daytime_transition()`.
- **Area response:** the field computes it on map load from the map's liked / disliked regions (asset porter map setup) and the partner's `favored_region`, and stores it on `Care`.

### 3.2 Visuals

- **`ConditionBubbles`** (`scripts/systems/condition_bubbles.gd`), a HUD control: `bubble.c`'s three slots, tick and render.
  - **Its parts:** the sprite table, the icon sequences, `lerp` with its wrap, the burst at frame 50, the top-of-screen clamp, the depth adjustment.
  - **Who drives it:** `Care.bubble_shown` replaces the current bubble, as `handleConditionBubble` does.
  - **Placement:** the 3D point is projected with the field camera. The size is `scale × projection / depth` (`renderSprite`), and each sprite is anchored at its (mx, my).
  - **Approximation:** the bubble's x / z follow the partner's position. The original offsets it from a bone (`CONDITION_FX_OFFSETS[type]`, `translateConditionFXToEntity`, `effect_common.c:307`), which isn't converted yet. The height is the original's: `DIGIMON_DATA.height`.
  - **Semi-transparency:** `PsxTexture` splits a palette page into opaque texels and texels whose colour has the STP bit (from the sidecar's raw palette). The bubble and the burst (attribute `0x40000000`, mode 0) draw their STP texels at half alpha. The icons (`0x50000000`, mode 1) draw theirs on an additive layer.
  - **Missing:** the butterfly is a later step (`butterfly.c` not ported); unhappy shows no butterfly yet.
- **`StatusBars`** (`scripts/systems/status_bars.gd`): the table of §2.14 from `etctim/08_system_w` (palettes p10 / p12 / p15), drawn opaque (the original's prims have no semi-transparency flag), with the slide and the blinking icon.
- **`PoopPiles`** (`scripts/field/poop_piles.gd`), under the 3D viewport:
  - one `UNTI` model (`tmd_files/ETCNA/UNTI.gltf`) per pile of the current map, at the tile centre, scaled `size / 10`, at the partner's height every frame;
  - rebuilt on map load and on `Care.poop_changed`.
- **The cloud effect** and the sounds (15 for sleep): later with effects / audio.

### 3.3 Stand-ins until the systems exist

| Original | Stand-in | Real version |
|---|---|---|
| menu "Sleep" (enabled while sleepy) | debug key `Z` (later also the panel), refused unless `Care.sleep_enabled` and both are free | menus milestone |
| save prompt after sleeping (sub-state 5) | skipped | menus |
| fade to black / in | `Fade`: `fade.c`'s counters exactly (`out_current`, `in_current`, `progress`, `protection`, stops game time); drawn as black at alpha `progress / 160` instead of the original's colour subtraction | kept, reused by warps later |
| "<name> is sick" text box (tamer state 0x14) | `Care.message`: the help line shows it for 100 frames; the tamer isn't stopped | text renderer |
| script section 0x4DE (collapse / death), `IS_SCRIPT_PAUSED` | the care sets the C values (lives − 1, timer 0, `IS_NATURAL_DEATH`), sets `script_running` and emits `script_requested(0x4DE)`. The field applies what `partnerTickDying` leaves at its end (lifetime 360, sickness / injury timers 0, `partner.c:674–676`) and ends the "script"; no rebirth | scripts milestone |
| scene animations the model lacks | skipped (the scene goes on); the original would wait forever | kept |
| partner state 9 (eating poop) | `tick_poop_detection()` finds the pile; the state isn't entered | with the poop eaters |
| evolution target, special evolutions (§2.2 step 7, sleep sub-state 7) | not computed | evolution step |
| butterfly, cloud effect, sounds | none | effects / audio |

### 3.4 Functions ported now, used later

`skip_hours` (scripts), `handle_toilet` (toilet scene), `handle_eating_poop` (poop eaters), `handle_praise_scold` (menus), `handle_post_battle_tiredness` (battle).
- **Deferred to the menus:** `partnerHandleFoodFeed` and `partnerWillRefuseItem` test item id ranges (food 0x26–0x46, evolution items, 0x73+). They wait for item properties for those ranges.
- They are short state changes, tested now against the C.
- The debug panel calls some of them: praise, scold, toilet.
- `skipHours` has a JP / US difference (`int16_t` vs `int32_t` hours); the US version is ported.

### 3.5 Debug panel

A panel in the field HUD (key `C`), not part of the original:
- **Values:** every care value, readable, with the condition bits as named toggles.
- **Time:** game speed ×1 / ×10 / ×60 (the `GameLoop` emits that many frames per tick, so every timer runs as in the game, only faster) and "+1 hour" through `skip_hours`.
- **Actions:** set happiness / discipline / tiredness / energy; make the partner hungry, poopy (pooping timer 1), sleepy; "Sleep" (enabled while sleepy); praise, scold, toilet.

`T` (one hour, `advance_to_time`) stays: it jumps the clock without the hourly care effects, like the scripts' time jumps.

## 4. Content properties (`specs/content.md` §4)

The care code names Digimon and items by literal id. The data porter derives these properties and checks the C text is unchanged (`out.check`), so `dw1` behaves the same. Done 2026-10-23 (`data_porter/specs/digimon.md` §3, `items.md` §3):

| C rule | Where | Property |
|---|---|---|
| `type == 3` → slot 0 = 0x2E, `learnMove(2)`; `type == 0x11` → 0x30, `learnMove(0x2B)` | `initializePartner`, `:499–506` | `raise_data.first_technique`: `{slot, move}` (null for others) |
| `type == 0xB \|\| type == 0x27` eat poop | `tickPoopDetection`, `:1697` | `raise_data.eats_poop` |
| `type != 0x27` raises the virus bar | `createPoopPile`, `:1319` | `raise_data.raises_virus_bar` (false for Sukamon) |
| `getItemCount(0x22)` boosts sleep | `sleepRegen`, `:1351` | `item_data.passive == "sleep_boost"` (Rest Pillow; the other passive items got theirs too, `data_porter/specs/items.md` §3) |
| levels 1 / 2 (Fresh / In-Training schedules), level checks of `setFoodTimer`, `setSleepTimes`, `tickSleepMechanics` | §2.4, §2.5 | `digimon.level.id` (already data) |

Also from data instead of ids: `initializePartner`'s finisher slot (`moves[i]` in 0x3A–0x70) reads the technique `category == "finisher"`.

`dw1`-only rules, kept as documented code:
- the sleep times 3 / 7 hours and the hunger steps 2 / 3 hours for levels 1 / 2;
- every threshold and rate in §2 (the original's balance).

The virus-bar evolution to Sukamon (0x27) and the reincarnation stats (types 1, 15, 29, 43) belong to the evolution / death steps (`virus_bar_target` there).

## 5. Verification

`tests/test_care.gd`, values worked out from the C:
- **Food timer:** Agumon at 14:30 → 17:00, `food_level` 150; the "previous call" rule (stored 13 at 14:00 → 17); wrap to 1 after 21; `next == HOUR` → hungry at once; Fresh / In-Training steps.
- **Hunger:**
  - `food_level` 1 → hungry on the next minute, `starvation_timer` 180;
  - a call expiring after 1,800 frames, with and without the care mistake;
  - energy −`energy_usage` per hour;
  - weight loss at 0 energy.
- **Sleep:**
  - Agumon sleepy from 19:00, not at 18:59;
  - a missed night at 04:00 (care mistake, schedule kept);
  - bedtime moving earlier with tiredness (`tiredness_sleep_timer`, `sleepy_minute`);
  - the loss per level.
- **Sickness:**
  - the `uint8_t` chance (tries 1, tiredness 0 → certain; a positive chance with seeded rolls);
  - the timer quirk (0 after getting sick);
  - injury → sickness at 12;
  - sick-too-long: lives − 1 and `script_requested(0x4DE)`.
- **Lifetime:** the 4-hour loss by happiness (50 → 1, −100 → 4).
- **Unhappiness:** seeded roll, +1 per 15 frames, stat loss 2 % with the floor of 1, cleared at ≥ 0.
- **Poop:**
  - `poop_level` per 10 minutes;
  - `pooping_timer` from discipline;
  - state 7 at 0;
  - `handleWildPoop` (US double, weight loss);
  - `createPoopPile` tiles by rotation, the collision step, the 16-per-map rule.
- **Bubbles:** choice and priority, alternation of two conditions every 50 frames, the 60-frame forget.
- **Sleeping:** `sleepRegen` with fixed rolls and both area factors; `handleSleeping` (time jump, schedule, poop pile, sick / injured, the dead hungry branch).
- **Gates:**
  - nothing while the clock is stopped, inactive, or in a daytime fade (from step 5 on);
  - the immortal hour;
  - partner-before-clock order (a hunger call at the exact frame).
- **Content properties:** Agumon's first technique from the property; a pack-patched `eats_poop` read by `tick_poop_detection`.

`VERIFY.md` Care section (human checks):
- bubbles over Agumon when hungry / poopy / sleepy, alternating with two conditions;
- the bars slide in and out with the clock;
- the wild-poop scene and the pile on the map;
- the sleep scene with its fade, waking at 04:00 with HP / MP restored;
- the debug panel speeds.

## 6. Open questions

- **Loading a game** calls `initializePartner` (§2.15). The port keeps the saved care values on load. Where the original restores `PARTNER_PARA` after the reset is to be traced with the save menu.
- **Wild poop, sub-state 1 (answered 2026-10-23):**
  - **Rule:** `getPartnerTamerCloseness() > 0` means near *or close* (0 is far). The partner runs to the tamer until it is within 3.5 radii, then squats.
  - **No walls in the scenes:** these states never call `entityCheckCollision`, the only caller of `checkMapCollision` (`map.c:3434`), so nothing tests the map. The port first blocked the partner on walls in every state, and a far partner then ran into a wall forever, with the tamer frozen. Now the map blocks only in the normal state (`Partner._move`). The sleep scene's walk to the tamer (sub-state 1) is covered by the same rule.
- **Partner stats** at a new game are 0 until the intro scripts set them. The unhappy stat loss then clamps them to 1, as the code would. The debug panel can set stats.
- **`sub_tiredness`** is never increased in the decomp (§2.6): kept as dead code.
- **`randomLimit(1)`** in `setSleepTimes` is always 0. Possibly meant as 0–1; kept.
- **`CONDITION_BUBBLE_TYPE`** starts at 0 (bss), so a hungry bubble can't be the first bubble shown after boot until the type is forgotten. Matches the C; harmless.
- **The butterfly** (`butterfly.c`) and `createCloudFX` are not read yet.
- **`handlePraiseScold`** (`:1113`):
  - **Which is which:** state 4 is the scold (discipline +2, happiness −10) and state 15 the praise (discipline −5, happiness + discipline / 10 + 2). The menu's "Scold" is entry 5 → state 4 and "Praise" entry 4 → state 15 (`game_menu.c:2187–2209`).
  - **Uninitialised happiness:** a scold with `ITEM_SCOLD_FLAG == 1` (right after an accident or a refused item) gives discipline +8 and leaves `happinessDelta` uninitialised. The port uses 0.
  - **Missing argument:** the US build calls `handlePraiseScold()` without its argument (`partner.c:400–404`), so `state` is whatever the register held, presumably still the partner state. The port passes the partner state.
