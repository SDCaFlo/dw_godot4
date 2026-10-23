# Items (`ITEM_PARA`, `ITEM_FUNCTIONS`, cards, shops … → `output/items/`)

Items and what they do, the healing values, the built-in inventories, the inventory sort, the recycle shop, cards and shops. Converter: `dwdata/groups/items.py` (`python -m dwdata convert items`).

## 1. Source

| Table | Where | C type |
|---|---|---|
| `ITEM_PARA` | `src/main/item.c:745` | `Item[128]` (`include/dw/item.h:10`), 32 bytes, 12 in EU (no `name`) |
| `ITEM_FUNCTIONS` | `src/main/item.c:1932` | `ItemFunction[128]` (`void (*)(int16_t)`, `item.h:50`) |
| `ITEM_CLUT_DATA` | `src/main/item.c:1904` | `uint8_t[128]` |
| handlers | `item.c:2190–2386`, `:2685` (`handleFood`); `main.c:4293` (`handleBuffDisks`) | `switch` on the item id |
| `HEALING_VALUES`, `HEAL_EFFECT_VARIANT` | `src/main/item.c:2064–2065` | `int16_t[4]`, `uint8_t[4]` |
| `INITIAL_INVENTORY_TYPES/AMOUNTS` | `src/main/item.c:74–90` | `InventoryTable` (`uint8_t[30]`) |
| `DEFAULT_INVENTORY_TYPES/AMOUNTS` | `src/main/main_menu.c:666–680` | `InventoryTable` |
| `ITEM_SORT_ORDER` | `src/main/inventory.c:81` | `uint8_t[3][6]` |
| `RECYCLABLE_ITEMS` | `src/main/script_common.c:350` | `uint8_t[78]` |
| `CARD_DATA`, `CARD_PRICES` | `src/main/script_common.c:438`, `:433` | `CardData[66]` (`include/dw/script.h:186`), `int32_t[5]` |
| `SHOP_MAPS`, `SHOPKEEP_DIGIMON_TYPES` | `src/main/script_common.c:346`, `:342` | `int16_t[8]`, `ShopkeeperIdTable` (`uint8_t[11]`, `:19`) |
| names | `text/main/item.yaml` → `ITEM_NAMES`, `ITEM_DESCS` | see `specs/text.md` |

- **Names:** as for Digimon, `ITEM_PARA_NAME(STR_ITEM_NAME_X)` embeds the name except in EU (`item.h:12`, `:53–58`). The converter expands it to the string id, or to nothing for EU, and checks that it is `ITEM_NAMES[id]`.
- **Release differences:** none in the tables.
  - `handleBuffDisks` has a non-US branch of no-op code in case 0x12 (`main.c:4355–4370`) that keeps the compiled code matching. The effect is the same in every release.
- **Shop stock isn't in C.** The item lists of the shops are written by the event scripts (`SCRIPT_STATE_PTR->smth`); only the shop maps and shopkeepers are tables.

## 2. Original usage

### ITEM_PARA

- **`value`**: shop price in bits (`createItemMenuAmountBox`, `script_common.c:1986`). Selling pays `value >> 1` (`:1992`, `:2618`). The recycle shop sells at `value` (`script_menu.c:1400`).
- **`meritValue`**: price in merit points (merit trade, item menu type 7: `script_common.c:890`, `:2630`).
- **`sortingValue`** (0–5): the item's group for sorting. `sortItems` (`inventory.c:960–978`) collects the items of each group, sorts each group by id, then concatenates the groups in the order `ITEM_SORT_ORDER[mode - 11]`.
- **`itemColor`**: where the item can be used, and its colour.
  - The Use command is allowed in the field (`GAME_STATE` 0) for 0 and 2, and in battle for 1 and 2 (`inventory.c:220–236`, `:888–902`).
  - The name is drawn in text colour `itemColor + 5`, or 8 for 0xff (`inventory.c:592–596`). The output names the values field / battle / both / none.
