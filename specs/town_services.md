# The item keeper, the jukebox and Birdramon's transport

Status (2026-10-25): coded, step 5e-4c (`PLANS.md` 5e-4). Code:
- `scenes/script/item_keeper_routines.tscn`, `jukebox_routines.tscn`, `birdramon_routines.tscn` (`scripts/script/*_routines.gd`);
- `KeeperMenu` (`scripts/ui/keeper_menu.gd`);
- the music and destination lists in `ItemMenu` (styles 2, 3), plus `move_to_top` / `move_to_bottom`, `place` and `_pad`, which `TradeMenu` now shares;
- `ScriptRoutines.sound` (its `music` is `ItemMenu.music`);
- the porter's jukebox `font` / `variant` / `unlock_trigger`.

Tests: `tests/test_town_services.gd`, `data_porter/tests/test_systems.py`. Checks: VERIFY "Item keeper, jukebox, Birdramon".

As built:
- **The keeper's help line** (0x4D5 entry 3) shows ✕ in the game's font. The dump's "△" was only how the converter named the glyph, so that open point is closed.
- **Birdramon's map names** are space-padded in the data, but US `drawString2` advances a space by the previous glyph's width, which is 0 at the start of a line. The names come out left-aligned, as in the C. A long name ("Great Canyon Top Area") is cut where the price's tab code 0x1B starts.
- **Long jukebox names** run past the box's right edge. The C draws each row 0xFF pixels wide, so this follows from the long US names (§5).

The last three `CALL_ROUTINE` builtins on the script item menu. Read `specs/shops.md` and `specs/card_shops.md` first: the routine nodes, `MenuRoutines`, the shared `ItemMenu`, its row styles, the MAPHEAD lines and `SCRIPT_TEXTBOX_MODE` are described there.
- **0x0B, the item keeper:** items moved between the inventory and the keeper's storage. File City, ROOM02 (script 171).
- **0x09, the jukebox:** pick a track and hear it; the map's music comes back afterwards. ROOM05B (script 175).
- **0x0A, Birdramon's transport:** a paid flight to an unlocked area. ROOM12 (script 167).

Script 209 calls all three too. It has no map; see `specs/card_shops.md`.

## 1. The C code (`shop/script_menu.c` unless noted)

