# Field maps — `maps` (`MAP/MAP*/*.MAP` + `*.TFS`)

Format: `dwporter/formats/map.py`. Family: `dwporter/families/maps.py` (`python -m dwporter convert maps`). Reference: DW1ModelConverter `src/MAP.cpp`, `MAP.hpp`, `GameData.cpp`.

Field maps are **pre-rendered 2D backgrounds** with a 3D camera: Digimon, doors and props are 3D models drawn over the picture with the map's camera; animated details are 2D sprites.

## On disc

`MAP/MAP<id // 15 + 1>/<NAME>.MAP` and `.TFS` (`buildMapPath`, map.c). The map table `MAP_ENTRIES[255]` lives in the executable (`SLUS_010.32` @ `0x801292D4`, 16 bytes each): `char name[10]; i8 num8bppImages; i8 num4bppImages; u8 flags (bits 0-4 sound id, 0x40 no time cycle, 0x80 has digimon); i8 doorsId; i8 toiletId; i8 loadingName` (index into `MAP_NAME_PTR` @ `0x801291BC`, the display name).

- 255 entries: 241 maps with files, 11 empty, 3 named but missing on disc (`YAKA01`, `YAKA21`, `YAKA25`); 242 `.MAP` files, one not in the table (`MAP/MAP16/MGEN17.MAP`, not exported).

### MAP

| Section | Layout | Loader |
|---|---|---|
| header | u32 setup, u32 × num8bpp, u32 × num4bpp, [u32 objects if any images], u32 entities, u32 collision | `loadMap` map.c:4020 |
| setup | i32: viewpoint xyz, reference xyz (both ×2 in game), 3 × light (dir xyz, rgb), ambient rgb (unused), projection H, liked regions[4], disliked regions[4], width, height, tile ids[w × h] (−1 = no tile) | `loadMapSetup` map.c:4143 |
| 8bpp images | TIMs; loaded at their VRAM position, CLUT too unless it targets row 480 | `loadMapImage1` overworld.c:380 |
| 4bpp images | TIMs; image loaded; only image 0's CLUT, row i → (i × 16, 486) | `loadMapImage2` overworld.c:394 |
| objects | i16 count; per object: tex x, tex y, width, height, pos3d xyz, clut, transparency; i16 instance count; per instance: sprites[8], times[8], x, y, flag | `loadMapObjects` overworld.c:331 |
| entities | i16 spawn x[10], y[10], z[10], rotation[10], warp target map[10], target spawn[10]; i16 digimon count; per digimon (if flag 0x80): 42 i16 (type, follow mode, position, rotation, tracking range, unk2, script id, hp, mp, current hp/mp, off, def, speed, brains, bits, charge mode, unk1, moves[4], priorities[4], flee xyz, waypoint count, ai sections[8]) + waypoints xyz | `loadMapEntities` tamer.c:379, `loadMapDigimon` overworld.c:1026 |

Each exported Digimon keeps the raw `unk1` and adds `targets_partner` (`unk1 == 1`): in battle (`NPC_ENTITIES[].unk1`, `BTL_selectFighterTarget` `battle_main.c:3696`) such an enemy never turns to the fighter that hit it, and with `unk1 == 0` an enemy gets +20 weight on area techniques while another enemy is alive (`BTL_selectEnemyMove`, `:3846`). `../../specs/battle.md` §2.10.
| collision | 100 × 100 bytes; cell (tx, tz) = world x ∈ [(tx−50)·100, +100), z ∈ [(50−tz)·100 − 100, +100) | `loadMapCollisionData` map_collision.c:23, `getTileTrigger` |

Every MAP byte is one of these sections (YAKA22 has one 40-byte gap). Collision values: `0` walkable, `128` blocked, others (`51`, `81`, `110`–`112`, …) trigger cells.

### TFS

`u16 width, u16 height` (disagree with the MAP layout in 13 maps; the game ignores them), `u32 palette count`, palettes × 256 u16 colours, then for each MAP tile id ≠ −1 in order: `u32 header` + 128 × 128 8bpp indices. Every TFS ends exactly after its last tile.

