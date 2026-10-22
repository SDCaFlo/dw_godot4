# TMD (standard PSX model) and `tmd_files` (66 `.TMD` files)

Format: `dwporter/formats/tmd.py` (reference: PSXPrev `Common/Parsers/TMDParser.cs`, `TMDHelper.cs`). glTF export: `dwporter/models.py` + `dwporter/exporters/gltf.py`. Textures: `dwporter/formats/vram.py`. Family: `dwporter/families/tmd_files.py` (`python -m dwporter convert tmd_files`).

## On disc

Little-endian.

| Offset | Type | Field |
|---|---|---|
| 0 | u32 | id `0x41` |
| 4 | u32 | flags: bit 0 FIXP (1 = absolute addresses, 0 = offsets relative to the object table). All game files use 0. |
| 8 | u32 | nobj |
| 12 | 28 × nobj | object table: u32 vert_top, n_vert, normal_top, n_normal, primitive_top, n_primitive; i32 scale (2^scale) |
| … | 8 × n | vertices: i16 x, y, z, pad |
| … | 8 × n | normals: i16 x, y, z, pad (4.12 fixed point, 4096 = 1.0) |
| … | | primitives: u8 olen, ilen, flag, mode, then `ilen` × 4 bytes |

Primitive header bits:

- `flag`: bit 0 = unlit (no normals), bit 1 = double-sided, bit 2 = gradation (one colour per vertex).
- `mode`: bit 0 = brightness off (TGE), bit 1 = semi-transparent (ABE), bit 2 = textured, bit 3 = quad, bit 4 = gouraud, bits 5-7 = code (1 polygon, 2 line, 3 sprite).

Packet layout for polygons, in file order (`packet_layout()`):

1. Textured: per vertex `u, v` (u8) followed by `CBA`, `TSB`, pad, pad (u16) for vertex 0, 1, 2, 3.
2. Colours (if untextured or unlit): `r, g, b, mode/pad` × (1, or one per vertex for gradation / unlit gouraud).
3. Lit: flat = `normal, v0, v1, v2[, v3]`; gouraud = `n0, v0, n1, v1, ...` (u16 indices). Unlit: `v0, v1, v2[, v3]`.
4. A trailing u16 pad for lit flat quads and unlit triangles.

The parser computes the layout from the bits and **rejects any packet whose layout size does not match its `ilen`**, so a wrong layout cannot pass silently.

- `TSB` (= `GetTPage`): x = bits 0-3 × 64, y = bit 4 × 256, abr = bits 5-6, colour mode = bits 7-8 (0 4bpp, 1 8bpp, 2 16bpp).
- `CBA` (= `GetClut`): x = bits 0-5 × 16, y = bits 6-14.

### Game data

- 66 files (`DOOR/` 33, `ETCDAT/` 7, `ETCHI/` 2, `ETCNA/` 15, `STDDAT/` 10), all parse; 4,495 primitives, 16 flag/mode variants, all triangles/quads (no lines or sprites).
- Every file ends exactly where its last block ends; every pad word is zero; sizes match `FILE_OFFSET_TABLE`.
- Winding: in 4,709 of 4,733 lit polygons the PSX vertex order is **clockwise** around the stored normal (`(v1-v0)×(v2-v0)` points opposite the normal); quads split as (0,1,2) + (1,3,2).

## Original handling

- `loadStaticTMD` (`dw_decomp/src/main/map_object.c:295`): `readFile`, `GsMapModelingData`, `GsLinkObject4`. Other loaders use `readFile` + the same libgs calls. **None of these patch TSB/CBA**, so a model samples whatever VRAM holds at its texture pages. (Digimon MMD models are different: `updateTMDTextureData` rewrites them, see `alltim.md`.)
- Which textures are in VRAM depends on context. Per file (`FILES` in `tmd_files.py`):

