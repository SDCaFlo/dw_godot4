# Battle overlay assets — `btl_rel` (`BTL_REL.BIN`)

Family: `dwporter/families/btl_rel.py` (`python -m dwporter convert btl_rel`).

The battle overlay carries, before its code, one texture and four small models used by the battle's own visuals (not the technique effects, which are EFEDAT: `specs/efe.md`). The port draws them in step 5d-5 (`../../specs/battle_effects.md` §4).

The arena overlay (`STD_REL.BIN`, step 4e-4) embeds the same texture and four models at the same offsets (0x0–0x4188, `dw_decomp/config/us/std.yaml`), byte-for-byte identical to `BTL_REL.BIN`, so the arena uses this family's output directly.

## On disc

`BTL_REL.BIN`, `FILE_OFFSET_TABLE` (`file_table_us.c:807`) size `0x2349C`, loaded at `0x80052AE0`. Segments (`dw_decomp/config/us/btl.yaml`):

| Offset | Address | Segment | Content | C symbol (`src/main/btl.c:23–27`) |
|---|---|---|---|---|
| 0x0 | 0x80052AE0 | `texture` | TIM, 4 bpp 136 × 48, VRAM (768, 448), CLUT (192, 500) × 2 | `BTL_FINISHER_TIM` |
| 0xD20 | 0x80053800 | `model_0` | TMD, 5 objects: the finisher aura | `BTL_FINISHER_MODEL` |
| 0x1D58 | 0x80054838 | `model_1` | TMD, 1 object: confusion | `BTL_CONFUSION_MODEL` |
| 0x2220 | 0x80054D00 | `model_2` | TMD, 1 object: stun | `BTL_STUN_MODEL` |
| 0x2848 | 0x80055328 | `model_3` | TMD, 7 objects: buff rings / disk | `BTL_BUFF_MODEL` |
| 0x4188 | 0x80056C68 | `header` | the overlay's code and data follow | |

## Original handling

`loadBattleData` (`btl.c:427–450`), after the overlay is loaded:
- `BTL_initializeFinisherAuraModel(BTL_FINISHER_TIM, BTL_FINISHER_MODEL)` (`battle_effect.c:5957`): `LoadImage` of the TIM at **its own** VRAM rect and CLUT, `GsMapModelingData`, then `BTL_setTMDObjectColor` on objects 0–4 (two colours, `BTL_D_8007380C` / `BTL_D_8007381C`).
- `BTL_initializeConfusionEffect(BTL_CONFUSION_MODEL)` (`:5534`), `BTL_initializeStunEffect(BTL_STUN_MODEL)` (`:5582`): `GsMapModelingData`.
- `initializeBuffModel(BTL_BUFF_MODEL)` (`main/buff_model.c`).

The models are drawn with the VRAM of a field session: `ETCDAT/ETCTIM.BIN` (`main.c:3434`) plus the overlay TIM.

## Godot representation

`output/btl_rel/`: `texture.png` (+ `.p1.png`, the second CLUT row) + `texture.json`; `finisher_aura`, `confusion`, `stun`, `buff` as `.gltf` / `.bin` + `_tex/` pages + sidecar, as `tmd_files` writes them (textures built from `ETCTIM.BIN` + the overlay TIM). Object colours set at run time (`BTL_setTMDObjectColor`) are the port's job, not the export's.

## Metadata

Sidecars as every TMD / TIM export; the model sidecar adds `model.symbol`, `model.description`, `model.texture_files`.

## Verification

File size; a TIM at 0x0 ending before 0xD20; each TMD parses at its segment offset and ends before the next one; every textured polygon's page is covered by the VRAM built from `ETCTIM.BIN` + the overlay TIM; bytes 0–0x4188 match `STD_REL.BIN` byte-for-byte (`config/us/std.yaml`). 15 checks.

## Open questions

- The stun model's page (896, 256, CLUT row 482) is the system sprite page; whether the battle changes that CLUT row at run time is to check when the stun visual is drawn (5d-5).
- The confusion model is untextured (flat colours).
