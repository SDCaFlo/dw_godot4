# Issues

Bugs found while playing, with their evidence. One entry per issue: what you see, where (map, time of day), what the original does, the screenshot(s), and the cause once known.

Screenshots go in `issues/evidence/`. They show game art, so the folder is gitignored (and `.gdignore`d, so Godot doesn't import them): only this list is committed. Name them `<id>_<short>.png` or keep the original name and link it here.

Status: **open**, **investigating**, **fixed** (with the commit), **won't fix** (with the reason).

## Open

### I-2. The models too bright at night
- **Seen:** at night (File City, 20:06) the tamer and Agumon keep their day colours.
- **Evidence:** `issues/evidence/dw_issue_top_of_tree_and_too_light_texture.png`; the original at night: `issues/evidence/dw_night_real_game.png`.
- **Expected:** the original lights the models with the map's 3 lights, scaled by the time of day (`updateTimeOfDay`, map.c:4301: × 1.0 day, red 1.0 / green, blue 0.7 evening, × 0.5 night; `asset_porter/specs/map.md` "TFS").
- **Cause:** the port drew every model unshaded, so the field lighting wasn't reproduced at all (`Content._psx_materials`).
- **Status:** fixed, to check in the game (2026-10-24, `specs/lighting.md`): lit models take the map's lights and the 0.5 ambient per vertex, scaled by the time of day at the end of the hour's fade. Rendered on TWNB01 (`tests/render_check.gd -- TWNB01 200 200 20 2 360 330`): Agumon lit from above, sides darker; at night his brightest pixels go from 255 to 213. Left to check against the game: the light's direction (open question in the spec) and the overall brightness.

### I-3. The models look too pixelated from far away
- **Seen:** small, distant models look blocky.
- **Evidence:** `issues/evidence/dw_issue_top_of_tree_and_too_light_texture.png`; `issues/evidence/dw_night_real_game.png`.
- **Notes:** the PSX also draws at 320 × 240 with no texture filtering; the reference screenshot looks like an emulator at a higher internal resolution (smooth edges). To decide: keep the PSX look, or render the 3D at 2× / 4× like an emulator's upscaling, while the background stays at its own resolution.

### I-5. The poop has a black outline
- **Seen:** a dark outline around the poop model. It was there before step 5a.
- **Evidence:** `issues/evidence/dw_issue_poop_outline.png`; the original: `issues/evidence/dw_real_poop_look.png`.
- **Cause:** not known yet. The model is `ETCNA/UNTI.TMD` (`PoopPiles`); the outline may be texels that should be transparent or semi-transparent.

## Fixed

### I-1. The tamer drawn over trees (draw order)
- **Seen:** on MAYO01 the tamer walks on top of trees; on other maps too (TWNB01, the bush on the right).
- **Evidence:** `issues/evidence/dw_issue_top_of_tree_and_too_light_texture.png`
- **Expected:** the parts of the background in front of him (tree trunks, bushes, roofs) cover him. These are the map's overlay sprites, ported in step 5a (`specs/map_objects.md`).
- **Status:** fixed (2026-10-24, `fbcf612`).
- **Cause:** the sprites in front of him were drawn without the texels that carry the STP bit. `MapOverlays` drew a sprite's STP texels only in its semi-transparent pass, and an opaque sprite (transparency 4) has none: those texels were never drawn. On the PSX the STP bit only matters on a semi-transparent polygon, so an opaque sprite draws them all. MAYO01's bush in front of the toilet is one: 3,959 opaque sprites on 90 maps have STP texels.
- **Fix:** an opaque sprite ignores its STP mask (`MapOverlays._material`). Reproduced and checked with `tests/render_check.gd -- MAYO01 250 40 20 0 430 190`: Agumon stands behind the bush, the bush now covers him. `tests/test_map_objects.gd` checks the bush's material.

### I-4. Holes in the background (grey speckles)
- **Seen:** grey dots across the rocks, at night.
- **Evidence:** `issues/evidence/dw_issue_missing_background_sprite_texture.png`
- **Cause:** texel colour 0x0000 is transparent on the PSX, so those background pixels show what is behind them: the frame's black clear on the PSX (`GsSortClear(0, 0, 0)`, main.c:3960), Godot's default grey clear colour in the port. The night palettes have more pure-black colours, so more holes (MAYO01: 958 at night, none by day).
- **Status:** fixed (2026-10-24, `fbcf612`): the project's default clear colour is black (`project.godot`). `tests/render_check.gd -- MAYO01 200 200 20 2` renders the night palette: the 501 transparent texels on screen are black.

## Ideas (not bugs)

### D-1. The debugger: pick a map to teleport to, a bigger view
- **Asked:** choose the map to warp to from a list (today `[` / `]` step through them), and a bigger window: the game keeps its 4:3 aspect, with the debug information readable beside it instead of inside the 320 × 240 picture.
