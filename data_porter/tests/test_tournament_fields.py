"""Step 4e-3, step 1 (specs/tournament_entry.md §5.1a): the tournament fields of systems/tournaments
and systems/tournament_medals. Acceptance checks written from the C by the reviewer; don't change
them to make the code pass. Step 1 is built: the tests always run (DW_STEP_4E_3=0 skips them)."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import systems
from dwdata.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4E_3", "6") or 6)


def _ids(values):
    """A reference list as ids (references are {"id", "name"}; plain ids are accepted too)."""
    return [v["id"] if isinstance(v, dict) else v for v in values]


@unittest.skipUnless(STEP >= 1, "PENDING (DW_STEP_4E_3 < 1)")
@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "utils2.c").is_file(), "dw_decomp not available")
class TournamentFieldsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = systems.convert(DEFAULT_INPUT, Path(cls.tmp.name))

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def load(self, name):
        return json.loads((Path(self.tmp.name) / "systems" / f"{name}.json").read_text(encoding="utf-8"))

    def test_checks_pass(self):
        self.assertTrue(self.out.ok, [f"{c.name}: {c.detail}" for c in self.out.checks if not c.passed])

    def test_won_trigger(self):
        # utils2.c:674 setTrigger(id + 15); TRIGGER_D_RANK_CUP_WON = 15 (trigger.h:805).
        records = self.load("tournaments")["records"]
        self.assertEqual(len(records), 23)
        self.assertEqual([r["won_trigger"] for r in records], [r["id"] + 15 for r in records])
        self.assertEqual(records[3]["won_trigger"], 18)  # TRIGGER_GRADE_A_CUP_WON (trigger.h:808)

    def test_rounds_to_win(self):
        # utils2.c:666-669: expected = 3, or 2 for id 5 (Grade R).
        records = self.load("tournaments")["records"]
        self.assertEqual([r["rounds_to_win"] for r in records], [2 if r["id"] == 5 else 3 for r in records])

    def test_open_pool(self):
        # utils2.c:603: only cup 0x16 takes its list without the roster triggers.
        records = self.load("tournaments")["records"]
        self.assertEqual([r["id"] for r in records if r["open_pool"]], [0x16])
        self.assertTrue(all(r["open_pool"] in (True, False) for r in records))

    def test_registered_by_builtin_0x21(self):
        # script_interp.c:1810: writePStat(3, 0x16).
        records = self.load("tournaments")["records"]
        self.assertEqual([r["id"] for r in records if r["registered_by_builtin_0x21"]], [0x16])

    def test_medal_cups(self):
        # tournament.c:173-209: triggers 15 + 0..5, 21 + 0..4, 26 + 0..6, 33 + 0..3 (id = trigger - 15).
        records = {r["condition"]: r for r in self.load("tournament_medals")["records"]}
        self.assertEqual(sorted(records), [0, 1, 2, 3, 4, 5])
        self.assertEqual(_ids(records[0]["cups"]), list(range(0, 6)))
        self.assertEqual(_ids(records[1]["cups"]), list(range(6, 11)))
        self.assertEqual(_ids(records[2]["cups"]), list(range(11, 18)))
        self.assertEqual(_ids(records[3]["cups"]), list(range(18, 22)))
        self.assertNotIn("cups", records[4])
        self.assertNotIn("cups", records[5])

    def test_medal_wins_and_cards(self):
        # tournament.c:213 (TOURNAMENT_WINS >= 100); :218-225 (cards 0..0x41, TRIGGER_BEATEN_GAME_ONCE = 50).
        records = {r["condition"]: r for r in self.load("tournament_medals")["records"]}
        self.assertEqual(records[4]["min_wins"], 100)
        self.assertTrue(records[5]["all_cards"])
        self.assertEqual(records[5]["trigger"], 50)
        for c in (0, 1, 2, 3):
            self.assertNotIn("min_wins", records[c])
            self.assertFalse(records[c].get("all_cards", False))

    def test_medal_ids_unchanged(self):
        # TOURNAMENT_MEDAL_IDS (tournament.c:37-39).
        records = sorted(self.load("tournament_medals")["records"], key=lambda r: r["condition"])
        self.assertEqual([r["medal"]["id"] for r in records], [0, 1, 2, 3, 4, 0xC])


if __name__ == "__main__":
    unittest.main()
