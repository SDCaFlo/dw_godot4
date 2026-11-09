# Verifying the porter output (human checks)

The converter runs its own checks on every run (`python -m dwporter convert all`: every family must end with `N/N checks passed`) and `python -m unittest discover -s tests -t .` must pass. Those prove the data was read the way the game reads it. What they cannot prove is that it *looks* right; that is what these checks are for. Allow ~30 minutes for a full pass; spot checks take 5.

Tools: an image viewer, **Blender** (File → Import → glTF 2.0), optionally **Godot** (drop files into a project). Remember what the game looks like (or keep a longplay video open).

## 1. Textures — 2 minutes

| Open | Look for |
|---|---|
| `output/card_all/card_00.png` … `card_65.png` | Clean trading cards; the number printed on each card = file number |
| `output/alltim/003_AGUM.png`, `.p1.png` … | Agumon's texture sheet; each `.pN` shows other parts in colour (eyes, mouth): that is expected, palettes are per body part |
| `output/etctim/06_item.png`, `output/tim_files/ETCDAT/ITEM.p3.png` | Item icon grid |
| `output/tim_files/ETCNA/TITLE256.png`, `STDDAT/GRADE/*.png` | Title screen, tournament title cards |

Wrong if: noise/garbage, colours shifted, images cut in half.

## 2. Static models — Blender, 5 minutes

Import from `output/tmd_files/`: `ETCNA/TAKA.gltf` (item box), `ETCNA/MEDAL.gltf`, `ETCNA/UNTI.gltf` (poop), `ETCDAT/TAMA.gltf` (eggs, 24 overlapping), `STDDAT/T_TOGI.gltf` and `B_TOGI.gltf` (arenas).

- Upright (+Y up), textured, faces not inside-out (enable *Backface Culling* in the viewport: you should see the outside).
- Use *Material Preview* / *Rendered* shading; textures are pixelated on purpose (nearest filtering).
- `DOOR/*.gltf` and some props are grey: they use map textures; the textured doors are in `output/maps/<NAME>/doors/`.

## 3. Digimon — Blender, 10 minutes

Import `output/mmd_files/MMD0/AGUM.gltf`, `MMD0/GREY.gltf`, `MMD0/BOYS.gltf` (player).

