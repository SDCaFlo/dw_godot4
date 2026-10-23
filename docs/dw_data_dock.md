# DW Data dock — guide

The **DW Data** dock is an editor panel for browsing the game's content inside Godot. It shows each record readably, with its model or image and the C code that uses it. Use it to:

- look up data while porting a system;
- check that the porters converted and linked everything correctly.

It is read-only: it never changes the data or the project.

It reads through `GameData`, the content registry, so it shows exactly what the game will see: the `dw1` pack, plus any packs listed in `dw/data/packs`. Assets come through `Content`.

## 1. Setup

1. Run both porters (from `dw_godot/`):
   ```
   cd asset_porter && python -m dwporter convert all
   cd ../data_porter && python -m dwdata convert all
   ```
2. Open the project in Godot 4.7. The plugin (`addons/dw_tools`) is enabled in `project.godot`; the dock appears in the upper-right dock area, as a tab next to the Inspector.
   - Not there? Open Project > Project Settings > Plugins and tick **DW Tools**.
   - Closed by accident? Disable the plugin and enable it again.
3. Optional, recommended: Project > Tools > **DW: Mirror dw1 assets**. Previews then use the Godot-imported copies, and the dock can show you that the import worked (§5). Without the mirror, previews load the porter's raw files.

## 2. Layout

```
┌ DW Data ───────────────────────────────────┐
│ [Digimon ▾]                ◀  ⟳  Raw [ ]    │  kind · back · reload · raw values
│ [search name, key or id     ] [en_us ▾]    │  filter · text language
├────────────────────────────────────────────┤
│   3  Agumon   dw1:agumon                   │  list: id · name · key
│   4  Betamon  dw1:betamon                  │
│  …                                         │
├────────────────────────────────────────────┤
│ [ rotating model / card / map background ] │  preview
│ [anim_00 ▾]                                │  animation picker (models)
│ Asset mmd_files/MMD0/AGUM.gltf: imported…  │  which file was loaded
│ Agumon  dw1:agumon  id 3                   │  the page
│ Rookie · Vaccine · Fire / Battle           │
│ Digimon (digimon/digimon_data)             │
│   moves: … Spit Fire #2 …                  │
│ Care / Evolution / Files / Sounds …        │
│ Cards: —                                   │
│ Spec: specs/digimon.md                     │
│ Used by the C code (170): …                │
└────────────────────────────────────────────┘
```

The divider between the list and the page can be dragged. The page scrolls.

## 3. Using it

- **Kinds** (top drop-down):
  - **Overview:** status of everything, and the asset check.
  - **Digimon, Techniques, Items, Cards, Maps, Tournaments:** the entity kinds of the registry (`specs/content.md` §2–3).
  - **Tables:** every table of the data porter, raw.
- **Search** filters the list by name, key or id. Examples: `grey` lists Greymon, the two NPC Greymon and MetalGreymon; `dw1:meat`; `38`.
- **Links:** blue names are references. Click to open them: a technique in a Digimon's slot list, the Digimon a card shows, evolution targets in `paths.to`, a favourite food. **◀** goes back.
- **Language:** switches every name and description between `ja`, `en_us` and `en_eu`. This is the same setting the game uses (`GameData.language`).
- **Raw:** also shows the C initializer values of each record (`c`) and its source line, for comparing with the decomp.
- **⟳ Reload:** reloads after you re-run a porter or change packs. Previews update too.

### What a page shows

- **Title line:** name, content key, numeric id. "added by a pack" means the record has no `dw1` id.
- **Headline:** the essentials of the kind:
  - Digimon: level · type · elements;
  - technique: category · power · MP · element · range;
  - item: price · where it can be used · description;
  - card: the Digimon it shows · rarity · price;
  - map: file, toilet, wild Digimon;
  - tournament: grade, opponents' base stat.
- **Changed by** (orange): packs that patched the record.
- **Components:** everything `GameData.entity()` gathers, one section each. For a Digimon:
  - Digimon (the record);
  - Files (model file names);
  - Sounds;
  - Care (raise data, sleep pattern, item take distance; partners only);
  - Evolution (requirements, paths, stat gains);
  - Enemy music.

  A section is missing when the Digimon doesn't have it (an NPC has no Care).
