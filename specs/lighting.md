# Field lighting (port spec)

Status (2026-10-24): ported for ISSUES.md I-2 (the models too bright at night): `PsxLit` (`scripts/content/psx_lit.gd`), `FieldLighting` (`scripts/field/field_lighting.gd`), `FieldMap.set_time_of_day`; `tests/test_lighting.gd`. Before, every model was drawn unshaded.

How the original lights the 3D models on the field (Digimon, the tamer, doors, props): the map's 3 directional lights and a fixed ambient, computed per vertex by the GTE, with the lights' colours scaled by the time of day.

All `file:line` references are in `external-resources/dw_decomp/src/main/`, US version.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `loadMapSetup` (`map.c:4143`) | the map's 3 lights (`GsSetFlatLight`), `MAP_LIGHTS`; the ambient | `FieldMap.load_map` → `FieldLighting` |
| `updateTimeOfDay` (`map.c:4301`) | the lights scaled by the hour, on map entry | `FieldMap.set_time_of_day` |
| `tickDaytimeTransition` (`map.c:4525`) | the same scale, at the end of the 25-frame fade | `FieldMap.set_time_of_day` (called at its end) |
| `GsSortObject4J`, `GsSetLightMatrix` (libgs; `drawObject`, `map_object.c:1070`; `model.c:2919`) | the per-vertex lighting of lit polygons | the `psx_lit` shader |

## 2. Original behaviour

### 2.1 The lights

- **Map data** (`loadMapSetup`; `map.json` `setup.lights`, `asset_porter/specs/map.md`): 3 lights, each a direction (x, y, z) and a colour (r, g, b, 0–255). `MAP_LIGHTS` keeps the map's values.
  - On the maps checked (MAYO01, TWNB01, TWNB04) only light 0 is on: direction (0, 170, z), down in PSX axes (+y is down), colour 178 (0.7); lights 1 and 2 are black.
- **Ambient:** `GsSetAmbient(0x800, 0x800, 0x800)`: 0.5 on every channel, on every map. The map's own ambient values are read and unused.
- **The time of day** (`updateTimeOfDay`, on map entry; `tickDaytimeTransition` at the end of its fade, frame 25):
  - day: the map's colours;
  - evening (16–20 h): green and blue × 7 / 10 (integer), red unchanged;
  - night (20–6 h): × 5 / 10 (`/ 2` at the end of the fade, the same integers);
  - maps with flag 0x40 (no time of day) keep the map's colours.
  - The lights change in one step at the end of the fade, when the palette does: during the 25 frames only the background fades.

### 2.2 Lighting a vertex (the GTE)

For the lit polygons of a TMD (flag bit 0 clear; the asset porter's `lit` materials):
- **Intensity** per channel: `I = ambient + Σ_lights colour_i × max(0, N · L_i)`, with:
  - `colour_i` the light's colour / 256 (the GTE's light colour matrix holds colour × 16, 4096 = 1.0);
  - `L_i` the light's direction reversed and normalised (`GsSetFlatLight` takes the direction the light travels);
  - `N` the vertex normal in world space (`GsSetLightMatrix` with the object's local-to-world matrix).
- **Per vertex:** gouraud polygons light each vertex with its normal; flat polygons light once with the face's normal. The colour is then interpolated across the polygon.
- **The colour:** the polygon's colour (128, 128, 128 for a textured lit polygon) × I, clamped to 255. The GPU then multiplies the texel by colour / 128 and clamps each 5-bit channel. A texel can reach up to twice its value: by day the top of a model gets 0.5 + 0.7 = 1.2, a side 0.5.
- **Unlit polygons** (the porter's `KHR_materials_unlit`) and those with the brightness bit off (TGE) aren't lit.
- **No fog or depth cue** on the field (no `GsSetLightMode`).

### 2.3 Semi-transparent polygons

- A semi-transparent polygon (TMD mode bit 1, ABE) blends only the texels whose colour has the STP bit (bit 15), with its tpage's mode `abr`: 0 half background + half texel, 1 background + texel, 2 background − texel, 3 background + texel / 4. Its other texels are drawn opaque. The texel is lit (or not) first, as any other.
- E.g. the poop (`ETCNA/UNTI`): its body has no STP texels; its shadow disc has them all, subtracted from the ground (ISSUES.md I-5).

## 3. Godot design

- **`PsxLit`** (`scripts/content/psx_lit.gd`): the shader's code is built there, one variant per blend / culling mode (Godot can't switch render modes per material). Unshaded spatial, lighting in `vertex()` (gouraud, as the GTE):
  - `I = psx_ambient + Σ psx_light_i_color × max(0, dot(N_world, -psx_light_i_dir))`;
  - `fragment()`: the texel (and the vertex colour, white when the mesh has none) × I, clamped to 1, computed on the sRGB values as the PSX does on its 5-bit ones, then converted to linear for Godot.
  - Texels with alpha 0 (colour 0x0000) are discarded; double-sided materials don't cull.
  - **Semi-transparency** (§2.3): a semi-transparent material with an STP mask (`extras.stp_texture`) gets a second pass (`next_pass`): the first draws the non-STP texels opaque, the second only the STP ones, with `blend_mix` at alpha 0.5, `blend_add`, `blend_sub` or `blend_add` at a quarter. Without a mask every texel is opaque, as on the PSX. Unlit semi-transparent materials take the same passes with the lighting off.
  - Godot blends in linear colour, the PSX in its 5-bit space: the blended texels may look slightly different (as the map sprites, `specs/map_objects.md` §6).
- **Global shader parameters** (`project.godot` `[shader_globals]`): `psx_ambient`, `psx_light_0_dir` … `psx_light_2_dir`, `psx_light_0_color` … `_2_color`. Their defaults are a typical map's (one light from above at 0.7), so models outside the field look as on a map by day. `FieldLighting.current` keeps the values last set (the headless renderer can't read globals back).
- **`Content._psx_materials`:** a lit material, or a semi-transparent one with an STP mask, becomes a `PsxLit` `ShaderMaterial` with its texture; the other unlit ones stay unshaded as before. It reads the porter's material extras from the glTF (`abr`, `semi_transparent`, `stp_texture`) by material name.
- **`FieldLighting`** (`scripts/field/field_lighting.gd`, static): `apply(lights, time_of_day)` converts the map's PSX lights (direction to Godot axes, colour / 256, the time-of-day scale with the C's integer maths) and sets the globals.
  - `FieldMap.load_map` keeps the map's lights; `set_time_of_day` applies them (it runs on map entry and at the end of the fade, as the C).

## 4. Verification

- `tests/test_lighting.gd`: the time-of-day scale (day / evening / night, the integer maths); the globals set by `FieldMap`; `Content.load_model` gives the lit surfaces the `psx_lit` material and keeps unlit ones unshaded.
- `tests/render_check.gd` with Agumon on screen, by day and at night, next to the original's screenshot (`issues/evidence/dw_night_real_game.png`).
- `VERIFY.md`, "Field lighting": the models by day (lit from above: lighter heads and shoulders, darker sides), in the evening (warmer), at night (darker); the change at the end of the hour's fade.

## 5. Open questions

- **The light's direction:** `GsSetFlatLight` is taken to give the direction the light travels (so a light pointing down lights the tops of the models). Checked by eye against the game.
- **Scaled models:** `GsSetLightMatrix` takes the local-to-world matrix with its scale, so a scaled model (the poop piles, scale size / 10) is lit by scaled normals: darker when smaller. The port normalises the normals.
- **Brightness-off (TGE) polygons** are drawn lit by the port if the glTF material is lit: the porter keeps the flag in the material's extras, not read yet.
