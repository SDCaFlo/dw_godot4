# Verifying the Godot game systems (human checks)

The porters have their own checklists (`asset_porter/VERIFY.md`, `data_porter/VERIFY.md`); this file covers the game systems ported to GDScript. Every system has a headless test that must print `OK` (run from `dw_godot/`, Godot 4.7, after both porters):

```
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

## Care (`scripts/systems/care.gd`, `specs/care.md`)

`test_care.gd` prints `OK: Care checks`. The care values aren't shown on screen yet (bubbles, bars and the debug panel come next), so these checks use what you can see: animations, the clock and the help line. Run the project (F5):

1. **Mood:** a new game's Agumon has happiness 50, so when standing still he plays his happy animation now and then.
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
   
   The pile isn't drawn yet. It is saved in the game state (`world.poop`).
5. **Hunger and the rest** (hunger calls at 1, 5, 9, 13, 17 and 21 o'clock, sickness, lifetime) only show through animations until the debug panel exists. The tests cover their timings.
6. **What isn't there yet:**
   - bubbles, status bars, poop piles, the debug panel;
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
