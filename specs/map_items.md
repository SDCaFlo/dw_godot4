# Items and chests on the map (port spec)

Status (2026-10-24): spec written, not coded. This is step 5b of `specs/script.md` §3.1.

Things to pick up on the field:
- **Items on the ground:** `SPAWN_ITEM` (0x74, 241 uses) puts an item on a tile. The tamer picks it up by walking next to it, with a "Woah!" box.
- **Chests:** `SPAWN_CHEST` (0x75, 71 uses) places a treasure chest model, mostly in map setups. ✕ next to it opens its tray, the item goes to the bag, and a trigger remembers the chest is empty.
- **Their boxes and sounds:**
  - the pickup / chest window;
  - "I can't hold anymore." when the bag is full;
  - "Hey! It's empty!" for an open chest;
  - the award box's sound, which waited for audio.

The inventory already exists (`GameState.give_item` / `remove_item` / `item_count`, `specs/game_state.md`), so this step adds what lies on the map and the tamer's two states that take it. Items dropped by beaten enemies use the same items on the ground; they come with the battles (5d, `spawnDroppedItems`, `battle_ui.c:405`).

All `file:line` references are in `external-resources/dw_decomp/src/main/` (US) unless they name another folder.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `SCRIPT_OP_SPAWN_ITEM`, `SCRIPT_OP_SPAWN_CHEST` (`script_interp.c:2117`, `:2122`) | the opcodes | `ScriptInterpreter` |
| `spawnItem`, `deleteDroppedItem`, `clearDroppedItems`, `initializeDroppedItems` (`item.c:2437`, `:2462`, `:2468`, `:2399`) | `DROPPED_ITEMS[11]`, the items on the ground | `MapItems` (`scripts/field/map_items.gd`) |
| `renderDroppedItem`, `renderOverworldItem`, `renderDroppedItemShadow` (`item.c:2430`, `:2478`, `:2508`) | the item's icon facing the camera and its shadow | `MapItems` |
| `setItemTexture` (`utils2.c:288`) | the icon's 16 × 16 cell of `ITEM.TIM` and its palette | `MapItems` |
| `checkItemPickup` (`tamer.c:618`) | walking next to an item starts the pickup | `Tamer` (walk state) |
| `tamerTickPickupItem` (`tamer.c:1401`, tamer state 7) | the pickup box | `Tamer.tick_pickup_item` |
| `pickupItem`, `giveItem` (`item.c:2633`, `:2562`) | the bag | `GameState.give_item` (exists) |
| `initializeChest`, `clearChests`, `emptyChests`, `renderChest` (`map_object.c:443`, `:286`, `:925`, `:467`) | `CHEST_ARRAY[8]`, the chest model | `MapChests` (`scripts/field/map_chests.gd`) |
| `spawnChest` (`map_object.c:841`) | a chest on a tile, its blocked cells, its interaction tile | `MapChests.spawn` |
| `tickOpenChestTray`, `tickCloseChestTray` (`map_object.c:1083`, `:1096`) | the tray sliding out / back | `MapChests` |
| `checkChestCollision` (`tamer.c:1287`), the end of `checkMapInteraction` (`tamer.c:714`) | ✕ next to a chest starts tamer state 14 | `field.gd` `_check_map_interaction` |
| `tamerTickTakeChest` (`tamer.c:1493`, tamer state 14) | the chest box, the trigger | `Tamer.tick_take_chest` |
| `renderItemPickupTextbox` (`tamer.c:801`) | the box's two lines (US layout) | the `MessageBox` strings |
| `tamerTickAwardSomething` sub-state 4's `playSound(0, 7)` (`tamer.c:1811`) | the award box's sound | `Tamer.tick_award_something` |

## 2. Original behaviour

### 2.1 Items on the ground (`spawnItem`, `DROPPED_ITEMS`)

