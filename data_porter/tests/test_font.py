import json
import re
import tempfile
import unittest
from pathlib import Path
from unittest import mock

from dwdata.groups import font
from dwdata.paths import DEFAULT_INPUT
from tests.test_text import VERSION_H

# US glyph codes in the real order: A-Z, a-z, 0-9, then punctuation and the button symbols (× last).
US_CODES = ([0x8260 + i for i in range(26)] + [0x8281 + i for i in range(26)] + [0x824F + i for i in range(10)]
            + [0x8140, 0x8142, 0x8148, 0x8149, 0x8176, 0x8175, 0x8143, 0x815F, 0x8146, 0x8147, 0x817B, 0x817C,
               0x8181, 0x819B, 0x81A0, 0x81A2, 0x817E])
KANJI = [0x889F + i for i in range(94)] + [0x8940 + i for i in range(63)] + [0x8980 + i for i in range(125)] \
    + [0x8A40 + i for i in range(63)] + [0x8A80 + i for i in range(125)] + [0x8B40 + i for i in range(63)] \
    + [0x8B80 + i for i in range(125)] + [0x8C40 + i for i in range(63)] + [0x8C80 + i for i in range(125)] \
    + [0x8D40 + i for i in range(63)] + [0x8D80 + i for i in range(125)]


def release_codes(size: int) -> list:
    """US letters and digits first, the 0xffff placeholder at slot 60, kanji to fill, sentinel 0 last."""
    base = US_CODES[:-1]
    codes = base[:60] + [0xFFFF] + base[60:]
    codes += KANJI[:size - 1 - len(codes)]
    return codes + [0]


A_ROWS = [0xF3FF, 0xEDFF, 0xDDFF, 0xDEFF, 0xBEFF, 0x80FF, 0x7F7F, 0x7F7F, 0x7F7F, 0x7F7F, 0xFFFF]


def c_array(name: str, ctype: str, size: str, values: list) -> list:
    return [f"{ctype} {name}[{size}] = {{"] + [f"\t{v}," for v in values] + ["};"]


def font_c(rows_bits: int = 0xF) -> str:
    def glyph(code, us):
        rows = A_ROWS if code == 0x8260 else [0xFFF0 | rows_bits] * 11
        width = ", 8" if us and 0x8281 <= code < 0x829B else ", 12" if us else ""
        return "{ { " + ", ".join(f"0x{r:04x}" for r in rows) + " }" + width + " }"
    lines = ["#include <dw/font.h>", "#include <dw/version.h>",
             "#if VERSION_IS(EU)", "#define NUM_GLYPHS 188", "#elif !VERSION_IS(US)", "#define NUM_GLYPHS 992",
             "#else", "#define NUM_GLYPHS 79", "#endif",
             "typedef struct {", "\tuint16_t pixelData[11];", "#if VERSION_IS(US)", "\tuint16_t width;", "#endif",
             "} GlyphData;"]
    for cond, codes, us in (("#if VERSION_IS(EU)", release_codes(188), False),
                            ("#elif !VERSION_IS(US)", release_codes(992), False), ("#else", US_CODES, True)):
        lines.append(cond)
        lines += c_array("CHAR_TO_GLYPH_TABLE", "uint16_t", "NUM_GLYPHS", [f"0x{c:04x}" for c in codes])
        lines += c_array("GLYPH_DATA", "GlyphData", "NUM_GLYPHS", [glyph(c, us) for c in codes])
    lines.append("#endif")
    lines += c_array("FONT_CLUT", "uint16_t", "16", ["0x0000", "0x6b5a", "0x7c00"] + ["0x0000"] * 13)
    lines += ["void evidence(void)", "{"] + [as_c(needle) for path, needle in font.EVIDENCE if path == font.FONT_C]
    return "\n".join(lines + ["}"]) + "\n"


def as_c(needle: str) -> str:
    """An evidence needle as compilable C: directives on their own lines, open braces closed."""
    text = re.sub(r"\s*(#(?:if|elif) \S+)\s+", r"\n\1\n", needle)
    text = re.sub(r"\s*#endif", "\n#endif", text)
    return text + "}" * (needle.count("{") - needle.count("}"))


