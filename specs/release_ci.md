# Release builds on GitHub Actions (distribution step D8)

How a release zip is built. Parent spec: `distribution.md` §1, §4, §9. Workflow: `.github/workflows/release.yml`; packaging: `release/package.py`; the player's `README.txt`: `release/README.txt`.

## 1. Triggers

- **A version tag** `vX.Y.Z` pushed to GitHub: build, then a **draft** release named `dw_godot4 X.Y.Z` with the zip attached and GitHub's generated notes. Nothing is public until the draft is published by hand (edit the notes first: they are what the launcher shows, `launcher.md` §4).
- **Run workflow** (Actions tab, `workflow_dispatch`): the same build, the zip kept as an artifact for 3 days, no release. Use it to try a build.

The tag must equal `version.json` `game` (`package.py` refuses otherwise): bump `version.json`, commit, then tag that commit.

## 2. Steps (windows-latest)

1. Godot `GODOT_VERSION` (the official build from `godotengine/godot-builds`) and only `templates/windows_release_x86_64.exe` from the export templates, cached between runs (`actions/cache`, about 100 MB instead of the 1 GB `.tpz`).
2. `--import`, then the tests that need no game content: `test_rules`, `test_release`, `test_launcher` (Godot), the `dw_convert` unit tests (synthetic images; the real-image tests skip). The other suites need the porters' output and stay local.
3. `--export-release "Windows Desktop"` (`export_presets.cfg`) and `python build_exe.py` (PyInstaller 6.11.1, Python `PYTHON_VERSION`).
4. `python release/package.py <version>`: `dw_godot4-<version>-windows.zip` laid out as `distribution.md` §4 (`dw_godot4.exe`, `.pck`, `tools/dw_convert/`, `LICENSE`, `THIRD_PARTY_NOTICES.md`, `README.txt`).

## 3. The content guard (`package.py`)

The zip is refused when a file has a game content extension (images, models, audio, movies, disc files), the `.pck` is over 20 MB (it is about 2 MB of code and scenes), or the `.pck` names the porters' output or the editor mirror (`content/dw1/`, `asset_porter/output`, ...). The runner has no game files in the first place; the guard catches a preset or `.gitignore` change that would let local content into a local build.

## 4. Cost

GitHub-hosted runners are free without limit on public repositories. On a private repository (GitHub Free) the account has 2,000 minutes a month and Windows minutes count double; a release run is about 10-15 minutes (more on the first, uncached run), so about 20-30 of the monthly minutes. Artifacts count toward the 500 MB storage of private repositories, hence the 3-day retention. Check Settings > Billing for the current numbers.

## 5. Local equivalent

From `dw_godot/`: export (Project > Export, or `godot --headless --path . --export-release "Windows Desktop" build/windows/dw_godot4.exe`), `cd dw_convert && python build_exe.py`, then `python release/package.py <version>`.
