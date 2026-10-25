# Scenes and composition (design note)

Status (2026-10-24): design decided with the user. Step 2 done (§7): `scenes/field/digimon.tscn`, `partner.tscn` and `npc.tscn` (inherited), `tamer.tscn`, each with a `Model` slot and an `AnimationSounds` component (`scripts/field/animation_sounds_component.gd`); the field instances them; an entity made with `.new()` (the logic tests) creates its missing parts itself (`_part`). Step 3 done: the `DropShadow` component scene (`scenes/field/drop_shadow.tscn`, `specs/drop_shadow.md`) under `Digimon.tscn` and `Tamer.tscn`. Step 4 done: `field.tscn` has the hosts of §4.2 (`scripts/field/hosts/`), `field.gd` keeps the start order, the wiring and the frame order (`Field._frame`, the one `GameLoop.frame` connection); no component connects to `GameLoop.frame` any more. The refactor plan is in `PLANS.md` ("Scene composition refactor": after 5b, before 5e).

How the game's runtime parts are put together in Godot:
- **Logic:** plain classes that reproduce the original's C code.
- **Scenes:** node trees that assemble that logic with Godot's resources (models, players, materials, UI). They can be opened in the editor and overridden by a mod.
- **Content:** data from the packs (`specs/content.md`).

Today almost everything is built in code by `field.gd`. This note says what each part becomes and the rules the refactor and every new system follow.

## 1. Why

- **Mods that change visuals or behaviour.** A Godot `.pck` pack can replace or add resources under `res://`. A part built from a scene file can be overridden that way: a Digimon with extra effects, another HUD, a new component. A part built with `.new()` in a script can't.
- **The editor.** A modder or a developer opens `Partner.tscn` and sees its parts, its exported settings and its preview. Today the partner exists only at run time.
- **Size.** `field.gd` is 754 lines that create about 17 systems and wire them by assignment. Every new system (menus, battles) would add to it.

**Not a goal:** data mods (new Digimon, items, maps, text, tweaked values) go through the content packs and need none of this (`specs/content.md`). Nothing here changes how the original's behaviour is reproduced.

## 2. Three layers

| Layer | What | Examples | Rules |
|---|---|---|---|
| **Logic** | the C functions, reproduced; state in plain fields | `ScriptInterpreter`, `ScriptContext`, `Care`, `Clock`'s tick, `Pad`, `PsxAnimator`, `SpuEnvelope`, `TextArea`, `MessageBox`, `MapItems` / `MapChests` slot rules, `Tamer.tick_*` states | names the C function; no scene-tree lookups; testable headless with `.new()` and injected references; stays as it is |
| **Scene** | nodes that own Godot resources and present the logic | `Digimon.tscn` and its components, `Field.tscn`'s parts, HUD pieces, the menus | built in `.tscn` files; wired by exports and node paths; may be replaced by a mod |
| **Content** | records and assets from the packs | Digimon records, models, item icons, songs | read through `GameData` / `Content`; logic reads properties, never id ranges |

