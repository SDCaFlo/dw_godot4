# dw_convert

The player's side of the conversion (`../specs/distribution.md`): from their own disc image to the files the two porters read, and (step D5) one entry point that runs both porters. Python 3, standard library only.

Status: D4 done (disc image reader, US check, extraction), D5 done (`run`: both porters in one command; the PyInstaller build).

## Usage

Run from this folder:

```
python -m dwconvert run <image> <output>        # the whole conversion: <output>/assets, data, content.json, convert.log
python -m dwconvert identify <image>            # .cue / .bin / .iso: is it the US disc? every file checked
python -m dwconvert extract <image> <folder>    # the disc files into <folder> (as game_dumped_files/), movies skipped
python -m dwconvert extract <image> <folder> --movies
python -m dwconvert files                       # (developers) rewrite dwconvert/us_files.json from game_dumped_files/
python -m unittest discover -s tests -t .       # real-image tests skipped without the image (DW_DISC_IMAGE); DW_RUN_FULL=1: every asset family
python build_exe.py                             # dist/dw_convert/dw_convert.exe (PyInstaller in .build/, gitignored)
```

## Code layout

| Path | Role |
|---|---|
| `dwconvert/image.py` | Images (`.cue` first data track, raw 2352 or 2048 sectors, mode 1 / mode 2 form 1 and 2), the ISO 9660 tree, `read_file` (each sector's data part, as `game_dumped_files/` has it), `extract` |
| `dwconvert/identify.py` | The US check: `SYSTEM.CNF`'s boot file, then every file's size and sha1 against `us_files.json` |
| `dwconvert/us_files.json` | Path, size and sha1 of the US disc's 818 files: hashes only, never content. Committed |
| `dwconvert/run.py` | `run()`: check, extract to a temp folder, every asset family (movies only with `--movies`), every data group in disc mode, `content.json` (`CONTENT_FORMAT`); `PROGRESS <0..1> <message>` lines and `convert.log` |
| `dw_convert.py`, `build_exe.py` | The exe's entry point and its build (one-folder PyInstaller; bundles the porters, `us_files.json` and the data porter's snapshot) |
| `specs/disc_image.md`, `specs/convert.md` | The specs (D4, D5) |
| `tests/test_image.py` | Synthetic images built by the test; with the developer's image, every file equal to `game_dumped_files/` |
| `tests/test_run.py` | With the developer's image: `run` with two asset families and every data group, equal to the porters run on `game_dumped_files/` |

## When the porters change

The exe bundles both porters and the data porter's snapshot: rebuild it (`python build_exe.py`) for a release after any porter change, and bump `run.CONTENT_FORMAT` when the game can't read an older output any more (the launcher then converts again, `../specs/distribution.md` §6).

## Rules

- Never write into `external-resources/` or the player's image; extracted files go where the caller says (game content: never commit them).
- The image is read, never trusted: a file that isn't the US one is reported, and the conversion stops unless `--allow-modified`.
