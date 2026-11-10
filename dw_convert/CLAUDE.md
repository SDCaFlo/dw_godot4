# dw_convert

The player's side of the conversion (`../specs/distribution.md`): from their own disc image to the files the two porters read, and (step D5) one entry point that runs both porters. Python 3, standard library only.

Status: D4 done (disc image reader, US check, extraction). D5 (the `dw_convert` entry point running both porters, the PyInstaller build) to do.

## Usage

Run from this folder:

```
python -m dwconvert identify <image>            # .cue / .bin / .iso: is it the US disc? every file checked
python -m dwconvert extract <image> <folder>    # the disc files into <folder> (as game_dumped_files/), movies skipped
python -m dwconvert extract <image> <folder> --movies
python -m dwconvert files                       # (developers) rewrite dwconvert/us_files.json from game_dumped_files/
python -m unittest discover -s tests -t .       # real-image tests skipped without the image (DW_DISC_IMAGE)
```

## Code layout

| Path | Role |
|---|---|
| `dwconvert/image.py` | Images (`.cue` first data track, raw 2352 or 2048 sectors, mode 1 / mode 2 form 1 and 2), the ISO 9660 tree, `read_file` (each sector's data part, as `game_dumped_files/` has it), `extract` |
| `dwconvert/identify.py` | The US check: `SYSTEM.CNF`'s boot file, then every file's size and sha1 against `us_files.json` |
| `dwconvert/us_files.json` | Path, size and sha1 of the US disc's 818 files: hashes only, never content. Committed |
| `specs/disc_image.md` | The spec |
| `tests/test_image.py` | Synthetic images built by the test; with the developer's image, every file equal to `game_dumped_files/` |

## Rules

- Never write into `external-resources/` or the player's image; extracted files go where the caller says (game content: never commit them).
- The image is read, never trusted: a file that isn't the US one is reported, and the conversion stops unless `--allow-modified`.
