import json
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import text
from dwdata.paths import DEFAULT_INPUT

VERSION_H = """\
#define VERSION_DATE_JP		19981224
#define VERSION_DATE_US		19990331
#define VERSION_DATE_JP_REV1	19990406
#define VERSION_DATE_EU		20010504
#define VERSION_ID_JP		1
#define VERSION_ID_US		4
#define VERSION_ID_JP_REV1	5
#define VERSION_ID_EU		6
#if defined(VERSION_JP)
#define VERSION_ID		VERSION_ID_JP
#define VERSION_REGION		VERSION_REGION_NTSCJ
#elif defined(VERSION_US)
#define VERSION_ID		VERSION_ID_US
#define VERSION_REGION		VERSION_REGION_NTSCU
#elif defined(VERSION_JP_REV1)
#define VERSION_ID		VERSION_ID_JP_REV1
#define VERSION_REGION		VERSION_REGION_NTSCJ
#elif defined(VERSION_EU)
#define VERSION_ID		VERSION_ID_EU
#define VERSION_REGION		VERSION_REGION_PAL
#endif
"""

YAML = """\
NAMES:
  storage: {default: embedded, eu: named}
  macro: PARA_NAME
  entries:
    - name: STR_NAME_A
      ja: エー
      en_us: Alpha
    - name: STR_NAME_B
      ja: ビー
      en_us: Beta
      en_eu: Bêta
LIST:
  lines: {eu: 2}
  empty: STR_EMPTY
  entries:
    - name: [STR_D0, STR_D0_2]
      ja: せつめい
      ja@jp: せつめい！
      en_us: Desc
      en_eu: [Line one, line two]
    - ja: せつめい
      en_us: Desc
      en_eu: [Line one, line two]
    - NULL
MESSAGES:
  strings:
    STR_HELLO:
      ja: こんにちは
      en_us: "Hello #C1\\0\\0"
      en_eu: "{C1}Hello"
    STR_EU_ONLY:
      ja: NULL
      en_us: NULL
      en_eu: Bye
STR_SINGLE:
  ja: ！
  en_us: "!"
"""

C_FILE = """\
#include <text/main/foo.h>

NAMES_STRINGS
LIST_STRINGS
LIST_TEXT
MESSAGES_TEXT
STR_SINGLE_TEXT

Para PARA[2] = {
	{ PARA_NAME(STR_NAME_A) 1 },
	{ PARA_NAME(STR_NAME_B) 2 },
};

void showHello(void)
{
	drawString(STR_HELLO, 0, 0);
#if VERSION_IS(EU)
	drawString(STR_EU_ONLY, 0, 0);
#endif
	drawString(LIST[0], 0, 0);
}
"""


def make_decomp(root: Path, yaml=YAML, c_file=C_FILE) -> None:
    (root / "include" / "dw").mkdir(parents=True)
    (root / "include" / "dw" / "version.h").write_text(VERSION_H, encoding="utf-8")
    (root / "config" / "us").mkdir(parents=True)
    (root / "config" / "us" / "main.yaml").write_text(
        "name: main\noptions:\n  src_path: src/main\nsegments:\n      - [0x100, c, foo]\n", encoding="utf-8")
    (root / "config" / "us" / "symbols.txt").write_text("STR_HELLO = 0x80100000; // size:0x10\n", encoding="utf-8")
    (root / "src" / "main").mkdir(parents=True)
    (root / "src" / "main" / "foo.c").write_text(c_file, encoding="utf-8")
    (root / "text" / "main").mkdir(parents=True)
    (root / "text" / "main" / "foo.yaml").write_text(yaml, encoding="utf-8")
    (root / "text" / "example.yaml").write_text("X:\n  ja: x\n  en_us: x\n", encoding="utf-8")


class TextConvertTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        self.decomp, self.output = self.root / "decomp", self.root / "out"

    def tearDown(self):
        self.tmp.cleanup()

    def convert(self, **kw):
        make_decomp(self.decomp, **kw)
        out = text.convert(self.decomp, self.output)
        table = json.loads((self.output / "text" / "main" / "foo.json").read_text(encoding="utf-8"))
        return out, table

    def test_converts_and_passes_checks(self):
        out, table = self.convert()
        failed = [f"{c.name}: {c.detail}" for c in out.checks if not c.passed]
        self.assertEqual(failed, [])
        self.assertEqual(list(table)[:6], ["table", "source", "schema", "records", "used_by", "godot"])
        blocks = {b["block"]: b for b in table["records"]}
        self.assertEqual([b["kind"] for b in table["records"]], ["entries", "entries", "strings", "text"])

        a, b = blocks["NAMES"]["entries"]
        self.assertEqual(a["text"], {"ja": "エー", "en_us": "Alpha", "en_eu": "Alpha"})  # en_eu falls back
        self.assertEqual(b["text"]["en_eu"], "Bêta")
        self.assertEqual(a["used_by"][0]["in"], "PARA")  # embedded in a data table via the macro
        self.assertEqual(blocks["NAMES"]["c"]["placed_at"], {"NAMES_STRINGS": [3], "PARA_NAME": [10, 11]})

        d0, unnamed, null = blocks["LIST"]["entries"]
        self.assertEqual(d0["text"]["en_eu"], "Line one\nline two")
        self.assertEqual(d0["lines"], {"en_eu": ["Line one", "line two"]})
        self.assertEqual(d0["release_text"], {"jp": "せつめい！"})
        self.assertEqual(unnamed["same_as"], {"ja": "STR_D0", "en_us": "STR_D0", "en_eu": "STR_D0"})
        self.assertTrue(null["null_entry"])
        self.assertEqual(blocks["LIST"]["used_by"][0]["in"], "showHello")

        hello, eu_only = blocks["MESSAGES"]["strings"]
        self.assertEqual(hello["text"]["en_us"], "Hello #C1")           # cut at the first NUL
        self.assertEqual(hello["variants"]["en_us"], "Hello #C1\0\0")  # raw kept
        self.assertEqual(hello["symbol"], {"address": "0x80100000", "size": 16})
        self.assertEqual(eu_only["used_by"][0]["releases"], ["eu"])
        self.assertEqual(blocks["STR_SINGLE"]["strings"][0]["id"], "STR_SINGLE")

        catalog = json.loads((self.output / "catalog.json").read_text(encoding="utf-8"))
        self.assertEqual([t["table"] for t in catalog["tables"]], ["text/main/foo"])
        self.assertTrue((self.output / "text" / "report.md").is_file())

    def test_code_using_missing_text_fails(self):
        out, _ = self.convert(c_file=C_FILE.replace("#if VERSION_IS(EU)\n", "").replace("#endif\n", ""))
        failed = [c.name for c in out.checks if not c.passed]
        self.assertEqual(failed, ["code only uses strings that exist in the release compiling it"])

    def test_c_definition_counts_as_text(self):
        c_file = C_FILE.replace("#if VERSION_IS(EU)\n", "").replace("#endif\n", "")
        c_file = c_file.replace("void showHello", '#if !VERSION_IS(EU)\nchar STR_EU_ONLY[] = "bye";\n#endif\n\nvoid showHello')
        out, table = self.convert(c_file=c_file)
        self.assertTrue(out.ok, [c.detail for c in out.checks if not c.passed])
        eu_only = table["records"][2]["strings"][1]
        self.assertEqual(eu_only["c_definitions"][0]["releases"], ["jp", "us", "jp_rev1"])

    def test_format_issue_is_reported(self):
        out, _ = self.convert(yaml=YAML.replace("      ja: こんにちは\n", "      jp: こんにちは\n"))
        failed = {c.name: c.detail for c in out.checks if not c.passed}
        self.assertIn("text/main/foo.yaml: format", failed)
        self.assertIn("no ja text", failed["text/main/foo.yaml: format"])


@unittest.skipUnless((DEFAULT_INPUT / "text").is_dir(), "dw_decomp not available")
class RealDataTests(unittest.TestCase):
    def test_real_text(self):
        with tempfile.TemporaryDirectory() as tmp:
            out = text.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [f"{c.name}: {c.detail}" for c in out.checks if not c.passed])
            item = json.loads((Path(tmp) / "text" / "main" / "item.json").read_text(encoding="utf-8"))
            moves = item["records"][0]
            self.assertEqual(moves["block"], "MOVE_NAMES")
            self.assertEqual(moves["entries"][2]["text"]["en_us"], "Spit Fire")
            main = json.loads((Path(tmp) / "text" / "main" / "main.json").read_text(encoding="utf-8"))
            names = main["records"][1]["entries"]
            self.assertEqual(names[3]["text"], {"ja": "アグモン", "en_us": "Agumon", "en_eu": "Agumon"})


if __name__ == "__main__":
    unittest.main()
