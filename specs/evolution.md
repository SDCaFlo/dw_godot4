# Evolution

Status (2026-10-26): approved; **5f-1 (the rules) done** (see "As built" at the end); 5f-2 (the scene) to do (`PLANS.md` 5f).

When and into what the partner evolves, and what evolving does to it. The rules are in `main/evolution.c`, the triggers in `partner_impl.c`, `partner.c` and `item.c`, and applying the evolution and the scene are in the `evl` overlay. The data porter already has the tables and documents the selection in detail (`data_porter/specs/evolution.md` §2). This spec says how the port runs them.

The work is split in two:
- **5f-1, the rules:** every trigger, the target selection, applying the evolution (stats, care, techniques, the model swap, the "raised" mark), and partner state 13 with a short **stand-in** for the scene.
- **5f-2, the scene:** the `evl` sequence (the field going dark, the camera orbit, the old model breaking into shards, sparks and flashes, the new model fading in). It is specced in outline here (§2.9) and in detail before 5f-2 is coded.

## 1. The C code

| C (US) | What |
|---|---|
| `tickConditions` (`partner_impl.c:2106–2149`) | the hourly check and the virus bar (§2.1, §2.4) |
| `getFreshEvolutionTarget`, `getInTrainingEvolutionTarget`, `getRookieEvolutionTarget`, `getChampionEvolutionTarget`, `calculateRequirementScore`, `getNumMasteredMoves` (`evolution.c:674–1050`) | the target selection (§2.2) |
| `handleSpecialEvolutions(mode, entity)` (`evolution.c:852`); its callers `partner.c:359` (mode 2, after waking) and `:417` (mode 3, after praise / scold) | special evolutions (§2.3) |
| `handleEvoItems` (`item.c:2190`), `HAS_USED_EVOITEM` (`evolution.c:670`, reset only by `initializeStatusObjects`, `partner_impl.c:427`, at boot `main.c:3408`) | the evolution items (§2.5) |
| `callDigimonRoutine` 2 and 10 (`partner.c:1150`, `:1207`) | script evolutions (§2.6) |
| `partnerTickEvolving` (`partner.c:741`), partner state 13, tamer state 6 | the partner while it evolves (§2.7) |
| `getEvoSequenceState`, `tickEvoSequenceLoading` (`main/evl.c`) | the scene's start (§2.8) |
| `EVL_initEvoSequence`, `EVL_tickEvoSequence` and its effects (`evl/evl.c:345–1290`) | the scene (5f-2, §2.9) |
| `EVL_applyEvolution`, `EVL_scaleBaseStats`, `EVL_clampBaseStats` (`evl/evl.c:1332–1556`), `initializeEvolvedPartner`, `resetPartnerPara`, `setSleepTimes` (`partner_impl.c:565–660`) | applying the evolution (§2.10) |
| `setDigimonRaised` / `hasDigimonRaised` (`script_common.c:3011`: trigger 0x200 + id, ids < 0x3F) | the "raised" mark |
| Data | `evolution/requirements`, `paths`, `stat_gains`, `item_targets` (done); `digimon_data` (`level`, `special`, `moves`, `height`, `radius`); `raise_data.default_weight`; `move_data` (`power`, `category`); new: `evolution/rules` (§3.3) |

## 2. Behaviour

`EVOLUTION_TARGET` (`Care.evolution_target`, −1 = none) is the Digimon to evolve into. Every trigger sets it and puts the tamer in state 6 and the partner in state 13; state 13 runs the evolution and clears it.

### 2.1 The hourly check (`tickConditions`, after the hour's care)

It runs where `Care` already stops today (`care.gd:217`): after the immortal-hour checks, once no daytime fade runs.

1. **The timed evolution**, only if the clock advanced this frame (`CURRENT_FRAME != LAST_HANDLED_FRAME`, `Care._advanced()`), the partner is in state 1 and the tamer in state 0. With `t` = `evo_timer` and the partner's level:
   - Fresh, `t` ≥ 6: the Fresh target (§2.2);
   - In-Training, `t` ≥ 24: the In-Training target;
   - Rookie, `t` ≥ 72: the Rookie target;
   - Champion, `t` ≥ 144: the Champion target;
   - then, separately: Champion with `t` == 360: `handleSpecialEvolutions(3)` (§2.3).

   Each sets `EVOLUTION_TARGET` to its result, which may be −1.