- **`droppable`**: the Drop command needs 1 (`inventory.c:245`, `:915`).
- **`unk`**: 0 everywhere, read nowhere.

### Handlers and effects

`ITEM_FUNCTIONS[type](type)` runs when the tamer's thrown item reaches the partner (`tickThrownItem`, `main.c:4280`) or when the partner is fed (`partnerTickFeedItem`, `partner.c:504`). NULL entries do nothing: 115–120, 123, 124 (key items such as the Blue Flute, fishing rods, Mansion key, Gear, AS Decoder). Most handlers switch on the item id; the converter reads each `case` (`CIndex.switch_cases`): constant assignments become `values`, any other statement is kept as C text in `code`.

- **`handleHPHealingItem`** (0–3) / **`handleMPHealingItem`** (4–6): restore `HEALING_VALUES[id]` HP or `HEALING_VALUES[id - 4]` MP (500 / 1500 / 5000 / 9999), capped at the maximum, unless HP is 0. The particle variant is `HEAL_EFFECT_VARIANT` (`item.c:2366–2386`).
- **`handleDoubleFloppy`** (7): +1500 HP and +1500 MP (`item.c:2351`).
- **`handleStatusItems`** (8–10, 13–14), `item.c:2218`:
  - 8 cures the battle status (`BTL_healStatusEffect(1)`)
  - 9 cures it in battle, then works like the Double floppy
  - 10 sets the partner's `FIGHTER_FLAG_PROTECTED`, which blocks statuses (see `specs/moves.md`)
  - 13 Bandage and 14 Medicine call `handleMedicineHealing(3, 2)` / `(3, 10)` (`item.c:2937`). With `injuryChance` 3, an injury always heals (`randomLimit(3) < 3`). Sickness heals when `randomLimit(10) <` the second value: 2 (20 %) for the Bandage, 10 (always) for Medicine.
- **`handleRestore`** (11–12): revives if HP is 0 (animation 0x2c) and ends the battle death countdown. 11 heals half the max HP; 12 heals 9999 and cures the battle status (`item.c:2315`).
- **`handleBuffDisks`** (15–21), `main.c:4293`: in battle, +20 (15–17) or +50 (19–21) to Off / Def / Speed, capped at 1.3 × the partner's starting battle stat (`INITIAL_COMBAT_STATS[0]`, at most 999). 18 gives +20 to all three without the cap.
- **`handleChips`** (22–37), `item.c:2248`:
  - 22 Auto Pilot runs script section 0x4dd while a script is paused.
  - 23–31 add permanent stats (HP / MP up to 9999, others up to 999); the DV chips (29–31) also take 24 from the remaining lifetime and call `addTamerLevel(10, -1)`.
  - 32 Port. potty works like a toilet (`handlePortaPotty`, `item.c:2954`).
  - **33–37 have no case**: using them does nothing. They are passive items whose effect comes from code that checks the inventory (the converter checks that code is still there):
    - 0x21 Trn. manual: training gains ×1.1 (`trn_reward.c:712`, `trn2_hud.c:251`)
    - 0x22 Rest pillow: sleep recovery ×1.2 (`partner_impl.c:1351`)
    - 0x23 Enemy repel: +20 on the battle roll of `btl.c:305–321`
    - 0x24 Enemy bell: −50 on that roll, and it wins over the repel
    - 0x25 Health shoe: while the tamer walks (animation 2), the partner gets +5 HP and MP every 20 frames (`partner.c:949–960`)
