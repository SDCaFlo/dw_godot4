# Sound — `sound` (`SOUND/VHB/*.VHB`) and `MMM.DAT`

Formats: `dwporter/formats/vab.py` (VHB container, VAB bank, PSX ADPCM), `dwporter/formats/seq.py` (SEQ → MIDI). Exporters: `exporters/wav.py`, `exporters/sf2.py`. Families: `dwporter/families/sound.py`, `dwporter/families/mmm_dat.py`.

## On disc

| File | `FILE_OFFSET_TABLE` (`file_table_us.c:756–762`) | Layout | Loaded by (`src/main/sound.c`) | VAB slot |
|---|---|---|---|---|
| `SS.VHB` | `0xDF5C` | one VHB | `initializeMusic` → `readVHBFile(0, "SOUND\\SS")` | 0 (system sounds) |
| `SL.VHB` | `0xD90C` | one VHB | `initializeMusic` → slot 1 | 1 |
| `SB.VHB` | `0x3CACC` | one VHB | `VSLoadSounds` (VS mode) | 8 |
| `ESALL.VHB` | `0x387000` | 22 VHBs at `MAP_SOUND_PARA[i]` = (sector·2, sectors·2) | `loadMapSounds(MAP_ENTRIES.flags & 0x1F)` | 8 (map sounds) |
| `VLALL.VHB` | `0x78000` | 16 VHBs × 15 sectors | `loadPartnerSounds(type)`: chunk `DIGIMON_VLALL_SOUND_ID[type]` (types 1–65, else 15) | 3 |
| `VBALL.VHB` | `0xF8800` | 71 VHBs × 7 sectors | `loadDigimonSounds(slot 4–7, type)`: chunk `DIGIMON_VBALL_SOUND_ID[type]` | 4–7 |
| `FAALL.VHB` | `0x283800` | 33 VHBs × 0x27 sectors (music fonts 1–33) | `loadMusicFont(font)`: chunk `font − 1`; SEQ section → `SEQ_BUFFER` | 2 |

Tables (executable, `config/us/symbols.txt`): `DIGIMON_VLALL_SOUND_ID` @ `0x80127EFC` (66 × u8), `DIGIMON_VBALL_SOUND_ID` @ `0x80127F40` (180 × u8), `MAP_SOUND_PARA` @ `0x80127FF4` (22 × {u16 sector·2, u16 count·2}), `VHB_SOUNDBUFFER_START` @ `0x80127ED4` (SPU addresses per slot), `ENEMY_MUSIC_MAPPING` @ `0x8012BAE4` (battle track per enemy type).

### VHB

`u32 offsets[]`, count = `offsets[0] / 4`: section 0 = VAB header (VH), 1 = VAB body (VB), last = end of data. FAALL chunks: VH, VB, SEQ table, end. The rest of a fixed-size chunk is zero.

### VAB (libsnd)

| Part | Size |
|---|---|
| VabHdr: `"pBAV"`, u32 version (7), u32 id, u32 fsize (VH + VB), u16 reserved, u16 programs, u16 tones, u16 vags, u8 master volume, u8 master pan, u8 attr1, u8 attr2, u32 reserved | 32 |
| ProgAtr[128]: u8 tones, volume, priority, mode, pan, reserved; s16 attr; u32 × 2 reserved | 2048 |
| VagAtr[programs][16]: u8 priority, mode, volume, pan, **center** (root note), **shift** (fine tune, 1/128 semitone), **min, max** (key range), vibrato w/t, portamento w/t, pitch bend min/max, 2 reserved; u16 adsr1, adsr2; s16 program, **vag**; 4 × s16 reserved | 512 × programs |
| u16 vag_sizes[256] (size / 8; entry 0 unused) | 512 |

