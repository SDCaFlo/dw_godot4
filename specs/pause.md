# The pause

START stops the game and shows a "Pause" box over a half-dark screen; START again resumes. Port of `handlePause` and its box.

## 1. C sources

| C | Where | Port |
|---|---|---|
| `handlePause` | `utils2.c:402` | `Pause.handle` / `Pause.poll`, `PauseHost.frame` / `_process` |
| `createPauseBox` | `utils2.c:443` | `Pause.create_box` → `PauseHost._on_box_created` |
| `removePauseBox` | `utils2.c:434` | `Pause.remove_box` → `PauseHost._on_box_removed` |
| `renderPauseBox` | `utils2.c:462` | `PauseHost._render_box` |
| `pauseFrame` | `utils.c:75` | `UIBoxes.render_frame` (§4) |
| callers | `main.c:3962` (`gameLoop`), `battle_main.c:1847` (`BTL_battleMain`), `std_main.c:5602` (the match loop); `removePauseBox` after the last two loops (`battle_main.c:1851`, `std_main.c:5605`) | `Field._handle_pause` |
| text | `MAIN_D_80134430` (`text/main/utils2.yaml`): "Pause" / ポーズ | `GameData.text(Pause.TEXT_ID)` |

`VS__handlePause` (`vs_combat.c:1233`) belongs to the VS mode, not planned (`PLANS.md`).

## 2. Original behaviour

**When.** `handlePause` runs at the end of every frame of three loops: the field's `gameLoop` (after the draw), the battle's fight loop (after `BTL_battleTickFrame`), and the tournament match's loop (after `STD_battleTickFrame`). The other loops (the battle intro and end, the arena's bracket and scenes, the menus' own loops) don't call it.

**Steps** (`utils2.c:402-432`):
1. If `PAUSE_BOX_VISIBLE` ≠ 0: `removePauseBox()`, `PAUSE_BOX_VISIBLE = 0`. So the box closes at the end of the first frame after the pause.
2. Return if `(readPStat(0) == 3 || IS_GAMETIME_RUNNING == 0) && GAME_STATE == 0`: in the field, not while a script has taken over (script value 0 = 3, `scriptPauseGame`) or game time is stopped. In battles (`GAME_STATE` 1) and matches (4 / 5) this check doesn't apply.
3. Return if `FADE_PROTECTION == 1` (a fade to black: warps, battle starts).
4. `PAUSE_INPUT = PadRead(1)`. If START (0x800) is down and wasn't in `PAUSE_INPUT_PREVIOUS`: `PAUSE_STATE ^= 1`. Then `PAUSE_INPUT_PREVIOUS = PAUSE_INPUT`.
   - The pause has its own previous read, updated only here. A return in step 2 or 3 leaves it stale: START held through a script pauses on the first free frame.
5. If `PAUSE_STATE` ≠ 0: `createPauseBox()`, `pauseFrame()` twice, `PAUSE_BOX_VISIBLE++`.
6. `while (PAUSE_STATE != 0)`: read the pad, toggle on a new START press. Nothing else runs (no tick, no draw): the screen keeps the last picture. Sound goes on, since the SPU and libsnd's sequencer run on interrupts (`SsSetTickMode(SS_TICK240)`, `sound.c:524`).

**`createPauseBox`** (when `MAIN_D_80134E7C` ≠ 1):
- `drawString("Pause", 0x78, 0xF0)` into the text area, in the current text colour.
- `createStaticUIBox(5, 1, 0, (-0x1A, -0xE, 0x38, 0x18), NULL, renderPauseBox)` (US; EU width 0x34, JP 0x30). Colour 1 is the blue-grey fill; the box opens at once.
- `MAIN_D_80134E7C = 1`, `playSound(0, 3)`.

**`removePauseBox`** (when `MAIN_D_80134E7C` ≠ 0): `removeStaticUIBox(5)`, flag 0, `playSound(0, 3)`.