- `setupMap` (map.c:4229): palettes → CLUT rows 481+; tiles streamed into VRAM (768 + x%4·64, y%3·128).
- `updateTimeOfDay` (map.c:4301): active palette (row 480) = 0 day, 1 evening (16–20h), 2 night (20–6h); lights × 1.0 / (r 1.0, g 0.7) / 0.5. Maps with flag 0x40 always use palette 0. Palette counts: 130 maps × 3, 108 × 1, a few 4–5.

### Object sprites (`buildMapOverlayPrim`, overworld.c:732)

| clut | texture page | CLUT |
|---|---|---|
| −1 | 8bpp at (384 + tex_x/256 · 128, 0) | (0, 480): active TFS palette → one sprite per palette |
| < 16 | 4bpp at (384 + tex_x/256 · 64, 0) | (clut · 16, 486) |
| ≥ 16 | 8bpp at (384 + tex_x/256 · 128, 0) | (0, clut + 468) |

UV = (tex_x % 256, tex_y % 256); `transparency` = blend mode; instance (x, y) = background pixel of the sprite's top-left.

### Doors

`DOOR_MAPDATA[doorsId − 1]` (exe @ `0x80122E60`, 24 × 54 bytes): 6 slots of model id (255 = none, `DOOR/DOOR<id>.TMD`), position xyz, rotation. Their textures are the map images in VRAM (`tmd.md`).

- `map.json` `doors` keeps each door's `slot` (0–5, `../../specs/map_objects.md` §2.6): the scripts' `ROTATE_3D_OBJECT` names the slot, and tables 1 and 6 have an empty slot 0 (`[255, 9, 9, 9, 10, 10]`, `[255, 18, 16, 17, 255, 255]`). The empty slots stay dropped.
- Model 10 is drawn twice by `renderDoors` (`map_object.c:374`): a mirrored copy (rotation `−vy`, `∓680` on z) makes a double door.

### Training slot machine textures (gym maps)

`loadTrainingLibrary` (map.c:5457) loads the TRN overlay on maps **0x70 TRAI00** (Green Gym), **0x4E GIAS09** (Gear Savanna) and **0x77 MIST05** (Misty Trees) (`TRAINING_MAPS` in `families/maps.py`). Its slot machine ("Bonus Try", `trn_slots.c` `TRN_renderSlotMachine`; `../../specs/training.md` §7.5) has no texture of its own: its two `GsSPRITE`s read the map's 4bpp page at VRAM (704, 0), rows v 0xD8–0xF7.

| Sprite | tpage | u, v, w × h | CLUT (cx, cy) | Use |
|---|---|---|---|---|
| `TRN_SLOT_SPRITE1` | 0x2B (4bpp, x 704, semi-trans rate 1) | (symbol − 1) × 32, 0xD8, 32 × 32 | (48, 486) = row-486 palette 3 | 7 reel symbols |
| `TRN_SLOT_SPRITE2` | 0x4B (4bpp, x 704, rate 2 = subtractive) | 0xE0, 0xD8, 8 × 32 | (64, 486) = palette 4 | reel window shade |

The page is composed from the map's 4bpp images in load order (`loadMapImage2`: each image at its TIM position, later images overwrite; only image 0's CLUT, row i → (i × 16, 486)). The strip comes from TRAI00 image 1 (704, 0, 256 tall), GIAS09 image 0, MIST05 image 2 (704, 216, 32 tall; its image 1 is 200 tall and stops above it).

Findings (all three maps give **identical** strips, indices and both palettes):
- p3: the symbols at u 0–223 (HP heart, MP circle, Offense, Defense, Speed arrows, Brains bulb, poop), index 0 = 0x0000 (transparent); **no colour has the STP bit**, so the symbols' semi-transparent mode never applies (drawn opaque).
- p4: every colour has the STP bit (0xFFFF … 0x8000, white to black); the window column u 0xE0–0xE7 is index 0 (white) at the top and bottom rows and 15 (0x8000, black) in the middle, so the subtraction darkens the reel's edges and leaves the pay line clear. u 0xE8–0xFF is index 0.

## Camera (verified)

`GsSetRefView2`: eye = viewpoint × 2, target = reference × 2 (PSX axes, +Y down); camera right = down × forward, screen down = forward × right. A point projects to `screen = H · (x/z, y/z)`; the screen centre shows the background centre at load (`setupMap`: cameraX = width·128/2 − 160, drawing offset 160, 120), so

