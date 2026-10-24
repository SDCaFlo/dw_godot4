# Map objects (port spec)

Status (2026-10-24): ported with step 5a of `specs/script.md` §3.1: `MapOverlays` (`scripts/field/map_overlays.gd`), the doors and blocked cells in `FieldMap`, the opcodes in `ScriptInterpreter`; `tests/test_map_objects.gd`, `tests/render_check.gd` (a rendered frame, not headless).

The field's map objects:
- **Overlay sprites:** animated 2D details drawn over the background and sorted against the 3D models. Examples: water, torches, smoke, lights, and the parts of the background that stand in front of the tamer.
- **Doors:** the 3D models of `DOOR_MAPDATA`.
- **Blocked areas:** the collision cells a script blocks.
- **The scripts that change them:**
  - `SET_OBJ_VISIBILITY` (0x57, 1,669 uses in 47 scripts: the most used unported opcode);
  - `MOVE_OBJECT_TO` (0x71, 293 uses);
  - `ROTATE_3D_OBJECT` (0x70, 103 uses);
  - `SET_RECT_IMPASSABLE` (0x7C, 16 uses);
  - `SPAWN_SPRITE_AT_ENTITY` (0x7E, 18 uses) and `SPAWN_SPRITE_AT_LOCATION` (0x7D, no uses);
  - builtin `CALL_ROUTINE 0x15` (107 uses).

All `file:line` references are in `external-resources/dw_decomp/src/main/`, US version.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `clearMapObjects`, `loadMapObjects` (`overworld.c:311`, `:331`), `calcMapObjectOrder` (`:420`, called by `setupMap`, `map.c:4296`) | the sprites and instances, their depth | `MapOverlays.load` |
| `renderMapOverlays`, `buildMapOverlayPrim` (`overworld.c:468`, `:732`; called by the map's render, `map.c:4013`) | drawing and animating | `MapOverlays.tick`, the quads |
| `buildSnowflakePrim` (`overworld.c:665`) | the snow maps' falling sprites | `MapOverlays` |
| `setMapObjectsFlag`, `resetMapObjectAnimation` (`overworld.c:930`, `:1002`) | visibility, animation restart | `MapOverlays.set_flag`, `reset_animation` |
| `tickMoveObjectTo` (`overworld.c:874`) | slot type 13 | `MapOverlays.tick_move_to` |
| `spawnSpriteAtLocation`, `spawnSpriteAtEntity`, `getDrawPosition`, `loadMapObjectPosition` (`overworld.c:952`, `:992`, `:939`, `:832`) | placing a sprite on a world point | `MapOverlays.place_at` |
| `updateMapLightState` (`utils2.c:553`) | File City's lights by the hour | `MapOverlays.update_light_state` |
| `loadDoors`, `renderDoors` (`map_object.c:309`, `:374`) | the door models | `FieldMap` (exists; slots kept) |
| `tickRotateDoor` (`map_object.c:932`) | slot type 12 | `FieldMap.tick_rotate_door` |
| `setImpassableRect` (`map_collision.c:190`) | blocked cells | `FieldMap.set_impassable_rect` |

## 2. Original behaviour

### 2.1 The data (`loadMapObjects`)

The MAP file's object section (`asset_porter/specs/map.md`, "objects") holds two lists.

**The sprites** (`LOCAL_MAP_OBJECTS`), per sprite:
- texture x, y, width, height;
- a 3D point (`someX/Y/Z`), used only for the depth;
- the CLUT;
- `transparency`, the blend mode.

**The instances** (`MAP_TILE_DATA.objects[188]`), per instance:
- `animSprites[8]`: a sprite index per frame; −1 ends the list, −2 is a blank frame;
- `animTimes[8]` (u8): frames per animation frame;
- the background pixel (x, y) of the top-left corner;
- `flag` (i8).

Load and setup:
- `clearMapObjects` first resets all 188 instances: no sprites, `currentFrame` −1, `flag` 1.
- `loadMapObjects` runs only when the map has images.
- `setupMap` then runs `calcMapObjectOrder`. It gives every loaded instance `currentFrame` 0 and its depth.

In the data: 214 of the 241 maps have instances, 8,764 in all, at most 188 on a map. 5,705 instances start with flag 0 (shown) and 3,059 with flag 1 (hidden).

**Snow maps** (map ids 0x58–0x60 and 0x84–0x87): the first 0x23 instances get a random y (`randomLimit(240)`). Those from 0x14 on also get a random x (`randomLimit(320)`). All of them get `flag |= 0x80` (§2.5).

### 2.2 Depth (`calcMapObjectOrder`)

The depth is computed once per map, at setup. The instance's first frame that isn't −1 or −2 gives the sprite, and that sprite's 3D point is projected:
- `depth = otz >> 2`, clamped to 0x23 … 0xFF6.
- A sprite whose `someY` is 10000 gets 0xFFE: behind every model, just over the background (0xFFF).
- A snow instance gets 0x1E, in front of the field.

The instance is drawn at that ordering-table entry (`AddPrim(&ot[orderValue])`):
- **Against the models:** the models' polygons sort by their own depth (`GsSortObject4J`, shift 2). A model in front of the sprite's 3D point draws over it, and one behind draws under it.
- **Against other sprites:** `AddPrim` puts a prim at the head of its entry's list, so on the same entry the instance added last is drawn first. On a tie, the lower instance index ends up on top.

### 2.3 Drawing and animation (`renderMapOverlays`, every game frame)

Nothing is drawn or animated while `MAP_LAYER_ENABLED` is 0 (battles, menus that hide the map). For each of the 188 instances whose frame isn't −1 (and `currentFrame` isn't −1):
- **Drawn** when:
  - the frame isn't −2 (blank) and `flag != 1`;
  - the instance is near the screen: `scrollX − 40 < x + width`, `x < scrollX + 360`, the same on y with 60 / 300.
