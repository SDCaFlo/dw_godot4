import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import systems
from dwdata.paths import DEFAULT_INPUT


class SystemsConvertTests(unittest.TestCase):
    def test_missing_decomp_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = systems.convert(Path(tmp) / "nothing", Path(tmp) / "out")
            self.assertEqual([c.name for c in out.checks if not c.passed], ["decomp found"])


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "map.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = systems.convert(DEFAULT_INPUT, Path(cls.tmp.name))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, name):
        return json.loads((Path(self.tmp.name) / "systems" / f"{name}.json").read_text(encoding="utf-8"))["records"]

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_battle_tables(self):
        flee = {(r["partner_type"]["name"], r["enemy_type"]["name"]): r["chance"]
                for r in self.load("flee_chances") if "chance" in r}
        self.assertEqual(flee[("virus", "virus")], 30)
        commands = self.load("battle_commands")
        self.assertEqual([(r["commands"], r["arena_commands"]) for r in commands],
                         [(3, 2), (4, 3), (5, 4), (7, 5), (8, 6), (9, 7)])
        # ../../specs/battle.md §2.3, §6
        lists = {r["count"]: r for r in self.load("battle_command_lists")}
        self.assertEqual(lists[5]["commands"], [11, 1, 4, 2, 3])
        self.assertEqual(lists[8]["commands"], [11, 1, 7, 6, 5, 4, 2, 3])
        self.assertEqual((lists[9]["commands"], lists[9]["technique_slots"], lists[9]["after"]),
                         ([11, 1, 7, 6, 5], [[2, 10], [1, 9], [0, 8]], [3]))
        hud = {r["name"]: r["values"] for r in self.load("battle_hud")}
        self.assertEqual(hud["FLEE_BUBBLE_SCALE"][:3], [100, 104, 108])
        self.assertEqual(len(hud["BTL_BATTLE_START_TEXT_POSITIONS"]), 155)
        self.assertEqual(len(self.load("item_throw")), 24)
        math = {r["name"]: r["values"] for r in self.load("psx_math")}
        self.assertEqual((len(math["SIN_LOOKUP_TABLE"]), math["SIN_LOOKUP_TABLE"][128]), (130, 4096))
        self.assertEqual(len(math["ATAN_LOOKUP_TABLE"]), 512)
        maps = self.load("maps")
        self.assertEqual(sum(1 for m in maps if m.get("concave")), 18)
        self.assertEqual([m["id"] for m in maps if m.get("no_battle_drops")], [0x8F])

    def test_world_and_arena(self):
        maps = self.load("maps")
        self.assertEqual(len(maps), 255)
        self.assertEqual(maps[0]["file"], "MAYO01")
        self.assertEqual(maps[0]["toilet"], 0)
        tournaments = self.load("tournaments")
        self.assertEqual(tournaments[0]["name"]["text"]["en_us"], "Grade D")
        self.assertEqual(tournaments[0]["grade_image"], "\\STDDAT\\GRADE\\GRADED.TIM")
        transport = self.load("birdramon_transport")
        self.assertEqual((transport[0]["map"]["id"], transport[0]["cost"]), (38, 1000))
        jukebox = self.load("jukebox")
        self.assertEqual(len(jukebox), 63)
        self.assertEqual((jukebox[0]["font"], jukebox[0]["variant"]), (1, 0))
        self.assertEqual((jukebox[1]["font"], jukebox[1]["variant"]), (1, 1))
        self.assertEqual([r["track"] for r in jukebox if r["unlock_trigger"] is not None], [0x3E])
        spots = self.load("training_spots")
        self.assertEqual([s["stat"] for s in spots[0]["spots"]], ["hp", "offense", "defense", "mp", "speed", "brain"])

    def test_slot_machine(self):
        (slots,) = self.load("slot_machine")
        self.assertEqual([len(r) for r in slots["reels"]], [13, 13, 13])
        self.assertEqual(slots["reels"][0][:7], [1, 2, 3, 4, 5, 6, 7])
        self.assertEqual(slots["assist_draw"], [0, 0, 0, 0, 0, 1, 1, 1, 1, 2])
        self.assertEqual([s.get("stat") for s in slots["symbols"]],
                         ["hp", "mp", "offense", "defense", "speed", "brain", None])
        self.assertTrue(slots["symbols"][6]["jackpot"])
        self.assertEqual({k: (v["payout"], v["sound"]) for k, v in slots["payouts"].items()},
                         {"jackpot": (100, 12), "own_stat": (40, 11), "other_match": (20, 11), "none": (5, 13)})


if __name__ == "__main__":
    unittest.main()