- Model assembled (head, arms, tail in place), correct colours (Agumon: green eyes, white claws).
- Open the *Dope Sheet → Action Editor*, pick actions `anim_00`, `anim_05`, `anim_07`… and play (timeline at 20 fps feels like the game; Blender's default 24 fps is fine).
- Expected: limbs move naturally, no parts flying off. Walk/run animations (e.g. Agumon `anim_02`–`04`) **move the whole model forward**: that is the game's root motion, not a bug.
- Some ids are duplicates of others (`same_data_as` in the glTF animation extras); identical motion there is correct.
- Optional: compare with DW1ModelConverter's output (`external_tools/DW1ModelConverter/build/Release/output/digimon/`) side by side.

## 4. Maps — 5 minutes

Open `output/maps/<NAME>/overview.png` for a few maps, e.g. `MAYO04A` (Jijimon's tree), `MAYO10` (Dragon Eye Lake beach), a town map and an indoor map. The overlay is computed from the map data through the game's camera:

| Marker | Must sit on |
|---|---|
| green dots | ground you can walk on in the game (stop at fences, water, walls) |
| orange dots | exits, doorways, special spots |
| cyan squares | where you enter the map |
| yellow squares | NPC Digimon (standing on walkable ground) |
| magenta squares | doors (on door openings) |
| sprites | animated details (water, fire, signs) in plausible places; drawn opaque here, so water overlays may look like dark rectangles |

Also: `background_0/1/2.png` = day / evening / night variants; `doors/door_<id>.gltf` in Blender should be textured.

Wrong if: green dots are offset/rotated against the art, markers in the sky or inside walls, sprites in random places.

Training slot machine (gyms `TRAI00`, `GIAS09`, `MIST05`): open `output/maps/TRAI00/training/slots_p3.png` (256 × 32, zoom in). It must show **7 symbols, 32 × 32, in a row** from the left: heart (HP), blue ring (MP), red round badge (Offense), yellow cog with blue centre (Defense), arrows (Speed), light bulb (Brains), yellow poop; then a narrow multicoloured column at u 224–231 and transparent to the right. `slots_p4.png` is the same strip in greys; what matters there is the **8-texel window column at u 0xE0 (224–231)**: white at the top and bottom, black in the middle (the subtractive shade of the reel window). `slots_p4.stp.png` is all white, `slots_p3.stp.png` all black. The other two maps' strips are the same (`manifest.json` `training_slots.identical`).

Wrong if: symbols cut in half or shifted (wrong page/rows), noise or a piece of background (wrong image order), wrong colours (CLUT rows not from image 0).

Curling sheet (`maps/FRZL17/curling/`): open `sheet.png` (256 × 88 indexed) and `sheet.p01.png`, `sheet.p08.png`. They must show the curling HUD sprites (scores, stone cursor, power meter, name plates, ready prompt) in clean pixels. In Blender, import `output/tmd_files/ETCDAT/KARRING.gltf`: 12 stone models, fully textured from page (640, 0) and CLUT row 486.

## 4b. Event scripts and arena collision — 5 minutes

Scripts: open `output/scripts/DG/script_004.txt` (Native Forest, map 3) and `output/scripts/MAPHEAD/script.txt` (section `0x3` = Native Forest setup).

- Dialogue reads as the game's English text (`"There are engraved\nletters here."`); `{color 7}`, `{partner_name}` etc. are the game's text codes.
- MAPHEAD sections start with `SET_SCRIPT script=<map+1> map=<map>`, then music (`SET_BGM`) and NPCs (`LOAD_DIGIMON` / `SET_DIGIMON` with Digimon names); compare with who you meet on that map in the game.
- Sections with ids 51–109 are trigger cells on the map (`collision` values in `maps/<NAME>/map.json`); others are NPC talks (section = NPC script id).

Wrong if: garbled text, Digimon names that don't fit the map, instructions after an `END_SECTION` that look like noise.

Arena collision: open `output/atr_files/STDDAT/B_TOGI/preview.png` (a disc) and `E_TOGI/preview.png` (a diamond). In Blender, import `tmd_files/STDDAT/E_TOGI.gltf` together with `atr_files/STDDAT/E_TOGI/collision_cells.gltf`: the cells cover the square fighting floor; for `B_TOGI.gltf` the disc lies inside the wooden ring.

## 4c. Sound — 10 minutes

Sound effects and instruments are plain WAV files (any player; Godot/Windows play them directly):

- `output/sound/SS/vag_*.wav` (menu/system sounds), `SB/` (battle), `ESALL/set_00/` (Native Forest area sounds), `VBALL/set_03/` (Agumon's cries), `VLALL/set_01/` (partner voices).
- Expected: clean sounds at the right pitch, no hiss or crackle. Looped instruments loop smoothly in players that read loop points (Godot, Audacity, foobar2000).
- `bank.json` → `usage` says who uses the bank (Digimon types, maps, font).

Music is MIDI + the font's instruments:

- `output/sound/FAALL/font_NN/track_T.mid` + `bank.sf2` of the same folder. Play them together in a SoundFont-capable player, e.g. VLC (Tools → Preferences → Show all → Input/Codecs → Audio codecs → FluidSynth → SoundFont file = that `bank.sf2`, then open the `.mid`) or Polyphone/foobar2000 + MIDI plugin.
- Font 1 = Native Forest (`SET_BGM bgm=1` in the MAPHEAD listing), font 33 = battle (4 tracks). Tracks 0/1 are usually day/night versions.
- The preview SF2 ignores the game's envelopes and reverb: notes may be a bit dry/abrupt, but melody, instruments and tempo must match the game.

Wrong if: noise instead of instruments, wrong key (everything sharp/flat), wrong tempo, instruments swapped between parts.

-"battle tracks may chirp in preview renders: missing envelopes, known"

The rendered songs (`python -m dwporter convert music`, a few minutes) are the music as the game plays it, envelopes and reverb included:

- `output/music/font_NN/track_T.wav`: open in any player. Compare with the game in an emulator (same map, same time of day): tempo, instruments, the envelopes (no chirping in font 33), the reverb's tail, the loudness between songs.
- Loops: a player that reads `smpl` loops (Audacity shows the loop region, foobar2000 / Godot loop it) should go from the end back into the loop without a click or a jump in the music. `index.json` → each track's `loop` (samples) and `play_once` (fonts 29–32 play once).

Wrong if: a song is silent or cut short, notes hang forever, a loop jumps audibly, the music is much louder or softer than the emulator's.

## 4d. Battle effects — 5 minutes

One folder per technique: `output/efe/<slot>_<technique>/` (slot = technique id).

- `texture.png`: the effect's texture strip (fire, sparks, water...) — should match the technique (`000_Fire_Tower` = flames, `010_Electric_Cloud` = lightning).
- `model.gltf` in Blender (Material Preview): `000_Fire_Tower` = a fire pillar on a scorched ring, `004_Magma_Bomb` = a lava rock, `015_Hurricane` = a tornado. Models are static; the script animates them (UV scrolling, spawning, scaling).
- `effect.txt`: the effect script. Expect readable flow: `SPAWN_SUB_EFFECT`, `BUILTIN 28 playEFESound`, `BUILTIN 3 drawTMD`, frame counters compared with `BRANCH_IF`, hit checks (`applyRadiusAttackHit`...).
- Known: slot 110 is an unused older copy of effect 344; slot 121 is empty fill.
- `effect.bin`: 20,480 bytes in every folder (the raw slot, for the port's effect VM; nothing to look at).

Wrong if: textures that look like noise or another technique, models inside-out or untextured where a texture exists.

**Battle overlay models** (`output/btl_rel/`, `specs/btl_rel.md`): `texture.png` is a small strip (136 × 48) with the finisher aura's glow; `finisher_aura.gltf` should look like a ring / column of glow layers around a standing Digimon's size; `confusion.gltf` a small flat-coloured shape that circles a head; `stun.gltf` a few stars; `buff.gltf` rings and a disk. Wrong if a model is a jumble of far-apart triangles (a wrong offset) or textured with something unrelated (the stun stars' palette is an open question: they may get their colours at run time).

## 4e. Movies — 5 minutes

`output/movies/<OP1|OP2|ED2|EDR>/`:

- `preview/frame_*.png` (one every 2 s): clean pictures, right colours (skin tones, sky), no blocky noise or colour swaps. OP1 starts with the BANDAI logo and a map of Japan; EDR ends with the credits.
- `audio.wav`: the movie's music and voices, 37.8 kHz stereo, normal speed and pitch.
- `movie.ogv` (only after installing ffmpeg and re-running `convert movies`): plays in VLC / Godot with audio in sync.

Wrong if: green/purple tints (colour planes swapped), smeared blocks, audio too fast/slow or chipmunk-pitched.

## 5. In Godot — field scene, 5 minutes

Run the project (F5; main scene `scenes/field/field.tscn`, see the project README). It starts in Native Forest:

- The tamer stands on the ground at the spawn point and is sized like in the game (about a fifth of the screen height on an outdoor map).
- Arrows walk (Shift runs); the background scrolls with him and stops at its edges, and he stays glued to the ground while it scrolls (no sliding against the picture).
- He stops at fences, trees and water; walking into an exit loads the next map (Native Forest top exit → MAYO02).
- `[` / `]` cycles through all maps; `T` switches day / evening / night backgrounds.

Wrong if: the tamer floats or sinks, drifts against the background while walking, walks through walls, or exits lead to the wrong map. The scene uses Digimon as a `Skeleton3D` + `AnimationPlayer` with `root_motion_track = Skeleton3D:bone_0`.

## 6. In Godot — editor mirror, 10 minutes (first import included)

Project > Tools > **DW: Mirror dw1 assets** copies models, map backgrounds / doors and cards into `res://content/dw1/` (`../specs/content.md` §6). The Output panel says how many files were copied; Godot then imports them (progress bar, a few minutes the first time).

- FileSystem dock: `content/dw1/mmd_files/MMD0/` shows a thumbnail for each model, `content/dw1/maps/<NAME>/` the backgrounds, `content/dw1/card_all/` the cards.
- Double-click `AGUM.gltf` (Advanced Import Settings): Agumon is textured; in the animation list, play `anim_03` (walk) — it moves like in the game. Drag `AGUM.gltf` into a 3D scene: it appears textured.
- Run `godot --headless --path . -s res://tests/test_content.gd` (from `dw_godot/`): `OK: Content checks` means the imported models play exactly like the runtime-loaded files (every animation track at every 20 fps frame). If it fails with an import-setting difference, Godot 4.7 may name an option differently than 4.3 (see `Content.MODEL_IMPORT`).
- F5 still works the same (the field now uses the imported tamer and backgrounds).
- `git status` shows nothing under `content/` (gitignored).
- DW Data dock > Overview > **Check assets**: `digimon 178/180`, `map 242/244`, `card 66/66`, each with as many "imported" as "found"; the missing ones are the known disc gaps (`../docs/dw_data_dock.md` §5).

## Reporting a problem

Note the file, the animation id or map name, and what you expected vs. saw. A screenshot of the game helps. The sidecar `.json` next to each output has the source file and offset to trace it back.
