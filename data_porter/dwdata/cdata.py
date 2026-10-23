"""C data reader: struct definitions, constants and initialized tables of the decomp, per release.

The decomp builds every release from one source tree, so a table is read once per release:
the file and the headers (include/dw/*.h) are filtered by their #if VERSION_... branches
(cpp.ConditionTracker), then parsed.

- Unit       one preprocessed file: tokens tagged with the releases that compile them, #defines
- Program    the view of one C file for one release: headers + file, typedefs / structs / enums,
             object-like #defines, initialized data definitions (`Move MOVE_DATA[122] = {...};`)
- CIndex     cache of units and programs; `table(c_file, name)` gives a Loaded table per release

Values are laid out on their C type the way a C compiler does it (brace elision, zero fill of
missing trailing values, conversion to the field's width). The reader covers what the decomp's
data tables use; anything else raises CError so a converter's check fails instead of guessing.
"""

import re
from pathlib import Path

from .cpp import ConditionTracker

TOKEN_RE = re.compile(r"""
    (?P<ws>\s+)
  | (?P<str>"(?:\\.|[^"\\\n])*")
  | (?P<char>'(?:\\.|[^'\\\n])+')
  | (?P<num>0[xX][0-9a-fA-F]+[uUlL]*|(?:\d+\.\d*|\.\d+)(?:[eE][-+]?\d+)?[fF]?|\d+[uUlL]*)
  | (?P<id>[A-Za-z_]\w*)
  | (?P<punct><<=|>>=|->|\+\+|--|<<|>>|<=|>=|==|!=|&&|\|\||\#\#|[-+*/%&|^~!<>=?:;,.(){}\[\]\#])
""", re.X)

# Scalar types: name -> (size in bytes, signed).
BASE_TYPES = {
    "int8_t": (1, True), "uint8_t": (1, False), "int16_t": (2, True), "uint16_t": (2, False),
    "int32_t": (4, True), "uint32_t": (4, False), "intptr_t": (4, True), "uintptr_t": (4, False),
    "size_t": (4, False),
    "char": (1, True), "signed char": (1, True), "unsigned char": (1, False),
    "short": (2, True), "short int": (2, True), "unsigned short": (2, False), "unsigned short int": (2, False),
    "int": (4, True), "signed": (4, True), "signed int": (4, True), "unsigned": (4, False), "unsigned int": (4, False),
    "long": (4, True), "long int": (4, True), "unsigned long": (4, False), "unsigned long int": (4, False),
    "u_char": (1, False), "u_short": (2, False), "u_int": (4, False), "u_long": (4, False),
}
QUALIFIERS = {"static", "const", "volatile", "register", "extern"}
ESCAPES = {"n": "\n", "t": "\t", "r": "\r", "0": "\0", "\\": "\\", "'": "'", '"': '"', "a": "\a", "b": "\b",
           "f": "\f", "v": "\v", "?": "?"}


class CError(Exception):
    pass


class Token:
    __slots__ = ("kind", "text", "file", "line")

    def __init__(self, kind: str, text: str, file: str, line: int):
        self.kind, self.text, self.file, self.line = kind, text, file, line

    def __repr__(self):
        return f"{self.text!r}@{self.line}"


class CSymbol:
    """A value that is not a number or a string: an address, a function, an unresolved name."""

    def __init__(self, text: str):
        self.text = text

    def __eq__(self, other):
        return isinstance(other, CSymbol) and other.text == self.text

    def __hash__(self):
        return hash(self.text)

    def __repr__(self):
        return f"CSymbol({self.text})"


def unescape(literal: str) -> str:
    """C string / char literal body (without quotes) -> text."""
    out, i = [], 0
    while i < len(literal):
        c = literal[i]
        if c != "\\":
            out.append(c)
            i += 1
            continue
        n = literal[i + 1]
        if n == "x":
            m = re.match(r"[0-9a-fA-F]+", literal[i + 2:])
            out.append(chr(int(m.group(0), 16)))
            i += 2 + len(m.group(0))
        elif n in "01234567":
            m = re.match(r"[0-7]{1,3}", literal[i + 1:])
            out.append(chr(int(m.group(0), 8)))
            i += 1 + len(m.group(0))
        elif n in ESCAPES:
            out.append(ESCAPES[n])
            i += 2
        else:
            raise CError(f"unknown escape \\{n}")
    return "".join(out)


def strip_comments(text: str) -> str:
    """Replace comments by spaces, keeping newlines (line numbers) and string literals."""
    out, i, n = [], 0, len(text)
    while i < n:
        c = text[i]
        if text.startswith("//", i):
            end = text.find("\n", i)
            end = n if end < 0 else end
            out.append(" " * (end - i))
            i = end
        elif text.startswith("/*", i):
            end = text.find("*/", i + 2)
            end = n if end < 0 else end + 2
            out.append("".join(ch if ch == "\n" else " " for ch in text[i:end]))
            i = end
        elif c in "\"'":
            j = i + 1
            while j < n and text[j] != c and text[j] != "\n":
                j += 2 if text[j] == "\\" else 1
            out.append(text[i:j + 1])
            i = j + 1
        else:
            out.append(c)
            i += 1
    return "".join(out)


