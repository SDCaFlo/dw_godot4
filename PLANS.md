# Plans and ideas

Working list of what comes next and ideas not started yet. Bugs found while playing are in `ISSUES.md` (with their evidence). Keep it current: when something is done, move it to "Done" with the commit and drop the details that now live in the code / docs. Per-tool progress stays in `asset_porter/PROGRESS.md` and `data_porter/PROGRESS.md`; the high-level roadmap is in `README.md`.

Last updated: 2026-10-26

## Rules for everything below

- Game content (assets, data, text) is generated locally and never committed. Editor helpers may show it, but only from memory or from gitignored folders: nodes created for a preview have no `owner` (not saved), saved properties are reset before a save (`NOTIFICATION_EDITOR_PRE_SAVE`), glTF textures are kept in memory (`Content.load_model`), and game content is only copied into the gitignored `res://content/dw1/` mirror. An export preset must exclude `content/dw1/*`.
- **Content architecture** (`specs/content.md`, decided 2026-10-23): everything is a content pack (the original game is the `dw1` pack); records have namespaced keys (`dw1:agumon`), numeric ids stay as `dw1` aliases; packs merge per record; **game logic reads properties, never id ranges or counts**. Modding is the last step, but nothing may be built in a way that blocks it.

## Next

1. **Content foundations** (`specs/content.md`, "Order of work")
   - [x] Design spec `specs/content.md`.
   - [x] Data porter: `key` on every entity record (§2 key rule, uniqueness check) and the `dw1` `pack.json` manifest.
   - [x] `GameData` as the pack registry: key lookups next to numeric aliases, entity view (components, §3), record-level merging (add / patch / remove, §5), replacing the whole-file mod folders.
   - [ ] Later in the registry (when needed): text in packs (new string ids; today pack records give names inline), `load_after` ordering, conflict reports.
   - [ ] Property flags (§4): added per system when that system is ported; techniques first (`move.kind`, `learnable`).
2. **Editor visibility** (seeing the game content while working in Godot)
   - [x] Field scene previews in the editor (`@tool` field scripts; pick `start_map` / `start_spawn` / `time_of_day` in the Inspector).
   - [x] `Content` loader (`scripts/content/content.gd`, was `PorterAssets`, §6): Godot-imported copy under `res://content/dw1/` if present, else the raw file.
   - [x] `res://content/dw1/` mirror: Project > Tools > "DW: Mirror dw1 assets" (`addons/dw_tools`) copies models, map backgrounds / doors and cards, with import settings that keep the animations exact (§6). Gitignored.
   - [ ] Export preset excluding `content/dw1/*` (when the first export is made).
   - [ ] Same preview pattern for the next scenes (battle, menus) as they are built.
   - [x] "DW Data" dock, read-only (`addons/dw_tools/data_dock.gd`, guide `docs/dw_data_dock.md`): Digimon / techniques / items / cards / maps / tournaments / tables, search, links, language, model / card / map previews, porter check status, asset check.
   - [ ] Dock later: text search across all strings, item icon / technique effect / map object previews.