- **Slots:** 11 slots (`DROPPED_ITEMS[11]`), each with an item type (0xFF = empty), its tile (`tileX`, `tileY`) and its sprite point.
- **`spawnItem(item, tileX, tileY)`:**
  - takes the first empty slot (none free: nothing happens);
  - its point is the tile's centre, `x = (tileX − 50)·100 + 50`, `z = (50 − tileY)·100 − 50`, at the tamer's current height (`ENTITY_TABLE[0]->location.vy`);
  - it adds the slot's render object.
- **Opcode:** `SPAWN_ITEM item, x, z` (5 bytes: u8, s16, s16) passes the two shorts as the tile.
- **Lifetime:** the items stay until they are picked up or the map changes. `changeMap` calls `clearDroppedItems` (`map.c:5335`), so items aren't kept across maps. Nothing saves them; a map's setup spawns them again when it runs.
- **Drawing (`renderOverworldItem`, every frame while the map layer is shown):**
  - The point is projected (`otz` = SZ / 4 from `gte_stszotz`). The icon is a square `width = (VIEWPORT_DISTANCE << 7) / (otz·4)` pixels wide, so it shows a 128-unit square in the world at that depth. It is centred on the projected point and drawn at ordering-table entry `otz >> 2`, so it sorts against the models like them.
  - It is drawn only when `0 < otz >> 2 < 0x1000`.
  - **Texture (`setItemTexture`):** 4bpp page (320, 0), which holds `ETCDAT/ITEM.TIM`; UV `(type % 16)·16`, `(type / 16)·16`, 16 × 16 (15 on the last row or column). The palette is (0xE0, 0x1E8 + `ITEM_CLUT_DATA[type]`): `item_data.icon_clut`, one of ITEM.TIM's 24 palettes.
  - **Quirk kept:** with `width ≥ 0x20` (close to the camera) the UV size is set to 15 × 15, dropping the icon's last row and column.
  - Colour 0x80 (neutral), opaque.
- **Shadow (`renderDroppedItemShadow`):** a 200 × 200 square on the ground (y 0) under the point.
  - It is subtractive (`getTPage(1, 2, 832, 256)`: 8bpp, abr 2), colour 0x30, and drawn at entry 0xFFD, just over the background, behind every model.
  - Texture: UV (0x40, 0x80, 63 × 63) of page (832, 256), palette (0, 0x1E7). That is `ETCDAT/SPOT256.TIM` (VRAM (832, 384), CLUT row 487): its cell at (64, 0), 63 × 63.
  - The entities' drop shadows use the same texture (`drop_shadow.c`; not ported yet, §6).

### 2.2 Picking up (`checkItemPickup`, tamer state 7)

- **The check** runs every frame of the tamer's walk state, right before `checkMapInteraction` (`tamer.c:586`):
  - the tamer's tile (`getModelTile`) is compared with each item's;
  - the first item within one tile on both axes (`|dx| ≤ 1`, `|dz| ≤ 1`) is `PICKED_UP_DROP_ID`;
  - if `HAS_PICKED_UP_ITEM` isn't set, it is set and the tamer goes to state 7;
  - when no item is near, `HAS_PICKED_UP_ITEM = 0`.

  So the same item doesn't start again until the tamer has left it (an item left behind because the bag was full).
