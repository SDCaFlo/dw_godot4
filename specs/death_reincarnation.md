# Death, lives and reincarnation

Port spec of the partner's lives, the life-loss scene (`MURD`), the death and rebirth scene (`DOOA`), the egg panel (`DOO2`) and the reincarnation: `CALL_DIGIMON_ROUTINE` 3, 4, 7, 9, 10; builtins 29 and 47; MAPHEAD section `0x4DE`; script 212 sections 71, 72, 73.

Status (2026-10-30): ported, with stand-in visuals for DOOA's shards (§9). First pass 2026-10-27 (`f558e5f` … `3249259`), reworked after review (`PLANS.md` step 6, R1–R13).

Source references:
- `src/murd/murd.c`: `MURD_tick` (:760), `MURD_tickScene` (:189), the lives box (:418–:470, :690–:753), the iris (`MURD_renderIris`).
- `src/dooa/dooa.c`: `DOOA_tick` (:1700), `DOOA_tickDissolve` (:310), `DOOA_getSequenceState` (:1748), `DOOA_tickRebirth` (:1003), `REINCARNATE_BABY_TYPE` (:209), `DOOA_SPARKLE_BONE_IDS` (:291).
- `src/doo2/doo2.c`: `DOO2_openEggBox` (:721), `DOO2_tickEggInput` (:739).
- `src/main/partner.c`: `callDigimonRoutine` (:1139), `partnerTickDying` (:640), `partnerTickDying2` (:796), `setSomeDyingState` (:1120).
- `src/main/tamer.c`: `tamerTickSicknessLostLife` (:1699), `tamerTickBattleLostLife` (:1734).
- `src/main/evolution.c`: `reincarnatePartner` (:1054); `src/main/partner_impl.c`: `initializeReincarnatedPartner` (:758), `setReincarnateStats` (:810), `tickSicknessMechanics` (:1907), `tickDeathCondition` (:1917).
- `src/main/script_interp.c`: `START_BATTLE`'s loss (:1919), `WAIT_FOR_ENTITY 0xD5` (:1389), builtins 29 / 47 (:483, :493, :1677, :1765); `src/main/script_common.c`: `lostAllLives` (:2456).
- `src/main/map.c`: `setDeathMap`, `changeToDeathMap` (:5400–:5423).

---

## 1. Life loss triggers

The partner has `lives` (3). Section `0x4DE` of MAPHEAD (script 0) runs when:

1. **A battle is lost** (`START_BATTLE`, outcome -1): `handleItemLoss`, `lives -= 1`, `remainingLifetime = 0` if no life is left, and the script jumps to script 0 section `0x4DE` (`ScriptInterpreter._after_battle`).
2. **12 hours sick** (`tickSicknessMechanics`): with partner state ≠ 8, tamer state 0, lifetime ≠ 0 and `IS_SCRIPT_PAUSED == 1`: script value 0xFF = 0, `lives -= 1`, `callScriptSection(0, 0x4DE, 0)`, sickness timer 0 (`Care.tick_sickness_mechanics` → `script_requested` → `CareHost` calls the interpreter).
3. **Old age** (`tickDeathCondition`): lifetime ≤ 0 outside the immortal hour, partner state ≠ 8, tamer state 0, the script paused: `IS_NATURAL_DEATH = 1`, value 0xFF = 0, section `0x4DE`.

Care reads `IS_SCRIPT_PAUSED` from the script context (`Care.script_ctx`); `script_running` is only its stand-in without one (the tests).

## 2. Section `0x4DE`

`UNSET_TRIGGER 1`, `SET_TRIGGER 41`, then by the partner's values:

| Case | `SECTION_ON_EXIT` | Routine | C |
|---|---|---|---|
| no life left | 73 | 7 | `tamerSetState(17)`, `partnerSetState(12)`, walk / run animations back to 0 |
| lifetime ≤ 0 | 71 | 3 | `partnerSetState(8)` |
| a life lost | 72 | 9 | `tamerSetState(19)`, `partnerSetState(12)`, animations as 7 |

Then `WAIT_FOR_ENTITY 255` (the sync bit; every routine clears it). `SECTION_ON_EXIT` pushes `{4, section}` on the script stack: the death map's change runs its MAPHEAD section (`changeMap` → `runMapHeadScript`, which replaces section 0x4DE), whose end runs that section of the map's script (212).

