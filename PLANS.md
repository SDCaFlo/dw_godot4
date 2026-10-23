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
   - [ ] `GameState` autoload + save / load + tests.
   - [ ] Clock: port `clock.c`; day / evening / night switch the map backgrounds; HUD clock.
   - [ ] Partner in the field: loaded from its `GameData` entity, follows the tamer like `partner.c`, idle / walk / run animations.
   - [ ] Care ticks: hunger, energy, sleep, poop, sickness, lifetime (`partner.c`, `partner_impl.c`), rules reading properties (`care` component); debug panel.
   - How each system is ported: a short spec (C functions reproduced, state and data read) → GDScript naming each C function → headless tests with values worked out from the C code → VERIFY section → this file.
4. **Next milestones, in order:** text renderer + event scripts (NPC dialogue, Jijimon intro, new game) → menus (inventory, feeding, items, Digimon status) → battle → evolution and training → tournaments and minigames.
5. **Field (as needed by the milestones):** NPC Digimon, map object sprites (water, fire), lighting, depth against the background, events.
6. **Text renderer** (with the scripts milestone): control codes (`#C1 #R #W` / `{C1}` / bare `C R W`), button and bits glyphs, a font with kana for `ja` (data_porter/specs/text.md §4).
7. **All system ports** (battle, care, evolution, menus): GDScript ports of the C logic, reading `GameData` properties (never id ranges); each function names the C function and the original condition it reproduces.
8. **Modding** (last; `specs/content.md` §7)
   - [ ] Mod formats: raw-file packs (folder + `pack.json`, no Godot needed) and `.pck` packs built in the editor.
   - [ ] Model contract for external models (animation names, scale, pivot, collision from data, textures); the asset porter names the original animations to the same contract.
   - [ ] "DW Data" dock as the modding tool: which packs changed a record, duplicate into a pack, edit, write the pack's JSON.
   - [ ] Mod loader UI: list packs, enable / disable, load order, conflicts.
   - [ ] Open questions: numeric ids for new content used by original scripts; a key lock file so `dw1` keys never change; conflicts between mods patching the same field.

## Ideas (not planned yet)

- Import original memory-card saves (`.mcr` / `.mcd`): `specs/game_state.md` maps the whole `SavegamePayload` layout.
- Godot `.tres` resources generated from the pack data for editor use (gitignored for `dw1`).

## Notes

- Godot on this machine's command line is 4.3 (`godotenv`); the project targets 4.7. Headless checks have been run with 4.3 on a scratch copy of the project (so 4.3 doesn't touch `.godot/`); the user runs 4.7.
- glTF loaded by a `@tool` script behaves differently in the editor: textures default to "extract" (the editor tries to copy them into the project) and meshes come out as `ImporterMeshInstance3D`, which don't render. `Content.load_model` handles both; always load models through it.
- Godot's scene importer defaults (30 fps bake, AnimationPlayer optimizer) distort PSX animations; dw1 models need `Content.MODEL_IMPORT` (written by the mirror). The optimizer is a per-node import option, so it can't be a project default. The runtime glTF loader also bakes at 30 fps unless told otherwise (`generate_scene(state, 20, …)`).
- Expected editor noise: `Basis … must be normalized` while importing the mirror (zero-scale keys in 12 models, `asset_porter/specs/mmd.md` open questions); `editor_resource_preview … !cache.has` while thumbnails are rebuilt (Godot). The tamer sets its root-motion track only in the running game (the editor's NodePath check misreads it as invalid).
- A headless 4.3 `--import` of the fresh mirror needs two passes (models before their textures in pass 1: "No loader found" errors, gone in pass 2); about 3 min in total here.
- Editor debugging: script `print()` from tool scripts doesn't reach the console of a headless editor; `push_warning()` does.
- In `godot -s` mode autoload names aren't registered: tests instantiate scripts directly, or run through the main scene.

## Done

- 2026-10-23 — DW Data dock and its guide; its asset check found the data porter's wrong model folders (Digimon 30–179), fixed. Editor mirror and `Content` loader (`9eb9172`).
- 2026-10-23 — `Content` loader and the `res://content/dw1/` editor mirror; runtime animations now baked at 20 fps (were resampled at 30). Registry (`e161e05`), cards as their own kind (`7ee3ccf`), content keys (`280d3d0`).
- 2026-10-23 — Content architecture spec (`specs/content.md`).
- 2026-10-23 — Field scene editor preview (`8a29c15`, tamer meshes `74a678b`; this file created).
- 2026-10-22 — `GameData` autoload (`907f6bc`); data porter complete (text, moves, Digimon, items, evolution, systems).
