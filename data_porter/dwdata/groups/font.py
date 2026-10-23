"""Font group: the game's own glyph tables per release, the font palette, the text tints, the ASCII map.

Follows specs/font.md (renderer: ../specs/text.md). GLYPH_DATA / CHAR_TO_GLYPH_TABLE (src/main/font.c) are
read per release with cdata.CIndex: US 79 glyphs with an advance width, JP 992, EU 188. FONT_CLUT
(font.c), TEXT_COLORS (utils.c) and CHAR_MAPPING_* (sjis.c) complete what drawGlyph / drawString /
renderString need. The rules written as code (EU widths, the drawString overrides, convertAsciiToJis)
are reproduced here and their C text is checked.
"""

import re
import struct
import zlib

from .. import tables
from ..cdata import CIndex
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText
from . import text as text_group

NAME = "font"
SPEC = "specs/font.md"
PURPOSE = "Font glyphs per language (bitmaps, Shift-JIS codes, widths), font palette, text tints, ASCII map"
SOURCE_GLOB = "src/main/font.c"
FONT_C = "src/main/font.c"
SJIS_C = "src/main/sjis.c"
UTILS_C = "src/main/utils.c"
FONT_H = "include/dw/font.h"

# Language -> release whose font it uses (text group: each language's main release).
LANGUAGES = {"en_us": "us", "ja": "jp_rev1", "en_eu": "eu"}
GLYPHS = {"us": 79, "eu": 188, "jp": 992}   # NUM_GLYPHS (font.c:8-14); every JP release has 992
GLYPH_HEIGHT = 11
CELL = 12                                   # GLYPH_CELL_WIDTH; pixels 0-11 are bits 15-4 of a row
UNUSED_BITS = 0xF
PLACEHOLDER = 0xFFFF                        # no 2-byte string code can match it
PLACEHOLDERS = {"en_us": [], "ja": [60], "en_eu": [60]}
FIXED_WIDTH = {"ja": 12}                    # GLYPH_WIDTH (font.h:12); drawString adds it after every glyph
SPACE = 0x8140

# drawGlyph (font.c:1611-1618): EU advance by code range.
EU_NARROW_RANGES = ((0x8260, 0x829B), (0x824F, 0x8259), (0x8341, 0x8395))
EU_NARROW_CODES = (0x8148, 0x8149, 0x8166, 0x8143, 0x8144, 0x8146, 0x817C, 0x815E, 0x8169, 0x816A)
EU_WIDTHS = (8, 12)
# drawString (US, font.c:1740-1746): two ASCII characters bypass convertAsciiToJis.
DRAW_STRING_OVERRIDES = {".": 0x8142, "'": 0x8175}
# convertAsciiToJis (sjis.c:73-89): (low, high, kind, value): kind "normal" = CHAR_MAPPING_NORMAL[value],
# "special" = specialOffset value into CHAR_MAPPING_SPECIAL.
ASCII_RANGES = ((0x20, 0x2F, "special", 0x1), (0x30, 0x39, "normal", 0x0), (0x3A, 0x40, "special", 0xB),
                (0x41, 0x5A, "normal", 0x1), (0x5B, 0x60, "special", 0x25), (0x61, 0x7A, "normal", 0x2),
                (0x7B, 0x7E, "special", 0x3F))

