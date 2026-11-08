# Sound and music (port spec)

Status (2026-10-24): ported with step 5c of `specs/script.md` §3.1: the `Sound` autoload (`scripts/audio/sound_system.gd`, `spu_voice.gd`, `spu_envelope.gd`, `sound_bank.gd`, `music_player.gd`, `animation_sounds.gd`), the songs rendered by the asset porter's `music` family; `tests/test_sound.gd`, `asset_porter/tests/test_music.py`; VERIFY "Sound".

The game's audio on the field:
- **Music:** the map's song (`SET_BGM`), its day / night variant, songs started by scripts.
- **Sound effects:** text boxes and windows, script sounds (`PLAY_SOUND`), the models' animation sounds (footsteps, voices), the tamer and partner actions already ported.
- **The banks behind them:** the system banks, the map's set, the partner's voice and sound banks.

Menus, battles, minigames and the death scenes use the same functions; they get wired when those systems are ported.

The formats (VAB banks, PSX ADPCM samples, SEQ songs) and the files are in `asset_porter/specs/sound.md`. The asset porter also renders the music to WAV with an emulation of libsnd and the SPU (that spec, "Music render"). This spec covers the game side.

All `file:line` references are in `external-resources/dw_decomp/src/main/` (US) unless they name another folder. libsnd is the Psy-Q sound library linked into the executable: its code is in `asm/us/main/psyq/libsnd.s` (assembly only). The matched C of the same library in the Symphony of the Night decomp (`sotn-decomp`, `src/main/psxsdk/libsnd/`, MIT) is a reading aid. Every rule below was checked against DW's own assembly where the two could differ, and the differences are noted.

## 1. C functions reproduced

| C | What | Godot |
|---|---|---|
| `initializeMusic` (`sound.c:517`) | libsnd start, the SS (slot 0) and SL (slot 1) banks, master volume 127, reverb Studio B depth 0x7000 | `Sound` autoload `_ready` |
| `readVHBFile`, `readVHBFileSectors` (`sound.c:385`, `:446`), `loadVHBFile` (`sound_async.c`) | a bank into a VAB slot (0–8) | `Sound.load_bank(slot, path)` |
| `loadMapSounds`, `loadMapSounds2` (`sound.c:721`, `sound_async.c:233`); `getMapSoundId` (asm `map.s`: `MAP_ENTRIES[id].flags & 0x1F`) | the map's ESALL set into slot 8, skipped when it is already loaded | `Sound.load_map_sounds(set)`, from the map record's `sound_bank` |
| `loadPartnerSounds`, `loadDigimonSounds` (`sound.c:676`, `:694`) | the partner's VLALL voice set (slot 3) and VBALL set (slot 4) | `Sound.load_partner_sounds(digimon)`, from `GameData.digimon_sounds` |
| `playSound`, `playSound2`, `startSound` (`sound.c:641`, `:666`, `:602`) | a sound effect: every tone of the program whose `max` is the note | `Sound.play_sound(slot, value) -> mask` |
| `getNextFreeChannel` (`sound.c:567`) | the next idle voice among 10–23, round robin | `Sound._next_free_channel()` |
| `stopSoundMask`, `stopSound` (`sound.c:629`, `:650`) | fade to 0 and key off | `Sound.stop_sound_mask(mask)`, `Sound.stop_sound()` |
| `SsUtKeyOnV`, `SsUtKeyOffV`, `SsUtAutoVol` (libsnd) | the sound-effect voice: volume, pan, pitch, ADSR, reverb | `SpuVoice` (§2.4) |
| `playMusic`, `loadMusicFont`, `seqOpen`, `seqPlay`, `seqStop`, `seqClose`, `stopBGM` (`sound.c:753`, `:738`, `:475`, `:488`, `:420`, `:429`, `:779`) | one song of a music font | `Music.play_music(font, track)`, `Music.stop_bgm()` |
| `playBGM`, `updateBGM`, `forceUpdateBGM`, `resetBGM`, `handleMusicOverride` (`script_interp.c:2587`, `:2608`, `:2629`, `:2377`, `:1584`) | the map's music with its day / night variant and the script overrides | `Music.play_bgm(id)`, `update_bgm()`, `force_update_bgm()`, `reset_bgm()`, `_music_override(font)` |
| `PLAY_SOUND`, `SET_BGM`, `STOP_BGM` (`scriptInstruction5Ato5F`, `script_interp.c:1557–1575`) | the script opcodes 0x5A, 0x5D, 0x5E | `ScriptInterpreter` |
| `tickGameClock` → `updateBGM` (`clock.c:171`) | the variant follows the hour | `Clock.tick_game_clock` |
| `renderAnimation` sound event `0x4000` (`anim.c:336`) | a model's animation plays a sound when it is on screen | `PsxAnimator` signal, `FieldDigimon` / `Tamer` |
| Text box and window sounds (`script_textbox.c:238–387`, `ui.c:223`, `:336`) | ✕ 3, △ 4, choice moves 2, choice ✕ 0xB; window opens 0, closes 1 | the existing `TextBoxes.sound` / `UIBoxes.sound` signals → `Sound.play_sound(0, id)` |

