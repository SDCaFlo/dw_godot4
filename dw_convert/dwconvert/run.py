"""The whole conversion (distribution step D5, ../specs/convert.md): the player's disc image -> the dw1
content pack the game loads (assets from the asset porter, data from the data porter in disc mode).

Progress for the launcher: lines `PROGRESS <0..1> <message>` on stdout; everything is also written to
<output>/convert.log.
"""

import json
import shutil
import sys
import tempfile
import time
import traceback
from pathlib import Path

from . import identify as ident
from . import image

# The shape of the output (../../specs/distribution.md §6): bump it when the game can't read an older
# output any more, so the launcher converts again.
CONTENT_FORMAT = 1
MOVIES = "MOVIE/"

# Share of the progress bar per step (rough durations).
STEPS = (("check", 0.05), ("extract", 0.15), ("assets", 0.70), ("data", 0.10))


def porters():
    """The two porter packages: bundled in the exe, or next to this folder in the source tree."""
    try:
        import dwporter  # noqa: F401
        import dwdata  # noqa: F401
    except ImportError:
        root = Path(__file__).resolve().parent.parent.parent
        for sub in ("asset_porter", "data_porter"):
            if str(root / sub) not in sys.path:
                sys.path.insert(0, str(root / sub))
    from dwporter import __version__ as asset_version
    from dwporter.families import FAMILIES
    from dwdata import __version__ as data_version
    from dwdata import discmode
    return FAMILIES, discmode, asset_version, data_version


class Progress:
    def __init__(self, log_path: Path = None, quiet: bool = False):
        self.log = open(log_path, "w", encoding="utf-8") if log_path else None
        self.quiet = quiet
        self.base, self.span = 0.0, 0.0

    def step(self, name: str):
        start = 0.0
        for n, share in STEPS:
            if n == name:
                self.base, self.span = start, share
                return
            start += share

    def at(self, fraction: float, message: str):
        self.line(f"PROGRESS {self.base + self.span * min(max(fraction, 0.0), 1.0):.3f} {message}")

    def line(self, text: str):
        if not self.quiet:
            print(text, flush=True)
        if self.log:
            self.log.write(text + "\n")
            self.log.flush()

    def close(self):
        if self.log:
            self.log.close()


def run(image_path, output, movies: bool = False, allow_modified: bool = False, keep_files: bool = False,
        work=None, quiet: bool = False, asset_families=None) -> int:
    """0 on success, 1 if the image isn't usable, 2 if a porter check failed (see convert.log).
    asset_families: only these asset porter families (tests); None = all."""
    output = Path(output)
    output.mkdir(parents=True, exist_ok=True)
    p = Progress(output / "convert.log", quiet)
    started = time.time()
    try:
        families, discmode, asset_version, data_version = porters()
        skip = () if movies else (MOVIES,)

        p.step("check")
        p.at(0, f"reading {Path(image_path).name}")
        with image.open_image(image_path) as img:
            report = ident.identify(img, skip)
            p.line(report.message())
            if not report.us or (not report.ok and not allow_modified):
                p.line("ERROR the image is not the US release as expected; nothing converted")
                return 1
            p.at(1, "disc checked")

            p.step("extract")
            disc = Path(work) if work else Path(tempfile.mkdtemp(prefix="dw_disc_"))
            image.extract(img, disc, skip, lambda done, total, path: p.at(done / total, f"extracting {path}"))

        try:
            p.step("assets")
            names = [n for n in (asset_families or families) if movies or n != "movies"]
            failed = []
            for k, name in enumerate(names):
                p.at(k / len(names), f"assets: {name}")
                out = families[name].convert(disc, output / "assets")
                bad = [c for c in out.checks if not c.passed]
                p.line(f"assets {name}: {len(out.checks) - len(bad)}/{len(out.checks)} checks passed")
                failed += [f"assets {name}: {c.name}: {c.detail}" for c in bad]

            p.step("data")
            p.at(0, "data: tables and text from the binaries")
            for out in discmode.convert(disc, output / "data"):
                bad = [c for c in out.checks if not c.passed]
                p.line(f"data {out.group}: {len(out.checks) - len(bad)}/{len(out.checks)} checks passed")
                failed += [f"data {out.group}: {c.name}: {c.detail}" for c in bad]
        finally:
            if not keep_files and not work:
                shutil.rmtree(disc, ignore_errors=True)

        for f in failed:
            p.line(f"FAILED {f}")
        (output / "content.json").write_text(json.dumps({
            "pack": "dw1", "content_format": CONTENT_FORMAT, "release": "us", "boot": report.boot,
            "movies": movies, "modified_files": report.different,
            "porters": {"asset_porter": asset_version, "data_porter": data_version},
            "converted": time.strftime("%Y-%m-%dT%H:%M:%S"), "ok": not failed,
        }, indent=1) + "\n", encoding="utf-8")
        p.at(1, f"done in {time.time() - started:.0f} s" + (f", {len(failed)} checks failed" if failed else ""))
        return 2 if failed else 0
    except Exception as e:   # the launcher shows the message and the log
        p.line(f"ERROR {type(e).__name__}: {e}")
        if p.log:
            traceback.print_exc(file=p.log)
        return 1
    finally:
        p.close()
