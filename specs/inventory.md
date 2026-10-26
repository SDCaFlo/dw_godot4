# Items: the inventory and feeding

Status (2026-10-25): coded, step 5e-2 (`PLANS.md` 5e): `ItemUse` (`scripts/systems/item_use.gd`), `scenes/ui/inventory.tscn` (`scripts/ui/inventory.gd`), the feeding scene (`Partner` state 5, `Tamer.held_item`), data porter `item_data.feeding` / `item_effects.requires_level`; `tests/test_inventory.gd`; VERIFY "Items".

The △ menu's ITEM icon opens the inventory: the item list with Use / Move / Sort / Drop. In the field, Use hands the item to the partner: the partner comes up, takes it or refuses it, and the item's effect runs (food, recovery, chips, medicine…). This step ports the inventory, the feeding scene, the refusal rules and the field effects of every item the field can use. Throwing an item in battle is the battle step's (5d).

## 1. The C code

| C (US) | What |
|---|---|
| `tickTriangleMenu` state 2, `handleGameMenuSelection` case 1 (`game_menu.c:1352`, `:2171`) | the menu hands over to the inventory |
| `addInventoryUI`, `tickInventoryUI`, `closeInventoryBoxes`, `closeInventoryBoxes2` (`inventory.c:324`, `:336`, `:463`, `:651`) | the inventory object and its actions |
| `createInventoryView`, `tickInventoryTop`, `renderInventoryTop`, `renderInventoryBottom`, `updateItemDescription` (`:479`, `:534`, `:566`, `:634`, `:830`) | the list (box 0) and the description (box 1) |
| `createItemOption`, `tickItemOption`, `renderItemOption`, `getItemOptionColor`, `selectOptionMenu`, `selectRegularInventory` (`:268`, `:681`, `:721`, `:209`, `:879`, `:924`) | the Use / Move / Sort / Drop box (box 2) |
| `createSortOption`, `tickSortOption`, `renderSortOption`, `selectSorting`, `sortItems` (`:699`, `:740`, `:745`, `:862`, `:947`) | sorting (box 3) |
| `createDropItemConfirmBox`, `tickDropItemConfirmBox`, `renderDropItemConfirmBox`, `selectDropItem` (`:770`–`:877`) | dropping (box 3) |
| `moveItem`, `drawInventoryText`, `drawInventoryTextLine` (`:847`, `:255`, `:304`) | moving, the names in the text area |
| `updateInventoryInputRepeatCounter`, `isInventoryButtonPressed`, `tickInventoryOptionSelector` (`:1005`–`:1034`) | held buttons repeat |
| `startFeedingItem`, `removeOneSelectedItem`, `renderFeedingItem` (`game_menu.c:2228`–`:2258`) | the hand-over |
| `partnerTickFeedItem` (`partner.c:425`), `checkEatDistance` (`partner.c:1094`), `removeTamerItem` (`item.c:2677`) | the feeding scene |
| `partnerWillRefuseItem` (`partner_impl.c:1431`), `partnerHandleFoodFeed` (`:1615`) | refusing, hunger |
| `ITEM_FUNCTIONS` and the handlers (`item.c:1932`, `:2190`–`:2386`, `:2685`–`:3060`) | the effects (`data_porter/specs/items.md` §2) |
| `renderItemSprite`, `setItemTexture`, `renderItemAmount`, `renderSelectionCursor` (`utils2.c:269`, `:298`, `:207`, `:232`) | drawing helpers |
| Data: `INVENTORY` (`specs/game_state.md`), `ITEM_PARA` (`items/item_data`), `item_effects`, `healing_values`, `ITEM_SORT_ORDER` (`items/sort_orders`), `ITEM_TAKE_DISTANCE` (`digimon/item_take_distance`), `EVOLUTION_ITEM_TARGET` (`evolution/item_targets`); texts `text/main/inventory.yaml`, `ITEM_NAMES`, `ITEM_DESCS` | |

