"""Step 4e-3, step 2 (../specs/tournament_entry.md §5.1b): scripts/tournament_cups.json, the arena's cup
data (sections 0x0A / 0x0B of script 168) as a table. Acceptance checks written from the C
(getCupDataJumpTable / getCupDataJumpTableEntry, tournament.c:146-166; isTournamentEnabled,
dget.c:350) by the reviewer; don't change them to make the code pass.

The expected values come from an independent reading of DG.SCN's bytes here (the DG table, then
the jump tables as the C reads them) and a few values checked by hand on 2026-11-01. Step 2 is
built: the tests always run (DW_STEP_4E_3=0 skips them)."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwporter.families import scripts
from dwporter.formats import scn
from dwporter.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4E_3", "6") or 6)
DG = DEFAULT_INPUT / "SCN" / "DG.SCN"
CUPS = 23
ARENA_SCRIPT = 168
COPIES = (213, 102, 209)


def _u16(b, o):
    return b[o] | b[o + 1] << 8


def _section(b, section_id):
    """getScriptSection: the section table starts at byte 2, entries (id, offset), 0xFFFF ends it."""
    at = 2
    while True:
        sid = _u16(b, at)
        if sid == 0xFFFF:
            return None
        if sid == section_id:
            return _u16(b, at + 2)
        at += 4


def _list(b, entry):
    """A DATA list read from entry + 2 up to the first byte >= 0xFE (dget.c:337, :371)."""
    out, o = [], entry + 2
    while b[o] < 0xFE:
        out.append(b[o])
        o += 1
    return out


def _read_cups(b):
    """The 23 cups as the C reads them: section 0x0A -> the cup's table -> its five entries."""
    s = _section(b, 0x0A)
    cups = []
    for cup in range(CUPS):
        table = _u16(b, s + cup * 4 + 2)
        entries = [_u16(b, table + k * 4 + 2) for k in range(5)]
        cups.append({
            "table": table,
            "entries": entries,
            "c_values": list(b[entries[1] + 2:entries[1] + 5]),
            "overleveled": _list(b, entries[2]),
            "eligible": _list(b, entries[3]),
            "opponents": None if b[entries[4] + 2] >= 0xFE else _list(b, entries[4]),
        })
    return cups, _list(b, _section(b, 0x0B))