| C (US) | What |
|---|---|
| `tickItemKeeper` (`:892`), `itemKeeperFillItemList` (`:1536`), `createItemKeepWindow` (`:1605`), `tickItemKeeperWindow` (`:1941`), `updateKeeperTextbox` (`:2035`), `keeperMoveOne` / `Ten` / `Stack` (`:2061`, `:2114`, `:2180`), `keeperScrollLeftToItem` / `Right…` (`:2238`, `:2296`), `renderKeeperBox` / `…Left` / `…Right` (`:2328`, `:2026`, `:2052`), `renderKeeperTableBox` (`script_common.c`) | the item keeper (§2.1) |
| `openJukebox` (`:947`), `jukeboxFillTitleList` (`:1636`), `createJukeboxMenu` (`:1672`), `tickJukeboxMenu` (`:2396`), `renderJukeboxMenu` (`:2451`), `calculateMusicMenuStrings` (`script_common.c`) | the jukebox (§2.2) |
| `tickBirdraTransport` (`:987`), `birdraFillTargetList` (`:1721`), `createBirdraTransportMenu` (`:1742`), `tickBirdraTransportMenu` (`:2471`), `renderBirdraTransportMenu` (`:2527`), `calculateBirdramonMenuStrings` (`script_common.c`) | Birdramon (§2.3) |
| `createItemMenuDescriptionBox` (`script_common.c:2163`) | its third argument is the UI box the description grows from (1 or 2 in the keeper) |
| Data | the keeper's storage (`GameState.state.script.item_keeper`, `smth[0x54 + item]`, ≤ 99 each); `BGM_TRACK_NAMES` and `MAIN_D_801303B8` (`systems/jukebox`, §3.2); `BIRDRA_TRANSPORT_TARGETS` (`systems/birdramon_transport`: `map` with its loading name, `entrance`, `trigger`, `cost`) |
| Text | MAPHEAD sections 0x4D5 (keeper) and 0x4D6 (jukebox entries 0–3, Birdramon 4–7); MAPHEAD section 0x4E3 (Birdramon's take-off: "Hold on tight!", `TELEPORT` from value 247); the US box labels `MAIN_D_801307B4` "In hand" and `MAIN_D_801307C0` "Keeping" (C string literals, `:479–481`) |

## 2. Behaviour

`owner` is `readPStat(0xFE)`. "→ n" waits for ✕ on the line, then step n (mode 1).

### 2.1 The item keeper (0x0B: `tickItemKeeper`)

The lines are entries of section 0x4D5:

| Index | Line |
|---|---|
| 0 | "Do you have any business at the Item Keeper?" |
| 1 | "Yes / No" |
| 2 | "Come to this shop when you need it." |
| 3 | "Use △ to move Items. Use ○ to move by tens and □ to move all." |
| 4 | "Items Stored" (JP label, box 1) |
| 5 | "Items in Hand" (JP label, box 2) |

**The steps:**
- **0:** two lists, 5 rows each, both with the scroll bar at (0x88, 0x28), 6 × 0x4A. Left = the storage, right = the inventory. Line 0, → 3.
- **2:** free both; `ACTIVE_INSTRUCTION` = 0.
- **3:** the active side = left (`MAIN_D_80134F90` = 0); choice line 1 as the tamer's, 2 choices → 4 / 5.
- **4:**
  - repeat on ↑ ↓ and on ✕ and ○ (`0x5000 | CONFIRM | ALT`): holding ✕ keeps moving items;
  - list type 5 (the item picker's rows);
  - `itemKeeperFillItemList`, `createItemKeepWindow`;
  - line 3, mode 3.
- **6** (△): repeat off; boxes 1 and 2 close; → step 5 at once.
- **5:** line 2, → 2.

**The lists (`itemKeeperFillItemList`):**
- **Left:** one row per item with a stored count, in id order: (item, count). Bit 0x80 when it can come out: the inventory has a free slot, or a slot holding the item with fewer than 99.
- **Right:** one row per inventory slot (the inventory's size): (item, amount), or (0xFF, 0) for an empty slot. Bit 0x80 when its stored count is not 99.

**The boxes (`createItemKeepWindow`):** both flags 0xE1, 148 × 127.
- **Box 1 (the storage):** rect (−152, −98) from the NPC's origin; tick `tickItemKeeperWindow`; rows 9…14 in VRAM mode 1 (the left half of the text rows); row slots 10–14.
- **Box 2 (the inventory):** rect (0, −98) from the tamer's origin; no tick; rows 9…14 in mode 2 (the right half); row slots 10–14.

**`updateKeeperTextbox(side)`:**
- line 4 (side 0, box 1) or 5 (side 1, box 2) shown as owner 0xFF; the box's write count is taken back;
- the bytes at offset 6 (`KEEPER_LABEL_END`) of rows 9 and 15 are set to 0x0D, in the box's half;
- the rows are written: style 0, start row 0xA.

In US the label rows are drawn over (below), as Mojyamon's.

**Input (`tickItemKeeperWindow`):** only when both lists' pages are not busy (the tick flips them), box 3 is closed, boxes 1 and 2 are open, ✕ was released, and the step is 1. The list is the active side's.
- **△:** → 6, sound 4.
- **←:** the active side = left; sound 2. **→:** right; sound 2.
- Only when the active list has rows:
  - **✕:** move one; **○:** move ten; **□:** move all. Sound 3 each, whether the move happened or not.
  - **↑ / ↓:** the cursor (style 0). With R1, `…MoveToTop` / `…MoveToBottom` and then `updateKeeperTextbox(side)`.
  - **START:** the description box (§2.9 of `specs/shops.md`). Its origin is (5, 0x20, 0x80, 0x12) + the active side's box (1 or 2) + cursor × 18. Sound 3.

**The moves.** Nothing moves for an empty row or a row without bit 0x80.

| Move | Out of storage (left) | Into storage (right) |
|---|---|---|
| One (`keeperMoveOne`) | needs `getItemCount(item) < 99`; storage − 1, `giveItem(item, 1)` | needs `getItemCount(item) ≠ 0`; `removeItem(item, 1)`, storage + 1 |
| Ten (`keeperMoveTen`) | needs a count ≥ 10 and `getItemCount < 90`; storage − 10, give 10 | needs a slot amount ≥ 10 and storage < 90; remove 10, storage + 10 |
| All (`keeperMoveStack`) | `amount = min(count, 99 − getItemCount)`; storage − amount, give amount | `amount = min(slot amount, 99 − storage)`; remove amount, storage + amount |

- `getItemCount` is the first slot holding the item.
- `removeItem` takes from every slot holding it (`GameState.remove_item`).
- After a move, both lists are refilled. The side moved from is scrolled to the item first, then the other side (`keeperScroll…ToItem`); each then rewrites its rows.

**`keeperScrollLeftToItem(item)`:**
- the previous top / cursor are saved;
- **item found at row i:** go to "show i";
- **not found:**
  - an empty list → top 0, cursor 0;
  - else `i = min(top + cursor, count − 1)`;
  - if `top + visible ≥ count` and `top ≠ 0`, top − 1, and nothing more;
  - else "show i".
- **"show i":** if i is in the window, cursor = i − top. Else, if `i − visible < 0`, top 0 and cursor i; else top `i − visible + 1` and cursor `visible − 1`.

**`keeperScrollRightToItem(item)`:** "show i" when the item is found, nothing otherwise.

**Render (`renderKeeperBox`, US).** For each box, `flag` = 1 for box 2:
- two table frames: `renderKeeperTableBox` at (4, 0x15) 0x67 × 0xB and at (0x6B, 0x15) 0x25 × 0xB, a light top-left line and a dark bottom-right line;
- header 0 at (8, 0x17) and header 3 at (0x6E, 0x17);
- the scroll bar;
- the cursor at (5, cursor × 0x12 + 0x21), 0x80 × 0x12;
- the label: "In hand" for box 2 / "Keeping" for box 1, drawn into the box's half at y 0x6C (+ the back page), shown at (0x2D, 7), 0x38 / 0x3C wide;
- on the active side's box, a half-transparent fill (0x80, 0x80, 0xFF) at (4, 3), 0x8C × 0x12: the title bar lights up;
- the rows at (8, 0x24), with no icons (mode 2).

### 2.2 The jukebox (0x09: `openJukebox`)

The lines are entries of section 0x4D6:

| Index | Line |
|---|---|
| 0 | "Which one do you want?" |
| 1 | "Help me on my next request." |
| 2 | "{bgm_name 249}, right?" |
| 3 | "Why don't you request a number that will make me hot?" |

**The steps:**
- **0:**
  - the left list: 6 rows, scroll bar at (0xD2, 0x18), 6 × 0x5A;
  - `jukeboxFillTitleList`;
  - line 3, → 3.
- **2:**
  - free the list;
  - `playBGM(ACTIVE_BGM_FONT)`: the map's music again;
  - `readMapTFS(CURRENT_SCREEN_ID)`;
  - `ACTIVE_INSTRUCTION` = 0.
- **3:** repeat on, `createJukeboxMenu`, line 0, mode 3.
- **4** (△): repeat off, box 1 closes, line 1, → 2.

**`jukeboxFillTitleList`:**
- the tracks 0–0x3E in order, one row each (the second byte unused);
- track 0x3E is listed only once trigger 50 (the game beaten once) is set;
- then the track now playing is looked up: the first row whose `MAIN_D_801303B8` (font, variant) is `ACTIVE_BGM_FONT` / `ACTIVE_BGM_TRACK`:
  - found: value 249 = its row and `MAIN_D_80134F8F` = the same;
  - not found: both 0xFF, and `stopBGM`.

  The row index equals the track id, since the hidden track is the last.

**`createJukeboxMenu`:**
- flags 0xF1, rect (−0x47, −0x62, 0xDE, 0x81) from the NPC's origin;
- rows 9…14;
- on the first open, the cursor is put on the row of track `value 249` (row 0 if none): "show i" as in §2.1, but with no "already in the window" case;
- then the rows are written (style 2).

**Input (`tickJukeboxMenu`):** only when box 1's page is not busy (the tick flips it), boxes 0 and 1 are open, and ✕ was released.
- **Playing:** first, if value 249 ≠ `MAIN_D_80134F8F`, the latter becomes the former, then `stopBGM` and `playMusic(MAIN_D_801303B8[track])`. This is how a pick starts its music on the next frame. `ACTIVE_BGM_FONT` is not changed.
- **✕:**
  - value 249 = the row's track;
  - line 2 ("{track name}, right?"), mode 3 (step 1, the list stays);
  - the rows are rewritten (the playing track turns colour 6);
  - sound 3.
- **△:** → 4, sound 4.
- **↑ / ↓:** style 2; with R1, `itemMenuCursorTop` / `Bottom` (start row 9).

**A row (`calculateMusicMenuStrings`, US):**
- `01 06` if the track is value 249 (playing), else `01 01`;
- the track number + 1 in 2 digits;
- `0F 00`, the track's name;
- `12 − len / 2` full-width spaces;
- the terminator.

**Render (`renderJukeboxMenu`):**
- header 4 at (8, 5) and header 5 at (0x26, 5);
- the scroll bar;
- the cursor at (5, cursor × 0x12 + 0x11), 0xCA × 0x12;
- the rows at (8, 0x13), mode 2.

### 2.3 Birdramon's transport (0x0A: `tickBirdraTransport`)

The lines are entries of section 0x4D6:

| Index | Line |
|---|---|
| 4 | "Where should I take you?" |
| 5 | "I think that going yourself may be the best way." |
| 6 | "Are you sure? Once you go, I can't take you back." |
| 7 | "I know / Cancel" |

**The steps:**
- **0:** the left list: 6 rows, scroll bar at (0xD2, 0x18). `birdraFillTargetList` makes one row per target whose trigger is set, in table order: (target, 0), | 0x80 when its cost ≤ bits. Line 4, → 3.
- **2:** free the list; `ACTIVE_INSTRUCTION` = 0.
- **3:**
  - `createShopBitsBox(1)` (the bits box);
  - `createBirdraTransportMenu`: flags 0xF1, rect (−71, −100, 222, 129) from the NPC's origin, rows 9…14, `initItemMenuBox`, the rows (style 3), `SHOP_VARIABLE` = 0;
  - repeat on; step 1.
- **4:** repeat off; choice line 7 as the tamer's, 2 choices → 5 / 6.
- **5** (I know):
  - boxes 2 and 1 close;
  - target = row & 0x7F;
  - value 247 = its map, value 248 = its `entrance`;
  - **the script moves to MAPHEAD section 0x4E3** (`ACTIVE_SCRIPT = getScript(0)`, `SCRIPT_POINTER` = the section);
  - bits −= `SHOP_VARIABLE`;
  - → 2 at once.

  When the routine ends, the interpreter runs 0x4E3: "Hold on tight!" (owner 5), then `TELEPORT 247` (the map and exit in values 247 / 248), already ported.
- **6** (△ in the list, or Cancel): repeat off, boxes 2 and 1 close, line 5, → 2.

**Input (`tickBirdraTransportMenu`):** only when box 1's page is not busy (the tick flips it), boxes 0 and 1 are open, ✕ was released, and `SHOP_VARIABLE` = 0.
- **✕ on an affordable row:** line 6, `SHOP_VARIABLE` = the cost, → 4, sound 3. On a red row: sound 0xB.
- **△:** → 6, sound 4.
- **↑ / ↓:** style 3, R1 for the top / bottom.

After Cancel, `SHOP_VARIABLE` keeps the cost, but box 1 is already closing.

**A row (`calculateBirdramonMenuStrings`, US):**
- `01 01` or `01 03` (red);
- the map's loading name. The US names are space-padded to 24 bytes, so the padding (`12 − len / 2`) adds nothing;
- `0F 00 1B 00`, the cost in 4 digits;
- the terminator.

**Render (`renderBirdraTransportMenu`):**
- header 6 at (8, 5) and header 2 at (0xA2, 5);
- the scroll bar;
- the cursor at (5, cursor × 0x12 + 0x11), 0xCA × 0x12;
- the rows at (8, 0x13), mode 2.

## 3. Godot design

### 3.1 Code

- **Routine nodes** (as in `specs/card_shops.md` §3), each on `MenuRoutines`:
  - `scenes/script/item_keeper_routines.tscn` + `scripts/script/item_keeper_routines.gd`: 0x0B;
  - `jukebox_routines.tscn` + `jukebox_routines.gd`: 0x09;
  - `birdramon_routines.tscn` + `birdramon_routines.gd`: 0x0A.
- **The boxes:**
  - `scripts/ui/keeper_menu.gd` (`class_name KeeperMenu`): the keeper's two boxes, the moves and the scroll-to-item;
  - the jukebox and Birdramon lists go in `ItemMenu`, as `create_music_menu` / `create_destination_menu` with their ticks, renders and row writers: style 2 and style 3 in `row_writers`.
- **Sound:** `ScriptRoutines` gets the interpreter's `sound` (the `SoundSystem`, its `music` = `MusicPlayer`). The jukebox calls `music.stop_bgm()`, `play_music(font, variant)` and `play_bgm(music.active_bgm_font)`. Without a sound system (tests), the music calls are skipped and logged by the test's fake.
- **`readMapTFS`** reloads the map's background textures, which the music's loading overwrote in VRAM. The port's music doesn't touch them, so it is a no-op.
- **The Birdramon jump:** `ctx.code` = MAPHEAD, `ctx.code_id` = MAPHEAD, `ctx.pointer` = section 0x4E3 (as the interpreter's `_jump_to_file`).
- **The labels "In hand" / "Keeping"** are C string literals in the US code, not text table entries. They become `KeeperMenu` constants with their C symbols.
- **Properties, not ids:**
  - the jukebox reads each track's `font` / `variant` and `unlock_trigger` (§3.2) instead of the literal track 0x3E;
  - Birdramon reads its targets' `trigger`, `cost`, `map`, `entrance`;
  - the keeper's left list is "every item, in id order, with a stored count".

### 3.2 Data porter change (`systems/jukebox`, `data_porter/specs/systems.md`)

- **`font`, `variant`** per track, from `MAIN_D_801303B8[track × 2]` / `[track × 2 + 1]` (`shop/script_menu.c:211`, 128 bytes: 64 pairs, the first 63 used).
- **`unlock_trigger`:** 50 for track 0x3E, null for the others. It comes from `jukeboxFillTitleList`'s `isTriggerSet(TRIGGER_50)` and `i != 0x3e`. The converter checks that this code text is still in `shop/script_menu.c`, and that `TRIGGER_50` is 50.
- **Checks:** 64 pairs; every used pair's font is 1–0x21 (`playMusic`'s range); 63 names.

## 4. Tests (`tests/test_town_services.gd`)

The same harness as `test_card_shops.gd`, with a fake music player that records its calls.

- **Item keeper:**
  - storage {Meat 15}, inventory {Meat 95, Sm.Recovery 3}: the rows and their 0x80 bits;
  - ✕ (one out): Meat 96 / 14;
  - ○ (ten out): refused, because 96 ≥ 90;
  - □ (all out): 3 out (99 − 96), the rest stays;
  - → to the inventory, ✕ (one in) and ○ (ten in);
  - an item stored to 99 can't take more (bit 0x80 off);
  - moving the last one out removes the left row, and the cursor stays in range (scroll-to-item);
  - START: the description box; △: line 2, then the script goes on;
  - "No" on the choice: line 2, then the end.
- **Jukebox:**
  - the rows (62 tracks before trigger 50, 63 after);
  - the cursor starts on the track now playing;
  - ✕ on another row: value 249 = it, line 2 names it, then `play_music(font, variant)` on the next frame;
  - △: "Help me on my next request.", then `play_bgm(the map's font)`, and the script goes on.
- **Birdramon:**
  - only targets with their trigger set are listed; red when too dear;
  - ✕ → line 6 → I know: bits − cost, values 247 / 248 = the map / entrance, the script runs MAPHEAD 0x4E3 ("Hold on tight!") up to its `TELEPORT`;
  - Cancel and △: line 5, then the end, bits unchanged.
- **Porter:** `data_porter` unit test for the jukebox table's new fields.

## 5. Open points

- **`padWithSpaces` with the jukebox names:** the US track names are longer than 24 bytes ("Non Bewildering Forest Theme" is 28). `12 − len / 2` is then negative, and the US loop (`while (used != 0)`) would run away. I can't explain from the code how the real game avoids this. The port pads nothing then (as for Mojyamon). **To check in the game:** how the US jukebox list looks.
- **The keeper's "move all" out of storage with `getItemCount` = 99** while another slot holds the item below 99: `amount` = 0, and `giveItem(item, 0)` adds nothing to that stack. The port does the same.
