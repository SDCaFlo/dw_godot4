# Curling (step 4g-K)

Status (2026-11-09): **approved by the user**; C1 in progress. Second minigame of step 4g (`PLANS.md`), after fishing. Its C is the `KAR_REL` overlay (`src/kar/kar.c`, 3186 lines, fully decompiled: no `INCLUDE_ASM`) plus the hooks in `src/main` (`kar.c`, `partner.c:1146`, `tamer.c:484`, `map.c:4093`). The "~17k" in `PLANS.md` counted the overlay's bss files. The code itself is about 2,500 lines.

The C names below are the decomp's (US). Line numbers are for `src/kar/kar.c` unless another file is named. Its globals are `MAIN_D_801352xx`. §3 gives them the names this spec uses.

## 0. How to work on it

- **Reuse the field.** Curling runs inside the normal field frame, on map FRZL17 (Freezeland, map 136). It is one world object (0x1388, `KAR_tickStones` / `KAR_renderScene`) and one tamer state (12, `KAR_tick`). The camera, `UIBoxes`, the text area, the map's overlay sprites (the ring markers), the NPCs and the sound are already there.
- **The state machine ticks once per game frame** (`KAR_tickMatchState`), with the C's states and frame counts. No `await`.
- **Integer maths as in the C.** The stones live in world units with `int16` speeds, `rcos` / `rsin` / `ratan2` on the 4096 circle and `SquareRoot0`. The collisions are iterative pushes (`r++` until the distance reaches 0x97), so the port must keep the C's integer types and its truncating divisions (`PsxMath.div`) or the stones end up elsewhere.
- **Data, not ids** (`specs/content.md` §4). The C loads the overlay by map id (`checkCurlingMap`: `mapId == 136`) and picks the opponent by entity slot (`readPStat(0x7A) + 2`). The port reads "this map has curling" from the data (§4), and the opponent's slot keeps the C's rule because it is a script value, not a record id.
- **World axes.** The C's +z points towards the camera. The port's world is `Vector3(x, y, -z)`, as everywhere in the field (`script_interpreter.gd` `_tick_camera_slot`). The logic keeps the C's axes, and only the view and the world interface flip z.

## 1. The C code

### 1.1 Where it is called

| C | Where | What |
|---|---|---|
| `checkCurlingMap(CURRENT_SCREEN)` | `map.c:4093` (every map load) | map 136: `loadDynamicLibrary(KAR_REL)`. Nothing else |
| `CALL_DIGIMON_ROUTINE 1` | `partner.c:1146`, `callDigimonRoutine` | `KAR_start()`, tamer state 12, partner state 11 (`partnerTickIdle`), `SOME_SCRIPT_SYNC_BIT = 0` |
| tamer state 12 | `tamer.c:483` | `KAR_tick()` every frame |
| `KAR_finishMatch` | `:945` | `SOME_SCRIPT_SYNC_BIT = 1`: the script's `WAIT_FOR_ENTITY` goes on |

**The script** (DG.SCN script 131, map 136, section 0x33, a trigger cell the tamer enters on arrival): if pstat 113 is not 0, `CALL_DIGIMON_ROUTINE 1`, `WAIT_FOR_ENTITY none`, then `WARP_TO` FRZL15 (134, exit 2, section 10) or ROOM20 (235, exit 2, section 11) by trigger 257. Script 206's sections 10 / 11 / 12 read pstat 121 (`0x79`, the result: 0 lost, 1 won, 2 won with ≥ 10 points) for the reward dialogue. Pstat 113 is set to 1 by the Mojyamon (FRZL15, script 129 section 6) and by ROOM20 (script 191 section 6) before they warp the tamer to map 136. Pstat 122 (`0x7A`) chooses the opponent: 0 Penguinmon (NPC slot 2, Digimon 57), 1 MetalMamemon (slot 3, `dw1:npc_metalmamemon`), and FRZL17's two map Digimon are those two. The port already runs these scripts. Only routine 1 is missing (it is reported as unported today, `script_interpreter.gd` `call_digimon_routine`).

### 1.2 The parts of `kar.c`

| Part | Functions | Lines |
|---|---|---|
| Tables | `KAR_D_8005AB80` … `KAR_D_8005B580`, the texts | 251–674 |
| Start, setup | `KAR_start`, `KAR_setupMatch`, `KAR_initializeOrderingTables` | 678–795 |
| Stones (the world object) | `KAR_tickStones`, `KAR_renderScene` | 797–943 |
| End | `KAR_finishMatch` | 945–971 |
| Tamer state 12 | `KAR_tick` (10 calls in a fixed order) | 973–985 |
| HUD | `KAR_renderAimArrow`, `_renderStoneCursor`, `_renderScores`, `_renderPowerMeter`, `_renderReadyPrompt`, `_renderNamePlates`, `_renderSprite` | 987–1213, 2749–2762 |
| Camera and markers | `KAR_handleAimScroll`, `KAR_updateRingMarkers` | 1215–1317 |
| Physics | `KAR_checkStonesStopped`, `_updateCollisions`, `_bounceOffWall`, `_distance`, `_resolveStoneCollision`, `_collidePeggedStone`, `_collideRestingStone`, `_collideMovingStones`, `_computeImpactShare`, `_computeSeparation`, `_getWallZone`, `_findWallContact`, `_reflectOffDiagonal`, `_placeAtContact`, `_rotatePoint` | 1319–1942, 2740–2747 |
| Debug (dead code) | `KAR_debugCollisionStone`, `_debugCollisionPair`: both `return` before doing anything | 1733–1760, 1815–1857 |
| Player input | `KAR_beginAiming`, `_selectPreviousStone`, `_selectNextStone`, `_turnAimLeft`, `_turnAimRight`, `_beginThrow` | 1944–2030 |
| Windows | `KAR_tickYesNoPrompt`, `KAR_tickHintBox`, `_drawHintPagePenguinmon`, `_drawHintPageMetalMamemon` | 2032–2138, 2457–2523 |
| Scoring | `KAR_classifyStoneRings`, `_tickScoreTally`, `_registerThrownStone` | 2140–2304, 2732–2738 |
| Opponent AI | `KAR_chooseOpponentShot`, `_findClearShotAngle`, `_aimAtStoneInRing`, `_setOpponentShot`, `_aimAtRandomStone`, `_aimBankShot`, `_findUnusedStoneOfType`, `_computeThrowPower` | 2306–2730 |
| The match state machine | `KAR_tickMatchState` | 2765–3186 |

## 2. Original behaviour

### 2.1 The stones (`KarStone`, `kar.h`)