SJIS_C = """\
typedef struct {
\tuint16_t shiftJIS;
\tuint16_t ascii;
} Ascii2ShiftJIS;
Ascii2ShiftJIS CHAR_MAPPING_NORMAL[3] = { { 0x824f, 0x0030 }, { 0x8260, 0x0041 }, { 0x8281, 0x0061 }, };
Ascii2ShiftJIS CHAR_MAPPING_SPECIAL[33] = {
\t{ 0x8140, 0x0020 }, { 0x8149, 0x0021 }, { 0x8168, 0x0022 }, { 0x8194, 0x0023 }, { 0x8190, 0x0024 },
\t{ 0x8193, 0x0025 }, { 0x8195, 0x0026 }, { 0x8166, 0x0027 }, { 0x8169, 0x0028 }, { 0x816a, 0x0029 },
\t{ 0x8196, 0x002a }, { 0x817b, 0x002b }, { 0x8143, 0x002c }, { 0x817c, 0x002d }, { 0x8142, 0x002e },
\t{ 0x815e, 0x002f }, { 0x8146, 0x003a }, { 0x8147, 0x003b }, { 0x8171, 0x003c }, { 0x8181, 0x003d },
\t{ 0x8172, 0x003e }, { 0x8148, 0x003f }, { 0x8197, 0x0040 }, { 0x816d, 0x005b }, { 0x815f, 0x005c },
\t{ 0x816e, 0x005d }, { 0x814f, 0x005e }, { 0x8151, 0x005f }, { 0x8165, 0x0060 }, { 0x816f, 0x007b },
\t{ 0x8162, 0x007c }, { 0x8170, 0x007d }, { 0x8150, 0x007e },
};
"""

UTILS_C = """\
#include <dw/graphics.h>
#include <dw/version.h>
#if VERSION_IS(EU)
RGB8 TEXT_COLORS[18] = {
#else
RGB8 TEXT_COLORS[17] = {
#endif
""" + "".join(f"\t{{ 0x{i * 8:02x}, 0x80, 0x80 }},\n" for i in range(17)) + """\
#if VERSION_IS(EU)
\t{ 0x2c, 0x7c, 0x54 },
#endif
};
"""


def make_decomp(root: Path, en_us: str = "Hello. It's #C1ok 100%d") -> None:
    (root / "include" / "dw").mkdir(parents=True)
    (root / "include" / "dw" / "version.h").write_text(VERSION_H, encoding="utf-8")
    (root / "include" / "dw" / "font.h").write_text("#define GLYPH_WIDTH 12\n", encoding="utf-8")
    (root / "include" / "dw" / "graphics.h").write_text("typedef struct {\n\tuint8_t r, g, b;\n} RGB8;\n",
                                                        encoding="utf-8")
    (root / "config" / "us").mkdir(parents=True)
    (root / "config" / "us" / "main.yaml").write_text(
        "name: main\noptions:\n  src_path: src/main\nsegments:\n      - [0x100, c, font]\n      - [0x200, c, sjis]\n"
        "      - [0x300, c, utils]\n", encoding="utf-8")
    main = root / "src" / "main"
    main.mkdir(parents=True)
    (main / "font.c").write_text(font_c(), encoding="utf-8")
    (main / "sjis.c").write_text(SJIS_C + "void f(void)\n{\n" + "\n".join(
        needle for path, needle in font.EVIDENCE if path == font.SJIS_C) + "\n}\n", encoding="utf-8")
    (main / "utils.c").write_text(UTILS_C, encoding="utf-8")
    kanji = bytes([0x88, 0x9F, 0x88, 0xA0]).decode("cp932")
    (root / "text" / "main").mkdir(parents=True)
    (root / "text" / "main" / "item.yaml").write_text(
        f"STR_TEST:\n  ja: \"{kanji}C1　{kanji}\"\n  en_us: \"{en_us}\"\n  en_eu: \"{{C1}}Hi 9\"\n",
        encoding="utf-8")


NO_MISSING = {"en_us": {}, "ja": {}, "en_eu": {}}


class FontConvertTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.decomp, self.output = self.root / "decomp", self.root / "out"

    def tearDown(self):
        self.tmp.cleanup()

    def load(self, name):
        return json.loads((self.output / "font" / f"{name}.json").read_text(encoding="utf-8"))

    def failed(self, out):
        return {c.name: c.detail for c in out.checks if not c.passed}

    def test_converts_and_passes_checks(self):
        make_decomp(self.decomp)
        with mock.patch.object(font, "KNOWN_MISSING", NO_MISSING):
            out = font.convert(self.decomp, self.output)
        self.assertEqual(self.failed(out), {})
        us = self.load("en_us")
        self.assertEqual(list(us)[:6], ["table", "source", "schema", "records", "used_by", "godot"])
        a = us["records"][0]
        self.assertEqual((a["code"], a["code_hex"], a["char"], a["width"]), (0x8260, "0x8260", "Ａ", 12))
        self.assertEqual(a["bitmap"][0], "....##......")
        self.assertEqual(a["bitmap"][5], ".#######....")                      # 0x80ff: a 0 bit is ink
        self.assertEqual(us["records"][26]["width"], 8)                        # ａ: US width from the data
        self.assertTrue(us["records"][-1]["sentinel"])
        self.assertEqual(us["records"][-1]["char"], "×")
        eu = self.load("en_eu")["records"]
        self.assertEqual(len(eu), 188)
        self.assertTrue(eu[60]["placeholder"])
        self.assertIsNone(eu[60]["char"])
        self.assertEqual((eu[0]["width"], eu[63]["width"]), (8, 12))          # Ａ narrow, the space 12
        ja = self.load("ja")["records"]
        self.assertEqual({r["width"] for r in ja}, {12})
        self.assertEqual(ja[-1]["code"], 0)
        ascii_ = {a["char"]: a for a in self.load("ascii")["records"]}
        self.assertEqual((ascii_["A"]["code"], ascii_["A"]["glyph"]["en_us"]), (0x8260, 0))
        self.assertEqual((ascii_["'"]["code"], ascii_["'"]["draw_string_code"]), (0x8166, 0x8175))
        self.assertEqual(ascii_["."]["draw_string_code"], 0x8142)
        self.assertIsNone(ascii_["&"]["glyph"]["en_us"])                        # no US glyph: draws ×
        self.assertEqual(self.load("clut")["records"][2]["rgb8"], [0, 0, 255])
        colors = self.load("text_colors")["records"]
        self.assertEqual((len(colors), colors[17]["releases"]), (18, ["eu"]))
        self.assertEqual(colors[16]["tint"], [1.0, 1.0, 1.0])
        self.assertTrue((self.output / "font" / "en_us.png").read_bytes().startswith(b"\x89PNG"))

    def test_text_character_without_a_glyph_fails(self):
        make_decomp(self.decomp, en_us="Rock & Roll")
        with mock.patch.object(font, "KNOWN_MISSING", NO_MISSING):
            out = font.convert(self.decomp, self.output)
        failed = self.failed(out)
        name = "en_us: every character of the text has a glyph, except the known ones"
        self.assertEqual(list(failed), [name])
        self.assertIn("text/main/item.yaml STR_TEST STR_TEST: found '&'", failed[name])

    def test_used_bits_fail(self):
        make_decomp(self.decomp)
        (self.decomp / "src" / "main" / "font.c").write_text(font_c(rows_bits=0x0), encoding="utf-8")
        with mock.patch.object(font, "KNOWN_MISSING", NO_MISSING):
            out = font.convert(self.decomp, self.output)
        self.assertIn("en_us: unused bits 3..0 are 1", self.failed(out))

    def test_rules(self):
        self.assertEqual([font.eu_width(c) for c in (0x8260, 0x8148, 0x8140, 0x889F, 0x8394, 0x8395)],
                         [8, 8, 12, 12, 8, 12])
        normal = [{"shiftJIS": 0x824F, "ascii": 0x30}, {"shiftJIS": 0x8260, "ascii": 0x41},
                  {"shiftJIS": 0x8281, "ascii": 0x61}]
        special = [{"shiftJIS": 0x8100 + i, "ascii": 0} for i in range(33)]
        self.assertEqual(font.ascii_to_jis(ord("z"), normal, special), 0x829A)
        self.assertEqual(font.ascii_to_jis(ord(" "), normal, special), 0x8100)        # special 0
        self.assertEqual(font.ascii_to_jis(ord(":"), normal, special), 0x8110)        # special 16
        self.assertEqual(font.ascii_to_jis(ord("~"), normal, special), 0x8120)        # special 32
        self.assertEqual(font.ascii_to_jis(0x7F, normal, special), 0)


@unittest.skipUnless((DEFAULT_INPUT / "src" / "main" / "font.c").is_file(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    def test_real_font(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = font.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [f"{c.name}: {c.detail}" for c in out.checks if not c.passed])
            load = lambda n: json.loads((Path(tmp) / "font" / f"{n}.json").read_text(encoding="utf-8"))
            us = load("en_us")["records"]
            self.assertEqual((len(us), us[0]["char"], us[62]["code"], us[-1]["char"]), (79, "Ａ", 0x8140, "×"))
            self.assertEqual(us[26]["width"], 8)                                     # ａ
            self.assertEqual(len(load("ja")["records"]), 992)
            self.assertEqual(len(load("en_eu")["records"]), 188)
            self.assertEqual(load("clut")["records"][1]["raw"], 0x6B5A)
            self.assertEqual(load("text_colors")["records"][0]["rgb"], [0x80, 0x80, 0x80])


if __name__ == "__main__":
    unittest.main()
