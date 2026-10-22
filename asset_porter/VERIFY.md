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

## 5. In Godot — field scene, 5 minutes

Run the project (F5; main scene `scenes/field/field.tscn`, see the project README). It starts in Native Forest:

- The tamer stands on the ground at the spawn point and is sized like in the game (about a fifth of the screen height on an outdoor map).
- Arrows walk (Shift runs); the background scrolls with him and stops at its edges, and he stays glued to the ground while it scrolls (no sliding against the picture).
- He stops at fences, trees and water; walking into an exit loads the next map (Native Forest top exit → MAYO02).
- `[` / `]` cycles through all maps; `T` switches day / evening / night backgrounds.

Wrong if: the tamer floats or sinks, drifts against the background while walking, walks through walls, or exits lead to the wrong map. The scene uses Digimon as a `Skeleton3D` + `AnimationPlayer` with `root_motion_track = Skeleton3D:bone_0`.

## Reporting a problem

Note the file, the animation id or map name, and what you expected vs. saw. A screenshot of the game helps. The sidecar `.json` next to each output has the source file and offset to trace it back.
