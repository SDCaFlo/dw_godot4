# Asset porter progress

Update this file whenever a format or family changes status. Status values: `todo`, `investigating` (reading the decomp / scanning), `spec` (spec written), `done` (converter + checks + tests), `blocked`.

Last updated: 2026-10-26

## Formats (parsers / exporters)

| Format | Status | Code | Spec | Notes |
|---|---|---|---|---|
| TIM (texture) | done | `dwporter/formats/tim.py` | `specs/tim.md` | 4/8/16/24bpp, multi-palette, STP mask |
| PNG (export) | done | `dwporter/exporters/png.py` | — | Indexed, RGBA, grey; stdlib only |
| TMD (model) | done | `dwporter/formats/tmd.py` | `specs/tmd.md` | Layout checked against `ilen` for every packet; all 66 files parse |
| glTF (export) | done | `dwporter/exporters/gltf.py`, `dwporter/models.py` | `specs/tmd.md` | Axis flip, winding, nearest-filtered texture pages, PSX data in `extras` |
| VRAM simulation | done | `dwporter/formats/vram.py` | `specs/tmd.md` | Builds textures like the GPU (page + CLUT) from the TIMs the game has loaded |
| MMD (Digimon models + animations) | done | `dwporter/formats/mmd.py`, `dwporter/models.py` | `specs/mmd.md` | TMD + animation table; exact port of the game's momentum animation (20 fps); RotMatrix order decoded from libgte asm |
| MAP / TFS (maps) | done | `dwporter/formats/map.py` | `specs/map.md` | Pre-rendered backgrounds + 3D camera (projection verified), collision, objects, entities, doors |
| SCN (event scripts) | done | `dwporter/formats/scn.py` | `specs/scn.md` | Offset table + per-script sections; full disassembler (all opcodes of `script.h`, IF conditions, selections, DATA), Shift-JIS text with control codes; lossless round trip |
| ATR (arena collision) | done | — (raw grid) | `specs/atr.md` | 100 × 100 cells, same layout as map collision |
| EFE (battle effects) | done | `dwporter/formats/efe.py` | `specs/efe.md` | 0x5000-byte slots; header, effect-script VM disassembler (18 opcodes, 97 built-ins, control-flow tracing), UV anims, TMD + TIM |
| VHB / VAB (sound banks) | done | `dwporter/formats/vab.py` | `specs/sound.md` | VHB offset table + libsnd VAB (programs, tones, samples); PSX ADPCM → WAV with loop points |
| SEQ (music) | done | `dwporter/formats/seq.py` | `specs/sound.md` | Sony pQES → Standard MIDI; loop markers |
| WAV / SF2 (export) | done | `dwporter/exporters/wav.py`, `sf2.py` | `specs/sound.md` | WAV with `smpl` loops; SF2 preview banks (no ADSR) |
| libsnd + SPU (music render) | done | `dwporter/formats/libsnd.py`, `spu.py` | `specs/sound.md` | libsnd's sequencer and voice manager (from DW's libsnd asm) on an SPU emulation: ADPCM loops, Gaussian interpolation, ADSR, Studio B reverb; tables read from the executable |
| STR (FMV) | done | `dwporter/formats/strmovie.py` | `specs/movies.md` | Sector interleave (7 video 2048 B : 1 XA 2324 B), MDEC v2/v3 bitstream decoder (MPEG-1 VLC, IDCT, YCbCr), XA ADPCM; numpy optional for speed |

## Families (disc files)

