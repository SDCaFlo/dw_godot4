# Disc image (distribution step D4)

How the player's disc image becomes the folder of disc files the two porters read (`game_dumped_files/` on our machine), and how we know it is the US release. Parent spec: `../../specs/distribution.md` §3. Code: `dwconvert/image.py`, `dwconvert/identify.py`; tests `tests/`.

## 1. Input

| Image | How it is read |
|---|---|
| `.cue` | its first `FILE` and that file's first data `TRACK`: `MODE2/2352` (the PSX standard), `MODE1/2352`, `MODE1/2048`; `INDEX 01` must be `00:00:00` (the data track starts the file) |
| `.bin` / `.img` without a cue | raw 2352-byte sectors when the size is a multiple of 2352 and sector 16 starts with the CD sync pattern (`00 FF×10 00`); else 2048-byte sectors |
| `.iso` | 2048-byte sectors (user data only) |

Other formats (`.chd`, `.ecm`, `.pbp`, multi-file cues) are refused with a message naming the format; converting them to `.bin/.cue` is the player's step (`docs/setup.md`).

The image checked on 2026-11-09 (`Digimon World (USA).bin/.cue`, 381,771,936 bytes = 162,318 sectors of 2352): one `MODE2/2352` track; the ISO 9660 volume descriptor at sector 16 (volume `DIGIMON`, 162,318 blocks of 2048), root directory at sector 22.

## 2. Sectors

A raw sector (2352 bytes) is sync (12), header (4: minute, second, frame, mode), then:

- **mode 1**: 2048 bytes of data, EDC / ECC;
- **mode 2** (CD-ROM XA): subheader (8: file, channel, submode, coding, twice); submode bit 5 (`0x20`) set = **form 2**: 2324 bytes of data + EDC (XA audio, part of the movies), else **form 1**: 2048 bytes + EDC / ECC.

A 2048-byte image holds only the form 1 data; a form 2 sector there is lost (its 2048 bytes are not the audio).

EDC / ECC are not checked (a bad dump shows as a file whose sha1 is not the US one, §4).

## 3. Files

ISO 9660: the primary volume descriptor (sector 16, `\x01CD001`), the root directory record at byte 156, directory records (length, extent LBA at +2, data length at +10, flags at +25: bit 1 = directory, name length at +32, name at +33, `;1` version dropped). Directories can span several sectors; a record never crosses a sector boundary (the rest of a sector is zero).

A file's bytes, as `game_dumped_files/` has them (`game_dumped_files/RESOURCE_DEFINITION.md`): for every sector of its extent (`ceil(data length / 2048)` sectors), the data part (2048 for form 1, 2324 for form 2), the last one cut at the data length for a file with no form 2 sector. So the movies (`MOVIE/*.STR`, mixed form 1 video and form 2 audio) come out as in the dump: every sector's payload; the other files are their data length exactly.

`extract(image, dest)` writes every file under its folder path (`CHDAT/MMD0/AGUM.MMD`). Options: skip the movies (`MOVIE/`, about 130 MB; the release build skips them, distribution Q2) and skip `MMM.DAT` (27 MB of zeros the code never opens; the asset porter's `mmm_dat` family checks it, so it stays by default).

## 4. The US check

`identify(image)`:

1. `SYSTEM.CNF` names the boot file (`BOOT = cdrom:\SLUS_010.32;1`). Another boot file: "this is <name>, only the US release (SLUS-01032) is supported", nothing extracted.
2. Every file is compared with the committed list of the US disc's files (`dwconvert/us_files.json`: path, size, sha1; hashes, not content), written from our dump by `python -m dwconvert files`. A file with another sha1, or missing, is reported by name (a bad or modified dump); the conversion refuses unless asked to go on (`--allow-modified`, for modded discs, at the player's risk).

The hashes of the 9 binaries the data porter reads are also in its snapshot (`data_porter/dwdata/snapshot/us.json`), which `DiscIndex` checks again.

## 5. Tests

- Synthetic images built in the test (a small ISO 9660 tree, raw mode 2 sectors with form 1 and form 2 data, and the same as 2048-byte `.iso`): files, folders, a directory over two sectors, form 2 payloads, a 2048 image losing form 2.
- With the developer's image (skipped if missing): `identify` says US; every extracted file equals `game_dumped_files/` byte for byte; `us_files.json` matches the dump.

## 6. Open questions

- Q1: Where the extracted files go for players (`user://` of the game, or a temp folder deleted after the conversion). Decided with the launcher (D7); D5's converter takes the folder as an argument.
