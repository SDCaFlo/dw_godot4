"""Distribution step D2 (../specs/distribution.md §2): the asset porter never reads the decomp while it
converts, so players can run it with only their disc. Values the porter takes from the decomp are
committed constants; this dev test checks them against the decomp when it is there (skipped otherwise),
and checks that no porter module reaches into external-resources except the default input folder."""

import re
import unittest
from pathlib import Path

from dwporter.families import scripts
from dwporter.paths import PORTER_ROOT, PROJECT_ROOT

DECOMP = PROJECT_ROOT / "external-resources" / "dw_decomp"


class DecompConstants(unittest.TestCase):

    def test_won_tournament(self):
        """isTournamentEnabled's case 1 (dget.c) reads the trigger of the cup scripts.WON_TOURNAMENT."""
        dget_c = DECOMP / "src" / "dget" / "dget.c"
        trigger_h = DECOMP / "include" / "dw" / "trigger.h"
        if not dget_c.is_file() or not trigger_h.is_file():
            self.skipTest("decomp missing")
        case_1 = re.search(r"case\s+1:\s+return\s+isTriggerSet\((TRIGGER_[A-Z0-9_]+)\);",
                           dget_c.read_text(encoding="utf-8"))
        self.assertIsNotNone(case_1, "case 1 of isTournamentEnabled")
        self.assertEqual(case_1.group(1), "TRIGGER_GRADE_A_CUP_WON")
        trig = re.search(r"#define\s+TRIGGER_GRADE_A_CUP_WON\s+TRIGGER_(\d+)", trigger_h.read_text(encoding="utf-8"))
        self.assertIsNotNone(trig, "TRIGGER_GRADE_A_CUP_WON in trigger.h")
        self.assertEqual(int(trig.group(1)) - 15, scripts.WON_TOURNAMENT)


class NoDecompAtRunTime(unittest.TestCase):

    def test_no_external_resources_reads(self):
        """Only dwporter/paths.py may name the project root or external-resources (DEFAULT_INPUT, the
        developer's dump). Citations such as "dw_decomp/src/..." in strings and comments are fine."""
        offenders = []
        for path in sorted((PORTER_ROOT / "dwporter").rglob("*.py")):
            if path.name == "paths.py" and path.parent.name == "dwporter":
                continue
            for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
                code = line.split("#", 1)[0]
                if "PROJECT_ROOT" in code or "external-resources" in code or "external_resources" in code:
                    offenders.append(f"{path.relative_to(PORTER_ROOT)}:{n}: {line.strip()}")
        self.assertEqual(offenders, [], "\n".join(offenders))


if __name__ == "__main__":
    unittest.main()
