# Map events and the ending (step 4f)

Status (2026-11-02): **approved.** The open questions (§8) stay open: the port does what the C reads, and the user checks in the game later. This is step 4f of `PLANS.md`, from the gap analysis after 4e-4. The scripts' remaining builtins and opcodes run as no-ops today (`ScriptInterpreter.UNPORTED` / `ROUTINE_WAITS`), so the story goes on, but the scene or effect is missing. With this step the game plays from start to the credits.

The C names are the decomp's (US). Each line number is in the file its table names.

## 0. How to work on it

- **One field part for the props.** The dirt cart, dirt pile, boulder, Toy Town boxes, gearbox and Angemon pedestal are all `loadStaticTMD` + `drawObject` objects of `map_object.c`. In the port they are one field part, `MapProps`: logic (positions, matrices, timers) plus a view (the TMD models). It is built like `MapChests`.
- **Reuse.**
  - `Fade` (black) gains the white mode.
  - `MapOverlays` already moves sprites (`store_positions`, `move`).
  - `HealingParticles` has `renderFXParticle`.
  - `DooaScene` has the wireframe and `EFECreateFlash`.
  - `PaletteFade` does CLUT fades.
  - `MoviePlayer` plays movie 3.
  - The interpreter's `call_digimon_routine` / `_call_routine` pattern (clear the sync bit, the scene sets it again) carries the new scenes.
- **Every value has its C line** (§3) or is marked `port-only` / `stand-in` (`docs/porting_checklist.md`).
- **Data, not ids.** The routines are tied to maps only by the scripts that call them; no code checks a map id. Each prop's model path is a constant with its C line, like `MapChests`' `TAKA.TMD`.

## 1. The C code and where it runs

The call sites come from the exported scripts (`asset_porter/output/scripts/DG/script_<map>.txt`, 2026-11-02).

| Event | C | Called by | Maps (script) |
|---|---|---|---|
| Dirt cart | `loadDirtCartModel` (`map_object.c:423`), `setDirtCartModel` (1186), `renderDirtCartModel` (1232) | routines 0x1A, 0x13 | Drill Tunnel TUNN02, TUNN06 (25, 29) |
| Dirt pile | `loadDirtPileModel` (1205), `decreaseDirtPileSize` (1109), `renderDirtPile` (435) | routines 0x1B, 0x14 | TUNN06 (29) |
| Boulder | `spawnBoulder` (616), `moveBoulder` (1130), `renderBoulder` (648); `script_interp.c:2129–2142` | opcodes 0x76 / 0x77 / 0x78 | Lava Cave TUNN07 (30) |
| Toy Town boxes | `spawnToyTownBoxes` (662), `renderToyTownBoxes` (708), `openToyTownBox` (1148) | routines 0x2B, 0x2C | Costume House OMOC02 (145) |
| Gearbox | `spawnGearbox` (749), `renderGearbox` (767) | routine 0x29 | Volume Villa GKYO01 (140) |
| Volume Villa's CLUT source | `somethingToyTown` (1156) → `readMapTFS(0x92)` (`map.c:4217`) | routine 0x2A | GKYO01 (140) |
| Angemon's pedestal | `spawnAngemonPedestal` (775), `renderAngemonPedestal` (794), `moveAngemonPedestal` (1167); tick case 50 (`script_interp.c:506`) | routines 0x31, 0x32 | Freezeland FRZL06 (93) |
| White fade | `fadeToWhite` / `fadeFromWhite` (`fade.c:170`, 193), `renderFade` (144) | routines 0x2D, 0x2E | Ogre Fortress OGRE03 (48), Ice Sanctuary ICSA02 (98), File City TWNB05 (184) |
| Meramon's shake | `createMeramonShake` / `tickMeramonShake` (`map.c:5472`, 5482) | routine 0x22 | Lava Cave TUNN08 (31) |
| Ninjamon's effect | `createNinjamonEffect` / `renderNinjamonEffect` (`overworld.c:777`, 801) | routine 0x26 | Digimon Bridge MAYO08B (10) |
| Monochromon's mood | `createMonochromonMoodBubble` (`script_common.c:3038`), `renderMonochromonMoodBubble` (1220) | routine 0x1C | File City TWNB20–23 (199–202) |
| Machinedramon's build-up | `EAB_startBuildup` (`eab/eab.c:649`), rings 219–341 | routine 0x33 (load), 0x28 (start, entity script id 5) | File City TWNB05 (184) |
| Machinedramon's spawn | `EAB_tick` (670), `EAB_tickSpawn` (349); `tamerTickMachinedramonSpawn` (`tamer.c:1718`, state 18) | digimon routine 8 (`partner.c:1189`) | TWNB05 (184) |
| The ending | `ENDI_tickEnding` (`endi/endi.c:407`), `ENDI_updateEnding` (159); `tamerTickEnding` (`tamer.c:1682`, state 16) | routine 0x34 (load), 0x35 (start); digimon routine 6 | File City TWNB13 (192); the debug room ROOM14 (209) |
| Then the credits | tick case 53 (`script_interp.c:516`): `MAIN_STATE = 3`; `main.c:3522–3527`: `cleanupGame`, `playMovie(3, 1)`, back to the title | after routine 0x35 | |
| The opening | digimon routine 5 → tamer state 15, `tamerTickOpening` (`setMapLayerEnabled(1)`) | digimon routine 5 | ROOM14 (209, debug menu only) |

