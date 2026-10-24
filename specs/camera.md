# Field camera (port spec)

Status (2026-10-24): spec written for step 4 of `specs/script.md` §3.1; code not started. Today `FieldMap.follow()` re-centres the tamer every Godot frame while `Tamer.camera_follow` is set; nothing else moves the camera.

The field's view: the fixed 3D camera of the map, a 2D background larger than the screen, and a scroll that keeps the two aligned. The original moves it three ways: the follow while the tamer walks, the pans of scripts and scenes, and the "with camera" moves that drag it along with an entity.

All `file:line` references are in `external-resources/dw_decomp/src/main/`; the US version.

## 1. C functions reproduced

| C | file | port |
|---|---|---|
| `initializeDrawingOffsets` | `map.c:4355` | map entry: centre on the tamer, clamped (`FieldMap.follow`, as now) |
| `tickCameraFollowPlayer`, `updateDrawingOffsets` | `map.c:4464`, `:4616` | the follow while the tamer walks (§2.2) |
| `cameraIsAtEdge` | `map.c:4818` | the clamp to the background (§2.1) |
| `createCameraMovement`, `checkCameraMovement`, `tickCameraMovement` | `map.c:4844`, `:5080`, `:4855` | pans (§2.3) |
| `tickCameraMoveTo`, `tickCameraMoveToEntity`, `storeEntityLocation` | `map.c:5100`, `:5114`, `:5054` | the camera slot's ticks (`specs/script.md` §2.7) |
| `moveCameraByDiff` | `map.c:5124` | the "with camera" moves (§2.4) |
| `setCameraFollowPlayer`, `unsetCameraFollowPlayer` | `map.c:5189`, `:5184` | `CAMERA_FOLLOW_PLAYER` |

Not ported: `handleTileUpdate`, `updateTileRow` / `Column`, `uploadMapTileImages`. They stream the background's 128 × 128 tiles into VRAM; the port draws the whole background.

## 2. Original behaviour

### 2.1 The state

