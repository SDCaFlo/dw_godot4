# The death scene's look (step 6-2)

Detailed spec for drawing the DOOA dissolution and rebirth (and the bits of MURD still drawn by stand-ins) the way the original does. The logic and timelines are already ported (`specs/death_reincarnation.md`: `MurdScene`, `DooaScene`, the states); this step replaces the stand-in visuals in `DeathHost` (`scripts/field/hosts/death_host.gd`, `partner_dissolve.gdshader`) with the original's effects. Bug report: `ISSUES.md` I-38 (`issues/evidence/dw_very_bugy_death.mp4`).

Status (2026-10-30): spec written, not started. To pick up: read §1 (what the player must see), §8 (Godot design), §9 (order of work).

Sources (all in `external-resources/dw_decomp/src/`):

| What | Where |
|---|---|
| the dissolution's timeline (already ported) | `dooa/dooa.c` `DOOA_tickDissolve` :310–577 |
| the rebirth's timeline (already ported) | `dooa/dooa.c` `DOOA_tickRebirth` :1020–1167 |
| the wireframe body | `main/model.c` `renderWireframed` :3003–3132, its call in `renderDigimon` :2911; `WIREFRAME_RNG_TABLE` :2501, `PARTNER_WIREFRAME_TOTAL` :83, `WIREFRAME_COLOR_MIN / MAX` :89–91 |
| the body's shards | `dooa/dooa.c` `DOOA_initShardEffect` :637, `DOOA_spawnShardWave` :791, `DOOA_spawnBoneShards` :1559–1696, `DOOA_updateShards` :1325–1422, `DOOA_renderShards` :1424–1557, `DOOA_toggleShardFlicker` :805, `DOOA_setShardState` :1210; structs `include/dw/dooa.h` |
| the cutscene camera | `dooa/dooa.c` `DOOA_updateCutsceneCamera` :728–789, `DOOA_getOrbitPosition` :1305–1323; calls in `DOOA_tickDissolve` phases 0–3 |
| the squash | `DOOA_DISSOLVE_SCALE_CURVE` :273, phase 0x64 :472–503 |
| the flashes | `EFECreateFlash` calls in phase 0x65 (:505–527) and rebirth 0xCE (:1080–1100); `setEFEFlashOffset` |
| the egg | `dooa/dooa.c` `DOOA_renderRebirth` :1169–1208; `doo2/doo2.c` `DOO2_renderWireframeModel` :410–553; the model `ETCDAT/TAMA.TMD` (24 objects: 4 eggs × 6 pieces) |
| the egg's pieces breaking off | `doo2/doo2.c` `DOO2_buildShardSet` :597–710, `DOO2_tickShardSet` :208, `DOO2_renderShardSet` :173, `DOO2_renderTriShard` / `QuadShard` :228–325; rebirth phase 0xD0 :1137–1158 |
| the spark streaks | `doo2/doo2.c` `DOO2_renderSparkStreak` :555–585, drawn by `DOOA_renderRebirth` while `fadeLevel > 0` |
| the CLUT fades | `DOOA_fadeModelClut` / `DOOA_fadeShardClut` :1229–1303, `DOO2_fadeClut` :372–408, `fadeoutCLUT1(level, DOOA_SCENE_CLUT)` (the map background) |
| MURD's partner over the iris, its lights | `murd/murd.c` `MURD_renderScene`, `MURD_renderDigimon`, `MURD_isDigimonLargerThanIris`, the `GsSetFlatLight` calls in phase 0 |

The 5f-2 evolution scene (`evl/evl.c:431–551`) uses the same wireframe renderer (`PARTNER_WIREFRAME_TOTAL`, `PARTNER_WIREFRAME_SUB[bone]`): build it once (§3) and reuse it there.

---

## 1. What the player sees (no life left / natural death)