- **Cards:** for a Digimon, the cards that show it. Most Digimon have none.
- **Spec:** the data porter spec of the table. Click it to open the Markdown file.
- **Used by the C code:** the decomp functions that read the table, with file:line and the fields read (the first 12; the table's `used_by` has all of them).

### Tables page

Kind **Tables**, then pick a table:
- its purpose and record count, and whether it is keyed;
- its C symbols and the `GameData` accessor (`godot.access`);
- every field's meaning (the schema);
- the first three records, the spec and the C users.

This is the place to check tables that aren't an entity: type factors, flee chances, tournament schedule, text blocks …

## 4. Previews

| Kind | Preview | From |
|---|---|---|
| Digimon | the model, slowly rotating, with an animation picker (all its animations, looping) | `mmd_files/MMD<id / 30>/<NAME>.gltf` |
| Card | the card image | `card_all/card_<id>.png` |
| Map | background 0 (day) | `maps/<FILE>/background_0.png` |

The line under the preview says which file was loaded: `imported copy res://content/dw1/…` (the mirror) or `raw file …/asset_porter/output/…`. `not found` means the data points to an asset that doesn't exist. Run **Check assets** (§5) to see all of them.

Previews use the game's PSX look: unshaded, nearest filtering. The camera frames the model's bounding box.

## 5. Verifying the conversion

The dock is the quickest way to check that the two porters and the mirror agree.

1. **Overview** (open the kind selector, choose Overview):
   - **Data / Assets / Editor mirror:** each folder, or a red note on what to run.
   - **Packs:** `dw1` plus any configured pack.
   - **Data porter checks:** one line per group (text, moves, digimon, items, evolution, systems). Every line should be green with `N/N`. A red line means `python -m dwdata convert all` reported failed checks; its manifest says which.
   - **Entities:** record counts. Expected: Digimon 180, Techniques 122, Items 128, Cards 66, Maps 255, Tournaments 23.
2. **▶ Check assets** (on the Overview page) follows every Digimon, map and card to its asset. Expected result:
   ```
   ! digimon: 178/180 found, 178 imported; missing: dw1:weregarurumon, dw1:unknown
   ! map: 242/244 found, 242 imported; missing: dw1:yaka01, dw1:yaka21
   ✔ card: 66/66 found, 66 imported
   ```
   - **The missing ones are gaps of the original disc, not conversion errors:** Digimon 62 (WereGarurumon, cut from the US game) and 114 have no model, and maps YAKA01 and YAKA21 are named in the map table but have no files (`asset_porter/specs/mmd.md`, `asset_porter/specs/map.md`). Maps with no file at all (11 unused entries) are not counted.
   - **"imported" counts assets loaded from the editor mirror.** It should equal "found" after the mirror is made and imported; 0 without the mirror.
   - **Anything else missing is a bug.** Click it to open its page. This check found the wrong model folders of Digimon 30–179 in the data porter (fixed 2026-10-23).
3. **Spot checks:** open a few pages you know and compare with the game:
   - Agumon: Rookie · Vaccine · Fire / Battle; first techniques Spit Fire and Fire Tower; Care hungry at 1, 5, 9, 13, 17, 21, favourite food Meat; evolves to Greymon, Meramon, Birdramon, Centarumon, Monochromon, Tyrannomon.
   - Meat: 50 bits, field use, "Makes Digimon a bit full".
   - Card Phoenixmon: rarity 0, 5000 bits.
   - Map `dw1:mayo01`: Native Forest, with its toilet.
   - Models: pick a few Digimon and play their animations: walk (`anim_03`), run (`anim_02`), a technique. They should move like in the game. With the mirror, the preview line says "imported copy".

   The porters' own `VERIFY.md` files list more expected values.
4. **Headless:** `godot --headless --path . -s res://tests/test_data_dock.gd` renders all ~840 pages, runs the asset check and must print `OK: DW Data dock checks`.

## 6. Troubleshooting

| Symptom | Cause / fix |
|---|---|
| No DW Data tab | Plugin disabled: Project Settings > Plugins > DW Tools |
| Lists are empty, Overview says data missing | Run `python -m dwdata convert all`; check `DW_DATA_OUTPUT` / `dw/data/output_dir` if the output is elsewhere; press ⟳ |
| Preview says "not found" for everything | Run `python -m dwporter convert all`; check `DW_PORTER_OUTPUT` / `dw/porter/output_dir` |
| Preview line says "raw file" although you made the mirror | The import hasn't finished, or that file isn't mirrored yet: wait for the import bar, or run the mirror again after re-running the asset porter |
| Values look old after re-running a porter | Press ⟳ (the dock caches tables like the game does) |
| Errors `Basis … must be normalized` in the Output panel | From the editor import of models with zero-scale keys; harmless (`asset_porter/specs/mmd.md` open questions) |

## 7. Limits and plans

- Read-only. Editing, "duplicate into my pack" and pack conflict views are part of the modding step (`PLANS.md` §7, `specs/content.md` §7).
- Text tables are browsable under Tables (blocks and their strings), but there is no text search across all strings yet.
- Item icons, technique effects and map objects have no preview yet (the asset porter has them; they need their own viewers).
- Code: `addons/dw_tools/data_dock.gd` (dock), `addons/dw_tools/plugin.gd` (registration, mirror menu), test `tests/test_data_dock.gd`.
