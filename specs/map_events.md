# Map events and the ending (step 4f)

Status (2026-11-02): **built** (steps 1-6 and 8; 7 dropped; "As built" at the end, VERIFY "Map events and the ending"). Approved 2026-11-02. The open questions (§8) stay open: the port does what the C reads, and the user checks in the game later. This is step 4f of `PLANS.md`, from the gap analysis after 4e-4. The scripts' remaining builtins and opcodes run as no-ops today (`ScriptInterpreter.UNPORTED` / `ROUTINE_WAITS`), so the story goes on, but the scene or effect is missing. With this step the game plays from start to the credits.

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

The call sites come from the exported scripts (`asset_porter/output/scripts/DG/script_<id>.txt`, 2026-11-02). A script id is **not** a map id: `scripts/index.json` gives the script each map's MAPHEAD section sets (`SET_SCRIPT`), and a few scripts are only reached by another's `JUMP_TO_FILE` (corrected 2026-11-02; the first draft took script ids for map ids).

| Event | C | Called by | Maps (script) |
|---|---|---|---|
| Dirt cart | `loadDirtCartModel` (`map_object.c:423`), `setDirtCartModel` (1186), `renderDirtCartModel` (1232) | routines 0x1A, 0x13 | Drill Tunnel TUNN01 (script 25), Underground Pond TUNN05 (29) |
| Dirt pile | `loadDirtPileModel` (1205), `decreaseDirtPileSize` (1109), `renderDirtPile` (435) | routines 0x1B, 0x14 | Underground Pond TUNN05 (29) |
| Boulder | `spawnBoulder` (616), `moveBoulder` (1130), `renderBoulder` (648); `script_interp.c:2129–2142` | opcodes 0x76 / 0x77 / 0x78 | Drill Tunnel 2nd floor TUNN06 (30) |
| Toy Town boxes | `spawnToyTownBoxes` (662), `renderToyTownBoxes` (708), `openToyTownBox` (1148) | routines 0x2B, 0x2C | Toy Mansion OMOC08 (145) |
| Gearbox | `spawnGearbox` (749), `renderGearbox` (767) | routine 0x29 | Robot House OMOC03 (140) |
| Robot House's TFS reload | `somethingToyTown` (1156) → `readMapTFS(0x92)` (`map.c:4217`) | routine 0x2A | Robot House OMOC03 (140) |
| Angemon's pedestal | `spawnAngemonPedestal` (775), `renderAngemonPedestal` (794), `moveAngemonPedestal` (1167); tick case 50 (`script_interp.c:506`) | routines 0x31, 0x32 | Ice Sanctuary ICSA01 (93) |
| White fade | `fadeToWhite` / `fadeFromWhite` (`fade.c:170`, 193), `renderFade` (144) | routines 0x2D, 0x2E | Ogre Fortress OGRE03 (48), Ice Sanctuary ICSA06 (98), Mt. Infinity MGEN99 (184) |
| Meramon's shake | `createMeramonShake` / `tickMeramonShake` (`map.c:5472`, 5482) | routine 0x22 | Lava Cave TUNN08 (31) |
| Ninjamon's effect | `createNinjamonEffect` / `renderNinjamonEffect` (`overworld.c:777`, 801) | routine 0x26 | Digimon Bridge MAYO08A (10) |
| Monochromon's mood | `createMonochromonMoodBubble` (`script_common.c:3038`), `renderMonochromonMoodBubble` (1220) | routine 0x1C | the Monochrome Shop GCAN11 (script 49 jumps to 199–202) |
| Machinedramon's build-up | `EAB_startBuildup` (`eab/eab.c:649`), rings 219–341 | routine 0x33 (load), 0x28 (start, entity script id 5) | Mt. Infinity MGEN99 (184) |
| Machinedramon's spawn | `EAB_tick` (670), `EAB_tickSpawn` (349); `tamerTickMachinedramonSpawn` (`tamer.c:1718`, state 18) | digimon routine 8 (`partner.c:1189`) | MGEN99 (184) |
| The ending | `ENDI_tickEnding` (`endi/endi.c:407`), `ENDI_updateEnding` (159); `tamerTickEnding` (`tamer.c:1682`, state 16) | routine 0x34 (load), 0x35 (start); digimon routine 6 | File City TEND01 / TEND02 (192); script 209 (jumped to from TWNA01's 164 and ROOM08's 178) |
| Then the credits | tick case 53 (`script_interp.c:516`): `MAIN_STATE = 3`; `main.c:3522–3527`: `cleanupGame`, `playMovie(3, 1)`, back to the title | after routine 0x35 | |
| The opening | digimon routine 5 → tamer state 15, `tamerTickOpening` (`setMapLayerEnabled(1)`) | digimon routine 5 | script 209 |

Routine 0x24 (`readMapTFS(CURRENT_SCREEN_ID)`) is called by no script.

**The story path to the credits** (script 184, section 0x33): START_BATTLE, routine 0x33 (loads `BOSS_EFE.TMD`), routine 0x28 (the build-up on entity script id 5), digimon routine 8 (the spawn), START_BATTLE (Machinedramon), routine 0x2D (to white), WARP_TO 236 / 237. Then script 192, section 0x33: routine 0x34, the farewell scene, routine 0x35 (the ending), then the credits.

## 2. What the player sees

- **Drill Tunnel (TUNN01) and Underground Pond (TUNN05):**
  - The partner pushes a cart (`DOSYA.TMD`) or carries a box (`HAKO.TMD`) in front of it, turning with it.
  - In TUNN05 a dirt pile (`T_YAMA.TMD`) shrinks a step each time Drimogemon's scene digs. It is gone once it is under 6/15 of its size.
- **Drill Tunnel 2nd floor (TUNN06):** a boulder (`IWA.TMD`, `IWA1.TIM`) appears, rolls (pitching 10 units a frame) as the script moves it, then disappears.
- **Lava Cave (TUNN08):** the 3D world shakes sideways for 10.5 s (Meramon).
- **Toy Mansion (OMOC08):** a big and a small box. Choosing one opens its lid (it swings 90° over 11 frames).
- **Robot House (OMOC03):** a gearbox (`GAND.TMD`).
- **Ice Sanctuary (ICSA01):** a pedestal (`ABOX.TMD`) slides 500 units away, shaking ±5 sideways, over 50 frames.
- **Ogre Fortress (OGRE03), Ice Sanctuary (ICSA06), Mt. Infinity (MGEN99):** the screen fades to white and back. The game time keeps running.
- **Digimon Bridge (MAYO08A):** the map's sprites (0–0x28) streak to the right for 3 s, then vanish.
- **The Monochrome Shop (GCAN11):** a mood bubble (one of 5 faces, 32×32) pops up and grows over a Digimon's head for 1.5 s.
- **Machinedramon** (Mt. Infinity MGEN99, the end of the story):
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

### 3.5 Robot House's TFS reload

| # | Name | C | Value | Status |
|---|---|---|---|---|
| V1 | `somethingToyTown(box)` | `map_object.c:1156–1164` | `TOY_TOWN_SELECTED_BOX = box`; when box 0 and trigger 350: `readMapTFS(0x92)`: map 0x92 = 146 = OMOC03, the Robot House itself (script 140 runs there): its own TFS read again into `GENERAL_BUFFER` | |
| V2 | Its effect | `map.c:4233–4241`, 4301–4325 | `setupMap` keeps pointers into that buffer (`MAP_CLUTS[0..2]`, the day / evening / night CLUTs) that `updateTimeOfDay` reloads row 480 from. The same file read into the same buffer gives the same CLUTs: nothing changes on screen (it restores the buffer if something used it meanwhile) | nothing to port (§8.1) |

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

