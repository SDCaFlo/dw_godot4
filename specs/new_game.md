# New game and naming

Status (2026-10-27): coded, step 4e-1 (`PLANS.md` 5e-4e). See "As built" at the end.

A new game in the original:
1. **The title menu.** The player picks New Game (4e-2; until then the port boots straight into step 2).
2. **The intro.** Jijimon walks in on a black screen and asks three questions; the answers pick the partner, Agumon or Gabumon. He then asks the tamer's name and the partner's name, each typed on the naming screen.
3. **Movie 1** (`OP2.STR`).
4. **File City.** The tamer and the partner start in File City (map 0xCC, TWNA01, exit 9). The partner is marked raised (I-16). File City's scripts play the opening and set the starting stats (I-23).

The same naming screen renames the partner later: builtin 0x20 with script value 0xFE = 3 (script 212).

Read `specs/shops.md` §3 first: the routine nodes, `MenuRoutines`, the MAPHEAD lines and `SCRIPT_TEXTBOX_MODE` described there are used here as is.

## 1. The C code

| C | Where | What |
|---|---|---|
| `main` (the mode-0 branch) | `main/main.c:3438–3454` | after the menu: `newGameScene`, movie 1, tamer, partner (`0xFE` ? Gabumon 0x11 : Agumon 3), `setDigimonRaised`, map and chests, `runMapHeadScript(0xCC)`, `addClock`, `stopGameTime` |
| `newGameScene` | `main/main.c:3727–3771` | the intro's own loop |
| `loadNewGameScene`, `unloadNewGameScene`, `tickNewGameJijimon` | `main/new_game.c` | Jijimon, camera, lights |
| `newGameStateMachine` | `shop/script_menu.c:1144–1294` | the questions and the two names; also builtin 0x20's tick (`script_interp.c:511`) |
| `initializeNamingBuffer` | `script_menu.c:1122` | builtin 0x20's start (`script_interp.c:1797`): the flags from script value 0xFE |
| `setupNewGameDialogueBox`, `showNewGameDialogue`, `showNewGameSelection` | `script_menu.c:2658–2700` | Jijimon's lines (MAPHEAD section 0x4D6) |
| `setupNameSelectorBox`, `setupNameDisplayBox` | `script_menu.c:2702–2766` | the two naming boxes (UI boxes 1 and 2) |
| `tickNamingBox`, `renderNamingBox`, `fillNamingMenuStrings`, `updateNamingPreview`, `namingDeleteLast`, `terminateNamingBuffer`, `namingSelection{Left,Right,Up,Down}`, `renderSelectionBox`, `renderNameDisplayBox`, `renderNamingUnderscore` | `script_menu.c:2768–3311` | the naming screen |
| `NAMING_CHAR_PAGES`, `NAMING_CTRL_BOXES`, `NAMING_ROLLOVER_*`, `NAMING_U02` … `NAMING_CHAR_WIDTH` | `script_menu.c:121–545` | the character pages, the button layout, the cursor sprite |
| `initializePartner` | `main/partner_impl.c:450` | already ported (`Care.initialize_partner`, the model part in `EntityHost`) |
| `setDigimonRaised` | `main/script_common.c:3011` | already ported (`GameState`) |
| `playMovie`, `MOV_playMovie` | `main/utils2.c:511`, `mov/mov.c` | the movie, skipped with Start (not movie 3) |

## 2. Behaviour

### 2.1 The boot path (mode 0, `main.c:3438–3454`)

