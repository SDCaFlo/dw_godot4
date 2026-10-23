# Partner in the field (port spec)

Status: implemented 2026-10-23 (`scripts/field/partner.gd`, `psx_animator.gd`, `FieldMap` path helpers; test `tests/test_partner.gd`; human checks in `VERIFY.md`).

The partner Digimon following the tamer on the field: model, placement, animations by distance, path finding around walls. Care (hunger, sleep, poop, sickness: `tickConditions` and the other states of `partnerTickOverworld`) is the next step. State fields are in `specs/game_state.md`.

## 1. C functions reproduced

| C (`external-resources/dw_decomp/`) | What | Godot |
|---|---|---|
| `partnerTick` → `partnerTickOverworld` (`partner.c:189–266`) | per game frame, by `PARTNER_STATE` | `Partner.tick()`: states 1 (normal), 3 (sleep) and 7 (wild poop); the care states are `specs/care.md` |
| `partnerTickNormal` (`partner.c:268`) | collision, walking, then care (later) | `Partner.tick()` |
| `partnerTickCollision` (`map.c:3267`) | waypoints, facing, wall handling | `Partner.tick_collision()` |
| `partnerTickWalking` (`partner.c:827`) | animation by distance | `Partner.tick_walking()` |
| `getPartnerTamerCloseness` (`partner.c:971`) | far / near / close | `Partner.closeness()` |
| `setPartnerSlowWalking`, `setPartnerIdle`, `updateConditionAnimation` (`partner.c:998–1085`) | which walk / idle / mood animation | same names |
| `initializePartnerWaypoint`, `setPartnerWaypoint`, `popPartnerWaypoint` (`map.c:2926–2947`, `:3375`) | ring of 30 waypoints | `Partner` waypoints |
| `isFiveTileWidePathBlocked`, `isLinearPathBlocked`, `isTileOffScreen`, `getModelTile` (`map.c:3133–3265`, `:3649`; `map_collision.c:148`) | line-of-sight on the collision grid, screen test, tiles | `FieldMap` |
| `entityLookAtLocation`, `entityLookAtTile` (`map.c:3389`, `utils2.c:344`) | face a point / tile | `Partner.look_at_psx()` |
| `collisionGrace` (`map.c:3466`), `entityCheckEntityCollision` (`map.c:3740`, non-tamer branch) | turn along the tamer; box edge vs the tamer's square | `Partner.collision_grace()`, `Partner.hits_tamer()`; `Partner.probe()` stands for `entityCheckCollision` (a probe of one frame's forward motion, `entityMoveForward`) |
| `loadMapEntities` → `setupPartnerOnWarp` (`tamer.c:379–413`, `partner_impl.c:848`) | placement when entering a map | `Partner.place_for_spawn()` |
| `startAnimation`, `tickAnimation` (`anim.c:201–357`) | animation state: frame, loop count, playing flag | `PsxAnimator` |

## 2. Original behaviour

### 2.1 Placement (`loadMapEntities`)

The partner starts 200 units from the tamer's spawn point, on the side the spawn rotation points to, and faces the tamer:
- **Offset by spawn rotation:**
  - ≤ 0x200 or > 0xE00: z + 200;
  - 0x201–0x600: x + 200;
  - 0x601–0xA00: z − 200;
  - 0xA01–0xE00: x − 200.
- **Rotation:** `(rotation + 0x800) % 0x1000`.
- **Then:** animation 0, state 1 (`setupPartnerOnWarp`).

### 2.2 Distance (`getPartnerTamerCloseness`)

`r` = the partner's `DIGIMON_DATA.radius`; `d²` = squared ground distance (x, z) to the tamer.
- **0, far:** `d² > (r·7/2)²`;
- **1, near:** `d² ≥ (r·5/2)²`;
- **2, close:** otherwise.

### 2.3 Facing and waypoints (`partnerTickCollision`)