A node script may hold logic (the tamer's state code lives on the `Tamer` node). The rule is that the logic doesn't depend on being in a scene: a test creates the node and sets its references.

## 3. Rules

1. **The frame order is explicit.** The original runs its systems in a fixed order every frame (the object list, `tickScript` before the objects, the tamer and partner before the clock: `specs/care.md` §2.1, `specs/script.md`). Today that order comes from the order `field.gd` connects to `GameLoop.frame`.
   - After the refactor, one node, the field root, connects to `GameLoop.frame` once and calls the systems in a list it owns, written down in its script with the C's order.
   - Components don't connect to `GameLoop.frame` themselves. Tree order or `_ready` order must never decide the frame order.
   - Per-frame presentation (a quad facing the camera, a voice's volume) may use `_process`, as today.
2. **Finding each other:**
   - **Inside a scene:** `@export` typed references (`@export var animator_sounds: AnimationSoundsComponent`) set in the `.tscn`, or fixed child names (`$Model`). No `find_child` by name across the tree, and no groups for core wiring (groups are fine for debug tools).
   - **Between systems:** the field root and the systems' hosts pass references down when they create or load something (the spawner sets an NPC's `field`, `entities`, `tamer`), as today.
   - **Services** (`GameState`, `GameData`, `GameLoop`, `Sound`): a script keeps its `var game_state: Node` (and so on) for the tests. If it is still null in `_ready`, it takes the autoload (`get_node_or_null("/root/GameState")`). So a scene works when dropped in the editor, and a test injects its own.
3. **Calls go down, signals go up.** A parent calls its children. A child reports with a signal and doesn't know who listens (`animation_sound`, `sound(id)`, `unported`, as today).
4. **Content fills the slots.** A scene doesn't name a specific Digimon or map. The model goes into an empty `Model` child from the record (`digimon_file`). Textures, sounds and texts come from `Content` / `GameData`.
5. **Editor previews keep working.** The `@tool` scripts keep their previews (the field's start map, the time of day). An entity scene gets an exported `preview_digimon` that loads the model in the editor, without saving it (the rules in `PLANS.md`, "Rules for everything below": no `owner`, reset before saving).
6. **Each refactor step is behaviour-neutral.** It changes how things are assembled, not what they do. The 15 test suites and `tests/exit_scan.tscn` must pass unchanged, test values included. A step that has to change a test value is doing more than a refactor. The only new behaviour in the series is the drop shadows, which come in their own step.

## 4. The layout

### 4.1 Entities

```
Digimon.tscn                 FieldDigimon (script): animation, movement, collision, on_screen
├─ Model                     Node3D, empty: the record's model is loaded into it (Content.load_model)
├─ AnimationSounds           AnimationSoundsComponent: the model's sound events -> animation_sound
└─ DropShadow                DropShadow: the SPOT256 square under it (PLANS "Drop shadows")

Partner.tscn  = Digimon.tscn inherited, script Partner     (the partner states, care hooks)
Npc.tscn      = Digimon.tscn inherited, script Npc         (slots, waypoints, talking)
Tamer.tscn                   Tamer (script): states 0-20, pad movement, boxes
├─ Model                     the tamer's model (BOYS)
├─ AnimationSounds
└─ DropShadow
```

- `PsxAnimator` stays a logic object owned by the entity, since it wraps the model's `AnimationPlayer` the way `startAnimation` / `tickAnimation` work. `AnimationSounds` becomes a small node component around today's class.
- **Inherited scenes vs one scene with a script swap:** inherited scenes, so the editor shows `Partner.tscn` and `Npc.tscn` as their own files, each of which a mod can replace.

### 4.2 The field

```
Field.tscn                   Field (script): starts the systems, owns the frame order (§3.1)
├─ World                     SubViewportContainer (render scale)
│  └─ SubViewport
│     ├─ Background, WorldEnvironment
│     ├─ FieldMap            camera, collision, doors, MapOverlays
│     ├─ Tamer               Tamer.tscn
│     ├─ Partner             Partner.tscn (its Digimon set from GameState)
│     ├─ Npcs                Npc.tscn instances, spawned by FieldEntities
│     ├─ MapItems, MapChests, PoopPiles
├─ Hud                       CanvasLayer: the help line, ClockHud, StatusBars, ConditionBubbles, CareDebugPanel, UIBoxes, Fade, MapName (drawing order)
├─ Systems
│  ├─ Entities               EntityHost: the partner and the NPC table (FieldEntities), the entity scenes, their sounds
│  ├─ MapSession             map loading and changes, warps, exits, the map interaction checks, items and chests
│  ├─ ScriptHost             TextArea, UIBoxes, ScriptContext, TextBoxes, ScriptInterpreter, the map name, NPC talks
│  ├─ CareHost               Care, the fade, the bars, the bubbles, the poop piles, the menu's Sleep
│  └─ ClockHost              Clock (with its music hookup), ClockHud, the map's daytime fade
└─ Debug                     DebugHost: the help line's text, the debug keys, DebugWindow, CareDebugPanel, ScriptDebug (left out of an export later)
```

As built (step 4, `scripts/field/hosts/`). A host is a node whose script holds the old `_start_*` code and the callbacks that belong to it (`check_map_interaction` and `change_map` in `MapSession`, `talk_to` and the speakers' screen positions in `ScriptHost`). A host creates its nodes; the 3D ones it adds to the world itself, the HUD ones the field adds in the drawing order. Hosts report up with signals (`message` to the help line, `map_loaded`, `npc_autotalk`); the field connects them and hands each host its references (`MapSession` gets `ScriptHost` and `CareHost`, which it calls during a map change). `Field` keeps only the start order, the frame order (`_frame`) and that hand-over. `MapSession` and `DebugHost` are tool scripts: the editor preview loads its map and help line through them.

### 4.3 Menus and later systems (5e on)

Each menu is a scene (`scenes/ui/<menu>.tscn`) on the existing UI pieces (`UIBoxes`, `TextArea`, `MessageBox`, `docs/ui.md`), opened by its host and ticked through the frame order. Battles get their own top-level scene later, in the same shape.

## 5. What a mod may override

- **Supported:**
  - replacing an entity scene (`Partner.tscn`, `Npc.tscn`, `Tamer.tscn`, `Digimon.tscn`);
  - replacing a component scene or adding nodes under an entity;
  - replacing a HUD piece or a menu scene;
  - the content of the slots (models, textures, sounds) through packs.
- **The contract a replacement keeps:**
  - the root's script, or a script that extends it;
  - the child names the code uses (`Model`, the components);
  - the signals.
- **Planned with modding (`PLANS.md` §9):** a Digimon record may name its own scene (an optional `scene` property, a key resolved like the other content). The default stays `Digimon.tscn` with the record's model.
- **Not supported:** changing the frame order, or replacing a logic class. A mod that wants other behaviour adds a component or a script that extends the entity's. It can't change how the original's systems tick.

## 6. Tests

- The logic tests stay as they are (`.new()` and injected references).
- The tests that need an entity load its scene (`load("res://scenes/field/partner.tscn").instantiate()`). This works headless; models come from `Content` as today.
- `tests/exit_scan.tscn` and the render checks keep driving the real `Field.tscn`, so they cover the wiring after each step.

## 7. Order of work

1. This note.
2. **Entity scenes:** `Digimon.tscn` with the `Model` slot and `AnimationSounds`, `Partner.tscn` / `Npc.tscn` inherited, `Tamer.tscn`; `FieldEntities` and the field instantiate them; the tests load them. Behaviour-neutral.
3. **`DropShadow`** as the first new component (`PLANS.md` "Drop shadows", `specs/drop_shadow.md`); the item shadows (`MapItems`) share its material. Done.
4. **Split `field.gd`** into the hosts of §4.2, with the explicit frame order. Behaviour-neutral, the tests and the exit scan unchanged. Done (in one change: the hosts call each other during start and map changes, so they couldn't be moved one at a time).
5. **5e's menus** as scenes from the start.

## 8. Open questions

- **The partner's model changes with evolution** (not ported yet). Does the scene reload its `Model` slot, or swap the whole partner node? Reloading the slot keeps the node and its references, which is simpler for the hosts. To decide with evolution.
- **Export presets:** the `Debug` branch and the debug window should be left out of a release export. That comes with the first export.
- **`.pck` load order and conflicts** between two mods replacing the same scene: with the mod loader (`PLANS.md` §9).