Routine 0x24 (`readMapTFS(CURRENT_SCREEN_ID)`) is called by no script.

**The story path to the credits** (script 184, section 0x33): START_BATTLE, routine 0x33 (loads `BOSS_EFE.TMD`), routine 0x28 (the build-up on entity script id 5), digimon routine 8 (the spawn), START_BATTLE (Machinedramon), routine 0x2D (to white), WARP_TO 236 / 237. Then script 192, section 0x33: routine 0x34, the farewell scene, routine 0x35 (the ending), then the credits.

## 2. What the player sees

- **Drill Tunnel:**
  - The partner pushes a cart (`DOSYA.TMD`) or carries a box (`HAKO.TMD`) in front of it, turning with it.
  - In TUNN06 a dirt pile (`T_YAMA.TMD`) shrinks a step each time Drimogemon's scene digs. It is gone once it is under 6/15 of its size.
- **Lava Cave:**
  - A boulder (`IWA.TMD`, `IWA1.TIM`) appears, rolls (pitching 10 units a frame) as the script moves it, then disappears.
  - In TUNN08 the screen shakes sideways for 10.5 s (Meramon).
- **Costume House:** a big and a small box. Choosing one opens its lid (it swings 90° over 11 frames).
- **Volume Villa:** a gearbox (`GAND.TMD`) stands by the path.
- **Freezeland:** a pedestal (`ABOX.TMD`) slides 500 units away, shaking ±5 sideways, over 50 frames.
- **Ogre Fortress, Ice Sanctuary, File City:** the screen fades to white and back. The game time keeps running.
- **Digimon Bridge:** the map's sprites (0–0x28) streak to the right for 3 s, then vanish.
- **File City, Monochromon's shop:** a mood bubble (one of 5 faces, 32×32) pops up and grows over a Digimon's head for 1.5 s.
- **Machinedramon** (File City, the end of the story):
  - **Build-up:** flat rings swell and shrink round a point, three at a time, new ones every 6 frames.
  - **Spawn:** the screen goes black (a subtractive full-screen quad, then fading back over 32 frames). Everything but Machinedramon is hidden, the map too, against a black backdrop (§8.3). It materialises from a wireframe while the camera swings round it, green line-squares spread from its feet, and rings pulse. After 16 s the map comes back and the battle starts.
- **The ending:** the tamer fades to black and turns translucent while sparks rise from his bones. He shrinks, then grows, and the sparks fly up. Then the credits movie plays, and the title screen follows.

## 3. The values

### 3.1 Props (`map_object.c`)

