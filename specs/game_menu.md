# The △ menu (game menu)

Status (2026-10-25): coded, step 5e-1 (`specs/script.md` §3.1, `PLANS.md` 5e): `scenes/ui/game_menu.tscn` (`scripts/ui/game_menu.gd`), `Systems/MenuHost`, the tamer's states 1 / 6 / 9 / 13, the partner's 4 / 15, data porter `raise_data.praise_pat_low`; `tests/test_game_menu.gd`; VERIFY "The △ menu".

The field's own menu: △ opens a box over the field with 6 icons (7 with a fishing rod): Items, Digimon, Player, Praise, Scold, Sleep, Fishing. This step ports the menu and the three options that act on the field (Praise, Scold, Sleep). The others open screens that come with their own steps (§6). It's the first menu built as a scene (`specs/scenes.md` §4.3).

## 1. The C code

| C (US) | What |
|---|---|
| `tamerTickWalkingState` (`tamer.c:515–538`) | △ opens the menu |
| `addGameMenu` (`game_menu.c:1306`), `tickTriangleMenu` (`:1328`), `closeTriangleMenu` (`:1403`), `closeUIBoxIfOpen` (`:1411`) | the menu object and its box |
| `createMenuBox` (`:1684`) | an animated UI box grown from the tamer's screen position |
| `renderGameMenu` (`:1424`), `renderDateDigits` (US `:1540`), `renderTriangleCursor` (`:1582`), `renderSeparatorLines` (`:4262`), `renderRectPolyFT4` (`:4276`) | drawing |
| `tickGameMenu` (`:1627`) | the box's tick: cursor, ✕, △ |
| `handleGameMenuSelection` (`:2168`), `setSleepDisabled` (`:2223`) | the options |
| `partnerTickPraiseScold` (`partner.c:368`), `tamerTickPraiseScold` (`tamer.c:1625`), `handlePraiseScold` (`partner_impl.c:1113`) | praise and scold |
| `getFishingAvailability` (`fish.c:59`) | whether the fishing icon shows |
| `IS_IN_MENU` (`main.c:3222`) and its readers | what stops while the menu is open |
| Data: `MENU_OPTIONS[8]`, `GAME_MENU_TEXT_SPRITES[8]`, `GAME_MENU_LINES`, `SELECTION_CURSOR_*` (`game_menu.c:389–493`), `STR_YEAR_DAY` (`text/main/game_menu.yaml`) | positions, texture rects |

## 2. Behaviour

### 2.1 Opening (`tamer.c:515`)

In the tamer's walking state, △ pressed this frame (`isKeyDown(0x10)`) opens the menu when:
- no script runs (`IS_SCRIPT_PAUSED == 1`);
- no fade is protected (`FADE_PROTECTION == 0`, US and later);
- UI box 0 is free (`state != 1` and `frame == 0`).

Then, in this order:
1. `addGameMenu`:
   - selection = 1 (Items); option count 7;
   - with a fishing rod (`getFishingAvailability != 0`): count 8, selection 7 (Fishing), and the Fishing icon disabled when availability is 1 (no rod or no food);
   - Sleep (option 6) enabled only while the partner is sleepy (`condition & 1`);
   - the menu object starts (state 0).
2. The tamer goes to state 1, which turns into state 6 (idle: animation 0) on his next tick.
3. His animation 0; the camera stops following him; `STORED_TAMER_POS` = his position (read by the inventory, §6).
4. `IS_IN_MENU = 1`; game time stops (`stopGameTime`); the partner's animation 0 (`setPartnerIdling`).

### 2.2 The menu object (`tickTriangleMenu`)

