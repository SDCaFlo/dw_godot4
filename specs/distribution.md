# Distribution, updates and the launcher (design)

How players who own the game get the port running, and how they get our fixes, without Godot, Python, the repo or the decomp. A design document like `content.md`: it fixes the rules and the order of work. Status of each part: `PLANS.md` ("Distribution").

Decided 2026-11-09 with the user: public GitHub repository, Windows first (Mac and Linux later), the porters shipped as a bundled exe.

## 1. The model

We ship **code only**. The player brings the game.

1. The player downloads a release zip from GitHub Releases: the exported Godot game, the bundled porter, no game content.
2. On first launch the **launcher screen** (§5) asks for their disc image, checks that it is the US disc, and runs the porter once. It writes the `dw1` pack into the player's data folder (§4).
3. From then on the game starts directly. An update replaces our code only. The `dw1` content is rebuilt from the disc only when an update changes the converter (§6).

The same model is used by other source ports that need the original game: Ship of Harkinian (needs the player's ROM, builds its asset archive on first launch), devilutionX (needs the player's `DIABDAT.MPQ`), OpenRCT2 (points at an installed copy).

**Never distributed, anywhere** (repo, releases, issues, CI artifacts): disc files, the porters' output, the editor mirror `content/dw1/`, screenshots or recordings of game art, decomp text copied in bulk, other games' models. §8 lists the checks before the repo goes public.

## 2. The decomp is not needed at run time

Players won't have `external-resources/`. Today:

| Part | Reads the decomp at run time? | Plan |
|---|---|---|
| Asset porter | Yes, for a few checks (`scripts.py` reads `dget.c` / `trigger.h` for "Grade A won") | List every read; make each a dev-only check that skips when the decomp is missing, or move it to the data porter's tests |
| Asset porter's `dwporter/data/*.py` | No: generated tables committed as code | Fine at run time; review what they hold before publishing (§8) |
| Data porter | Yes, entirely: C tables, constants, `text/*.yaml` | **Read the same values from the player's `SLUS_010.32` and `*_REL.BIN`** (below) |

### 2.1 The data porter's new input

Every table the data porter writes keeps its JSON shape (`data_porter/CLAUDE.md` "Output"). Only where the values come from changes:

- **Layouts are committed code**: each table's address in the US executable or overlay (from `config/us/symbols*.txt`), its element size and its field layout (from the C struct). These are facts about the binary, not game content.
- **Values are read from the player's files** at convert time, with the layout above. Text is read from the binary as well (the strings the YAML tables generate are in the executable and the overlays, encoded in the game's charset).
- **Schema, `used_by`, specs stay generated from the decomp**, by us, as committed metadata: they describe the code, they hold no values.
- **The decomp stays the trusted source, in our tests.** A dev test compares, table by table, the JSON read from the binary with the JSON read from the decomp (`test_cross_asset_porter.py` already does this for maps and toilets). A table moves to the binary reader only once it matches exactly.
- Values that exist only as code (`switch_cases` effects, `#define`s used in expressions) become committed constants with their C source in a comment, like any port constant (`docs/porting_checklist.md`). List them as the work finds them.

So on a player's machine the data porter needs only the disc. On ours it also runs the decomp checks.

### 2.2 One porter

The two porters become one program for players: `dwporter` and `dwdata` stay separate Python packages (and keep their own docs and tests), behind one entry point that runs both in order on a disc image. Name: `dw_convert` (`port-only`).

## 3. The disc image

Players have a disc image, not the extracted files we work from. Built in D4: `dw_convert/` (`dw_convert/specs/disc_image.md`).

- **Input**: `.cue` + `.bin` (raw 2352-byte sectors), a single `.bin`, or a 2048-byte `.iso`. Read with a small ISO 9660 reader on Mode 2 sectors. Committed code, standard library only.
- **Movies need the raw sectors**: `MOVIE/*.STR` mix video and XA audio sectors (`game_dumped_files/RESOURCE_DEFINITION.md` "Gotchas"). From a `.bin` we get them directly; from a 2048-byte `.iso` the XA audio is lost, so the porter converts what it can and the launcher says the movies are not available from that image.
- **Version check**: the image must be the US release (`SLUS-01032`). Identify it by `SYSTEM.CNF`'s boot name and the hash of `SLUS_010.32`. Other releases (JP, EU) get a clear "not supported yet" message, not a broken conversion.
- **The developer path stays**: the porters keep accepting an extracted folder (`game_dumped_files/`), so our workflow doesn't change.

## 4. Where things live

