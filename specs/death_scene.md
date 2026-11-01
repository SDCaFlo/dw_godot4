# The death scene's look (step 6-2)

Drawing the DOOA dissolution and rebirth, and the parts of MURD still drawn by stand-ins, the way the original does. The scenes' timelines are already ported (`specs/death_reincarnation.md`: `MurdScene`, `DooaScene`, the partner and tamer states). This step replaces the stand-in visuals in `DeathHost` (`scripts/field/hosts/death_host.gd`, `scenes/field/death/partner_dissolve.gdshader`) and fills the logic gaps of §4.11. Bug report: `ISSUES.md` I-38 (`issues/evidence/dw_very_bugy_death.mp4`).

**Status (2026-10-31):** done (all nine steps, branch `feat/6-2-death-scene`); the acceptance tests pass (§7, the gate removed). As built: §9. The user's in-game checks: `VERIFY.md` "Death, lives and reincarnation" (confirmed by the user 2026-10-31).

## 0. How to work on this step

- Read first: `AGENTS.md` (the folder above `dw_godot/`), `docs/porting_checklist.md`, then this spec: §1 (what the player sees), §3 (the values), §5 (the design), §6 (your step).
- **The acceptance tests are fixed:** `tests/test_death_scene.gd`, the 6-2 checks in `tests/death_scan.gd` and `tests/test_rules.gd`'s "6-2 stand-ins". Don't change them; when one looks wrong, stop and report it with the C line that shows it. They were written from the C by the reviewer, not from the port. (They were gated by `DW_STEP_6_2=1` until step 9; now they are plain checks.)
- **Every value comes from §3.** A value you need that isn't there: find it in the C, add its row (C file, line, value, status), and say so in your report. Never guess one.
- **One step of §6 at a time.** Each step lists the files it owns; don't edit others. After each step: run every suite (`tests/test_*.gd`, `tests/test_rules.gd` included), `tests/exit_scan.tscn` and `tests/death_scan.tscn`, then stop for review and the user's in-game check.
- The C is in `external-resources/dw_decomp/src/`. **We port the US build:** where the C has `#if VERSION_IS(US)` / `#else`, read the US branch (e.g. `renderWireframed` is `model.c:3129`, not `:3003`).

---

## 1. What the player sees (no life left, or a natural death)

