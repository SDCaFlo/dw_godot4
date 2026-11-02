# The arena (step 4e-4)

Status (2026-11-01): **draft, waiting for approval.** Step 4e-4 of `PLANS.md`. It replaces `ArenaStandIn` (`specs/tournament_entry.md` §5.4) with the tournament itself: the bracket, the three matches, the scenes between them and the champion's podium. Its C is the `STD_REL` overlay (`src/std/`).

The C names below are the decomp's (US). Line numbers are for `src/std/std_*.c` unless another file is named. "Same as btl" means the function body equals its `BTL_` twin once the prefix is swapped (the comparison of 2026-11-01, §1.2).

## 0. How to work on it

- **Reuse first.** Two thirds of `std` is a copy of `btl`, which the port already has (`Battle`, `EffectHost`, `EfeVm`, `EfeView`, `BattleFx`, the HUD pieces, the status visuals). The arena reuses those classes. Where the C differs, the arena **overrides the one function that differs** (§5.2) instead of copying a class.
- **The blocking loops become phases**, as in `BattleSession`: `STD_tournamentMain`, `STD_runIntro`, `STD_combatSetup`, `STD_combatMain` and the result screens each run their own `while` over `STD_battleTickFrame`. The port runs one original frame per `frame()` call, in the same order, with no `await`.
- **Every value has its C line** (§3) or is marked `port-only` / `stand-in` (`docs/porting_checklist.md`).
- **Data, not ids** (`specs/content.md` §4). The C names Digimon, cups and maps by id in a few places (§4.2). Each of those becomes a property.

## 1. The C code

### 1.1 Where it is called

`startTournament` (`main/utils2.c:577`) draws the 7 opponents (already ported: `TournamentCups.draw_opponents`), stops the music, loads `STD_REL`, and calls `STD_tournamentMain(&{cup, opponents[7]})` (`utils2.c:661`). It then runs `thunkReinitializeAfterTournament` and the bookkeeping (`TournamentCups.finish`). Builtin 0x06 (`TournamentRoutines._tick_0x06`, state 7) already waits on `arena.finished` / `arena.result`.

After the builtin, both callers add 6 hours and warp (script 213 `0x1034–0x1050`: `WARP_TO` 208 or 223, section 61; script 102 `0x09D4–0x09DE`: `WARP_TO` 106, section 82). **The field is reloaded after every tournament**, so the arena may leave the field's entities as it likes (the C removes the map's NPCs, `removeMapEntities`, `std_setup.c:257`, and moves the partner).

### 1.2 What is a copy of `btl` (measured 2026-11-01)

Non-blank lines, US branches of the `#if VERSION` blocks:

| File | Functions | Same as btl | Near (one change or a few) | Arena only |
|---|---|---|---|---|
| `std_effect.c` | 222 (4435 lines) | 197 (3992) | 10 (130) | 15 (313): the win / lose / champion / podium scenes |
| `std_main.c` | 166 (4932) | 71 (1648) | 11 (909) | 84 (2375): bracket, intro, cameras, timer, 1-on-1 end test, arena command menu |
| `std_hud.c` | 28 (752) | 12 (351) | 2 (39) | 14 (362): commands, finisher gauges, versus / win-lose / champion models |
| `std_setup.c` | 14 (442) | 0 | 0 | 14 (442): the tournament loop, opponents, arena loading, camera, lights |

So the arena's own code is ~3.5k lines. The near copies are listed in §4.6 with each difference.

## 2. What the player sees

