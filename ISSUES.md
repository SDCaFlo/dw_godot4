# Issues

Bugs found while playing, with their evidence. One entry per issue: what you see, where (map, time of day), what the original does, the screenshot(s), and the cause once known.

Screenshots go in `issues/evidence/`. They show game art, so the folder is gitignored (and `.gdignore`d, so Godot doesn't import them): only this list is committed. Name them `<id>_<short>.png` or keep the original name and link it here.

Status: **open**, **investigating**, **fixed** (with the commit), **won't fix** (with the reason).

## Open

Reported 2026-10-25 (minor, to check later).

### I-12. No mist in the misty trees
- **Seen:** the Misty Trees maps have no mist.
- **Expected:** the original's mist over those maps (not ported yet: find its effect in the decomp).
- **Status:** open.

### I-13. Time-of-day changes are a hard cut
- **Seen:** the light jumps when the time of day changes (afternoon → night, night → day, day → afternoon).
- **Expected:** the original fades the lighting softly from one time of day to the next.
- **Note:** `specs/lighting.md` takes the lights "at the end of the hour's fade"; the fade itself (`updateTimeOfDay`, map.c:4301, and the background palettes) still has to be reproduced.
- **Status:** open.

### I-15. No pause
- **Seen:** the game can't be paused.
- **Expected:** the original's pause (START in the field; to find in the decomp).
- **Status:** open.

### I-16. The partner (Agumon) isn't in the evolution chart
- **Seen:** in a new game the Player screen's chart is empty; the original shows Agumon.
- **Evidence:** `issues/evidence/dw_issue_evo_char_menu_color.png`.
- **Cause:** the new game marks the first partner raised (`setDigimonRaised(partnerId)`, `main.c:3452`, trigger 0x200 + id); `GameState.new_game` doesn't.
- **Status:** open.

### I-18. To verify: the inventory cursor at the top
- **Question:** in the original inventory, does ↑ on the first row wrap to the bottom, or stay at the top? Compare with the port (`specs/inventory.md`).
- **Status:** to verify.

### I-19. To verify: the partner's mood animations too often
- **Question:** the partner may play its hungry / happy / poop animation and sound more often than the original. Compare the timers with the game (`specs/partner.md`, `specs/care.md`).
- **Status:** to verify.

## Fixed

### I-14. Player / Digimon screen: the tab headers all look selected
- **Seen:** every tab is drawn light; in the original the tabs not shown are darker, with blue labels.
- **Evidence:** `issues/evidence/dw_issue_card_menu_colors.png`, `issues/evidence/dw_issue_evo_char_menu_color.png` (left original, right port).
- **Cause:** `renderMenuTab(x, w, layer)` passes `layer` (1 for tabs not shown) as `renderRectPolyFT4`'s flag, and flag 1 dims the sprite (`game_menu.c:2960`, `:4305`). `MenuDraw.menu_tab` did not pass `flags` to `sprite`, defaulting to 0 (undimmed).
- **Status:** fixed (2026-10-25): `MenuDraw.menu_tab` passes `flags = 0` when `front` is true and `1` (dimmed) when `false` (`scripts/ui/menu_draw.gd`).

### I-17. Chart and card screens: the cells and columns have no contour
- **Seen:** the evolution chart's cells and level columns, and the card list's cells, are flat; in the original they have a light top-left and a dark bottom-right edge.
- **Evidence:** `issues/evidence/dw_issue_card_menu_colors.png`, `issues/evidence/dw_issue_evo_char_menu_color.png`.
- **Cause:** `renderBorderBox` and `renderInsetBox` (`game_menu.c:3801`, `:3849`) add their border lines to the ordering table bucket first, then the filled box; because the PSX GPU traverses each bucket in reverse of its additions, the box is drawn first and the lines are drawn over it. `MenuDraw.border_box` and `MenuDraw.inset_box` drew the lines first and the box over them, which covered the highlight edges.
- **Status:** fixed (2026-10-25; checked in the game): `MenuDraw.border_box` and `MenuDraw.inset_box` now draw the fill box first, then the bottom-right line, then the top-left line over it (`scripts/ui/menu_draw.gd`).

### I-10. Feeding: the tamer takes the item out of the bag again and again
- **Seen:** Use on an item: while the partner comes and takes it, the tamer keeps pulling the item out of the bag, over and over (reported 2026-10-25 with step 5e-2).
- **Cause:** his "hold it out" animation (5) loops only its frames 10-11 in the model's data (`loop` start frame 10, end 11), so the original plays it once and holds the arm out. `PsxAnimator` approximated every loop by looping the whole animation, so it started over from frame 1.
- **Status:** fixed (2026-10-25; checked in the game): `PsxAnimator` plays a partial loop once, then wraps inside the loop's segment; `tests/test_inventory.gd` checks the pose doesn't start over. Every entity's partial loops now play like the original (the partner's and the NPCs' too).

### I-11. Feeding: stuck after the partner refuses an item
- **Seen:** the partner refuses the item: the tamer stays with his hand in his bag, the game never resumes (reported 2026-10-25).
- **Cause:** after a refusal the scene waits until the tamer's animation 4 (the bag) reaches its last frame (`animFrame >= frameCount`, `partner.c:523`). Animation 4 loops as a whole, and the port's "ended" test was only true for animations that stop; the port's frame also never showed a loop's last frame (it went 10 -> 1), so the wait never ended.
- **Evidence:** `issues/evidence/dw_issue_refuse_item_lock_bug.mp4` (still stuck after the first fix).
- **Second cause (found with the evidence):** the first fix made the animator report the last frame on the Godot frame where the loop wraps. The tests and traces ran at a fixed 20 fps (one Godot frame per game frame), where that works; in the game, at 60 fps and more, the next Godot frame overwrote it before the 20 Hz game tick looked, so the wait still never ended. Reproduced with a 60 fps trace.
- **Status:** fixed again (2026-10-25, `5b7b323`; checked in the game): `PsxAnimator.passes` counts the passes through a loop's end and the scene's test (`Tamer.scene_animation_ended()`) reads it, so it holds whatever the frame rate; `tests/test_inventory.gd` now runs the refusal at 60 fps (3 model frames per game frame) and checks both end free with the item still in the bag.
- **Follow-up:** other scene waits on a *looping* animation's last frame (`animator.frame >= frame_count` in the partner's scenes) can miss it the same way at high frame rates; they should read `passes` too (to review).