- **`tamerTickPickupItem` (state 7):**
  - **0:**
    - `startAnimation(tamer, 0xC)` (the pick-up animation), the camera stops following;
    - the text area: rows 0xC–0x2F cleared;
    - `DIGIMON_NAME(0)` at row 0xC (the tamer's name; the US box doesn't show it, below);
    - the item's name at row 0x18, "Woah!" (`MAIN_D_801341FC`) at row 0x24;
    - `TAKE_CHEST_STATE = 0`, the frame counter 0.
  - **1:** when UI box 1 is free, it opens it (`createAnimatedUIBox(1, color 0, features 2)`) from the 10 × 10 rect around the tamer's screen point (`getEntityScreenPos(tamer, 1)` − 5) to (−130, 42, 262, 59), drawn by `renderItemPickupTextbox`.
  - **2:** counter + 1. On ✕ newly pressed (`isKeyDown`) with the counter above 4:
    - if the counter is below 0x3C, `playSound(0, 3)`;
    - **`giveItem(type, 0)` fails** (the item at 99, or no free slot): row 0x18 gets "I can't hold anymore." (`MAIN_D_80122D68`), `TAKE_CHEST_STATE = 1`, the counter is reset, go to 3;
    - **otherwise:** `playSound(0, 7)`, go to 4.
  - **3:** counter + 1; ✕ newly pressed after 4 frames (sound 3 below 0x3C) → 4.
  - **4:**
    - the box shrinks back to the tamer (`removeAnimatedUIBox`);
    - with `TAKE_CHEST_STATE == 0`, `pickupItem`: `giveItem(type, 1)` and, if it succeeded, the item leaves the ground;
    - tamer state 0, the camera follows again.
  - The counter is capped at 10 after every tick. The "below 0x3C" test is therefore always true: the sound always plays.
- **`giveItem(item, amount)` (exists as `GameState.give_item`):**
  - the first slot already holding the item: +amount up to 99, true; an item already at 99 returns false, without looking for another slot;
  - otherwise the first empty slot takes the item with `amount`.

  **Quirk kept:** the test call with amount 0 puts the item in an empty slot with 0, and `pickupItem`'s +1 then lands in that slot. The port's `give_item` already does (an empty slot takes the item with amount 0).

### 2.3 Chests (`spawnChest`, `CHEST_ARRAY`)