1. **The intro:** `newGameScene()`.
2. **Movie 1:** `finalizeMusic`, `playMovie(1, 1)`, `initializeMusic`.
3. **The tamer:** `initializeTamer`.
4. **The partner:** `initializePartner(readPStat(0xFE) == 0 ? 3 : 0x11)`. Its care values, its first technique (Agumon 0x2E with `learnMove(2)`, Gabumon 0x30 with `learnMove(0x2B)`) and its finisher slot. Lives are 3.
5. **Raised:** `setDigimonRaised(partner)`, trigger 0x200 + id.
6. **The map:** `initializeMap`, `initializeChest`, then `runMapHeadScript(0xCC)`. The default record has exit 9; MAPHEAD section 0xCC loads script 164 (TWNA01) with Jijimon and Tokomon, trigger 54 unset.
7. **The clock:** `addClock`, then `stopGameTime`: time stands still until a script starts it again.
8. **Fade in:** `fadeFromBlack(0x28)`, then the game loop.

The intro's names and script value 0xFE are written into the default record. `initializeDefaultSavegame` ran at the title menu, before the intro.

### 2.2 The intro scene (`newGameScene`, `loadNewGameScene`)

- **Setup:**
  - `checkShopMap(0xDA)`: loads the shop overlay, which holds `newGameStateMachine`. Nothing to port.
  - `initializeNamingBuffer(0)`: flags 0, step 0, empty buffer, `ACTIVE_INSTRUCTION = CALL_ROUTINE`, textbox mode 0.
  - `initializeTextbox`, `fadeFromBlack(0x14)`.
  - Script values: 0xFE = 0, 0xF3 = 0xFF (the questions wait).
- **Jijimon** (model 0x75, entity 2, an NPC slot):
  - **Placement:** at (0x320, 0x96, 0), rotation (0, 0x400, 0), animation 2 (his walk). The animation's root motion walks him in.
  - **Each frame:** a counter counts up to 30000. At 0x23 he turns to (0, 0x71, 0), starts animation 0 (standing) and writes 0xF3 = 0, which starts the questions. His animation ticks every frame.
- **The camera:**
  - **View:** `GsSetProjection(1000)`. `GsSetRefView2`: eye (0, 0, -0x1068), looking at (0, 0, 0), no roll.
  - **Projection centre:** `DRAWING_OFFSET` (0xA0, 0xB9), 65 px below the screen centre.
  - **Background:** black (`GsSortClear(0, 0, 0)`); nothing else is drawn.
- **The lights** (`GsSetFlatLight`, `GsSetAmbient(0x800, 0x800, 0x800)`):

  | Light | Direction | Colour |
  |---|---|---|
  | 0 | (0x1E, 0x64, 0x1E) | (0x40, 0x40, 0x40) |
  | 1 | (-0x1E, 0x64, 0) | (0x28, 0x28, 0x28) |
  | 2 | (0, 0x64, -0x1E) | (0x26, 0x26, 0x26) |