EVIDENCE = [
    (FONT_C, "CHAR_TO_GLYPH_TABLE[NUM_GLYPHS - 1] = code; for (n = 0;; ++n) { if (code == CHAR_TO_GLYPH_TABLE[n]) "
             "{ break; } }"),
    (FONT_C, "if ((code >= 0x8260 && code < 0x829b) || (code >= 0x824f && code < 0x8259) || (code >= 0x8341 && "
             "code < 0x8395) || code == 0x8148 || code == 0x8149 || code == 0x8166 || code == 0x8143 || code == 0x8144 "
             "|| code == 0x8146 || code == 0x817c || code == 0x815e || code == 0x8169 || code == 0x816a) { width = 8; "
             "} else { width = 12; }"),
    (FONT_C, "#if VERSION_IS(EU) if (code == 0x8140) { return 8; } #elif !VERSION_IS(US) if (code == 0x8140) { "
             "return; } #endif"),
    (FONT_C, "if (*str == '.') { codepoint = 0x8142; } else if (*str == '\\'') { codepoint = 0x8175; } else { "
             "codepoint = convertAsciiToJis(*str); }"),
    (FONT_C, "if ((x < 0) || (x >= TEXT_DRAW_LIMIT)) {"),
    (FONT_C, "if ((rowData & 0x8000) == 0) { tmp |= COLORCODE_LOWBITS; }"),
    (SJIS_C, "offset = (input - 0x20) - (specialOffset - 1); return CHAR_MAPPING_SPECIAL[offset].shiftJIS;"),
    (SJIS_C, "return (uint16_t)(input + CHAR_MAPPING_NORMAL[charType].shiftJIS - CHAR_MAPPING_NORMAL[charType].ascii);"),
] + [(SJIS_C, f"if ((input >= {lo:#x}) && (input <= {hi:#x})) {{ "
              f"{'specialOffset' if kind == 'special' else 'charType'} = {value:#x}; }}")
     for lo, hi, kind, value in ASCII_RANGES]

# Characters of each language's text that its font has no glyph for (drawn as the last glyph: × in US, a
# crossed box in JP / EU). Keyed by "<text file> <block> <string>". The check fails when this changes.
KNOWN_MISSING = {
    "en_us": {
        "text/btl/battle_hud.yaml MESSAGES BTL_STR_MP_BONUS_PERCENT": "%",
        "text/main/item.yaml MOVE_NAMES STR_MOVE_NAME_DARK_NETWORK_CONCERT_CRUSH": "&",
        "text/main/main_menu.yaml SAVE_LABELS MAIN_D_80134678": "に",
        "text/main/main_menu.yaml SAVE_LABELS MAIN_D_8013467C": "が",
        "text/main/main_menu.yaml SAVE_LABELS MAIN_D_80134680": "を",
        "text/main/main_menu.yaml SAVE_MESSAGES MAIN_D_8013134C": "にのカスットドメモリロー",
        "text/shop/script_menu.yaml HIRAGANA_KA_ROW MAIN_D_8013045C": "かきくけと",
    },
    "ja": {},
    "en_eu": {
        "text/shop/script_menu.yaml HIRAGANA_KA_ROW MAIN_D_8013045C": "かきくけこ",
    },
}
# What each language's renderers don't draw as glyphs: control codes (data_porter specs/text.md §2), printf
# specifiers filled in before drawing, line breaks of multi-line entries.
NOT_DRAWN = {
    "en_us": re.compile(r"#C.|#R|#W|%0?\d*[ds]|\n"),
    "ja": re.compile(r"[\x00-\x7f]|　"),   # bare C<c> / R / W / 0 codes; drawGlyph skips the space
    "en_eu": re.compile(r"\{[A-Z]\d*\}|\n"),
}

TABLE_PURPOSES = {
    "en_us": "US font: 79 glyphs (11 rows x 12 px, Shift-JIS code, advance width)",
    "ja": "JP font: 992 glyphs (kana, kanji; 11 rows x 12 px, Shift-JIS code, fixed 12 px)",
    "en_eu": "EU font: 188 glyphs (11 rows x 12 px, Shift-JIS code, width 8 or 12 by code range)",
    "clut": "FONT_CLUT: the 16 colours of the text area's 4-bit pixels (index 0 transparent)",
    "text_colors": "TEXT_COLORS: tint per renderString colour (0x80 = x1.0)",
    "ascii": "ASCII 0x20-0x7E -> full-width Shift-JIS code (convertAsciiToJis, drawString overrides) and glyph",
}

