import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import digimon
from dwdata.paths import DEFAULT_INPUT


class DigimonConvertTests(unittest.TestCase):
    def test_missing_decomp_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = digimon.convert(Path(tmp) / "nothing", Path(tmp) / "out")
            self.assertEqual([c.name for c in out.checks if not c.passed], ["decomp found"])


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "main.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = digimon.convert(DEFAULT_INPUT, Path(cls.tmp.name))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, name):
        return json.loads((Path(self.tmp.name) / "digimon" / f"{name}.json").read_text(encoding="utf-8"))

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_agumon(self):
        agumon = self.load("digimon_data")["records"][3]
        self.assertEqual(agumon["name"]["text"]["en_us"], "Agumon")
        self.assertEqual((agumon["level"]["name"], agumon["type"]["name"]), ("rookie", "vaccine"))
        self.assertEqual([e["name"] for e in agumon["elements"]], ["fire", "none", "battle"])
        self.assertEqual(agumon["moves"][0], {"slot": 0, "anim": 0x2E, "move": {"id": 2, "name": "Spit Fire"}})
        self.assertEqual(agumon["c"]["name"], "STR_DIGIMON_NAME_AGUMON")
        raise_ = self.load("raise_data")["records"][3]
        self.assertEqual(raise_["favorite_food"], {"id": 38, "name": "Meat"})
        self.assertEqual(raise_["hunger_hours"], [1, 5, 9, 13, 17, 21])
        # care properties from the literal ids of partner_impl.c (specs/care.md §4)
        self.assertEqual(raise_["first_technique"], {"slot": 0, "anim": 0x2E, "move": {"id": 2, "name": "Spit Fire"}})
        rows = self.load("raise_data")["records"]
        self.assertEqual(rows[0x11]["first_technique"]["slot"], 2)
        self.assertEqual(rows[0x11]["first_technique"]["move"]["id"], 0x2B)
        self.assertIsNone(rows[1]["first_technique"])
        self.assertEqual([r["id"] for r in rows if r["eats_poop"]], [0xB, 0x27])
        self.assertEqual([r["id"] for r in rows if not r["raises_virus_bar"]], [0x27])
        # the praise's low pat: below Champion, and Mamemon, MetalMamemon, Digitamamon
        low = [r["id"] for r in rows if r["praise_pat_low"]]
        self.assertIn(3, low)                          # Agumon, Rookie
        self.assertNotIn(5, low)                       # Greymon, Champion
        self.assertTrue({0xD, 0x1B, 0x38} <= set(low))
        self.assertEqual(self.load("file_names")["records"][3]["mmd"], "CHDAT/MMD0/AGUM.MMD")

    def test_battle_properties(self):
        # ../../specs/battle.md §6: from the literal ids of loadBattleData, BTL_resetFlatten, entityGetTechFromAnim
        records = self.load("digimon_data")["records"]
        self.assertEqual(records[3]["battle_music"], 1)              # a partner Digimon: the default
        self.assertEqual(records[0x73]["battle_music"], 3)
        self.assertIn(records[0x43]["battle_music"], (1, 2))         # ENEMY_MUSIC_MAPPING[0]
        self.assertEqual([r["id"] for r in records if r["battle_scale"] != 0x1000], [0x71])
        self.assertEqual(records[0x71]["battle_scale"], 0x1800)
        self.assertEqual([(r["id"], r["anim_technique"]) for r in records if "anim_technique" in r],
                         [(0x3C, {"60": 0x70})])

    def test_release_differences_and_placeholders(self):
        records = self.load("digimon_data")["records"]
        self.assertEqual(records[111]["release_values"], {"jp": {"dropItem": 4, "dropChance": 10}})
        self.assertTrue(records[0]["no_technique_list"])
        self.assertEqual(records[0]["moves"], [])
        sounds = self.load("sound_ids")["records"]
        self.assertIsNone(sounds[0]["vlall"])          # only ids 1-65 read the voice bank
        self.assertIsNotNone(sounds[3]["vlall"])


if __name__ == "__main__":
    unittest.main()
