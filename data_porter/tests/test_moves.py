import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import moves
from dwdata.paths import DEFAULT_INPUT
from tests.test_text import VERSION_H

MOVE_H = """\
#ifndef DW_MOVE_H
#define DW_MOVE_H
#include <dw/types.h>
typedef struct {
	int32_t distance;
	int16_t power;
	uint8_t mpCost;
	uint8_t iframes;
	uint8_t range;
	uint8_t special;
	uint8_t status;
	uint8_t accuracy;
	uint8_t statusChance;
	uint8_t unk3;
	uint8_t unk4;
	uint8_t unk5;
} Move;
#endif
"""

EVIDENCE = """\
void f(void)
{
	if ((tech >= 0x3a) && (tech < 0x71)) {}
	if (tech == 0x2d) {}
	tech = 0x79;
	if (move == 0x2C || move == 0x30) {}
	x = MOVE_DATA[tech].power + MOVE_DATA[tech].mpCost;
}
"""


def move_line(i: int, range_=2) -> str:
    # distance 400^2, power = id, mpCost 10, element id % 7, status 1 with a chance on even ids
    status, chance = (1, 20) if i % 2 == 0 else (0, 0)
    return (f"\t{{ 0x{160000:08x}, {i}, 10, 1, {range_}, {i % 7}, {status}, 100, {chance}, {i % 4}, 0, 0 }},")


def make_decomp(root: Path, bad_range_at=None) -> None:
    (root / "include" / "dw").mkdir(parents=True)
    (root / "include" / "dw" / "version.h").write_text(VERSION_H, encoding="utf-8")
    (root / "include" / "dw" / "move.h").write_text(MOVE_H, encoding="utf-8")
    (root / "config" / "us").mkdir(parents=True)
    (root / "config" / "us" / "main.yaml").write_text(
        "name: main\noptions:\n  src_path: src/main\nsegments:\n      - [0x100, c, item]\n", encoding="utf-8")
    (root / "config" / "us" / "symbols.txt").write_text(
        "MOVE_DATA = 0x8012623C; // size:0x7A0\nTYPE_FACTORS = 0x80125F70; // size:0x31\n"
        "MOVE_LEARN_CHANCES = 0x80125FA4; // size:0xAE\n", encoding="utf-8")
    item = ["#include <dw/move.h>", "#include <text/main/item.h>", "", "MOVE_NAMES_TEXT", "",
            "uint8_t TYPE_FACTORS[7][7] = {"]
    item += ["\t{ " + ", ".join(str([10, 15, 5, 20, 2][(a + d) % 5]) for d in range(7)) + " }," for a in range(7)]
    item += ["};", "", "uint8_t MOVE_LEARN_CHANCES[58][3] = {"]
    item += [f"\t{{ {i}, {i // 2}, 0 }}," for i in range(58)]
    item += ["};", "", "Move MOVE_DATA[122] = {"]
    item += [move_line(i, 7 if i == bad_range_at else 2) for i in range(122)]
    item += ["};", ""]
    (root / "src" / "main").mkdir(parents=True)
    (root / "src" / "main" / "item.c").write_text("\n".join(item), encoding="utf-8")
    (root / "src" / "main" / "utils2.c").write_text(EVIDENCE, encoding="utf-8")
    (root / "src" / "btl").mkdir(parents=True)
    (root / "src" / "btl" / "battle_main.c").write_text(EVIDENCE, encoding="utf-8")
    names = ["MOVE_NAMES:", "  entries:"]
    for i in range(121):
        names += [f"    - name: STR_MOVE_{i}", f"      ja: わざ{i}", f"      en_us: Move {i}"]
    names += ["    - NULL"]
    (root / "text" / "main").mkdir(parents=True)
    (root / "text" / "main" / "item.yaml").write_text("\n".join(names) + "\n", encoding="utf-8")


class MovesConvertTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.decomp, self.output = self.root / "decomp", self.root / "out"

    def tearDown(self):
        self.tmp.cleanup()

    def load(self, name):
        return json.loads((self.output / "moves" / f"{name}.json").read_text(encoding="utf-8"))

    def test_converts_and_passes_checks(self):
        make_decomp(self.decomp)
        out = moves.convert(self.decomp, self.output)
        self.assertEqual([f"{c.name}: {c.detail}" for c in out.checks if not c.passed], [])
        table = self.load("move_data")
        self.assertEqual(list(table)[:6], ["table", "source", "schema", "records", "used_by", "godot"])
        m = table["records"][4]
        self.assertEqual(m["name"]["string_id"], "STR_MOVE_4")
        self.assertEqual((m["power"], m["mp_cost"], m["mp"], m["distance"]), (4, 10, 30, 400))
        self.assertEqual(m["element"], {"id": 4, "name": "ice"})
        self.assertEqual(m["status"], {"id": 1, "name": "poison"})
        self.assertEqual(m["flags"], {"value": 0, "needs_target": False, "shared_cooldown": False})
        self.assertEqual(table["records"][3]["flags"]["value"], 3)
        self.assertEqual([table["records"][i]["category"] for i in (0x39, 0x3a, 0x70, 0x71)],
                         ["technique", "finisher", "finisher", "other"])
        self.assertEqual(table["records"][0x2c]["learned_with"], 0x30)
        self.assertEqual(table["used_by"][0]["fields"], ["mpCost", "power"])
        factors = self.load("type_factors")
        self.assertEqual(factors["records"][0]["against"][1], {"defender": {"id": 1, "name": "battle"},
                                                               "factor": 15, "multiplier": 1.5})
        self.assertEqual(self.load("learn_chances")["records"][9]["chances"], [9, 4, 0])
        self.assertTrue((self.output / "moves" / "report.md").is_file())

    def test_unknown_range_fails(self):
        make_decomp(self.decomp, bad_range_at=5)
        out = moves.convert(self.decomp, self.output)
        failed = {c.name: c.detail for c in out.checks if not c.passed}
        self.assertEqual(list(failed), ["MOVE_DATA: range is a known value"])
        self.assertEqual(failed["MOVE_DATA: range is a known value"], "5: 7")


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "item.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    def test_real_moves(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = moves.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [f"{c.name}: {c.detail}" for c in out.checks if not c.passed])
            table = json.loads((Path(tmp) / "moves" / "move_data.json").read_text(encoding="utf-8"))
            spit_fire = table["records"][2]
            self.assertEqual(spit_fire["name"]["text"]["en_us"], "Spit Fire")
            self.assertEqual((spit_fire["power"], spit_fire["mp"], spit_fire["element"]["name"]), (66, 30, "fire"))
            self.assertEqual(table["records"][30]["release_values"], {"jp": {"unk3": 0}})   # Full Potential
            self.assertEqual(len(table["records"]), 122)


if __name__ == "__main__":
    unittest.main()
