"""Step 4g-K, C1 (../../specs/curling.md §4): the systems/curling table. Acceptance checks written from
the C (src/kar/kar.c, src/main/kar.c) by the reviewer; don't change them to make the code pass.
DW_STEP_4G_K=0 skips them (PENDING)."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import systems
from dwdata.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4G_K", "1") or 1)


def _id(v):
    return v["id"] if isinstance(v, dict) else v


@unittest.skipUnless(STEP >= 1, "PENDING (DW_STEP_4G_K < 1)")
@unittest.skipUnless((DEFAULT_INPUT / "src" / "kar" / "kar.c").is_file(), "dw_decomp not available")
class CurlingFieldsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = systems.convert(DEFAULT_INPUT, Path(cls.tmp.name))
        table = json.loads((Path(cls.tmp.name) / "systems" / "curling.json").read_text(encoding="utf-8"))
        cls.table = table
        cls.rec = table["records"][0]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_one_record_with_sources(self):
        self.assertEqual(len(self.table["records"]), 1)
        self.assertTrue(any("kar.c" in str(s) for s in json.dumps(self.table["source"]).split(",")))
        self.assertIn("GameData.curling", json.dumps(self.table.get("godot", {})))

    def test_map_and_pstats(self):
        # src/main/kar.c:10 `if (mapId == 136)`; KAR_start :793 readPStat(0x7a) + 2; KAR_finishMatch :964-969.
        self.assertEqual(self.rec["map"]["key"], "dw1:frzl17")
        self.assertEqual(_id(self.rec["map"]), 136)
        self.assertEqual(self.rec["pstat_opponent"], 0x7A)
        self.assertEqual(self.rec["opponent_slot_base"], 2)
        self.assertEqual(self.rec["pstat_result"], 0x79)

    def test_stone_types(self):
        # MAIN_D_80134A08 {30, 25, 35, 30} (:268); type 3 sticks (KAR_tickStones :847).
        types = self.rec["stone_types"]
        self.assertEqual([t["weight"] for t in types], [30, 25, 35, 30])
        self.assertEqual([t["pegged"] for t in types], [False, False, False, True])
        self.assertEqual(self.rec["type_roll"], [3, 2, 2, 1, 1, 1, 0, 0, 0, 0])  # KAR_D_8005AB8C (:253)

    def test_models(self):
        self.assertEqual(self.rec["row_models"], [2, 1, 0])  # KAR_D_8005AB80 (:251)
        self.assertEqual(self.rec["pegged_models"], [11, 10, 9])  # MAIN_D_80134A4C (:443)

    def test_obstacles(self):
        # KAR_D_8005AB98 {0x2C1, 0xEB, 0xFFFFFF15} (:261, US: VERSION_EQUAL_OR_NEWER(JP_TRIAL)).
        self.assertEqual(self.rec["obstacle_x"], [0x2C1, 0xEB, -0xEB])

    def test_zones(self):
        # KAR_D_8005B438 (:453) {dx, dz, radius}; points MAIN_D_80134A44 {2, 1, -2, 2} (:441);
        # markers KAR_D_8005B450 {start, count} (:462).
        zones = self.rec["zones"]
        self.assertEqual([[z["dx"], z["dz"], z["radius"]] for z in zones],
                         [[0, 0x6B6, 0x91], [0, 0x6B6, 0x177], [-0x190, 0x90E, 0xCD], [0x190, 0x90E, 0xCD]])
        self.assertEqual([z["points"] for z in zones], [2, 1, -2, 2])
        self.assertEqual([[z["marker_start"], z["marker_count"]] for z in zones], [[25, 1], [19, 4], [16, 3], [13, 3]])

    def test_shot_plans(self):
        self.assertEqual(self.rec["shot_plans"], [[1, 0, 2, 3], [3, 2, 0, 1]])  # KAR_D_8005B418 (:446)

    def test_hint_pages(self):
        pages = [0x00, 0x0C, 0x14, 0x18, 0x28, 0x2C, 0x30, 0x34, 0x38, 0x3C]  # :351, :434
        self.assertEqual(self.rec["hints"]["penguinmon"]["pages"], pages)
        self.assertEqual(self.rec["hints"]["metalmamemon"]["pages"], pages)

    def test_hint_lines(self):
        # KAR_D_8005AF58 / KAR_D_8005B318 (:281, :360): 61 entries; every 4th the name; US en_us text.
        peng = self.rec["hints"]["penguinmon"]["lines"]
        metal = self.rec["hints"]["metalmamemon"]["lines"]
        self.assertEqual(len(peng), 61)
        self.assertEqual(len(metal), 61)
        self.assertEqual(peng[0]["string_id"], "KAR_STR_PENGUINMON")
        self.assertEqual(peng[1]["text"]["en_us"], "First of all, please choose")
        self.assertEqual(metal[0]["string_id"], "KAR_STR_METALMAMEMON")
        self.assertIsNone(peng[60])  # NULL terminator (:342)
        self.assertEqual(metal[60]["string_id"], "KAR_METALMAMEMON_LINE_60")  # US (:424)
        self.assertEqual(peng[0x34 + 1]["text"]["en_us"], "Yeah! I won!")  # page 7: the opponent wins
        self.assertEqual(peng[0x38 + 1]["text"]["en_us"], "Awh, I lost. ")  # page 8: the tamer wins

    def test_menu_text(self):
        # MAIN_D_80134A20 = {KAR_D_8005ABB8, NULL} in US (:274).
        self.assertEqual(self.rec["menu"]["text"]["en_us"], "Start GameExplain Game")

    def test_sprites(self):
        s = self.rec["sprites"]

        def box(name):
            v = s[name]
            return [v["x"], v["y"], v["clut_x"], v["clut_y"], v["u"], v["v"], v["w"], v["h"]]
        self.assertEqual(box("stone_cursor"), [-0x96, 0, 0x80, 0x1E6, 0, 0x28, 0x18, 0x18])  # :480
        self.assertEqual(box("score_digit"), [-0x96, 0, 0x10, 0x1E6, 0, 0x28, 0x10, 0x10])  # :495
        self.assertEqual(box("gauge_bar"), [-0x32, -0x32, 0x80, 0x1E6, 0x30, 0x18, 0x10, 0x10])  # :528
        self.assertEqual(box("gauge_frame"), [-0x32, -0x32, 0x70, 0x1E6, 0, 0x18, 0x30, 0x10])  # :542
        self.assertEqual([[p["x"], p["y"], p["clut_x"], p["u"], p["v"], p["w"], p["h"]] for p in s["plates"]],
                         [[-0x8C, -0x5F, 0x90, 0x70, 0x18, 0x20, 0x20], [-0x82, -0x46, 0x70, 0x18, 0x38, 0x30, 0x20],
                          [0x64, -0x5F, 0xA0, 0x90, 0x18, 0x20, 0x20], [0x50, -0x46, 0x80, 0x18, 0x38, 0x30, 0x20]])  # :559
        self.assertEqual(box("plate_metalmamemon"), [0x64, -0x5F, 0xC0, 0x1E6, 0xB0, 0x18, 0x20, 0x20])  # :634
        self.assertEqual(box("ready_prompt"), [-0x34, 0, 0xB0, 0x1E6, 0x68, 0x3E, 0x97, 0x0A])  # :649
        for name in ("stone_cursor", "score_digit", "gauge_bar", "gauge_frame", "plate_metalmamemon", "ready_prompt"):
            self.assertEqual([s[name]["r"], s[name]["g"], s[name]["b"]], [0x80, 0x80, 0x80], name)

    def test_digits(self):
        # KAR_D_8005B4A0 (:510): 0-9 then the minus sign.
        self.assertEqual([[d["u"], d["v"]] for d in self.rec["digits"]],
                         [[0x40, 0x18], [0x50, 0x18], [0x60, 0x18], [0x40, 0x28], [0x50, 0x28], [0x60, 0x28],
                          [0x48, 0x38], [0x58, 0x38], [0x48, 0x48], [0x58, 0x48], [0, 0x40]])

    def test_stack_view(self):
        # KAR_D_8005B580 (:664): GsRVIEW2 {vpx, vpy, vpz, vrx, vry, vrz, rz}; GsSetProjection(0x200) (:911).
        v = self.rec["stack_view"]
        self.assertEqual(v["eye"], [0, 0, -0xCF8])
        self.assertEqual(v["target"], [0, 0, 0])
        self.assertEqual(v["rz"], 0)
        self.assertEqual(v["projection"], 0x200)


if __name__ == "__main__":
    unittest.main()
