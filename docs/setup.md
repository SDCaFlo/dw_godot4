# Playing dw_godot4 (Windows)

dw_godot4 is an unofficial, non-commercial port of *Digimon World* (PlayStation, 1999) to the Godot engine. **The download contains no game content.** You need your own copy of the game: the port converts the content from your disc image, once, on your computer.

The port is a work in progress: many parts of the game are done, others are missing or use stand-ins. Movies are not converted yet.

## What you need

- Windows 10 or 11, 64-bit, with a graphics card that supports Direct3D 12.
- A disc image of **Digimon World, US release (SLUS-01032)**. Japanese and European discs are not supported yet. Best as `.cue` + `.bin`. A single `.bin` or a `.iso` also works. Make it from a disc you own. This project doesn't link to disc images or tell you where to find them.
- About 2 GB of free space: 1.5 GB for the converted content, plus the game.

## Install

1. Download `dw_godot4-<version>-windows.zip` from the [Releases page](https://github.com/SDCaFlo/dw_godot4/releases).
2. Unzip it anywhere, for example `C:\Games\dw_godot4`. Keep the `tools` folder next to `dw_godot4.exe`.
3. Start `dw_godot4.exe`.

The exe isn't signed, so Windows SmartScreen may say *"Windows protected your PC"*. Click **More info**, then **Run anyway**. Windows asks once per new version.

## First start: converting your disc

1. The launcher asks for your disc image. If an image is in the game's folder, it's already filled in. Otherwise click **Browse** and choose the `.cue` (or the `.bin` / `.iso`).
2. The launcher checks the image right away. If it's not the US release, or the file isn't a usable disc image, it says so.
3. Click **Convert**. The conversion takes roughly 15 to 30 minutes, most of it rendering the music. A progress bar and a log show what it's doing. You can cancel; nothing is kept from a cancelled run.
4. When it's done, click **Play**. The game restarts once and opens the title screen.

From then on, the game starts directly. The disc image is only needed again when an update changes the converter. The launcher then asks to convert again, using the image path it remembers.

## Where your files are

Everything the game writes is in `%APPDATA%\dw_godot4\`. To open it, paste that path into the Explorer address bar.

| Folder / file | What |
|---|---|
| `content\dw1\` | The converted content (made from your disc; don't share it). |
| `saves\` | Your saves. |
| `settings.cfg` | The disc image path and the update check setting. |
| `logs\godot.log` | The game's log (the last runs). |
| `content\dw1\convert.log` | The last conversion's log. |

The game's folder (where the exe is) holds only the program. It can be deleted or replaced without losing anything.

## Launcher settings

Hold **Shift** while the game starts to open the launcher's settings:

- **Play**.
- **Convert again**, from the image shown (choose another one first if you want).
- **Update check: on / off**.
- **Quit**.

## Updates

Once a day at most, the launcher checks GitHub for a newer release. If one is out, it shows the version and the notes, with a button that opens the release page. To update:

1. Download the new zip.
2. Unzip it **over** your game folder, replacing the files. Or unzip it to a new folder and delete the old one.

Your saves and the converted content are in `%APPDATA%\dw_godot4\`, so they're kept. If the new version needs the content converted again, the launcher says so on the next start.

The check only reads `api.github.com`. It sends nothing about you or your game. Turn it off in the launcher settings.

## Controls

A controller (XInput, e.g. an Xbox pad) maps like a PlayStation pad. On the keyboard:

| PlayStation | Keyboard |
|---|---|
| D-pad | Arrow keys |
| ✕ | Enter or Space |
| ◯ | Backspace |
| △ (menu) | Esc |
| R1 (run) | Shift |
| Start | P |

□, L1, L2, R2 and Select have no keyboard keys yet: use a controller for them.

## When something goes wrong

- **"This image can't be used"**: the file isn't the US disc, or it isn't a disc image (`.cue` / `.bin` / `.iso`). If you chose a `.cue`, its `.bin` must be in the same folder, under the name the `.cue` lists.
- **"Conversion failed"**: click **Open the log**. The log is also at `%APPDATA%\dw_godot4\content\dw1.new\convert.log`. Your previous content, if any, is kept.
- **"Conversion finished with problems"**: the content was made, but some checks failed. **Use it anyway** plays with it, though some things may look wrong. Please report it with the log.
- **The game doesn't start or shows a black window**: update your graphics driver. Then look at `%APPDATA%\dw_godot4\logs\godot.log`.
- **Start again from scratch**: delete `%APPDATA%\dw_godot4\content\`. The next start converts again. Keep `saves\`.

Report bugs on the [Issues page](https://github.com/SDCaFlo/dw_godot4/issues) with the version (in the launcher settings) and the log. **Don't attach screenshots of game art, game files or your converted content**: the project doesn't host game content.

## Legal

This port isn't affiliated with or endorsed by Bandai Namco or any rights holder. Digimon World and all related names are the property of their owners. Our code is MIT-licensed (`LICENSE`), and that licence doesn't cover the game's content. Don't share disc images or the converted content.
