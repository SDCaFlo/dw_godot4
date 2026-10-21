# Digimon World GODOT

A port of the original PlayStation game **Digimon World** to the [Godot](https://godotengine.org/) engine (4.7, Forward Plus renderer), aimed at making future development, modding and maintenance easier.

> **Status:** early work in progress. The project currently contains only the empty Godot project skeleton.

## Approach

The port is a reimplementation of the game's logic and data in Godot, guided by two external resources that are **not** included in this repository:

1. **Decompiled C code** of the original game, used as a reference for game logic, formulas, data structures and behavior.
2. **Extracted game assets** (models, textures, audio, maps, text, etc.) from the original disc image, converted into formats Godot can use.

## Repository layout

```
dw_godot_port/
├── dw_godot/            # Godot project (this repository)
│   ├── project.godot
│   └── README.md
└── external-resources/  # Not tracked; reference material and extracted assets
    └── dw_decomp/       # Decompiled C code (asm/, config/, include/, src/, text/, ...)
```

`external-resources/` is listed in `.gitignore` and must be provided locally.

## Requirements

- [Godot 4.7](https://godotengine.org/download) (Forward Plus)
- A legally obtained copy of Digimon World (PS1) to extract assets from
- The decompiled source of the game placed in `external-resources/dw_decomp/`

## Getting started

1. Clone this repository.
2. Place the decompilation in `external-resources/dw_decomp/`.
3. Extract the game assets from your own copy of the game (extraction tooling/instructions: *TBD*).
4. Open `dw_godot/project.godot` with Godot 4.7 and run the project.

## Roadmap

- [ ] Asset extraction and conversion pipeline
- [ ] Core game systems (state, save data, scripting/events)
- [ ] Overworld: maps, camera, player movement
- [ ] Digimon data, stats, evolution and care mechanics
- [ ] Battle system
- [ ] UI, menus and text
- [ ] Audio

## Legal

This is a fan project and is not affiliated with or endorsed by Bandai or any rights holder. Digimon World and all related assets are the property of their respective owners. No copyrighted game assets or original code are distributed with this repository; you must supply your own copy of the game.