Tone block k belongs to the k-th program with `tones > 0` (FAALL fonts skip program numbers; every tone's `program` field confirms the mapping). VB = the VAGs (samples) back to back. In 14 VBALL chunks `vags` counts one sample more than the size table lists; the extra bytes after the listed samples are not referenced by any tone and are kept raw.

### Samples (PSX SPU ADPCM)

16-byte blocks: `shift | filter << 4`, flags (bit 2 loop start, bit 0 end, bit 1 repeat), 14 bytes = 28 4-bit samples. `sample = (nibble << 12 >> shift) + (s1·f0 + s2·f1 + 32) >> 6`, filters (0,0) (60,0) (115,−52) (98,−55) (122,−60) / 64. Played at the tone's `center` note the SPU reads them at 44.1 kHz; another note plays at 44100 · 2^((note − center + shift/128)/12).

### Sound effects (`playSound`, `startSound`)

`playSound(slot, value)`: slots 0, 1, 8 → program `value / 16`, note `value % 16 + 60`; slots 3–7 → program 0, note `value`. `startSound` keys on **every tone of the program whose `max` equals the note** (each effect = one or more samples). Script `PLAY_SOUND bank, sound` and MMD animation sound events (`bank`, `sound`) use this.

### Music (`playMusic(font, track)`)

FAALL chunk `font − 1`: VAB = the instruments (slot 2); SEQ section = `u32 offsets[]` (count = `offsets[0] / 4`) to `count` SEQs ("tracks"; day/night variants; font 33 = battle, 4 tracks, track chosen by `ENEMY_MUSIC_MAPPING`). Tracks are 4-byte aligned: each is followed by 1–4 bytes, `00` then `CD` fill (the build tool's uninitialised memory, as in MMD files). `seqPlay` loops them forever except fonts 0x1D–0x20 (played once unless track 1 / 2). Scripts: `SET_BGM bgm` → `playBGM` → font = bgm, track from `handleMusicOverride` (pstat 245, day/night by hour).

SEQ: `"pQES"`, u32 BE version, u16 BE resolution (480), u24 BE tempo (µs per quarter), u8 × 2 rhythm, MIDI events (variable-length deltas, running status); `FF 51 t t t` tempo and `FF 2F` end have no length byte. Loop markers: CC 99 (NRPN) = 20 loop start, 30 loop end.

## Godot representation

`output/sound/`:

| Path | Content |
|---|---|
| `<FILE>/` (SS, SL, SB) or `<FILE>/<set>/` (`ESALL/set_00`–`21`, `VLALL/set_00`–`15`, `VBALL/set_00`–`70`, `FAALL/font_01`–`33`) | one VAB |
| `…/vag_<nn>.wav` | sample nn (VAB numbering), 16-bit mono 44.1 kHz; loop points in a `smpl` chunk (Godot's WAV importer reads them) |
| `…/bank.json` | identity (source span), VHB offsets, VAB header, programs, tones (+ `pitch_at_note` formula inputs), samples (offset, size, loop, sha1 of the ADPCM bytes), unreferenced bytes (raw hex), usage |
| `…/bank.sf2` | **preview** soundfont: one preset per program (bank 0, also bank 128 so MIDI channel 10 plays), key ranges, root key, fine tune, pan, volume, loops. Envelopes (ADSR) are not converted. |
| `FAALL/font_nn/track_<t>.seq` | the SEQ bytes, unchanged |
| `FAALL/font_nn/track_<t>.mid` | Standard MIDI (format 0) with the same events; play with `bank.sf2` to hear the song |
| `index.json` | slot table, per file the chunks (offset, size, folder), and the raw tables (`DIGIMON_VLALL/VBALL_SOUND_ID`, `MAP_SOUND_PARA`, `ENEMY_MUSIC_MAPPING`, SPU start addresses); each `bank.json` `usage` names the Digimon types / maps / font that load it |

## Verification

- Sizes match the file table; chunk counts match the code (16, 71, 33; 22 ESALL ranges tile the file exactly).
- Every VHB: offsets ascending; VAB magic/version; VH size = 32 + 2048 + 512·programs + 512 = VB offset; `fsize` = VB end − VH start; programs with tones = `programs`; tone counts sum to `tones`; every tone's `program` matches its block and `vag` ≤ `vags`; listed sample sizes fit in VB; chunk tail after the end offset is zero.
- ADPCM: filters ≤ 4 in every block.
- SEQ: every track parses to `FF 2F`; tracks end 1–4 bytes before the next offset (`00` + `CD` fill).
- Every VBALL set is used by at least one Digimon type.
- `MMM.DAT`: all 27,648,000 bytes are zero (13,500 sectors) and no code references it: disc filler, nothing to convert.

## Open questions

- ADSR (`adsr1/adsr2`) → envelopes, reverb (`SpuSetReverb`, studio B) and the SEQ volume (0x50) are not applied in the preview SF2; the raw values are in `bank.json`.
- Which VBALL/VLALL sound numbers map to which animation/battle sounds is in the animation and battle code (MMD sound events give `bank`, `sound`).