**`renderPauseBox`**:
- A black box over the whole screen (−0xA0, −0x78, 0x140, 0xF0), attribute 0x40000000: semi-transparency rate 0, so the screen is drawn at half brightness. Its ordering-table layer is `7 − 5 = 2`: in front of the world, the HUD and boxes 0–4, behind box 5's own fill (layer 1).
- The text: `renderString(0, x + 6, y + 6, 0x2A, 0xC, 0x78, 0xF0, 0, 1)` at the box's final position, colour 0, layer 0, with a shadow (US; EU width 0x28, JP 0x24).

**`pauseFrame`** ticks and draws every object (`tickObjects`, `renderObjects`), without reading the pad and without the script. Its purpose is to get the box into both frame buffers. Its side effect is that every object (the entities, the clock, the UI boxes' tick functions) runs two more frames before the freeze.

## 3. Godot design

- **`Pause`** (`scripts/systems/pause.gd`, logic): `PAUSE_STATE`, `PAUSE_BOX_VISIBLE`, `PAUSE_INPUT_PREVIOUS`, `MAIN_D_80134E7C`.
  - `handle(input, blocked)`: steps 1–5. Returns true when the wait loop must run.
  - `poll(input)`: one read of the loop.
  - `is_blocked(in_field, script_value_0, game_time_running, fade_protection)`: steps 2–3.
  - The signals `box_created` / `box_removed`.
- **`PauseHost`** (`scripts/field/hosts/pause_host.gd`, node `Systems/PauseHost` in `field.tscn`, `PROCESS_MODE_ALWAYS`):
  - `frame(in_loop, blocked)`, at the end of every field frame. It reads START (the action `pad_start`, plus taps since the last read).
    - Outside the three loops it only closes a box left over, which is `removePauseBox` after the battle / match loop.
    - When `handle` returns true, it pauses the scene tree.
  - `_process`: while paused, `poll` once per Godot frame; when the state goes back to 0, it unpauses the tree.
  - It draws the box on `UIBoxes` slot 5 and plays sound 0 / 3 through `Sound`.
- **The freeze.** `get_tree().paused`:
  - every entity, animation and tween stops;
  - `GameLoop` stops emitting `frame`, and leaves its catch-up loop as soon as a frame paused the tree, dropping the time owed;
  - the `Sound` autoload is `PROCESS_MODE_ALWAYS`, so the music and the sounds go on as on the PSX.
- **`Field._handle_pause(in_loop, in_field)`**, last in each branch of `Field._frame`:
  - the field: in the loop, with the field gate;
  - a battle: in the loop while `BattleHost.in_fight()` (phase `FIGHT`);
  - a tournament: in the loop while `Arena.in_fight()` (session `MATCH`, match `FIGHT`).
  - `blocked` comes from script value 0, `Clock.running` (`IS_GAMETIME_RUNNING`) and `Fade.protection`.
- **The box's draw.** `UIBoxes` draws a static box's frame and then calls its render. So `_render_box` draws the dark screen, box 5's frame again over it, then the text.
- **START on the keyboard:** `P` (port-only; the pad's START button as before).

## 4. Differences from the C

- **`pauseFrame`'s object ticks are not reproduced (stand-in).** The port draws the boxes twice (`UIBoxes.render_frame`: the render functions and their counters) but doesn't tick the objects. In the original the world runs two more frames (0.1 s) after START before it freezes; in the port it freezes on the frame START was read. Ticking "the objects" alone isn't possible: the port's frame doesn't separate the object ticks from the script and the AI.
- **The frozen picture** is the live 3D view with nothing moving. A shader driven by `TIME` would keep animating; none of the field's does today.

## 5. Tests

`tests/test_pause.gd`:
- the gate (field / battle, script value 0, game time, fade);
- the toggle on a new press only (held START, other buttons);
- the box opening once, with `PAUSE_BOX_VISIBLE`, and closing on the next handle;
- the stale previous read after a blocked frame;
- the host: the tree paused and resumed, box 5 (static, colour 1, rect, drawn before the freeze), the sound on open and close, the box closing outside the loops;
- `GameLoop` stopping in the middle of a catch-up step.