def tokenize(code: str, file: str, line: int) -> list:
    tokens, pos = [], 0
    while pos < len(code):
        m = TOKEN_RE.match(code, pos)
        if not m:
            raise CError(f"{file}:{line}: cannot tokenize {code[pos:pos + 20]!r}")
        kind = m.lastgroup
        if kind != "ws":
            tokens.append(Token(kind, m.group(0), file, line))
        pos = m.end()
    return tokens


class Unit:
    """One file, preprocessed for every release at once.

    tokens   [(Token, releases compiling it, releases where it depends on unknown macros)]
    defines  [(name, params or None, body tokens, line, releases, unknown releases)]
    """

    DEFINE_RE = re.compile(r"\s*#\s*define\s+([A-Za-z_]\w*)(\()?")

    def __init__(self, path: str, text: str, releases: dict):
        self.path = path
        self.tokens, self.defines = [], []
        tracker = ConditionTracker(releases)
        lines = strip_comments(text).split("\n")
        # Include guard (`#ifndef DW_MOVE_H` + `#define DW_MOVE_H` as first directives): always compiled.
        directives = [k for k, line in enumerate(lines) if line.lstrip().startswith("#")][:2]
        if len(directives) == 2:
            g = re.match(r"\s*#\s*ifndef\s+(\w+)\s*$", lines[directives[0]])
            if g and re.match(rf"\s*#\s*define\s+{g.group(1)}\b", lines[directives[1]]):
                lines[directives[0]] = "#if 1"
        i = 0
        while i < len(lines):
            number, code = i + 1, lines[i]
            while code.endswith("\\") and i + 1 < len(lines):
                i += 1
                code = code[:-1] + " " + lines[i]
            i += 1
            if tracker.line(code):
                continue
            active = tracker.active
            on = frozenset(r for r, v in active.items() if v is True)
            unknown = frozenset(r for r, v in active.items() if v is None)
            if code.lstrip().startswith("#"):
                m = self.DEFINE_RE.match(code)
                if m:
                    rest = code[m.end():]
                    params = None
                    if m.group(2):
                        close = rest.index(")")
                        params = [p.strip() for p in rest[:close].split(",") if p.strip()]
                        rest = rest[close + 1:]
                    self.defines.append((m.group(1), params, tokenize(rest, path, number), number, on, unknown))
                continue
            for tok in tokenize(code, path, number):
                self.tokens.append((tok, on, unknown))

    def view(self, release: str) -> list:
        return [t for t, on, _ in self.tokens if release in on]

    def unknown_lines(self, release: str) -> set:
        return {t.line for t, _, unk in self.tokens if release in unk}


# -- types ------------------------------------------------------------------------------------

class Scalar:
    def __init__(self, name: str, size: int, signed: bool):
        self.name, self.size, self.signed = name, size, signed

    def describe(self) -> str:
        return self.name


class Pointer:
    def __init__(self, target: str):
        self.target = target

    def describe(self) -> str:
        return self.target + " *"


class Array:
    def __init__(self, elem, n):
        self.elem, self.n = elem, n

    def describe(self) -> str:
        dims, ty = [], self
        while isinstance(ty, Array):
            dims.append(f"[{'' if ty.n is None else ty.n}]")
            ty = ty.elem
        return ty.describe() + "".join(dims)


class Struct:
    def __init__(self, name: str, fields: list, union: bool = False, file: str = None, line: int = None):
        self.name, self.fields, self.union, self.file, self.line = name, fields, union, file, line

    def describe(self) -> str:
        return self.name


class Field:
    def __init__(self, name: str, type_, bits=None):
        self.name, self.type, self.bits = name, type_, bits


def sizeof(ty) -> int:
    """Size in bytes with MIPS (PSX) alignment: every type aligned to its largest scalar, pointers 4."""
    if isinstance(ty, Scalar):
        return ty.size
    if isinstance(ty, Pointer):
        return 4
    if isinstance(ty, Array):
        if ty.n is None:
            raise CError(f"sizeof unsized {ty.describe()}")
        return ty.n * sizeof(ty.elem)
    if any(f.bits is not None for f in ty.fields):
        raise CError(f"sizeof {ty.name}: bit fields not supported")
    align = alignof(ty)
    if ty.union:
        size = max(sizeof(f.type) for f in ty.fields)
    else:
        size = 0
        for f in ty.fields:
            a = alignof(f.type)
            size = (size + a - 1) // a * a + sizeof(f.type)
    return (size + align - 1) // align * align


