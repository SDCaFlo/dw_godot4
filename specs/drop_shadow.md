# Drop shadows

Status (2026-10-24): coded as the entity component `DropShadow` (`scripts/field/drop_shadow.gd`, `scenes/field/drop_shadow.tscn`), the first component of the scene refactor (`specs/scenes.md` §7 step 3).

## 1. The C code

`renderDropShadow(entity)` (`drop_shadow.c:19`), called at the end of `renderDigimon` (`model.c:2881`) for every entity it draws:
- **When:** `renderDigimon` returns early when the entity is not on the map (`isOnMap == 0`) or off screen (`isOnScreen == 0`, unless `isOnMap == 2`). So the shadow shows exactly when the model does.
  - The tamer's (entity 0) also needs `PLAYER_SHADOW_ENABLED` (`model.c:87`, 1). `initializeTamer` sets it to 1 (`tamer.c:341`); only the ending clears it (`endi.c:426`), so in the field it's always on.
  - `getTileTrigger(&location) == -1`: no shadow on a blocked cell.
- **The square:** four ground points at the entity's location, `x ± radius`, `z ± radius`, `y` = the entity's `location.vy`. `radius` = `DIGIMON_DATA[type].radius`. The square is in world axes; it doesn't turn with the entity.
- **The primitive:** a `POLY_FT4`, semi-transparent, `getTPage(1, 2, 832, 256)` (8bpp, abr 2 = subtractive), palette (0, 0x1E7), UV (0x40, 0x80) 63 × 63, colour 0x30, at ordering-table entry 0xFFD (just over the background, behind every model).
  - The same texture, colour and entry as the item shadow (`renderDroppedItemShadow`, `specs/map_items.md` §2.1): `ETCDAT/SPOT256.TIM`, its cell at (64, 0).
- `renderAABB` (the entity's collision box) follows; it returns at once (`aabb.c`, a debug leftover), so nothing is drawn.

## 2. Godot design

- `DropShadow` is a `MeshInstance3D` component under the entity (`Digimon.tscn`, `Tamer.tscn`, `specs/scenes.md` §4.1). Its `entity` export defaults to its parent.
- It is `top_level`, so the square stays in world axes. Every frame (`_process`, presentation only) it:
  - moves to the entity's position;
  - takes the entity's `radius` (a `2·radius` square);
  - shows only when the entity is on the map, on screen and its cell isn't blocked (`FieldMap.tile_trigger != -1`). An entity without a field (headless tests) has no shadow.
- The material is `DropShadow.material()`, one shared `ShaderMaterial` used by the items' shadows too (`MapItems`).
- **The subtraction is done in gamma values, as on the PSX.** Godot's 3D blends in linear light, where the night's dark grounds are so close to 0 that a `blend_sub` of the spot's faint edge already wipes them to black: the whole spot turned into a hard black shape at night (reported 2026-10-24). So the shader reads the screen behind it (`hint_screen_texture`: the copy Godot makes before the transparent pass, with the background and the opaque models), converts it to gamma, subtracts the raw texel values (the PSX's own, no `source_color`) times 0x30 / 0x80, and converts back.
  - On the PSX too a dark ground ends black where the spot is strong: at night only the spot's outer part fades (texels under about 0x58 on Native Forest's night ground), by day the whole gradient shows.
- Approximations:
  - depth-tested rather than drawn at entry 0xFFD, so the shadow can darken a model that stands far behind it (a small difference);
  - the screen copy is taken once before the transparent pass, so where two shadows overlap (the tamer's and the partner's) the ground is darkened once, not twice; and a semi-transparent model drawn before it is not under it.
- Half a unit over the ground, like the item shadow.

## 3. Checks

- The test suites and the exit scan pass unchanged: the shadow only presents, no logic reads it.
- `VERIFY.md` "Drop shadows".