- **Where:** in mode 0, the screen position is (x, y) minus the scroll, as the background (`buildMapOverlayPrim`: `x − cameraX + DRAWING_OFFSET − 160`).
  - Mode 1 (screen coordinates) is for `orderValue < 20`. Only the Ninjamon effect uses it (§6).
  - The sprite's colour is 128 (unchanged).
- **Blending:** `transparency` 4 is opaque (`SetSemiTrans 0`); any other value is semi-transparent with blend mode `transparency & 3`:
  - 0: 50 / 50;
  - 1: additive;
  - 2: subtractive;
  - 3: +25 %.
  - In the data: 4,518 sprites are opaque, 3,580 additive, 564 50 / 50, 448 +25 % and 57 subtractive. Ten sprites have values 1280–1344, which `& 3` makes 0.
  - As on any PSX polygon, the blending applies only to the texels with the STP bit set, and texel 0x0000 is not drawn.
- **Texture:** `clut` −1 is an 8-bit sprite on CLUT row 480, the map's active time-of-day palette, so these sprites change palette with the background. Below 16 it is a 4-bit sprite on row 486. From 16 on it is 8-bit on row `clut + 468`.
- **Animation:**
  - every frame, drawn or not (hidden, off screen, a blank frame), `timer` (u8) counts up;
  - when it equals `animTimes[currentFrame]`, the next frame starts and the timer goes back to 0;
  - after the last frame (−1 next, or frame 8) it starts again at frame 0.
  - **Quirk kept:** `animTimes` 0 is a still sprite only for 256 frames. The u8 timer wraps to 0 and then the frame advances. With a single frame nothing changes.

### 2.4 Changing them