def alignof(ty) -> int:
    if isinstance(ty, Scalar):
        return ty.size
    if isinstance(ty, Pointer):
        return 4
    if isinstance(ty, Array):
        return alignof(ty.elem)
    return max((alignof(f.type) for f in ty.fields), default=1)


def _is_char_array(ty) -> bool:
    return isinstance(ty, Array) and isinstance(ty.elem, Scalar) and ty.elem.size == 1


def _zero(ty):
    if isinstance(ty, Struct):
        return {f.name: _zero(f.type) for f in (ty.fields[:1] if ty.union else ty.fields)}
    if isinstance(ty, Array):
        if _is_char_array(ty):
            return ""
        return [_zero(ty.elem) for _ in range(ty.n or 0)]
    if isinstance(ty, Pointer):
        return None
    return 0


# -- initializer nodes ------------------------------------------------------------------------

class Braced:
    def __init__(self, items: list, line: int):
        self.items, self.line = items, line   # items: [(designator or None, node)]


class Expr:
    def __init__(self, tokens: list, line: int):
        self.tokens, self.line = tokens, line


class Value:
    """An already-known value (from a macro hook); sits in token lists, so it has a token-like `text`."""

    text = "<value>"

    def __init__(self, value, line: int):
        self.value, self.line = value, line


class Decl:
    def __init__(self, name, type_tokens, pointers, dims, init, file, line):
        self.name, self.type_tokens, self.pointers, self.dims = name, type_tokens, pointers, dims
        self.init, self.file, self.line = init, file, line   # init: tokens between '=' and ';'


def _match(tokens: list, i: int) -> int:
    """Index of the bracket closing tokens[i]."""
    pairs = {"{": "}", "(": ")", "[": "]"}
    want, depth = pairs[tokens[i].text], 0
    for j in range(i, len(tokens)):
        t = tokens[j].text
        if t == tokens[i].text:
            depth += 1
        elif t == want:
            depth -= 1
            if depth == 0:
                return j
    raise CError(f"{tokens[i].file}:{tokens[i].line}: unbalanced {tokens[i].text!r}")


def _split(tokens: list, sep: str) -> list:
    """Split at `sep` outside brackets."""
    parts, cur, depth = [], [], 0
    for t in tokens:
        if t.text in "({[":
            depth += 1
        elif t.text in ")}]":
            depth -= 1
        if t.text == sep and depth == 0:
            parts.append(cur)
            cur = []
        else:
            cur.append(t)
    if cur:
        parts.append(cur)
    return parts


def statements(tokens: list) -> list:
    """Top-level statements; function bodies and blocks are dropped."""
    out, cur, i = [], [], 0
    while i < len(tokens):
        t = tokens[i]
        if t.text == "{":
            j = _match(tokens, i)
            if not cur or cur[-1].text == ")":
                # function body, or a bare block (K&R bodies: `f(a) int a; {` ends its header at ';')
                cur = []
                i = j + 1
                continue
            cur.extend(tokens[i:j + 1])
            i = j + 1
            continue
        if t.text == ";":
            if cur:
                out.append(cur)
            cur = []
        else:
            cur.append(t)
        i += 1
    if cur:
        out.append(cur)
    return out


def _sdk_structs() -> dict:
    """PSY-Q SDK types used in the decomp's structs (libgte / libgpu layouts); the SDK headers aren't in the decomp."""
    s16, s32, u8 = Scalar("int16_t", 2, True), Scalar("int32_t", 4, True), Scalar("uint8_t", 1, False)

    def st(name, fields):
        return Struct(name, [Field(n, t) for n, t in fields], file="PSY-Q SDK")
    return {
        "VECTOR": st("VECTOR", [("vx", s32), ("vy", s32), ("vz", s32), ("pad", s32)]),
        "SVECTOR": st("SVECTOR", [("vx", s16), ("vy", s16), ("vz", s16), ("pad", s16)]),
        "DVECTOR": st("DVECTOR", [("vx", s16), ("vy", s16)]),
        "CVECTOR": st("CVECTOR", [("r", u8), ("g", u8), ("b", u8), ("cd", u8)]),
        "RECT": st("RECT", [("x", s16), ("y", s16), ("w", s16), ("h", s16)]),
        "MATRIX": st("MATRIX", [("m", Array(Array(s16, 3), 3)), ("t", Array(s32, 3))]),
    }


