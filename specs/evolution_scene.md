# The evolution scene (step 5f-2)

The `evl` overlay's sequence, drawn the way the original draws it: the field going dark, the camera swinging in and orbiting, the old body breaking bone by bone into outlines and flying shards, the sparks, the green rings on the floor, the flashes, the growth to the new Digimon's size, and the new model building up face group by face group. 5f-1 (`specs/evolution.md`, "As built") ported the rules, partner state 13 and the loading part of the scene (`EvolutionScene`, 57 + 56 frames), then a **stand-in**: `EVL_applyEvolution` at once, then the new Digimon's pose. This step replaces the stand-in with `EVL_initEvoSequence` / `EVL_tickEvoSequence` and their effects.

**Status (2026-11-01):** approved by the user; acceptance tests written (§7), ready for hand-off. Step 1 is next.

## 0. How to work on this step

- Read first: `docs/porting_checklist.md`, then this spec: §1 (what the player sees), §3 (the values), §5 (the design), §6 (your step). The building blocks come from 6-2 (`specs/death_scene.md` §5): `PartnerWireframe`, `TmdFaceGroups`, `CutsceneCamera`, `FieldMap`'s view hook, `BattleFx` / `BattleFxView` with a projector, `SparkStreaks`, `PaletteFade`, `BackgroundDark`. Read their code before writing new code.
- **The acceptance tests are fixed** once written (§7): `tests/test_evolution_scene.gd`, `tests/evolution_scan.tscn` and `tests/test_rules.gd`'s "5f-2 stand-ins". Don't change them. When one looks wrong, stop and report it with the C line that shows it.
- **Every value comes from §3.** If you need a value that isn't there, find it in the C, add its row (C file, line, value, status) and say so in your report. Never guess one.
- **One step of §6 at a time.** Each step lists the files it owns; don't edit others. After each step run every suite (`tests/test_*.gd`, `tests/test_rules.gd` included), `tests/exit_scan.tscn`, `tests/death_scan.tscn` and `tests/evolution_scan.tscn`. Then stop for review and the user's in-game check.
- The C is in `external-resources/dw_decomp/src/`: `evl/evl.c` (the whole overlay, fully decompiled, no `INCLUDE_ASM`), `main/evl.c` (the loading), `main/effect_common.c` (`lerp`, `calculateBoneMatrix`, the CLUT fades, `addScreenPolyFT3/4`, `worldPosToScreenPos`), `main/efe.c` (the flashes), `main/model.c` (`renderWireframed`, `PARTNER_WIREFRAME_SUB`). We port the US build.
- All arithmetic is the C's integer arithmetic: `lerp` is `PsxMath.lerp_int` (`effect_common.c:278`, with its wrap-around: `lerp(0, 20, 0, 200, 250)` = 4, not 25), divisions truncate towards zero (`PsxMath.div`), all RNG through `Rng.rand()` / `Rng.custom_random()`.

---

## 1. What the player sees

The frames are the sequence's `timer` (`EVO_SEQUENCE_DATA.timer`), counting from 0 at its first tick, the frame after the loading ends (§3 A2). Agumon → Greymon is the example.

