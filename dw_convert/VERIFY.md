# Verifying the converter (human checks)

## The exe (`python build_exe.py`)

- `dist/dw_convert/dw_convert.exe identify "<your image>.cue"` prints "Digimon World, US release (SLUS-01032): every file as expected" (about a second).
- `dist/dw_convert/dw_convert.exe run "<your image>.cue" <some folder>`: `PROGRESS` lines climbing to `1.000`, one "checks passed" line per asset family and data group, exit code 0; then `<folder>/content.json` says `"ok": true` and `<folder>/assets`, `<folder>/data` exist. It takes about 20-25 minutes (the music rendering is most of it).
- The game on that output: `DW_PORTER_OUTPUT=<folder>/assets` and `DW_DATA_OUTPUT=<folder>/data` before starting Godot; a new game plays as usual (English only, no movies).
- Delete the folder afterwards (game content).