class Program:
    """One C file seen by one release: its own declarations plus the headers'.

    With `base` (a Program of the headers alone), the headers' declarations are copied from it
    instead of being parsed again.
    """

    def __init__(self, release: str, units: list, main, hooks: dict = None, base=None):
        self.release = release
        self.main = main
        self.hooks = hooks or {}
        self.defines = {}      # name -> (params, tokens)
        self.enums = {}        # name -> int
        self.typedefs = {}     # name -> type
        self.structs = dict(_sdk_structs())   # 'struct Tag' / typedef name -> Struct
        self.data = {}         # name -> Decl (main unit only)
        self.issues = []
        if base is not None:
            for attr in ("defines", "enums", "typedefs", "structs"):
                getattr(self, attr).update(getattr(base, attr))
            units = []
        own = units + ([main] if main is not None else [])
        for unit in own:
            for name, params, body, _, on, _ in unit.defines:
                if release in on:
                    self.defines[name] = (params, body)
        # Headers use types of headers read later: retry failed declarations until nothing changes.
        pending = [(st, unit is main) for unit in own for st in statements(unit.view(release))]
        while pending:
            failed = []
            for st, is_main in pending:
                try:
                    self._statement(st, is_main)
                except CError as e:
                    failed.append((st, is_main, str(e)))
            if len(failed) == len(pending):
                self.issues += [e for _, _, e in failed]
                break
            pending = [(st, m) for st, m, _ in failed]

    # -- declarations -------------------------------------------------------------------------

    def _statement(self, st: list, is_main: bool) -> None:
        texts = [t.text for t in st]
        if texts[0] == "typedef":
            self._typedef(st[1:])
        elif texts[0] in ("struct", "union") and len(st) > 2 and texts[2] == "{" and texts[-1] == "}":
            self._struct(st, None)
        elif texts[0] == "enum" and "{" in texts:
            self._enum(st)
        elif is_main and "=" in texts:
            self._data(st)

    def _typedef(self, st: list) -> None:
        texts = [t.text for t in st]
        if texts[0] in ("struct", "union") and "{" in texts:
            body_end = _match(st, texts.index("{"))
            names = [t.text for t in st[body_end + 1:] if t.kind == "id"]
            ty = self._struct(st[:body_end + 1], names[0] if names else None)
            for n in names:
                self.structs[n] = ty
                self.typedefs[n] = ty
        elif texts[0] == "enum" and "{" in texts:
            self._enum(st)
            for t in st[_match(st, texts.index("{")) + 1:]:
                if t.kind == "id":
                    self.typedefs[t.text] = Scalar(t.text, 4, True)
        elif "(" not in texts and st[-1].kind == "id":
            pointers = texts.count("*")
            base = [t for t in st[:-1] if t.text != "*"]
            try:
                ty = self.type_of(base, pointers, [])
            except CError:
                return  # alias of a type we don't know (SDK types, function types): ignored
            self.typedefs[st[-1].text] = ty

    def _struct(self, st: list, name):
        texts = [t.text for t in st]
        union = texts[0] == "union"
        open_ = texts.index("{")
        tag = texts[1] if open_ == 2 else None
        fields = []
        for decl in _split(st[open_ + 1:_match(st, open_)], ";"):
            fields += self._fields(decl)
        ty = Struct(name or (f"struct {tag}" if tag else "<anonymous>"), fields, union, st[0].file, st[0].line)
        if tag:
            self.structs[f"{'union' if union else 'struct'} {tag}"] = ty
        return ty

    def _fields(self, decl: list) -> list:
        texts = [t.text for t in decl]
        if not decl:
            return []
        if texts[0] in ("struct", "union") and "{" in texts:
            end = _match(decl, texts.index("{"))
            inner = self._struct(decl[:end + 1], None)
            out = []
            for d in _split(decl[end + 1:], ","):
                out.append(self._declarator(d, inner))
            return out or [Field(None, inner)]
        if "(" in texts:
            # function pointer field: `void (*func)(int);`
            names = [t.text for t in decl if t.kind == "id"]
            star = texts.index("*") if "*" in texts else None
            name = decl[star + 1].text if star is not None else names[-1]
            return [Field(name, Pointer("function"))]
        # `type a, *b, c[3];`: the first declarator's name is the identifier followed by '[', ':' or the end
        parts = _split(decl, ",")
        first = parts[0]
        name_idx = next((k for k, t in enumerate(first)
                         if t.kind == "id" and (k + 1 == len(first) or first[k + 1].text in ("[", ":"))), None)
        if name_idx is None:
            raise CError(f"{decl[0].file}:{decl[0].line}: cannot read field {' '.join(texts)}")
        base = [t for t in first[:name_idx] if t.text != "*" and t.text not in QUALIFIERS]
        stars = sum(1 for t in first[:name_idx] if t.text == "*")
        out = [self._declarator(first[name_idx:], None, base, stars)]
        for d in parts[1:]:
            out.append(self._declarator(d, None, base))
        return out

    def _declarator(self, d: list, inner=None, base=None, pointers=0) -> Field:
        d = [t for t in d if t.text not in QUALIFIERS]
        while d and d[0].text == "*":
            pointers += 1
            d = d[1:]
        if not d or d[0].kind != "id":
            raise CError(f"bad declarator {' '.join(t.text for t in d)}")
        name, dims, bits, k = d[0].text, [], None, 1
        while k < len(d):
            if d[k].text == "[":
                j = _match(d, k)
                dims.append(self.eval_int(d[k + 1:j]) if j > k + 1 else None)
                k = j + 1
            elif d[k].text == ":":
                bits = self.eval_int(d[k + 1:])
                break
            else:
                raise CError(f"{d[k].file}:{d[k].line}: unexpected {d[k].text!r} in declarator")
        if inner is not None:
            ty = inner if not pointers else Pointer(inner.name)
            for n in reversed(dims):
                ty = Array(ty, n)
        else:
            ty = self.type_of(base, pointers, dims)
        return Field(name, ty, bits)

    def _enum(self, st: list) -> None:
        texts = [t.text for t in st]
        open_ = texts.index("{")
        value = 0
        for item in _split(st[open_ + 1:_match(st, open_)], ","):
            if not item:
                continue
            if len(item) > 1 and item[1].text == "=":
                value = self.eval_int(item[2:])
            self.enums[item[0].text] = value
            value += 1

    def _data(self, st: list) -> None:
        texts = [t.text for t in st]
        eq = texts.index("=")
        head = st[:eq]
        if "(" in [t.text for t in head] or not head:
            return  # function pointer tables etc.: not supported yet
        name_idx = None
        for k, t in enumerate(head):
            if t.kind == "id" and (k + 1 == len(head) or head[k + 1].text == "["):
                name_idx = k
                break
        if name_idx is None or any(t.text == "extern" for t in head):
            return
        dims, k = [], name_idx + 1
        while k < len(head) and head[k].text == "[":
            j = _match(head, k)
            dims.append(head[k + 1:j])
            k = j + 1
        type_tokens = [t for t in head[:name_idx] if t.text not in QUALIFIERS and t.text != "*"]
        pointers = sum(1 for t in head[:name_idx] if t.text == "*")
        name = head[name_idx].text
        self.data[name] = Decl(name, type_tokens, pointers, dims, st[eq + 1:], head[name_idx].file,
                               head[name_idx].line)

    # -- types --------------------------------------------------------------------------------

    def type_of(self, base_tokens: list, pointers: int, dims: list):
        texts = [t.text for t in base_tokens if t.text not in QUALIFIERS]
        key = " ".join(texts)
        if pointers:
            ty = Pointer(key)
        elif key in BASE_TYPES:
            ty = Scalar(key, *BASE_TYPES[key])
        elif key in self.typedefs:
            ty = self.typedefs[key]
        elif key in self.structs:
            ty = self.structs[key]
        else:
            raise CError(f"unknown type {key!r}")
        for n in reversed(dims):
            if isinstance(n, list):
                n = self.eval_int(n) if n else None
            ty = Array(ty, n)
        return ty

    def decl_type(self, decl: Decl):
        # Generated macros that expand to declarations (`MOVE_NAMES_TEXT`, from text headers the
        # decomp doesn't ship) end without ';', so they prefix the next declaration: skip them.
        for k in range(len(decl.type_tokens)):
            try:
                return self.type_of(decl.type_tokens[k:], decl.pointers, decl.dims)
            except CError:
                if k == len(decl.type_tokens) - 1:
                    raise
        return self.type_of(decl.type_tokens, decl.pointers, decl.dims)

    # -- expressions --------------------------------------------------------------------------

    def constant(self, name: str, seen=()):
        if name in self.enums:
            return self.enums[name]
        if name in self.defines and self.defines[name][0] is None and name not in seen:
            return self.evaluate(self.defines[name][1], seen + (name,))
        raise _Unresolved(name)

    def eval_int(self, tokens: list) -> int:
        v = self.evaluate(tokens)
        if not isinstance(v, int):
            raise CError(f"not an integer constant: {' '.join(t.text for t in tokens)}")
        return v

    def evaluate(self, tokens: list, seen=()):
        """Value of a constant expression: int, str (string literal) or CSymbol (address / unknown name)."""
        if not tokens:
            raise CError("empty expression")
        try:
            parser = _ExprParser(self, tokens, seen)
            v = parser.parse()
            if parser.pos != len(tokens):
                raise CError(f"{tokens[0].file}:{tokens[0].line}: cannot evaluate "
                             f"{' '.join(t.text for t in tokens)}")
            return v
        except _Unresolved:
            return CSymbol(_join(tokens))

    # -- initializers -------------------------------------------------------------------------

    def parse_init(self, tokens: list):
        tokens = self._expand(tokens)
        node, pos = self._init_node(tokens, 0)
        if pos != len(tokens):
            t = tokens[pos]
            raise CError(f"{t.file}:{t.line}: unexpected {t.text!r} after initializer")
        return node

    def _expand(self, tokens: list) -> list:
        """Apply the caller's macro hooks: NAME(args) -> list of tokens / Value nodes."""
        out, i = [], 0
        while i < len(tokens):
            t = tokens[i]
            if t.kind == "id" and t.text in self.hooks and i + 1 < len(tokens) and tokens[i + 1].text == "(":
                j = _match(tokens, i + 1)
                args = [_join(a) for a in _split(tokens[i + 2:j], ",")]
                for v in self.hooks[t.text](args, self.release, t):
                    out.append(v)
                i = j + 1
                continue
            out.append(t)
            i += 1
        return out

    def _init_node(self, tokens: list, pos: int):
        t = tokens[pos]
        if isinstance(t, Value):
            return t, pos + 1
        if t.text == "{":
            end = _match(tokens, pos)
            items, i = [], pos + 1
            while i < end:
                designator = None
                if tokens[i].text == "." and tokens[i + 2].text == "=":
                    designator = tokens[i + 1].text
                    i += 3
                elif tokens[i].text == "[":
                    j = _match(tokens, i)
                    if tokens[j + 1].text == "=":
                        designator = self.eval_int(tokens[i + 1:j])
                        i = j + 2
                node, i = self._init_node(tokens, i)
                items.append((designator, node))
                if i < end and isinstance(tokens[i], Token) and tokens[i].text == ",":
                    i += 1
                elif i < end and not isinstance(tokens[i - 1], Value):
                    raise CError(f"{tokens[i].file}:{tokens[i].line}: expected ',' got {tokens[i].text!r}")
            return Braced(items, t.line), end + 1
        # expression up to ',' or the closing brace
        depth, i = 0, pos
        while i < len(tokens):
            x = tokens[i]
            if isinstance(x, Value):
                break
            if x.text in "([":
                depth += 1
            elif x.text in ")]":
                depth -= 1
            elif depth == 0 and x.text in (",", "}"):
                break
            i += 1
        return Expr(tokens[pos:i], t.line), i

    def build(self, ty, node, ctx):
        """Lay an initializer node out on type `ty` (C semantics)."""
        if isinstance(node, Value):
            return self._scalar(ty, node.value, ctx, node.line) if isinstance(ty, (Scalar, Pointer)) else node.value
        if isinstance(ty, Array) and _is_char_array(ty):
            inner = node.items[0][1] if isinstance(node, Braced) and len(node.items) == 1 else node
            if isinstance(inner, Expr):
                v = self.evaluate(inner.tokens)
                if isinstance(v, str):
                    # Length is not checked: the source is UTF-8, the game stores Shift-JIS.
                    return v
        if isinstance(ty, (Array, Struct)):
            if not isinstance(node, Braced):
                raise CError(f"line {node.line}: {ty.describe()} needs a braced initializer")
            value, pos = self._fill(ty, node.items, 0, ctx, node.line)
            if pos != len(node.items):
                ctx.issue(node.line, f"{len(node.items) - pos} excess values for {ty.describe()}")
            return value
        if isinstance(node, Braced):
            if len(node.items) != 1:
                raise CError(f"line {node.line}: braced scalar with {len(node.items)} values")
            node = node.items[0][1]
        return self._scalar(ty, self.evaluate(node.tokens), ctx, node.line)

    def _takes_whole(self, ty, node) -> bool:
        if isinstance(node, (Braced, Value)) or isinstance(ty, (Scalar, Pointer)):
            return True
        if _is_char_array(ty) and isinstance(node, Expr):
            return isinstance(self.evaluate(node.tokens), str)
        return False

    def _fill(self, ty, items: list, pos: int, ctx, line: int):
        if isinstance(ty, Array):
            out = []
            while (ty.n is None and pos < len(items)) or (ty.n is not None and len(out) < ty.n):
                if pos >= len(items):
                    ctx.implicit += 1
                    out.append(_zero(ty.elem))
                    continue
                designator, node = items[pos]
                if designator is not None:
                    if not isinstance(designator, int) or designator < len(out):
                        raise CError(f"line {node.line}: unsupported array designator {designator!r}")
                    while len(out) < designator:
                        ctx.implicit += 1
                        out.append(_zero(ty.elem))
                if self._takes_whole(ty.elem, node):
                    out.append(self.build(ty.elem, node, ctx))
                    pos += 1
                else:
                    v, pos = self._fill(ty.elem, items, pos, ctx, node.line)
                    out.append(v)
            return out, pos
        if isinstance(ty, Struct):
            fields = ty.fields[:1] if ty.union else ty.fields
            out, k = {}, 0
            while k < len(fields):
                f = fields[k]
                if pos >= len(items):
                    ctx.implicit += 1
                    out[f.name] = _zero(f.type)
                    k += 1
                    continue
                designator, node = items[pos]
                if designator is not None:
                    names = [x.name for x in fields]
                    if not isinstance(designator, str) or designator not in names:
                        raise CError(f"line {node.line}: unknown field designator {designator!r}")
                    target = names.index(designator)
                    if target < k:
                        raise CError(f"line {node.line}: field designator {designator!r} goes backwards")
                    while k < target:
                        ctx.implicit += 1
                        out[fields[k].name] = _zero(fields[k].type)
                        k += 1
                    f = fields[k]
                if self._takes_whole(f.type, node):
                    out[f.name] = self.build(f.type, node, ctx)
                    pos += 1
                else:
                    out[f.name], pos = self._fill(f.type, items, pos, ctx, node.line)
                k += 1
            return out, pos
        # scalar reached through elision
        _, node = items[pos]
        return self.build(ty, node, ctx), pos + 1

    def _scalar(self, ty, v, ctx, line):
        if isinstance(ty, Pointer):
            if isinstance(v, int) and v == 0:
                return None
            return v.text if isinstance(v, CSymbol) else v
        if isinstance(v, CSymbol):
            ctx.issue(line, f"{ty.describe()} initialized with non-constant {v.text}")
            return v.text
        if isinstance(v, str):
            ctx.issue(line, f"{ty.describe()} initialized with a string")
            return v
        if isinstance(v, float):
            return v
        bits = ty.size * 8
        if not -(1 << (bits - 1)) <= v < (1 << bits):
            ctx.issue(line, f"{v} does not fit {ty.name}")
            return v
        stored = v & ((1 << bits) - 1)
        if ty.signed and stored >= 1 << (bits - 1):
            stored -= 1 << bits
        if stored != v:
            ctx.wrapped.append({"line": line, "written": v, "stored": stored, "type": ty.name})
        return stored


