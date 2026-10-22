# Arena collision — `atr_files` (`STDDAT/*.ATR`)

Family: `dwporter/families/atr_files.py` (`python -m dwporter convert atr_files`).

## On disc

| File | `FILE_OFFSET_TABLE` (`file_table_us.c`) | Size |
|---|---|---|
| `STDDAT/B_TOGI.ATR` | line 766, `{ 0x23e56, 0x2710 }` | 10,000 bytes |
| `STDDAT/E_TOGI.ATR` | line 772, `{ 0x23e9f, 0x2710 }` | 10,000 bytes |

No header: 100 × 100 bytes, the same grid as a field map's collision section (`specs/map.md`): cell (tx, tz) covers world x ∈ [(tx − 50)·100, +100), z ∈ [(50 − tz)·100 − 100, +100); `0` walkable, `0x80` bit set = blocked.

## Original handling

Loaded straight into `MAP_COLLISION_DATA` (the field collision buffer), then the normal collision code (`map_collision.c`: `checkMapCollisionX/Z`, `getTileTrigger`) keeps fighters inside the arena.

| Code | Stage table | Stage → file |
|---|---|---|
| `src/vs/vs_scene.c:1061` `VS_ARENA_COLLISIONS[3]`, loaded by `VS_loadArenaAssets` (`vs_scene.c:1695`) | `VS_BATTLE_SETUP.stage` (VS mode: chosen in `vs_select.c:1195`, random in `vs_demo.c`) | 0 → B_TOGI.ATR (arena model T_TOGI), 1 → B_TOGI.ATR (B_TOGI), 2 → E_TOGI.ATR (E_TOGI) |
| `src/std/std_main.c:1344` `STD_ARENA_COLLISIONS[3]`, loaded by `std_setup.c:655` | tournament arena id | 0 → B_TOGI.ATR (T_TOGI), 1 → B_TOGI.ATR (B_TOGI), 2 → NULL |

So the T_TOGI arena has no collision file of its own and reuses B_TOGI's; E_TOGI.ATR is only used in VS mode. The arena models (`STDDAT/*_TOGI.TMD`, `tmd_files`) are drawn with identity coordinates, so their TMD coordinates are world coordinates and line up with the grid.

## Godot representation

`output/atr_files/STDDAT/<NAME>/`:

| File | Content |
|---|---|
| `collision.png` | 100 × 100 grey, raw values (lossless) |
| `preview.png` | 400 × 400 (4 px per cell): walkable white, blocked dark, other values orange; human check |
| `collision_cells.gltf/.bin` | flat quads at y = 0 for the walkable cells, in the porter's Godot/glTF axes (x, −y, −z); import together with `tmd_files/STDDAT/<arena>.gltf` to check that they cover the arena floor |
| `<NAME>.json` | sidecar: identity, values (list of 10,000), value counts, walkable bounding box, stage usage (VS / STD tables, arena models) |

## Metadata

Sidecar `<NAME>.json`: `asset_id` (`STDDAT/<NAME>.ATR@0x0`), `source` (path, offset, size, sha1 of the bytes and of the file), `psxprev_name`, `outputs`, `collision.values` (all 10,000 raw bytes, row tz = 0 first), `collision.counts`, `collision.walkable_box` (cell ranges), `usage` (VS / STD stage indices and the arena models drawn with the grid).

## Verification

- Size = 10,000 = file table size.
- Values are only `0` and `0x80` (others would be triggers; flagged if found).
- Walkable cells form one block in the middle of the grid (bounding box recorded).

## Open questions

- The grid is 100 × 100 like a field map, but only the centre is walkable; whether the battle camera or the AI read anything else from it is not checked.
