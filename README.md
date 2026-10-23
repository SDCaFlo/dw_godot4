# Digimon World GODOT

A port of the original PlayStation game **Digimon World** to the [Godot](https://godotengine.org/) engine (4.7, Forward Plus renderer), aimed at making future development, modding and maintenance easier.

> **Status:** early work in progress. The asset porter converts every file of the disc (textures, models, Digimon with animations, field maps, event scripts, sound and music, battle effects, movies); a first field scene walks the tamer around the converted maps. The data porter (game data from the decomp) converts all in-game text, in every language, the techniques (moves, element factors, learn chances) the Digimon data (size, type, level, elements, drops, technique slots, partner care data) the items (prices, use, effects, cards, shops) evolution (requirements, paths, stat gains, evolution items) and the system tables (battle AI, tournaments, maps, transport, fishing, …); the Godot `GameData` autoload loads it at runtime (the field shows the area name in the chosen language).

## Approach

The port is a reimplementation of the game's logic and data in Godot, guided by two external resources that are **not** included in this repository:

1. **Decompiled C code** of the original game (`dw_decomp`), used as a reference for game logic, formulas, data structures and behavior.
2. **Your own dump of the game disc**, the source of the assets.

Two Python tools in this repository turn them into open formats that the game loads at runtime. Their output is generated locally and **never committed** (it is game content):

| Tool | Input | Output | Docs |
|---|---|---|---|
| `asset_porter/` | dumped disc files | textures (PNG), models and animations (glTF), maps, scripts, sound (WAV/MIDI/SF2), effects, movies (OGV) as `asset_porter/output/` | `asset_porter/CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` |
| `data_porter/` | `dw_decomp` C tables, constants and text | game data as JSON (Digimon stats, evolution, moves, items, text, …) as `data_porter/output/` | `data_porter/CLAUDE.md`, `PROGRESS.md`, `VERIFY.md` |

Each tool documents, per format or table, how the original code used it and how it maps to Godot (`specs/`), checks its own output on every run, and lists human checks in `VERIFY.md`.

## Repository layout

```
dw_godot_port/
├── dw_godot/                 # Godot project (this repository)
│   ├── project.godot         # 320x240 base resolution (the PSX screen), scaled 3x
│   ├── asset_porter/         # Python tool: disc files -> PNG/glTF/WAV/OGV/JSON (see its CLAUDE.md)
│   │   └── output/           # Generated assets, gitignored, not imported by Godot (.gdignore)
│   ├── data_porter/          # Python tool: decomp tables/text -> JSON game data (see its CLAUDE.md)
│   │   └── output/           # Generated data, gitignored, not imported by Godot (.gdignore)
│   ├── addons/dw_tools/      # Editor plugin: Project > Tools > "DW: Mirror dw1 assets"
│   ├── content/dw1/          # Editor mirror of the dw1 assets, imported by Godot (gitignored, local)
│   ├── PLANS.md              # To-do list and ideas
│   ├── specs/content.md      # Content architecture (packs, keys, merging)
│   ├── scenes/field/         # Field scene (map + tamer)
│   ├── scripts/
│   │   ├── content/          # Content: asset loader (editor mirror if imported, else the porter output)
│   │   ├── data/             # GameData autoload: runtime loading of the data porter output
│   │   └── field/            # FieldMap (background, camera, collision, warps), Tamer, field.gd
│   └── tests/                # Godot headless tests (test_game_data.gd, test_content.gd)
└── external-resources/       # Not tracked; reference material and dumped game files
    ├── dw_decomp/            # Decompiled C code (asm/, config/, include/, src/, text/, ...)
    └── game_dumped_files/    # Files dumped from your own disc
```

`external-resources/` is listed in `.gitignore` and must be provided locally.

## Requirements

- [Godot 4.7](https://godotengine.org/download) (Forward Plus)
- Python 3 (both porters, standard library only; optional: numpy to speed up movie decoding)
- Optional: [ffmpeg](https://ffmpeg.org/) with libtheora/libvorbis (e.g. `winget install Gyan.FFmpeg`) to export the movies as `.ogv`
- A legally obtained copy of Digimon World (PS1) to dump the files from
- The decompiled source of the game placed in `external-resources/dw_decomp/`

## Getting started

1. Clone this repository.
2. Place the decompilation in `external-resources/dw_decomp/` and the dumped disc files in `external-resources/game_dumped_files/` (see their `RESOURCE_DEFINITION.md`).
3. Convert the assets (from `dw_godot/`):
   ```
   cd asset_porter
   python -m dwporter convert all          # writes asset_porter/output/, ~15 min (movies included)
   python -m unittest discover -s tests -t .
   ```
4. Convert the game data:
   ```
   cd data_porter
   python -m dwdata convert all            # writes data_porter/output/ (text, moves, digimon, items, evolution, systems), about a minute
   python -m unittest discover -s tests -t .
   ```
   Every run ends with `N/N checks passed` per family/group; a failed check makes the command exit non-zero.
5. Optional: go through each tool's `VERIFY.md` (human checks: look at textures, open models in Blender, listen to sounds, …).
6. Open `dw_godot/project.godot` with Godot 4.7 and run the project (F5). Optional: `godot --headless --path . -s res://tests/test_game_data.gd` and `res://tests/test_content.gd` check the data and asset loaders.
7. Optional, to see the game's models and maps in the editor: Project > Tools > **DW: Mirror dw1 assets**. It copies the models, map backgrounds / doors and cards (about 330 MB) into `res://content/dw1/` (gitignored) and Godot imports them (a few minutes the first time): FileSystem thumbnails, drag a Digimon `.gltf` into a scene, preview its animations. The game then loads these imported copies too. Run it again after re-running the asset porter.

The output folders can be moved: `DW_PORTER_OUTPUT` / `dw/porter/output_dir` (assets) and `DW_DATA_OUTPUT` / `dw/data/output_dir` (data).

## Game data in Godot

`GameData` (autoload, `scripts/data/game_data.gd`) is the content registry: it reads the data porter's JSON (the original game as the `dw1` content pack, `specs/content.md`) on first use, by numeric id or content key: `GameData.digimon(3)` = `GameData.digimon("dw1:agumon")`, `GameData.move(2)`, `GameData.item("dw1:meat")`, `GameData.map(0)`, `GameData.entity("digimon", "dw1:agumon")` (the Digimon with its care, evolution, model files…; cards are collectibles of their own, `GameData.cards_of(digimon)`), `GameData.battle_commands(brain, arena)`, any table with `GameData.table("systems/fishing")`, and text with `GameData.text("STR_DIGIMON_NAME_AGUMON")` or `GameData.localize(record.name)` in `GameData.language` (`ja`, `en_us`, `en_eu`; setting `dw/data/language`). Content packs (folders listed in `dw/data/packs` or `DW_DATA_PACKS`) are merged over `dw1` record by record: add, patch or remove single records. Details: `data_porter/CLAUDE.md` ("Godot side") and each table's spec.

## Field scene

`scenes/field/field.tscn` (main scene) loads a map from `asset_porter/output/maps/` at runtime and lets the tamer walk on it:

- Background: the map's pre-rendered picture on a canvas layer; the 3D (tamer, doors) is rendered into a transparent 320×240 viewport over it, like the PSX drew polygons over the background tiles.
- Camera: the game's camera (`GsSetRefView2`) with a shifted projection centre, so the background scrolls with the tamer exactly like the original (`map.c: initializeDrawingOffsets`).
- Tamer: walk/run animations move him through their root motion (the game's `applyRootMomentum`); directions are snapped to the camera like `tamerTickWalkingState`; collision uses the map's 100×100 grid with the game's edge checks; trigger cells 110–119 warp to the next map.
- Keys: arrows move, Shift runs, `[` / `]` previous / next map, `T` time of day, `L` text language (area name from `GameData`), `H` hides the help line. The start map and spawn are exported on the `Field` node.

In the editor the scene previews the map too: select the `Field` node and pick `start_map` (drop-down of the converted maps), `start_spawn` and `time_of_day` in the Inspector; the 2D view shows the background with the 3D drawn over it, the 3D view the tamer and doors. The preview lives only in memory: it is cleared before each save, so `field.tscn` never contains game content (`editor_preview` turns it off).

Not yet: NPC Digimon, partner, map object sprites (water, fire), lighting, depth against the background, events/scripts. The porter output folder can be moved with the `DW_PORTER_OUTPUT` environment variable or the `dw/porter/output_dir` project setting.

## Roadmap

Detailed next steps and ideas: `PLANS.md`. How content is organised (the original game as the `dw1` content pack, keys, and room for new content and mods later): `specs/content.md`.

- [x] Asset extraction and conversion pipeline (every disc file: textures, models, Digimon, maps, scripts, sound, effects, movies)
- [x] Game data pipeline (data porter: text, moves, Digimon, items, evolution, system tables)
- [x] Godot `GameData` loader for the data porter output
- [ ] Core game systems (state, save data, scripting/events)
- [ ] Overworld: maps, camera, player movement (first version: field scene)
- [ ] Digimon data, stats, evolution and care mechanics
- [ ] Battle system
- [ ] UI, menus and text
- [ ] Audio

## Legal

This is a fan project and is not affiliated with or endorsed by Bandai or any rights holder. Digimon World and all related assets are the property of their respective owners. No copyrighted game assets, game data or original code are distributed with this repository: both porters generate their output locally from your own copy of the game and the decompilation, and that output is never committed.