1. A fade to black (5 frames), then the **bracket intro** (`STD_addBracketIntro`): the eight entrants' sprites and names on the bracket, under the arena's title picture (the grade image), for 0x78 frames, then fading in.
2. **Before each match**, the bracket (`STD_addBracket`): the pairs of this round "fight" as icons that hop and shoot small projectiles at each other. The losers drop down, and the winners climb a row. When the partner's pair comes up, the screen dims and the match starts.
3. **A match:**
   - The intro: the camera chases the partner, who walks 0x514 or 0x7D0 units while its name drops in letter by letter in the big font and its stats count up. Then the same for the opponent. ✕ skips either one.
   - The battle start text ("Fight!"), then a 1-on-1 battle with the field's rules, a 99-second timer, the command menu at the bottom (no Run, no items), and both fighters' finisher gauges at the top.
   - The arena camera orbits the two, with random cuts.
   - The end: a faint (the winner's victory pose, the "Win" or "Lose" letters), or the timer at 0. A time-out shows the damage each side dealt ("Damage" window) and decides by it; a draw shows "Draw" and counts as a loss.
4. After three wins, **the champion scene**: the podium, the "CHAMPION" letters, the camera circling the partner as the podium rises.
5. A fade to black, and back to the field (the script warps).

## 3. The values

Status **C** = from the decomp at that line. **port-only** = decided here.

### 3.1 The tournament (`std_setup.c`)

| What | C | Value |
|---|---|---|
| Opponent stand-ins: type 0x40 → 0x36, 0x3F → 0x30, 0x41 → 0x2A | `STD_tournamentMain` 530–540 | ids → Digimon property (§4.2) |
| Fade out / wait / sounds | 541–543 | `fadeToBlack(5)`, `STD_tickFrames(5)` (= 6 frames, `<=`, `std_main.c:6185`), `loadMapSounds(0x10)` |
| Arena choice | 544–548 | `CURRENT_SCREEN == 0x6A` (BETL02) → arena 1, else 0 → map property (§4.2) |
| Bracket intro length | 555–556 | `fadeFromBlack(5)`, `STD_tickFrames(0x78)` |
| Matches | 559 | until `STD_MATCH_RESULT == -1` or 3 played |
| Result | 609–613 | won: `i` (3), else `i - 1` (matches won) |
| Champion: fade | 589–592 | `fadeToBlack(0xA)`, 11 frames |
| Champion: podium in | 594–599 | `fadeFromBlack(0xF)`, ≥ 16 frames while `MAIN_D_801350F0 > 0` |
| End | `STD_deinitializeTournament` 432–460 | `stopBGM`, `stopSound`, `fadeToBlack(1)`, 11 frames, partner `vy = 0`, `GAME_STATE = 0` |
| Music font | `STD_initializeTournament` 245–249 | arena 0 → 0x1E, arena 1 → 0x20 (variants 0 partner intro, 1 opponent intro, 2 fight, 3 win, 4 lose) |
| Bracket music | `STD_addBracket` 3544, `STD_addBracketIntro` 3672 | font 0x1D, variant 0 (intro), 1 (bracket), 2 (champion) |
| Camera at rest | `STD_initializeCamera` 415–430 | projection 500; rotation (100, 0, 0); translation (0, 500, 3000) |
| Lights | `STD_initializeLighting` 474–499 | (1000, 1000, 1000) white; (−1000, 1000, −1000) 160; (−20, 20, 200) 96; ambient 0x400 |
| Arena files | `STD_ARENA_MODELS` / `TIMS` / `COLLISIONS` (`std_main.c:1326–1348`), `STD_ARENA_COUNTS` (`std_setup.c:126`) | `StdArenaCfg` is `{modelCount, timCount}` (`include/dw/std.h:13`): arena 0 `T_TOGI.TMD` (3 objects, matches its header) + `T_TOGI.TIM` (4 TIMs); arena 1 `B_TOGI.TMD` (4 objects) + `B_TOGI.TIM` (1 TIM); both `B_TOGI.ATR` |
| Arena drawing | `STD_renderArena0` 682, `STD_renderArena1` 720 | objects by OT (object 0 in OT 0xFFE, 1–2 in 0xFFF, 1 or 3 at layer 2); object 0 gets attribute 0x200 (no light) once the bracket ends |
| Opponent stats | `STD_initializeOpponent` 279–389 | base `STD_OPPONENT_BASE_STATS[cup]` (data: `opponent_base_stat`); level 3 ×1, 4 ×2, 5 ×25/10; Off/Def/Spd/Brn `base ± (30 − rand(61))%`, HP/MP ×10; caps 999 / 9999; `chargeMode 0` |
| Opponent moves | same, 357–388 | the techniques the Digimon knows (anims 0x2E–0x3C) that are not finishers and cost ≤ MP/10 ÷ 3, shuffled, the first 3; none → 0x2E; slot 3 = the Digimon's finisher. A self/Counter list is shuffled and rolled (1 in 10) but then overwritten (dead code, keep the rolls) |

### 3.2 The bracket (`std_main.c:2949–3735`)

| What | C | Value |
|---|---|---|
| Player slot | `STD_setupParticipants` 3468 | `randomLimit(8)` |
| Shuffle of the 7 | 3471–3474 | `swap(list[i], list[rand(7)+1])` for i 1–7 |
| First-round winners | 3483–3489 | `rand(100) < STD_WIN_CHANCES[lvlA−3][lvlB−3]` (data: `tournament_win_chances`) |
| Second round | 3491–3513 | the partner's side is its own match, the other side rolled |
| Opponents in order | 3515–3534 | neighbour slot, then round-1 winner of the next pair, then round-2 winner of the other half |
| Slot states 0–7 | `STD_updateBracket` 2949–3207 | 0 idle 0x29 frames, 1 rise to row (sound 8/5 at 5), 2 face-off 0x29 frames then shoot (sound 8/1), 3 wait for the hit, 4 hit (0x15 / 0x1F frames, sound 8/3), 5 hop (`STD_BRACKET_HOP_Y`, sound 8/4 at 0x14), 6 move along the path, 7 final (0x3D frames) |
| Blink | everywhere | sprite frame toggles every 10 frames |
| Dim before a partner match | 3034–3037 | `STD_BRACKET_FADE += 3` up to 0x80 |
| Paths, rows, hop | `STD_BRACKET_PATHS` (1450), `STD_BRACKET_ROW_Y` (1395), `STD_BRACKET_HOP_Y` (1389) | tables → data (§4.1) |
| Projectile speed | `STD_tickBracketProjectile` 3604 | 1 px (matches 1–4), 3 px (5–6); match 7 would read `d` unset, but match 7 is the final, which always holds the partner, and the partner's pairs never shoot (state 2 dims instead): dead |
| Projectile hit | `STD_renderBracketProjectile` 3623 | within 9 (right) / 0x11 (left) px of the target |
| Hit flash | `STD_tickBracketHitFlash` 3582 | drawn when `timer % 5 == 4`, removed at 0x10 |
| Intro fade | `STD_tickBracketIntro` 3686 | after 0x65 frames: fade −8, overlay −8 down to 8, title −8 |
| Sprites | `STD_renderBracketDigimon` 3341 | `STDTIM` page `(type/64)*64 + 0x380`, CLUT row `STD_DIGIMON_SPRITE_CLUT[type]` (data), 16×16 cells, 2 frames |
| Names | `STD_drawBracket` 3212, `STD_renderBracketGlyph` 3420 | vertical, 8 px glyphs from `STD_INTRO_DIGIMON_NAMES` (data); `len ≥ 8` uses the smaller column (US branch). **US: `STD_renderBracketGlyph` never calls `AddPrim`** (`#if !VERSION_IS(US)`): the names are not drawn in the US release |
| Background | 3297–3309 | the bracket image (`STDTIM` 0x340, CLUT (0x20, 0x1E0)) at (−0x80, −0x61) 255×0x87, box fill 0x20 grey full screen, both layer 5 |

### 3.3 The match (`std_main.c`)

| What | C | Value |
|---|---|---|
| Start positions | `STD_placePlayer1/2` 1568–1607 | arena 1: ±0x708, else ±0x9C4; partner faces 0x400, opponent 0xC00 |
| Intro walk | `STD_runIntro` 1885 | distance 0x514 (arena 1) / 0x7D0; ✕ (newly pressed) skips to the end position |
| Intro sound | 1895, 1945 | the opponent's voice bank `readVBALLSection(5, type)`, `loadSB` between the two |
| Intro name | `STD_addIntroText` 1625, `STD_tickIntroName`, `STD_renderIntroName` | colour by `special[0]` (`STD_INTRO_NAME_COLORS`), one letter every 4 frames, letter sizes 64/44/38/32 and offsets 16/7/3/0; x = −len·16, y = 68, then climbs 28 a frame to −71; name length = glyph count, 10 for 0x4E and 0x3C (→ data) |
| **US: big letters** | `STD_renderIntroNameChar` 1852 | **no `AddPrim` in US** (`#if !VERSION_IS(US)`): the US release doesn't draw the intro name either (§8.1) |
| Intro stats | `STD_tickIntroStats` 1969, `STD_renderIntroStats` 2009 | count up 200 (HP/MP) / 20 a frame to the value; sound 0/0x16 while counting; bars `value·100/limit` (`STD_STAT_BAR_LIMITS`), green (0x50, 0xC8, 0x50) |
| Timer | `STD_initializeCombat` 4138, `STD_tickFighterCounter` 2920 | 99, −1 every 20 frames while neither fighter is fainting (anim 0x2B) |
| Fighters | 4166–4168 | `ENEMY_COUNT = 1`; partner entity 1, opponent its entity |
| Same Digimon | 4140–4142 | both the same type → the 1P / 2P markers (`STD_renderPlayerMarker`) |
| Commands | 4210–4256 | first command 0xB (finisher) instead of Run; list by brain (`battle_commands` `arena_commands`) |
| Start text | `STD_combatSetup` 3939–4035 | same as btl; ≥ 60 frames; the orbit's min distance 200 → +400 to 4200, then −400 to 1000 |
| End test | `STD_checkEndCondition` 4038–4103 | §4.4 |
| Victory | `STD_deinitializeCombat` 4524 | win 0x64 / loss 0x78 frames of pose 0x2A, music variant 3 / 4, then 20 frames |
| After a match | 4574–4590 | Off/Def/Spd/Brn back to the start values, **HP and MP +1/5 of the max** (capped) |
| Time-out window | `STD_addTimeoutWindow` 4698, `STD_tickBattleResultScreen` 4641 | "TIME UP" at 0, window at 0x3C, ✕ after 0x3D, ends at 0x79 (a draw: 0x3D) |

### 3.4 The cameras (`STD_tickVSPhase`, 2306)

`STD_CAMERA_STATE`: 0 manual (pad 2, debug), 1 the orbit (`STD_setCameraOrbit`), 2 top-down, 3/5 relative to a fighter, 4/6 a viewpoint from a fighter's bone, 7 look at one fighter, 8 fixed viewpoint, 9 the intro chase, 10 rotating (between matches), 11 the champion. Their values: `STD_CAMERA_PRESETS` (1360), `STD_RANDOM_VIEWPOINTS` (1372), the chase (2652–2780), the intro camera (2753–2852: 22 keys `STD_D_8007A41C` and a curve whose slopes are all 0, so it is piecewise linear with an integer slope, `effect_common.c:612–676`). Cuts: `STD_selectRandomCamera` (1 in 3, from `setupMoveExecution`), `STD_setRandomViewpoint` (1 in 3 on a hit), and every 600 frames 1 in 2 (`STD_tickBattle` 4486).

### 3.5 The scenes

| Scene | C | Model | Timeline |
|---|---|---|---|
| Versus / Draw | `std_hud.c:1138–1225` | `DRAW.TMD`, 4 objects | slide in −200 a frame from x 1000 to `STD_VERSUS_MODEL_TARGET_X`, object i after 5·i frames; done at 0x51 |
| Win | `std_effect.c:1516–1600` | `WIN_LOSE.TMD` objects 0–3 | from z −0x30C to 0xDC (+0x32), rotate with `STD_WIN_ROTATION_X/Y`, the outer two slide along `STD_WIN_X_CURVE` |
| Lose | `std_effect.c:1401–1514` | `WIN_LOSE.TMD` objects 4–7 | 32 random black columns wipe down (+0x3C), letters drop (`STD_LOSE_DROP_Y`), tilt (`STD_LOSE_TILT`) |
| Champion | `std_hud.c:1273–1396`, `std_effect.c:1251–1398` | `CHAMP.TMD` (9 letters), `T_DAI` / `B_DAI.TMD` podium | letters spin in (0x200 a frame), VRAM column scroll (`MoveImage`), then rise; the partner and podium rise 0x19 a frame; camera orbit `STD_CHAMPION_ORBIT_ANGLES`, then pose 0x2A and `STD_CHAMPION_CAMERA_Y` |

## 4. Behaviour

### 4.1 Data (data porter, new `systems/arena` record and Digimon properties)

From the C tables, each with its C-text check: `STD_BRACKET_PATHS`, `STD_BRACKET_ROW_Y`, `STD_BRACKET_HOP_Y`, `STD_BRACKET_PROJECTILE_CLUTS`, `STD_CAMERA_PRESETS`, `STD_RANDOM_VIEWPOINTS`, `STD_D_8007A41C` (camera keys), `STD_INTRO_NAME_COLORS`, `STD_INTRO_NAME_CHAR_SIZES / OFFSETS`, `STD_STAT_BAR_LIMITS`, `STD_COMMAND_LABEL_U / W`, `STD_COMMAND_MENU_LAYOUTS`, `STD_COMMAND_ICON_UVS`, `STD_SPECIAL_ICON_UVS`, `STD_FINISHER_SEGMENT_U / W / X`, `STD_FINISHER_PULSE`, `STD_CHAMPION_CAMERA_Y`, `STD_LOSE_DROP_Y`, `STD_LOSE_TILT`, `STD_WIN_X_CURVE`, `STD_VERSUS_MODEL_TARGET_X`, the camera SVECTORs (720–729), the music fonts. Already there: `opponent_base_stat`, `grade_image`, `tournament_win_chances`, `battle_commands.arena_commands`, `rounds_to_win`.

### 4.2 Ids become properties

| C | Property |
|---|---|
| `STD_INTRO_DIGIMON_NAMES[type]` (870, 112×14), `0x4E` / `0x3C` length 10 | Digimon `arena_name` {`glyphs`, `length`} |
| `STD_DIGIMON_SPRITE_CLUT[type]` | Digimon `bracket_sprite` {`clut`} (page from the type's slot, as the C) |
| `STD_BRACKET_PROJECTILE_ICONS[type]` | Digimon `bracket_icon` |
| 0x40 → 0x36, 0x3F → 0x30, 0x41 → 0x2A (`std_setup.c:530`) | Digimon `arena_stand_in` (the type that fights instead) |
| `CURRENT_SCREEN == 0x6A` → arena 1 (`std_setup.c:544`, `std_main.c:3716`, `std_hud.c:1373`) | map `arena_model` (0 / 1) |
| finisher range 0x3A–0x70, Counter 0x2D | existing `category finisher`, `counter` |
| type 0x71 scale 0x1800 | existing `battle_scale` |

### 4.3 The tournament loop (`STD_tournamentMain`)

Phases: `FADE_OUT` (6 frames) → `BRACKET_INTRO` (0x79 frames) → per match: `BRACKET` (until `STD_BRACKET_FINISHED`) → `MATCH` (§4.4) → `AFTER_MATCH` (win: the win scene is removed and the camera reset to state 10; loss: the lose scene removed). After a loss or the third match: `CHAMPION` (won only) → `END` (`STD_deinitializeTournament`, 11 frames) → `DONE` with the result. The opponent of match i is created just before it (`STD_initializeOpponent(local[i], i, cup)`).

### 4.4 A match (`STD_runMatch` → `STD_runIntro`, `STD_combatMain`)

- `INTRO_PARTNER` / `INTRO_OPPONENT`: until the walk animation ends (`animFlag & 1` clear) or ✕.
- `SETUP` (`STD_initializeCombat`, then `STD_combatSetup`'s two loops: the start text and its burst).
- `FIGHT`: each frame `STD_checkEndCondition`, then `tickPartnerAI`, `tickEnemyAI`, `STD_tickBattle`, the object frame. The pause (`handlePause`) waits for the field pause, as in battles.
- End test (`STD_checkEndCondition`, US = `JP_TRIAL` or newer: none while either damage buffer is non-zero):
  - the partner fainted (0x2B ended): −1 if the opponent still lives, else 2 once the opponent's faint ended;
  - the opponent fainted (ended): 1 if the partner's HP minus its buffer > 0, else 2 once the partner's faint ended;
  - the timer at 0, both alive: compare the damage taken (`STD_STARTING_HP − HP`); more taken by the partner → −1, less → 1, equal → 2; the result screen first (§3.3).
- `END` (`STD_deinitializeCombat(a, b)`): on a draw (2) the versus scene, unless it already ran in the result screen (`STD_TIMER != 0 || !STD_IS_DRAW`); otherwise the winner's pose loop; then 20 frames, HUD off, the stats reset and the +1/5 heal. A draw returns −1 (a loss).

### 4.5 The arena's own rules inside the battle

`STD_tickBattle` (4431) is `BTL`'s fighter-state loop with the arena's camera timer at its end. The differences from btl, all 1-on-1:
- The partner always targets fighter 1, and the opponent fighter 0 (`STD_tickPartnerAI`, `STD_setupMoveExecution`, `STD_updateFighterStatusVisuals`). No Run command. A finisher command also applies the charge requirement (`tickPartnerAI` case 11).
- The partner's AI idles when the opponent is dead **or the partner's HP ≤ its damage buffer**.
- A faint: `STD_selectRandomCamera(…, 5)` (the win / lose letters and the end camera) if the other one is still alive, and `STD_DISABLE_HITTING = 1` (every later hit misses: `STD_applyPartnerStatsToFighter` returns 0).
- The opponent's move priorities are 30, 30, 30, 0 every frame (`STD_tickEnemyAI`). Its charge-mode-2 switch is a 1-in-10 roll instead of the off-screen test.
- The area-technique lock (`FLEE_DISABLED[1] = 0x6E`) has a twin for the opponent (`P2_AOE_TIMER`), and `STD_selectMoveTarget` (6660) holds an area technique while the other fighter's area technique runs.
- MP is always paid (no `FLEE_DISABLED[0]` test). No `FLEE_TIMER` check in the hits, no `HAS_TAKEN_DAMAGE`.
- Hit chance (`STD_applyPartnerStatsToFighter` = `BTL_calculateHitChance`): no level-under-3 rule; `STD_DISABLE_HITTING` → 0.
- Ranged techniques (`STD_tickDigimonAttackRanged`, 5104): the 80-frame give-up becomes 100 frames of trying and then 60 of idling.
- Senile (`STD_tickDigimonSenile`, 4860): a status with its own timer.
- Type 0x71's scale isn't restored after the flatten (`STD_applyMoveResult` vs `BTL_tickStatusEffects`).
- No combat-area edge (`entityCheckCombatArea` returns 0 in `GAME_STATE` 4, `map.c:3053`). The arena's walls come from `B_TOGI.ATR` (tiles, as the field's collision: `asset_porter/specs/atr.md`).
- The finisher charge-up gauge sits at (−0x8C, −0x4A) (`STD_initializeFinisherChargeup`).
- Effects: the screen fade dims the arena's CLUT row (`modifySomeImage`, `main/efe.c:986`: VRAM (512, 248) 256×7, each colour × (255 − c)/255) instead of a full-screen quad. The fixed view saves and restores `GsWSMATRIX` (same result as btl's copy).

### 4.6 The HUD

| Piece | C | Reuse |
|---|---|---|
| Start text and burst | `std_hud.c:566–885` | same as btl: `StartText` |
| Entity numbers | `main/entity_text.c:187` (`GAME_STATE == 4`) | same: `EntityNumbers` |
| Status bars (both fighters) | `STD_addFighterStatusBars(0/1)` | btl's copy with an index: `PartnerStatusBars` with a `fighter` export (§8.2) |
| Finisher gauge (the partner's only: `STD_renderFighterStatusBars` calls it for id 0, `std_hud.c:1093`) | `STD_renderFighterHPBar` 906, `STD_renderHPBarDigits` 980, `STD_renderFinisherReadyIcon` 949 | new `ArenaFinisherGauge`. Its id-1 branches (x 0x37 / 0x6E) are never reached. **Quirk:** the ready icon's box is at x −0x58 whatever the id |
| Command menu | `STD_addCommandMenu` 7502, `STD_renderCommandMenu` 1750, `STD_renderMoveName` 7467, `STD_handleCommands` (`std_hud.c:504`: ←/→ wrap 1..n−1, ✕ buffers, △-less; R1 (0x80) the finisher when the gauge is full) | new `ArenaCommandMenu` |
| Lifebar toggle | `STD_tickTamerTournament` (`std_hud.c:540`, Select 0x100) | the session |
| Timer | `STD_renderCounterDigits` 2867 | new `ArenaTimer` |
| 1P / 2P marker | `STD_renderPlayerMarker` 5674 | new `ArenaPlayerMarker` |
| Time-out | `STD_renderTimeoutText` 5617, `STD_renderTimeoutWindow` 5632 | new `ArenaTimeout` (UI box 0) |
| Intro name and stats | §3.3 | new `ArenaIntroStats` (and `ArenaIntroName`, drawing nothing in US, §8.1) |
| Bracket, bracket intro | §3.2 | new `ArenaBracketView` |
| Status visuals, auras, projectiles | `std_effect.c` | same as btl: `scenes/battle/fx/` |

## 5. Godot design

### 5.0 The data (step 1, exact shape; the tests read these names)

**`systems/arena`** (data porter, `systems.py`): one record, `{"id": 0, "key": "dw1:arena", …}`. Every value is the C value (signed where the C type is signed), in C order:

| Field | C |
|---|---|
| `music` `{arena_fonts: [0x1E, 0x20], bracket_font: 0x1D}` | `std_setup.c:245–249`; `playMusic(0x1d, …)` in `STD_addBracket` / `STD_addBracketIntro` (checked against the C text) |
| `bracket` `{paths: [{x: [8], facing: [8]} × 8], row_y: [8], hop_y: [24], projectile_cluts: [16]}` | `STD_BRACKET_PATHS` (`unk0` → `x`, `unk10` → `facing`), `STD_BRACKET_ROW_Y`, `STD_BRACKET_HOP_Y`, `STD_BRACKET_PROJECTILE_CLUTS` |
| `camera` `{presets: [[rx, ry, rz, tx, ty, tz] × 9], random_viewpoints: [[3] × 5], intro_keys: [22], vectors: {intro_stage1_pos, intro_stage1_rot, chase_offset, chase_rotation, intro_offset, intro_rotation, intro_stage2_pos, intro_stage2_rot}}` (vectors `[x, y, z]`) | `STD_CAMERA_PRESETS`, `STD_RANDOM_VIEWPOINTS`, `STD_D_8007A41C`, the SVECTORs `std_main.c:720–729` (`STD_CAMERA_INTRO_OFFSET` → `intro_offset`, `STD_CAMERA_INTRO_ROTATION` → `intro_rotation`) |
| `intro` `{name_colors: [[r, g, b] × 10], char_sizes: [4], char_offsets: [4], stat_bar_limits: [6]}` | `STD_INTRO_NAME_COLORS`, `STD_INTRO_NAME_CHAR_SIZES / OFFSETS`, `STD_STAT_BAR_LIMITS` |
| `command_menu` `{label_u: [5], label_w: [5], layouts: [[10] × 8], icon_uvs: [[u, v] × 8], special_icon_uvs: [[u, v] × 8]}` | `STD_COMMAND_LABEL_U / W`, `STD_COMMAND_MENU_LAYOUTS`, `STD_COMMAND_ICON_UVS`, `STD_SPECIAL_ICON_UVS` |
| `finisher_gauge` `{pulse: [12], segment_u: [8], segment_w: [8], segment_x: [8]}` | `std_hud.c:375`, `:422–424` |
| `scenes` `{champion_camera_y: [8], lose_drop_y: [24], lose_tilt: [14], win_x_curve: [18], versus_target_x: [4]}` | `std_hud.c:399–426` |

Its `godot.access`: `GameData.system("arena")[0]`.

**Digimon** (`digimon_data`, `digimon.py`), on ids 0–0x6F only (the C tables have 112 rows; the other records don't get the fields):
- `arena_name` `{glyphs: [14 raw bytes of STD_INTRO_DIGIMON_NAMES[id]], length}`: `length` = `strlen(US name) / 2` (`DIGIMON_DATA[type].name`, `STD_addIntroText` 1650), 10 for 0x4E and 0x3C (the C names those two ids: checked against the C text, kept as data);
- `bracket_sprite_clut` = `STD_DIGIMON_SPRITE_CLUT[id]`; `bracket_icon` = `STD_BRACKET_PROJECTILE_ICONS[id]`;
- `arena_stand_in` `{id, name}` on 0x3F → 0x30, 0x40 → 0x36, 0x41 → 0x2A only (`std_setup.c:530–540`, checked against the C text).

**Maps** (`systems/maps`): `arena_model` on every record, 1 for 0x6A (BETL02), else 0 (`std_setup.c:544`, checked against the C text). (Not `arena`: that field already exists, the `ARENA_MAPS` flag of the dget overlay.)

**Asset porter:** nothing new to export (the STDDAT TMDs, ATRs, the stacked TIMs, `GRADE/*`, `TIME.TIM` and `STDTIM.BIN` are already out). `btl_rel` gains one check whose name contains `STD_REL`: `STD_REL.BIN`'s bytes 0–0x4188 (texture and the 4 models, `config/us/std.yaml`) equal `BTL_REL.BIN`'s, so the arena uses the `btl_rel` output. Its spec and PROGRESS say so.

### 5.1 Scenes

```
scenes/arena/arena.tscn          Arena (Node): replaces ArenaStandIn, same API (start, finished, result)
  World (Node3D)                 the arena model, lights, the fighters, ArenaCamera; shown instead of the field's world
  Hud (Control)                  the HUD pieces of §4.6 (scenes/arena/hud/), plus the reused battle pieces
  Scenes (Node3D)                versus / win / lose / champion / podium (scenes/arena/scenes/), one scene each
```

- **The fighters are the arena's own Digimon instances** (the partner's model and the opponent's, `FieldDigimon` like the field's), not the field's nodes. The C moves the field's partner and removes the map's NPCs. The port leaves the field alone, because the script warps right after (§1.1). The partner's stats are `GameState`'s (the battle writes them, as in the C). `port-only`, see §8.3.
- The field's world is hidden while the arena runs, and `Field._frame` runs only `arena.frame()`, as it does for `BattleHost`.
- Each scene and HUD piece has the small API of the battle's (`BattleHudPiece`: `tick(pressed)`, `_draw` only draws), so a mod can restyle it (`docs/composition` memory, `specs/scenes.md` §3).

### 5.2 Logic (headless, tested)

- **`ArenaTournament`** (`scripts/systems/arena/arena_tournament.gd`, `class_name ArenaTournament extends RefCounted`, step 2). Pure logic, no phases (the phase loop of §4.3 is step 4's):
  - `_init(game_data: Node)`; `var roll: Callable` = `Rng.random_limit` (a `func(limit) -> int`; every `randomLimit` of the C goes through it, in the C's order, so tests script the rolls);
  - `stand_in(type) -> int` (`arena_stand_in`, else the type);
  - `setup_participants(partner_type, opponents: Array /* 7 types */) -> {player_slot, participants: [8], round1: [4], round2: [2], opponents: [3]}` (`STD_setupParticipants`; rolls: 8, then 7 × 7, then 4 × 100, then 1 × 100; the input array isn't changed);
  - `initialize_opponent(type, cup) -> {base: {max_hp, max_mp, offense, defense, speed, brains, moves: [4]}, current: {hp, mp, charge_mode}}` (`STD_initializeOpponent`; moves are animation ids 0x2E + slot or `null` for 0xFF; the technique of a slot is the Digimon's `anim_technique` override or `c.moves[slot]`, as `Battle.technique_of`; finisher = `category == "finisher"`, Counter = `counter`, self = `range` 4; `base` from the cup's `opponent_base_stat`; level from `level.id`, with 3 ×1, 4 ×2, 5 ×25/10 and any other level ×1 (`port-only`: the C leaves `mul` / `div` unset); C integer division truncates toward zero, as GDScript's `/` on ints);
  - `static result(match_result, played) -> int` (`std_setup.c:609–613`).
- **`ArenaBracket`** (`arena_bracket.gd`, `class_name ArenaBracket extends RefCounted`, step 2):
  - `_init(game_data, player_slot, round1: Array, round2: Array)` (the arrays are kept and changed as the C changes `STD_ROUND1/2_WINNERS`) = `STD_initializeBracket`; `signal sound(bank: int, id: int)` for every `playSound`;
  - `var match, fade, finished, round1, round2`; `var slots: Array[Dictionary]` (8) with `x` (`unk0`), `y` (`unk2`), `row` (`unk4`), `frame` (`unk5`), `facing` (`unk6`), `state` (`unk7`), `timer` (`unk8`), `timer2` (`unk9`), `hit` (`unkA[0]`), `mode` (`unkA[1]`), `loser` (`unkC`); `var projectiles: Dictionary` slot → `{x, y, flag, owner}` (only live ones; the last `owner` per slot stays readable, as the C's static array: state 6 reads it); `var flashes: Array` (slots with a hit flash);
  - `begin()` = `STD_addBracket` (`finished = false`, `fade = 0`; the music is the view's); `frame(match_result)` = one C frame: the projectiles' ticks (`STD_tickBracketProjectile`, which also tests the hit), the flashes' ticks, then `STD_updateBracket` (it runs in the bracket's render, after every tick);
  - `begin_intro()` / `intro_frame()` with `intro_timer`, `intro_overlay` (`MAIN_D_80135165`), `intro_title` (`MAIN_D_80135166`) and `fade` (`STD_addBracketIntro`, `STD_tickBracketIntro`).
- **`ArenaBattle extends Battle`** (`scripts/systems/arena/arena_battle.gd`, step 3). `var camera: ArenaCamera` (null: no camera calls), `var disable_hitting` (`STD_DISABLE_HITTING`), `var p2_aoe_timer` (`P2_AOE_TIMER`). `no_escape` stays false: the arena writes `FLEE_DISABLED[0] = 1` (`std_main.c:4161`) but never reads it, so the opponent pays its MP. The differences of §4.5 are either **hooks** added to `Battle` (each defaults to the btl line it replaces, so field battles don't change; `tests/test_battle.gd` proves it) or **overrides** of whole functions whose arena C differs throughout:
  - hooks in `Battle`: `_on_fighter_fainted(f, index)` (after `faint` in both AIs), `_partner_gives_up(f)` (the idle branch's extra test), `_partner_retarget(f, site)` (the four `select_target` calls of `tickPartnerAI`; arena: target 1), `_after_finisher_command(f)` (arena: `STD_applyChargeRequirement`), `_before_enemy_ai(f)` (arena: priorities 30, 30, 30, 0), `_enemy_charge_mode(f)` (btl: the screen test; arena: `randomLimit(10) == 0` → 2, else `randomLimit(2)`), `_start_shared_cooldown(f)` (`startQueuedMove`: btl `FLEE_DISABLED[1]`; arena the partner's or `P2_AOE_TIMER`), `_default_target(f)` (`setupMoveExecution`'s partner branch; arena: fighter 1), `_after_move_execution(f, technique)` (arena: the camera tail, `std_main.c:6783–6807`), `_restore_scale_after_flatten(f)` (arena: none), `_no_usable_enemy_move(f)` (btl: charge mode 2; arena: none, `STD_selectEnemyMove`), `_mp_weight_slot(keys, i)` (btl `keys[i]`; arena `keys[keys[i]]`, `STD_selectPartnerMove` 6478);
  - overrides: `_set_up_commands` (§4.5; the field list of the same brain band without Run (1) and Change (7), `std_main.c:4210–4256`), `initialize_combat`, `tick_fighter_states` (`STD_tickBattle` with its camera timer, 4431), `tick_senile_state` (`STD_tickDigimonSenile`), `tick_ranged_attack` (`STD_tickDigimonAttackRanged`), `is_move_on_cooldown` (`STD_selectMoveTarget`), `hit_chance` (`STD_applyPartnerStatsToFighter`), `retarget_after_hit` (the hit's random viewpoint instead, 5765–5771), `clear_confusion` (`STD_updateFighterStatusVisuals`), `apply_damage_buffers` (`STD_renderFighterStatusBars`: both fighters drain every frame, MP clamped at 0).
- **`ArenaCamera`** (`scripts/systems/arena/arena_camera.gd`, step 3): `_init(world: BattleWorld, partner := 1)`, `var opponent`; the C's state as fields (`state`, `timer`, `focused`, `rotation`, `translation`, `eye` / `ref` (`GS_VIEWPOINT` vp / vr), `viewport_distance`, `min_distance` (`STD_DEFAULT_CAM_MIN_DISTANCE`), `close` (`MAIN_D_8013510C`), the chase and intro records); `tick()` = `STD_tickVSPhase`; one method per C function under its snake-case name (`set_camera_orbit`, `set_camera_yxz`, `select_random_camera`, `set_random_viewpoint`, `set_champion_camera`, `start_camera_chase`, `start_camera_intro`, …); `signal scene_requested(kind)` ("win" / "lose", from `STD_selectRandomCamera` mode 5); `world_screen_matrix()` and `projection()` give the view. States 0 and 10 read pad 2 (a debug camera): the port has no pad 2, so state 0 holds and state 10 only turns 2 a frame (`port-only`, nothing to press).
- **`ArenaMatch`** (`scripts/systems/arena/arena_match.gd`, step 3): `_init(world, effects, game_data, camera)`, owns its `ArenaBattle`; `begin(partner, opponent, arena)` then `frame(pressed)` per original frame, `is_done()`, `result` (1 won, −1 lost or draw). Phases: `INTRO_PARTNER`, `INTRO_OPPONENT`, `SETUP_TEXT`, `SETUP_BURST`, `FIGHT`, `RESULT_SCREEN`, `VERSUS`, `VICTORY`, `END`, `DONE` (§4.4). Fields: `timer` (`STD_TIMER`), `timer_active`, `damage` (`STD_DAMAGE[2]`), `starting_hp`, `is_draw`. `check_end_condition() -> int` = `STD_checkEndCondition`; `handle_commands(pressed)` = `STD_handleCommands`; `deinitialize(a, b) -> int` = `STD_deinitializeCombat`'s bookkeeping (the stats back, the 1/5 heal, the charge mode). Visual events (`intro_name`, `intro_stats`, `timeout`, `versus`, …) go out through `visual(kind, args)` for the views of steps 5–6.
- **`ArenaWorld extends BattleWorld`** (`scripts/arena/arena_world.gd`): the world on the arena's entities and `B_TOGI.ATR`; no combat area; `GsWSMATRIX` from the arena camera.

### 5.3 The frame

`Arena.frame()` = the tournament phase's logic (which runs the match's logic in `MATCH`), then the object ticks in the C's order: the fighters' animations (`STD_tickPartnerTournament` = `tickAnimation`; the NPC tick removes itself), `EffectHost.tick()`, the visuals, the HUD pieces, the camera (`STD_tickVSPhase` is an object, 0x1A8), then the draws that change state (the bars, the effects).

### 5.4 What stays code

The formulas and their integer order, the phase machine and frame counts, the bracket's slot states, the camera states, the animation ids (0x21–0x2E, the model contract), the HUD layouts. Everything else is data (§4.1–4.2).

## 6. Order of work

Each step owns its files; all suites and scans pass after every step; a step is done when its gate in §7 passes.

| Step | What | Files | Complexity · Model |
|---|---|---|---|
| 1 | Data porter: `systems/arena`, the Digimon properties, the map `arena`, checks, spec, PROGRESS. Asset porter: the `STD_REL` = `BTL_REL` check in `btl_rel` (§5.0; the STDDAT files are already exported, confirmed 2026-11-01) | `data_porter/dwdata/groups/systems.py`, `digimon.py`, `data_porter/specs/systems.md`, `digimon.md`, `data_porter/PROGRESS.md`; `asset_porter/dwporter/families/btl_rel.py`, `asset_porter/specs/btl_rel.md`, `asset_porter/PROGRESS.md` | **Low** · Gemini 3.8 Flash (High) |
| 2 | `ArenaTournament`, `ArenaBracket` (logic, §5.2 APIs) | `scripts/systems/arena/arena_tournament.gd`, `arena_bracket.gd` | **Low** · Gemini 3.8 Flash (High): every value in §3, the tests decide |
| 3 | `ArenaBattle`, `ArenaMatch`, `ArenaCamera` (logic); any `Battle` split | `scripts/systems/arena/arena_battle.gd`, `arena_match.gd`, `arena_camera.gd`, `scripts/systems/battle/battle.gd` (splits only) | **Hard** · main session: overrides into a 2.3k-line class, the camera maths |
| 4 | The `Arena` scene, `ArenaWorld`, the arena model and its OT layers, the fighters, the camera view, the field hook-up (replaces `ArenaStandIn`), a plain HUD so it can be played | `scenes/arena/arena.tscn`, `scripts/arena/arena.gd`, `arena_world.gd`, `arena_view.gd`; `scenes/field/field.tscn`, `scripts/field/field.gd`; `ArenaStandIn` removed | **Hard** · main session: rendering, the field wiring |
| 5 | The HUD pieces of §4.6 | `scenes/arena/hud/`, `scripts/ui/arena/`; the `fighter` export on `PartnerStatusBars` | **Medium** · Claude Sonnet 5.5 (Medium), or Gemini 3.8 Flash (High) via agy |
| 6 | The bracket view and the four scenes (versus, win, lose, champion + podium) | `scenes/arena/scenes/`, `scripts/arena/scenes/` | **Hard** · main session: TMD scenes, VRAM column scroll |
| 7 | The effects in the arena: `EffectHost` on `ArenaWorld`, the CLUT fade | `scripts/systems/battle/effect_host.gd` (a hook), `scripts/arena/arena_view.gd` | **Medium** · Claude Sonnet 5.5 (Medium), or Gemini 3.8 Flash (High) via agy |
| 8 | VERIFY "The arena", PLANS, "As built", gates removed | `VERIFY.md`, `PLANS.md`, this spec, the tests | main session |

The game is playable end to end after step 4. Steps 5–7 can then run in any order.

## 7. Tests (acceptance checks, written before the code; gate `DW_STEP_4E_4=<step>`)

Steps 1 and 2's checks are written (2026-11-01). Steps 3–7's are written into the same files before each of those steps starts (they depend on `Battle`'s internals, which step 3 reads first).

- `data_porter/tests/test_arena_fields.py`, `asset_porter/tests/test_arena_assets.py`: every table of §4.1 against the C text; the properties of §4.2 (Agumon's glyphs, the 0x4E / 0x3C lengths, the three stand-ins, BETL02's arena 1).
- `tests/test_arena.gd`, with a seeded `Rng`:
  - the participants: player slot, shuffle, round winners and the three opponents for a given seed and levels;
  - the opponent's stats (each level's factor, the caps) and moves (the MP filter, no finishers in 0–2, the finisher in 3, the dead self-list roll);
  - the stand-in types; the result for 3 wins (3), a loss in match 1 / 2 / 3 (0 / 1 / 2), and for cup 5 (§8.4);
  - the bracket: the slot states frame by frame for one round, the projectile speeds, the dim, `finished`;
  - the end test: each branch, including the damage buffers and the time-out (more / less / equal damage) and the draw → −1;
  - the arena rules of §4.5, one check each (targets, the HP-buffer idle, `DISABLE_HITTING`, priorities 30/30/30/0, the 1-in-10 charge mode, the opponent's area lock, MP paid, the ranged give-up timing, no 0x71 restore);
  - the timer (−1 per 20 frames, held while one faints); after a match: the stats reset and the +1/5 heal;
  - the camera: the orbit's position and angles for two fighter positions; the preset and viewpoint picks;
  - a whole tournament on a stub world to `DONE`, won and lost.
- `tests/arena_scan.tscn`: the real field on ROOM13, builtin 0x06 → the arena → the warp back, with a strong partner (wins) and a weak one (loses), checking no error, the result in script value 0xFF, the field reloaded.

## 8. Open questions

1. **The US release draws neither the intro's big name nor the bracket's names.** Confirmed in the matching US assembly (`asm/us/std/matchings/std_main/STD_renderIntroNameChar.s`, `STD_renderBracketGlyph.s`): neither reaches the ordering table (0 accesses, `STD_renderBracketDigimon` next to them has 2), so the primitives are built and dropped. The port builds the state (the timings depend on it: the stats appear when the last letter lands) and draws nothing, as the US game. A later option could draw them (the JP / EU behaviour).
2. **The status bars:** `STD_addFighterStatusBars` / `STD_renderFighterStatusBars` compared equal to btl's, with a fighter index. Step 5 checks whether `PartnerStatusBars` can take an index or the arena needs its own piece.
3. ~~Own fighter instances~~ **Decided 2026-11-01 (the user):** the arena is its own scene with its own fighter instances (§5.1, `port-only`). The C moves the field's partner and removes the map's NPCs, but the script warps right after, so none of it is visible.
4. **Cup 5 (Grade R)** expects 2 wins (`utils2.c:666`), but the loop always runs up to 3 matches. So winning all three counts as a loss, and losing the third counts as a win. Grade R is never on the schedule (`days` empty, `opponent_base_stat` 0), so it's likely unused. The port keeps the C.
5. ~~Match 3's projectile speed~~ Settled while writing the checks: match 7's unset `d` is never read (§3.2).

## As built (step 3, 2026-11-02)

- **`Battle`** got the hooks of §5.2 (each returns what its btl line did; `tests/test_battle.gd` 86/86 unchanged) and `tick_fighter_states` split into the shared cooldown, `_tick_fighters()` (the state loop both overlays share) and the hits / statuses.
- **`ArenaBattle`**, **`ArenaCamera`**, **`ArenaMatch`** (`scripts/systems/arena/`) as §5.2. `BattleWorld.set_location` (no-op default) for `STD_placePlayer1 / 2` and `STD_setPostIntroPosition`.
- **Found while porting** (in the spec's tables now):
  - both fighters' HP buffers drain every frame and MP is floored at 0 (`STD_renderFighterStatusBars`, no bar gate as in the field);
  - only the partner's finisher gauge is drawn (§4.6);
  - `STD_selectPartnerMove` writes `weights[keys[keys[i]]]` in the MP mode, `STD_selectEnemyMove` keeps the charge mode when nothing is usable (two differences the first comparison missed: near-copies at 0.99);
  - `FLEE_DISABLED[0]`, `FLEE_TIMER` and `HAS_TAKEN_DAMAGE` are never read in std;
  - `posData + 0x78` in `STD_handlePartnerMoveCommand` is `location` (`GsDOBJ2` 16 + `GsCOORDINATE2` 80 + scale 16 + rotation 8): the same as btl's;
  - the intro camera's curve (`processSomeArenaArrays`) would divide by zero past key 360 (its last two keys are 0): the camera is removed long before; `port-only` guard.
- **Order in a frame** (`ArenaMatch._objects`): the tamer's tick (Select, the commands), `STD_tickVSPhase` then the chase and the intro camera (their objects come after 0x1A8), the intro name and stats, the timer, the command menu, the effects, the charge-up, the start text, then the draws that change state (the damage buffers, the effects).
- **`port-only`:** pad 2 (the debug cameras 0 and 10) is not read; `GsSetRefView2`'s axes are computed in floats as the field's camera.
- **Tests:** `tests/test_arena.gd` gate 3: 78 checks (commands per brain band, every §4.5 rule against its btl behaviour, the damage buffers, each end-test branch and the time-out, the timer, the after-match heal, the orbit / top / champion / rotating cameras, a whole match won with real effects and a time-out draw without them). 232 with steps 2-3.