| Textures (`texture_files`) | Models | Why |
|---|---|---|
| `ETCDAT/ETCTIM.BIN` (loaded for the whole field session, `main.c:3434`) | `DEFEFF`, `MAHI`, `DOSYA`, `HAKO`, `MEDAL`, `TAKA`, `UNTI` | UVs land on `DEFEFF`/`BI_IN`/`FEEL_EF`/`SBOY`/`SYSTEM_W` inside ETCTIM |
| Sibling TIM loaded by the same code | `EX` (`EX.TIM`), `TAMA` (`TAMA.TIM`, `dooa.c:536`), `IWA` (`IWA1.TIM`, `map_object.c:624`), `SAO`/`SEA` (`FISHING.TIM`) | |
| Arena TIM | `T_TOGI`, `T_DAI` (`T_TOGI.TIM`); `B_TOGI`, `B_DAI` (`B_TOGI.TIM`); `E_TOGI`, `E_DAI` (`E_TOGI.TIM`) | arena tables, `std_hud.c` |
| `STDDAT/STDTIM.BIN` | `1P2PWIN`, `CHAMP`, `DRAW`, `WIN_LOSE` | `time_up` entry (832, 0) |
| none (untextured) | `FEEL_EF` | |
| **map textures, not bound yet** | `DOOR/*`, `ETCNA/DOOR`, `ABOX`, `BIGBOX`, `GAND`, `SMABOX`, `TRY`, `T_YAMA`, `WARP`, `KARRING`, `BOSS_EFE` | pages at (640/704/512/384, 0) and CLUT rows 484-486, the area map textures occupy |

## Godot representation

`output/tmd_files/<FOLDER>/<NAME>.gltf` + `.bin` + `<NAME>_tex/page_<x>_<y>_<bpp>bpp_clut_<x>_<y>.png` + `<NAME>.json`.

- One glTF node + mesh per TMD object (`object_<i>`), mesh primitives grouped by material.
- Axes `(x, -y, -z)` (PSX +Y down → glTF +Y up), units = raw PSX units × 2^scale, triangles emitted as (0,2,1) / quads (0,2,1)+(1,2,3) so glTF counter-clockwise = PSX front face.
- Textures are full 256×256 texture pages sampled through the polygon's CLUT exactly like the GPU (4/8bpp index → CLUT colour; `0x0000` → alpha 0). UV = page pixel / 256. Nearest filtering.
- Materials: one per (TSB, CBA, semi-transparent, double-sided, lit, TGE). `alphaMode` MASK (BLEND when semi-transparent), `doubleSided` from the flag, `KHR_materials_unlit` when unlit. Vertex colours (`COLOR_0`) for coloured polygons: untextured `c/255`, textured `min(c/128, 1)` (128 = neutral).
- Unbound (map) models: geometry and UVs are exported, materials are untextured; TSB/CBA stay in `extras`.

Port mapping: `loadStaticTMD(X_TMD, ...)` / `readFile(X_TMD)` → instance `<FOLDER>/<NAME>.gltf`. Semi-transparency blend modes (`abr`) and TGE are in material `extras` for a custom shader if needed.

## Metadata

Sidecar `<NAME>.json`:

- common keys (`asset_id`, `source`, `outputs` incl. `model`, `model_buffer`, `texture_page` entries)
- `tmd`: flags, size, and per object the header plus **all raw vertices, normals and primitives** (offset, olen, ilen, flag, mode, indices, UVs, CBA, TSB, colours): the lossless source of the model
- `textures`: per (page, CLUT): UV box used, output path, `missing_texels_in_uv_box`, and which loaded TIMs cover the page and CLUT (`vram_sources`)
- `model`: description, code refs, `texture_files`, `texture_note`, `textures_bound`

glTF `extras`: root `asset_id`; per node the object header; per mesh primitive the file offsets of its PSX packets; per material TSB/CBA/tpage/CLUT/flags.

## Verification (run on every conversion)

- Every `.TMD` on disc is listed in `FILES`.
- Per file: valid TMD with every packet layout matching `ilen`, blocks end exactly at file end, zero pad words.
- Bound models: every texture page has **0 missing texels** inside the UV area the model uses.
- Tests: synthetic packet parsing, `ilen` mismatch rejection, exported winding agrees with the normal, real-data conversion.

Current result: 66 assets, 221/221 checks. Renders checked by eye: TAKA (item box), TAMA (egg), MEDAL, UNTI, SAO, IWA, B_TOGI/T_TOGI arenas, CHAMP, WIN_LOSE.

## Open questions

- Map-textured models need the map texture format (`.TFS`) to be bound; then they can be exported per map.
- `ETCNA/TAKA.TIM` covers the same VRAM as ETCTIM's `FEEL_EF` part but differs and has no loader; the game draws the item box with `FEEL_EF`.
- `E_DAI.TMD` and `ETCNA/DOOR.TMD`, `MAHI.TMD`, `DEFEFF.TMD` have no loader found in the decomp (bindings from UVs only).
- Semi-transparency modes (`abr` 0-3) are approximated as alpha blend; a faithful port needs custom blend modes.
- `SEA.TMD` is a flat shadow; the fishing Seadramon itself may be another model.
