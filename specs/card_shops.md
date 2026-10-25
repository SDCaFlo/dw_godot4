# Card shops, the merit shop and Mojyamon's trades

Status (2026-10-25): coded, step 5e-4b (`PLANS.md` 5e-4). Code:
- `scenes/script/card_shop_routines.tscn`, `merit_shop_routines.tscn`, `mojyamon_routines.tscn` (`scripts/script/*_routines.gd`);
- `MenuRoutines` (`scripts/script/menu_routines.gd`), now also the base of `ShopRoutines`;
- `TradeMenu` (`scripts/ui/trade_menu.gd`);
- the card and merit parts of `ItemMenu`;
- `ScriptRoutines.menu`, the one item menu.

Tests: `tests/test_card_shops.gd`. Checks: VERIFY "Card shops, merit shop, Mojyamon".

As built:
- **Row writers by style:** `ItemMenu.row_writers` maps `updateItemMenuStrings`' style to its writer (0 items, 1 cards). `TradeMenu` adds style 4; the jukebox (2) and Birdramon (3) will add theirs.
- **The trade box flips its own page** in its tick, as `tickMojyaTradeMenu` does. Its render (mode 2, no icons) never flips. So ✕ counts only from the frame after the flip (`isXPressedAfterDialogue` sees ✕ released there), as in the original.
- **The trade label** (`TRADE_LABEL`) is drawn into the text area over row 9 on every render, as the C's `drawString`.
- **Card names:** a line like "This is a {Digimon}card." prints the name with no space after it ("Mojyamoncard"), as the C's `strcpy` of the US name does.

Three more `CALL_ROUTINE` builtins on the script item menu of `specs/shops.md` (read that first: the routine host, `SCRIPT_TEXTBOX_MODE`, the MAPHEAD lines, the list box, the amount box and the Yes / No box are described there):
- **0x0E, the card shops:** a pack of 3 random cards, buying a single card, selling cards. Gear Savanna's Market Manager (GIAS06B, script 126) and script 209.
- **0x01, the merit shop:** cards traded for merit points, merit points traded for items. Script 135 (GKYO02) and script 209.
- **0x02, Mojyamon's trades:** 3 item-for-item trades per Mojyamon. Freezeland (FRZL14 and FRZL15, scripts 128 and 129) and script 209.

They add three list types to the item menu (3: buy a card, 4: sell cards, 6: show a card), the merit item list (type 7, whose rows are already ported), and a trade box of their own.

Script 209 has no map in the asset porter's index. It holds the same shops (card, merit, Mojyamon, Birdramon), probably a test or a removed map. It needs no work of its own.

## 1. The C code

| C (US) | What |
|---|---|
| `CALL_ROUTINE` (`script_interp.c:1658`), its tick (`:421–561`) | 0x01, 0x02 and 0x0E wait like 0x08. The tick calls `openMeritShop` (0x01) and `openMojyamonShop` (0x02). For 0x0E it calls `openSellCardMenu` if trigger 3 is set, else `openBuyCardMenu` if trigger 4 is set, else `rollCardPack`. |
| `rollCardPack`, `rollCard`, `showCardTextbox` (`shop/script_menu.c:679`, `:1414`, `:1327`) | the pack (§2.2) |
| `openBuyCardMenu`, `hasAnyCardToBuy` (`:711`, `:1296`) | buying a single card (§2.3) |
| `openSellCardMenu`, `shopFillSellCardList` (`:753`, `:1359`) | selling cards (§2.4) |
| `openMeritShop`, `shopFillMeritItemList`, `createMeritCardTradeDialogue` (`:788`, `:1479`, `:1911`), `readSelectedItemMerit` (`script_common.c:877`) | the merit shop (§2.5) |
| `openMojyamonShop`, `mojyaTradeFillItemList`, `createMojyaTradeMenu`, `setMojyaItemTradedTrigger`, `tickMojyaTradeMenu`, `renderMojyaTradeMenu`, `updateMojyaTradeStrings` (`:1051`, `:1758`, `:1786`, `:1801`, `:2547`, `:2605`, `:2647`) | Mojyamon (§2.6) |
| `createCardMenu`, `tickCardMenu`, `renderCardMenu` (`:1452`, `:1816`, `:1876`), `calculateCardMenuStrings` (`script_common.c:2666`), `renderCardSprite` (`:2416`) | the card list (§2.7) |
| `calculateItemListStrings`, `padWithSpaces` (`script_common.c`, after `:2905`), `itemMenuCursorMoveToTop` / `…Bottom` (`:2858–2885`) | the trade rows (§2.6.2) |
| `createItemMenuAmountBox`, `tickItemMenuAmountBox`, `renderItemMenuAmountBox`, `updateItemMenuAmountBoxString` (`:1964`, `:1457`, `:937`, `:1023`); `createSingleCardShopMenu`, `tickSingleCardShop` (`:2047`, `:1070`) | the shared boxes, with their card branches (§2.8) |
| Data | `CARD_DATA` (`items/card_data`: `digimon`, `rarity` = `spriteId`, `price` = `CARD_PRICES[rarity]`, `sell_price`, `merit`); `ITEM_PARA.meritValue` (`items/item_data.merit`); `MOJYAMON_ITEMS_GIVE` / `GET` (`systems/mojyamon_trades`); the card counts (`GameState.card_count` / `set_card_count`, `getCardAmount` / `setCardAmount`, `script_interp.c:2483`); the card shop's 6 slots (`GameState.state.script.card_shop`, `SCRIPT_STATE_PTR->smth[0..5]`); `MERIT` (`GameState.state.merit`) |
| Text | MAPHEAD sections 0x4D3 (cards), 0x4D4 (merit), 0x4D6 (Mojyamon), 0x4D8 entry 0 ("Is it OK? Yes No"); `TRADE_LABEL` (`text/shop/script_menu.yaml`, US "You have Will trade") |

