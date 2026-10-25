# The Digimon and Player screens

Status (2026-10-25): spec written, step 5e-3 (`PLANS.md` 5e). Not coded yet. Coded in two parts: **5e-3a** the Digimon screen (§3), **5e-3b** the Player screen (§4).

The △ menu's DIGIMON and PLAYER icons open a full-screen window with tabs:
- **Digimon:** Status (the partner's values, its model) and Techniques (the equipped techniques, the finisher, and a grid of every technique where they are equipped).
- **Player:** Info (the tamer, his model), Evolution chart (every Digimon raised, and each one's paths), Medals (the medals won, a rotating 3D medal), Cards (the card collection, a card's picture).

They only show the state and change one thing: the equipped techniques. The drawing coordinates are the C's tables, copied as they are into the port (like `MENU_OPTIONS` in `specs/game_menu.md`); this spec names each table and says what it draws.

## 1. The C code

| C (US) | What |
|---|---|
| `tickTriangleMenu` states 3–6 (`game_menu.c:1359–1399`) | opening and closing the two screens |
| `tickDigimonMenu`, `renderDigimonMenu` (`:1705`, `:1822`) | the Digimon screen: tabs, input |
| `renderDigimonStatsView`, `drawDigimonStatsStrings`, `renderDigimonStatsBar`, `renderDigimonStatusConditions` (`:2402`, `:3859`, `:3899`, `:3912`) | Status tab |
| `renderDigimonMovesView` (US `:2752`), `drawDigimonMovesText` (`:4048`), `drawMoveViewHelpStrings` (`:3318`), `renderDigimonMovesSelected` (`:3060`), `renderDigimonMoveBox` (`:3183`), `getEquippedSlot` (`:2260`), `equipMove` (`:2298`), `sortArray` (`:3337`) | Techniques tab |
| `tickPlayerMenu`, `renderPlayerMenu` (`:1860`, `:2131`) | the Player screen |
| `renderPlayerInfoView`, `drawPlayerInfoStrings` (`:2976`, `:4126`) | Info tab |
| `renderEvoChartView`, `renderEvoChartDetail`, `drawEvoChartStrings` (`:3365`, `:3450`, `:4168`) | Evolution chart tab |
| `renderMedalView`, `drawMedalViewStrings`, `renderDigiviceMedals`, `activateMedalTexture` (`:3664`, `:4199`, `:4024`; `map_object.c:1193`) | Medals tab |
| `renderCardsView`, `drawCardViewStrings`, `loadCardImage`, `renderCardImage`, `renderCardCount` (`:3750`, `:4240`, `:2380`–`:2400`) | Cards tab |
| `renderMenuTab`, `renderInsetBox`, `renderBox`, `renderBorderBox`, `renderSeparatorLines` (`:2960`, `:3801`–`:3857`, `:4262`) | drawing helpers |
| `renderDigiviceEntity` (`:3953`) | the partner's / tamer's model in the window |
| `hasDigimonRaised`, `hasMedal` (`script_common.c:3019`, `:3033`), `entityGetTechFromAnim` (`utils2.c:333`), `hasMove` (`utils2.c:311`) | state |
| Data: `STATS_VIEW_*`, `MOVES_*`, `DIGIMON_MOVE_INFO_LINES_*`, `TAMER_*`, `EVO_CHART_*`, `CHART_*`, `MAIN_D_8012472C` (medal lines), `MAIN_D_80124B48` (chart insets), `CARD_SPRITE_CLUT`, `DIGIVICE_ENTITY_VIEW`, `MEDAL_VIEW` (`game_menu.c:364–1235`); texts `MENU_LABELS`, `STATUS_VIEW_LABELS`, `PLAYER_VIEW_LABELS`, `TECH_VIEW_LABELS`, `CARD_CHART_LABELS`, `LEVEL_TITLES`, `MEDAL_NAMES`, `MEDAL_DESCRIPTIONS` (`text/main/game_menu.yaml`) | |

## 2. Opening and closing (`tickTriangleMenu`)

- ✕ on DIGIMON / PLAYER: menu state 3 / 5. Box 0 (the △ menu) closes; once it is closed, box 1 opens (−0x96, −0x59, 300 × 0xBE), colour 0, no features, grown from the tamer's point, with the screen's tick and render. The text area is cleared and the first tab label drawn; `MENU_STATE` = 0, `MENU_SUB_STATE` = 0, tab 0; the menu object idles (state −1).
- **The screen's ticks hide the tamer and the partner** (`isOnScreen = 0` every frame: their models are drawn in the window instead, §3.1, §4.1).
- **Back** (the screen sets menu state 4 / 6): the tamer and partner shown again, box 1 closes; once closed, menu state 0: the △ menu opens again (on its current selection).
- `IS_IN_MENU` stays 1 and game time stays stopped the whole time.

**`MENU_STATE` in each tab:** 0 = drawing the tab's strings into the text area, one part per frame (`MENU_SUB_STATE`); once done, 1 = shown. Changing tab resets both to 0 (the next tab redraws its strings). A tab drawn while its strings aren't finished shows nothing but the box.

**Tabs** (`renderMenuTab`): drawn over the top edge of box 1; the current tab's label in colour 0 and its tab at layer 0 (in front), the others in colour 1 (`DIGIMON_MENU_VIEWS` / `MAIN_D_801342A4`, 1 = not current), their tab one pixel shorter. US label positions: Digimon (−0x8A, −0x65) 0x3C wide, Techniques (−0x3F, −0x65) 0x30; Player Info (−0x89) 0x3C, Chart (−0x3E) 0x3C, Medals (0xD) 0x24, Cards (0x40) 0x24; tabs at (−0x91, 0x4C), (−0x46, 0x40 / 0x4C), (5, 0x34), (0x38, 0x34).

## 3. The Digimon screen (5e-3a)

### 3.1 Input (`tickDigimonMenu`)

While on Status, or on Techniques with `MENU_STATE` 1:
- **→ / ←** (`CHANGED_INPUT`, `MENU_STATE` ≠ 0): next / previous tab (0–1, no wrap); a change resets `MENU_STATE` / `MENU_SUB_STATE` and plays sound 2.
- **△:** if `MENU_STATE` is 1, back to the △ menu (§2); sound 4 either way.
- **✕ on Techniques:** if `MENU_STATE` is 1, `MENU_STATE` = 2 (the window shrinks, then the grid opens, §3.3); sound 3.

In the technique grid (`MENU_STATE` 6):
- **△:** leaves the grid (`MENU_STATE` = 4) only if one of the 3 equipped slots holds a technique with power ≠ 0; sound 4 either way. (A partner must keep one attack equipped.)
- **□** (0x80): the help page (`MENU_STATE` 7, `MENU_SUB_STATE` 0), sound 3.
- **✕:** on an equipped technique, it is unequipped (that slot = 0xFF), sound 3; else `equipMove` (§3.4).
- **Arrows** (`CHANGED_INPUT`): the cursor moves 0x12 across, 0xF down, kept within x 0x73–0xF1, y 0x6F–0xC9 (8 columns, 7 rows); sound 2 when it moved.

On the help page (`MENU_STATE` 8): **△** → `MENU_STATE` 9 (redraw the grid's strings, then 6), sound 4.

### 3.2 Status tab (`renderDigimonStatsView`, `MENU_STATE` 1)

- **Strings** (`drawDigimonStatsStrings`, 4 frames): clear `DIGIMON_STATS_TEXT_AREA`; the help line (`MAIN_D_80124C54`) at row 0xF0; labels; the Digimon's name (US at (0, 0x48)); the partner's name at (0, 0x3C); `STATUS_VIEW_LABELS[1]`, `[2]`.
- **Drawn:**
  - separator lines (`STATS_VIEW_LINES`, 6), the 9 labels (`STATS_VIEW_TEXT`, colour 3), the 21 icons (`STATS_VIEW_ELEMENTS`, palettes `STATS_VIEW_ELEMENT_CLUT`), 13 inset boxes (`STATS_VIEW_INSETS`);
  - the partner's name and its Digimon's name (US: width = name length · 10, at most 0x78);
  - numbers (`renderNumber`): age, weight, HP / max HP, MP / max MP, Offense, Defense, Speed, Brains (US positions in `renderDigimonStatsView`);
  - stat bars (`renderDigimonStatsBar`: width = scale · value / max, 2 px high, colour (0x32, 0xC8, 0xC8)): HP and MP scaled 100 / 9999, the others 50 / 999;
  - the Digimon's specialties (`DIGIMON_DATA.special[3]`, 0xFF = none): icons blinking every 5 frames, palette by specialty (2–4 one, 5 another); its type icon (`DIGIMON_DATA.type`, unless 0); its sleep pattern's label (`RAISE_DATA.sleepCycle`, 5 = its own label);
  - lives: 3 empty hearts, filled for `i < lives`;
  - conditions (`renderDigimonStatusConditions`): one bobbing icon per condition bit in the order sick, injured, hungry, sleepy, unhappy, tired (`MAIN_D_80123DD0` masks), plus poopy; the bob follows `PLAYTIME_FRAMES % 16`;
  - happiness (an up / down face and a bar: ≥ 0 the right half by happiness / 2, < 0 the left half by (happiness + 100) / 2) and discipline (face by ≥ 50, bar), the virus bar (`virusBar · 3` wide);
  - **the partner's model** (`renderDigiviceEntity`, §5).

### 3.3 Techniques tab (`renderDigimonMovesView`)

`MENU_STATE` 1 – the summary:
- **Strings** (`drawDigimonMovesText`, 6 frames): reads the 4 equipped slots: `EQUIPPED_MOVES[i]` = the technique of `stats.base.moves[i]` (a battle animation; `entityGetTechFromAnim`: `DIGIMON_DATA[type].moves[anim − 0x2E]`) or 0xFF; draws their names at rows 0x18 + 12i, the labels; puts the grid cursor at (0x73, 0x6F).
- **Drawn:** the "Tech set" frame (`MOVES_VIEW_TECHSET_TEXT`, 13 pieces, lines `MOVES_TECHSET_LINES`); for each of the 3 slots: name, power, MP (`mpCost · 3`), range label, status icon (`MOVE_DATA`); the finisher (slot 3) the same without MP; two help lines ("✕: set techniques" style, colours 0xF / 7).

`MENU_STATE` 2–5 – the transition: box 1's height −0x27 per frame until < 0x4A (states 2 / 4), then +0x27 per frame until > 0xBD (3 / 5); 3 then opens the grid (6), 5 returns to the summary (1).

`MENU_STATE` 6 – the grid:
- The "Learned" label, the help-page frame (`MOVES_VIEW_HELP_LINES`, `MOVES_VIEW_HELP_CORNERS`), the element column icons (7 rows, at x −0x43 and 100), 8 column markers, a 7 × 8 grid of boxes, the cursor sprite at (cursor x − 0xA0, cursor y − 0x78).
- **The selected technique** (`renderDigimonMovesSelected`): a panel on the side away from the cursor (left when the cursor is right of x 0xA8): its name (drawn into the text area at row 0x84), power, MP, range, status — only if learned (`hasMove`).
- **The grid** (`renderDigimonMoveBox`):
  - each equipped technique's box red ((200, 0, 0x28), semi-transparent);
  - a box is dark grey when the partner's Digimon can't use that technique (not in its `DIGIMON_DATA.moves`, sorted ascending); the two Dynamite Kick / Black Out pairs (0x2C / 0x30, 0x37 / 0x39) count as one cell (§3.5);
  - each learned technique's icon (its `MOVE_DATA.special` row of icons, blinking every 10 frames, palette by special).

`MENU_STATE` 7 / 8 – the help page: `drawMoveViewHelpStrings` (8 frames: `STATUS_VIEW_LABELS[9..16]` at rows 0x18 + 12i), then its lines, labels and sample sprites (`MOVES_VIEW_STRING_SPRITES`, `MOVES_VIEW_SPRITES` — US skips sprite 2). 9: redraw the grid's strings (`drawDigimonMovesText`), then 6.

### 3.4 Equipping (`equipMove`, `getEquippedSlot`)

The cursor's cell → technique id (`(x − 0x73) / 18` = column, `(y − 0x6F) / 15` = grid row): grid rows 0–6 hold the id blocks 0–7, 0x28–0x2F, 8–0xF, 0x20–0x27, 0x10–0x17, 0x18–0x1F, 0x31–0x38 (row 6 skips 0x30).
- **Equipped** (`getEquippedSlot`): one of the 3 slots holds it (0x2C's cell also matches 0x30, 0x37's also 0x39) → that slot is emptied.
- **`equipMove`:**
  1. not learned (`hasMove`): sound 4;
  2. find it in the partner Digimon's 16 technique slots (`DIGIMON_DATA[type].moves`); for 0x2C / 0x37 the Digimon's own variant (0x30 / 0x39) is used if that's the one it has; not there: sound 4;
  3. the first free of the 3 slots (none: sound 4) gets it: `stats.base.moves[slot]` = 0x2E + the technique's slot index (its battle animation), its name redrawn at row 0x18 + 12·slot; sound 3.

### 3.5 Data

- **The grid is a layout of technique ids by element.** The port reads it as a property: the data porter adds `move_data.menu_cell {row, column}` from the C's id blocks (checked against the text of `getEquippedSlot` / `renderDigimonMoveBox`), with the two pairs sharing one cell (`learned_with`, already a property). The ported code finds a cell's technique by that property, never by computing ids.
- `GameState`: `partner.stats.base.moves[4]` holds technique keys (`specs/game_state.md`), not animation ids; equipping writes the key, the battle animation is derived when needed (the technique's index in the Digimon's list). `partner.learned_moves` for `hasMove`.

## 4. The Player screen (5e-3b)

### 4.1 Input (`tickPlayerMenu`)

`MENU_STATE` < 2 (a tab shown):
- **→ / ←:** tab 0–3, no wrap; sound 2.
- **△:** back to the △ menu (§2), sound 4.
- **✕** on the Chart, Medals or Cards tab (`MENU_STATE` 1): `MENU_STATE` 2 (the tab's cursor), sound 3, medal and card selections 0.

`MENU_STATE` ≥ 2:
- **△** in state 2: back to state 1 (no cursor), sound 4.
- **Chart** (state 2): the cursor over 9 columns (the levels, 2 for In-Training, then Rookie, Champion ×4, Ultimate ×2; rows by column: columns 0–1 move by 2 rows, max row 6; column 2 max 8; 4–6 and 8 max 6; others 7); sound 2 on a move; the Digimon under the cursor (`EVO_CHART_BOXES` by position). **✕** on a raised Digimon (`hasDigimonRaised`): box 2 opens the detail (§4.3), state 3, sound 3; not raised: sound 4. State 3, **△**: box 2 shrinks back to the cell, state 2, sound 3.
- **Medals** (US: in every state ≥ 2, the JP / EU versions only in state 2): the cursor over a 5 × 3 grid; on a change, sound 2, and if that medal is won, its texture is loaded into the 3D medal (`activateMedalTexture`) and the description redrawn (state 3 → 2).
- **Cards** (state 2): the cursor over 11 × 6; sound 2; **✕** on an owned card (`getCardAmount`): sound 3, state 3, the card's picture (`CARD/CARD.ALL`, entry `id`) in box 2 (−0x4B, −0x53, 0x96 × 0xB4) and its count in box 3 (0x4A, 0x45, 0x36 × 0x18), grown from the card's cell. State 3, **△**: sound 4, both shrink back, state 2.

### 4.2 Info tab (`renderPlayerInfoView`)

Strings (`drawPlayerInfoStrings`, 6 frames): the labels, the tamer's name (`DIGIMON_NAME(0)`), the 11 tamer level titles (`LEVEL_TITLES`), US: the playtime as "%d : %d". Drawn: lines (`TAMER_VIEW_PLAYER_LINES`), labels (`TAMER_WINDOW_NAME_STRING`), the tamer's name, his level and its title, Digimon raised (`raisedCount`), bits (money, 6 digits), playtime, 4 key items shown as icons when their triggers are set (0x2D, 0x2E, 0x2F, 0x30), the number of medals won (of 18), insets (`TAMER_WINDOW_BOXES`), **the tamer's model** (§5).

### 4.3 Evolution chart (`renderEvoChartView`, `renderEvoChartDetail`)

- Every Digimon raised (`hasDigimonRaised(i + 1)`, trigger 0x200 + id) shows its 16 × 16 portrait at its `EVO_CHART_BOXES` cell (palette by `clut`); the selected one blinks in states ≥ 2; every cell has a bordered box; five coloured level columns; two footer lines.
  - **Quirk:** the loops run over 0x3E = 62 entries of `EVO_CHART_BOXES[61]`; the 62nd reads past the table. To check when coding (what the next table holds there).
- **Detail** (box 2): the selected Digimon's portrait in the centre, its level's name and its name; the Digimon it can come from (`EVOLUTION_PATHS.from`, up to 5) and evolve to (`.to`, up to 6) at fixed spots (`CHART_FROM_*` / `CHART_TO_*`, odd or even counts), joined by 3-pixel coloured lines; portraits only for the raised ones (others an empty box).

### 4.4 Medals (`renderMedalView`)

15 slots (5 × 3): a won medal (`hasMedal(i)`, trigger 0x16C + i) shows its sprite, else a blank; the selected one's name and 3 description lines (`MEDAL_NAMES`, `MEDAL_DESCRIPTIONS`) and the **rotating 3D medal** (`renderDigiviceMedals`: `ETCNA/MEDAL.TMD`, rotation +0x64 per frame around y, projection 0x400, view `MEDAL_VIEW`; its texture is the medal's cell of the medal atlas, `activateMedalTexture`: VRAM (518 + (id % 9)·6, 432 + (id / 9)·32) copied to (512, 432)). The count on the Info tab goes to 18 (`hasMedal(0..17)`); this grid shows 15.

### 4.5 Cards (`renderCardsView`)

66 cells (11 × 6): an owned card's portrait (`CARD_SPRITE_CLUT` palette), a bordered box each; the cursor; two footer lines. The picture: `CARD.ALL` entry `id` (asset porter `card_all`), drawn 0x96 × 0xB4; the count with `renderNumber` and a "×"-style glyph.

## 5. The model in the window (`renderDigiviceEntity`)

The entity's model is drawn into the window with its own view: projection 0x200, eye (1300, 0, −3280) looking at (0, 0, 0) (`DIGIVICE_ENTITY_VIEW`), one white light (0x80) from (100, 100, 100); the model at `RAISE_DATA[type].view {x, y, z}` (the tamer: type 0), rotation 0, animation 0's first pose; then put back. The field hides the entity meanwhile (§2).

Godot: a `SubViewport` with its own `World3D`, camera and light, holding a separate instance of the entity's model (`Content.load_model`) posed at animation 0's first frame, shown in the window as a texture at the place the PSX projection puts it. The field's own entities stay untouched (the C's save / restore of position and animation isn't needed).

## 6. Sounds

| Sound (bank 0) | When |
|---|---|
| 2 | tab change, any cursor move |
| 3 | ✕ (open the grid, equip, unequip, open a detail / card), □ (help) |
| 4 | △, a refused equip, ✕ on something not raised / not owned |

## 7. Godot design

- **Scenes** `scenes/ui/digimon_screen.tscn` (5e-3a) and `scenes/ui/player_screen.tscn` (5e-3b), each the box-1 window of §2 with its tabs, opened by `GameMenu` (states 3–6) through `MenuHost`, like the inventory. The tabs are child nodes / scripts of the screen (one per tab) so a mod can replace one.
- **`DigiviceView`** (`scripts/ui/digivice_view.gd`): §5's model view, shared by both screens.
- **Data porter:** `move_data.menu_cell` (§3.5). The layout tables of §1 are copied into the scripts (they are the screens' layout, not game data).
- **Assets needed:** the system textures already used (`etctim/08_system_w`, `04_fi_info`); for 5e-3b the evolution chart portraits, the medal atlas and `MEDAL.TMD`, the card pictures (`card_all`) — each located from the VRAM pages the C names, when coding.

## 8. Tests

- `tests/test_digimon_screen.gd` (5e-3a): opening / closing through the menu; tab changes and their sounds; the summary's equipped techniques for Agumon (Spit Fire); the grid's cell → technique mapping for every cell (against `menu_cell`); equip / unequip / refusals (not learned, not usable by this Digimon, 3 slots full), the "keep one attack" rule on △; the help page round trip.
- `tests/test_player_screen.gd` (5e-3b): tabs; the chart cursor's limits per column and the Digimon under it; a raised / not raised detail; the medal and card cursors; a card's picture for an owned card.

## 9. Open points

- `EVO_CHART_BOXES` read one past its 61 entries (§4.3).
- The exact US playtime string (`FMT_PLAYTIME`, "%d : %d") and the key items of the Info tab (triggers 0x2D–0x30: which items) — to name when coding.
- The medal atlas's TIM and `MEDAL.TMD`'s texture placement (§4.4).