### I-9. NPCs walk off through walls while the △ menu is open
- **Seen:** open the △ menu while an NPC is walking: it keeps walking in its direction, through the map's walls, without end (Native Forest, day; reported 2026-10-25 with step 5e-1).
- **Evidence:** `issues/evidence/dw_issue_npc_walking_out_while_in_menu.mp4`.
- **Cause:** while the menu is open (`IS_IN_MENU`) the field skipped the NPCs' game-frame tick, which does their collision and turning, but their animation and its root motion run every Godot frame (`FieldDigimon._process`), so the walk kept moving them. In the original `NPCEntityTickOverworld` returns before its `tickAnimation` too (`overworld.c:1232`, `:1353`): the NPCs stand frozen, animation included.
- **Status:** fixed (2026-10-25; checked in the game: "the npc is solved"): the field freezes the NPCs while the menu is open (`FieldDigimon.frozen`, `EntityHost.freeze_npcs`); `tests/test_game_menu.gd` checks a walking NPC stays put and moves again after.

### I-8. On the snow maps the tamer is drawn over the scenery in front of him (Freezeland)
- **Seen:** the tamer and the partner stand on top of things that should hide them: the boulder on FRZL13 and the ice crystals on FRZL12 (Freezeland, day). In the original they walk behind them.
- **Evidence:** `issues/evidence/dw_issue_freezeland_player_on_top_of_BOULDER.png` (FRZL13), `issues/evidence/dw_issue_freezeland_player_on_top_of_ice.png` (FRZL12).
- **Cause:** those pieces are overlay sprites drawn by depth over the background (as the trees of I-1): the boulder is FRZL13's instance 35 (sprite 7, 224 × 192, at (300, 0, −440)), the ice FRZL12's sprites 7–13. On the snow maps the field loads the overlays twice: `FieldMap.load_map`, then again with the map's snow (`MapOverlays.load(data, snow)`). `MapOverlays.clear` emptied its sprite list with `clear()`, but that list *is* the map data's `objects` array, so the second load found no sprites: every non-snow instance got the "behind everything" depth and drew nothing, and what you saw was the plain background. `tests/render_check.gd` (one load) drew the boulder over the tamer correctly, which pointed at the second load. It hits all 13 snow maps (ids 0x58–0x60, 0x84–0x87).
- **Status:** fixed (2026-10-24; checked in the game: "it looks perfect"): `clear()` drops the reference instead of emptying the shared array; `tests/test_map_objects.gd` loads FRZL13 twice and checks the boulder is drawn at its depth (fails on the old code: 0 sprites left).

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
- **Expanded** (2026-10-25): a State tab (`DebugStateTab`, `scripts/debug/state_tab.gd`): triggers, script values, bits / merit, items, cards, and unlock presets built from the data (Birdramon's destinations, the jukebox's locked tracks). Test: `tests/test_debug_state.gd`.