Three rows of five stones (`KAR_D_8005B5A0[3]`, each `KarStoneRow`): row 0 is the tamer's, row 1 the opponent's, row 2 the obstacles. Each row has `score` (int8), `thrown` (int8), and two AI fields, `unk2` (int16, the opponent's planned power, or the demo's) and `unk4` (uint16, the opponent's chosen stone). The port names them `plan_power` and `plan_stone`.

Per stone: `state` (int32), `type` (int8: 0 heavy, 1 medium, 2 light, 3 pegged, from the hint texts and the weights), `weight` (int16), `speed` (int16), `angle` (int32, the 4096 circle; 0 = +x, 0x400 = +z), `ring`, `prevRing` (int8), `target` (VECTOR: the last position, see below), `rotation` (SVECTOR), `pos` (VECTOR).

`state`:

| Value | Meaning | Where |
|---|---|---|
| −0x65 | out of play (not drawn) | setup: unused obstacles; `checkStonesStopped` (`:1352`): a stone at rest with `pos.vz ≥ 0xBE`; the thrown stone's copy in row 2, slot 4 (`:2831`) |
| −1 | waiting in the side stack (drawn in the HUD projection) | setup, rows 0–1 |
| 0 | held: follows the thrower each frame (`renderScene :888`) | `beginAiming` |
| 1 | on the ice (sliding or at rest) | setup (obstacles), the throw (`:3022`) |
| 2 | pegged, stuck | a type 3 stone at rest (`tickStones :847`); a pushed pegged stone that stopped (`:844`) |
| 3 | pegged, being pushed: it moves around `target` | `collidePeggedStone` |
| ≥ 100 | blinking off during the tally (`+100` / `−100`); not drawn when ≥ 0x65 | `tickScoreTally :2281` |

**Setup** (`KAR_setupMatch(mode)`, `:686`): `obstacles = rand() % 3`; the selected stone, row and power gauge go to 0. Per row: one `rand()` (unused), `score = thrown = unk2 = unk4 = 0`. Per stone, in order: `n = rand() % 10`, then speed, angle, ring and prevRing go to 0. In mode 0, `type = KAR_D_8005AB8C[n]` = `{3,2,2,1,1,1,0,0,0,0}`. In mode 1 (the demo), `type = min(i, 3)`. Model `type * 3 + {2,1,0}[row]` of `KARRING.TMD`.
- Rows 0–1: `pos = (row ? 0x2BC : −0x2BC, i * 0xAA − 0x50, 0)`, `rotation = (0x96, 0, 0)`, state −1. The first `pos` assignment at `:738` is overwritten at once and has no effect.
- Row 2, `i < obstacles`: `pos = (KAR_D_8005AB98[i] − rand() % 0x13F, 0, −(rand() % 0x3E8 + 0x3E8))` with `KAR_D_8005AB98 = {0x2C1, 0xEB, −0xEB}` (US; JP uses `rand() % 0x5DC − 0x2EE`), rotation 0, state 1, speed 0. Note the C's evaluation order: `pos.vx`'s `rand()` runs before `pos.vz`'s.
- Row 2, the rest: pos 0, state −0x65.
- `weight = {30, 25, 35, 30}[type]` (`MAIN_D_80134A08`). Light (type 2) is the heaviest number: the speed is divided by the weight, so a bigger `weight` means a shorter slide.

**The world object** (`KAR_tickStones`, `:797`), every frame, rows 0–2, stones 0–4:
1. If `state` is not 2 or 3: `target = pos` (the start of this frame's step).
2. In match state 5, the selected stone spins: `rotation.vy += 0x14`. The others get `rotation.vy = 0`.
3. If `state > 0` and `speed ≥ 0`: `move = (int16)(speed / weight)`, `speed = (uint32)(speed * 98) / 100` (stored as int16), and `speed = 0` if `move < 2`.
   - `state < 3`: `pos.vx += move * rcos(angle) / 4096`, `pos.vz += move * rsin(angle) / 4096`.
   - `state == 3`: if `speed > 0`: `step = move / 10`, `angle -= 0x800` (wrapped into 0..0xFFF), `pos = target + step * (rcos, rsin)(angle) / 4096`, and `speed = 0` if `step == 0`. Else: `speed = 0`, state 2. The `angle −= 0x800` flips the direction every frame, so the stone shakes around its peg point. It only moves this way, never slides.
   - `state == 1 && move ≤ 0 && type == 3`: state 2, model `{11,10,9}[row]`, `playSound2(8, 4)`.
4. Then `KAR_updateCollisions()`.

**Drawing** (`KAR_renderScene`, `:860`): rows 0–2 with three skips. Row 1 is skipped when the match state is below 0x10, not 3, and either a hint is showing (`hintPage != 0`) or the state is below 5: the opponent's stack is hidden during the demo and the introduction. In match states < 4, stone `i` is skipped until `timer ≥ i * 0x3C + 0x3C` (the stack builds up one stone a second, §2.6). A held stone (state 0) is placed each frame:
- thrower 0 (the tamer): bone 9's world translation + (0, 0x78, 0), rotation 0;
- thrower 2 (Penguinmon): its `location` − (0x50, 0, 0), with the rotation kept;
- thrower 3 (MetalMamemon): bone 4's translation + (0, 0x78, 0), rotation 0.

`state < 0` stones (the stacks) draw with projection 0x200 and the view `KAR_D_8005B580` (eye (0, 0, −0xCF8), looking at the origin) into the overlay's own 10-deep ordering table, which is drawn on top of the field. The `state < −0x64` ones are skipped. The other stones draw in the field's view at OT shift 2, and the ones with `state ≥ 0x65` are skipped.

### 2.2 Walls (`KAR_bounceOffWall`, `:1468`; `KAR_getWallZone`, `:1859`)

For every stone with `state > 0` and `speed ≠ 0`, the zone of `(int16)pos`:

| Zone | Test (in order) | Bounce |
|---|---|---|
| 6 | `z ≥ 0x465` | only if `target.vz < 0x465`: sound (8, 3), `angle = −angle`, `pos.vz = 2·0x465 − pos.vz` |
| 1 | `z ≥ −0x7D0` and `x < −0x2D4` | `pos.vx = −2·0x2D5 − pos.vx`, `angle = 0x800 − angle` |
| 2 | `z ≥ −0x7D0` and `x ≥ 0x2D5` | `angle = 0x1800 − angle`, `pos.vx = 2·0x2D5 − pos.vx` |
| 3 | `z < −0x7D0` and `z + 2x < −0xDC4` and `x < 0x1AA` | the back-left diagonal: `findWallContact(flag 0)`, `reflectOffDiagonal(0)`, `placeAtContact` |
| 4 | `z < −0x7D0` and `z − 2x < −0xDC4` and `x ≥ 0x1A9` | the back-right diagonal, the same with flag 1 |
| 5 | `z < −0x7D0` and `z < −0x9DC` | `angle = −angle`, `pos.vz = −2·0x9DD − pos.vz` |
| 0 | otherwise | none |

Zones 1–5 play sound (8, 3) first. In 1, 2 and 5, `d` is an int16: `pos -= d * 2`.
- `findWallContact` (`:1888`) walks back from `pos` along `angle + 0x800` in 1-unit steps (`i++`) until `(z + 0xDC5) ± 2x > 0`. Its `t <= 0` loop condition comes from the asm and stays as it is.
- `reflectOffDiagonal(p, dir)` (`:1916`) writes `p[3]`, the word at offset 12, which is `angle`: `angle = 2·ratan2(1, ±2) − ((angle + 0x800) & 0xFFF)`.
- `placeAtContact` (`:1934`) sets `pos = contact + (|target − pos| − |contact − target|)` along the new angle.

### 2.3 Collisions (`KAR_updateCollisions`, `:1362`)

Walls first, every frame and in every match state. Then, **only in match state 0xB**, 11 sub-steps (`step = 0..10`):
- each stone with `state > 0` gets `cur = (target · (10 − step) + pos · step) / 10` (x and z; and in US, `cur.vy = target.vy`);
- for each pair `a < b` (index `row * 5 + slot`, both `state > 0`) with `KAR_distance(cur[a] − cur[b]) < 0x96`, it calls `resolveStoneCollision(stone b, P[b], stone a, P[a])`, where `P = cur` at step 0 and `prev` (the previous sub-step's `cur`) after that;
- `prev = cur`. US (≥ JP_TRIAL): if any pair collided and `step == 10`, `step--`, so the last sub-step repeats until a pass has no contact. `collided` is reset after each step.

`KAR_distance(x, y) = SquareRoot0((uint32)(x·x + y·y))`. The `x*x` products are `long` and the sum is stored in `uint32_t`.

**`resolveStoneCollision(A, a, B, b)`** (`:1541`): sound (8, 1) if `A.speed + B.speed ≥ 0xBB8` (int16 sum), else (8, 2). Then:
- if either stone is pegged (state 2 or 3): `collidePeggedStone(pegged, its point, other, its point)`, with A taken first if both are;
- else if either has `speed ≤ 0`: `collideRestingStone(resting, …, mover, …)`, with A taken first;
- else `collideMovingStones(B, b, A, a)`. The arguments are swapped here.

**`collidePeggedStone(P, a, M, b)`** (`:1569`):
- `ang1 = ratan2(M.target − M.pos) & 0xFFF` (M's travel direction, backwards), `r = ratan2(b − a) & 0xFFF`;
- `da = 2r − ang1`, reduced `% 0x1000` only when `≥ 0x1000`, so it can stay negative;
- `dd = 0x400 − (|r − ang1| % 0x400)`, `r = dd · |M.pos − b| / 0x400`;
- then `M.pos = b + r·(rcos, rsin)(da)/4096` with `r++` until `|M.pos − P.pos| ≥ 0x97`;
- `t = (M.speed >> 1) · dd / 0x400`, `P.speed = t`, `M.speed −= t`;
- `P.angle = ratan2(M.target − b)`, `M.angle = da`, `P.state = 3`, `M.target = b`.

**`collideRestingStone(R, a, M, b)`** (`:1607`):
- if both speeds are 0: `R.pos = a`, `M.pos = b`, and nothing else;
- else `share = computeImpactShare(M, b, a)`, `p1 = computeSeparation(M, b, a)`, `R.pos += p1`, `M.pos −= p1` (x, z);
- then push apart one unit at a time until the distance is ≥ 0x97: if `|p1| ≠ 0`, both move along `ang = ratan2(p1)` from their new places, R forward and M backward; else only M moves, along `ratan2(M.pos − R.pos)`;
- `R.target = a`, `M.target = b`, `M.speed −= share`, `R.speed = share`, `R.angle = ratan2(R.pos − a) & 0xFFF`, `M.angle = ratan2(M.pos − b) & 0xFFF`.

**`collideMovingStones(A, a, B, b)`** (`:1665`):
- `s1 = impactShare(A, a, b)`, `s2 = impactShare(B, b, a)`, `p1 = separation(B, b, a)`, `p2 = separation(A, a, b)`, `delta = p2 − p1`;
- if `|delta| ≠ 0`: `ang = ratan2(delta)`, `B.pos += delta`, `A.pos −= delta`, `A.speed += (int16)(s2 − s1)`, `B.speed += (int16)(s1 − s2)`;
  - then push apart: if `A.speed > B.speed`, A moves from its place along `+ang` (US; JP `−ang`), else B along `+ang`, one unit at a time until ≥ 0x97;
  - `A.target = a`, `B.target = b`, `A.angle = ratan2(A.pos − a)`, `B.angle = ratan2(B.pos − b)`;
- else if `B.speed / A.weight < 5` or `A.speed / B.weight < 5`: `B.speed = 0`, both back to their `target`. Otherwise both go to `a` / `b`.

**`computeImpactShare(S, a, b)`** (`:1762`): `d = ((S.angle & 0xFFF) − (ratan2(b − a) & 0xFFF)) & 0xFFF`. If `d < 0x400` or `d > 0xC00`: `d = 0x1000 − d` when `> 0xC00`, then `0x400 − d % 0x400`, and the result is `d · S.speed / 0x400`. Else 0.

**`computeSeparation(out, S, a, b)`** (`:1784`): `d = |S.angle & 0xFFF − ratan2(b − a) & 0xFFF|` (no wrap). If `d < 0x400` or `d > 0xC00`: `r = (0x400 − d % 0x400) · KAR_distance(S.pos.vz − a.vz, S.pos.vx − a.vx) / 0x400`, then `out = r · (rcos, rsin)(ang) / 4096` with `r++` until `out ≠ 0`. Else `out = 0`. The function is declared `int32_t` but returns nothing: callers ignore the value.

### 2.4 Rings and scoring

Four scoring zones, `KAR_D_8005B438` (the same values are in `KAR_D_8005B460`): offsets `(dx, dz)` added to the stone's position, so the zone centres are at `(−dx, −dz)`:

| Ring | Centre (x, z) | Radius | Points (`MAIN_D_80134A44`) | Map objects (`KAR_D_8005B450`: start, count) |
|---|---|---|---|---|
| 1 GOOD (centre) | (0, −0x6B6) | 0x91 | +2 | 25, 1 |
| 2 blue line | (0, −0x6B6) | 0x177 | +1 | 19, 4 |
| 3 BAD | (0x190, −0x90E) | 0xCD | −2 | 16, 3 |
| 4 GOOD | (−0x190, −0x90E) | 0xCD | +2 | 13, 3 |

The texts confirm the labels: "touches the GOOD mark, two points", "blue line, outside the GOOD mark, one point", "the BAD on bottom right, lose two points". FRZL17's object instances 13–25 are flagged hidden (flag 1) in the map data. They are the lit ring markers.

**`KAR_classifyStoneRings`** (`:2140`, after each throw, from state 0xC): for rows 0–1, `score = 0`, and for each stone `prevRing = ring`, `ring = 0`. A stone with `state > 0` and `pos.vz < −0x564` gets the first zone (1→4) with `distance ≤ radius`: `ring = zone + 1`, `| 0x10` for row 1. The first `KAR_distance` at `:2160` is unused. Then `KAR_registerThrownStone()`: `throwOrder[thrown0 + thrown1] = the selected stone` (`KAR_D_800639C0`, 10 slots), `tallyLast = −1`.

**`KAR_updateRingMarkers`** (`:1248`, each frame, from tamer state 12):
- match state 0xB: `lit = 0`. For each moving stone of rows 0–1 (`state > 0`, `speed > 0`), it sets the bit of the first zone not yet lit that has `distance < radius`, then stops looking for that stone. Then each ring with its bit set gets `flags[ring] = 1`. The flags are a local copy of `MAIN_D_80134A48`, all 0, so they are reset every frame. Then `setMapObjectsFlag(start, count, flag ^ 1)`, so the zones a stone is sliding over light up.
- match state 0xD: the stone being tallied (`throwOrder[tallyIndex]`), if its ring changed and `state < 0x65`, lights its ring.
- other states: all four markers hidden (`flag ^ 1 = 1`).

**`KAR_tickScoreTally`** (`:2181`, match state 0xD). It walks `throwOrder` from the last stone thrown back to the first, showing each stone whose ring changed:
- A confirm press sets `skip`. With `skip` and a sub-state of 1 or 2, the scores are recomputed from every `throwOrder` stone (`state > 0`, ring ≠ 0: `score[player] += points[ring − 1]`), the `≥ 100` states are restored, the timers cleared, and it returns 1.
- If `tallyLast ≠ tallyIndex`, it moves down to the next stone with a ring and sets `tallyLast` to it, sub-state 0. No stone left: `skip = 0`, return 1.
- Sub-state 0: if the stone's ring changed, pan with `tickCameraMoveTo(stone.pos.vx, stone.pos.vz, 5)` until it arrives, then sub-state 1. Else go straight to 1.
- Sub-state 1: `score[player] += points[ring − 1]`, sub-state 2. If the ring changed and is not 0: sound (8, 6) for ring 3 (BAD), else (8, 5).
- Sub-state 2: if the ring changed and is not 0, it blinks. `blink++ ≥ 0xB` toggles the state `±100`, `blink −= 10` and `blinks++`. After 8 toggles (`blinks++ ≥ 7`), it moves to the next stone with sub-state 4. A stone whose ring didn't change moves on at once. Returns 1 when `tallyIndex < 0`.
- Note: a stone that doesn't change ring still adds its points in sub-state 1, because `classifyStoneRings` cleared the score. The tally rebuilds the whole score every turn.

**The result** (`KAR_finishMatch`, `:945`): `score0 > score1`: pstat 0x79 = 2 if `score0 ≥ 0xA`, else 1. Else 0 (a tie loses: "in the case of a tie, I win!").

### 2.5 The opponent (`KAR_chooseOpponentShot`, `:2306`, state 0x11)

`thrower` is the opponent's entity slot (`pstat 0x7A + 2`). The plan is written to row 1: `unk4` = the stone, `unk2` = the power, and the stone's `angle`. Coordinates `(x, z)` below are targets.

**Penguinmon (slot 2):**
1. `a = findClearShotAngle(0, −0x6A4)` (the ring centre). If clear (`≠ −1`), `setOpponentShot(1, a, 0, −0x6A4)`.
2. Else, if the tamer leads (`score0 > score1`): aim at its own stone in ring 4 (`aimAtStoneInRing(1, 0x14)`, ring 4 of row 1), then at a tamer stone in ring 2, then a clear shot at (−0x190, −0x960) with plan row 1, else `aimAtRandomStone()` with power 0x960. Each one that works uses `setOpponentShot(0, a, its x, its z)`, except the third, which uses `(1, a, 0, −0x960)`.
3. Else the same chain without the first step.

**MetalMamemon (slot 3)**, from bone 4's world translation `(px, pz)`:
1. First stone (`thrown1 == 0`): straight at (−0x190, −0x8FC) if that line is clear (`ratan2` equals `findClearShotAngle`, which returns the line's own angle when nothing is in the way), else at (0, −0x6A4) the same way, else at (0, −0x6A4) with `± rand() % 100` (+ on an odd count, − on an even one), plan row 0.
2. Later stones: the first waiting stone of row 1 (`state == −1`). If it is pegged (type 3): `unk4 = i`, and a straight shot at (0, −0x6A4) if clear, else `unk4 = 6`. Any other type: `unk4 = 6`. Note: `unk4 = 6` is set for each waiting stone that isn't pegged until a pegged one breaks the loop.
3. If `unk4 == 6`, it answers the tamer's last stone (`lastStone`, `KAR_D_80063914`, a copy made in state 0xF):
   - type 0–2 in ring 3 or out: aim at (−0x190, −0x8FC);
   - the stone is gone (`state < 0`): the centre with the random offset;
   - else one time in two: (−0x190, −0x8FC) if clear, else straight at the tamer's stone;
   - the other time: `aimBankShot(lastStone, 0x190, −0x8FC)` with power 0x960;
   - type 3: the centre with the random offset.

**Helpers:**
- `findClearShotAngle(x, z)` (`:2525`): it starts at the thrower's `location` (Penguinmon) or bone 4 (MetalMamemon), `ang = ratan2(z − pz, x − px)`, and steps 30 (Penguinmon) or 10 (MetalMamemon) units at a time (each step truncated to int16) while `z < pz`. A stone with `state > 0` within 0x97 makes it return −1 for Penguinmon, or `ratan2(stone − (x, z))` for MetalMamemon. Note that this angle is not the shot's direction. If the path reaches the target's z, it returns `ang`.
- `aimAtStoneInRing(row, key)` (`:2576`): the first stone of the row with `state < 2` and `ring == key`, which writes its x and z and returns `findClearShotAngle` at it. None: −1.
- `setOpponentShot(planRow, angle, x, z)` (`:2600`): the stone is the first unused stone of the types in `KAR_D_8005B418[planRow]` (row 0: 1, 0, 2, 3; row 1: 3, 2, 0, 1) (`findUnusedStoneOfType`: `state == −1` and that type). Then `stone.angle = angle` and `unk2 = computeThrowPower(stone.weight, x, z)`. If no type has a stone, `stone` is uninitialised in the C. That can't happen while a row-1 stone is waiting (the four types cover every stone).
- `aimAtRandomStone()` (`:2624`): if `lastStone.state < 0`, `ratan2(−0xC1C, −0x190)`. Else a random tamer stone with `state == 1` (`rand() % count`), or (0, −0x6A4) if there is none, then `ratan2(pz − 0x578, px − 0x190)`.
- `aimBankShot(stone, x, z)` (`:2663`): the point 150 units behind the stone, away from `(x, z)`, mirrored in the left wall: `cx' = −0x2D5 − (cx + 0x2D5)`. The angle from bone 4 to `(cx', cz)`.
- `computeThrowPower(weight, x, z)` (`:2704`): `dist = KAR_distance(0x190 − x, 0x578 − z)`. Then `acc = 0`, `cur = weight`, `value = cur * 100`, and while `acc < dist`: `acc += cur / weight`, `value = value * 100 / 98`, `cur = value / 100` (all uint32). The result is `cur − 0x258` (Penguinmon) or `− 0x1F4` (MetalMamemon). This is the slide run backwards, so the opponent's power is near exact. It is measured from (0x190, 0x578), the opponent's spot.

### 2.6 The match (`KAR_tickMatchState`, `:2765`)

`thrower` is 0 (the tamer) when `row == 0`, else the opponent's slot. `hint` is `MAIN_D_80135250`: 0 none, ≥ 1 the shown hint's box, −1 just closed. The demo is the explanation round: `hint ≠ 0` drives both sides by the plan.

| State | What | Next |
|---|---|---|
| 0 | `timer = 0`. The tamer at (−0x190, 0x578), the opponent at (0x190, 0x578), both rotation 0 and animation 0; `clearTextArea`, `hint = 0` | 1 |
| 1 | `KAR_tickYesNoPrompt` (§2.7): "Start Game" → 3; "Explain Game" → `clearTextArea`, `KAR_setupMatch(1)` | 3, or 2 |
| 2 | (the demo) `timer += 6` until `≥ 0x169` (61 frames), then `timer = 0` | 4 |
| 3 | the ready prompt has blinked (`readyTimer ≥ 0x30`, §2.8): `timer += 6` until `≥ 0x169`, then `timer = 0` | 5 |
| 4 | (the demo) `hint = 1`; row 0's plan: `unk4 = rand() % 5`, `unk2 = 0x7D0`, that stone's angle `ratan2(−0xC1C, 0x190)` | 5 |
| 5 | choosing a stone (below) | 6 |
| 6 | aiming (below) | 7 |
| 7 | `tickCameraMoveTo(stone.pos.vx, stone.pos.vz, 0x14)` until it arrives (`MAIN_D_80135224 == 1`); `aimTurn = 0` | 8 |
| 8 | power (below) | 9, or back to 6 |
| 9 | the throw animation (tamer 0x25, Penguinmon 0x1E, MetalMamemon 0x20); `stone.speed = power + 0x258`; `timer = 0`; `slideSound = playSound2(8, 0)`; `camPrev = stone.pos` | 0xA |
| 0xA | `timer++ ≥ 3` (4 frames): `timer = 0`, stone state 1, `camPrev = stone.pos` | 0xB |
| 0xB | sliding: `moveCameraByDiff(camPrev, stone.pos)`, `camPrev = stone.pos`. `KAR_checkStonesStopped` moves on when no `state > 0` stone has `speed > 0` | 0xC |
| 0xC | `thunkStopSoundMask(slideSound)`, `classifyStoneRings`, `thrown[row]++`, then each row's `thrown` = the number of its stones with `state ≠ −1` | 0xD |
| 0xD | `tickScoreTally` until it returns 1 | 0xE (demo) or 0xF |
| 0xE | `tickCameraMoveTo(0, −0x6A4, 0xA)` until it arrives | 0xF |
| 0xF | `tickHintBox(3)` until it returns 0 (§2.7), then the turn change (below) | 3 (after the demo) or 0x10 |
| 0x10 | `tickCameraMoveTo(thrower location, 0x14)` until it arrives. Both rows have thrown 5: `hint = 1`, `clearTextArea`, state 0x13, and if `score0 > score1` sound (8, 7), page 8 ("Awh, I lost"), else sound (8, 8), page 7 ("Yeah! I won!"). Else the opponent's turn → 0x11, the tamer's → 5 | 0x11, 5 or 0x13 |
| 0x11 | `chooseOpponentShot`; `hint = 1`, `timer = power = 0`; page 5 if the tamer leads, 6 on a tie, 4 if behind ("You're not that great!" / "The battle is just beginning!" / "Hey you're pretty good!") | 0x13 |
| 0x12 | (unused: no state sets it) `UI_BOX_DATA[0].state == 1` | 0x13 |
| 0x13 | `tickHintBox(page)` until 0: `hint = 0`; page ≥ 7 → `KAR_finishMatch`, else state 5 with `timer = power = 0` | 5 or 0x14 |
| 0x14 | `timer = power = 0`, `KAR_finishMatch` (which returns at once once state is 0x14) | — |

**State 5, choosing a stone.**
- Demo or opponent: `tickHintBox(0)` first; while it returns 1, the frame ends. Then every 16 frames (`timer++ ≥ 0x10`, `timer −= 0xF`): if the selected stone is the plan's (`unk4`), the stone is copied into row 2 slot 4 with state −0x65, then `beginAiming`, `timer = 0`, and `hint = 1` if a hint was on. If the plan's stone is further down, `selectNextStone`.
- The tamer: confirm → `beginAiming`; else up → `selectPreviousStone`; else down → `selectNextStone` (edge presses, `POLLED_INPUT` against `POLLED_INPUT_PREVIOUS`; the `else` chain is US). `aimTurn = 0`.
- `selectPrevious` / `selectNext` move to the nearest stone above / below with `state == −1`.
- `beginAiming` (`:1944`): state 6. Animation 0x23 for the tamer, 0x1C for Penguinmon, none for MetalMamemon. The stone's state becomes 0 (held). A pegged stone shows the plain model (row 0: model 2, row 1: model 1). `aim = −0x400`, and the thrower's `rotation.vy = 0`.

**State 6, aiming.** `aim` is the throw angle (−0x400 = straight up the rink, −z). Left and right turn the thrower and `aim` together: `turnAimLeft(d)` and `turnAimRight(d)` both do `rotation.vy −= d`, `aim += d`. The two functions are identical. Only the sign of `d` differs.
- The tamer: confirm → `beginThrow`. Right (0x2000) while `aim < −0x18F`: `aimTurn` = +1, or +1 more each held frame, then `turnAimLeft(aimTurn)`. Left (0x8000) while `aim ≥ −0x5B6`: `aimTurn` = −1, then −1 more each frame, then `turnAimRight(aimTurn)`. Neither held: `aimTurn = 0`. The turn speeds up while held. The range is −0x5B6 … −0x18F, ±0x227 around straight.
- Demo / opponent (US, `:2898–2931`): while `tickHintBox(1)` returns 1, the pad turns the aim as above, one direction a frame (`if` / `else if`). Holding neither, or a turn past its limit, ends the frame (`break`). **After a turn there is no `break`**: the frame goes on to the plan test below, so it can also turn 0xA, or call `beginThrow` (corrected 2026-11-09 in C3's review). When it returns 0, or after a turn: the aim is within ±0xA of the plan's `stone.angle` → `beginThrow` (and `hint = 1` if on). Else it turns 0xA towards it.
- `beginThrow` (`:2020`): state 7. Animation 0x24 (tamer), 0x1D (Penguinmon) or 0x1F (MetalMamemon).

**State 8, power.** `power += 0x64` each frame. At `≥ 0xBB8` (30 frames): `power = 0`, back to state 6, both throwers to their spots, and the thrower's animation 0. The tamer:
- confirm → state 9, `stone.angle = aim`, `stone.rotation.vy = tamer.rotation.vy`.
- Demo / opponent: while `tickHintBox(2)` returns 1, `power` is capped at the row's own plan `unk2` (the `+= 0x64` comes first, so it sits at the plan). Else when `row1.unk2 ≤ power` → state 9 with `stone.rotation.vy = opponent.rotation.vy`, and `hint = 1` if on. This test reads **row 1's** plan even in the demo, where the plan is row 0's (0x7D0) and row 1's `unk2` is 0 (`setupMatch(1)`). So the demo throws on the frame its hint closes, at `0x7D0 + 0x64`. In a real match the opponent shows no hint (`hint` is 0 from state 0x13), so it throws on the first frame its power reaches its plan. The port keeps both as written.
- In the tamer's branch, `stone.angle = aim`. The opponent's plan angle was set by `setOpponentShot`, and its aim only turned towards it.

**The turn change (end of 0xF).** Both throwers go back to their spots with animation 0. On the tamer's turn, the stone is copied to `lastStone`.
- After the demo (`hint ≠ 0`): `tickCameraMoveTo(thrower location, 0x14)` until it arrives, then `thrower.rotation.vy = 0`, `hint = 0`, state 3, `KAR_setupMatch(0)`, `timer = 0`.
- Else the next row: with equal `thrown` counts, row 1 if both are 5, otherwise row 0 if `score0 < score1`, else row 1 (the leader throws second); with unequal counts, the one with fewer. The selected stone is the row's first with `state == −1`. `timer = power = 0`, state 0x10.

### 2.7 The windows

**The yes / no prompt** (`KAR_tickYesNoPrompt`, `:2032`):
- `hint` counts 0 → 2 over the first two frames. The US has one string, "Start GameExplain Game" (`KAR_D_8005ABB8`), drawn into the text area at y `hint * 13 + 0xDD`. The second string is NULL, and US draws nothing for it (to check: `drawString(NULL)`, §8).
- At `hint == 2`, box 0 opens: `createAnimatedUIBox(0, 0, 2, final (−130, 42, 262, 59), start (75, −5, 10, 10))`, `hint = 3`.
- Box open (state 1): confirm → `removeAnimatedUIBox(0)`. Up or down (US: `else if`) toggles 3 ↔ 4 with `playSound(0, 2)`. US draws `renderString(0, −0x7C, 0x30, 0x52, 0xD, 0, 0xDC, 6, 1)` ("Start Game") and `(0, −0x7C, 0x3D, 0x5C, 0xD, 0x53, 0xDC, 6, 1)` ("Explain Game", from text x 0x53), with the cursor at `(finalX + 6, finalY + 7 + (hint − 3)·13, 0x5E, 0xD, 6)`.
- Once the box has closed (state 0 again), it returns `hint − 2`: 1 start, 2 explain.

**The hint box** (`KAR_tickHintBox(page)`, `:2085`). Returns 0 when no hint is on (`hint == 0`).
- Box 0 closed with `hint == 1`: open it with `final (−130, 42, 262, 59)` and start `(0, 0, 10, 10)` (pages ≥ 4) or `(0x4B, −5, 10, 10)` (pages 0–3); `clearTextArea`, `lineIndex = 0`, return 1. Closed otherwise: return 0.
- Open: draw line `lineIndex` of the page with `KAR_drawHintPage<opponent>(page, lineIndex)`. Each page holds `lines / 4` boxes of 4 lines. Line 0 of each box (the name) is in colour 7, the others in colour 1. Line `n` goes to the text area at y `n·13 + 1`. `lineIndex++` while below `boxes · 4`, so one line is written per frame.
- Confirm: `hint++`, `playSound(0, 3)`. Past the last box: `removeAnimatedUIBox(0)`, `hint = −1`.
- While on: `renderString(0, finalX + 4, finalY + 2, 0xFC, 0x34, 0, (hint − 1)·52, 6, 1)` and `renderUIBox(0)`.
- Pages (`KAR_D_8005B04C`, the same for both, `{0, 0xC, 0x14, 0x18, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C}`): 0 choosing (3 boxes), 1 aiming (2), 2 power (1), 3 the rules (4), 4–6 the mid-match lines (1 each), 7 the opponent wins, 8 the tamer wins.
- The texts are `text/kar/kar.yaml` (`PENGUINMON_DIALOGUE`, `METALMAMEMON_DIALOGUE`), already exported (`data_porter/output/text/kar/kar.json`).

`KAR_finishMatch` sets `setTextColor(1)`.

### 2.8 The HUD (`KAR_tick`'s draw calls)

All of it is drawn with `KAR_renderSprite` (`:2749`): a `POLY_FT4` at `(x, y, w, h)` in screen coordinates centred on (0, 0) of the 320 × 240 screen, UV `(u, v, w, h)` on tpage (640, 0) 4bpp, the given CLUT (x = palette · 16, y 486) and RGB, at OT 10 of the field's table. Every sprite uses RGB (0x80, 0x80, 0x80).
- **The scores** (`KAR_renderScores`): each row's score as two digits, `KAR_D_8005B48C` (16 × 16, CLUT (0x10, 0x1E6)). Ones at x −0x69 (row 0) or 0x68 (row 1), tens at x − 0x10, y −0x3E. The glyph UVs are `KAR_D_8005B4A0` (0–9, and 10 = the minus sign, used as the tens glyph of a negative score). The ones digit is `|score % 10|`.
- **The power gauge** (`KAR_renderPowerMeter`), in match states 8–9: the frame `KAR_D_8005B4CC[1]` (48 × 16 at UV (0, 0x18)) at x −0x32 / 0x32 (row 0 / 1), CLUT x 0x70 / 0x80. Then, for `i = 10 … 1` with `250 · i ≤ power`, a bar `KAR_D_8005B4CC[0]` (16 × 16, UV (0x30, 0x18)) at `x = frameX + 3i − 3`, CLUT x 0x30 for i = 10 and 0x70 for the others. The bars are drawn before the frame.
- **The ready prompt** (`KAR_renderReadyPrompt`), in match state 3: `readyTimer++` capped at 0x30. Drawn on the frames with bit 8 set: `KAR_D_8005B56C` (0x97 × 0xA at UV (0x68, 0x3E), CLUT x 0xB0, at (−0x34, 0)). Other states: `readyTimer = 0`.
- **The name plates** (`KAR_renderNamePlates`), always: `KAR_D_8005B4F4[0..3]`. For MetalMamemon (slot 3), plate 2 becomes `KAR_D_8005B558`.
- **The stone cursor** (`KAR_renderStoneCursor`), in match state 5: `KAR_D_8005B478` (24 × 24, UV (0, 0x28), CLUT x 0x80) at x −0x78 (row 0) or 0x64 (row 1), `y = stone · 30 − 0x2D`.
- **The aim arrow** (`KAR_renderAimArrow`, `:987`), in match states 6–7:
  - `arrowPhase` (`timer`, uint16): `if (timer-- != 0) timer += 0xBF` (`:1017`). It adds 0xBE a frame (mod 0x10000), and a timer at 0 becomes 0xFFFF; it does not count down (corrected 2026-11-09 in C3's review). `arrowGap++ ≥ 0x28` → 0 (`MAIN_D_80135238`).
  - 15 points: `(0, 0, −200·(i + 1))` rotated by the thrower's rotation, plus the selected stone's x and z (y 0). Each is folded back inside x ∈ [−0x2EE, 0x2EE] (int16 reflection, repeated): the dotted line shows the wall bounces.
  - Shade `(timer + i·0xBF/15) mod 0xBF`, RGB `shade + 0x40`.
  - Points 0–13 are 16 × 16 dots, UV (0x18, 0x38) with h −16 (flipped), centred on the projected point.
  - Point 14 is the arrowhead: UV (0x28, 0x28), 16 × 16 when the rotation is 0x800, else 15 × 15. It is rotated in screen space by `−((ratan2(prev − cur) − 0xC00) % 0x1000)` (`KAR_rotatePoint`).
  - CLUT (0x80, 0x1E6), at the projected point's OT depth (`otz`). Dot `arrowGap / 3` is skipped, so a gap runs along the line.
- **The aim scroll** (`KAR_handleAimScroll`), in match state 6 on the tamer's turn: up / down scroll the camera by ∓10 pixels a frame (`moveCameraByOffset`). Left / right scroll it by ∓8 when `|aimTurn| ≥ 10` or a hint is on.

The sprite tables in full:

| Name | C | x, y | CLUT x | u, v | w × h |
|---|---|---|---|---|---|
| stone cursor | `KAR_D_8005B478` | (set) | 0x80 | 0, 0x28 | 0x18 × 0x18 |
| score digit | `KAR_D_8005B48C` | (set) | 0x10 | (glyph) | 0x10 × 0x10 |
| gauge bar | `KAR_D_8005B4CC[0]` | (set), −0x32 | 0x80 (set) | 0x30, 0x18 | 0x10 × 0x10 |
| gauge frame | `KAR_D_8005B4CC[1]` | (set), −0x32 | 0x70 (set) | 0, 0x18 | 0x30 × 0x10 |
| plate 0 | `KAR_D_8005B4F4[0]` | −0x8C, −0x5F | 0x90 | 0x70, 0x18 | 0x20 × 0x20 |
| plate 1 | `KAR_D_8005B4F4[1]` | −0x82, −0x46 | 0x70 | 0x18, 0x38 | 0x30 × 0x20 |
| plate 2 (Penguinmon) | `KAR_D_8005B4F4[2]` | 0x64, −0x5F | 0xA0 | 0x90, 0x18 | 0x20 × 0x20 |
| plate 2 (MetalMamemon) | `KAR_D_8005B558` | 0x64, −0x5F | 0xC0 | 0xB0, 0x18 | 0x20 × 0x20 |
| plate 3 | `KAR_D_8005B4F4[3]` | 0x50, −0x46 | 0x80 | 0x18, 0x38 | 0x30 × 0x20 |
| ready prompt | `KAR_D_8005B56C` | −0x34, 0 | 0xB0 | 0x68, 0x3E | 0x97 × 0x0A |
| digits 0–9, − | `KAR_D_8005B4A0` | — | — | (0x40,0x18) (0x50,0x18) (0x60,0x18) (0x40,0x28) (0x50,0x28) (0x60,0x28) (0x48,0x38) (0x58,0x38) (0x48,0x48) (0x58,0x48), − (0, 0x40) | — |

### 2.9 The camera

- `tickCameraMoveTo(x, z, speed)` (`map.c:5100`): `CAMERA_TARGET = (x, tamer.y, z)`, then `checkCameraMovement(speed)`. The port has it (`script_interpreter.gd` `_tick_camera_slot`, `FieldMap.pan_target` / `check_pan`). Curling uses it at speed 5 (the tally), 0xA (back to the ring), 0x14 (to the stone, to the thrower).
- `moveCameraByDiff(from, to)` (`map.c:5124`): the port has it (`FieldMap.scroll_by(screen_motion)`).
- `moveCameraByOffset(dx, dy)` (`map.c:5168`): camera += d, drawing offset −= d, then the edge clamp. The port has `FieldMap.scroll_pixels`. Its clamp is to check against `cameraIsAtEdge` in C4.
- `uploadMapTileImages` after each camera step streams the background tiles into VRAM. The port draws the whole background: **port-only**, nothing to do.

### 2.10 Sounds

All `playSound2(8, n)`: the map's bank (slot 8; the same formula as `Sound.play_sound(8, n)`).

| n | When |
|---|---|
| 0 | the throw; looped, stopped in state 0xC (`thunkStopSoundMask`) |
| 1 / 2 | a hard (speeds ≥ 0xBB8) / soft collision |
| 3 | a wall |
| 4 | a pegged stone sticks |
| 5 / 6 | the tally: a scoring ring / the BAD ring |
| 7 / 8 | the match ends: the tamer wins / loses |

And `playSound(0, 2)` (the prompt's cursor), `playSound(0, 3)` (a hint box's next page).

### 2.11 Start and end

`KAR_start` (`:778`):
- `SOME_SCRIPT_SYNC_BIT = 0`;
- reads `\ETCDAT\KARRING.TMD` and maps it;
- the tamer's `isOnMap = 1`, match state 0, `KAR_setupMatch(0)`;
- adds object 0x1388 (`KAR_tickStones`, `KAR_renderScene`);
- `opponent = readPStat(0x7A) + 2`.

`KAR_finishMatch` (`:945`):
- state 0x14;
- the opponent, the partner and the tamer face 0x800 (towards the camera), animation 2;
- the sync bit is set, the object is removed, `setTextColor(1)`;
- pstat 0x79 (§2.4).

The tamer stays in state 12 until the script's `WARP_TO` changes the map.

## 3. Constants

Globals (names used here):

| C | Name | C | Name |
|---|---|---|---|
| `MAIN_D_80135244` | match state | `MAIN_D_8013523A` | selected stone |
| `MAIN_D_8013523C` | row (thrower side) | `MAIN_D_8013523E` | power |
| `MAIN_D_80135248` | opponent slot | `MAIN_D_8013524C` | aim |
| `MAIN_D_80135250` | hint | `MAIN_D_80135252` | timer |
| `MAIN_D_80135254` | aimTurn | `MAIN_D_80135256` | tallyIndex |
| `MAIN_D_80135257` | lit rings | `MAIN_D_80134A4F` | tallyLast |
| `MAIN_D_8013522C` | lineIndex | `MAIN_D_8013522D` | skip |
| `MAIN_D_8013522E` | tally sub-state | `MAIN_D_80135230` / `_34` | blinks / blink |
| `MAIN_D_80135238` | arrowGap | `MAIN_D_80135220` | readyTimer |
| `MAIN_D_80135224` | camera arrived | `MAIN_D_80135228` | slideSound |
| `KAR_D_800638F4` / `KAR_D_80063904` | camPrev / camFrom | `KAR_D_80063914` | lastStone |
| `KAR_D_800639C0[10]` | throwOrder | `KAR_D_8005B5A0[3]` | rows |

Every value in §2 has its line there. The tables:

| What | C source | Value | Status |
|---|---|---|---|
| Model per row | `KAR_D_8005AB80`, `:251` | {2, 1, 0}, model `type·3 + id` | data (C1) |
| Type roll | `KAR_D_8005AB8C`, `:253` | {3,2,2,1,1,1,0,0,0,0} | data |
| Obstacle x | `KAR_D_8005AB98`, `:261` | {0x2C1, 0xEB, −0xEB} | data |
| Weights | `MAIN_D_80134A08`, `:268` | {30, 25, 35, 30} | data |
| Prompt boxes | `MAIN_D_80134A10/18/28/30`, `:269–277` | §2.7 | code constants |
| Hint pages | `KAR_D_8005B04C`, `KAR_D_8005B40C`, `:351, :434` | §2.7 | data |
| Points | `MAIN_D_80134A44`, `:441` | {2, 1, −2, 2} | data |
| Pegged models | `MAIN_D_80134A4C`, `:443` | {11, 10, 9} | data |
| Shot plans | `KAR_D_8005B418`, `:446` | {1,0,2,3}, {3,2,0,1} | data |
| Zones | `KAR_D_8005B438` / `B460`, `:453, :471` | §2.4 | data |
| Ring markers | `KAR_D_8005B450`, `:462` | §2.4 | data |
| HUD sprites | `KAR_D_8005B478` … `B56C`, `:480–662` | §2.8 | data |
| Stack view | `KAR_D_8005B580`, `:664` | eye (0, 0, −0xCF8), projection 0x200 | data |
| Stack positions | `:741–744` | x ±0x2BC, y `i·0xAA − 0x50`, rot x 0x96 | code constants |
| Friction | `:822` | `speed · 98 / 100`, stop when `move < 2` | code constants |
| Contact distance | `:1438`, `:1596` … | 0x96 (test), 0x97 (push until) | code constants |
| Walls | `:1492–1521`, `:1859–1884` | §2.2 | code constants |
| Spots | `:2776–2780` | tamer (−0x190, 0x578), opponent (0x190, 0x578) | code constants |
| Aim range | `:2937`, `:2945` | −0x5B6 … −0x18F, start −0x400 | code constants |
| Power | `:2971`, `:3013` | +0x64 a frame, 0xBB8 max, speed = power + 0x258 | code constants |
| Stone in hand | `:891–902` | tamer bone 9 + 0x78 y; MetalMamemon bone 4 + 0x78 y; Penguinmon location − 0x50 x | code constants |
| Ring line | `:2157` | `pos.vz < −0x564` | code constant |
| Out of play | `:1352` | `pos.vz ≥ 0xBE` at rest | code constant |
| AI targets | §2.5 | (0, −0x6A4), (∓0x190, −0x8FC), (−0x190, −0x960), (0x190, 0x578), steps 30 / 10, power − 0x258 / − 0x1F4 | code constants |
| Texts | `text/kar/kar.yaml` | §2.7 | text (already exported) |
| Animations | `:1953`, `:2024`, `:3006`, `:955` | tamer 0x23 / 0x24 / 0x25; Penguinmon 0x1C / 0x1D / 0x1E; MetalMamemon — / 0x1F / 0x20; all 0 (wait), 2 (end) | code constants (C4 checks the models have them) |
| The opponent | `KAR_start :793` | slot `pstat 0x7A + 2` | ported (a script value) |
| Result | `KAR_finishMatch :962` | pstat 0x79 = 0 / 1 / 2 (≥ 0xA) | ported |
| Background tiles | `uploadMapTileImages` | — | port-only: the port draws the whole background |

## 4. Data and assets to add (C1)

**Asset porter:**
- **The map's 4bpp image.** FRZL17 has one 4bpp TIM (map image 1: VRAM (640, 0), 64 × 88 units = 256 × 88 pixels, CLUT 16 rows → (i·16, 486), `loadMapImage2`, `overworld.c:394`). The `maps` family keeps its header but writes no PNG. It holds both the HUD sprites and `KARRING.TMD`'s textures (tpage (640, 0), CLUT row 486). It is exported for the curling map only, like the mood faces (§4.1). Other 4bpp users get their own exports when their systems need them.
- **`KARRING.TMD`'s textures.** Its sidecar says `textures_bound: false` ("loaded by the KAR overlay or map"). Bind them to FRZL17's 4bpp image (a `vram_sources` entry naming the map), so the glTF has its textures. Check the 12 objects: models 0–8 are the three rows' plain stones of types 0–2, and 9–11 the pegged ones.

**Data porter** (`systems/curling`, from `kar.c`'s tables, each with its C symbol and a check against the C text):
- the map, by key (`dw1:frzl17`), so the field asks "does this map have curling" (the C's `mapId == 136`), and `pstat_opponent` 0x7A, `pstat_result` 0x79;
- `stone_types` (`weight` by type, the pegged flag for type 3), the type roll, the model ids per row and the pegged models;
- the obstacle x, the zones with points and marker objects, the shot plans, the hint page offsets, the HUD sprites, the digit UVs, the stack view.

### 4.1 The output contract (the C1 tests: `asset_porter/tests/test_curling_assets.py`, `data_porter/tests/test_curling_fields.py`, `tests/test_curling_data.gd`)

**Asset porter, `maps` family** (`CURLING_MAPS = {"FRZL17"}`, like `MOOD_BUBBLE_MAPS`; `_mood_faces` is the model to follow):
- `maps/FRZL17/curling/sheet.png`: u 0–255, v 0–87 of the 4bpp page (640, 0) as the map's images leave VRAM (`_map_vram`), an indexed PNG with the texel indices and palette 0;
- `sheet.p00.png` … `sheet.p15.png`: the same texels through CLUT (n·16, 486), RGBA (`psx.color_to_rgba`: 0x0000 transparent);
- `sheet.json`: `asset_id`, `family`, `format`, `source` (the 4bpp TIM's span in `FRZL17.MAP`), `outputs`, and `vram`: `page {x 640, y 0, bpp 4}`, `uv_rect {u 0, v 0, w 256, h 88}`, `rect {x 640, y 0, w 64, h 88}`, `clut_row 486`, `palettes` (16 lists of 16 raw u16 colours, palette n = CLUT x n·16), the CLUT sources. Also `source_images` and `code_refs` (`overworld.c:394 loadMapImage2` and the `kar.c` sprite users). A check that the rect and the 16 palettes are fully loaded. `asset_porter/specs/map.md` gets a row like the mood faces'.

**Asset porter, `tmd_files`:** `KARRING.TMD`'s texture source becomes FRZL17's VRAM as `loadMap` leaves it (the maps family's `_map_vram` for that map, any TFS palette: page 640 and row 486 don't depend on it), not `MAP` (None). Then `textures_bound: true`, a PNG per (page, CLUT), `missing_texels_in_uv_box == 0`, and `vram_sources` naming `FRZL17.MAP`. The existing "texture pages fully covered" check applies. `asset_porter/specs/tmd.md` is updated.

**Data porter, `systems/curling`** (one record; `data_porter/specs/systems.md` gets a `curling` section like `fishing`'s; `catalog.json` and `PROGRESS.md` updated):
- `map` (reference to `systems/maps`, with `key` `dw1:frzl17`), `pstat_opponent` 0x7A, `opponent_slot_base` 2, `pstat_result` 0x79;
- `stone_types[4]`: `{type, weight, pegged}`; `type_roll[10]`, `row_models[3]`, `pegged_models[3]`, `obstacle_x[3]` (US; other releases in `release_values`);
- `zones[4]`: `{ring, dx, dz, radius, points, marker_start, marker_count}` (`KAR_D_8005B438` + `MAIN_D_80134A44` + `KAR_D_8005B450`), with a check that `KAR_D_8005B460` equals `KAR_D_8005B438`;
- `shot_plans[2][4]`;
- `hints`: `{penguinmon, metalmamemon}`, each `{pages[10], lines[61]}`. A line is a text reference (`string_id` and `text`, as other tables give text) or null;
- `menu`: the US prompt string (`KAR_D_8005ABB8`) as a text reference;
- `sprites`: `stone_cursor`, `score_digit`, `gauge_bar`, `gauge_frame`, `plates[4]`, `plate_metalmamemon`, `ready_prompt`, each `{x, y, clut_x, clut_y, u, v, w, h, r, g, b}` with its C symbol in `source`;
- `digits[11]`: `{u, v}`;
- `stack_view`: `{eye [vpx, vpy, vpz], target [vrx, vry, vrz], rz, projection 0x200}`;
- the code literals the record stands for, checked to still be in the C like `FISH_EVIDENCE`: `if (mapId == 136)` (`src/main/kar.c`), `readPStat(0x7a)`, `writePStat(0x79, 2)`, `GsSetProjection(0x200)`, `stone->weight = weights.weight[stone->type]`, `if (stone->state == 1 && move <= 0 && stone->type == 3)`.

**`GameData`:** `curling()` (the record or {}), `curling_map(map_ref)` (the record when `map_ref`, a key or an id, is its map, else {}), like `fishing()` / `fishing_map()`.

**As built (C1):**
- Asset porter: exported FRZL17 4bpp sheet (`maps/FRZL17/curling/sheet.png`, `sheet.p00.png`..`sheet.p15.png`, `sheet.json`) and bound `ETCDAT/KARRING.TMD` textures to FRZL17 VRAM (`KARRING.gltf`; `TmdFile.map_vram` + `maps.map_vram`).
- Reviewed 2026-11-09 (main session): the path special case in `tmd_files` replaced by the `map_vram` field, the map's image counts read from the executable's table, `curling_map` reduced to the key match, an evidence check added for `stack_view`.
- Data porter: added `systems/curling` table (one record) reading 22 tables from `src/kar/kar.c` and `src/main/kar.c`, with C-text evidence for its literals (the stack view included: `KAR_D_8005B580` is a libgs type the table reader doesn't parse); updated `catalog.json` and `PROGRESS.md`.
- `GameData`: added `curling()` and `curling_map(map_ref)`.

## 5. Godot design

### 5.1 Logic (`scripts/systems/curling/`, headless-testable)

- **`CurlingStones`**: the three rows and the physics (§2.1–2.4): `setup(mode)`, `tick()` (`KAR_tickStones` with the collisions and walls), `classify_rings()`, the tally, `check_stopped()`, `distance()`. Pure integers, `PsxMath` (`ratan2`, `rcos`, `rsin`, `div`, `s16`) plus a `SquareRoot0` added to `PsxMath` (libgte: the integer square root of a uint32), `Rng.rand()`.
- **C2's contract** (`scripts/systems/curling/curling_stones.gd`, checked by `tests/test_curling.gd`):
  - `class_name CurlingStones extends RefCounted`; `const STATE_OUT := -0x65, STATE_WAITING := -1, STATE_HELD := 0, STATE_ICE := 1, STATE_PEGGED := 2, STATE_PUSHED := 3`; `signal sound(id: int)` (`playSound2(8, id)`).
  - Inner classes `Stone` (`state, type, weight, speed, angle, ring, prev_ring, model: int`; `target, rotation, pos: Vector3i`) and `Row` (`score, thrown, plan_power, plan_stone: int`; `stones: Array` of 5). `rows`: 3 `Row`s.
  - `_init(data: Dictionary)` takes `GameData.curling()`. Before `setup`, every stone is `STATE_OUT` with zeros (port-only: the C's bss).
  - `setup(mode)` (`KAR_setupMatch`, its `Rng.rand()` calls in the C's order).
  - `place(row, i, type, state, pos, speed := 0, angle := 0) -> Stone`. Port-only, for C3's copy into row 2 and the tests: it sets the type, the weight and model from the data, the state, `pos` and `target = pos`, speed, angle, rotation 0 and rings 0.
  - `tick(match_state, selected_row := -1, selected_stone := -1)` (`KAR_tickStones` with `KAR_updateCollisions`). `check_stopped() -> bool` (`KAR_checkStonesStopped`: true where the C sets state 0xC; the out-of-play rule always runs). `classify_rings()` (without `KAR_registerThrownStone`, which is C3's). `lit_rings() -> int` (state 0xB's bit mask of `KAR_updateRingMarkers`).
  - `static wall_zone(x, z)`, `static distance(x, y)`, `impact_share(stone, a, b)`, `separation(stone, a, b) -> Vector3i`.
  - `PsxMath.square_root0(v)`: `SquareRoot0`, the floor square root of `v & 0xFFFFFFFF` (Q5).
- **As built (C2)**: `curling_stones.gd` ports the functions of §2.1-2.4 one to one (`Stone` / `Row` fields as in the contract; `impact_share` and `separation` are instance methods, `wall_zone` and `distance` static). `tick()` takes the match state and the selected stone as arguments instead of the C's globals; `check_stopped()` has no state-0xB guard (the caller runs it in 0xB). `KAR_debugCollisionStone` / `KAR_debugCollisionPair` are not ported (they `return` at once). `setup()` leaves `target` alone, as the C does. `PsxMath.square_root0` is an integer floor root (Q5).
- **C3's contract** (checked by `tests/test_curling_match.gd` with a fake world):
  - **`CurlingWorld`** (`curling_world.gd`, `RefCounted`, no-op defaults like `FishingWorld`). Slots are `ENTITY_TABLE` indices: 0 tamer, 1 partner, 2 / 3 the opponent.
    - entities: `location(slot) -> Vector3i`, `set_location_xz(slot, x, z)`, `yaw(slot) -> int`, `set_yaw(slot, v)`, `start_animation(slot, id)`, `bone_translation(slot, bone) -> Vector3i` (`posData[bone].posMatrix.workm.t`);
    - camera: `camera_move_to(x, z, speed) -> int` (`tickCameraMoveTo`: 1 when it arrives), `camera_move_by_diff(from, to)`, `camera_move_by_offset(dx, dy)`;
    - `set_map_objects_flag(start, count, flag)`;
    - UI box 0: `box_state() -> int` (`UI_BOX_DATA[0].state`), `create_box(final: Rect2i, start: Rect2i)`, `remove_box()`;
    - the text area: `clear_text_area()`, `draw_string(text, x, y)`, `set_text_color(c)`, `localize(ref) -> String` (a hint line's text reference; null → "");
    - sounds: `play_sound(bank, id) -> int` (the voice mask; `playSound` and `playSound2`), `stop_sound_mask(mask)`;
    - `read_pstat(i)`, `write_pstat(i, v)`, `set_sync_bit(v)`.
  - **`CurlingMatch`** (`curling_match.gd`): `_init(data, world: CurlingWorld, pad: Pad)`, with `stones: CurlingStones` and `ai: CurlingAi`.
    - Fields are §3's names in snake_case: `state, row, selected, power, aim, hint, timer, aim_turn, opponent, tally_index, tally_last, lit, line_index, skip, tally_sub, blinks, blink, arrow_gap, ready_timer, camera_arrived, slide_sound, cam_prev, cam_from`, plus `last_stone`, `throw_order` (10, null) and `active`.
    - `last_stone` starts as the C's bss: a `Stone` with every field 0 (state 0, not −0x65).
    - `start()` is `KAR_start` without the file read and the tamer's `isOnMap`, which the host does.
    - `tick_stones()` is the world object's tick (`stones.tick` while `active`).
    - `update_held_stone()` is `KAR_renderScene`'s placement of the held stone, called by the host in the render phase.
    - `tamer_tick()` is `KAR_tick`: the ten calls in order. It rebuilds `sprites` (the HUD's `KarSprite`s in draw order: dictionaries `{x, y, clut_x, clut_y, u, v, w, h, r, g, b}`) and `arrow` (the 15 points: `{pos, shade, head, rot, skip}`).
    - `finish()` is `KAR_finishMatch`; it sets `active = false` (`removeObject`).
    - `skipped(row, i) -> bool`: `KAR_renderScene`'s skips (the opponent's stack in the introduction, the stack built up one stone a second, the hidden states), for the view. `update_held_stone` places held stones without them, which gives the C's result: a stone is held only in states 6–0xA, where no skip hits the throwing row.
    - The prompt and the hint box may be helper classes (`CurlingPrompt`, `CurlingHintBox`) or part of the match. A NULL string draws nothing (Q1).
  - **`CurlingAi`** (`curling_ai.gd`): `_init(stones, world, data)` (the record, for the shot plans); `choose(opponent, last_stone)` (`KAR_chooseOpponentShot`: writes row 1's `plan_stone`, `plan_power` and the stone's `angle`); `find_clear_shot_angle(opponent, x, z)`, `aim_at_stone_in_ring(opponent, row, key) -> Vector3i` (angle, x, z; angle −1 when none), `compute_throw_power(opponent, weight, x, z)`, `aim_bank_shot(opponent, stone, x, z)`, `aim_at_random_stone(last_stone)`, `find_unused_stone_of_type(type)`, `set_shot(opponent, plan_row, angle, x, z)`. The thrower's point is Penguinmon's `location` or MetalMamemon's bone 4.
- **As built (C3)**: `curling_world.gd`, `curling_ai.gd`, `curling_match.gd` follow the contract. The prompt and the hint box are methods of `CurlingMatch` (`_tick_yes_no_prompt`, `_tick_hint_box`, `_draw_hint_page`), and their `renderString` / `renderSelectionCursor` / `renderUIBox` calls are left to the view, which reads `hint` and the box state. `CurlingAi._init(stones, world, data)` takes the record for the shot plans. `aim_at_stone_in_ring(opponent, row, key)` returns `Vector3i(angle, x, z)`, with angle −1 when no stone matches. `CurlingMatch.skipped(p, i)` ports `KAR_renderScene`'s skips for the view. `update_held_stone()` places every held stone without those skips (a held stone only exists in states 6–0xA, where they never apply). The arrow rotates by `(0, yaw, 0)`, because the world gives only `rotation.vy`. The stones' `sound` signal goes to `world.play_sound(8, id)`. Two points where the C differs from §2: (1) in US state 6, a pad turn while the hint shows falls through to the plan's test (no `break`, `kar.c:2900–2919`), so the frame does not end, and the port does the same; (2) the arrow's `timer-- != 0 → += 0xBF` adds 0xBE a frame (mod 0x10000) rather than counting down, and the port does the same.
- **`CurlingAi`**: §2.5. It reads the stones and the thrower's point (the world gives bone 4 or the location).
- **`CurlingMatch`**: `KAR_tickMatchState` and the rest of `KAR_tick` in its order (§2.6–2.8), the prompt and the hint box as small logic classes (`CurlingPrompt`, `CurlingHintBox`, like `FishingTextBox`), the ring markers and the HUD state (which sprites, where), which the view draws.
- **The world interface** (`CurlingWorld`, like `FishingWorld`):
  - the entities by slot 0 / 1 / 2 / 3: location, `rotation.vy`, bone world translations (9, 4), `start_animation`;
  - the camera: `move_to(x, z, speed) -> bool`, `move_by_diff(from, to)`, `move_by_offset(dx, dy)`;
  - `set_map_objects_flag(start, count, flag)`;
  - the pad (`polled`, `polled_previous`);
  - the UI box 0 (`create_animated`, `remove_animated`, `state`), the text area (`clear`, `draw_string(text, x, y)`, `set_text_color`);
  - sounds (`play_sound2(8, n) -> mask`, `stop_sound_mask`, `play_sound(0, n)`);
  - pstats (read 0x7A, write 0x79), the sync bit.

### 5.2 Field wiring

- **`CurlingHost`** (`scripts/field/hosts/curling_host.gd`, node `Systems/CurlingHost`): ready on maps with curling data (`checkCurlingMap`). `start()` is `KAR_start`. It ticks the stones in the object order (`Field._frame`, as the C's object 0x1388), and the tamer's state 12 calls `tamer_tick()` (`KAR_tick`).
- **Routine 1:** `script_interpreter.gd` `call_digimon_routine(1)`: `curling.start()`, tamer state 12 (`Tamer.STATE_CURLING`), partner state 11, sync bit 0, `_sync_scene = true`.
- **`FieldCurlingWorld`**: the interface on the field's tamer, partner, `FieldEntities` (slots 2 / 3 = FRZL17's two map Digimon), `FieldMap`, `MapOverlays.set_flag`, `UIBoxes`, `TextArea`, `GameState` and `Sound`.

### 5.3 View (`scenes/field/curling_view.tscn`)

- **The stones on the ice:** `KARRING.TMD`'s objects (lit like the field's models, `PsxLit`), posed from each stone's `pos` / `rotation` (`RotMatrix`, `TransMatrix`), hidden for the skipped states.
- **The side stacks** (`state < 0`): drawn by their own camera (projection 0x200, eye (0, 0, −0xCF8)) over the field, under the HUD sprites: **a second 3D viewport layer** (decided by the user, 2026-11-09) with its own camera set from `stack_view`.
- **The HUD sprites** and **the aim arrow**: 2D on the HUD (`CurlingHud`) from the 4bpp sheet with the CLUT per sprite, under the UI boxes. The arrow's dots project the world points with the field's camera (`FieldMap` projection).
- **The windows:** box 0 on `UIBoxes` and the text area (`docs/ui.md`).

## 6. Steps

| Step | What | Complexity |
|---|---|---|
| C1 | Data and assets (§4): the asset porter's map 4bpp image and `KARRING.TMD`'s textures, the data porter's `systems/curling` with its checks, `GameData.curling()`. | Low · Gemini 3.8 Flash (High) |
| C2 | Logic, stones: `CurlingStones` (setup, slide, walls, collisions, rings, tally, stop) and `PsxMath.square_root0`; `tests/test_curling.gd`, fixed seeds. | Medium · Claude Sonnet 5.5 (Medium): one class, but the integer types and push loops need care |
| C3 | Logic, match: `CurlingMatch`, `CurlingAi`, `CurlingPrompt`, `CurlingHintBox`, `CurlingWorld` (a fake world in the tests); `tests/test_curling_match.gd`. | Hard · Claude Opus 5.5 (Medium): long state machine, the demo's reuse of the opponent paths, state 8's row-1 test |
| C4 | Field wiring: `CurlingHost`, `FieldCurlingWorld`, routine 1, tamer state 12, partner state 11, the opponent slot, the markers, the camera helpers, the sounds; `tests/curling_scan.tscn` up to the prompt. | Medium · Claude Sonnet 5.5 (Medium) |
| C5 | View: the stones, the side stacks' projection, the HUD sprites, the arrow, the windows' contents. | Hard · Claude Opus 5.5 (Medium): rendering, a second projection, CLUT sprites |
| C6 | `tests/curling_scan.tscn`: a whole match (start, five throws each with a fixed seed, the tally, the end, pstat 0x79, the script's warp); `VERIFY.md` "Curling"; `PLANS.md`. | Medium · Claude Sonnet 5.5 (Medium) |

## 7. Tests

The acceptance checks are written from §2 by the main session before each step (`docs/porting_checklist.md` §6).

- **C1:**
  - FRZL17's 4bpp image is 256 × 88 with 16 palettes;
  - `KARRING.TMD` has 12 objects and its textures resolve;
  - `systems/curling`'s values against the C text.
- **C2:**
  - `setup(0)` with a fixed seed: the types from the roll, the weights, rows 0–1 at the stack positions with state −1, 0–2 obstacles with their x / z ranges;
  - the slide: a stone with weight 30 and speed 2000 travels the distance the C's loop gives (worked out by hand from `:821–829`), stops when `move < 2`;
  - each wall zone at points on both sides, and each bounce's new angle and position;
  - the diagonal walls' contact and reflection;
  - a pegged stone sticks (state 2, model swap, sound 4) and shakes when hit (state 3);
  - resting / moving / pegged collisions: the speeds after (`share`), the pair ends ≥ 0x97 apart, the targets;
  - the ring classification at the zone edges (≤ radius in, > radius out), row 1's 0x10 flag, the `−0x564` line;
  - the tally's totals with the negative ring; the out-of-play rule (`vz ≥ 0xBE`);
  - `computeThrowPower` against the slide (a stone thrown at that power + 0x258 from the spot stops near the target).
- **C3:**
  - the state table (§2.6) step by step with a fake world: the prompt's two answers, the demo's 61-frame wait, the stone choice every 16 frames, the aim range and its acceleration, the power gauge's 30 frames and the return to 6, the 4-frame release;
  - the turn order (fewer thrown first, the leader second on equal counts);
  - the end with each result (pstat 0x79 = 0, 1 and 2, a tie = 0), the facing and the sync bit;
  - the AI's choices for each branch of §2.5 with set-up stones;
  - the demo throws at 0x834 on the frame its power hint closes; the opponent at the first power ≥ its plan.
- **C4:**
  - the map gets a `CurlingHost`, other maps don't;
  - routine 1 sets the states and the sync bit;
  - the opponent is slot 2 or 3 by pstat 0x7A;
  - the markers' flags in states 0xB / 0xD;
  - the scan reaches the prompt.
- **C6:** the scan: a whole match to the script's `WARP_TO`.

## 8. Open questions

- **Q1. The US yes / no strings** (answered 2026-11-09). `MAIN_D_80134A20 = {KAR_D_8005ABB8, NULL}` (US), and `drawString` is called with the NULL on the prompt's second frame. US `drawString` (`font.c:1728`) loops `while (*str != '\0')`, so it reads PSX address 0. That is the kernel's reserved low RAM, which holds 0, so nothing is drawn. **port-only:** a NULL string draws nothing (to confirm in an emulator). Both options' pixels come from the first string, cut at text x 0x53.
- **Q2. `checkCameraMovement`'s return.** `tickCameraMoveTo` is declared `void` in `map.c:5100`, but KAR uses its value as "arrived" (`== 1`). On MIPS it is `checkCameraMovement`'s `v0`, left in the register. The port's `check_pan` returns that. Confirm in C4 that it is `1` once (then −1, `map.c:5091`).
- **Q3. The opponent's rotation.** In state 8 the opponent's stone takes `rotation.vy = ENTITY_TABLE[opponent].rotation.vy`, while `turnAim*` turned the opponent's `rotation.vy` by `−d`. Only the model's spin shows it. Nothing to decide: ported as written.
- **Q5. `SquareRoot0`** is libgte's, not in the decomp, like `ratan2` and `rsin` (`PsxMath`'s header, `specs/battle_effects.md` §6). The port uses the floor square root. libgte's table and Newton steps may differ by one in some values, which would move a collision's push-apart by a unit. The C2 tests' values follow this model.
- **Q6. The aim arrow's rotation.** `KAR_renderAimArrow` rotates by the thrower's whole `rotation` (`RotMatrix`, `:1031`). The world interface gives only the yaw, so the port uses (0, yaw, 0). The throwers' x / z rotations are 0 in the field as far as the port knows; to check in C4 against the entities' `rotation`.
- **Q4. Penguinmon's held stone** keeps its rotation (`:891`, no reset). Nothing to decide: ported as written.
