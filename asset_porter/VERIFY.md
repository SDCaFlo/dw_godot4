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

## 4d. Battle effects — 5 minutes

One folder per technique: `output/efe/<slot>_<technique>/` (slot = technique id).

- `texture.png`: the effect's texture strip (fire, sparks, water...) — should match the technique (`000_Fire_Tower` = flames, `010_Electric_Cloud` = lightning).
- `model.gltf` in Blender (Material Preview): `000_Fire_Tower` = a fire pillar on a scorched ring, `004_Magma_Bomb` = a lava rock, `015_Hurricane` = a tornado. Models are static; the script animates them (UV scrolling, spawning, scaling).
- `effect.txt`: the effect script. Expect readable flow: `SPAWN_SUB_EFFECT`, `BUILTIN 28 playEFESound`, `BUILTIN 3 drawTMD`, frame counters compared with `BRANCH_IF`, hit checks (`applyRadiusAttackHit`...).
- Known: slot 110 is an unused older copy of effect 344; slot 121 is empty fill.

Wrong if: textures that look like noise or another technique, models inside-out or untextured where a texture exists.

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

## Reporting a problem

Note the file, the animation id or map name, and what you expected vs. saw. A screenshot of the game helps. The sidecar `.json` next to each output has the source file and offset to trace it back.
