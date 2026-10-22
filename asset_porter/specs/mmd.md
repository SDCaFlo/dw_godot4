# MMD (Digimon models) — `mmd_files` (178 files)

Format and animation simulator: `dwporter/formats/mmd.py`. Skeleton data: `dwporter/data/skeletons.py` (generated from the decomp, verified against `SLUS_010.32`). glTF: `dwporter/models.py` (`build_skeletal`). Family: `dwporter/families/mmd_files.py` (`python -m dwporter convert mmd_files`). Reference: DW1ModelConverter (`external_tools/DW1ModelConverter/src/Model.cpp`, `Animation.cpp`, `GameData.cpp`).

## On disc

`CHDAT/MMD<type // 30>/<NAME>.MMD`, one per digimon type (`dwporter/data/digimon.py`); types 62 (`wEAG`) and 114 (`tAKA`) have no file, no skeleton and 0 bones.

| Offset | Content |
|---|---|
| 0 | u32 `tmd_offset` (always 8) |
| 4 | u32 `anim_offset` |
| 8 | standard TMD (`tmd.md`), one object per mesh bone |
| `anim_offset` | animation table: u32 offsets relative to the table, 0 = no animation. **No count**: the table ends where the first animation starts (smallest offset / 4). Several ids can share one offset. |
| … | animations, back to back |

Every byte of all 178 files is header, TMD, table or animation, plus at most a 2-byte alignment pad (`CD CD`, filler of the original tool).

TMD quirk: `TANE.MMD` primitives index normals past the object's declared normal count; the GTE just reads the following entries, so the parser reads them too (`tmd.parse(strict=False)`, recorded as `lenient_reads`).

### Animation

```
u16 frame_count            bit 15 = has scale
per bone 1..n-1:           [i16 scale x, y, z]  i16 rot x, y, z  i16 loc x, y, z     (bone 0 = root, not stored)
instructions, until a 0x0000 word:
  0x0fff  keyframe (frame)   entries while word & 0x8000:
                             u16 0x8000 | axes << 6 | bone ; i16 divisor ; i16 value per set axis
                             axes bits 8..0 = scale x, y, z, rot x, y, z, loc x, y, z
  0x1nnn  loop start         count = low byte (0 and 0xFF = endless)
  0x2fff  loop end (frame)   u16 frame to jump back to
  0x3fff  texture (frame)    u16 src x<<8|y ; u16 w<<8|h ; u16 dest x<<8|y      (MoveImage in the model slot)
  0x4fff  sound (frame)      u16 bank<<8|sound   (bank 4 = the digimon's own VAB)
```

Units: rotation 4096 = 360°, scale 4096 = 1.0, location = model units. Totals: 4,843 animations, 157,565 ticks, 2,070 endless loops, 17,866 texture moves, 6,115 sounds.

## Original handling

| Where | What |
|---|---|
| `dw_decomp/src/main/model.c:3405`, `:3620` | Load `CHDAT\MMD<type/30>\<NAME>.MMD`; `modelPtr = mmd + mmd[0]`, `animTablePtr = mmd + mmd[1]` |
| `dw_decomp/src/main/model.c:3285`, `:3557` | Texture: ALLTIM slot `type` (`alltim.md`), uploaded at the model slot (`uploadModelTexture`) |
| `dw_decomp/src/main/graphics.c:156` | `updateTMDTextureData(model, pixelPage, offX, offY, clutPage - 0x7A00)` (decomp parameter names are misleading): per object, until the first untextured primitive: TSB = (TSB & ~0x1F) + pixelPage, CBA += slot index, every UV += (offX, offY) |
| `dw_decomp/src/main/model.c:2310` | `DIGIMON_SKELETONS[180]`: `SkeletonBone {object, parent}` arrays (0xFF = no mesh / no parent), 78 distinct, shared between types |
| `dw_decomp/src/main/main.c:254` | `DIGIMON_DATA[180].boneCount` (also radius, height) |
| `dw_decomp/src/main/anim.c` | `startAnimation` (initial pose of bones 1..n-1), `tickAnimation` (instructions), `tickMomentum` / `animApplyMomentum` (per-frame integration), `applyRootMomentum` (root motion) |
| `dw_decomp/src/main/anim.c:calculatePosMatrix` | bone matrix = `TransMatrix(loc)`, `RotMatrix(rot)`, `ScaleMatrix(scale)` → T·R·S |
| `asm/us/main/psyq/libgte.s` `RotMatrix` | **Rx·Ry·Rz** (decoded from the assembly: m00 = cz·cy, m01 = −sz·cy, m02 = sy, m12 = −cy·sx, …) |
| `dw_decomp/src/main/main.c:3761` | main loop `VSync(3)`: one animation tick per frame at **20 fps** (NTSC) |