- **`SET_OBJ_VISIBILITY _, instance, flag`** (0x57, 3 argument bytes, no pause): `setMapObjectsFlag(instance, 1, flag)` sets the **whole** flag. The scripts use 0 (show, 925 uses) and 1 (hide, 744 uses). On a snow instance it would also clear bit 0x80.
- **`MOVE_OBJECT_TO slot, instance, speed, steps, _, x, y`** (0x71, 9 argument bytes; pause):
  - It sets slot `12 + slot` to type 13. The asset porter calls `steps` "angle".
  - `speed` is stored but unused.
  - Each frame `tickMoveObjectTo(instance, slot, steps, x, y)` runs:
    - first frame (`MAP_OBJECT_MOVE_TO_DATA[slot]` 0): `delta = (target − position) / steps` per axis (C division), and the flag is set;
    - every frame, including the first: the position moves by `delta`;
    - an axis is snapped to its target once it passes it (`delta > 0`: x ≥ target, `delta < 0`: x ≤ target), or at once when its `delta` is 0;
    - it is done when both axes are on the target, and the flag goes back to 0.
  - The flags are per slot (10), cleared by `loadMapObjects`. The deltas are per slot too (`MOVE_OBJECT_DELTA_X/Y[slot]`).
  - It moves in background pixels, through nothing: only the drawing position changes.
- **`SPAWN_SPRITE_AT_ENTITY id, node, instance`** (0x7E, 3 bytes):
  - `getDrawPosition` takes the world position of the entity's `node` (its bone matrix, `posData[node].posMatrix.workm.t`) and projects it to a background pixel;
  - `spawnSpriteAtLocation(…, count 1)` places the instance's top-left corner half the sprite's size above-left of that pixel. The sprite is the instance's first non-blank frame;
  - `loadMapObjectPosition` then clears bit 0x10 of the flag. It does **not** show the instance: the scripts show it with `SET_OBJ_VISIBILITY`.
- **`SPAWN_SPRITE_AT_LOCATION count, x, y, z, instance`** (0x7D, 9 bytes): the same for `count` instances from `instance` on, at a world point. It has no uses in the scripts.
- **`CALL_ROUTINE 0x15`** (107 uses): `resetMapObjectAnimation(script value 0xF7, count script value 0xF8)` sets timer 0 and frame 0 on those instances. The frame then ends (`longjmp 2`).
- **`updateMapLightState`** (every game frame, `gameLoop` → `updateTournamentRegistration`, `tournament.c:119`, before `tickScript`):
  - it reads one entry, `MAP_LIGHT_UPDATE_DATA[1] = {map 0xB7, mode 1, start 0x31, count 2, trigger 0xFFFF}` (`script_common.c:267`);
  - on File City TWNB04 (map 183) instances 49–50 get flag 1 (hidden) from 7:00 to 18:59, and 0 the rest of the day. This is mode 1: mode 0 would do the opposite;
  - the entry would only apply while its trigger is set; 0xFFFF means always;
  - since this runs every frame, it overrides the scripts' flags for those two instances;
  - **Quirk kept:** `updateTournamentRegistration` returns before it on some frames while a tournament is registered (`tournament.c:52-110`), and then the lights aren't updated that frame.

### 2.5 Snow (`buildSnowflakePrim`)

Only for instances with flag bit 0x80, every frame:
- **Movement by sprite id** (`animSprites[0]`):
  - 0, 3, 4: `randomLimit(6)`, folded to −2 … 3 (a value above 3 becomes `−(r % 3)`), fall 3 px;
  - 1, 5, 6: `randomLimit(2)`: 0 or 1, fall 1 px;
  - 2: `randomLimit(4)`: −1 … 2, fall 10 px;
  - other sprite ids leave the C's range and speed uninitialised: the port gives them no drift and no fall.
- **Drift:** applied to x every third frame, and only for sprites 0, 3 and 4. It is always added to the drawn position. x wraps between 0 and 320.
- **Landing:** from y 0x83 on, a flake (not sprite 2) has a 2-in-10 chance per frame to start its "melt" frames. When they end it goes back to y 0. Every flake goes back to y 0 at y 0xF1.
- **Drawing:** in screen coordinates (not scrolled), always 4-bit on row 486 (`clut × 16`), at order 0x1E.

