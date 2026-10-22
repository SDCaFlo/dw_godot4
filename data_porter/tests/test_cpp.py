import unittest

from dwdata.cpp import ConditionTracker, Release, evaluate

RELEASES = {r.name: r for r in (
    Release("jp", 1, 19981224, "NTSCJ"), Release("us", 4, 19990331, "NTSCU"),
    Release("jp_rev1", 5, 19990406, "NTSCJ"), Release("eu", 6, 20010504, "PAL"))}


def ev(expr, name):
    return evaluate(expr, RELEASES[name], RELEASES)


class EvaluateTests(unittest.TestCase):
    def test_version_macros(self):
        self.assertEqual(ev("VERSION_IS(EU)", "eu"), 1)
        self.assertEqual(ev("VERSION_IS(EU)", "us"), 0)
        self.assertEqual(ev("!VERSION_IS(US) && !VERSION_IS(EU)", "jp"), 1)
        self.assertEqual(ev("!VERSION_IS(US) && !VERSION_IS(EU)", "us"), 0)
        self.assertEqual(ev("VERSION_REGION_IS(NTSCJ)", "jp_rev1"), 1)
        self.assertEqual(ev("VERSION_EQUAL_OR_NEWER(US)", "jp_rev1"), 1)
        self.assertEqual(ev("VERSION_EQUAL_OR_NEWER(US)", "jp"), 0)
        self.assertEqual(ev("defined(VERSION_US)", "us"), 1)

    def test_unknown(self):
        self.assertIsNone(ev("defined(__MWERKS__)", "us"))
        self.assertEqual(ev("defined(__MWERKS__) && VERSION_IS(EU)", "us"), 0)
        self.assertEqual(ev("defined(__MWERKS__) || VERSION_IS(US)", "us"), 1)


class TrackerTests(unittest.TestCase):
    def test_if_elif_else(self):
        t = ConditionTracker(RELEASES)
        seen = {}
        for line in ["#if VERSION_IS(US)", "a", "#elif !VERSION_IS(EU)", "b", "#else", "c", "#endif", "d"]:
            if not t.line(line):
                seen[line] = sorted(n for n, v in t.active.items() if v)
        self.assertEqual(seen["a"], ["us"])
        self.assertEqual(seen["b"], ["jp", "jp_rev1"])
        self.assertEqual(seen["c"], ["eu"])
        self.assertEqual(seen["d"], ["eu", "jp", "jp_rev1", "us"])

    def test_nested_unknown(self):
        t = ConditionTracker(RELEASES)
        t.line("#ifdef __MWERKS__")
        t.line("#if VERSION_IS(EU)")
        self.assertEqual(t.active, {"jp": False, "us": False, "jp_rev1": False, "eu": None})


if __name__ == "__main__":
    unittest.main()