Frames are `DooaScene.frame` (the dissolution's `seq->frame`, `dooa.c:310`), then the rebirth's own counter.

1. **Iris** (0–0x21, natural death only: MURD drew it otherwise). Everything is drawn under the iris until the partner gets bigger on screen than the iris's window (`DOOA_hasIrisClosed`, `dooa.c:602`). From then on the partner is drawn in front of the iris (its own ordering table, `DOOA_renderDissolve`, `dooa.c:579`).
2. **Map change** (0x23): Jijimon's house. The room is black: the map background faded to 0 (`fadeoutCLUT1(0xFF)`, `dooa.c:406`), every entity hidden but the partner. The partner keeps its old map position, and the camera keeps the old map's view.
3. **Camera in** (0x23–0x55): the camera moves from the old map's view to an orbit view of the partner (§4.4).
4. **To the centre** (0x56): the partner jumps to the room's origin, facing the tamer, and the camera jumps to nearly the final orbit view there. With lives left it plays animation 0xC (falling), then 1.
5. **Wireframe and falling shards** (0x69–0x8C): 36 frames, the wireframe share stepping 15 → 0 (V-B1). At each step, the faces of that group turn into flickering grey outlines, and about 3 in 4 of them break off as textured shards that fall to the floor and stay there. Sound (8, 0) at 0x69, stopped at 0x8C.
6. **Squash** (0xC0–0xD0): the all-outline body squashes, then stretches up and thins, then sinks (V-C). Sound (8, 1) at 0xBF.
7. **Gone, the rising flash** (0xD1–0x135): the body disappears; sound (8, 2). A flash appears every frame, rising from below the floor to the ground and wobbling sideways (V-E). At 0x135 the shards on the floor start flickering in random colours, sound (8, 3).
8. **Camera out** (0x149–0x17B): the camera moves back to the room's own view (the orbit run backwards).
9. **Jijimon fades in** (0x185–0x1B7) from black, alone in the dark room with the flickering shards. **No egg.** The dialogue (script 212) runs.
10. **Rebirth** (its own frame counter, `DOOA_tickRebirth`, `dooa.c:1020`):
    - 10: sound (8, 5). The shards lift: each spins up, flies out to a random radius and rises to a random height.
    - 100: the shards gather: one by one (a random 0–19 frame wait) they spiral into the centre and up, then vanish (all gone by 131).
    - 101–132: the egg (`TAMA.TMD`, the 6 pieces of the chosen egg) appears at the room's origin **face group by face group**: only its textured faces, no outlines (V-G3).
    - 132: sound (8, 6). 132–152: a big flash at (0, −100, 0) shrinks each frame; until 146, spark streaks shoot out from 100 above the origin.
    - 152: the reincarnation; the tamer and the other people come back and fade in from black with the room's background, over 152–202. The partner (the baby) is hidden.
    - 202: the baby is shown at the origin, animation 0x1C. Then one entry per frame of the sparkle table (47 frames): at 6 of them, one egg piece breaks into falling translucent fragments and is no longer drawn; sound (8, 7).
    - 262: animation 0xB; when it ends, the rebirth is over.

With lives left (a life lost, MURD only): the iris, the lives box, the darkening, the map change. Only §4.10 of this spec applies.

## 2. The stand-ins to remove

In `DeathHost` (`specs/death_reincarnation.md` §9):
- `partner_dissolve.gdshader` pulls the skinned mesh's vertices down in model space, which garbles the models; a line mesh copies the triangles (`_start_dissolve`, `_wireframe`, `_draw_dissolve`, `_end_dissolve`). Replaced by §4.1 and §4.2.
- No camera move: the partner goes to the origin with the field camera unchanged, so it isn't centred. Replaced by §4.4.
- `_spawn_egg`: the egg model shown solid from 0x185. Wrong: the egg only exists in the rebirth (§4.6), and 0x185 is Jijimon's fade (§4.9).
- `DooaScene.squash`: a made-up curve. Replaced by §4.3.
- `DooaScene.egg_fade`: it is Jijimon's palette fade, not an egg. Renamed `jijimon_fade` (§4.9).
- The iris is drawn under the 3D world, so the partner always shows, and it is hard-edged. Replaced by §4.10.

## 3. The values

Every number the step uses. **Status:** `ported` (the code does what the C line does), `port-only` (the C has no such value; the reason is given), `stand-in` (not allowed at the end of this step). C paths are under `external-resources/dw_decomp/src/`. A value marked "already" is in the code today.

### A. The wireframe body (`main/model.c`, US build)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| A1 | `WIREFRAME_RNG_TABLE` | `model.c:2501` | `[6, 3, 11, 8, 10, 13, 1, 4, 14, 7, 12, 15, 5, 2, 9, 0]` | ported |
| A2 | Face `i` drawn textured | `model.c:3177, 3217` (`renderWireframed`, US :3129) | `A1[i & 15] < share`, else its outline | ported |
| A3 | Partner path | `model.c:2911–2919` (`renderDigimon`) | total ≠ 16 → `renderWireframed(obj, total)`; else `SUB[bone]` ≠ 16 → `renderWireframed(obj, SUB[bone])`; else the normal model | ported |
| A4 | `PARTNER_WIREFRAME_TOTAL` start | `model.c:83` | 16 (= the normal model) | ported |
| A5 | Line grey | `model.c:3155–3156` | `MIN + rand() % (MAX − MIN)`, one `rand()` per drawn object per frame | ported |
| A6 | `WIREFRAME_COLOR_MIN / MAX` | `model.c:89, 91`; reset `dooa.c:493–494` | 0x37 / 0xFF | ported |
| A7 | Primitive kinds | `model.c:3174, 3215` | `(mode & 0xFC) == 0x34` triangle, `== 0x3C` quad; **any other mode ends the object's loop** (`model.c:3263`) | ported |
| A8 | Triangle outline | `model.c:3198–3202` | v0 v1 v2 v0 (LINE_F4, x3 = x0) | ported |
| A9 | Quad outline | `model.c:3239–3257` | v0 v1 v3 v2, then v2 → v0 (LINE_F4 + LINE_F2) | ported |
| A10 | Culling | `model.c:3180, 3198, 3220, 3239` | every face and every outline is culled by `RotNclip` (> 0), double-sided faces too | ported |
| A11 | Textured faces' light | `model.c:3163`, `NormalColorCol3` after :3180 | `NormalColorCol3` with colour 0x80: the model's normal lighting | ported |

### B. The dissolve timeline (`dooa/dooa.c`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| B1 | `DOOA_SHARD_WAVE_SCHEDULE` | `dooa.c:263` | `[15,15,15,15,15,14,14,14, 14,13,13,13,12,12,12,11, 11,11,10,10,10,9,9,8, 8,7,7,6,6,5,5,4, 3,2,1,0]` | ported |
| B2 | Schedule frames | `dooa.c:453–460` | from 0x69 to 0x8C: `total = B1[frame − 0x69]`; a wave spawns on 0x69 and when the value changes (16 waves: 0x69, 0x6E, 0x72, 0x75, 0x78, 0x7B, 0x7E, 0x80, 0x82, 0x84, 0x86, 0x88, 0x89, 0x8A, 0x8B, 0x8C) | ported |
| B3 | Total back to 16 | `dooa.c:495` | at 0xD1 | ported |
| B4 | Phase 2 first frame | `dooa.c:435–444` | frame 0x57: partner at the origin, animation 0xC (lives left), `storedY` = the partner's y | ported (port today does it at 0x56: fix) |
| B5 | Anim 0xC's end | `dooa.c:334–339` | animation 1, `storedY` again, saved location and rotation | already |
| B6 | Squash target y | `dooa.c:465` | `storedY − (height + 100)` (the flash's start y, §E) | ported |
| B7 | Map-change animations | `dooa.c:394–400` | lives left: 1; else 0x2C and the playing flag cleared (`animFlag &= 0xFE` = `PsxAnimator.playing = false`) | already (flag: ported) |
| B8 | Partner hidden while larger than the iris | `dooa.c:342–344` | `DOOA_hasIrisClosed(entity, 0, 0x21, frame)` → drawn in the front layer | ported |

### C. The squash (`dooa.c:472–503`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| C1 | `DOOA_DISSOLVE_SCALE_CURVE` | `dooa.c:273` | `[100,94,89,85,82,80,79,79, 100,120,139,157,174,190,205,219, 232,244,255,265,274,282,289,295, 300,350,395,435,470,500,525,545]` | ported |
| C2 | Index | `dooa.c:474` | `lerp(0, 0x1F, 0xBF, 0xD0, frame)` | ported |
| C3 | Scale (4096 = 1) | `dooa.c:475–479` | `work = (C1[i] − 100) × 200 / 100 + 100`; `sy = (work << 12) / 100`; `sx = ((10000 / work) << 12) / 100`, then `sx = lerp(sx, sx × 50 / 100, 0xBF, 0xD0, frame)`; `sz = sx` | ported |
| C4 | Mirror and sink | `dooa.c:480–490` | when `C1[i] ≥ 0x12D`: `work = 0x12C − (C1[i] − 0x12C)`, `sy` from it; the partner's y → B6 (`lerp(y, targetY, f − 1, f, f)` = targetY at once), playing flag cleared | ported |
| C5 | Expected per frame | (from C1–C4) | 0xC0: sy 3604 sx 4492 · 0xC4: 5734 / 2481 · 0xC8: 14909 / 813 · 0xCC: 20070 / 506 · 0xCD: 16384 / 385, sinks · 0xD0: 409 / 204, sinks | (test values) |
| C6 | Gone | `dooa.c:492–503` | 0xD1: animation 0x21, hidden, y back to the saved y, sound (8, 2) | already |
| C7 | Root scale after 0xD1 | none | the C leaves the last scale (the partner is hidden until the baby loads at 152) | port-only: reset to 1 with the new model at 152; the C's reset in the model reload isn't traced |

### D. The cutscene camera (`DOOA_updateCutsceneCamera`, `dooa.c:728–789`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| D1 | Orbit rotation | `dooa.c:210, 760–761` | `MAIN_D_80134BB4` = (0, 0, 0), never written; so `(0, angle + 0x638, 0)` | ported |
| D2 | Orbit distance | `dooa.c:763` | `height × 5 + 1200` | ported |
| D3 | Reference point | `dooa.c:1310–1312` | `(pos.x, pos.y − height / 2, pos.z)` | ported |
| D4 | Eye | `dooa.c:1313–1320` | `RotMatrixZYX(D1) · (0, 0, D2)` + ref, then y `+= −400 − 2 × height` | ported |
| D5 | First half (start .. mid) | `dooa.c:766–776` | ref lerps from the start view's to D3; drawing offset lerps to (160, 120); eye and projection stay the start's | ported |
| D6 | Second half (mid .. end) | `dooa.c:777–786` | eye lerps to D4; ref = D3; offset x 160, y `lerp(120, 120 + lerp(0, 20, 0, 200, height), mid, end, f)`; projection `lerp(start, 1000, mid, end, f)` | ported |
| D7 | `mid` | `dooa.c:744` | `(start + end) / 2`; frames outside [start, end] change nothing | ported |
| D8 | Start view (orbit in) | `dooa.c:1724–1727` (`DOOA_tick`) | the old map's view, drawing offset and projection when the dissolve starts | ported |
| D9 | Calls, phase 1 | `dooa.c:426–429` | 0x23–0x55: `(partner location, its rotation y, 0x23, 0x55, frame)` | ported |
| D10 | Start view (room) | `dooa.c:375–385, 413–416` | at 0x56: the death map's own view; drawing offset (0xBC, 0x78) in ROOM10 (0xCD), (0xA0, 0x78) in ROOM08; its projection | ported |
| D11 | Jump at 0x56 | `dooa.c:423` | after the move to the origin: `(origin, rotation y, 0, 0x64, 0x63)` | ported |
| D12 | Out, phase 3 | `dooa.c:552–553` | `frame' = 0x2C4 − frame`, `(…, 0x149, 0x17B, frame')`: from 0x149 to 0x17B the orbit runs backwards and ends on D10 | ported |
| D13 | Phase 4 | `dooa.c:565–575` | the map's real drawing offset back, the camera target reset, `tickCameraMovement(1)`, the follow on: the map's own view | ported |
| D14 | Height | `DIGIMON_DATA[type].height` | the partner's record (`digimon.height`) | ported |
| D15 | View units | `map.c:4153–4159` | `GS_VIEWPOINT` is world units (the map file stores half; `loadMapSetup` doubles) = `FieldMap`'s eye / target | ported |

### E. The flashes (`EFECreateFlash`, already `BattleFx.create_flash`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| E1 | Rising flash, every frame 0xD2–0x135 | `dooa.c:505–529` | `create_flash(0, pos, −1, 8, 0, 0x14, start, end)`: `pos.y = lerp(B6, 0, 0xD1, 0x135, frame)`, x / z the partner's; start colour each channel `rand() % 100 + 60`; end 0x14 | ported |
| E2 | Its sideways wobble | `dooa.c:521–523`, `efe.c:965` | `setEFEFlashOffset(newest, sin(lerp(0, 0x600, 0xD1, 0x135, frame)) × 10 / 4096, 0)` | ported (new: `BattleFx.set_flash_offset`) |
| E3 | Offset in the render | `efe.c:916–923` | mode ≥ 0: `screen += offset × VIEWPORT_DISTANCE / depth` | ported |
| E4 | Rebirth flash, every frame 133–152 | `dooa.c:1083–1098` | `create_flash(0, (0, −100, 0), −1, 4, 0, level × 25 × 4096 / 1000, start, end)` with `level = lerp(20, 10, 132, 152, f)`; colour `L + rand() % (L × 50 / 120)` per channel with `L = lerp(120, 10, 132, 152, f)`; end `L / 6` | ported |
| E5 | E4's expected | (from E4) | 133: scale 2048, L 115 · 142: 1536, 65 · 152: 1024, 10 | (test values) |

### F. The body's shards (`DOOA_spawnBoneShards` `dooa.c:1559`, `DOOA_updateShards` `:1325`, `DOOA_renderShards` `:1424`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| F1 | Bones | `dooa.c:791–803` | 2 .. boneCount − 1, those with an object | ported |
| F2 | Vertices | `dooa.c:1584–1593` | the object's vertices through the bone's current matrix (`calculateBoneMatrix`: this frame's pose) | ported |
| F3 | Per face `j`, in order | `dooa.c:1611` | `(rand() & 3) != 0` first (**one `rand()` per face, every face**), then `A1[j & 15] == wave` | ported |
| F4 | Kinds | `dooa.c:1612–1614, 1681–1690` | mode 0x34 / 0x36 triangle, 0x3C / 0x3E quad; any other mode: no shard, **and the C doesn't step past it** (every later face of that object reads the same one: no more shards from that object, the `rand()` still rolled per face) | ported |
| F5 | Centre | `dooa.c:1617–1619, 1630–1632` | mean of the face's vertices (triangle /3, quad /4), minus (partner x, storedY, partner z) | ported |
| F6 | Shape | `dooa.c:1620–1628` | `vertex[k]` = vertex − centre (before the subtraction of F5) | ported |
| F7 | Initial | `dooa.c:1633–1642` | fallSpeed 0, radius 0x1000, rot (0, 0, 0), `axisDistance = getDistance(cx, 0, cz)` (0 → 1), delay 0 | ported |
| F8 | Buffer limit | `dooa.c:1608` | stops when full (`DOOA_SHARD_BUFFER_SIZE`) | port-only: no limit (no model reaches it; the user's check §6) |
| F9 | Effect colour | `dooa.c:653–655` | R = G = B = 0x50 | ported |
| F10 | State 0 (fall) | `dooa.c:1343–1352` | `fallSpeed = min(fallSpeed + 1, 0x400)`; `cy = min(cy + fallSpeed, 0)` | ported |
| F11 | State 1 entry | `dooa.c:1355–1364` | spin 0; `spinMax = rand() % 0x155 + 0xE3`; radius 0x1000; `targetRadius = 0x64000/ad + rand() % (0x190000/ad − 0x64000/ad)`; fallSpeed 0; `dropDepth = rand() % 0x226` (rolls in that order, per shard) | ported |
| F12 | State 1 frame | `dooa.c:1365–1384` | `spin += 1` if `spinMax / 80 == 0` else `spin += spinMax / 100`, capped at spinMax; `rotY += spin`; if `radius < target`: `radius += 1` if `target / 80 == 0` else `+= target / 100` (no cap); `fallSpeed += 1`; `cy = max(cy − (fallSpeed >> 3), −dropDepth)` | ported (the /80 vs /100 quirk kept) |
| F13 | State 2 | `dooa.c:1386–1388` | `rotY += spin` (DOOA never sets it) | ported |
| F14 | State 3 entry | `dooa.c:1391–1394` | `delay = rand() % 20`; `targetRadius = radius` | ported |
| F15 | State 3 frame | `dooa.c:1395–1407` | delay > 0: −1; else `radius −= target / 10 + 1`, below 0: radius 0, delay −1 (gone); `cy = lerp(−dropDepth, storedY − 100, target, 0, radius)`; then `rotY = (rotY + spin) % 4096` | ported |
| F16 | Flicker colour | `dooa.c:1334–1339` | while `flash`: R, G, B each `rand() % 100 + 60`, every frame (in the update, before the shards) | ported |
| F17 | Flicker on | `dooa.c:527` | at 0x135 (`DOOA_toggleShardFlicker`) | ported |
| F18 | Shard states | `dooa.c:1044, 1060` | rebirth 10 → state 1, 100 → state 3; removed at 132 | ported |
| F19 | Position | `dooa.c:1476–1496` | `offset = (cx × radius / 4096, cy, cz × radius / 4096)`; each vertex `RotMatrixZYX(rot) · (offset + vertex[k])` + (partner x, storedY, partner z) | ported |
| F20 | Look, normal | `dooa.c:1466–1470` | flat (`POLY_FT3/4`), unlit, the face's texture and UVs, colour **(R, B, G)** (G / B swapped) / 128 | ported |
| F21 | Look, flickering | `dooa.c:1460–1465` | colour (R, G, B) / 128, texture SPOT256 at UV (0, 128)–(3, 131) = white texels: a flat colour | ported |
| F22 | Drawn | `dooa.c:1458` | shards with `delay ≥ 0` | ported |

### G. The egg (`DOOA_renderRebirth` `dooa.c:1169`, `DOO2_renderWireframeModel` `doo2/doo2.c:410`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| G1 | Model | `dooa.c:285–286, 530–551` | `ETCDAT/TAMA.TMD` + `TAMA.TIM` (loaded at 0x17B): 24 objects, egg `e` = objects `e × 6 + i` | ported |
| G2 | Threshold `MAIN_D_80135324` | `dooa.c:1062–1066`; reset `:1771–1775` | 0 at the rebirth's start (with the piece flags); phase 0xCD is entered on frame 100 and computes from 101: `lerp(1, 16, 100, 132, f)` for 101–129, 16 from 130 | ported |
| G3 | **No outlines** | `doo2.c:486–495, 531–543` | the outline primitives are built but never `AddPrim`ed: only faces with `A1[i & 15] < threshold` are drawn | ported |
| G4 | Primitive kinds | `doo2.c:457, 499` | mode exactly 0x34 / 0x3C; another mode ends the loop | ported |
| G5 | Placement | `dooa.c:1183–1186` | identity coordinates: the TMD's vertices are world positions (PSX y −193 .. 0: on the floor at the origin) | ported |
| G6 | Light | `doo2.c:443` | `NormalColorCol3`, colour 0x80, the scene's lights | ported |
| G7 | Palette | `TAMA.json` per face `cba` | egg 0: CLUT (128, 488), 1: (128, 489), 2: (128, 490), 3: (128, 491): each egg its own row (in the glTF already) | ported |
| G8 | Pieces drawn | `dooa.c:1181–1182` | piece `i` while `MAIN_D_80135364[i] == 0` | ported |
| G9 | Line grey `rand()` | `doo2.c:433` | one `rand()` per drawn piece per frame (rolled, unused) | ported |
| G10 | `DOOA_SPARKLE_BONE_IDS` | `dooa.c:291` | 48 entries, 47 read: `[-1,-1,-1,-1, 0,-1,-1,-1, -1,-1,-1,-1, -1,-1, 1,-1, -1,-1,-1,-1, -1,-1,-1,-1, 2,-1,-1,-1, -1,-1,-1,-1, -1,-1, 3,-1, -1,-1,-1,-1, -1,-1,-1,-1, 4, 5,-1, 0]`: pieces at entries 4, 14, 24, 34, 44, 45 | already |
| G11 | Expected thresholds | (from G2) | 99: 0 · 100: 0 · 101: 1 · 103: 2 · 115: 8 · 116: 8 · 129: 14 · 130: 16 | (test values) |

### H. The egg's pieces (`DOO2_buildShardSet` `doo2.c:597`, `DOO2_renderTriShard / QuadShard` `:228 / :272`, `DOO2_tickShardSet` `:208`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| H1 | Slots | `doo2.c:629–636` | 6 sets; none free → nothing | ported |
| H2 | Vertices | `doo2.c:641–647` | the object's vertices + offset (0) | ported |
| H3 | "Centre" | `doo2.c:662–700` | the mean of the face's first **three vertex normals** (`worldVertices` is the TMD's `normal_top`, indexed by n0..n2; quads also /3 of three): a 4096-length direction | ported |
| H4 | Per frame | `doo2.c:251–259, 301–309` | `frame += 1`; `offsetY += frame + cy / 240`; if `offsetY + (va.y + vb.y + vc.**z**) / 3 > 0` (quads: `(pa.y + pb.y + pc.**z** + pd.y) / 4`): `offsetY = −that mean`, else `offsetX += cx / 240`, `offsetZ += cz / 240` | ported (the C's `.vz` typo kept) |
| H5 | Look | `doo2.c:189–191, 242, 291` | flat, semi-transparent with the face's tpage blend: TAMA's tsb 25 = **abr 0 (half / half)**; grey `(41 − timer) × 74 / 40 + 54` / 128 | ported |
| H6 | Expected grey | (from H5) | timer 0: 129 · 1: 128 · 20: 92 · 40: 55 | (test values) |
| H7 | Life | `doo2.c:208–216` | removed when the timer reaches 41 | ported |
| H8 | Kinds | `doo2.c:194, 199` | 0x34 triangle, 0x3C quad | ported |

### I. The spark streaks (`DOOA_renderRebirth` `dooa.c:1194–1206`, `DOO2_renderSparkStreak` `doo2.c:555`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| I1 | Count per frame | `dooa.c:1079–1081` | `fadeLevel = lerp(5, 0, 132, 150, f)` for rebirth 133–146, else 0 | ported |
| I2 | Expected | (from I1) | 133–135: 5 · 136–139: 4 · 140–142: 3 · 143–146: 2 · 147: 0 | (test values) |
| I3 | Per streak, in order | `dooa.c:1198–1200`, `doo2.c:566–583` | `range = custom_random(−170, 1024)`; `rot.x = rand() % range`; `rot.y = rand()`; `a = RotMatrixZYX(rot) · (0, 0, custom_random(400, 500))` + origin; `b = a + (custom_random(−50, 50) ×3)`; grey `rand() % 128 + 10` | ported |
| I4 | `rand() % 0` | `dooa.c:1199` | `range` can be 0: the R3000 leaves the dividend, so `rand() % 0 = rand()` | port-only (the C's result is the hardware's) |
| I5 | Origin | `dooa.c:1201–1204` | the partner's location, y − 100 | ported |
| I6 | Look | `doo2.c:577–583` | triangle (b, origin, a), additive (abr 1), DEFEFF on tpage (768, 256), CLUT (192, 489) = palette 1, UV (0x5F, 0xA0) (0x5F, 0xA7) (0x30, 0xA0) (image v = v − 0x80) | ported |

### J. The palette fades

| # | What | C source | Value | Status |
|---|---|---|---|---|
| J1 | Map background black | `dooa.c:405–406` | 0x23: `fadeoutCLUT1(0xFF)` = `DooaScene.darkness` 0xFF | already |
| J2 | Jijimon (entity 2) | `dooa.c:556–560`, `doo2.c:372` | 0x185–0x1B7: shown; his palette tile (32, 488) × `(0xFF − work) / 0xFF`, `work = lerp(0xFF, 0, 0x185, 0x1B7, f)` | ported |
| J3 | J2 expected | (from J2) | `work` 0x185: 255 · 0x19E: 128 · 0x1B7: 0 | (test values) |
| J4 | Others back at 152 | `dooa.c:1108–1114` | shown again; the tamer's tile (0, 488) and entities 3 / 4's tiles (48, 488, 32 wide) set to black | ported |
| J5 | Fade 152–201 | `dooa.c:1132–1138` | `level = lerp(255, 0, 152, 202, f)`: the background every frame; on even frames the tamer's palette, on odd frames entities 3 and 4's, × `(255 − level) / 255` | ported |
| J6 | J5 expected | (from J5) | level 152: 255 · 153: 250 · 177: 128 · 201: 6 | (test values) |
| J7 | End | `dooa.c:1122–1126` | 202: everything at full colour | ported |
| J8 | Not faded | | the partner's palette (16, 488) | ported |
| J9 | STP on faded colours | `dooa.c:1249, 1287` | the C sets the STP bit so black texels stay opaque | port-only: a tint multiply keeps them opaque already |
| J10 | Tile ↔ entity | `asset_porter/specs/alltim.md` "slots" | (0, 488) tamer, (16) partner, (32 + 16 k) NPC k = entity 2 + k | ported |

### K. MURD and the iris (`murd/murd.c`, `dooa.c:579–636, 863`)

| # | What | C source | Value | Status |
|---|---|---|---|---|
| K1 | Iris radius | `murd.c:374, 578`, `dooa.c:620` | `(lerp(200, 0, start, end, t) << 12) / 128`; DOOA clamps `t` to `end` (`dooa.c:614`) | ported |
| K2 | K1 expected (MURD, 0..0x23) | (from K1) | t 1: 6240 · 10: 4576 · 34: 192 · 35: 0 | (test values) |
| K3 | Partner in front | `murd.c:359–391`, `dooa.c:602–636` | `size = getDistance(2r, h, 2r)` of the record; `z` the depth of (x, y − h/2, z); `z ≤ 0` → in front; else in front when `radius ≤ ((size × H / z) << 12) / 256` | ported |
| K4 | Iris window | `murd.c:596–607` (`MURD_renderIris`) | `renderParticleFlash`: SPOT256 u 0 quarter (v base 0x80), CLUT (0, 487), **subtractive** (abr 2), colour 0x80, scale = radius, at the partner's screen point | ported |
| K5 | Black around it | `murd.c:608–688` | 4 subtractive rects of SPOT256's white texels (UV (0, 0x80) 3 × 3), colour 0x80, overlapping the window by `lerp(4, 1, 0x1860, 0, radius)` px | ported |
| K6 | Shown | `murd.c` phase 0 / `dooa.c:586` | MURD 0..0x23; DOOA frames < 36 | already (timing) |
| K7 | MURD lights | `murd.c:208–228` | dir (0x1E, 0x64, 0x1E) grey 0x40; (−0x1E, 0x64, 0) 0x28; (0, 0x64, −0x1E) 0x26 — from phase 1 (0x23) | ported |
| K8 | Lights back | `murd.c` map change | the death map's own lights (its `loadMapSetup`) | ported |

## 4. Behaviour

### 4.1 The wireframe body (§A)

Per bone object, per frame, with `share` = the total, or `SUB[bone]` when the total is 16 (the evolution, 5f-2): faces in the object's primitive order; face `i` is textured when `A1[i & 15] < share`, else its outline in the object's grey (A5). The loop stops at the first primitive of another kind (A7): no face after it is drawn. Every face and every outline is back-face culled (A10). The grey is rolled **once per drawn object per frame**, in bone order, only while the object is in wireframe mode.

### 4.2 The body's shards (§F)

Spawned at each wave (B2) from the current pose (F1–F7); updated every frame by the effect's state (F10–F16); drawn after the model (F19–F22). The shards stay on the floor through the dialogue, flickering from 0x135, until the rebirth lifts them.

### 4.3 The squash (§C)

From 0xC0 to 0xD0, the partner's scale is set from the curve each frame; from the first index whose curve value is ≥ 0x12D (index 25, frame 0xCD), the y scale mirrors back and the partner moves down to B6 at once.

### 4.4 The cutscene camera (§D)

`view(start, position, angle, height, s, e, f)` gives the eye, the reference point, the drawing offset and the projection for frame `f`, exactly as D2–D7. `FieldMap` applies it (it already builds its camera from an eye and a target, `asset_porter/dwporter/formats/map.py:165`): eye / target through the same basis maths, the projection, and the drawing offset as the projection centre (`FieldMap._apply_scroll`). The field's camera follow stays off until D13.

### 4.5 The flashes (§E)

`BattleFx` (logic, already the C's `EFECreateFlash` / `tickEFEFlash`) gains `set_flash_offset(id, x, y)` (E2). `BattleFxView` draws the flashes with the offset (E3). A new flash each frame, each living 8 (rising) or 4 (rebirth) frames.

### 4.6 The egg (§G)

The 6 pieces of `egg_slot`, at the origin, only their textured faces whose group is under the threshold (no outlines, G3). The piece flags (G8) hide a piece once it has broken.

### 4.7 The egg's pieces (§H)

At a sparkle entry ≥ 0, that piece becomes a set of falling translucent fragments for 41 frames.

### 4.8 The spark streaks (§I)

`fadeLevel` streaks a frame from 100 above the origin, each a thin additive triangle with random direction and length.

### 4.9 The palette fades (§J)

A palette fade is a tint (colour multiply) on that entity's model materials (`PsxLit`'s `tint` uniform), from 0 (black) to 1. Jijimon (entity 2) fades in over 0x185–0x1B7; the tamer and entities 3 / 4 over 152–202 on alternating frames (J5); the partner never.

### 4.10 MURD and the iris (§K)

The iris is the subtractive window and four rectangles (K4, K5), drawn over the world. The partner is drawn over the iris once K3 says it's larger (B8). MURD's three lights replace the map's from phase 1 until the map change brings the death map's.

### 4.11 Logic gaps in `DooaScene` / `MurdScene` today

Each is fixed in the step that needs it (§6):
- Phase 2's first frame is 0x57 (B4): the port does the move's follow-up at 0x56.
- Missing: B6 (flash target), B3 + A6 reset at 0xD1, F17 at 0x135, the camera calls D9–D13, G1 at 0x17B, F18, G2, H, I1, J4–J7, B8 / K3, K7.
- `egg_fade` → `jijimon_fade` (§2).
- `squash` (Vector2) → `scale` (Vector3i, 4096 = 1, C3).

## 5. Godot design (decided)

Logic in plain classes (headless-testable, `specs/scenes.md` §3); views are scenes that `DeathHost` instantiates (rule 7: a mod can replace them). `DeathHost._process` hands the views the logic's state; nothing in a view changes the logic. All RNG through `Rng.rand()` / `Rng.custom_random()`.

| Part | Files | Kind | API (what the tests call) |
|---|---|---|---|
| `DooaScene` (extended) | `scripts/field/death/dooa_scene.gd` | logic | new members: `wireframe_total`, `wire_color_min`, `wire_color_max`; `scale: Vector3i` (4096 = 1, replaces `squash`); `stored_y`, `flash_target_y`; `jijimon_fade` (a level: 255 black … 0 full, replaces `egg_fade`); `egg_threshold`; `piece_flags` (6 ints, 0 drawn / −1 broken); `fade_level`; `tamer_fade`, `others_fade` (levels, J5); `fx: BattleFx` (it owns and ticks the flashes), `last_flash` (FLASH_INSTANCE, −1 none); `shards: DooaShards`; `pieces: EggPieceShards`. Signal `wave_spawned(wave: int)` (B2: `DeathHost` answers it in the same call with the posed bones, `shards.spawn_wave`). Callables `get_view`, `set_view`, `restore_view` (the `FieldMap` hook, D8–D13; `set_view` only with a non-empty view). |
| `TmdFaceGroups` | `scripts/content/tmd_face_groups.gd` | logic + mesh building | `static func shown(share: int) -> PackedInt32Array` (the groups with `A1[g] < share`, ascending); `static func build(object: Dictionary, materials: Array[Material], outlines: bool) -> Dictionary` from a sidecar object (`tmd.objects[i]`) and one material per face: `{"faces": ArrayMesh, "groups": PackedInt32Array, "lines": ArrayMesh, "line_groups": PackedInt32Array, "end": int}`. One surface per (group, material) that has faces (`groups[s]` = surface `s`'s group); outlines as `PRIMITIVE_LINES` pairs (A8: 6 vertices, A9: 8); `end` = the face index where A7 stops. Vertices through `Content.psx_to_godot`. |
| `PartnerWireframe` | `scenes/field/partner_wireframe.tscn`, `scripts/field/partner_wireframe.gd` | view (shared with 5f-2, so not under `death/`) | `static func face_materials(model: Node3D, sidecar: Dictionary, gltf: Dictionary) -> Array` (per object index, one `Material` per face: the surface whose glTF primitive lists the face's `offset`, made single-sided); `attach(model, sidecar, gltf)`; `share` (the last total set); `set_share(total: int, sub := PackedInt32Array())`; `roll_greys(min: int, max: int)` (A5); `detach()` |
| `DooaShards` | `scripts/field/death/dooa_shards.gd` | logic | `state`, `flash: bool`, `color: Vector3i` (R, G, B), `location: Vector3i`, `stored_y`; `shards: Array[Dictionary]`, each `{"bone", "face", "kind" ("tri" / "quad"), "center": Vector3i, "vertex": Array[Vector3i], "fall_speed", "radius", "rot": Vector3i, "axis_distance", "delay", "spin", "spin_max", "target_radius", "drop_depth"}`; `spawn_wave(wave: int, bones: Array)` (each `{"bone": int, "object": Dictionary, "vertices": Array[Vector3i]}`: the object's vertices posed, PSX world units); `tick()`; `vertices(shard) -> Array[Vector3i]` (F19) |
| `DeathShards` | `scenes/field/death/death_shards.tscn`, `scripts/field/death/death_shards.gd` | view | `draw(shards: DooaShards)`: one `ArrayMesh` rebuilt per frame, a surface per texture page / palette, `PsxLit` unlit material, `tint` = F20 / F21 |
| `CutsceneCamera` | `scripts/field/death/cutscene_camera.gd` | logic | `static func orbit(position: Vector3i, angle: int, height: int) -> Array` (`[ref, eye]`, D1–D4); `static func view(start: Dictionary, position: Vector3i, angle: int, height: int, s: int, e: int, f: int) -> Dictionary` (`start` and the result `{"eye": Vector3i, "ref": Vector3i, "offset": Vector2i, "projection": int}`; `{}` outside [s, e]) |
| `FieldMap` camera hook | `scripts/field/field_map.gd` (new functions only) | — | `view() -> Dictionary` (the current eye, ref, offset, projection, PSX); `set_view(v: Dictionary)`; `restore_map_view()`; `world_to_screen(psx: Vector3i) -> Dictionary` (`{"screen": Vector2i, "sz": int}`, as `BattleEffectContext.world_to_screen`) |
| Flashes | `scripts/systems/battle/battle_fx.gd` (`set_flash_offset(id, x, y)`, flash fields `offset_x`, `offset_y`), `scripts/systems/battle/battle_fx_view.gd` (two optional overrides: `fx: BattleFx`, `projector: Object` with `world_to_screen` / `viewport_distance`; unset = today's battle path, unchanged) | logic + view | `DooaScene.fx` is the logic; `DeathHost` draws it with a `battle_fx_view.tscn` whose overrides are `dooa.fx` and the `FieldMap` |
| `RebirthEgg` | `scenes/field/death/rebirth_egg.tscn`, `scripts/field/death/rebirth_egg.gd` | view | `load_egg(slot: int)`; `set_threshold(t: int)`; `set_piece_shown(i: int, shown: bool)`; `shown_faces() -> int` (the faces drawn now); `roll_greys()` (G9); its child `Pieces` draws `dooa.pieces` |
| `EggPieceShards` | `scripts/field/death/egg_piece_shards.gd` | logic | `sets: Array[Dictionary]` (6), each `{"timer" (−1 free), "object", "faces": [{"centre": Vector3i, "offset": Vector3i, "frame": int}]}`; `build(object: Dictionary) -> int` (slot or −1); `tick()` (timer + 1 and the removal at 41, then H4's step); `grey(set) -> int` (H5) |
| `SparkStreaks` | `scripts/field/death/spark_streaks.gd` (logic), `scenes/field/death/spark_streaks.tscn` (view under `DeathHost`) | logic + view | `static func roll(count: int, origin: Vector3i) -> Array`, one `{"a": Vector3i, "b": Vector3i, "origin": Vector3i, "grey": int}` per streak (I3–I5) |
| `PaletteFade` | `scripts/field/death/palette_fade.gd` | logic | `static func factor(level: int) -> float` (`(255 − level) / 255`); `static func apply(entity: Node3D, factor: float)` sets `PsxLit`'s `tint` on every pass of the entity's materials (copies, like `PsxLit.use_own_light`); `static func clear(entity: Node3D)` |
| `DeathIrisMath` | `scripts/field/death/death_iris_math.gd` | logic | `static func radius(start: int, end: int, t: int, clamp_end: bool) -> int` (K1); `static func in_front(radius: int, size: int, h: int, z: int) -> bool` (K3) |
| Iris view | `scenes/field/death/death_iris.tscn`, `scripts/ui/death_iris.gd` (rewritten) | view | `show_iris(centre: Vector2, radius: int)`, `hide_iris()`: a `CanvasItem` in the HUD drawing K4 (SPOT256's quarter, mirrored, `PsxUiFilter.material("sub")`) and K5 |
| Partner over the iris | `scripts/field/hosts/death_host.gd` | view wiring | while B8 / K3 say so: the partner's meshes on render layer 20; a second `Camera3D` (a copy of the field camera every frame, cull mask layer 20) renders into a transparent `SubViewport` the size of the world viewport, shown in a `CanvasLayer` over the iris |
| `DeathHost` | `scripts/field/hosts/death_host.gd`, `scenes/field/hosts/death_host.tscn` | view host | exposes `wireframe: PartnerWireframe` and `egg: RebirthEgg` (the scan reads them) |
| Outline culling | in `PartnerWireframe._process` | — | as built: no line shader. The outlines are an `ImmediateMesh` per bone object rebuilt each frame, with the faces that face the camera only (`PartnerWireframe.front_facing`: the first three vertices in the PSX order, Godot's clockwise front face; a quad's v2 is its outline's fourth point) |

Data sources: the model's sidecar (`<model>.json`: `tmd.objects[i].primitives` in TMD order with `mode`, `vertices`, `normals`, `uvs`, `tsb`, `cba`, `offset`; `skeleton` bone → `objIndex`) and its glTF JSON (each mesh primitive's `extras` lists the file offsets of its PSX packets, `asset_porter/specs/tmd.md:78`). A face's material is the material of the Godot surface whose primitive lists the face's `offset` (surface `k` = glTF primitive `k`), made single-sided (A10). The imported model has `Skeleton3D` / `BoneAttachment3D` `bone_<i>` / `MeshInstance3D` `bone_<i>` with bone-local vertices: the wireframe meshes are siblings under the same attachment. Shard vertices (F2): `Content.psx_to_godot` inverse of the attachment's global transform × the bone-local vertex, rounded to ints.

**Order in the frame:** the logic ticks in `DooaScene.tick` (the object list, as today); the render-time rolls (A5, G9, I3) happen in `DeathHost.tick_objects()` right after it, in the order wireframe greys, egg greys, streaks. The C's exact order between entity rendering and object rendering isn't traced: **port-only**. The tests check how many draws each part makes, not the global order.

## 6. Order of work

Each step: its complexity and model (`docs/agent_workflow.md` "Complexity and model"), its files (owned; no other file changes), the tests that must pass, and the user's in-game check. A step that mixes logic and rendering is rated per half. All suites and both scans pass after every step.

| Step | Complexity · model |
|---|---|
| 1. Face groups, wireframe body | **Hard** · Claude Opus 5.5 (Medium): meshes from the sidecar on animated bones, the line shader's culling |
| 2. Body shards | logic (`DooaShards`) **Low** · Gemini 3.8 Flash (High); view (`DeathShards`, posed vertices from the bones) **Hard** · Claude Opus 5.5 (Medium) |
| 3. Squash | **Low** · Gemini 3.8 Flash (High) |
| 4. Camera | logic (`CutsceneCamera`) **Low** · Gemini 3.8 Flash (High); `FieldMap` hook **Hard** · Claude Opus 5.5 (Medium): the camera basis and frustum, checked on screen |
| 5. Flashes | **Medium** · Claude Sonnet 5.5 (Medium): the battle's `BattleFx` / `BattleFxView` changed without changing the battle |
| 6. Egg, pieces, streaks | logic (`EggPieceShards`, `SparkStreaks`, G2 / G8 / I1) **Low** · Gemini 3.8 Flash (High); views (`RebirthEgg` meshes, streak triangles) **Hard** · Claude Opus 5.5 (Medium) |
| 7. Palette fades | **Low** · Gemini 3.8 Flash (High) for `PaletteFade.factor` and the levels; applying the tint to the materials is **Medium** · Claude Sonnet 5.5 (Medium) |
| 8. MURD / iris | **Hard** · Claude Opus 5.5 (Medium): the subtractive iris and the partner drawn over it |
| 9. Clean up | **Low** · Gemini 3.8 Flash (High) |

The spec, the tests and the review of every step: Claude Opus 5.5 (the main session).

1. **Face groups and the wireframe body.** Files: `tmd_face_groups.gd`, `partner_wireframe.tscn/.gd`, `shaders/wireframe_line.gdshader`, `DooaScene` (`wireframe_total`, B2, B3, A6), `DeathHost` (attach / share / greys; remove `_wireframe`). Tests: `test_death_scene.gd` "face groups", "wireframe schedule". Check: the body turns to outlines group by group over 0x69–0x8C and stays in outlines until it vanishes; lines on the far side are hidden.
2. **The body's shards.** Files: `dooa_shards.gd`, `death_shards.tscn/.gd`, `DooaScene` (spawn, F17, F18), `DeathHost` (remove `partner_dissolve.gdshader` and `_start_dissolve`, `_draw_dissolve`, `_end_dissolve`). Tests: "shards". Check: textured pieces fall off at each step and lie on the floor; from 0x135 they flicker in colours.
3. **The squash.** Files: `DooaScene` (`scale`, C), `DeathHost` (apply the scale). Tests: "squash". Check: the outline body squashes, shoots up thin, then sinks.
4. **The camera.** Files: `cutscene_camera.gd`, `field_map.gd` (new functions only), `DooaScene` (D8–D13, B4), `DeathHost`. Tests: "camera", `death_scan` "centred". Check: the camera swings in to the partner, which stands centred in the room; at the end it swings back to the room's view.
5. **The flashes.** Files: `battle_fx.gd`, `battle_fx_view.gd` (the two overrides only), `DooaScene` (E1, E2, E4), `DeathHost`. Tests: "flashes"; the battle suites unchanged. Check: a flash rises from the floor and wobbles after the body vanishes; a big flash shrinks at the rebirth.
6. **The egg, its pieces, the streaks.** Files: `rebirth_egg.tscn/.gd`, `egg_piece_shards.gd`, `spark_streaks.gd/.tscn`, `DooaScene` (G2, G8, I1), `DeathHost` (remove `_spawn_egg`). Tests: "egg", "pieces", "streaks", `death_scan` "no egg before the rebirth". Check: no egg during the dialogue; the egg appears in pieces after the shards gather; sparks; the egg breaks into falling translucent pieces after the baby appears.
7. **The palette fades.** Files: `palette_fade.gd`, `DooaScene` (`jijimon_fade`, J4–J7), `DeathHost`. Tests: "fades". Check: Jijimon fades in from black; at the rebirth the tamer and the room fade in, the baby is bright.
8. **MURD / iris.** Files: `death_iris.tscn`, `scripts/ui/death_iris.gd`, `MurdScene` (K7), `DooaScene` (B8), `DeathHost` (the partner layer). Tests: "iris". Check: the iris closes with a soft edge; the partner shows on the black only once it fills the window; on the black screen it is lit from the front-left.
9. **Clean up.** Files: `specs/death_reincarnation.md` §9, `VERIFY.md` (the checks above), `ISSUES.md` I-38, `PLANS.md`. `tests/test_rules.gd` "6-2 stand-ins gone" passes.

## 7. Tests

Gated by `DW_STEP_6_2=1` until step 9; plain checks since. The expected values are the C's (§3), worked out by the reviewer from the C, not with the port's code.

`tests/test_death_scene.gd` (headless; Agumon's real model data when the porter output is there):
- **face groups:** `TmdFaceGroups.shown` for 0, 1, 8, 15, 16; a fake object of 20 faces: vertex counts per group (triangle 3 / quad 6; outlines 6 / 8), materials kept per surface, the quad's outline order (A9), A7's stop at a 0x2C face; Agumon: every bone object's face finds its material (`PartnerWireframe.face_materials`).
- **shards:** a fake 2-bone model: one `rand()` per face (36 for 18 + 18, F3), the faces that break (replayed), bone 3 stuck after its 0x2C face (F4); F7's initial values; F5 / F6 / F19 (a fresh shard draws exactly its face); F10's fall and cap; F11's three rolls per shard and their values; F12's first step and the /80 vs /100 quirk; F15 (all gone within 31 frames, at storedY − 100, rotY mod 4096); F16's range.
- **camera:** `CutsceneCamera.orbit` (D1–D4); `view` outside the range, at 0x30 (D5, ref y −65), at the end (D6, with the `lerp(0, 20, 0, 200, 250) = 4` wrap), D12's return to the start view.
- **flash offset:** `BattleFx.set_flash_offset` (E2).
- **pieces:** H3's normals mean, H4 on a hand-made triangle (frame 1: (0, 12, 5); frame 2: (0, 23, 5) through the `.vz` term), H5's grey, H7's removal, H1's six slots.
- **streaks:** `SparkStreaks.roll`: 3 `rand()` and 5 `custom_random()` per streak (I3), the grey range.
- **fades:** `PaletteFade.factor`.
- **iris:** `DeathIrisMath.radius` (K2, DOOA's clamp), `in_front` (K3).
- **dissolve timeline** (`DooaScene` with fakes and the camera callables): `wireframe_total` every frame 1–0xD1 (B2, B3); the 16 `wave_spawned` (B2); A6's reset; C5's scales; B6; the camera calls (D9–D13; the 0x56 view = `view(the room's view with its fixed offset, origin, …, 0, 0x64, 0x63)`); E1's y; F17; J2 / J3.
- **rebirth timeline:** F18 (state 1 at 10, 3 at 100); G2 / G11; I1 / I2; E4 / E5; J4–J7 (the even / odd alternation); G8 / G10 (pieces at 207, 217, 227, 237, 247, 248).
- Not unit-tested (the user's check): A5 / G9's grey rolls, I4 (`rand() % 0`), the views' drawing.

`tests/death_scan.gd`, in the two cases that run DOOA (the last life lost to sickness, the natural death):
- **centred:** at 0x63 the partner's centre (y + h/2) projects to (160, `lerp(120, 120 + lerp(0, 20, 0, 200, h), 50, 100, 99)`) ± 1.5 px. Today: (127, 44) for (160, 123), the bug in the video.
- **outlines:** at 0x8D, `death_host.wireframe.share == 0`.
- **shards on the floor:** at 0x135, shards exist and every `center.y` is 0.
- **no egg:** from 0x185 to rebirth frame 99 no egg face shown (`death_host.egg.shown_faces()`), and never the old stand-in egg. Today: the stand-in shows in the dialogue.
- **the baby at the origin:** from rebirth 202, shown at (0, 0, 0).
- **nothing left:** at the end, the wireframe at 16, the egg hidden, no shards, the partner's scale 1.

`tests/test_rules.gd` "6-2 stand-ins": no `partner_dissolve.gdshader`, `_spawn_egg`, `_start_dissolve`, `_draw_dissolve`, `_end_dissolve` in `scripts/`.

## As built (2026-10-31)

- **All nine steps** in one pass (branch `feat/6-2-death-scene`), by the main session. `tests/test_death_scene.gd` 90 checks; `tests/death_scan.tscn` 3 / 3 with every 6-2 check (also run with the real renderer); every suite and `tests/exit_scan.tscn` unchanged.
- **Deviations from §5:** the outlines are culled on the CPU (the table's "Outline culling" row) instead of a line shader; `DooaScene` owns the flashes' `BattleFx` and the shards' and pieces' logic (it ticks them after itself), `DeathHost` only draws them; `TmdFaceGroups.build` also returns the raw arrays (a headless renderer keeps no mesh data); the iris's background darkening is its own `BackgroundDark` (the background layer), the iris window and the partner overlay are canvas layers 1 and 2 of the world viewport.
- **Fixes to the tests while building** (the reviewer's own bugs, not the values): the Agumon check read the bone objects from the glTF's node extras (the sidecar's skeleton is `[object, parent]` pairs, not `objIndex`), and nulls there; the vertex counts and the outline order read `build()`'s arrays; the streak check read the custom RNG before the replay reseeded it; the 0x56 view's expected offset follows the death map.
- **Not checked by tests** (the user's in-game check, `VERIFY.md`): the look of each part, the outline culling's side, A5 / G9 / I4.
- **After the user's first check** (2026-10-31, `issues/evidence/dw_death_process.mp4`): (1) the iris was a square: SPOT256's colours all have the STP bit (0xFFFF), so its texels are `PsxTexture.stp`, not `base`; (2) the partner's drop shadow turned into a dark disc over the black: it went to the overlay layer, where nothing is behind it to subtract from; it stays in the main pass now (subtracting from black leaves black, as in the C); (3) the floor shards turned grey after 0xD1: their textures came from the wireframe, detached then; `DeathShards` keeps each shard's texture; (4) the room jumped up-left at 0x1B7: phase 4 restored the map's load scroll, the C pans to centre (0, 0, 0) in the same frame (`tickCameraMovement(1)`, D13); measured, Jijimon now stays on the same pixel across the hand-back.
- **Seen, not from 6-2:** a rendered run prints `ERROR: Parameter "material" is null` 8 times at the field's start (engine side, no script line); `spec/6-2-handoff` without 6-2 prints the same 8.

## 8. Questions answered (2026-10-31)

- `MAIN_D_80134BB4`: (0, 0, 0), only read (`dooa.c:210`, `asm/us/main/data/dooa/dooa.sdata.s`). D1.
- The egg's palette: each egg's own row of `TAMA.TIM`, from its faces' `cba` (G7). The DOO2 `saveClutTile` at 0x17B is for the egg panel.
- The faded palette tiles: (0, 488) the tamer, (32, 488) Jijimon, (48, 488) × 32 entities 3 and 4; the partner's (16, 488) is never faded (J). `DOOA_fadeShardClut` is misnamed: the shards are gone by then.
- The shard buffer limit: F8 (port-only).
- Line culling: the C culls outlines like faces (A10); decided in §5 (the line shader).
- New answers found while sourcing: the US `renderWireframed` (`:3129`); the egg's outlines are never drawn (G3); the pieces' blend is half / half (H5), not additive; the pieces' "centre" is the normals' mean (H3) and the floor test's `.vz` typo (H4); the flicker texture is white (F21); the start view is the old map's (D8).

Still open, not blocking: the global RNG order between entity and object rendering (§5, port-only); C7's scale reset.
