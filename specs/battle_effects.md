# Battle effects (the EFE engine)

Status (2026-10-26): approved; **step 1 (the API and the VM) done**, see "As built" at the end. Part of step 5d (`specs/battle.md` §3, §7). Step 1 (the VM and its logic built-ins) is detailed here. Steps 2–3 (drawing) are outlined, and get a detailed section before they are coded, as evolution's scene did.

Every battle technique is a small program: the effect script of its EFE slot. The engine runs it each frame. The script moves the effect's instances (projectiles, beams, explosions), draws them with the slot's model and texture, plays its sounds, and **reports its hits** as attack objects, which the battle resolves (`specs/battle.md` §2.11). So the engine is part of the battle's rules: when and whether a technique hits depends on its script. The asset porter already reads the slots and disassembles the scripts (`asset_porter/specs/efe.md`). This spec says how the port runs them.

## 1. The C code

| C (US) | What |
|---|---|
| `BTL_initializeEFEEngine`, `BTL_removeEFEEngine` (`battle_effect.c:2122–2156`) | the engine object (id 0x500: tick `BTL_tickEFEEngine`, render `BTL_renderEFEEngine`) |
| `BTL_loadMoveEFE`, `BTL_loadNextEFEFile`, `BTL_setupLoadedEFEFile`, `BTL_handleEFEFileLoaded`, `BTL_unloadEFESlot`, `BTL_unloadAllEFESlots` (`:1574–1870`, `:2157–2180`) | loading a technique into one of 16 slots, running its init script (§2.1) |
| `BTL_startEFE`, `BTL_runEFESlotScript`, `BTL_stopEFESubEffect` (`:1637`, `:2181–2208`) | starting and stopping an effect (§2.2) |
| `BTL_tickEFEEngine`, `BTL_renderEFEEngine` (`:1461–1545`) | the per-frame passes (§2.3) |
| `BTL_runEFEScript`, `BTL_dispatchEFEOpcode`, the opcode handlers (`:4740–5145`, `:5336–5358`) | the VM (§2.4) |
| `BTL_EFE_SUB_OPCODE_HANDLERS[97]` and the 97 built-ins (`:2209–4740`, `:5145–5330`); names by id in `asset_porter/dwporter/formats/efe.py` `BUILTINS` | the built-ins (§2.5) |
| `BTL_applyBoxAttackHit`, `BTL_applyRadiusAttackHit`, `BTL_applyLineAttackHit`, `BTL_addAttackObjectToTarget`, `BTL_checkCollisionWithDefaultPower`, `BTL_findHitEntity`, `BTL_checkTargetCollision`, `BTL_isTargetUnhit` | the hits (§2.6) |
| `initializeAttackObjects`, `addAttackObject`, `popAttackObject` (`main/graphics.c:91–140`) | the attack-object queue |
| `BTL_playEFESound`, `BTL_clearEFESoundChannels`, `BTL_stopEFESounds` | sounds (§2.7) |
| `BTL_tickEFEUVAnimation`, `BTL_offsetEFEPrimitiveUVs`, `BTL_initializeUVAnim` | UV animations (§2.8) |
| `BTL_*ParticleEmitter*` (`:1449`, `:1898–2040`, `:4288`) | the 4 particle emitters (§2.8) |
| `EFECreateFlash`, `EFERotateVector` (main, built-ins 18 / 7), `createParticleFX`, `createCloudFX` | shared main-binary helpers |
| Status and battle visuals (`:5359–6750`): poison bubbles and effect, confusion, stun and its sparks, finisher aura and sparks, aura projectiles, item particles, buff rings / disk / trails | §4 |

## 2. Behaviour

### 2.1 Slots and loading

