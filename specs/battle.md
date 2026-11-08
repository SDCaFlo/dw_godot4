# Battles

Status (2026-10-26): approved; **5d-1, 5d-2 and 5d-3 done**, see "As built" at the end. Step 5d of `PLANS.md`. The technique effects, which also make the hits, have their own spec: `specs/battle_effects.md`.

The field battles of the original: a wild or scripted enemy starts a fight on the map where it stands. The partner fights on its own (its AI). The tamer gives it orders from the command menu and throws items. The battle ends when every enemy faints, when the partner faints and the countdown runs out, or when the tamer runs away. Rewards (bits, stat gains, items, techniques), the care changes and 20 minutes of game time follow.

Not in this spec:
- the tournaments' arena battles (`std` overlay, `GAME_STATE` 4 / 5): step 4e reuses this port;
- versus mode (`vs`);
- what follows a lost battle: the `MURD` / `DOOA` scenes (step 6, "death and lives"). This spec ends a lost battle at the start of script section 0x4DE.

## 0. How the original runs a battle

The battle is a blocking call inside the script interpreter. `START_BATTLE` calls `startBattle`, which runs its own frame loops until the battle is over and returns the outcome. During those loops the field's frame doesn't run: no script, clock, care or camera follow. Each battle frame is the battle logic, then `BTL_battleTickFrame`, which ticks and draws the object list. The object list holds:
- the entities: the tamer, the partner and the NPCs, whose tick functions switch to their battle versions while `GAME_STATE` ≠ 0;
- the effect engine;
- the HUD pieces.

`GAME_STATE`: 0 field, 3 loading the battle, 2 battle set up / ending, 1 fighting (commands accepted), 4 / 5 the arena.

The fighters are the field's own entities, on the same map, at the same places. The partner is fighter 0. The enemies (1–3) are NPC entities 2–9 (`COMBAT_DATA.player.entityIds`). There's no separate arena scene.

## 1. The C code

| C (US) | What |
|---|---|
| `SCRIPT_OP_START_BATTLE` (`script_interp.c:1897–1957`) | counting, predefined enemies, `stopBGM`, the outcome and what the script does with it (§2.17) |
| `startBattle`, `advanceBattleTime` (`tamer.c:832–967`) | the outer call; care and time after the battle (§2.16) |
| `handleBattleStart`, `loadBattleData`, `isScreenConcave`, the flee bubbles, `startBattleIdleAnimation`, `handleBattleIdle` (`main/btl.c`) | who joins, the loading (§2.1–2.2) |
| `BTL_initializeCombat`, `BTL_handleBattleIntro`, `BTL_isBattleFinished` (`btl/battle_setup.c`) | set-up, intro, end test (§2.3–2.5) |
| `BTL_battleMain` and the rest of `btl/battle_main.c` | the main loop, AI, fighter states, movement, techniques, hits, damage, statuses, victory (§2.5–2.13) |
| `handleCommands`, `handleFleeing`, `tamerTickBattle`, `partnerTickBattle`, `NPCEntityTickBattle` (`main/battle_tick.c`) | the tamer's commands, running away, the entities' battle ticks (§2.6, §2.14) |
| `battle_ui.c` (main): `handleBattleEndBox`, `battleStatsGainsAndDrops`, `handleBattleInjury`, `battleMoveLearning`, the bits and stats boxes, `resetStatsAfterCombat` | the rewards (§2.15) |
| `damageTick` (`utils.c:93`) | how a hit drains HP (§2.11) |
| `btl/command_menu.c`, `command_shout.c`, `battle_hud.c`, `main/entity_text.c` | the HUD (§4) |
| `addThrownItem`, `startThrowingItem`, `tickThrownItem` (`main.c:4221–4290`), the battle branches of `item.c` (`:2220–2390`) and `inventory.c` | items in battle (§2.18) |
| `tickTamerWaypoints`, `initializeTamerWaypoints`, `clearTamerWaypoints` (`map.c:3111–3131`, `:3527`); called from `tamerTickWalkingState` (`tamer.c:515`) and the map load (`map.c:4091`) | the tamer's path back to the map entry, used by the intro and by Run (§2.4, §2.14). **Not ported yet** in the field. |
| `entityCheckCollision` with a combat area (`map.c:3416–3460`), `entityCheckCombatArea` (`map.c:3042`) | the screen box the fighters stay in (§2.9) |
| `btl/battle_effect.c` | the effect engine and the status / aura / buff / item visuals (`specs/battle_effects.md`) |
| Data | `moves/move_data`, `type_factors`, `learn_chances`; `systems/battle_ai`, `battle_commands`, `flee_chances`, `stat_gain_factors`, `enemy_music`; `digimon_data` (`type`, `level`, `special`, `radius`, `height`, `moves`, `drop_item`, `drop_chance`); the map's Digimon (`map.json` `digimon`: battle stats, moves, priorities, bits, charge mode, `unk1`, flee point); new properties in §6 |

## 2. Behaviour

### 2.1 Who fights (`handleBattleStart`, `btl.c:209`)