1. **Iris** (DOOA frames 0–0x21, natural death only; MURD drew it otherwise). The partner stays drawn over the black once it is larger than the window (`DOOA_hasIrisClosed` / `MURD_isDigimonLargerThanIris`: it moves to a separate ordering table in front).
2. **Map change** (0x23): Jijimon's house, all black (`fadeoutCLUT1(0xFF)` on the background; every entity hidden but the partner). The partner keeps its old map position; the camera is put back to the old map's view, then orbits in to it (0x23–0x55).
3. **To the centre** (0x56): the partner is moved to the room's origin, facing the tamer, the camera jumps to its orbit view there (0x63 of a 0–0x64 move: §5). With lives left it plays animation 0xC, then 1.
4. **Wireframe and falling shards** (0x69–0x8C): 36 frames, `PARTNER_WIREFRAME_TOTAL` stepping 15 → 0 (`DOOA_SHARD_WAVE_SCHEDULE`). At each step, the faces of that group turn into lines; about 3 of 4 of them break off as textured shards and fall to the floor, where they stay. Sound `playSound2(8, 0)` at 0x69, stopped at 0x8C.
5. **Squash** (0xBF–0xD1): the all-wireframe body stretches up and thins (`DOOA_DISSOLVE_SCALE_CURVE`), then sinks: `stopSound`, `playSound(8, 1)` at 0xBF.
6. **Gone and the rising flash** (0xD1–0x135): the body disappears (animation 0x21, off the map), `playSound(8, 2)`; a flash rises from below the floor to the ground and wobbles sideways. The wireframe colour range is reset (0x37–0xFF). At 0x135 the shards on the floor start flickering in random flat colours (`DOOA_toggleShardFlicker`), `playSound2(8, 3)`.
7. **Camera** (0x149–0x17B): it moves back (the orbit lerp run backwards: `frame = 0x2C4 − frame`).
8. **Jijimon fades in** (0x185–0x1B7) from black (his model CLUT, `DOO2_fadeClut`). No egg yet. The dialogue (script 212 section 71 / 73) runs with the room black, the shards flickering on the floor, Jijimon lit.
9. **Rebirth** (routine 4, `DOOA_tickRebirth`, its own frame counter):
   - 10: `stopSound`, `playSound(8, 5)`; the shards lift (shard state 1): each spins up to its own speed, flies out to a random radius and rises to a random height.
   - 100: the shards converge (state 3): one by one (random 0–19 frame delay) they spiral back to the centre and up to 100 above the floor, then vanish.
   - 100–132: the egg (`TAMA.TMD`, the 6 objects of the chosen egg) fades in at the room's origin as a wireframe filling in face group by face group (threshold `lerp(1, 16, 100, 132)`).
   - 132: the shard object is removed, the baby's model loads, `playSound(8, 6)`; 132–152 a big flash at (0, −100, 0) shrinks, spark streaks shoot out from 100 above the partner (`fadeLevel = lerp(5, 0, 132, 150)` streaks a frame).
   - 152: `reincarnatePartner`; the others shown again; the room's background, the model and shard CLUTs fade in from black over 152–202.
   - 202: the baby shown at the origin, animation 0x1C; then one frame per entry of `DOOA_SPARKLE_BONE_IDS` (47): at each entry ≥ 0 that egg piece breaks into a shard set (§6) and stops being drawn, `playSound(8, 7)`.
   - 262: animation 0xB; at its end the rebirth is over.

With lives left (a life lost), only MURD runs: the iris, the lives box, the darkening, the map change; nothing in this spec but §7.

## 2. What the port draws now (to replace)

`DeathHost` (stand-ins, `specs/death_reincarnation.md` §9):
- `partner_dissolve.gdshader` pulls the skinned mesh's vertices down in model space, which garbles the models; a separate line mesh copies the triangles. Remove both.
- No camera move: the partner is moved to the origin with the field camera unchanged. Replace with §5.
- The egg model from 0x185 to 152 as a solid model. Wrong: the egg only exists in the rebirth (§6), and 0x185 is Jijimon's fade.
- `DooaScene.squash` is a made-up curve. Replace with `DOOA_DISSOLVE_SCALE_CURVE` (§4.3).
- The iris is drawn under the 3D world so the partner always shows; the C shows it in front only once it is larger than the window (§7).

