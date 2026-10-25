# Verifying the Godot game systems (human checks)

The porters have their own checklists (`asset_porter/VERIFY.md`, `data_porter/VERIFY.md`); this file covers the game systems ported to GDScript. Every system has a headless test that must print `OK` (run from `dw_godot/`, Godot 4.7, after both porters):

```
godot --headless --path . -s res://tests/test_script.gd
godot --headless --path . -s res://tests/test_npc.gd
godot --headless --path . -s res://tests/test_camera.gd
godot --headless --path . -s res://tests/test_map_objects.gd
godot --headless --path . -s res://tests/test_lighting.gd
godot --path . -s res://tests/render_check.gd -- MAYO01 0 260 140   # not headless: renders a frame
godot --headless --path . -s res://tests/test_text.gd
godot --headless --path . -s res://tests/test_care.gd
godot --headless --path . -s res://tests/test_partner.gd
godot --headless --path . -s res://tests/test_clock.gd
godot --headless --path . -s res://tests/test_game_state.gd
godot --headless --path . -s res://tests/test_game_data.gd
godot --headless --path . -s res://tests/test_content.gd
godot --headless --path . -s res://tests/test_data_dock.gd
```

With the Steam build of Godot the executable is `godot.windows.opt.tools.64.exe` in the Steam library folder (`steamapps\common\Godot Engine\`); call it as `& "<path>" --headless --path . -s res://tests/test_game_state.gd` from PowerShell. Godot 4.7 prints a "GDScript backtrace" under each error or warning, including the tests' expected ones.

The tests prove the code does what the spec says. What they can't prove is that the spec matches the game. That is what the checks below are for: compare with what you know of the game.

Sections are added as systems are ported (`PLANS.md`).

## Text and windows (`scripts/ui/`, `specs/text.md`, guide `docs/ui.md`)

`test_text.gd` prints `OK: text checks`. Run the project (F5), open the care panel (`C`) and press **"injured 12h"**: on the next frame Agumon gets sick and the message box opens.

1. **The box:**
   - it grows from the tamer as a grey outline in 5 quick steps, to a strip near the bottom of the screen;
   - the frame is black / light blue / blue lines with small corner pieces, and the inside is half dark (you see the field through it);
   - a small button sprite blinks in the bottom-right corner (3 frames).
   - Compare with any message in the game, e.g. when a partner gets sick: colours, size and place should match.
2. **The text:**
   - the partner's name in orange (colour 10), then "is Sick!" in light grey;
   - the letters are the game's own font: 12 px capitals, narrow lowercase (`i` 4 px), no anti-aliasing.
   - **Gap after the name:** there is a gap between the name and "is Sick!". The C code places the text at 12 px per letter of the name, and the US letters are narrower (`specs/text.md` §2.5). If you remember the game showing "Agumon is sick!" without a gap, say so: that would mean the US build differs from the decomp here.
3. **While it is open:**
   - game time stops (the clock and bars slide away);
   - the tamer can't walk and Agumon stands idle.
   - Press ✕ (Enter / Space): the box shrinks back to the tamer, the clock comes back, you can walk. As in the C, it reacts to ✕ being held, so holding ✕ when the box appears closes it at once.
   - Wrong if: the box never closes, or you stay frozen after it.
4. **Language (`L`):** press `L` before "injured 12h":
   - `ja`: the name in the JP font's full-width Latin letters, then the Japanese text;
   - `en_eu`: the EU font, all letters 8 px apart, so the gap after the name is smaller (8 px per letter).
5. **Dialogue:** see the Scripts section: the dialogue box is checked with the script sections that use it.
6. **Not there yet:** the medal and tamer-level messages, the sounds.

## Controller (`scripts/core/pad.gd`, `tamer.gd`; `specs/text.md` §2.8)

`test_text.gd` checks the pad actions, `test_camera.gd` the direction chain. With a gamepad plugged in:

1. **✕ on text boxes:** talk to an NPC and press the pad's bottom button (✕ / A): the pages turn and the box closes, as with Enter. △ (top button) cancels in choices.
2. **Facing after the stick:** walk with the left stick in each direction and let go: the tamer keeps facing where he walked, never turns down on release. Same with the d-pad.
3. **Running:** hold the right shoulder (R1) or △ while walking: he runs. On the keyboard Shift still runs.
4. **Keyboard:** arrows, Enter / Space and Shift work as before.

## Scripts (`scripts/script/`, `specs/script.md`)

`test_script.gd` prints `OK: script checks`. Besides its synthetic checks it runs every section of every script (1269) and every map setup (255) to its end, played like a player (texts confirmed, choices tried in turn), in about 15 s; it prints the unported instructions it met.

In the game (F5), `D` runs the next section of the current map's script (the help line names it: `script 4 section 0x51 (2 / 7)`). Sections are run as they are written. Entering a map and the trigger cells already start them (see Map changes below); talking to NPCs comes with step 3. Check:
1. **On the start map (Native Forest, MAYO04A):** `D` twice. The first section (0xFE, the map entry) only spawns items, which aren't on the map yet: the help line says `script: not ported yet: SPAWN_ITEM`. The second (0x51) is the sign: "There are engraved letters here." from the tamer (his name "Player" in light blue), then "No one's here! Go home!" and "Is someone living here?" without a speaker. ✕ turns them.
2. **While a section runs:** the tamer can't walk, the partner stands, game time stops (the clock and bars slide away). When it ends everything comes back.
3. **Text details:**
   - the speaker's name on the first row, the text on 3 rows; a text without a speaker uses all 4;
   - words in another colour, the blinking "next" sprite, texts going on to a second page;
   - holding ✕ doesn't skip a new box: it waits until ✕ was released once.
4. **Choices:** at Dragon Eye Lake (press `]` until the help line shows `MAYO06`), `D` twice runs section 0x51, the Lake Guardian's flute scene. It first checks the inventory, so what it shows depends on the items you carry. With the flute: "Will you play the Lake Guardian's **Blue Flute**?" and "I'll play / I won't play". A grey cursor bar covers the option; up and down move it and wrap; ✕ picks; △ leaves the choice.
5. **Unported:** each instruction the port can't run yet is named once in the help line (NPCs, movement, animations, sounds, items on the map, battles, shops). The section goes on without it, as in the original with that system missing.
6. **Compare with the game:** the order of the texts in a scene you know, the speaker colours, when the box closes. Wrong if: a section never ends, texts come in the wrong order, or the game stays frozen after a section.

## Map changes (`scripts/field/field.gd`, `tamer.gd`, `scripts/ui/map_name.gd`, `specs/script.md` §2.2, §3)

Every map is entered through its MAPHEAD script, as in the original. Run the project (F5).
1. **Start:** Native Forest (MAYO04A). The help line names what its setup met and couldn't run (`SET_BGM`, `LOAD_DIGIMON`, `SET_DIGIMON`, `SPAWN_ITEM`); the tamer and Agumon stand at the map's exit 0.
2. **Walking through an exit:**
   - the tamer keeps running straight in his direction while the screen fades to black over 1 s, darkest colours first, fully black by the end (no walls stop him, as in the C); the camera stays where it was;
   - at the half the map's area name appears in the centre ("Coela Point" going to MAYO05) in white, in front of the black;
   - at full black the name goes and the screen stays black for 1 s more (the port's stand-in for the CD load, `Fade.LOAD_FRAMES`); then it fades in over 1 s, with the tamer and Agumon standing still at the exit that matches the one you took;
   - the clock and bars stop during the change and come back after it.
   - Wrong if: the name is off-centre, the fade doesn't cover the tamer and Agumon, you warp back at once (a loop), or you can't move after arriving.
3. **Coming back:** go back through the same exit: you arrive at the exit you left from. A few map changes store another map as the previous one (`change_map_previous` in the data): the Birdra Transport room (ROOM12) to its six destinations, Great Canyon (GCAN08_1 → GCAN07), Dragon Eye Lake → BETL01, Secret Beach Cave (OGRE10 → map 0x87), Coela Point → Tropical Jungle (TROP01, previous = map 13). Where the game uses the previous map (e.g. fleeing a battle), the port uses the same one.
4. **Script walk-outs:** many exits are a script instead of a warp cell (121 of them: File City and its houses, the factory, the mountain paths, …). E.g. Green Gym (TRAI00) toward Jijimon's house: stepping on the exit, the tamer runs on toward a point past the edge (the script's `ENTITY_WALK_TO`) while the screen fades, stops there, and the map changes. Wrong if: he stands still at the exit, or keeps running on the new map.
5. **Exits with a short scene** (17 of them; `tests/exit_scan.tscn` plays them all headless: `godot --headless --fixed-fps 60 --path . res://tests/exit_scan.tscn`, every line `ok`). Teleport with the debugger's Maps tab and watch the scene before the warp:
   - Great Canyon Top (GCAN08_1): the first time, "What?", the walk around, "I felt the ground move."; step off the cell and back: "What? No way!", they sink (the ground objects swap) and fall to GCAN07;
   - Grey Lord's Mansion (YAKA24): at the books, the choice; "I'll take it": the walk, "Huh?", they slide away and land wounded on YAKA15 ("I'm wounded!");
   - Secret Beach Cave (OGRE11): Ogremon's gang scene, then FRZL16 (the battle is skipped until battles are ported);
   - Toy Town (OMOC04–07): the locked door ("It won't open." until trigger 349), then the door rooms: the right door (picked at random on entry) opens and you walk through, a wrong one plays its trap;
   - TOPN01, GCAN10, FACT01: a short walk or turn, then the warp.
   - Skipped for now, by design: sounds, chests, battles and a few built-in routines (0x2B, 0x2C, 0x37), which come with steps 5b–5e.
6. **Trigger cells:** on MAYO04A, stand at the sign and press ✕: the sign's text (section 0x51) runs. Cells that start a scene when stepped on (51–79) run it at once, if their map has one.
7. **Toilet:** step on a toilet while Agumon needs to go: its scene plays (see Camera, item 4).
8. **Debug `[` / `]`:** the previous / next map, with the same fade and name, to its exit 0.

## NPCs (`scripts/field/npc.gd`, `field_entities.gd`, `field_digimon.gd`, `specs/npc.md`)

`test_npc.gd` prints `OK: NPC checks`. In the game (F5), the map setups place the map's Digimon; between talks they wander their paths and react to you by their follow mode (`specs/npc.md` §2.10). Check:
1. **Native Forest (MAYO04A), the start:** by day (7:00–19:00) an Aruraumon walks back and forth between two points by the fence, turning in arcs; at night (`T` advances the hour) a Goburimon instead (after re-entering the map). Wrong if: none appear, two of the same, or it walks on the spot / never turns back.
2. **Talking:** walk into the Aruraumon. It talks on contact (autotalk 1): the tamer stops against it, he and the NPC turn to face each other, and the box opens with its name in yellow ("I guess I can play with you."). Its battle is reported as unported, and the section goes on.
3. **✕ talk:** File City (press `]` to the TWNA maps) or Jijimon's house: walk up to an NPC with autotalk 0, face it and press ✕ from a short distance (the reach is 50 units in front). Its section starts; walking into it without ✕ only stops you.
4. **Blocking:** you can't walk through an NPC; Agumon goes around NPCs as it goes around walls.
5. **Scenes:** sections that walk, turn, slide or animate NPCs play those moves, with the camera pans (see Camera). Compare a scene you know: who turns to whom, who walks where.
6. **The original's slot-7 quirk** (`specs/npc.md` §6, `PLANS.md`): after a scene that animates an NPC, on a map whose last NPC has script id 12 (File City's Whamon), check the real game: can you still talk to that NPC?
7. **Wandering (3b):** on maps with several NPCs (File City, the forests), the walkers go from point to point, stop for a moment (½–4 s), and loop. Against a wall or another Digimon they slide along it and turn away instead of walking into it. Wrong if: one stays pressed into a wall walking on the spot, or walks through walls.
8. **Wild enemies (follow mode 12):** walk into an enemy's range (e.g. MAYO04A's walking Aruraumon, by day, or Goburimon, at night: 300 units around the point where it first stands). It walks, then runs, at the place where you were when it noticed you (it doesn't steer after you). It stops there or when it touches you, waits 2 s, then walks back to its place. Touching you starts its section (the battle is reported). Compare with the game: the moment it notices you, the speed of the charge, the wait.
9. **Looking at you (follow mode 2):** near such an NPC it stops and turns to follow you; when you walk away it goes back to its path.
10. **During a talk:** the NPC you talk to stops; the others keep moving. After the talk it restarts its path from the first point.
11. **Agumon and NPCs:** when Agumon bumps into an NPC it no longer overlaps it: it stops moving towards it and turns along it.

## Camera (`scripts/field/field_map.gd`, `tamer.gd`, `specs/camera.md`; the script's moves `specs/script.md` §2.7 "Step 4")

`test_camera.gd` prints `OK: camera checks`. The camera now moves as the original's: while you hold a direction it scrolls by exactly how far the tamer moved on screen; it doesn't re-centre him. In the game (F5), check:
1. **Plain walking:** the tamer stays where he is on screen while you walk; the camera doesn't move while nothing is held. Wrong if: it jitters, or lags behind and catches up.
2. **Map edges:** walk to an edge of a big map (Native Forest's sides): the camera stops and the tamer walks on towards the screen's edge. Walk back: the camera starts again only once he is back where it stopped (about the screen's centre). Compare with the game: where on screen he is when the camera starts again.
3. **Walk-out exits** (Green Gym towards Jijimon's house): the camera stays put while he runs off, during the fade.
4. **The toilet:** when Agumon needs to go (Care, item 4: about every 4 game hours, then 42 game minutes before the accident), walk onto a toilet cell on a map that has one (MAYO01 does). Then:
   - the camera slides to the toilet over 1 s while Agumon runs there (two legs: to a point near it, then onto it), the tamer turning to follow it;
   - Agumon squats (its animation 10); at the end: not poopy any more, happiness and discipline + 2;
   - the camera slides back to the tamer over 1 s while Agumon walks back to the first point; then the field is free again.
   - Compare with the game: the tamer's facing while Agumon walks back (the C turns him to a garbage point there, `specs/care.md` §6), the timing.
5. **Cutscenes with camera moves:** sections that pan the camera (`MOVE_CAMERA_TO`, `MOVE_CAMERA_TO_ENTITY`; e.g. the File City scenes, Jijimon's house) and walk or slide entities with it. After a pan back to the tamer he is centred again; after a pan elsewhere, the follow carries on from there, so he may stay off-centre until you walk. Compare where the tamer is on screen afterwards with the game.
6. **Rising / sinking** (`ENTITY_MOVE_TO_AXIS` on y, 15 uses): entities slide up or down without changing animation.

## Map objects (`scripts/field/map_overlays.gd`, `field_map.gd`, `specs/map_objects.md`)

`test_map_objects.gd` prints `OK: map object checks`. `render_check.gd` prints `background 0 / 76800 pixels differ` and saves the frame in `user://` (it says where): open it, the map's sprites must sit on the background. In the game (F5), check:
1. **Animated details:** Native Forest's flowers (MAYO01, the lower left), water, torches and smoke on other maps. Walk behind MAYO01's bush by the toilet: it covers the tamer (ISSUES.md I-1). Compare their speed with the game, and the tamer walking in front of and behind the parts of the background that are sprites (tree trunks, roofs). Wrong if: a sprite is offset from the background, flickers, or covers the tamer when he is in front of it.
2. **Brightness:** the glowing (additive) sprites, e.g. File City's lights and the Factorial Town effects. Compare with the game: Godot blends in linear colour, so they may look brighter (`specs/map_objects.md` §6).
3. **File City TWNB04's lights** (instances 49–50): off from 7:00 to 18:59, on otherwise.
4. **Doors:** the Great Canyon gates (GCAN02/03/06/10) sliding apart in their scene before the warp; Grey Lord's Mansion doors (YAKA11A / 11B / 13), with both halves of the double doors (model 10). Compare whether those doors snap shut at the end of their swing as in the port (§6).
5. **Scenes that move sprites:** Amida Forest (TROP06), Secret Beach Cave (OGRE10), Factorial Town (FACT08B).
6. **Digimon Bridge (MAYO08A):** when the bridge is broken, its cells are blocked (the tamer stops before them).
7. **Snow** on Freezeland (FRZL01–16): flakes falling over everything, drifting, melting at the bottom.
8. **Day / evening / night:** the sprites change palette with the background, at the end of its fade.
9. **No grey dots at night:** the background's transparent texels show black (ISSUES.md I-4), e.g. the rocks of Native Forest at night.

## Field lighting (`scripts/content/psx_lit.gd`, `scripts/field/field_lighting.gd`, `specs/lighting.md`)

`test_lighting.gd` prints `OK: lighting checks`. The models are now lit by the map's light and a fixed ambient, as the original. In the game (F5), check against the original:
1. **By day:** the tamer and the Digimon lit from above: heads and shoulders lighter, sides and the parts facing down darker. Wrong if: lit from below (the light's direction, `specs/lighting.md` §5), or much darker / brighter overall than the game.
2. **Evening (16:00, `T` to advance):** warmer, less green and blue.
3. **Night (20:00):** clearly darker (ISSUES.md I-2, `issues/evidence/dw_night_real_game.png`).
4. **The change:** the models change at the end of the hour's 25-frame fade, with the palette sprites, not during it.
5. **Doors and props** (Grey Lord's Mansion doors, the poop) are lit the same way.
6. **The poop** (ISSUES.md I-5): no dark ring around it; a soft shadow darkens the ground under it instead (compare `issues/evidence/dw_real_poop_look.png`).
7. **Other semi-transparent models** (technique effects, shadows): their glowing or darkening parts blend with what is behind them instead of covering it.

## Debugger and render scale (`scripts/debug/debug_window.gd`, `field.gd`; ISSUES.md D-1, I-3)

In the game (F5):
1. **The windows:** the game opens at 1280 × 960 (4:3); a "DW debugger" window opens beside it (F1 hides / shows it, its close button hides it).
2. **Status tab:** the map, the clock and the last message follow the game.
3. **Maps tab:** type part of a name (`MAYO`, `File City`): the list narrows. Double-click a map (or select it and press Go): the tamer warps there with the fade, at the exit chosen (out-of-range exits are clamped).
4. **Render tab:** 1× is the PSX's blocky 3D, 4× smooth; switching is immediate. At every scale the background is unchanged, and the text boxes, the condition bubbles and the map name sit where they did (they use the models' screen positions).
5. **Textures** (ISSUES.md I-6): Palmon (MAYO03) and Aruraumon (MAYO04A) without speckles or a crawling pattern, at 1× and 4×.
6. **Running** (ISSUES.md I-7): at 4× the picture doesn't shake while the tamer runs; at 1× the scroll is in whole pixels as before.
7. **Text and windows filter** (ISSUES.md D-3, Render tab checkbox, on by default): the text boxes' letters, the box borders, the clock and the status bars have rounded edges instead of square steps, in their own colours (no blur); the box backgrounds still blend with the scene. Off: square PSX pixels.

## Care (`scripts/systems/care.gd`, `specs/care.md`)

`test_care.gd` prints `OK: Care checks`. Run the project (F5):

1. **Mood and bars:**
   - a new game's Agumon has happiness 50, so when standing still he plays his happy animation now and then;
   - bottom right, next to the help line, two bars: happiness (smiling face) and discipline;
   - at 50 / 50 the happiness bar is half full (12 of 25 dots) and the discipline bar shows only its background row;
   - the bars slide off to the right whenever the clock slides away (the sleep scene) and come back with it.
2. **Bubbles:** a bubble rises over Agumon's head, bobs, and pops after about 2.5 seconds, then shows again every 3 seconds while the condition lasts:
   - hungry: a piece of meat;
   - poopy: a poop;
   - sleepy: 1–3 Z's;
   - tired, sick, injured: their own icons.
   
   With two conditions the two bubbles take turns. A new game starts with "hungry" counted as already shown, so the very first hungry bubble comes about 3 seconds late (a C quirk, `specs/care.md` §6).
   - Wrong if: the bubble sits on the ground, is far too big or small, or never pops.
   - The bubble is translucent: you see the background through it, the icon is solid.
2. **Sleepy and the sleep scene:**
   - Agumon gets sleepy at 19:00 (press `T` until 19:00).
   - Press `Z` (the menu's "Sleep"). Before 19:00 the help line says it only works while he is sleepy.
   - At 19:00 or later:
     - the clock slides away;
     - the tamer and Agumon face each other, and the tamer plays his animation;
     - Agumon lies down, falls asleep, and the screen fades to black;
     - it fades back in at 04:00 of the next day, the clock returns and both walk again.
   - Wrong if: the scene hangs at a step, the time after it isn't 04:00, or you can't walk after it.
3. **A missed night:** stay awake past 19:00 without pressing `Z` and keep `T` going to 04:00. Agumon simply wakes up (a care mistake); his sleepy walk ends.
4. **Pooping in the wild:** Agumon needs the toilet about every 4 game hours (4 real minutes). It then takes 42 game minutes (about 42 seconds at discipline 50) until the accident:
   - he plays his "need to poop" animation now and then;
   - then you stop, he runs to you, squats and stands up;
   - you can walk again.
   - Try it with Agumon far away too: walk off, or put a wall between you, just before the accident. He runs straight to you, through walls (the original has no wall check in this scene).
   - Wrong if: you stay frozen, or he keeps running without squatting.
   
   A poop pile (a brown swirl with a shadow) stays on the ground in front of where he squatted. It is still there after you leave the map and come back, and there are at most 16 per map.
5. **Hunger:** a hungry bubble at Agumon's hunger hours (1, 5, 9, 13, 17, 21 o'clock; the first call is 09:00 on a new game). It lasts 1.5 game hours if you don't feed him (no feeding yet), then the next call is set.
6. **Debug panel (`C`):** the care values on the right; click the buttons (focus stays with the game, so arrows still move).
   - **Speed:** ×60 makes one game hour pass in a real minute. Every value moves as in the game, only sooner: the clock, food, the poop level every 10 minutes, energy every hour.
   - **Hunger:** "hungry now" shows the meat bubble at once, and "starve" counts down. After 1.5 game hours without food the call ends; with energy below 20 it's a care mistake ("mistakes" + 1).
   - **Poop:** "poop now" starts the accident on the next frame. "toilet" while poopy clears it: poop level 48, happiness and discipline + 2.
   - **Sickness:** toggle "sick" to see its bubble. At ×60, happiness and discipline drop every game hour (−10 / −5) and "timer" rises; at 12 a life is lost and the help line names the collapse script. "injured 12h" makes him sick the original way, with the "<name> is sick" message box (Text section above).
   - **Praise / scold:** praise lowers discipline by 5 and raises happiness; scold raises discipline by 2 and lowers happiness by 10. The bars follow.
   - **Sleep:** "stats", then wait for 19:00 (or "+1 hour") and press "sleep". HP / MP rise during the night: about 70–80 % of the maximum for a full night.
   - **Wrong if:** a value jumps somewhere the game couldn't put it, or the bars and bubbles don't follow the values.
7. **What isn't there yet:**
   - the butterfly over an unhappy partner;
   - feeding, praise / scold, toilets (menus);
   - the collapse / death script (the help line names it), evolution, the butterfly.

## Partner (`scripts/field/partner.gd`, `psx_animator.gd`, `specs/partner.md`)

`test_partner.gd` prints `OK: Partner checks`. Then run the project (F5):

1. **Start:** Agumon stands next to the tamer and idles.
2. **Walk away slowly:**
   - he follows, walking when the distance is medium (about 2.5–3.5 Agumon widths);
   - he runs when you get further (hold Shift);
   - when you stop, he finishes his step, stops next to you and idles.
3. **Close:** he doesn't walk into the tamer and stops facing him, also at a diagonal. Run, then stop: once he has caught up he stands still (he must not keep turning on the spot).
4. **Standing still:** after a few seconds he plays another standing animation now and then. Hungry, sleepy, happy and other mood animations need the care step.
5. **Walls:** walk around a corner or a tree so that the wall is between you. He takes the way you walked; he never stays pressed into a wall or corner. On a tight corner he may cut a little into the wall: the original doesn't stop him at walls either (`specs/partner.md` §3). Compare with the game: does Agumon cut corners the same way? If you walk far away while he's off screen, he catches up by appearing on your path.
6. **Map changes:** after a warp he appears 200 units from your spawn point, facing you.
7. **Other Digimon:** select the `Field` node and type a key in **Debug Partner** in the Inspector (e.g. `dw1:gabumon`, `dw1:greymon`; keys are shown in the DW Data dock), then F5: that model follows instead, with its own size. Clear it afterwards (it's saved in the scene).
   - Wrong if: he floats, sinks, slides without animating, runs in place, or gets stuck walking next to the tamer.
8. **What isn't there yet:**
   - care states (sleep, eating, poop), other entity collisions (NPCs), the Health Shoe;
   - the tamer can walk through the partner (the tamer's side of the collision comes with NPCs).

## Clock (`scripts/systems/clock.gd`, `clock_hud.gd`, `specs/clock.md`)

`test_clock.gd` prints `OK: Clock checks`. Then run the project (F5):

1. **HUD:** the alarm clock sits in the top-left corner: two bells, the face (day / evening / night sectors), the minute hand, a small creature on top that moves, and a yellow hour marker on the rim. The game starts at 08:00, so the hand points up and the marker is on the right side.
2. **Time runs:** one game minute per real second. The hand turns 6° per minute; the help line at the bottom shows the year, day and time.
3. **`T`** jumps one hour ahead (debug key). At 17:00 the creature on top switches to its night frame (with a "Z"); at 16:00, 20:00 and 06:00 the background fades over about a second: day → evening → night → day. Maps without a day / night cycle never change (110 of them, e.g. Drill Tunnel `TUNN01`, Grey Lord's Mansion `YAKA02`; use `[` / `]` to get there).
   - Wrong if: the fade jumps instantly, happens at other hours, or happens indoors.
4. **Real time:** waiting from 15:59 to 16:00 without pressing `T` starts the same fade on its own.
5. **Map changes:** walking to another map at night keeps the night background.
6. **What isn't there yet:**
   - the partner's status bars next to the clock (care step);
   - the clock sliding out while scripts stop the time (no scripts yet);
   - the tamer and Digimon don't get darker at night (no field lighting yet).

## Game state (`scripts/state/game_state.gd`, `specs/game_state.md`)

There is no save menu yet, so these checks are about the save file itself.

1. `test_game_state.gd` prints `OK: GameState checks`. Its line `ERROR: Parse JSON failed` is expected: it is the test's broken save being refused.
2. Open the test's save `user://test_game_state_saves/slot_01.json`. On Windows that is `%APPDATA%\Godot\app_userdata\Digimon World GODOT\test_game_state_saves\`; in the editor: Project > Open User Data Folder.
   - It is readable JSON: `preview` (player, partner, area "File City", playtime), then `state` with `clock`, `tamer`, `partner` (with `care`: about 65 fields such as `remaining_lifetime`, `happiness`, `poop_level`), `world`, `money`, `inventory`, `script`.
   - Content is written as keys: `"digimon": "dw1:agumon"`, `"item": "dw1:lrg_recovery"`, `"screen": "dw1:twna01"`.
   - `script.values` has 35 entries (0–34): the original saves only those.
3. New-game values, if you remember the game's start:
   - 08:00 on day 0;
   - the partner has 3 lives and a lifetime of 288;
   - the start is File City.
   
   The 50,000 bits and the full inventory are the C default record, which the intro scripts may replace (`specs/game_state.md` §5).
4. Hand edit: change `money` in `slot_01.json` and load it, e.g. from a script or the debug panel when it exists. The new value is used; a broken edit is refused with a message instead of loading garbage.
