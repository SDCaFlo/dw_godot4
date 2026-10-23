import tempfile
import unittest
from pathlib import Path

from dwdata.cdata import CError, CIndex, Value, sizeof
from dwdata.decomp import Decomp
from tests.test_text import VERSION_H

HEADER = """\
#ifndef DW_THING_H
#define DW_THING_H

#include <dw/types.h>

#define COUNT 3
#define DOUBLE (COUNT * 2)

typedef enum { KIND_A, KIND_B = 5, KIND_C } Kind;

typedef struct {
#if !VERSION_IS(EU)
	char name[8];
#endif
	int32_t big;
	int16_t small;
	uint8_t list[COUNT];
	uint8_t flag;
} Thing;

typedef struct {
	Thing thing;     /* uses a type of this header */
	Other other;     /* uses a type of a header read later */
	SVECTOR pos;
} Holder;

#endif
"""

LATER_HEADER = """\
#ifndef DW_ZZZ_H
#define DW_ZZZ_H
typedef struct { uint16_t a, *b; } Other;
#endif
"""

C_FILE = """\
#include <dw/thing.h>

GENERATED_TEXT_MACRO

Thing THINGS[2] = {
	{
		NAME(STR_A)
		0x10, -1, { 1, 2, 3 }, KIND_C,
	},
#if VERSION_IS(JP)
	{ NAME(STR_B) 0x20, 0xffff, 4, 5, 6, DOUBLE },   // brace elision, wrapped value
#else
	{ NAME(STR_B) 0x20, 7, 4, 5 },                   // last field zero-filled
#endif
};

static const char GREETING[] = "Hi\\n" "there";
uint8_t GRID[2][3] = { { 1, 2, 3 }, 4, 5, 6 };
Holder HOLDER = { .other = { 1 } };
"""


def name_hook(args, release, tok):
    return [] if release == "eu" else [Value(args[0], tok.line)]


class CDataTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        root = Path(self.tmp.name)
        (root / "include" / "dw").mkdir(parents=True)
        (root / "include" / "dw" / "version.h").write_text(VERSION_H, encoding="utf-8")
        (root / "include" / "dw" / "thing.h").write_text(HEADER, encoding="utf-8")
        (root / "include" / "dw" / "zzz.h").write_text(LATER_HEADER, encoding="utf-8")
        (root / "src" / "main").mkdir(parents=True)
        (root / "src" / "main" / "thing.c").write_text(C_FILE, encoding="utf-8")
        self.index = CIndex(Decomp(root))

    def tearDown(self):
        self.tmp.cleanup()

    def table(self, name, hooks=None):
        return self.index.table("src/main/thing.c", name, hooks)

    def test_struct_table_per_release(self):
        things = self.table("THINGS", {"NAME": name_hook})
        us, jp, eu = things["us"], things["jp"], things["eu"]
        self.assertEqual(us.type.describe(), "Thing[2]")
        self.assertEqual(us.value[0], {"name": "STR_A", "big": 16, "small": -1, "list": [1, 2, 3], "flag": 6})
        self.assertEqual(us.value[1], {"name": "STR_B", "big": 32, "small": 7, "list": [4, 5, 0], "flag": 0})
        self.assertEqual(us.implicit, 2)
        self.assertEqual(us.element_lines, [6, 13])
        self.assertEqual(jp.value[1], {"name": "STR_B", "big": 32, "small": -1, "list": [4, 5, 6], "flag": 6})
        self.assertEqual(jp.wrapped, [{"line": 11, "written": 0xffff, "stored": -1, "type": "int16_t"}])
        self.assertNotIn("name", eu.value[0])             # the field doesn't exist in EU
        self.assertEqual(eu.issues, [])

    def test_strings_arrays_designators(self):
        self.assertEqual(self.table("GREETING")["us"].value, "Hi\nthere")
        grid = self.table("GRID")["us"]
        self.assertEqual(grid.type.describe(), "uint8_t[2][3]")
        self.assertEqual(grid.value, [[1, 2, 3], [4, 5, 6]])
        holder = self.table("HOLDER")["us"]
        self.assertEqual(holder.value["other"], {"a": 1, "b": None})
        self.assertEqual(holder.value["pos"], {"vx": 0, "vy": 0, "vz": 0, "pad": 0})

    def test_constants_and_sizes(self):
        prog = self.index.program("src/main/thing.c", "us")
        self.assertEqual((prog.enums["KIND_A"], prog.enums["KIND_C"]), (0, 6))
        self.assertEqual(prog.eval_int(prog.defines["DOUBLE"][1]), 6)
        self.assertEqual(sizeof(prog.structs["Thing"]), 20)      # 8 + 4 + 2 + 3 + 1, padded to 4
        eu = self.index.program("src/main/thing.c", "eu")
        self.assertEqual(sizeof(eu.structs["Thing"]), 12)        # 4 + 2 + 3 + 1, padded to 4
        self.assertEqual(self.table("THINGS", {"NAME": name_hook})["jp"].decl.line, 5)

    def test_generated_macro_prefix_is_skipped_but_unknown_types_raise(self):
        prog = self.index.program("src/main/thing.c", "us")
        tokens = prog.data["THINGS"].type_tokens
        self.assertEqual([t.text for t in tokens], ["GENERATED_TEXT_MACRO", "Thing"])
        with self.assertRaises(CError):
            prog.type_of(tokens[:1], 0, [])


if __name__ == "__main__":
    unittest.main()
