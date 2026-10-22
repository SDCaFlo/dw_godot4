# Digimon World GODOT

A port of the original PlayStation game **Digimon World** to the [Godot](https://godotengine.org/) engine (4.7, Forward Plus renderer), aimed at making future development, modding and maintenance easier.

> **Status:** early work in progress. The asset porter converts textures, models, Digimon (with animations) and field maps; a first field scene walks the tamer around the converted maps.

## Approach

The port is a reimplementation of the game's logic and data in Godot, guided by two external resources that are **not** included in this repository:

1. **Decompiled C code** of the original game, used as a reference for game logic, formulas, data structures and behavior.
2. **Extracted game assets** (models, textures, audio, maps, text, etc.) from the original disc image, converted into formats Godot can use by the asset porter.

## Repository layout

```
dw_godot_port/
├── dw_godot/                 # Godot project (this repository)
│   ├── project.godot         # 320x240 base resolution (the PSX screen), scaled 3x
│   ├── asset_porter/         # Python tool: disc files -> PNG/glTF/JSON (see its CLAUDE.md)
│   │   └── output/           # Generated assets, gitignored, not imported by Godot (.gdignore)
│   ├── scenes/field/         # Field scene (map + tamer)
│   └── scripts/
│       ├── porter/           # PorterAssets: runtime loading of the porter output
│       └── field/            # FieldMap (background, camera, collision, warps), Tamer, field.gd
└── external-resources/       # Not tracked; reference material and dumped game files
    ├── dw_decomp/            # Decompiled C code (asm/, config/, include/, src/, text/, ...)
    └── game_dumped_files/    # Files dumped from your own disc
```

`external-resources/` is listed in `.gitignore` and must be provided locally.

## Requirements

- [Godot 4.7](https://godotengine.org/download) (Forward Plus)
- Python 3 (asset porter, standard library only)
- A legally obtained copy of Digimon World (PS1) to dump the files from
- The decompiled source of the game placed in `external-resources/dw_decomp/`

## Getting started

1. Clone this repository.
2. Place the decompilation in `external-resources/dw_decomp/` and the dumped disc files in `external-resources/game_dumped_files/`.
3. Convert the assets: `cd asset_porter && python -m dwporter convert all` (writes `asset_porter/output/`).
4. Open `dw_godot/project.godot` with Godot 4.7 and run the project (F5).

## Field scene

`scenes/field/field.tscn` (main scene) loads a map from `asset_porter/output/maps/` at runtime and lets the tamer walk on it:

- Background: the map's pre-rendered picture on a canvas layer; the 3D (tamer, doors) is rendered into a transparent 320×240 viewport over it, like the PSX drew polygons over the background tiles.
- Camera: the game's camera (`GsSetRefView2`) with a shifted projection centre, so the background scrolls with the tamer exactly like the original (`map.c: initializeDrawingOffsets`).
- Tamer: walk/run animations move him through their root motion (the game's `applyRootMomentum`); directions are snapped to the camera like `tamerTickWalkingState`; collision uses the map's 100×100 grid with the game's edge checks; trigger cells 110–119 warp to the next map.
- Keys: arrows move, Shift runs, `[` / `]` previous / next map, `T` time of day, `H` hides the help line. The start map and spawn are exported on the `Field` node.

Not yet: NPC Digimon, partner, map object sprites (water, fire), lighting, depth against the background, events/scripts. The porter output folder can be moved with the `DW_PORTER_OUTPUT` environment variable or the `dw/porter/output_dir` project setting.

## Roadmap

- [x] Asset extraction and conversion pipeline (textures, models, Digimon, maps; sound/effects pending)
- [ ] Core game systems (state, save data, scripting/events)
- [ ] Overworld: maps, camera, player movement (first version: field scene)
- [ ] Digimon data, stats, evolution and care mechanics
- [ ] Battle system
- [ ] UI, menus and text
- [ ] Audio

## Legal

This is a fan project and is not affiliated with or endorsed by Bandai or any rights holder. Digimon World and all related assets are the property of their respective owners. No copyrighted game assets or original code are distributed with this repository; you must supply your own copy of the game.