2. **The virus bar**, every time this point is reached: if `virus_bar` ≥ 16 and the partner isn't Sukamon (0x27):
   - target = Sukamon;
   - script value 5 (`PSTAT_SUKAMON_BACKUP_DIGIMON`) = the partner's type;
   - `suka_backup_hp / mp / off / def / speed / brain` = the base stats;
   - `virus_bar` = 0.
3. If `EVOLUTION_TARGET` ≠ −1 and the partner isn't in state 13: tamer state 6, partner state 13.

The timed check repeats every frame its conditions hold, so a −1 result means "not yet": the next frames (and hours) try again.

### 2.2 The target selection

As in `data_porter/specs/evolution.md` §2, with these points for the port:
- **Fresh:** the fixed target (Botamon → Koromon, Punimon → Tsunomon, Poyomon → Tokomon, Yuramon → Tanemon). `getFreshEvolutionTarget` also sets `evo_timer` = 0 at once. For another Fresh the C returns an uninitialised value; the port returns −1.
- **In-Training:** the candidate (the `to` list, in order) with the highest score ≥ 3; the first one wins a tie.
- **Rookie / Champion:** among the candidates with a score ≥ 3, the highest average of the stats their requirements name (HP and MP / 10).
  - **The quirk stays:** the sum and count are reset only when a candidate becomes the best, so a losing candidate's stats add into the next one's average. A candidate whose average is ≤ the best keeps its sums too.
  - The best average starts at 0, so a candidate with an average of 0 never wins.
  - Rookie only: no candidate, and `evo_timer` ≥ 96 → Numemon (11).
- **The score** (`calculateRequirementScore`), one point each:
  1. care mistakes ≥ the requirement (≤ with flag 0x10);
  2. weight within ± 5;
  3. stats: for a Rookie target, the partner's highest stat (HP and MP / 10; with equal values the **last** one wins) has requirement 1; otherwise every stat ≥ its requirement (−1 always passes: a signed compare);
  4. the bonus: any of "comes from `digimon`", discipline ≥, happiness ≥, battles ≥ (≤ with flag 0x01), mastered techniques ≥ (`getNumMasteredMoves`: the learned-move bits).

  Then, if the score is ≥ 3 and there is a current best: a target already raised against a best not raised → 0; a target not raised against a best raised → + 1. "Raised" reads the target's `targetDigimon` (`stat_gains`).
- **Battles** is `care.battles` (0 until the battles are ported, 5d).

### 2.3 Special evolutions (`handleSpecialEvolutions`)