### 2.6 Doors (`loadDoors`, `renderDoors`, `tickRotateDoor`)

- **The slots:** `MAP_3D_OBJ[6]` gets the 6 slots of `DOOR_MAPDATA[doorsId − 1]`:
  - model id, translation, rotation y, and `direction` = the rotation;
  - model 255 (−1 as i8) is an empty slot, skipped when drawing;
  - **the slot index matters:** `ROTATE_3D_OBJECT` names a slot. Tables 1 and 6 have an empty slot 0 (`[255, 9, 9, 9, 10, 10]`, `[255, 18, 16, 17, 255, 255]`). The asset porter today drops empty slots, which would shift those indices (§3).
- **Model 10** is drawn twice: once as is, and a mirrored copy with rotation `−vy`, moved `∓680` on z (`+680` when `vy < 0`). It is a double door. The port doesn't draw the copy today.
- **`ROTATE_3D_OBJECT door, _, target`** (0x70, 3 argument bytes; pause): slot 11 gets type 12 with `entityId` = the door slot and `target` (i8, the direction, 1 or −1).
- **`tickRotateDoor(door, target)`, by the door's model**, with one shared timer `MAP_OBJ_ROTATE_TIMER`:

  | models | each frame | done |
  |---|---|---|
  | 0 | rotation y −= target × 33 | timer > 32 (33 frames: about −1,056, 93°) |
  | 9–0xD, 0x10–0x13 | rotation y += target × 33 | timer > 32, and the rotation goes back to `direction` |
  | 0xE, 0xF | rotation y += target × 33 | timer > 32 |
  | 5, 0x1F, 0x20 | translation y −= target × 200 (up) | timer > 9 |
  | 0x15, 0x16, 0x18, 0x1B, 0x1D | translation x += 30 (z on map 0x81) | timer > 9 |
  | 0x14, 0x17, 0x19, 0x1C, 0x1E | translation x −= 30 (z on map 0x81) | timer > 9 |
  | 0x1A | rotation x −= target × 110, clamped to −0x400 … 0 | timer > 19 |
  | others | nothing | never |

  - The timer is incremented first, and the "done" frame doesn't move. When done, the timer is reset to 0.
- **How the scripts use it:** the canyon gates (GCAN02/03/06/10, models 22–25, scripts 37, 38, 41, 124) give `ROTATE_3D_OBJECT` for door 0 and door 1 on alternate frames, with `DELAY 1` between them, 10 calls in all. Each call replaces slot 11, so one door ticks per frame.
  - **The shared timer counts every tick, whichever door it moves:** from 0, door 0 moves on ticks 1, 3, 5, 7, 9 and door 1 on 2, 4, 6, 8. The 10th tick (door 1) passes 9: it is done without moving, and the timer goes back to 0. So door 0 moves 5 frames (150) and door 1 only 4 (120).
  - A swing that never reaches "done" leaves the timer where it stopped for the next one. Kept as in the C: besides "done", only `loadDoors` resets it, on map load.
- The models 9–13 doors snap back to closed at the end. The scripts that use them warp away or close them again in the same frame. To check in the game (§6).

### 2.7 Blocked areas (`SET_RECT_IMPASSABLE`)

- **`SET_RECT_IMPASSABLE _, x, z, w, h`** (0x7C, 7 argument bytes, no pause): `setImpassableRect` sets the collision cells `[x, x + w) × [z, z + h)` to 0x80 (blocked).
  - The arguments are cast to i8. All the scripts' values are below 128.
  - The original `MAP_COLLISION_DATA` is read again on the next map load, so the block lasts until then.
- **Example:** MAYO08A Digimon Bridge, script 10: `x 22, z 16, w 3, h 12` blocks the broken bridge.

## 3. Godot design

