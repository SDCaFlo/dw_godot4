# alltim — `CHDAT/ALLTIM.TIM` (Digimon model textures)

Converter: `dwporter/families/alltim.py` (`python -m dwporter convert alltim`). Type table: `dwporter/data/digimon.py`.

## On disc

- Path: `CHDAT/ALLTIM.TIM`, 3,317,760 bytes (`0x32A000`).
- `FILE_OFFSET_TABLE`: `{ 0x000003b6, 0x0032a000, "ALLTIM.TIM" }` (`dw_decomp/src/main/file_table_us.c:9`).
- Layout: **180 slots of `0x4800` bytes (9 sectors)**, slot index = **digimon type id**. Each slot holds one TIM at its start, zero-padded to the slot end. Despite the extension, the file is not a single TIM.
- Every TIM: 4bpp, 16-colour CLUT with 1–16 rows (palettes), image up to 256×128 (168 of 180 are exactly 256×128 with 16 palettes).
- Every TIM header says image at VRAM (320, 0), CLUT at (0, 488). **The game ignores this** (see below).

See `tim.md` for the TIM format.

## Original handling

| Where | What |
|---|---|
| `dw_decomp/src/main/model.c:2506` | `char MAIN_D_8011D190[] = "ALLTIM.TIM";` |
| `dw_decomp/src/main/model.c:3285` | `loadDigimonTexture(digiType, path, component)`: `readFileSectors("ALLTIM.TIM", buf, digiType * 9, 9)` into a `0x4800` buffer, then `uploadModelTexture` |
| `dw_decomp/src/main/model.c:3621` | `loadMMDAsync`: same read (`digimonType * 9`, 9 sectors, `imageSize = 0x4800`), followed by the model `CHDAT\MMD<type/30>\<NAME>.MMD` |
| `dw_decomp/src/main/model.c:3557` | `uploadModelTexture`: `GsGetTimInfo`, then **overrides** `px/py/cx/cy` from the `ModelComponent` (`pixelPage`, `pixelOffsetX/Y`, `clutPage`) and `LoadImage`s image and CLUT |
| `dw_decomp/src/main/model.c:3400` | NPC model slot `k` (0–4): `pixelPage = k/2 + 0x16`, `pixelOffsetY = (k%2) << 7`, `clutPage = (k+2) \| 0x7A00` |
| `dw_decomp/src/main/model.c:3424` | Tamer: `pixelPage 0x15`, `clutPage 0x7A00`. Partner: `pixelPage 0x15`, `pixelOffsetY 0x80`, `clutPage 0x7A01` |
| `dw_decomp/src/main/model.c:3418` | `updateTMDTextureData(model, pixelPage, offX, offY, clutPage - 0x7A00)`: patches the model's polygons to point at the slot (relevant for the MMD/TMD spec) |
| `dw_decomp/src/main/model.c:2508` | `PTR_DIGIMON_FILE_NAMES[180]`: model file name per type |
| `dw_decomp/text/main/main.yaml` | `DIGIMON_NAMES`: display name per type (same order, `DIGIMON_PARA` in `src/main/main.c`) |

Resulting VRAM slots (`RUNTIME_SLOTS`, also in `manifest.json`):

| Slot | Image (x, y) | CLUT (x, y) |
|---|---|---|
| tamer | (320, 256) | (0, 488) |
| partner | (320, 384) | (16, 488) |
| npc0–npc4 | (384, 256), (384, 384), (448, 256), (448, 384), (512, 256) | (32..96, 488), step 16 |

Each slot is 64×128 VRAM units (256×128 4bpp pixels) and 16 CLUT rows of 16 colours.

### Palettes are per polygon, not skins

The CLUT rows colour different parts of the model (e.g. Agumon: palette 0 green eyes/claws, 1 red eyes/mouth, 2 grey). Each model polygon selects its row. A single PNG is therefore **not** a complete texture; rendering a model correctly needs the index image plus the polygon's palette. The model converter (MMD/TMD) will have to either keep per-polygon palette ids or bake the colours.

## Godot representation

- `output/alltim/<type>_<FILE>.png` (palette 0) and `<type>_<FILE>.p<N>.png` (palette N), indexed 4bpp PNGs; e.g. `003_AGUM.png`, `003_AGUM.p1.png`.
- Port mapping:
  - `loadDigimonTexture(type)` / `loadMMDAsync(type)` → texture set for `DIGIMON_TYPES[type]`.
  - Slot assignment (tamer / partner / NPC k) and the VRAM override have no Godot equivalent; kept in `manifest.json` for reference.

## Metadata

Sidecar `<type>_<FILE>.json`: common keys + `tim`, `vram` (the header values, **not** where the game puts it), and

```json
"digimon": {"type": 3, "file_name": "AGUM", "string_id": "STR_DIGIMON_NAME_AGUMON", "name": "Agumon", "model": "CHDAT/MMD0/AGUM.MMD"},
"slot": {"offset": 55296, "size": 18432, "sector": 27, "sectors": 9},
"loader": "loadDigimonTexture(type) / loadMMDAsync(type)",
"vram_position_overridden": true
```

`manifest.json` adds `runtime_slots`.

## Verification (run on every conversion)

- File size equals the table size and is a multiple of `0x4800`; 180 slots = `0xB4` (loader limit) = entries in `DIGIMON_TYPES`.
- Each slot: valid TIM, fits the slot, 4bpp with 16-colour CLUT, ≤ 256×128 and ≤ 16 palettes (fits a runtime slot), padding is zero, and the model file exists (except the known missing ones below).

Current result: 180 assets, 1083/1083 checks passed.

## Open questions

- Types 62 (`wEAG`, WereGarurumon) and 114 (`tAKA`, empty name) have a texture but **no model file** on disc or in `FILE_OFFSET_TABLE`. The lower-case names suggest unused types. Their textures are still exported.
- Some types share a display name (e.g. several "Greymon", "MetalGreymon"): enemy/NPC variants (`E*`, `CE*` file names) with their own textures. Use the type id, not the name, as the key.
