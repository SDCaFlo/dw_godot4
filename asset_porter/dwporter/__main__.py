"""Command line: python -m dwporter <command> ...  (run from the asset_porter folder)."""

import argparse
import sys
from pathlib import Path

from . import paths, scan
from .families import FAMILIES


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="dwporter", description="Digimon World asset porter")
    parser.add_argument("--input", type=Path, default=paths.DEFAULT_INPUT, help="dumped game files folder")
    parser.add_argument("--output", type=Path, default=paths.DEFAULT_OUTPUT, help="output folder")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list asset families")

    p = sub.add_parser("convert", help="convert one or more asset families")
    p.add_argument("families", nargs="+", help="family names, or 'all'")

    p = sub.add_parser("scan", help="find TIMs in files (paths relative to --input)")
    p.add_argument("paths", nargs="+")
    p.add_argument("--align", type=int, default=4)
    p.add_argument("--dry-run", action="store_true", help="only print what is found")

    args = parser.parse_args(argv)

    if args.command == "list":
        for name, module in FAMILIES.items():
            print(f"{name:12} {module.SOURCE_PATH:20} {module.SPEC}")
        return 0

    if args.command == "convert":
        names = list(FAMILIES) if args.families == ["all"] else args.families
        unknown = [n for n in names if n not in FAMILIES]
        if unknown:
            parser.error(f"unknown family: {', '.join(unknown)}")
        ok = True
        for name in names:
            out = FAMILIES[name].convert(args.input, args.output)
            failed = [c for c in out.checks if not c.passed]
            print(f"{name}: {len(out.assets)} assets, {len(out.checks) - len(failed)}/{len(out.checks)} checks passed -> {out.dir}")
            for c in failed:
                print(f"  FAILED {c.name}: {c.detail}")
            ok &= not failed
        return 0 if ok else 1

    if args.command == "scan":
        for src, found in scan.scan_files(args.input, args.output, args.paths, args.align, args.dry_run):
            print(f"{src.path}: {len(found)} TIM")
            for t in found:
                print(f"  0x{t.offset:08X} {t.bpp:2}bpp {t.width}x{t.height} vram=({t.x},{t.y})"
                      + (f" clut=({t.clut.x},{t.clut.y})x{t.clut.height}" if t.clut else ""))
        return 0

    return 1


if __name__ == "__main__":
    sys.exit(main())
