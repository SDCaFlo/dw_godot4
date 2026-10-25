# Shops and the script item menu

Status (2026-10-25): coded, step 5e-4a (`PLANS.md` 5e-4). Code: `ScriptRoutines` (`scripts/script/script_routines.gd`, node `Systems/ScriptHost/Routines`), `scenes/script/shop_routines.tscn` (`scripts/script/shop_routines.gd`), `ItemMenu` (`scripts/ui/item_menu.gd`), `TextBoxes.show_maphead_textbox` / `show_maphead_selection`, `MenuDraw.item_icon`. Tests: `tests/test_shops.gd`. Checks: VERIFY "Shops".

As built:
- **Port bug fixed** (`TextBoxes.tick_selection_dialogue`): △ in a choice now asks who owns the choice *before* `advanceTextbox` clears `ACTIVE_INSTRUCTION`, as the C does. Before the fix, a routine's choice (Buy / Sell / See ya) was cancelled like a script's SET_SELECTION.
- **`flipTextboxPage`** (`script_common.c:2536`) falls off its end after flipping a page, so its return value there is undefined. The port counts that frame as busy. It runs in the list's on-render step, so the drawing never changes state.
- **Where shopkeepers come from:** when and whether a shopkeeper stands on the map is decided by the map's MAPHEAD entry section, not by the shop:
  - the hour, with `STORE_DATE` then `IF` on value 107 (e.g. Freezeland's Hyogamon / IceDevimon, 7–19 h);
  - story triggers (e.g. File City's Item Shop keepers, Mojyamon in Freezeland).

  The port already runs those (map entry, NPC spawning). The shop builtin only runs the dialogue.
- **Gear Savanna:** map 0x83 (GIAS06B), the one map with `playShopSoundOnlyInSavannah`, is the Digimon Card Shop (Market Manager, builtin 0x0E): `specs/card_shops.md`.
- **One item menu:** since 5e-4b, `ScriptRoutines` makes the one `ItemMenu` (`host.menu`), shared by every routine node (`specs/card_shops.md` §3). The shop helpers are in the base class `MenuRoutines`.

Talking to a shopkeeper starts an event script. The script sets the shop's stock and calls a builtin routine (`CALL_ROUTINE`). The routine runs a small dialogue with menus:
- the shopkeeper's greeting;
- Buy / Sell / See ya;
- a list of items with their prices;
- an amount box;
- the bits box in the corner.

When the routine is done, the script goes on.

This step ports that machinery: the **script item menu** (`script_common.c`), the **general shop and the recycle shop** (builtin 0x08), the **bits box** (0x0F), and the **item picker** (0x00, 70 calls in the scripts). It also adds the **routine host** that the later builtins plug into. The merit shop, Mojyamon's trades, the card shops, the item keeper, the jukebox and Birdramon reuse the item menu with other list types; they are later parts of 5e-4.

## 1. The C code

| C (US) | What |
|---|---|
| `CALL_ROUTINE` (`script_interp.c:1658`); its tick (`:421–561`) | builtins 0x00 and 0x08 wait (`ACTIVE_INSTRUCTION` = `CALL_ROUTINE`, `SCRIPT_STATE_2` = 0, `SCRIPT_TEXTBOX_MODE` = 0, the frame ends); the tick calls `openDiscardItem` (0x00) or `openShop` / `openRecycleShop` (0x08, by trigger 3) every frame until they set `ACTIVE_INSTRUCTION` = 0. 0x0F: `createShopBitsBox(1)`, no wait; 0x23: `loadShopLibrary` (an overlay load). |
| `tickScriptDialogueBox` (`script_textbox.c:969`) | a routine waits for its text through `SCRIPT_TEXTBOX_MODE`. Mode 1: confirm, then `SCRIPT_STATE_2 = SCRIPT_NEXT_STATE_2`. Mode 2: a choice, then `SCRIPT_NEXT_STATE_2 + choice`. Mode 3: the page shown (`tickBackgroundDialogue`). Ported (`TextBoxes.tick_script_dialogue_box`). |
| `openShop` (`script_common.c:1618`), `openRecycleShop` (`shop/script_menu.c:584`) | the shops' steps (§2.2, §2.3) |
| `openDiscardItem` (`script_common.c:1815`) | the item picker (§2.4) |
| `createShopBitsBox`, `tickShopBitsBox`, `renderShopBitsBox` (`:1757`, `:1154`, `:3123`) | the bits box (box 2) |
| `showMapHeadTextbox`, `showMapheadSelection`, `getShopkeeperLine`, `resolveMapHeadEntry` (`:2431`, `:2971`, `:1174`, `:1204`) | the shopkeeper's lines, from the MAPHEAD script (§2.1) |
| `allocateItemMenuBox`, `createItemMenu`, `tickItemMenu`, `renderItemMenu`, `getItemMenuFromType`, `initItemMenuBox` (`:1729`, `:1788`, `:798`, `:984`, `:1856`, `:1875`) | the item menu (box 1) |
| `shopFillBuyItemList`, `shopFillSellItemList`, `fillRecycleShopItemList` (`:695`, `:765`, `script_menu.c:1385`) | the lists |
| `updateItemMenuStrings`, `calculateItemMenuStrings`, `updateItemMenuLine`, `getTextboxLine`, `terminateString`, `flipTextboxPage` (`:1896`, `:2563`, `:2799`, `:2886`, `:2905`, `:2536`) | the rows as text lines |
| `itemMenuCursorUp` / `Down` / `Top` / `Bottom`, `…MoveToTop` / `…MoveToBottom` (`:2095–2160`, `:2858–2885`) | the cursor and scrolling |
| `renderItemMenuSprite`, `renderItemMenuScrollBar`, `renderItemMenuItemList`, `renderHorizontalLine`, `renderInsetWithoutBox` (`:2221`, `:2254`, `:2304`, `:2386`, `:2403`) | drawing |
| `createItemMenuAmountBox`, `tickItemMenuAmountBox`, `renderItemMenuAmountBox`, `updateItemMenuAmountBoxString` (`:1964`, `:1457`, `:937`, `:1023`) | the amount box (box 3): buying and selling |
| `createItemMenuDescriptionBox`, `tickItemMenuDescriptionBox`, `renderItemMenuDescriptionBox` (`:2163`, `:903`, `:921`) | an item's description (box 3, □ / START) |
| `createSingleCardShopMenu`, `tickSingleCardShop`, `renderSingleCardShop` (`:2047`, `:1070`, `:1127`) | the "Is it OK? Yes No" box of the item picker (box 3) |
| `isPartnerBaby` (`:1439`), `getRecycleId` (`:1386`), `playShopSoundOnlyInSavannah` (`:2371`), `isXPressedAfterDialogue`, `setInputRepeatMask` (`:1310`, `:1322`) | helpers |
| Data | `ITEM_PARA` (`items/item_data`: `price` = `value`, `droppable`); `RECYCLABLE_ITEMS` (`items/recyclable_items`); `SHOPKEEP_DIGIMON_TYPES` (`items/shops`); `BABY_IDS` (`systems/babies`); the item names and descriptions (`ITEM_NAMES`, `ITEM_DESCS`); the recycle stock (`GameState.state.script.recycle_stock`, `SCRIPT_STATE_PTR->smth[6 + i]`) |
| Tables | `ITEM_MENU_POS[8]`, `ITEM_MENU_DESCRIPTION_RECTS[8]`, `SELECTION_CURSOR_WIDTHS[8]` (`:624–638`), `ITEM_MENU_HEADER_UVS[7]` (`:330`), `AMOUNT_BOX_LAYOUT` (US `:292`), `CONFIRM_BOX_LAYOUT` (US `:316`), `MAIN_D_801345C0` / `C2` (`:261`) |

## 2. Behaviour

### 2.1 How a script uses a shop

Before the call, the script:
- **Sets the stock** as triggers: trigger 0x180 + item id for each item on sale. It clears them again after the call.
- **Names the shopkeeper:** script value 0xFE = the NPC's script id, or 0xFF for none.
- **Picks the shop:** trigger 3 unset for the regular shop, set for the recycle shop.

Example: `DG/script_126` section 0x52: "This's a Recycled Goods shop.", then "I want a regular item / I want a recycled item / Next time".

**The shopkeeper's lines** (`getShopkeeperLine`) come from the MAPHEAD script (script 0). They are a section of 14 entries: section 0x4C4 + i when the NPC's Digimon type is `SHOPKEEP_DIGIMON_TYPES[i]`, 0x4C4 for any other NPC, and 0x4CE when value 0xFE is 0xFF.
- **Format:** each entry is a `JUMP_TO` whose target is a `SHOW_TEXTBOX`; the text starts 2 bytes after it.
- **The lines of 0x4C4, by index:**

| Index | Line |
|---|---|
| 0 | "What are you going to do?" |
| 1 | "I don't have anything to sell." |
| 2 | "Buy / Sell / See ya" (a 3-way choice) |
| 3 | "Buy / See ya" |
| 4 | "Come again." |
| 5 | "That's too bad." |
| 6 | "Bits {money}" |
| 7 | "Points {merit}" |
| 8 | "Shop." |
| 9 | "Want to sell anything?" |
| 0xA | "Thanks." |
| 0xB | "Have anything else?" |
| 0xC | "No." |
| 0xD | "I'll discount it {shop_value}." |

The other sections reword some of these.

**Showing a line** (`showMapHeadTextbox`):
- in box 0, `setDialogueOwner(owner)` first (the speaker line, the box's origin);
- the script pointer is pointed at that text, `showTextboxReady(box, owner)` runs, and the pointer comes back;
- `ACTIVE_INSTRUCTION` stays `CALL_ROUTINE`.

`showMapheadSelection` shows the same kind of line as a choice:
- `count` choices;
- the first call sets `current` = 0;
- cursor width = the widest line × 12 + 2;
- cursor offset 0xD below the speaker line.

### 2.2 The shop (builtin 0x08, trigger 3 unset: `openShop`)

`SCRIPT_STATE_2` steps. "→ n" means: wait for ✕ on the line, then go to step n (`SCRIPT_TEXTBOX_MODE` 1).
- **0:** the lists' boxes are allocated:
  - left (buy): 6 rows, scroll bar at (0xB2, 0x18), 6 × 0x5A;
  - right (sell): 6 rows, scroll bar at (0xD2, 0x18).

  "Bought something" = 0. If any stock trigger 0x180–0x1FF is set: line 0, → 3; else line 1, → 2.
- **2:** free the lists; `ACTIVE_INSTRUCTION` = 0 (the script goes on).
- **3:** the bits box (§2.5); the choice line 2 (Buy / Sell / See ya) as the tamer's (owner 0xFD), 3 choices (mode 2): Buy → 4, Sell → 5, See ya → 6. △ picks the last one. The choice keeps its last position (`SHOP_ACTION_SELECTED`).
- **4:** d-pad repeat on ↑ ↓ (mask 0x5000); list type 0 (buy): `shopFillBuyItemList`, `createItemMenu`; line 8 in the dialogue box, shown without waiting (mode 3). Step 1 (the item menu works; §2.6).
- **5:** the same for selling: type 1, `shopFillSellItemList`, line 9.
- **6:** the bits box closes; line 4 if something was bought (or sold), else line 5; → 2.
- **7** (after a purchase or a sale, §2.7):
  - repeat off; the item menu closes;
  - line 0xD for a purchase while the partner is a baby (`isPartnerBaby`: its type is in `BABY_IDS`; the line names the discount, `SHOP_VARIABLE`), else line 0xA;
  - "bought something" = 1; → 3.
- **8** (△ in the list): repeat off, the item menu closes, line 0xB; step 9 then waits for ✕ → 3.

**The lists:**
- **`shopFillBuyItemList`:** one row per stock trigger, in item id order: (item, buyable).
  - Not buyable (0) when its price > bits.
  - With a free slot, not buyable when a slot of it holds 99.
  - Without a free slot, buyable only when a slot of it holds fewer than 99.
- **`shopFillSellItemList`:** one row per inventory slot, empty ones too: (item or 0xFF, amount | 0x80 when the item is `droppable`).

### 2.3 The recycle shop (builtin 0x08, trigger 3 set: `openRecycleShop`)

Like §2.2 with these differences:
- **The list:** list type 2, left list only (scroll bar at 0xD2). One row per recycle stock slot with a count: (`RECYCLABLE_ITEMS[i]`, count | 0x80 when its price ≤ bits).
- **The choice:** line 3 (Buy / See ya), 2 choices: → 4 or 5. Steps 5 and 6 both close: line 4 or 5, → 2.
- **After a purchase (step 7):** the list is filled again. → 3 if anything is left, else → 9: line 0xC, → 6.

### 2.4 The item picker (builtin 0x00: `openDiscardItem`)

The decomp names it "discard". The scripts use it to **pick an item to give**, for example `DG/script_002` section 6: "I'm hungry." / Give food:
1. **Before the call:** the script sets trigger 3.
2. **After it:** trigger 3 still set means no item could be picked ("I don't have food now."). Otherwise script value 0xFE is the item picked (0xFF if cancelled). The script then removes it (builtin 0x0C) and reacts by item.

The steps:
- **0:** the right list (scroll bar at 0x9A), `shopFillSellItemList`.
  - If an item is `droppable`: → 3 at once (mode 0).
  - Else: trigger 3 set, value 0xFE = 0xFF, → 2 (falls through to 1 this frame).
- **2:** free the list; `ACTIVE_INSTRUCTION` = 0.
- **3:** repeat on, list type 5, `createItemMenu`; step 1.
- **4:** repeat off, the item menu closes; → 2.

In the list:
- **✕ on a `droppable` item** opens "Is it OK? Yes No" (§2.8).
- **△** works only while trigger 3 is set: value 0xFE = 0xFF, trigger 3 unset, → 4, sound 4. The C plays sound 4 even when △ does nothing.

### 2.5 The bits box (box 2; builtin 0x0F; `createShopBitsBox`)

- **Box:** `createTextbox(2, 0xE1, (−0x98, −0x62, 0x52, 0x21), origin of owner 0xFD)`: animated, title style, at the top left. Rows: `registerTextbox(2, row 8, 1 row)`.
- **Text:** line 6 ("Bits {money}"), or line 7 ("Points {merit}") when called with 0 (the merit shop). It is redrawn when `UPDATE_SHOP_BIT_BOX` is set: on creation and after each sale or purchase.
- **Already open:** a call only asks for the redraw.
- **US render:** two parts of its text-area row: (x + 6 + 0x10, y + 4), 0x30 wide from u 0; and (same x, y + 4 + 0xD), 0x3C wide from u 0x30. The label sits above the number.
- **Closing:** builtin 0x10 (`triggerBoxCloseFlag(2)`, ported) closes it, as do steps 6.

### 2.6 The item menu (box 1)

**`createItemMenu`:**
- `createTextbox(1, 0xF1, ITEM_MENU_POS[type], origin)`. The origin is owner 0xFD for types 1 and 5, else the NPC in value 0xFE.
- Rows: `registerTextbox(1, row 9, 6 rows, double-buffered, mode 0)`.
- The box's cursor starts at the top, its 6 row slots = text rows 9…14. The visible rows are written (§2.6.1). `SHOP_VARIABLE` = 0.

**`ITEM_MENU_POS` (x, y, w, h) by type:**

| Type | Rect |
|---|---|
| 0, 3, 7 | (−0x37, −0x62, 0xBE, 0x81) |
| 1, 2, 4 | (−0x47, −0x62, 0xDE, 0x81) |
| 5, 6 | (−0x24, −0x62, 0xA6, 0x81) |

**List types:**

| Type | List |
|---|---|
| 0 | buy |
| 1 | sell |
| 2 | recycle |
| 3, 4 | cards (later) |
| 5 | item picker |
| 6 | (later) |
| 7 | merit (later) |

**Input (`tickItemMenu`):** only when all of these hold:
- the rows are not being redrawn (`flipTextboxPage`);
- box 3 is closed and box 1 open;
- ✕ was released since the box opened (`isXPressedAfterDialogue`);
- `SHOP_VARIABLE` is 0;
- the step is 1.

Then, first match wins:
- **✕:** the amount box (types 0–2, §2.7), the Yes / No box (type 5, §2.8), the merit trade (type 7, later).
- **△:** type 5 as §2.4; type 7 → 0xA (later); else → 8. Sound 4.
- **↑:** the cursor up one; with R1 held, to the top.
- **↓:** down one; with R1 held, to the bottom.
- **START (0x800):** the description box (§2.9), sound 3.

**The cursor:**
- **Up:**
  - at the top of the list, sound 0xB;
  - at the top of the window, the list scrolls (the row slots rotate, the new row is written: `updateItemMenuLine`);
  - sound 2.
- **Down:** the same at the bottom (sound 0xB past the last row).
- **Top / bottom:** move there, rewrite all rows, sound 2.

#### 2.6.1 The rows (`calculateItemMenuStrings`, US)

Each visible row is a text line in box 1's line buffers, at its row slot's text row, on the back page.

**Bytes of a row, in order:**
1. `01 c`: colour 1 when available, 3 (grey) when not.
   - Types 0 and 7: available when the second byte ≠ 0.
   - Others: available when its bit 0x80 is set.
2. The item's name.
3. `0F 00`.
4. Unless type 5: `16 00` (tab to 0x69), then the price as 4 digits without leading zeros, then `0F 00`. The price is the item's `price` (type 1: half of it). On a sell row of an item that can't be sold: `81 7C` × 4 ("－－－－") and `0F 00` instead.
5. Type 1: the amount (2 digits).
6. Type 2: `1C 00`, then the amount (2 digits).
7. `01 01`, then `00 00` on the last row, `0D 00` before the next.

**Rows with item 0xFF** (empty slots in the sell list) are written but not drawn.

#### 2.6.2 Drawing (`renderItemMenu`)

**Headers:** SYSTEM_W page 5, palette row 492 (p4), `ITEM_MENU_HEADER_UVS` (u, v, w, h; the C's v − 0x80 = image row):

| Header | At | Drawn |
|---|---|---|
| 0 | (bx + 8, by + 5) | always |
| 1 | (bx + 0x80, by + 5) | types 0–4 |
| 3 | (bx + 0xB6, by + 5) | types 1–4 |
| 2 | (bx + 0x80) | type 7 |
| 3 | (bx + 0x80) | type 5 |

**Scroll bar** (`renderItemMenuScrollBar`): at the list's rect in the box.
- An inset: lines 0x020202 / 0xA08769.
- A thumb: lines, box 0x5B7080.
- A track: box 0x354B5C.
- The thumb's height is h × visible / max(count, visible). Its y is y + 1 + (h·100 / rows × top / 100).

**The selection cursor** (`renderSelectionCursor`): at (bx + 5, by + 0x11 + cursor × 0x12), `SELECTION_CURSOR_WIDTHS[type]` × 0x12.

**The rows** (`renderItemMenuItemList`):
- The item icons (`renderItemSprite`): at (bx + 8, by + 0x12 + i × 0x12). While the rows redraw, the previous top row is used.
- The texts: 0xFF wide from the text area, at (bx + 0x1A, by + 0x13 + i × 0x12), with a shadow.

### 2.7 The amount box (box 3; types 0–2)

**✕ on a row** (`createItemMenuAmountBox`) sets the unit price and the maximum amount. The row's second byte is `amount`.
- **Sell (type 1):**
  - the item must be sellable (`amount` & 0x80);
  - unit price = price / 2;
  - maximum = the slot's amount.
- **Buy (type 0):**
  - the item must be buyable;
  - maximum 99.
- **Recycle (type 2):**
  - the item must be affordable;
  - maximum = the stock.

For buy and recycle, two more limits:
- the maximum is cut to 99 − the inventory's count of it;
- then, if maximum × price > bits, it becomes bits / price.

Failing these gives sound 0xB. Otherwise:
- amount = 1;
- the box opens: `createTextbox(3, 0xC1, (−0x41, −0x2A, 0x82, 0x53))`, from the row (origin = the description rect of the type + box 1's corner + cursor × 18);
- its line is box 0's back-page rows (`updateItemMenuSubTextboxLine`), 1 row;
- sound 3.

**Its line (US):**
1. the item's name;
2. `18 00`, the unit price (5 digits);
3. `19 00`, the amount (2 digits);
4. `1A 00`, the total (6 digits, capped at 999999);
5. `00 00`.

**Drawing** (`renderItemMenuAmountBox`):
- two separator lines: (4, 0x17) 0x7A wide and (0xC, 0x3C) 0x6A wide;
- an inset at (0x55, 0x2A, 0x1A, 0xE);
- the item icon at (8, 5);
- four parts of the line: `AMOUNT_BOX_LAYOUT` US (x, y, chars), taken 12 px per char from u 0, 8, 13, 15: name (0x1A, 7), price (0x4A, 0x1B), amount (0x59, 0x2B), total (0x40, 0x41).

**Input** (`tickItemMenuAmountBox`, once ✕ was released), first match wins:
- **↑:** +1, or +10 with ○ held; the +10 is undone if it passes the maximum. Sound 2. Nothing at the maximum.
- **↓:** −1, or −10 with ○ held; the −10 is undone if it reaches 0 or less. Sound 2. Nothing at 1.
- **△:** the box closes, sound 4.
- **□:** amount = the maximum, sound 3.
- **✕:** the sale or purchase:
  - **Sell:**
    - bits += amount × unit price (capped at 999999);
    - the items are removed;
    - the box shrinks toward the NPC.
  - **Buy / recycle:**
    - with a baby partner the unit price is 90% (integer), and `SHOP_VARIABLE` = amount × the discount (the 0xD line names it);
    - bits −= amount × unit price;
    - the items are given;
    - recycle: the stock slot `getRecycleId(item)` loses the amount;
    - the box shrinks toward owner 0xFD.

  Then:
  - step 7;
  - the bits box redraws;
  - on map 0x83 (`MAIN_D_801345C0`) `playSound(0, 0x17)` (`playShopSoundOnlyInSavannah`).

  There is no other sound on ✕ here.

The line is rewritten every frame the box is open.

### 2.8 "Is it OK? Yes No" (box 3; type 5)

**✕ on a `droppable` row** (`createSingleCardShopMenu`; sound 0xB otherwise):
- the box `createTextbox(3, 0xC1, (−0x38, −0x15, 0x70, 0x2A))` opens from the row, 2 rows;
- its text is MAPHEAD section 0x4D8 line 0 ("Is it OK?\nYes No"), shown in box 3 (no speaker);
- choice = Yes (0);
- sound 3.

**Input:**
- **△:** the box closes, sound 4.
- **←:** Yes, sound 2.
- **→:** No, sound 2.
- **✕:** the box closes.
  - **On Yes:** value 0xFE = the item, trigger 3 unset, step 4, sound 3.
  - **On No:** sound 4.

**Drawing** (`CONFIRM_BOX_LAYOUT` US: x, y, w, u, v; from the box's row):
- the question (0, 0, w 4…), "Yes" and "No" (the `12 × n` cells of row + 0x24);
- the selection cursor at (x + 8 + choice × 47, y + 0x12), 0x28 × 0xE.

### 2.9 The description box (box 3; START in the list)

- The box `createTextbox(3, 0xC1, (−0x84, −0xB, 0x108, 0x16))` opens from the row, 1 row: the item's description (`ITEM_DESCS`), drawn at (x + 6, y + 5) with a shadow.
- **Closing:** ✕, △ or START (once ✕ was released) close it, sound 3.
- **Empty rows:** on an empty row (0xFF) nothing opens, yet the C still plays sound 3.

## 3. Godot design

- **The routine host:** `ScriptRoutines` (`scripts/script/script_routines.gd`), a node under `Systems/ScriptHost`. Its children are the routine nodes, each listing the builtins it runs (`ROUTINES := [0x00, 0x08, 0x0F, 0x23]`) and implementing `start(routine) -> bool` (true: the routine waits) and `tick(routine)`.
  - **Calls:** `ScriptInterpreter._call_routine` asks the host first. A waiting routine gets the C's setup: `active_instruction` = `CALL_ROUTINE`, `state_2` = 0, `textbox_mode` = 0, and the frame ends. `_tick_waiting_instruction` then calls the host's `tick(script_param_1)` each frame.
  - **Unported builtins:** ones without a node keep today's behaviour: reported, they end at once.
  - **Modding:** a mod adds or replaces a builtin by adding a node (`specs/scenes.md`).
- **`scenes/script/shop_routines.tscn`** + `scripts/script/shop_routines.gd`: §2.2–2.5 (0x00, 0x08, 0x0F, 0x23 a no-op). It holds the shops' steps and calls the item menu.
- **`ItemMenu`** (`scripts/ui/item_menu.gd`, a plain class; one instance, `ScriptRoutines.menu`, shared by the routines): the two lists (`ItemMenuBox`: buffer, count, visible rows, rect, top, cursor, row slots), `create` / `tick` / `render`, the rows' strings, the amount box, the Yes / No box and the description box. It works on `TextBoxes` (line buffers, `create_textbox`, `register_textbox`, the pages), `UIBoxes` and `GameState` (bits, items, triggers, recycle stock). Later list types (cards, merit, music, Birdramon) add their row writers here.
- **MAPHEAD lines:** `TextBoxes` gets `show_mapHead_textbox(index, owner, box, section)` and `show_mapHead_selection(...)`. They point `ctx.code` / `ctx.pointer` at the MAPHEAD script's text (`ScriptFiles.script(0)`, the section table) for the call, then put them back, like the C's pointer swap.
- **Shared drawing:** the item icon (`renderItemSprite`, today inside `Inventory`) moves to `MenuDraw.item_icon`, so the inventory and the item menu share it. The same goes for the selection cursor and the separator / inset lines (`renderHorizontalLine`, `renderInsetWithoutBox`).
- **Input repeat:** `setInputRepeatMask` → `Pad.repeat_mask`. The routine restores 0 where the C does.
- **Data:** everything listed in §1 is already ported (`price`, `droppable`, `recyclable_items`, `shops.shopkeepers`, `babies.baby_ids`). "Is the partner a baby" reads `babies.baby_ids`, as the C does: the table is the property.

## 4. Tests (`tests/test_shops.gd`)

Run on a real shop script section: `DG/script_126` section 0x52 (regular and recycle), or a small synthetic script that sets the stock triggers and value 0xFE.
- **Flow:** the greeting, the Buy / Sell / See ya choice, the buy list's rows (names, prices, grey when unaffordable or capped at 99), the bits box text.
- **Buying:**
  - the maximum (99 − owned, bits / price);
  - ↑ ↓ and ○ ±10, □ to max;
  - ✕ takes the bits and gives the items;
  - the baby discount (90%, the 0xD line);
  - the bits box redraws.
- **Selling:** half price, the "－－－－" rows, the items removed, bits capped at 999999.
- **Recycle:** the stock is lowered; at the end the 0xC line, then the farewell.
- **Item picker:** no droppable item → trigger 3 set, value 0xFE = 0xFF; Yes gives value 0xFE = the item and unsets trigger 3; △ with trigger 3 set cancels.
- **Ending:** the script goes on after the routine (`ACTIVE_INSTRUCTION` 0).
- **The description box**, the cursor's scrolling past 6 rows.
- **Unported builtins** still end at once (`test_script.gd` unchanged).

## 5. Open points

- The header sprites' look (`ITEM_MENU_HEADER_UVS` reads SYSTEM_W at v 0xA2 / 0xB0 + …): checked when rendering.
- `CONFIRM_BOX_LAYOUT`'s exact cells: checked against the picture when coding.
- The text of the other shopkeeper sections (0x4C5–0x4CD): read from MAPHEAD, nothing to port.
