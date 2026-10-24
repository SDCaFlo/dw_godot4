# Plans and ideas

Working list of what comes next and ideas not started yet. Keep it current: when something is done, move it to "Done" with the commit and drop the details that now live in the code / docs. Per-tool progress stays in `asset_porter/PROGRESS.md` and `data_porter/PROGRESS.md`; the high-level roadmap is in `README.md`.

Last updated: 2026-10-23

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
     - [ ] Backlog (graphics): a black area around the poop piles (reported 2026-10-23). Probably the pile's shadow polygon, semi-transparent in the TMD, drawn opaque by the glTF import (check the UNTI.TMD primitive flags and the asset porter's material export).
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
     - [ ] 3. NPCs (`specs/npc.md`): spawning, talking, autotalk, animations; `SECTION_ON_EXIT`; `CALL_DIGIMON_ROUTINE` (0 the partner's toilet scene, 7 the collapse) and the collapse script 0x4DE replacing the care stand-in;
     - [ ] 4. scripted movement and the camera (done early: the slot ticks and `ENTITY_WALK_TO` for the tamer and partner, tamer state 10 / partner state 12, so the 121 walk-out exits play);
     - [ ] 5. builtins, battles, items / chests, map objects, sound, with their systems.
   - [ ] Backlog (exits, found 2026-10-23): 17 trigger-cell exits play a short scene before their `WARP_TO` (camera moves, the partner's walks, turns, animations, NPCs): GCAN08_1 0x35, YAKA23 0x52, YAKA24 0x51, OGRE11 0x33, TOPN01 0x36, GCAN10 0x51, FACT01 0x51, OMOC04 0x51, OMOC05 0x51–0x53, OMOC06 0x51–0x53, OMOC07 0x51–0x53. Today the scene is skipped and the tamer stands through the fade. They play once steps 3–4 port `ENTITY_SET_ROTATION`, `ENTITY_LOOK_AT_ENTITY`, `ENTITY_WALK_TO_WITH_CAMERA`, `ENTITY_MOVE_TO(_AXIS)`, `PLAY_ANIMATION`; check them then (scan: every section with a warp, `specs/script.md` §2.7).
   - [ ] Backlog (controller, reported 2026-10-23):
     - with a gamepad, ✕ does nothing on text boxes, while movement works. Check which Godot actions the pad's buttons trigger (`ui_accept` joypad events in the project's input map), and map the PSX buttons as their own actions (`pad_confirm`, `pad_cancel`, …) for both keyboard and joypad.
     - on some maps, after moving with the stick and letting go, the tamer ends up facing down, as if down had been pressed in the last frame. Probably the stick passing through the deadzone or a diagonal on its way back to the centre, read by `Tamer._input_direction` (`Input.get_axis`, then `roundi`). Check the raw axis values on release, and read the d-pad like the PSX pad (digital directions, `Pad` bits) instead of analog axes.
5. **Next milestones, in order:** text and scripts (above: NPC dialogue, Jijimon intro, new game) → menus (inventory, feeding, items, Digimon status) → battle → evolution and training → tournaments and minigames.
6. **Field (as needed by the milestones):** NPC Digimon, map object sprites (water, fire), lighting, depth against the background, events.
7. **Text, later parts:** the battle / menu control codes (`#C1 #R #W` / `{C1}` / bare `C R W`, data_porter/specs/text.md §2) with their renderers; the `ja` font comes from the JP glyph table (`specs/text.md` §2.1).
8. **All system ports** (battle, care, evolution, menus): GDScript ports of the C logic, reading `GameData` properties (never id ranges); each function names the C function and the original condition it reproduces.
9. **Modding** (last; `specs/content.md` §7)
   - [ ] Mod formats: raw-file packs (folder + `pack.json`, no Godot needed) and `.pck` packs built in the editor.
   - [ ] Model contract for external models (animation names, scale, pivot, collision from data, textures); the asset porter names the original animations to the same contract.
   - [ ] "DW Data" dock as the modding tool: which packs changed a record, duplicate into a pack, edit, write the pack's JSON.
   - [ ] Mod loader UI: list packs, enable / disable, load order, conflicts.
   - [ ] Open questions: numeric ids for new content used by original scripts; a key lock file so `dw1` keys never change; conflicts between mods patching the same field.

## Ideas (not planned yet)

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

- 2026-10-23 — Partner follows the tamer (`165d61a`), clock (`2f3f505`), GameState (`90effc9`).
- 2026-10-23 — DW Data dock and its guide; its asset check found the data porter's wrong model folders (Digimon 30–179), fixed. Editor mirror and `Content` loader (`9eb9172`).
- 2026-10-23 — `Content` loader and the `res://content/dw1/` editor mirror; runtime animations now baked at 20 fps (were resampled at 30). Registry (`e161e05`), cards as their own kind (`7ee3ccf`), content keys (`280d3d0`).
- 2026-10-23 — Content architecture spec (`specs/content.md`).
- 2026-10-23 — Field scene editor preview (`8a29c15`, tamer meshes `74a678b`; this file created).
- 2026-10-22 — `GameData` autoload (`907f6bc`); data porter complete (text, moves, Digimon, items, evolution, systems).
