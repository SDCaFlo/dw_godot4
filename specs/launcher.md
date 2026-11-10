# The launcher (distribution step D7)

The exported game's first scene: it makes sure the converted `dw1` pack is there and current, then starts the game. Parent spec: `distribution.md` §5 (the screen), §6 (versions and updates, U1). Code: `scripts/launcher/` (`launcher.gd`, `launcher_logic.gd`, `converter_process.gd`), scene `scenes/launcher/launcher.tscn`; test `tests/test_launcher.gd`.

## 1. When it runs

`project.godot` sets `run/main_scene.template` to the launcher, so only an exported game starts there; the editor (F5) and the tests keep `scenes/game.tscn` and the porters' outputs. Run `launcher.tscn` on its own (F6) to try it in the editor: it then works on the editor's `user://content/dw1/` and the built `dw_convert/dist/` exe, or the source (`python dw_convert/dw_convert.py`), or `DW_CONVERT`.

It uses Godot's default controls at the window's size (the game's 320x240 scaling is switched off while it shows, restored before the game): the game's font and windows are converted content, which may not exist yet. English only (`port-only`).

## 2. What it decides (`LauncherLogic.decide`)

| The pack folder (`user://content/dw1/`) | Action |
|---|---|
| `content.json`, `assets/`, `data/catalog.json` there; `content_format` = this build's (`Release.content_format()`); `ok`, or `accepted` | play (after the update check) |
| missing, incomplete, another `content_format`, or failed checks not accepted | convert: the disc page, with the reason. The image is checked (`dw_convert identify`) right away when one is known |

The disc image path is remembered in `user://settings.cfg` (`[disc] path`). When none is known, an image (`.cue`, then `.iso`, then `.bin`) next to the exe is suggested.

Hold Shift while it starts, or pass `--launcher` after `--` on the command line, for the settings page: Play, Convert again, the update check on / off, the developer tools on / off (`[dev] tools`, read by `Release.dev_tools`: the debugger window, the debug keys and the full help line in the game; also `--dev` on the command line; always on in the editor).

## 3. The conversion

- `dw_convert run <image> user://content/dw1.new` (`ConverterProcess`: two threads read stdout and stderr; the scene polls them every frame). `PROGRESS` lines drive the bar and the status line, the other lines go to the log view; every line is also printed to the game's log (`dw_convert: ...`).
- Exit 0: the new folder replaces the old pack (`LauncherLogic.swap_in`: old renamed to `.old`, new renamed in, old deleted). Exit 2 (a porter check failed): "Use it anyway" marks `content.json` `accepted: true` and swaps it in; or try again. Exit 1 / cancel: the old pack is kept, the log path is shown.
- After a conversion, Play restarts the game (`OS.set_restart_on_exit`): `GameData` and `Sound` read the content when they start.
- Where `dw_convert` is (`LauncherLogic.converter_command`): `DW_CONVERT` (an exe, or a `.py` run with `python`); exported, `tools/dw_convert/dw_convert.exe` next to the game's exe (the release zip carries the one-folder build there, D8).

## 4. The update check (U1)

- `version.json` `repo` ("owner/name"; empty: no check). At most once a day (`[updates] last_check`), off with `[updates] check=false`.
- `GET https://api.github.com/repos/<repo>/releases/latest` (4 s timeout). A newer `tag_name` than `Release.game()` (numbers compared, a `v` prefix and pre-release suffixes ignored) shows the version, the notes, "Open the release page" and "Later". Any failure (offline, no release yet) just starts the game.

## 5. Tests

`tests/test_launcher.gd`: the decisions, progress lines, version compare, update timing, release JSON, image search, the swap; `ConverterProcess` on `tests/fixtures/fake_convert.py` (stdout and stderr, exit code); the scene with `live = false` (never leaves, no network): ready pack, the disc page, a whole conversion with the fake into a temp folder, the exit-2 "use it anyway" path. Needs `python` on PATH. The real exe and the update notice are checked by hand (`VERIFY.md` "The exported game").