- **`MAP_TILE_DATA.cameraX / Y`:** the background pixel at the screen's top-left (the port's `FieldMap.scroll`).
- **`DRAWING_OFFSET_X / Y`:** where the 3D projection centre is drawn on screen. Every function that changes the scroll changes it by the opposite amount, and the clamp sets it to its limit, so it always equals `background / 2 − scroll` (`DRAW_OFFSET_LIMIT_X_MAX = cameraX₀ + 160` with `cameraX₀ = width·128 / 2 − 160`). The port derives it from the scroll (`FieldMap.follow`'s frustum offset), so the camera state is the scroll alone.
- **`PLAYER_OFFSET_X / Y`:** a second drawing offset that is never clamped. In scroll units the port calls it the **virtual scroll** `v = background / 2 − PLAYER_OFFSET`: where the scroll would be without the background's edges.
- **The clamp** (`cameraIsAtEdge`): the scroll is kept in `[0, background − 320 × 240]`. It reports per axis whether it had to clamp; the C's `atEdge` is 0 when clamped and 1 when free.
- **`CAMERA_FOLLOW_PLAYER`:** set on map load; pans and scenes clear it (the sleep scene, wild poop, warps; the port's `Tamer.camera_follow`).

### 2.2 The follow (`tickCameraFollowPlayer`, every frame in `renderMap`)

- **Only when** the field is up (`GAME_STATE` 0), `CAMERA_FOLLOW_PLAYER` is set, the tamer is free (state 0), and a direction is held (`POLLED_INPUT` up / right / down / left).
- **The step:** `d` = the tamer's screen motion this frame. `STORED_TAMER_POS` is set at the end of `tamerTickWalkingState` (`tamer.c:592`; `:533` when the menu opens) before his animation moves him, so `d` is one frame's root motion as drawn.
  - The scroll moves by `d`, then `updateDrawingOffsets`: the clamp; `v += d`.
  - **Per axis, if the clamp didn't apply:** if the held direction points away from where the virtual scroll is, the scroll's step is undone (it stays). Left held and `v > scroll`, or right held and `v < scroll`; the same for up / down with y.
- **Effect:** the scroll follows `clamp(v)`. At an edge the scroll stops and the tamer walks towards the screen edge while `v` goes on. Walking back, the scroll stays until `v` is back inside the edges, i.e. until the tamer is back where the scroll would have him.
- **On map entry** (`initializeDrawingOffsets`): `v` = the scroll that centres the tamer, and the scroll is `clamp(v)` (the port's `follow()` as now).
- **Consequences:**
  - the tamer is centred only if he was centred when `v` was last set;
  - the camera doesn't move while he is moved by anything else: scripts (state 10), warps (state 5), scenes, or when no direction is held;
  - after a pan he stays where the pan left him on screen (§2.3).

### 2.3 Pans (`createCameraMovement` / `checkCameraMovement` → `tickCameraMovement`)

A pan is an object (`0xFB1`) that runs once per frame until it ends. Its instance id is the **speed** (the number of frames for the move).

- **Started by:**
  - the camera slot (10) of a script, through `checkCameraMovement(speed)`;
  - scenes, through `createCameraMovement(&target, speed)` (the toilet, `specs/care.md` §2.16).
- **`CAMERA_REACHED_TARGET`:** −1 idle, 0 moving, 1 reached.
  - `checkCameraMovement`: at −1 it sets 0, adds the object and returns 0; at 1 it sets −1 and returns 1 (the slot is done); otherwise 0.
  - `createCameraMovement` sets −1 and adds the object directly.
- **First frame:** the target point (`CAMERA_TARGET`, PSX x, y, z) is taken once (later changes don't count).
  - The target scroll `T` is the one that puts the point at the screen centre, clamped to the edges.
  - `total = T − scroll`, per axis.
  - `v = T` at once (`PLAYER_OFFSET = CAMERA_MOVE_DIFF`): after the pan, the follow continues from there.
  - The follow is turned off (`unsetCameraFollowPlayer`).
- **Every frame**, per axis:
  1. **Step:** the scroll moves `total / speed` (C division, toward 0).
  2. **Remainder:** the first `|total % speed| + 1` frames move 1 more in the direction of `total`. With `total` 0 that is −1, undone by step 4.
  3. **Edges:** the clamp.
  4. **Not clamped:** past `T` (or `total` 0) it is set to `T`. The axis is done on `T`.
  5. **Clamped:** the axis counts as done.
- **The end:** when both axes are done.
  - The follow is turned back on (`setCameraFollowPlayer`); `CAMERA_REACHED_TARGET` 0 → 1 (a scene's −1 stays −1); the object is removed.
  - A slot sees the 1 on its next tick and is freed then.
- **Length:** about `speed` frames. The scripts use 10–30 (`MOVE_CAMERA_TO`: 62 uses, 20 the most common; `MOVE_CAMERA_TO_ENTITY`: 158, 10 the most common, 42 of them back to the tamer at speed 10).
- **`MOVE_CAMERA_TO x, z`:** the target is (x, the tamer's y, z), set again every frame (`tickCameraMoveTo`). Its return value is `checkCameraMovement`'s: the decomp writes it as `void`, but the assembly tail-calls `checkCameraMovement` (`asm/us/main/matchings/map/tickCameraMoveTo.s`).
- **`MOVE_CAMERA_TO_ENTITY id`:** the target is the entity's location (`storeEntityLocation`), copied every frame, but only the first frame's counts. An id with no entity leaves the old target.

### 2.4 Moves with the camera (`moveCameraByDiff(from, to)`)

The "with camera" walks and moves (`specs/script.md` §2.7) call it every frame, with the entity's previous and current position:
- the scroll moves by the screen motion between the two, then `updateDrawingOffsets` as in §2.2, with the pad as it is: during a scene usually no direction is held, so no step is undone. The clamp still applies, and `v` takes the whole motion;
- the follow flag isn't changed: the walking entity drags the camera along.
- The walk's previous position (`PREVIOUS_CAMERA_POS`, with `PREVIOUS_CAMERA_POS_INITIALIZED`) is one global for every slot (`specs/script.md` §2.7).

## 3. Godot design

- **`FieldMap`** (`scripts/field/field_map.gd`):
  - `scroll` (as now) and `virtual_scroll` (`v`). `follow(world)` stays the map entry (sets both).
  - `scroll_by(delta, pad)`: §2.2's step (scroll, clamp, `v`, the undo by the held direction).
  - `screen_motion(from, to)`: the background-pixel motion of a 3D move (`background_pixel` difference), the `d` of §2.2 and §2.4.
  - The pan: `start_pan(psx_target, speed)` (`createCameraMovement`), `check_pan(speed)` (`checkCameraMovement`, for the slot), `tick_pan()` (`tickCameraMovement`), `pan_reached` (`CAMERA_REACHED_TARGET`).
  - `tick_pan()` runs on `GameLoop.frame` after the script and the partner. That order is a guess (§6).
  - `_apply_scroll()`: the background position and the frustum offset from `scroll`, as `follow` does now.
- **`Tamer`:**
  - `_process` replaces `field.follow(global_position)` with `field.scroll_by(field.screen_motion(before, after), pad)`;
  - only while `camera_follow` (`CAMERA_FOLLOW_PLAYER`), state 0 and a held direction (§2.2).
  - `camera_follow` keeps its users (warps, sleep, wild poop); pans set and clear it too.
- **The interpreter:** the camera slot 10 (types 6, 7) calls `check_pan`; the "with camera" moves call `scroll_by` (`specs/script.md` §2.7).
- **Units:** the scroll is in background pixels as now. The original's projection gives whole pixels (`gte_stsxy`), so the motion is rounded to whole pixels, with the remainder carried, so slow walks still scroll.

## 4. Data

Nothing new: the camera matrices, projection and background size are in the map's `map.json` (the asset porter, `asset_porter/specs/map.md`).

## 5. Verification

`tests/test_camera.gd` (new, headless, a `FieldMap` with a real map's camera):
- the follow: no scroll without a held direction or with the tamer not free; at an edge the scroll stops and `v` goes on; walking back, the scroll waits until `v` is back in range; the result is `clamp(v)`;
- a pan: `total / speed` steps with the remainder's extra pixel, ending on `T` in about `speed` frames; a target beyond the edge ends at the edge; `v = T`; the follow is off while it runs and on after; `check_pan` returns 1 once, a frame after the end;
- `scroll_by` without a direction: clamp only, `v` takes the whole motion.

`VERIFY.md`, "Camera":
- walk to a map edge and back: the camera stops at the edge, and on the way back starts again only when the tamer is back near the centre;
- after a script pans the camera away and back (Jijimon's house intro, the File City cutscenes), compare with the original where the tamer is on screen afterwards;
- walk-out exits: the camera stays while the tamer runs off (state 10 doesn't follow).

## 6. Open questions

- **The pan object's first frame:** it is added during the script's slot tick (or a scene's tick). Whether it runs the same frame depends on the object list's order (`addObject`, `tickObjects`), not traced. The port runs it the same frame; off by one frame at most.
- **Pixel rounding:** `gte_stsxy` rounds each point's projection to whole pixels, and the motion is the difference of two rounded projections. The port's carried remainder gives the same total over a walk, but may differ by 1 pixel on a frame.