| Family | Source | Status | Assets | Checks | Spec | Notes |
|---|---|---|---|---|---|---|
| `card_all` | `CARD/CARD.ALL` | done | 66 | 465/465 | `specs/card_all.md` | 66 card images, 0x7000-byte slots |
| `alltim` | `CHDAT/ALLTIM.TIM` | done | 180 | 1083/1083 | `specs/alltim.md` | One texture per digimon type, 0x4800-byte slots; palettes are per polygon; types 62/114 have no model |
| `etctim` | `ETCDAT/ETCTIM.BIN` | done | 9 | 49/49 | `specs/stacked_tim.md` | = 9 ETCDAT `.TIM` files concatenated (entries named after them); 3/9 drawers found in code |
| `stdtim` | `STDDAT/STDTIM.BIN` | done | 6 | 28/28 | `specs/stacked_tim.md` | Tournament graphics; 4/6 users found in code |
| `tim_files` | 51 standalone `*.TIM` (ETCDAT, ETCHI, ETCNA, STDDAT, GRADE) | done | 54 | 271/271 | `specs/tim_files.md` | Loader + code refs per file; T_TOGI has 4 TIMs; 9 ETCDAT files are also inside ETCTIM.BIN; SLOT/TAKA/EX have no loader |
| `tmd_files` | 66 `*.TMD` (DOOR, ETCDAT, ETCHI, ETCNA, STDDAT) | done | 66 | 221/221 | `specs/tmd.md` | glTF + texture pages; 22 field/effect/arena/result models textured, 1 untextured, 43 use map textures (bound when maps are done) |
| `mmd_files` | 178 `CHDAT/MMD*/*.MMD` | done | 178 | 1071/1071 | `specs/mmd.md` | Rigid bone hierarchy, 4,843 animations (loops, sounds, texture moves as events), textures from the ALLTIM slot; matches DW1ModelConverter within 1 unit / <1° |
| `maps` | 241 `MAP/MAP*/*.MAP` + `.TFS` | done | 244 | 1256/1256 | `specs/map.md` | Backgrounds per time of day, sprites, textured doors, `overview.png` for human checks; GIAS06B/ICSA05 sprites need VRAM loaded by events; training slot strips (`training/slots_p3/p4.png`) for the 3 gym maps |
| `efe` | `ETCHI/EFEDAT.EFE` | done | 331 | 1029/1029 | `specs/efe.md` | 120 technique effects (slot = technique id, named; raw slot `effect.bin` for the effect VM), 89 textured models, 121 textures, scripts as JSON + listings; slot 110 stale copy of 344, slot 121 fill |
| `btl_rel` | `BTL_REL.BIN` | done | 5 | 14/14 | `specs/btl_rel.md` | The battle overlay's TIM and its 4 models (finisher aura, confusion, stun, buff), textured from ETCTIM.BIN + the TIM |
| `atr_files` | `STDDAT/B_TOGI.ATR`, `E_TOGI.ATR` | done | 2 | 7/7 | `specs/atr.md` | Arena collision; walkable disc (B) / diamond (E) checked against the arena models; T_TOGI arena reuses B_TOGI.ATR |
| `scripts` | `SCN/MAPHEAD.SCN`, `SCN/DG.SCN` | done | 223 | 1571/1571 | `specs/scn.md` | 222 DG scripts + MAPHEAD (map setup); 39,797 instructions, 4,844 texts; map → script links; JSON + readable listings |
| `sound` | 7 `SOUND/VHB/*.VHB` | done | 145 | 1396/1396 | `specs/sound.md` | 145 VABs (SS, SL, SB, 22 ESALL map sets, 16 VLALL partner sets, 71 VBALL Digimon sets, 33 FAALL music fonts), 834 samples, 74 music tracks (.seq + .mid), usage per bank |
| `music` | `SOUND/VHB/FAALL.VHB` + `SLUS_010.32` tables | done | 74 | see manifest | `specs/sound.md` | The 74 songs rendered like the game plays them (WAV 44.1 kHz stereo, intro + loop in `smpl`; fonts 0x1D–0x20 once); `index.json` per track |
| `mmm_dat` | `MMM.DAT` | done | 0 | 2/2 | `specs/sound.md` | All zeros, never opened by the code: disc filler, nothing to convert |
| `movies` | 4 `MOVIE/*.STR` | done | 4 | 20/20 | `specs/movies.md` | 13,089 frames (320x176, ~30 fps) all decode with code counts matching their headers; audio WAV (37.8 kHz stereo, length = video); preview PNG every 2 s; `.ogv` for Godot (ffmpeg) |
| | `*_REL.BIN`, `SLUS_010.32` | — | | | | Code; data tables come from the decomp, not converted here |

## Game data from the decomp (not disc files)