class _Unresolved(Exception):
    pass


def _join(tokens) -> str:
    out = ""
    for t in tokens:
        text = t.text if isinstance(t, Token) else str(t)
        if out and (out[-1].isalnum() or out[-1] == "_") and (text[0].isalnum() or text[0] == "_"):
            out += " "
        out += text
    return out


def _cdiv(a, b):
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


class _ExprParser:
    BINARY = {"||": 1, "&&": 2, "|": 3, "^": 4, "&": 5, "==": 6, "!=": 6, "<": 7, ">": 7, "<=": 7, ">=": 7,
              "<<": 8, ">>": 8, "+": 9, "-": 9, "*": 10, "/": 10, "%": 10}

    def __init__(self, program: Program, tokens: list, seen):
        self.p, self.toks, self.pos, self.seen = program, tokens, 0, seen

    def peek(self):
        return self.toks[self.pos].text if self.pos < len(self.toks) else None

    def parse(self, min_prec=1):
        left = self.unary()
        while True:
            op = self.peek()
            prec = self.BINARY.get(op)
            if prec is None or prec < min_prec:
                return left
            self.pos += 1
            right = self.parse(prec + 1)
            left = self.apply(op, left, right)

    def apply(self, op, a, b):
        if isinstance(a, str) or isinstance(b, str):
            raise CError(f"operator {op} on a string")
        ops = {"+": lambda: a + b, "-": lambda: a - b, "*": lambda: a * b,
               "/": lambda: _cdiv(a, b), "%": lambda: a - _cdiv(a, b) * b,
               "<<": lambda: a << b, ">>": lambda: a >> b, "&": lambda: a & b, "|": lambda: a | b,
               "^": lambda: a ^ b, "==": lambda: int(a == b), "!=": lambda: int(a != b), "<": lambda: int(a < b),
               ">": lambda: int(a > b), "<=": lambda: int(a <= b), ">=": lambda: int(a >= b),
               "&&": lambda: int(bool(a) and bool(b)), "||": lambda: int(bool(a) or bool(b))}
        return ops[op]()

    def _is_cast(self) -> bool:
        if self.peek() != "(":
            return False
        j = self.pos + 1
        words = []
        while j < len(self.toks) and self.toks[j].text != ")":
            words.append(self.toks[j].text)
            j += 1
        names = [w for w in words if w != "*" and w not in QUALIFIERS]
        key = " ".join(names)
        return bool(names) and (key in BASE_TYPES or key in self.p.typedefs or key in self.p.structs)

    def unary(self):
        t = self.peek()
        if t is None:
            raise CError("unexpected end of expression")
        if t in ("-", "+", "~", "!"):
            self.pos += 1
            v = self.unary()
            if isinstance(v, str):
                raise CError(f"operator {t} on a string")
            return {"-": -v, "+": v, "~": ~v, "!": int(not v)}[t]
        if t == "&":
            raise _Unresolved("&")
        if t == "sizeof":
            raise CError("sizeof is not supported")
        if self._is_cast():
            self.pos = next(j for j in range(self.pos, len(self.toks)) if self.toks[j].text == ")") + 1
            return self.unary()
        return self.primary()

    def primary(self):
        tok = self.toks[self.pos]
        self.pos += 1
        if tok.text == "(":
            v = self.parse()
            if self.peek() != ")":
                raise CError("missing )")
            self.pos += 1
            return v
        if tok.kind == "num":
            text = tok.text.rstrip("uUlL")
            if re.search(r"[.eE]", text) and not text.lower().startswith("0x"):
                return float(text.rstrip("fF"))
            return int(text, 0) if not re.fullmatch(r"0\d+", text) else int(text, 8)
        if tok.kind == "char":
            s = unescape(tok.text[1:-1])
            return ord(s) if len(s) == 1 else int.from_bytes(s.encode("latin-1"), "big")
        if tok.kind == "str":
            s = unescape(tok.text[1:-1])
            while self.pos < len(self.toks) and self.toks[self.pos].kind == "str":
                s += unescape(self.toks[self.pos].text[1:-1])
                self.pos += 1
            return s
        if tok.kind == "id":
            if self.peek() in ("(", "[", ".", "->"):
                raise _Unresolved(tok.text)
            return self.p.constant(tok.text, self.seen)
        raise CError(f"{tok.file}:{tok.line}: unexpected {tok.text!r} in expression")


