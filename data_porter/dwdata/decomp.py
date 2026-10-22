"""Read-only index of the decomp: releases, binaries, symbol addresses and code references.

- releases      include/dw/version.h: name, id, build date, region (NTSCJ / NTSCU / PAL)
- binaries      config/us/<binary>.yaml: which C file is linked into which binary (main, btl, ...)
- symbols       config/us/symbols*.txt: US RAM address (and size) of a named symbol
- references    every use of an identifier in src/**/*.c, with the enclosing function or data
                symbol and the releases whose build compiles that line (#if VERSION_... blocks)

The scope detection relies on the decomp's style (K&R-ish: a function's `{` and `}` and a
data initializer's closing `};` sit at column 0); it is a reading aid, not a C parser.
"""

import re
from pathlib import Path

from .cpp import ConditionTracker, Release

IDENT_RE = re.compile(r"[A-Za-z_]\w*")
HEADER_RE = re.compile(r"[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*\(")
DATA_RE = re.compile(r"(?:static\s+|const\s+)*[A-Za-z_][\w\s\*]*?\b([A-Za-z_]\w*)\s*(?:\[[^\]]*\]\s*)*=")
NOT_HEADERS = {"if", "for", "while", "switch", "return", "sizeof", "typedef", "struct", "union", "enum"}


def _blank_comments_and_literals(line: str, in_comment: bool) -> tuple:
    """Replace comments and string/char literals by spaces (keeps columns). Returns (code, in_comment)."""
    out = []
    i, n = 0, len(line)
    while i < n:
        if in_comment:
            end = line.find("*/", i)
            if end < 0:
                out.append(" " * (n - i))
                return "".join(out), True
            out.append(" " * (end + 2 - i))
            i, in_comment = end + 2, False
            continue
        c = line[i]
        if line.startswith("//", i):
            out.append(" " * (n - i))
            break
        if line.startswith("/*", i):
            in_comment = True
            continue
        if c in "\"'":
            j = i + 1
            while j < n and line[j] != c:
                j += 2 if line[j] == "\\" else 1
            out.append(c + " " * (min(j, n) - i - 1) + (c if j < n else ""))
            i = j + 1
            continue
        out.append(c)
        i += 1
    return "".join(out), in_comment