## 2. Original behaviour

### 2.1 Banks (VAB slots)

The SPU holds nine banks at once, each in a fixed slot (`VHB_SOUNDBUFFER_START`, `sound.c:47`):

| Slot | Bank | Loaded |
|---|---|---|
| 0 | `SS` (system sounds) | at start, kept |
| 1 | `SL` (footsteps and common animation sounds) | at start, kept |
| 2 | the current music font (`FAALL` chunk) | `loadMusicFont`, when the font changes |
| 3 | the partner's voice (`VLALL` set) | `loadPartnerSounds(type)`: `DIGIMON_VLALL_SOUND_ID[type]` for types 1–65, else set 15 |
| 4 | the partner's sounds (`VBALL` set) | `loadPartnerSounds` → `loadDigimonSounds(4, type)`; in battle 4–7 are the fighters (`btl.c:412`) |
| 5–7 | other Digimon (`VBALL` sets) | battles; builtin 0x33 loads VBALL set 0x73 into slot 5 (`script_interp.c:1845`) |
| 8 | the map's set (`ESALL`), or `SB` in VS mode | `loadMapSounds(getMapSoundId(map))` at every map load (`map.c:4084`); special sets: 19 at evolution (`partner.c:655`), 20 the ending, 21 the boss (`script_interp.c:1846`, `:1851`) |

`loadMapSounds` and `loadMapSounds2` do nothing when the set is already loaded (`ACTIVE_MAP_SOUND_ID`).

### 2.2 Sound effects (`playSound`)

- **Which tones play:**
  - Slots 0, 1, 8: program `value / 16`, note `value % 16 + 60`.
  - Slots 3–7: program 0, note `value`.
  - Slot 2 and others: nothing (the function returns without a value).
  - `startSound` keys on **every tone of the program whose `max` equals the note**. One effect can be several samples at once.
- **Voices:**
  - Each tone gets a voice from `getNextFreeChannel`. It scans the 14 voices 10–23, starting after the last one used (`FREE_CHANNEL_INDEX`), and takes the first whose key status isn't on.
  - If all 14 are busy, it takes the next one in turn anyway, cutting what it played.
  - The key-on is `SsUtKeyOnV(voice, slot, prog, tone, note, 0, 0x7F, 0x7F)`.
  - `playSound` returns the mask of the voices used.