1. **Into the dark** (0–0x20). The map background, the bubbles and the item icons fade to black over 32 frames. The tamer and the other people fade too, on alternating frames (the tamer on even frames, the NPCs on odd ones). The partner keeps its colours.
2. **Hidden** (0x20). Everyone but the partner disappears and the map's objects go (doors, sprites, items, chests, poop). The camera's view is saved. The new model starts loading.
3. **Camera in** (0x21–0x60). Over 0x21–0x40 the camera turns to look at the partner's middle, and the partner slides to the screen centre. Over 0x41–0x60 it moves in to an orbit point behind and above the partner, at a distance from the partner's size, and the field of view narrows (projection 1000).
4. **First orbit** (0x61–0x6A). The camera circles the partner, 0x16 a frame.
5. **The first bone breaks** (0x6A). Sounds (8, 1) and (8, 0), animation 0xC (it falls, then plays 1 when 0xC ends). The camera stops where it is.
6. **Bones breaking** (0x6A–0xA2 for Agumon's 16 bones). The bones go one by one in a random order: at 0x6A, then 0x70, 0x80, 0x8A, 0x92, 0x96, 0x98, 0x9A, then one every frame from 0x9B until none is left. For each one:
   - a sound (8, 2, 3 or 4);
   - the bone's part of the body turns into flickering grey outlines (all of it, at once);
   - its faces fly off as translucent textured shards, each along its own normal, fading over 32 frames;
   - a spark streak shoots out from the body's centre (bone 1) in the bone's direction, every frame until 0x11C (only the first 16 bones get one: all of Agumon's, 16 of Greymon's 20);
   - a grey flash at the bone.
   From 0x6B, green square rings grow out on the floor around the partner's feet, fading as they grow: 9 rings in every 18 frames, until 0x162.
7. **The body glows** (0x70–0xCC). The partner's colours flicker towards white by random amounts, a little more each frame until 0x9A, then at full strength until 0xCC. The last flicker stays until the model changes.
8. **The camera orbits again** (0xA5–0x162). It speeds up from 0 to 0x16 a frame over 0xA5–0xC2, then keeps turning.
9. **Growing** (0xCC–0x107). The body (outlines by now) stretches from the old Digimon's radius and height to the new one's. The orbit's distance follows the size.
10. **Flashes** (0xD6–0x11B). At 0xD6 the sounds stop and sound (8, 5) plays. On every even frame from 0xD8, a flash at the body's centre grows bigger and brighter towards 0x11B. About half of them are drawn in front of everything, the others behind.
11. **The new Digimon** (0x11C). The evolution is applied (`EVL_applyEvolution`): the new model is at the same place, in outlines, animation 0. From 0x126 to 0x14E its faces fill in group by group. It is solid from 0x14F.
12. **Back** (0x162–0x163). The camera returns to the saved view. In the next frame the colours come back, everyone and the map's objects reappear, the music comes back, the rings vanish, the map's sounds reload, and the new Digimon plays animation 0xB (its pose). When 0xB ends, the scene is over (timer −1) and partner state 13 ends (5f-1).

## 2. The stand-in to remove

In `EvolutionScene` (`scripts/field/evolution_scene.gd`):
- `_apply()` and `STATE_POSE`: `apply_evolution` at once when the loading ends, then animation 0xB. They are replaced by the sequence (§4).
- The file's header and the comments calling it a stand-in.
- 5f-1's ordering (`Partner.tick_evolving` calls `evolution_scene.tick()`) is changed too (A1).

## 3. The values

Every number the step uses. **Status** is one of:
- `ported`: the code does what the C line does;
- `port-only`: the C has no such value, and the reason is given;
- `stand-in`: not allowed at the end of this step.

C paths are under `external-resources/dw_decomp/src/`; `evl.c` means `evl/evl.c`. A value marked "already" is in the code today.

### A. The frame and the objects

| # | What | C source | Value | Status |
|---|---|---|---|---|
| A1 | Who ticks the scene | `main/evl.c:35` (loading object 0x809), `evl.c:1329` (sequence object 0x80A); `partner.c:774` reads `getEvoSequenceState(…, 1)` = the timer only (`main/evl.c:86–88`) | The loading and the sequence are objects, ticked in the object list. Partner state 13 only reads the timer. Port: `EvolutionHost.tick_objects()` in `Field._frame`'s object slot, right after `death_host.tick_objects()`; `Partner.tick_evolving` sub-state 2 reads `evolution_scene.timer` | ported (fixes 5f-1, which ticks the scene from the partner); the place among the other objects is port-only: the C's object slots aren't traced |
| A2 | First sequence tick | `main/evl.c:47–50`, `world_object.c:19–36` (`addObject` takes the first free slot; the loading object's slot was just freed) | The loading ends with `EVL_initEvoSequence` (timer 0, state 0). The sequence's first tick is the next frame | ported |
| A3 | Objects made during a tick | `addObject` (first free slot) | The shard sets, sparks, particles and flashes made in a tick are drawn that same frame (`renderObjects` runs after `tickObjects`). They tick from the next frame | port-only: their slot order is untraced, so the next-frame rule is a choice |
| A4 | Timer step | `evl.c:588` | `timer += 1` after each state's work (states 0–3). State 4 sets −1 and returns (`:581`). So state 1 starts at 0x21, state 2 at 0x6B, state 3 runs at 0x163, state 4 from 0x164 | ported |
| A5 | Animation 0xC's end | `evl.c:377–380` | Every tick, before the states: if the animation is 0xC and `animFrame == frameCount`, play 1 | ported |
| A6 | Unused stores | `evl.c:406–407, 552–555`; `main/evl.c:79` | `EVL_D_80068908` (location), `MAIN_D_801351F0` (rotation), `EVL_D_80068918` + `MAIN_D_801351FC..204` (the view at 0x162) and `heightFactor` are written, never read | not ported (no effect) |

### B. State 0 and the hand-over (`evl.c:383–409`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| B1 | Map fade level | `evl.c:384–390` | `alpha = lerp(0, 0xFF, 0, 0x20, f)` for f < 0x20, else 0xFF; both `fadeoutCLUT1(alpha)` and `fadeoutCLUT2(alpha)`. Expected: f 0: 0 · 1: 7 · 16: 127 · 31: 247 · 32: 255 | ported |
| B2 | `fadeoutCLUT1` | `effect_common.c:364–399` | The map background's CLUTs, each channel × (255 − level) / 255 = `BackgroundDark` at alpha level / 255 (as 6-2 J1) | already (BackgroundDark) |
| B3 | `fadeoutCLUT2`'s tiles | `effect_common.c:420–457`, `asset_porter/specs/stacked_tim.md` | (272, 480) × 16 = `feel_ef` palette 0 (bubbles, poop); (96, 501) × 16 = `system_w` palette 13; (224, 488) 16 × 24 = the `item` icons' palettes. Port: the same multiply on the nodes drawn with them: `ConditionBubbles`, `PoopPiles`, `MapItems`, `MapChests`' icons. `system_w` palette 13's user is open (§8 Q1) | ported (Q1 open) |
| B4 | Tamer / NPC banks | `evl.c:391–395`, `:595–677` | Even frames: bank 0 = (0, 488) 16 × 24 (the tamer's tile). Odd frames: bank 1 = (32, 488) 48 × 24 (entities 2, 3, 4). Each channel × (0x20 − f) / 0x20, f = the timer | ported (as `PaletteFade`, factor (32 − f) / 32) |
| B5 | B4 expected | (from B4) | f 0: 1 · 8: 0.75 · 16: 0.5 · 31: 1/32 → 0 per channel (5-bit: `c × 1 / 32` = 0 for c ≤ 31) · 32: 0 | (test values) |
| B6 | STP on faded banks | `evl.c:620–621, 662–663` | When f ≠ start, every colour gets the STP bit, black (0x0000, transparent) included: such texels draw opaque black during the fade | port-only: the tint keeps them transparent (as 6-2 J9). Checked in the original by the user (2026-11-01, §8 Q4): the tamer just fades, no black patches |
| B7 | RNG in the fades | `evl.c:611–613, 653–655` | Each bank fade rolls 3 `rand()` (unused): 3 a frame in state 0, and 6 in state 3 (both banks) | ported (the rolls) |
| B8 | Partner's palette | `evl.c:1297`; banks B4 | Not faded (its tile isn't in either bank) | ported |
| B9 | At 0x20 | `evl.c:396–408` | State 1; `EVL_setOtherEntitiesVisible(0)`; `setMapLayerEnabled(0)`; the view saved (`GS_VIEWPOINT`, drawing offset, `VIEWPORT_DISTANCE`); the new model's load starts | ported |
| B10 | Others hidden | `evl.c:679–700` | Every entity but the partner with `isOnMap ≠ 0` → `isOnMap = 0`, remembered. Restore: each back to its remembered value | ported (`FieldEntities.table()`, `visible`) |
| B11 | Map layer | `utils2.c:487`; readers `map_object.c:383`, `item.c:2429`, `clock.c:104` | Off: the map's objects and dropped items aren't drawn, and the clock doesn't advance (already stopped by state 13) | ported (`Field.map_layer_nodes`, as 6-2) |

### C. The camera (`EVL_updateEvoCamera` `evl.c:702`, `EVL_calculateCameraVectors` `:834`, state 2 `:481–502`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| C1 | Orbit point | `evl.c:834–852` | `ref = bone 0's world position − (0, height / 2, 0)`; `eye = RotMatrixZYX(rot) · (0, 0, distance) + ref`, then `eye.y += −0x190 − 2 × height`. Bone 0's position is the location (`calculateBoneMatrix`, `effect_common.c:336`) | ported (= `CutsceneCamera.orbit` with a distance) |
| C2 | Distance | `evl.c:731–736, 762–767, 489–494` | `max(height, radius) × 5 + 0x4B0` (6-2's D2 uses the height only) | ported |
| C3 | C2 expected | (from C2, `digimon_data`) | Agumon (r 120, h 250): 2450 · Greymon (230, 400): 3200 · at 0xEA (r 175, h 325, C10): 2825 | (test values) |
| C4 | Rotation | `evl.c:729–730, 760–761, 487–488` | `(0, angle + partner rotation.y, 0)` (`MAIN_D_801349F8`, `MAIN_D_80134A00`, `MAIN_D_801349EC` = 0, never written) | ported |
| C5 | Called | `evl.c:411` | Only in state 1 (timer 0x21–0x6A) | ported |
| C6 | 0x20–0x60 | `evl.c:711–753` | `angle = 0x638` each frame. f ≤ 0x40: ref `lerp(saved ref, orbit ref, 0x20, 0x40, f)`, offset `lerp(saved, (160, 120), 0x20, 0x40, f)`; eye and projection stay. 0x41–0x60: eye `lerp(saved eye, orbit eye, 0x40, 0x60, f)`, offset y `lerp(120, 120 + lerp(0, 20, 0, 200, height), 0x40, 0x60, f)`, projection `lerp(saved, 1000, 0x40, 0x60, f)`; ref and offset x stay | ported (= `CutsceneCamera.view(saved, location, 0x638 + rot.y, height, 0x20, 0x60, f)` with C2's distance) |
| C7 | Offset y end | (from C6) | `lerp(0, 20, 0, 200, h)`: Agumon 250 → **4** (the wrap), Koromon 150 → 15, Greymon 400 → 19 (wrap): Agumon ends at (160, 124) | (test values) |
| C8 | 0x61–0x6A | `evl.c:755–775` | `angle += 0x16`, then ref and eye = the orbit (C1) at that angle; the offset and projection stay. Angle at 0x6A: 0x714 | ported |
| C9 | 0x6B–0xA4 | `evl.c:481` | The camera isn't touched: it stays at 0x6A's view | ported |
| C10 | State 2's size | `evl.c:462–480` | < 0xCC: the old Digimon's radius / height; 0xCC–0x107: `lerp(old, new, 0xCC, 0x108, f)` each; ≥ 0x108: the new one's (`digimonId` = `stat_gains[target].targetDigimon`) | ported |
| C11 | 0xA5–0x162 | `evl.c:481–502` | `angle += lerp(0, 0x16, 0xA4, 0xC2, f)` for f < 0xC3, else `+= 0x16`; ref and eye = the orbit with C10's sizes; offset and projection stay | ported |
| C12 | C11 expected | (from C8, C11) | angle at 0xA5: 0x714 (step 0) · 0xB3: 0x765 · 0xC2: 0x85B · 0xC3: 0x871 · 0x162: 0x161B. Steps: 0xA5: 0 · 0xB3: 11 · 0xC2: 22 | (test values) |
| C13 | Restore | `evl.c:550–559` (0x162), `:563–566` (0x163) | The saved view back (`GS_VIEWPOINT`, offset, projection) | ported (`FieldMap.restore_map_view()`: the scroll doesn't move while the follow is off, so it gives the saved view; the scan checks `view()` equals the saved one) |
| C14 | Camera follow | `partner.c:752, 790` (5f-1) | Off from state 13's sub-state 0 to its end | already |

### D. The bones breaking (`evl.c:415–461`, `EVL_initEvoSequence` `:1277`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| D1 | Bone order | `evl.c:1306–1327` | `order[i] = rand() & 0xFFF` for i = 1 .. boneCount − 1 (boneCount − 1 rolls, in that order); then boneCount − 1 times: the lowest `order[j]` over j = 1 .. boneCount − 1 (strict `>`: the lowest index wins a tie) → `list[i − 1]`, `order[best] = 0x1000`. `list[boneCount − 1] = −2`, the rest −1 | ported |
| D2 | Bone count | `DIGIMON_DATA[type].boneCount` | `digimon.bone_count` of the old Digimon (Agumon 22: bones 1–21) | ported |
| D3 | Break frames | `evl.c:412–419, 429–431, 457–460`, `EVL_D_80063EFC` `:253` | 0x6A (state 1's last frame); 0x70–0x9A where `EVL_D_80063EFC[f − 0x70] ≥ 0` (indices 0, 16, 26, 34, 38, 40, 42 → 0x70, 0x80, 0x8A, 0x92, 0x96, 0x98, 0x9A); every frame 0x9B–0x11B. One bone each, while `next < boneCount − 1` | ported |
| D4 | Bones without an object | `evl.c:433–438` | `objIndex == −1` (the sidecar's `skeleton.bones[b][0]` = 255): skipped in the same frame, and the next bone in the list is tried | ported |
| D5 | Per bone, in order | `evl.c:439–454` | `playSound(8, rand() % 3 + 2)`; `EVL_buildShardSet(obj, bone)` (§E); `PARTNER_WIREFRAME_SUB[bone] = 0`; `EVL_spawnSpark(bone, 0x11C − f)` (§F); a flash (D6) | ported |
| D6 | Bone flash | `evl.c:443–454`, `efe.c:808` | `create_flash(1, bone position, −1, 10, 0, 0x333, (0x96, 0x96, 0x96), (0x14, 0x14, 0x14))`; the position is copied (it doesn't follow the bone) | ported |
| D7 | Bone position | `evl.c:443` (`posData[bone].posMatrix.workm.t`) | The bone's world position from the last render | port-only: the port reads the current pose (the C's is the previous frame's) |
| D8 | Agumon expected | (from D3, D4, the sidecar `AGUM.json`) | 16 of bones 1–21 have an object: breaks at 0x6A, 0x70, 0x80, 0x8A, 0x92, 0x96, 0x98, 0x9A, then 0x9B–0xA2 | (test values: the scan counts the breaks and their frames) |

### E. The shard sets (`EVL_buildShardSet` `evl.c:1001`, `EVL_tickShardSet` `:869`, `EVL_renderShardSet` `:882`, `EVL_renderTriShard` / `QuadShard` `:912` / `:1118`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| E1 | Slots | `evl.c:301–316, 1038–1045` | 30; none free → no set (the rest of D5 still happens) | ported (no partner reaches it: at most 29 breakable bones, Phoenixmon; E11) |
| E2 | Vertices | `evl.c:1047–1057` | The object's vertices through the bone's current matrix (`calculateBoneMatrix`, the root's rotation, scale and location included): world positions, frozen | ported |
| E3 | Drift per face | `evl.c:1070–1112` | Per primitive in order: modes 0x34 / 0x36 (triangle) and 0x3C / 0x3E (quad): the mean of the **first three** posed normals (`n0 n1 n2`, quads also / 3; the bone matrix's rotation and scale, no translation); any other mode: nothing written and the pointer doesn't move (no later face is read) | ported |
| E4 | Offset | `evl.c:931–933, 1139–1141` | `drift × timer / 60` per component (truncated) | ported |
| E5 | Grey | `evl.c:895–897` | `(31 − timer) × 74 / 30 + 54`: timer 0: 130 · 15: 93 · 31: 54 | ported |
| E6 | Life | `evl.c:869–880` | tick: `timer ≥ 0x1F` → removed, else + 1. With A3: drawn at timers 0 … 31 (32 frames) | ported |
| E7 | Look | `evl.c:922–948, 1129–1160` | `POLY_FT3 / FT4`, unlit, the face's UVs and CLUT, semi-transparent; tpage = the model's `pixelPage` (`model.c:3400`: 0x16 + k / 2, abr bits 0 = **half / half**); colour E5 / 128; no back-face culling (`RotTransPers3/4`, no `NormalClip`) | ported |
| E8 | Which texels blend | PSX STP rule; the palette at draw time (G2–G4) | A semi-transparent primitive blends only the texels whose STP bit is set; the others are opaque. The shards read the partner's live palette: its own STP bits until the brighten's first non-start frame (0x71), then every non-black colour has STP (G3). So shards draw opaque (except the model's own STP texels) up to 0x70, half / half from 0x71 | ported |
| E9 | Render loop | `evl.c:899–909` | The same stop as E3: an unknown mode ends the set's drawing | ported |
| E10 | Scratch buffer | `evl.c:1031, 1114`; `EVL_D_80066274` size 0x153C (`symbols_evl.txt`) | Vertices + drifts of every set, 6 bytes each, never reset in a sequence. Over 0x153C bytes it overruns the flash buffer. No partner reaches it: the largest is Agumon's 4812 bytes; only Guardromon, Jijimon, Cherrymon, King Sukamon, ShogunGekomon and Machinedramon would (measured on the porter's sidecars, 2026-11-01) | port-only: no limit |
| E11 | Gone before the apply | (from D3, E6; the partners' sidecars) | The most breakable bones of any partner is 29 (Phoenixmon): its last set is built at 0xAF and drawn last at 0xCF, so every set is gone before 0x11C. At most 25 sets alive at once (at 0xAF) | (test value) |

### F. The sparks (`EVL_spawnSpark` `evl.c:806`, `EVL_tickSpark` `:1264`, `EVL_renderSparkStreak` `:1222`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| F1 | Slots | `evl.c:815–823` | 16; none free → no spark. All sparks live until 0x11C, so only the first 16 broken bones get one (Agumon breaks 16, Greymon 20, Phoenixmon 29) | ported |
| F2 | Timer | `evl.c:442, 1264–1275` | `0x11C − f` at the break; tick: `timer < 0` → removed, else − 1. With A3: drawn from the break frame to 0x11D | ported |
| F3 | Points | `evl.c:1234–1250` | `a` = bone 1's position; `d = bone's position − a` (int16); `lenSq = d·d`; `s = custom_random(0x190, 0x1F4)²`; tip `b = a + d × s / lenSq` per component | ported |
| F4 | `lenSq` = 0 | `evl.c:1248–1250`; `asm/us/evl/evl.s` (`div` with no zero check) | Bone 1's own spark: d = 0. The R3000A gives −1 for 0 / 0, so `b = a + (−1, −1, −1)` | port-only: the hardware's result |
| F5 | Jitter | `evl.c:1251–1253` | `c = b + custom_random(−0x50, 0x50)` per component (x, y, z in order) | ported |
| F6 | Grey | `evl.c:1260` | `rand() % 128 + 10`, after F3–F5's rolls | ported |
| F7 | Rolls per spark per frame | (from F3–F6) | 4 `custom_random()` then 1 `rand()`, every frame it is drawn | ported |
| F8 | Look | `evl.c:1254–1261` | Triangle (c, a, b), additive (`getTPage(0, 1, 768, 256)`), CLUT (192, 489), UVs (0x5F, 0xA0) (0x5F, 0xA7) (0x30, 0xA0): the same primitive as DOO2's streak, drawn with `SparkStreaks` (6-2 I6: its `{"b": c, "origin": a, "a": b}`) | ported |
| F9 | After the apply | `effect_common.c:341–343` | The sparks drawn at 0x11C–0x11D read the new model's bones; a bone ≥ the new `boneCount` reads bone 0 | ported |

### G. The palettes of the partner (`EVL_brightenDigimonClut` `evl.c:951`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| G1 | Frames | `evl.c:426–428` | Timer 0x70–0xCC (`< 0xCD`): `brighten(start 0x70, end 0x9A, t = min(f, 0x9A))` | ported |
| G2 | Rolls | `evl.c:973–975` | Each call: factors `rand() % 100` for R, G, B, in that order (3 rolls a frame) | ported |
| G3 | Per colour | `evl.c:976–995` | Over the partner's palette tile (16 × 24): colours that aren't black (any channel ≠ 0): each channel `c += factor × ((31 − c) × (t − 0x70) / 0x2A) / 100` (5-bit, truncated). If t ≠ 0x70 their STP bit is set. Black stays black and keeps its STP bit | ported |
| G4 | G3 expected | (from G3) | c 10, factor 50, t 0x85: (21 × 21 / 42) = 10 → 50 × 10 / 100 = 5 → **15** · c 0, any: 0 · c 31: 31 · t 0x70: unchanged · t 0x9A, factor 99, c 0: … stays 0 (black) · c 1, factor 99, t 0x9A: 1 + 99 × 30 / 100 = **30** | (test values) |
| G5 | After 0xCC | `evl.c:426`; nothing restores the tile | The last frame's colours stay until the old model is replaced at 0x11C (the new one has its own palette) | ported |
| G6 | Where it shows | (from G3, D5) | On the old body's faces still textured (the bones not yet broken), and on the shards (E8) | ported |

### H. The particles (`EVL_spawnParticle` `evl.c:778`, `EVL_tickParticle` `:1163`, `EVL_renderParticle` `:1176`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| H1 | Spawn | `evl.c:421–425`, `EVL_D_80063F28` `:262` | State 2 only (0x6B–0x162): when `table[f % 18] ≠ 0` (table `1 2 3 4 5 4 3 2 1 0 0 0 0 0 0 0 0 0`), one particle at `EVL_D_80064D40` = the partner's location at `EVL_initEvoSequence` (`:1294`) | ported |
| H2 | Colour | `evl.c:200, 422–423` | (0x0A, g, 0x0A) with `g = lerp(0x32, 0xE6, 1, 5, v)`: v 1–5 → 50, 95, 140, 185, 230 | ported |
| H3 | Slots | `evl.c:783–793` | 100; none free → none | ported (about 44 alive at most) |
| H4 | Life | `evl.c:1163–1174` | tick: `timer ≥ 0x56` → removed, else + 1. Drawn at timers 0 … 0x56 | ported |
| H5 | Shape | `evl.c:1186–1196` | A square on the floor: corners (x ± s, y, z ± s) in the order (+, +), (+, −), (−, −), (−, +), `s = lerp(8, 0x9C4, 0, 0x56, timer)`: 0: 8 · 1: 36 · 43: 1254 · 0x56: 2500 | ported |
| H6 | Edges | `evl.c:1198–1217` | Edge i → i + 1 (mod 4), a `LINE_F2`, opaque, colour `lerp(c, 0, 0, 0x56, timer)` per channel (g 230: 0: 230 · 43: 115 · 0x55: 3 · 0x56: 0), drawn only if both ends' depth (`worldPosToScreenPos >> 4`, as the flashes') is in (0x20, 0x1000) | ported |
| H7 | Depth | `evl.c:1214` | OT 0xFA1: behind every model, over the background (black by then) | ported (2D lines on the background layer, under the 3D world) |
| H8 | Released | `evl.c:575, 854–867` | State 3: every particle removed | ported |

### I. The flashes at the centre (`evl.c:503–529`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| I1 | Sounds | `evl.c:503–506` | At 0xD6: `stopSound()`, `playSound(8, 5)` | ported |
| I2 | Frames | `evl.c:507` | Even frames of 0xD7–0x11B: 0xD8, 0xDA … 0x11A (34 flashes) | ported |
| I3 | The call | `evl.c:508–528` | `create_flash(0, bone 1's position, depth, 10, 0, lerp(0x333, 0x4800, 0xD6, 0x11C, f), start, (0x14, 0x14, 0x14))`; `depth = 0x21` when `(f & lerp(5, 1, 0xD6, 0x11C, f)) == 0`, else 0xFA0; start = `lerp(0x32, 0x78, 0xD6, 0x11C, f) + rand() % 100` for R, G, B in that order | ported |
| I4 | I3 expected | (from I3) | f 0xD8: mask 5, depth 0x21, scale 0x52A, base 52 · 0xDC: 5, 0xFA0, 0x918, 56 · 0xF8: 4, 0x21, 0x249D, 84 · 0xFA: 3, 0xFA0, 0x2695, 86 · 0x11A: 2, 0xFA0, 0x4608, 118. 17 of the 34 at depth 0x21 | (test values) |
| I5 | Flash buffer | `evl.c:1302` (`initializeFlashData(EVL_D_800677B0)`), `efe.c:832–841` | The sequence's own 12 flash slots (`BattleFx`, its own instance); none free → no flash | ported |

### J. The bodies (`renderWireframed` via `renderDigimon`, `model.c:2911–2919`; `evl.c:441, 530–551`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| J1 | Old body | `evl.c:441`, `model.c:2493, 2915` | `PARTNER_WIREFRAME_TOTAL` 16; `SUB[bone] = 0` per broken bone: that bone's object is all outlines (6-2 A2–A11), the others normal | ported (`PartnerWireframe.set_share(16, sub)`) |
| J2 | Greys | 6-2 A5–A6 | One `rand()` per object drawn in wireframe per frame; min / max 0x37 / 0xFF (the evolution never changes them) | already |
| J3 | Scale | `evl.c:466–472` | 0xCC–0x107: root scale x = z = `lerp(0x1000, (r_new << 12) / r_old, 0xCC, 0x108, f)`, y = `lerp(0x1000, (h_new << 12) / h_old, …)`; from 0x108 to 0x11B unchanged (the 0x107 value) | ported |
| J4 | J3 expected | (Agumon → Greymon: ratios 7850, 6553) | 0xCC: (4096, 4096) · 0xEA: (5973, 5324) · 0x107: (7787, 6512) | (test values) |
| J5 | The apply | `evl.c:530–543` | At 0x11C: `TOTAL = 0`, `SUB[0..39] = 16`, `EVL_applyEvolution` (5f-1: `Evolution.apply_evolution` + `Partner.load_digimon` at the same position and rotation), animation 0 | ported |
| J6 | New model's scale | `model.c:2853–2858` | 0x1000 (the model's set-up) | ported |
| J7 | New body | `evl.c:544–546, 551` | 0x11C–0x125: all outlines (total 0); 0x126–0x14E: `TOTAL = lerp(0, 0x10, 0x126, 0x14E, f)`: 0x126: 0 · 0x13A: 8 · 0x14D: 15 · 0x14E: 16; 0x162: 16 | ported |
| J8 | Shadow | `drop_shadow.c` (`specs/drop_shadow.md`) | Drawn as usual. It subtracts from a black background, so nothing shows | ported (nothing to do) |

### K. The end (`evl.c:561–585`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| K1 | 0x162 | `evl.c:547–559` | State 3, `TOTAL = 16`, the saved view back | ported |
| K2 | 0x163 (state 3) | `evl.c:561–577` | The view again; `fadeoutCLUT1(0)`, `fadeoutCLUT2(0)`; both banks back (`fade(…, 0, 1, 0)`: factor 1, their own STP bits); entities and map layer back (B10, B11); `forceUpdateBGM`; animation 0xB; the particles released; `loadMapSounds2(map's sound set)` | ported |
| K3 | State 4 | `evl.c:578–585` | When 0xB's `animFrame == frameCount`: `timer = −1`, the object removed (`isSoundLoaded(0, 8)` is a query: nothing to port) | ported (an endless 0xB: `PsxAnimator.finish_loop`, as 5f-1) |
| K4 | Partner state 13's end | `partner.c:774–791` | 5f-1 §2.7 (game time, `EVOLUTION_TARGET = −1`, map sounds, state 1, sync bit or the tamer freed and the follow back) | already |

## 4. Behaviour

### 4.1 The sequence (§A–§D, §I–§K)

`EvlSequence` is `EVL_tickEvoSequence` as one state machine, frame for frame: state 0 (B1–B9), 1 (C5–C8, the first break at 0x6A), 2 (D3–D6, H1, G1, C10–C11, J3, I1–I3, J5, J7, K1), 3 (K2), 4 (K3). It owns the logic of its effects (§4.2–4.5) and ticks them in the same call, but what it makes in a call isn't ticked until the next one (A3): right after the tick of frame f, a new flash has progress 0, a new set timer 0, a new particle timer 0, a new spark timer `0x11C − f`. Within a state-2 frame the rolls come in the C's order: the brighten's three, then each break's sound, then the centre flash's three. It changes nothing outside itself: it reports through its members and signals, and the host applies them.

### 4.2 The shard sets (§E)

One set per broken bone, built from the bone's posed vertices and normals at the break, frozen. Each frame each face is drawn at its vertices + drift × timer / 60, in grey E5, half / half where its texel has STP (E8).

### 4.3 The sparks (§F)

Up to 16 sparks, each a triangle from bone 1 outwards in its bone's direction, re-rolled every frame (F3–F7) from the bones' current positions.

### 4.4 The particles (§H)

Green square outlines on the floor plane at the partner's start location, growing and fading, drawn behind everything.

### 4.5 The flashes (§D6, §I)

The sequence's own `BattleFx`: one flash per broken bone, and the 34 centre flashes. Drawn by a `BattleFxView` with `FieldMap` as its projector (as in 6-2).

### 4.6 The palettes (§B, §G)

- **Fades:** a tint on the materials (`PaletteFade`, factor 0–1):
  - the map background: `BackgroundDark`;
  - the bubbles, poop, items and chests' icons: their own tint (B3);
  - the tamer on even frames and the NPCs on odd frames: `PaletteFade` (B4).
- **Brighten:** a per-channel pull towards white on the partner's textured passes, done in the shader on 5-bit values (G3): `PsxLit` uniforms `brighten_factor` (the three rolls / 100) and `brighten_step` ((t − 0x70) / 0x2A as the integer pair). The same values go to `PartnerWireframe`'s face materials and the shards' materials. After the brighten's first non-start frame, the shards' blend covers every non-black texel (E8).

## 5. Godot design (to approve)

Logic lives in plain classes, headless-testable (`specs/scenes.md` §3). Views are scenes that `EvolutionHost` instantiates, so a mod can replace them (rule 7). The host hands the views the logic's state every frame; nothing in a view changes the logic.

| Part | Files | Kind | API (what the tests call) |
|---|---|---|---|
| `EvlSequence` | `scripts/field/evolution/evl_sequence.gd` (`RefCounted`) | logic | `init(bone_count: int, bone_objects: PackedInt32Array, location: Vector3i, rotation_y: int, old_size: Vector2i, new_size: Vector2i)` (D1, H1, C4, C10: sizes are (radius, height); the bone order rolled here, nothing else rolled); `tick()` (the frame `timer`, then `timer += 1`, A4); members `timer`, `state`, `bone_order: PackedInt32Array` (40), `next_bone`, `angle`, `map_fade` (0–255, B1), `bank0_factor` / `bank1_factor` (B4, float, 1 = full), `brighten: Vector3i` (factors) and `brighten_t` (−1 none), `scale: Vector3i` (4096 = 1), `wireframe_total`, `wireframe_sub: PackedInt32Array` (40), `saved_view: Dictionary`; `fx: BattleFx`, `shards: EvlShardSets`, `sparks: EvlSparks`, `particles: EvlParticles`. Signals `bone_broken(bone: int)` (the host builds the set in the same call: `shards.build(...)` with the posed bone), `hand_over()` (0x20), `applied()` (after the apply at 0x11C), `ended()` (0x163). Callables `get_view`, `set_view`, `restore_view`, `bone_position(bone) -> Vector3i` (bone 0 = the location, C1), `apply_evolution()`, `play_sound(slot, value)`, `stop_sound()`, `start_animation(id)`, `animation_done() -> bool` (the animation last started has played to its end); each may be unset (headless: skipped). Member `animation`: the id last started (A5 reads it) |
| `EvolutionScene` (changed) | `scripts/field/evolution_scene.gd` | logic | The loading as today, then `EvlSequence` (A2), in member `sequence` (null until the loading ends); `timer` is the C's one `EVO_SEQUENCE_DATA.timer` (the loading's, then the sequence's, −1 at the end), read by the partner (A1); `tick()` still returns it; it provides the sequence's `apply_evolution`, `start_animation` and `animation_done` from the partner; the stand-in removed (§2) |
| `EvlShardSets` | `scripts/field/evolution/evl_shard_sets.gd` | logic | `sets: Array[Dictionary]` (30), each `{"timer" (−1 free), "bone", "object", "vertices": Array[Vector3i], "drifts": Array[Vector3i]}`; `build(bone: int, object: Dictionary, vertices: Array[Vector3i], normals: Array[Vector3i]) -> int` (slot or −1); `tick()`; `faces(set) -> Array` (each `{"kind", "face", "points": Array[Vector3i]}`: E3, E4, E9); `static func grey(timer: int) -> int` (E5) |
| `EvlSparks` | `scripts/field/evolution/evl_sparks.gd` | logic | `sparks: Array[Dictionary]` (16) `{"bone" (−1 free), "timer"}`; `spawn(bone, timer) -> int`; `tick()`; `static func streak(bone_pos: Vector3i, centre: Vector3i) -> Dictionary` (`{"a", "b", "origin", "grey"}` for `SparkStreaks.draw_streaks`: F3–F7) |
| `EvlParticles` | `scripts/field/evolution/evl_particles.gd` | logic | `particles: Array[Dictionary]` (100) `{"timer" (−1 free), "pos", "color": Vector3i}`; `spawn(pos, color) -> int`; `tick()`; `release_all()`; `static func corners(p) -> Array[Vector3i]` (H5); `static func color(p) -> Vector3i` (H6) |
| `PaletteBrighten` | `scripts/field/evolution/palette_brighten.gd` | logic | `static func channel(c5: int, factor: int, t: int) -> int` (G3, one channel); `static func colour(rgb5: Vector3i, factors: Vector3i, t: int) -> Vector3i` (G3: black stays black); `static func apply(node: Node3D, factors: Vector3i, t: int)`; `static func clear(node: Node3D)` (like `PaletteFade`: copies of the materials) |
| `PsxLit` brighten | `shaders/psx_lit/psx_lit.gdshaderinc` (uniforms only, off by default) | view | `brighten_factor: ivec3`, `brighten_t: int` (−1 off): G3 on the texel's 5-bit channels. With them off, nothing changes (every render check byte-identical) |
| `CutsceneCamera` (extended) | `scripts/field/death/cutscene_camera.gd` | logic | `orbit(position, angle, height, distance := -1)` and `view(…, distance := -1)`: −1 = 6-2's `height × 5 + 1200` (DOOA unchanged); EVL passes C2. Note: `orbit` adds 0x638 to its angle (DOOA's D1); EVL's angle already holds it (C6, C8), so the rotation must come out as `angle + rotation.y` (the tests check the views, not how) |
| `MapLayer` | `scripts/field/map_layer.gd` | logic | `set_enabled(nodes: Array, enabled: bool)` (`setMapLayerEnabled`, moved out of `DeathHost._set_map_layer`, which then calls it) |
| `EvolutionHost` | `scenes/field/hosts/evolution_host.tscn`, `scripts/field/hosts/evolution_host.gd` | view host | Children: `EvolutionScene`, `PartnerWireframe` (an instance of `partner_wireframe.tscn`). Made in `start()`: `EvlShardsView`, `SparkStreaks`, `EvlParticlesView`, a `BattleFxView` (`fx = sequence.fx`, `projector = field_map`), a `BackgroundDark`. `tick_objects()` (A1); `bone_position` from the model's `Skeleton3D` (bone ≥ count → 0, F9); the wireframe attached at the first break and re-attached to the new model on `applied`. Exposes `wireframe`, `shards_view`, `particles_view` (the scan reads them) |
| `EvlShardsView` | `scenes/field/evolution/evl_shards.tscn`, `scripts/field/evolution/evl_shards_view.gd` | view | `draw(sets: EvlShardSets, materials_of: Callable, translucent: bool)`: one `ArrayMesh` per frame, double-sided, unlit, the face's material with the grey and the brighten, half / half on STP texels (E7, E8); `shown_faces() -> int` |
| `EvlParticlesView` | `scenes/field/evolution/evl_particles.tscn`, `scripts/field/evolution/evl_particles_view.gd` | view | A `Node2D` on the field's background layer (under the 3D world, H7): `draw(particles: EvlParticles, project: Callable)` with `FieldMap.world_to_screen` and H6's depth test; `shown_lines() -> int` |
| `PartnerWireframe` (extended) | `scripts/field/partner_wireframe.gd` | view | `posed_bones()` entries also carry `"normals": Array[Vector3i]` (the object's normals through the attachment's basis, PSX ints, E3) |
| Field wiring | `scripts/field/field.gd`, `scripts/field/hosts/care_host.gd`, `scripts/field/partner.gd`, `scenes/field/field.tscn` | wiring | `Systems/EvolutionHost`; `CareHost` keeps `Evolution` but no longer makes `EvolutionScene`; `Partner.tick_evolving` reads the timer (A1) |

Data sources: the old and new models' sidecars and glTF (as 6-2: `skeleton.bones[b][0]` = the object, 255 none; `tmd.objects[i]` with `vertices`, `normals`, `primitives` in TMD order); `digimon_data` `bone_count`, `radius`, `height`.

**Order in the frame** (port-only, as 6-2 §5): the sequence ticks in `EvolutionHost.tick_objects()`, then its effects tick (A3), then the host draws. The render-time rolls happen in this order: the wireframe greys, then the sparks (F7). The C's order between the entity render and the object render isn't traced.

## 6. Order of work

Each step lists its complexity and model (`docs/agent_workflow.md` "Complexity and model"), its files (owned), its tests and the user's in-game check. All suites and the three scans pass after every step. The spec, the tests and the review of every step are done by Claude Opus 5.5 (the main session).

| Step | Complexity · model |
|---|---|
| 1. The sequence and its host | logic (`EvlSequence`, `CutsceneCamera`'s distance, `MapLayer`) **Low** · Gemini 3.8 Flash (High): every value in §3 and the tests decide it. Host, field wiring, camera, hiding, flashes' view **Medium** · Claude Sonnet 5.5 (Medium): several systems wired, the moves already proven by 6-2 |
| 2. The bodies | **Medium** · Claude Sonnet 5.5 (Medium): `PartnerWireframe` exists; new are the per-bone shares, the re-attach to the new model and the root scale; a short in-game check covers the look |
| 3. The shard sets | logic (`EvlShardSets`) **Low** · Gemini 3.8 Flash (High); view (`EvlShardsView`, posed normals, double-sided half / half on STP texels) **Hard** · Claude Opus 5.5 (Medium): rendering the tests can't judge |
| 4. Sparks and particles | logic (`EvlSparks`, `EvlParticles`) **Low** · Gemini 3.8 Flash (High); views (`SparkStreaks` reused, `EvlParticlesView` on the background layer) **Medium** · Claude Sonnet 5.5 (Medium) |
| 5. The palettes | fades (B1–B4: `BackgroundDark`, `PaletteFade`, the CLUT2 nodes) **Medium** · Claude Sonnet 5.5 (Medium); brighten (`PaletteBrighten`, the `PsxLit` uniforms, shared with the wireframe and the shards) **Hard** · Claude Opus 5.5 (Medium): shader maths on 5-bit texels, a visual result |
| 6. Clean up | **Low** · Gemini 3.8 Flash (High) |

1. **The sequence and its host.**
   - Files: `evl_sequence.gd`, `evolution_scene.gd`, `cutscene_camera.gd` (the distance parameter only), `map_layer.gd`, `death_host.gd` (`_set_map_layer` calls `MapLayer` only), `evolution_host.tscn/.gd`, `field.gd`, `field.tscn`, `care_host.gd`, `partner.gd` (`tick_evolving` sub-state 2 only).
   - Tests: `test_evolution_scene.gd` "timeline", "camera", "bones", "flashes"; `test_evolution.gd` unchanged (its loading timings stay: A1 moves the call, not the timers); `evolution_scan` "hand-over", "centred", "end".
   - Check: the field goes dark; everyone but the partner vanishes; the camera swings in and the partner stands centred; it orbits, stops, then orbits faster; flashes at the bones and at the centre; at the end the field comes back as it was. The body is still solid in this step.
2. **The bodies.**
   - Files: `evolution_host.gd` (wireframe and scale), `partner_wireframe.gd` (only if the re-attach needs it).
   - Tests: "bodies"; `evolution_scan` "outlines", "new body".
   - Check: each bone turns to grey outlines as it breaks; the outline body stretches to the new size; the new Digimon appears in outlines and fills in.
3. **The shard sets.**
   - Files: `evl_shard_sets.gd`, `evl_shards.tscn`, `evl_shards_view.gd`, `partner_wireframe.gd` (`posed_bones` normals), `evolution_host.gd`.
   - Tests: "shards".
   - Check: each breaking bone's faces fly off along their normals, fade and vanish; the first two bones' shards are solid, the later ones see-through.
4. **Sparks and particles.**
   - Files: `evl_sparks.gd`, `evl_particles.gd`, `evl_particles.tscn`, `evl_particles_view.gd`, `evolution_host.gd`.
   - Tests: "sparks", "particles"; `evolution_scan` "rings behind".
   - Check: streaks from the body's middle towards each broken bone, flickering; green squares growing on the floor, always behind the partner.
5. **The palettes.**
   - Files: `palette_brighten.gd`, `psx_lit.gdshaderinc` (uniforms and their branch only), `evolution_host.gd`, `evl_shards_view.gd` (the brighten values).
   - Tests: "fades", "brighten"; `tests/render_check.gd` byte-identical with the brighten off.
   - Check: the tamer and the NPCs darken and flicker out as the field goes dark; the bubble and any items fade; the partner glows in flickering colours from the first breaks; its shards carry the glow.
6. **Clean up.**
   - Files: `specs/evolution.md` §2.9 (points here), `VERIFY.md` "Evolution" (the checks above), `PLANS.md`, this spec's "As built".
   - Tests: `test_rules.gd` "5f-2 stand-ins gone".

## 7. Tests

Written 2026-11-01 by the reviewer. The expected values are the C's (§3), worked out from the C, not with the port's code. Until step 6 each check runs only once its step is reached: `DW_STEP_5F_2=<step>` (1–6); without it they print PENDING. Set it to the step being built (e.g. `DW_STEP_5F_2=3` runs the checks of steps 1–3). `tests/test_evolution.gd`'s state-13 and loading checks follow the same gate: from step 1 the partner reads the timer (A1) and the loading's end no longer applies the evolution (§2).

`tests/test_evolution_scene.gd` (headless; with Agumon's and Greymon's real data and sidecars when the porter output is there):
- **timeline:** an `EvlSequence` with fakes: the states by frame (A4: 1 at 0x21, 2 at 0x6B, 3 at 0x163, −1 when the fake's animation ends); `map_fade` (B1); `bank0_factor` on even frames and `bank1_factor` on odd ones (B4, B5); 3 `rand()` a frame for the banks (B7); `hand_over` at 0x20; the sounds (D5, I1, the 0x6A pair); animations 0xC → 1, 0 at 0x11C, 0xB at 0x163; `apply_evolution` called once, at 0x11C; the loading → first tick on the next frame (A2).
- **camera:** `CutsceneCamera.orbit` with C2's distance; the views at 0x21, 0x40, 0x50, 0x60 (C6, C7: Agumon's offset (160, 124)); `angle` per frame (C8, C9, C11, C12); the C10 sizes at 0xCB, 0xCC, 0xEA, 0x108; `restore_view` at 0x162 and 0x163.
- **bones:** D1 replayed with a seeded RNG (the rolls, the tie rule, the −2); the break frames (D3) on a 22-bone fake; bones without objects skipped in the same frame (D4); per break: one `rand()` before the build, the sound, `wireframe_sub[bone] = 0`, a spark with timer `0x11C − f`, the flash (D6); 17 breaks with only 16 sparks (F1).
- **bodies:** `wireframe_total` / `wireframe_sub` every frame (J1, J5, J7); `scale` (J3, J4).
- **flashes:** D6 per break; I2–I4 (the 34 frames, depth, scale, colour base, 3 rolls each); the 12-slot limit (I5).
- **shards:** E3 (normals mean, quads / 3, a 0x2C face stops the object), E4, E5, E6 (32 drawn frames), E1's limit, E11.
- **sparks:** F2's life; F3 on hand-made positions; F4 (bone 1: b = a − 1); F5–F7 (rolls replayed); F9.
- **particles:** H1 (spawn frames, 0x6B–0x162), H2, H4, H5, H6 (colours and the depth test on a fake projector), H8.
- **fades / brighten:** `PaletteBrighten.channel` (G4); G1 (frames, t clamp), G2 (3 rolls a frame, R G B order), G5 (unchanged after 0xCC).
- Not unit-tested (the user's check): the look of each view; B6 (Q4); E8's blend on screen.

`tests/evolution_scan.tscn` (the real field, Agumon → Greymon through `Evolution`'s state 13):
- **hand-over:** at 0x20, every entity but the partner hidden; the map layer nodes hidden; `saved_view == field_map.view()` before the camera moves.
- **centred:** from 0x60 to 0x6A the partner's middle (y + h / 2) projects to (160, 124) ± 1.5 px.
- **outlines:** at 0xA3, every bone of Agumon with an object has share 0 (D8).
- **rings behind:** while particles exist, `particles_view` is on the background layer (under the world).
- **new body:** at 0x11C the partner is Greymon, the wireframe attached to the new model with total 0; at 0x14F share 16.
- **end:** at the end, `view()` equals the saved view, the entities and map layer as before, no sets / sparks / particles / flashes alive, scale 1, no tint or brighten on any material, partner state 1, the tamer free and followed.

`tests/test_rules.gd` "5f-2 stand-ins": no `stand-in` in `scripts/field/evolution_scene.gd`, no `STATE_POSE` / `_apply(` there.

## 8. Open questions

- **Q1.** `system_w` palette 13 ((96, 501)) is faded with the map (B3). Which field element draws with it? Not found yet. The port fades nothing for it until it is found. It is hidden or idle during the scene in any case (state 13 closes box 1 and the menus).
- **Q2.** Bubble 7 (shown by the loading) fades with B3 only if it draws with `feel_ef` palette 0 (row 480). The implementer reads the bubble's palette from the porter's `feel_ef` data and fades it only if so.
- **Q3.** `fadeoutCLUT1` uploads rows 481–483 from an uninitialised stack buffer (`effect_common.c:381–386`: `src` / `dst` skip 768 entries that are never written). Whatever those rows hold in the field turns to garbage while it runs. The port doesn't reproduce it (port-only); nothing in the field seen so far draws with those rows.
- **Q4.** Answered (the user, 2026-11-01): in the original the tamer just fades, with no black patches, so B6's tint is right.
- **Q5.** A3's next-frame rule, and the order of the render-time rolls (§5), are the port's choice. They change no value a test checks, only which `rand()` goes where within a frame.
