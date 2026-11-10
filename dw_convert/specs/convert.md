# The conversion (distribution step D5)

One command from the player's disc image to the `dw1` content pack the game loads: `dw_convert run <image> <output>` (`python -m dwconvert run` in the source tree, `dw_convert.exe run` in a release). Parent spec: `../../specs/distribution.md` §2.2, §5, §6. Code: `dwconvert/run.py`; the exe: `build_exe.py`.

## 1. Steps

| Step | What | Progress share |
|---|---|---|
| check | open the image, the US check (`disc_image.md` §4); stops unless US (or `--allow-modified`) | 5% |
| extract | the disc files into a temp folder (movies skipped unless `--movies`) | 15% |
| assets | every asset porter family (`dwporter.families.FAMILIES`) but `movies` (unless `--movies`) into `<output>/assets` | 70% |
| data | every data porter group in disc mode (`dwdata.discmode.convert`) into `<output>/data` | 10% |

The temp folder is deleted at the end (`--keep-files` keeps it). Both porters run in the same process, imported as packages (bundled in the exe, or from `../asset_porter` and `../data_porter` in the source tree).

## 2. Output

```
<output>/
  assets/          the asset porter's output (as asset_porter/output/)
  data/            the data porter's output (as data_porter/output/), en_us only
  content.json     {pack, content_format, release, boot, movies, modified_files, porters, converted, ok}
  convert.log      every line printed, plus the traceback of an error
```

`content_format` (`run.CONTENT_FORMAT`, 1) is what the launcher compares with its own to convert again after an update (distribution §6). The game points `Content` at `assets/` and `GameData` at `data/` (D6).

## 3. Progress and exit codes

- Lines `PROGRESS <0..1> <message>` on stdout (overall fraction, three decimals), for the launcher's bar; other lines are messages for the log view.
- Exit 0: done; 1: the image is not usable (not US, unreadable, an error: the message and `convert.log`); 2: converted, but a porter check failed (`FAILED ...` lines; `content.json` has `ok: false`).

## 4. The exe

`python build_exe.py` builds `dist/dw_convert/` (one-folder PyInstaller build: `dw_convert.exe` + `_internal/`), with PyInstaller 6.11.1 from its own environment in `.build/` (gitignored); data files bundled: `dwconvert/us_files.json`, `data_porter/dwdata/snapshot/us.json`. Excluded: numpy, PIL, tkinter (optional speed-ups, movies only). Windows first (distribution §1); the same script builds on Linux / Mac later.

## 5. Tests

`tests/test_run.py`: with the developer's image (skipped without it), the whole run into a temp folder: exit 0, every step's checks pass, `content.json`, the data output equal to `discmode.convert` on `game_dumped_files/`, and the assets output equal to the asset porter's on `game_dumped_files/` (spot files). The exe is checked by hand (`VERIFY.md`).
