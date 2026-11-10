"""Command line: python -m dwconvert <command> ...  (run from the dw_convert folder).

  run <image> <output>             the whole conversion: the dw1 pack (assets/, data/, content.json) in <output>
  identify <image>                 is it the US disc? every file checked against us_files.json
  extract <image> <folder>         the disc files into <folder> (as game_dumped_files/), after the check
  files [<dump folder>]            (developers) rewrite us_files.json from a dump of the US disc
"""

import argparse
import json
import sys
from pathlib import Path

from . import identify as ident
from . import image

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent.parent
DEFAULT_DUMP = PROJECT_ROOT / "external-resources" / "game_dumped_files"
MOVIES = "MOVIE/"


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="dwconvert", description="Digimon World disc image tools")
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("run", help="convert a disc image into the game's dw1 content (both porters)")
    p.add_argument("image", type=Path)
    p.add_argument("output", type=Path)
    p.add_argument("--movies", action="store_true", help="also convert the movies (needs ffmpeg)")
    p.add_argument("--allow-modified", action="store_true", help="go on when files differ from the US disc")
    p.add_argument("--keep-files", action="store_true", help="keep the extracted disc files (in a temp folder)")
    p = sub.add_parser("identify", help="check a disc image")
    p.add_argument("image", type=Path)
    p = sub.add_parser("extract", help="extract a disc image's files")
    p.add_argument("image", type=Path)
    p.add_argument("folder", type=Path)
    p.add_argument("--movies", action="store_true", help="also the movies (MOVIE/*.STR, about 130 MB)")
    p.add_argument("--allow-modified", action="store_true",
                   help="go on when files differ from the US disc (a modded disc, at your own risk)")
    p = sub.add_parser("files", help="(developers) write us_files.json from a dump of the US disc")
    p.add_argument("dump", type=Path, nargs="?", default=DEFAULT_DUMP)
    args = parser.parse_args(argv)
    sys.stdout.reconfigure(errors="backslashreplace")

    if args.command == "run":
        from .run import run
        return run(args.image, args.output, args.movies, args.allow_modified, args.keep_files)

    if args.command == "files":
        listing = ident.file_list(args.dump)
        ident.US_FILES.write_text(json.dumps({
            "release": "us", "boot": ident.US_BOOT, "generated_by": "python -m dwconvert files",
            "files": listing}, indent=1) + "\n", encoding="utf-8")
        print(f"{len(listing)} files -> {ident.US_FILES}")
        return 0

    try:
        img = image.open_image(args.image)
    except (image.ImageError, OSError) as e:
        print(f"error: {e}")
        return 2
    with img:
        skip = () if args.command == "identify" or args.movies else (MOVIES,)
        report = ident.identify(img, skip)
        print(report.message())
        if args.command == "identify":
            return 0 if report.ok else 1
        if not report.us or (not report.ok and not args.allow_modified):
            return 1
        last = [0]

        def progress(done, total, path):
            pct = done * 100 // total
            if pct >= last[0] + 10 or done == total:
                last[0] = pct
                print(f"  {pct}% ({done}/{total}) {path}")

        written = image.extract(img, args.folder, skip, progress)
        print(f"{len(written)} files -> {args.folder}" + ("" if args.movies else " (movies skipped)"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
