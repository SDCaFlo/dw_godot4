"""Builds the release zip (distribution step D8, specs/release_ci.md) from the Godot export and the
dw_convert build, and refuses to package anything that looks like game content.

    python release/package.py <version>      (from dw_godot/; after the export and build_exe.py)

Reads build/windows/ (dw_godot4.exe, dw_godot4.pck) and dw_convert/dist/dw_convert/; writes
build/dw_godot4-<version>-windows.zip:

    dw_godot4-<version>-windows/
      dw_godot4.exe, dw_godot4.pck
      tools/dw_convert/            dw_convert.exe + _internal/
      LICENSE, THIRD_PARTY_NOTICES.md, README.txt
"""

import json
import re
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
EXPORT = ROOT / "build" / "windows"
CONVERT = ROOT / "dw_convert" / "dist" / "dw_convert"
NAME = "dw_godot4"

# Extensions of game content (disc files and the porters' output): never in a release.
CONTENT_EXT = {".glb", ".gltf", ".png", ".jpg", ".wav", ".ogg", ".ogv", ".mid", ".sf2", ".bin", ".cue",
               ".iso", ".tim", ".tmd", ".mmd", ".str", ".vh", ".vb", ".dat", ".scn", ".map"}
# Folders of the porters' output and the editor mirror, as they would appear inside the .pck.
CONTENT_PATHS = (b"content/dw1/", b"asset_porter/output", b"data_porter/output", b"mmd_files/", b"card_all/")
# The .pck holds code and scenes only (about 2 MB); far more means content got in.
PCK_LIMIT = 20 * 1024 * 1024


def check_version(version: str) -> list:
    game = json.loads((ROOT / "version.json").read_text(encoding="utf-8")).get("game")
    return [] if game == version else [f"version.json game is {game!r}, the tag says {version!r}"]


def check_files(files: list) -> list:
    """files: [(path in the zip, Path on disk)]."""
    problems = []
    for arc, src in files:
        if Path(arc).suffix.lower() in CONTENT_EXT:
            problems.append(f"{arc}: a game content file type")
    pck = EXPORT / f"{NAME}.pck"
    if pck.stat().st_size > PCK_LIMIT:
        problems.append(f"{pck.name} is {pck.stat().st_size // 1024 // 1024} MB (limit {PCK_LIMIT // 1024 // 1024} MB)")
    data = pck.read_bytes()
    for p in CONTENT_PATHS:
        if p in data:
            problems.append(f"{pck.name} names {p.decode()}")
    return problems


def collect(version: str) -> list:
    top = f"{NAME}-{version}-windows"
    files = [(f"{top}/{NAME}.exe", EXPORT / f"{NAME}.exe"), (f"{top}/{NAME}.pck", EXPORT / f"{NAME}.pck")]
    for f in sorted(CONVERT.rglob("*")):
        if f.is_file():
            files.append((f"{top}/tools/dw_convert/{f.relative_to(CONVERT).as_posix()}", f))
    for f in ("LICENSE", "THIRD_PARTY_NOTICES.md"):
        files.append((f"{top}/{f}", ROOT / f))
    files.append((f"{top}/README.txt", ROOT / "release" / "README.txt"))
    return files


def main(argv) -> int:
    if len(argv) != 1 or not re.fullmatch(r"\d+\.\d+\.\d+([-+].+)?", argv[0].lstrip("v")):
        print(__doc__)
        return 2
    version = argv[0].lstrip("v")
    missing = [p for p in (EXPORT / f"{NAME}.exe", EXPORT / f"{NAME}.pck", CONVERT / "dw_convert.exe") if not p.is_file()]
    if missing:
        print("missing (export the game and run build_exe.py first): " + ", ".join(map(str, missing)))
        return 1
    files = collect(version)
    problems = check_version(version) + check_files(files)
    if problems:
        for p in problems:
            print("REFUSED " + p)
        return 1
    out = ROOT / "build" / f"{NAME}-{version}-windows.zip"
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for arc, src in files:
            z.write(src, arc)
    print(f"{out} ({out.stat().st_size // 1024 // 1024} MB, {len(files)} files)")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
