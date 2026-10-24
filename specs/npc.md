# NPCs (port spec)

Status (2026-10-23): step 3 of `specs/script.md` §3.1 done, option A (decided 2026-10-23): the map Digimon appear, can be talked to, and are moved and animated by scripts; between talks they stand. Code: `scripts/field/field_digimon.gd` (shared with the partner), `npc.gd`, `field_entities.gd`, the interpreter's entity opcodes, `field.gd`; test `tests/test_npc.gd` (38 checks). Their own behaviour (waypoint wandering, looking at / tracking the tamer) is step 3b (§3.4), filled into the same frame function.

The map Digimon ("NPCs") of the original: up to 8 per map, placed by the map setup scripts from the map's entity list, ticked once per game frame, talked to by touching them (✕ or on contact), and moved by script instructions. Wild enemies are NPCs too: their talk section starts the battle.

All `file:line` references are in `external-resources/dw_decomp/src/main/`; the US version unless noted.

## 1. C functions reproduced

| C | file | port |
|---|---|---|
| `loadMapDigimon` | `overworld.c:1026` | the map's `digimon` list (asset porter) → the 8 slots |
| `clearMapDigimon`, `removeMapEntities`, `clearMapAITable` | `overworld.c:1156`, `:1181`, `:1207` | map change |
| `scriptLoadModel`, `scriptUnloadModel`, `initializeLoadedNPCModels` | `script_interp.c:2561`, `:2645`, `:2225` | the 8 loaded-model slots |
| `scriptSetDigimon` | `overworld.c:1093` | `SET_DIGIMON` |
| `scriptUnloadEntity` | `overworld.c:1142` | `UNLOAD_ENTITY` |
| `NPCEntityTick`, `NPCEntityTickOverworld` | `overworld.c:1120`, `:1224` | the NPC frame (AI branches empty until 3b) |
| `scriptIdToEntityId`, `getEntityFromScriptId` | `script_value.c:131`, `tamer.c:1249` | script id → entity |
| `entityCheckCollision`, `entityCheckEntityCollision`, `entityIsInEntity`, `isInvisible` | `map.c:3400`, `:3740`, `:3840`, `utils2.c:367` | entity collision for the tamer, the partner and the NPCs |
| `checkMapInteraction` (the NPC part) | `tamer.c:660-682` | talking |
| `scriptPauseGame` (the turn to each other) | `script_interp.c:2740-2750` | movement type 0 at a talk |
| `tickLookAtEntity`, `getRotationDifference`, `rotateEntity`, `tickEntitySetRotation` | `tamer.c:1058`, `overworld.c:1484`, `:1503`, `tamer.c:1105` | movement types 0 and 1 |
| `scriptStartAnimation`, `scriptNPCStartAnimation`, `scriptSetEntityWalking` (NPC part), `setActiveAnim` | `script_interp.c:893`, `overworld.c:1802`, `script_interp.c:879`, `overworld.c:1783` | `PLAY_ANIMATION`, walks |
| `setMovementEnabled` (the NPC part) | `overworld.c:1869` | `stopAnim` |
| `resetEntityOrigin` | `overworld.c:1829` | `RESET_ENTITY_ORIGIN` |
| `initializeLoadedMap` (the NPC overlap) | `main.c:3821-3858` | with loaded games (§2.8) |

## 2. Original behaviour

### 2.1 The map's entity list and the 8 slots

