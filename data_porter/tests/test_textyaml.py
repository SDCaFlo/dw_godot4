import unittest

from dwdata import textyaml
from dwdata.textyaml import YamlError, parse, to_python

DOC = """\
# comment
BLOCK:                      # trailing comment
  storage: {default: embedded, eu: named}
  lines: {eu: 2}
  entries:
    - name: A
      ja: あ
      en_us: "Yes"           # quoted so it stays text
      named: [eu]
    - name:
        - B1
        - B2
      ja: い
      en_us: Two words
      en_eu:
        - first
        - NULL
    - NULL
SINGLE:
  ja: "\\0"
  en_us: 20
  en_eu: "#C1 a # b {W}"
QUOTE:
  ja: 'it''s'
  en_us: Koga's Laws
"""


class TextYamlTests(unittest.TestCase):
    def test_structure_and_scalars(self):
        root = to_python(parse(DOC))
        block = root["BLOCK"]
        self.assertEqual(block["storage"], {"default": "embedded", "eu": "named"})
        self.assertEqual(block["lines"], {"eu": "2"})
        a, b, null = block["entries"]
        self.assertEqual(a, {"name": "A", "ja": "あ", "en_us": "Yes", "named": ["eu"]})
        self.assertEqual(b["name"], ["B1", "B2"])
        self.assertEqual(b["en_eu"], ["first", None])
        self.assertIsNone(null)
        # Scalars stay strings; escapes are decoded; '#' inside quotes is text.
        self.assertEqual(root["SINGLE"], {"ja": "\0", "en_us": "20", "en_eu": "#C1 a # b {W}"})
        self.assertEqual(root["QUOTE"], {"ja": "it's", "en_us": "Koga's Laws"})

    def test_line_numbers(self):
        root = parse(DOC)
        self.assertEqual(root.key_lines["BLOCK"], 2)
        entries = root.get("BLOCK").get("entries")
        self.assertEqual(entries.items[1].line, 10)
        self.assertEqual(root.get("SINGLE").get("en_us").line, 21)

    def test_quoted_null_is_text(self):
        self.assertEqual(to_python(parse('A:\n  ja: "NULL"\n  en_us: NULL\n')), {"A": {"ja": "NULL", "en_us": None}})

    def test_errors(self):
        for bad in ("A:\n  ja: x\n  ja: y\n",           # duplicate key
                    "A:\n  ja: a: b\n",                  # ':' in plain scalar
                    "A:\n\tja: x\n",                     # tab indentation
                    "A:\n  ja: |\n    x\n",              # block scalar
                    'A:\n  ja: "open\n',                 # unterminated quote
                    "A:\n  ja: x\n    en_us: y\n",       # bad indentation
                    "A:\n"):                             # key without value
            with self.assertRaises(YamlError, msg=bad):
                parse(bad)

    def test_unknown_escape(self):
        with self.assertRaises(YamlError):
            parse('A:\n  ja: "\\q"\n')
        self.assertEqual(textyaml.to_python(parse('A:\n  ja: "\\x41\\u3042"\n')), {"A": {"ja": "Aあ"}})


if __name__ == "__main__":
    unittest.main()
