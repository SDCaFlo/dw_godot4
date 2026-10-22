"""Command line: python -m dwdata <command> ...  (run from the data_porter folder)."""

import argparse
import sys
from pathlib import Path

from . import paths
from .groups import GROUPS


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(prog="dwdata", description="Digimon World data porter")
    parser.add_argument("--input", type=Path, default=paths.DEFAULT_INPUT, help="dw_decomp folder")
    parser.add_argument("--output", type=Path, default=paths.DEFAULT_OUTPUT, help="output folder")
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("list", help="list data groups")

    p = sub.add_parser("convert", help="convert one or more data groups")
    p.add_argument("groups", nargs="+", help="group names, or 'all'")

    args = parser.parse_args(argv)

    if args.command == "list":
        for name, module in GROUPS.items():
            print(f"{name:12} {module.SOURCE_GLOB:24} {module.SPEC}  {module.PURPOSE}")
        return 0

    if args.command == "convert":
        names = list(GROUPS) if args.groups == ["all"] else args.groups
        unknown = [n for n in names if n not in GROUPS]
        if unknown:
            parser.error(f"unknown group: {', '.join(unknown)}")
        ok = True
        for name in names:
            out = GROUPS[name].convert(args.input, args.output)
            failed = [c for c in out.checks if not c.passed]
            print(f"{name}: {len(out.tables)} tables, {len(out.checks) - len(failed)}/{len(out.checks)} checks passed"
                  f" -> {out.dir}")
            for c in failed:
                print(f"  FAILED {c.name}: {c.detail}")
            ok &= not failed
        return 0 if ok else 1

    return 1


if __name__ == "__main__":
    sys.exit(main())
