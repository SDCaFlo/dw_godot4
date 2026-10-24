# Issues

Bugs found while playing, with their evidence. One entry per issue: what you see, where (map, time of day), what the original does, the screenshot(s), and the cause once known.

Screenshots go in `issues/evidence/`. They show game art, so the folder is gitignored (and `.gdignore`d, so Godot doesn't import them): only this list is committed. Name them `<id>_<short>.png` or keep the original name and link it here.

Status: **open**, **investigating**, **fixed** (with the commit), **won't fix** (with the reason).

## Open

### I-3. The models look too pixelated from far away
- **Seen:** small, distant models look blocky.
- **Evidence:** `issues/evidence/dw_issue_top_of_tree_and_too_light_texture.png`; `issues/evidence/dw_night_real_game.png`.
- **Notes:** the PSX also draws at 320 × 240 with no texture filtering; the reference screenshot looks like an emulator at a higher internal resolution (smooth edges).
- **Status:** fixed (2026-10-24, `b6538ef`; checked in the game: "the 4x render looks cool"). Render the 3D at 4× by default, like an emulator's upscaling, with the choice in the debugger (D-1, "Render" tab: 1× the PSX's to 4×). The field's `render_scale` sets the 3D viewport to 320 × 240 × the scale, shown at the PSX size; the background canvas layer scales with it, so it keeps its exact pixels; every screen position goes through `FieldMap.unproject`. The game window is now 1280 × 960 (4×).

### I-6. Textures shimmer (Palmon, Aruraumon)
- **Seen:** Palmon's body shimmers: a fine checkered pattern that changes from frame to frame while it animates. Still there at 4×, and on other Digimon: Aruraumon on MAYO04A (dark speckles on its yellow body and its flower bud).
- **Evidence:** `issues/evidence/dw_issue_palmon_texture_shimmering.mp4` (MAYO03, night); `issues/evidence/dw_issue_texture_shimmering.mp4` (MAYO04A, Aruraumon, 4×).
- **Cause:** not aliasing (the first guess): the texture sampling. Some polygons map a whole face onto one column of texels (Aruraumon: UVs (208, 65), (208, 65), (208, 48): a strip). The porter's UVs are texel / 256, the left edge of a texel: across the face the interpolated coordinate sits on 208 and rounding picks texel 207 or 208 from pixel to pixel. Where the two differ, speckles, moving with the model. The PSX takes floor(u): always texel 208. Found by rendering Aruraumon at 4× (`RC_SCALE=4 tests/render_check.gd -- MAYO04A 200 200 20 0 360 330 mmd_files/MMD2/ARUR.gltf`); flat colours per surface (`RC_TINT=1`) showed no speckles, so it wasn't z-fighting.
- **Status:** fixed (2026-10-24; checked in the game): `PsxLit` samples the PSX's texel, floor of the coordinate nudged by 1 / 1024 texel (`psx_uv`). The render shows the body and the bud clean.

### I-7. The camera shakes while running
- **Seen:** while the tamer runs, the picture shakes a little.
- **Evidence:** `issues/evidence/dw_issue_no_text_render_and_camerashaking.mp4` (CHKA01, Mansion Basement, 4×).
- **Cause:** I-3's 4× render. The follow scrolls the background in whole PSX pixels (as the C, `gte_stsxy`), while the 3D now draws the tamer at a quarter of a PSX pixel: he drifts up to half a PSX pixel (2 screen pixels) against the background and snaps back when the scroll steps. At 1× both are on the same pixel grid.
- **Status:** fixed (2026-10-24; checked in the game): above 1× the follow rounds the motion to the render's pixels (`FieldMap._pixel_round`: quarter pixels at 4×); the background, drawn at the render scale, scrolls in those steps. At 1× it is the C's whole pixels as before (`tests/test_camera.gd`). The pans still step in whole pixels.
- **Also in the video:** the tamer's text box shows only " ! ": that is the script's line (script 63, offset 0x00F4, `SHOW_TEXTBOX " ! "`), his surprise. "Player" stands for the tamer's name until the naming is ported.

## Fixed

