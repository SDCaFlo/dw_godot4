"""The whole conversion (specs/convert.md, distribution step D5), with the developer's image (skipped without
it): a run with two asset families and every data group, its output against the porters run on
game_dumped_files/. DW_RUN_FULL=1 also runs every asset family (about 25 minutes).
    python -m unittest discover -s tests -t .
"""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwconvert.__main__ import DEFAULT_DUMP
from dwconvert.run import CONTENT_FORMAT, porters, run

from tests.test_image import REAL

FAMILIES = ["card_all", "atr_files"]


@unittest.skipUnless(REAL.is_file() and DEFAULT_DUMP.is_dir(), "needs the US image and game_dumped_files")
class Run(unittest.TestCase):

    def _tree(self, root: Path) -> dict:
        return {p.relative_to(root).as_posix(): p.read_bytes() for p in root.rglob("*") if p.is_file()}

    def test_run(self):
        full = os.environ.get("DW_RUN_FULL") == "1"
        families, discmode, _, _ = porters()
        with tempfile.TemporaryDirectory() as out, tempfile.TemporaryDirectory() as ref:
            out, ref = Path(out), Path(ref)
            code = run(REAL, out, quiet=True, asset_families=None if full else FAMILIES)
            self.assertEqual(code, 0, (out / "convert.log").read_text(encoding="utf-8")[-2000:])
            content = json.loads((out / "content.json").read_text(encoding="utf-8"))
            self.assertEqual((content["content_format"], content["release"], content["ok"]), (CONTENT_FORMAT, "us", True))
            log = (out / "convert.log").read_text(encoding="utf-8")
            self.assertIn("PROGRESS 1.000", log)
            # The same porters on our dump give the same output.
            for name in (list(families) if full else FAMILIES):
                if name != "movies":
                    families[name].convert(DEFAULT_DUMP, ref / "assets")
            discmode.convert(DEFAULT_DUMP, ref / "data")
            got, want = self._tree(out / "assets"), self._tree(ref / "assets")
            # music/index.json records each track's render time (wall clock)
            diff = [k for k in want if got.get(k) != want[k] and k != "music/index.json"]
            self.assertEqual((sorted(set(want) - set(got))[:5], diff[:5]), ([], []))
            self.assertEqual(self._tree(out / "data"), self._tree(ref / "data"))


if __name__ == "__main__":
    unittest.main()