- **The loop**, each frame (`VSync(3)`, the game's 20 Hz):
  1. `pollInputGame`, `processInput`.
  2. `tickTextboxHandling`.
  3. `newGameStateMachine()` if 0xF3 is 0.
  4. The objects (Jijimon, the UI boxes) tick and render.

  When the machine returns 1: `fadeToBlack(0x28)`. The loop ends once the fade is complete; then Jijimon is removed.

### 2.3 The questions (`newGameStateMachine`)

- **The lines:** `showNewGameDialogue(i, next)` shows MAPHEAD section 0x4D6 entry i in box 0, as speaker 0xFE (keep the owner), then mode 1: ✕ goes to `next`.
- **The choices:** `showNewGameSelection(i, next)` shows a two-option selection, then mode 2: `next` + the choice.
- **The box:** `setupNewGameDialogueBox` creates box 0 (flags 0x81, rect (-130, -78, 262, 59)), growing from Jijimon's screen position (entity of type 0x75 in slots 2–9, bone 1). It registers rows 0–3 (`registerTextbox(0, 0, 4, 1, 0)`), double-buffered.
- **Before step 0:**
  - Trigger 49 is set; while it is set, △ in a selection plays the refused sound 11 instead of cancelling (`tickSelectionDialogue`, `script_textbox.c:243`).
  - The tamer's name is emptied (`MAIN_D_80134600[7]`, an empty string): the choice lines' speaker `{tamer_name}` shows nothing.
  - `DRAW_STRING2_IS_FIXED_WIDTH` = 0.

| Step | Does | Text (0x4D6) |
|---|---|---|
| 0 | set trigger 49, empty tamer name, box 0; line 0x10 → 2 | "I'm Jijimon. Tell me about yourself." |
| 2 | line 0x11 → 3 | "Do you have a Digivice?" |
| 3 | choice 0x12 → 4 (Yes) / 5 (No) | Yes / No |
| 4 | line 0x13 → 6 | "I see." |
| 5 | line 0x16 → 10 | "I see." |
| 6 | line 0x14 → 7 | "Which do you like better, day or night?" |
| 7 | choice 0x15 → 8 (Day) / 9 (Night) | Day / Night |
| 10 | line 0x17 → 11 | "Do you have friends?" |
| 11 | choice 0x18 → 8 (Yes) / 9 (No) | Yes / No |
| 8 | value 0xFE = 0 (Agumon) → 0x11 | |
| 9 | value 0xFE = 1 (Gabumon) → 0x11 | |
| 0x11 | line 0x19 → 0x12 | "Alright." |
| 0x12 | line 0x1A → 0x13 | "What's your name?" |
| 0x13 | close box 0 → 0x14 | |
| 0x14 | input repeat ↑↓←→ (0xF000), the naming boxes, fixed-width text on → 1 (the naming box's ○ OK sets 0x15) | |
| 0x15 | repeat off; the buffer becomes the tamer's name (flag bit 0 clear) or the partner's (set); close boxes 1 and 2; fixed width off → 0x16 | |
| 0x16 | flag bit 1 (renaming): wait for box 1 to close, then **return 1**. Else box 0 again; the tamer: line 0x1B → 0x17; the partner: line 0x1E → 0x1B | "*name*, right?" |
| 0x17 | choice 0x1C → 0x18 (Yes) / 0x19 (No) | Yes / No |
| 0x18 | line 0x1D → 0x1A | "What's your Digimon's name?" |
| 0x19 | → 0x13 (name again) | |
| 0x1A | flag bit 0 set (the partner), buffer emptied → 0x13 | |
| 0x1B | choice 0x1C → 0x1C (Yes) / 0x1D (No) | Yes / No |
| 0x1C | line 0x1F → 0x1E | "Good Name." |
| 0x1D | → 0x13 | |
| 0x1E | line 0x20 → 0x1F | "That's all the questions I have. See ya later!" |
| 0x1F | close box 0, unset trigger 49, **return 1** | |

- **The answers:** only the second question decides; "Do you have a Digivice?" picks which one is asked. Yes leads to day / night (Day: Agumon, Night: Gabumon). No leads to "Do you have friends?" (Yes: Agumon, No: Gabumon).
- **The partner's name:** the buffer starts empty, not with the Digimon's name.
- **The partner's Digimon:** it isn't known yet while it is named. Its line 0x1E shows `{partner_name}`, the name just typed.
- **Return values:** every other step returns 0. Step 1 is the waiting step: the text box's tick moves it on.

### 2.4 The naming screen (boxes 1 and 2)

- **The two boxes.** Both grow from Jijimon's screen position, with flags 0xC1 (renaming: 0xE1).
  - **Box 1, the selector:** rect (-145, -91, 290, 138), text-area rows 1–7, double-buffered (`registerTextbox(1, 1, 7, 1, 0)`). It opens on page 0 (`SHOP_AMOUNT`), cursor 0.
  - **Box 2, the name:** rect (-145, 60, 149, 42), text-area row 0, single (`registerTextbox(2, 0, 1, 0, 0)`). The letter cursor starts at `strlen(buffer) / 2`, at most 5.
  - **The text rows:**
    - row 1 holds `\x01\x07` "Name" `\x01\x01` "BackOK";
    - rows 2–4 hold the left half's 9 character rows, 3 per text row (15 glyphs);
    - rows 5–7 hold the right half's.
- **The characters** (`NAMING_CHAR_PAGES`, US). One page in two halves of 9 rows of 5, full-width Shift-JIS; US has no page buttons, so only page 0 is used.
  - Left: `ＡＢＣＤＥ` `ＦＧＨＩＪ` `ＫＬＭＮＯ` `ＰＱＲＳＴ` `ＵＶＷＸＹ` `Ｚ　　　　`, then three rows of full-width spaces.
  - Right: `ａｂｃｄｅ` … `ｚ　　　　` `０１２３４` `５６７８９`, then one row of spaces.
  - JP and EU have more pages and the hiragana / katakana tables.
- **The cursor**, `NAMING_SELECTOR`:
  - On a character it is the cell index: row × 5 + column. Rows 0–8 are the left half, 9–17 the right.
  - On a button it is 0x8000 | the button. US buttons: 0 Back, 1 OK.
- **Input** (`tickNamingBox`). It runs only after box 1's page flip, with both boxes open and `isXPressedAfterDialogue`.
  - **□:** clears the whole name. Sound 3.
  - **✕ on a character:** writes it at the letter cursor and ends the name there. The cursor moves on, up to the 6th letter.
    - A full-width space as the first letter is refused (sound 11).
    - When the 6th letter is written while the cursor is already on it, the cursor jumps to OK.
    - Sound 3.
  - **✕ on Back:** deletes the last letter (`namingDeleteLast`).
  - **✕ on OK:** an empty name is refused (sound 11). Otherwise trailing full-width spaces are cut (`terminateNamingBuffer`), sound 3, step 0x15.
  - **○:** jumps to the first button (Back). Sound 2.
  - **△:** deletes the last letter.
    - Sound 3, and only when the name isn't empty.
    - **Quirk kept (US):** the cursor moves back first, then the name is ended there. The cursor stays on the 6th letter once it is written, so on a full name one △ removes both the 6th and the 5th letters.
  - **Start:** jumps to OK. Sound 2.
  - **Arrows** (sound 2, repeating):
    - **↑ / ↓:** wrap within the half (rows 0–8, or 9–17, the empty rows included). On the buttons they cycle Back ↔ OK.
    - **← / →:** move along the row; past an edge the cursor crosses to the other half. From the left half's first column, ← goes to Back (`NAMING_ROLLOVER_CHARS`: 0x8000 for every row), as does → from the right half's last column.
    - **From a button:** ← goes to cell 0x19 + 0x31 = 74 (row 14, column 4: the right half's 6th row); → goes to cell 0x19 = 25 (row 5, column 0: the left half's 6th row). From `NAMING_ROLLOVER_CTRL`.
- **Box 1's drawing** (`renderNamingBox`, from the box's final position (bx, by)):
  - **Labels**, from text row 1 (`NAMING_CTRL_BOXES`, US: x, y, width): "Name" (0x0E, 6, 0x30), "Back" (0x0E, 0x5A, 0x30), "OK" (0x0E, 0x76, 0x18).
  - **Quirk kept (US):** a 4th label call reads past the 3-entry table (y offset and width 0x8000) and draws nothing. On JP / EU it greys OK while the name is empty.
  - **Characters:** each drawn as a 12 × 12 cell. The left half at x = bx + 0x4E + column × 18, y = by + 6 + row × 14; the right half 0x70 further right.
- **The cursor sprite** (`renderSelectionBox`):
  - **The sprite:** 8 pieces of the UI texture page (tpage at (896, 448), CLUT (256, 508)), 4 × 4 corners and stretched edges (`NAMING_U02`, `U13`, `V01`, `V23`, `Y`, `HEIGHT`), at OT layer 5.
  - **On a character:** a frame 20 wide at (bx + 0x4A + column × 18, by + 2 + row × 14). The right half's x base is 0xBA. X offsets `NAMING_CTRL_X`, widths `NAMING_CTRL_WIDTH`.
  - **On a button:** a frame 0x31 wide at the label's position − 4 (`NAMING_CHAR_X`, `NAMING_CHAR_WIDTH`; the decomp's names are swapped).