## 2. Behaviour

### 2.1 How the scripts call them

- **Card shop** (script 126, the same in 209). The script asks what you want, then:
  - **Pack:** `REDUCE_MONEY 500`, builtin 0x0F (the bits box), "Open the pack right away.", triggers 3 and 4 unset, 0x0E, then 0x16.
  - **Single card:** trigger 3 unset, trigger 4 set, 0x0E, then 0x16.
  - **Sell:** trigger 3 set, 0x0E.

  0x16 is `scriptCheckTournamentMedal` (`tournament.c:242`). It awards a medal when its conditions hold, and one of them is "all 66 cards and the game beaten once". It belongs to the tournaments (§5).
- **Merit shop** (script 135): value 0xFE = the NPC, then 0x01.
- **Mojyamon** (scripts 128 / 129): value 0xFE = the NPC; value 249 = the trade set (FRZL14: set 1 or 2 for its two Mojyamon; FRZL15: set 0); then 0x02.

`owner` below is `readPStat(0xFE)`, the NPC. "→ n" means: wait for ✕ on the line, then go to step n (mode 1). "Line n" in §2.2–2.4 is entry n of section 0x4D3.

### 2.2 The pack (0x0E, triggers 3 and 4 unset: `rollCardPack`)

Steps 0, 2 and 3 each roll one card (`rollCard`), show it (`showCardTextbox`) and → 2, 3, 4. Step 4: `ACTIVE_INSTRUCTION` = 0. The script has already taken the 500 bits.

**`rollCard`:**
- `r = randomLimit(100)`. The rarity class is 0 for r = 0, 1 for 1–4, 2 for 5–19, 3 for 20–49, 4 for 50–99.
- The cards of that class are collected in id order (ids 0–0x41, `spriteId == class`). One of them is picked with `randomLimit(count)`.

**`showCardTextbox`:** value 249 holds the card.
- `n` = how many of that card you hold.
- **The line:**

| You hold | Line | Text |
|---|---|---|
| none, class 0 | 2 | "This is a {Digimon}card." |
| none, class 1 | 3 | "This is a {Digimon}card." |
| none, class ≥ 2 | 4 | "This is a {Digimon}that I don't have yet." |
| 1–5 | 5 | "A {Digimon}card!" |
| 6 or more | 6 | "Another {Digimon}card." |

- If `n < 9`, the count becomes `n + 1`. A card already held 9 times is shown, but not added.
- Value 249 = the card's Digimon id (the line's `{digimon_name 249}`). The line is the tamer's (owner 0xFD), in box 0.

### 2.3 Buying a single card (0x0E, trigger 4 set: `openBuyCardMenu`)

