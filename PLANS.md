# Plans and ideas

Working list of what comes next and ideas not started yet. Keep it current: when something is done, move it to "Done" with the commit and drop the details that now live in the code / docs. Per-tool progress stays in `asset_porter/PROGRESS.md` and `data_porter/PROGRESS.md`; the high-level roadmap is in `README.md`.

Last updated: 2026-10-23

## Rule for everything below

Game content (assets, data, text) is generated locally and never committed. Editor helpers may show it, but only from memory or from gitignored folders: nodes created for a preview have no `owner` (not saved), saved properties are reset before a save (`NOTIFICATION_EDITOR_PRE_SAVE`), glTF textures are kept in memory (`PorterAssets.load_model`), and nothing is copied under a tracked `res://` path.

## Next

1. **Editor visibility** (seeing the game content while working in Godot)
   - [x] Field scene previews in the editor (`@tool` field scripts; pick `start_map` / `start_spawn` / `time_of_day` in the Inspector).
   - [ ] Same pattern for the next scenes (battle, menus) as they are built.
   - [ ] **Local import folder:** copy a selection of the asset porter output (models, maps; not movies) into a gitignored `res://local_assets/` without `.gdignore`, so Godot imports it: FileSystem thumbnails, drag a Digimon into a scene, animation preview. Scenes would reference these paths only. Needs: `.gitignore` entry, a porter command or editor button, a check that `.godot/` stays ignored.
   - [ ] **"DW Data" editor dock** (`EditorPlugin`): browse Digimon / techniques / items / maps through `GameData`, search, readable record view, spec link, model preview (from the local import folder). Later: edit values and write them to a mod folder (a modding tool). Alternative considered: generating `.tres` resources into a gitignored folder for the normal Inspector.
2. **Core game systems:** game state and save data (the savegame layout of the decomp), event script interpreter (the asset porter converts the scripts), game clock.
3. **Field:** NPC Digimon and the partner, map object sprites (water, fire), lighting, depth against the background, events.
4. **Text renderer:** control codes (`#C1 #R #W` / `{C1}` / bare `C R W`), button and bits glyphs, a font with kana for `ja` (specs/text.md §4).
5. **Battle, care, evolution, menus:** GDScript ports of the C logic, reading `GameData`; each function names the C function it reproduces (data_porter/specs say where the logic is).

## Ideas (not planned yet)

- Godot `.tres` resources generated from the data porter JSON for editor use (gitignored).
- Mod loader UI: list mod folders, enable / disable, show which tables a mod replaces.

## Notes

- Godot on this machine's command line is 4.3 (`godotenv`); the project targets 4.7. Headless checks have been run with 4.3 on a scratch copy of the project (so 4.3 doesn't touch `.godot/`); the user runs 4.7.
- glTF loaded by a `@tool` script behaves differently in the editor: textures default to "extract" (the editor tries to copy them into the project) and meshes come out as `ImporterMeshInstance3D`, which don't render. `PorterAssets.load_model` handles both; always load models through it.
- Editor debugging: script `print()` from tool scripts doesn't reach the console of a headless editor; `push_warning()` does.
- In `godot -s` mode autoload names aren't registered: tests instantiate scripts directly, or run through the main scene.

## Done

- 2026-10-23 — Field scene editor preview (this file created).
- 2026-10-22 — `GameData` autoload (`907f6bc`); data porter complete (text, moves, Digimon, items, evolution, systems).