3. **Milestone "living field"** (decided 2026-10-23): the world runs while you walk; no text or scripts needed yet.
   - [x] `GameState` spec (`specs/game_state.md`): every C global / `SavedState` / `PartnerPara` field mapped to a Godot field with `file:line`, content by key, save / load as JSON in `user://`.
   - [x] `GameState` autoload + save / load + tests (`scripts/state/game_state.gd`, `tests/test_game_state.gd`, `VERIFY.md`).
   - [x] Clock: port `clock.c`; day / evening / night switch the map backgrounds; HUD clock (`specs/clock.md`, `scripts/systems/clock.gd`, `GameLoop` 20 Hz frames, `tests/test_clock.gd`).
   - [x] Partner in the field: loaded from its `GameData` entity, follows the tamer like `partner.c`, idle / walk / run animations (`specs/partner.md`, `scripts/field/partner.gd`, `tests/test_partner.gd`).
   - [ ] Later with NPCs: entity collisions for the tamer and NPCs, the exact movement / collision split (`specs/partner.md` §5); partial animation loops in `PsxAnimator`.
   - [ ] Care ticks: hunger, energy, sleep, poop, sickness, lifetime (`partner.c`, `partner_impl.c`), rules reading properties (`care` component); debug panel.
     - [x] Spec `specs/care.md`.
     - [x] Data porter: the §4 properties (`raise_data.first_technique`, `eats_poop`, `raises_virus_bar`; `item_data.passive`) with checks on the C text.
     - [x] `Care` (`scripts/systems/care.gd`) + partner states 1, 3, 7, tamer state / camera follow / scene animations, `Fade`; partner ticks before the clock; area response from the map setup; `tests/test_care.gd`; debug key `Z` for the menu's Sleep.
     - [x] Bubbles (`feel_ef`, STP split by `PsxTexture`), status bars (`system_w`), poop piles (`UNTI`), fade.
     - [x] Backlog (graphics): fixed 2026-10-24 as ISSUES.md I-5 (`5fdc59e`). Was: a black area around the poop piles (reported 2026-10-23). Probably the pile's shadow polygon, semi-transparent in the TMD, drawn opaque by the glTF import (check the UNTI.TMD primitive flags and the asset porter's material export).
     - [ ] Later: the bubble's bone offset (`CONDITION_FX_OFFSETS`, effect_common.c:307) into the data / asset porter; the butterfly (`butterfly.c`); `createCloudFX` with the effects.
     - [x] Debug panel (`C`, `scripts/debug/care_debug_panel.gd`, `GameLoop.speed`), `tests/test_care.gd`, VERIFY section.
   - How each system is ported: a short spec (C functions reproduced, state and data read) → GDScript naming each C function → headless tests with values worked out from the C code → VERIFY section → this file.
