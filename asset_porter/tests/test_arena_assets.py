"""Step 4e-4, step 1 (../specs/arena.md §5.0): what the arena loads from the disc. Acceptance checks
written from the C by the reviewer; don't change them to make the code pass.

- STD_REL.BIN's texture and four models (config/us/std.yaml: 0x0, 0xD20, 0x1D58, 0x2220, 0x2848, up to
  the header at 0x4188) are the same bytes as BTL_REL.BIN's, so the arena uses the btl_rel output; the
  btl_rel family records it as a check.
- The STDDAT files the arena reads (std_setup.c, std_hud.c, std_main.c:1326-1348) are exported with the
  object and TIM counts the C relies on (StdArenaCfg {modelCount {3, 4}, timCount {4, 1}}, std_setup.c:126,
  include/dw/std.h:13; STD_loadVersusSceneModel 4 objects, STD_loadWinLoseModel 8, STD_loadChampionModels 9).

Step 1 is built: the tests always run (DW_STEP_4E_4=0 skips them)."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwporter.families import btl_rel, tim_files, tmd_files
from dwporter.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4E_4", "1") or 1)
STD = DEFAULT_INPUT / "STD_REL.BIN"
BTL = DEFAULT_INPUT / "BTL_REL.BIN"
ASSETS_END = 0x4188
GRADES = ["GRADED", "GRADEC", "GRADEB", "GRADEA", "GRADES", "GRADER", "CAPV1", "CAPV2", "CAPV3", "CAPV4",
          "CAPVO", "FR", "GP", "TW", "CO", "NT", "MT", "DT", "DY", "WI", "AN", "HU", "BT"]  # STD_GRADES (std_setup.c:209)


def _sidecars(out_dir, prefix):
    return sorted(p for p in out_dir.glob(prefix + "*.json"))


@unittest.skipUnless(STEP >= 1, "PENDING (DW_STEP_4E_4 < 1)")
@unittest.skipUnless(STD.is_file() and BTL.is_file(), "game dump not available")
class ArenaAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        root = Path(cls.tmp.name)
        cls.btl = btl_rel.convert(DEFAULT_INPUT, root)
        cls.tmd = tmd_files.convert(DEFAULT_INPUT, root)
        cls.tim = tim_files.convert(DEFAULT_INPUT, root)
        cls.root = root

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_std_rel_assets_equal_btl_rel(self):
        s = STD.read_bytes()
        b = BTL.read_bytes()
        self.assertEqual(s[:ASSETS_END], b[:ASSETS_END])
        names = [c.name for c in self.btl.checks]
        hit = [c for c in self.btl.checks if "STD_REL" in c.name]
        self.assertTrue(hit, names)
        self.assertTrue(all(c.passed for c in hit), [(c.name, c.detail) for c in hit])

    def objects(self, name):
        side = json.loads((self.root / "tmd_files" / "STDDAT" / f"{name}.json").read_text(encoding="utf-8"))
        return len(side["tmd"]["objects"])

    def test_arena_models(self):
        self.assertEqual(self.objects("T_TOGI"), 3)
        self.assertEqual(self.objects("B_TOGI"), 4)

    def test_scene_models(self):
        self.assertEqual(self.objects("DRAW"), 4)
        self.assertEqual(self.objects("WIN_LOSE"), 8)
        self.assertEqual(self.objects("CHAMP"), 9)
        self.assertGreaterEqual(self.objects("T_DAI"), 1)
        self.assertGreaterEqual(self.objects("B_DAI"), 1)

    def test_arena_textures(self):
        out = self.root / "tim_files" / "STDDAT"
        self.assertEqual(len(_sidecars(out, "T_TOGI")), 4)
        self.assertEqual(len(_sidecars(out, "B_TOGI")), 1)
        self.assertTrue((out / "TIME.json").is_file())
        for g in GRADES:
            self.assertTrue((out / "GRADE" / f"{g}.json").is_file(), g)

    def test_checks_pass(self):
        for o in (self.btl, self.tmd, self.tim):
            self.assertTrue(o.ok, [f"{c.name}: {c.detail}" for c in o.checks if not c.passed])


if __name__ == "__main__":
    unittest.main()