@unittest.skipUnless(STEP >= 2, "PENDING (DW_STEP_4E_3 < 2)")
@unittest.skipUnless(DG.is_file(), "game dump not available")
class TournamentCupsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.out = scripts.convert(DEFAULT_INPUT, Path(cls.tmp.name))
        path = Path(cls.tmp.name) / "scripts" / "tournament_cups.json"
        cls.table = json.loads(path.read_text(encoding="utf-8"))
        cls.records = cls.table["records"]
        dg = DG.read_bytes()
        offsets = {sid: (off, size) for sid, off, size in scn.parse_dg_table(dg)["scripts"]}
        cls.script = {sid: dg[offsets[sid][0]:offsets[sid][0] + offsets[sid][1]]
                      for sid in (ARENA_SCRIPT,) + COPIES}

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_checks_pass(self):
        failed = [c for c in self.out.checks if not c.passed] if hasattr(self.out, "checks") else []
        self.assertFalse(failed, [getattr(c, "name", c) for c in failed])

    def test_one_record_per_cup(self):
        self.assertEqual([r["id"] for r in self.records], list(range(CUPS)))

    def test_matches_the_c_reading(self):
        cups, _ = _read_cups(self.script[ARENA_SCRIPT])
        for r, c in zip(self.records, cups):
            self.assertEqual(r["requirement"]["c_values"], c["c_values"], f"cup {r['id']} requirement")
            self.assertEqual(r["requirement"]["min_roster"], c["c_values"][0], f"cup {r['id']} min_roster")
            self.assertEqual(r["overleveled"], c["overleveled"], f"cup {r['id']} overleveled")
            self.assertEqual(r["eligible"], c["eligible"], f"cup {r['id']} eligible")
            self.assertEqual(r["opponents"], c["opponents"], f"cup {r['id']} opponents")
            self.assertEqual(r["source"]["script"], ARENA_SCRIPT)
            self.assertEqual(r["source"]["cup_table"], c["table"])
            self.assertEqual(r["source"]["entries"], c["entries"])
            self.assertEqual(r["info"]["offset"], c["entries"][0])

    def test_copies_are_equal(self):
        # The C reads ACTIVE_MAP_SCRIPT's copy; the table is only valid while all copies agree.
        base, base_b = _read_cups(self.script[ARENA_SCRIPT])
        for sid in COPIES:
            cups, b_list = _read_cups(self.script[sid])
            strip = lambda cs: [{k: v for k, v in c.items() if k not in ("table", "entries")} for c in cs]
            self.assertEqual(strip(cups), strip(base), f"script {sid}")
            self.assertEqual(b_list, base_b, f"script {sid} section 0x0B")

    def test_requirement_kinds(self):
        # isTournamentEnabled's switch (dget.c:388-421); case 1 = TRIGGER_GRADE_A_CUP_WON (18 = 15 + 3).
        _, b_list = _read_cups(self.script[ARENA_SCRIPT])
        for r in self.records:
            n, m, kind = r["requirement"]["c_values"]
            also = r["requirement"]["also"]
            if kind == 0:
                self.assertEqual(also, {"type": "none"}, f"cup {r['id']}")
            elif kind == 1:
                self.assertEqual(also, {"type": "won", "tournament": 3}, f"cup {r['id']}")
            elif kind == 2:
                self.assertEqual(also, {"type": "count", "list": b_list, "min": m}, f"cup {r['id']}")
            else:
                self.assertEqual(also, {"type": "count_until", "until": kind, "min": m}, f"cup {r['id']}")

    def test_hand_checked_values(self):
        by_id = {r["id"]: r for r in self.records}
        self.assertEqual(by_id[0]["requirement"]["c_values"], [0, 0, 0])      # Grade D
        self.assertEqual(by_id[2]["requirement"]["c_values"], [24, 0, 0])     # Grade B
        self.assertEqual(by_id[3]["requirement"]["also"]["type"], "count")    # Grade A [8, 4, 2]
        self.assertEqual(by_id[3]["requirement"]["also"]["list"][:3], [12, 13, 14])
        self.assertEqual(by_id[4]["requirement"]["also"], {"type": "won", "tournament": 3})  # Grade S
        self.assertIsNone(by_id[5]["opponents"])                               # Grade R: the whole roster
        self.assertEqual(by_id[11]["requirement"]["also"], {"type": "count_until", "until": 56, "min": 4})
        self.assertEqual(by_id[18]["opponents"][:4], [3, 4, 8, 5])            # Dino Cup, unsorted
        self.assertEqual(by_id[0]["eligible"][:3], [3, 4, 5])
        self.assertIn(12, by_id[0]["overleveled"])                            # MetalGreymon too strong for D
        self.assertEqual(by_id[22]["opponents"][:4], [67, 74, 102, 111])      # Beetle Cup
        self.assertEqual(by_id[0]["info"]["offset"], 3342)
        self.assertEqual(by_id[0]["source"]["cup_table"], 3322)

    def test_info(self):
        b = self.script[ARENA_SCRIPT]
        cups, _ = _read_cups(b)
        for r, c in zip(self.records, cups):
            raw = bytes.fromhex(r["info"]["raw"])
            self.assertEqual(raw[0], 0x1A, f"cup {r['id']}: SHOW_TEXTBOX")
            self.assertEqual(raw, b[c["entries"][0]:c["entries"][0] + len(raw)], f"cup {r['id']}: raw bytes")
        by_id = {r["id"]: r for r in self.records}
        self.assertTrue(by_id[0]["info"]["text"].startswith("- Grade D -"))
        # Cup 0x16 shares the Humanoid Cup's info (both entries point at the same text).
        self.assertEqual(by_id[22]["info"], by_id[21]["info"])

    def test_list_ids_in_roster_range(self):
        for r in self.records:
            for name in ("overleveled", "eligible", "opponents"):
                self.assertTrue(all(0 <= v < 0x70 for v in (r[name] or [])), f"cup {r['id']} {name}")


if __name__ == "__main__":
    unittest.main()