- **0:** the left list: 6 rows, scroll bar at (0xB2, 0x18), 6 × 0x5A. `hasAnyCardToBuy` fills it from the shop's 6 slots:
  - each row is (card, available), or (0xFF, 0) for an empty slot;
  - available = 1 when `CARD_PRICES[rarity] ≤ MONEY` and you hold fewer than 9 of the card;
  - the row count is always 6.

  If any slot holds a card: → step 3 at once (mode 0). Else: line 1 ("We don't have any more."), → 2.
- **2:** free the list; `ACTIVE_INSTRUCTION` = 0.
- **3:** repeat on (0x5000), type 3, `createCardMenu` (§2.7), line 0 ("Look what we got today.") shown without waiting (mode 3); step 1.
- **4:** repeat off, box 1 closes; → 2.

So the routine sells **one card per call**. The script then says "You want something else?" and asks again.

**In the list:**
- **✕** opens "Is it OK? Yes No" (§2.8) if the row has a card and available ≠ 0, else sound 0xB.
- **Yes** (`tickSingleCardShop`):
  - the card count + 1;
  - bits −= `CARD_PRICES[rarity]`;
  - the slot becomes empty: `smth[box->cursor]` = 0xFF (the cursor, not top row + cursor; with 6 rows in a 6-row box they are the same);
  - the bits box updates; the Savannah sound; → step 4.
- **△** → 4, sound 4.

There is no discount and no "Thanks" line.

### 2.4 Selling cards (0x0E, trigger 3 set: `openSellCardMenu`)

- **0:** the left list: 6 rows, scroll bar at (0xD2, 0x18). `shopFillSellCardList` makes one row per card id 1–0x40, in id order:
  - (card, count) for a card you hold;
  - (0xFF, 0) for one you don't. It is an empty row that still takes its place.

  → 3 at once, whatever the result (even holding no cards).
- **2:** free the list; `ACTIVE_INSTRUCTION` = 0.
- **3:** repeat on, type 4, `createCardMenu` (box origin: the tamer), line 8 ("Which card do you want to sell?"), mode 3.
- **4:** repeat off, box 1 closes; → 2.

**In the list:**
- **✕** opens the amount box (§2.8): unit price `CARD_PRICES[rarity] >> 1`, at most the count you hold.
- **Confirming:**
  - bits += amount × unit price, capped at 999 999;
  - the card count −= amount;
  - the box closes towards owner 0xFE; the bits box updates; the Savannah sound; → 4.
- **△** → 4.

One sale per call.

### 2.5 The merit shop (0x01: `openMeritShop`)

The lines here are entries of section 0x4D4.
- **0:** two lists:
  - left (cards): 6 rows, scroll bar at (0x9A, 0x18);
  - right (items): 6 rows, scroll bar at (0xB2, 0x18).

  Line 0 ("You want 'Merit' too? What are you going to do?"), → 3.
- **2:** free both; `ACTIVE_INSTRUCTION` = 0.
- **3:**
  - repeat off;
  - `createShopBitsBox(0)`: the box shows the shopkeeper line 7, "Points {merit}";
  - choice line 1 as the tamer's, 3 choices ("Show a Digimon card / Use Merit points / See ya") → 4 / 5 / 6.

  The C passes a fresh `selection` = 0, so the cursor starts at the top each time, unlike the shop's `SHOP_ACTION_SELECTED`.
- **4:** repeat on, type 6, `shopFillSellCardList` (§2.4, left), `createCardMenu`, line 5 ("What did you bring?"), mode 3.
- **5:** repeat on, type 7, `shopFillMeritItemList` (right), `createItemMenu` (`specs/shops.md` §2.6), line 6 ("What do you want?"), mode 3.
- **6:** the bits box closes; → 2. No new line: mode 1 waits for ✕ on the box as it is.
- **Showing a card** (type 6, ✕: `createMeritCardTradeDialogue`). If the row has a card and its count ≠ 0:
  - `SHOP_ITEM_TYPE` = the card; `SHOP_VARIABLE` = its `meritValue`;
  - line `rarity + 7` as owner 0xFE: 7 / 8 "This is very rare! … {shop_value}points.", 9 "very good stuff", 10 "very common", 11 "This isn't good. …";
  - → 7, sound 3.

  Else sound 0xB.
- **7:** repeat off; choice line 2 ("Give it / Cancel") → 8 / 9.
- **8:**
  - box 1 closes;
  - merit += `SHOP_VARIABLE`, capped at 9999;
  - the points box updates;
  - the card count − 1;
  - → 3 at once (mode 0), the Savannah sound.