GLYPH_SCHEMA = {
    "index": {"meaning": "index in CHAR_TO_GLYPH_TABLE / GLYPH_DATA"},
    "line": {"meaning": "line of the GLYPH_DATA record in src/main/font.c"},
    "code": {"c_name": "CHAR_TO_GLYPH_TABLE[index]", "c_type": "uint16_t",
             "meaning": "Shift-JIS code (first byte high) drawGlyph compares with; 0xffff = placeholder"},
    "code_hex": {"derived": "code as 0x%04x"},
    "char": {"derived": "code decoded as cp932 (the Shift-JIS variant the decomp's text YAML matches); null for the "
                        "placeholder and the sentinel's code 0. EU draws accented Latin letters at katakana codes: "
                        "there char is the code's meaning, not the shape"},
    "rows": {"c_name": "pixelData", "c_type": "uint16_t[11]",
             "meaning": "one row per line, top first: bits 15..4 = pixels 0..11 from the left, a 0 bit is ink; "
                        "bits 3..0 unused (1)"},
    "bitmap": {"derived": "rows as text, '#' = ink"},
    "width": {"meaning": "advance in px: US GlyphData.width (what drawGlyph returns); EU by code range "
                         "(drawGlyph, font.c:1611); JP GLYPH_WIDTH 12 (drawString)"},
    "sentinel": {"meaning": "last entry: drawGlyph writes the searched code into it first, so a code missing from "
                            "the table draws this glyph"},
    "placeholder": {"meaning": "code 0xffff: never matched by a 2-byte string code"},
    "c": {"meaning": "the GLYPH_DATA record exactly as the C initializer gives it"},
    "release_values": {"meaning": "fields that differ in another release of the same language: {release: {field: value}}"},
}


def _collapsed(text: str) -> str:
    return " ".join(text.split())


def _decode(code: int):
    if code in (0, PLACEHOLDER):
        return None
    try:
        return bytes([code >> 8, code & 0xFF]).decode("cp932")
    except UnicodeDecodeError:
        return None


def _encode(ch: str):
    try:
        b = ch.encode("cp932")
    except UnicodeEncodeError:
        return None
    return b[0] << 8 | b[1] if len(b) == 2 else None


def eu_width(code: int) -> int:
    """drawGlyph's EU advance (font.c:1611-1618)."""
    narrow = any(lo <= code < hi for lo, hi in EU_NARROW_RANGES) or code in EU_NARROW_CODES
    return EU_WIDTHS[0] if narrow else EU_WIDTHS[1]


def ascii_to_jis(c: int, normal: list, special: list) -> int:
    """convertAsciiToJis (sjis.c:63) on the parsed CHAR_MAPPING_* tables; 0 outside 0x20-0x7E."""
    for lo, hi, kind, value in ASCII_RANGES:
        if lo <= c <= hi:
            if kind == "special":
                return special[(c - 0x20) - (value - 1)]["shiftJIS"]
            return (c + normal[value]["shiftJIS"] - normal[value]["ascii"]) & 0xFFFF
    return 0


def draw_code(ch: str, language: str, normal: list, special: list):
    """The code a language's drawString hands drawGlyph for one character of its text (None: no code)."""
    if ord(ch) < 0x80:
        if language == "en_us" and ch in DRAW_STRING_OVERRIDES:
            return DRAW_STRING_OVERRIDES[ch]
        return ascii_to_jis(ord(ch), normal, special) or None
    return _encode(ch)


def _bitmap(rows: list) -> list:
    return ["".join("." if row >> (15 - x) & 1 else "#" for x in range(CELL)) for row in rows]


def _png(width: int, height: int, gray: bytes) -> bytes:
    def chunk(kind, data):
        return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data) & 0xFFFFFFFF)
    raw = b"".join(b"\0" + gray[y * width:(y + 1) * width] for y in range(height))
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def _sheet(records: list, scale: int = 2, per_row: int = 16) -> bytes:
    """Glyph sheet for VERIFY: 16 glyphs per row, ink black on white, cells separated by grey lines."""
    cw, ch = CELL + 1, GLYPH_HEIGHT + 1
    w, h = per_row * cw + 1, (len(records) + per_row - 1) // per_row * ch + 1
    px = bytearray([0xC0]) * (w * h)
    for n, rec in enumerate(records):
        ox, oy = n % per_row * cw + 1, n // per_row * ch + 1
        for y, row in enumerate(rec["rows"]):
            for x in range(CELL):
                px[(oy + y) * w + ox + x] = 0xFF if row >> (15 - x) & 1 else 0x00
    big = bytearray()
    for y in range(h):
        line = bytes(v for v in px[y * w:(y + 1) * w] for _ in range(scale))
        big += line * scale
    return _png(w * scale, h * scale, bytes(big))