class Decomp:
    def __init__(self, root: Path):
        self.root = Path(root)
        self._releases = None
        self._binaries = None
        self._symbols = {}

    def rel(self, path: Path) -> str:
        return Path(path).resolve().relative_to(self.root.resolve()).as_posix()

    def exists(self) -> bool:
        return (self.root / "include" / "dw" / "version.h").is_file()

    # -- releases ---------------------------------------------------------------------------

    @property
    def releases(self) -> dict:
        """{name: Release} in VERSION_ID order (jp, jp_trial, jp_bombom, us, jp_rev1, eu)."""
        if self._releases is None:
            text = (self.root / "include" / "dw" / "version.h").read_text(encoding="utf-8")
            ids = {m.group(1): int(m.group(2)) for m in re.finditer(r"#define\s+VERSION_ID_(\w+)\s+(\d+)", text)}
            dates = {m.group(1): int(m.group(2)) for m in re.finditer(r"#define\s+VERSION_DATE_(\w+)\s+(\d+)", text)}
            regions = {m.group(1): m.group(2) for m in re.finditer(
                r"defined\(VERSION_(\w+)\)\s*\n(?:#define[^\n]*\n)*?#define\s+VERSION_REGION\s+VERSION_REGION_(\w+)", text)}
            self._releases = {name.lower(): Release(name.lower(), ids[name], dates[name], regions[name])
                              for name in sorted(ids, key=ids.get)}
        return self._releases

    # -- binaries ---------------------------------------------------------------------------

    @property
    def binaries(self) -> dict:
        """{'src/main/item.c': 'main', 'src/shop/script_menu.c': 'main', ...} from the splat configs."""
        if self._binaries is None:
            self._binaries = {}
            for cfg in sorted((self.root / "config" / "us").glob("*.yaml")):
                text = cfg.read_text(encoding="utf-8")
                name = re.search(r"^name:\s*(\S+)", text, re.M)
                src = re.search(r"^\s*src_path:\s*(\S+)", text, re.M)
                if not name or not src:
                    continue
                for m in re.finditer(r"-\s*\[\s*0x[0-9A-Fa-f]+\s*,\s*c\s*,\s*([^\],]+?)\s*\]", text):
                    path = (Path(src.group(1)) / (m.group(1) + ".c")).as_posix()
                    parts = []
                    for p in path.split("/"):
                        if p == "..":
                            parts.pop()
                        elif p != ".":
                            parts.append(p)
                    self._binaries["/".join(parts)] = name.group(1)
        return self._binaries

    def binary_of(self, src_rel: str) -> str:
        """Binary a C file is linked into; files missing from the configs fall back to their folder."""
        return self.binaries.get(src_rel) or src_rel.split("/")[1]

    # -- symbols ----------------------------------------------------------------------------

    def symbols(self, binary: str) -> dict:
        """{name: {"address": "0x80124C88", "size": 10 or None}} for one binary (US)."""
        if binary not in self._symbols:
            fname = "symbols.txt" if binary == "main" else f"symbols_{binary}.txt"
            path = self.root / "config" / "us" / fname
            table = {}
            if path.is_file():
                for line in path.read_text(encoding="utf-8").splitlines():
                    m = re.match(r"\s*([A-Za-z_]\w*)\s*=\s*(0x[0-9A-Fa-f]+)\s*;(.*)", line)
                    if not m:
                        continue
                    size = re.search(r"size:\s*(0x[0-9A-Fa-f]+|\d+)", m.group(3))
                    table[m.group(1)] = {"address": "0x" + m.group(2)[2:].upper(),
                                         "size": int(size.group(1), 0) if size else None}
            self._symbols[binary] = table
        return self._symbols[binary]

    # -- references -------------------------------------------------------------------------

    def c_files(self) -> list:
        return sorted(p for p in (self.root / "src").rglob("*.c"))

    def references(self, names) -> dict:
        """{name: [ref, ...]} for every identifier in `names` used in src/**/*.c.

        ref = {"file", "line", "binary", "in": function / data symbol / macro or None,
               "kind": "function" | "data" | "macro" | None, "releases": [...], "unknown": [...]}
        `releases` lists the releases whose build compiles the line; `unknown` the ones that
        depend on macros the tracker cannot evaluate. extern declarations are skipped.
        """
        names = set(names)
        found = {n: [] for n in names}
        for path in self.c_files():
            text = path.read_text(encoding="utf-8", errors="replace")
            if not names & set(IDENT_RE.findall(text)):
                continue
            self._scan(path, text, names, found)
        return found

    def _scan(self, path: Path, text: str, names: set, found: dict) -> None:
        rel = self.rel(path)
        binary = self.binary_of(rel)
        tracker = ConditionTracker(self.releases)
        in_comment = False
        scope = None          # (kind, name) of the open function / data initializer
        pending = None        # last function header seen at column 0
        for number, raw in enumerate(text.splitlines(), 1):
            code, in_comment = _blank_comments_and_literals(raw, in_comment)
            if tracker.line(code):
                continue
            stripped = code.strip()
            line_scope = scope
            close = False
            if code.startswith("#"):
                m = re.match(r"#\s*define\s+(\w+)", code)
                line_scope = ("macro", m.group(1)) if m else None
            elif code[:1] == "{":
                if scope is None and pending:
                    scope = line_scope = ("function", pending)
                pending = None
            elif code[:1] == "}":
                close = True
            elif code[:1].isalpha() or code[:1] == "_":
                if stripped.startswith("extern "):
                    continue
                d = DATA_RE.match(code)
                h = HEADER_RE.match(code)
                if d and (not h or d.end() <= h.end()):
                    line_scope = ("data", d.group(1))
                    if "{" in code and not re.search(r"}\s*;\s*$", stripped):
                        scope = line_scope
                    pending = None
                elif h and h.group(1) not in NOT_HEADERS and not stripped.endswith(";"):
                    pending = h.group(1)
                    if stripped.endswith("{"):
                        scope = line_scope = ("function", pending)
                        pending = None
            seen = set()
            for m in IDENT_RE.finditer(code):
                if m.group(0) in names and m.group(0) not in seen:
                    seen.add(m.group(0))
                    active = tracker.active
                    ref = {"file": rel, "line": number, "binary": binary,
                           "in": line_scope[1] if line_scope else None,
                           "kind": line_scope[0] if line_scope else None,
                           "releases": [r for r, v in active.items() if v is True]}
                    unknown = [r for r, v in active.items() if v is None]
                    if unknown:
                        ref["unknown"] = unknown
                    found[m.group(0)].append(ref)
            if close:
                scope = None