- **9** (Cancel), **0xD** (Cancel on an item): box 1 closes; → 3 at once.
- **0xA** (△ in either list): repeat off, box 1 closes; → 3 at once.
- **Picking an item** (type 7, ✕: `readSelectedItemMerit`). If the row's item is available:
  - `SHOP_VARIABLE` = its merit price;
  - → 0xB at once (mode 0), sound 3.

  Else sound 0xB. There is no amount box: one item per trade.
- **0xB:** repeat off; choice line 3 ("OK / Cancel") → 0xC / 0xD. The list stays open behind it.
- **0xC:**
  - box 1 closes;
  - merit −= `SHOP_VARIABLE`;
  - the points box updates;
  - `giveItem(item, 1)`;
  - → 3 at once, the Savannah sound.

Line 4 ("Are you sure?") is not used.

**`shopFillMeritItemList`:** one row for each item 0–0x7F whose `meritValue` ≠ 0, in id order: (item, available). Available = 1 when:
- `meritValue ≤ MERIT`, and
- the inventory has a free slot, or a slot holding the item with fewer than 99.

The rows (type 7: name, the merit price in 4 digits, header 2 "MERIT") are already ported (`ItemMenu._row_string`).

### 2.6 Mojyamon (0x02: `openMojyamonShop`)

The lines here are entries of section 0x4D6.
- **0:**
  - both lists are allocated with 3 rows and no scroll bar (rect 0);
  - `mojyaTradeFillItemList` fills them (§2.6.1);
  - value 249 = 0xFF ("nothing picked");
  - line 8 ("I'm a collector. If you got a thing I want, I'll trade."), → 3.
- **2:** free both; `ACTIVE_INSTRUCTION` = 0.
- **3:** repeat on, `createMojyaTradeMenu` (§2.6.2), line 9 ("What will you give me?"), mode 3.
- **4:** repeat off; choice line 0xC ("Yeah / Well..., no") → 5 / 6.
- **5:**
  - box 1 closes;
  - `giveItem(get, 1)` for the row's item from the right list;
  - **if that worked:** `removeItem(value 249, 1)` (the item you give), the trade's trigger (below), line 0xD ("Thanks!");
  - **else:** line 0xE ("Too many Items.");
  - → 2, the Savannah sound.
- **6** (△ in the list, or "Well..., no"): repeat off, box 1 closes, line 10 ("I'll trade all the time, so bring whatever you got."), → 2.

Each call makes at most one trade, and "no" ends the talk.

**The traded triggers (`setMojyaItemTradedTrigger`):**
- trigger `set × 3 + row + 5` is set;
- if all of triggers 5–13 are then set, trigger 14 is set too.

They only mark the row (the "－" below); a trade can be made again.

#### 2.6.1 The trade list (`mojyaTradeFillItemList`)

`ITEM_MENU_TYPE` is set to `set × 3` (value 249 × 3), so the C reuses it as the trade set's base. Mojyamon's box has its own tick and render, which never read it as a list type.

For `i` in 0–2:
- left row `i` = `GIVE[base + i]`, | 0x80 when you hold at least one;
- right row `i` = `GET[base + i]`.

Both lists have 3 rows.

#### 2.6.2 The trade box (`createMojyaTradeMenu`, `tickMojyaTradeMenu`, `renderMojyaTradeMenu`)

- **Box 1:** flags 0xE1, rect (−88, −80, 223, 83) from the NPC's origin; rows 9…12 (`registerTextbox(1, 9, 4, 1, 0)`). The left list's row slots are text rows 10–12.
- **`updateMojyaTradeStrings`:**
  - MAPHEAD line 0xF ("I want You have") is shown in box 1 as owner 0xFF;
  - the box's write count is taken back;
  - the bytes at offset 20 of text rows 9 and 13 are set to 0x0D;
  - the trade rows are written (style 4).

  In the US render nothing reads row 9: the label comes from `TRADE_LABEL`. The JP leftover is kept for the write count (§5).