The partner faces the tamer (`entityLookAtLocation`: `rotation.vy = _atan(dz, dx)`). When the way between them is blocked, it follows the tiles the tamer walked over:
- **When the tamer enters a new tile:**
  - If the 5-tile-wide path from the tamer's tile to the partner's tile is blocked (`isFiveTileWidePathBlocked`: 5 parallel `isLinearPathBlocked` lines, ±2 tiles across the main axis; any blocked line counts), the tamer's previous tile becomes a waypoint. This happens only if the path from the tamer to the last waypoint is blocked too; with no waypoints, the list starts over with that tile.
  - Otherwise the waypoints are cleared.
- **Shortcuts:** with 2 or more waypoints, the three before the last are tested from the newest back. At the first one the tamer can see (path not blocked), the waypoints after it are dropped.
- **Off-screen jump:** if the current waypoint's tile is off screen (`isTileOffScreen`: projected more than 200 / 160 px from the screen centre) while the partner is off screen too, the partner jumps to that tile's centre and the waypoint is consumed.
- **Facing:** with waypoints, the partner faces the current waypoint's tile centre and consumes it on arrival; without, it faces the tamer.
- **Obstacles:** `entityCheckCollision` probes one step of the animation's forward motion (`entityMoveForward`; 0 while idling, so a standing partner hits nothing). An entity collision (codes 0–9) restores the previous rotation and calls `collisionGrace(tamer, partner)`. That tries the 4 directions of `COLLISION_GRACE_ROTATION[rotation / 512]` and turns at most 0x50 per frame towards the first free one; with none free it turns 32 and stops.
  - **The tamer never makes it turn:** he is `collisionGrace`'s first argument, which `entityCheckCollision` skips as its `source`. Bumping the tamer only keeps the old rotation; the grace turn is for other entities (NPCs) and walls met at the same time.

### 2.4 Animations (`partnerTickWalking`)

Animation ids follow the game: 0 idle, 1 tired idle, 2 walk, 3 tired walk, 4 run, 5 happy, 7 unhappy, 0x0E injured / sick, 0x0F hungry, 0x10 poopy, 0x11 sleepy, 0x12 tired, 0x13 unhappy (condition).
- **Far (0):**
  - while walking (2 / 3) and not unhappy, the walk finishes its loop (loop count 0xFF → 1) and then turns into the run (4);
  - otherwise run, or walk (2) when unhappy (`condition & 0x10`).
- **Near (1):** from the run straight to the walk; from any other animation once it has played to the end (an endless one finishes its loop first). It's the tired walk (3) when sleepy, tired, injured or sick (`condition & 0x63`).
- **Close (2):**
  - **Stop:** a moving animation (2–4) finishes its loop, then stops; the same once the path ahead is free. Stopping means idle (0), or tired idle (1) with those conditions, and a new "emotion" timeout of 1–5 animation lengths (`randomLimit(5) + 1`).
  - **Moods** (`updateConditionAnimation`): standing longer than the timeout picks one:
    - no condition: happy (5) when happiness ≥ 0x1F, unhappy (7) when < −0x1E, else idle;
    - otherwise by condition: injured / sick → 0x0E, poopy → 0x10, hungry → 0x0F, tired → 0x12, sleepy → 0x11, unhappy → 0x13.
  - **Back to idle:** a mood that has stopped playing returns to idle with a new timeout.
- `STOP_DISTANCE_TIMER` counts frames since the last animation change.
- **US / JP_TRIAL-and-later `IS_STANDING_STILL` behaviour** (1 while moving, 2 while close): a mood is only picked while close, and `setPartnerIdle` restarts idle when coming to a stop.
- **Health Shoe:** while the tamer runs with it, +5 HP / MP every 20 frames (`partner.c:949–968`). This comes with the items step.

### 2.5 Animation state (`startAnimation`, `tickAnimation`)

- **`startAnimation`:** frame = 1, playing flag (`animFlag & 1`) on, loop count 0, frame count from the data.
- **`tickAnimation`:**
  - **Loop start:** sets the loop count (0 or 0xFF = endless).
  - **Loop end:** decrements it (never 0xFF) and jumps back unless it reached 0.
  - **End:** when the frame reaches the frame count, the playing flag clears.