- **Box 2's drawing** (`renderNameDisplayBox`, `updateNamingPreview`):
  - **The text:** `updateNamingPreview` writes the prompt, the name and spaces up to 6 letters into text row 0 (`drawString2`, fixed width: 12 px a letter). **US:** the prompt (`MAIN_D_801345F4`) is empty.
  - **The name:** the row's first 0x48 px (tamer) or 0x54 px (partner) are drawn at (x + 7, y + 6).
  - **Quirk kept (US):** six more 12-px cells from u = 0x48 / 0x54 are drawn at (x + 0x3A + i × 14, y + 0x14). On JP they are the name after the prompt; on US they show the row's empty end.
  - **The letter cursor:** a 3-line underscore 12 wide at (cursor × 12 + 4, 0x10) from the box, in the colour words 0x020202 / 0x10C0C0 / 0x020202 (`drawLine2P`, `renderNamingUnderscore`; the middle line is yellow, r = g = 0xC0, b = 0x10).
- **The names** are up to 6 full-width letters (12 bytes and the terminator). Elsewhere they are drawn full width (`specs/text.md` §2.6).

### 2.5 Builtin 0x20: renaming (`initializeNamingBuffer(readPStat(0xFE))`)

- **Flags** (script value 0xFE): bit 1 renames, bit 0 picks the partner.
- **Without bit 1** (values 0, 1): the state is reset and the routine runs `newGameStateMachine` from step 0, i.e. the whole intro dialogue. Only the debug script 209 does that (values 2, 3 there). **Quirk kept:** it needs Jijimon among the map's entities for the boxes' origin; without him the C reads an uninitialised position.
- **With bit 1:**
  - `closeBox(0)`, step 0x14. The buffer starts with the current name (tamer or partner).
  - The tick is `newGameStateMachine`: the naming boxes, then step 0x16. That step waits for box 1 to close, then ends the routine (`ACTIVE_INSTRUCTION = 0`).
  - No dialogue and no Jijimon line. The boxes' origin is Jijimon's position if he is on the map, else an uninitialised position (the port uses the screen centre).