- **The porters:**
  - **asset porter** (`asset_porter/specs/map.md` first): `map.json`'s `doors` keeps the slot of each door (`slot` 0–5), so `ROTATE_3D_OBJECT`'s index finds it. The empty slots stay dropped.
    - Check: tables 1 and 6 keep slots 1–5.
    - The object sprites' PNGs lost the STP bit the blending needs (RGBA, alpha only for 0x0000): the porter now writes an `.stp.png` mask next to each sprite that has STP texels (`objects[k].stp_files`). 4,247 of the 4,635 semi-transparent sprites in use have one; the others draw opaque, as on the PSX.
  - **data porter** (`data_porter/specs/systems.md`): `MAP_LIGHT_UPDATE_DATA` becomes a component of the map record, `light_objects: {start, count, mode, trigger or null}`. The light rule then reads a map property, not a map id (`specs/content.md`).
- **`MapOverlays`** (new, `scripts/field/map_overlays.gd`, a child of `FieldMap`):
  - `load(data, map_entry)` builds the instances from `map.json` (`objects`, `object_instances`), with the snow setup. The snow maps become a map property too (`snow`), not the id ranges.
  - Each instance is a quad in the 3D scene, facing the camera at the view depth of its sprite's 3D point:
    - its corners are the background pixels `(x, y)` … `(x + w, y + h)` projected back to that depth (`FieldMap` has the projection);
    - the camera never moves (the scroll only shifts the frustum), so a quad stays still while the camera scrolls, as the background does;
    - the depth buffer then sorts it against the models as the C's ordering table does, to within the ordering table's steps (§6).
    - `someY` 10000: the quad sits just in front of the background, behind everything.
  - **Materials:** unshaded, the blend mode from `transparency` (mix, add, subtract, +25 %), depth test on, no depth write for the semi-transparent ones.
    - On a tie the C draws the lower index on top: `sorting_offset` follows the index.
    - Time-of-day palette sprites (`clut` −1) use the PNG of the active palette (`object_<k>_p<N>.png`). They change palette when the background's fade ends (`FieldMap.set_time_of_day`); the C fades row 480 for both, so during the 25 frames of the fade the sprites keep the old palette (§6).
    - **The compositing:** the background canvas layer moved into the 3D viewport, as its environment's background (`Environment.BG_CANVAS`, canvas layers up to −1). The additive and subtractive sprites then blend with the background, which a transparent viewport over it couldn't do. `tests/render_check.gd` checks the background reaches the screen unchanged (0 pixels differ on MAYO01 and TWNB04).
  - **Snow:** quads as the others, at the depth of order 0x1E (480), placed each frame on the screen pixels (scroll + x, y): in front of every model, as the C's order 0x1E.
  - **`tick()`** on `GameLoop.frame`, after the interpreter (where the C renders), unless the map layer is off: the animation of §2.3 and the snow of §2.5. The quad's visibility follows the flag and the blank frames. The off-screen test is only an optimisation and doesn't change what is drawn, so it isn't ported.
  - `set_flag(instance, flag)`, `reset_animation(start, count)`, `tick_move_to(instance, slot, steps, x, y) -> bool`, `place_at(world, instance, count)`, `update_light_state(hour, triggers)`.
  - The sprite PNGs load at runtime from the raw output (`Content`: the editor mirror leaves them out, 19k files).
- **`FieldMap`:**
  - `_load_doors` keeps the 6 slots (an array, null for empty) with their PSX translation, rotation and `direction`. It draws model 10's mirrored copy.
  - `tick_rotate_door(slot, target) -> bool` (§2.6), with `_rotate_timer` reset on load. It writes the door node's transform.
  - `set_impassable_rect(x, z, w, h)` writes the collision cells.
- **The interpreter** (`specs/script.md` §2.7):
  - slots 11–21 tick type 12 through `field.tick_rotate_door` and type 13 through `overlays.tick_move_to`. Today they end at once;
  - `SET_OBJ_VISIBILITY`, `SET_RECT_IMPASSABLE`, `SPAWN_SPRITE_AT_ENTITY` / `_AT_LOCATION` and builtin 0x15 call the field.
  - The node position for `SPAWN_SPRITE_AT_ENTITY` is the entity's bone `node` from its animator (the same bones as the C's `posData`).
  - Without a field they stay reported, as now.
