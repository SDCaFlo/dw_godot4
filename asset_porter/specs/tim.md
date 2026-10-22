# TIM (standard PSX texture)

Base format used by most image data on the disc, alone (`*.TIM`) or inside containers (`CARD.ALL`, `*TIM.BIN`, `ALLTIM.TIM`, maps, ...). Implemented in `dwporter/formats/tim.py`; reference: PSXPrev `Common/Parsers/TIMParser.cs`.

## On disc

Little-endian.

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | id: low byte `0x10`, version byte `0`, upper 16 bits `0` |
| 4 | u32 | flag: bits 0-2 pmode (0 = 4bpp, 1 = 8bpp, 2 = 16bpp, 3 = 24bpp), bit 3 = has CLUT |
| 8 | CLUT block (if flag bit 3) | u32 block size (incl. header), u16 x, u16 y, u16 w, u16 h, then `w*h` u16 colours |
| … | image block | u32 block size (incl. header), u16 x, u16 y, u16 stride (16-bit units), u16 h, then `stride*2*h` bytes |

- x/y are VRAM coordinates (16-bit units, VRAM is 1024×512). Pixel width = `stride * 16 / bpp`.
- 4bpp: two pixels per byte, **low nibble is the left pixel**.
- Colour: 15-bit `0bSBBBBBGGGGGRRRRR`. `0x0000` is drawn transparent by the GPU; bit 15 (STP) enables per-polygon semi-transparency (blend mode comes from the polygon, not the texture).
- A CLUT with h > 1 holds several palettes (e.g. `ETCDAT/ITEM.TIM` has 24); the game picks one by CLUT id.
- Quirk handled: pmode 2/3 with a CLUT is treated as indexed (PSXPrev / jpsxdec).

## Original handling

Generic loader: `loadStackedTIMEntry()` (`dw_decomp/src/main/file.c:116`) reads sectors, calls `GsGetTimInfo`, then `LoadImage` for the image rect and, if present, the CLUT rect. After that the game only refers to the texture through **VRAM ids**: `GetTPage(tp, abr, x, y)` and `GetClut(x, y)` plus UVs. Family specs list the exact callers.

## Godot representation

| Source | Output |
|---|---|
| 4/8bpp | Indexed PNG per palette: `<name>.png` (palette 0), `<name>.p<N>.png` (palette N). Indices are kept exactly; palette alpha 0 for `0x0000`. |
| 16bpp | RGBA PNG (`0x0000` → alpha 0) + `<name>.stp.png` grey mask (255 = STP set), only if any STP bit is set. |
| 24bpp | RGBA PNG, alpha 255. |

Channels are expanded `v<<3 | v>>2`; `>>3` gives back the original 5-bit value.

## Metadata (sidecar keys)

- `tim`: flag, pmode, bpp, width, height, stride, sizes, and `clut.palettes` = **all raw u16 colours** (STP included). With the PNG indices this rebuilds the original TIM exactly.
- `vram`: `image_rect`, `clut_rect`, `texture_page`, `uv_origin`, `tpage` (`GetTPage` with abr 0), `clut_ids` (`GetClut` per palette row). Match these against constants in the code to find who uses a texture.

## Verification

Unit tests in `tests/test_tim.py`: nibble order, palette transparency, STP mask, reversible colour expansion, libgpu id formulas, rejection of invalid data, scanning, PNG index round-trip.

## Open questions

- 24bpp row padding (PSXPrev also leaves it as a todo); none seen yet.
- STP is not encoded in PNG alpha for indexed images; consumers must read `tim.clut.palettes` if they need it.