### I-5. The poop has a black outline
- **Seen:** a dark outline around the poop model. It was there before step 5a.
- **Evidence:** `issues/evidence/dw_issue_poop_outline.png`; the original: `issues/evidence/dw_real_poop_look.png`.
- **Cause:** the poop model (`ETCNA/UNTI.TMD`, `PoopPiles`) has two parts: the body, and a round shadow disc under it. The disc's texels are dark greys that all carry the STP bit, on a semi-transparent polygon with blend mode `abr` 2: the PSX subtracts them from the ground, a soft darkening. The port drew every semi-transparent polygon with a plain alpha blend, so the disc showed as an opaque dark ring. The model textures also had no STP information: the asset porter dropped the bit.
- **Status:** fixed (2026-10-24, `5fdc59e`; checked in the game): the asset porter writes STP masks for model textures (`<page>.stp.png`, material `extras.stp_texture`; `asset_porter/specs/tmd.md` "STP masks"), and `PsxLit` draws a semi-transparent polygon in two passes: its non-STP texels opaque, its STP texels with the `abr` mode (half, add, subtract, quarter). `tests/test_lighting.gd` checks the poop's two materials; `tests/render_check.gd -- MAYO01 200 300 20 0 360 420 tmd_files/ETCNA/UNTI.gltf` shows it on the grass without the ring. Every model with semi-transparent polygons is drawn this way now (effects, shadows).

### I-2. The models too bright at night
- **Seen:** at night (File City, 20:06) the tamer and Agumon keep their day colours.
- **Evidence:** `issues/evidence/dw_issue_top_of_tree_and_too_light_texture.png`; the original at night: `issues/evidence/dw_night_real_game.png`.
- **Expected:** the original lights the models with the map's 3 lights, scaled by the time of day (`updateTimeOfDay`, map.c:4301: × 1.0 day, red 1.0 / green, blue 0.7 evening, × 0.5 night; `asset_porter/specs/map.md` "TFS").
- **Cause:** the port drew every model unshaded, so the field lighting wasn't reproduced at all (`Content._psx_materials`).
- **Status:** fixed (2026-10-24, `19fd5b8`, `specs/lighting.md`; checked in the game): lit models take the map's lights and the 0.5 ambient per vertex, scaled by the time of day at the end of the hour's fade. Rendered on TWNB01 (`tests/render_check.gd -- TWNB01 200 200 20 2 360 330`): Agumon lit from above, sides darker; at night his brightest pixels go from 255 to 213.

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

### D-2. A CONFIG menu for the render options
- **Asked:** a future configuration menu where players choose the 3D render amplification (today only the debugger's Render tab and the field's `render_scale`, 4× by default) and the text and windows' filter (D-3: on by default, the player's choice).

### D-3. Upscale the text and windows like the models
- **Asked:** at 4× the text and windows should be upscaled too, with a filter as emulators do; on by default, later in the CONFIG menu (D-2).
- **Status:** done (2026-10-24; checked in the game): `PsxUiFilter` (`scripts/ui/psx_ui_filter.gd`), a canvas shader on the UI nodes (the boxes and their text, the map name, the clock, the status bars, the condition bubbles): Scale4x (Scale2x / EPX twice) rebuilds each texel's sub-pixels from its neighbours, keeping the art's colours and rounding its stair-steps. It runs in each node's own drawing, so the boxes' and bubbles' additive texels still blend with the scene. The global shader parameter `psx_ui_filter` switches it (the field's `ui_filter`, the debugger's Render tab); off, the texels are square blocks. Not filtered: the debug help line and the care panel (Godot's own font). First version's bug (seen in the game: the clock and windows too saturated, the text grey): the shader multiplied by `COLOR`, which in a Godot 4 canvas fragment already holds the texture's colour, so every colour was squared; it now multiplies by the draw's tint only (a varying from `vertex()`).

### D-1. The debugger: pick a map to teleport to, a bigger view
- **Asked:** choose the map to warp to from a list (today `[` / `]` step through them), and a bigger window: the game keeps its 4:3 aspect, with the debug information readable beside it instead of inside the 320 × 240 picture.
- **Status:** done (2026-10-24, `b6538ef`; checked: "the new debugger is cool"): `DebugWindow` (`scripts/debug/debug_window.gd`), its own OS window (`display/window/subwindows/embed_subwindows=false`), F1 toggles it. Tabs: Status (map, clock, last message, the keys), Maps (filter, double-click or Go teleports to the exit chosen), Render (the 3D render scale, I-3). The game window is 1280 × 960. Later: the care panel (`C`) could move into a tab.
