# Fishing (step 4g-F)

Status (2026-11-07): **approved** by the user. First minigame of step 4g (`PLANS.md`). Its C is the `FISH_REL` overlay (`src/fish/fish.c`, 4713 lines, about 3,800 of them code) plus `src/main/fish.c` (144 lines), which hooks it into the field.

The C names below are the decomp's (US). Line numbers are for `src/fish/fish.c` unless another file is named. The tables at the top of `fish.c` (`:343–936`) are the data, and §3 lists every constant.

## 0. How to work on it

- **Reuse the field.** Fishing runs inside the normal field frame: it isn't its own loop like the battles. It is one world object (`FISH_tickFishingWorld` / `FISH_renderFishingWorld`, object 0x3001) and one tamer state (11). The port adds one host and one view to the field. The camera, `UIBoxes`, the text area, the inventory, the sound and the script interpreter are already there.
- **The state machine ticks once per game frame**, with the C's states and frame counts. No `await`.
- **The fish live in the background's pixel space.** The spots, the water outlines and the Seadramon's path are polygons in projected coordinates (pixels from the projection centre, before the drawing offset). They are turned into ground points with `mapToWorldPosition`. The port keeps that: `FieldMap` gives the projected point of a world point and the ground point under a projected point (§5.3).
- **Data, not ids** (`specs/content.md` §4). The C picks the fishing maps by id (`checkFishingMap`: `mapId == 8 || mapId == 6`). The port reads "this map has fishing" from the data (§4).

## 1. The C code

### 1.1 Where it is called

| C | Where | What |
|---|---|---|
| `checkFishingMap(CURRENT_SCREEN)` | `map.c:4092` (every map load), `main.c:3510` (game end, map 0) | `deinitializeFishing`, then on maps 8 / 6: `FISHING_DATA` zeroed, `mapData` = the map's `FISHING_MAP_DATA`, `FISH_init`. Always `startGameTime` |
| `getFishingAvailability` | `game_menu.c:1311` (`addGameMenu`) | 0 no fishing here (no icon), 1 icon disabled (no rod, or no food item), 2 icon enabled |
| menu option 7 | `game_menu.c:2210–2219` | if enabled: `closeTriangleMenu`, `setCameraFollowPlayer`, `initializeFishing` (= `FISH_loadFishing`), tamer state 11, `IS_IN_MENU = 0`. Game time stays stopped (the menu stopped it) |
| tamer state 11 | `tamer.c:480` → `tamerTickFishing` (`main/fish.c:81`) | `FISH_tamerTick`; when it returns 1 (Seadramon landed): `setFishingDisabled`, `triggerSeadramonCutscene(&fish position)` |
| `triggerSeadramonCutscene` | `script_common.c:3057` | `callScriptSection(0, 0x4E4, 0)` (the argument is ignored) |
| `isFishing` | `clock.c:103` | the clock doesn't tick while `rod.fishingState != 0` |
| `setFishingDisabled` / `Enabled` | `partner.c:664, 673` (dying), `:751, 780` (evolution), `:810` (dying 2) | `fishingDisabled`: the world object stops ticking and drawing |
| `deinitializeFishing` | `partner.c:646` (dying, sub-state 0) | `FISH_deinitialize`, `FISHING_DATA_PTR = NULL` |

- `getBestFishingRod` (`main/fish.c:19`): 2 with trigger `TRIGGER_HAVE_AMAZING_ROD`, 1 with `TRIGGER_HAVE_OLD_FISHROD`, else 0.
- `hasFoodItem` (`:32`): an inventory slot holds an item whose `ITEM_PARA.sortingValue == 2`.

### 1.2 The parts of `fish.c`

| Part | Functions | Lines |
|---|---|---|
| Camera scroll | `FISH_panCameraTo`, `_panCameraToTamer`, `_panCameraWithDPad`, `_scrollCameraTo`, `_applySavedCameraScroll`, `_enableCameraControl` | 969–1053, 4673–4709 |
| Screen and water tests | `FISH_isScreenPointVisible`, `_projectPoint`, `_isWithinCastRange`, `_isFishableWater1/2`, `_lerpTableByX/Y` | 1055–1117, 4475–4535 |
| Bait menu (box 3) | `FISH_openBaitMenu`, `_tickBaitMenu`, `_renderBaitMenu`, `_drawBaitMenuRow`, `_closeBaitMenu`, … | 1119–1404 |
| Text box (box 2) | `FISH_showTextBox`, `_tickTextBox`, `_renderTextBox`, `_closeTextBox`, `_scrollViewToTarget` | 1406–1557 |
| Spots | `FISH_randomPointInSpot` | 1559–1610 |
| Sprites | `FISH_drawSprite2D`, `_drawSprite3D` | 1616–1704 |
| Markers (16) | `FISH_spawnMarker`, `_tickMarker(s)`, `_drawMarker(s)`, `_clearMarkers` | 1706–1829 |
| Ripples (16) | `FISH_spawnRipple`, `_tickRipple(s)`, `_drawRipple(s)` | 1831–2001 |
| Tension | `FISH_beginTension`, `_updateTension`, `_drawTensionGauge`, `_resetTension` | 2017–2117 |
| Bait sprite | `FISH_showBaitSprite`, `_moveBaitToRodTip`, `_tickBaitSprite`, `_drawBaitSprite` | 2119–2286 |
| Bobber ("swimmer") | `FISH_bobberCommand`, `_tickBobberPhysics`, `_getRodTipPos` | 2288–2555 |
| Seadramon | `FISH_spawnSeadramon`, `_tickSeadramon`, `_drawSeadramon`, `_pushSeadramonSegment` | 2557–2692 |
| Fish (33) | `FISH_spawnFish`, `_tickFish`, `_drawFish(Sprite)`, `_tickFishPopulation`, `_findFishToBite` | 2694–3096 |
| Hooked fish | `FISH_hookFish`, `_tickHookedFish`, `_tryStrike`, `_drawHookedFish` | 3098–3467 |
| Rod and line | `FISH_updateRodPose`, `_drawRodSegments`, `_drawFishingLine`, `_clipLineToRect` | 3469–3678 |
| The rod's state machine | `FISH_tickRod` | 3688–4418 |
| Object, start, end | `FISH_tickFishingWorld`, `_renderFishingWorld`, `_loadFishing`, `_endFishing`, `_init`, `_deinitialize`, `_tamerTick` | 4420–4671 |