Only with the tamer in state 0. One roll `r` = `randomLimit(100)` per call; the later rules overwrite the earlier ones:
- **Mode 2** (after waking up, `partnerTickSleeping`'s end):
  - `r` < 30: Birdramon or Seadramon with discipline 100, happiness 100, tiredness 0 → Airdramon; Vegiemon with battles ≥ 50 and discipline 100 → Ninjamon; Drimogemon with Defense ≥ 500 and discipline 100 → Monochromon;
  - `r` < 50: an In-Training (Koromon, Tsunomon, Tokomon, Tanemon) on map 1 → Kunemon.
- **Mode 3** (after a praise or scold, and at Champion `evo_timer` == 360 from §2.1):
  - Whamon or Shellmon, Champion, `evo_timer` == 200, `r` < 30 → Coelamon;
  - `NANIMON_TRIGGER` set → Nanimon, and the trigger is cleared (`Care` already sets it: a Rookie scolded at discipline 0 and happiness −100);
  - Champion, `evo_timer` ≥ 240, `r` < 50 → Vademon.

A result ≠ −1 sets `EVOLUTION_TARGET`, tamer state 6 and partner state 13 at once. The function returns its result; §2.1 stores it in `EVOLUTION_TARGET` again (the same value).

### 2.4 The virus bar

§2.1 step 2. Sukamon's own evolution back is a script (routine 2, §2.6); applying it uses the backup (§2.10).

### 2.5 The evolution items (`handleEvoItems`)

The inventory's Use on an item whose handler is `handleEvoItems`:
- items 0x7D / 0x7E / 0x7F: target Gigadramon / Panjyamon / MetalEtemon, with no level check;
- the others (`item_targets`): only if the partner's level is the target's level − 1; else nothing happens. The item is still used up: the feeding scene removes it after the handler either way (`removeOneSelectedItem`). The partner refuses most wrong-level items before eating them (`ItemUse._evolution_refused`: target level = its level, + 2 or − 1); the other levels are eaten for nothing.
- then: `HAS_USED_EVOITEM` = 1, the tamer's held item cleared (`removeTamerItem`), the inventory closes, tamer state 6, partner state 13.

**`HAS_USED_EVOITEM` is never cleared** except at boot. Once an item was used, every later evolution of the session (natural ones too) gets no stat gains and no Ultimate lifetime bonus, until the game is restarted. It isn't saved. The port keeps it the same way (a flag of the running game, not of `GameState`). Open point §6.

### 2.6 Script evolutions (`CALL_DIGIMON_ROUTINE`)

- **2:** target = script value 5 (Sukamon's backup Digimon), partner state 13, the sync bit cleared.
- **10:** target = script value 0xFE, partner state 13, the sync bit cleared.

The script waits on the sync bit, which state 13 sets at its end (§2.7). These are the game's event evolutions; they all come from the scripts, not from `evolution.c`:

| Where | Script | Rule |
|---|---|---|
| Factorial Town, the remodel shop (FACT10) | 156, section 5 | Only for **Mamemon** (13), 2000 bits: a roll of 0–9; 0 → **Giromon** (41, "It didn't work, but…"), 1–5 → **MetalMamemon** (27), else nothing |
| Toy Town, the Costume House (OMOC02) | 139 | **Numemon** (11) and the zipper → **Monzaemon** (14) |
| Trash Mountain, King Sukamon (GOMI02) | 159 | **Sukamon** back to its saved Digimon (routine 2) |
| After losing a battle (script 212, section 72, at Jijimon's house, with lives left) | 212 | a roll of 0–99: Agumon, Betamon, Gabumon, Elecmon, Patamon, Kunemon, Biyomon, Palmon, < 10 → **Bakemon** (37); MetalGreymon or Megadramon, < 10 → **SkullGreymon** (26); Kokatorimon, < 10 → **Phoenixmon** (59); Angemon, < 50 with discipline ≤ 49 → **Devimon** (6) |
| A debug NPC, "Mr. Digivolution" (File City, script 164 section 6, with the debug warps) | 164 | Numemon, Sukamon or Botamon on request |
| A script without a map | 209 | "Digivolve to Sukamon" (routine 2 after storing the type) |

So these need no evolution code of their own: once routines 2 and 10 work (5f-1), the Factorial Town, Costume House and King Sukamon ones work in the field as their scripts already run. The battle-loss ones (SkullGreymon, Devimon, Bakemon, Phoenixmon) run when the battles and the "death and lives" step (6) reach script 212. Greymon → MetalGreymon is a normal Champion → Ultimate evolution by requirements (§2.2), not an event.

### 2.7 Partner state 13 (`partnerTickEvolving`)

- **Sub-state 0:**
  - game time stops (`stopGameTime`);
  - the △ menu, the inventory and box 1 close; fishing is disabled; the camera stops following the tamer;
  - the tamer looks at the partner; the partner plays animation 2 (walk);
  - → 1.
- **1:** the partner looks at the tamer (and walks: animation 2 has root motion). Once closeness > 0 (`Partner.closeness()`): the scene starts (`getEvoSequenceState(…, 0)`, §2.8), → 2.
- **2:** each frame the scene's timer (`getEvoSequenceState(…, 1)`). At −1:
  - game time runs again; `EVOLUTION_TARGET` = −1;
  - the map's sounds, shop, arena and TFS are reloaded (the port: the map's sound set);
  - fishing enabled; partner state 1;
  - if the sync bit is 0 (a script evolution), it is set; else the tamer goes back to state 0 and the camera follows him.

### 2.8 The scene's start (`getEvoSequenceState(…, 0)`, `tickEvoSequenceLoading`)

- the scene's data: timer 0, state 0, the target, `digimonId` = `stat_gains[target].targetDigimon`, the height factor;
- the partner plays animation 0; sounds stop; the evolution sound set (map sounds 18) and the new Digimon's voice bank (`VLALL`) load; the `evl` overlay loads;
- **the loading object**, each frame (its timer + 1, at most 30000):
  - state 0: once the timer is past 55 (the 57th frame): state 1, timer 0 (then + 1), the partner plays animation 1, condition bubble 7 over it;
  - state 1: once the timer is past 55 again (56 more frames; and the overlay loaded): the object ends, the music stops (`stopBGM`), the sequence starts (`EVL_initEvoSequence`, §2.9).

`getEvoSequenceState(…, 1)` returns the timer, which the sequence sets to −1 when it ends.

### 2.9 The sequence (5f-2, outline)

`EVL_initEvoSequence`: the effects' buffers, the field's two CLUT banks and the partner's CLUT saved, a random order of the partner's bones. Then `EVL_tickEvoSequence`, one state a frame, its timer counting from 0:
- **0 (frames 0–31):** the field's palettes and the partner's fade to black (`fadeoutCLUT1/2`, `EVL_fadeClutBank0/1`). At 32: the other entities and the map hidden, the camera saved, the new model loads; → 1.
- **1:** the camera moves around the partner (`EVL_updateEvoCamera`) until frame 0x6A: sounds (8, 1) and (8, 0), animation 0xC (then 1 when it ends), → 2 with the first shard.
- **2 (to frame 0x162):**
  - green particles rise (`EVL_spawnParticle`, the pattern `EVL_D_80063F28`);
  - frames 0x70–0xCC: the partner's CLUT brightens (`EVL_brightenDigimonClut`);
  - frames 0x70–0x11B: the bones break off one by one in the random order, each a shard set flying off (`EVL_buildShardSet`), a spark streak (`EVL_spawnSpark`), a flash (`EFECreateFlash`) and a sound (8, 2–4); the bone's wireframe level → 0;
  - frames 0xCC–0x107: the scale and size grow from the old Digimon's to the new one's;
  - from 0xA5: the camera orbits (speed up to 0x16 a frame), its distance from the size;
  - 0xD6: sounds stop, sound (8, 5); 0xD7–0x11B: flashes at bone 1, faster towards the end;
  - **0x11C: `EVL_applyEvolution`** (§2.10): the new partner; animation 0;
  - 0x126–0x14E: the new model fades in (`PARTNER_WIREFRAME_TOTAL` 0 → 0x10);
  - 0x162: the camera and offsets restored, → 3.
- **3:** the palettes back, entities and map shown, the music back (`forceUpdateBGM`), animation 0xB (the new Digimon's pose), particles released, the map's sounds reloaded; → 4.
- **4:** when animation 0xB ends: timer −1, the object ends.

5f-2 ports this with Godot means (the palette fades as a fade of the field's colours, the shards from the model's meshes, the flashes like `ParticleFX`), with its own detailed section before coding.

**The 5f-1 stand-in:** the loading part of §2.8 as in the C (animation 0, 55 frames, animation 1 with bubble 7, 55 frames, the music stops), then at once `EVL_applyEvolution`, animation 0xB of the new Digimon, and the end (−1) when it finishes; the music comes back. So the evolution plays, lasts about 6 s plus the pose, and every rule and state can be checked before the scene exists.

### 2.10 Applying the evolution (`EVL_applyEvolution(entity, stats, para, target)`)

With `gains` = `stat_gains[target]`, `new` = `gains.targetDigimon`, `oldLevel` = the partner's level, `level` = the target's level:
1. **Stats:**
   - **Scaled** if the target is Devimon (6), Numemon (0xB), Sukamon (0x27) or Nanimon (0x35), or the partner is Sukamon, or `level` < 3: `EVL_scaleBaseStats(gains.brains)`:
     - nothing if `HAS_USED_EVOITEM`;
     - the partner not Sukamon: each base stat × `brains` / 10;
     - the partner Sukamon: each = `backup + (stat − backup / 2) / 2` with the `suka_backup_*` values, and `virus_bar` = 0;
     - then the clamp, and the current HP / MP cut to the new maximums.
   - **Otherwise**, if no item was used: each stat `s` with gain `g`: `s + g / 10` if `s` ≥ `g`, else `(g + s) / 2`; then the clamp (HP, MP ≤ 9999; the others ≤ 999). When **no** script runs (`IS_SCRIPT_PAUSED` = 1, so not the script evolutions): a new Champion gives `addTamerLevel(20, 1)`, a new Ultimate `addTamerLevel(100, 1)` (`Clock.add_tamer_level`).
2. **Care:** weight = `raise_data[new].default_weight`; care mistakes and battles = 0. An Ultimate without an item: `remaining_lifetime` + 96.
3. **The new technique:** the element block of `new`'s first element (`special[0]`): ids from `base` to `base + 8` **inclusive** (`base` by element: 0 → 0, 1 → 40, 2 → 8, 3 → 32, 4 → 16, 5 → 24, 6 → 49). Among `new`'s 16 move slots, the moves in that range are the candidates, in slot order. The best starts as the first candidate and is replaced by any candidate with a lower, non-zero power. It is learnt (`learnMove`).
   - The range is 9 ids, so it includes the first technique of the next block (open point §6).
   - Equipped: slot 0 = the best's slot (`0x2E + i`); slots 1 and 2 empty; below Rookie, slot 0 = the first slot (`0x2E`). Slot 3 = the last slot holding a finisher, else empty.
4. **The partner:** the old model is removed; the new Digimon is set up at the same position and rotation (`initializeEvolvedPartner`): animation 0, `condition` = 0, the sleep times (`setSleepTimes`) and the care reset (`resetPartnerPara`) for `new`, the immortal hour cleared, the voice bank 4. `new` is marked raised (trigger 0x200 + `new`).
5. If the level changed: `evo_timer` = 0.

`partner.digimon` becomes `new`. `HAS_USED_EVOITEM` isn't cleared (§2.5).

## 3. Godot design

### 3.1 Logic

- **`Evolution`** (`scripts/systems/evolution.gd`, `RefCounted`, tested headless), with `GameState`, `GameData`, `Care`, `Clock`, `Rng`:
  - `fresh_target(id)`, `in_training_target(id)`, `rookie_target(id)`, `champion_target(id)`, `requirement_score(current, target, best)`, `mastered_moves()`;
  - `special_evolution(mode) -> int` (§2.3; it starts state 13 itself, as the C);
  - `hourly_check()` (§2.1, called by `Care` at its marked point), `item_evolution(item)` (§2.5);
  - `apply_evolution(target)` (§2.10): the state changes and the new technique; it returns the new Digimon for the field to swap the model;
  - `scale_base_stats(pct)`, `clamp_base_stats()`;
  - `used_item` (`HAS_USED_EVOITEM`): a field of the running game, false at start, never saved.
- **`Care`:** its marked lines call `Evolution` (the hourly check, the virus bar). `reset_partner_para` and `set_sleep_times` exist and are used by `apply_evolution`.
- **`GameState`:** `set_raised(id)` / `is_raised(id)` (trigger 0x200 + id, ids < 0x3F), used by the Player screen's chart too.

### 3.2 The field

- **`Partner.STATE_EVOLVING`** (13) with `tick_evolving()` (§2.7), and its hooks: mode 2 at the end of waking (`partner.gd:227`), mode 3 after praise / scold (`:236`).
- **`EvolutionScene`** (`scripts/field/evolution_scene.gd`, a node of the field like `CloudFX`, created by `CareHost` or its own host): `start(target)`, `tick() -> int` (the timer, −1 at the end). 5f-1 is the stand-in of §2.9; 5f-2 replaces its middle with the sequence. It swaps the model with `Partner.load_digimon(new)` at the apply point, keeping position and rotation, and loads the new voice bank and the evolution sound set through `Sound`.
- **The script:** `CALL_DIGIMON_ROUTINE` 2 and 10 in `ScriptInterpreter` (their pstat reads, partner state 13, the sync bit).
- **The items:** `ItemUse._handle_evo_items` stops reporting "unported" and calls `Evolution.item_evolution`.
- The tamer's state 6 exists (`Tamer.STATE_STILL`).

### 3.3 Data (data porter, one new table: `evolution/rules.json`)

The literal ids and thresholds of §2 become rule records (`specs/content.md` §4), checked against the C text as the converter already does:
- `hours`: per level the `evo_timer` threshold (Fresh 6, In-Training 24, Rookie 72, Champion 144) and the selection kind (`fixed`, `best_score`, `best_average`);
- `fresh_targets`: per Fresh its fixed target (checked equal to its `paths.to`);
- `fallback`: Rookie, `evo_timer` ≥ 96 → Numemon;
- `virus`: bar ≥ 16 → Sukamon, the backup value 5;
- `scaled_targets`: Devimon, Numemon, Sukamon, Nanimon (plus the code rules "from the virus target" and "level < 3");
- `special`: the rules of §2.3 in C order, each `{mode, chance, from [ids] or level, conditions {discipline, happiness, tiredness, battles_at_least, defense_at_least, evo_timer, evo_timer_at_least, map, nanimon_trigger}, target}`;
- `technique_blocks`: per element its `base` and the inclusive `+ 8` (from `evl.c:1418`);
- `item_targets_fixed` stays in `item_targets` (already there).

`GameData.evolution_rules()`. The logic reads the records; it never names Numemon, Sukamon or the element bases. A mod can add special rules or change the thresholds.

### 3.4 What stays code

The order of the checks, the score's four points and the raised adjustment, the averaging quirk, the stat formulas, the 9999 / 999 clamps, the item flag's lifetime, state 13's sub-states, the loading timings (55 + 55 frames).

## 4. Tests (`tests/test_evolution.gd`)

- **Selection** (set stats and care, fixed data):
  - the Fresh targets and `evo_timer` reset; a mod's Fresh → −1;
  - In-Training: best score ≥ 3, the tie;
  - Rookie / Champion: the averages, the quirk (a losing candidate's sums carried into the next), the 0 average;
  - the Numemon fallback at 96, not before;
  - the score: each point, flags 0x10 / 0x01, the Rookie highest-stat rule with ties (last wins), −1 stats, the bonus fields, the raised adjustment both ways.
- **Special:** each rule with its roll, the overwrite order, the tamer-state gate, the Nanimon trigger cleared.
- **The hourly check:** the gates (advanced, partner 1, tamer 0), the thresholds per level, Champion at 360, the virus bar (backup, pstat 5, bar 0), state 13 started.
- **Items:** the level check, 0x7D–0x7F without it, the flag, the item removed; the flag kept for the next evolution.
- **Apply:** the scaled targets and level < 3, the item flag, the Sukamon backup formula and `virus_bar`; the gain formula both branches and the clamps; current HP / MP; the tamer level during a script; weight, mistakes, battles, Ultimate lifetime; the technique block (lowest non-zero power, the 9th id, below Rookie, the finisher slot); `evo_timer` only on a level change; raised.
- **State 13** with a stub scene: sub-states, closeness, the end (time, sync bit or the tamer freed).
- **Script routines 2 / 10** and the stand-in scene's timings; the Factorial Town remodel (script 156) and the Costume House (139) run end to end with a stub scene.
- **Data porter:** `evolution/rules` records and checks.

VERIFY gets "Evolution": with the debugger, set `evo_timer` and stats, wait for the hour, see the partner evolve; an evolution item; Sukamon from the virus bar; the Factorial Town remodel with a Mamemon.

## 5. Order of work

1. Data porter `evolution/rules` + `GameData.evolution_rules()`.
2. `Evolution` and its tests; `GameState` raised helpers.
3. The hooks: `Care`, the partner's mode 2 / 3, state 13, the stand-in scene, the script routines, the items.
4. VERIFY, PLANS. Then 5f-2.

## 6. Open points

- **`HAS_USED_EVOITEM` for the whole session** (§2.5): faithful, but it looks like a bug of the original (no gains for every later evolution). The port keeps it; the user may want a fix later as an option.
- **The technique block's 9th id** (`moveBase + 8` inclusive) reaches the next element's first technique. It only matters if a Digimon has that move in its list; the port keeps the C.
- **Map 1** for Kunemon: `dw1:mayo02`, Kunemon's Bed (resolved).
- **The evolution chart's first partner** (I-16) is the new game's job (4e), not evolution's.
- **Battles** stay 0 until 5d, so battle-based bonuses and Ninjamon can't happen yet.
- **The debugger** needs a way to set `evo_timer`, stats and the virus bar quickly (the State tab has the stats; the care panel shows `evo_timer`). 5f-1 adds what's missing.

## As built (5f-1, 2026-10-26)

- **Data:** `evolution/rules.json` (data porter, 25/25 checks): keyed rule records (`hours`, `fresh_target`, `fallback`, `virus`, `scaled_target`, `special` in C order, `technique_block`), each checked against the C text; `GameData.evolution_rules(rule)`. Special conditions: `discipline` / `happiness` / `tiredness` / `level` / `evo_timer` (equal), `battles_at_least` / `defense_at_least` / `evo_timer_at_least`, `map {id}`, `nanimon_trigger`.
- **`Evolution`** (`scripts/systems/evolution.gd`) as §3.1. The selection reads the mapped requirement fields (null = −1 of the C). `_best_average` keeps the quirk; a candidate naming no stat (never in the data) keeps the sum instead of dividing by 0. The `best_average` hours rule runs `rookie_target`, whose fallback is looked up by the partner's level, so the Champion has none. Mastered techniques = the learned list's size (one bit per learned technique id, the pairs included).
- **Care:** `nanimon_trigger` (set or cleared by a scold, as `handlePraiseScold`; `handle_praise_scold` no longer returns it), `evolution` (the hourly check at the end of `tick_conditions`).
- **GameState:** `set_raised` / `is_raised` (`TRIGGER_RAISED` 0x200, `RAISED_IDS` 0x3F); the Player screen uses them.
- **Partner:** `STATE_EVOLVING` (13), `tick_evolving`, `evolution_scene`; `_special_evolution` at the end of waking (mode 2) and of praise / scold (mode 3). Sub-state 0 doesn't close menus: the partner isn't ticked while the △ menu is open, and an item starts the evolution after the menu closed. Without a scene the evolution applies at once.
- **`EvolutionScene`** (`scripts/field/evolution_scene.gd`, a child of `CareHost`, which also creates `Evolution`): the loading part (57 + 56 frames), the evolution sound set (18) and the new voice bank, `stopBGM`; then the stand-in: `apply_evolution`, `Partner.load_digimon` at the same place, animation 0xB; at its end the map's sound set and `force_update_bgm`, timer −1.
- **Script:** `CALL_DIGIMON_ROUTINE` 2 / 10 (script values 5 / 0xFE). The Factorial Town remodel doesn't wait on the sync bit: it waits 570 frames (`DELAY`), long enough for the stand-in and the real sequence.
- **Items:** `ItemUse._handle_evo_items` → `Evolution.item_evolution`; `ItemUse.is_ported` and the inventory's "not ported" message are gone.
- **Debugger:** the care panel (`C`) has `evo+12` and `virus+4`.
- **Tests:** `tests/test_evolution.gd` (101 checks): selection with stubbed requirement / path records, the score points and the raised adjustment, the special rules with seeded rolls, the hourly check and Care's call, items, apply (gains, clamps, scaled, Sukamon, item flag, lifetime, tamer level, technique), state 13 with a stub scene, the scene's loading timings with Agumon's model, routines 2 / 10, and the remodel (script 156) end to end (seeded: Mamemon → MetalMamemon). Not run end to end: the Costume House (script 139), which uses routine 10 the same way.