- **`updateMapLightState`** runs each frame from the field, before the interpreter (where the C runs it).

## 4. Data

- **Asset porter `maps/<NAME>/map.json`:** `objects` (per sprite: `files` per palette, `width`, `height`, `pos3d`, `clut`, `page`, `transparency`), `object_instances` (`sprites`, `times`, `x`, `y`, `flag`), `doors` (+ `slot`), `map_entry.id`.
- **Data porter, map records:** `light_objects` (new), `snow` (new: the ranges of `loadMapObjects`, from the C's literal ids, checked against its text like `change_map_previous`).

## 5. Verification

`tests/test_map_objects.gd` (new):
- **Animation:** the times and the frame list, the blank frames, −1 ends, the u8 wrap of `times` 0, a hidden instance still animating, `reset_animation`.
- **`MOVE_OBJECT_TO`:**
  - the delta from the first frame, with C division (e.g. 100 px in 3 steps: 33, 66, 99, then the snap to 100);
  - a delta of 0 snaps that axis at once;
  - the per-slot flags;
  - the slot freed when done; `WAIT_FOR_ENTITY 0xCB + slot` waits for it.
- **Doors:**
  - model 0 turns −33 a frame for 32 frames and ends on the 33rd;
  - models 9–13 snap back;
  - the canyon gates' alternating calls with the shared timer: door 0 moves 5 frames, door 1 4;
  - the slots of tables 1 and 6.
- **Flags and the light rule:** TWNB04's instances 49–50 at 6:59, 7:00, 18:59, 19:00.
- **`SET_RECT_IMPASSABLE`:** the cells blocked, the next map load restores them.
- **On real data:** every map loads its instances, and their depth is between the background and the camera. The MOVE_OBJECT_TO sections (scripts 18, 136, 154, …) run to their end.

`VERIFY.md`, a new "Map objects" section:
- **Animated details:** water, torches and smoke on a few maps (Native Forest, File City, Factorial Town). Their speed, and the tamer walking in front of and behind them.
- **File City TWNB04's lights:** off by day, on from 19:00.
- **The canyon gates** (Great Canyon) opening in their scene; a double door (model 10) showing both halves.
- **Amida Forest / Secret Beach Cave / Factorial Town:** the scenes that move sprites.
- **Digimon Bridge:** the broken bridge blocked.
- **A snow map** (Freezeland): the falling snow.

## 6. Open questions

- **Depth steps:**
  - the C sorts a whole sprite at one ordering-table entry (`otz >> 2`), and a model's polygons at theirs (shift 2). The port's depth buffer compares per pixel, so a model crossing a sprite's depth may cut through it instead of being wholly in front or behind;
  - the C's order between a model's polygon and a sprite on the same entry isn't known.
- **Mist** (`renderMist`, screens 115–119, 121, 163, 220) and the **Ninjamon effect** (`createNinjamonEffect`, overlay mode 1): drawn from the overlays but started by other code. They aren't in this step.
- **Models 9–13 snapping back** (§2.6) at the end of their swing: to check in the game, on a map with those doors.
- **Blending in linear colour:** Godot blends in its linear buffer, the PSX in its 5-bit colour space: the additive sprites (3,580) may look brighter than on the PSX. To compare in the game.
- **The time-of-day fade** doesn't fade the palette sprites (§3): they switch at its end.
- **The 3D map props** started by builtins (the boulder `SPAWN_BOULDER` / `MOVE_BOULDER` in Drill Tunnel, the dirt cart, Toy Town's boxes, the gearbox, Angemon's pedestal, the medals, the chests, the warp crystals; `map_object.c`): they share `MAP_3D_OBJ` slot 0 with the doors in some cases. They come with their own systems.