- **`handleFood`** (38–70, and 121 Rain Plant, 122 Steak), `item.c:2685`. Every case sets some of these variables (all start at 0, `:2706–2708`):
  - energy: added with `addEnergy`, capped at `RAISE_DATA.energyCap` (see `specs/digimon.md`)
  - tiredness (reduced), happiness, discipline, weight
  - lifetime: added to `remainingLifetime`
  - addedHP / MP / Offense / Defense / Speed / Brain: permanent stats, capped at 9999 / 999
  - healedHP / MP: current HP / MP
  - trainFlag / trainValue / trainDuration: a training boost through `setTrainingBoost` (`item.c:3025`)
    - bits 0x01 Off, 0x02 Def, 0x04 Speed, 0x08 Brain, 0x10 HP, 0x20 MP: each bit scales that stat's gym gain from `x * v / 10` to `x * v * trainValue / 100` (`trn_reward.c:169–519`)
    - the boost lasts `trainDuration * 1200` frames
  - sicknessChance: % chance to make the partner sick (`handleItemSickness`, `item.c:3035`)
  - Favourite food: ×1.4 energy and +2 happiness (`item.c:2904`).
  - Every food also lowers the poop level (`decreasePoopLevel`).
- **`handleEvoItems`** (71–114 and 125–127), `item.c:2190`:
  - Items below 0x7d evolve into `EVOLUTION_ITEM_TARGET[item - 0x47]` (`item.c:1923`; part of the Evolution group), only if the target is one level above the partner.
  - 0x7d / 0x7e / 0x7f evolve into 0x40 / 0x3f / 0x41 (`item.c:2194–2203`).
  - Using one sets `HAS_USED_EVOITEM`, which changes Ultimate lifetime (see `specs/digimon.md`).

### Other tables

- **`ITEM_CLUT_DATA`**: palette row of each item icon. `setItemTexture` (`utils2.c:308`) sets the CLUT to (0xe0, 0x1e8 + value), and the fishing bait sprite uses it too (`fish.c:2278`).
- **Inventories** (30 slots, type 0xff = empty):
  - `INITIAL_INVENTORY_*` is copied to RAM by `initializeInventory` at boot (`item.c:2665`, from `initializeInventoryModules`, `main.c:4211`).
  - `DEFAULT_INVENTORY_*` is written into `initializeDefaultSavegame` (`main_menu.c:4952`), which the title menu's first option loads (`main_menu.c:3644–3649`, `:4466–4469`).
  - Both hold large amounts of high-end items (40 Lrg. recovery, 45 Omnipotent, …). See open questions.
- **`ITEM_SORT_ORDER[3][6]`**: the 3 sort modes (11–13), each an order of the 6 groups.
- **`RECYCLABLE_ITEMS[78]`**: the items the recycle shop can stock. Slot `i` keeps its count in `SCRIPT_STATE_PTR->smth[i + 6]` (`script_menu.c:1394–1404`, `getRecycleId`, `script_common.c:1386`). Item 0x54 is listed twice.
- **`CARD_DATA[66]`**: `digimonId`, `spriteId` (rarity class) and `meritValue`.
  - A card costs `CARD_PRICES[spriteId]` (5000 / 1500 / 500 / 100 / 50) and sells for half (`script_common.c:2019`, `:1110`).
  - Card rolls (`rollCard`, `script_menu.c:1414`): `r = randomLimit(100)`, then class 0 if r = 0 (1 %), 1 for 1–4 (4 %), 2 for 5–19 (15 %), 3 for 20–49 (30 %), 4 for 50–99 (50 %). One card of that class is then picked at random.
  - The merit trade pays `meritValue` (`script_menu.c:1924`).
  - Cards 0 and 65 are tamer placeholders with class 5, which has no price.
- **`SHOP_MAPS[8]`**: entering one of these maps loads the shop overlay (`checkShopMap`, `script_common.c:3075`).
- **`SHOPKEEP_DIGIMON_TYPES`**: Digimon types that act as shopkeepers when they are the script's NPC (`getShopkeeperLine`, `script_common.c:1181`); 0xff ends the list.

## 3. Mapping

`output/items/`: `item_data`, `item_effects`, `healing_values`, `inventories`, `sort_orders`, `recyclable_items`, `card_data`, `shops` (common table shape) and `report.md`.