def _text_strings(decomp: Decomp):
    """(key, language, text) of every string as its language's main release draws it."""
    for path in sorted(decomp.rel(p) for p in decomp.root.glob(text_group.SOURCE_GLOB)):
        if path in text_group.EXCLUDED:
            continue
        for block in text_group.load_file(decomp, path).blocks:
            for item in block["items"]:
                label = item["id"] or f"[{item.get('index')}]"
                for language, release in LANGUAGES.items():
                    t = (item.get("by_release") or {}).get(release)
                    if t:
                        yield f"{path} {block['block']} {label}", language, t


def _report(fonts: dict, clut: list, colors: list, ascii_records: list, missing: dict) -> str:
    out = ["# Font report", "",
           "Generated by `python -m dwdata convert font`. Glyph sheets: `en_us.png`, `ja.png`, `en_eu.png` (16 per "
           "row, table order, 2x). See `specs/font.md` and `../specs/text.md`.", "",
           "## Glyph counts", "", "| language | release | glyphs | widths | sentinel (last) code |", "|---|---|---|---|---|"]
    for language, recs in fonts.items():
        widths = sorted({r["width"] for r in recs})
        out.append(f"| {language} | {LANGUAGES[language]} | {len(recs)} | {widths} | {recs[-1]['code_hex']} |")
    us = fonts["en_us"]
    out += ["", "## US glyphs", "", "| index | code | char | width | bitmap |", "|---|---|---|---|---|"]
    for r in us:
        out.append(f"| {r['index']} | {r['code_hex']} | {r['char'] or '—'} | {r['width']} | "
                   f"<code>{'<br>'.join(r['bitmap'])}</code> |")
    out += ["", "## Font palette (`FONT_CLUT`)", "", "| index | raw | rgb8 | transparent |", "|---|---|---|---|"]
    for c in clut:
        out.append(f"| {c['index']} | {c['raw_hex']} | {c['rgb8']} | {c['transparent']} |")
    out += ["", "## Text tints (`TEXT_COLORS`)", "", "| index | rgb | tint | releases |", "|---|---|---|---|"]
    for c in colors:
        out.append(f"| {c['index']} | {c['rgb']} | {c['tint']} | {', '.join(c['releases'])} |")
    out += ["", "## ASCII map (US `drawString`)", "", "| ascii | char | convertAsciiToJis | drawn as | en_us glyph | "
            "en_eu glyph |", "|---|---|---|---|---|---|"]
    for a in ascii_records:
        ch = a["char"].replace("|", "\\|")
        out.append(f"| {a['ascii']:#04x} | `{ch}` | {a['code_hex']} | {a['draw_string_code_hex']} | "
                   f"{a['glyph']['en_us']} | {a['glyph']['en_eu']} |")
    out += ["", "## Text characters without a glyph", "",
            "Drawn as the sentinel's glyph (× in US, a crossed box in JP / EU).", ""]
    for language, found in missing.items():
        for key, chars in sorted(found.items()):
            out.append(f"- {language}: {key}: `{chars}`")
    return "\n".join(out) + "\n"


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    index = CIndex(decomp)
    sources = [SourceText(decomp.root, p).identity() for p in (FONT_C, FONT_H, SJIS_C, UTILS_C)]
    for path, needle in EVIDENCE:
        text = _collapsed((decomp.root / path).read_text(encoding="utf-8", errors="replace"))
        out.check(f"code still has: {needle[:70]}…", _collapsed(needle) in text, path)

    codes = tables.load(out, index, FONT_C, "CHAR_TO_GLYPH_TABLE")
    glyphs = tables.load(out, index, FONT_C, "GLYPH_DATA")
    clut = tables.load(out, index, FONT_C, "FONT_CLUT")
    colors = tables.load(out, index, UTILS_C, "TEXT_COLORS")
    normal = tables.load(out, index, SJIS_C, "CHAR_MAPPING_NORMAL")
    special = tables.load(out, index, SJIS_C, "CHAR_MAPPING_SPECIAL")
    if not (codes and glyphs and clut and colors and normal and special):
        out.finish(sources)
        return out
    for loaded in (codes, clut, colors, normal, special):
        tables.size_check(out, decomp, loaded)

    # GlyphData: US has a width after the rows (font.c:34-39).
    problems = []
    for release in decomp.releases:
        st = index.program(FONT_C, release).structs.get("GlyphData")
        want = ["pixelData", "width"] if release == "us" else ["pixelData"]
        got = [f.name for f in st.fields] if st else None
        if got != want:
            problems.append(f"{release}: {got}")
    out.check("struct GlyphData has the fields the spec maps", not problems, "; ".join(problems) or
              "US pixelData + width, other releases pixelData")

    sizes = {r: (len(codes[r].value), len(glyphs[r].value)) for r in decomp.releases}
    out.check("glyph tables have NUM_GLYPHS entries (US 79, JP 992, EU 188)",
              all(s == (GLYPHS.get(r, GLYPHS["jp"]),) * 2 for r, s in sizes.items()), str(sizes))
    jp = [r for r in decomp.releases if r not in ("us", "eu")]
    same = [r for r in jp if codes[r].value == codes["jp_rev1"].value and glyphs[r].value == glyphs["jp_rev1"].value]
    out.check("every JP release has the same font", same == jp, f"same as jp_rev1: {same}")

    mapping_n, mapping_s = normal["us"].value, special["us"].value
    out.check("CHAR_MAPPING_* are the same in every release",
              all(normal[r].value == mapping_n and special[r].value == mapping_s for r in decomp.releases),
              f"{len(mapping_n)} normal, {len(mapping_s)} special")

    refs = decomp.references(["CHAR_TO_GLYPH_TABLE", "GLYPH_DATA", "FONT_CLUT", "TEXT_COLORS",
                              "CHAR_MAPPING_NORMAL", "CHAR_MAPPING_SPECIAL"])

    def source_of(loaded, extra=None):
        return tables.source(decomp, loaded, sources, extra)

    # -- glyph tables --------------------------------------------------------------------------
    fonts, lookup = {}, {}
    for language, release in LANGUAGES.items():
        c_codes, c_glyphs = codes[release].value, glyphs[release].value
        lines = glyphs[release].element_lines or [None] * len(c_glyphs)
        last = len(c_codes) - 1
        records, bad = [], {"unused bits 3..0 are 1": [], "char decodes": [], "width in range": []}
        for i, (code, raw) in enumerate(zip(c_codes, c_glyphs)):
            rows = raw["pixelData"]
            if any(r & UNUSED_BITS != UNUSED_BITS for r in rows):
                bad["unused bits 3..0 are 1"].append(str(i))
            if release == "us":
                width = raw["width"]
            elif language == "en_eu":
                width = eu_width(code)
            else:
                width = FIXED_WIDTH[language]
            if not 0 < width <= CELL:
                bad["width in range"].append(f"{i}: {width}")
            char = _decode(code)
            if char is None and i != last and code != PLACEHOLDER:
                bad["char decodes"].append(f"{i}: {code:#06x}")
            rec = {"index": i, "line": lines[i], "code": code, "code_hex": f"{code:#06x}", "char": char,
                   "rows": rows, "bitmap": _bitmap(rows), "width": width}
            if i == last:
                rec["sentinel"] = True
            if code == PLACEHOLDER:
                rec["placeholder"] = True
            rec["c"] = raw
            rd = {}
            for other in (r for r in jp if language == "ja" and r != release):
                d = {k: v for k, v in (("code", codes[other].value[i]), ("rows", glyphs[other].value[i]["pixelData"]))
                     if v != rec[k]}
                if d:
                    rd[other] = d
            if rd:
                rec["release_values"] = rd
            records.append(rec)
        for check, items in bad.items():
            out.check(f"{language}: {check}", not items, "; ".join(items[:10]) or f"{len(records)} glyphs")
        body = c_codes[:last]
        dupes = sorted({f"{c:#06x}" for c in body if body.count(c) > 1})
        out.check(f"{language}: codes are unique", not dupes, ", ".join(dupes) or f"{len(set(body))} codes")
        placeholders = [r["index"] for r in records if r.get("placeholder")]
        out.check(f"{language}: 0xffff placeholders only at the known slots", placeholders == PLACEHOLDERS[language],
                  f"at {placeholders or 'none'}, known {PLACEHOLDERS[language] or 'none'}")
        fonts[language] = records
        # drawGlyph's search: first match, else the last glyph (whose code the C overwrites)
        lookup[language] = {}
        for r in records:
            lookup[language].setdefault(r["code"], r["index"])

        schema = dict(GLYPH_SCHEMA)
        out.write_table(language, {
            "table": {"name": f"font/{language}", "purpose": TABLE_PURPOSES[language]},
            "source": source_of(glyphs, {"codes": f"{FONT_C} CHAR_TO_GLYPH_TABLE", "release": release,
                                         "glyph_height": GLYPH_HEIGHT, "cell_width": CELL}),
            "schema": schema,
            "records": records,
            "used_by": tables.used_by(decomp, refs["GLYPH_DATA"] + refs["CHAR_TO_GLYPH_TABLE"], [], glyphs),
            "godot": {"status": "implemented (scripts/data/game_data.gd)",
                      "access": f"GameData.font(\"{language}\") -> records",
                      "notes": "PsxFont looks codes up like drawGlyph: first match, else the last (sentinel) glyph. "
                               + ("The full-width space 0x8140 is a glyph (US draws it)." if language == "en_us" else
                                  "drawGlyph skips the full-width space 0x8140 (EU advances 8, JP 12).")},
        }, symbols=["CHAR_TO_GLYPH_TABLE", "GLYPH_DATA"])
        (out.dir / f"{language}.png").write_bytes(_sheet(records))
        out.reports.append(f"{NAME}/{language}.png")

    # -- font palette ---------------------------------------------------------------------------
    clut_records = []
    for i, raw in enumerate(clut["us"].value):
        r5, g5, b5 = raw & 0x1F, raw >> 5 & 0x1F, raw >> 10 & 0x1F
        clut_records.append({"index": i, "raw": raw, "raw_hex": f"{raw:#06x}", "rgb5": [r5, g5, b5],
                             "stp": bool(raw >> 15), "rgb8": [(v << 3) | (v >> 2) for v in (r5, g5, b5)],
                             "transparent": raw == 0})
    out.check("FONT_CLUT: index 0 is transparent", clut_records[0]["transparent"], clut_records[0]["raw_hex"])
    out.write_table("clut", {
        "table": {"name": "font/clut", "purpose": TABLE_PURPOSES["clut"]},
        "source": source_of(clut, {"vram": {"x": 208, "y": 488}}),
        "schema": {"index": {"meaning": "colour index of a text-area pixel (setTextColor sets the ink index)"},
                   "raw": {"c_type": "uint16_t", "meaning": "15-bit BGR + STP as loaded into VRAM"},
                   "rgb5": {"derived": "red, green, blue 0-31"},
                   "stp": {"derived": "bit 15 (semi-transparency select); 0 in every entry"},
                   "rgb8": {"derived": "(v << 3) | (v >> 2), as the asset porter's PNGs"},
                   "transparent": {"derived": "raw == 0: the PSX draws no pixel"}},
        "records": clut_records,
        "release_values": tables.diffs(clut, lambda l: l.value),
        "used_by": tables.used_by(decomp, refs["FONT_CLUT"], [], clut),
        "godot": {"status": "implemented (scripts/data/game_data.gd)", "access": "GameData.font_clut() -> records",
                  "notes": "TextArea's palette texture."},
    }, symbols=["FONT_CLUT"])

    # -- text tints ------------------------------------------------------------------------------
    by_release = {r: l.value for r, l in colors.items()}
    longest = max(by_release.values(), key=len)
    prefix_ok = all(v == longest[:len(v)] for v in by_release.values())
    out.check("TEXT_COLORS: the releases differ only in extra entries at the end", prefix_ok,
              str({r: len(v) for r, v in by_release.items()}))
    color_records = []
    for i, c in enumerate(longest):
        rgb = [c["r"], c["g"], c["b"]]
        color_records.append({"index": i, "rgb": rgb, "tint": [v / 0x80 for v in rgb],
                              "releases": [r for r, v in by_release.items() if i < len(v)]})
    out.write_table("text_colors", {
        "table": {"name": "font/text_colors", "purpose": TABLE_PURPOSES["text_colors"]},
        "source": source_of(colors),
        "schema": {"index": {"meaning": "renderString's color argument"},
                   "rgb": {"c_type": "RGB8", "meaning": "polygon colour of the text quad (0x80 = texture as is)"},
                   "tint": {"derived": "rgb / 0x80 (the PSX modulates texels by colour / 128, saturating)"},
                   "releases": {"meaning": "releases whose table has this entry"}},
        "records": color_records,
        "used_by": tables.used_by(decomp, refs["TEXT_COLORS"], [], colors),
        "godot": {"status": "implemented (scripts/data/game_data.gd)", "access": "GameData.text_colors() -> records"},
    }, symbols=["TEXT_COLORS"])

    # -- ASCII map --------------------------------------------------------------------------------
    ascii_records = []
    for c in range(0x20, 0x7F):
        code = ascii_to_jis(c, mapping_n, mapping_s)
        drawn = DRAW_STRING_OVERRIDES.get(chr(c), code)
        ascii_records.append({"ascii": c, "char": chr(c), "code": code, "code_hex": f"{code:#06x}",
                              "draw_string_code": drawn, "draw_string_code_hex": f"{drawn:#06x}",
                              "glyph": {lang: lookup[lang].get(drawn) for lang in ("en_us", "en_eu")}})
    out.check("convertAsciiToJis gives a code for every ASCII 0x20-0x7E", all(a["code"] for a in ascii_records),
              f"{len(ascii_records)} characters")
    out.check("drawString's '.' override equals convertAsciiToJis (only ' differs)",
              ascii_to_jis(ord("."), mapping_n, mapping_s) == DRAW_STRING_OVERRIDES["."],
              f"' -> {ascii_to_jis(ord(chr(39)), mapping_n, mapping_s):#06x} by convertAsciiToJis, 0x8175 by drawString")
    out.write_table("ascii", {
        "table": {"name": "font/ascii", "purpose": TABLE_PURPOSES["ascii"]},
        "source": source_of(special, {"function": f"{SJIS_C} convertAsciiToJis", "overrides": f"{FONT_C} drawString"}),
        "schema": {"ascii": {"meaning": "ASCII byte"}, "char": {"derived": "the character"},
                   "code": {"meaning": "convertAsciiToJis(ascii): full-width Shift-JIS code (battle-end box, "
                                       "drawString2, EU text)"},
                   "draw_string_code": {"meaning": "US drawString: '.' -> 0x8142 and ' -> 0x8175 (「), else code"},
                   "glyph": {"meaning": "index of draw_string_code in font/en_us and font/en_eu; null = drawn as the "
                                        "sentinel glyph"}},
        "records": ascii_records,
        "c": {"CHAR_MAPPING_NORMAL": mapping_n, "CHAR_MAPPING_SPECIAL": mapping_s},
        "used_by": tables.used_by(decomp, refs["CHAR_MAPPING_NORMAL"] + refs["CHAR_MAPPING_SPECIAL"], [], special),
        "godot": {"status": "implemented (scripts/data/game_data.gd)", "access": "GameData.font_ascii() -> records",
                  "notes": "PsxFont encodes ASCII through draw_string_code (drawString) or code (drawString2)."},
    }, symbols=["CHAR_MAPPING_NORMAL", "CHAR_MAPPING_SPECIAL"])

    # -- coverage of the game's own text ----------------------------------------------------------
    missing = {lang: {} for lang in LANGUAGES}
    for key, language, text in _text_strings(decomp):
        chars = []
        for ch in NOT_DRAWN[language].sub("", text):
            code = draw_code(ch, language, mapping_n, mapping_s)
            if language == "en_eu" and code == SPACE:
                continue
            if (code is None or code not in lookup[language]) and ch not in chars:
                chars.append(ch)
        if chars:
            missing[language][key] = "".join(sorted(chars))
    for language in LANGUAGES:
        found, known = missing[language], KNOWN_MISSING[language]
        diff = {k: (found.get(k), known.get(k)) for k in set(found) | set(known) if found.get(k) != known.get(k)}
        out.check(f"{language}: every character of the text has a glyph, except the known ones", not diff,
                  "; ".join(f"{k}: found {f!r}, known {n!r}" for k, (f, n) in sorted(diff.items())[:5])
                  or f"{len(found)} known strings: {', '.join(sorted(set(''.join(found.values())))) or 'none'}")

    out.write_report("report.md", _report(fonts, clut_records, color_records, ascii_records, missing))
    out.finish(sources, extra={"counts": {lang: len(recs) for lang, recs in fonts.items()},
                               "missing_glyphs": missing})
    return out