# -- index ------------------------------------------------------------------------------------

class Loaded:
    """One table as one release compiles it."""

    def __init__(self, release, decl, type_, value, element_lines, issues, wrapped, implicit, unknown_lines):
        self.release, self.decl, self.type, self.value = release, decl, type_, value
        self.element_lines = element_lines   # source line of each top-level element (or None)
        self.issues, self.wrapped, self.implicit, self.unknown_lines = issues, wrapped, implicit, unknown_lines


class _Ctx:
    def __init__(self, file):
        self.file, self.issues, self.wrapped, self.implicit = file, [], [], 0

    def issue(self, line, message):
        self.issues.append(f"{self.file}:{line}: {message}")


class CIndex:
    HEADER_GLOB = "include/dw/*.h"

    def __init__(self, decomp):
        self.decomp = decomp
        self.releases = decomp.releases
        self._units = {}
        self._bases = {}

    def unit(self, rel: str) -> Unit:
        if rel not in self._units:
            text = (self.decomp.root / rel).read_text(encoding="utf-8", errors="replace")
            self._units[rel] = Unit(rel, text, self.releases)
        return self._units[rel]

    def headers(self) -> list:
        return [self.unit(self.decomp.rel(p)) for p in sorted(self.decomp.root.glob(self.HEADER_GLOB))]

    def base(self, release: str) -> Program:
        """The headers alone, for one release (cached)."""
        if release not in self._bases:
            self._bases[release] = Program(release, self.headers(), None)
        return self._bases[release]

    def program(self, c_rel: str, release: str, hooks: dict = None) -> Program:
        return Program(release, [], self.unit(c_rel), hooks, base=self.base(release))

    def table(self, c_rel: str, name: str, hooks: dict = None) -> dict:
        """{release: Loaded or None (not defined in that release)}; raises CError on parse errors."""
        out = {}
        for release in self.releases:
            prog = self.program(c_rel, release, hooks)
            decl = prog.data.get(name)
            if decl is None:
                out[release] = None
                continue
            ty = prog.decl_type(decl)
            node = prog.parse_init(decl.init)
            ctx = _Ctx(c_rel)
            value = prog.build(ty, node, ctx)
            lines = None
            if isinstance(ty, Array) and isinstance(node, Braced) and isinstance(value, list) \
                    and len(node.items) == len(value):
                lines = [n.line for _, n in node.items]
            span = {decl.line} | {t.line for t in decl.init if isinstance(t, Token)}
            first, last = min(span), max(span)
            unknown = sorted(n for n in self.unit(c_rel).unknown_lines(release) if first <= n <= last)
            out[release] = Loaded(release, decl, ty, value, lines, ctx.issues, ctx.wrapped, ctx.implicit, unknown)
        return out

    def struct_source(self, c_rel: str, release: str, type_name: str):
        """(file, line) of a struct definition."""
        ty = self.program(c_rel, release).structs.get(type_name)
        return (ty.file, ty.line) if ty else (None, None)


def describe_type(ty) -> list:
    """Schema-friendly description of a struct's fields: [{"c_name", "c_type", "bits"?}]."""
    if not isinstance(ty, Struct):
        return [{"c_type": ty.describe()}]
    out = []
    for f in ty.fields:
        d = {"c_name": f.name, "c_type": f.type.describe()}
        if f.bits is not None:
            d["bits"] = f.bits
        out.append(d)
    return out