The talked-to entity `id` (`TALKED_TO_ENTITY`, the NPC whose section reached `START_BATTLE`) is enemy 1. `entityIds[0]` = 1 (the partner). `FLEE_DISABLED[0]` = trigger 1 (a battle you can't run from: the bosses). `IS_PREDEFINED_BATTLE` = script value 0xFA.

**Predefined** (0xFA = 1): the enemies are the entities in script values 0xFB–0xFD (≠ 0xFF; `START_BATTLE` has turned script ids into entity ids). Each gets flee bubble 0. Every other visible NPC on the map gets bubble 1, and those off screen leave the map (`isOnMap` = 0).

**Otherwise**, for each NPC slot 2–9 present on the map:
- `id` itself: bubble 0.
- Off screen: leaves the map (`isOnMap` = 0), no bubble.
- Already 3 enemies: bubble 1.
- On a **concave** map (`CONCAVE_SCREENS`, 18 maps): if the straight tile path from the tamer's tile, or from the partner's, to the NPC's tile is blocked (`isLinearPathBlocked`): bubble 1.
- Else the **join roll**: `r = randomLimit(100)`; with the Enemy bell (0x24) in the inventory `r −= 50`, else with the Enemy repel (0x23) `r += 20`; `FLEE_DISABLED[0]` → `r = 0`. It joins if `r < FLEE_CHANCES[partner type][its type]` (`systems/flee_chances`, by the Digimon `type` Data / Vaccine / Virus). A partner of type 0xFF joins it with a second roll `randomLimit(100) < 70`. Joining → bubble 0, else bubble 1.

`ENEMY_COUNT` = the number of enemies (1–3).

**Flee bubbles** (`setFleeBubble`, `renderFleeBubble`): bubble 0 ("!") over a joining enemy, 1 over one that runs off. A sprite from VRAM (tpage (896, 256), CLUT (0x100, 0x1E7), u = type·24 + 0xB8, v 0x80, 24 × 24) over the Digimon's head (`height` + 0xC8 up, rising 50 over the first 5 frames, then at + 0xFA), growing in over 5 frames then pulsing (`FLEE_BUBBLE_SCALE`), screen size from the depth, clamped to the screen. A second small quad (u = type·16 + 0xC8, v 0x98) points from the bubble to the Digimon. Removed when the effects have loaded (`LOAD_EFE_STATE` 0) or after 200 frames.

### 2.2 Loading (`loadBattleData`, `btl.c:358`)

- **Music:** `playMusic(0x21, n)` (sound font 33): n = 3 if enemy 1's type is 0x73; else for an NPC enemy: 0 if predefined, else its `ENEMY_MUSIC_MAPPING` entry (enemy types 0x43–0x6F; 1 for the others); 0 for a predefined non-NPC, else 1.
- `currentCommand` = 3 (Your Call). The tamer plays animation 1. Every visible NPC plays 0x21 (battle idle). `GAME_STATE` = 3.
- Not predefined: the partner plays 0x24 (run) and, each loading frame, runs up to the tamer (the field's partner collision in `GAME_STATE` 3: it heads for its waypoints or the tamer and goes idle on touching him, `map.c:3337–3367`); the enemies look at the partner.
- The fighters' sound banks: enemy `i` gets bank `i + 4` (`vabId`) with its `VBALL` set; the partner keeps bank 4.
- The battle objects are set up (item particles, finisher aura, poison, confusion, stun, buff models, the effect engine).
- **Techniques:** for each fighter and each of its 4 move slots ≠ 0xFF: if the slot's animation has no technique (`entityGetTechFromAnim` = 0xFF) the slot is **cleared** (`moves[j] = 0xFF`); else its effect (technique + 0x100) is loaded into the next effect slot. `fighter[i].effectSlot[j]` = that slot, or −1. Each (fighter, slot) gets its own effect slot, duplicates included (at most 16).
- `stats.current.unk1` (the running technique + 0x100) and `efeSubEffect` = −1.
- The partner goes idle (`handleBattleIdle`). `GAME_STATE` = 2.

The loading waits are CD reads in the original (§7: the port's length).

### 2.3 Set-up (`BTL_initializeCombat`, `battle_setup.c:43`)

- Globals: death countdown off, `FINISHING_ENTITY` none, `NO_AI_FLAG` 0, `FLEE_DISABLED[1]` 0, `FLEE_TIMER` 0, the life-bar toggle off, `BATTLE_FRAME_COUNT` = 1, `HAS_TAKEN_DAMAGE` 0, `IS_TAMERLESS_BATTLE` = trigger 2, `usedMoves[12]` = 0xFF, the counters (`hitCount`, `blockedCount`, `unk2` = hits that took ≥ 20 % of the partner's HP, `statusedCount`) 0. The charge mode the partner had is saved (`BTL_SAVED_CHARGE_MODE`), the partner's tile noted.
- **Each fighter:** `isHit` 0, target 0xFF, damage buffers 0, flags 0, `moveRange` 0, timers 0, `speedBuffer` 100, `statusFxId` / `activeEffectSlot` −1, the blocked-attack table cleared;
  - `buffsRemaining` = brain / 100 + 1 below 400 brain, 4 below 600, else 5;
  - `buffPrioTimer` = brain / 10 + 5;
  - `finisherGoal` = 3000 − speed.
  - Quirk: the loop clears `table2[i]` instead of `table2[j]`. Harmless: `table1` is all −1.
- **The commands** (§2.6) by the partner's brain: `numCommands` = `BRAIN_TO_COMMAND_MAP[brain / 100]` (3, 4, 5, 7, 8) below 500, else 9. The list, from index 0: 11 (finisher), 1 (Run), then by count:
  - 3: 3;
  - 4: 2, 3;
  - 5: 4, 2, 3;
  - 7: 7, 5, 4, 2, 3;
  - 8: 7, 6, 5, 4, 2, 3;
  - 9: 7, 6, 5, then 10 / 9 / 8 for each equipped technique slot 2 / 1 / 0, then 3; `numCommands` = that length.

  `hoveredCommand` = the last index (Your Call); current and buffered command = 3.
- `INITIAL_COMBAT_STATS[i]` = each fighter's base HP, MP, Off, Def, Speed, Brains.
- **Injured or sick** partner (`condition & 0x60`): Off, Def, Speed and Brains each lose a fifth (restored after, §2.15).
- `startingHP` = the partner's current HP. The command menu opens.

### 2.4 The intro (`BTL_handleBattleIntro`, `battle_setup.c:207`)

- The partner goes idle and looks at enemy 1. The start text appears (§4).
- Every visible NPC not in the battle runs off: animation 0x24, `animFlag |= 4` (its animation ticks twice a frame, §2.5), looking at its map flee point (`npc.flee`).
- The tamer runs back (animation 3, sound (0, 0x10)) along his waypoints, last first (§2.14), then towards his start tile. Each frame he checks the combat area (`entityCheckCollision(partner, tamer, 0x136, 0xE6)`, or 0x12C × 0xDC once on the start-tile leg). On the area's edge (result 11), or on reaching the start tile: animation 1, he looks at the partner, and the timer jumps to 198.
- Each frame the partner keeps looking at enemy 1 (with its field collision), and the frame runs.
- It ends when the timer has reached 200, every runner is off screen (320 × 240) and the start text has finished. Then:
  - the tamer's waypoints keep the unused part;
  - the runners leave the map;
  - the start-text burst plays (sound (0, 0x11)) to its end;
  - `GAME_STATE` = 1.

### 2.5 The main loop (`BTL_battleMain`, `battle_main.c:1832`)

The combat area is set to the screen centre (`COMBAT_AREA` from the drawing offset). Set-up, intro, then each frame until `BTL_isBattleFinished`:
1. `BTL_tickPartnerAI` (§2.7);
2. `BTL_tickEnemyAI` (§2.8);
3. `BTL_tickFighterStates` (§2.9): each fighter's state, then the hits (§2.11) and the statuses (§2.12);
4. `BTL_tickPartnerWaypointTrail`: the partner's waypoint ring follows its moves (tile changes; `isFiveTileWidePathBlocked`);
5. the frame: the objects' ticks, then their draws. In order:
   - the tamer (§2.6);
   - the partner and the NPCs: animation only; an NPC with `animFlag & 4` ticks twice;
   - the effect engine (`specs/battle_effects.md`);
   - the HUD pieces;
   - the HP bars' draw, which also applies the damage (§2.11);
6. the pause (`handlePause`, `specs/pause.md`);
7. `BATTLE_FRAME_COUNT` + 1.

**The end test** (`BTL_isBattleFinished`):
- **Ran away:** `FLEE_TIMER` ≥ 41 and the partner alive (`HP − hpDamageBuffer` > 0) → over.
- **Getting up** (partner animation 0x2C, after a revive item): the countdown resets. When the animation ends:
  - the partner's dead flag and `isHit` clear;
  - a finisher in progress is cancelled (aura removed, `NO_AI_FLAG` 0);
  - every fighter's cooldown is 0 and its flags 0x40, 0x400, 0x800, 0x1000, 0x2000 clear;
  - `moveRange` 0 for the living.
- **Fainted** (partner animation 0x2B, finished): the countdown counts while the tamer holds no thrown item. At 20 the countdown sprite appears (§4); at 171 → over (lost).
- **Won:** every enemy in animation 0x2B, finished, and the partner alive → over.

After the loop: the pause box closes, `BTL_deinitializeCombat` (§2.15). The result is −1 if the partner's HP is 0, 0 if the current command is Run (1), else 1.

### 2.6 The tamer and the commands (`tamerTickBattle`, `handleCommands`)

While fighting (`GAME_STATE` 1) and not running away:
- ✕ (`CANCEL_BUTTON`, US) opens the inventory (`addInventoryUI`), unless the battle is tamerless.
- The tamer looks at the partner. With no box 0 open: animation 0xA while the partner's finisher runs; else 1 (after 6 / 0xE end). After 171 frames of animation 1 it restarts 1.
- Select (0x100) toggles the enemy life bars (§4).
- `handleCommands`: nothing in a tamerless battle, or while box 0 (the inventory) is open.
  - **Running away** (current command 1): at `FLEE_TIMER` 20, with the partner alive, `fadeToBlack(20)`; `handleFleeing` (§2.14); `FLEE_TIMER` + 1.
  - **Left (0x8000) / Right (0x2000):** the hovered command + 1 / − 1 with wrap-around, skipping index 1 (Run) when `FLEE_DISABLED[0]`; sound (0, 2).
  - **○ (`CONFIRM_BUTTON`):** sound (0, 3). Nothing more if no enemy is left. The tamer plays 0xE (pointing). `bufferedCommand` = `availableCommands[hovered]`.
    - **Quirk:** the discipline delay is computed (`0xA0 − discipline / 10` below 70, else `(10 − discipline / 10)·10`) and then overwritten with 0. So orders always take effect at the partner's next tick. The port keeps 0.
    - Run: current command = 1 at once. On the start tile the tamer looks 3000 units out of the map entry's warp (`MAP_WARPS[CURRENT_EXIT]`, rotation + 0x800). Animation 3.
    - Change (7): `changeTarget` = 1.
    - The shout (§4).
  - **□ (0x80):** if the partner's finisher gauge is full (`finisherProgress == finisherGoal`): buffered = current = 11, sound (0, 3), the shout.

**The commands:**

| Id | Name (shout) | Partner |
|---|---|---|
| 1 | Run | runs to the tamer, stops off screen (§2.14) |
| 2 | Attack | strongest technique (power), charge mode 0 |
| 3 | Your Call | its own choice (§2.7), its saved charge mode |
| 4 | Moderate | cheapest technique (MP), charge mode 2 |
| 5 | Distance | keeps away from its target |
| 6 | Defensive | stands, looking at its target |
| 7 | Change | switches target |
| 8–10 | technique slot 0–2 | that technique |
| 11 | finisher | the finisher (slot 3) |

### 2.7 The partner's AI (`BTL_tickPartnerAI`, `battle_main.c:306`)

Each frame, fighter 0:
1. With `commandDelay` 0, current command = buffered (else the delay counts down while free).
2. Without a finisher running (`NO_AI_FLAG` 0):
   - **Distracted** ("senile", flag 0x2000): with HP above its damage buffer and brain < 301, every `(brain / 2 + 1)·20` frames, if `70 − discipline > randomLimit(100)`: distracted for 100 frames (animation 0x13, ignores orders, §2.9).
   - The cooldown counts down (to 1).
   - The speed buffer fills, unless distracted: + `speed / 100 + 1` every second frame, up to 100 (`BTL_increaseSpeedBuffer`).
3. Knocked back, attacking, blocking or dead (0x10, 0x20, 0x80, 0x8000): stop.
4. HP 0: faint (`BTL_faintDigimon`: `isHit` 1, dead flag, animation 0x2B, flatten undone, statuses removed, flags reset, `moveRange` −1) and stop.
5. No enemy left: idle, `moveRange` −1, flatten undone, statuses removed, flags = 0x40 only. Stop.
6. A finisher running: stop.
7. Free (not confused, stunned, flattened or dead, and `flatTimer` 0), by current command:
   - **7 Change** (with a target and `changeTarget` 1): 2 enemies → the other; 3 → the nearest at first, then cycling through the ones not just used (`unk5[2]`, `unk7`); `changeTarget` 0; stop.
   - **8–10:** if that slot is usable (§2.10): retarget if the target is down, queue it (unless already queued with `moveRange` > 0), apply its charge requirement; stop.
   - **11:** retarget if the target is down; queue slot 3 unless already queued; stop.
   - Other than 2 and 4: charge mode back to the saved one.
8. Flattened: every 100 frames, a random living enemy as target.
9. Busy with a queued technique (0x40): stop.
10. Command 1: `moveRange` 1, flag 0x40.
11. Flattened: `queuedAnim` 0, target choice (§2.10), `moveRange` 2, `flatSprite` 0, flag 0x40; stop. Stunned: stop. Confused: a random technique (`BTL_selectConfusedMove`: 70 % no target, else a random living enemy; a random usable slot or the 80-frame charge-up); stop. Charging, cooling down or distracted: stop.
12. Unless flag 0x400 (a target given by being hit), choose a target (`BTL_selectFighterTarget`, §2.10).
13. Command 2 / 4: no usable technique → charge-up 80 frames; else the strongest (power; ties → most effective by element; ties → random) or the cheapest (MP; same tie rules), with charge mode 0 / 2. Otherwise "Your Call" (`BTL_selectPartnerMove`, §2.10). Queue it.

### 2.8 The enemies' AI (`BTL_tickEnemyAI`, `battle_main.c:515`)

Every 20 frames every fighter's `buffPrioTimer` − 1 (to 0). For each enemy:
- Without a finisher running: distracted as the partner, with the chance `(300 − brain) / 4 > randomLimit(100)`; the speed buffer; the cooldown.
- Knocked back, attacking, blocking, dead: skip. HP 0: faint. HP ≤ its damage buffer (dying): idle, `moveRange` −1, flatten undone, statuses removed and cleared.
- The partner at HP 0: idle, flatten undone, flag 0x40, `moveRange` −1.
- A finisher running: **return** (the remaining enemies skip this frame too). Busy (0x40): skip.
- Flattened: `queuedAnim` 0, target 0, `moveRange` 2, animation 0x23, `flatSprite` 0, flag 0x40. Stunned: skip. Confused: a random technique. Distracted, charging, cooling down: skip.
- Free: if its slot 3 is a finisher and its gauge is full: target the partner, queue slot 3, gauge 0.
- Unless 0x400: target = the partner.
- Charge mode: 2 if its bone 1 is off screen (200 × 160 box), else `randomLimit(2)`.
- `BTL_selectEnemyMove` (§2.10).

### 2.9 Fighter states and movement (`BTL_tickFighterStates`, `battle_main.c:648`)

`FLEE_DISABLED[1]` (the shared cooldown, §2.10) − 1. For each fighter: its finisher gauge + 1, then by flags:
- **Attacking (0x20)** → `BTL_tickAttackState`: while the attack animation plays, it is held (`animFlag` bit 0 cleared) if another fighter is countering (technique 0x2D) at it. Then `BTL_tickFighterAction`.
- **Knocked back / blocking (0x10 / 0x80)** → `BTL_tickHitState`: `BTL_tickFighterAction`; once the animation is done, the invulnerability counts down and re-holds it until 0.
- **Else, unless `moveRange` −1:** flattened → `BTL_tickFlatState`; stunned → animation 0x22; confused → `BTL_tickConfusedState`; distracted → `BTL_tickSenileState` (animation 0x13, 100 frames); charging → `BTL_tickChargeState`; cooling down → `BTL_tickCooldownState`; else `BTL_tickQueuedMove`.

**`BTL_tickFighterAction`** (the end of an action):
- the collision probe sets / clears `animFlag` bit 1;
- the flattened attack's timer (0x1C: aura projectile, 0xA: sprite 0, 0: animation released);
- when the animation ends: the finisher is over (`NO_AI_FLAG` 0);
- after an attack: `hitCount` + 1 (partner), flag 0x400 cleared, cooldown 40 frames (0x1000), finisher gauge + `goal·2 / 50`;
- once the invulnerability is out, the knock-back / attack / block flags clear;
- `flatTimer` −1 → 0x41 (the flatten starts).

**Moving** (all with the combat area 0x118 × 0xC8, screen pixels around `COMBAT_AREA`, and the entity collisions):
- **Walking animation:** 0x23 when HP ≤ max / 5 or poisoned, else 0x24. **Idle:** 0x22 when weak or poisoned, else 0x21.
- **Melee (range 1)** `BTL_tickMeleeAttack`:
  - Out of contact (`(radius_a + radius_b)²`): walk at the target, with `collisionGrace` on a block.
  - In contact: go idle, then start the technique (§2.10). A finisher first starts its 80-frame wind-up: `NO_AI_FLAG` 1, `FINISHING_ENTITY`, the aura, the partner's charge-up gauge (§4).
- **Ranged (2, 3)** `BTL_tickRangedAttack`, with `total = distance² + (radius_a + radius_b)²`:
  - farther than `total·1.3`: walk closer;
  - nearer than `total·0.7`: back away;
  - in between: start (a flattened fighter only every 40 frames).
  - After 80 frames without reaching the band (`unk15`): start anyway.
- **Self (4):** idle, start at once.
- **Charging** `BTL_tickChargeState`, by charge mode, while waiting for the speed buffer (§2.10):
  - 0: keep the distance band;
  - 1: stand and look at the target;
  - 2: back away.

  With a cooldown set (the 80-frame "no usable technique" wait) it runs until the cooldown reaches 1.
- **Cooling down:** keep the distance (modes 0 / 1) or back away (2) until the cooldown is 1.
- **Distance band** `BTL_maintainDistanceRange`: contact² = `(radius_a + radius_b + 200)²`; band `[contact + near, contact + far]`: (0x27100, 0x4E200) while walking (0x23 / 0x24), else (0, 0x75300).
- **Backing away** `BTL_backAwayFromTarget`: turn away from the target (first time), else steer 20 per frame, try ± 90°, else `BTL_findUnblockedRotation` (the cardinal candidates around the blocked side, then a random turn).
- **The partner's own commands** (`BTL_handlePartnerMoveCommand`, before the above):
  - Run: walk to the tamer; off screen → stop, animation 0x21;
  - Defensive: stand and look at the target;
  - Distance: back away while nearer than its target's longest technique reach + 0x9C400 (+ 0x27100 while walking).
- **Confused** `BTL_tickConfusedState`: random turns (20 % chance of ± 0x200); with no target it walks into the air and attacks the empty spot (5 % per frame); else as the queued technique.
- `entityCheckCollision` in battle: the tamer is no obstacle for a walking fighter (0x23 / 0x24), and a Digimon at HP 0 is none either.

### 2.10 Choosing and starting a technique

- **Usable** (`BTL_isMoveUsable`):
  - the slot is set;
  - not Counter (0x2D) or a finisher;
  - a self technique only with `buffsRemaining` > 0;
  - a `needs_target` technique only with a target;
  - MP ≥ cost. The cost is `mp_cost·3`. For the partner: brain ≥ 700 cuts it by 5 / 10 / 15 / 20 % (700 / 800 / 900 / 999); injured or sick raises it by half.
- **Target** (`BTL_selectFighterTarget`):
  - **An enemy, or the partner after a hit** (`retarget` with the attacker):
    - an enemy with map `unk1` 1, or failing a 71 % roll, targets the partner;
    - else the attacker, if alive, with flag 0x400.
  - **The partner otherwise:**
    - "Change" keeps a living target;
    - brain ≥ 300: a random status-afflicted enemy if any; else the weakest (`BTL_calculateTargetScore`: HP % + inverted element factor × Def % / 10), switching only if it scores 40 below the current one;
    - brain ≥ 150: keep a living target, else the weakest;
    - else the nearest.
- **The partner's "Your Call"** (`BTL_selectPartnerMove`): weights per slot 0–2:
  - charge mode 0: rank by power, `YOUR_CALL_POWER_PRIO` 50 / 20 / 5;
  - mode 1: 20 each;
  - mode 2: rank by MP, `YOUR_CALL_MP_PRIO` 50 / 20 / 10;
  - empty slots + 5, unusable 0;
  - a self technique: + `buffPrioTimer` + the element bonus against itself;
  - others: + the element bonus against the target (`BTL_calculateElementBonus`: factor 20 / 15 / 10 / 5 / 2 → 10 / 7 / 5 / 3 / 1);
  - area (range 3) with brain ≥ 200 and ≥ 2 enemies alive: + count·10 (mode 0) or ·15;
  - mode 2 below 31 % HP: re-rank by distance (`YOUR_CALL_WIDE_PRIO`). **Quirk:** this inner loop reuses the outer `i`, which leaves the outer loop early. The port keeps it.

  Then a weighted roll; an empty slot picked → the 80-frame charge-up.
- **Enemies** (`BTL_selectEnemyMove`): weights = the map Digimon's 4 move priorities. Unusable → 0. Area + 20 when another enemy is alive and `unk1` = 0. Self + `buffPrioTimer`. Weighted roll over 4 slots. No usable technique → charge mode 2 and the 80-frame charge-up.
- **Queueing** (`BTL_setupQueuedMove`): `queuedAnim`, `moveRange` = the technique's range, the charge requirement, flag 0x40.
- **The charge requirement** (`BTL_applyChargeRequirement`), flag 0x800 until:
  - mode 0: the speed buffer is > 0;
  - mode 1: it reaches 100 or the technique's power;
  - mode 2: it is full (100).
- **Starting** (`BTL_startQueuedMove`):
  - a finisher: the wind-up (§2.9);
  - a `shared_cooldown` technique while `FLEE_DISABLED[1]` > 0: wait;
  - a target being knocked down (0x28 / 0x29): wait;
  - else look at the target, start the animation, flag 0x20, and `BTL_setupMoveExecution` (a flattened fighter waits 30 frames, `flatAttackTimer`).
- **`BTL_setupMoveExecution`:**
  - attacker and target for the effect: self for range 4; a `needs_target` technique without a target picks the partner, or the partner's last living enemy;
  - MP: the partner's cost (brain and condition rules, in the other order and rounding, `:2527–2543`) goes into `mpDamageBuffer`. An enemy pays `mp_cost·3` at once, except in a `FLEE_DISABLED[0]` battle. Finishers are free;
  - an enemy's technique < 0x3A goes into `usedMoves` (for learning, §2.15);
  - the effect slot starts (`BTL_startEFE`, `specs/battle_effects.md`);
  - a self technique uses one `buffsRemaining`;
  - speed buffer − power (minimum −155).

### 2.11 Hits and damage (`BTL_tickAttackHits`, `battle_main.c:2084`)

The effects report hits as attack objects (victim, position, effect slot, caster; `specs/battle_effects.md`). For each living fighter, one attack object a frame (none while `FLEE_TIMER` ≥ 19):
1. The victim is countering its attacker: `isHit` 0, ignored.
2. A self technique (buff, `BTL_applyBuffMove`): Off / Def / Speed rise by the technique's fractions (§6), each capped at 999, with a number shown; `isHit` 0.
3. The victim's own effect stops, its knock-back / attack / 0x40 flags clear. A finisher in progress by the victim is cancelled.
4. **Hit chance** (`BTL_calculateHitChance`):
   - always 100 when the victim is below level 3, stunned, flattened or distracted, while the partner is sick, when the victim's speed buffer is ≤ 0, or when it is in a technique animation (≥ 0x2E);
   - a finisher: 100 and it breaks a block;
   - blocking: 0;
   - else `x = accuracy / 2·(def.speed − att.speed / 10) / 999`, ×6/5 when the victim is idle (0x21 / 0x22); chance = `clamp(accuracy − x, 0, 100)`.
5. **Hit** (`randomLimit(100) < chance`):
   - retarget (the partner: if `TARGET_ATTACKER_CHANCE[mode] − discipline > roll`, or its target is down);
   - damage (`BTL_calculateDamage`, below) into `hpDamageBuffer` (≤ 9999);
   - `HAS_TAKEN_DAMAGE`; a partner hit ≥ 20 % of its max HP counts in `unk2`;
   - knock-back flag; `BTL_handleHitReaction`: face the hit (front 0x28 or back 0x29, by the hit's angle against its facing), hit particles of the technique's element (`createParticleFX`, life `iframes` + 16), a flattened victim turns to sprite 3;
   - the number (§4); invulnerability = the technique's `iframes`; the status roll (`BTL_applyMoveStatus`, §2.12).
6. **Miss:**
   - **Counter:** a melee hit on a victim that isn't blocking, knows Counter, has MP ≥ 165 and wins `randomLimit(100) < speed / level`: it counters the attacker at once.
   - Else the attack is **blocked**:
     - a new block (per attacker effect and sub-effect, `BTL_addBlockedAttack`) shows a block spark;
     - while still blocking with invulnerability left: only the invulnerability resets to 3;
     - a melee technique still does `damage·(10..30) / 100` (≥ 1) as chip damage;
     - the victim's gauge + `goal·3 / 50`, the attacker's + `goal·4 / 50`; `blockedCount` + 1 (partner);
     - the victim faces the hit, blocks (flag 0x80, animation 0x25), invulnerability 3.

**Damage** (`BTL_calculateDamage`): `m` = the sum of `TYPE_FACTORS[technique element][e]` over the victim's 3 elements (10 for an empty one). When the technique is Counter (0x2D), the victim's defence counts only `def·3 / 10`.
- A technique: `diff = clamp(off − def, −500, 500)`; `dmg = m·(power + diff·power / 500) / 30·(90..110) / 100`.
- A finisher: `(off + power)·m / 30`. Then:
  - the partner's: × charge-up / 40 when its charge-up is ≥ 41;
  - an enemy's: × (100..200) / 100;
  - then × (90..110) / 100.
- Clamped to 1..9999. The random factors are `randomLimit(21) + 90` and `randomLimit(101) + 100`. The C's integer order matters.

**The damage buffer** (`damageTick`): each frame HP drops by 900 / 80 / 6 / 1 while the buffer is above 999 / 99 / 9 / 0; at HP ≤ 0, HP and the buffer are 0. It runs in the HP bars' draw: an enemy's only while its bar is shown (§4), the partner's in its status bars, where the MP buffer is also taken off at once. A fighter is "defeated" for targeting as soon as `HP − hpDamageBuffer` ≤ 0.

### 2.12 Statuses (`BTL_tickStatusEffects`, `BTL_applyMoveStatus`)

On a hit, unless the victim is protected (flag 0x100), with `randomLimit(100) < status_chance`:
- **Poison:** timer 100. Every 100 frames `max HP·(1..3) / 100` into the damage buffer, with a number in colour 0xC.
- **Confusion:** timer 200–300.
- **Stun:** timer 200–240.
- **Flatten:** `flatTimer` −1, which `BTL_tickFighterAction` turns into 0x41. The squash animation runs as the timer falls (`BTL_applyFlattenScale`). At 0x40 the fighter stops (animation 0x22). At 3 its sprite shows. At 0 it is flattened for `randomLimit(81) + 224` frames as a flat sprite that only fires aura projectiles. Then the reverse runs and the other statuses' visuals return.

A partner status counts in `statusedCount`. Timers don't run during a finisher. One visual at a time (`statusFxId`), by priority: flatten > stun > confusion > poison. Curing items (`BTL_healStatusEffect`) clear them all, with the buff-rings effect.

### 2.13 Finishers

- Ids 0x3A–0x70 (category `finisher`), in slot 3. The gauge (`finisherProgress` up to `finisherGoal` = 3000 − speed) fills:
  - + 1 a frame (only if slot 3 holds a finisher);
  - + `goal·2 / 50` per attack ended;
  - + `goal·3 / 50` per block;
  - + `goal·4 / 50` for an attacker that was blocked.
- The partner's starts with □ when full (command 11); an enemy's starts by itself when full.
- **Wind-up:** `NO_AI_FLAG` 1 and `FINISHING_ENTITY`: every other fighter idles, timers and AI pause. The finisher animation is held. The aura shows (`BTL_addFinisherAura`). `BTL_FINISHER_TIMER` = 80 frames of looking at the target.
  - The partner's charge-up gauge: L1 / R1 (bits 0x4 / 0x8, pressed) + 2 each, up to 80, for 80 frames. Damage × charge / 40 from 41.
  - Then the technique runs. Finishers cost nothing and always hit.
- The flag clears when the animation ends, or when the finisher's user is hit.

### 2.14 Running away (`handleFleeing`)

Command 1: the partner runs to the tamer and stops off screen. The tamer runs back along his waypoints (last first: `TAMER_WAYPOINT_COUNT − 1` down), then to his start tile. From there he heads 3000 units out of the map entry's warp, with the collision off (`animFlag |= 2`). At `FLEE_TIMER` 20 the screen fades to black; at 41 the battle is over (outcome 0). Hits stop counting from 19.

**The tamer's waypoints** (`tickTamerWaypoints`, run by his walking state): on each tile change, if the straight path back to the start tile (the map entry's tile, `initializeTamerWaypoints` at map load) is blocked, the previous tile is added (when the path to the last waypoint is blocked too), else they are cleared. A shortcut check keeps the list short. The field doesn't keep these yet: this step ports them (`GameState` already saves them).

### 2.15 The end (`BTL_deinitializeCombat`, `BTL_handleVictorySequence`, `handleBattleEndBox`)

- The partner's charge mode is restored. `GAME_STATE` 2. Every battle object and effect is removed, and the inventory boxes close.
- Per fighter: flatten undone, statuses removed, flags 0. **Enemies** get back their starting HP (as current HP), MP and Off / Def / Speed / Brains.
- **Won** (partner HP > 0, not running):
  1. tamer animation 1, partner 0x21; the music and sounds stop; sound (0, 0x15); the map's sound set reloads. Wait 41 frames at least.
  2. Sound (0, 0x18); tamer animation 0xB, partner 0x2A (the victory pose). Wait for both to end; the partner then idles.
  3. **The end box** (`handleBattleEndBox`):
     - bits = the sum of the enemies' map `bits`;
     - **stat gains** (`battleStatsGainsAndDrops`): for each stat, `e` = the best enemy's starting value, `p` = the partner's, `f` = `STAT_GAIN_ENEMY_FACTORS[enemies − 1]` (10 / 12 / 16). With `d = p·10` (10 when p is 0): if `e ≥ p`, gain `(d + e·f − 1) / d`; else 1 with chance `e·f·100 / d` %. A stat still at 0 gets a second roll:
       - HP: `(startingHP − HP)·100 / max HP`;
       - MP and Off: hits·10;
       - Def: big hits (`unk2`)·10;
       - Speed: blocks·10 + `(startingHP − HP)·50 / max HP`;
       - Brains: hits·5 + big hits·5;
     - **drops:** each enemy drops its `drop_item` if `drop_chance > randomLimit(100)`; none on map 0x8F;
     - the box text, in order: "<Digimon> dropped <item>" per drop; "<partner> was injured" (if not injured yet and damaged: injury if `randomLimit(100) < tiredness − HP %`, condition 0x20); the new command at brain 100 / 200 / 300 / 400 / 500 crossed ("… listens to …"); the MP discount at brain 700 / 800 / 900 / 999 crossed; a learnt technique (`battleMoveLearning`: among the enemies' used techniques not known, of one of the partner's elements and in its move list, each kept with `MOVE_LEARN_CHANCES[id][element slot]` %, one at random is learnt);
     - the stats box (gains added one by one, or at once with ○ / ✕) and the bits box (counted into `MONEY` one per frame with sound (0, 0x16), or at once; ≤ 999,999; sound (0, 0x17) at the end); the final balance box; the text scrolled to its end;
     - the dropped items appear at the enemies' places (`spawnDroppedItems`, `MapItems`);
     - the partner's base stats are reset from `INITIAL_COMBAT_STATS[0]`, into which the gains were added (`resetStatsAfterCombat`: this also undoes buffs and the injury penalty). HP / MP max ≤ 9999, the others ≤ 999.
  4. The enemies play 0x2C (get up). In a `FLEE_DISABLED[0]` battle they wait for it and idle. Otherwise they run (0x24, double speed) to their flee points until all are off screen.
- **Lost or ran:** the base stats are reset, the countdown and numbers removed.
- The command menu closes (frames run until it has slid out). The partner's status bars go.
- **The other NPCs:** with `FLEE_DISABLED[0]`, every non-fighter on screen leaves the map and those off screen come back. Otherwise every NPC on screen leaves (`animFlag` bit 2 cleared) and those off screen come back. So the defeated enemies are gone from the map until it reloads.
- The music and sounds stop.

### 2.16 Back in the field (`startBattle`, `tamer.c:832`)

Before the battle: `GAME_STATE` 1, the tamer's position saved, the camera stops following, the △ menu closes, game time stops. After: `GAME_STATE` 0, then by outcome:
- **−1 lost:** happiness − 30, discipline − 20, `partnerSetState(−1)`, no daytime fade (`SKIP_DAYTIME_TRANSITION`).
- **0 ran:** happiness − 10, discipline − 6, tiredness + 2, `handlePostBattleTiredness`, no daytime fade.
- **1 won:** the map music back (`playBGM(ACTIVE_BGM_FONT)`), the map's TFS reloaded, the tamer's position saved, partner state 1, happiness + 2, `handlePostBattleTiredness`, `battles` + 1, daytime fades allowed.

Then `tickConditionBoundaries`, and **`advanceBattleTime`**: + 20 minutes and `CURRENT_FRAME` + 400.
- On an hour change: lifetime − 1 (≥ 0); while sleepy the sleep counters + 1; while sick the sickness tries and timer + 1; while injured the injury timer + 1; the day / year roll over.
- Hungry: `starvationTimer` − 40, and a care mistake if it reaches ≤ 0 with energy below the threshold. Else food − 20.
- Poopy: `poopingTimer` − 400, else `poopLevel` − 2.
- The clock hand.
- Won, on a map with time of day: the daytime fade at 16:00, 20:00 or 6:00 (`initializeDaytimeTransition` 0 / 1 / 2).

### 2.17 The script (`START_BATTLE`)

- `BATTLES_STARTED` + 1 (≤ 9999). Predefined enemies' script ids → entity ids (0xFB–0xFD). `stopBGM`. The battle. Script value 0xFF = the outcome.
- **−1:** `handleItemLoss`, lives − 1 (at 0: `remainingLifetime` 0), and the script jumps to script 0, section 0x4DE (the collapse / battle loss: step 6).
- **0:** `BATTLES_FLED` + 1. A script map change back to the previous map (`PREVIOUS_SCREEN`, `PREVIOUS_EXIT`; no map name; the stack entry {4, 0xFF} and `longjmp` 3, as `specs/script.md` §2 runs for `WARP_TO`).
- **1:** with trigger 1, movement is enabled again and the text box reset. Else the camera moves back to the tamer: slot 10, type 7, entity 0xFD, speed 10 (`specs/camera.md`), and the script waits for it (`WAIT_FOR_ENTITY` 10).

### 2.18 Items in battle

- Box 0 open (the inventory) pauses the commands, not the fight.
- Use with `GAME_STATE` 1 throws the item (`startThrowingItem`): the tamer plays 6 and the item is removed. The item rides the tamer's hand (bone 9) until frame 7 of the animation. Then it flies to the partner over 24 frames (`ITEM_THROW_HEIGHT` arc). On arrival its item function runs with the battle branches, then the item particles show.
- The battle branches (`item.c:2220–2390`, `GAME_STATE` 1):
  - status cures (`BTL_healStatusEffect(1)`);
  - Restore revives a fainted partner (animation 0x2C);
  - buff disks raise Off / Def / Speed up to 1.3 × the starting stat (`specs/items.md`);
  - the inventory's battle colours and the Drop option greyed out.
- The death countdown pauses while an item is in the air.

## 3. The effects

Each technique is an effect script run by the effect engine (`specs/battle_effects.md`). The engine draws the technique and reports its hits as attack objects, which §2.11 resolves. The battle logic only starts an effect (`BTL_startEFE`) and stops one (`BTL_stopEFESubEffect`). The status, finisher-aura, buff, item-particle and aura-projectile visuals belong to the same file in the C and to the same spec in the port.

**In the port every technique effect is an instantiated scene behind one API** (`BattleEffect`, `specs/battle_effects.md` §3.0–3.1), so techniques can be modded: the battle creates one per loaded technique, calls `start` / `stop` / `tick` / `draw` in its frame order, gives it a context to read the fighters, and receives `hit(victim, position, sub_effect)` signals. It never computes damage in the effect. The original techniques are the default implementation (`EfeEffect`, the bytecode VM); a move record may name another scene (`effect_scene`).

## 4. The HUD

All in the original's 2D layer at 320 × 240, built on `UIBoxes` / `TextArea` / `PsxDraw` (`docs/ui.md`). VRAM coordinates are the C's. The images come from the system textures the menus already load.
- **Command menu** (`command_menu.c`): icons in a row (`BTL_COMMAND_MENU_LAYOUTS`, the icon UVs `BTL_COMMAND_ICON_UVS`; a technique command shows its element icon, `BTL_SPECIAL_ICON_UVS`). It slides in (`SLIDE_Y` then `SLIDE_X`, 7 steps each) and out at the end. The cursor blinks every 8 frames while fighting. The hovered command's name is shown (`BTL_drawHoveredCommandName`).
- **Shout** (`command_shout.c`): the order's text ("Run!", "Attack!", …) over the tamer with a hop / drop motion (`BTL_SHOUT_HOP_OFFSETS`, `DROP_OFFSETS`).
- **Partner status bars** (`battle_hud.c:969–1080`): HP / MP bars sliding in with the menu, the numbers (`BTL_renderNumber`), the finisher gauge in segments with its pulse when full and the "ready" icon. Their draw applies the partner's damage and MP buffers (§2.11).
- **Enemy HP bars** (`BTL_renderEnemyHPBars`): a 50-px bar beside each enemy's head with a leader line, colour from green to red, and the HP number. Shown for 21 frames after its last damage, or always with the Select toggle (dead ones excepted). The draw applies the enemy's damage buffer.
- **Numbers over the fighters** (`entity_text.c`): damage (colour 0), poison (0xC), buffs (0xB).
- **Start text and burst** (`BTL_initializeBattleStartText`, `…Burst`): the pieces of `BTL_BATTLE_START_TEXT_PIECES` flying in at the positions of `BTL_BATTLE_START_TEXT_POSITIONS`, then the burst.
- **Finisher charge-up** (`command_menu.c:360–452`): the gauge over the partner (46 × 12 frame, 4-px bars per 8 points).
- **Death countdown** (`command_menu.c:454–580`): the spinning digit over the partner.
- **Flee bubbles** (§2.1).
- **End boxes** (`battle_ui.c`, `battle_hud.c:245–530`): the text box with its scroll, the stats box, the bits box, the final balance.

## 5. Godot design

### 5.0 Design choice: composition and instantiation (decided 2026-10-26)

Battles are meant to be modded later (techniques first, then visuals and HUD). So, following `specs/scenes.md` §3: **whatever a mod may want to replace or extend is an instantiated scene with a small API, created by the battle and talking back with signals**; the C's rules stay in plain classes that only the scenes' defaults use. In this spec that means:
- each technique effect is a `BattleEffect` scene (§3, `specs/battle_effects.md` §3.0), chosen per move;
- each status / aura / buff / item visual is its own scene (`specs/battle_effects.md` §4);
- each HUD piece is its own scene (§5.2);
- the fighters stay the field's entity scenes (`Partner.tscn`, `Npc.tscn`), with battle behaviour added to them rather than new fighter objects.

What stays code (not a mod point): the battle's rules, its phases and the frame order (§5.4).

### 5.1 Logic (headless, tested)

- **`Battle`** (`scripts/systems/battle/battle.gd`, `RefCounted`): every `BTL_*` function of `battle_setup.c` and `battle_main.c`, and the battle parts of `battle_tick.c`, `battle_ui.c`, `btl.c` and `startBattle`, under the C names in snake case. References: `game_state`, `data`, `rng`, `pad`, `sound`, `effects` (the `EffectHost`, which creates and runs the effect scenes and holds the attack-object queue, `specs/battle_effects.md` §3.2), the field's `entities`, `tamer`, `field_map` (tiles, collision, screen projection). It owns the `BattleEffectContext` the effects read. It holds the globals (`NO_AI_FLAG`, `FINISHING_ENTITY`, `FLEE_TIMER`, `BATTLE_FRAME_COUNT`, `FLEE_DISABLED[2]`, `INITIAL_COMBAT_STATS`, …).
- **`BattleFighter`** (`FighterData`) and **`BattlePlayer`** (`PlayerData`): plain data with the C's fields and flag constants (`FLAG_POISONED` … `FLAG_DEAD`).
- **The blocking loops become phases.** `Battle.frame()` runs one original frame:
  - `LOADING` (§2.2): the loading frames, enemies looking at the partner, the partner running in;
  - `INTRO` (§2.4) and `INTRO_BURST`;
  - `FIGHT` (§2.5);
  - `VICTORY_WAIT` / `VICTORY_POSE` / `END_BOX` sub-phases / `ENEMIES_LEAVE` (§2.15);
  - `MENU_CLOSE`;
  - `DONE`, with the outcome.

  Each phase does what one pass of its C loop does, in the same order, then the object frame (§5.3). No `await`. Every phase is testable frame by frame.
- **Fighters are the field entities.** `FieldDigimon` gets a battle-stats view (`base` HP / MP / Off / Def / Speed / Brains and the 4 moves with their priorities, `current` HP / MP, `charge_mode`, `vab_id`, `is_hit`, `efe_sub_effect`, `unk1`, `flat_sprite`, scale). The partner reads and writes `GameState`. An NPC reads its map record's battle stats (`Npc`: copied at spawn like the C's `NPC_ENTITIES`). The battle animations (0x21–0x2C, 0x2E + slot) play through `PsxAnimator` as today.
- **Collision:** `FieldDigimon.check_collision` gains the combat-area box (result 11, `entityCheckCombatArea` through `FieldMap.unproject`) and the battle exceptions (§2.9). `collision_grace` is reused.
- **Tamer:** `tamer_tick_battle` (§2.6), the waypoint trail (`tickTamerWaypoints`) in his walking state, `handle_fleeing`.
- **Items:** `ItemUse` gets the "battle" context (the battle branches of the handlers it already names, §2.18). The thrown item is a small object owned by `Battle`.

### 5.2 Scenes

```
BattleHost (Systems/BattleHost)    starts a battle for START_BATTLE, owns Battle and its EffectHost, runs its frame
scenes/battle/battle_hud.tscn      CanvasLayer: CommandMenu, CommandShout, PartnerStatusBars, EnemyHpBars,
                                   EntityNumbers, StartText, FinisherChargeup, DeathCountdown, FleeBubbles, EndBoxes
                                   (each its own scene)
scenes/battle/effects/             battle_effect.tscn (the API), efe_effect.tscn + efe_view.tscn (the original
                                   techniques); one instance per loaded technique, in the 3D world while the battle runs
scenes/battle/fx/                  the status / aura / buff / item visuals, one scene each
```

Each HUD piece is its own scene with a script that draws one C object from `Battle`'s state (no logic of its own beyond the C's tick of that object), so a mod can restyle it. They are added to the field's `Hud` while a battle runs and freed after it.

### 5.3 The frame

`Field._frame` checks `BattleHost.active` first. During a battle it calls only `battle_host.frame()`, as the original runs only the battle loop. The script, clock, care, menus and NPC AI stay frozen. `frame()` runs:
1. `Battle.frame()` (the phase's logic, §2.5 steps 1–4);
2. the object ticks in the C's list order: the tamer's battle tick, the partner's and the NPCs' animation ticks, `EffectHost.tick()` (each effect scene's `tick()` in slot order), the battle visuals' and HUD pieces' ticks;
3. the object draws that change state: the HP bars' damage application, `EffectHost.draw()` (each effect's `draw()`).

`START_BATTLE` in `ScriptInterpreter` asks the field to start a battle and waits (a wait instruction like `WAIT_FOR_ENTITY`). When `Battle` is `DONE`, `BattleHost` runs `startBattle`'s tail (§2.16) and hands the outcome back. The interpreter writes 0xFF and runs §2.17.

### 5.4 What stays code, what is data

- **Data (§6):** every table of §1, the technique properties (category, range, flags, buff fractions), the per-Digimon battle music and size, the map properties, the Digimon types for the flee table.
- **Code:** the formulas and their integer order, the state machine and its frame counts, the animation ids 0x21–0x2E (the model contract), the HUD layouts.

## 6. Data and assets

**Data porter** (new or extended, each checked against the C text):
- `move_data`: `buff {off, def, speed}` as integer fractions `[num, den]` for the 5 self techniques (`BTL_applyBuffMove`: 0x29 Off 3/10; 0x2A Off 1/10, Def 5/100, Speed 1/10; 0x22 Def 1/5, Speed 1/10; 0x15 Off 7/100, Def 8/100, Speed 7/100; 0x1E Off 1/4, Def 3/20, Speed 3/20). The logic reads `buff`, not the ids. Also the optional `effect_scene` (the technique's `BattleEffect` scene, `specs/battle_effects.md` §3.0): never set for `dw1`, read by the battle, documented for mods. `category` already marks `finisher`; new: a `counter` flag on 0x2D (`BTL_isMoveUsable`, `BTL_tickAttackHits`, `BTL_calculateDamage`), so the logic doesn't name 0x2D.
- `digimon_data`:
  - `battle_music` (0–3) from `ENEMY_MUSIC_MAPPING`, 1 for types outside 0x43–0x6F, 3 for 0x73;
  - `battle_scale` (0x1000, or 0x1800 for type 0x71: `BTL_resetFlatten`, `tickStatusEffects`);
  - `anim_technique` overrides (type 0x3C: animation 0x3C → technique 0x70, `entityGetTechFromAnim`).
- `maps`: `concave` (`CONCAVE_SCREENS`), `no_battle_drops` (map 0x8F, `battleStatsGainsAndDrops`).
- `systems`: the command lists per count (§2.3), `ITEM_THROW_HEIGHT`, the HUD tables (`BTL_COMMAND_MENU_LAYOUTS`, `SLIDE_X / Y`, `BTL_COMMAND_ICON_UVS`, `BTL_SPECIAL_ICON_UVS`, `BTL_STATUS_BAR_X`, `BTL_STATUS_BAR_SPRITES`, `BTL_FINISHER_PULSE`, `BTL_SHOUT_*_OFFSETS`, `BTL_BATTLE_START_TEXT_PIECES / POSITIONS`, `FLEE_BUBBLE_SCALE`, the countdown digit UVs) as one `battle_hud` record.
- `systems/psx_math`: the sine and arctangent lookup tables (`include/dw/sin_lookup_table.h`, `atan_lookup_table.h`) for `PsxMath` (`specs/battle_effects.md` §3.2).
- Text: `text/btl/*.yaml`, `text/main/battle_ui.yaml` (already in the text group; checked).

**Asset porter:**
- `map.json` `digimon[].unk1` named `targets_partner` (1: never retargets an attacker; 0: favours area techniques, §2.10). Its other battle fields are already exported.
- New family `btl_rel` (`BTL_REL.BIN`, segments in `config/us/btl.yaml`):
  - the TIM at 0x0 (finisher aura texture);
  - the TMDs at 0xD20 (finisher aura), 0x1D58 (confusion), 0x2220 (stun), 0x2848 (buff);
  - glTF + textures like `tmd_files`.
- `efe`: also the raw slot bytes (`effect.bin`, 0x5000), which the effect VM runs on (`specs/battle_effects.md` §3).

## 7. Order of work

1. **5d-1, data and assets** (§6): the porters, `GameData` accessors, checks.
2. **5d-2, the effect VM, logic part** (`specs/battle_effects.md` §5 step 1): it runs every technique's scripts headless and produces its hits.
3. **5d-3, the battle logic and the field hook-up**: `Battle`, `BattleFighter`, `BattleHost`, the phases, the tamer's waypoints and battle tick, collision, `START_BATTLE` and the outcomes, care and time after, rewards (logic), items in battle. A plain HUD (command menu, HP numbers, the end texts in a `MessageBox`) so the battle can be played. `tests/test_battle.gd`, VERIFY "Battles".
4. **5d-4, the HUD** (§4), each piece as the original draws it.
5. **5d-5, the effects' drawing** (`specs/battle_effects.md` §5 steps 2–3): the techniques, then the status, aura, buff and item visuals.

Then step 6 (death and lives) picks up section 0x4DE, and 4e reuses `Battle` for the arena.

## 8. Tests (`tests/test_battle.gd`, with stub fighters and a seeded `Rng`)

- **Start:** the join roll with the repel / bell, `FLEE_DISABLED`, a type-0xFF partner, the 3-enemy cap, off-screen NPCs leaving, concave maps' line of sight, predefined enemies; the music choice; slots whose animation has no technique are cleared; effect slots per (fighter, slot).
- **Set-up:** buffs remaining / priority / goal by stats; the command lists for each brain band and the 9-command technique slots; the injury penalty and its reset.
- **AI:** distraction chance and period; the speed buffer; the partner's target rules per brain band; "Your Call" weights (each charge mode, area bonus, the mode-2 quirk) with a seeded roll; Attack / Moderate tie-breaks; enemy weights with `unk1`; the confused choice.
- **Techniques:** usability (MP with the brain and condition factors, buffs left, needs-target, Counter / finisher excluded); the charge requirement per mode; the shared cooldown; MP payment (partner buffer, enemy direct, `FLEE_DISABLED[0]`); `usedMoves`; speed buffer − power.
- **Movement** (a flat test map): melee contact, the ranged band and its 80-frame give-up, backing away, the combat-area stop (11).
- **Hits:** hit chance branches; damage for a technique, Counter and a finisher (partner charge-up, enemy factor) against hand-worked values; clamps; block, chip damage, gauge gains; counters; hit reaction front / back; buffs from self techniques; `damageTick` steps; the enemy bar gate.
- **Statuses:** each status's timers, poison ticks, the flatten timeline (0x41 → 0x40 → 3 → 0 → flat 224–304 → back), visual priority, cures; no timers during a finisher.
- **Finishers:** gauge gains; wind-up 80 frames; charge-up presses; AI frozen; cancel on hit.
- **End:** each end-test branch (ran at 41, countdown 171 with the item pause, revive at 0x2C, all enemies down); the outcome values; enemies restored; stat gains (both formulas, second rolls), drops and map 0x8F, injury, learning with `MOVE_LEARN_CHANCES`, the command / MP texts at the thresholds; bits to `MONEY` with the cap; the base-stat reset.
- **Field:** `startBattle`'s care per outcome; `advanceBattleTime` (hour roll-over effects, hunger / poop, daytime fade on a win); `START_BATTLE`'s counters and script value 0xFF; ran → the map change to the previous map; lost → item loss, lives, section 0x4DE; won → the camera slot 10 wait; the tamer's waypoints; a whole battle against a real map's wild Digimon run headless to a win with a seeded roll.

VERIFY gets "Battles": walk into a wild Digimon on a map near File City, watch the start (bubbles, runners, the tamer backing off), give each command, throw a recovery item, win and read the end box, run from another, lose one with a weak partner (it reaches the 0x4DE stand-in).

## 9. Open points

- **Loading length** (§2.2): the original's loading frames are CD time. Decided (2026-10-26): the port shows the flee bubbles and the run-in for a fixed 40 frames. To compare with the game later.
- **The discipline delay** is dead code in the US release (§2.6). The port keeps it at 0; an option could restore it later.
- **`unk2` / `unk5` / `unk7` and `PlayerDataSub`** keep the C names until their use is clear (`unk25` is the enemy bar's visibility timer).
- **The pause** in battle: ported (`specs/pause.md`, while the phase is `FIGHT`).
- **Map `unk1`** of the NPC record: its name `targets_partner` is from its two uses here; to confirm on maps where it is 1.
- **The arena** (`std`) copies this code with changes: when 4e comes, `Battle` gets an arena mode rather than a copy.

## As built (5d-3, 2026-10-26)

- **Logic** (`scripts/systems/battle/`, headless):
  - `Battle` (`battle.gd`): `battle_setup.c` and `battle_main.c` under the C names: set-up, both AIs, the fighter states, movement (melee, ranged band, backing away, `BTL_findUnblockedRotation`), choosing / starting techniques, hits, damage, statuses, finishers, the damage buffers. It reads properties: `category` finisher, `counter`, `buff`, `flags`, `battle_scale`, `anim_technique`, the command lists. Visual and HUD events go out through `visual(kind, args)`.
  - `BattleFighter` (`FighterData`), `BattleRewards` (`battle_ui.c`: gains, drops, injury, the texts, learning, the stats / bits counting), `BattleStartText` (the start text's motion, which ends the intro and draws random numbers).
  - `BattleSession`: the C's blocking loops as phases (`LOADING` 40 frames, `INTRO`, `INTRO_BURST`, `FIGHT`, `VICTORY_WAIT`, `VICTORY_POSE`, `END_BOX`, `ENEMIES_UP` / `ENEMIES_LEAVE`, `MENU_CLOSE`, `DONE`), `handleBattleStart`, `loadBattleData`, `tamerTickBattle`, `handleCommands`, `handleFleeing`, `BTL_isBattleFinished`, `BTL_deinitializeCombat`.
  - `BattleWorld` (extends `BattleEffectContext`): everything the logic reads or changes in the world.
- **Field** (`scripts/field/`):
  - `FieldBattleWorld`: the world on the field's entities, map, camera, `GameState` and `Sound`. NPC stats come from their map record into the slot (`stats`, the partner's layout), and last for the map visit as `NPC_ENTITIES` does. `entityCheckCombatArea` tests the two corners the C's loop reads (it indexes `QUADRANTS[i]` for `i` 0–1 only).
  - `BattleHost` (`Systems/BattleHost`): starts the session for `START_BATTLE`, runs its frame (the field runs only that while it's active, then the boxes and the fade), then `startBattle`'s tail and `advanceBattleTime`; `item_loss` (`handleItemLoss`).
  - `ScriptInterpreter`: `START_BATTLE` counts, converts the predefined enemies, stops the music, waits for the battle, then the outcome: −1 item loss, lives, script 0 section 0x4DE; 0 the map change back; 1 trigger 1 or the camera pan back (slot 10).
  - `Tamer`: `tickTamerWaypoints` in his walking state, `initializeTamerWaypoints` at each map load.
- **Corrections to this spec:**
  - In the US release ✕ (`CONFIRM`) gives a command and **△** (`CANCEL`) opens the inventory (§2.6 said ✕).
  - ~~After a won battle, the fleeing enemies that are off screen stay on the map.~~ Corrected 2026-10-26 (ISSUES.md I-25): `isOnScreen` is only updated by the NPCs' field tick, so in a battle it keeps its value from the battle's start; the enemies on screen then leave the map after the battle, even once they have run off screen.
- **Not yet (moved to 5d-4 with the HUD):** items in battle (the inventory's battle mode, throwing; △ shows a message), the flee bubbles, start text, menu, bars, numbers, countdown and end boxes on screen (their state is in the logic; the end box's text waits 60 frames per text or a press). `handlePause` is ported since (`specs/pause.md`).
- **Approximations to revisit:**
  - the loading run-in uses the field's partner collision, plus "idle on reaching the tamer" (`partnerTickCollision` in `GAME_STATE` 3);
  - `world_screen_matrix` (`GsWSMATRIX`) is the identity until the field exposes its camera matrix, so the effects' screen-projection built-ins aren't exact yet (5d-5);
  - `SKIP_DAYTIME_TRANSITION` isn't ported;
  - the aura projectile (a flattened fighter's attack, effect 0x179) is emitted as an event but not run.
- **Tests:**
  - `tests/test_battle.gd` (49 checks): damage (technique, finisher with charge-up), hit chance branches, `damageTick`, MP costs with brain and sickness, buffs, Your Call's sort, the command lists per brain band, set-up values, the injury penalty, poison / stun / the flatten timeline, the start text, and three whole battles on a stub world (a win with gains and bits, running away, a loss through the death countdown).
  - `tests/battle_scan.tscn`: battles in the real field scene on TROP01, TROP02 and MAYO03.
  - Seen in the tests: a hit cancels the victim's technique (`BTL_removeMoveEffect`), so a slow technique (Fire Tower strikes after 21 frames) can lose every exchange to a faster one, as in the C.

## As built (5d-4, 2026-10-26)

- **The HUD** (`scenes/battle/battle_hud.tscn`, each piece its own scene in `scenes/battle/hud/`, scripts in `scripts/ui/battle/`):
  - `BattleHud` is a `Control`, not a `CanvasLayer` (§5.2 said one): it sits in the field's `Hud` in a slot behind the UI boxes (`BattleHost.hud_slot`), so the end boxes and the inventory draw in front of it as their ordering-table layers say. The host makes it for a battle and frees it after.
  - Each piece extends `BattleHudPiece` (the API a modded piece keeps): `session`, `world`, `text_area`, `boxes`, `data`; `on_visual(kind, args)` for every `Battle.visual` event; `tick(pressed)` once per game frame, after the battle's frame. A piece's state changes in `tick` (the C's render functions count frames; Godot's `_draw` may run more often), `_draw` only draws.
  - The pieces, back to front: `EntityNumbers` (layer 14), `PartnerStatusBars` (10), `FleeBubbles` (8), `FinisherChargeup`, `CommandShout`, `CommandMenu`, `DeathCountdown`, `EnemyHpBars` (7, in the reverse of the C's render order), `StartText` (5-6), `EndBoxes` (on the UI boxes 0-2). Within a piece, primitives added to one layer are drawn in reverse of the C's adds, as the ordering table does.
  - `BattleHudDraw`: the two texture pages (BI_IN at (896, 384), BTLCOMND / FEEL_EF on (960, 256)), `quad` (a POLY_FT4 with free corners: the command menu's unfolding quads, the start text's projected pieces, mirrored UVs), `sprite` (GsSortSprite with pivot, scale, rotation), `entity_text` (drawEntityText), `hud_number` (BTL_renderNumber), semi-transparency mode 0 as the STP texels at 50 %. The HUD's C tables come from `systems/battle_hud` (`BattleHudDraw.table`).
  - The logic keeps what decides anything: the menu's slide steps (`BattleSession.command_menu_steps`, `command_menu_active`), the damage the bars apply (`Battle.apply_damage_buffers`, which now records `bars_shown`, the enemy bars it drew), the start text's motion (`BattleStartText` now keeps each burst piece's drawn `quad`), the end box's counting (`BattleRewards`). The end text's typing is the HUD's (`EndBoxes`: `BTL_tickBattleEndText` in the bits box's tick, `BTL_isEndBoxTextFinished` as the session's `end_text_done`).
  - **US end text:** `BTL_drawBattleEndText` draws nothing while `BATTLE_END_TYPING` is 0 (`while (flag)`), and typing starts only on ✕ / △. So after the two glyphs drawn when the boxes open, each part of the text waits for a press (a `#W` stops the typing again). The C's end test `c == '0'` is read as the buffer's end.
  - `BIT_TEXT` (the text area at (156, 240)) is empty in the US release and isn't drawn.
  - The field's HUD objects keep running in a battle (`BTL_battleTickFrame` runs every object): the clock and the care bars slide off while time is stopped.
- **Items in battle** (§2.18):
  - △ opens the inventory (`Inventory.open`, its names drawn at the battle's set-up). It ticks after the battle's frame, not while the tamer runs away. `Inventory.game_mode` (GAME_STATE: 0 field, 1 fighting, 2 / 3 the battle's other states) picks the Use colour by the item's battle use, greys Drop in a fight, makes Use emit `throw_item` (GAME_STATE 1) instead of the feeding hand-over, and leaves △ on the list without going back to the △ menu.
  - `BattleThrownItem` (`TAMER_ITEM`): in the hand (bone 9) until frame 7 of the throw, then 24 frames to the partner on `ITEM_THROW_HEIGHT`; the last step's integer division leaves it 1 unit short, as in the C. `BattleSession.throw_item` / `tick_thrown_item`; the death countdown pauses while it flies. The tamer draws it (`Tamer.show_held_item_at`) and holds it as `held_item`, so the inventory won't open meanwhile.
  - The item lands through `ItemUse.apply` with `ItemUse.battle` set. The battle branches read the item effect's new `battle` block (data porter: `cure_status` shown / quiet, `protect`, the disks' `buff` per stat with `capped`), never the ids: the numbers over the partner (0xB, icons 1 HP / 2 MP / 3-5 stats), `BTL_healStatusEffect`, `PROTECTED`, Restore's revive (0x2C) and `Battle.remove_death_countdown`, the buff disks (`handleBuffDisks`, new). The healing sparkles are emitted as `ItemUse.healing_effect` (ISSUES.md I-21, drawn later); `item_particles` and `buff_disk` go out as visual events for 5d-5.
- **Approximations to revisit:**
  - the end box's buttons: the C wants ✕ or △ alone and newly pressed (`POLLED_INPUT == CONFIRM_BUTTON`); the HUD takes them newly pressed;
  - the flee bubbles, the charge-up gauge and the countdown project through the field camera (`BattleWorld.project`), not `GsWSMATRIX`;
  - the end text's two first glyphs are drawn in one frame (the C spreads them over two);
  - the stat bars' fills in the stats box start at x −22 as in the C (`rect.x = -22`), whatever the box's position.
- **Found in play (2026-10-26):**
  - the knock-back's collision probe follows the animation's signed forward momentum (`FieldDigimon.forward_step`, `entityMoveForward`), so a backwards slide stops at the map's walls (ISSUES.md I-26);
  - `FieldBattleWorld.is_on_screen` reads the NPC's flag as its field tick left it, and an NPC off the map doesn't animate (`Npc._process`; `NPCEntityTick` returns first): no root motion, no steps (I-25);
  - the help line names each phase a battle enters, and a battle without an enemy says so (I-24).
- **Found in play (2026-11-07):**
  - the root motion moves one tick late, as the C's momentum (`startAnimation` resets it, `tickAnimation` moves it before reading the keyframes), so a fighter restarting its walk every tick turns in place instead of walking through the fence (ISSUES.md I-28; `specs/partner.md` §3);
  - the sidestep (`collisionGrace(NULL, entity, 0x118, 0xC8)`) probes with the battle's own `entityCheckCollision`: the combat area (280 x 200 pixels at the screen centre), the map, and the entities without the fainted (HP 0) and without the tamer while the fighter walks (anim 0x23 / 0x24, `map.c:3446-3452`). The port's ran the field's probe, so it turned fighters off screen and let fainted Digimon block (`FieldDigimon.grace_with`, ISSUES.md I-42). The tamer does block a fighter that runs, attacks or is knocked back, as in the C.
- **Equipped moves:** the partner's stats hold technique keys (`specs/game_state.md`), the NPCs' the C's animation ids; `Battle.anim_of_move` reads a key as 0x2E + the technique's slot in the Digimon's list (`BattleFighter.move_anim`, the loading). Found in play (ISSUES.md I-22).
- **Tests:** `tests/test_battle.gd` (83 checks: + a key-equipped technique, the throw's timing, a throw in a battle, every battle branch of the item effects), `tests/test_battle_hud.gd` (16 checks: a win and a loss with the HUD in the tree), `tests/test_inventory.gd` (84: + the battle mode); `battle_scan` taps ✕ in the end box, and takes `BATTLE_MAPS`, `BATTLE_RAW` (the new game's partner with File City's stats), `BATTLE_TALK` / `BATTLE_ENTITY` (start through the enemy's talk script), `BATTLE_SECTION` / `BATTLE_VALUES` (a trigger cell's key fight), `BATTLE_AT`, `BATTLE_DEBUG=<frames>`; it fails when a fighter stands on a blocking cell, or a defeated enemy stays on the map or still moves.
