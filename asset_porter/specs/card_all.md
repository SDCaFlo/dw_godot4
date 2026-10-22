# card_all — `CARD/CARD.ALL` (trading card images)

Converter: `dwporter/families/card_all.py` (`python -m dwporter convert card_all`).

## On disc

- Path: `CARD/CARD.ALL`, 1,892,352 bytes (`0x1CE000`).
- `FILE_OFFSET_TABLE`: `{ 0x00000019, 0x001ce000, "CARD.ALL" }` (`dw_decomp/src/main/file_table_us.c:8`).
- Layout: **66 slots of `0x7000` bytes (14 sectors)**. Each slot holds one TIM at its start, zero-padded to the slot end.
- Every TIM: 8bpp, 150×180, image at VRAM (576, 256), stride 75; CLUT at (448, 511), 256×1. TIM size 27,544 bytes.
- Slot index = card number printed on the card (card 00 is "主人公", the player).

See `tim.md` for the TIM format.

## Original handling

| Where | What |
|---|---|
| `dw_decomp/src/main/game_menu.c:461` | `char MAIN_D_80123E78[] = "\\CARD\\CARD.ALL";` |
| `dw_decomp/src/main/game_menu.c:2380` | `loadCardImage(id)` → `loadStackedTIMEntry(MAIN_D_80123E78, TEXTURE_BUFFER, id * 0xe, 0xe)`: reads 14 sectors starting at sector `id * 14` |
| `dw_decomp/src/main/file.c:116` | `loadStackedTIMEntry`: `readFileSectors`, `GsGetTimInfo`, `LoadImage` for image and CLUT. Overwrites the same VRAM area for every card, so only one card is loaded at a time |
| `dw_decomp/src/main/game_menu.c:2386` | `renderCardImage()` → `renderRectPolyFT4(-0x4b, -0x54, 0x96, 0xb4, 0, 0, GetTPage(1, 0, 576, 256), GetClut(448, 511), 4, 0)`: draws 150×180 at screen offset (−75, −84), UV (0, 0) |
| `dw_decomp/src/main/game_menu.c:2078` | `loadCardImage(SELECTED_CARD)` from the card menu; also listed in function tables at `game_menu.c:301` and `:331` |

## Godot representation

- `output/card_all/card_NN.png` — indexed 8bpp PNG, `NN` = card id (00–65).
- Port mapping:
  - `loadCardImage(id)` + `renderCardImage()` → show texture `card_%02d.png % id` at 150×180, centred as in the original (top-left at −75, −84 from the menu origin).
  - The VRAM upload / tpage / CLUT handling has no equivalent; it is kept in metadata only.

## Metadata

Sidecar `card_NN.json`: common keys (see `dwporter/assets.py`) + `tim`, `vram`, and

```json
"card": {"id": 0, "slot": {"offset": 0, "size": 28672, "sector": 0, "sectors": 14}, "loader": "loadCardImage(id)"}
```

`manifest.json` lists the code references above and all check results.

## Verification (run on every conversion)

- File size equals the table size and is a multiple of `0x7000`; 66 slots.
- Each slot: valid TIM, fits the slot, 8bpp, `tpage == GetTPage(1,0,576,256)`, `clut == GetClut(448,511)`, size 150×180 (= draw size), padding after the TIM is zero.

Current result: 66 assets, 465/465 checks passed.

## Open questions

- Card names, prices and other card data live elsewhere (likely tables in `game_menu.c` / item data); not part of this family.
- Whether all 66 cards are reachable in game is not checked here.