| What | Where | Changed by |
|---|---|---|
| Godot engine + launcher | `dw_godot4.exe` | a full release only |
| Our game code | `game.pck` next to the exe | updates (§6) |
| The porter | `tools/dw_convert.exe` next to the exe | updates (§6) |
| `dw1` pack (converted content) | `user://content/dw1/` (`%APPDATA%\dw_godot4\` on Windows, D6) | the porter only |
| Settings (disc path, versions, options) | `user://settings.cfg` | the launcher |
| Saves | `user://` (as today, `specs/save.md`) | the game |
| Mods | `user://mods/` (`digimon-packs-decisions`) | the player |

- `Content` and `GameData` already take their folder from a project setting or an environment variable (`dw/porter/output_dir`, `dw/data/output_dir`). In an exported game the default becomes `user://content/dw1/assets` and `.../data`. In the editor the defaults stay `res://asset_porter/output` and `res://data_porter/output`.
- Built in D6: `Release` (`scripts/core/release.gd`) gives the defaults (`OS.has_feature("editor")` decides) and reads `res://version.json`; `project.godot` sets `config/use_custom_user_dir.template=true` with `custom_user_dir_name="dw_godot4"`, so an exported game's `user://` is `%APPDATA%\dw_godot4\` while the editor keeps its own folder (the developer's saves don't mix with a player build's). The export preset (`export_presets.cfg`, "Windows Desktop") writes `build/windows/dw_godot4.exe` + `dw_godot4.pck` (gitignored); it excludes `tests/`, `content/dw1/`, `addons/dw_tools/`, `issues/`; the porters and `dw_convert/` are `.gdignore`d. Until U2 the pack is `dw_godot4.pck`, the name Godot loads by itself, not `game.pck`.
- The exported game loads the raw porter files at run time (glTF, PNG, JSON), the path `Content` already has when the editor mirror is missing. The mirror is an editor convenience only.

## 5. The launcher screen

Not a separate program: the exe's first scene. It decides, then hands over to the title screen.

1. **No disc set or no `dw1` pack**: ask for the disc image (file dialog), or detect one next to the exe. Check it (§3). Run `dw_convert.exe` with a progress view (the porter prints one line per step; the launcher shows it). On failure: the porter's message and the log file path.
2. **An update is available** (§6): show the version and the change notes; Update / Later.
3. **The `dw1` pack is older than the porter** (§6): re-convert from the remembered disc path, with the progress view. If the image is gone, ask again.
4. Otherwise: start the game. A "Settings" entry lets the player change the disc image or force a re-conversion.

## 6. Versions and updates