- **Use:** script 212 (value 3: rename the partner, after "I want a new name").

### 2.6 Movie 1 (`MOV_playMovie`)

- **The movie:** `OP2.STR`, 320 × 176 at y = 32 of the 240-line screen, with its XA audio. The asset porter writes `movies/OP2/movie.ogv` (`asset_porter/specs/movies.md`).
- **Skipping:** Start ends it (every movie but 3, `mov.c:265`).
- **Around it:** the music is stopped before (`finalizeMusic`) and restarted after.

## 3. Godot design

### 3.1 Scenes

- **`Game`** (`scenes/game.tscn`, `scripts/game/game.gd`): main.c's loop as a scene that swaps its child.
  - It becomes the project's main scene. `scenes/field/field.tscn` still runs on its own (F6) with its debug `start_map`, as today.
  - The boot modes (`GameState.state.boot_mode`):
    - 0, a new game: `GameState.new_game()`, then `NewGameScene`, then `MoviePlayer` (movie 1), then the field (§3.3).
    - 1 and 2 come with 4e-2 (the title menu, loading).
  - **Debug:** `DW_SKIP_INTRO=1` skips the intro and the movie, with value 0xFE = 0 and the default names.
- **`NewGameScene`** (`scenes/new_game/new_game.tscn`, `scripts/new_game/new_game_scene.gd`): `newGameScene` and `new_game.c`.
  - **The staging** is exported properties defaulting to the C's values (§2.2), so a mod can restage the intro by overriding the scene: the guide's Digimon (default `dw1:jijimon`), its position and rotations, the turn frame, the camera, the lights and ambient, the background colour.
  - **The guide:** a `digimon.tscn` model with a `PsxAnimator`; its root motion moves it, as the field's NPCs do.
  - **The HUD:** its own text area, `UIBoxes`, `ScriptContext` and `TextBoxes`, made as `ScriptHost.start` makes them, with `entity_screen_position` returning the guide's bone-1 screen position. A `ScriptRoutines` node holds a `NamingRoutines`.
  - **The frame order:** pad, `tick_textbox_handling`, the routine's tick while value 0xF3 is 0, the guide, the UI boxes. Then the fade.
  - **The end:** the scene emits `finished` when the routine has returned 1 and the fade to black is complete.