- **"Finish the loop":** code sets an endless loop's count to 1, so the animation leaves the loop at its next end and plays to the end.

## 3. Godot design

- **`PsxAnimator`** (`scripts/field/psx_animator.gd`) wraps a model's `AnimationPlayer` with the original animation state: `anim_id`, `frame`, `frame_count`, `loop_count`, `playing`.
  - **Source:** the glTF animation extras of the asset porter: `frame_count`, and `loop` (start / end frame) for endless loops (`asset_porter/specs/mmd.md`).
  - **Loops:** endless animations loop in Godot; `finish_loop()` turns looping off, so the animation plays to its end and stops.
  - **Approximation:** this matches the original for loops that span the whole animation (all locomotion and idle animations). Partial loops (e.g. Agumon `anim_19`: frames 10–11) are not reproduced yet.
- **`Partner`** (`scripts/field/partner.gd`, a node of the field scene next to the tamer) loads the model of `GameState.state.partner.digimon` through its `files` component (`CHDAT/MMD<n>/<NAME>.MMD` → `mmd_files/MMD<n>/<NAME>.gltf`).
  - **Logic:** decisions run once per game frame (`GameLoop.frame`).
  - **Visuals:** the animation and root-motion movement run every Godot frame, like the tamer, so they stay smooth.
  - **Walls:** the partner moves like the tamer: root motion along its facing, undone when the map blocks it, sliding along the free axis.
    
    The original's split between the collision probe (`entityCheckCollision` restores the position) and the movement in the momentum code isn't traced yet, so this follows the tamer port.
  - **Entity collisions:** the partner checks the tamer only, with the box test of `entityCheckEntityCollision`: its leading edge after one step (`Partner.step`, the root motion of the last game frame) against the tamer's square, radii `DIGIMON_DATA` 120 for Agumon and 100 for the tamer. A bump keeps the old rotation (§2.3) and, in the close range, stops the walk at once. It never blocks the movement: like the original, the entity checks restore the position, and only the map stops the momentum.
    
    **Why it must not block:** the boxes touch at up to about 311 units on a diagonal, which is still "near" (≥ 300 for Agumon). A blocked step there would leave the partner walking in place; unblocked, it walks on into the close range and stops. NPCs and the tamer's own collision with the partner come with NPCs.
    
    **Fixed 2026-10-23:** the first version blocked the step, probed 10 units even while idling and let `collisionGrace` count the tamer. The partner then turned 0x50 per frame while standing next to the tamer (it spun after a run).
- **`FieldMap`** gets the map helpers of §2.3: `model_tile`, `is_linear_path_blocked`, `is_five_tile_wide_path_blocked`, `is_tile_off_screen`.
- **`GameState`:** `partner.position` / `tamer.position` follow the entities every game frame.

## 4. Verification

`tests/test_partner.gd`:
- `closeness` at the three distances for a known radius;
- placement for each spawn-rotation quadrant;
- the line and 5-wide path checks on a synthetic grid;
- the waypoint ring (push, shortcut, pop);
- the animation choice table (far / near / close, condition overrides, happiness moods);
- `PsxAnimator` loop / finish / end flags on a real model.

`VERIFY.md` Partner section: Agumon follows, runs when far, walks when near, stops close and idles, finds the way around a wall.

## 5. Open questions

- The exact movement / collision split (§3) and entity collisions (`entityCheckEntityCollision`).
- The partner and tamer states that block a time-of-day fade (`specs/clock.md` §2.5) come with the other partner states.
- `initializePartner` (`partner_impl.c:450`): ported with the care step (`Care.initialize_partner`, reading `raise_data.first_technique`; `specs/care.md` §2.15).
- The order in a frame: the partner ticks before the clock (`specs/care.md` §2.1). The field starts it first; `on_screen` is now updated after the state's tick, like `partnerTickOverworld`.
