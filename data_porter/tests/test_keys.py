import unittest

from dwdata import tables
from dwdata.output import GroupWriter


def _rec(i, sid=None, **extra):
    return {"id": i, "name": {"string_id": sid, "text": {}} if sid else None, **extra}


class KeyTests(unittest.TestCase):
    """Content keys (specs/content.md §2)."""

    def _keys(self, records, kind="move", base=None):
        out = GroupWriter(".", "test", "", "")
        tables.keys(out, records, kind, base or tables.name_base("STR_MOVE_NAME_"))
        return out, [r["key"] for r in records]

    def test_rule(self):
        records = [_rec(0, "STR_MOVE_NAME_FIRE_TOWER"), _rec(1, "STR_MOVE_NAME_BUBBLE"),
                   _rec(2, "STR_MOVE_NAME_BUBBLE"), _rec(3)]
        out, keys = self._keys(records)
        self.assertEqual(keys, ["dw1:fire_tower", "dw1:bubble_1", "dw1:bubble_2", "dw1:move_3"])
        self.assertTrue(out.ok)

    def test_key_follows_id(self):
        records = [_rec(0, "STR_MOVE_NAME_SPIT_FIRE", power=66)]
        self._keys(records)
        self.assertEqual(list(records[0]), ["id", "key", "name", "power"])

    def test_bad_key_fails(self):
        out, _ = self._keys([_rec(0, "x")], base=lambda r: "Spit Fire")
        self.assertFalse(out.ok)

    def test_custom_base(self):
        records = [{"id": 0, "file": "MAYO01"}, {"id": 1, "file": ""}]
        out, keys = self._keys(records, "map", lambda r: r["file"].lower() or None)
        self.assertEqual(keys, ["dw1:mayo01", "dw1:map_1"])
        self.assertTrue(out.ok)


if __name__ == "__main__":
    unittest.main()