| Data | Source | Status | Notes |
|---|---|---|---|
| Text / strings | `dw_decomp/text/**/*.yaml` | todo | `en_us` |
| Digimon type table (file + display names) | `PTR_DIGIMON_FILE_NAMES`, `DIGIMON_NAMES` | done | `dwporter/data/digimon.py`, generated from the decomp |
| Skeletons, bone counts, radius/height | `DIGIMON_SKELETONS`, `DIGIMON_DATA` | done | `dwporter/data/skeletons.py`, generated from the decomp, verified against `SLUS_010.32` |
| Digimon raise data | `RAISE_DATA` (`include/dw/partner.h`) | todo | |
| Technique names | `MOVE_NAMES` | done | `dwporter/data/moves.py`, generated from `text/main/item.yaml` |
| Items, moves (stats), evolution tables | `dw_decomp/src/main/*.c` | todo | |

## Infrastructure

| Item | Status | Notes |
|---|---|---|
| CLI (`list`, `convert`, `scan`) | done | |
| Identity sidecars + `manifest.json` | done | `dwporter/assets.py` |
| Verification checks (fail = non-zero exit) | done | |
| Unit tests | done | `tests/test_tim.py`, 41 tests |
| Human verification guide | done | `VERIFY.md` |
| Godot import of `output/` | done | `asset_porter/.gdignore`: the editor never imports it; the game loads it through `scripts/content/content.gd` (`Content`): raw at runtime, or the Godot-imported editor mirror `res://content/dw1/` (models, map backgrounds / doors, cards; gitignored) when present |

## Log