The logic (`DooaScene`, `MurdScene`) stays; it gains the state the views need (§8).

## 3. The wireframe body (`renderWireframed`)

A Digimon model is rigid per bone: each bone's TMD object is one mesh with bone-local vertices (`asset_porter/specs/mmd.md`). The sidecar `<NAME>.json` keeps every object's primitives in TMD order (`tmd.objects[i].primitives[j]`: `kind` tri / quad, `vertices`, `normals`, `uvs`, `tsb`, `cba`), and `skeleton` maps bones to objects (`objIndex`, -1 = no object).

Per object, per frame, with `share` = `PARTNER_WIREFRAME_TOTAL` (or `PARTNER_WIREFRAME_SUB[bone]` when the total is 16, used by the evolution):
- face `i` (its index in the object's primitive list) is drawn **textured** when `WIREFRAME_RNG_TABLE[i & 15] < share`, else as its **outline**: a closed polyline of its 3 or 4 vertices (quads in the order v0 v1 v3 v2, the TMD's strip order), flat colour.
- `WIREFRAME_RNG_TABLE = [6, 3, 11, 8, 10, 13, 1, 4, 14, 7, 12, 15, 5, 2, 9, 0]`. So `share` 16 = all textured (the normal path, `GsSortObject4J`), 0 = all lines.
- Both are back-face culled (`RotNclip3/4 > 0`).
- The line colour is grey `WIREFRAME_COLOR_MIN + rand() % (MAX − MIN)`, drawn again for every object every frame (it flickers). MIN / MAX are 0x37 / 0xFF (DOOA sets them again at 0xD1; the evolution changes them).