A state machine (`TRIANGLE_MENU_STATE`), ticked with the objects:
- **0 (opening):**
  - `createMenuBox(0, -0x42, -0x50, 0x84, h, 2)`, h = 0x95 with fishing, else 0x6E: an animated box, colour 1, features 2 (`UIBoxes.FEATURE_HALF_FILL`), growing from a 10 × 10 square at the tamer's screen position (`getEntityScreenPos(tamer, 1)`). `createMenuBox` does nothing while the box is open (state 1) or still closing (frame ≠ 0).
  - Once box 0 reaches frame 4: state −1 (open: the box's tick takes over).
  - Every frame of state 0: clear the text area's 24 × 12 at (0, 232) and draw `STR_YEAR_DAY` ("YearDay") at (0, 232).
- **−1 (open):** nothing; `tickGameMenu` runs as box 0's tick.
- **2 (Items):** close box 0; once closed, the inventory (`addInventoryUI`, §6).
- **3 (Digimon), 5 (Player):** close box 0; once closed, open box 1 (−0x96, −0x59, 300 × 0xBE) with its screen (§6).
- **4, 6 (back from those screens):** the tamer and partner on screen again, close box 1; once closed, state 0 (the menu reopens).
- **1:** close box 0 and remove the object (not used by the US code paths above).

`closeUIBoxIfOpen(id)`: if the box is open (`frame ≥ 5`, state 1), `removeAnimatedUIBox(id, NULL)`: it shrinks back to where it grew from.

`closeTriangleMenu`: close box 1, the inventory's boxes, box 0; remove the object.

### 2.3 The box's tick (`tickGameMenu`)

Every frame while the box is open:
1. If the partner became sleepy (`condition & 1`), Sleep is enabled (it never gets disabled here; `setSleepDisabled(1)` comes from `handleSleeping`).
2. **Cursor** on buttons pressed this frame (`polled & ~polled_previous`), the options in rows of 3 (`count` = 7 or 8, entries 1 to count − 1):
   - **up** (0x1000): `sel -= 3`; if `sel ≤ 0`: `sel += ((count + 1) / 3) * 3`; then if `sel ≥ count`: `sel -= 3`;
   - **down** (0x4000): `sel += 3`; if `sel ≥ count`: `sel -= ((count + 1) / 3) * 3`; then if `sel ≤ 0`: `sel += 3`;
   - **left** (0x8000): `sel -= 1`; if `sel ≤ 0`: `sel = count − 1`;
   - **right** (0x2000): `sel += 1`; if `sel ≥ count`: `sel = 1`;
   - only one direction per frame (up, down, left, right in that order); a change plays sound (0, 2).
3. Only in state −1:
   - **✕** (`isKeyDown(CONFIRM)`): sound (0, 4) if the option is disabled, else (0, 3); then `handleGameMenuSelection(sel)`.
   - **△** (`isKeyDown(CANCEL)`) while box 0 is open (state 1) or closed (frame 0): sound (0, 4), `closeTriangleMenu`, tamer state 0, the camera follows him, `IS_IN_MENU = 0`, game time runs (`startGameTime`).

Worked example, 7 options (no fishing), the grid `1 2 3 / 4 5 6`: up from 1 → 1 − 3 = −2 → +6 = 4; down from 5 → 8 ≥ 7 → 8 − 6 = 2; left from 1 → 6; right from 6 → 1. With 8 options (`7` is above the grid): up from 1 → −2 + 9 = 7; up from 2 → −1 + 9 = 8 ≥ 8 → 5.

### 2.4 The options (`handleGameMenuSelection`)

| Entry | Option | ✕ does |
|---|---|---|
| 1 | Items | if enabled: menu state 2, `drawInventoryText` (§6) |
| 2 | Digimon | menu state 3 (§6) |
| 3 | Player | menu state 5 (§6) |
| 4 | Praise | if enabled: `closeTriangleMenu`, partner state 15, `IS_IN_MENU = 0`, game time runs |
| 5 | Scold | if enabled: `closeTriangleMenu`, partner state 4, `IS_IN_MENU = 0`, game time runs |
| 6 | Sleep | if enabled: `closeTriangleMenu`, partner state 3, `IS_IN_MENU = 0`, game time runs |
| 7 | Fishing | if enabled: `closeTriangleMenu`, the camera follows, `initializeFishing`, tamer state 11, `IS_IN_MENU = 0` (game time stays stopped: fishing runs its own) |

Only Sleep and Fishing are ever disabled (`MENU_OPTIONS[n].disabled`); the others start enabled and nothing changes them. A disabled option plays the refusal sound and does nothing.

The tamer stays in state 6 after Praise / Scold / Sleep: the partner's scene sets him (§2.5, `specs/care.md`).

### 2.5 Praise and scold

**Partner, states 15 (praise) and 4 (scold)** (`partnerTickPraiseScold`, sub-state):
- **0:** the camera stops following; `tickPartnerWaypoints`; unless already close to the tamer (`getPartnerTamerCloseness() == 2`), animation 2 (walk). Sub-state 1.
- **1:** each frame the tamer looks at the partner and the partner at the tamer. Once close (2):
  - partner animation 0;
  - praise: sound (0, 14), tamer state 13; scold: tamer state 9;
  - sub-state 2.
- **2:** once the tamer's animation is 0 again (his praise / scold animation is over), `handlePraiseScold(state)` (`Care.handle_praise_scold`), sub-state 3.
- **3:** the partner's animation loops once (loop count 255 → 1); when it ends: partner state 1, tamer state 0, the camera follows, `handleSpecialEvolutions(3, partner)` (evolution: not ported, §7).

The US build calls `handlePraiseScold()` without its argument, but `$a0` still holds the partner state on that path (`partnerTickPraiseScold.s`: `$a0` is untouched between the entry and the call), so the port passes it (`specs/care.md` §6).

**Tamer, states 13 (praise) and 9 (scold)** (`tamerTickPraiseScold`, sub-state):
- **0:**
  - praise: tamer animation 0x26 (pat low) if the partner is below Champion (`level < 4`) or is Mamemon, MetalMamemon or Digitamamon (ids 0x0D, 0x1B, 0x38), else 0x27 (pat high); partner animation 0x0B;
  - scold: sound (0, 13); tamer animation 7; partner animation 0x19 if `ITEM_SCOLD_FLAG == 1` (right after a refused item or an accident), else 0x0C;
  - sub-state 1.
- **1:** when the tamer's animation ends: tamer state 6 (idle: animation 0, which lets the partner's sub-state 2 go on).

