# asset_porter

Tooling that converts the original Digimon World (US, PSX) disc files into Godot-friendly formats, while keeping a documented link between each converted asset and the original code that used it.

Status: core implemented in Python 3 (standard library only; Pillow optional for viewing). Progress per format and family is tracked in `PROGRESS.md`; read it first and update it (tables + log line) whenever a format or family changes status.

## Usage

Run from this folder:

```
python -m dwporter list                       # asset families
python -m dwporter convert card_all           # or: convert all
python -m dwporter scan ETCDAT/ITEM.TIM       # find TIMs in any file (PSXPrev-style), --dry-run to only print
python -m unittest discover -s tests -t .     # tests (real-data test skipped if the dump is missing)
```

Defaults: input `../../external-resources/game_dumped_files/`, output `output/` (gitignored); override with `--input` / `--output`. `convert` exits non-zero if any verification check fails.

## Code layout

| Path | Role |
|---|---|
| `dwporter/__main__.py` | CLI |
| `dwporter/paths.py` | Default paths, sector size |
| `dwporter/source.py` | `SourceFile` / `SourceSpan`: byte ranges that carry their identity (path, offset, size, sha1) |
| `dwporter/assets.py` | `AssetWriter`: writes outputs + sidecar JSON + `manifest.json`, records checks |
| `dwporter/formats/` | Format parsers (`tim.py`, `tmd.py`), PSX helpers (`psx.py`: colours, `GetTPage`, `GetClut`) and `vram.py` (VRAM copy that builds textures like the GPU) |
| `dwporter/exporters/` | Writers for open formats (`png.py`, `gltf.py`; stdlib only) |
| `dwporter/models.py` | TMD → glTF conversion used by `AssetWriter.write_tmd` |
| `dwporter/families/` | One converter per asset family, registered in `families/__init__.py` |
| `dwporter/data/` | Tables generated from the decomp, shared by families (`digimon.py`: type id → file name, display name, model path) |
| `dwporter/scan.py` | Generic TIM scan of any file |
| `specs/` | One spec per format/family |
| `tests/` | `unittest` tests |
| `output/` | Generated: `output/<family>/` and `output/scan/<source path>/` |

## Identity (lossless) rules

Every output has a sidecar `<name>.json` with: `asset_id` (`<path>@0x<offset>`), `family`, `format`, `source` (path, offset, size, sha1 of the bytes and of the whole file), `psxprev_name`, `outputs`, the format's raw header data (e.g. TIM palettes as raw u16 values) and its hardware placement (`vram`: rects, tpage, CLUT ids), plus family data (e.g. `card.id`, slot sectors). Each family folder has a `manifest.json` with code references, source file hashes and check results. Outputs must keep all information needed to rebuild the original data (indexed PNGs keep indices; raw values live in the sidecar). Never drop a field to simplify an output.

## Goals

- Read the **user's own** dumped disc files; never commit game data or converted output.
- Write only open formats (PNG, glTF, OGG/WAV, JSON) plus metadata that keeps each asset's original identity: source file, offset, size, format, and the hardware placement the code relies on (VRAM x/y, CLUT position, scale, ...).
- One spec per asset family, written from the decomp, that both the converter and Claude follow.
- Deterministic and re-runnable: same input gives the same output.

## Folder links

Paths are relative to this folder.

| What | Path | Notes |
|---|---|---|
| Dumped game files (input) | `../../external-resources/game_dumped_files/` | Original disc files, read-only. Read its `RESOURCE_DEFINITION.md` first. |
| Output | `output/` | Generated, gitignored. |
| Decompiled code | `../../external-resources/dw_decomp/` | Read its `RESOURCE_DEFINITION.md` first. |
| PSXPrev (reference tool/source) | `../../external_tools/psxprev/` | Read its `RESOURCE_DEFINITION.md` first. |
| Godot project | `../` | Converted assets are consumed from here. |
| Project overview | `../../CLAUDE.md` | |

### `game_dumped_files/` contents

