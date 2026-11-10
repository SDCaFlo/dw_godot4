"""Disc mode, steps D3a and D3b (specs/from_disc.md §3, §5): the snapshot, DiscIndex and DiscText.

- The reader on synthetic bytes: struct alignment, unions, text, numbers, pointers, slot overrides.
- The committed snapshot holds no values: only layouts, addresses, identifiers and hashes.
- With the developer's disc: DiscIndex reads every table from the binaries and the snapshot alone.
- With the decomp and the disc: the snapshot is up to date, and every table read from the binaries
  equals the decomp's US value (the equivalence check of §1).
"""

import json
import re
import tempfile
import unittest
from pathlib import Path

from dwdata import disc, paths
from dwdata.cdata import Array, Field, Pointer, Scalar, Struct
from dwdata.decomp import Decomp

U8, S16, U16, S32 = Scalar("uint8_t", 1, False), Scalar("int16_t", 2, True), Scalar("uint16_t", 2, False), \
    Scalar("int32_t", 4, True)
CHAR = Scalar("char", 1, True)
HAVE_DISC = (paths.DEFAULT_DISC / "SLUS_010.32").is_file()
HAVE_DECOMP = Decomp(paths.DEFAULT_INPUT).exists()


def _snapshot() -> dict:
    return json.loads(disc.SNAPSHOT.read_text(encoding="utf-8"))


class Reader(unittest.TestCase):

    def test_struct_layout(self):
        """Fields aligned to their size (MIPS), as cdata.sizeof lays them out."""
        st = Struct("S", [Field("a", U8), Field("b", S16), Field("c", U8), Field("d", S32)])
        data = bytes([7, 0, 0xFE, 0xFF, 9, 0, 0, 0, 1, 0, 0, 0])
        self.assertEqual(disc._Reader(data, 0, {}).value(st, 0), {"a": 7, "b": -2, "c": 9, "d": 1})

    def test_union_first_field(self):
        st = Struct("U", [Field("x", U16), Field("y", S32)], union=True)
        self.assertEqual(disc._Reader(bytes([1, 2, 3, 4]), 0, {}).value(st, 0), {"x": 0x201})

    def test_text_and_numbers(self):
        """char arrays are text up to the first NUL (Shift-JIS); uint8_t arrays are numbers."""
        data = b"Hi\0\0" + bytes([1, 2, 3])
        r = disc._Reader(data, 0, {})
        self.assertEqual(r.value(Array(CHAR, 4), 0), "Hi")
        self.assertEqual(r.value(Array(U8, 3), 4), [1, 2, 3])
        self.assertEqual(disc._Reader("ＡＢ".encode("shift_jis") + b"\0", 0, {}).value(Array(CHAR, 5), 0), "ＡＢ")

    def test_pointers_and_slots(self):
        data = (0x80010000).to_bytes(4, "little") * 2 + bytes(4) + b"Agumon\0\0"
        ty = Struct("P", [Field("p", Array(Pointer("char"), 3)), Field("name", Array(CHAR, 8))])
        slots = {".p[1]": {"pointer": ["0x80010000", "LINE_B"]}, ".name": {"text_id": "STR_NAME_AGUMON"}}
        r = disc._Reader(data, 0, {"0x80010000": "LINE_A"}, slots)
        self.assertEqual(r.value(ty, 0), {"p": ["LINE_A", "LINE_B", None], "name": "STR_NAME_AGUMON"})
        self.assertEqual(r.texts, {".name": "Agumon"})
        self.assertEqual(r.unknown_pointers, [])
        r = disc._Reader((0x80020000).to_bytes(4, "little"), 0, {})
        self.assertEqual(r.value(Pointer("char"), 0), "0x80020000")
        self.assertEqual(r.unknown_pointers, ["0x80020000"])

    def test_type_round_trip(self):
        inner = Struct(None, [Field("u", S16), Field("v", S16)], file="include/x.h", line=3)
        other = Struct(None, [Field("dx", S16)], file="include/x.h", line=9)
        ty = Struct("T", [Field("a", Array(inner, 2)), Field("b", other), Field("c", Pointer("char"))])
        structs = {}
        js = disc.type_to_json(ty, structs)
        structs.pop("\0ids")
        self.assertEqual(len(structs), 3, "two anonymous structs kept apart")
        back = disc.type_from_json(json.loads(json.dumps(js)), json.loads(json.dumps(structs)))
        data = bytes([1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 0, 0]) + (0).to_bytes(4, "little")
        self.assertEqual(disc._Reader(data, 0, {}).value(back, 0),
                         {"a": [{"u": 1, "v": 2}, {"u": 3, "v": 4}], "b": {"dx": 5}, "c": None})

    def test_encode(self):
        st = Struct("S", [Field("a", U8), Field("b", S16)])
        self.assertEqual(disc.encode(Array(st, 2), [{"a": 1, "b": -1}, {"a": 2, "b": 3}]),
                         bytes([1, 0, 0xFF, 0xFF, 2, 0, 3, 0]))


