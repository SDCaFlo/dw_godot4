"""Cross-check with the asset porter's own decomp tables (asset_porter/dwporter/data).

The two porters stay stand-alone (CLAUDE.md "Decisions"); this test only compares them.
"""

import importlib.util
import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import digimon, moves
from dwdata.paths import DEFAULT_INPUT, PORTER_ROOT

ASSET_DATA = PORTER_ROOT.parent / "asset_porter" / "dwporter" / "data"


def _module(name):
    spec = importlib.util.spec_from_file_location(f"asset_porter_data_{name}", ASSET_DATA / f"{name}.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


@unittest.skipUnless((DEFAULT_INPUT / "src").is_dir() and ASSET_DATA.is_dir(),
                     "dw_decomp or asset_porter not available")
class CrossAssetPorterTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        out = Path(cls.tmp.name)
        digimon.convert(DEFAULT_INPUT, out)
        moves.convert(DEFAULT_INPUT, out)
        cls.out = out

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, table):
        return json.loads((self.out / f"{table}.json").read_text(encoding="utf-8"))["records"]

    def test_digimon_names_and_files(self):
        theirs = _module("digimon").DIGIMON_TYPES
        data, files = self.load("digimon/digimon_data"), self.load("digimon/file_names")
        ours = [(f["file_name"], d["name"]["string_id"], d["name"]["text"]["en_us"]) for d, f in zip(data, files)]
        self.assertEqual(ours, [tuple(t[:3]) for t in theirs])

    def test_bones_and_size(self):
        theirs = _module("skeletons").TYPE_PARAMS
        ours = [(d["bone_count"], d["radius"], d["height"]) for d in self.load("digimon/digimon_data")]
        self.assertEqual(ours, [tuple(t[1:4]) for t in theirs])

    def test_move_names(self):
        theirs = _module("moves").MOVE_NAMES
        ours = [m["name"]["text"]["en_us"] if m["name"] else None for m in self.load("moves/move_data")]
        self.assertEqual(ours[:len(theirs)], list(theirs))


EXE = PORTER_ROOT.parent.parent / "external-resources" / "game_dumped_files" / "SLUS_010.32"


@unittest.skipUnless((DEFAULT_INPUT / "src").is_dir() and EXE.is_file() and ASSET_DATA.is_dir(),
                     "dw_decomp, the dumped executable or asset_porter not available")
class CrossExecutableTests(unittest.TestCase):
    """The data porter reads C source; the asset porter reads the same tables from the US executable."""

    def test_maps_and_toilets_match_the_executable(self):
        import sys
        sys.path.insert(0, str(ASSET_DATA.parent.parent))
        try:
            from dwporter.families import maps as asset_maps
        finally:
            sys.path.pop(0)
        theirs = asset_maps.read_tables(EXE.read_bytes())
        from dwdata.groups import systems
        with tempfile.TemporaryDirectory() as tmp:
            systems.convert(DEFAULT_INPUT, Path(tmp))
            ours = json.loads((Path(tmp) / "systems" / "maps.json").read_text(encoding="utf-8"))["records"]
            toilets = json.loads((Path(tmp) / "systems" / "toilets.json").read_text(encoding="utf-8"))["records"]
        self.assertEqual([(m["file"], m["images_8bpp"], m["images_4bpp"], m["sound_bank"], m["no_time_of_day"],
                           m["wild_digimon"], m["doors_id"], m["c"]["toiletId"], m["c"]["loadingName"]) for m in ours],
                         [(e["filename"], e["num_8bpp"], e["num_4bpp"], e["sound_id"], e["no_time_cycle"],
                           e["has_digimon"], e["doors_id"], e["toilet_id"], e["loading_name"])
                          for e in theirs["entries"]])
        self.assertEqual([(m["name"]["text"]["en_us"] or "").strip() for m in ours],
                         [e["display_name"] for e in theirs["entries"]])
        self.assertEqual([t["walk_to"] + t["camera_to"] for t in toilets], theirs["toilets"])


if __name__ == "__main__":
    unittest.main()