- 16 effect slots (`EFE_DATA_PTR[16]`) and 16 effect texture places. A technique's effect id is its technique + 0x100. EFEDAT slot N holds technique N.
- `BTL_loadMoveEFE(moves, effectIds)` loads a list (one entry per fighter technique slot, `specs/battle.md` §2.2). Each entry:
  - takes a free model slot and reads the 0x5000-byte EFEDAT entry onto the effect heap;
  - places the TIM in a free texture place (page 0x19 + i / 8, y offset (i % 8)·32; CLUT at (128 + (i / 4)·16, 488 + (i % 4)·6)) and remaps the TMD to it;
  - checks the header's effect id (−3 if wrong: EFEDAT slot 110's stale copy, `asset_porter/specs/efe.md`);
  - takes the first free engine slot `k` and sets its data base (header + 0x34), sub-effect contexts (`numSubEffects`, `inst` = null), UV anims (reset), start and init scripts;
  - **runs the init script**, 4 instructions per load step, to its end;
  - `EFE_LOADED_MOVE_DATA[k]` = the effect id, or the init script's negative result;
  - the entry's result is `k`.

  A slot copy is private: the same technique for two fighters gets two slots with their own data.
- Errors (`isLoaded` < 0): −1 no engine slot, −2 no texture place, −3 wrong id, −4 id out of range, −5 no model slot. The battle treats a failed entry as an effect slot of −1, so that technique runs with no effect and no hit.

### 2.2 Starting and stopping

- `BTL_startEFE(k)`: nothing if `k` is out of range or the slot failed. Else `UNUSED_EFE_ARRAY[k]` = −1, and the start script runs at once (`BTL_runEFESlotScript`). The current instance is none, the context is sub-effect 0, `EFE_ACTIVE_SECTION` = −1. The start script spawns the effect's first sub-effects (opcode 17), whose source and target are `BATTLE_ATTACKING_DIGIMON` / `BATTLE_TARGETED_DIGIMON` (`BTL_setupMoveExecution`). The return value is `EFE_ACTIVE_SECTION`, the index of the first spawned instance, which the battle keeps as the fighter's `efeSubEffect`.
- `BTL_stopEFESubEffect(k, s)`: sub-effect `s` of slot `k` stops: `inst` = null, its instance's frame = −1. (When the fighter is hit or starts another technique, `BTL_removeMoveEffect`.)

### 2.3 Each frame

The engine is one object of the battle's list (`specs/battle.md` §5.3).
- **Tick** (`BTL_tickEFEEngine`):
  1. `UNUSED_EFE_ARRAY` 0 → 1;
  2. for each loaded slot, for each active sub-effect: its instance's frame + 1, then its **tick script** (`inst`) runs; then the slot's UV animations step;
  3. the particle emitters tick;
  4. a looping sound whose context's instance frame is < 0 is stopped.
- **Render** (`BTL_renderEFEEngine`): the UV-anim "drawn" marks reset; for each active sub-effect, its **draw script** (`someInst`) runs; the emitters draw.

So each sub-effect has two entry points (set by built-in 2 `initializeSubEffectInstructions`). The tick script holds the motion and the hits; the draw script holds the drawing built-ins. Some scripts mix them. Both run with the same instance and context.

### 2.4 The VM