## 2. Original behaviour

### 2.1 The fishing maps

The world object runs on maps 8 (`MAYO10`) and 6 (`MAYO06`) from the map's load, whether the tamer fishes or not: **the fish swim in the water as soon as you enter.**

- **`FISH_tickFishingWorld`**: nothing while `fishingDisabled` or the partner is evolving (`PARTNER_STATE == 0xD`). Otherwise:
  - `FISH_updateRodPose`;
  - if the text box shows, nothing more;
  - else the ripples, the markers, the fish population (§2.2), the hooked fish (§2.6).
- **`FISH_renderFishingWorld`**, with the same two gates: the fish, the hooked fish, the ripples, the markers. Then, only while `rod.displayRod`:
  - the rod's segments and the bobber, when `displaySwimmer`;
  - the line, when `displayLine`;
  - the tension gauge;
  - the bait sprite.

**Per map** (`FISHING_MAP_DATA`, `:895`):

| Field | Map 8 | Map 6 | Use |
|---|---|---|---|
| `scale` | 0x7000 | 0x3800 | bobber and ripple sprite scale |
| `unk8` | 0x46 | 0x23 | the bait sprite's radius; the splash ripples' scale (× 75, × 10) |
| `fishScaleSmall` / `Large` | 0x155 / 0xAA | 0x155 / 0xAA | fish sprite scale per size unit (below / from size 100) |
| `seadramonTime1` / `2` | 9999 / 9999 (never) | 0x6A4 / 0x320 (17:00, 8:00) | the hours Seadramon can come |
| `fishingSpots` | `FISH_D_8007A830` | `FISH_D_8007A950` | 6 spots (one per kind) |
| `isWater` | `FISH_isFishableWater1` | `FISH_isFishableWater2` | the water test |
| `castRange` | 300 | 300 | the bobber is "too close" within this distance of the tamer |
| sprite file | `FISHING.TIM` | `FISHING2.TIM` | the sprites (same layout) |
| Seadramon waypoints | `FISH_D_8007A9CC`, 8 points | the same | |

**A spot** (`FishingSpot`): `unk0` (its share of the population: 30, 25, 18, 14, 8, 5 on both maps), a debug colour (`unk4`, unused), and a polygon of 4–9 points (`points`, `pointCount`).