## 2. Behaviour

### 2.1 From the △ menu to the inventory

- ✕ on ITEM (`handleGameMenuSelection` case 1): menu state 2 and `drawInventoryText` (below).
- Menu state 2 (`tickTriangleMenu`): close box 0 (`closeUIBoxIfOpen`); once it is closed (frame 0), `addInventoryUI` and the menu object idles (state −1).
- `addInventoryUI`: unless already open, box 0 free (state 0) and the tamer holds no item: the inventory object starts with action 1.
- **Back:** △ on the list (action 2) closes boxes 1 and 0 (`closeInventoryBoxes2`). Once box 0 is closed (frame 0): `closeInventoryBoxes` (all boxes, the object), then `closeTriangleMenu` + `addGameMenu` (the △ menu opens again, from Items), the tamer's animation 0.
- `IS_IN_MENU` stays 1 the whole time, and game time stays stopped (`specs/game_menu.md` §2.6).

### 2.2 `drawInventoryText` (the text area)

- Clear the text area.
- For each filled slot i: `names[i] = i` and the item's name drawn at `((i & 1)·0x60, (i / 2)·0xC)`. So slot i's name sits in the text area at that cell, and the list renders it from there.
- The 4 option labels (`ITEM_MENU_LABELS`: Use, Move, Sort, Drop) at `(0xC0, i·12)`.
- `names[]` is that drawing cache: moving and sorting swap it with the items (`specs/game_state.md`: not saved; the port recomputes it).

### 2.3 The inventory object (`tickInventoryUI`)

Every frame (field: `GAME_STATE` 0; the battle's `currentCommand` test is the battle step's):

1. **✕ pressed this frame** (`polled & ~polled_previous & CONFIRM`):
   - box 3 open: sort open → `selectSorting`, else → `selectDropItem`;
   - box 2 open → `selectOptionMenu`;
   - else → `selectRegularInventory`.
2. **△ pressed this frame:**
   - box 3 open: sort → action 9, drop → action 15 (close box 3);
   - box 2 closed: moving an item (box 0 in state 4) → sound 3, box 0 back to state 1, action 0 (move cancelled); else box 1 open → action 2 (back to the menu);
   - box 2 open → action 4 (close box 2).
3. **The action** (`INVENTORY_ACTION`):

| Action | What |
|---|---|
| 1 | `createInventoryView`; the tamer's animation 4 (unless already playing) |
| 2 | back to the menu (2.1) |
| 3 | `createItemOption` (open box 2) |
| 4, 6 | close box 2 |
| 5 | Use: close box 2; once it is closed, close boxes 1 and 0; once box 0 is free: `startFeedingItem(item)`, action 0 |
| 7 | Drop, confirmed: close box 3, then box 2; then action 0 and the whole slot is removed (`removeItem(type, amount)`) |
| 8 | `createSortOption` (open box 3) |
| 9, 15 | close box 3 |
| 11–13 | after a sort: close box 3, then box 2, then action 0 |
| 14 | `createDropItemConfirmBox` (open box 3) |

### 2.4 The list (box 0) and the description (box 1)

- **`createInventoryView`:** once box 0 is free (frame 0): pointer, scroll offset 0; box 0 opens animated from the tamer's screen point:
  - rect (−0x98, −0x68, 0x130, h): h = 0x6E for a 10-slot inventory, else 0xB6;
  - colour 0, `FEATURE_HALF_FILL`, plus `FEATURE_SCROLL_BAR` above 10 slots (visible rows 9, total rows 10 for 20 slots, 15 for 30; 5 rows for 10 slots);
  - once box 0 is open, box 1 opens: (−0x98, 0x4D, 0x130, 0x1C), colour 0, half fill, from a 16 × 16 square at box 0's (x + 8, y + 0xE); no tick, `renderInventoryBottom`.