- 2026-10-21 — Core created (TIM, PNG, CLI, sidecars, scan). `card_all` done: 66 assets, 465/465 checks.
- 2026-10-21 — `alltim` done: 180 Digimon textures, 1083/1083 checks. Added `dwporter/data/digimon.py` (type → file name, display name, model path). Found the game overrides the TIM's VRAM position at load time.
- 2026-10-21 — `etctim` (9 assets, 41/41) and `stdtim` (6 assets, 28/28) done with shared `stacked_tim.py`. Unlike ALLTIM, these load at their header VRAM positions; users matched via `GetTPage`/`GetClut` constants (7 of 15 so far).
- 2026-10-21 — `tim_files` done: all 51 standalone TIMs (54 assets, 271/271), loaders and path tables (`STD_GRADES`, arena tables) recorded. Found ETCTIM.BIN = 9 ETCDAT TIMs concatenated; `etctim` entries renamed after them (49/49). All TIM data on the disc outside maps/models is now converted.
- 2026-10-22 — TMD parser, glTF exporter and VRAM simulation done. `tmd_files`: all 66 TMDs (221/221). Texture bindings from code + UV coverage; 43 models (doors, map props) wait for map textures. Winding verified against stored normals.
- 2026-10-22 — `mmd_files` done: 178 Digimon models with skeletons and 4,843 animations (1071/1071). Animation = exact port of anim.c; RotMatrix = Rx·Ry·Rz confirmed from the libgte assembly; cross-checked against DW1ModelConverter. Output JSON made compact (all families, 477 MB → 163 MB for MMD).
- 2026-10-22 — MMD glTF now declares a skin (all bones as joints): animations were wrong in Blender as a plain node hierarchy; fixed and confirmed by the user. Verified in Godot 4.4.1 headless: poses match the data, no stale bones when switching animations.
- 2026-10-22 — `maps` done: 241 field maps (MAP_ENTRIES/DOOR_MAPDATA/TOILET_DATA read from the executable). Camera projection derived from GsSetRefView2 and verified by projecting collision onto backgrounds. Doors textured per map. Added VERIFY.md (human checks).
- 2026-10-22 — First consumer in Godot: `scenes/field/field.tscn` loads maps + the tamer from `output/` at runtime (`asset_porter/.gdignore` keeps the editor from importing it). Camera projection matches `map.json` to <0.001 px; root motion, collision and warps (110–119) work on real maps.
- 2026-10-22 — `atr_files` (2 assets, 7/7) and `scripts` (223 assets, 1571/1571) done. SCN = the event script bytecode: every opcode decoded from `script.h` + the interpreter, all 223 scripts rebuild byte for byte, all jumps/sections land on instructions. Found: DG script 0 = copy of MAPHEAD; sector padding is build-tool leftovers (incl. source names `\SCN\MAPnnn.SCN`); US text is full-width Shift-JIS with 。/「/− drawn as . ' -.
- 2026-10-22 — `sound` (145 assets, 1396/1396) and `mmm_dat` (2/2) done. VHB = offset table + VAB; bundles are fixed sector chunks picked by tables read from the executable (Digimon → VLALL/VBALL set, map → ESALL set, music font → FAALL). ADPCM decode checked against wrong variants (no-filter is 10x rougher, swapped nibbles clip); SEQ tracks padded with 00 + CD fill. MMM.DAT is 27 MB of zeros (disc filler).
- 2026-10-22 — `efe` done (331 assets, 1029/1029): EFEDAT = 122 slots, slot N = technique N (effect id = technique + 0x100). Effect scripts disassembled by tracing the VM's control flow (99% of script bytes reached, rest kept raw); models textured via effect texture slot 0 (`updateTMDTextureData` moved to `formats/tmd.py`, shared with MMD). Renders checked: Fire Tower pillar, Magma Bomb rock, lightning bolts, Hurricane tornado.
- 2026-10-22 — `movies` done (4 assets, 20/20). The STR dump is complete (earlier "truncated" note was wrong): sectors keep their payload size (2048 video / 2324 audio) while the file table counts 2336. MDEC v3 decoder verified by the per-frame code count in every frame header (13,089/13,089) and by eye (BANDAI logo, Japan map, Digivice, credits). `.ogv` export via ffmpeg (Theora yuv420p + Vorbis, 16–21 MB per movie). All disc files are now converted or explained.
- 2026-10-24 — `maps`: door slots kept in `map.json` (`slot`; tables 1 and 6 start with an empty one), and object sprites get an STP mask (`object_<k>[_p<p>].stp.png`, `objects[k].stp_files`; `Vram.sample_page_stp`) for the semi-transparent blending (`../specs/map_objects.md`).
- 2026-10-24 — Models (`tmd_files`, `mmd_files`, `efe`, map doors): texture pages with STP texels get a `.stp.png` mask, named by the semi-transparent materials' `extras.stp_texture` (ISSUES.md I-5: the poop's subtractive shadow).
- 2026-10-24 — `music`: the songs rendered offline (`formats/libsnd.py` + `formats/spu.py`, `tests/test_music.py`). libsnd checked against DW's asm (key-on volume squared for songs only, `_SsVmSetVol` reads the voice's own tone, NRPN 20/30 loops with the count from data entry, the 240 Hz tick); `_svm_ptable` and `_spu_rev_param` (Studio B = entry 3) read from `SLUS_010.32`. ~2x real time per song in pure Python, one process per song.
- 2026-10-26 — `maps`: training slot machine textures for the maps that load the TRN overlay (0x70 TRAI00, 0x4E GIAS09, 0x77 MIST05; `loadTrainingLibrary`). The 4bpp page (704, 0) composed in load order, rows v 0xD8–0xF7 exported as `training/slots_p3.png` (symbols, CLUT (48, 486)) and `slots_p4.png` (reel window, CLUT (64, 486)) + `.stp.png` + `slots.json` (`Vram.page_indices`). All three maps give byte-identical strips (informational check); 244 assets, 1256/1256 checks; p3 has no STP colours, p4 all STP.
- 2026-10-26 — Battle step 5d-1 (`../specs/battle.md` §6): new family `btl_rel` (the battle overlay's TIM and finisher aura / confusion / stun / buff models, 14/14 checks, `specs/btl_rel.md`); `efe` also writes each raw slot (`effect.bin`) for the port's effect VM; `maps` adds `targets_partner` (`unk1 == 1`) to each map Digimon, keeping `unk1`.
- 2026-10-26 — `efe` listings: `BRANCH_IF` now reads "if (… op register) goto": the VM jumps when the comparison is true (`BTL_EFE_COMPARISONS` return 0 when true); the old text said "if not". Found while porting the VM (5d-2).
