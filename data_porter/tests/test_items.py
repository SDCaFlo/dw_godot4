import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import items
from dwdata.paths import DEFAULT_INPUT


class ItemsConvertTests(unittest.TestCase):
    def test_missing_decomp_fails_cleanly(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = items.convert(Path(tmp) / "nothing", Path(tmp) / "out")
            self.assertEqual([c.name for c in out.checks if not c.passed], ["decomp found"])


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "item.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = items.convert(DEFAULT_INPUT, Path(cls.tmp.name))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, name):
        return json.loads((Path(self.tmp.name) / "items" / f"{name}.json").read_text(encoding="utf-8"))["records"]

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_meat(self):
        meat = self.load("item_data")[38]
        self.assertEqual(meat["name"]["text"]["en_us"], "Meat")
        self.assertEqual(meat["description"]["text"]["en_us"], "Makes Digimon a bit full")
        self.assertEqual((meat["price"], meat["sell_price"], meat["usable"]["name"]), (50, 25, "field"))
        self.assertEqual(meat["handler"], "handleFood")
        effects = {e["item"]["id"]: e for e in self.load("item_effects")}
        self.assertEqual(effects[38]["values"], {"energy": 12, "weight": 1})
        self.assertEqual(effects[0]["values"], {"heal": 500, "effect_variant": 0})
        self.assertEqual(effects[41]["train_boost"], {"stats": ["off", "brain", "mp"], "factor_percent": 120,
                                                      "frames": 7200})
        self.assertIn("passive", effects[0x21])
        items = self.load("item_data")
        self.assertEqual(items[0x22]["passive"], "sleep_boost")      # Rest Pillow (sleepRegen)
        self.assertEqual(effects[0x22]["passive"]["property"], "sleep_boost")
        # the feeding ranges of partnerWillRefuseItem / partnerHandleFoodFeed (../specs/inventory.md §2.9)
        self.assertEqual(items[0x00]["feeding"], "obedience")      # Sm. recovery
        self.assertEqual(items[0x22]["feeding"], "refused")        # Rest pillow (passive)
        self.assertEqual(items[0x26]["feeding"], "food")           # Meat
        self.assertEqual(items[0x7A]["feeding"], "food")           # Steak
        self.assertEqual(items[0x73]["feeding"], "refused")        # key item
        self.assertEqual(items[0x47]["feeding"], "evolution")
        self.assertEqual(effects[0x7E]["requires_level"], 3)
        self.assertNotIn("passive", meat)
        # the battle branches (../../specs/battle.md §2.18)
        self.assertEqual(effects[8]["battle"], {"cure_status": "shown"})
        self.assertEqual(effects[10]["battle"], {"protect": True})
        self.assertEqual(effects[0x13]["battle"]["buff"], {"offense": {"amount": 50, "capped": True, "icon": 3}})
        self.assertFalse(effects[0x12]["battle"]["buff"]["speed"]["capped"])     # Omni Disk: no cap

    def test_cards_and_shops(self):
        cards = self.load("card_data")
        self.assertEqual(len(cards), 66)
        self.assertEqual(cards[1]["price"], 5000)
        self.assertIsNone(cards[0]["price"])
        shops = self.load("shops")[0]
        self.assertEqual(len(shops["maps"]), 8)
        self.assertEqual(shops["shopkeepers"][-1]["name"], "Betamon")


if __name__ == "__main__":
    unittest.main()