**The low pat is data, not ids** (`specs/content.md`): the data porter adds `praise_pat_low` to `raise_data` (true for levels Fresh to Rookie and for the three types above). The port reads only the property.

### 2.6 While the menu is open (`IS_IN_MENU == 1`)

- **Partner** (`partnerTickOverworld`, `partner.c:215`): only its animation runs, none of its state code.
- **NPCs** (`overworld.c:1232`): their tick returns at once.
- **Condition bubbles** (`bubble.c:482`, `:619`): neither ticked nor drawn.
- **Butterfly** (`butterfly.c:98`, `:113`): not drawn (the butterfly isn't ported).
- **Game time** is stopped (2.1), so the clock HUD and the status bars slide away.

### 2.7 Drawing (`renderGameMenu`, box 0's render function, ordering-table layers 5–6)

All sprites come from `ETCDAT/FI_INFO.TIM` (asset porter `etctim/04_fi_info`, the clock's texture): page (896, 256) 4bpp, so a sprite's `(texX, texY + 0xC0)` is image pixel `(texX, texY)`. Palette `p<n>` = CLUT row 496 + n. Screen coordinates are relative to the centre (160, 120).

- `yOffset` = −0x28 with 7 options (the fishing row on top is left out), 0 with 8.
- **Separator lines** (`GAME_MENU_LINES`, the first 2): (−62, −59)–(62, −59) colour (2, 2, 2) and (−63, −58)–(63, −58) colour (0x90, 0xD9, 0xFA), layer 5, not moved by `yOffset`.
- **"Year" and "Day"** (US): the text area's (0, 0xE7, 0x24 × 0xC) at (−0x3C, −0x49) and (0x24, 0xE7, 0x1C × 0xC) at (6, −0x49), colour 0, layer 6.
- **The date** (US `renderDateDigits`), layer 5, palette p12 (`0x7F10`): `DAY + 1` (2 digits) and `YEAR + 1` (3 digits) without leading zeros, most significant first:
  - day digit j at (0x25 + 9j, −0x4A), year digit j at (−0x16 + 9j, −0x4A), each 7 × 12;
  - the digit's sprite: 0 at u 0x78, v 0x34; 1–4 at u `(d − 1)·8 + 0x60`, v 0x28; 5–9 at u `(d − 5)·8 + 0x50`, v 0x34; drawn from u + 1.
- **Each option** 1 to count − 1 (`MENU_OPTIONS[i]`):
  - icon: `width × height` at `(x − 0x42, y − 0x50 + yOffset)`, sprite `(texX + h, texY)` with `h` = 0x14 on the selected option during frames where `PLAYTIME_FRAMES % 10 < 5` (blink), else 0; palette p`clutY` (12 or 13);
  - label (`GAME_MENU_TEXT_SPRITES[i]`): `width × height` at `(x − 0x42, y − 0x50 + yOffset)`, sprite `(texX, texY − 1)`, palette p13 (`0x7F50`);
  - both at layer 6, darkened (colour 0x32 instead of 0x80) when disabled.
- **Cursor** (`renderTriangleCursor`): 8 quads around the selected icon at base `(x − 0x46, y − 0x53 + yOffset)`, layer 5, palette p12 (`0x7F10`... `GetClut(0x100, 0x1FC)`), from the `SELECTION_CURSOR_*` tables (4 corners 4 × 4, the top / bottom edges 0x18 × 4, the side edges 4 × 0x16; UVs in u 0–0xC, v 0xFB–0xFF of the page: image rows 59–63). Some corners have flipped UVs (u0 > u1). The art (`04_fi_info.p12`) is the rounded corner at u 0–3, the edge band (black, yellow, black) at 4–7 and the side bar at 8–11, in rows v 0xFC–0xFF (0xFB is an empty row).
  - **Taken literally the table doesn't close the frame.** Simulated with the PSX's polygon sampling (texels from u0 up to u1 − 1, or u0 down to u1 + 1 when mirrored), the non-mirrored quads show rows 0xFB–0xFE, so the top corners lose their last row. The 22-px sides show the empty row for their first 5 px, so there's a 2-px gap under the top corners, and the bottom edge lands one row off the mirrored bottom corners. Shifting the rows by one breaks the bottom instead.
  - **The port draws the pieces as the art fits together, in the table's 29 × 26 bounds** (`GameMenu.CURSOR_PIECES`): corners at (0, 0), (25, 0), (0, 22), (25, 22), mirrored on the right and at the bottom; the edge bands between them (the bottom one mirrored); the sides from y 4 to 21 (the right one mirrored); edges and sides first, the corners over them (the C's AddPrims into one ordering-table entry are drawn last first).
  - Reported twice (2026-10-25: the first literal versions left gaps, then showed the side bars under the corners). To compare with a capture of the real game: if the original shows gaps, the literal version is in this file's history.

| Option | `MENU_OPTIONS` x, y, clutY, w × h, tex | Label x, y, w × h, tex |
|---|---|---|
| 1 Items | 0x14, 0x47, 12, 20 × 20, (0x00, 0x00) | 0x13, 0x60, 0x18 × 7, (0x50, 0x14) |
| 2 Digimon | 0x38, 0x47, 13, 20 × 20, (0x28, 0x00) | 0x35, 0x60, 0x1C × 7, (0x50, 0x1B) |
| 3 Player | 0x5B, 0x47, 12, 20 × 20, (0x00, 0x14) | 0x5A, 0x60, 0x1C × 7, (0x50, 0x22) |
| 4 Praise | 0x14, 0x6F, 13, 20 × 20, (0x28, 0x14) | 0x15, 0x88, 0x14 × 7, (0x6C, 0x14) |
| 5 Scold | 0x38, 0x6F, 13, 20 × 20, (0x00, 0x28) | 0x39, 0x88, 0x14 × 7, (0x6C, 0x1B) |
| 6 Sleep | 0x5B, 0x6F, 13, 20 × 20, (0x28, 0x28) | 0x60, 0x88, 0x14 × 7, (0x6C, 0x22) |
| 7 Fishing | 0x14, 0x1F, 13, 20 × 19, (0x50, 0x00) | 0x17, 0x38, 0x10 × 7, (0x50, 0x29) |

Checked against the texture (`04_fi_info.p13.png`): the label column at u 0x50 reads ITEM, DIGIMON, PLAYER, FISH and the one at u 0x6C PRAISE, SCOLD, SLEEP. `renderRectPolyFT4` takes one texel off a sprite that would reach u or v 0x100 (none of these do).

## 3. Sounds

| Sound (bank 0) | When |
|---|---|
| 0, 1 | the box opens / closes (UIBoxes, already wired) |
| 2 | the cursor moves |
| 3 | ✕ on an enabled option |
| 4 | ✕ on a disabled option; △ closes the menu |
| 13 | the tamer scolds |
| 14 | the partner is praised (when it reaches the tamer) |

## 4. Godot design

- **Scene** `scenes/ui/game_menu.tscn`: a `GameMenu` node (`scripts/ui/game_menu.gd`), the menu object of §2.2–2.4 and box 0's tick and render functions (on `UIBoxes`, `docs/ui.md`). It's the logic and the presentation of this menu; a mod may replace the scene (`specs/scenes.md` §5).
  - References (set by its host): `boxes`, `text_area`, `tamer`, `partner`, `care`, `clock`, `pad`, `sound`, `game_state`; services fall back to the autoloads.
  - Signals up: `closed` (the field resumes), `option_chosen(entry)` for the screens not ported yet (the help line names them).
  - `is_open` is `IS_IN_MENU`.
- **Host** `Systems/MenuHost` (`scripts/field/hosts/menu_host.gd`): instances the scene, opens it when the tamer asks (`tamer.open_menu`, a callable like `change_map`), and gives it its references.
- **Frame order** (`Field._frame`): the menu object ticks after the NPCs (its `addObject` slot is the first free one, after the field's fixed objects); box 0's tick runs in the UI boxes' pass as today. While `is_open`:
  - `Field._frame` skips the partner's state tick and the NPCs' ticks (§2.6: where the C returns at the top of the tick);
  - `CareHost` skips and hides the condition bubbles.
- **Tamer:** state 1 (menu opened, → 6 next tick), states 9 / 13 (scold / praise, §2.5); the △ check in the walking state; `STORED_TAMER_POS`. State 6 now runs `tamerTickIdle` (animation 0 once), which every scene that sets it relies on (the praise's wait for animation 0).
- **Data porter:** `praise_pat_low` is on `raise_data` (partner care data), beside the other care properties.
- **The pad** comes from the host (`GameLoop.pad`, passed down by the field).
- **Partner:** states 4 / 15 (`tick_praise_scold`), calling `care.handle_praise_scold`.
- **Care:** `sleep_enabled` already reflects `MENU_OPTIONS[6].disabled` (`setSleepDisabled`). The debug key `Z` and the care panel's Sleep go through the menu's option 6 code.
- **Data porter:** `raise_data.praise_pat_low` (§2.5), with its evidence in `data_porter/specs/digimon.md`.

## 5. Tests (`tests/test_game_menu.gd`)

Headless, with `UIBoxes`, a tamer, a partner and `Care` as in `test_npc.gd`:
- opening: △ only in the walking state with no script and box 0 free; tamer state 1 → 6, game time stopped, `is_open`;
- the cursor's wrap-around (§2.3's worked examples, with 7 and 8 options) and sound 2;
- ✕ on Sleep while not sleepy: sound 4, nothing else; while sleepy: sound 3, partner state 3, the menu closed;
- △: sound 4, the menu closes, tamer state 0, game time runs;
- praise and scold: the partner walks up, the sounds (14 / 13), the tamer's animation (0x26 / 0x27 by `praise_pat_low`, 7), `handle_praise_scold`'s values (discipline / happiness), states back to 1 / 0;
- while open: the NPCs and the partner's state don't tick, the bubbles are hidden;
- the drawing: the date digits' sprites for day 1, year 1 and for 12 / 345.

## 6. Not in this step

- **Items** (5e-2): `addInventoryUI`, `drawInventoryText` (`inventory.c`), feeding (`startFeedingItem`, `partnerTickFeedItem`, partner state 5, tamer state 6), `ITEM_SCOLD_FLAG` from a refused item, `STORED_TAMER_POS`.
- **Digimon and Player screens** (5e-3): `tickDigimonMenu` / `renderDigimonMenu` (status, techniques, evolution chart), `tickPlayerMenu` / `renderPlayerMenu` (tamer info, medals, cards).
- **Fishing** (with its own step): `getFishingAvailability` needs `FISHING_DATA_PTR` (loaded with fishing maps) and the rods; until then the count stays 7 and the Fishing row isn't drawn.
- The **script builtins with their menus** (shops, item bank, ...), one step each (5e-4 on).

Until 5e-2 / 5e-3, ✕ on Items, Digimon or Player plays sound 3 and names the screen in the help line; the menu stays open.

## 7. Open points

- **Evolution after praise / scold** (`handleSpecialEvolutions(3)`, `NANIMON_TRIGGER`): with evolution. `Care.handle_praise_scold` already sets the trigger.
- **The menu object's slot:** the original adds it to the first free object slot, so its place in the frame depends on what was freed before. Its state machine only reads the UI boxes, so the port's fixed place (after the NPCs) doesn't change what it does.
