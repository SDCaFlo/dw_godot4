# Save system and Title menu

Status: draft for step 4e-2 (`PLANS.md` 5e-4e-2).

The save system in *Digimon World* connects the memory card save files, the title screen boot flow, in-game save points (the Save Machine), and the sleep save confirmation.

Read `specs/game_state.md` first (which specifies the save payload, serialization, and `GameState` fields) and `specs/scenes.md` (scene composition and decoupling).

---

## 1. The C Code Reference

| C function / data | Where | What |
|---|---|---|
| `runMainMenu` | `main/main.c:3685–3726` | Title menu loop; loads `ETCNA/TITLE2.TIM`, runs `tickMainMenu` and `renderMainMenuBackground` |
| `tickMainMenu` | `main/main_menu.c:3319–4630` | State machine for all main menu / save / memory card views |
| `renderMainMenu` | `main_menu.c:5153–5228` | Draws the active menu view (`MENU_VIEWS[CURRENT_MENU]`) |
| `renderInitialMenu` | `main_menu.c:5342–5368` | Title menu options: New Game, Continue, Battle Mode |
| `renderSelectSlot` | `main_menu.c:1915–1933`, `:2317–2415` | Slot selection view with preview (player, partner, area, time) |
| `renderSleepMenu` | `main_menu.c:1935–1951` | "Do you want to save? Yes / No" popup after partner sleeps |
| `renderConfirmOverwrite` | `main_menu.c:1953–1985` | Confirmation box when saving over an existing slot |
| `openSaveMachine` | `main_menu.c:5273–5286` | Builtin 0x30: opens save machine (menu 0x3C / 0x46 / 0x44) |
| `gameClearSave` | `main_menu.c:5318–5329` | Builtin 0x36: sets `MAIN_STATE = 2`, awards Machinedramon data, saves |
| `partnerTickSleep` | `main/partner.c:324–350` | Partner sleep sub-states 5–6: triggers menu 40 (`0x28`) while screen is dark |
| `recalculatePPandArena` | `main/main.c:3902–3931` | Recalculates Prosperity Points (script value 1) and clears arena triggers before saving |
| `writeSavegame` | `main_menu.c:5071–5134` | Gathers state into `SavegamePayload` and writes record |
| `loadSavegame` | `main_menu.c:5016–5069` | Restores state from `SavegamePayload` and sets `MAIN_STATE` |

---

## 2. Systems & Flows

### 2.1 Pre-Save State Adjustments (`recalculatePPandArena`, `main.c:3902`)
Before committing a save to disk, the original executes critical cleanup:
1. **Prosperity Points (PP):** Script value 1 (`pstats[1]`).
   - Resets PP counter to 0.
   - For every Digimon ID `i` from 3 to 58 (`0x03` to `0x3A`):
     - Check if `DIGIMON_DATA[i].level >= 3` and trigger `(0xC8 + i)` is set (city recruit flag).
     - If `i` is 0x0B (Numemon), 0x27 (Sukamon), or 0x35 (Nanimon): `pp += 1`.
     - Otherwise: `pp += (level - 2)`.
   - Store calculated `pp` in script value 1.
2. **Arena Triggers:** If script value 3 >= 23 (`0x17`):
   - Unset triggers `0x25`, `0x26`, and `0x27`.
3. **Script Value 0 Masking:**
   - If script value 0 equals 3 during save (`main_menu.c:5080`), temporarily set it to 0 during write and restore it to 3 immediately after.

### 2.2 Boot Modes (`MAIN_STATE`)
The title screen loads or starts a game, setting `MAIN_STATE`:
- **Mode 0 (New Game):** Runs intro questionnaire (`NewGameScene`), movie 1, and boots File City map `0xCC`.
- **Mode 1 (Continue Game):** Loads saved slot into `GameState`. Boots directly into saved `world.screen` (exit / coordinates), restores tamer and partner, starts map head script and clock.
- **Mode 2 (Game Clear Save):** Plays Movie 2 (`ED.STR`), then boots into File City (`world.screen`).

### 2.3 The 4 Save / Load Access Points

#### A. Title Screen (`TitleMenu`)
- Background: `ETCNA/TITLE2.TIM` (or `TITLE256.TIM`) displayed at native 320×240.
- Box: Centered menu box at (72, 50), size (176, 58) [US values: (0x48, 0x32, 0xB0, 0x3A)]:
  - `NEW GAME`: Starts Mode 0.
  - `CONTINUE GAME`: Enabled only if at least one save file exists in `GameState.save_dir`. Opens the `SaveSlotBox` in Load mode.
  - `BATTLE MODE`: Versus mode (stubbed / disabled with message until Arena/VS step).