Three version numbers, all written in a `version.json` built into `game.pck` and in the release (`res://version.json`, read by `Release`; `tests/test_release.gd` checks its `content_format` against `dw_convert`'s `run.CONTENT_FORMAT`; `mod_api` is 0 until mods are released):

| Version | Meaning | Bumped when |
|---|---|---|
| `game` | the release (`0.3.1`) | every release |
| `content_format` | the shape of the porter's output | the porter output changes in a way old output can't be used |
| `mod_api` | what mods can rely on (keys, table shapes, script commands) | a change could break an existing mod |

- The porter writes `content_format` into the `dw1` pack's `content.json` (D5). The launcher compares it with its own and re-converts when they differ. Content is never downloaded.
- **Update check**: the GitHub Releases API (`/repos/<owner>/<repo>/releases/latest`), at launch, at most once a day, can be turned off in Settings.
- **First version (U1)**: notify only. "Version X is out", the notes, and a button that opens the release page. The player unzips over the old folder (saves and content are in `user://`, so nothing is lost).
- **Second version (U2)**: download. The release carries `game.pck`, `dw_convert.exe` and a `manifest.json` (file, size, SHA-256). The launcher downloads changed files to a temp folder, checks the hashes, swaps them in, and restarts. The exe itself only changes on a full release (engine upgrade): then U2 falls back to U1's "download the zip".
- Godot loads `game.pck` at start; replacing it while the game runs is avoided by swapping before it is loaded (the launcher lives in the exe's embedded pack, the game in `game.pck`).

## 7. Updates and mods

Updates and mods never touch each other's files (§4). What can break is the meaning of a mod's records after a code change. Rules:

- A mod's `pack.json` declares `mod_api` (the version it was made for). The Mods screen marks mods with an older `mod_api` as "may not work", and refuses one with a newer `mod_api`.
- Mods override content by key through the pack registry (`content.md` §5). They never patch `game.pck` or the `dw1` files.
- Mod depth, in tiers (later, `specs/digimon_packs.md` covers tier 1):
  1. **Data**: Digimon, items, techniques, stats. Safe and stable.
  2. **Scripts**: quests, NPCs, events, written for the game's own script interpreter (`specs/script.md`), which the original's quests already use. Cannot reach outside the game.
  3. **Code**: `.pck` packs replacing scenes or GDScript (`scenes.md`). Anything goes, including harm to the player's PC, and breaks easily on updates. Off by default, with a warning.

## 8. Before the repo goes public

A one-time audit, then a rule kept from then on. Done 2026-11-10 (D1), results:

- Every blob of every local branch: no images, audio, models or disc files except the Veemon `.glb` below; the only large files are the data porter snapshot (layouts, no values: `data_porter/specs/from_disc.md`) and `us_files.json` (hashes).
- Game text: every en/ja string of the decomp's text tables (25+ / 8+ characters) and every dialogue piece of the converted scripts (25+ characters) searched in every blob: only single quoted lines in specs and tests (about 40 in all), none in bulk.
- No secrets, no personal paths beyond the Steam Godot path and the developer's image folder name in a test default.
- Commits rewritten to the GitHub noreply address before the first push. Only `main` is pushed; `spec/digimon_contract` stays local.
- Committed tables `asset_porter/dwporter/data/*.py` kept: Digimon file names, names and string ids (180), technique names (about 120), skeleton tables; short identifiers and structure the asset porter needs to name and assemble files. Moving them to the disc read (like the data porter) is possible later.
- Licence: MIT (`LICENSE`), notices in `THIRD_PARTY_NOTICES.md`; `config/name` and the README title are `dw_godot4`, the README states unofficial / own copy needed / no disc images.

The rule from now on: never commit or attach game content (§1 "Never distributed"); a branch is pushed only after the same blob scan.

- **History**: no game content in any commit of any branch that is pushed. Found 2026-11-09: branch `spec/digimon_contract` (commit `93f35f6`) has `content/mypack/models/veemon/veemon.glb`, a model ported from another Digimon game. Don't push that branch; keep it local or rewrite it without the model.
- **Committed tables**: `asset_porter/dwporter/data/*.py` hold names and skeleton tables generated from the decomp. Decide per table: keep (short identifiers needed to name files), or move to generated output read from the disc.
- **Tests and docs**: no bulk game text or data copied in (single values cited with their C source are fine).
- **Name and look**: the public name is `dw_godot4` (decided 2026-11-09), no official logos; the README says it needs a legally owned copy, is unofficial and non-commercial, and links to no disc images.
- **Licence**: choose one for our code. Note the decomp's licence, and the licences of anything bundled (Godot: MIT; Python and PyInstaller's bootloader: permissive; ffmpeg if bundled for movies: LGPL build only).

## 9. Order of work

| Step | What | Rating |
|---|---|---|
| D1 (done 2026-11-10) | Audit (§8) and its fixes; choose our licence | Low, needs the user |
| D2 | Asset porter: list and remove its run-time decomp reads (§2) | Low |
| D3 | Data porter from the binary (§2.1): inventory and steps D3a-D3d in `data_porter/specs/from_disc.md` | Hard, several steps |
| D4 (done 2026-11-09) | Disc image reader and version check (§3): `dw_convert/`, the files extracted for both porters | Medium |
| D5 (done 2026-11-09) | `dw_convert`: one entry point, progress lines, a log file; PyInstaller build script; the release build skips the movies (Q2): `dw_convert/specs/convert.md` | Medium |
| D6 (done 2026-11-10) | Export: Windows preset (excludes `content/dw1/*`, `asset_porter/`, `data_porter/`, `tests/`, `external-resources`), `user://` content defaults (§4), `version.json` | Medium |
| D7 (done 2026-11-10) | Launcher screen (§5) with update check U1 (§6): `launcher.md` | Medium |
| D8 (done 2026-11-10) | GitHub Action: on a version tag, build the export and `dw_convert.exe`, attach them to a release: `release_ci.md` | Medium |
| D9 | `docs/setup.md` for players, `docs/release.md` for us | Low |
| D10 | Later: U2 downloads; `mod_api` in the Mods screen; Mac and Linux builds | — |

D2 and D3 can start before D1 is finished; nothing is pushed until D1 is done.

## 10. Open questions

- Q1: ~~The project's public name.~~ Decided 2026-11-09: `dw_godot4` (repo, exe, `user://` folder).
- Q2: ~~Movies.~~ Decided 2026-11-09: skipped for now. The release's `dw_convert` doesn't convert `MOVIE/*.STR` and the game skips a movie it doesn't have (as the port does today without the `.ogv`). Adding them later is an ordinary update: the porter's movie step and `content_format` bumped, so the launcher re-converts from the remembered disc image (§6). Options then: bundle an LGPL ffmpeg, or decode the STR frames in Godot.
- Q3: Can the data porter's text be read from the binary byte-exact for all three languages, or only for US English (the release we read)? Expected: US only, since the image is the US disc.
- Q4: ~~Code signing.~~ Decided 2026-11-09: unsigned at first; `docs/setup.md` explains the SmartScreen warning ("More info" > "Run anyway").