- **The view** (`scripts/field/map_props_view.gd`, built in code like `MapChests`): one `Content.load_model` per prop, placed from `transform()`, hidden while the map layer is off (`map_layer_nodes`). The cart follows the partner each frame (P3).
- **The interpreter:** routines 0x13, 0x14, 0x1A, 0x1B, 0x29, 0x2A, 0x2B, 0x2C, 0x31, 0x32 (tick: `move_pedestal`) and opcodes 0x76–0x78 call `MapProps` through a `props` field. 0x13, 0x14 and 0x77 end the frame (`longjmp 2`). They leave `ROUTINE_WAITS` / `UNPORTED` when the field is there.
- **The map change** calls `unload()` (P20). P21 is kept: `Clock`'s time-of-day update calls `props.on_time_of_day()`, which drops the pedestal while it is loaded.

#### 4.1.2 The view and the wiring (step 2)

- **`Content.psx_transform(m: PackedInt32Array) -> Transform3D`** (`scripts/content/content.gd`): a PSX 3×4 matrix to Godot. The basis is `ArenaSceneView._godot_basis`'s (column j = (m[j], −m[3+j], −m[6+j]) · f[j] / 4096 with f = (1, −1, −1)); the origin is `psx_to_godot([m[9], m[10], m[11]])`. `ArenaSceneView` keeps its own copy (not touched in this step).
- **`MapPropsView`** (`scripts/field/map_props_view.gd`, `class_name MapPropsView extends Node3D`). Fields: `props: MapProps`, `partner: Node3D` (a `FieldDigimon`: `position`, `direction`, `radius`). `render()` once per game frame (the props' `render*` functions):
  1. `props.tick_render(visible)`: the map layer (P13, P19) is the view's `visible`, which `Field.map_layer_nodes()` turns off.
  2. Per group: a model is loaded the first time its group is loaded (`MapProps.MODELS`), and freed when the group is unloaded. The cart group has two models (`cart`, `cart_box`); the boxes group two (`big_box`, `small_box`), each with its lid as the model's `object_1` node.
  3. Each model's `visible` = `props.drawn(prop)`; for the cart group, `cart` shows only at `cart_model == 0` and `cart_box` only at 1.
  4. Placement: `transform = Content.psx_transform(props.transform(prop))`; a lid's `object_1.transform = Content.psx_transform(props.transform(&"big_lid"))` (relative to its box). The cart: `props.cart_transform(Vector3i(psx location), Vector3i(0, partner.direction, 0), partner.radius)`, the location being `(x, −y, −z)` of `partner.position` rounded.
  `node(prop: StringName) -> Node3D`: the model of `cart`, `cart_box`, `pile`, `boulder`, `big_box`, `small_box`, `gearbox` or `pedestal`; null when not loaded.
- **`GameState.session := {}`** (`scripts/state/game_state.gd`): values the C keeps in static data, never saved, kept across new games and loads (`port-only` place, C behaviour).
- **`MapSession`** (`scripts/field/hosts/map_session.gd`): `start_map_items()` also makes `map_props = MapProps.new(GameState.session)` and `map_props_view` (name `"MapProps"`, `props`, `partner`), added to `world`. `_load_map_at_exit` calls `map_props.unload()` with the items' and chests' clear (P20). The partner is set later than `start_map_items` (`field.gd:245`): the view reads `map_session.partner` through a `partner` set in `Field` after it (one line next to `map_session.partner = partner`).
- **`Field`** (`scripts/field/field.gd`): `scripts.map_props = map_session.map_props` next to `scripts.map_chests`; `map_layer_nodes()` adds `map_session.map_props_view`; `_frame()` calls `map_session.map_props_view.render()` right after `_field.overlays.tick()`.
- **`ScriptHost`** (`scripts/field/hosts/script_host.gd`): `var map_props: MapProps`, passed to `interpreter.map_props` next to `map_chests`.
- **`ScriptInterpreter`**: `var map_props: MapProps` (null: the routines and opcodes stay unported, as now). With it:
  - routine 0x13: `set_dirt_cart_model(read_pstat(0xFE))`, then STOP (`script_interp.c:1753–1756`); 0x14: `decrease_dirt_pile()`, STOP (1757); 0x1A `load_dirt_cart()` (1777); 0x1B `load_dirt_pile()` (1780); 0x29 `spawn_gearbox()` (1870); 0x2A `set_box(s8(read_pstat(0xFE)), game_state.is_trigger_set(350))` (1873), and when it returns true the TFS reload is reported once as unported (`"readMapTFS (step 7)"`); 0x2B `spawn_toy_town_boxes()` (1876); 0x2C `open_box(s8(read_pstat(0xFE)))` (1879); 0x31 `spawn_pedestal()` (1888);
  - routine 0x32: `active_instruction = OP_CALL_ROUTINE`, `textbox_mode = 0`, STOP (1770–1775); its wait (`_tick_waiting_instruction`) calls `map_props.move_pedestal()` each frame and ends when it returns true (case 50, 506–510);
  - opcode 0x76 (SPAWN_BOULDER): 1 byte, `spawn_boulder()`; 0x77 (MOVE_BOULDER): 1 byte, two `int16_t` x / z, `move_boulder(x, z)`, STOP; 0x78 (DESPAWN_BOULDER): 1 byte, `despawn_boulder()` (2129–2142).
- **P21:** `FieldMap` gets `signal daytime_transition_removed(palette: int)`, emitted in `set_time_of_day` when a daytime fade is running (`_transition_frame >= 0`), with the fade's target palette, before `_end_transition()`. That covers both C removals: the fade's end at frame 25 (`map.c:4577`) and `updateTimeOfDay` during a fade (4307). `MapSession` connects it to `map_props.on_daytime_removal(Clock.PALETTE.find_key(palette))` (palette → time of day).

### 4.2 The screen effects

- **`Fade.fade_to_white(n)` / `fade_from_white(n)`** set `mode = 1`: additive, no clock stop, no protection. Drawn on the layer under the text boxes (OT 10 vs 1: `port-only` layer choice, the same order). Routines 0x2D / 0x2E with script value 0xFE.
- **`MeramonShake`** (logic, `scripts/field/meramon_shake.gd`): `tick() -> int` returns the frame's x step (S5) and ends at 0xD2. `FieldMap` gets `offset_shake: Vector2` (`port-only` name), added in `drawing_offset()` and to the camera's projection centre, and reset at the end (S6). No quad (S7).
- **`NinjamonEffect`** (`scripts/field/ninjamon_effect.gd`): drives `MapOverlays` sprites 0..0x28 as in S8, through `store_positions` / `move` / `set_flag`, rolling `Rng.random_limit`.
- **`MoodBubble`** (`scripts/field/mood_bubble.gd`, a canvas piece like `ConditionBubbles`): S9–S11, at the entity's condition-FX point (`BattleEffectContext.condition_fx_position`'s field twin, or the bone offset `GameData.condition_fx_offset`), sorted by depth.

#### 4.2.1 The logic's API (step 3)

No drawing and no wiring (step 4). `int16_t` values wrap as in the C (`PsxMath.s16`).