| # | Name | Line | Value | Status |
|---|---|---|---|---|
| P1 | `DIRT_CART_TMD`, `DIRT_CART_BOX_TMD` | 73, 74 | `ETCNA/DOSYA.TMD` (model 0), `ETCNA/HAKO.TMD` (model 1) | |
| P2 | `ACTIVE_DIRT_CART_MODEL` after load | 430 | 2 (none drawn) | |
| P3 | Cart place | 1232–1270 | partner's location + RotMatrix(partner rotation) · (0, 0, `radius` + 100); rotation = the partner's. `radius` is the Digimon's `DIGIMON_DATA.radius` | |
| P4 | US quirk | 1240 | `rotation = DIRT_CART_ROTATION` is compiled out in US (an unused local) | nothing to port |
| P5 | `DIRT_PILE_TMD`, `DIRT_PILE_LOCATION` | 76, 75 | `ETCNA/T_YAMA.TMD`, (2037, 0, 849), rotation 0 | |
| P6 | `DIRT_PILE_SIZE_COUNTER` | 69 | starts at 15 (static data). Each 0x14: −1, scale = counter · 0x1000 / 15 on all axes. **Never reset**: it lasts until the console is switched off, and it isn't in the save | session value (§4.1) |
| P7 | `renderDirtPile` | 437 | drawn while counter ≥ 6 | |
| P8 | `BOULDER_TMD`, `BOULDER_TIM` | 80, 81 | `ETCNA/IWA.TMD`, `ETCNA/IWA1.TIM` | |
| P9 | Boulder spawn | 630–635 | translation (−300, −500, 2000), rotation 0, scale 0x1000 | |
| P10 | `moveBoulder(dx, dz)` | 1137–1139 | **translation.vy += dx** (the first argument goes to y, a C quirk the port keeps), vz += dz, rotation.vx −= 10. Then the frame ends (`longjmp 2`) | |
| P11 | `BIG_BOX_TMD`, `SMALL_BOX_TMD` | 85, 86 | `ETCNA/BIGBOX.TMD`, `ETCNA/SMABOX.TMD`: object 0 = box, object 1 = lid (its coordinate's parent is the box's) | |
| P12 | `BIG_BOX_LOCATION`, `SMALL_BOX_LOCATION` | 83, 84 | (500, −600, 600), (−400, −400, 600) | |
| P13 | Lid | 712–735 | box `TOY_TOWN_SELECTED_BOX` (1 big, 2 small): its lid's rotation.vx −= 100 a frame, down to −0x400. Ticked in the render, so only while the map layer is on | |
| P14 | `openToyTownBox` | 1148 | `TOY_TOWN_SELECTED_BOX` = script value 0xFE | |
| P15 | `GEARBOX_TMD`, `GEARBOX_LOCATION` | 88, 87 | `ETCNA/GAND.TMD`, (−100, 0, 1700) | |
| P16 | `UNUSED_GEARBOX_VALUE` | 760 | 0x294, never read | nothing to port |
| P17 | `ANGEMON_PEDESTAL_TMD`, start | 90, 784–785 | `ETCNA/ABOX.TMD`; x 0, z 1500 | |
| P18 | `moveAngemonPedestal` | 1167–1183 | z += 10; x = 5 when z % 20 == 0, else −5; at z > 1999: z = 2000, done (the wait ends). The wait is CALL_ROUTINE 0x32's tick, case 50 (`script_interp.c:506`) | |
| P19 | Draw | `drawObject` 1070 | `GsSortObject4J(…, 2)`, lit (the light matrix from the object's LW). Each `render*` draws only while `MAP_LAYER_ENABLED` | |
| P20 | Removal | `unloadMapParts` 917–928 | on every map change: objects 0xFB3 (cart), 0xFB4 (pile), 0xFB6 (boulder), 0xFBD (boxes), 0xFBC (gearbox), 0xFBE (pedestal); opcode 0x78 removes 0xFB6 | |
| P21 | Id clash | `map.c:4307–4308`, 4577; `world_object.c:51` | `removeObject` matches id **and** instance. The daytime transition is object 0xFBE with instance = the new time of day (`map.c:4509`); the pedestal is 0xFBE instance 0. `updateTimeOfDay` (while a transition runs) and the transition's own end remove (0xFBE, target): with target 0 the search finds the pedestal first when its slot is lower, which it is when it spawned first (`stand-in`: the port assumes it always is). So a transition to time of day 0 while the pedestal is up removes the pedestal | §8.2 |

### 3.2 Screen effects

| # | Name | C | Value | Status |
|---|---|---|---|---|
| S1 | `fadeToWhite(n)` | `fade.c:170–189` | `FADE_DATA = n + 1`, `FADE_OUT_CURRENT = 1`, `FADE_MODE = 1`; US: a running fade object is removed first. **No** `stopGameTime`, **no** `FADE_PROTECTION` | |
| S2 | `fadeFromWhite(n)` | 193–202 | as `fadeFromBlack` with `FADE_MODE = 1` | |
| S3 | `renderFade` mode 1 | 144–165 | `GetTPage(0, 1, …)`: **additive** (abr 1); added at OT 10 instead of 1, so OT 0–9 (the HUD, the text boxes) stays on top | |
| S4 | The fades' length | routines 0x2D / 0x2E | script value 0xFE (scripts use 20 and 40) | |
| S5 | Meramon's shake | `map.c:5482–5500` | per frame `f` from 0: amplitude 1 (f < 0x1F), 2 (< 0x3D), 3 (< 0x79), 2 (< 0xB5), else 1; negated on even frames; `DRAWING_OFFSET_X += it` | |
| S6 | Its end | 5537–5541 | at frame 0xD2 (after 210 frames): both drawing offsets back to the values saved at the start | |
| S7 | Its quad | 5503–5530 | a growing subtractive quad (abr 2), colour `MERAMON_SHAKE_RED/GREEN/BLUE`, which are bss and never written (`map.c:2801`, no store in `map.s`): colour 0 subtracts nothing | nothing drawn (same picture) |
| S8 | Ninjamon | `overworld.c:777–835` | sprites 0..0x28 (0x29) of the map's overlay objects. Start: positions saved; per sprite dx = `randomLimit(10)` + 12, dy = `randomLimit(10)` + 3. Each frame: x += dx, y += dy, order value 10; when x > 0xA0: back to its saved place, new dx / dy. After 0x3C frames: every one gets flag 1 (hidden), done | |
| S9 | Monochromon bubble | `script_common.c:3038–3054` | entity = script value 0xF7, mood = script value 0xF8. Mood < 5 and the entity on the map: timer 0x1E, `u = mood · 32`, object added. Mood ≥ 5: removed | |
| S10 | The sprite | 271–290 | 32×32, tpage (640, 0) 4-bit, `v` 0, CLUT (0, 486), pivot (16, 16), colour 0x80, attribute 0x50000000 | |
| S11 | Its draw | 1220–1250 | at `translateConditionFXToEntity` → `worldPosToScreenPos`; `o = 0x10 − (timer >> 1)`; y −= o; scale = o << 8 (1/16 → 1); OT depth >> 4; then the timer −1 down to 0. It stays (full size) until mood ≥ 5 or a map change | |

### 3.3 Machinedramon (`eab/eab.c`)

| # | Name | Line | Value | Status |
|---|---|---|---|---|
| E1 | Model | `script_interp.c:157`, 1842 | `ETCHI/BOSS_EFE.TMD` object 0. `EAB_setModelColor` (159) sets the flat colour of its prims 0x2D / 0x2F to `EAB_D_800616DC` (0x3C, 0x3C, 0x3C) | |
| E2 | Build-up | 649–668, 187–199 | the entity (script id 5) is hidden (`isOnMap = 0`); sound (8, 0); `frame = (frame + 1) % 18`, a ring when `frame % 6 == 0`; at most 3 rings | |
| E3 | Build-up ring | 241–274 | 0x12 frames; xz scale `lerp(0x10B8, 0x614, 1, 0x12, t)`; y scale `sin(lerp(0, 0x80, 1, 0x12, t)) · 0xC3C / 4096 + 0x15C`; rotation (0, 0x800, 0); at the entity's location | |
| E4 | Spawn start | 670–706 | Sound (8, 1). Nine `EFECreateFlash` at `EAB_D_8006170C[i]` (xyz, last value 0x1400), args 0x22, 0x32, 0, colours 0x14 → 0xFF | |
| E5 | Phase 0 | 365–383 | from frame 0x2D: a white flash quad (E9). At 0x32: phase 1. Setup: entity on the map, animation 0x21; every entity but entity 2 hidden (their state saved); map layer off; viewpoint saved; the build-up removed; sound stopped, `playSound2(8, 2)`; the entity's `vabId = 5` | |
| E6 | Phase 1 | 384–444 | Each frame: a spawn ring (E7). At 0xD2: animation 0x33, looping (353–356). Frames 0x32–0x52: a flash, grey `lerp(0xFF, 0, 0x32, 0x52)`. A particle when `EAB_D_8006179C[frame % 18]` ≠ 0 (E8). The white backdrop (E10). Frames 0x32–0x122: `ENTITY1_WIREFRAME_TOTAL = 0x10 − sin(lerp(0x80, 0, 0x32, 0x122)) · 16 / 4096` (`model.c:2922`: entity 2 drawn as a wireframe). Camera: E11 | |
| E7 | Spawn ring | 298–329 | 9 frames; xz `lerp(0x16CC, 0x10B8, 1, 0x12, t)`; y `sin(lerp(0, 0x80, 1, 0x12, t)) · 0x2B8 / 4096 + 0xAE`; rotation (0, 0x800, 0) | |
| E8 | Particles | 461–468, 513–538, 579–647 | Up to 100, 0x56 frames. A square of 4 `LINE_F2` lines at the entity's location, half-size `lerp(8, 0x9C4, 0, 0x56, t)`, OT 0xF9F. Colour fades to 0. Green = `lerp(0x32, 0xE6, 1, 5, EAB_D_8006179C[f % 18])` · `sin(lerp(0, 0x80, 0x32, 0x122, f))` / 4096; r = 0x0A, b = 0x0A (`MAIN_D_80134C3C`). Edges with a corner's OT depth outside (0x20, 0x1000) are skipped | |
| E9 | Flash quad | 471–486 | full screen, abr 2 (subtractive: at 0xFF the screen goes black) on the texel (832, 256) u 0 v 0x80, CLUT (0, 487), colour = the value, OT 0xA | |
| E10 | Backdrop | 540–557 | full screen, the same texel and mode, colour (0xFF, 0xFF, 0xFF), OT 0xFA0 (behind the entity) | §8.3 |
| E11 | Camera orbit | 412–432, 559–577 | yaw `lerp(0x71C, 0x171C, 0x32, 0x122)` + the entity's yaw (then 0x171C); distance `lerp(0xDAC, 0xBB8, 0x32, 0x140)`; height `lerp(0x258, 0x32, 0x32, 0x140)`; target = bone 0 − (0, 0x64, 0); eye = target + RotMatrixZYX(0, yaw, 0) · (0, 0, distance) − (0, height, 0). Frame 0x13F: the saved viewpoint | |
| E12 | Phase 2 | 434–458 | At 0x140: particles removed, map layer on, entities shown again, viewpoint restored, sound stopped, `playSound(8, 3)`. Spawn rings until 0x14A. At 0x154: rings removed, `frame = −1`, so `tamerTickMachinedramonSpawn` sets the sync bit | |

### 3.4 The ending (`endi/endi.c`)

| # | Name | Line | Value | Status |
|---|---|---|---|---|
| N1 | Start | 407–431 | entity 0 (the tamer). `ENDI_downloadClut` (VRAM (0, 488) 16×24: 384 colours, the tamer's CLUTs), then `ENDI_setClutStp` (STP bit on every non-black colour) and `ENDI_setModelSemiTrans` (prims 0x34 / 0x3C get semi-transparency; tpage abr → 1, additive). Shadow off (`PLAYER_SHADOW_ENABLED = 0`); sound (8, 0) | |
| N2 | Phase 0 | 172–179 | frames 0–60: every colour `c · (60 − f) / 60` (integer per 5-bit channel); colour 0 loses STP (transparent). A particle a frame on bone `f % (boneCount − 1) + 1` | `PaletteFade` stand-in as `specs/death_scene.md` §4.9 |
| N3 | Phase 1 | 180–198 | a particle a frame; scale `lerp(0x1000, 0x999, 60, 78, f)`, then `lerp(0x999, 0x1800, 78, 80, f)`. At 80: sound (8, 1), the particles detached (positions fixed in the world, relative to bone 0's), velocity −450 | |
| N4 | Phase 2 | 199–208 | particles' base y += velocity; velocity += 20; at ≥ 0 (23 frames): phase 3 | |
| N5 | Phase 3 | 209–215 | sound stopped, particles removed, `frame = −1`, so `tamerTickEnding` sets the sync bit | |
| N6 | Particles | 280–300, 368–405 | 80 max. Offset `rand() % 140 − 70`, `rand() % 80 − 40`, `rand() % 80 − 40` from the bone, scaled by the entity's scale. Each frame colour `rand() % 70 + 60` per channel, size `rand() % 15 + 15`, `renderFXParticle` | |
| N7 | Release quirk | 313–317 | `ENDI_DATA.base` takes bone 0's `t[1], t[2], t[3]` (y, z, and one past the array) as x, y, z: the base is shifted | §8.4 |
| N8 | After | `script_interp.c:516–520`, `main.c:3522–3527` | the routine's wait (case 53) sees the sync bit: `MAIN_STATE = 3`. The game loop ends, `cleanupGame`, `playMovie(3, 1)`, then the boot loop again (landing screen, title) | |

### 3.5 Volume Villa's CLUT source

| # | Name | C | Value | Status |
|---|---|---|---|---|
| V1 | `somethingToyTown(box)` | `map_object.c:1156–1164` | `TOY_TOWN_SELECTED_BOX = box`; when box 0 and trigger 350: `readMapTFS(0x92)` (Robot House OMOC03's TFS into `GENERAL_BUFFER`) | |
| V2 | Its effect | `map.c:4233–4241`, 4301–4325 | `setupMap` keeps pointers into that buffer (`MAP_CLUTS[0..2]`, the day / evening / night CLUTs). `updateTimeOfDay` reloads CLUT row 480 from them, so after V1 Volume Villa's background takes OMOC03's CLUTs at the next time-of-day update | §8.1 |

## 4. Behaviour (the port)

### 4.1 `MapProps`

- **The logic** (`scripts/field/map_props.gd`, class `MapProps`, no nodes) holds:
  - `cart_model` (0, 1, 2);
  - the pile's counter;
  - the boulder's translation and rotation;
  - the box lids and the selected box;
  - the pedestal's x / z;
  - each prop's "loaded" flag.

  Its API names the C functions (the exact signatures are in §4.1.1): `load_dirt_cart()`, `set_dirt_cart_model(m)`, `load_dirt_pile()`, `decrease_dirt_pile()`, `spawn_boulder()`, `move_boulder(dx, dz)`, `despawn_boulder()`, `spawn_toy_town_boxes()`, `open_box(b)`, `set_box(b)` (0x2A), `spawn_gearbox()`, `spawn_pedestal()`, `move_pedestal() -> bool`, `unload()` (`unloadMapParts`), `tick_render(map_layer_on)` (the lids), and per prop `transform(name) -> PackedInt32Array` (the PSX matrix).
- **The pile's counter** is a session value: it is not saved and resets only at boot. `GameState` gets a `session` dictionary for values the C keeps in static data. `port-only` placement, C behaviour.
#### 4.1.1 The logic's API (step 1)

`class_name MapProps extends RefCounted`. Matrices are `PsxMath` 3×4 matrices (`PackedInt32Array`, 9 rotation entries then the translation), built with `PsxMath.rot_matrix` / `scale_matrix` / `trans_matrix` as the C builds them. Props are named by `StringName`: `&"cart"`, `&"pile"`, `&"boulder"`, `&"big_box"`, `&"big_lid"`, `&"small_box"`, `&"small_lid"`, `&"gearbox"`, `&"pedestal"`.

- `_init(session: Dictionary)`: the pile's counter lives in `session["dirt_pile_size"]`, 15 when absent (P6). The field is `session`.
- `const MODELS := {&"cart": "tmd_files/ETCNA/DOSYA.gltf", &"cart_box": "tmd_files/ETCNA/HAKO.gltf", &"pile": …T_YAMA, &"boulder": …IWA, &"big_box": …BIGBOX, &"small_box": …SMABOX, &"gearbox": …GAND, &"pedestal": …ABOX}` (P1, P5, P8, P11, P15, P17; the lids are object 1 of their box's model). `const BOULDER_TEXTURE := "ETCNA/IWA1.TIM"` (P8).
- State fields: `cart_model` (int, P2), `boulder_translation` / `boulder_rotation` (`Vector3i`), `selected_box` (int, P14), `big_lid` / `small_lid` (int, P13), `pedestal_x` / `pedestal_z` (int, P18), `loaded: Dictionary` (prop group → bool; groups `&"cart"`, `&"pile"`, `&"boulder"`, `&"boxes"`, `&"gearbox"`, `&"pedestal"`).
- `load_dirt_cart()`: loaded, `cart_model = 2`. `set_dirt_cart_model(m)`.
- `load_dirt_pile()`. `decrease_dirt_pile()`: counter −1 (`int8_t`: wraps −128 → 127). `dirt_pile_size() -> int`.
- `spawn_boulder()` (P9). `move_boulder(dx, dz)` (P10; both arguments `int16_t`, the rotation an `SVECTOR` `int16_t`). `despawn_boulder()` (opcode 0x78).
- `spawn_toy_town_boxes()`: loaded, lids 0, `selected_box` 0. `open_box(b)` (P14). `set_box(b: int, trigger_350: bool) -> bool` (V1): sets `selected_box`, returns `b == 0 and trigger_350` (the caller reloads the TFS, step 7).
- `spawn_gearbox()`: loaded, `selected_box = 0` (`map_object.c:754`).
- `spawn_pedestal()` (P17). `move_pedestal() -> bool` (P18).
- `unload()` (P20): every group unloaded; the state values stay (the C only removes the objects).
- `on_daytime_removal(target: int) -> bool` (P21): when `target == 0` and the pedestal is loaded, unloads it and returns true (the transition's own object then survives); else false.
- `tick_render(map_layer_on: bool)` (P13): the lid of `selected_box` −100, floor −0x400, only while the map layer is on.
- `drawn(prop) -> bool`: its group is loaded, and for `&"cart"` `cart_model != 2`, for `&"pile"` the counter ≥ 6 (P7). The map layer is the view's (P19).
- `transform(prop) -> PackedInt32Array` (not the cart):
  - pile: `trans_matrix(scale_matrix(rot_matrix(0), s), (2037, 0, 849))`, `s` = counter · 0x1000 / 15 (C division, truncating; stored `int16_t`) on all axes;
  - boulder: `trans_matrix(scale_matrix(rot_matrix(rotation), 0x1000), translation)` (`projectPosition`, 639; called at 633 and 1143);
  - big_box / small_box: identity with the box's location (P12);
  - big_lid / small_lid: `rot_matrix((lid, 0, 0))`, translation 0, relative to its box;
  - gearbox: identity at (−100, 0, 1700);
  - pedestal: identity at (`pedestal_x`, 0, `pedestal_z`).
- `cart_transform(location: Vector3i, rotation: Vector3i, radius: int) -> PackedInt32Array` (P3): `m = rot_matrix(rotation)`; `w = apply_matrix_lv(m, (0, 0, radius + 100))`; `w.x += location.x`, `w.z += location.z` (**y is not**: the cart's height is the rotated offset's alone, 1260–1261); the result is `trans_matrix(m, w)`.

**Shared buffers (`port-only`).** The C draws the pile, boulder, gearbox and pedestal through one object (`GENERAL_OBJECT3`), and the cart and the small box through `GENERAL_COORDS[0..1]`. The port keeps each prop's state apart: no script loads two of them on one map (§1: each is on its own map), and every map change unloads them.

- **The view** (`scenes/field/map_props.tscn`, `scripts/field/map_props_view.gd`): one `Content.load_model` per prop, placed from `transform()`, hidden while the map layer is off (`map_layer_nodes`). The cart follows the partner each frame (P3).
- **The interpreter:** routines 0x13, 0x14, 0x1A, 0x1B, 0x29, 0x2A, 0x2B, 0x2C, 0x31, 0x32 (tick: `move_pedestal`) and opcodes 0x76–0x78 call `MapProps` through a `props` field. 0x13, 0x14 and 0x77 end the frame (`longjmp 2`). They leave `ROUTINE_WAITS` / `UNPORTED` when the field is there.
- **The map change** calls `unload()` (P20). P21 is kept: `Clock`'s time-of-day update calls `props.on_time_of_day()`, which drops the pedestal while it is loaded.

### 4.2 The screen effects

- **`Fade.fade_to_white(n)` / `fade_from_white(n)`** set `mode = 1`: additive, no clock stop, no protection. Drawn on the layer under the text boxes (OT 10 vs 1: `port-only` layer choice, the same order). Routines 0x2D / 0x2E with script value 0xFE.
- **`MeramonShake`** (logic, `scripts/field/meramon_shake.gd`): `tick() -> int` returns the frame's x step (S5) and ends at 0xD2. `FieldMap` gets `offset_shake: Vector2` (`port-only` name), added in `drawing_offset()` and to the camera's projection centre, and reset at the end (S6). No quad (S7).
- **`NinjamonEffect`** (`scripts/field/ninjamon_effect.gd`): drives `MapOverlays` sprites 0..0x28 as in S8, through `store_positions` / `move` / `set_flag`, rolling `Rng.random_limit`.
- **`MoodBubble`** (`scripts/field/mood_bubble.gd`, a canvas piece like `ConditionBubbles`): S9–S11, at the entity's condition-FX point (`BattleEffectContext.condition_fx_position`'s field twin, or the bone offset `GameData.condition_fx_offset`), sorted by depth.

### 4.3 Machinedramon

`EabScene` (logic, `scripts/field/eab/eab_scene.gd`) holds the timelines E2–E12: frames, phases, rings, particles, colours, the camera's eye / target, the wireframe total. `EabView` draws:
- the rings (`BOSS_EFE.gltf` object 0, untextured, flat grey 0x3C);
- the flash and backdrop quads;
- the particles' lines;
- the wireframe on entity 2 (`DooaScene`'s wireframe draw, entity 2's instead of the partner's).

The nine flashes go through the death scene's `EFECreateFlash` port. `TamerHost` / the interpreter: digimon routine 8 sets tamer state 18 and partner state 11, clears the sync bit, and the scene sets it again (as routines 7 / 9). Routines 0x33 / 0x28 load the model and start the build-up on script entity 5.

### 4.4 The ending and the credits

`EndingScene` (logic, `scripts/field/ending/ending_scene.gd`): N1–N7.

The view:
- the tamer's palette fade (`PaletteFade` on the tamer, with the STP rule: black texels become transparent);
- the tamer drawn additive (N1);
- scale on the tamer node;
- the particles through `HealingParticles`' `renderFXParticle` draw.

Digimon routine 6 and routine 0x35 set tamer state 16. Routine 0x35's wait (case 53) sees the sync bit and asks the game to end the field: `Game` frees the field, plays movie 3 (not skippable), then shows the title (`main.c` loop). Digimon routine 5 (debug menu only) sets tamer state 15: map layer on, sync bit set.

## 5. Godot design (files)

| Part | Files |
|---|---|
| Props | `scripts/field/map_props.gd`, `scripts/field/map_props_view.gd`, `scenes/field/map_props.tscn`; `scripts/field/field.gd` (wiring); `scripts/state/game_state.gd` (`session`) |
| Interpreter | `scripts/script/script_interpreter.gd` (the routines and opcodes) |
| Screen effects | `scripts/field/fade.gd`, `scripts/field/meramon_shake.gd`, `scripts/field/ninjamon_effect.gd`, `scripts/field/mood_bubble.gd`, `scripts/field/field_map.gd` (`offset_shake`) |
| Machinedramon | `scripts/field/eab/eab_scene.gd`, `eab_view.gd`, `scripts/field/tamer.gd` (state 18), `scripts/field/hosts/` (wiring) |
| Ending | `scripts/field/ending/ending_scene.gd`, `ending_view.gd`, `scripts/field/tamer.gd` (states 15 / 16), `scripts/game/game.gd` (end → movie 3 → title) |

## 6. Order of work

All suites and scans pass after every step; a step is done when its gate in §7 passes.

| Step | What | Complexity · Model | Delegate? |
|---|---|---|---|
| 1 | `MapProps` logic (§3.1, §4.1 logic): positions, matrices, lids, pedestal, pile counter, `unload`, the time-of-day clash | **Low** · Gemini 3.8 Flash (High): numbers only, one file, the tests decide | **agy** |
| 2 | `MapProps` view and wiring: the models, map layer, cart following the partner, the interpreter's routines / opcodes, map change, `GameState.session` | **Medium** · Claude Sonnet 5.5 (Medium), or agy with a precise brief: several files, the tests cover the wiring, an in-game look covers placement | **agy** (brief lists every hook) |
| 3 | Screen-effect logic: `MeramonShake`, `NinjamonEffect`'s maths, the bubble's timer / scale, the white fade's counters (S1–S11) | **Low** · Gemini 3.8 Flash (High) | **agy** |
| 4 | Screen-effect views and wiring: `Fade` white (additive layer), `FieldMap.offset_shake`, the overlays, `MoodBubble` drawing, the routines | **Medium**: rendering is simple (a fade, a sprite, an offset), the tests check the state | agy or Sonnet; **agy** if step 2 went well |
| 5 | Machinedramon (§3.3, §4.3): `EabScene` logic **Medium**, the view **Hard** (rings, quads, lines, wireframe, camera, hidden entities) | **Hard** · main session (Opus) | no |
| 6 | The ending and credits (§3.4, §4.4): `EndingScene` **Medium**, the view and the CLUT/STP fade **Hard**, the `Game` end path **Medium** | **Hard** · main session | no (the `Game` path could be split off to agy) |
| 7 | Volume Villa's CLUT source (§3.5), after §8.1 is decided | **Hard** (background palettes) · main session | no |
| 8 | VERIFY "Map events", PLANS, "As built", gates | main session | no |

Steps 1–4 can run before 5–6, and 1 and 3 in parallel (they own different files). The story reaches the credits after step 6.

## 7. Tests (acceptance checks, written before each step; gate `DW_STEP_4F=<step>`)

`tests/test_map_events.gd` (`-s`, with `GameData`; the field-bound checks go in a scan scene like `arena_scan`):
- **Step 1:**
  - every P row (positions, scale per counter, the counter's floor of 6, `move_boulder`'s y quirk, the lid's 11 frames to −0x400, the pedestal's 50 frames and its ±5);
  - `unload` clears all;
  - the time-of-day clash drops the pedestal.
- **Step 2:**
  - a script stub calling each routine / opcode reaches `MapProps`; 0x13 / 0x14 / 0x77 end the frame; 0x32 waits until done;
  - the routines are gone from the unported reports;
  - a map change unloads;
  - the cart's world transform for a given partner position, yaw and radius;
  - in the scan: Drill Tunnel's and Costume House's sections run with the props drawn.
- **Step 3:**
  - the shake's 210 steps (sum 0, the amplitude per range), the offsets restored;
  - Ninjamon with a seeded `Rng`: positions after 1 / 2 frames, a wrap, all hidden at 0x3C;
  - the bubble's scale and y offset per timer, mood ≥ 5 removes;
  - white fade counters, no clock stop.
- **Step 4:** the routines reach the pieces; the fade's blend is additive; `FieldMap.drawing_offset()` follows the shake.
- **Step 5:** E2–E12 frame by frame (ring scales, flash levels, particle colours, wireframe total, camera eye / target at chosen frames, phase changes, the sync bit at 0x154), entity visibility saved and restored.
- **Step 6:** N2–N5 (the colour factor per frame, the scale curve, release at 80, velocity to 0, the end), the sync bit, `Game` playing movie 3 then the title.

## 8. Open questions

1. **Volume Villa's CLUTs (§3.5).** After trigger 350, does the original Volume Villa's background change colours at the next hour (OMOC03's CLUTs)? If the CLUTs are the same or the change is visible and intended, port it (step 7). If it looks broken in the original, keep it and note it. Needs the user to check the original game.
2. **The pedestal and the time of day (P21).** Kept as in the C. Seen only if the hour changes during Freezeland's pedestal scene.
3. **EAB's flash and backdrop (E9, E10)** are subtractive (abr 2) at colour 0xFF on the texel at (832, 256) u 0 v 0x80, CLUT 487: if that texel is white, the screen goes black (flash) and the background behind Machinedramon is black (backdrop at OT 0xFA0). Step 5 reads the texel from the VRAM dump to confirm; the port follows the C either way.
4. **ENDI's base (N7)** reads `t[1..3]` (one past the translation): the detached sparks are offset. The port keeps it with `t[3]` = the next word of the C's `MATRIX` (`port-only` value 0 if unknown). To confirm in the original.
5. **Movie 3** is the credits (`movies.json`); `MoviePlayer` must not let Start skip it (`specs/new_game.md`).