- **A row (`calculateItemListStrings`, US):**
  - `01 07`;
  - "－" (0x817C) if the trade's trigger is set, else a full-width space (0x8140);
  - `01 01` (available) or `01 03` (red), the give item's name;
  - `8 − len / 2` full-width spaces (`len` = the name's bytes);
  - `0F 00 01 01`, the get item's name;
  - the terminator.
- **Tick:** only when box 1's page is not busy, boxes 0 and 1 are open, ✕ was released (`isXPressedAfterDialogue`), and value 249 = 0xFF.
  - **✕ on an available row:** value 249 = the give item; line 0xB ("You'll really give me {item}?"), → 4, sound 3. On a red row: sound 0xB.
  - **△:** → 6, sound 4.
  - **↑ / ↓:** `itemMenuCursorUp` / `Down` (style 4). With R1: `itemMenuCursorMoveToTop` / `…Bottom` then `updateMojyaTradeStrings`.
- **Render (US):**
  - a horizontal line at (4, 0x15), 0xD7 wide;
  - `TRADE_LABEL` drawn into the box's text area at y 0x6C (+ the back page), shown in two parts: 0x42 px at (0x14, 5) ("You have") and 0x4E px at (0x7A, 5) ("Will trade");
  - the cursor at (5, cursor × 0x12 + 0x19), 0xD4 × 0x12;
  - the rows at (8, 0x1B), with no icons (mode 2).

### 2.7 The card list (box 1, types 3 / 4 / 6: `createCardMenu`, `tickCardMenu`, `renderCardMenu`)

- **The box:** like `createItemMenu`: flags 0xF1, `ITEM_MENU_POS[type]`, rows 9…14, `SHOP_VARIABLE` = 0.
  - Origin: the tamer for type 4, else owner.
  - The list is always the left one (`getItemMenuFromType`: only 1, 5 and 7 use the right).
- **Tick:** like `tickItemMenu`, but without the `SCRIPT_STATE_2 == 1` check and without START.
  - **✕:** type 3 → Yes / No (§2.3); type 6 → the merit trade (§2.5); type 4 → the amount box (§2.4).
  - **△:** type 6 → 0xA, else → 4; sound 4.
  - **↑ / ↓** with repeat, R1 for the top / bottom: style 1.
- **A row (`calculateCardMenuStrings`, US):** for a card:
  - the colour byte after `01`:
    - type 3: 7 if available and not held yet, 1 if available, 3 (red) if not;
    - types 4 and 6: always 1;
  - the Digimon's name, `17 00 0F 00`;
  - type 3: the price in 4 digits;
  - type 4: half the price in 4 digits, `0F 00`, the count in 2 digits;
  - type 6: the count in 2 digits.

  An empty row is only the terminator.
- **Render:**
  - header 0 at (8, 5);
  - type 6: header 3 at (0x80, 5);
  - else: header 1 at (0x80, 5), and for type 4 also header 3 at (0xB6, 5);
  - the scroll bar;
  - the cursor (`SELECTION_CURSOR_WIDTHS[type]`);
  - the rows (mode 1). The icon is `renderCardSprite(rarity)` at (8 + 2, row + 0x12 + 2): SYSTEM_W, u = rarity × 12, v = 0x1C0, 12 × 12, CLUT (96, 493).

### 2.8 The shared boxes with cards

- **The amount box, `ITEM_MENU_TYPE ≥ 3`** (type 4):
  - price = `CARD_PRICES[rarity] >> 1`; max = the row's count (not limited by bits or room);
  - the line holds the Digimon's name;
  - the icon is the card sprite at (+2, +2);
  - confirming does §2.4 and → 4 instead of 7.
- **"Is it OK? Yes No", `ITEM_MENU_TYPE ≠ 5`** (type 3):
  - the box opens when the row's second byte ≠ 0 (type 5 checks bit 0x80);
  - Yes buys the card (§2.3).

## 3. Godot design

- **One item menu for all routines.** The C's item menu is global: the bits box opened by builtin 0x0F has to see the card shop's "update the bits box". So `ScriptRoutines` makes the one `ItemMenu` (`host.menu`) in `configure`, and every routine node uses it. `ShopRoutines` stops making its own.
- **Routine nodes** (children of `Systems/ScriptHost/Routines`, one scene each, as `shop_routines.tscn`):
  - `scenes/script/card_shop_routines.tscn` + `scripts/script/card_shop_routines.gd`: 0x0E, §2.2–2.4;
  - `scenes/script/merit_shop_routines.tscn` + `merit_shop_routines.gd`: 0x01, §2.5;
  - `scenes/script/mojyamon_routines.tscn` + `mojyamon_routines.gd`: 0x02, §2.6.

  Helpers shared with `ShopRoutines` (`_line`, `_then`, `_choice`, `_close_list`) move to a small base script `scripts/script/menu_routines.gd` (`class_name MenuRoutines`). The three nodes and `ShopRoutines` extend it. `_choice` gets the `section` and `keep` arguments.
- **`ItemMenu`:**
  - adds `TYPE_CARD_BUY` 3, `TYPE_CARD_SELL` 4, `TYPE_CARD_SHOW` 6;
  - adds `fill_card_shop()`, `fill_cards()`, `fill_merit()`, and `create_card_menu()` / `tick_card_menu` / `render_card_menu`;
  - adds a `style` argument to `update_strings` and the cursor functions: 0 items, 1 cards, 4 trades. They call the matching row writer, as `updateItemMenuStrings` does;
  - adds the card branches of the amount box and the Yes / No box;
  - draws the card icon (SYSTEM_W through `MenuDraw.sprite`).
- **Mojyamon's box:** `scripts/ui/trade_menu.gd` (`class_name TradeMenu`, RefCounted), on the item menu's list boxes and row helpers. It keeps `trade_base` (the C's `ITEM_MENU_TYPE` = set × 3) as a field of its own, instead of overwriting the list type.
- **Properties, not id ranges** (`specs/content.md`):
  - the sell / show list is "every card that has a price, in id order" (the C's ids 1–0x40; cards 0 and 0x41 are the class-5 tamer placeholders, which have none);
  - the roll picks among the cards whose `rarity` is the rolled class;
  - the merit list is "every item with `merit` > 0, in id order";
  - Mojyamon's trades come from `systems/mojyamon_trades`, by `set`.
  - Constants that stay code, as in the C: the roll thresholds, the limit of 9 of a card from shops and packs (`CARD_SHOP_LIMIT`), the merit cap of 9999, and the traded triggers 5–14.
- **Random:** `Rng.random_limit` (`scripts/core/rng.gd`). Tests seed it.

## 4. Tests (`tests/test_card_shops.gd`)

The same harness as `test_shops.gd` (synthetic script: set the values and triggers, `CALL_ROUTINE`, then a marker value).

- **Pack:**
  - a seeded roll gives 3 lines from 0x4D3 entries 2–6, the counts + 1, and value 249 = a Digimon id;
  - a card held 9 times stays at 9 (line 6);
  - every rolled card has the rolled class.
- **Single card:**
  - the rows from the 6 slots (an empty slot is a blank row; red when too dear or held 9 times; colour 7 when not held);
  - ✕ Yes: bits − price, count + 1, slot empty, the script goes on;
  - all slots empty: line 1, then the script goes on.
- **Selling:** 64 rows with blanks for cards not held; the amount box's max = the count; selling 2 adds 2 × half the price and takes 2 cards.
- **Merit:**
  - the choice's three branches;
  - showing a card: line `rarity + 7`, Give it: merit + value (cap 9999), count − 1, back at the choice;
  - an item: merit − price, the item given;
  - △ in each list goes back to the choice; See ya ends.
- **Mojyamon:**
  - set 1's rows (red without the item, "－" once traded);
  - Yeah: the items swapped, trigger `3 + row + 5` set, "Thanks!";
  - a full inventory: "Too many Items." and nothing swapped;
  - "Well..., no" and △ end the talk;
  - all of triggers 5–13 → 14.
- **Shared menu:** a 0x0F bits box opened before 0x0E updates after a card is bought.

## 5. Open points

- **0x16 `scriptCheckTournamentMedal`** stays unported until the tournaments. Until then, the "all cards and the game beaten" medal is not awarded after a card shop visit.
- **The card shop's stock** is not this step's: `dailyPStatTrigger` (`script_common.c:1399`, already ported in `Clock`) re-rolls the 6 slots each new day, and `GameState.new_game` starts them at cards 0x3A–0x3F. A bought card's slot stays empty until the next day.
- **`updateMojyaTradeStrings`' row 9 / 13 writes** in US are JP leftovers (the label rows). The port does them for the same buffer state. Nothing draws them.
- **`padWithSpaces` pads `8 − len / 2` full-width spaces**, `len` in bytes. US names are 1 byte a character, so "Giant Meat" gets 3. A name over 16 bytes would make `used` negative and loop for a long time in US. The port pads 0 instead. The test checks that no Mojyamon give item is over 16 bytes.