Godot: a `PartnerWireframe` component (scene) built from the sidecar when the scene starts: per bone object, two meshes attached to the same `BoneAttachment3D` (or the bone's node) as the model's: one with the textured faces split into 16 surfaces by group (`i & 15`), one with the outlines (`PRIMITIVE_LINES`) split the same way. `share` shows the textured groups with `WIREFRAME_RNG_TABLE[g] < share` and the outlines of the others; the model's own meshes are hidden while `share < 16`. The line colour is a per-object material parameter changed every game frame. Culling: back faces off for both (lines: cull per face in a shader from the face normal, or accept drawing back lines; note the choice).

## 4. The body's shards (`DOOA_SHARD_EFFECT`)

### 4.1 Spawning (`DOOA_spawnShardWave(wire)`, `DOOA_spawnBoneShards`)

Called when the schedule's value changes (and on its first frame), for bones 2 .. boneCount − 1 (not the root, not bone 1). For each bone with an object: its vertices through the bone's current world matrix (`calculateBoneMatrix`: the animated pose that frame); for each face `j` with `WIREFRAME_RNG_TABLE[j & 15] == wire` and `(rand() & 3) != 0` (3 in 4), one shard:
- `centre` = mean of the face's world vertices, minus the partner's location (x, z) and minus the stored y (`DOOA_storeDigimonY`, the partner's y when the shards started; phase 2's first frame);
- `vertex[k]` = world vertex − centre (before that subtraction): the face's shape around its centre;
- the face's UVs, CLUT and the model's texture page (it stays textured);
- `fallSpeed` 0, `radius` 0x1000 (1.0), `rot` (0, 0, 0), `axisDistance` = |(centre.x, centre.z)| (≥ 1), `delay` 0.

The buffer holds at most `0x4B000`-ish bytes (`GENERAL_BUFFER_PTR + 0x4B000`): the C stops adding when full. Note the limit; no need to reproduce it unless a model overflows.

### 4.2 Update (`DOOA_updateShards`, every frame, by shard state)

Positions are PSX units, y down; `centreY` is relative to the stored y (0 = the partner's feet).
- **State 0** (the dissolve): `fallSpeed = min(fallSpeed + 1, 0x400)`; `centreY = min(centreY + fallSpeed, 0)`: they fall with gravity and stop on the floor.
- **State 1** (rebirth 10–100), on entry: `spin` 0, `spinMax = rand() % 0x155 + 0xE3`, `radius` 0x1000, `targetRadius` random in [0x64000 / axisDistance, 0x190000 / axisDistance), `fallSpeed` 0, `dropDepth = rand() % 0x226`. Every frame: `spin += spinMax / 100` (or 1 if `spinMax / 80 == 0`), capped at `spinMax`; `rotY += spin`; `radius` grows by `targetRadius / 100` (or 1) up to `targetRadius`; `fallSpeed += 1`; `centreY = max(centreY − (fallSpeed >> 3), −dropDepth)` (they rise).
- **State 2**: `rotY += spin` (unused by DOOA).
- **State 3** (rebirth 100–132), on entry: `delay = rand() % 20`, `targetRadius = radius`. Every frame: while `delay > 0` count down; then `radius −= targetRadius / 10 + 1`; at < 0: radius 0, `delay = −1` (gone); `centreY = lerp(−dropDepth, storedY − 100, targetRadius, 0, radius)`; `rotY += spin`, mod 4096.
- `flash` set (0x135 on): the colour is re-rolled every frame, each channel `rand() % 100 + 60`.

### 4.3 Drawing (`DOOA_renderShards`)

For each shard with `delay >= 0`: offset = (centre.x × radius / 4096, centre.y, centre.z × radius / 4096); each vertex = offset + vertex[k], rotated by `RotMatrixZYX(rot)`, plus (partner location x, stored y, partner location z). Flat-shaded textured triangle / quad (`POLY_FT3/4`): colour (R, B, G) of the effect (note the swapped G / B, 0x50 each at the start), the face's UVs. With `flash` on: untextured, colour (R, G, B) random every frame. The shards are drawn after the model, in the main ordering table.

Godot: `DeathShards` (a scene with a `MeshInstance3D` rebuilt every frame from an `ImmediateMesh` or a `MultiMesh`-free `ArrayMesh`, the model's texture in a PSX material; logic in a plain `DooaShards` class with the state of §4.2 so it is testable headless). The squash (phase 0x64) uses `DOOA_DISSOLVE_SCALE_CURVE` (32 entries): `index = lerp(0, 0x1F, 0xBF, 0xD0, frame)`; `work = (curve[index] − 100) × 2 + 100`; scale y = work / 100, x = z = (10000 / work) / 100 then lerped to half over the phase; from entries ≥ 0x12D (≥ 301) the y scale mirrors back (`work = 0x12C − (curve − 0x12C)`) and the partner's y moves toward `storedY − (height + 100)` (it sinks). Port it in `DooaScene` (replace `squash`).

## 5. The cutscene camera (`DOOA_updateCutsceneCamera`)

The field camera is `GsSetRefView2` + projection + drawing offset (`FieldMap`, `specs/camera.md`). DOOA saves the old map's view before the map change, restores it after (so the partner, still at its old coordinates, is seen as before), then moves it:
- Target: the orbit around `position` (the partner) at `rotation = MAIN_D_80134BB4` with `vy = angle + 0x638` (angle = the partner's rotation y), distance `height × 5 + 1200`; `ref` = position − height / 2 up; `pos` = ref + R·(0, 0, distance), then 400 + 2 × height further up (`DOOA_getOrbitPosition`).
- First half (start .. mid): the reference point lerps from the start view's to `ref`, the drawing offset to (160, 120), the eye and the projection stay.
- Second half (mid .. end): the eye lerps to `pos`, the drawing offset y to 120 + lerp(0, 20, 0, 200, height), the projection distance to 1000.
- Calls: phase 1, frames 0x23–0x55 (orbit in); at 0x56 once with frame 0x63 of 0–0x64 after the partner moved to the origin (a near-final jump); phase 3, `frame' = 0x2C4 − frame` over 0x149–0x17B (back out). Phase 4: the camera target reset, `tickCameraMovement(1)`, the follow back on.
- `MAIN_D_80134BB4`: read its value from the decomp (a global SVECTOR in `main`); the rest of the rotation (vx, vz) comes from it.

Godot: a `CutsceneCamera` helper (logic, headless-testable: start view, the orbit maths, frame → view) that `DooaScene` drives and `FieldMap` applies (it already builds the camera from eye / target / projection / drawing offset; add a way to set them directly and to restore the map's own). The field's camera follow stays off until phase 4.

## 6. The egg and its pieces (rebirth)

- `DOOA_renderRebirth`, every frame of the rebirth object: for the 6 objects `eggSlot × 6 + i` of `TAMA.TMD` whose `MAIN_D_80135364[i] == 0`, at the world origin (identity coordinates: the TMD's vertices are world positions; the glTF's y range is 50–193 per object: check the sign convention, they should sit above the floor where the baby appears, around the flash at (0, −100, 0)), drawn with `DOO2_renderWireframeModel(obj, threshold)`: the same face-group rule as §3 with `threshold = MAIN_D_80135324` (0 until 100: lines only; `lerp(1, 16, 100, 132)`, then 16: solid). Lit (`NormalColorCol3`, light colour 0x80).
- The egg model: `tmd_files/ETCDAT/TAMA.gltf` + `TAMA.json` (24 objects, texture `TAMA.TIM`). Note: the CLUT used depends on the egg (the panel's palettes 4–7); check the glTF's per-object textures.
- **Sparkles** (phase 0xD0, one entry a frame): for an entry `b >= 0` of `DOOA_SPARKLE_BONE_IDS`: `DOO2_buildShardSet(offset 0, TAMA, b + eggSlot × 6)`: piece `b` stops being drawn (`MAIN_D_80135364[b] = −1`) and becomes a shard set (one of 6 slots, 40 frames): each face falls apart from its own centre: `offsetY += frame + centreY / 240`, x / z drift by `centre / 240` per frame until the face's mean y reaches the floor (then it stays on it); semi-transparent (additive, `SetSemiTrans 1`), colour `(41 − timer) × 74 / 40 + 54` grey. Removed at 41 frames. `playSound(8, 7)`.
- **Spark streaks** (`DOO2_renderSparkStreak`, `fadeLevel` a frame, 132–150): from 100 above the partner, a thin additive triangle: tip `a` = rotation (vx = rand() % customRandom(−170, 1024), vy = rand()) of (0, 0, customRandom(400, 500)), side `b` = a ± customRandom(−50, 50) per axis, from `origin`; colour (rand() % 128 + 10, same, same); texture page (768, 256) clut (192, 489), UVs (0x5F, 0xA0) (0x5F, 0xA7) (0x30, 0xA0).

Godot: `RebirthEgg` scene (the 6 piece meshes with the §3 wireframe rule, a threshold property) and `EggPieceShards` (logic + mesh, 6 slots); streaks in the same view as the flashes.

## 7. MURD and the iris

- The partner over the iris: the C draws it in a separate ordering table in front of the iris once `radius ≤ projected size` (`MURD_isDigimonLargerThanIris`, `DOOA_hasIrisClosed`: size = |(2 × radius, height, 2 × radius)| of the Digimon record, projected at its middle). Before that it is behind the iris like everything else. The port draws the iris under the 3D world (everyone else hidden at once). To do: hide the others at phase 1 as the C (they are behind the iris until then), and draw the iris over the world with the partner on top only from that moment (e.g. the iris in the HUD and the partner rendered to a layer over it, or a stencil).
- The iris's edge: the C draws a soft round window (the flash texture at (832, 256), clut (0, 487), scaled by the radius) inside four black rectangles that overlap it by `lerp(4, 1, 0x1860, 0, radius)` pixels. The port's circle is hard-edged.
- MURD's lights (phase 0 → 1): three flat lights `(0x1E, 0x64, 0x1E) 0x40`, `(−0x1E, 0x64, 0) 0x28`, `(0, 0x64, −0x1E) 0x26` (direction, grey level) for the partner on the black screen. The port's lighting is `specs/lighting.md`: set these as the partner's lights for MURD's duration.
- Jijimon's CLUT fade (DOOA 0x185–0x1B7) and the rebirth's CLUT fades (152–202): `(r, g, b) × (end − frame) / (end − start)` of the saved CLUT: a colour multiply on that entity's materials (the port's PSX material has a tint / modulate parameter: use it). The map background's `fadeoutCLUT1` is already the iris's `darkness` (keep).

## 8. Godot design

- **Logic stays in `DooaScene` / `MurdScene`**; they gain: `wireframe_total` (`PARTNER_WIREFRAME_TOTAL`, with its reset to 16 at the end), `wire_color_min / max`, the shard effect's state (`DooaShards`: list of shards, state, flash, colour), the egg's threshold (`MAIN_D_80135324`), the piece flags (`MAIN_D_80135364`), `fade_level`, the flash data, the camera views. All plain data so the tests check them frame by frame (as `tests/test_death_reincarnation.gd` does for the timeline).
- **Views are scenes** under `death_host.tscn` (replaceable by a mod, `specs/scenes.md` rule 7): `PartnerWireframe` (also used by the evolution scene: put it in `scenes/field/` not `death/`), `DeathShards`, `RebirthEgg`, `EggPieceShards`, the flashes (reuse `BattleFx` / `EFECreateFlash` if its port fits the field, `scripts/systems/battle/battle_fx.gd`), the iris (`DeathIris`, §7). `DeathHost._process` hands them the logic's state.
- **Model data:** the sidecar's `tmd` (primitives in order, vertices, UVs, CLUT / texture page) and `skeleton` (bone → object). The glTF's own meshes may reorder or triangulate faces: build the wireframe and shard meshes from the sidecar, positioned by the model's bone transforms (the same `Skeleton3D` / bone nodes the animation moves).
- **Remove** `partner_dissolve.gdshader`, `DeathHost._start_dissolve / _wireframe / _end_dissolve / _spawn_egg`, the egg from 0x185, the made-up squash.
- **RNG:** `rand()` → `Rng.rand()`, `customRandom` → `Rng.custom_random` (tests seed them).

## 9. Order of work

1. `PartnerWireframe` from the sidecar + `WIREFRAME_RNG_TABLE`, a test that the groups split as the C's (`i & 15`) and that `share` 16 / 0 / 8 show the right faces. Hook `DooaScene.wireframe_total` (the schedule over 0x69–0x8C, 16 again at the end).
2. `DooaShards` logic (§4.1–4.2) with tests on a small fake model (spawn counts with a seeded RNG, the fall to 0, state 1 / 3 maths), then its view (§4.3).
3. The squash curve in `DooaScene` (§4.3) and the partner's sink.
4. `CutsceneCamera` (§5) and the `FieldMap` hook; check in game that the partner stays centred.
5. The rebirth: `RebirthEgg` (§6), the egg piece shards, the spark streaks; the CLUT fades (§7).
6. The flashes (0x65 rising flash, 0xCE big flash).
7. MURD / iris layering and the lights (§7).
8. Remove the stand-ins; update `specs/death_reincarnation.md` §9, `VERIFY.md`, `ISSUES.md` I-38; `tests/death_scan.tscn` keeps passing.

Each step is visible on its own; check in game after 1, 2, 4 and 5 (no movies: the user checks, `VERIFY.md`).

## 10. Open questions

- `MAIN_D_80134BB4` (the orbit's base rotation): its value isn't read yet.
- The egg's CLUT per egg slot (palettes 4–7 of `TAMA.TIM` in the panel): which one the 3D egg uses (the TMD's `cba` per object, or the DOO2 `saveClutTile` swap at 0x17B).
- `DOOA_fadeModelClut` writes the CLUT at (0, 488) and `DOOA_fadeShardClut` another tile; `DOO2_fadeClut` (32, 488) for entity 2: confirm which entity each tile belongs to (entity CLUT slots) before mapping them to Godot materials.
- The shard buffer limit (§4.1) for the biggest models.
- Whether the lines should be back-face culled per face (the C does; Godot lines aren't).