4. **Milestone "text and scripts"** (started 2026-10-23):
   - [x] Text renderer spec (`specs/text.md`): font, text area, `renderString`, UI boxes, message box, dialogue box.
   - [x] Data porter group `font` (`data_porter/specs/font.md`): glyph tables per language, `FONT_CLUT`, `TEXT_COLORS`, ASCII map, glyph sheets; 52 checks including each language's text coverage; `GameData.font()` and friends.
   - [x] `PsxFont`, `TextArea`, `PsxDraw`, `UIBoxes`, `MessageBox` in `scripts/ui/` (reusable for new windows, menus, shops: guide `docs/ui.md`); tamer state 20 shows "<name> is sick"; partner state 11; `GameLoop.pad_pressed` (`POLLED_INPUT`); `tests/test_text.gd`; VERIFY "Text and windows".
   - [x] `TextBoxes` (all of `script_textbox.c`: `showTextbox`, `drawString2`, pages, choices, custom size; `specs/text.md` §2.6–2.7), `ScriptContext` (the interpreter's globals), `Pad` (`POLLED_INPUT` / `CHANGED_INPUT` / `isKeyDown`, §2.8; the tamer's box now closes on a held ✕ like the C), debug player `D` (replaced by the interpreter's section runner).
   - [ ] Event-script interpreter (`specs/script.md`, spec written 2026-10-23). Order (§3.1):
     - [x] 1. core: `ScriptFiles`, `ScriptInterpreter` (flow, IF, stack, values, triggers, money, items, cards, stats, dates, text, DELAY), unported opcodes skipped and reported; `D` runs the map's sections; data porter `systems/script_stat_limits`; `tests/test_script.gd` runs all 1269 sections and 255 map setups to their end;
     - [x] 2. entry points: map entry through MAPHEAD (`SET_SCRIPT`, section 0xFE, `setupMap`), warp cells (tamer state 5: fade, map name `scripts/ui/map_name.gd`, `changeMap`), trigger cells 51–109, toilet cell (section 0x4E2), `WARP_TO` / `TELEPORT`; data porter `change_map_previous` (63 checks); `Fade` now covers the screen (its rect had size 0); VERIFY "Map changes";
     - [x] 3. NPCs (`specs/npc.md`; `FieldDigimon` shared with the partner, `Npc`, `FieldEntities`, the entity opcodes, talking; `tests/test_npc.gd`; VERIFY "NPCs"), option A (decided 2026-10-23): spawning, talking, autotalk, animations; the NPCs stand with their idle animation between talks (spec written 2026-10-23). `CALL_DIGIMON_ROUTINE` moved out: the toilet scene (routine 0) goes to step 4 (camera pan), the collapse / battle loss (7 / 9, the `MURD` + `DOOA` scenes) becomes its own "death and lives" system with the collapse script 0x4DE;
     - [x] 3b. (after 3) NPC behaviour between talks, option B (done 2026-10-24): `NPCEntityTickWaypointAI` / `NPCEntityTickWaypointWalk` (wandering on waypoints) and the `followMode` branches (`NPCEntityTickLookingAtTamer`, `TrackingTamer` 1–4) of `NPCEntityTickOverworld` (`overworld.c:1224`). Step 3 ports that function's frame with these two branches empty, so 3b only fills them in. Spec and code 2026-10-24 (`specs/npc.md` §2.10, §3.4; `Npc` AI, `FieldDigimon` blocked axes and `check_collision`, the partner's NPC bumps; VERIFY "NPCs" 7–11);
     - [x] 4. scripted movement and the camera, and the partner's toilet scene (`CALL_DIGIMON_ROUTINE` 0, needs the camera pan) (done early: the slot ticks and `ENTITY_WALK_TO` for the tamer and partner, tamer state 10 / partner state 12, so the 121 walk-out exits play). Spec written 2026-10-24: `specs/camera.md` (new: the follow by the tamer's motion with the virtual scroll, pans, moves with the camera), `specs/script.md` §2.7 "Step 4" (slot types 3–11, 14, 15, `WAIT_FOR_ENTITY`, the sync bit), `specs/care.md` §2.16 (the toilet scene). Coded 2026-10-24 (`tests/test_camera.gd`; VERIFY "Camera");
     - [ ] 5. with their systems, split (`specs/script.md` §3.1): 5a map objects, 5b items / chests on the map, 5c sound and music, 5d battles, 5e the builtins with their menus;
       - [x] 5a. map objects: spec written 2026-10-24 (`specs/map_objects.md`: overlay sprites, `SET_OBJ_VISIBILITY`, `MOVE_OBJECT_TO`, doors `ROTATE_3D_OBJECT`, `SET_RECT_IMPASSABLE`, builtin 0x15, File City's lights, snow; asset porter door slots; data porter `light_objects`, `snow`). Coded 2026-10-24 (`MapOverlays`; the background moved into the 3D viewport, `Environment.BG_CANVAS`, so sprites blend with it; STP masks from the asset porter; `tests/test_map_objects.gd`, `tests/render_check.gd`; VERIFY "Map objects");
       - [x] 5b. items and chests: coded 2026-10-24 (`MapItems`, `MapChests`, tamer states 7 / 14; `tests/test_map_items.gd`; VERIFY "Items and chests"). Spec written 2026-10-24 (`specs/map_items.md`: items on the ground, the pickup (tamer state 7), chests (state 14) with their tray and trigger, the box texts, the sounds). Then: the entities' drop shadows (see below).
       - [ ] Scene composition refactor (decided 2026-10-24, after 5b, before 5e), so `.pck` mods and the editor can see, override and extend the field's parts; data mods keep going through the content packs (`specs/content.md`). The ported logic stays in plain classes and the 20 Hz `GameLoop` stays; scenes are the layer that assembles them:
         1. [x] Design note (`specs/scenes.md`, written 2026-10-24): the scene layout, how components find each other (exports / node paths, no globals beyond the autoloads), what stays plain logic, what a mod may override.
         2. [x] Entity scenes (done 2026-10-24; behaviour-neutral, all tests unchanged): a `Digimon.tscn` shell (script + components: animator, animation sounds, drop shadow; an empty `Model` slot filled from the Digimon's record), `Partner.tscn` / `Npc.tscn` on it, the tamer likewise; the tests instantiate the scenes.
         3. [x] The drop shadows (below) as the first component written this way (done 2026-10-24).
         4. [x] Split `field.gd` (done 2026-10-24: 805 -> 255 lines): the hosts `Systems/Entities`, `MapSession`, `ScriptHost`, `CareHost`, `ClockHost` and `Debug` (`scripts/field/hosts/`); the field keeps the start order, the wiring and the frame order (`Field._frame`, the one `GameLoop.frame` connection; Clock, ClockHud, StatusBars, ConditionBubbles, UIBoxes and CareDebugPanel no longer connect themselves). The 15 test suites and `tests/exit_scan.tscn` pass unchanged.
         5. Then 5e's menus are built as scenes from the start.
         6. [ ] Placing map Digimon (raised 2026-10-26, **to discuss**): today a map's Digimon come from data (the map's 8-slot table: type, position, stats, script id; `FieldEntities`, `specs/npc.md`) and appear when the map script runs `SET_DIGIMON`. Each one is an `npc.tscn` instance, but nothing is placed in the editor and one Digimon type can't have its own scene. For modders making maps with wild Digimon, ideas: an editor marker node (`DigimonSpawn`) that writes the same table, so the original's data stays the default; a per-Digimon scene override (custom components, AI); lifting the 8-slot limit for mod maps. *Side note: we need to evaluate the possibilities (marker nodes, scene overrides, data-only, the slot limit, how scripts find the Digimon) before deciding; nothing is decided.*
       - [x] Drop shadows (coded 2026-10-24: `DropShadow`, `scenes/field/drop_shadow.tscn`, `specs/drop_shadow.md`; VERIFY "Drop shadows"; the item shadows use its material): `renderDropShadow` (`drop_shadow.c`) under the tamer, the partner and the NPCs: a radius-sized subtractive square of `ETCDAT/SPOT256.TIM` (cell (64, 0), 63 x 63, palette row 487), colour 0x30, at OT 0xFFD, skipped on blocked cells; shares the item shadow's material (`specs/map_items.md` §2.1, §6).
       - [x] 5c. sound and music: spec written 2026-10-24, coded 2026-10-24 (the `Sound` autoload, `scripts/audio/`; the asset porter's `music` family renders the 74 songs; `tests/test_sound.gd`, `asset_porter/tests/test_music.py`; VERIFY "Sound"). Was: spec written 2026-10-24 (`specs/sound.md`; `asset_porter/specs/sound.md` "Music render": the songs rendered offline with libsnd's sequencer / voice manager and the SPU, from the decomp's libsnd asm and the executable's tables; effects played live by `Sound` with the SPU envelope). Order: (1) asset porter renderer + tests, (2) `Sound` / `Music` in Godot + wiring + `tests/test_sound.gd`, (3) VERIFY "Sound". Not in 5c (left to their steps): chest / item sounds (5b), battle music and banks (5d), menu, shop and partner-interaction sounds (5e);
       - [ ] 5d. battles (started 2026-10-26; spec approved 2026-10-26: `specs/battle.md`, `specs/battle_effects.md`). Includes the battle music (`stopBGM`, `ENEMY_MUSIC_MAPPING`, font 33, `playBGM` after a win) and the fighters' sound banks 4–7. Steps (`specs/battle.md` §7):
         - [x] 5d-1. Data and assets (done 2026-10-26: data porter moves 34/34, Digimon 42/42, systems 103/103; asset porter `btl_rel` 14/14, `efe.bin`, `targets_partner`): move `buff` / `counter`, Digimon `battle_music` / `battle_scale` / `anim_technique`, map `concave` / `no_battle_drops`, the battle HUD tables, `systems/psx_math`; asset porter `btl_rel` family, `efe` raw slot bytes, `map.json` `unk1` → `targets_partner`.
         - [x] 5d-2. The effect API and VM, logic part (done 2026-10-26; `specs/battle_effects.md` "As built": 41 checks, all 120 effects run, 8 miss the stub target, to recheck with real fighters in 5d-3) (`PsxMath`; `BattleEffect` scene API + `BattleEffectContext` + `EffectHost`, decided 2026-10-26 so techniques can be modded; `EfeEffect` / `EfeVm` with every opcode and non-drawing built-in, the hits; `tests/test_efe.gd` runs all 120 effects and a test mod effect).
         - [x] 5d-3. The battle logic and the field hook-up (done 2026-10-26; `specs/battle.md` "As built": items in battle moved to 5d-4) (`Battle`, `BattleHost`, the phases, the tamer's waypoints, `START_BATTLE` and its outcomes, care and time after, rewards, items in battle; a plain HUD; `tests/test_battle.gd`; VERIFY "Battles").
         - [x] 5d-4. The HUD as the original draws it, and items in battle (done 2026-10-26; `specs/battle.md` "As built (5d-4)"): the ten HUD pieces as scenes (`scenes/battle/battle_hud.tscn`, `scenes/battle/hud/`, `scripts/ui/battle/`), the inventory's battle mode, the throw (`BattleThrownItem`), the item effects' battle branches (`item_effects.battle`); `tests/test_battle_hud.gd`; VERIFY "Battles".
         - [ ] 5d-5. Drawing the effects, then the status / aura / buff / item visuals (detailed spec approved 2026-10-27: `specs/battle_effects.md` §7). Sub-steps:
           - [x] 5d-5a (coded 2026-10-27, `specs/battle_effects.md` "As built (5d-5a)", VERIFY "Battle effects"): `EfeView` (models, UV animations, colours, projected sprites), the shared effects' logic (`BattleFx`: sparks with their rolls, entity particles, clouds, flashes) and view (`BattleFxView`, with the emitters), the Effects gallery tab, I-27 (`loadSB`), the field's `GsWSMATRIX`.
           - [x] 5d-5b (coded 2026-10-27, `specs/battle_effects.md` "As built (5d-5b)", VERIFY "Battle effects"): the screen primitives at their OT depth, the world primitives (3D quad, waves, ribbon, ring tube, lines, wireframes), the CLUT writes (`EfeTexture`), `drawTMDScreenSpace`, the fixed view and the map layer; the bones' real rotation (fixed: techniques fired along a bone flew off); the gallery's distance setting. Left to compare with the original: Deadly Bomb's lob distance, High Electro Shocker's bone table.
           - [ ] 5d-5c: the other visuals (§4) and the healing particles (I-21).
           - [ ] Refine: the techniques look very transparent: moved to `ISSUES.md` I-30 (2026-10-27), for the issue backlog.
         - [ ] Debugger: partner tools (asked 2026-10-27): **Digivolve to** any Digimon (a picker, through the evolution rules' change of Digimon) and **Learn all techniques** (every technique the partner's Digimon can learn), to try any Digimon and test techniques in battle.
         - [ ] Battle debugger (asked 2026-10-26, for future debugging): a debugger tab or overlay with each fighter's live battle state: the speed meter (`speedBuffer`) and its refill per frame (`speed / 100 + 1` every other frame), the charge mode and requirement, the cooldown, the flags (charging, cooldown, busy, knocked back…), the queued technique and target, the move range, HP / MP with their damage buffers, the finisher gauge; and the phase, the flee timer, the death countdown. The scan's `BATTLE_DEBUG` dump is the start of its contents.
       - [ ] 5e. builtins and menus, each a scene from the start (`specs/scenes.md` §4.3), each wiring its sounds (`Sound.play_sound`):
         1. [x] The △ menu (`specs/game_menu.md`, coded 2026-10-25: `scenes/ui/game_menu.tscn`, `Systems/MenuHost`, `tests/test_game_menu.gd`, VERIFY "The △ menu"; spec written 2026-10-24): opening / closing, the icons, cursor and date, Praise / Scold (partner states 15 / 4, tamer states 13 / 9, sounds 14 / 13) and Sleep; what stops while it is open; data porter `raise_data.praise_pat_low`. The debug key Z and the care panel's Sleep now go through the menu's Sleep.
         2. [x] Items (`specs/inventory.md`, coded 2026-10-25: `ItemUse`, `scenes/ui/inventory.tscn`, the feeding scene, `tests/test_inventory.gd`, VERIFY "Items"; spec written 2026-10-25): the inventory (`inventory.c`: list, Use / Move / Sort / Drop), feeding (partner state 5) with the refusal rules (`ITEM_SCOLD_FLAG`) and the hunger rule, the field effects of every item (`ItemEffects`); data porter `item_data.feeding`, `item_effects.evolution.requires_level`. Evolution items wait for evolution.
         3. [x] The Digimon and Player screens (`specs/status_screens.md`, spec written 2026-10-25), coded in two parts: [x] 3a the Digimon screen (coded 2026-10-25; `tests/test_digimon_screen.gd`, VERIFY "The Digimon screen") (Status, Techniques with equipping; data porter `move_data.menu_cell`; the partner's model in the window), [x] 3b the Player screen (coded 2026-10-25; `tests/test_player_screen.gd`, VERIFY "The Player screen") (Info, Evolution chart, Medals with the 3D medal, Cards with their pictures). Idea: the chart and card pages hold the original's 61 Digimon / 66 cards (layout tables in the scripts); a content pack adding some would need extra pages.
         4. [ ] The script builtins with their menus, one at a time (shops, item bank, jukebox, Birdramon, training, tournaments, naming, save, ...).
            - [x] 4a. The script item menu, the shop and recycle shop (0x08), the bits box (0x0F), the item picker (0x00), and the routine host the later builtins plug into (`specs/shops.md`; coded 2026-10-25, `tests/test_shops.gd`, VERIFY "Shops").
            - [x] 4b. The card shops (0x0E: pack, single card, selling; Gear Savanna's Market Manager), the merit shop (0x01), Mojyamon's trades (0x02) (`specs/card_shops.md`; coded 2026-10-25, `tests/test_card_shops.gd`, VERIFY "Card shops, merit shop, Mojyamon").
            - [x] 4c. The item keeper (0x0B), the jukebox (0x09), Birdramon's transport (0x0A) (`specs/town_services.md`; coded 2026-10-25 with the porter's jukebox fields, `tests/test_town_services.gd`, VERIFY "Item keeper, jukebox, Birdramon").
            - [ ] 4d. Training (0x07, `specs/training.md`):
                - [x] 4d-1. The core (gains, the hour, the stats box) and HP at the Green Gym, with the field pieces (coded 2026-10-25, `tests/test_training.gd`, VERIFY "Training").
                - [x] 4d-2. Offense, Speed, Defense, MP, Brains (new orders, move learning): the eight stations of TRAI00, GIAS09 and MIST05, hit sparks, two data tables (`specs/training.md` §6).
                - [x] 4d-3. The slot-machine bonus (Bonus Try): `SlotMachine`, `SlotSession`, `TrainingSlotsBox` (box 3), the stations' hooks, the `systems/slot_machine` table and the gym maps' slot textures (2026-10-26, `specs/training.md` §7, VERIFY "Training" 4).
                - [ ] 4d-4. The TRN2 stations (maps 0x63, 0x6B, 0x6C, 0xA5). **On hold** (2026-10-26: evolution first); it keeps its place here.
            - [ ] 4e. Tournaments (with 0x16, the medal check), naming / new game, save.
         - Fishing (the menu's 7th icon) comes with fishing.
         - [ ] The healing particles of the recovery items (ISSUES.md I-21, reported 2026-10-26): `addHealingParticleEffect` (`main/particle.c:209`) from the item handlers, with its variants; a field effect, independent of the battles.
       - [ ] To check in the game: the additive sprites' brightness (Godot blends in linear colour), Grey Lord's Mansion doors (YAKA11, models 9 / 10) snapping shut at the end of their swing (`specs/map_objects.md` §6);
     - [ ] 5f. Evolution (decided 2026-10-26, before 4d-4 and the battles; `specs/evolution.md`): the rules of `main/evolution.c` (when and into what the partner evolves: stats, care, weight, battles, the evolution items), then the evolution scene (`evl` overlay). Battles won read the counter, 0 until 5d. Unblocks the evolution items (5e-2) and I-16.
  - [x] 5f-1, the rules (2026-10-26): `evolution/rules` table, `Evolution`, partner state 13 with a stand-in scene, script routines 2 / 10, the evolution items; 101 checks (`specs/evolution.md` "As built").
  - [ ] 5f-2, the scene (`evl` sequence: palette fades, camera orbit, shards, flashes): detailed spec first.
     - [ ] 6. death and lives (after the battles): the collapse and the battle loss (`CALL_DIGIMON_ROUTINE` 7 / 9, the `MURD` + `DOOA` scenes, ~2350 lines of C), the collapse script 0x4DE replacing the care stand-in.
   - [ ] To check in the real game (`specs/npc.md` §6): after a scene that walks or animates an NPC, on a map with a slot-7 NPC (script id 12, e.g. File City's Whamon on TWNA02–13), can you still walk into it and talk to it? It tells the leftover value of the original's `setActiveAnim(0xC)` bug.
   - [ ] To check in the real game (`specs/npc.md` §6, step 3b): DGHA02's slot-2 Tsukaimon (path `1 1 0 0`, only 2 waypoints) and FACT04's slot-6 NPC (path `0`, no waypoint) read a path step the map data doesn't have; the C uses the slot's value from the previous map. Watch them after entering from different maps: how long do they wait, where do they walk? The port waits 0 frames.
   - [ ] Backlog (NPC behaviour, 2026-10-24): compare step 3b with the original game, the chasing most of all (`VERIFY.md` NPCs 7–11). Works roughly; the user wants to check whether the follow modes feel as aggressive as the original: when an enemy notices you (the tracking rect, strict edges around its map position), how fast it charges (walk then run, turning 0x71 per frame), where it stops (the tile you stood on, or touching you), the 40-frame wait, the walk home. Things to check if it differs: the PSX `_atan` vs the port's `atan2` rounding, the root-motion speed of animations 2 / 4, the turn rate, the order of the AI and the collision in the frame. Tune only to match the original (the C is the reference).
   - [x] Backlog (exits, found 2026-10-23): the 17 trigger-cell exits with a short scene before their `WARP_TO` play (checked 2026-10-24, `tests/exit_scan.tscn`, VERIFY "Map changes" 5).
   - [ ] UI filter shader: Godot prints `ERROR: Condition "!actions.custom_samplers.has(function->arguments[j].tex_builtin)" is true. Continuing.` when compiling `PsxUiFilter` (the built-in `TEXTURE` passed to its functions). First verify whether it is a real error or only a log: does the filter's texture lose its sampler settings (filter / repeat), does it show in the windowed game too or only headless, is it a known Godot 4.7 issue? The filter draws right today. If it is real, sample `TEXTURE` inside `fragment()` only.
   - [x] Backlog (controller, reported 2026-10-23): fixed 2026-10-24, see "Done".
5. **Next milestones, in order:** text and scripts (above: NPC dialogue, Jijimon intro, new game) → menus (inventory, feeding, items, Digimon status) → battle → evolution and training → tournaments and minigames.
6. **Field (as needed by the milestones):** NPC Digimon, map object sprites (water, fire), lighting, depth against the background, events.
   - [ ] Field pause (`handlePause()`, `utils2.c:402`: static UI box 5, pause frame loop, PadRead 0x800).
   - [ ] Misty Trees mist overlay (`renderMist()`, `overworld.c:550–660`: multi-layered scrolling semi-transparent poly effect for maps `MIST01`–`MIST07`, fade via `tickRemoveMist()`).
7. **Text, later parts:** the battle / menu control codes (`#C1 #R #W` / `{C1}` / bare `C R W`, data_porter/specs/text.md §2) with their renderers; the `ja` font comes from the JP glyph table (`specs/text.md` §2.1).
8. **All system ports** (battle, care, evolution, menus): GDScript ports of the C logic, reading `GameData` properties (never id ranges); each function names the C function and the original condition it reproduces.
9. **Modding** (last; `specs/content.md` §7)
   - [ ] Mod formats: raw-file packs (folder + `pack.json`, no Godot needed) and `.pck` packs built in the editor.
   - [ ] Model contract for external models (animation names, scale, pivot, collision from data, textures); the asset porter names the original animations to the same contract.
   - [ ] "DW Data" dock as the modding tool: which packs changed a record, duplicate into a pack, edit, write the pack's JSON.
   - [ ] Mod loader UI: list packs, enable / disable, load order, conflicts.
   - [ ] Open questions: numeric ids for new content used by original scripts; a key lock file so `dw1` keys never change; conflicts between mods patching the same field.

## Ideas (not planned yet)

- Sound: mirror the sound samples and rendered songs into `res://content/dw1/` with QOA compression (the songs are ~0.9 GB of WAV); the CONFIG menu's music / effects volumes (buses `Music`, `Sfx`).

- A CONFIG menu for players: the 3D render scale and the text and windows' filter (ISSUES.md D-2, D-3), later other options.
- Try other upscaling filters for the text and windows (today Scale4x, ISSUES.md D-3): e.g. xBR / ScaleFX-style edge filters, HQx, a CRT look; compare them with the game in an emulator, and offer the good ones in the CONFIG menu.

- Import original memory-card saves (`.mcr` / `.mcd`): `specs/game_state.md` maps the whole `SavegamePayload` layout.
- Godot `.tres` resources generated from the pack data for editor use (gitignored for `dw1`).

## Notes

- Godot 4.7.2 (Steam): `F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`; run the headless tests with it on the real project (`--headless --path . -s res://tests/<test>.gd`). `godot.exe` on the PATH is an older 4.3 (`godotenv`); earlier checks used it on a scratch copy. 4.7 prints a GDScript backtrace under every error / warning, the tests' expected ones included.
- glTF loaded by a `@tool` script behaves differently in the editor: textures default to "extract" (the editor tries to copy them into the project) and meshes come out as `ImporterMeshInstance3D`, which don't render. `Content.load_model` handles both; always load models through it.
- Godot's scene importer defaults (30 fps bake, AnimationPlayer optimizer) distort PSX animations; dw1 models need `Content.MODEL_IMPORT` (written by the mirror). The optimizer is a per-node import option, so it can't be a project default. The runtime glTF loader also bakes at 30 fps unless told otherwise (`generate_scene(state, 20, …)`).
- Expected editor noise: `Basis … must be normalized` while importing the mirror (zero-scale keys in 12 models, `asset_porter/specs/mmd.md` open questions); `editor_resource_preview … !cache.has` while thumbnails are rebuilt (Godot). The tamer sets its root-motion track only in the running game (the editor's NodePath check misreads it as invalid).
- A headless 4.3 `--import` of the fresh mirror needs two passes (models before their textures in pass 1: "No loader found" errors, gone in pass 2); about 3 min in total here.
- Editor debugging: script `print()` from tool scripts doesn't reach the console of a headless editor; `push_warning()` does.
- In `godot -s` mode autoload names aren't registered: tests instantiate scripts directly, or run through the main scene.

## Done

- 2026-10-24 — ISSUES.md I-8: the snow maps' scenery sprites (Freezeland's boulder, ice) were lost on the second overlay load and the tamer drew over them.

- 2026-10-24 — Step 5c, sound and music: the songs rendered offline by the asset porter (`music` family: libsnd's sequencer and voice manager checked against DW's libsnd asm, on an SPU emulation with the Studio B reverb; tables read from the executable); the `Sound` autoload plays them (day / night variants, `SET_BGM`, `STOP_BGM`, the clock's `updateBGM`) and the sound effects voice by voice (`playSound`, the SPU envelope, voices 10–23): script `PLAY_SOUND`, text boxes and windows, the animations' footsteps, the map's and the partner's banks.

- 2026-10-24 — The 17 exits with a short scene play (steps 3–4 ported their opcodes): `tests/exit_scan.tscn` plays each one in the field scene (21 runs: GCAN08_1's two visits, Toy Town's locked door and its random doors, right and wrong); still skipped on the way, with their steps: sounds, chests, battles, builtins 0x2B / 0x2C / 0x37.

- 2026-10-24 — Controller bugs (reported 2026-10-23): Godot's `ui_accept` / `ui_cancel` have no joypad buttons, so ✕ did nothing on a pad; now one action per PSX button (`pad_cross`, …, `Pad.add_actions`, keyboard + joypad). The tamer faced down on releasing the stick: a weak tilt rounded to (0, 0), whose missing offset defaulted to 0 (down); now he walks on the d-pad bits like `tamerTickWalkingState` (direction kept when nothing is held; R1 or △ runs).

- 2026-10-24 — ISSUES.md D-3: the text and windows' upscaling filter (`PsxUiFilter`, Scale4x, on by default); I-6 / I-7 (`95ee1cf`).

- 2026-10-24 — ISSUES.md I-6 (texels sampled as the PSX: no speckles), I-7 (the camera's shake at 4×).

- 2026-10-24 — ISSUES.md D-1 (the debugger window: status, map list, render scale) and I-3 (3D render scale, 4× by default); I-6 (Palmon's shimmering) logged.
- 2026-10-24 — ISSUES.md I-5 (`5fdc59e`).

- 2026-10-24 — ISSUES.md I-5 details: the PSX semi-transparency of model polygons (STP masks from the asset porter, `PsxLit` blended passes): the poop's shadow.
- 2026-10-24 — ISSUES.md I-2: the field lighting (`specs/lighting.md`: the map's lights and the ambient per vertex, by the time of day; `PsxLit`, `FieldLighting`, `tests/test_lighting.gd`; `19fd5b8`).
- 2026-10-24 — ISSUES.md (new) with I-1 (sprites in front of the tamer) and I-4 (night holes) fixed (`fbcf612`).

- 2026-10-23 — Partner follows the tamer (`165d61a`), clock (`2f3f505`), GameState (`90effc9`).
- 2026-10-23 — DW Data dock and its guide; its asset check found the data porter's wrong model folders (Digimon 30–179), fixed. Editor mirror and `Content` loader (`9eb9172`).
- 2026-10-23 — `Content` loader and the `res://content/dw1/` editor mirror; runtime animations now baked at 20 fps (were resampled at 30). Registry (`e161e05`), cards as their own kind (`7ee3ccf`), content keys (`280d3d0`).
- 2026-10-23 — Content architecture spec (`specs/content.md`).
- 2026-10-23 — Field scene editor preview (`8a29c15`, tamer meshes `74a678b`; this file created).
- 2026-10-22 — `GameData` autoload (`907f6bc`); data porter complete (text, moves, Digimon, items, evolution, systems).
