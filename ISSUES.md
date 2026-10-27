# Issues

Bugs found while playing, with their evidence. One entry per issue: what you see, where (map, time of day), what the original does, the screenshot(s), and the cause once known.

Screenshots go in `issues/evidence/`. They show game art, so the folder is gitignored (and `.gdignore`d, so Godot doesn't import them): only this list is committed. Name them `<id>_<short>.png` or keep the original name and link it here.

Status: **open**, **investigating**, **fixed** (with the commit), **won't fix** (with the reason).

## Open

Reported 2026-10-25.

### I-16. The partner (Agumon) isn't in the evolution chart
- **Seen:** in a new game the Player screen's chart is empty; the original shows Agumon.
- **Evidence:** `issues/evidence/dw_issue_evo_char_menu_color.png`.
- **Cause:** in the original, the first partner is marked raised (`setDigimonRaised(partnerId)`, `main.c:3452`, trigger `0x200 + id`) when the new game intro process (`newGameScene()`, Jijimon's questionnaire and naming) completes, and subsequent Digimon are marked upon evolution (`evl.c:1489`) or reincarnation (`evolution.c:1079`). Neither the new game intro sequence nor the evolution system has been ported yet (PLANS.md step 4e / milestone 5).
- **Status:** on hold (waiting for the new game sequence in step 4e).

Reported 2026-10-26.

### I-23. A new game's partner fights with 0 stats
- **Seen:** in battle the partner does nothing, faints at once, and a Restore brings it back with 0 HP (reported 2026-10-26 with step 5d-4, new game on MAYO04A).
- **What the original does:** the new game's stats come from File City's script after the intro (DG script 193, section 55: `SET_STAT` Off 80, Def 60, Speed 70, Brains 70, HP / MP 800 / 600 for Agumon; 70 / 80 / 60 / 70, 700 / 700 for Gabumon). `initializePartner` sets only the moves.
- **Cause:** the port starts a new game straight on a map (`Field.start_map`), without the intro and File City's scenes (step 4e), so the default record's stats stay 0.
- **Status:** open until the intro (4e). Decided 2026-10-26: no stand-in; the debugger's State tab has **Max all stats** (every base stat at its cap, HP / MP full) for testing battles.

### I-24. A battle that never starts (Native Forest)
- **Seen:** on MAYO04A, a sky-blue face (the "flees" bubble) over an Aruraumon, then the battle never started, for minutes (reported 2026-10-26 with step 5d-4). Expected: the Digimon you talk to always fights (red face); only the others may flee, so a battle always has an enemy, except key fights, which have their own list.
- **What the original does:** `handleBattleStart` (`btl.c:209`) puts the talked-to Digimon first in the fight with the "joins" bubble before rolling the others; a key fight (script value 0xFA) takes its enemies from script values 0xFB-0xFD and gives every other Digimon on screen the "flees" bubble. The intro then waits until every runner has left the screen.
- **Checked:** the bubbles' faces are right (type 0 red, type 1 sky blue); the port's start is the C's; on MAYO04A a fight through Aruraumon's talk section, one next to Etemon's tree, and the Etemon ambush (section 0x33, a key fight against the hidden Etemon, entity 2) all start and end in `tests/battle_scan.tscn`. MAYO04A has, besides the Aruraumon, a hidden Etemon (entity 2) up in a tree (y -1000), the ambush's enemy.
- **Since then:** the help line names each phase a battle enters ("battle: INTRO"…), and a battle without an enemy says so.
- **Status:** could not reproduce (2026-10-26): pending further evidence. Possibly linked to the 0-stat partner of a new game (I-23); if it happens again, note where, how the battle began and the last "battle: …" line on the help line.

### I-28. In battle the partner can walk onto a blocking cell
- **Seen:** by `tests/battle_scan.tscn` with a new game's partner (`BATTLE_RAW=1 BATTLE_MAPS=TROP01,TROP02,MAYO03,MAYO01,MAYO04A`), in about half the runs: the partner, walking (animation 0x24, `ANIM_WALK`), stands on a blocking map cell for 4 to 116 frames (TROP02 near (-700, -3020), MAYO01 near (-2928, -1011), TROP01). Found 2026-10-27; the same on the committed 5d-4 code, so not from 5d-5. Not the knock-back of I-26 (that one is a hit animation).
- **What the original does:** to check: the battle's walking (moving into range, `BTL_tickMeleeAttack` / `BTL_tickRangedAttack`, the move-forward probe `entityCheckCollision` like the knock-back's).
- **Status:** open. The scan's runs differ (frame pacing), so it is intermittent; the next step is a run that dumps the partner's state when it happens.

### I-31. Winter Blast draws away from the battle
- **Seen:** 2026-10-27, in a real battle: Winter Blast's visual appears somewhere else on the map, not where the fighters are.
- **To check:** its pieces are the 5d-5b screen primitives (the scrolling snowy backdrop, `renderScrollingBackground` / `renderParallaxSprites`, placed through `FieldMap.drawing_offset()` and `screen_to_world`) and its models / sprites at the instance positions. Compare in the Effects gallery against a battle on the same map: whether the drawing offset or the depth slot puts the backdrop off the camera's view, or the instance's start position (its bone / caster table) is off.
- **Status:** open.

### I-30. Most techniques look very transparent
- **Seen:** after 5d-5a / 5d-5b (2026-10-27), in the Effects gallery and in battle: most techniques' models and sprites are drawn, but very faint, almost invisible.
- **To check against the original** (in the gallery, one technique at a time): the blend modes of the models' and sprites' STP texels (half / add on a bright background; `WorldSprites`, `PsxLit`), the sprites' tint (128 = 1.0), the textures' palettes and which texels carry the STP bit, the sRGB conversion of the additive passes.
- **Status:** open. Not a missing feature: the drawing is there (`specs/battle_effects.md` "As built (5d-5a)", "(5d-5b)").

### I-21. Recovery items show no healing effect
- **Seen:** giving the partner a recovery item (e.g. Sm. recovery) heals it, but nothing shows on the partner.
- **Cause:** the original draws a healing particle effect over the partner (`addHealingParticleEffect(partner, variant)`, `main/particle.c:209`), called by the item handlers (`item.c:2236`, `:2242`, `:2348`, `:2362`, `:2373`; variants `HEAL_EFFECT_VARIANT`). The inventory step left it for later (`specs/inventory.md` §6: "with the effects"); it was not in the plans.
- **Status:** open. A small field effect of its own (main binary, not the battle's effect engine): planned in `PLANS.md` (5e follow-ups). Since 5d-4 the item handlers emit `ItemUse.healing_effect(variant)` where the C calls it (field and battle); nothing draws it yet.

## Fixed

### I-29. Digimon doesn't play satiety animation when fed
- **Seen:** when hungry and fed food, if no longer hungry, the partner does not play its satiety animation.
- **What the original does:** when hungry and fed, if no longer hungry (energy reached `energyThreshold`) or when given its favorite food, the original sets `PARTNER_ANIMATION = 0x0B` and starts animation 0x0B (satiety / fullness animation; `partner_impl.c:1639`).
- **Cause:** in `partnerHandleFoodFeed` (`partner_impl.c:1639`), the original sets `PARTNER_ANIMATION = 0x0B` and starts animation 0x0B. In `Partner.tick_feed_item` (`scripts/field/partner.gd:382`), `partner_animation` was not updated to `ItemUse.ANIM_HAPPY` (0x0B), so on the next tick `tick_walking` saw `partner_animation (0) != anim_id (11)` and instantly overwrote it with idle (animation 0).
- **Status:** fixed (2026-10-27): `Partner.tick_feed_item` sets `partner_animation = ItemUse.ANIM_HAPPY` when `handle_food_feed` is true; `tests/test_inventory.gd` verifies the satiety animation (0x0B) is triggered when fed full / favorite, continues playing in normal state without interruption, and returns to idle upon completion.

### I-27. Spit Fire's sound doesn't sound like the original
- **Seen:** in battle, Agumon's Spit Fire plays a sound that seems to belong to another technique (reported 2026-10-26 after step 5d-4).
- **What the original does:** the techniques' sounds play from sound slot 8 (`BTL_playEFESound`: `playSound(8, id)`). Outside a battle slot 8 holds the map's ESALL set; at a battle's start `loadSB()` (`btl.c:408`) loads the battle's own bank `SOUND\SB` there, and the battle's end loads the map's set back (`loadMapSounds2`, `battle_main.c:893`).
- **Cause:** the port never loaded `SOUND\SB`: the techniques played the sound of the same id from the map's set.
- **Status:** fixed (2026-10-27, with 5d-5a): `BattleSession` loads the battle's bank where the C does (`BattleWorld.load_battle_sounds`, `Sound.load_battle_sounds`), and the debugger's technique gallery too; `tests/test_battle.gd` checks it. To confirm by ear against the original (VERIFY "Battle effects" 3).

### I-26. A hit throws the fighter out of the map
- **Seen:** a hit knocks a fighter through the fence, out of the walkable map; it can't come back (reported 2026-10-26 with step 5d-4; `issues/evidence/dw_issue_battle_stuck_corner.png`, `dw_issue_battle_stuck_corner_2.png`).
- **What the original does:** every frame of the hit state, `BTL_tickFighterAction` probes the fighter's next step (`entityCheckCollision(NULL, fighter, 0x118, 0xC8)`: the combat area, the map, the others) and holds it on any hit. The step is the animation's own forward momentum (`entityMoveForward`, `map.c:3677`), signed: a knock-back slides backwards, so the probe looks behind.
- **Cause:** the port probed with the length of the last frame's motion, always forwards, so a backwards slide never saw the fence; and a held frame recorded no motion, so the next frame's probe saw none and let it move again.
- **Status:** fixed (2026-10-26): `FieldDigimon.forward_step` (the signed forward momentum, held or not) is what `FieldBattleWorld.check_collision` probes with. `tests/battle_scan.tscn` checks no fighter stands on a blocking cell: with the old probe 3 of 4 maps failed (up to 188 frames out of the map), now none.

### I-25. A defeated enemy comes back
- **Seen:** an enemy that ran away after losing stays on the map, walks back later and can be fought again (reported 2026-10-26 with step 5d-4).
- **What the original does:** `BTL_deinitializeCombat` takes every NPC whose `isOnScreen` is set off the map. Only the NPCs' field tick updates that flag (`overworld.c:1352`; their battle tick only animates), so it keeps its value from the battle's start: the enemies on screen then are taken off the map, even though they have run off screen by the end.
- **Cause:** the port recomputed the flag live, so an enemy that had run off counted as off screen and stayed (the 5d-3 test even expected it).
- **Status:** fixed (2026-10-26): `FieldBattleWorld.is_on_screen` reads the flag as the field tick left it; `tests/test_battle.gd` and `tests/battle_scan.tscn` check the defeated enemy leaves the map.
- **Then (retest):** it no longer came back, but its footsteps could still be heard. Off the map in the original, the entity keeps its slot but nothing ticks it: `NPCEntityTick` returns before its animation (`overworld.c:1122`) and `renderDigimon` skips it (`model.c:2891`). The port only hid the node: its flee run kept animating, moving it by root motion and playing its steps (they play while `isOnScreen`, frozen from the battle's start). Fixed: `Npc._process` does nothing off the map; `tests/battle_scan.tscn` checks the defeated entity no longer moves (fails on all 3 maps without the fix); confirmed in the game 2026-10-26. The node isn't freed, as the C keeps the entity: a script can still find it by its script id, a `SET_DIGIMON` brings it back, and the next map frees it (`removeMapEntities`).

### I-22. The partner's equipped techniques didn't work in battle
- **Seen:** with a technique equipped the partner still didn't use it (reported 2026-10-26 with step 5d-4).
- **Cause:** the game state keeps the equipped moves as technique keys (`specs/game_state.md`), but the battle read them as the C's animation ids (0x2E + slot): a key read as 0, no technique, and the slot was cleared. The tests and the battle scan gave the partner animation ids, so they didn't see it.
- **Status:** fixed (2026-10-26): `Battle.anim_of_move` turns a key into its animation for the fighter's Digimon (`BattleFighter.move_anim`, the loading); `tests/test_battle.gd` fights with a key-equipped technique.

### I-20. Battle start: the tamer runs off the screen
- **Seen:** when a battle starts after walking about the map, the tamer runs towards where he entered the map and leaves the screen (reported 2026-10-26 with step 5d-3).
- **What the original does:** the intro sends him back along his way to the map entry (his waypoints, then his start tile), but each frame tests his next step against a combat area of 310 x 230 screen pixels around the battle (`entityCheckCollision(partner, tamer, 0x136, 0xE6)`, `battle_setup.c:261`); at its edge (result 11) he stops, turns to the partner and stands (`specs/battle.md` §2.4).
- **Cause:** the port has that test (`FieldBattleWorld.check_collision`), but it measures the step his animation's root motion made in the last game frame, and the tamer's scripted-walk movement (the state the battle drives him in) moved him without recording that step. The probe always saw a step of 0, never hit the area's edge, and he ran on.
- **Status:** fixed (2026-10-26, with 5d-3): `Tamer._process` records the step in that state too and keeps a held step still. `tests/battle_scan.tscn` now starts each battle with the tamer far from his entry and checks he is on screen when the fight begins (it fails without the fix on 2 of its 3 maps).

### I-14. Player / Digimon screen: the tab headers all look selected
- **Seen:** every tab is drawn light; in the original the tabs not shown are darker, with blue labels.
- **Evidence:** `issues/evidence/dw_issue_card_menu_colors.png`, `issues/evidence/dw_issue_evo_char_menu_color.png` (left original, right port).
- **Cause:** `renderMenuTab(x, w, layer)` passes `layer` (1 for tabs not shown) as `renderRectPolyFT4`'s flag, and flag 1 dims the sprite (`game_menu.c:2960`, `:4305`). `MenuDraw.menu_tab` did not pass `flags` to `sprite`, defaulting to 0 (undimmed).
- **Status:** fixed (2026-10-25, `1e38bdf`): `MenuDraw.menu_tab` passes `flags = 0` when `front` is true and `1` (dimmed) when `false` (`scripts/ui/menu_draw.gd`).

### I-17. Chart and card screens: the cells and columns have no contour
- **Seen:** the evolution chart's cells and level columns, and the card list's cells, are flat; in the original they have a light top-left and a dark bottom-right edge.
- **Evidence:** `issues/evidence/dw_issue_card_menu_colors.png`, `issues/evidence/dw_issue_evo_char_menu_color.png`.
- **Cause:** `renderBorderBox` and `renderInsetBox` (`game_menu.c:3801`, `:3849`) add their border lines to the ordering table bucket first, then the filled box; because the PSX GPU traverses each bucket in reverse of its additions, the box is drawn first and the lines are drawn over it. `MenuDraw.border_box` and `MenuDraw.inset_box` drew the lines first and the box over them, which covered the highlight edges.
- **Status:** fixed (2026-10-25, `1569541`; checked in the game): `MenuDraw.border_box` and `MenuDraw.inset_box` now draw the fill box first, then the bottom-right line, then the top-left line over it (`scripts/ui/menu_draw.gd`).

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

## Won't fix

### I-12. No mist in the misty trees
- **Seen:** the Misty Trees maps have no mist.
- **Expected:** the original's mist over those maps.
- **Status:** won't fix (not a bug: unimplemented feature). In the original, the mist overlay (`renderMist`, `overworld.c:550–660`) is a screen rendering routine using scrolling semi-transparent polygon layers over maps `MIST01`–`MIST07`. Belongs in `PLANS.md` under field rendering features.

### I-13. Time-of-day changes are a hard cut
- **Seen:** the light jumps when the time of day changes.
- **Expected:** the original fades the lighting softly from one time of day to the next.
- **Status:** won't fix (dropped, 2026-10-25). Verified that under normal clock progression the transition fades smoothly; the hard cut seen was an artifact of using the debug hour-skip key.

### I-15. No pause
- **Seen:** the game can't be paused.
- **Expected:** the original's pause (START in the field).
- **Status:** won't fix (not a bug: unimplemented feature). In the original, pause is handled by `handlePause()` (`utils2.c:402`), opening static UI box 5, looping `pauseFrame()`, and polling START input (0x800). Belongs in `PLANS.md` as an unported field feature.

### I-18. The inventory cursor at the top
- **Question:** in the original inventory, does ↑ on the first row wrap to the bottom, or stay at the top?
- **Status:** won't fix (verified normal behavior, 2026-10-25). In the original PSX game, pressing ↑ on the first row wraps to the bottom row, matching the current port implementation.

### I-19. The partner's mood animations too often
- **Question:** the partner may play its hungry / happy / poop animation and sound more often than the original. Compare the timers with the game (`specs/partner.md`, `specs/care.md`).
- **Status:** won't fix (verified with decomp, 2026-10-25). Double-checked `partner.c:888` (`partnerTickWalking`), `partner_impl.c:482` and `partner_impl.c:1012` (`updateConditionAnimation`). The implementation is an exact 1:1 match to the decomp C code:
  - In a new game, happiness is 50. Since 50 ≥ 31 (`0x1F`), the partner is classified as happy.
  - When standing close to the tamer (closeness 2), the partner idles for `anim->frameCount * EMOTION_ANIM_TIMEOUT` ticks. For Agumon, idle (anim 0) has 17 frames, and `EMOTION_ANIM_TIMEOUT` is `randomLimit(5) + 1` (1 to 5).
  - This means it idles for 1 to 5 idle loops (17 to 85 frames at 20 Hz = 0.85 to 4.25 seconds, average 2.55s) before triggering the happy animation (anim 5, 67 frames = 3.35s) with its roar sound. Once anim 5 finishes, it idles again for 1 to 5 loops (average 2.55s) and repeats.
  - This frequent repetition of mood animations when happy, hungry, or needing to poop is authentic original PSX game design.

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