Script 212's sections start with `WAIT_FOR_ENTITY 0xD5`: it clears the sync bit and waits for it; the scene sets it when it is over (MURD with lives left; the partner's state 8 after DOOA). The interpreter counts the tamer in 17 / 19 and the partner in 8 / 14 as a scene that sets the bit (`_death_scene_running`), so these waits hold until the scene ends.

Routine 4 (`partnerSetState(14)`) starts the rebirth; routine 10 (`EVOLUTION_TARGET = readPStat(254)`, `partnerSetState(13)`) a death evolution. Routines 2 / 10 only set the target and state 13: the evolution scene applies it (`specs/evolution.md`).

## 3. MURD: a life lost (`MurdScene`)

Started by the tamer's state 17 / 19 (`MURD_tick(partner, 0)`): timer 0, phase 0, the lives; with lives left the death map is chosen now (§5). `MurdScene.tick` is `MURD_tickScene`, one object frame; `timer` is what `MURD_tick(.., 1)` returns, `OVER` (-10) once removed.

| Phase | Frames | What |
|---|---|---|
| 0 | 0–0x23 | the iris closes on the partner (radius `2 × lerp(200, 0, 0, 0x23, t)` px around its middle, location − height / 2); drawn while timer < 0x24 |
| → 1 | 0x23 | background black (`fadeoutCLUT1(0xFF)`), every entity but the partner hidden, the lives box opens (box 3, from the partner's screen point), `stopBGM`, the map layer off |
| 1–2 | to 0x5F | the partner shown; lives left → 3, none → 0x64 (the box shrinks back to the partner) |
| 3 | 0x5F–0x87 | full-screen darkening `lerp(0, 0xA0)` (subtractive, `MURD_renderFullscreenFade`: it darkens, no white flash); at 0x87 the box is removed (static) |
| 4 | | black (0xFF) until box 3 is free |
| 5 | | `changeToDeathMap`; `tamerSetFullState(0x13, 1)`, partner state 11, the tamer shown |
| 6 | to 0x91 | black; then the map layer on |
| 7 | 0x91–0xB9 | darkening `lerp(0xA0, 0)`; then the object is removed |
| 0x64 | | until box 3 is free |
| 0x65 | | removed; `DOOA_tick(partner, .., 0)`: the dissolution, the partner off the map |

The lives box (`MurdBox`, `ETCHI/LIFE.TIM`): backdrop 64 × 24 at (-85, -40); hearts 24 × 24 at x = `i × 0x22 − 11` (34 px apart), y = -40: `lives` full, the lost one (index `lives`) full for 10 frames, blinking every 2 frames until 30, then empty; the rest empty. Not ported: the flat lights MURD sets for the partner.

Tamer states: **17** `tamerTickSicknessLostLife`: sub-state 0 starts MURD; 1 sets the sync bit once MURD and DOOA are both over (DOOA's map change puts him in state 6 first, so with no life left the bit comes from the partner's state 8). **19** `tamerTickBattleLostLife`: the same with MURD only.

## 4. Death evolutions (script 212 section 72)

At 2020 the section rolls `STORE_RANDOM 99` into script value 110:

| Partner | Condition | Roll | Into |
|---|---|---|---|
| Rookies (Agumon, Betamon, Gabumon, Elecmon, Patamon, Kunemon, Biyomon, Palmon) | | < 10 | Bakemon (37) |
| MetalGreymon (12), Megadramon (54) | | < 10 | SkullGreymon (26) |
| Kokatorimon (50) | | < 10 | Phoenixmon (59) |
| Angemon (20) | discipline ≤ 49 | < 50 | Devimon (6) |

A success sets value 254, calls routine 10 (state 13, the evolution scene), waits `DELAY 550` and shows "{name} has digivolved!". Otherwise HP / MP are refilled and the injury and sickness removed, and Jijimon or Centarumon comments. These are script data; the port runs them through the interpreter.

## 5. The death map

`setDeathMap(map, 1)` (`murd.c:781`, `dooa.c:1734`): **ROOM10** (map 0xCD = 205) when trigger 0xDC or 0xD6 is set or prosperity (script value 1) ≥ 50, else **ROOM08** (0xDA = 218); entrance 1 (`DooaScene.choose_death_map`). These ids and triggers are dw1 rules kept as constants (content.md §4: listed here deliberately).

## 6. DOOA: the dissolution (`DooaScene`, `DISSOLVE`)

`DOOA_tick(partner, .., 0)`: frame 0 (lives left: the natural death, which draws its own iris) or 0x23 (no life left: MURD drew it; the partner is off the map); animation 1 with lives left; the death map. `DooaScene.tick` is `DOOA_tickDissolve` (frame + 1 first; animation 0xC at its end goes back to 1):

| Phase | Frames | What |
|---|---|---|
| 0 | 0–0x23 | the iris (0–0x21, drawn while frame < 36); at 0x23: `changeToDeathMap`, `stopBGM`, `loadMapSounds2(0x13)`, `setSomeDyingState` (tamer 6, partner 8 sub-state 2, no camera follow), the partner back at its place, animation 1 (lives left) or 0x2C, the others hidden and kept (`DOOA_setOtherEntitiesVisible(0)`), the map layer off, `DOOA_hideAllButPartner`, the background black |
| 1 | to 0x56 | the partner shown; then it stands at the room's origin facing the tamer, animation 0xC with lives left |
| 2 | 0x69–0xBF | `playSound2(8, 0)` at 0x69, `stopSound` at 0x8C, shard waves 0x69–0x8C; at 0xBF `stopSound`, `playSound(8, 1)` |
| 0x64 | 0xBF–0xD1 | the squash (`DOOA_DISSOLVE_SCALE_CURVE`); at 0xD1 animation 0x21, the partner off the map, `playSound(8, 2)` |
| 0x65 | to 0x135 | the rising flash; then `playSound2(8, 3)` |
| 3 | to 0x17B | the camera; then the egg model is loaded |
| 0x66 | 0x185–0x1B7 | entity 2 shown, the egg fades in (`DOO2_fadeClut`) |
| 4 | | the camera reset, the object removed, frame -1 |

The partner is gone at the end whatever its lives (a natural death too); the background stays black until the rebirth.

Partner state **8** (`partnerTickDying`): sub-state 0: walk animation, the tamer looks at it, no camera follow, `loadMapSounds2(19)`; 1: it faces the tamer and walks; close to him (`getPartnerTamerCloseness > 0`) DOOA starts, the tamer stands (6); 2: once DOOA's frame is -1, every frame: lifetime 360, sickness and injury timers 0, the tamer's position kept, the sync bit set. The C also closes the fishing, the △ menu, the inventory and box 1 (the port's partner doesn't tick while they are open).

## 7. Builtins 29 and 47 (`DeathRoutines`)

- **29** (`DOO2_openEggBox` + `DOO2_tickEggInput`): egg slot 0 in DOOA's sequence, box 3 (168 × 80) with the 4 eggs (`ETCDAT/TAMA`), `stopSound`, `playSound(8, 4)`. → / ← move the slot (`(slot ± 1) % 4`, sound 2), ✕ shrinks the box (sound 3); the routine ends once box 3 is free. The slot is `DooaScene.egg_slot` (`DOOA_REINCARNATION_SEQ.eggSlot`); the field hands the routine node the DOOA scene.
- **47** (`lostAllLives`): set up by `CALL_ROUTINE` (step 0); its tick: step 0 counts the learnt techniques (the C's `hasMove(0..0x39)`: moves of category `technique`), `n = (10 − tamerLevel) × 2 × n`, rounded at 50 / 100; none → the routine ends; else value 0xF4 = n, step 2. Step 2: a random one (`randomLimit` over the pool in id order) is unlearnt, value 0xF3 = it, MAPHEAD `0x4D8` line 7 ("… has been forgotten!"), ✕ → step 3. Step 3: 0xF4 − 1; 0 → the box closes, the routine ends; else step 2.

## 8. DOOA: the rebirth and the reincarnation

Partner state **14** (`partnerTickDying2`): sub-state 0 starts the rebirth (`DOOA_getSequenceState(0, 0)`: with no life left the egg is `rand() % 4`, else the panel's); 1: once it is over: lifetime 360, evo timer 0, sickness and injury 0, the tamer's position kept, the sync bit, script value 0 (`PSTAT_TIME_SPEED`) = 0, sub-state 2. The C also reloads the map's sounds and TFS.

`DOOA_tickRebirth`: 10 `stopSound`, `playSound(8, 5)`; 50, 100 the shards; 132 `playSound(8, 6)`, the baby's model loads; **152** `reincarnatePartner`, the partner at (0, 0, 0), the others back (`DOOA_setOtherEntitiesVisible(1)`), entity 2 and the tamer shown, the partner still hidden, the map layer on; 152–202 the background fades back; **202** the partner shown, animation 0x1C; then 47 frames of sparkles (`playSound(8, 7)` where `DOOA_SPARKLE_BONE_IDS` ≥ 0: 6 times); 262 animation 0xB; its end: frame -1. The baby stays at the room's centre.

`reincarnatePartner` / `initializeReincarnatedPartner` / `setReincarnateStats` (`Evolution.reincarnate(egg)`):
- the egg's Digimon (`systems/babies` `reincarnation_eggs`: 1 Botamon, 15 Punimon, 29 Poyomon, 43 Yuramon), through its `stat_gains` target;
- techniques: slot 0 = `0x2E` (the new Digimon's technique slot 0), the others empty; nothing learnt;
- base stats: the egg record's `base_stats` (the C's literals, read by the data porter) + `stat × tamerLevel / 100` of the dead partner's when `IS_NATURAL_DEATH == 1`; HP / MP full; `IS_NATURAL_DEATH` cleared;
- condition 0, sleep times, missed sleep 0, tiredness sleep timer 0, `resetPartnerPara`; discipline, happiness, `unused3` 50; times sick 0; lifetime 360; age 0; evo timer 0; `EVOLUTION_TARGET = -1`; care mistakes, battles 0; weight = the baby's default; raised count + 1 (max 99); no immortal hour; 3 lives; the Digimon marked raised.

Then script 212 asks about the name (`SET_SELECTION`, builtin 0x20).

## 9. Godot design (as built)

```
scenes/field/hosts/death_host.tscn   DeathHost: wires the scenes, draws them
├─ MurdScene                          scripts/field/death/murd_scene.gd (logic: MURD_tickScene)
└─ DooaScene                          scripts/field/death/dooa_scene.gd (logic: DOOA_tickDissolve, DOOA_tickRebirth)
scenes/field/death/death_iris.tscn    DeathIris + death_iris.gdshader: the iris and the background's darkness (background layer)
scenes/field/death/death_darken.tscn  MURD's full-screen darkening (subtractive, in the HUD after the UI boxes)
scenes/field/death/partner_dissolve.gdshader  the stand-in dissolve
scripts/ui/murd_box.gd, egg_select_box.gd     the UI boxes (box 3)
scripts/script/death_routines.gd              builtins 29, 47 (scenes/script/death_routines.tscn under ScriptHost/Routines)
```

- **Logic like the C:** routines 3 / 4 / 7 / 9 only set the tamer's and the partner's states; those states start MURD / DOOA and wait for them (`Tamer.tick_lost_life`, `Partner.tick_dying`, `Partner.tick_rebirth`), as `EvolutionScene` for state 13. `MurdScene` and `DooaScene` are objects ticked in the field's frame after the script's objects (`DeathHost.tick_objects`); they read and change the entities through references, the map through `change_map` / `map_layer` callables, and report DOOA's phases with `phase_changed`. They run headless with `.new()` (the tests).
- **Presentation:** `DeathHost._process` draws from their state (MURD's and DOOA's render functions): the iris and the background's darkness (`DeathIris` in the background canvas layer, under the 3D world, so the partner stays in front: a stand-in for the C drawing it over the iris), the full-screen darkening, the stand-in dissolve and the egg model (`tmd_files/ETCDAT/TAMA.gltf` at the origin).
- **Modding:** `death_host.tscn` and its children, the iris and darkening scenes and the shaders can be replaced; the routines node is replaceable as every builtin node.
- **Stand-ins** (to port later): DOOA's shards, wireframes and flashes (`DOOA_spawnShardWave`, `DOOA_updateShards`, `EFECreateFlash`), the scale curve, the cutscene camera (`DOOA_updateCutsceneCamera`), the models' CLUT fades, MURD's lights; the C's iris layering (the partner over the iris only once it is larger than the window).

## 10. Tests

- `tests/test_death_reincarnation.gd` (95 checks): the egg records; `reincarnate` (inheritance, the cleared flag, techniques, care values, raised count); builtin 47's steps and rounding; section 0x4DE's three branches; the death evolutions (routine 10's target and state 13, the Digimon untouched, `DELAY` kept); MurdBox; builtin 29 with DOOA's slot; MURD with lives left and with none (frames, map change, states, sounds, sync bit); the natural death (walk, phases in order, sounds, the partner gone); the rebirth (frame 152, 202, sparkles, the end values); Care reading `IS_SCRIPT_PAUSED`.
- `tests/death_scan.tscn`: the three cases in the real field (battle loss, the last life to sickness, the natural death), checking the death map, the iris, no dialogue before the scene ends, the rebirth.
- `tests/exit_scan.tscn`: Toy Town's trap battles reach these scenes (its timeout covers them; script 212's choices take their second answer).