- **Data:** each map file has up to 8 Digimon (`loadMapDigimon`, read only when the map's flag `0x80` is set). Per Digimon: type, follow mode, position, rotation, tracking range, `unk2`, script id, battle stats (hp, mp, current hp / mp, off, def, speed, brain, bits, charge mode, `unk1`, 4 moves and priorities), flee point, waypoint count, 8 AI sections, the waypoints. The asset porter exports all of it as `map.json` `digimon` (with the type name).
  - 216 maps have a list (sizes 1–8). Follow modes in use: 1 (372), 2 (175), 12 (441), 16 (1).
  - Script ids are 5–12 for slots 0–7 on every map (the slot-7 NPC always has script id 12; it matters for the quirk in §2.6).
- **Slot table:** `MAP_DIGIMON_TABLE[8]` (the map data plus the AI state: `animation`, `stopAnim`, `lookAtTamerState`, `hasWaypointTarget`, `waypointWaitTimer`, angles, the path's `activeSection`) and `NPC_ENTITIES[8]` (the entity: script id, autotalk, stats, flee point). An NPC exists on the map when `ENTITY_TABLE[slot + 2]` is set and `isOnMap` is 1.
- **Loading a map** (`loadMap`, `map.c:4066`): `clearMapDigimon` empties all 8 slots (type −1, AI sections −1, AI state 0, `NPC_ACTIVE_ANIM` 0, entity table cleared), then `loadMapEntities` → `loadMapDigimon` fills the slots from the map file. No NPC appears yet: the map's MAPHEAD section places them (§2.2).
- **Leaving a map** (`changeMap`, `map.c:5334`): `removeMapEntities` removes the 8 entities, unloads every loaded model, clears the model list and the AI state.

### 2.2 Script instructions

- **`LOAD_DIGIMON type`** (`script_interp.c:1311`): the model goes into the first free of 8 model slots (`LOADED_DIGIMON_MODELS`). With all 8 taken nothing happens. No `scriptPauseGame`.
  - Map setups load 0–4 models (82 / 69 / 55 / 34 / 15 sections).
- **`SET_DIGIMON type, slot, autotalk`** (`:1315`, `scriptSetDigimon`): `scriptPauseGame(0xFF)`; if `type` isn't the map's type for that slot, nothing happens (returns 0). Otherwise:
  - the slot's old entity (if any) is removed, the entity is created with the NPC tick;
  - position and rotation from the map data, animation `MAP_DIGIMON_TABLE[slot].animation` (0 after loading the map);
  - autotalk set, `NPC_IS_WALKING_TOWARDS` 0, `isOnMap` 1, `isOnScreen` from the camera.
  - The model isn't checked: the scripts always `LOAD_DIGIMON` first (a type loaded once serves several slots, e.g. MAYO04A's two Goburimon).
  - All 1456 uses in the scripts match their map's slot type (checked on the map setups).
  - Autotalk in the scripts: 1 (954 uses), 0 (502).
- **`UNLOAD_ENTITY id`** (`:1321`, `scriptUnloadEntity`): `scriptPauseGame(0xFF)`; the entity of that script id leaves the map (`isOnMap` 0, entity removed). The slot's map data stays, so a later `SET_DIGIMON` brings it back. 119 uses. With an id that has no entity, `getEntityFromScriptId` returns garbage in the C (no case falls through): the port does nothing and reports it.
- **`UNLOAD_DIGIMON type`** (`:2142`): frees the model slot of that type. 10 uses.
- **`SET_AUTOTALK id, value`** (`:1992`): sets an NPC's autotalk (ignored for the tamer, the partner, a missing NPC). 8 uses, all value 0.
- **`PLAY_ANIMATION id, anim`** (`:1526`, `scriptStartAnimation`, `:893`): no `scriptPauseGame`.
  - the tamer: `startAnimationTamer(anim)`, tamer state 10;
  - the partner: `partnerStartAnimation(anim)`, partner state 12;
  - an NPC: `scriptNPCStartAnimation(id, anim)` (the first NPC with that script id), then the `setActiveAnim` quirk (§2.6).
  - 850 uses: 430 the tamer, 97 the partner, 323 NPCs.
- **`ENTITY_WALK_TO` on an NPC** (`specs/script.md` §2.7): `scriptNPCStartAnimation(id, (anim + 1) << 1)`, the quirk of §2.6, slot 2–9 type 2. `tickEntityWalkTo` sets `NPC_IS_WALKING_TOWARDS[slot]` while it walks and clears it when done.
- **`ENTITY_LOOK_AT_ENTITY id, target`** (`:1413`): `scriptPauseGame(0xFF)`; slot type 0 (§2.5). 607 uses.
- **`ENTITY_SET_ROTATION id, angle`** (`:1425`): `scriptPauseGame(0xFF)`; slot type 1: `rotation.vy = angle`, done in one frame. 336 uses.
- **`RESET_ENTITY_ORIGIN id`** (`overworld.c:1829`): the NPC's map position becomes where it stands now; its waypoints move by the same delta (only for AI sections not 0, up to the first −1). Used by step 3b's wandering.
- **`CALL_DIGIMON_ROUTINE n`** (`partner.c:1139`): starts tamer / partner scenes, not NPC ones. Not part of this step (§2.9).
- **`SECTION_ON_EXIT section`**: already ported (pushes a type-4 stack entry, `specs/script.md` §2.4); its 8 sections need this step's opcodes to play.

### 2.3 The NPC frame (`NPCEntityTick` → `NPCEntityTickOverworld`, `overworld.c:1120`, `:1224`)

Every NPC on the map, once per frame (in the object list, after the tamer and the partner), unless the game is in a menu:

1. If `NPC_ACTIVE_ANIM[slot] != 0`: nothing but the animation tick (step 6).
2. Else if `stopAnim` (the script took it over, §2.7): if `animation != 0`, set it to 0 and start animation 0. Then step 6.
3. Else (free):
   - **3b:** `NPCEntityTickWaypointAI` when `lookAtTamerState == 0`;
   - **3b:** by `followMode`: 2 / 11 look at the tamer while he is in the tracking rect; 3–5 / 12–14 track him (`NPCEntityTickTrackingTamer`); 6 / 15 and 7 / 16 track him in a radius (`TrackingTamer2`, animation 2 or 4); 8 / 9 / 17 / 18 in the rect (`TrackingTamer2`, animation 2);
   - `NPC_COLLISION_STATE[slot] = entityCheckCollision(NULL, npc, 0, 0)`;
   - **autotalk (US):** if that hit the tamer (0), the tamer is free (state 0) and the NPC's autotalk is 1: the NPC's step is blocked (`animFlag |= 2`), and while no script runs (`IS_SCRIPT_PAUSED == 1`) its section starts: `TALKED_TO_ENTITY = slot + 2`, `callScriptSection(CURRENT_SCRIPT_ID, npc.scriptId, 1)` (menus closed first);
   - if it hit anything, isn't walking to a script point and plays animation 2–4 (a walk): `collisionGrace` turns it along the obstacle.
4. (JP only: the block and the talk also for autotalk 0 when ✕ is pressed.)
5. `isOnScreen` from the camera (320 × 240).
6. `tickAnimation`: the animation, with its root motion (blocked by `animFlag & 2`).

In option A step 3 does nothing (the NPCs stand in animation 0). The rest runs as written.

### 2.4 Collision between entities (`entityCheckCollision`, `map.c:3400`)

For an entity about to take its next step (`entityMoveForward`: the animation's forward momentum along its rotation; axis-aligned rotations move on one axis only):
- **11:** outside a combat area (battles only, both `arg2` / `arg3` non-zero);
- **10:** the map blocks the step (`checkMapCollision`);
- **0–9:** the first of entities 0–9 (tamer, partner, NPCs) it would touch, skipping itself, the `source` argument, invisible ones (`isInvisible`: not on screen or not on the map) and NPCs / the partner with current HP 0 (none in the map data);
- **−1:** free. The position is restored in every case: it only tests.

`entityCheckEntityCollision(entity, other, dx, dz)` (`:3740`): `other` is a square of its radius (`DIGIMON_DATA[type].radius`).
- **The tamer** (entity 0, on the field): the 4 edges of his own square, and `entityIsInEntity` (the squares overlap).
  - While ✕ is newly pressed this frame (`POLLED_INPUT & ~POLLED_INPUT_PREVIOUS`) and he stands (animation 0), his square reaches 50 further on the sides he faces: that is the talking reach.
- **Others:** only the edges on the side they move to (as the partner's tamer check already ported, `partner.gd` `hits_tamer`).

### 2.5 Talking (`checkMapInteraction`, `tamer.c:660`; `scriptPauseGame`, `script_interp.c:2740`)

Every frame while the tamer walks freely (tamer state 0, `tamerTickWalkingState`), before the trigger cells:
- `entityCheckCollision(partner, tamer, 0, 0)`: the partner is the source, so it never stops him.
- **An NPC (2–9):** his step is blocked (`animFlag |= 2`: no root motion this frame, he stands against the NPC). If its autotalk is 1, or it is 0 and ✕ was pressed (`CHANGED_INPUT & CONFIRM`), and no script runs: `TALKED_TO_ENTITY` = the entity, `callScriptSection(CURRENT_SCRIPT_ID, npc.scriptId, 1)`. The section id is the NPC's script id (5–12).
- **The map (10):** `collisionGrace` (the port's tamer slides along walls instead, `tamer.gd` `_move`).
- **The turn:** the talk section's first `scriptPauseGame` (`SCRIPT_SECTION_IS_EVENT` = 1, trigger 44 not set): the NPC's slot and the tamer's slot get type 0 towards each other (`tickLookAtEntity`).
  - **`tickLookAtEntity(id, target)`** (`tamer.c:1058`): first frame, it stores the target's position (`ROTATION_DATA`); then each frame it turns by 0x200 (`rotateEntity`) the shorter way towards that point until it reaches the angle. Done after 1–5 frames.
  - The NPC's `setMovementEnabled(owner, 1)` comes from the talk section's `SET_DIALOG_OWNER` / `scriptPauseGame(owner)`: `stopAnim` 1 and its AI state cleared.

### 2.6 Quirk: `setActiveAnim(0xC)` (`script_interp.c:889`, `:903`)

`scriptSetEntityWalking` and `scriptStartAnimation` end their NPC case with `setActiveAnim(0xc)`, but `setActiveAnim(scriptId, animId)` takes two arguments (`overworld.c:1783`). The assembly (`asm/us/main/matchings/script_interp/scriptSetEntityWalking.s`) passes `a0 = 0xC` and leaves `a1` as the previous call left it:
- the intended effect (the walked / animated NPC's `NPC_ACTIVE_ANIM` = 0xC, gating its frame to the animation) **never happens**: that NPC keeps running §2.3 step 3 (its collision and autotalk) while the script moves it;
- instead the NPC with **script id 12** (the slot-7 NPC on 48 maps) gets `NPC_ACTIVE_ANIM[7]` = that leftover `a1`.
  - If no NPC has the animated script id, `a1` is still the animation id `(anim + 1) << 1` (non-zero): slot 7's frame then only animates until the next map load.
  - Otherwise `a1` is whatever `startAnimation`'s last calls (`resetMomentumData`, `setupModelMatrix`) left: not known from the code (§6).
- **Port:** keep the missing intended effect. The slot-7 write is applied as described when the animated NPC is missing; otherwise its value is the open question of §6, and the port leaves `NPC_ACTIVE_ANIM[7]` unchanged.

### 2.7 Scripts and NPCs (`setMovementEnabled`, `overworld.c:1869`)

- `setMovementEnabled(npc, 1)`: `stopAnim` 1 and its AI state cleared (`clearMapAITable(slot)`). `setMovementEnabled(-1, x)` (the end of a script) sets every slot's `stopAnim` to `x`; with 1 it clears all AI state.
- So during a talk only the speaking NPCs stop; the other NPCs keep their frame (their collision, autotalk with `IS_SCRIPT_PAUSED` 0 does nothing).
- `scriptIdToEntityId(id)`: 0xFD → 0, 0xFC → 1, else the first NPC on the map (entity set) with that script id → slot + 2, else 0xFF.

### 2.8 Loaded games (`initializeLoadedMap`, `main.c:3791`)

A loaded game enters its map through MAPHEAD like a warp (the NPCs appear by script), then puts the tamer and the partner at their saved positions. If the tamer then stands in an NPC (`entityCheckCollision(partner, tamer)` → 2–9):
- for NPC types 0x6D, ≥ 0x75, 1, 2, 0xF, 0x10, 0x1D, 0x1E, 0x2B, 0x2C, 0x5C on screen 0x9B, 0x6A on screen 0x55: the tamer and the partner are moved to the current exit's spawn;
- for any other NPC: the NPC leaves the map (`isOnMap` 0).

The savegame's `npcMaps[8]` (`world.npc_on_map`) is written on save and copied back on load (`main_menu.c:5042`) but nothing reads it.

### 2.9 Not in this step

- **`CALL_DIGIMON_ROUTINE`** (60 uses): routines 0–10 set tamer / partner scene states (`partner.c:1139`) and clear the sync bit:
  - 0 the toilet scene (`tickPartnerToilet`, `partner.c:536`: the partner walks to the toilet, the camera pans with `createCameraMovement` / `tickCameraMovement`, `map.c:4844`): needs the camera moves → step 4 (decided 2026-10-23);
  - 7 / 9 the collapse and the battle loss: the `MURD` scene (lives box, iris; `src/murd/murd.c`, 700 lines) and `DOOA` (`src/dooa/dooa.c`, 1650 lines): their own system, step 6 "death and lives" of `specs/script.md` §3.1 (after the battles), with the collapse script 0x4DE replacing the care stand-in;
  - 1 (`KAR`), 2 / 10 (evolution), 3 / 4 (dying), 5 / 6 (opening / ending), 8 (Machinedramon): with their systems;
  - 214 (32 uses, all `49 D6`): no case; only the `scriptPauseGame`.
  - Until then the routines stay reported and the sync-bit wait ends at once (as now).
- **Step 3b:** the AI branches of §2.3 step 3.
- **Battles:** an enemy's talk section reaches `START_BATTLE` (reported) and goes on as if nothing happened (`specs/script.md` §6).

## 3. Godot design

### 3.1 Entities

- **`FieldDigimon`** (`scripts/field/field_digimon.gd`, new): what the partner and the NPCs share, moved out of `Partner`:
  - the model of a Digimon type (`load_digimon`), the `PsxAnimator`, `radius`, `direction`, `start_animation`, `look_at_psx`, `tile()`, the root-motion step (`step`), `on_screen`;
  - `probe(rotation, source)`: `entityCheckCollision` for its next step against the map and the entity table (§2.4) — the partner's tamer-only `probe` / `hits_tamer` become this.
  - `Partner` extends it (no behaviour change; `test_partner.gd` must still pass).
- **`Npc`** (`scripts/field/npc.gd`, extends `FieldDigimon`): one NPC slot: the map data (`MAP_DIGIMON_TABLE`: type, follow mode, position, rotation, tracking range, AI sections, waypoints) and its state (`script_id`, `autotalk`, `stop_anim`, `active_anim`, `walking_towards`, `collision_state`, `on_map`, the AI state of 3b: `look_at_tamer_state`, `has_waypoint_target`, `waypoint_wait_timer`, the angles, `active_section`). `tick()` is §2.3, with `tick_waypoint_ai()` and `tick_follow_mode()` empty (reported once).
- **`FieldEntities`** (`scripts/field/field_entities.gd`, new): `ENTITY_TABLE[10]`: the tamer, the partner, 8 NPC slots. `script_id_to_entity_id`, `entity_from_script_id`, `entity_check_collision(source, entity)`, `npc_for_script_id`, the 8 loaded-model slots. The interpreter's `_actor`, `script_id_to_entity_id` and the field's `_entity_screen_position` / `entity_type` use it.
- The tamer gets `step`, `on_screen` / `on_map` and the blocked-step flag (`animFlag & 2`), so his root motion stops at an NPC like the original's. His model radius (100) equals `DIGIMON_DATA[0].radius`.
- Without an entity table (headless tests of other systems) the entity opcodes run as unported (`ScriptInterpreter.NPC_OPS`, their bytes in `UNPORTED`).

### 3.2 The field

- **Map load** (`_load_map_at_exit`): `clearMapDigimon` + `loadMapDigimon` from `map.json` `digimon` (only when the map's `has_digimon` flag is set). **Map change** (`_change_map`): `removeMapEntities` first.
- **NPC nodes** go into the 3D world like the partner; each ticks on `GameLoop.frame` after the partner, in slot order.
- **Talking** (`_check_map_interaction`): the NPC part of §2.5 before the trigger cells, as the C.
- **Speakers:** `_entity_screen_position` and `entity_type` answer for NPCs, so NPC boxes grow from the NPC and show its name in the NPC colour.

### 3.3 The interpreter

- `LOAD_DIGIMON`, `SET_DIGIMON`, `UNLOAD_ENTITY`, `UNLOAD_DIGIMON`, `SET_AUTOTALK`, `PLAY_ANIMATION`, `ENTITY_LOOK_AT_ENTITY`, `ENTITY_SET_ROTATION`, `RESET_ENTITY_ORIGIN` leave `UNPORTED`.
- Movement slots 2–9 tick NPCs; types 0 and 1 get their ticks (`tickLookAtEntity`, `tickEntitySetRotation`), for every actor; `ENTITY_WALK_TO` on NPCs works.
- `scriptPauseGame`'s turn to each other (§2.5) and `setMovementEnabled` for NPCs (§2.7).
- The tamer's `start_animation` takes any animation id: the loops (0, 2, 3) through his `AnimationPlayer` as now, the others as scene animations (`PsxAnimator`, as the sleep scene's 8).

### 3.4 Step 3b (later)

Fill `Npc.tick_waypoint_ai()` (`NPCEntityTickWaypointAI`, `NPCEntityTickWaypointWalk`, `overworld.c:1359`, `:1723`) and `Npc.tick_follow_mode()` (`NPCEntityTickLookingAtTamer`, `TrackingTamer` 1–4, `NPCEntityIsInTrackingRect` / `Radius`, `overworld.c:1400-1719`). The data (waypoints, AI sections, tracking range, follow mode), the AI state fields, the collision, `collisionGrace` and the root-motion movement are all in place after step 3.

## 4. Data

- **Map Digimon:** the asset porter's `map.json` `digimon` (all fields of §2.1, lossless). Nothing new.
- **Radii and models:** `GameData.digimon(type)` (`radius`), `GameData.digimon_file(type)` (`mmd`), as the partner.
- **State:** nothing saved: NPCs are runtime state (`specs/game_state.md` §2.5). `world.npc_on_map` keeps being written on save, as the original.

## 5. Verification

`tests/test_npc.gd` (new, headless, synthetic slots and the real map data):
- `loadMapDigimon` from MAYO04A's list: 5 slots, types, script ids 5–9, positions; `clearMapDigimon` resets;
- `SET_DIGIMON`: a wrong type does nothing; the right one places the NPC (position, rotation, animation 0, autotalk, on map); twice replaces it;
- `LOAD_DIGIMON` with 8 models loaded does nothing; `UNLOAD_DIGIMON` frees the slot;
- `UNLOAD_ENTITY`, then `SET_DIGIMON` again;
- `scriptIdToEntityId` (tamer, partner, NPC, missing);
- collision: the tamer's reach with ✕ newly pressed (50 units); the edge tests for others; off-screen NPCs don't collide;
- talking: ✕ touching an autotalk-0 NPC starts its section as an event; autotalk 1 starts on contact only with the tamer free; not while a script runs; the tamer's step is blocked;
- the turn: type 0 turns 0x200 per frame the short way and ends on the angle; type 1 in one frame;
- `setMovementEnabled` for one NPC and for all (`stopAnim`, the AI state cleared);
- the `setActiveAnim` quirk: an animated NPC keeps its frame; with no NPC of that script id, slot 7 gets the animation id;
- `PLAY_ANIMATION` for the tamer (state 10), the partner (state 12), an NPC.
- `test_script.gd`: the real-script run keeps every section ending; fewer unported names.
- `test_partner.gd` unchanged after the `FieldDigimon` refactor.

`VERIFY.md`, NPCs:
- MAYO04A (the start map): the Aruraumon (day, 7:00–19:00) or the Goburimon (night) at their places, as the setup's IFs choose;
- touch a wild one: its section starts (the battle is reported);
- File City: talk with ✕ to an NPC: the tamer and the NPC turn to each other, the box grows from the NPC with its name;
- cutscenes with NPC walks and animations.

## 6. Open questions

- **The leftover `a1` of `setActiveAnim(0xC)`** (§2.6) when the animated NPC exists: the value written to the slot-7 NPC's `NPC_ACTIVE_ANIM`. If it is non-zero, the slot-7 NPC stops reacting (no collision, no autotalk) after any scene that walks or animates another NPC, until the map is reloaded. Checkable in an emulator: after such a scene on a map with a slot-7 NPC (e.g. File City's Whamon, TWNA02–13), can you still walk into it / talk to it?
- **MAYO04A's Etemon** stands at y = −1000 (1000 units up) with autotalk 1, placed only before trigger 242: what it is for (a scene's actor parked out of sight?) isn't traced.
- **`unk1`, `unk2`** of the map data: not read by the overworld code found so far (battle?).
