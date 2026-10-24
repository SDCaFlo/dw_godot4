# Verifying the Godot game systems (human checks)

The porters have their own checklists (`asset_porter/VERIFY.md`, `data_porter/VERIFY.md`); this file covers the game systems ported to GDScript. Every system has a headless test that must print `OK` (run from `dw_godot/`, Godot 4.7, after both porters):

```
godot --headless --path . -s res://tests/test_script.gd
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
   - the tamer keeps running straight in his direction while the screen fades to black over 1 s (no walls stop him, as in the C); the camera stops following him;
   - at the half the map's area name appears in the centre ("Coela Point" going to MAYO05) in white, in front of the black;
   - at full black the name goes and the screen stays black for 1 s more (the port's stand-in for the CD load, `Fade.LOAD_FRAMES`); then it fades in over 1 s, with the tamer and Agumon standing still at the exit that matches the one you took;
   - the clock and bars stop during the change and come back after it.
   - Wrong if: the name is off-centre, the fade doesn't cover the tamer and Agumon, you warp back at once (a loop), or you can't move after arriving.
3. **Coming back:** go back through the same exit: you arrive at the exit you left from. A few map changes store another map as the previous one (`change_map_previous` in the data): the Birdra Transport room (ROOM12) to its six destinations, Great Canyon (GCAN08_1 → GCAN07), Dragon Eye Lake → BETL01, Secret Beach Cave (OGRE10 → map 0x87), Coela Point → Tropical Jungle (TROP01, previous = map 13). Where the game uses the previous map (e.g. fleeing a battle), the port uses the same one.
4. **Script walk-outs:** many exits are a script instead of a warp cell (121 of them: File City and its houses, the factory, the mountain paths, …). E.g. Green Gym (TRAI00) toward Jijimon's house: stepping on the exit, the tamer runs on toward a point past the edge (the script's `ENTITY_WALK_TO`) while the screen fades, stops there, and the map changes. Wrong if: he stands still at the exit, or keeps running on the new map. A few exits start a short scene first (GCAN08_1, YAKA24, OGRE11, TOPN01, OMOC04–07); those still lack their scene (NPCs and camera moves come later).
5. **Trigger cells:** on MAYO04A, stand at the sign and press ✕: the sign's text (section 0x51) runs. Cells that start a scene when stepped on (51–79) run it at once, if their map has one.
6. **Toilet:** step on a toilet while Agumon needs to go: its script (MAPHEAD 0x4E2) runs; Agumon's toilet scene itself is unported (reported), so only the texts show for now.
7. **Debug `[` / `]`:** the previous / next map, with the same fade and name, to its exit 0.

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
5. **Walls:** walk around a corner or a tree so that the wall is between you. He takes the way you walked instead of pressing into the wall. If you walk far away while he's off screen, he catches up by appearing on your path.
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