- `item_data` merges the three per-item C arrays, which share the index: `ITEM_PARA` with `name` and `description` from the text, `handler` from `ITEM_FUNCTIONS`, `icon_clut` from `ITEM_CLUT_DATA`.
  - Renamed fields: `price` (C `value`), `merit` (C `meritValue`), `sort_category` (C `sortingValue`), `usable` (C `itemColor`, as `{id, name}`), `droppable` (bool).
  - Derived: `sell_price` = value >> 1.
  - **Property `passive`** on the five passive items (`../specs/content.md` §4): `training_boost` (0x21), `sleep_boost` (0x22), `battle_repel` (0x23), `battle_lure` (0x24), `walking_heal` (0x25). Absent on every other item.
    - It replaces the literal ids of the inventory checks (`getItemCount(0x22)` …). The ported code asks "does the inventory hold an item whose `passive` is `sleep_boost`", so a pack can add another pillow.
    - Each property comes from the same evidence check as `item_effects.passive`.
  - `c` keeps the raw `ITEM_PARA` record.
- `item_effects`: one record per item with a handler.
  - `values` (switch assignments, or the heal values); `code` (other statements, C text); `defaults`
  - `train_boost` (decoded `trainFlag`); `passive` (passive items: effect, `property`, evidence); `evolution` (where the target comes from)
- `card_data`: `digimon {id, name}`, `rarity`, `price`, `sell_price`, `merit`, `c`. `source.prices` lists the price and roll range per class.
- `inventories`: `default_savegame` and `boot`, as non-empty slots `{slot, item, amount}` plus the raw arrays.
- `shops`: one record with `maps` and `shopkeepers`.

## 4. Godot usage

- `GameData.item(id)`, `item_effect(id)`, `card(id)`, `shops()`, `recyclable_items()`, `sort_order(mode)`, `inventory_preset(name)`.
- The inventory UI uses `usable`, `droppable` and `sort_category`. Shops use `price`, `sell_price`, `merit`. Feeding and throwing call a GDScript port of each handler, which reads `item_effects`. The handler rules of §2 (caps, favourite food, sickness, boosts, buff caps) are code, not data.
- **Modding:**
  - Prices, merit values and food effects can change freely within their C types.
  - Keep 128 items: drops, scripts and shops use the ids.
  - Keep the handler ranges: HP / MP items 0–6 index `HEALING_VALUES` by id, and evolution items below 0x7d index `EVOLUTION_ITEM_TARGET` by `id - 0x47`.
  - Keep 66 cards and the 5 rarity classes.

## 5. Verification

The converter checks:

- the decomp exists, and the structs `Item` (EU without `name`) and `CardData` have the mapped fields in every release;
- every table parses in every release with no issues, and each table's size equals its US symbol size where one is given;
- there are 128 entries in `ITEM_PARA`, `ITEM_FUNCTIONS`, `ITEM_CLUT_DATA`, `ITEM_NAMES` and `ITEM_DESCS`;
- each item's embedded name is `ITEM_NAMES[id]`; use, droppable and sort category are known values;
- every handler in `ITEM_FUNCTIONS` is one the spec describes;
- every item of a switch handler has a case, except the five passive items, whose inventory checks must still be in the code; no case falls through; the switches are the same in every release, except the no-op branch of `handleBuffDisks`;
- every card has a priced rarity class, except the class-5 tamer placeholders, which have no merit value.

Tests: `tests/test_items.py` (real data), `tests/test_cdata.py` (switch reader, function-pointer tables).

## 6. Open questions

- **Built-in inventories:** both look like test inventories. Whether the opening event scripts replace the default savegame's inventory isn't traced (scripts topic). Check what a new game really starts with.
- **Enemy repel / bell:** the roll in `btl.c:305–321` is part of the code that decides which enemies join a battle (the flee test of `specs/digimon.md` is next to it). The exact meaning of +20 / −50 needs that function read in full.
- **`sortingValue` group names** aren't in the text; the sort mode labels are (`text/main/inventory.yaml`).
- **Shop stock** comes from the event scripts. Not covered here.
- **`trainFlag` 0x16 / 0x29** in food are the stat masks above. Their match with the stats each gym trains comes from the order of the gain variables in `trn_reward.c`, which is consistent but not named in the code.
