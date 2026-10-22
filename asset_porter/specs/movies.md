# Movies — `movies` (`MOVIE/*.STR`)

Format: `dwporter/formats/strmovie.py`. Family: `dwporter/families/movies.py` (`python -m dwporter convert movies`).

## On disc

| File | `FILE_OFFSET_TABLE` (`file_table_us.c:750–753`) | `MOV_MOVIES` (`src/mov/mov.c:46`) | Played (`main.c`) |
|---|---|---|---|
| `OP1.STR` | `0x296FD00` = 18,600 × 2336 | movie 0, last frame 3637 | :3418, :3427 (opening) |
| `OP2.STR` | `0x2464A00` = 16,336 × 2336 | movie 1, last frame 3266 | :3442 |
| `ED2.STR` | `0x1D8CA00` = 13,264 × 2336 | movie 2, last frame 2654 | :3476 |
| `EDR.STR` | `0x2675E00` = 17,264 × 2336 | movie 3, last frame 3447 (cannot be skipped) | :3527 |

The table counts every sector as 2336 bytes (Mode 2 raw user data). The dumped files keep each sector's payload: **7 video sectors of 2048 bytes, then 1 XA audio sector of 2324 bytes**, repeating; a few empty 2048-byte video slots at the end. Sector counts match the table exactly; only the 8-byte CD subheaders (XA file/channel/coding info) are not in the files. Audio sectors = sectors / 8.

### Video sector (2048 bytes)

32-byte STR header (libpress `StHEADER`): `60 01 01 80` (0x0160, 0x8001), u16 chunk, u16 chunks in frame, u32 frame number (1-based), u32 frame bitstream size, u16 width (320), u16 height (176), u16 MDEC code count field, u16 0x3800, u16 qscale, u16 version (3), u32 0. Then 2016 bytes of the frame's bitstream. A frame = its chunks' payloads in order, cut to the bitstream size.

### Bitstream (libpress `DecDCTvlc2` → MDEC)

8-byte header: u16 code count field (= MDEC codes / 2 rounded up to 32), u16 0x3800, u16 qscale, u16 version. Then 16-bit little-endian words read MSB first:

- 16×16 macroblocks, column by column (x outer, y inner); 6 blocks each: Cr, Cb, Y top-left, Y top-right, Y bottom-left, Y bottom-right.
- DC: v2 = 10-bit signed; v3 = MPEG-1 DC size code (luma / chroma tables) + difference bits; value = previous (per Y / Cb / Cr, reset each frame) + difference · 4.
- AC: MPEG-1 table B.14 codes + sign bit; `000001` escape + 6-bit run + 10-bit level; `10` end of block.
- Dequantisation (MDEC): DC · 2; AC `(level · Q[j] · qscale + 4) >> 3`, Q = MPEG-1 intra matrix with Q[0] = 2, zigzag order.
- 8×8 IDCT, YCbCr → RGB (R = Y + 1.402 Cr, G = Y − 0.3437 Cb − 0.7143 Cr, B = Y + 1.772 Cb, + 128), 4:2:0 chroma. `DecDCTin(…, 3)`: 24-bit output.

### Playback (`src/mov/mov.c`)

`CdRead2(CdlModeStream | CdlModeSpeed | CdlModeRT …)`: double speed = 150 sectors/s, so 300 frames take 300 · sectors-per-frame / 150 s (~30 fps); XA audio is played by the CD hardware (37.8 kHz stereo: 18.75 audio sectors/s × 2016 samples per channel). Picture drawn at (0, 32) on the 320×240 screen (letterbox). `MOV_readFrame` stops when the frame number reaches `MOV_MOVIES[id].frameCount`; frames after it are black fade-out padding.

### XA audio sector (2324 bytes)

18 sound groups of 128 bytes (+ 20 bytes padding): 16 bytes of parameters (unit k uses byte 4 + k: shift = low nibble, filter = bits 4–5), 112 bytes of data = 28 rows × 4 bytes, 8 units × 4-bit samples; even units left, odd right. `sample = (nibble << 12 >> shift) + (s1·K0 + s2·K1 + 32) >> 6`, K0 = 0, 60, 115, 98; K1 = 0, 0, −52, −55.

## Godot representation

`output/movies/<NAME>/`:

| File | Content |
|---|---|
| `audio.wav` | XA audio, 16-bit stereo 37.8 kHz, whole stream |
| `preview/frame_<n>.png` | every 60th frame (2 s) + the last frame the game shows (human check) |
| `movie.ogv` | **only if ffmpeg is available** (`PATH` or `DW_FFMPEG`; needs libtheora + libvorbis, e.g. `winget install Gyan.FFmpeg`): Theora (yuv420p, like the source) + Vorbis 37.8 kHz stereo of frames 1 … game's last frame at the exact frame rate (frames / (sectors / 150)), audio cut to the same length — the format Godot's `VideoStreamPlayer` plays |
| `frames/frame_<n>.png` | every frame, only with `DW_MOVIE_ALL_FRAMES=1` (~100 KB each, ~1.3 GB for all movies) |
| `movie.json` | identity, sector map (`V`/`A`/`E` per sector), per-frame header + decode statistics, frame rate, audio info, game cut-off |

The STR file stays the lossless source: every frame's bitstream is identified by its sectors (offsets in `movie.json`), the outputs are decodes.

## Verification

- Sector walk ends exactly at the file end; sector count = table size / 2336; every 8th sector is audio, others video or trailing empty.
- Frames numbered 1 … N without gaps; chunks complete and in order; bitstream size ≤ chunks · 2016.
- Every frame decodes; decoded MDEC code count / 2 rounded up to 32 = the header's count field (proves the VLC tables and block structure); bits used ≤ bits available.
- Audio duration = video duration (sectors / 150 s); no clipping.

## Open questions

- The hardware MDEC uses an integer IDCT; the float IDCT here can differ by ±1 per channel.
- XA coding info (rate/stereo) is inferred from timing (audio length = video length), the subheaders are not in the dump.