#### B. Save Machine (Builtin `0x30`, `openSaveMachine`)
- Triggered by `CALL_ROUTINE 0x30` in scripts (e.g. Jijimon's house TWNA02 terminal).
- Dialogue / Options:
  - If partner is Champion / Ultimate (level >= 3): allows Save or Battle Registration.
  - Opens `SaveSlotBox` in Save mode.
  - Selecting a slot confirms save:
    - If slot already has data: shows "Overwrite this data? Yes / No".
    - On confirmation: calls `GameState.save_game(slot)`, shows "Save complete", and closes.

#### C. Sleep Save Prompt (Menu `0x28` / `renderSleepMenu`)
- Triggered during partner sleep in field or bed (`partner.c:325`):
  - In sub-state 5, while the screen is completely faded to black (`FADE_OUT_CURRENT > 39`), opens a prompt:
    - Text: "Do you want to save?"
    - Choices: "Yes" / "No".
  - If "Yes": opens `SaveSlotBox` in Save mode over black screen.
  - Upon completion or if "No": transitions to sub-state 6, wakes up partner, advances clock, and fades back in.

#### D. Game Clear Save (Builtin `0x36`, `gameClearSave`)
- Triggered upon beating the final boss / game ending:
  - Sets `MAIN_STATE = 2`.
  - Sets save location `world.screen` to File City top map (`TWNA01`).
  - Awards Machinedramon registration data to slot 39.
  - Opens `SaveSlotBox` to save game-clear progress.

---

## 3. Decoupled Architecture & Scene Composition

To ensure full moddability and clean decoupling:

```
[ Game (scripts/game/game.gd) ]
       │
       ├─► [ TitleMenu (scenes/title/title_menu.tscn) ]
       │         │
       │         └─► [ SaveSlotBox (scenes/ui/save_slot_box.tscn) ] (Mode: Load)
       │
       ├─► [ NewGame (scenes/new_game/new_game.tscn) ]
       │
       ├─► [ MoviePlayer (scenes/movie/movie_player.tscn) ]
       │
       └─► [ Field (scenes/field/field.tscn) ]
                 │
                 ├─► [ Systems/ScriptHost ]
                 │         │
                 │         └─► [ Routines/SaveRoutines (builtin 0x30 & 0x36) ]
                 │                   │
                 │                   └─► [ SaveSlotBox ] (Mode: Save)
                 │
                 └─► [ Systems/Entities/Partner ]
                           │ (sub-state 5 during sleep)
                           └─► [ SleepSavePrompt ] ──► [ SaveSlotBox ] (Mode: Save)
```

### Components

1. **`TitleMenu` (`scenes/title/title_menu.tscn`, `scripts/ui/title_menu.gd`)**:
   - Manages the title background, music (`TITLE` / `BGM`), and cursor selection.
   - Emits signals:
     - `new_game_requested`
     - `load_game_requested(slot: int)`
     - `battle_mode_requested`

2. **`SaveSlotBox` (`scenes/ui/save_slot_box.tscn`, `scripts/ui/save_slot_box.gd`)**:
   - Reusable standalone UI component for slot browsing, inspectable previews, and confirmations.
   - **Data source:** Queries `GameState.list_saves()` and `GameState.preview()`.
   - **Display:**
     - Slots displayed with index, player name, partner species, map location, and formatted playtime.
     - Extensibility: Supports standard 2-slot view (authentic PSX) with paginated or list scrolling to support N slots seamlessly for modders and players!
   - **Confirmation sub-boxes:**
     - Overwrite warning dialog.
     - Success notification ("Data saved.").
   - Emits signals:
     - `slot_selected(slot: int)`
     - `cancelled`

3. **`SaveRoutines` (`scripts/script/save_routines.gd`)**:
   - Extends `Node` / `MenuRoutines`.
   - Declares `routines = [0x30, 0x36]`.
   - Implements `start(routine) -> bool` and `tick(routine)`.
   - Plugs into `ScriptRoutines` via standard composition without any hardcoded branch in the script interpreter.

4. **`Partner.tick_sleep()` Sleep Prompt Integration**:
   - Partner sub-state 5 yields to the sleep save prompt before waking up.
   - Decoupled via `MenuHost` or `UIBoxes` prompt so `Partner` logic remains headless testable.

---

## 4. Tests & Verification

- `tests/test_save_system.gd`:
  - Recalculate PP and Arena trigger checks (verifying PP calculation with various recruit triggers).
  - Slot preview formatting and sorting.
  - Multi-slot listing and save/load cycle through `SaveSlotBox` logic.
  - Title menu navigation and conditional Continue button enablement.
  - Save machine routine (0x30) step progression and slot selection.
  - Sleep save prompt response handling (Yes -> save -> wake, No -> wake).
- In-game verification documented in `VERIFY.md` under "Save and Title Menu".