- **`tickInventoryTop`** (box 0's tick), while box 2 is closed and box 1 open; up / down with repeat, left / right on this frame's press only:
  - up: pointer − 2 if ≥ 2; down: + 2 if < size − 2; left: − 1 on an odd slot; right: + 1 on an even slot; each move sound 2;
  - scroll: if pointer < offset·2 → offset − 1; if pointer > (offset + visible − 1)·2 + 1 → offset + 1.
- **Held buttons** (`isInventoryButtonPressed`): pressed this frame, or held for 11 frames and more (a counter of frames with the pad unchanged; any change resets it).
- **`renderInventoryTop`:** from slot offset·2, 10 cells (10-slot inventory) or 18, two columns:
  - cell i at column x + (i & 1 ? 0x9A : 0xA), row y + 8 + (i / 2)·0x12, where (x, y) is box 0's final rect;
  - the item's icon (`renderItemSprite`: 16 × 16 from ITEM.TIM, its palette `icon_clut`, 15 texels on the last row / column);
  - its name from the text area cell `names[slot]`, 0x60 × 0xC at x + (0xAD / 0x1D), y + 0xA + row·0x12, colour `usable + 5` (field 5, battle 6, both 7) or 8 (none), shadowed;
  - its amount (`renderItemAmount`, 2 digits, colour 0) at x + (0x113 / 0x83), y + 0xC + row·0x12;
  - moving: the source cell framed by two 3-point lines in colour 0x5D4AF1 (x + (0x97 / 7), y + 7 + row·0x12, 0x8A × 0x12);
  - the selection cursor (`renderSelectionCursor`, `PsxDraw.selection_cursor`) on the pointer's cell, 0x8A × 0x12;
  - the box's scroll bar follows the offset (`box.rowOffset`).
- **`renderInventoryBottom`:** for a filled slot: when the pointer changed, `updateItemDescription` (clear text-area (0, 0xB4, 0xFC × 0xC), draw `ITEM_DESCS[item]` there); render that region at (box 1 x + 0x1A, y + 8), colour 9, shadowed.

### 2.5 The options (box 2)

- **`createItemOption`** (action 3, box 1 open, box 2 free): selection 0 (Use); box 2 opens at the cell: x = box 0 x + (odd ? 0x9A : 0xA), y = box 0 y + 0x18 + row·0x12 for rows 0–4, else box 0 y + 0x20 + (row − 6)·0x12; 0x3A × 0x54, colour 1, features 0, from the cell (x − 3, box 0 y + 7 + row·0x12, 0x8A × 0x12).
- **`tickItemOption`:** while box 3 is closed: up / down with repeat over the 4 options, sound 2.
- **`renderItemOption`:** the 4 labels (text area (0xC0, i·0xC), 0x24 × 0xC) at (x + 0xC, box y + 8 + i·0x12) in `getItemOptionColor(i)`; the cursor (x + 9, y + 6 + sel·0x12, 0x28 × 0x10).
- **`getItemOptionColor`:** Move, Sort: 9. Use: 9 if the item can be used here (field: `usable` field or both), else 0xA (grey). Drop: 9 if `droppable`, else 0xA (and 0xA in battle). An empty slot: 0xA for Use and Drop.
- **`selectOptionMenu`** (✕ in box 2, not while sorting, box 3 closed):
  - **Use:** a filled slot usable here → action 5;
  - **Move:** action 6, `ITEM_MOVE_SOURCE` = pointer, box 0 → state 4 (it stays open, box 2 closes);
  - **Sort:** action 8;
  - **Drop:** in the field, a filled droppable slot → action 14.
  - A grey option does nothing (no sound).
- **`selectRegularInventory`** (✕ on the list, not while sorting or using, box 2 closed):
  - box 0 free → action 1;
  - moving (action 6): sound 4, box 0 back to state 1, action 0, `moveItem` (swap the pointer's slot and the source's: item, amount, name cell; redraw the description if the slot isn't empty);
  - else (action < 5, the tamer holds nothing, box 1 open) → action 3.

### 2.6 Sort and drop (box 3)

- **`createSortOption`** (box 2 open, box 3 free): draw `STR_BATTLE`, `STR_RAISE`, `STR_BASIC` at (0xC0, 0x30 / 0x3C / 0x48); selection 0; box 3 opens at box 2's right edge (box 2 x + w, box 2 y, 0x48 × 0x42), colour 1, features 0, from the Sort row (box 2 x + 9, y + 6 + sel·0x12, 0x28 × 0x10). Its tick: up / down with repeat over 3, sound 2. Its render: the 3 labels (text area (0xC0, 0x30 + i·0xC), 0x30 × 0xC, colour 9) and the cursor (0x36 × 0x10).
- **`selectSorting`:** unless already done with this mode, `sortItems(11 + selection)`, action 11–13.
- **`sortItems(mode)`:** the 6 groups (`sort_category` 0–5), each sorted by item id, laid out in the order `ITEM_SORT_ORDER[mode − 11]`; then, slot by slot, the inventory is brought to that order by swapping (item, amount, name cell). Empty slots end up last.
- **`createDropItemConfirmBox`** (box 2 open, box 3 free): draw `STR_YES` (0xC5, 0x54), `STR_NO` (0xC0, 0x60), `STR_ARE_YOU_SURE` (0, 0xC0); selection 1 (No); box 3 at (−0x40, −0x26, 0x80 × 0x35), colour 1, from the Drop row. Its tick: left / right with repeat, sound 2. Its render: the question (text area (0, 0xC0, 0x6C × 0xC) at (−0x34, −0x1E)), Yes / No at (box x + 0x12 + i·0x34 + 5, y + 0x20), the cursor (box x + 0x12 + sel·0x35, y + 0x1E, 0x2A × 0x10).
- **`selectDropItem`:** Yes → action 7 (the whole slot goes), No → action 15.

### 2.7 Feeding: the hand-over (`startFeedingItem`)

If the tamer holds nothing: `TAMER_ITEM.type` = the item, tamer state 6, partner state 5, the △ menu object goes, `IS_IN_MENU = 0`, game time runs. (Box 0 is already closed: action 5.)

### 2.8 The feeding scene (`partnerTickFeedItem`, partner state 5)

`checkEatDistance(d)`: true when the tamer–partner ground distance ≤ d·200/10 + 160, with d = `ITEM_TAKE_DISTANCE[partner type − 1]`.

- **0:** if already within the distance → sub-state 1, else 2. Partner animation 2 (walk), its rotation turned by half a turn (`rotation.vy += 2048`), `tickPartnerWaypoints`.
- **1** (too close): the tamer looks at the partner; once out of the distance → 3. (It walks away first.)
- **2** (too far): the tamer and the partner look at each other; once within the distance → 3.
- **3:** the partner looks at the tamer; tamer animation 5 (holds the item out), sound 12, partner animation 0; the item is drawn in the tamer's hand (`renderFeedingItem`: the item icon, as on the ground, at the tamer's bone 9); → 4.
- **4:** once the tamer's animation frame > 7: `partnerWillRefuseItem()`: takes it → partner animation 8 (eats), sub-state 5; refuses → animation 13, sub-state 7.
- **5:** on the eating animation's frame 11 the item disappears; on frame 15 the tamer's animation 0; at its end → 6.
- **6** (same frame, the animation is over): partner state 1, tamer state 0, the camera follows; the item's handler (`ITEM_FUNCTIONS[type]`, 2.10); one of the item removed from the slot under the inventory pointer (`removeOneSelectedItem`); the tamer's item cleared; `partnerHandleFoodFeed(type)`.
- **7** (refused): at the end of the refusal animation the item disappears, partner animation 0, tamer animation 4; → 8.
- **8:** at the end of the tamer's animation: tamer state 0, partner state 1, the tamer's item cleared, the camera follows. The item stays in the bag.

### 2.9 Refusing (`partnerWillRefuseItem`) and hunger (`partnerHandleFoodFeed`)

`partnerWillRefuseItem`, in this order (`refusedFavFood` = 0 first; `chance` = random 0–9):
1. Key items (0x73–0x7C except 0x79 / 0x7A) and the passive chips (0x21–0x25): refused.
2. Evolution items (0x47–0x72, 0x7D–0x7F):
   - 0x7E: refused unless the partner is a Rookie (level 3); 0x7D, 0x7F: refused unless it is a Champion (level 4);
   - the others: refused when the target's level (`ITEM_EVOLUTION_TARGET`) equals the partner's, the partner's + 2, or the partner's − 1.
3. `ITEM_SCOLD_FLAG == 2` (a scold after a refusal, `specs/game_menu.md` §2.5): flag 0, taken.
4. Non-food items below 0x26: refused when `random(100) < 110 − (discipline + random(10) + 10)`, which also sets `ITEM_SCOLD_FLAG = 1` (a scold now counts more and makes it take the next item).
5. Not hungry, the favourite food, and `chance < 2` (20 %): refused (`refusedFavFood = 2`). (The C then sets `ITEM_SCOLD_FLAG = 1` only if hungry, which can't happen on this path.)
6. Else taken.

- **US macro:** `ITEM_EVOLUTION_TARGET(item)` is `(&ITEM_CLUT_DATA[0x39])[item]` in US, which reads past `ITEM_CLUT_DATA[128]` into the table that follows, `EVOLUTION_ITEM_TARGET` (0x39 + 0x47 = 0x80): the same values as `EVOLUTION_ITEM_TARGET[item − 0x47]`.

`partnerHandleFoodFeed(type)` (US = JP_TRIAL and later):
- **hungry** (`condition & 4`): only food (0x26–0x46, 0x79, 0x7A) counts:
  - energy ≥ `energyThreshold` (full): happiness + 5, discipline + 1, not hungry, `setFoodTimer`, starvation timer 0;
  - the favourite food, or full: partner animation 0xB (happy).
- **not hungry:** food: happiness − 3, discipline − 2 (fed while not hungry); anything else: nothing.

### 2.10 The effects in the field (`ITEM_FUNCTIONS`, `data_porter/specs/items.md` §2)

Field (`GAME_STATE` 0) branches only; the values come from `item_effects` / `healing_values`.

| Items | Handler | Field effect |
|---|---|---|
| 0–3 | `handleHPHealingItem` | unless HP is 0: current HP + `HEALING_VALUES[id]`, capped at max HP; the healing particles |
| 4–6 | `handleMPHealingItem` | unless HP is 0: current MP + `HEALING_VALUES[id − 4]`, capped |
| 7 | `handleDoubleFloppy` | unless HP is 0: HP + 1500, MP + 1500, capped |
| 9 | `handleStatusItems` | (the battle status cure is battle only) then as 7 |
| 12 | `handleRestore` | (a partner at HP 0 plays animation 0x2C) HP + 9999, capped |
| 13, 14 | `handleStatusItems` | unless HP is 0: `handleMedicineHealing(3, 2)` / `(3, 10)`: injured → cured (random(3) < 3: always), injury timer 0; sick → cured when random(10) < 2 / 10, sickness and area-effect timers 0 |
| 22 | `handleChips` (Auto Pilot) | while no script runs: the tamer's item cleared, script section 0x4DD of script 0 |
| 23–31 | `handleChips` | permanent stats + `values` (HP / MP capped at 9999, others 999); lifetime − 24 (not below 0) and `addTamerLevel(10, −1)` for 29–31 |
| 32 | `handleChips` (Port. potty) | poopy → poop level = `poopTimer`, not poopy, `handlePoopWeightLoss` |
| 33–37 | (no case) | nothing (passive items; refused anyway, 2.9) |
| 38–70, 121, 122 | `handleFood` | the values; favourite food: energy × 1.4, happiness + 2; then `addEnergy` (cap `energyCap`), `reduceTiredness` (≥ 0), `addHappiness` / `addDiscipline` (≤ 100), `addWeight` (1–99), poop level − 1, `setTrainingBoost(flag, value, duration)` (**always**, so a food without a boost clears a running one), `handleItemSickness`, lifetime + `lifetime`, permanent / current HP and MP and stats with their caps |
| 71–114, 125–127 | `handleEvoItems` | evolution (2.11) |
| 115–120, 123, 124 | none | nothing (refused anyway) |

- `handleItemSickness(chance)`: `random(100) < chance` and not sick → sick, times sick + 1, sickness timer 1, an injury cured; the sick message (tamer state 20, `Care`'s sick message).
- The healing particles (`addHealingParticleEffect`) come with the effects (not ported: §6).

### 2.11 Evolution items

`handleEvoItems`: below 0x7D, only when the target's level − 1 is the partner's level; 0x7D / 0x7E / 0x7F → 0x40 / 0x3F / 0x41. Then `HAS_USED_EVOITEM = 1`, the tamer's item cleared, the inventory closed, tamer state 6, partner state 0xD (evolving). Ported with evolution: `specs/evolution.md` §2.5.

## 3. Sounds

| Sound (bank 0) | When |
|---|---|
| 0, 1 | a box opens / closes (UIBoxes) |
| 2 | the list's, the options', the sort's and the confirm box's cursor |
| 3 | △ cancels a move |
| 4 | ✕ ends a move |
| 12 | the tamer holds the item out |

## 4. Godot design

Three layers; only the middle one knows what an item does, and it knows it from the item's properties, never its id.

| Layer | What | Knows about items |
|---|---|---|
| **Inventory** (scene) | the list, Move / Sort / Drop, the cursor; on Use it hands the item over and closes | asks item use whether Use / Drop are allowed (the grey options) |
| **Item use** (`ItemUse`, plain logic) | where an item can be used, whether the partner takes it, what it does, the hunger rule, taking one out of the bag | everything, from `item_data` / `item_effects` |
| **The feeding scene** (`Partner` state 5) | the walk-up, the hand-over, eating or refusing | nothing: it asks item use at the two moments the C does (2.8 sub-states 4 and 6) |

- **`ItemUse`** (`scripts/systems/item_use.gd`), the C's item rules, one function each:
  - `can_use(item, context)` (`usable`: field / battle / both; `getItemOptionColor`, `selectOptionMenu`), `can_drop(item)` (`droppable`);
  - `will_refuse(item)` (`partnerWillRefuseItem`, 2.9), from `item_data.feeding`, the partner's discipline / hunger / favourite food and `ITEM_SCOLD_FLAG`;
  - `apply(item)` (`ITEM_FUNCTIONS[type](type)`, 2.10): dispatched by the item's `handler` property to one function per C handler (`handle_food`, `handle_chips`, …), each reading its numbers from `item_effects` / `healing_values`. A pack can add an item that uses an existing handler with its own values, and no code changes; a new kind of effect is a new handler function;
  - `handle_food_feed(item)` (`partnerHandleFoodFeed`, 2.9), `remove_one(item)` (`removeOneSelectedItem`);
  - the `context` is "field" now; the battle step (5d) calls the same functions with "battle" and adds the battle branches inside the same handlers (throwing, buff disks, status cures).
  - It changes the partner's care values through `Care` (its values, `set_food_timer`, `handle_poop_weight_loss`, the sick message) and the stats in `GameState`. `Care` keeps `ITEM_SCOLD_FLAG` (its praise / scold reads it).
  - This replaces `specs/care.md` §3.4's plan of porting `partnerWillRefuseItem` and `partnerHandleFoodFeed` inside `Care`.
- **Scene** `scenes/ui/inventory.tscn`: an `Inventory` node (`scripts/ui/inventory.gd`), the inventory object (2.3) and the tick / render functions of boxes 0–3. Opened by `GameMenu` (its state 2) through `MenuHost`, ticked by `MenuHost` after the menu object.
  - References: `boxes`, `text_area`, `tamer`, `game_state`, `data`, `item_use`, `pad`, `sound`; signals up: `closed` (back to the △ menu), `use_item(item, slot)` (the hand-over, 2.7).
  - The inventory in the state: `game_state.state["inventory"]` (`specs/game_state.md`). `names[]` isn't saved: the inventory keeps its own cell per slot, rebuilt by `drawInventoryText` and swapped with the items by Move / Sort.
  - Sort: `GameData.sort_order(mode)`, the items' `sort_category`.
- **The feeding scene:** `Partner` state 5 (`tick_feed_item`), with `check_eat_distance` reading the partner's `item_take_distance`; `Tamer.held_item` (`TAMER_ITEM`) and its icon in the hand (a `MapItems`-style icon at bone 9).
- **Data porter: properties instead of the id ranges** (`specs/content.md`; the porter checks the C text of each range):
  - `item_data.feeding`: `"refused"` (key items and passive chips, 2.9 step 1), `"evolution"` (step 2), `"obedience"` (the discipline roll of step 4: non-food items below 0x26), `"food"` (0x26–0x46, 0x79, 0x7A: the hunger rule, 2.9);
  - `item_effects.requires_level` for 0x7D–0x7F (4, 3, 4), so the refusal reads data.
- **Frame order:** the inventory object after the △ menu object (`MenuHost`); the feeding scene in the partner's tick.

## 5. Tests (`tests/test_inventory.gd`)

Headless, like `test_game_menu.gd`:
- opening from the menu (ITEM): box 0 closes, the inventory opens with box 1; △ goes back to the △ menu;
- the cursor: up / down / left / right limits, the scroll offset on a 30-slot inventory, the 11-frame repeat;
- the options' colours for a field item, a battle item, a non-droppable item; a grey option does nothing;
- Move (swap, the △ cancel and its sound 3, the ✕ end and its sound 4), Sort (each mode's order on a mixed bag, empty slots last), Drop (No keeps it, Yes removes the slot);
- the refusal rules (2.9) one by one, with fixed random values;
- `partnerHandleFoodFeed`: hungry and full, hungry not full, the favourite food's animation, not hungry;
- the field effects: a recovery (cap, HP 0), a chip (caps, the DV chips' lifetime and tamer level), Medicine, the Port. potty, a food (favourite × 1.4, the caps, the training boost reset), the sickness roll;
- the feeding scene from Use to the end, taken and refused: the sounds, the item removed only when taken.

## 6. Not in this step

- **Evolution:** an accepted evolution item starts partner state 0xD (`specs/evolution.md` §2.5, done 2026-10-26).
- **The healing particles** (`addHealingParticleEffect`): with the effects.
- **Battle:** throwing (`startThrowingItem`, `GAME_STATE` 1), the battle-only items (buff disks, status cures, the shield), the `currentCommand` test.
- (Resolved while coding.) **The item amount digits:** `setEntityTextDigit` (`utils.c`, asm) sets texture page 0x1E (VRAM (896, 256)) and the palette (256, 484). UV (d·6 + 0x89, 0x9C) is VRAM row 412, inside `ETCDAT/BI_IN.TIM` (asset porter `etctim/00_bi_in`, rows 384–447): its palette 4, image (d·6 + 0x89, 28), 6 × 10.

## 7. Open points

- **0x7E's and 0x7D / 0x7F's targets** (0x3F, 0x40, 0x41) and the "Ultimate lifetime" effect of `HAS_USED_EVOITEM` belong to evolution.
- **The refusal's dead branch** (2.9 step 5): kept as code, documented.
