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

## Music render (planned 2026-10-24)

The game never changes a song while it plays: fixed volume 0x50, no tempo, crescendo or pause calls (`sound.c` is the only caller of libsnd's sequence functions; game side: `../specs/sound.md` §2.3). So each song is rendered once, here, into a WAV that Godot plays. The render emulates libsnd's sequencer and voice manager (`asm/us/main/psyq/libsnd.s`; the matched C of the same library in `sotn-decomp` `src/main/psxsdk/libsnd/` is a reading aid) and the SPU (psx-spx). Module: `dwporter/formats/spu.py` (voice, ADSR, Gaussian interpolation, reverb) and `dwporter/formats/libsnd.py` (sequencer, voice allocation, volumes); family `music` (`dwporter/families/music.py`, `python -m dwporter convert music`; `DW_MUSIC_FONTS=1,2` for a subset) writes the renders.

Tables are read from the executable (`SLUS_010.32`, file offset = address − 0x80090000) with checks, not retyped:
- `_svm_ptable` @ `0x80128864`: 193 u16, the pitch of semitone `i / 16`, sixteenth `i % 16`, with 0x1000 = 44.1 kHz.
- `_spu_rev_param` @ `0x8012855C`: 0x44-byte entries, u32 mask, then 32 u16 registers (dAPF1, dAPF2, vIIR, vCOMB1–4, vWALL, vAPF1–2, mLSAME, mRSAME, mLCOMB1, mRCOMB1, mLCOMB2, mRCOMB2, dLSAME, dRSAME, mLDIFF, mRDIFF, mLCOMB3, mRCOMB3, mLCOMB4, mRCOMB4, dLDIFF, dRDIFF, mLAPF1, mRAPF1, mLAPF2, mRAPF2, vLIN, vRIN). Mode 3 (`SPU_REV_MODE_STUDIO_B`, used by `initializeMusic`) is "Studio Medium": dAPF1 0xB1, … vRIN 0x8000, work area 0x4840 bytes.

### Sequencer (libsnd, `SsSetTickMode(SS_TICK240)`: 240 ticks per second)

- **Opening (`SsSeqOpen`, `_SsInitSoundSeq`):**
  - resolution from the header; tempo in BPM = `60000000 / tempo` (integer);
  - each channel starts at program = channel, volume 127, pan 64;
  - the first delta is read.
  - Deltas are kept ×10 (`_SsReadDeltaValue`).
- **Tick increment `unk70`:**
  - `resolution · bpm · 10 / (240 · 60)`, plus 1 when the remainder is more than half;
  - when `resolution · bpm · 10 < 240 · 60`, the slow branch counts ticks between steps instead (`_SsSeqPlay`).
  - The same formula runs for the tempo meta event (`FF 51`).
- **Each tick (`SsSeqCalledTbyT`):**
  1. `_SsVmFlush` first: the register writes of the previous tick reach the SPU now, so an event sounds one tick (4.17 ms) after it is read.
  2. Then `_SsSeqPlay`: with the remaining delta above the increment, it is decreased by the increment. Otherwise events are read until the accumulated delta covers the increment, and the rest carries over.

  The render keeps this quantisation: 44100 / 240 = 183.75 samples per tick, with the fraction accumulated.
- **Events** (SEQ order: status / data, then the delta):
  - `9n` note on, velocity 0 = key off;
  - `Bn` control: 7 volume (also re-sets the channel's sounding voices, `_SsVmSetVol`), 10 pan (same), 6 data entry, 99 NRPN, others ignored;
  - `Cn` program;
  - `En` pitch bend: only the second (MSB) byte is used;
  - `FF 51` tempo, `FF 2F` end.
- **Loops (NRPN 99):**
  - **20** marks the loop start, just after it. The next data entry (CC 6) is the count; 127 means forever.
  - **30** is the loop end. With count 127 it jumps back to the start at once, the delta after it dropped. A smaller count jumps back count − 1 times.

  60 of the 74 songs use one forever-loop.
- **End `FF 2F`:**
  - a song played forever (`SSPLAY_INFINITY`) restarts from its first event, delta 0, with the sounding voices kept;
  - a song played once keys off all its voices (`_SsVmSeqKeyOff`) and stops.

  Fonts 0x1D track ≠ 1 and 0x1E–0x20 track ≠ 2 play once (`seqPlay`, `sound.c:488`).

### Voices (libsnd voice manager, 24 SPU voices)

- **Key-on (`_SsVmKeyOn`):**
  - every tone of the program with `min ≤ note ≤ max` gets a voice;
  - the voice's owner is the sequence, and it records the note, program and tone.
- **Allocation (`_SsVmAlloc`):**
  - the first voice that is neither keyed nor still sounding (envelope not 0);
  - otherwise the voice with the lowest priority below the tone's priority;
  - among equals, the lowest envelope level, then the oldest.
  - All voices age by 1, and the new one is reset to 0.
  - A voice whose envelope read 0 for 15 ticks in a row is freed (`_SsVmFlush`).
- **Volume (`_SsVmKeyOnNow`, DW asm):**
  - `v = velocity · ch_vol / 127`, then `v = v · mvol · 0x3FFF / 127²`, then `v = v · prog_vol · tone_vol / 127²` (integer divisions in this order);
  - `L = v · seq_vol_L / 127`, `R = v · seq_vol_R / 127` with seq vol 0x50;
  - three pan stages (tone pan, program pan, channel pan). Each, for `pan < 64`, does `R = R · pan / 63`, else `L = L · (127 − pan) / 63`;
  - then **squared**, `L = L² / 0x3FFF`, `R = R² / 0x3FFF` (sequence notes only), into the voice volume registers.
- **Pitch (`note2pitch`):**
  - `n = note + 60 − center`;
  - `p = _svm_ptable[(n % 12) · 16 + min(shift / 8, 15)]`;
  - shifted left by `n / 12 − 5` octaves (right when negative).
- **Pitch bend (`_SsVmPBVoice`):**
  - applies to the channel's sounding voices only, so a new note starts unbent;
  - `b = msb − 64`. Upward: `note + b · pbmax / 63`, fraction `(b · pbmax % 63) · 2`. Downward: `note + b · pbmin / 64 − 1`, fraction `(b · pbmin % 64) · 2 + 127`;
  - the result goes through `note2pitch2(note, fraction)`, whose fine part is `(fraction + shift) / 8` with a carry into the next semitone.
  - To confirm against DW's asm when coding.
- **ADSR registers:** the tone's `adsr1`, and `adsr2` plus the damper (0: no song uses CC 64).
- **Reverb:** the voice's bit is set at key-on when `tone.mode & 4` (319 of the 453 music tones).
- **Key-off:** a note-off finds the voices with the same note, program and owner, then starts their release.

### SPU (psx-spx; per 44.1 kHz sample)

- **Voice:**
  - The pitch counter advances by the pitch (clamped to 0x4000); bits 12+ index the sample, bits 4–11 the Gaussian table (4 points, 512-entry table).
  - The ADPCM block flags handle loops: loop start, loop end with repeat (jump), and loop end without repeat (mute: envelope 0).
  - ADSR as in `../specs/sound.md` §2.4.
  - Output: `sample · env >> 15`, then `· vol·2 >> 15` per side.
- **Reverb:** at 22.05 kHz on the summed reverb-bit voices.
  - Same-side and different-side reflections, 4 combs, 2 all-passes, on a 0x4840-byte ring;
  - values saturate at ±0x7FFF, products are `>> 15`, `vLIN` / `vRIN` 0x8000;
  - output × depth 0x7000 (`SpuSetReverbDepth`), added to the dry mix.
- **Mix:** voices + reverb, × main volume 0x3FFF·2, saturated to 16 bits.

### Output

- **`output/music/font_nn/track_<t>.wav`:** 16-bit stereo, 44.1 kHz.
  - **Songs that loop:** rendered through the intro, then the loop body twice. The `smpl` loop is the second pass, from the sample where the second jump back lands to where the third would, so the tails and the reverb carried into the loop are already in it.
  - A song looping at `FF 2F` (no markers) does the same with the whole song.
  - **Songs that play once:** rendered until the key-off's release and the reverb fall silent; no loop.
- **`output/music/index.json`:** the render settings (rate, tick rate, seq volume, reverb preset and registers, the pitch table) and per track: the source span (asset id, sha1), play mode, length, the libsnd ticks, the loop ticks and sample positions, the loop / restart / end events, peak, clipped samples, render time.
- **Cost:** 74 songs, 44 minutes of music for one pass of each, about 70 minutes with the second loop pass. That is about 0.7 GB of WAV. Pure Python, with one song per process (`multiprocessing`).

### Checks

- The tables read from the executable: `_svm_ptable[0]` = 0x1000, `[192]` = 0x2000; `_spu_rev_param` entry 1 = Room (dAPF1 0x7D), entry 3 = Studio Medium (dAPF1 0xB1).
- Every song renders to its end or its loop.
- The loop's second pass is as long as the body in ticks.
- No sample clips more than a set number of times.
- Unit tests:
  - ADSR step vectors (the same as the Godot `SpuEnvelope` tests);
  - a Gaussian interpolation sum;
  - the pitch of a note at its centre = 0x1000;
  - the libsnd volume formula against values worked out from the asm.

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
| `index.json` | slot table, per file the chunks (offset, size, folder), and the raw tables (`DIGIMON_VLALL/VBALL_SOUND_ID`, `MAP_SOUND_PARA`, `ENEMY_MUSIC_MAPPING`, SPU start addresses, `svm_ptable`: libsnd's pitch table `_svm_ptable` @ `0x80128864`, for the game's sound effects); each `bank.json` `usage` names the Digimon types / maps / font that load it |

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
- Preview renders (human check, 2026-10-22): the samples (WAV) sound correct, and the field-music previews (fonts 1, 2) sound right. The battle previews (font 33, tracks 0 and 3) have a chirping sound in the background, though the music is recognisable. Most likely cause: the quick preview renderer (and the preview SF2) ignore the VAB envelopes (adsr1/adsr2), so short looped percussion/synth samples keep playing at full volume instead of fading. Pitch bend and vibrato (vibrato_*, pitchbend_*) are also ignored, and there's no reverb. The data itself is not suspected. To fix when audio is improved: convert ADSR to SF2 envelopes (or apply them in the Godot player), and add pitch bend, vibrato and the SEQ volume (0x50).
