# Stacked TIM files — `ETCDAT/ETCTIM.BIN`, `STDDAT/STDTIM.BIN`

Files made of TIMs placed back to back, loaded all at once into VRAM at the positions in their own headers.

Converters: `dwporter/families/stacked_tim.py` (shared), `etctim.py`, `stdtim.py` (`python -m dwporter convert etctim stdtim`). Each family module holds the per-entry table (name, description, expected VRAM, code references).

## On disc

| File | `FILE_OFFSET_TABLE` (`file_table_us.c`) | TIMs |
|---|---|---|
| `ETCDAT/ETCTIM.BIN` | `:225 { 0x1cd0, 0x1eac0, "ETCTIM.BIN" }` | 9 |
| `STDDAT/STDTIM.BIN` | `:775 { 0x23ebb, 0x20d80, "STDTIM.BIN" }` | 6 |

- No header and no padding between TIMs: each TIM starts right where the previous ends. The last TIM ends exactly at the file end.
- Every TIM is 4bpp except ETCTIM entry 7 (8bpp).
- See `tim.md` for the TIM format.

## Original handling

| Where | What |
|---|---|
| `dw_decomp/src/main/utils2.c:492` | `loadStackedTIMFile(path)`: `readFile` into `GENERAL_BUFFER`; **while** the next word is `0x10`: `GsGetTimInfo`, `LoadImage` image (and CLUT), advance by `4 + 16 + pw*ph*2 [+ 12 + cw*ch*2]` bytes. Block sizes in the file are not used. |
| `dw_decomp/src/std/std_setup.c:501` | `STD_loadTIMToVRAM(path)`: same walk, fixed count of **6** (STDTIM). |
| `dw_decomp/src/main/main.c:247` | `"\\ETCDAT\\ETCTIM.BIN"` (EU uses `ETCTIM_E.BIN`), loaded at `main.c:3434` before the main menu and again at `:3444/:3460/:3478` (new game / load / continue). |
| `dw_decomp/src/vs/vs_demo.c:115, :177, :492` | VS / demo mode loads both files. |
| `dw_decomp/src/std/std_setup.c:270` | Tournament setup loads STDTIM. Also `dw_decomp/src/vs/vs_scene.c:1180`. |

Because the TIM header positions are used as-is, **the `vram` block in each sidecar is where the game puts the data**, and drawing code refers to it with `GetTPage(...)` / `GetClut(...)` constants.

### Entries

`identified_by: code` = a drawing function found by matching its `GetTPage`/`GetClut` constants; `visual` = named from the image only, users not found yet (they may compute the page or come from 3D models).

**ETCTIM.BIN**

| # | Name | Image / CLUT VRAM | Identified | Users / notes |
|---|---|---|---|---|
| 0 | `ui_system` | (896,384) / (256,480)×16 | visual | Digit fonts, PUSH, star burst |
| 1 | `status_icons` | (960,448) / (272,496)×16 | visual | Condition / emotion icons |
| 2 | `smoke` | (768,384) / (192,488)×5 | visual | Smoke / dust strip |
| 3 | `scene_props` | (960,384) / (272,480)×16 | visual | Computer screens, bubbles, poop |
| 4 | `clock` | (896,448) / (256,496)×16 | code | `clock.c:228` `initializeClockData`, `clock.c:280` `renderGameClock` |
| 5 | `digimon_icons` | (512,256) / (112,488)×16 | visual | Portrait icons, medal discs |
| 6 | `items` | (320,0) / (224,488)×24 | visual | Item icons; **byte-identical to `ETCDAT/ITEM.TIM`** |
| 7 | `glow` | (832,384) / (0,487)×1, 8bpp | code | `map.c:5524` `tickMeramonShake` |
| 8 | `ui_menu` | (320,128) / (96,488)×16 | code | `script_textbox.c:1008` `renderUIBox` |

**STDTIM.BIN**

| # | Name | Image / CLUT VRAM | Identified | Users / notes |
|---|---|---|---|---|
| 0 | `digimon_icons_a` | (896,0) / (288,480)×16 | visual | Digimon icons |
| 1 | `digimon_icons_b` | (960,0) / (304,480)×16 | code | `std_main.c:3594` `STD_tickBracketHitFlash`, `:3630` `STD_renderBracketProjectile` |
| 2 | `time_up` | (832,0) / (16,480)×6 | code | `std_main.c:2878` `STD_renderCounterDigits` |
| 3 | `font_large` | (768,0) / (0,480)×2 | visual | Large Latin + katakana font |
| 4 | `font_small` | (832,256) / (48,480)×1 | code | `std_main.c:3428` `STD_renderBracketGlyph` |
| 5 | `bracket` | (832,120) / (32,480)×1 | code | `std_main.c:3301` `STD_drawBracket` (texture page shared with `time_up`) |

## Godot representation

- `output/<family>/<NN>_<name>.png` (+ `.p<N>.png` per extra palette), indexed PNGs, e.g. `output/etctim/04_clock.png`.
- Port mapping: "draw from tpage T / clut C at UV (u, v)" → texture `<name>` at pixel (u, v) − `vram.uv_origin`, palette row = `vram.clut_ids.index(C)`. Several TIMs can share a texture page (`time_up` and `bracket`), so match on the image rect, not only the page.

## Metadata

Sidecar: common keys + `tim`, `vram` (real game placement), and

```json
"entry": {"index": 4, "name": "clock", "description": "...", "identified_by": "code", "code_refs": ["..."], "duplicate_of": null},
"loader": "loadStackedTIMFile(path)"
```

## Verification (run on every conversion)

- File size equals the table size.
- Walk exactly like the loader: each TIM valid and packed (loader step == TIM size), expected TIM count (9 / 6), rest of file zero.
- Each TIM at the expected image and CLUT position.
- `duplicate_of` files are byte-identical.
- No two image/CLUT rects of the same file overlap in VRAM (they are loaded together).

Current result: etctim 9 assets, 41/41 checks; stdtim 6 assets, 28/28 checks.

## Open questions

- Users of the `visual` entries are not found yet. Next step: search for computed `GetTPage` values (texture page numbers, e.g. `tpage = 0x1e`) and TMD models that reference these pages.
- STDTIM `font_large` shares CLUT (0, 480) with map tiles (`map.c:4347`, `overworld.c:765`); different data occupies it at different times, so those are not users of this file.
- `ETCTIM_E.BIN` (EU) is not on the US disc.
