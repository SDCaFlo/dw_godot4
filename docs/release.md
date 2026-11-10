# Making a release (for us)

How a version of dw_godot4 gets from `main` to players. The design: `specs/distribution.md`. The build: `specs/release_ci.md` (workflow `.github/workflows/release.yml`, packaging `release/package.py`). What players read: `docs/setup.md` (link it from the release notes).

## The rules

- **Code only.** Never commit, attach or upload game content anywhere: disc files, the porters' output, the editor mirror `content/dw1/`, screenshots or recordings of game art, decomp text in bulk, models from other games (`distribution.md` §1, §8). `package.py` refuses a zip that looks like content; that is a last guard, not the check.
- **Only `main` is pushed** to `origin` (`SDCaFlo/dw_godot4`), and only after the blob scan below. `spec/digimon_contract` is never pushed (it holds a model from another game).
- **Commits use the GitHub noreply address** (`git config user.email`), never a personal one.

## 1. Before the release

1. Everything merged into `main`. The tests pass locally: the Godot suites listed in `VERIFY.md` and the porters' `unittest`s.
2. Pick the version (`x.y.z`; before 1.0: `y` for new systems, `z` for fixes). Set `version.json` `game`.
3. Did the converter's output change in a way old content can't be read? Then bump `content_format` in **both** `version.json` and `dw_convert/dwconvert/run.py` `CONTENT_FORMAT` (`tests/test_release.gd` checks they agree). Players will convert again on their next start, so say so in the notes.
4. `mod_api` stays 0 until mods are released (`distribution.md` §7).
5. Commit "Release x.y.z" on `main`.

## 2. The scan before pushing

From `dw_godot/`, list what the push would add and check that none of it is content:

```
git fetch origin
git rev-list --objects origin/main..main | git cat-file --batch-check='%(objecttype) %(objectname) %(objectsize) %(rest)' | grep '^blob' | sort -k3 -n | tail -20
git log --format='%ae' origin/main..main | sort -u
```

- No image, model, audio, movie or disc file types. No unexplained large blob (`.py` tables and `us_files.json` are expected).
- The only author address is the noreply one.

Then `git push origin main`.

## 3. Try the build

Actions > **release** > **Run workflow** (branch `main`). It runs the content-free tests, exports the game, builds `dw_convert.exe` and keeps the zip as an artifact for 3 days. Download it, unzip it somewhere new, and check by hand (`VERIFY.md` "The exported game"):

- It starts on the launcher. With existing content in `%APPDATA%\dw_godot4\content\dw1` it goes straight to the title.
- Shift at start opens the settings page, showing the new version.
- If `content_format` changed: the launcher asks to convert again, and the conversion works.
- A save loads.

The same build locally, without GitHub: `specs/release_ci.md` §5.

## 4. Tag and publish

```
git tag vX.Y.Z
git push origin vX.Y.Z
```

The tag must equal `version.json` `game` (`package.py` refuses otherwise). The workflow creates a **draft** release `dw_godot4 X.Y.Z` with the zip and GitHub's generated notes. Nothing is public yet.

Edit the draft's notes, which are what the launcher's update notice shows:

- What changed, for players: systems added, bugs fixed. Not the commit list.
- **"Converts again"** when `content_format` changed (the disc image is needed).
- Known problems.
- A link to `docs/setup.md` (install, SmartScreen, where saves are).

Then **Publish release**. Players' launchers see it on their next daily check (`releases/latest` ignores drafts and pre-releases).

A wrong tag before publishing: delete the draft, then `git push origin :refs/tags/vX.Y.Z` and `git tag -d vX.Y.Z`. Fix and tag again. Once published, don't move a tag: make `x.y.z+1`.

## 5. After

- Tick the release in `PLANS.md`.
- Try the update notice once: start an older build with the update check due. It shows the new version and notes. The check runs at most once a day; delete `[updates] last_check` in `%APPDATA%\dw_godot4\settings.cfg` to force it.

## Notes

- **Private repository**: while it is private, the launcher's check gets a 404 and just starts the game. Players can't download either: releases are for people with access to the repo.
- **Actions minutes**: free on a public repository. On a private one they count toward the monthly free minutes (`release_ci.md` §4).
- **Godot upgrade**: change `GODOT_VERSION` in the workflow along with the project. Its cache key changes with it.
- **Signing**: the exe and `dw_convert.exe` are unsigned (SmartScreen warns). Signing is a later decision (cost, a certificate).