- **`MoviePlayer`** (`scenes/movie/movie_player.tscn`, `scripts/movie/movie_player.gd`):
  - A `VideoStreamPlayer` on a black 320 × 240 screen, the video at (0, 32) and 320 × 176.
  - `play(id, skippable)` loads `movies/<OP1|OP2|ED2|EDR>/movie.ogv` through `Content`, and emits `finished` at the end, or on Start if skippable.
  - **No `.ogv`** (no ffmpeg when porting): it emits `finished` on the next frame and prints a note.
  - The four movies' files and "can be skipped" come from the data (§3.4).

### 3.2 Logic

- **`NamingRoutines`** (`scripts/script/naming_routines.gd`, `scenes/script/naming_routines.tscn`; extends `MenuRoutines`). It runs builtin 0x20 and the intro:
  - `start(0x20)`: `initializeNamingBuffer(value 0xFE)`.
  - `tick(0x20)`: `newGameStateMachine`; at its return 1 the routine ends.
  - `new_game_tick() -> bool`: the same machine for `NewGameScene` (true when done).
  - **State:** the naming buffer as an array of up to 6 full-width codes, the flags, the letter cursor.
  - **The names** are stored in `GameState` as text: full-width letters become their ASCII form (Ａ → A, ０ → 0, full-width space → space). They are written back full width when drawn, as today's names are (`PsxFont.to_bytes(name, true)`). Renaming starts the buffer from that text, encoded full width.
  - **The partner choice:** steps 8 / 9 write value 0xFE, as the C does. The boot reads which partner that is from the data (§3.4), not from the C's ids.
- **`NamingBox`** (`scripts/ui/naming_box.gd`): boxes 1 and 2.
  - **What it does:** `tickNamingBox` and the two renders, `fillNamingMenuStrings`, `updateNamingPreview`, the cursor moves, `namingDeleteLast`, `terminateNamingBuffer`, the cursor sprite and the underscore.
  - **Where:** a `RefCounted` drawn through the UI boxes' render callables, like `TrainingSlotsBox`.
  - **The characters** come from the data (§3.4); the layout constants are the C's US tables.
- **`TextBoxes`:** the selection's △ refusal while trigger 49 is set is already in `tick_selection_dialogue`? To check while coding; if not, it is added there (it is the C's rule for every selection).

### 3.3 The field after the intro (`Game`)

- **The partner:** `GameState.state.partner.digimon` = the data's partner for value 0xFE.
- **The names:** the tamer's and the partner's, already written by the routine.
- **Raised:** `GameState.set_digimon_raised(partner)` (fixes I-16).
- **The field:** `field.tscn` is instanced with `start_map` / `start_spawn` from the record's screen and exit (TWNA01, 9), through `MapSession.begin` (`runMapHeadScript`).
  - `CareHost` already runs `Care.initialize_partner()` on a new game (care values, techniques, lives).
  - `Field` gets a property `boot := false` (true from `Game`). With it, the field uses the record's map instead of its debug `start_map`, and doesn't apply the debug overrides.
- **The clock:** stopped after the start (`stopGameTime`), as in the C: `ClockHost` gets a `stop_game_time()` if it has none.
- **Fade in:** `fadeFromBlack(0x28)`.
- **The starting stats (I-23):** they come from File City's scripts (script 193, section 55) as the game plays on. They are not set by the boot.