### Momentum semantics (what `simulate` ports)

- A keyframe entry sets, per axis, `delta = value / divisor` (C division) and spreads `value % divisor` with a Bresenham counter (`sign`, `counter`, `reload = divisor`). The rate stays until the next keyframe for that axis.
- Each tick: (1) apply momentum to every bone (rotation stored as int16, wraps), (2) process instructions whose frame equals the current frame, (3) stop at `frame_count`, else frame + 1.
- Root (bone 0): scale/rotation integrate like the others; location deltas (×2^15) are rotated/scaled by the root matrix and accumulated (`applyRootMomentum`); x is frozen for animation ids 0x23/0x24.
- Loop end: count−1 (0xFF never decrements); 0 → continue, else jump to the frame and back to the loop start. Count 0 underflows to 0xFF → endless.
- Quirk: at the start of a tick the game tests `instr & 0x1000` (not the opcode), so a texture instruction (0x3xxx) there would be read as a loop start. The simulator reproduces it and counts it: **0 occurrences** in the game data.

## Godot representation

`output/mmd_files/MMD<n>/<NAME>.gltf` + `.bin` + `<NAME>_tex/` + `<NAME>.json`.

- **Rigid bone hierarchy**: one glTF node `bone_<i>` per bone, parent from the skeleton; the bone's TMD object is its mesh (vertices are already bone-local). A glTF skin lists all bones as joints (no vertex weights), so importers build a real skeleton: Godot a `Skeleton3D`, Blender an armature. Without it, Blender played most animations wrong (checked by the user); Godot 4.4.1 was fine either way.
- Rest pose: tick 1 of the lowest animation id (`rest_pose` in the sidecar); bone 0 at the origin.
- Transforms converted to glTF axes: translation (x, −y, −z), rotation = q(Rx(a)·Ry(−b)·Rz(−c)), scale /4096.
- **Animations** `anim_<id>` (one per table id; `same_data_as` lists ids with identical data): the game's poses tick by tick, time = (tick − 1) / 20, LINEAR. Keys are dropped only when interpolation reproduces them exactly (constant integer steps; rotation: single axis, < 90° per run). Bone 0 translation = root motion.
- Endless loops are simulated through one pass; `extras.loop` gives `start_time`/`end_time` (play once, then repeat from `start_time` to `end_time`).
- Animation `extras.events`: sounds (`bank`, `sound`, `time`) and texture moves (`src`/`size`/`dest` in slot VRAM units and `*_uv` in page pixels).
- Textures: the ALLTIM texture uploaded in the **tamer slot** (pixel page 0x15 → image (320, 256), CLUT (0, 488), no UV offset), TSB/CBA/UVs patched like `updateTMDTextureData`, then one 256×256 page per CLUT row used (each polygon picks its row). In this slot the patched UVs equal the file UVs.

Port mapping: `loadMMDAsync(type)` / `thunkLoadMMD(type)` → instance `MMD<type/30>/<NAME>.gltf`; `startAnimation(entity, id)` → play `anim_<id>` (use `extras.loop`); texture moves → copy the UV rect in the material texture(s) at `time` (blinking eyes etc.); sounds → play `bank`/`sound` at `time`; root motion → bone 0 translation track.

## Metadata

Sidecar `<NAME>.json`: common keys + `digimon` (type, names), `skeleton` (name, `{object, parent}` per bone, radius, height), `texture_source` (ALLTIM offset, slot), `rest_pose`, `lenient_reads`, `animation_keys`, `textures`, `tmd` (raw model **after** the slot patch; the original TSB/CBA/UVs are TSB & ~0x1F | 0x05 and unchanged CBA/UVs), and `mmd` (offsets, `anim_table`, every animation's raw header and instructions with file offsets).

## Verification (run on every conversion)

- Every `.MMD` on disc belongs to a digimon type; types without skeleton have no model.
- Per type: skeleton pointer, bone count and `{object, parent}` bytes match `SLUS_010.32` (decomp tables = executable); bones use every TMD object exactly once; every file byte explained; every animation simulates (no quirk); every texture page fully covered by the ALLTIM slot.
- Visual checks: Agumon, Greymon, the tamer (rest and animated), compared against DW1ModelConverter: same keyframe values; translations within 1 unit (their float momentum vs exact integer stepping), rotations within ~0.4° at keyframes.

Current result: 178 assets, 1071/1071 checks.

## Open questions

- Animation names (idle, walk, attack ids) are not mapped yet; ids follow the game (`startAnimation(entity, id)`).
- Texture moves are exported as events; a Godot implementation must apply them to the material texture (or bake frames).
- Semi-transparency (`abr`) is approximated as alpha blend (see `tmd.md`).
- The root starts at identity; in game it starts from the entity's current orientation.