The instruction set is in `asset_porter/specs/efe.md` ("Script VM"). For the port:
- **Memory.** The scripts address bytes: scope 1 = the slot's data base, scope 0 = the current instance (`EFE_CURRENT_DATA_SEGMENT`). Instances are `EfeInstance` records inside the slot's data area: frame `int32` at +0, then the transform (position xyz `int32` at +4 / +8 / +0xC, rotation xyz at +0x10 / +0x14 / +0x18), then the effect's own variables. `PUSH_ADDRESS` pushes an absolute address, which built-ins read and write through (vectors, output flags, tables such as `EfeTechBoneOffset`). The port runs each slot on **its own copy of the slot's bytes** (`PackedByteArray`, 0x5000). Addresses are offsets in that copy, and built-ins read and write it with the C's sizes and signedness.
- **Stacks.** The data stack (`int32` values, `EFE_SCRIPT_MEM1_DATA`) and the call stack (return addresses; a 0 pushed first, so the last `RETURN` ends the run) are fresh for every run. Built-ins pop their arguments in reverse.
- **A run** (`BTL_runEFEScript`) executes until the script pointer is null (STOP, the outer RETURN, a built-in that ends it), with no instruction limit. After the run: if the instance's frame is −1, the sub-effect is freed (`inst` = null).
- **Sizes and operators** (`(w >> 8) & 0xF`: 4 → `int32`, 2 → `int16`, else `int8`; operator / compare `w >> 12`): exactly as the C's handler tables (`BTL_set/add/sub/mul/div/mod/shl/shrInt{8,16,32}Variable`, `BTL_compare*`). Integer division truncates toward zero; shifts are arithmetic.
- **`LOAD_RANDOM`** is the C's `rand()`, not `randomLimit`. The port draws it from the shared `Rng` with the C's `rand` range (0–0x7FFF), so seeded tests are reproducible.
- **Opcode 17 `SPAWN_SUB_EFFECT`** (`BTL_spawnEFESubEffect`, `:4680`):
  - finds the first instance with frame −1 among `count` records from `table` (stride `stride`); with none free it acts as `RETURN`;
  - `EFE_ACTIVE_SECTION` = that index, if not yet set;
  - finds the next free context after the current one (none → `RETURN`);
  - the new context gets the instance, the parent instance (the current one), and source / target: the battle's attacker / target from the start script, else the parent's;
  - execution continues in the new instance, after the 12 bytes. The spawned code runs its setup right away (usually built-in 2 and a `STOP`).
- **Contexts** (`EfeSubEffect`: `inst`, `someInst`, instance, parent instance, source, target, bone offset) live in the slot's data in the C, but no script reads them as bytes. The port keeps them as a GDScript array beside the copy, indexed like the C's.

### 2.5 The built-ins

97, by id (`BUILTINS` in the asset porter). Their arguments come off the data stack. Grouped by what the port needs from them:

