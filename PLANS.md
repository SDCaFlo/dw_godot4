# Plans and ideas

Working list of what comes next and ideas not started yet. Keep it current: when something is done, move it to "Done" with the commit and drop the details that now live in the code / docs. Per-tool progress stays in `asset_porter/PROGRESS.md` and `data_porter/PROGRESS.md`; the high-level roadmap is in `README.md`.

Last updated: 2026-10-23

## Rules for everything below

- Game content (assets, data, text) is generated locally and never committed. Editor helpers may show it, but only from memory or from gitignored folders: nodes created for a preview have no `owner` (not saved), saved properties are reset before a save (`NOTIFICATION_EDITOR_PRE_SAVE`), glTF textures are kept in memory (`PorterAssets.load_model`), and nothing is copied under a tracked `res://` path.
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
   - [ ] `Content` loader (successor of `PorterAssets`, §6): Godot-imported copy under `res://content/<pack>/` if present, else the raw file.
   - [ ] `res://content/dw1/` mirror: a local step copies models and maps (not movies) from the asset porter output into this gitignored folder (no `.gdignore`), so Godot imports them: FileSystem thumbnails, drag a Digimon into a scene, animation preview. Needs a `.gitignore` entry and a check that nothing under it is ever tracked.
   - [ ] Same preview pattern for the next scenes (battle, menus) as they are built.
   - [ ] "DW Data" dock, read-only first: browse Digimon / techniques / items / maps from the registry, search, readable record view, spec link, model preview.
3. **Core game systems:** game state and save data (savegames store keys), event script interpreter (the asset porter converts the scripts), game clock.
4. **Field:** NPC Digimon and the partner, map object sprites (water, fire), lighting, depth against the background, events.
5. **Text renderer:** control codes (`#C1 #R #W` / `{C1}` / bare `C R W`), button and bits glyphs, a font with kana for `ja` (data_porter/specs/text.md §4).
6. **Battle, care, evolution, menus:** GDScript ports of the C logic, reading `GameData` properties (never id ranges); each function names the C function and the original condition it reproduces.
7. **Modding** (last; `specs/content.md` §7)
   - [ ] Mod formats: raw-file packs (folder + `pack.json`, no Godot needed) and `.pck` packs built in the editor.
   - [ ] Model contract for external models (animation names, scale, pivot, collision from data, textures); the asset porter names the original animations to the same contract.
   - [ ] "DW Data" dock as the modding tool: which packs changed a record, duplicate into a pack, edit, write the pack's JSON.
   - [ ] Mod loader UI: list packs, enable / disable, load order, conflicts.
   - [ ] Open questions: numeric ids for new content used by original scripts; a key lock file so `dw1` keys never change; conflicts between mods patching the same field.

## Ideas (not planned yet)

- Godot `.tres` resources generated from the pack data for editor use (gitignored for `dw1`).

## Notes

- Godot on this machine's command line is 4.3 (`godotenv`); the project targets 4.7. Headless checks have been run with 4.3 on a scratch copy of the project (so 4.3 doesn't touch `.godot/`); the user runs 4.7.
- glTF loaded by a `@tool` script behaves differently in the editor: textures default to "extract" (the editor tries to copy them into the project) and meshes come out as `ImporterMeshInstance3D`, which don't render. `PorterAssets.load_model` handles both; always load models through it.
- Editor debugging: script `print()` from tool scripts doesn't reach the console of a headless editor; `push_warning()` does.
- In `godot -s` mode autoload names aren't registered: tests instantiate scripts directly, or run through the main scene.

## Done

- 2026-10-23 — Content architecture spec (`specs/content.md`).
- 2026-10-23 — Field scene editor preview (`8a29c15`, tamer meshes `74a678b`; this file created).
- 2026-10-22 — `GameData` autoload (`907f6bc`); data porter complete (text, moves, Digimon, items, evolution, systems).