### 3.4 Data porter (`systems` group, `data_porter/specs/systems.md`)

- **`systems/new_game`** (`main.c:3445–3449`, `partner_impl.c:500–508`, `new_game.c`):
  - `partners`: the partner for each value of 0xFE (0: `dw1:agumon`, 1: `dw1:gabumon`).
  - `guide`: `dw1:jijimon`, the Digimon whose screen position the boxes grow from (the C's type 0x75 test).
  - `start_map`: `dw1:twna01` (0xCC). `start_exit`: 9 (the default record's; the record keeps its own copy).
  - `movie`: 1.
  - `GameState.new_game` keeps reading its partner argument; `Game` passes the data's.
- **`systems/naming`** (`NAMING_CHAR_PAGES`, `script_menu.c:121–352`, per language):
  - The pages, each two halves of 9 rows of 5 characters, as text.
  - The US list has one page; JP and EU are listed with theirs even though only US is drawn today.
  - **Check:** every US row is 5 full-width characters.
- **`systems/movies`** (`MOV_MOVIES[4]`, `mov/mov.c:46`): file, last frame, skippable (all but 3).

## 4. Tests (`tests/test_new_game.gd`)

- **The questions:** the machine driven with a fake pad through the six answer paths. Value 0xFE ends 0 / 1 as §2.3. The line indices and the steps are in the C's order.
- **Trigger 49:** set during the questions, unset at the end. △ in a selection is refused while it is set.
- **The naming:**
  - typing, the 6-letter cap and the jump to OK;
  - □ clears the name;
  - △ / Back with the US quirk;
  - the refused leading space and empty OK;
  - trailing spaces cut;
  - every cursor move, including the half crossings, the wraps and the button rollovers (25 / 74);
  - Start / ○ jumps.
- **The names:** the full-width ↔ ASCII conversion, and a name drawn in a dialogue line (`{tamer_name}`).
- **"No" to the name:** returns to the naming with the name kept (the buffer isn't cleared for the tamer); the partner's naming starts empty.
- **Builtin 0x20 with value 3:** starts at the naming with the partner's name, ends after box 1 closes, and changes only the partner's name.
- **The boot:**
  - `Game` with `DW_SKIP_INTRO` reaches the field on TWNA01 at exit 9, with Agumon raised (trigger 0x203) and its first technique;
  - value 0xFE = 1 gives Gabumon (trigger 0x211).
- **The data:** the porter's tests for `systems/new_game`, `naming`, `movies`.
- **The rest:** the existing suites pass, and the scan scenes still start (they instance `field.tscn` directly).

## 5. VERIFY ("New game")

1. **Start:** run the project (F5). Jijimon walks in from the right on black, turns to the camera, and the dialogue opens from him.
2. **The questions:** answer them. The choice lines show no speaker name, and △ doesn't cancel a choice (refused sound).
3. **The naming screen:**
   - **The layout:** the "Name" title; Back and OK on the left; A–Z left and a–z / 0–9 right.
   - **Typing and moving:** the frame cursor moves and wraps; ○ jumps to Back, Start to OK; □ clears.
   - **The limits:** a 7th letter isn't accepted, and a leading space is refused.
4. **The confirmation:** "*name*, right?" No goes back to the naming; Yes asks the Digimon's name.
5. **The end:** after "That's all the questions…" the screen fades. The opening movie plays (Start skips it), then File City.
6. **The game:** the partner is Agumon for Day / friends Yes, Gabumon for Night / friends No. The Player screen's chart shows it (I-16). Its stats aren't 0 once File City's opening has run (I-23).
7. **Renaming:** the partner renaming (script 212, when the game offers it) opens the naming screen with the current name.

## 6. Open points

- **The main scene** changes to `scenes/game.tscn`. Running `field.tscn` directly keeps today's debug start.
- **I-23** depends on File City's opening script reaching section 55 of script 193. If an opcode on the way isn't ported yet, the help line will name it; that would be fixed in the interpreter, not by setting stats in the boot.
- **Fades and music:** the fade colour and the intro's music. `newGameScene` plays none; the title menu's music is stopped by `finalizeMusic` only after the intro. To compare with the original.
- **The guide's walk-in** relies on animation 2's root motion. If the porter's animation has none, Jijimon would stand off screen until frame 0x23. To check against the original while coding.

## As built (4e-1, 2026-10-27)

- **The code:**
  - `NamingRoutines` (`scripts/script/naming_routines.gd`, `scenes/script/naming_routines.tscn`): builtin 0x20 and the questions. It is in the field's routines too, so script 212's rename works.
  - `NamingBox` (`scripts/ui/naming_box.gd`): boxes 1 and 2.
  - `NewGameScene` (`scripts/new_game/new_game_scene.gd`, `scenes/new_game/new_game.tscn`).
  - `MoviePlayer` (`scripts/movie/movie_player.gd`, `scenes/movie/movie_player.tscn`).
  - `Game` (`scripts/game/game.gd`, `scenes/game.tscn`), now the project's main scene.
  - `Field.boot`.
- **The interpreter:**
  - It now resets a waiting builtin's step and textbox mode **before** the routine's `start`, so 0x20's own setup (step 0x14 for a rename) stands. In the C only the builtins in the reset list get it (`script_interp.c:1661–1680`); 0x20's `initializeNamingBuffer` sets its own step.
  - `CALL_ROUTINE 0x37` (`setLoopCountToOne(value 0xFE)`) is ported: File City's opening uses it.
- **Shared code:** `flipTextboxPage` moved from `ItemMenu.flip_page` to `TextBoxes.flip_textbox_page`; `ItemMenu` calls it.
- **New hooks:**
  - **The guide's position:** `NamingRoutines.guide_screen_position(type)`. The field's `ScriptHost` gives the screen position of the last NPC of that type; the intro gives its guide's.
  - **Moving without a map:** `FieldDigimon.moves_without_map` lets the intro's guide follow its walk's root motion.
- **The data:** `systems/new_game`, `systems/naming`, `systems/movies` (`data_porter/specs/systems.md`).
- **The names:** typed names are kept in `GameState` as ASCII where they are full-width Latin (`NamingRoutines.from_full_width` / `to_full_width`).
- **The boot** (`Game._new_game`):
  - `GameState.new_game()`, the intro, `Sound.music.stop_bgm()`, movie 1.
  - `GameState.start_new_game_partner`: the partner for value 0xFE, marked raised.
  - The field with `boot`: it starts on the record's screen and exit, stops the clock for a new game and fades in over 0x28 frames. The debug start overrides (`DW_START_MAP`, `DW_START_HOUR`) are off.
- **I-16 and I-23 are fixed.** The partner is marked raised at the boot. File City's opening sets the stats as in the original: `tests/new_game_scan.tscn` sees Agumon at 80 / 60 / 70 / 70, 800 / 600 at frame 863, with no unported instruction on the way.
- **Tests:**
  - `tests/test_new_game.gd` (71 checks): the four answer paths, trigger 49, the naming input and quirks, the cursor moves, "No" to the name, the rename, the names' conversion, the boot's partner.
  - `tests/new_game_scan.tscn`: the boot in the real scenes; `NEW_GAME_INTRO=1` plays the intro through too (it caught the intro's text boxes having no script files, so no lines: fixed the same day).
  - `data_porter/tests/test_systems.py`: the three tables.
- **Open:**
  - Checked in the game 2026-10-27: the intro, the questions, the naming and the boot look right, except the naming screen's letter cursor frame (ISSUES.md I-34).
  - The title menu (4e-2) comes before the intro; until then the game boots straight into it.