| Path | Contents | Size |
|---|---|---|
| `SLUS_010.32` | Main executable (`main` in the decomp) | |
| `*_REL.BIN` | Code overlays (`btl`, `std`, `trn`, `vs`, ...; see dw_decomp) | |
| `CARD/CARD.ALL` | Single 1.8 MB file (`0x1ce000`, matches `FILE_OFFSET_TABLE`) | 1.9M |
| `CHDAT/` | `MMD0`–`MMD5/` + root: 178 `.MMD` (Digimon models), 1 `.TIM` | 13M |
| `MAP/` | `MAP1`–`MAP17/`: 242 `.MAP` + 242 `.TFS` | 134M |
| `DOOR/` | 33 `.TMD` | 52K |
| `ETCDAT/`, `ETCHI/`, `ETCNA/` | `.TIM`, `.TMD`, `.EFE`, `.BIN` | ~3M |
| `STDDAT/` | `.TIM`, `.TMD`, `.ATR`, `.BIN`; `GRADE/` subfolder | 1.5M |
| `SCN/` | 2 `.SCN` | 816K |
| `SOUND/VHB/` | 7 `.VHB` | 7.9M |
| `MOVIE/` | 4 `.STR` (MDEC video) | 131M |
| `MMM.DAT` | 27 MB data file | |
| `SYSTEM.CNF` | Boot config | |

Formats are only known by extension until a spec confirms them. Standard PSX formats: TIM (texture), TMD (model), STR (video). Game-specific: MMD, MAP, TFS, EFE, ATR, SCN, VHB, `MMM.DAT`.

## Specs

Location: `specs/<family>.md`, one per format or asset family. Existing: `specs/tim.md` (TIM format), `specs/card_all.md` (`CARD/CARD.ALL`), `specs/alltim.md` (`CHDAT/ALLTIM.TIM`), `specs/stacked_tim.md` (`ETCDAT/ETCTIM.BIN`, `STDDAT/STDTIM.BIN`), `specs/tim_files.md` (51 standalone `*.TIM`), `specs/tmd.md` (TMD format, glTF export, `tmd_files`).

Each spec must contain:

1. **On disc:** path, `FILE_OFFSET_TABLE` entry (`dw_decomp/src/main/file_table_us.c`), layout (header, tables, offsets).
2. **Original handling:** loader and user functions with `file:line` references (C in `dw_decomp/src`, asm in `dw_decomp/asm/us`); how it is read into RAM, which offsets/indices the code computes, where data ends up (VRAM rect, CLUT, RAM address, symbol from `config/us/symbols*.txt`).
3. **Godot representation:** output files and formats, and how each original access maps to the new one (e.g. "offset into table N" becomes `cards[N]`).
4. **Metadata:** the fields written next to each output to keep its original identity.
5. **Verification:** checks the converter runs (sizes, counts, round-trips) against values in the code or file.
6. **Open questions:** anything not confirmed from code, clearly marked.

Write specs from evidence in the decomp, not from guesses. Update the spec before changing converter behaviour.

## Tool: PSXPrev

`../../external_tools/psxprev/` — read `RESOURCE_DEFINITION.md` there.

- Use as **reference source** for standard formats: `Common/Parsers/TIMParser.cs` (TIM), `TMDParser.cs`/`TMDHelper.cs` (TMD), `Common/Exporters/glTF2Exporter.cs` (glTF).
- Use as **cross-check**: its output for a file shows which standard blocks exist and at which offset. Names are `<file>_<hex offset>` (e.g. `MGEN99.MAP_20558` = offset `0x20558`).
- It does not understand game-specific formats; do not treat its output as complete.
- Do not copy its code verbatim without keeping the BSD 2-Clause notice.

## Workflow for a new asset family

1. Find the file in `FILE_OFFSET_TABLE` and grep the decomp for its name, index and loader (`file.c`, `file_queue.c`, `file_table_us.c` are the entry points).
2. Read the code that consumes the data; note offsets, structs (`include/dw/*.h`) and VRAM/CLUT targets.
3. Scan the file (`python -m dwporter scan <path> --dry-run`, or PSXPrev) to see the standard blocks it contains.
4. Write `specs/<family>.md`.
5. Implement `dwporter/families/<family>.py` (follow `card_all.py`: `NAME`, `SOURCE_PATH`, `SPEC`, `CODE_REFS`, `convert()` with `out.check(...)` for every assumption), register it, add tests.
6. Run it, review the output, and record findings back in the spec.
7. Update `PROGRESS.md`.

## Rules

- Never write into `external-resources/` or `external_tools/`.
- Never commit dumped or converted game data; generated output goes to a gitignored folder.