- **Flow and setup:**
  - 0 `checkTechCompatibility`: the bone-offset table entry for the source's original type (`getOriginalType`); not found → the run ends with −1;
  - 1 `initializeUVAnim`; 2 `initializeSubEffectInstructions`; 5 `initializeEFETransform` (copy the parent's transform, or `setTransformToBoneOffset` without a parent);
  - 11 / 67 discard operands; 42 `printDebugValue` (no-op);
  - 95 `markEFEFinished`; 96 `isTargetUnhit`.
- **Maths** (fixed-point, §3.2):
  - 38 / 39 sine / cosine; 40 `interpolateValue`; 41 `getRandomInRange`; 43 `getVectorEulerAngles`; 47 `getVectorLength`;
  - 48–54 vector copy / add / sub / mul / div / mask / shift; 71–73 vector by scalar;
  - 12 `interpolateVector`; 25 `calculatePolarOffset`;
  - 45 / 58 normalise angles; 57 `rotateVectorByAngles`; 59 `combineRotations`; 7 `EFERotateVector`.
- **Transforms and entities:**
  - 8 / 29 / 32 / 69 set the transform from a bone (target bone, the bone offset, source bone, bone matrix); 56 / 62 read a bone's transform;
  - 14 `copyTargetEntityPosition`; 23 / 37 target / source Digimon size; 26 / 61 copy from / to the parent;
  - 13 `steerTransformTowardPoint`; 33 `rotateTransformTowardPoint`; 36 `applyHomingMovement`; 55 `centerTransformOnEntities`; 88 `faceTargetEntity`;
  - 10 `getScatteredSpawnPosition`; 17 / 75 `selectNextTargetEntity` / `selectRandomTargetEntity`; 46 `setTargetToHitEntity`.

  These need the fighters' bone world matrices in PSX units (`calculateBoneMatrix`).
- **Hits** (§2.6): 6, 9, 34, 44, 89, 90, 91, 96.
- **Sound** (§2.7): 28 `playEFESound`.
- **Camera and screen:**
  - 21 `projectPositionToScreen`; 74 `convertToViewSpace`; 76 `getCameraRotation`; 81 / 94 viewport distance;
  - 63 `setupFixedCamera`; 64 `restoreCameraView`: a fixed view for some finishers (projection 0x200, eye at z −2000);
  - 93 `disableMapLayer` (re-enabled by every tick).
- **Effects from the main binary:** 16 `addParticleEmitter`; 18 `EFECreateFlash`; 19 `addCloudEffect`; 27 `addSourceEntityParticleFX`.
- **Drawing** (steps 2–3, §5):
  - 3 `drawTMD`, 77 `drawTMDYXZ`, 79 `drawTMDScreenSpace`; 15 `setEFEModelObjectColor`; 78 / 80 CLUT colours;
  - 4 / 20 / 22 / 24 sprites; 65 / 70 textured quads; 60 lines; 66 / 68 wireframe grid / box;
  - 30 scrolling background; 31 parallax sprites; 82 radial waves; 83–85 ribbons; 86 ring tube;
  - 87 screen overlay; 92 screen fade; 35 `getUVAnimTimer`.

Some of the logic built-ins are called from draw scripts and some draw built-ins return values the script uses (35, 21). So the port runs **both** passes in step 1; the drawing built-ins pop their arguments and do nothing until steps 2–3.

### 2.6 Hits

Every hit built-in checks the candidates (entities 1–9, not the source, present on the map, `isHit` 0), marks the victim `isHit` = 1, and queues an attack object `{victim, position, effect slot (COMBAT_EFFECT_ITR), sub-effect, caster}`:
- **91 `applyBoxAttackHit(extent*, out*, r)`:** an AABB at the instance's position with the given extent (`findAABBHitEntity`); the first unhit entity; `r` < 0 → the current sub-effect. 6 is 91 with `r` = −1.
- **90 `applyRadiusAttackHit(r, out*)`:** every unhit entity within `r + radius` (squared, xz). The position is on the line to the source at the victim's radius, at half its height.
- **89 `applyLineAttackHit(arg*, out*, width)`:** the segment from the source to the instance (xz) against each entity's radius square (`doSomethingWithSomePoints`), above `−height − arg[1]`; the first one.
- **9 `addAttackObjectToTarget`:** the context's target, if unhit, at the instance's position.
- **44 `findHitEntity(out*, mode, extent*)`:** a test without a hit: mode 0 the first unhit entity in the box, 1 any entity.
- **34 `checkTargetCollision`**, **96 `isTargetUnhit`:** tests on the target.

`isHit` stays 1 until the battle clears it (the victim's invulnerability end, a block, a miss), so one technique hits a victim once per window. The queue (`addAttackObject` / `popAttackObject`, `graphics.c`) keeps them per victim; the battle pops one per victim per frame. Effect 0x179 (the aura projectile, §4) uses technique 0x79.

### 2.7 Sounds

`playEFESound(id)`: −1 nothing. Ids 0x12, 0x20, 0x21, 0x22 are loops: played with `playSound2(8, id)` into one of 10 channels tied to the context, and stopped when that instance's frame goes below 0 (§2.3). Others: `playSound(8, id)`. Bank 8 is the battle effects' sound bank. Its loading and its relation to the fighters' banks 4–7 come from `specs/sound.md` §2 and are checked in step 1.

### 2.8 UV animations and emitters

- **UV animation** per TMD object: a keyframe table `{frames, du, dv}`. Each tick: frame + 1; at the keyframe's length the object's primitive UVs shift by `(du, dv)` (`BTL_offsetEFEPrimitiveUVs`), and the table loops. `getUVAnimTimer` reads its frame.
- **Particle emitters** (4, 21 particles each): set by `addParticleEmitter` with an instance transform, life, offset, start speed, acceleration, colour and type; ticked and drawn by the engine.

## 3. Godot design

### 3.0 Design choice: every technique effect is a scene behind one API (decided 2026-10-26)

**Why:** techniques are among the first things a modder will want to change or add (a new Digimon's attack, a restyled Fire Tower). So the battle never knows how an effect works. It instantiates the technique's **effect scene**, talks to it through a fixed API, and gets its hits back as signals. The original's 120 techniques are one implementation of that API (`EfeEffect`, which runs their bytecode); a mod's technique can be another (hand-made nodes, `GPUParticles3D`, its own script), with no change to the battle.

This follows the general rule of the port (`specs/scenes.md` §3): **prefer composition and instantiated scenes, above all for anything a mod may want to replace or extend.** Logic that reproduces the C stays in plain, testable classes; the scene is the slot a mod fills.

```
BattleEffect (scenes/battle/effects/battle_effect.tscn, script BattleEffect: the API, no behaviour)
├─ EfeEffect.tscn     default: the original technique, its bytecode run by EfeVm (§3.2)
└─ <a mod's scene>    any scene whose root script extends BattleEffect
```

**Which scene a technique uses:** the move record's optional `effect_scene` (a content key / `res://` path, resolved like other content, `specs/content.md`). Absent → `EfeEffect.tscn` with the technique's EFEDAT slot. A `dw1` move never sets it.

### 3.1 The API (`BattleEffect`, `scripts/systems/battle/battle_effect.gd`)

**Lifetime: one instance per loaded technique, for the whole battle** — the C's slot (§2.1), not one per use:
- the original's scripts keep their variables in the slot between uses, so a fresh instance per use could change behaviour;
- a technique can be started again while its earlier instances are still on screen.

The battle creates them during loading (`specs/battle.md` §2.2: one per fighter technique slot, duplicates included), keeps them as the fighter's `effectSlot[j]`, and frees them at the battle's end (`BTL_unloadAllEFESlots`).

**In (set by the battle before use):**
- `setup(technique: int, caster_slot: int, ctx: BattleEffectContext) -> int`: loads what it needs; returns 0, or the C's negative load error (§2.1), in which case the battle treats the slot as −1.
- `ctx` (`BattleEffectContext`, owned by the battle): the only way an effect sees the battle. Read: the fighters by entity id 0–9 (presence, `is_on_map`, PSX position and rotation, bone world matrices `bone_matrix(entity, bone)`, `radius`, `height`, original type, `is_hit`), the attacker and target of the current start, the camera / screen projection and `PsxMath`. Services: `sound` (play, loops), `rng` (the C's `rand` and `randomLimit`), the shared FX (`particle_fx`, `cloud_fx`, `flash`), the map layer toggle, the fixed camera.
- `mark_hit(victim)` and `is_hit(victim)` go through `ctx` too: the "hit once per window" rule (§2.6) is the battle's, not the effect's.

**Calls (from the battle, once per original frame, in its frame order — never from `_process`):**
- `start(attacker, target) -> int`: begins a use; returns the sub-effect index the battle keeps (`EFE_ACTIVE_SECTION`, −1 if none).
- `stop(sub_effect)`: ends that use early (`BTL_stopEFESubEffect`).
- `tick()`: the logic pass (§2.3 tick: motion, hits, sounds).
- `draw()`: the presentation pass (§2.3 render). An effect may also need values from it (the original's draw scripts compute some), so it is called headless too; drawing nodes simply aren't created without a view.
- `is_running() -> bool`; `unload()`.

**Out (signals up; the effect never computes damage):**
- `hit(victim: int, position: Vector3i, sub_effect: int)`: one attack object (§2.6), PSX units. The battle queues it (`addAttackObject`) and resolves it (`specs/battle.md` §2.11). The effect marks the victim through `ctx.mark_hit` first, as the C does.
- `finished(sub_effect: int)`: the use's instances have all ended (frame −1).

**What a mod's effect must respect:** frame-driven `tick` / `draw` only, hits only through `hit`, state only through `ctx`. Everything else (its nodes, materials, how it moves) is free.

### 3.2 `EfeEffect`: the original techniques (logic headless)

- **`EfeEffect`** (`scenes/battle/effects/efe_effect.tscn`, script extends `BattleEffect`): one EFE slot. Holds the byte copy, the header, the contexts, the UV anims, the model / texture handles. `start` / `stop` / `tick` / `draw` are `BTL_startEFE` / `BTL_stopEFESubEffect` and the slot's part of `BTL_tickEFEEngine` / `BTL_renderEFEEngine`.
- **`EfeVm`** (`scripts/systems/battle/efe_vm.gd`, plain class): the interpreter over one slot. The opcodes and the 97 built-ins as methods named after the C (`_builtin_apply_box_attack_hit`, …), dispatched by id. Hit built-ins call `ctx.mark_hit` and emit through the effect's `hit`. Drawing built-ins call a **draw sink**; in step 1 the sink records the calls (for tests) and draws nothing.
- **`EfeView`** (a child node of `EfeEffect`, steps 2–3, §3.4): the draw sink that draws.
- **The slot bytes** come from the asset porter's `effect.bin` (`specs/battle.md` §6), read through `Content`; the model and texture from the existing `model.gltf` / `texture.png`.
- **The engine-wide parts** of §2 (16-slot limit, 16 texture places, the 4 particle emitters, the 10 loop-sound channels, the attack-object queue, `UNUSED_EFE_ARRAY`) live in **`EffectHost`** (`scripts/systems/battle/effect_host.gd`, owned by the battle): it creates the effect scenes, enforces the C's limits for `EfeEffect`s (so the original's load errors still happen), ticks / draws them in slot order (the C's loop order), then the emitters, then the loop-sound check. A mod effect counts as a slot but brings its own resources.

### 3.3 PSX fixed-point maths

The scripts' motion and their hit timing depend on the GTE's integer maths. The port needs exact versions in one helper, **`PsxMath`** (`scripts/core/psx_math.gd`):
- `rsin` / `rcos` (4096 = 1.0, the decomp's `sin_lookup_table.h`);
- `ratan` (`_atan`, `atan_lookup_table.h`);
- `RotMatrix`, `RotMatrixYXZ`, `RotMatrixZYX`, `ScaleMatrix`, `MulMatrix`, `ApplyMatrixSV` / `LV`, `matrixToEuler2`;
- `SquareRoot0`.

The tables come from the data porter (`systems/psx_math`, checked against the headers), since the porters generate data, not code. The battle logic's own angles (`entityLookAtLocation`, the hit reaction) use the same `ratan`. `specs/npc.md`'s open point on `_atan` vs `atan2` is then settled by the same helper.

### 3.4 The view (steps 2–3)

`EfeView` (a child of each `EfeEffect`, its own scene `scenes/battle/effects/efe_view.tscn` so a mod can restyle the original techniques' drawing without touching their logic) receives the draw calls each render pass and draws them in the 3D viewport: TMD objects as mesh instances from the slot's glTF (object `id` → its mesh, with the UV offsets in the material), sprites and quads as camera-facing or screen quads, lines, ribbons, waves, the screen fade / overlay on the HUD layer, the fixed camera as a temporary camera. PSX semi-transparency modes go through the existing `PsxLit` blended passes. Instances are pooled and re-used each frame, so a frame shows exactly what that frame's draw scripts drew.

## 4. The battle visuals outside the scripts

Driven by the battle logic, drawn with the `btl_rel` models (`specs/battle.md` §6) and the system textures. They come in step 3. By the same rule (§3.0), each is its own scene (`scenes/battle/fx/<name>.tscn`) instantiated by the battle on its C trigger and freed on its C removal, with the C's tick as its frame call. The aura projectile is a `BattleEffect` (it makes hits) whose default implementation is its C code, not a script.

| Visual | C | Shown |
|---|---|---|
| Poison bubbles and effect | `BTL_addPoisonEffect`, `BTL_addPoisonBubble` (`:5359–5500`) | while poisoned (visual priority, `specs/battle.md` §2.12) |
| Confusion (circling model) | `BTL_addConfusionEffect` (`:5501–5580`), model `BTL_REL` 0x1D58 | while confused |
| Stun (stars) and sparks | `BTL_addStunEffect`, `BTL_addStunSubEffect` (`:5582–5828`), model 0x2220 | while stunned |
| Finisher aura and sparks | `BTL_addFinisherAura` (`:5855–6040`), model 0xD20 + TIM 0x0 | the finisher wind-up |
| Aura projectiles (effect 0x179) | `BTL_addAuraProjectile` (`:6040–6180`) | a flattened fighter's attack; **makes hits** (technique 0x79), so its logic is in step 1 |
| Item particles | `BTL_addItemParticles` (`:6190–6320`) | an item reaching the partner |
| Buff rings, disk, trails | `BTL_addBuffRingsEffect` and friends (`:6320–6750`), model 0x2848 | buffs, cures |
| Hit particles, flashes, clouds | `createParticleFX`, `EFECreateFlash`, `createCloudFX` (main) | hits and blocks; reuse the field's `ParticleFX` / `CloudFX` |

## 5. Order of work

1. **The VM and its logic** (with 5d-2):
   - `PsxMath` and its tables;
   - the API: `BattleEffect`, `BattleEffectContext`, `EffectHost`; the move record's `effect_scene` (data porter: the field, absent on every `dw1` move);
   - `EfeEffect` and `EfeVm`: every opcode; every built-in except the drawing ones (no-op pops);
   - the hits, sounds, UV-anim timers and emitter state;
   - the aura projectile's logic.

   Tests (`tests/test_efe.gd`):
   - each opcode, size and operator on hand-made bytes;
   - every one of the 120 effects loads and runs its init script;
   - each runs its start script with two stub fighters facing each other at a typical distance, until all its instances end, without error, and produces its hits; a table of "frames to first hit" per technique is printed for review;
   - seeded runs are repeatable;
   - the hit built-ins' geometry on hand-placed fighters;
   - the API contract: a minimal test effect scene (extends `BattleEffect`, hits on its 10th tick) set as a move's `effect_scene` is created, started, ticked and reports its hit exactly like an `EfeEffect`; `EffectHost`'s slot limit and load errors.
2. **Drawing the techniques** (5d-5): `EfeView` and the drawing built-ins. Detailed spec first, from the render built-ins' C. VERIFY: a technique gallery in the debugger (a test map, two Digimon, a technique picker).
3. **The other visuals** (5d-5): §4.

## 6. Open points

- **Effect timing vs the original.** Without an emulator trace the port can't compare frame by frame. The step-1 table of "frames to first hit" is the reference to check against the game for a few techniques (the user's in-game checks).
- **Sound bank 8** (§2.7): where it is loaded in battle; to confirm in step 1.
- **Unreached script bytes** (`asset_porter/specs/efe.md`: ~1 % gaps): if a run reaches one, the VM reports it and stops that run.
- **`MAIN_D_80134CDC`**, set to 1 by every spawn: its reader is in main; to identify in step 1.
- **Slot 110**'s stale copy fails to load in the original too (effect 366 has no effect). The port keeps that.

## As built (step 1, 5d-2, 2026-10-26)

- **`PsxMath`** (`scripts/core/psx_math.gd`): the game's `_sin` / `_cos` / `_atan` (tables from `systems/psx_math`), `getDistance`, `toEulerAngles`, `matrixToEuler1 / 2`, `multiplyRotations`, `lerp` exactly; libgte's `RotMatrix` (Rx·Ry·Rz), `RotMatrixYXZ` (Ry·Rx·Rz), `RotMatrixZYX` (Rz·Ry·Rx), `ApplyMatrixSV` (saturated) / `LV`, `MulMatrix0`, `ScaleMatrix`, `GsMulCoord0`, `rsin` / `rcos` / `ratan2` from their documented behaviour. The orders are the ones the game's `matrixToEuler1 / 2` invert (checked by the tests). C casts and division (`s8`, `s16`, `s32`, `div`, `mod`). `Rng.custom_random` reproduces `customRandom`'s two LCGs.
- **The API:** `BattleEffect` (`scripts/systems/battle/battle_effect.gd`, scene `scenes/battle/effects/battle_effect.tscn`): `setup` / `start` / `stop` / `tick` / `draw` / `is_running` / `unload`, signals `hit(victim, position, sub_effect, caster)` and `finished(sub_effect)`. `BattleEffectContext` (`battle_effect_context.gd`): entities by `ENTITY_TABLE` index (presence, map / screen flags, type, HP, `is_hit`, location, yaw, bone matrices, `look_at`), Digimon data (radius, height, `original_type`), the camera (`world_screen_matrix`, `viewport_distance`, `world_to_screen`), the map layer, the fixed camera, sounds and the shared effects (`effect(kind, args)`). The base is an empty world; the battle (5d-3) extends it.
- **`EffectHost`** (`effect_host.gd`): the 16 slots, texture places, `EFE_LOADED_MOVE_DATA`, `UNUSED_EFE_ARRAY`, the VM globals (`target_entity_index`, `hit_entity_index`, `sub_effect_index`, `combat_effect_itr`, `bone_offset`), the attack-object queue (16, oldest first, `pop_attack_object(victim)`), the 10 loop-sound channels, the 4 particle emitters with their `rand()` calls. The scene per technique: `scene_override` (tests), the move's `effect_scene`, else `efe_effect.tscn`. A load error frees the effect and gives -1 for that entry; the C stops the whole list at the first error (`goto end`), which no original data hits.
- **`EfeEffect`** (`efe_effect.gd`, scene `efe_effect.tscn`) runs on a private copy of `efe/<slot>/effect.bin`; addresses are offsets in that copy (data base 0x34); `load_bytes` takes a hand-made slot. Contexts and UV animations are GDScript records beside the bytes; the UV offsets accumulate per object for the view. `finished` is emitted when the last context of the slot ends.
- **`EfeVm`** (`efe_vm.gd`): the 18 opcodes and the 97 built-ins. **A branch jumps when its comparison is true** (`BTL_EFE_COMPARISONS` return 0 when true); the asset porter's listing said "if not", fixed. The drawing built-ins pop their C argument counts and record `[name, args…]` in `draw_calls` when `record_draws` is set. Runs stop after 200,000 instructions or on a bad address and report a fault (none occur).
- **Data:** `digimon_data.original_type` (`ORIGINAL_DIGIMON_TYPES`, `getOriginalType`) added for `checkTechCompatibility`.
- **Not in step 1:** the aura projectile (effect 0x179) moves to 5d-3, since the battle's flatten state drives it.
- **Tests** (`tests/test_efe.gd`, 41 checks): `PsxMath`; every opcode on a hand-made slot (sizes, operators, a true comparison jumping, CALL / RETURN, `LOAD_INDEXED`, a built-in, spawn, tick, a hit, the draw sink); a mod effect (`tests/fixtures/hit_effect.tscn`) through the same API; all 120 original effects load (slot 110 fails its id check, as in the original) and run without a fault against two stub fighters at the C's attack distance, with the "frames to first hit" table printed.
- **Open, for 5d-3 with real fighters:** 8 techniques don't hit the stub target: Ice Statue (17), Buster Dive (47), Fireball (61), Boom Bubble (71), Deadly Bomb (74), Hand of Fate (82), Frozen Fire Shot (97), High Electro Shocker (112). The stub skeleton puts every bone on one vertical line, so effects that start from a hand bone fly beside the target (Fireball's shot passes 305 units to the side). 112 belongs to H-Kabuterimon through its `anim_technique` override, but its bone table lists only Digimon 1, so its start fails; to check whether the original fails too. Ice Statue and Deadly Bomb wait for something the stub never gives and run the full 600 frames.
- **Open:** libgte's own `rcossin_tbl` / `ratan2` tables aren't in the decomp; the rounding may differ by one unit from the PSX.