**The water tests:**
- Map 8 (`FISH_isFishableWater1`, `:4511`): false below `−DRAW_OFFSET_LIMIT_Y_MIN + 0xF0` (the bottom of the background). Otherwise water where `y ≥` the shoreline `FISH_D_8007A890` (16 points), interpolated in x (`FISH_lerpTableByX`; outside the table's x range → 0, which counts as water).
- Map 6 (`FISH_isFishableWater2`, `:4524`): false from `x ≥ 0x1AD`; water when `y < 6`; else water where `x ≤` the shoreline `FISH_D_8007A9B0` (7 points), interpolated in y.

**`FISH_isScreenPointVisible(x, y)`**: the point is inside the background (`−DRAW_OFFSET_LIMIT_X_MAX … −DRAW_OFFSET_LIMIT_X_MIN + 0x140` in x, the same in y with 0xF0). Despite its name, it tests the whole background, not the screen.

**`FISH_randomPointInSpot(spot)`** (`:1559`):
1. Pick 3 different points of the polygon (`customRandom(0, count − 1)`).
2. Clamp them to the background. Note that this writes the clamp into the table itself.
3. Blend: p = lerp(p0, p1, t1), then lerp(p2, p, t2), with t from `customRandom(0, 0x1000)`.
4. Retry from step 1 until the point is in the background and in water.
5. `mapToWorldPosition`: the ground point (y = 0) under that projected point.

### 2.2 The fish (`FISH_tickFishPopulation`, `:2925`; `FISH_tickFish`, `:2709`)

**The pool:** 33 fish (`FishPool.items`). `next` starts at item 1 and the search wraps around (`FISH_allocFish`).

**Each frame:**
- `frameCount++`.
- If `escapeTimer > 0`, it counts down and no fish spawn.
- Else:
  - If fewer than 0x20 fish live, one spawns, in the spot of the kind with the lowest `count[k] × 10000 / (total × share[k])`. Ties go to the last such kind. With no fish yet (`total` = 0) the division is 0 / 0. The asm has no trap there (`div` at `FISH_tickFishPopulation.s:93`, no `break`), and the R3000 gives −1 for a division by zero with a dividend ≥ 0 (psx-spx). So every count is −1 and the first fish is kind 5. Then 4, and so on. The port computes the same values (port the rule, not the CPU: −1 where the divisor is 0).
  - Every 20 game frames (`VSync(-1) / 3 % 20 == 0`), on map 6, if the hour is one of the Seadramon hours, no Seadramon lives and no fish is hooked, Seadramon spawns (§2.3). The minutes don't matter: `now` is computed but not used.
- Then every live fish ticks.

**`FISH_spawnFish(kind)`:**
- `size` = `customRandom(lo, hi)` of its kind;
- `lifetime` = `customRandom(0x258, 0x4B0)` frames;
- state 0, transparency 0;
- position: a random point in the kind's spot;
- heading: towards another random point of the spot.

**Fish states:**

| State | What it does |
|---|---|
| 0 (appear) | Move 0x1E along the heading; transparency + 8. At 0x80: wait `customRandom(moveDelayMin, moveDelayMax)` frames, state 0xA |
| 0xA (idle) | `lifetime − 1`: at 0 → leave. `timeNextMove − 1`: at 0 → new target. Then the checks below |
| 0x14 (swim) | Move `timeThisMove`, then `timeThisMove −= timeThisMove >> 3`. Below 8 → wait again (state 0xA). Then the checks |
| 0x1E (leave) | Move 0x28; transparency − 8; at 0 the fish is gone |

- **New target:** a random point of the spot. Speed = distance / 8, clamped to 0…0x32, then to the fish's size. State 0x14.
- **The checks** in states 0xA and 0x14:
  - **A ripple attracts:** within the attractor's radius of the newest ripple that has one (§2.5), the fish flees: `escapeTimer = 0x1E`, heading away from the ripple (+0x800), state 0x1E.
  - **The bait attracts:** if the rod's bait is the kind's `bait` item and the bobber is 0xC9…0x257 away, the fish swims to the bobber. Speed = distance / 8, clamped to 3…0x32, then to the size.
- **Leave:** heading away from the tamer (+0x800), state 0x1E.

**Drawing** (`FISH_drawFishSprite`, `:2837`): a flat sprite on the water, a dark shadow.
- Rotation (−0x400, heading, 0).
- Subtractive blend (`flags` 6: semi-transparency mode 2, screen − sprite), grey `transparency × 30 / 128`.
- Ordering-table depth + 0x64.
- Big fish (size ≥ 100): sprites `MAIN_D_801349A4[(phase / 3) & 7]`, scale size × `fishScaleLarge`. Small fish: sprites `MAIN_D_801349AC[(phase / 4) & 3]`, scale size × `fishScaleSmall`.
- A hooked fish from state 0x1F on is drawn with the struggle sprites (`MAIN_D_801349B0` / `B8[phase % 6]`) at scale size × 170 / size × 0x155.

### 2.3 Seadramon (kind 6)

- **Spawn** (`:2618`): `size` = `customRandom(300, 300)` = 300; `lifetime` is drawn but never used. It starts at waypoint 0, heads to waypoint 1, state = 1 (the next waypoint).
- **Tick** (`:2642`), while waypoints remain:
  - transparency + 8 (up to 0x80);
  - turn towards the waypoint by at most ±0x80 per frame;
  - speed + 0xA when facing it, − 0xA while turning, clamped 0…0x32;
  - move;
  - within max(speed, 0xA) of the waypoint → next one;
  - then speed = max(distance / 10, 1).
- **Past the last waypoint:** speed + 0xA (up to 0x32), straight on, transparency − 8; at 0 it's gone.
- Every frame (also while hooked) the position and heading are pushed into a 5-entry history (`FISH_SEADRAMON_HISTORY`).
- **Drawing** (`:2568`): the 5 objects of `SEA.TMD` (a flat silhouette in segments). Segment i uses history[i]'s rotation (x + 0x800, z mirrored) and starts where segment i − 1 ends: offsets `FISH_D_8007A56C` = z −0xC8, −0xAF, −0x7D, −0x8C, 0.
- **Bites:** a Seadramon within 0xC9 of the bobber is tested every 8 frames at a 20 % chance, whatever the bait (§2.6).

### 2.4 The bobber (`FishingSwimmer`; `FISH_bobberCommand`, `FISH_tickBobberPhysics`)

**Modes** (`swimmer.mode`):
- 0: left alone;
- 1: at the rod tip (bone 6 of the tamer + `MAIN_D_8013498C` (28, 0, 2) rotated + (0, 17, 0));
- 2–4: flying.

**Flying** (`:2488`):
- Each velocity axis loses `v × 300 >> 12` (at least 1 towards 0); `vy += gravity`.
- With a line length (`dist ≠ 0`), the bobber is pulled back onto a sphere of that radius around the line's start, before and after the move (a pendulum). The pull is added to the velocity the first time.
- If the ground point under it leaves the background, x and z go back and their velocity is 0.
- Then the bait sprite ticks: it hangs 0x64 below the bobber along the line. In state 8, when it goes from above (y < 0) to under the water (y ≥ 0) at a water point: a ripple (kind 0, attracts 0x64, scale `unk8 × 75`).

**Animation states** (`swimmer.state`, ticked by command 0; `timer` counts up):

| State | Entered by | Sprite | Next |
|---|---|---|---|
| 3 | reset | none | |
| 4 | command 4 (at the rod tip) | 1 | |
| 5, 6 | commands 5, 6 (unused) | 1 | |
| 7 | command 7 (lands): ripple −1 (attracts 0x64) | `MAIN_D_8013499C[timer]` = 1, 2, 3, 4, 5, 4, 3, −1 | 8 |
| 8 | floating | 3 | each frame a ½ chance of ±1 drift in x and z; a 1⁄60 chance of state 9 (ripple −2) |
| 9 | bob | `FISH_D_8007A4D8[timer / 3]` = 4, 3, −1 | 8 |
| 10 | command 2 (a nibble): sound 8 / 3, ripple −3 | `FISH_D_8007A4E4[timer]` = 4, 5, 4, 3, −1 | 8 |
| 11 | command 11 (the bait is taken): sound 8 / 4, ripple −4 | `FISH_D_8007A540[timer]` = 4, 5, 6, 7, −1 | 13 (under) |
| 12 | (unreachable: command 12 enters state 11, as command 11 does) | `FISH_D_8007A4F8` | 8 |
| 13 | under the water | none | |
| 14 | command 14 (line cut / hook lost) | `FISH_D_8007A554[timer]` = 7, 6, 5, 4, 3, −1 | 8 |

- Command 12 (a big fish's nibble) runs the same code as command 11 (the `snap12` label, `:2416`): sound 8 / 4, ripple −4, state 0xB. So a big fish's random nibble sinks the bobber (state 13, under) until the fish takes the bait (command 11 again) or escapes (command 7). State 12 and `FISH_D_8007A4F8` are unused. The decomp is byte-matching, so this is the game's behaviour.
- **Drawing** (command 1): `FISH_SPRITES[sprite − 1 + (swimmerType == 1 ? 0x11 : 0x18)]`: the old rod's float or the amazing rod's lure. Scale `mapData.scale`, opaque, depth −10.

### 2.5 Ripples and markers

**Ripples:** a pool of 16 (`FISH_spawnRipple(kind, pos, attract, spread, scale)`).
- The position is ±`spread` random in x and z, with y = 0.
- With `attract ≠ 0` it becomes the pool's attractor, with that radius (§2.2). The attractor is dropped when its ripple ends.
- Each frame the sprite comes from its kind's sequence; −1, or a sprite ≥ 13, frees it:
  - kind 0: `MAIN_D_80134958[frame / 2]` = 1, 2, 3, 4, 5, −1 (`FISH_SPRITES[s − 1]`);
  - kinds −1…−4 use `FISH_SPRITES[s + 4]`:
    - −1: `MAIN_D_80134960[frame]` = 0…5;
    - −2: `MAIN_D_80134968[frame / 3]` = 4, 5;
    - −3: `MAIN_D_8013496C[frame]` = 2…5;
    - −4: `FISH_D_8007A4B4[frame]` = 0, 0, 6…12, 2, 3, 4, 4, 5, 5, 5.
  - Sprite 0 isn't drawn.
- Drawn flat on the water, scale `mapData.scale × scale >> 12`, additive (`flags` 5), depth −10.

**Markers:** a pool of 16, each living 10 frames.
- One shows over every fish that `FISH_findFishToBite` rolls for: sprite 0x2F if it could bite, 0x30 if its chance is 0.
- Drawn as a 2D sprite at the fish's projected point, layer 0x42. They are cleared when a fish is hooked.

### 2.6 The hooked fish (`HookedFish`; `FISH_findFishToBite`, `FISH_hookFish`, `FISH_tickHookedFish`)

**Who bites** (`:3036`), called each frame in state 9 while ✕ is up and the bait is still on:
- No fish may already be hooked.
- For each live fish within 0xC9 of the bobber:
  - **Seadramon:** only when `VSync / 3 % 8 == 0`; chance 20.
  - **A fish:** only when `VSync / 3 % 20 == 0` and in state 0xA or 0x14. The chance is `FISH_BITE_CHANCE[(bait − 0x26) × 6 + kind]` for a bait item 0x26…0x46, else 0.
  - A marker spawns over it.
  - With `customRandom(1, 100) ≤ chance`, this fish bites.
- **Correction to `data_porter/specs/systems.md`:** its third argument is `rod.bait`, the bait's item id (`:4019–4021`). It isn't a depth: the table is the bite chance per **bait item** 0x26…0x46 and fish kind.

**`FISH_hookFish`** (`:3105`):
- The fish leaves the pool, and the markers are cleared.
- It turns to the bobber; state 0xA; `animMode` 0; `strikeTimer` 0.
- Small fish (size < 0x96): `nibbleTime` = `customRandom(0x14, 0x28)`, `catchingTime` = 0x1E. Big fish: `customRandom(0x28, 0x3C)` and 0x3C.
- `powerLeft` = size + 0x96, `powerMax` = `powerLeft` + 0x64, `escaped` 0.

**`FISH_tickHookedFish(mode)`**: nothing while the text box shows. Modes:
- 0x10: grabbed (state 0x28);
- 0xF: escape;
- 0x12: Seadramon reeled in (state 0x64);
- 0x11: gone (inactive);
- 0: tick the state.

| State | What it does |
|---|---|
| 0xA (nibbling) | Until `framesOnState == nibbleTime`, it moves up to 0xA per frame towards the bobber (when ≥ 4 away). Small fish: a 1⁄20 chance per frame of a nibble (command 2), while 20+ frames remain. Big fish: a 1⁄20 chance of command 12. At `nibbleTime`: command 11, `rod.itemTaken = 1`, **the bait item leaves the inventory** (`removeItem(slot's item, 1)`), state 0x14 |
| 0x14 (it has the bait) | Keeps moving to the bobber. After `catchingTime` frames → escape |
| 0x28 (struggling, set by a strike) | A 1⁄11 chance of sound 8 / 5. A 1⁄10 chance of a new heading away from the tamer ±0x384. A ¼ chance of two ripples (attract 0x2BC). It looks up to 30 times for a heading whose point 0x12C ahead is water, else a heading to a random spot point. It moves `timeThisMove / (powerLeft ≤ powerMax / 10 ? 15 : 8)` and **drags the bobber with it**. Then the rest test below |
| 0x32 (pulling) | Every other frame `powerLeft − 1`. A 1⁄11 chance of sound 8 / 6. A ripple each frame. The same heading search. It moves `timeThisMove`, dragging the bobber. Rod not in state 0xB → escape. After `nibbleTime` frames → back to 0x28 |
| 0x5A (escaping) | Move 0x28 away from the tamer; transparency − 8; at 0 it's gone |
| 0x64 (Seadramon, landed) | Moves towards `FISH_REEL_TARGET` (the world origin: the global is never written) at up to 0x32 per frame, a ripple each frame, sound 8 / 6 at a 50 % chance |

**The rest test** in state 0x28 decides when the fish starts to pull (state 0x32):
- With ✕ never pressed (`pressedFrames == −1`, impossible: it's set to 0), or every 3rd frame of a press of 0x3D+ frames, or at a 1⁄10 chance (`customRandom(1, 20) < 3`), it rolls.
- With `customRandom(1, 0x1000) ≤ powerLeft × 0x1000 / powerMax`, it pulls:
  - heading away from the tamer ±0x384;
  - `timeThisMove` = `customRandom(0x14, 0x32)`;
  - `nibbleTime` = `customRandom(9, 0x13)`;
  - state 0x32.
- Otherwise, rod not in state 0xB → escape.

**Escape:** `escaped = 1`; bobber command 7; heading away from the tamer (+0x800); state 0x5A.

After the state, `framesOnState++`, `animPhase++`, `strikeTimer` counts down, and for Seadramon the history is pushed.

**`FISH_tryStrike`** (✕ in rod state 0xA): in state 0x14 within the first half of `catchingTime`, `strikeTimer = 0x14` and grabbed. Otherwise escape.

### 2.7 Tension (`FISH_updateTension`, `:2036`)

- `limit` = 5000 with the old rod (`swimmerType` 1), 10000 with the amazing rod. The level starts at 0.
- Each frame of rod state 0xB the level changes by `FISH_remapClamped(size, 50, 300, a, b)`:
  - ✕ up, fish not pulling: −0xA6;
  - ✕ up, fish pulling (state 0x32): +0x29 … +0x53;
  - ✕ down, fish not pulling: +0x47 … +0x7D;
  - ✕ down, fish pulling: +0xA6 … +0x1F4.
- The level is clamped to ±limit.
- **The colour** (also the line's): white at 0, blending to yellow at +limit/2 and red at +limit; to cyan at −limit/2 and blue at −limit.
- **At −limit:** returns 2, the hook comes out (the fish escapes).
- **At +limit** for `(4 − remap(size, 50, 300, 1, 3)) × 5` frames in a row (15, 10 or 5): returns 1, the line snaps.
- **`FISH_remapClamped(x, x0, x1, y0, y1)`** (`fish_model.c:61`): x clamped to [x0, x1], then `y0 + ((y1 − y0)(x − x0) + (x1 − x0) / 2) / (x1 − x0)`.

**The gauge** (`FISH_drawTensionGauge`):
- frame sprite 31 at (−95, −64) from the screen centre, layer 0xA;
- `remap(level, −limit, limit, 0, 9)` bars of sprite 32 at x + 3i, layer 9, in the tension colour.

### 2.8 The rod (`FISH_tickRod`, `:3688`)

While the text box shows, the rod only pans the camera to the box's target (`FISH_scrollViewToTarget`) and nothing else runs (no `framesOnState`, no bobber).

`FISH_loadFishing` (the menu) starts it:
- the camera stops following and its scroll is saved (`FISH_enableCameraControl`);
- state 2, rod shown;
- the hooked fish escapes;
- `swimmerType` = the best rod. With no rod it falls through to 2 (unreachable: the icon is disabled). Rod 2 also copies a palette row (`MoveImage` 0x1C0, 0x1E4, 0x1C × 8 → 0x1C0, 0x1DC): the amazing rod's colours.

| State | What happens | Leaves to |
|---|---|---|
| 2 | Pan to the tamer (radius 0x10) | 3 when centred |
| 3 | Frame 0: open the bait menu (§2.9). Wait while it shows | cancelled → 0xE. Chosen: `itemSlot`, `bait` = its item, `itemTaken` 0, tamer anim 0x1B → 1 |
| 1 | ← / → turn the tamer 0x40 per frame. When anim 0x1B ends: the bobber shows → **cast** | |
| **cast** | Bobber at the rod tip. If the bait was taken → **give up**. Anim 0x1C, bobber command 4, mode 1, the line shows, the bait sprite at the tip | 0xE96 |
| 0xE96 | Pan to the bobber (radius 0x10, step 0x28 × 0x1E) | 6 when centred |
| 6 | Bait at the tip. ○ held: d-pad pans the camera. ✕: **throw**. △: bait sprite off → 0xE. ← / → turn; pan to the bobber | |
| **throw** | Anim 0x1D; mode 2, velocity 0, line length = the bobber's distance to the line start, gravity 0x1E | 7 |
| 7 | ✕ → **release**; ○ → release with `framesOnState = 0x14` (full power). Pan. When anim 0x1D ends → cast | |
| **release** | Anim 0x1E. `throwPower` = `framesOnState + 5`; mode 3, the bobber from the line start, no line length, gravity 3. Velocity = (0, 0, `remap(throwPower, 0, 0x14, 0x64, old rod ? 0xC8 : 0x190)`) rotated by (0, tamer + 0x800, −0xC8). Sound 8 / 0 | 8 |
| 8 | Pan (○: d-pad). ✕: stop x/z (drop straight down). While above the water (y < 0): △ → cast. Else → **splash** | |
| **splash** | Bait sprite off; y = 0. Not in the background or not water → cast. Sound 8 / 2, the tamer anim's `loopCount = 1`, bobber command 7, mode 0 | 9 |
| 9 | ✕ held: anim 0x20 (on a press, or when it ends); the bobber is pulled towards the rod by the rod tip's forward motion since last frame; with the bait taken, every 20 frames from frame 0x1F a 1000⁄10000 roll **snags** an item (§2.10). ✕ up: anim 0x1F (on a release, or when it ends); with the bait on, a bite test (§2.6) → 0xA. Then: bobber not over water in the background, or within `castRange` → cast. ○: d-pad pans. △ → cast | |
| 0xA | Pan. Fish escaped or gone: "They took my bait!" → splash. ✕: strike: a hit → "Hooked!" → **tension** (state 0xB, `pressedFrames` 0); a miss → "Too late! / They got my bait!" when the bait is taken, else "Too fast! / But I still got my bait!" → splash. △: escape → splash | |
| 0xB | §2.8.1 | |
| 0xD | The catch flies to the rod tip at 0x28 per frame (the bobber with it). When there and the camera is centred (radius 0x20): the catch message (§2.10) → **finish** | |
| **finish** | Anim 0x1C, bobber command 4, mode 1, the line shows, the tamer faces 0 (on both maps), bait sprite at the tip | 0xE |
| 0xE | Pan to the tamer; then `FISH_endFishing` (state 0) | |
| 0x4B0 | Line cut: at frame 0xA, sound 8 / 0xA, "My line got cut! / Pay attention to tension gauge / and be more calm" | 0xE |
| 0x4B1 | Hook lost: at frame 0xA, sound 8 / 0xA, "My hook got lost! / Pay attention…" | splash |
| 0x44C | Snagged: the item flies to the rod tip, sound 8 / 8, the item given (§2.10) | finish |
| 0x11AF | Seadramon: pan to the tamer; when the fish is within 0x32 of the world origin: `catchComplete` | |

**Give up** (cast with the bait taken): with no food item left → 0xE. Else anim 0, bobber off, bait sprite off, line off, mode 0 → state 2 (choose a bait again).

After every state, `framesOnState++` and the bobber ticks (`FISH_tickBobberPhysics`).

#### 2.8.1 Reeling (state 0xB)

- **✕ down:** `pressedFrames` counts up from 0. Anim 0x22 on a press, or when it ends. The bobber is pulled towards the rod by twice the rod tip's forward motion, minus `remap(size, 50, 300, 1, 10)`, halved.
- **✕ up:** `pressedFrames` counts down from 0. Anim 0x21 on a release.
- **Landed:** the bobber's point is on land in the background, or within `castRange + size` of the tamer:
  - Seadramon: state 0x64, → 0x11AF.
  - A fish: it leaves the water; `bait` = kind + 0x3E (the fish's item); sound 8 / 7; the item sprite at the bobber; a ripple (attract 1, scale `unk8 × 10`); mode 0 → 0xD.
- Tension 1 (snap): escape, sound 8 / 9, the line off, command 14 → 0x4B0.
- Tension 2 (hook out): escape, sound 8 / 9, the line stays, command 14 → 0x4B1.
- △: escape → splash. ○: d-pad pans; else pan to the bobber.

### 2.9 The bait menu (box 3) and the text box (box 2)

**Bait menu** (`FISH_openBaitMenu`, `:1318`):
- **Contents:** the inventory slots whose item is food (`sortingValue == 2`), in slot order, 2 per row. With none it wouldn't open (returns 0), but state 3 is only reached with food: the menu icon is disabled without it (`getFishingAvailability`), and a give-up checks `hasFoodItem` first.
- **The box:** animated, colour 0, features 2, or 6 with a scroll bar when there are more than 9 rows. It grows from a 10 × 10 square at the tamer's screen point (bone 1) to (−0x98, −0x68, 0x132, 0xB6).
- **Each cell:**
  - the item icon at (x + 8 or 0x98, y + 0xE + 0x12 row);
  - the name, from the text area (row % 9) × 12, column × 0x60;
  - a "×" glyph (8 × 8 at u 0x80, v 0x9C, CLUT (256, 484));
  - the count (`renderItemAmount`, 2 digits).
- **The cursor:** at (x + 6 + 144 × column, y + 0xD + 18 × row), 0x8E × 0x12.
- **Moving:** ↑ / ↓ move the row and scroll it. ← / → swap the column, wrapping. Each move plays sound 0 / 2. A key held for 11+ frames repeats every frame (`MAIN_D_801351D8` counts frames with the pad unchanged).
- **✕** on a filled cell: chosen (sound 0 / 2). **△:** cancelled (sound 0 / 2). Either closes the box towards its start.

**Text box** (`FISH_showTextBox(l0, l1, l2, l3, target)`, `:1502`):
- The lines are drawn into the text area at rows 0, 12, 24, 36.
- A static box 2, colour 0, features 2, at (−0x82, 0x2A, 0x106, 0x3B).
- The lines render at (x + 5, y + 3 + 13i), with the "next" arrow (`renderUIBox`, `TEXTBOX_OPEN_TIMER`).
- **Closing:** ✕ after 10 frames, or △ at once. It plays sound 0 / 3 and clears the pad for the frame.
- **While it shows:** the camera pans to `target` once per frame (radius 0x10), the world object and the rod stop, and the hooked fish waits.

### 2.10 Catches and snags

**A catch** (state 0xD):
- The message, US: size ≥ 200 → `"Great! Total length %d m %d cm"`; size ≥ 100 → `"Total length %d m %d cm"` (`/ 100`, `% 100`); else `"Total length %d cm"`.
  - The US C divides the ≥ 200 case by **200** (`size / 200`, `size % 200`, `:4279`), so 250 reads "1 m 50 cm". **Port-only fix (the user, 2026-11-07):** the port uses `/ 100` and `% 100` there too, so the length shown is right. The other releases print the right digits as well (`:4233–4276`).
- A new record per kind goes into `FISH_RECORD_SIZE` (not saved, never shown).
- `PARTNER_PARA.fishCaught + 1` (the "100 fish" medal); sound 8 / 8.
- `giveItem(item, 1)`. The box: the item name, the length, "I got one!", plus "It looks sad. Let it go." when the bag is full.

**A snag** (state 9): `r = customRandom(0, 99)` picks the first `FISH_BAIT_CHANCES` entry with `r ≤ threshold`:
- Sm. recovery ≤ 34, Various ≤ 62, Restore ≤ 82, Omni Disk ≤ 92, Auto Pilot ≤ 97, Coral charm ≤ 99.
- Sound 8 / 9, "Huh?! I wonder if something / got stuck? It got stuck!".
- Then state 0x44C gives it: the name, "It got stuck!", or with a full bag "My bag was so full I / could not carry it" (US).

### 2.11 Ending

- **`FISH_endFishing`:**
  - if the rod showed: the saved camera scroll is restored, the camera follows, tamer anim 0, rod off, state 0;
  - the bait menu and the text box close; the tension resets; the bait sprite and the bobber are cleared.
- **`FISH_tamerTick`** after the rod's tick:
  - not fishing (state 0) → tamer state 0, `startGameTime`, returns 0;
  - `catchComplete` (Seadramon) → the hooked fish goes, `FISH_endFishing`, tamer state 0, returns 1. `tamerTickFishing` then disables fishing and calls script section 0x4E4. Game time stays stopped: the script takes over.

### 2.12 The camera (`FISH_panCameraTo(radius, pos, maxDX, maxDY)`, `:969`)

1. Project `pos`. Each axis's offset from the view centre is taken as is when within `max` (0 = always). Otherwise it moves `max` towards the centre, so the camera trails the point by up to (`maxDX`, `maxDY`).
2. The result is clamped to the background.
3. With `radius > 0` the step is cut to `radius` pixels along its direction.
4. `FISH_scrollCameraTo` moves the drawing offset and `MAP_TILE_DATA.camera`. Only while camera control is on (`MAIN_D_801351DC[2]`).

It returns 0 when no move was needed: that is the "centred" test of states 2, 0xE96, 0xD, 0xE and 0x11AF.

`FISH_panCameraWithDPad`: 5 pixels per frame per held direction, clamped. ○ held turns the d-pad into this pan in states 6, 8, 9, 0xB.

### 2.13 The rod model and the line

**`FISH_updateRodPose`** (every frame of the world object, `:3469`):
- The rod base is the tamer's bone 9 (the hand) times a fixed rotation (`MAIN_D_801349C0`, from `toEulerAngles(−6, 0x34, 0x127)` under (0x400, 0x400, 0)), moved by (1, 19, −48).
- Its 5 segments (`FISH_D_8007A594` lengths 0xFC, 0xB9, 0x65, 0x4B, 0) bend towards the bobber.
- Each of segments 1–3 bends by ¼ of the direction to the bobber in the rod's frame. The bend is limited to a length of `(level + limit) × 512 / (2 × limit)` with the gauge showing, else 0x80: the rod bends more as the tension rises.
- `lineStart` = segment 4's end; the previous frame's goes to `lineStartMirror`.

**Drawing:**
- **The rod:** objects 0–3 of `SAO.TMD`, one per segment, only while `displaySwimmer` (from the end of anim 0x1B in state 1 to `FISH_endFishing` or a give-up): no rod during the pan and the bait menu (states 2, 3).
- **The line:** from `lineStart` to the bobber, projected. It is clipped to the screen and drawn as a polyline of `drawLine2P` steps of about 0x40 pixels, in the tension colour (white without a fish).
- **The bait sprite** (`FISH_drawBaitSprite`): the item's icon (tpage (320, 0), CLUT `ITEM_CLUT_DATA`) as a square of radius `unk8 × H / z` at the projected point. Only above the water (y < 0).

### 2.14 Sounds

All from slot 8 (the map's set: both maps load set 13), except the menu clicks:

| Sound | When |
|---|---|
| 8 / 0 | release (the cast) |
| 8 / 2 | splash |
| 8 / 3 | nibble (command 2) |
| 8 / 4 | the bobber goes under (commands 11, 12) |
| 8 / 5 | struggling, 1⁄11 per frame |
| 8 / 6 | pulling, 1⁄11 per frame; Seadramon landed, ½ per frame |
| 8 / 7 | landed |
| 8 / 8 | the item is given |
| 8 / 9 | line cut / hook lost / snag |
| 8 / 0xA | the line-cut / hook-lost message |
| 0 / 2 | bait menu moves, choice, cancel |
| 0 / 3 | text box closes |

## 3. Constants

Every value in §2 is from the line given there. The tables:

| What | C source | Value | Status |
|---|---|---|---|
| Fish kinds | `FISH_KIND_INFO`, `:829` | sizes 50–60, 55–85, 60–100, 70–150, 100–230, 210–300, Seadramon 300; delays 30–60, 30–60, 40–75, 50–90, 60–120, 60–120; bait −1, −1, 0x45, 0x40, 0x44, 0x42; item 62–67 | data (`systems/fishing.kinds`) |
| Bite chances | `FISH_BITE_CHANCE`, `:426` | 33 bait items × 6 kinds | data, rename to per-bait (§2.6) |
| Snags | `FISH_BAIT_CHANCES`, `:365` | §2.10 | data |
| Sprites | `FISH_SPRITES[49]`, `:374` | tpage, CLUT, u0 v0 u1 v1, origin | **to port** (§4) |
| Spots | `FISH_D_8007A830`, `:583`; `FISH_D_8007A950`, `:727` | 6 per map: share, polygon | **to port** (the polygons are C symbols today) |
| Shorelines | `FISH_D_8007A890` (16), `FISH_D_8007A9B0` (7) | the water tests | **to port** |
| Seadramon path | `FISH_D_8007A9CC`, `:812` | 8 points | **to port** |
| Ripple sequences | `MAIN_D_80134958/60/68/6C`, `FISH_D_8007A4B4` | §2.5 | code constants |
| Bobber sequences | `MAIN_D_8013499C`, `FISH_D_8007A4D8/E4/F8`, `FISH_D_8007A540/554` | §2.4 | code constants |
| Fish frames | `MAIN_D_801349A4/AC/B0/B8` | §2.2 | code constants |
| Rod | `FISH_D_8007A594`, `MAIN_D_801349C0/C8`, `MAIN_D_8013497C/84/8C/94` | §2.13, §2.4 | code constants |
| Seadramon segments | `FISH_D_8007A56C` | §2.3 | code constants |
| Gauge position | `MAIN_D_80134974` | (−95, −64) | code constant |
| Pools | `Fish items[33]`, `FishRipple[16]`, `FishMarker[16]` | 33, 16, 16 | code constants |
| Texts | `text/fish/fish.yaml` | the messages | text (already exported) |

## 4. Data to add (data porter)

**Done (F1, 2026-11-07):** `data_porter/specs/systems.md` "fishing", `GameData.fishing()`, `fishing_map(key or id)`, `fishing_bite_chance(bait, kind)`. Both TIMs are converted (`tim_files/ETCDAT/FISHING*.png`): the sprites' CLUT ids are the TIM's palettes 0 (0x601C), 1 (0x605C), 2 (0x609C) and 4 (0x611C), image v from 0x8C. The amazing rod's `MoveImage` (VRAM (0x1C0, 0x1E4, 0x1C × 8) → (0x1C0, 0x1DC)) copies texture rows v 0xE4–0xEB, u 0–0x6F onto v 0xDC–0xE3: that is a view detail for F5. The maps table gets no `fishing` flag: the field asks `GameData.fishing_map(map)`, which is {} off the fishing maps.

The `systems/fishing` record keeps its fields. The fishing map entries gain resolved values in place of the C symbol names:

- `map`: the map's key (`dw1:mayo10`, `dw1:mayo06`), so the field asks "does this map have fishing" instead of testing ids;
- `spots[6]`: `{share, points: [[x, y], …]}`;
- `water`: `{test: "shore_below" | "shore_left", points: […], …}`. The two C functions differ, so each keeps its own rule, named by what it does (§2.1);
- `seadramon_path`: the 8 points, and `seadramon_hours` from `seadramonTime1/2` (9999 = never);
- `sprites`: the sprite file and `FISH_SPRITES[49]`.

Also:
- `bite_chance_by_depth` → `bite_chance_by_bait`, keyed by the bait item. The spec text in `data_porter/specs/systems.md` is fixed to match.
- The TIMs: `FISHING.TIM` / `FISHING2.TIM` are converted (`tim_files/ETCDAT/FISHING.*`). Check that `FISHING2` is there too, and which palette rows `FISH_SPRITES`' CLUTs (0x601C, 0x605C, 0x609C, 0x611C) map to. The amazing rod's palette move needs the same check.

## 5. Godot design

### 5.1 Logic (`scripts/systems/fishing/`, headless-testable)

- **`Fishing`**: the `FishingData` of one map: the pools, the rod, the hooked fish, the tension, the bobber, the bait sprite. `tick_world()` is `FISH_tickFishingWorld` and `tick_rod()` is `FISH_tickRod` / `FISH_tamerTick`.
- **The world interface it calls** (injected callables or a small `FishingWorld` object, like `ArenaWorld`):
  - the tamer: position, yaw, bone 6 / 9 transforms, `start_animation(id)`, `animation_done()`, `set_state`;
  - the projection: `project(world) -> Vector2?`, `ground_at(projected) -> Vector3`, the background bounds;
  - the camera: scroll by a pixel step, save and restore the scroll;
  - the pad (`polled`, `polled_previous`); the inventory (`slots`, `remove_item`, `give_item`, `has_food`); the triggers (the rods);
  - the sounds; the text box; the bait menu;
  - `Rng.custom_random`; the game frame (`GameLoop.frame_count` for `VSync / 3`).
- Fixed-point maths as in the C (integer vectors, `toEulerAngles` / `rotateVector`: reuse `PsxMath`).

### 5.2 Field wiring

- **`FishingHost`** (`scripts/field/hosts/fishing_host.gd`, node `Systems/FishingHost`): made at map load when the map has fishing data (`checkFishingMap`), freed at the next map load or at death (`deinitializeFishing`). It ticks the world object in the object order (after the tamer and the partner, `Field._frame`). The tamer's state 11 calls `tamer_tick()`.
- **The menu:** `GameMenu.fishing_availability` → `FishingHost.availability()`; option 7 → `FishingHost.start()` (`FISH_loadFishing`) and tamer state 11.
- **The clock:** `Clock.active` is false while fishing (`isFishing`).
- **Dying and evolution:** `set_disabled(true / false)` where `partner.c` calls it.
- **The end with Seadramon:** `interpreter.call_section(0, 0x4E4)`.

### 5.3 Projection

`FieldMap.background_pixel(world) − background_size / 2` is the C's projected point. `world_at_pixel` with the ray-to-ground of `mapToWorldPosition` gives the ground point. `DRAW_OFFSET_LIMIT_*` are the scroll's clamp (`FieldMap._clamp_scroll`). `FISH_scrollCameraTo` is `FieldMap.scroll_by` without the follow, and the saved scroll is `FieldMap.view()` / `set_view()`.

### 5.4 View (`scenes/field/fishing_view.tscn`)

- **The sprites** (fish, Seadramon segments, ripples, bobber, bait icon) are quads in the 3D viewport, from `FISH_SPRITES` on the fishing texture, with the PSX blend modes: subtractive (fish), additive (ripples), opaque (bobber). Their depth-order offsets become a small render priority.
- **The rod:** the 4 meshes of `SAO.gltf`, posed each frame from the logic's segment transforms.
- **The line and the gauge:** 2D on the HUD (`PsxDraw` lines; the gauge's sprites).
- **The bait menu and the text box** on `UIBoxes` slots 3 and 2 (`docs/ui.md`), from `FishingBaitMenu` / `FishingTextBox` logic.

## 6. Steps

| Step | What | Complexity |
|---|---|---|
| F1 | Data: §4 (porter + `GameData` accessors), with its checks | Low |
| F2 | Logic, world: spots, water tests, fish and Seadramon AI, ripples, markers, population (`tests/test_fishing.gd`, fixed seeds) | Medium |
| F3 | Logic, rod: the state machine, bobber physics, hooked fish, tension, catch and snag (fake world in the tests) | Hard |
| F4 | Field wiring: the host, the menu, tamer state 11, the clock, dying / evolution, the camera, Seadramon's script | Medium |
| F5 | View: the sprites, the rod, the line, the gauge; the bait menu and the text box on `UIBoxes` | Medium |
| F6 | `tests/fishing_scan.tscn` (a cast, a bite, a catch on map 8 with a fixed seed), `VERIFY.md` | Medium |

## 7. Tests

- **F2:**
  - `randomPointInSpot` stays in water and in the background;
  - the water tests at points on both sides of each shoreline;
  - a fish's states and timings against §2.2 (appear 16 frames, leave on lifetime, flee a ripple);
  - the population balance by share;
  - Seadramon only on map 6 at 8 and 17 h, following its path.
- **F3:**
  - the cast power (`remap` at 0, 0x14, beyond);
  - the release velocity;
  - the splash rules;
  - the bite test against `FISH_BITE_CHANCE` with a fixed seed;
  - nibble / strike windows (too fast, too late);
  - the tension per case and the snap / escape thresholds (15 / 10 / 5 frames);
  - the catch message (the right length for ≥ 200: the port-only fix of the US `/ 200`);
  - `fishCaught + 1`, the item given / bag full;
  - the snag table.
- **F4:**
  - the icon's availability (no rod, no food, both);
  - state 11 stops game time and returns it;
  - no fishing data off maps 8 / 6.
- **F6:** the scan.

## 8. Open questions

- **Q1. `FISH_REEL_TARGET`** is never written, so a hooked Seadramon swims to the world origin. To check on map 6 that the origin is in its water.