# Every string in the snapshot is one of these: never a game value.
IDENT = r"[A-Za-z_][A-Za-z0-9_]*"
ALLOWED_STRING = re.compile("|".join([
    IDENT,                                                    # symbol, field, struct, string id names
    r"0x[0-9A-F]{8}",                                         # addresses
    r"[0-9a-f]{40}",                                          # sha1 of the US binaries
    r"[A-Z0-9_]+\.(BIN|32)",                                  # binary file names
    r"(src|include)/[\w/]+\.[ch]",                            # decomp file paths
    r"(src|include)/[\w/]+\.[ch]:" + IDENT,                   # table keys
    IDENT + r"(#\d+)?",                                       # struct keys
    r"PSY-Q SDK",                                             # where the SDK's structs come from
    r"(unsigned |signed )?" + IDENT + r"( \*)*",              # C type names (pointer targets)
    r"symbol|search|absent|pointer|array|row|copy|slot|empty",   # how a table or string was located
    r"[a-z0-9_]+/[a-z0-9_]+",                                 # text table names (main/item)
    r"#\d+",                                                 # entry keys of a text block
    r"(\[\d+\]|\.\w+)+",                                     # paths inside a table ([0].name)
    r"python -m dwdata snapshot",
]))


class SnapshotHoldsNoValues(unittest.TestCase):

    def test_strings(self):
        """Only identifiers, addresses, paths and hashes; the reasons in ABSENT are code comments."""
        bad = []

        def walk(v, where):
            if isinstance(v, dict):
                for k, x in v.items():
                    if not ALLOWED_STRING.fullmatch(k) and not re.fullmatch(r"[.\w\[\]]+", k):
                        bad.append(f"{where}: key {k!r}")
                    if k != "why":
                        walk(x, f"{where}.{k}")
            elif isinstance(v, list):
                for k, x in enumerate(v):
                    walk(x, f"{where}[{k}]")
            elif isinstance(v, str) and not ALLOWED_STRING.fullmatch(v):
                bad.append(f"{where}: {v!r}")

        walk(_snapshot(), "")
        self.assertEqual(bad[:20], [])

    def test_table_keys(self):
        """A table entry is a location and a layout; numbers are addresses, sizes, lines and lengths."""
        snap = _snapshot()
        self.assertEqual(set(snap), {"format", "release", "generated_by", "binaries", "tables", "structs", "pointers",
                                     "strings"})
        for key, t in snap["tables"].items():
            allowed = {"c_file", "name", "located", "why"} if t["located"] == "absent" else \
                {"c_file", "name", "binary", "address", "size", "located", "type", "decl", "element_lines", "slots"}
            self.assertLessEqual(set(t), allowed, key)

    def test_string_keys(self):
        """A string's entry is where it is and how long, never its text."""
        allowed = {"located", "binary", "address", "length", "table", "path", "alias"}
        for table, blocks in _snapshot()["strings"].items():
            for block, items in blocks.items():
                for key, loc in items.items():
                    self.assertLessEqual(set(loc), allowed, f"{table} {block} {key}")


@unittest.skipUnless(HAVE_DISC, "the US binaries are missing")
class FromTheDiscAlone(unittest.TestCase):

    def test_every_table_reads(self):
        """No decomp involved: the snapshot and the binaries give every table."""
        index = disc.DiscIndex(paths.DEFAULT_DISC)
        problems = []
        for key, t in index.snapshot["tables"].items():
            loaded = index.table(t["c_file"], t["name"])["us"]
            if t["located"] == "absent":
                self.assertIsNone(loaded, key)
                continue
            problems += [f"{key}: {i}" for i in loaded.issues]
        self.assertEqual(problems, [])

    def test_every_string_reads(self):
        strings = disc.DiscText(disc.DiscIndex(paths.DEFAULT_DISC)).strings()
        self.assertEqual(len(strings), sum(len(i) for b in _snapshot()["strings"].values() for i in b.values()))
        self.assertTrue(all(isinstance(v, str) and "\ufffd" not in v for v in strings.values()),
                        "every string decodes as Shift-JIS")

    def test_wrong_file_refused(self):
        with tempfile.TemporaryDirectory() as d:
            (Path(d) / "SLUS_010.32").write_bytes(b"\0" * 0x1000)
            index = disc.DiscIndex(Path(d))
            with self.assertRaises(disc.CError):
                index.table("src/main/main.c", "DIGIMON_DATA")


@unittest.skipUnless(HAVE_DISC and HAVE_DECOMP, "needs the decomp and the US binaries")
class AgainstTheDecomp(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        with tempfile.TemporaryDirectory() as work:
            cls.rec = disc.record_groups(paths.DEFAULT_INPUT, Path(work))
        cls.snap, cls.problems = disc.build_snapshot(cls.rec, paths.DEFAULT_DISC)

    def test_snapshot_builds(self):
        self.assertEqual(self.problems, [])

    def test_snapshot_up_to_date(self):
        self.assertEqual(json.loads(json.dumps(self.snap)), _snapshot(),
                         "dwdata/snapshot/us.json is stale: python -m dwdata snapshot")

    def test_every_table_equals_the_decomp(self):
        self.assertEqual(disc.check(self.rec, disc.DiscIndex(paths.DEFAULT_DISC, _snapshot())), [])

    def test_every_string_equals_the_decomp(self):
        """Every US string (1,117 on 2026-11-09) read from the binaries is the decomp's en_us text."""
        self.assertEqual(disc.check_text(self.rec, disc.DiscText(disc.DiscIndex(paths.DEFAULT_DISC, _snapshot()))), [])

    def test_every_loaded_table_is_in_the_snapshot(self):
        keys = {f"{c}:{n}" for c, n in self.rec.tables} | set(disc.ABSENT)
        self.assertEqual(keys, set(_snapshot()["tables"]))


if __name__ == "__main__":
    unittest.main()