- **`Fade`** (`scripts/field/fade.gd`) gains `var mode := 2` (`FADE_MODE`; `initializeFadeData`, `fade.c:69`, sets 2) and:
  - `fade_to_black` / `fade_from_black` also set `mode = 2` (`fade.c:81`, 97);
  - `fade_to_white(frames)` (S1): as `fade_to_black` (`_out_frames = frames + 1`, `out_current = 1`, `in_current = 0` as the port's black fade does for the removed render object), `mode = 1`; the clock and `protection` are untouched;
  - `fade_from_white(frames)` (S2): as `fade_from_black`, `mode = 1`;
  - `tick()` is unchanged: both modes share renderFadeOut / renderFadeIn (`fade.c:101–142`), so the end of a fade from white also clears `protection` (`fade.c:125`).
- **`MeramonShake`** (`scripts/field/meramon_shake.gd`, `class_name MeramonShake extends RefCounted`):
  - `start(offset: Vector2i)` (`createMeramonShake`, `map.c:5472`): `frame = 0`, `saved_offset = offset`, `done = false`;
  - `tick() -> int` (`tickMeramonShake`, 5482): the frame's x step (S5: amplitude by `frame`, negated when `frame` is even), then `frame += 1`; at `frame >= 0xD2`, `done = true` (S6: the caller then puts `saved_offset` back). Ticking when done returns 0. No quad (S7).
- **`NinjamonEffect`** (`scripts/field/ninjamon_effect.gd`, `class_name NinjamonEffect extends RefCounted`), S8:
  - `const COUNT := 0x29`;
  - `start(saved: Array)` (`createNinjamonEffect`, `overworld.c:777`): `saved` is `MapOverlays.store_positions(0, COUNT)` (Vector2i); `positions` = a copy; `frame = 0`, `done = false`; per sprite, in order, `dx[i] = Rng.random_limit(10) + 12`, then `dy[i] = Rng.random_limit(10) + 3`;
  - `tick() -> bool` (`renderNinjamonEffect`, 801): per sprite `positions[i] += (dx[i], dy[i])` (`int16_t`); when x > 0xA0, back to `saved[i]` and new `dx[i]`, `dy[i]` (rolled in that order). Then `frame += 1`; at `frame >= 0x3C`, `done = true`. Returns `done`. The caller writes the positions and order value 10 (`const ORDER := 10`) to the overlays, and on done sets flag 1 on the 0x29 sprites.
- **`MoodBubble`** (`scripts/field/mood_bubble.gd`, `class_name MoodBubble extends RefCounted`; the drawing is step 4's `MoodBubbleView`), S9–S11:
  - consts from `MONOCHROMON_BUBBLE_SPRITE` (`script_common.c:271–290`): `SIZE := 32`, `PIVOT := Vector2i(16, 16)`, `TPAGE := Vector2i(640, 0)` (4-bit), `CLUT := Vector2i(0, 486)`, `COLOR := 0x80`;
  - `create(entity_on_map: bool, mood: int)` (`createMonochromonMoodBubble`, 3038): mood is `& 0xFF`. Mood < 5: when the entity is on the map, `timer = 0x1E`, `u = mood * 32`, `instances += 1`. Mood ≥ 5: `instances -= 1` (not below 0). `addObject` doesn't check for a running bubble, so two calls without a removal run two render objects on the one sprite: the port keeps that count;
  - `render(entity_on_map: bool) -> Array` (`renderMonochromonMoodBubble`, 1220): empty when the entity is off the map (the C returns before the timer). Else once per instance: `offset = 0x10 − (timer >> 1)`, `scale = s16(offset << 8)`; append `{"offset": offset, "scale": scale}`; then `timer −= 1` unless 0. The caller draws each at the entity's condition-FX point, y − offset;
  - `clear()`: `instances = 0` (`port-only`, for tests; the C never removes the bubble on a map change: `unloadMap`, `map.c:4446`).

#### 4.2.2 The views and the wiring (step 4)

- **`Fade`'s drawing:** `_draw_progress` sets the material's `blend_mode` from `mode`: 1 → `BLEND_MODE_ADD` (S3, `GetTPage(0, 1, …)`: the texel, assumed white like the black fade's, added at `progress / 128`), 2 → `BLEND_MODE_SUB` (as now). The fade's place in the HUD stays (under the text boxes, as OT 10 is under OT 0–9; the port's black fade is there too: `port-only` layer, the same order for the white one).
- **`FieldMap.offset_shake: Vector2`** (`port-only` name for what Meramon's tick adds to `DRAWING_OFFSET_X`) and `set_offset_shake(v)`, which stores it and calls `_apply_scroll()`. `drawing_offset()` adds it in both branches (map view and scene view). The background doesn't move (it is drawn from the camera scroll, not the drawing offset); the 3D world and the overlay sprites do (`buildMapOverlayPrim` mode 0 adds `DRAWING_OFFSET_X`, `overworld.c:737–740`), which the frustum shift already gives.
- **`MapOverlays`:**
  - `set_positions(positions: Array, start: int, order: int)`: instance `start + i` gets `x`, `y` = `positions[i]` and `order` = `order` (`renderNinjamonEffect`'s writes), then `_show`; indices past the instances are skipped, as `load_positions` does;
  - `_show`: an instance with `order < 20` (`SCREEN_ORDER`, `overworld.c:499`) is drawn in screen coordinates: its corner is `field.scroll + Vector2(x, y) + SCREEN / 2` (`buildMapOverlayPrim` mode 1, 741–743: the primitive at (x, y) from the screen centre, no scroll). Its depth stays `order · OT_UNIT`.
- **`MapEffects`** (`scripts/field/hosts/map_effects.gd`, `class_name MapEffects extends Node`): owns one `MeramonShake`, one `NinjamonEffect`, one `MoodBubble`. Fields: `field_map: FieldMap`, `interpreter: ScriptInterpreter`, `game_state: Node`; state `shake_running`, `ninjamon_running` (bool), `bubble_draws: Array` (the last `render()` result) and `bubble_entity: Node3D` (the entity they are drawn at; null when off the map).
  - `start_meramon_shake()` (0x22): `shake.start(Vector2i(field_map.offset_shake))`, `shake_running = true`;
  - `start_ninjamon()` (0x26): `ninjamon.start(field_map.overlays.store_positions(0, NinjamonEffect.COUNT))`, `ninjamon_running = true`;
  - `create_mood_bubble()` (0x1C): `bubble.create(entity != null, game_state.script_value(0xF8))` with `entity = interpreter.entity_for_script_id(game_state.script_value(0xF7))`;
  - `tick()`, once per game frame right after `MapPropsView.render()` (`port-only` place: the C ticks the shake with the tick objects and draws the other two with the render objects, all in the same frame):
    1. shake: `field_map.set_offset_shake(field_map.offset_shake + Vector2(shake.tick(), 0))`; when `shake.done`, `set_offset_shake(Vector2(shake.saved_offset))` and `shake_running = false` (S6: the C restores the saved offsets; the port's offset follows the scroll, so it restores the shake part: `stand-in`);
    2. Ninjamon: `done = ninjamon.tick()`; `field_map.overlays.set_positions(ninjamon.positions, 0, NinjamonEffect.ORDER)`; when done, `field_map.overlays.set_flag(0, 1, NinjamonEffect.COUNT)` and `ninjamon_running = false`;
    3. the bubble: `bubble_entity` = the entity for script value 0xF7 (as above); `bubble_draws = bubble.render(bubble_entity != null)`.
  - The bubble is drawn by `MoodBubbleView` (§4.2.3).
- **`ScriptInterpreter`:** `var fade: Fade`, `var map_effects: MapEffects` (null: unported as now), and `func entity_for_script_id(script_id: int) -> Node3D` (public, returns `_entity_for_script_id`). Routines: 0x1C `map_effects.create_mood_bubble()` (`script_interp.c:1783`), 0x22 `start_meramon_shake()` (1814), 0x26 `start_ninjamon()` (1838), 0x2D `fade.fade_to_white(read_pstat(0xFE))` (1882), 0x2E `fade.fade_from_white(read_pstat(0xFE))` (1885). None ends the frame.
- **Wiring:** `MapSession.start_map_items()` also makes `map_effects` (name `"MapEffects"`, `field_map`, `game_state = GameState`), added as a child of the session; `Field._start()`, after `care_host.start()`: `scripts.interpreter.fade = care_host.fade`, `map_session.map_effects.interpreter = scripts.interpreter`, `scripts.interpreter.map_effects = map_session.map_effects` (only when `scripts.interpreter` isn't null); `Field._frame()` calls `map_session.map_effects.tick()` right after `map_props_view.render()`.

#### 4.2.3 The mood bubble's view (step 4b, main session)

- **Asset porter** (`maps` family, `asset_porter/specs/map.md`): GCAN11's faces, u 0–159 v 0–31 of the 4bpp page (640, 0) through CLUT (0, 486), as `maps/GCAN11/mood/faces.png` + `.stp.png` + sidecar.
- **`MoodBubbleView`** (`scripts/field/mood_bubble_view.gd`, a HUD `Control` like `ConditionBubbles`): each frame (`refresh()` after `MapEffects.tick()`), one sprite per `bubble_draws` entry: the condition-FX point of `bubble_entity` (`translateConditionFXToEntity`: `GameData.condition_fx_offset`'s offset through the bone's world basis), projected by `FieldMap.world_to_screen` from `drawing_offset()`; the pivot (16, 16) on (x, y − offset), size 32 · scale / 4096; region u = `bubble.u`. Opaque texels drawn, STP texels added (attribute 0x50000000, rate 1). The faces are the current map's (`maps/<NAME>/mood/faces`), so a map without them draws nothing. `stand-in`: in the HUD, over the 3D world (the C sorts it at OT depth >> 4).
- **`PsxTexture.load_masked(rel)`**: a porter PNG split by its `.stp.png` mask (`TrainingSlotsBox.load_strip` uses it too).
- **Wiring:** `MapSession.mood_bubble_view` (made in `start_map_items`), in the field's HUD after the condition bubbles.

**The map-textured props (found 2026-11-02).** T_YAMA, BIGBOX, SMABOX, GAND, ABOX and BOSS_EFE have no texture of their own: they read the map's VRAM (`asset_porter/specs/tmd.md`). The porter now exports them per map like the doors (`maps/<NAME>/props/<FILE>.gltf`: T_YAMA on TUNN05, the boxes on OMOC08, GAND on OMOC03, ABOX on ICSA01, BOSS_EFE on MGEN99), and `MapPropsView.model_path()` prefers the current map's copy.

### 4.3 Machinedramon

`EabScene` (logic, `scripts/field/eab/eab_scene.gd`) holds the timelines E2–E12: frames, phases, rings, particles, colours, the camera's eye / target, the wireframe total. `EabView` draws:
- the rings (`BOSS_EFE.gltf` object 0, untextured, flat grey 0x3C);
- the flash and backdrop quads;
- the particles' lines;
- the wireframe on entity 2 (`DooaScene`'s wireframe draw, entity 2's instead of the partner's).

The nine flashes go through the death scene's `EFECreateFlash` port. `TamerHost` / the interpreter: digimon routine 8 sets tamer state 18 and partner state 11, clears the sync bit, and the scene sets it again (as routines 7 / 9). Routines 0x33 / 0x28 load the model and start the build-up on script entity 5.

#### 4.3.1 The logic's API (step 5a)

`class_name EabScene extends RefCounted` (`scripts/field/eab/eab_scene.gd`), modelled on `EvlSequence`. Values are PSX integers; `lerp` is `PsxMath.lerp_int` (with its wrap quirk: E6's angle runs past 0x122 until 0x140), `_sin` is `PsxMath.sin512`, C divisions `PsxMath.div`.

- Constants (each with its line): `RINGS := 3` (the slots `EAB_addBuildupRing` / `EAB_addSpawnRing` search, 219, 276), `RING_BUILDUP := 0`, `RING_SPAWN := 1`, `BUILDUP_RING_LIFE := 0x12` (249), `SPAWN_RING_LIFE := 9` (306), `PARTICLES := 100` (519), `PARTICLE_LIFE := 0x56` (600), `FLASHES` (`EAB_D_8006170C`, 136: nine `[x, y, z, scale_max]`), `PULSE` (`EAB_D_8006179C`, 148: 18 values), `PARTICLE_RB := 0x0A` (`MAIN_D_80134C3C`, 124), `MODEL_COLOR := Vector3i(0x3C, 0x3C, 0x3C)` (E1), `RING_ROTATION := Vector3i(0, 0x800, 0)` (122, 123), `ANIM_RISE := 0x21`, `ANIM_LOOP := 0x33`, `VAB_ID := 5`, `SOUND_BANK := 8`.
- State: `buildup_active`, `buildup_frame` (`MAIN_D_801353F0`); `spawn_active`, `frame`, `phase` (`EAB_D_800617E8`); `rings: Array[Dictionary]` (3 × `{"timer": -1, "kind"}`); `particles: Array[Dictionary]` (100 × `{"timer": -1, "pos": Vector3i, "color": Vector3i}`); `fx := BattleFx.new()` (its own flash slots: `initializeFlashData(EAB_D_80061800)`); `wireframe_total := 16` (`ENTITY1_WIREFRAME_TOTAL`, `model.c:85`, kept between frames).
- Inputs the host sets before each `tick()`: `location: Vector3i` (`ENTITY_TABLE[2]`'s location), `yaw: int` (its rotation.vy), `bone0: Vector3i` (`calculateBoneMatrix(entity, 0).t`), `anim_id: int`, `anim_ended: bool` (animFrame == frameCount).
- Outputs, cleared at the start of each `tick()`: `events: Array` (in the C's order; strings or arrays: `"buildup_entity_hidden"`, `["sound2", bank, id]`, `["sound", bank, id]`, `"stop_sound"`, `"entity_on_map"`, `["animation", id]`, `"hide_entities"`, `"show_entities"`, `"map_layer_off"`, `"map_layer_on"`, `"save_view"`, `"restore_view"`, `["vab", id]`), `flashes_drawn: Array[int]` (each `EAB_renderFlash` colour this frame, in order), `backdrop: bool`, `view: Dictionary` (`{"eye": Vector3i, "ref": Vector3i}` when the orbit set `GS_VIEWPOINT` this frame and no restore followed, else `{}`).
- `start_buildup()` (`EAB_startBuildup`, 649): `buildup_frame = 0`, `buildup_active = true`, every ring's timer −1; events `"buildup_entity_hidden"`, `["sound2", 8, 0]` (called from routine 0x28; its events are read by the host right away).
- `start_spawn()` (`EAB_tick` init, 680–706): `frame = 0`, `phase = 0`, `spawn_active = true`, every particle's timer −1, `fx.reset()`, then per `FLASHES[i]`: `fx.create_flash(0x20, Vector3i(x, y, z), 0x22, 0x32, 0, scale_max, Vector3i(0x14, 0x14, 0x14), Vector3i(0xFF, 0xFF, 0xFF))` (the stack order of 694–703); event `["sound", 8, 1]`.
- `result() -> int` (`EAB_tick(entity, 1)`): `frame` (−1 once done: `tamerTickMachinedramonSpawn` then sets the sync bit).
- `tick()`, one game frame, in this order (`port-only`: the C's object list puts the rings and particles after the objects that add them, so a ring or particle is ticked in the frame it is added: `stand-in` for the slot order):
  1. `buildup_active`: `EAB_tickBuildup` (187): `buildup_frame = (buildup_frame + 1) % 18`; when `% 6 == 0` a ring of kind `RING_BUILDUP` (the first slot with timer < 0 gets timer 0; none free: nothing).
  2. `spawn_active`: `EAB_tickSpawn` (349–458) exactly as the C: `frame += 1`; when `anim_id == ANIM_LOOP and anim_ended`: `["animation", 0x33]`; then the phases:
     - phase 0: frame ≥ 0x2D → `flashes_drawn.append(0xFF)`; frame < 0x32 → stop. Else phase 1 and events `"entity_on_map"`, `["animation", 0x21]`, `"hide_entities"`, `"map_layer_off"`, `"save_view"`, `buildup_active = false`, `"stop_sound"`, `["sound2", 8, 2]`, `["vab", 5]`; falls through;
     - phase 1: a `RING_SPAWN` ring; frame == 0xD2 → `["animation", 0x33]`; 0x32 ≤ frame < 0x53 → `flashes_drawn.append(lerp(0xFF, 0, 0x32, 0x52, frame))`; `v = PULSE[frame % 18]` ≠ 0 → a particle at `location`, colour (0x0A, g, 0x0A) with `g = lerp(0x32, 0xE6, 1, 5, v)`, then `g = div(g · sin512(lerp(0, 0x80, 0x32, 0x122, frame)), 4096) & 0xFF` (the first free of 100 slots gets timer 0; none: nothing); `backdrop = true`; 0x32 ≤ frame < 0x123 → `wireframe_total = 0x10 − div(sin512(lerp(0x80, 0, 0x32, 0x122, frame)) · 16, 4096)`; the orbit: `ry = lerp(0x71C, 0x171C, 0x32, 0x122, frame)` for 0x32 ≤ frame < 0x123, else 0x171C; `ry += yaw`; `distance = lerp(0xDAC, 0xBB8, 0x32, 0x140, frame)`; `height = lerp(0x258, 0x32, 0x32, 0x140, frame)`; `ref = bone0 − (0, 0x64, 0)`; `eye = apply_matrix_lv(rot_matrix_zyx((0, ry, 0)), (0, 0, distance)) + ref − (0, height, 0)` (`EAB_calculateCameraOrbit`, 559); `view = {"eye", "ref"}`; frame == 0x13F → `view = {}`, `"restore_view"`; frame < 0x140 → stop. Else phase 2: every particle's timer −1, `"map_layer_on"`, `"show_entities"`, `view = {}`, `"restore_view"`, `"stop_sound"`, `["sound", 8, 3]`;
     - phase 2: frame < 0x14A → a `RING_SPAWN` ring; frame ≥ 0x154 → every ring's timer −1, `frame = −1`, `spawn_active = false`.
  3. Each ring with timer ≥ 0: timer + 1; at ≥ its kind's life → −1 (`EAB_tickBuildupRing` 241, `EAB_tickSpawnRing` 298).
  4. Each particle with timer ≥ 0: at ≥ 0x56 → −1, else + 1 (`EAB_tickParticle`, 595).
  5. `fx.tick()`.
- `ring_scale(i) -> Vector3i` (x, y, z) for ring i's timer `t`: buildup: xz `lerp(0x10B8, 0x614, 1, 0x12, t)`, y `div(sin512(lerp(0, 0x80, 1, 0x12, t)) · 0xC3C, 4096) + 0x15C` (255–274); spawn: xz `lerp(0x16CC, 0x10B8, 1, 0x12, t)`, y `div(sin512(…) · 0x2B8, 4096) + 0xAE` (312–329).
- `particle_size(i) -> int` = `lerp(8, 0x9C4, 0, 0x56, timer)`; `particle_color(i) -> Vector3i` = each channel `lerp(c, 0, 0, 0x56, timer)` (`EAB_renderParticle`, 608–647).
- C quirk kept: `EAB_setModelColor` (159) only advances its primitive pointer on a 0x2D / 0x2F primitive, so after the first other primitive it rewrites nothing more. The view colours what the C colours (step 5b).

#### 4.3.2 The host, the view and the wiring (step 5b, main session)

`BOSS_EFE.TMD` (the porter's `tmd_files/ETCHI/BOSS_EFE.json`): one object of 12 quads, all mode 0x2F (textured, semi-transparent, brightness off), tsb 42 (page (640, 0) 4bpp, abr 1: additive), CBA (0, 486), colour 128. `EAB_setModelColor` therefore rewrites all 12 to 0x3C: the texel × 0x3C / 128, its STP texels added. The texture is the map's VRAM: `maps/MGEN99/props/BOSS_EFE.gltf` (§4.2.3's per-map props; `tmd_files/ETCHI/BOSS_EFE.gltf` on another map, untextured).

`EabHost` (`scripts/field/hosts/eab_host.gd`, `class_name EabHost extends Node`) owns `scene: EabScene` and `view: EabView` and does what the C's events do:
- References: `field_map`, `entities: FieldEntities`, `sound`, `data`, `map_layer_nodes: Callable`, `world` (the 3D views' parent), `background: Node` (the field's background layer).
- `load_scene()`, routine 0x33 (`script_interp.c:1841–1846`): `readVBALLSection(5, 0x73)` → `sound.load_bank(5, "sound/VBALL/set_%02d" % vball)` with `vball` = `data.digimon_sounds(0x73).vball` (`DIGIMON_VBALL_SOUND_ID[0x73]`, `sound_async.c:227`); `loadMapSounds2(0x15)` → `sound.load_map_sounds(0x15)`; the ring model loaded (`view.load_model(field_map.map_name)`). The REL load and the file request have nothing to port.
- `start_buildup(entity)`, routine 0x28 (`script_interp.c:1853–1856`, `isSoundLoaded(0, 8)` is a wait with nothing to wait for: `port-only` none): the build-up entity kept, `scene.start_buildup()`, its events run at once.
- `start_spawn()` / `result()`, tamer state 18 (`tamerTickMachinedramonSpawn`, `tamer.c:1718`): entity 2 kept as the spawn entity (`EAB_tick(ENTITY_TABLE[2], 0)`), the inputs set, `scene.start_spawn()`, its events run at once; `result()` = `scene.result()`.
- `tick_objects()`, once per frame after `EvolutionHost.tick_objects` (the object list, `port-only` place): the inputs from entity 2 (`location` its position, `yaw` its `direction`, `bone0` its bone 0's world position, `anim_id` / `anim_ended` its animator's `anim_id` and `frame == frame_count`), `scene.tick()`, the events in order, the view, then `view.draw_frame(...)`. Nothing runs while neither the build-up nor the spawn nor a ring is live.
- The events:
  - `"buildup_entity_hidden"`: the build-up entity `on_map = false`, hidden (`entity->isOnMap = 0`, 663);
  - `["sound", b, id]`, `["sound2", b, id]`: `sound.play_sound(b, id)` (`playSound` / `playSound2`: the port plays both the same way, as `TrainingStation`);
  - `"stop_sound"`: `sound.stop_sound()`;
  - `"entity_on_map"`: entity 2 `on_map = true`, shown;
  - `["animation", id]`: entity 2's `start_animation(id)`;
  - `"hide_entities"` / `"show_entities"`: `EAB_setEntitiesVisible` (497): every entity but 2 that is on the map goes off it (hidden), its slot remembered (`EAB_D_80061A04`); back: every entity but 2 gets the remembered `on_map` (shown when 1);
  - `"map_layer_off"` / `"map_layer_on"`: `MapLayer.set_enabled(map_layer_nodes, …)`;
  - `"save_view"`: `field_map.view()` kept (`EAB_D_800619E4 = GS_VIEWPOINT`);
  - `scene.view` not empty: `field_map.set_view({"eye", "ref", "projection", "offset"})` with the saved projection and drawing offset (the C changes only `GS_VIEWPOINT`);
  - `"restore_view"`: `field_map.restore_map_view()` (`stand-in`: the saved viewpoint is the map's own; script 184 moves no camera before).
  - `["vab", 5]`: entity 2's `sound_slot = 5` (`stats.current.vabId`, 391).
- The wireframe: a `PartnerWireframe` on entity 2's model (`ENTITY1_WIREFRAME_TOTAL`, `model.c:2922`), attached at `start_spawn`, `set_share(scene.wireframe_total)` every frame and `roll_greys(0x37, 0xFF)` while it isn't 16 (`WIREFRAME_COLOR_MIN` / `MAX`, `model.c:89`, 91); detached at the end (`frame` −1).
- The flashes: a `BattleFxView` on `scene.fx`.

`EabView` (`scripts/field/eab/eab_view.gd`, `class_name EabView extends Node`) draws:
- `rings`: 3 instances of the ring model in `world`, tinted 0x3C / 128 (`PaletteFade.apply`); ring i shown when its timer ≥ 0, its transform `Content.psx_transform(ring_matrix(scale, location))` = `TransMatrix(ScaleMatrix(RotMatrix(RING_ROTATION), scale), location)` (`renderTMDModel`, `effect_common.c:579`), the location the build-up entity's for a build-up ring, entity 2's for a spawn ring (`fx->entity`, 236, 293);
- `lines` (a `Node2D` on the background layer, over the backdrop: OT 0xF9F in front of 0xFA0, behind every model): each live particle's square (corners `pos ± size` in x and z, 613–620), each edge between two corners whose `sz >> 4` is in (0x20, 0x1000) (628–629), 1 px, its colour (as `EvlParticlesView`);
- `backdrop` (a `ColorRect` on the background layer, before `lines`): shown while `scene.backdrop`, subtractive, level `subtract_level(0xFF)`;
- `flash` (a `Control` on a `CanvasLayer` of layer 1 in `world`: over the 3D world, `stand-in` for OT 0xA under the HUD): one full-screen subtractive rect per `scene.flashes_drawn` value, each `subtract_level(c)`.
- `static func subtract_level(c) -> int` = `mini(0x1F, (0x1F * c) >> 7)`: the texel (SPOT256 index 255 = 0xFFFF: 31 per channel) × the colour / 128, saturated (§8.3); the rect subtracts `level / 31`.
- `static func ring_matrix(scale: Vector3i, location: Vector3i) -> PackedInt32Array`.
- `static func particle_lines(scene, project: Callable, offset: Vector2) -> Array` (`[from, to, Color]` per edge, screen pixels with the drawing offset).

Wiring: `ScriptInterpreter.eab: EabHost`; routines 0x33 / 0x28 (no longer unported); digimon routine 8 (`partner.c:1189`): `tamer.set_state(18)`, `partner.set_state(Partner.STATE_IDLE)` (11), sync bit 0, `_sync_scene`. `Tamer.STATE_MACHINEDRAMON_SPAWN := 18`, `tick_machinedramon_spawn()`: sub-state 0 `eab.start_spawn()`, 1; sub-state 1: `eab.result() < 0` → sync bit 1. `Field` makes the host (`$Systems/EabHost`), hands the references and calls `tick_objects`.

### 4.4 The ending and the credits

`EndingScene` (logic, `scripts/field/ending/ending_scene.gd`): N1–N7.

The view:
- the tamer's palette fade (`PaletteFade` on the tamer, with the STP rule: black texels become transparent);
- the tamer drawn additive (N1);
- scale on the tamer node;
- the particles through `HealingParticles`' `renderFXParticle` draw.

Digimon routine 6 and routine 0x35 set tamer state 16. Routine 0x35's wait (case 53) sees the sync bit and asks the game to end the field: `Game` frees the field, plays movie 3 (not skippable), then shows the title (`main.c` loop). Digimon routine 5 (debug menu only) sets tamer state 15: map layer on, sync bit set.

Found in the data and the C (2026-11-02):
- The tamer's TMD (`CHDAT/MMD0/BOYS`, the porter's sidecar) has 305 primitives, all mode 0x34 (116) or 0x3C (189): `ENDI_setModelSemiTrans`'s switch (which doesn't advance on another mode) changes them all, so the whole tamer becomes semi-transparent, abr 1 (additive). Its textures use CLUTs (0, 488)… inside the faded rect (0, 488) 16 × 24.
- `ENDI_updateEnding` increments `frame` before the switch, so the fade runs at frames 1–60; at 60 every colour is 0, so the tamer is invisible from then on (a colour 0 without STP is transparent).
- N7 cancels out: at the release `pos = world − base` and from then the particle is drawn at `pos + base` (both SVECTOR, so only an int16 wrap could show). The port uses 0 for `t[3]` (`port-only`); §8.4 answered.
- Script 192 calls routine 0x36 (`gameClearSave`, the game-clear save; `SaveRoutines`, already ported) before 0x35.
- Routine 0x34's `loadTextureFile(OP.TIM)` lands at VRAM (576, 256) (the porter's `tim_files/ETCHI/OP.json`); nothing in `endi.c` reads it (`renderFXParticle` reads (768, 256)): nothing to port.

#### 4.4.1 The logic's API (step 6)

`class_name EndingScene extends RefCounted` (`scripts/field/ending/ending_scene.gd`). Values are PSX integers; `lerp` is `PsxMath.lerp_int`, C divisions `PsxMath.div`, `rand()` is `Rng.rand()`.
- Constants: `PARTICLES := 80` (`NUM_ENDI_PARTICLES`, `endi.h:10`), `FADE_END := 60` (172), `PEAK := 78` (183), `GROW_END := 80` (189), `SCALE_ONE := 0x1000`, `SCALE_LOW := 0x999`, `SCALE_HIGH := 0x1800` (186–188), `VELOCITY := -450` (194), `GRAVITY := 20` (205), `SOUND_BANK := 8`, the particle rolls (`rand() % 140 − 70`, `% 80 − 40`, `% 80 − 40`, 280–282; colour `rand() % 70 + 60`, size `rand() % 15 + 15`, 390–394).
- State: `frame`, `phase` (`ENDI_STATE`), `active`; `particles: Array[Dictionary]` (80 × `{"active": -1, "bone", "pos": Vector3i}`), `attached := true` (`ENDI_DATA.flag`), `shown := false` (the render object 0x813 is in the list), `base: Vector3i`, `velocity`, `scale := 0x1000` (the tamer's `posData->scale`), `fade_frame := 0` (the frame of the last `ENDI_fadeClut`).
- Inputs: `bone_count` (`DIGIMON_DATA[0].boneCount`), `bone_matrix: Callable` (bone → `PackedInt32Array`, PsxMath's 12-int layout: the bone's world matrix, `calculateBoneMatrix` / `posMatrix.workm`).
- Outputs: `events` (cleared at the start of each `tick()`; `["sound", 8, id]`, `"stop_sound"`).
- `start()` (`ENDI_tickEnding(entity, 0)`, 407–431): frame 0, phase 0, active, every particle −1, `attached`, `shown`, `fade_frame = 0`, `scale = 0x1000`; event `["sound", 8, 0]` (the CLUT STP, the semi-transparency and the shadow are the host's).
- `result()`: `frame` (−1 once over).
- `tick()` (`ENDI_updateEnding`, 159): exactly as the C: `frame += 1`; phase 0: `fade_frame = frame`, a particle at bone `frame % (bone_count − 1) + 1`, phase 1 at ≥ 60; phase 1: a particle, `scale` per N3, at ≥ 80 `["sound", 8, 1]`, phase 2, `release()`, `velocity = −450`; phase 2: `base.y = s16(base.y + velocity)`, `velocity += 20`, phase 3 at ≥ 0; phase 3: `"stop_sound"`, `shown = false`, `frame = −1`, not active.
- Spawn (`ENDI_spawnParticle`, 266): the first slot with `active < 0` (none: nothing, `port-only` guard: the C writes slot 80; 80 spawns fill exactly the 80 slots, so it never happens), `active 0`, the bone, `pos` from the three rolls in order x, y, z.
- `release()` (`ENDI_releaseParticles`, 302): `attached = false`; `base = s16(m0.t[1], m0.t[2], 0)` with `m0 = bone_matrix(0)` (N7); each active particle: `pos = s16(world(p) − base)`.
- `world(p)`: `v = s16(div(pos · scale, 0x1000))` per axis, `s16(apply_matrix_lv(m, v) + m.t)` with `m = bone_matrix(p.bone)` (`ApplyMatrixSV`, 327–332, 375–380).
- `render() -> Array` (`ENDI_renderParticles`, 368): `[]` unless `shown`; per active particle in slot order `{"pos": world(p) if attached else s16(pos + base), "color": Vector3i(r, g, b), "size"}`, rolling r, g, b, size in that order.
- `static func fade_factor(fade_frame) -> float` = `(60 − fade_frame) / 60.0` (`stand-in` for `ENDI_fadeClut`'s per-5-bit-channel `c · (60 − f) / 60`, as `PaletteFade` in `specs/death_scene.md` §4.9).

#### 4.4.2 The host, the view and the wiring (step 6)

`EndingHost` (`scripts/field/hosts/ending_host.gd`, `class_name EndingHost extends Node`, `$Systems/EndingHost`):
- References: `tamer`, `field_map`, `sound`, `data`, `map_layer_nodes`, `world`.
- `load_scene()`, routine 0x34 (`script_interp.c:1848–1852`): `sound.load_map_sounds(0x14)` (the OP.TIM load and the REL have nothing to port).
- `start()` / `result()`, tamer state 16 (`tamerTickEnding`, `tamer.c:1682`; `isSoundLoaded(0, 8)` has nothing to wait for): `scene.bone_count` from `data.digimon(0)`, `scene.bone_matrix` from the tamer's skeleton, `scene.start()`; then the tamer's materials replaced by `PsxLit.semi_transparent(model, 1)` (N1: one blended pass per surface, abr 1, every texel), its `DropShadow.enabled = false` (`PLAYER_SHADOW_ENABLED = 0`); events run.
- `tick_objects()` after `EabHost.tick_objects`: while active, `scene.tick()`, events (`sound.play_sound` / `sound.stop_sound`), then the drawing: the tamer's tint `fade_factor(scene.fade_frame)` on every pass, `tamer.scale = scale / 4096`, the particles (`scene.render()`) through `FxParticles.draw` (`renderFXParticle`, moved out of `HealingParticles`: the DEFEFF dot, added, culled at OT depth (SZ >> 4) − 0x37).
- Routines: `ScriptInterpreter.ending: EndingHost`; 0x34 → `load_scene()`; 0x35 (`script_interp.c:1858–1864`): `isSoundLoaded`, `tamer.set_state(16)`, sync bit 0, waits (`OP_CALL_ROUTINE`, mode 0); the wait (case 53, 516–520): sync bit 1 → `active_instruction = 0`, the `game_ended` signal, the frame ends. Digimon routines 5 / 6 (`partner.c:1166–1175`): tamer state 15 / 16, partner state 11, sync bit 0, `_sync_scene`.
- `Tamer.STATE_OPENING := 15` (`tamerTickOpening`, 1668: sub-state 0 → 1; 1: the map layer on through `Tamer.map_layer_nodes`, sync bit 1) and `STATE_ENDING := 16` (`tick_ending`: sub-state 0 `ending.start()`, 1; 1: `ending.result() < 0` → sync bit 1).
- `Field.game_ended` (relayed from the interpreter's, `MAIN_STATE = 3`): `Game` listens on the field it made: `cleanupGame` (the field freed), `finalizeMusic` (`Sound.music.stop_bgm()`), `playMovie(3, 1)` (not skippable), then `_title()` (the C's boot loop: `main.c:3410`).

## 5. Godot design (files)

| Part | Files |
|---|---|
| Props | `scripts/field/map_props.gd`, `scripts/field/map_props_view.gd`; `scripts/content/content.gd` (`psx_transform`); `scripts/field/field.gd`, `scripts/field/hosts/map_session.gd`, `script_host.gd` (wiring); `scripts/field/field_map.gd` (P21's signal); `scripts/state/game_state.gd` (`session`) |
| Interpreter | `scripts/script/script_interpreter.gd` (the routines and opcodes) |
| Screen effects | `scripts/field/fade.gd`, `scripts/field/meramon_shake.gd`, `scripts/field/ninjamon_effect.gd`, `scripts/field/mood_bubble.gd` (logic), `mood_bubble_view.gd`, `scripts/field/field_map.gd` (`offset_shake`) |
| Machinedramon | `scripts/field/eab/eab_scene.gd`, `eab_view.gd`, `scripts/field/hosts/eab_host.gd`, `scripts/field/tamer.gd` (state 18), `scripts/script/script_interpreter.gd` (0x28, 0x33, digimon routine 8), `scripts/field/field.gd`, `scenes/field/field.tscn` (wiring), `scripts/field/evolution/evl_particles_view.gd` (`set_lines`) |
| Ending | `scripts/field/ending/ending_scene.gd`, `scripts/field/hosts/ending_host.gd`, `scripts/field/fx_particles.gd` (`renderFXParticle`, out of `healing_particles.gd`), `scripts/content/psx_lit.gd` (`semi_transparent`), `content.gd` (`psx_matrix`), `scripts/field/drop_shadow.gd` (`enabled`), `scripts/field/tamer.gd` (states 15 / 16), `scripts/script/script_interpreter.gd` (0x34, 0x35, case 53, digimon routines 5 / 6), `scripts/field/field.gd` (`game_ended`), `scripts/game/game.gd` (end → movie 3 → title) |

## 6. Order of work

All suites and scans pass after every step; a step is done when its gate in §7 passes.

| Step | What | Complexity · Model | Delegate? |
|---|---|---|---|
| 1 | `MapProps` logic (§3.1, §4.1 logic): positions, matrices, lids, pedestal, pile counter, `unload`, the time-of-day clash | **Low** · Gemini 3.8 Flash (High): numbers only, one file, the tests decide | **agy** |
| 2 | `MapProps` view and wiring: the models, map layer, cart following the partner, the interpreter's routines / opcodes, map change, `GameState.session` | **Medium** · Claude Sonnet 5.5 (Medium), or agy with a precise brief: several files, the tests cover the wiring, an in-game look covers placement | **agy** (brief lists every hook) |
| 3 | Screen-effect logic: `MeramonShake`, `NinjamonEffect`'s maths, the bubble's timer / scale, the white fade's counters (S1–S11) | **Low** · Gemini 3.8 Flash (High) | **agy** |
| 4 | Screen-effect views and wiring: `Fade` white (additive layer), `FieldMap.offset_shake`, the overlays, `MoodBubble` drawing, the routines | **Medium**: rendering is simple (a fade, a sprite, an offset), the tests check the state | agy or Sonnet; **agy** if step 2 went well |
| 5a | Machinedramon's logic (§3.3, §4.3.1): `EabScene`, every timeline by the frame | **Medium** · Gemini 3.8 Flash (High) with the exact API and tests | **agy** |
| 5b | **Done (2026-11-02).** Machinedramon's view and wiring (§4.3, §4.3.2): rings, quads, lines, wireframe, camera, hidden entities, routines 0x28 / 0x33, digimon routine 8, tamer state 18 | **Hard** · main session (Opus) | no |
| 6 | **Done (2026-11-02).** The ending and credits (§3.4, §4.4): `EndingScene` **Medium**, the view and the CLUT/STP fade **Hard**, the `Game` end path **Medium** | **Hard** · main session | no (the `Game` path could be split off to agy) |
| 7 | ~~Robot House's TFS reload (§3.5)~~: the map rereads its own TFS, so nothing changes (§8.1, 2026-11-02) | none | dropped |
| 8 | **Done (2026-11-02).** VERIFY "Map events and the ending", PLANS, "As built", gates (both test files default to step 6) | main session | no |

Steps 1–4 can run before 5–6, and 1 and 3 in parallel (they own different files). The story reaches the credits after step 6.

## 7. Tests (acceptance checks, written before each step; gate `DW_STEP_4F=<step>`)

`tests/test_map_events.gd` (`-s`, with `GameData`): steps 1, 3 and later logic. `tests/test_map_events_field.gd` (`-s`, a `FieldMap` and an interpreter like `test_map_objects.gd`): step 2 and 4's wiring.
- **Step 1:**
  - every P row (positions, scale per counter, the counter's floor of 6, `move_boulder`'s y quirk, the lid's 11 frames to −0x400, the pedestal's 50 frames and its ±5);
  - `unload` clears all;
  - the time-of-day clash drops the pedestal.
- **Step 2:**
  - a script stub calling each routine / opcode reaches `MapProps`; 0x13 / 0x14 / 0x77 end the frame; 0x32 waits until done;
  - the routines are gone from the unported reports;
  - a map change unloads;
  - the cart's world transform for a given partner position, yaw and radius;
  - in the scan: Underground Pond's and Toy Mansion's sections run with the props drawn.
- **Step 3:**
  - the shake's 210 steps (sum 0, the amplitude per range), the offsets restored;
  - Ninjamon with a seeded `Rng`: positions after 1 / 2 frames, a wrap, all hidden at 0x3C;
  - the bubble's scale and y offset per timer, mood ≥ 5 removes;
  - white fade counters, no clock stop.
- **Step 4:** the routines reach the pieces; the fade's blend is additive; `FieldMap.drawing_offset()` follows the shake.
- **Step 5:** E2–E12 frame by frame (ring scales, flash levels, particle colours, wireframe total, camera eye / target at chosen frames, phase changes, the sync bit at 0x154), entity visibility saved and restored.
- **Step 6:** N2–N5 (the colour factor per frame, the scale curve, release at 80, velocity to 0, the end), the sync bit, `Game` playing movie 3 then the title.

## 8. Open questions

1. **~~Volume Villa's CLUTs (§3.5)~~: answered (2026-11-02).** Routine 0x2A runs in script 140, on OMOC03 itself, so `readMapTFS(0x92)` rereads the map's own TFS: the CLUTs stay the same. Nothing to port (step 7 dropped).
2. **The pedestal and the time of day (P21).** Kept as in the C. Seen only if the hour changes during Ice Sanctuary's (ICSA01) pedestal scene.
3. **EAB's flash and backdrop (E9, E10): answered from the data (2026-11-02).** The texel at (832, 256) 8bpp, u 0 v 0x80, CLUT (0, 487) is SPOT256's (`etctim/07_spot256`, image (0, 0)) index 255 = 0xFFFF: white with STP. Subtracted at colour 0xFF it removes everything: the flash turns the screen black, and the backdrop (OT 0xFA0, in front of the background, behind the models) blacks out the map behind Machinedramon.
4. **~~ENDI's base (N7)~~: answered (2026-11-02): it cancels out (§4.4).** It reads `t[1..3]` (one past the translation): the detached sparks are offset. The port keeps it with `t[3]` = the next word of the C's `MATRIX` (`port-only` value 0 if unknown). To confirm in the original.
6. **~~The mood bubble's faces (S10)~~: answered (2026-11-02).** Scripts 199–202 run on GCAN11, the Monochrome Shop (script 49 jumps to them), not on TWNB20–23. GCAN11's 4bpp image 0 is exactly the rect the sprite reads (VRAM (640, 0), 160 × 32: five 32 × 32 faces); the porter exports it (`maps/GCAN11/mood/faces.png`, `asset_porter/specs/map.md`) and `MoodBubbleView` draws it (§4.2.3).
5. **Movie 3** is the credits (`movies.json`); `MoviePlayer` must not let Start skip it (`specs/new_game.md`).

## As built (2026-11-02)

- **Steps and commits:** spec `aac8364`; 1 `MapProps` (`48e5af5`, agy); 2-3 the props' view and wiring, the screen effects' logic (`a594525`, agy); 4 the screen effects' views and wiring (`e20e94b`, agy); 5a `EabScene` (agy), the mood bubble's view and the per-map props (`ce6773a`); 5b `EabHost` / `EabView` (`9491dd3`); 6 `EndingScene` / `EndingHost`, the credits (`753846d`); 8 this. Step 7 dropped (§8.1).
- **Found on the way** (in the tables now):
  - a script id is not a map id: §1's maps were corrected from `scripts/index.json` (the first draft took script 145 for map 145); the map-textured TMDs (T_YAMA, BIGBOX, SMABOX, GAND, ABOX, BOSS_EFE) are exported per map (porter `maps/<NAME>/props/`, like the doors), and Monochromon's faces from GCAN11 (`maps/GCAN11/mood/`);
  - `unloadMap` (`map.c:4446`) never removes the screen effects: no map-change clear (agy's step 4 had one; removed);
  - EAB: the flash and backdrop texel is SPOT256's 0xFFFF, subtracted (black, §8.3); `EAB_renderBackdrop` runs at frame 0x140 too (before the phase-2 test); all 12 of BOSS_EFE's quads are 0x2F, so `EAB_setModelColor` colours them all;
  - ENDI: all of the tamer's 305 primitives are 0x34 / 0x3C (no stall); the fade runs at frames 1-60; the release's `t[3]` cancels out (§8.4);
  - script 192 runs routine 0x36 (the game-clear save, already ported) before 0x35; the ending's section is started by Machinedramon's `WARP_TO … section=51`, not by entering TEND01 / TEND02 (VERIFY).
- **Shared code changed:** `Fade` (white, additive), `FieldMap.offset_shake` / `set_offset_shake`, `MapOverlays.set_positions`, `PsxTexture.load_masked` (out of `TrainingSlotsBox`), `EvlParticlesView.set_lines`, `FxParticles` (`renderFXParticle`, out of `HealingParticles`), `PsxLit.semi_transparent`, `Content.psx_transform` / `psx_matrix` (the latter out of `FieldBattleWorld`), `DropShadow.enabled`, `Tamer.bone_basis`, `GameState.session`, `Game._start_field` / `_end_game`.
- **Stand-ins** (marked in the code): a ring or particle is ticked in the frame it is added (the C's object order); EAB's flash over the world but under the HUD; the restored viewpoint is the map's own; the ending's CLUT fade as one tint (`PaletteFade`'s rule); the tamer's mood-bubble point is his position.
- **Left outside 4f** (PLANS): `SaveRoutines`' 0x36 skips `awardMachinedramonData` and hard-codes map 0xCC instead of `getFileCityTopMap()`.
- **Tests:** `test_map_events.gd` 321 checks (steps 1, 3, 5a, 6), `test_map_events_field.gd` 315 (steps 2, 4, 5b, 6); every check runs by default (`DW_STEP_4F` can limit them). The exit scan reports nothing unported.
