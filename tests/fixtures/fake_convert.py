"""A stand-in for dw_convert in tests/test_launcher.gd: the same commands, exit codes and output
shape (dw_convert/specs/convert.md), no disc. An image whose name has "bad" fails the check (1),
"problems" converts with a failed check (2)."""

import json
import sys
from pathlib import Path


def main(argv):
    command, image = argv[0], Path(argv[1])
    if command == "identify":
        print("Digimon World, US release (SLUS-01032): every file as expected" if "bad" not in image.name
              else "not the US release")
        return 1 if "bad" in image.name else 0
    out = Path(argv[2])
    print("PROGRESS 0.000 reading " + image.name, flush=True)
    print("a warning on stderr", file=sys.stderr, flush=True)
    if "bad" in image.name:
        print("ERROR the image is not the US release as expected; nothing converted")
        return 1
    (out / "assets").mkdir(parents=True, exist_ok=True)
    (out / "data").mkdir(parents=True, exist_ok=True)
    (out / "data" / "catalog.json").write_text("{}\n", encoding="utf-8")
    (out / "convert.log").write_text("log\n", encoding="utf-8")
    print("assets maps: 3/3 checks passed")
    print("PROGRESS 0.500 assets: maps", flush=True)
    ok = "problems" not in image.name
    (out / "content.json").write_text(json.dumps({"pack": "dw1", "content_format": 1, "ok": ok}), encoding="utf-8")
    print("PROGRESS 1.000 done in 0 s", flush=True)
    return 0 if ok else 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