- **`stopSoundMask(mask)`:** for each voice in the mask, `SsUtAutoVol(voice, 0x7F, 0, 6)` then `SsUtKeyOffV`. `stopSound` does the same for every voice 10–23 that is on, after `SsUtAllKeyOff(0)`.
- **The voice (libsnd `SsUtKeyOnV` → `_SsVmKeyOnNow`, asm `libsnd.s`):**
  - **Volume:** `v = 0x7F · mvol · 0x3FFF / 127²`, then `v = v · program volume · tone volume / 127²`. `mvol` is the bank's master volume, 127 in every bank.
  - **Pan:** three stages (tone pan, program pan, the key-on's pan 0x40). Each one, for `pan < 0x40`, scales the right side by `pan / 63`; otherwise it scales the left by `(127 − pan) / 63`.
  - **No squaring for sound effects:** in DW's libsnd the `v² / 0x3FFF` curve only applies to sequence notes (the voice's owner ≠ 0x21). The newer libsnd of `sotn-decomp` squares every voice.
  - **Pitch:** `note2pitch2(note, 0)`. The tone's `shift` (fine tune) / 8 picks one of 16 steps per semitone in libsnd's pitch table `_svm_ptable` (`0x80128864`: 12 × 16 + 1 entries, 0x1000 = 44.1 kHz at the tone's `center`), shifted by octaves.
  - **Envelope:** the tone's `adsr1` / `adsr2`, run by the SPU (§2.4).
  - **Reverb:** only when the tone's `mode & 4`. `_SsVmKeyOnNow` sets or clears the voice's reverb bit at every key-on, overriding `initializeMusic`'s "all voices on". 2 SS tones and 60 ESALL tones have it; no SL, VLALL or VBALL tone does.
- **Sample end:** a sample without a loop ends on its last block, which mutes the voice. A looped sample keeps playing at the sustain level until a key-off: 22 tones loop like this (ESALL sets 13, 14, 18, 19, 21; SB; SL program 1 note 73).

### 2.3 Music

- **`playMusic(font, track)`:**
  - Fonts 1–33. Any other font returns 0, playing nothing.
  - Nothing happens if this font and track already play.
  - Otherwise: stop and close the song, load the font if it changed (its instruments into slot 2, its songs into `SEQ_BUFFER`), and open the track (track 0 if `track` is past the font's count).
  - Then `SsSeqSetVol(0x50, 0x50)` and play:
    - fonts 0x1D (track ≠ 1) and 0x1E–0x20 (track ≠ 2) play once;
    - every other song loops forever.
- **`stopBGM`:** stop and close, `CURRENT_SEQ_TRACK = −1`. So the next `playMusic` always restarts, even for the same song.
- **`playBGM(id)`:**
  - `id == 0xFF`: `resetBGM`, which is `ACTIVE_BGM_FONT = 0xFF` plus `stopBGM`.
  - Otherwise: font = `id`, then `handleMusicOverride(&font, &variant)`, `ACTIVE_BGM_FONT = font`, `ACTIVE_BGM_TRACK = variant`, `stopBGM`, `playMusic(font, variant)`.
  - Because `playBGM` stops first, entering a map with the same song restarts it (the map scripts call `SET_BGM` at each entry).
- **`handleMusicOverride`, by script value 245:**

  | 245 | font | variant |
  |---|---|---|
  | 0 | unchanged | 0 from 6:00 to 20:59, else 1 |
  | 1 | unchanged | 0 |
  | 2 | 6 | 2 |
  | 3 | 0x0B | 2 |
  | 4 | 0x0F | 2 |
  | 5 / 6 | 0x15 | 0 / 1 |
  | 7 / 8 | 0x1A | 0 / 1 |
  | 9 / 10 | 0x1B | 0 / 1 |
  | other | unchanged | left unset (the caller's stack byte) |

  **Quirk kept:** the active font becomes the overridden one, so after an override `updateBGM` starts from that font.
- **`updateBGM`** (every frame the clock runs, `clock.c:171`):
  - with `ACTIVE_BGM_FONT == 0xFF`, it calls `resetBGM`;
  - otherwise it applies the override, and restarts the music only if the font or variant changed.

  That is how the field songs switch at 6:00 and 21:00. `forceUpdateBGM` always restarts.
- **Script opcodes:**
  - `PLAY_SOUND bank, sound` (0x5A, 501 uses) is `playSound`.
  - `SET_BGM id` (0x5D, 527 uses) is `playBGM`.
  - `STOP_BGM x` (0x5E) is `resetBGM`; its byte is ignored.
  - The `0xFB` load-map command calls `resetBGM` (`script_interp.c:2852`).
  - `START_BATTLE` calls `stopBGM` (`script_interp.c:1913`); after a won battle the tamer state calls `playBGM(ACTIVE_BGM_FONT)` (`tamer.c:862`).
- **What libsnd does with a song** is reproduced by the asset porter's renderer, since nothing in the game changes a song while it plays:
  - the volume is fixed at 0x50;
  - libsnd's tempo, crescendo, pause and replay functions are never called;
  - the game only opens, plays, stops and closes.

  So each song is played back from the rendered WAV, looping where libsnd loops (the porter's spec, "Music render").

### 2.4 The SPU voice (sound effects at run time)

The hardware rules come from psx-spx ("Sound Processing Unit"). The asset porter's renderer implements the same ones for the music.
- **Pitch:** a counter advances by the pitch register every 44.1 kHz cycle; 0x1000 plays the sample at its own rate.
- **ADSR** (`adsr1` / `adsr2`, the envelope level 0..0x7FFF):
  - **Attack:** linear or exponential, up to 0x7FFF. Rate = bits 14–8 of `adsr1` (shift = bits 14–10, step = bits 9–8).
  - **Decay:** exponential down to the sustain level `(bits 3–0 + 1) · 0x800`, shift = bits 7–4 of `adsr1`.
  - **Sustain:** linear or exponential, up or down, until key-off. Rate = bits 12–6 of `adsr2`; mode = bit 15, direction = bit 14.
  - **Release** after key-off: linear or exponential, down to 0; shift = bits 4–0 of `adsr2`, mode = bit 5.
  - **Each step:**
    1. `step = 7 − (rate & 3)` (inverted to `−8 + (rate & 3)` when decreasing), `step <<= max(0, 11 − shift)`, `increment = 0x8000 >> max(0, shift − 11)`.
    2. Exponential increase above 0x6000: the step is divided by 4 (shift < 10), the increment is divided by 4 (shift ≥ 11), or both are halved (shift 10).
    3. Exponential decrease: `step = step · level / 0x8000`.
    4. The increment is at least 1 unless the rate is all ones (0x7F; 0x1F for decay / release), which never steps.
    5. Each cycle `counter += increment`. When bit 15 is set, the counter is reset to 0, the level moves by the step, and it is clamped to 0..0x7FFF.
  - Key-on starts the attack at level 0.
- **Output:** `sample · level / 0x8000 · volume / 0x4000` per side.
  - The volume register holds volume / 2: 0x3FFF is full.
  - The main volume is `SsSetMVol(127, 127)`, which is full.
- **Reverb (Studio B):** voices with the reverb bit also feed the reverb unit. Depth is 0x7000 both sides, with the preset at `_spu_rev_param[3]` (`0x8012855C + 3 · 0x44`; checked in `SLUS_010.32`: Room is entry 1, Studio Medium entry 3).

## 3. Godot design

- **`Sound` autoload** (`scripts/audio/sound.gd`): the sound-effect side of `sound.c` plus libsnd's voice functions for sound effects.
  - **Slots:** `slots[0..8]`, each a loaded bank (`SoundBank`: programs, tones, samples as `AudioStreamWAV` from the asset porter's `vag_<nn>.wav`, loops from their `smpl` chunk).
  - **Voices:** 14 `SpuVoice` nodes for voices 10–23. Each has an `AudioStreamPlayer` with the tone's sample, `pitch_scale = pitch / 0x1000`, and per-side volume from §2.2 (an `AudioStreamPlayer` per side panned through two buses, or one player with a panner effect; the simplest that keeps the exact L / R gains).
  - **Envelope:** `SpuEnvelope` (`scripts/audio/spu_envelope.gd`, §2.4, the same integer steps as the porter's renderer) is advanced by the 44.1 kHz cycles elapsed since the last Godot frame. The player's volume follows the envelope level and is updated every frame. The envelope is exact, but it is applied at the frame rate instead of per sample (a deliberate difference).
  - A voice ends when its sample ends (no loop) or its envelope reaches 0 after key-off. `getNextFreeChannel` reads that as "key status off".
  - **Reverb:** a voice with `mode & 4` plays on the `SfxReverb` bus (a Godot `AudioEffectReverb`, tuned by ear to Studio B), the others on `Sfx`. This is a deliberate approximation; the music's reverb is the exact one, baked in by the renderer.
  - `play_sound(slot, value) -> int` (the voice mask), `stop_sound_mask(mask)`, `stop_sound()`, `load_bank(slot, path)`, `load_map_sounds(set)`, `load_partner_sounds(digimon)`.
- **`Music`** (`scripts/audio/music.gd`, a node in the `Sound` autoload): the music side.
  - **State:** `ACTIVE_BGM_FONT`, `ACTIVE_BGM_TRACK`, `CURRENT_SEQ_FONT`, `CURRENT_SEQ_TRACK`. Not saved: the original's save doesn't hold them, and every map entry sets the music.
  - **Playback:** one `AudioStreamPlayer` on the `Music` bus, with the rendered `music/font_nn/track_t.wav` (asset porter family `music`). Loop points come from the WAV, and the songs that play once have none.
  - **Volume:** the render already includes `SsSeqSetVol(0x50)`, the mix and the reverb, so the player stays at 0 dB.
  - `play_music(font, track)`, `stop_bgm()`, `play_bgm(id)`, `update_bgm()`, `force_update_bgm()`, `reset_bgm()`; they read script value 245 and the hour from `GameState`.
- **Buses** (created by `SoundSystem.ensure_buses` at start when the project's layout doesn't have them): `Master` → `Music`, `Sfx`; `SfxLeft` / `SfxRight` (hard-panned) → `Sfx`; `SfxReverbLeft` / `SfxReverbRight` → `SfxReverb` (an `AudioEffectReverb`) → `Sfx`. Each effect voice is two players, one per side, so libsnd's exact L / R gains apply. At key-on the envelope runs half a frame ahead, so a fast attack sounds from the sample's start (the volume is set once per frame). The CONFIG menu (ISSUES.md D-2) can later set the bus volumes.
- **Content:** the banks and songs are content like the models. They are found through `Content` (the `res://content/dw1/` mirror, imported by the editor, else the raw files). The map's set comes from the map record (`sound_bank`), and the partner's from its Digimon record (`digimon_sounds`: `vlall`, null → set 15 as `loadPartnerSounds` does; `vball`). Game logic reads these properties, never type ranges.
- **Wiring in the field:**
  - `ScriptInterpreter`: 0x5A, 0x5D, 0x5E, and `resetBGM` in the 0xFB load-map path.
  - `field.gd`: `load_map_sounds` in the map load, `load_partner_sounds` with the partner.
  - `Clock.tick_game_clock` calls `update_bgm` at its end.
  - `TextBoxes.sound` / `UIBoxes.sound` → `play_sound(0, id)`.
  - `AnimationSounds` (on the tamer and every `FieldDigimon`) emits the glTF animation `events` of type sound as the animation passes them, loops included. The entity plays it if it is on screen, with bank 4 replaced by the entity's slot: the partner's is 4 (`partner_impl.c:465`), the tamer and NPCs skip bank 4 (§6). In the field animations (ids 0–4) only bank 1 (747 events: footsteps) and bank 3 (6) occur.
- **Not wired yet (later steps):** item and chest sounds (5b, `tamer.c:1447–1811`), battle start and its music (5d), menus and shops (5e), the title screen. The pause box's sound 0 / 3 is wired (`specs/pause.md`).

## 4. Data

- **Asset porter, already converted** (`output/sound/`): the banks, `vag_<nn>.wav` samples with loops, the `bank.json` tones (`adsr1`, `adsr2`, `center`, `shift`, `min`, `max`, `volume`, `pan`, `mode`, …), the songs (`.seq`, `.mid`).
- **New (family `music`):** the rendered songs `output/music/font_nn/track_t.wav` with their loop points, and `output/music/index.json` (per track: loop ticks and samples, length, peak, play mode; the render settings). See `asset_porter/specs/sound.md` "Music render".
- **Data porter, existing:** the map records' `sound_bank`, the Digimon records' `vball` / `vlall`.

## 5. Verification

- **Tests** (`tests/test_sound.gd`, headless; values worked out from the C and the asm):
  - `playSound`'s program / note for slots 0, 1, 3–8 and its tone selection (`max == note`, several tones);
  - `getNextFreeChannel`'s round robin and the all-busy case;
  - the volume and pan formula for a few tones (exact integers), no squaring;
  - the pitch from `_svm_ptable` for notes around the centre and with `shift`;
  - `SpuEnvelope` against step-by-step vectors shared with the porter's renderer tests;
  - `stop_sound_mask`;
  - `handleMusicOverride` for every value of 245 and both sides of 6:00 / 21:00;
  - `playBGM` / `updateBGM` (restart only on a change, 0xFF);
  - the map and partner set loads (skipped when already loaded).
- **Human checks** (VERIFY.md "Sound"):
  - the field songs and their night variants, against the game in an emulator;
  - the text box clicks;
  - footsteps and the partner's voice;
  - a map with looping ambience;
  - the reverb.

## 6. Open questions

- **NPCs' bank-4 animation sounds:** in the field nothing sets an NPC entity's `vabId` (only battles do, `btl.c:412`). An NPC's bank-4 sound events would play on slot `vabId`, which is probably 0, the system bank.

  For now the port skips bank-4 events for NPCs. To check in the game: does an NPC make odd system sounds while animating? Bank 4 holds 1,568 of the 4,918 animation sound events, but most are in battle animations.
- **Music and effects sharing voices:** in the original, libsnd's song voices and the effects' voices 10–23 are the same 24 SPU voices, so a busy effect can cut a song note (and the reverse). The port renders the music apart and keeps the effects on their own voices, which leaves out this glitch.
- **Decay → sustain:** the renderer checks `(level >> 11) <= sustain` after each decay step (as duckstation does); Mednafen tests equality, which can skip a level with fast exponential decays. To compare by ear if a song's sustained notes sound off.
- **Tone `mode` values other than 0 and 4:** one FAALL tone has mode 1. libsnd only tests bit 2 (reverb) in the key-on. Noise voices (vag 0xFF) don't occur in DW's banks (porter check).
- **To check against DW's assembly while coding:**
  - `SsUtKeyOnV`'s pan argument;
  - `SeAutoVol`'s direction for 127 → 0 in 6 ticks. In `sotn-decomp`, a fall computes a positive step and ends at once.
