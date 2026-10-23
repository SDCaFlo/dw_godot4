# Verifying the Godot game systems (human checks)

The porters have their own checklists (`asset_porter/VERIFY.md`, `data_porter/VERIFY.md`); this file covers the game systems ported to GDScript. Every system has a headless test that must print `OK` (run from `dw_godot/`, Godot 4.7, after both porters):

```
godot --headless --path . -s res://tests/test_clock.gd
godot --headless --path . -s res://tests/test_game_state.gd
godot --headless --path . -s res://tests/test_game_data.gd
godot --headless --path . -s res://tests/test_content.gd
godot --headless --path . -s res://tests/test_data_dock.gd
```

With the Steam build of Godot the executable is `godot.windows.opt.tools.64.exe` in the Steam library folder (`steamapps\common\Godot Engine\`); call it as `& "<path>" --headless --path . -s res://tests/test_game_state.gd` from PowerShell. Godot 4.7 prints a "GDScript backtrace" under each error or warning, including the tests' expected ones.

The tests prove the code does what the spec says. What they can't prove is that the spec matches the game. That is what the checks below are for: compare with what you know of the game.

Sections are added as systems are ported (`PLANS.md`).

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
