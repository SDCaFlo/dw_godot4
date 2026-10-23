import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import evolution
from dwdata.paths import DEFAULT_INPUT


class EvolutionConvertTests(unittest.TestCase):
    def test_missing_decomp_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = evolution.convert(Path(tmp) / "nothing", Path(tmp) / "out")
            self.assertEqual([c.name for c in out.checks if not c.passed], ["decomp found"])


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "evolution.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = evolution.convert(DEFAULT_INPUT, Path(cls.tmp.name))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, name):
        return json.loads((Path(self.tmp.name) / "evolution" / f"{name}.json").read_text(encoding="utf-8"))["records"]

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_greymon_and_agumon(self):
        reqs = self.load("requirements")
        greymon, agumon = reqs[5], reqs[3]
        self.assertEqual(greymon["stat_rule"], "minimum")
        self.assertEqual(greymon["stats"], {"hp": None, "mp": None, "offense": 100, "defense": 100, "speed": 100,
                                            "brain": 100})
        self.assertEqual(greymon["care_mistakes"], {"value": 1, "at_most": True})
        self.assertEqual((greymon["weight"]["value"], greymon["bonus"]["discipline"], greymon["bonus"]["techs"]),
                         (30, 90, 35))
        self.assertEqual(agumon["stat_rule"], "highest")
        self.assertEqual([s for s, v in agumon["stats"].items() if v], ["hp", "mp", "offense"])
        self.assertEqual(agumon["bonus"]["from_digimon"], 2)        # Koromon

    def test_paths_gains_items(self):
        paths = {p["id"]: p for p in self.load("paths")}
        self.assertEqual(paths[3]["to"], [5, 9, 21, 36, 47, 8])      # Agumon -> Greymon, Meramon, ...
        self.assertEqual(paths[59]["ignored_values"], [-2, 0])
        gains = self.load("stat_gains")
        self.assertEqual(gains[11]["applied_as"], "scale")           # Numemon
        self.assertEqual(gains[11]["scale"], 0.8)
        self.assertEqual(gains[5]["gains"]["hp"], 2000)
        items = {t["item"]["id"]: t for t in self.load("item_targets")}
        self.assertEqual(items[0x47]["target"]["name"], "Greymon")
        self.assertFalse(items[0x72]["can_work"])                    # Moon mirror -> WereGarurumon


if __name__ == "__main__":
    unittest.main()
