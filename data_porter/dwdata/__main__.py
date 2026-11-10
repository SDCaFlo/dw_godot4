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

    p = sub.add_parser("snapshot", help="write dwdata/snapshot/us.json (disc mode layouts) from the decomp")
    p.add_argument("--disc", type=Path, default=paths.DEFAULT_DISC,
                   help="folder with the US binaries (SLUS_010.32, *_REL.BIN): records their sha1 and checks "
                        "every table read from them against the decomp")
    p.add_argument("--check", action="store_true", help="only check the committed snapshot, don't write it")

    args = parser.parse_args(argv)

    if args.command == "snapshot":
        return _snapshot(args)

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



def _snapshot(args) -> int:
    import json
    sys.stdout.reconfigure(errors="backslashreplace")
    import tempfile
    from . import disc
    with tempfile.TemporaryDirectory() as work:
        rec = disc.record_groups(args.input, Path(work))
    if not (args.disc / disc.BINARY_FILES["main"]).is_file():
        print(f"no US binaries in {args.disc} (--disc): the snapshot needs them for pointers and hashes")
        return 1
    disc_root = args.disc
    snap, problems = disc.build_snapshot(rec, disc_root)
    if args.check:
        committed = json.loads(disc.SNAPSHOT.read_text(encoding="utf-8"))
        if committed != json.loads(json.dumps(snap)):
            problems.append(f"{disc.SNAPSHOT.name} differs from the decomp (run python -m dwdata snapshot)")
    index = disc.DiscIndex(disc_root, json.loads(json.dumps(snap)))
    problems += disc.check(rec, index)
    problems += disc.check_text(rec, disc.DiscText(index))
    if not args.check and not problems:
        disc.write_snapshot(snap)
    n_strings = sum(len(items) for blocks in snap["strings"].values() for items in blocks.values())
    print(f"snapshot: {len(snap['tables'])} tables, {len(snap['structs'])} structs, {len(snap['pointers'])} pointer "
          f"targets, {n_strings} strings, {len(snap['binaries'])} binaries; {len(problems)} problems"
          + ("" if args.check or problems else f" -> {disc.SNAPSHOT}"))
    for p in problems:
        print("  " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