- **Slots:** 8 (`NUM_CHESTS`); `item` 0xFF = empty. `initializeChest` (at game start, `main.c:3454`) loads `ETCNA/TAKA.TMD`: two objects, the box (0) and its tray (1), the tray's coordinates a child of the box's (`GsInitCoordinate2(&CHEST_COORDS[0], &CHEST_COORDS[1])`).
- **`SPAWN_CHEST item, x, y, z, rotation, trigger`** (11 bytes: u8, s16 × 4, u16) → `spawnChest(x, y, z, rotation, item, trigger)`. In the first empty slot:
  - **already taken** (`isTriggerSet(trigger)`): `isTaken = 1` and the tray out (`trayLocation.vz = −160`); otherwise `isTaken = 0`, the tray in (0);
  - `rotation.vy = rotation`, the tray's rotation 0;
  - the point (x, y, z) → its tile (`getModelTile`); `setImpassableSquare(tileX, tileY, 2)` blocks the 4 × 4 cells x − 2 … x + 1, y − 2 … y + 1 (the US loop's ends are exclusive);
  - the chest stands at the tile's centre, `x = tileX·100 − 4950`, y 0, `z = 4950 − tileY·100`;
  - **the interaction tile** is 4 tiles in front of it, toward the tray: rotation 0 → tileY + 4; 0x800 → tileY − 4; 0x400 → tileX − 4; 0xC00 → tileX + 4 (other rotations: the chest's own tile).
- **Lifetime:** the chests are emptied (`emptyChests`, `item = 0xFF`) when the map is unloaded (`map_object.c:929`); the map's setup spawns them again, and the trigger says whether each is taken.
- **Drawing (`renderChest`):** the box at its location and rotation, the tray at `trayLocation` / `trayRotation` relative to the box (so `vz = −160` slides it out along the box's own axis), scale 1; skipped when off screen (`isBoxOffScreen`, 100 × 100).
- **`checkChestCollision`** (from `checkMapInteraction`, only in tamer state 0, after the cells): the first chest whose interaction tile is within one tile of the tamer's (`|dx| ≤ 1`, `|dz| ≤ 1`). With ✕ newly pressed (`CHANGED_INPUT`): `INTERACTED_CHEST`, tamer state 14. Unlike the cells and the NPCs, this doesn't check `IS_SCRIPT_PAUSED`.

### 2.4 Taking a chest (`tamerTickTakeChest`, tamer state 14)

- **0:**
  - `startAnimation(tamer, 0)`, partner state 0xB (idle), the camera stops following, the tamer faces the chest (`entityLookAtLocation`);
  - the text area: the tamer's name at row 0xC; **not taken:** the item's name at row 0x18, "Woah!" at row 0x24, `TAKE_CHEST_STATE = 0`; **taken:** "Hey! It's empty!" (`MAIN_D_80122D80`) at row 0x18, `TAKE_CHEST_STATE = 2`.
- **1:** when UI box 1 is free, the tray slides out 20 a frame (`tickOpenChestTray`). At −160 it stops and sets `isTaken = 1`, and the box opens as for the pickup, with the counter at 0. Then → 2 (`TAKE_CHEST_STATE` 0) or → 4 (empty).
  - An empty chest's tray is already at −160, so it passes at once.
- **2:** counter + 1; with ✕ **held** (`POLLED_INPUT`, not newly pressed) and the counter above 5:
  - the counter is reset;
  - **`giveItem(item, 0)` fails:** "I can't hold anymore." at row 0x18, `TAKE_CHEST_STATE = 1`, → 3;
  - **otherwise:** `setTrigger(chest.trigger)`, → 4. There's no sound here, unlike the pickup.
- **3:** the tray slides back 20 a frame (`tickCloseChestTray`, `isTaken = 0` at 0), then → 4. The chest can be opened again later.
- **4:** counter + 1; ✕ held after 5 frames:
  - the box shrinks to the tamer;
  - with `TAKE_CHEST_STATE == 0`, `giveItem(item, 1)`;
  - tamer state 0, partner state 1, the camera follows.
- **Quirk kept:** the item is given when the box closes, but the trigger is set when ✕ is first pressed; both happen in the same visit, so nothing is lost.

### 2.5 The box (`renderItemPickupTextbox`, US)

The text rows above, shown in UI box 1 (colour 0, features 2) by `renderString(color, x, y, w, h, u, v, layer 5, shadow 0)`:
- **`TAKE_CHEST_STATE` 0:** the item's name, colour 0xF (yellow), at (−125, 0x2D) from row 0x18, 0x60 wide; and "Woah!", colour 0, at (−125, 0x39) from row 0x24, 0x5A wide.
- **1 (bag full):** row 0x18 ("I can't hold anymore."), colour 0, at (−125, 0x39), 0xF0 wide; the item's name line is gone.
- **2 (empty chest):** row 0x18 ("Hey! It's empty!"), colour 0, at (−125, 0x39), 0x90 wide.

Then `renderUIBox(1)` and `TEXTBOX_OPEN_TIMER + 1`. The other versions also show the tamer's name (row 0xC) and centre the item's name.

## 3. Godot design

- **`MapItems`** (`scripts/field/map_items.gd`, a node of the field's 3D world): the 11 slots.
  - `spawn(item_key, tile)`, `near(tile) -> int` (the slot, −1), `remove(slot)`, `clear()`.
  - Each item is a camera-facing quad (as the overlay sprites, `MapOverlays`) at its point. Its size is the projected 128-unit square, and it is placed at the point's view depth, so it sorts against the models by depth as on the PSX.
  - The quad's texture is the item's 16 × 16 cell of the `ITEM.TIM` palette PNG (`tim_files/ETCDAT/ITEM.p<n>.png`, n = `icon_clut`), with the 15 × 15 quirk when close.
  - The shadow is a subtractive quad on the ground with the `SPOT256.TIM` cell, drawn just over the background (as I-5's poop shadow).
- **`MapChests`** (`scripts/field/map_chests.gd`): the 8 slots, `TAKA.gltf` loaded once (`Content.load_model`).
  - The box node at its tile's centre and rotation, the tray node a child at (0, 0, tray z).
  - `spawn(item, point, rotation, trigger)`, `near(tile) -> int`, `tick_open(k) -> bool`, `tick_close(k) -> bool`, `clear()`.
  - It blocks its cells through `FieldMap` (the `set_impassable_rect` of 5a, with the square's exact cells).
- **`Tamer`:**
  - state 7 (`tick_pickup_item`) and state 14 (`tick_take_chest`), following §2.2 / §2.4 sub-state by sub-state, on the existing `MessageBox` (box 1, the award box's rect) with the §2.5 strings;
  - the walk state's pickup check before the map interaction, with `has_picked_up` (`HAS_PICKED_UP_ITEM`);
  - animation 0xC through `play_scene_animation`.
- **Field:**
  - `_check_map_interaction` ends with the chest check;
  - the map load clears the items and chests (as `changeMap` / `unloadMap` do) before the MAPHEAD setup spawns them;
  - the interpreter gets `map_items` / `map_chests` for the two opcodes.
- **Texts:** `GameData` text `text/main/tamer` (`MAIN_D_801341FC`, `MAIN_D_80122D68`, `MAIN_D_80122D80`), the item's name from its record, all in the current language.
- **Sounds:** `playSound(0, 3)` and `(0, 7)` through `Sound` (specs/sound.md), and the award box's `(0, 7)` now that sound exists.
- **Content:** items by key (`dw1:...`); the opcode's numeric id goes through `GameData.key_of("items/item_data", id)`. The icon cell and palette come from the record (`id` for the cell, as the original's texture layout, and `icon_clut`). A mod's item without an icon in `ITEM.TIM` would need its own icon file; that comes with modding.

## 4. Data

- **Asset porter, already converted:**
  - `tim_files/ETCDAT/ITEM.*.png`: the icons, one PNG per palette, VRAM (320, 0), palettes at (224, 488 + n);
  - `tim_files/ETCDAT/SPOT256.*`: the shadow, VRAM (832, 384), palette row 487;
  - `tmd_files/ETCNA/TAKA.gltf`: the chest, nodes `object_0` (box) and `object_1` (tray).
- **Data porter, already converted:** `items/item_data` (name, `icon_clut`, key); the text table `text/main/tamer`.
- **Nothing new is saved:** the items on the ground aren't saved (`specs/game_state.md`: "dropped items" are runtime only), and the chests' state is their triggers.

## 5. Verification

- **Tests** (`tests/test_map_items.gd`, on the porter output):
  - `spawnItem`'s slots and tile point, 11 at most;
  - `near` within one tile;
  - the pickup's sub-states with a test pad: the box, ✕, the bag full on an item at 99 (the item stays, `has_picked_up` holds until the tamer leaves);
  - `give_item(item, 0)` on an empty slot;
  - `spawnChest`:
    - the taken state from its trigger;
    - the 4 × 4 blocked cells;
    - the interaction tile for the four rotations;
  - the chest's sub-states: the tray from 0 to −160 in 8 frames, the trigger at the first ✕, the item at the close, the empty chest's text, the bag-full path closing the tray;
  - a real map's setup spawning its chests (e.g. OGRE11's `SPAWN_CHEST` in its 0xFE section, trigger 672).
- **Human checks** (VERIFY.md "Items and chests"):
  - an item on the ground (where a script spawns one): the icon floats at the tile with its shadow, the box when you walk to it, the item in the bag;
  - a chest: the model, ✕ next to it, the tray, the box, then "Hey! It's empty!" the second time and after leaving and coming back;
  - the bag full.

## 6. Open questions

- **The entities' drop shadows** (`renderDropShadow`, `drop_shadow.c`): the same SPOT256 texture under the tamer, the partner and the NPCs, a radius-sized square. They aren't drawn in the port yet. They're small and would share the item shadow's material, so they could come right after this step (to decide).
- **`getEntityScreenPos(tamer, 1)`** for the box's start point is the existing `Tamer.screen_rect`.
- **The pick-up animation 0xC:** does the tamer model have it (`BOYS.gltf` anim 12)? Check while coding; the C does nothing for a missing animation, like `PsxAnimator.play`.
- **The item height** is the tamer's height at spawn time: normally 0. A script spawning an item during a scene with the tamer off the ground would float it; kept.