```
background pixel = (bg_width / 2 + H·x/z, bg_height / 2 + H·y/z)
```

Verified on several maps by projecting the collision grid: walkable cells cover exactly the walkable ground (fences, beaches, bridges), triggers sit on exits and doorways, doors land on door openings (`overview.png`).

For Godot (axes x, −y, −z): camera at `(eye.x, −eye.y, −eye.z)` looking at the target, vertical FOV = `2·atan(120 / H)` for the 320 × 240 screen; show the background so its centre is at the screen centre (then scroll it with the camera offset like the game).

## Godot representation

`output/maps/<NAME>/`:

| File | Content |
|---|---|
| `background_<p>.png` | full background (width·128 × height·128) with palette p; missing tiles transparent |
| `collision.png` | 100 × 100 grey, raw collision values |
| `objects/object_<k>.png`, `object_<k>_p<p>.png` | object sprites (per palette when clut = −1) |
| `objects/object_<k>[_p<p>].stp.png` | grey mask, 255 where the texel's colour has the STP bit: the texels a semi-transparent sprite blends (`tim.md`). Only for sprites that have one; `objects[k].stp_files` lists them per palette (null when none) |
| `doors/door_<id>.gltf` | door models textured with this map's VRAM |
| `training/slots_p3.png`, `slots_p4.png` | training maps only: the slot strip (256 × 32, page (704, 0) v 0xD8–0xF7) as indexed PNG keeping the 4bpp indices, through CLUT (48, 486) / (64, 486) |
| `training/slots_p<p>.stp.png` | grey mask, 255 where the texel's colour has the STP bit (always written: all 0 for p3, all 255 for p4) |
| `training/slots.json` | sidecar: `asset_id` = the image holding the strip, `vram` (page, uv rect, VRAM rect, per palette: CLUT pos + id, raw u16 colours, CLUT source, tpage + semi-trans rate, drawing sprite), `source_images` (every image writing into the rect, load order), `code_refs` |
| `overview.png` | **human check**: background (palette 0) + object sprites (frame 0, opaque) + walkable cells (green), trigger cells (orange), spawns (cyan), NPC digimon (yellow), doors (magenta) |
| `map.json` | everything: table entry (incl. display name, sound, flags), header, setup, camera, TFS palettes + tile headers, image TIM headers/VRAM, objects (+ placement in VRAM, missing texels, whether used), instances, spawns, warps (+ target map name), digimon (+ type name, stats, AI, waypoints), doors, toilet, collision values, overview counts |

## Verification (run on every conversion)

- Every table entry with a name has its files (except the 3 known missing); at most one MAP file outside the table.
- MAP and TFS parse; TFS ends exactly after its tiles; MAP bytes explained.
- Sprites used by object instances are fully in loaded VRAM (unused definitions may point at unloaded CLUTs, e.g. MAYO10 object 17). UVs wrap inside the page like the GPU's 8-bit UVs (MIST02 object 10 is 480 px tall, FACT08B object 89 crosses u = 256; `uv_wraps` in `map.json`). **Exception:** GIAS06B objects 63–66 use CLUT row 485, which neither the map nor its TFS loads (its twin GIAS06A has the same images); it must come from an event or leftover VRAM — sprites are exported with those texels transparent. Same for **ICSA05** (Ice Sanctuary, map 101, reached only through warp crystals): objects 0–2 read 4bpp pages at x = 448 / 512 that the map does not load.
- Door textures fully covered by the map's VRAM.
- Training maps: the slot strip and its two CLUTs fully in loaded VRAM. Informational (always passes, detail + `manifest.json` `training_slots`): whether the three maps' strips are identical.
- Projected collision lands on the background.

## Open questions

- Object `flag` and `transparency` semantics are only partly read (overview draws sprites opaque).
- Map IDs 0x58–0x60 and 0x84–0x87 randomise the first 0x23 object instances (snow/leaf effects, `loadMapObjects`).
- Warp crystals (maps 101–103), training poop (0xA5), toilets, fishing/curling/shop/arena hooks are handled by code, not map data.
- Doors in `tmd_files` stay untextured; the per-map doors here carry the textures.
