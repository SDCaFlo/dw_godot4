"""Reader for the YAML subset used by the decomp's text/**/*.yaml files.

Supported: block mappings and sequences (space indentation), `- key: value` items,
flow mappings / sequences of scalars (`{eu: 2}`, `[eu]`), plain, double-quoted
(YAML escapes such as `\\0`) and single-quoted scalars, `#` comments.

Unlike full YAML, every scalar stays a string (`20`, `Yes` are text): only the plain
scalar `NULL` becomes None, which is how the decomp marks a text that does not exist.
Anything outside the subset (tabs, block scalars, anchors, multi-line plain scalars,
duplicate keys) raises YamlError instead of being guessed. Every node keeps its line.
"""

import re

KEY_RE = re.compile(r"[A-Za-z0-9_@.]+")
DQ_ESCAPES = {"0": "\0", "a": "\a", "b": "\b", "t": "\t", "n": "\n", "v": "\v", "f": "\f", "r": "\r",
              "e": "\x1b", " ": " ", '"': '"', "/": "/", "\\": "\\", "N": "\x85", "_": "\xa0"}
DQ_HEX = {"x": 2, "u": 4, "U": 8}


class YamlError(ValueError):
    def __init__(self, path: str, line: int, message: str):
        super().__init__(f"{path}:{line}: {message}")
        self.path, self.line = path, line


class Scalar:
    def __init__(self, value, line: int, style: str):
        self.value, self.line, self.style = value, line, style  # style: plain / double / single

    def __repr__(self):
        return f"Scalar({self.value!r}@{self.line})"


class Seq:
    def __init__(self, items: list, line: int):
        self.items, self.line = items, line

    def __repr__(self):
        return f"Seq({self.items!r}@{self.line})"


class Map:
    def __init__(self, line: int):
        self.line = line
        self.entries = {}     # key -> node (insertion order = file order)
        self.key_lines = {}   # key -> line of the key

    def get(self, key, default=None):
        return self.entries.get(key, default)

    def keys(self):
        return list(self.entries)

    def items(self):
        return self.entries.items()

    def __contains__(self, key):
        return key in self.entries

    def __repr__(self):
        return f"Map({self.entries!r}@{self.line})"


def to_python(node):
    """Plain Python value of a node (dict / list / str / None), without line numbers."""
    if isinstance(node, Map):
        return {k: to_python(v) for k, v in node.items()}
    if isinstance(node, Seq):
        return [to_python(v) for v in node.items]
    return node.value


class _Line:
    __slots__ = ("indent", "text", "number")

    def __init__(self, indent, text, number):
        self.indent, self.text, self.number = indent, text, number


def _strip_comment(raw: str, path: str, number: int) -> str:
    quote = None
    i = 0
    while i < len(raw):
        c = raw[i]
        if quote == '"':
            if c == "\\":
                i += 1
            elif c == '"':
                quote = None
        elif quote == "'":
            if c == "'":
                if i + 1 < len(raw) and raw[i + 1] == "'":
                    i += 1
                else:
                    quote = None
        elif c in "\"'" and (i == 0 or raw[i - 1] in " \t:-[{,"):
            quote = c
        elif c == "#" and (i == 0 or raw[i - 1] in " \t"):
            return raw[:i].rstrip()
        i += 1
    if quote:
        raise YamlError(path, number, "unterminated quoted scalar")
    return raw.rstrip()


def _lines(text: str, path: str) -> list:
    out = []
    for number, raw in enumerate(text.splitlines(), 1):
        if "\t" in raw[:len(raw) - len(raw.lstrip())]:
            raise YamlError(path, number, "tab in indentation")
        body = _strip_comment(raw, path, number)
        if not body.strip():
            continue
        indent = len(body) - len(body.lstrip(" "))
        out.append(_Line(indent, body.strip(), number))
    return out


def _double_quoted(s: str, path: str, number: int) -> tuple:
    """Parse "..." at the start of s; returns (value, rest)."""
    out = []
    i = 1
    while i < len(s):
        c = s[i]
        if c == '"':
            return "".join(out), s[i + 1:]
        if c == "\\":
            i += 1
            if i >= len(s):
                break
            e = s[i]
            if e in DQ_ESCAPES:
                out.append(DQ_ESCAPES[e])
            elif e in DQ_HEX:
                digits = s[i + 1:i + 1 + DQ_HEX[e]]
                if len(digits) != DQ_HEX[e] or not all(d in "0123456789abcdefABCDEF" for d in digits):
                    raise YamlError(path, number, f"bad escape \\{e}{digits}")
                out.append(chr(int(digits, 16)))
                i += DQ_HEX[e]
            else:
                raise YamlError(path, number, f"unknown escape \\{e}")
        else:
            out.append(c)
        i += 1
    raise YamlError(path, number, "unterminated double-quoted scalar")


def _single_quoted(s: str, path: str, number: int) -> tuple:
    out = []
    i = 1
    while i < len(s):
        if s[i] == "'":
            if i + 1 < len(s) and s[i + 1] == "'":
                out.append("'")
                i += 2
                continue
            return "".join(out), s[i + 1:]
        out.append(s[i])
        i += 1
    raise YamlError(path, number, "unterminated single-quoted scalar")


def _split_flow(body: str, path: str, number: int) -> list:
    parts, depth, quote, start, i = [], 0, None, 0, 0
    while i < len(body):
        c = body[i]
        if quote:
            if c == "\\" and quote == '"':
                i += 1
            elif c == quote:
                quote = None
        elif c in "\"'":
            quote = c
        elif c in "[{":
            depth += 1
        elif c in "]}":
            depth -= 1
        elif c == "," and depth == 0:
            parts.append(body[start:i])
            start = i + 1
        i += 1
    if quote or depth:
        raise YamlError(path, number, "unbalanced flow collection")
    parts.append(body[start:])
    parts = [p.strip() for p in parts]
    if parts == [""]:
        return []
    if any(p == "" for p in parts):
        raise YamlError(path, number, "empty item in flow collection")
    return parts


def _inline(s: str, path: str, number: int):
    """A value written on the same line: scalar or flow collection."""
    s = s.strip()
    if s.startswith("{") or s.startswith("["):
        close = "}" if s[0] == "{" else "]"
        if not s.endswith(close):
            raise YamlError(path, number, "flow collection must end on the same line")
        parts = _split_flow(s[1:-1], path, number)
        if close == "]":
            return Seq([_inline(p, path, number) for p in parts], number)
        node = Map(number)
        for p in parts:
            key, rest = _split_key(p, path, number)
            if rest is None:
                raise YamlError(path, number, f"flow mapping item without value: {p!r}")
            if key in node.entries:
                raise YamlError(path, number, f"duplicate key {key!r}")
            node.entries[key] = _inline(rest, path, number)
            node.key_lines[key] = number
        return node
    if s.startswith('"'):
        value, rest = _double_quoted(s, path, number)
        if rest.strip():
            raise YamlError(path, number, f"text after quoted scalar: {rest!r}")
        return Scalar(value, number, "double")
    if s.startswith("'"):
        value, rest = _single_quoted(s, path, number)
        if rest.strip():
            raise YamlError(path, number, f"text after quoted scalar: {rest!r}")
        return Scalar(value, number, "single")
    if s[0] in "&*!|>%@`":
        raise YamlError(path, number, f"unsupported YAML syntax: {s!r}")
    if ": " in s or s.endswith(":"):
        raise YamlError(path, number, f"':' in plain scalar (quote it): {s!r}")
    return Scalar(None if s == "NULL" else s, number, "plain")


def _split_key(text: str, path: str, number: int) -> tuple:
    """'key: value' -> (key, 'value'); 'key:' -> (key, None)."""
    if text.endswith(":"):
        key, rest = text[:-1], None
    else:
        pos = text.find(": ")
        if pos < 0:
            raise YamlError(path, number, f"expected 'key: value', got {text!r}")
        key, rest = text[:pos], text[pos + 2:]
    if not KEY_RE.fullmatch(key):
        raise YamlError(path, number, f"unsupported key {key!r}")
    return key, rest


def _is_item(line: _Line) -> bool:
    return line.text == "-" or line.text.startswith("- ")


class _Parser:
    def __init__(self, text: str, path: str):
        self.path = path
        self.lines = _lines(text, path)

    def block(self, i: int, indent: int):
        if _is_item(self.lines[i]):
            return self.seq(i, indent)
        return self.map(i, indent)

    def seq(self, i: int, indent: int):
        node = Seq([], self.lines[i].number)
        while i < len(self.lines) and self.lines[i].indent == indent and _is_item(self.lines[i]):
            line = self.lines[i]
            content = line.text[1:].lstrip(" ")
            if not content:
                if i + 1 >= len(self.lines) or self.lines[i + 1].indent <= indent:
                    raise YamlError(self.path, line.number, "empty sequence item")
                item, i = self.block(i + 1, self.lines[i + 1].indent)
            elif not content.startswith(("{", "[", '"', "'")) and (": " in content or content.endswith(":")):
                # "- key: value": a mapping whose first key sits at the column after "- ".
                col = line.indent + (len(line.text) - len(content))
                self.lines[i] = _Line(col, content, line.number)
                item, i = self.map(i, col)
            else:
                item, i = _inline(content, self.path, line.number), i + 1
            node.items.append(item)
        if i < len(self.lines) and self.lines[i].indent > indent:
            raise YamlError(self.path, self.lines[i].number, "unexpected indentation")
        return node, i

    def map(self, i: int, indent: int):
        node = Map(self.lines[i].number)
        while i < len(self.lines) and self.lines[i].indent == indent and not _is_item(self.lines[i]):
            line = self.lines[i]
            key, rest = _split_key(line.text, self.path, line.number)
            if key in node.entries:
                raise YamlError(self.path, line.number, f"duplicate key {key!r}")
            if rest is not None:
                value, i = _inline(rest, self.path, line.number), i + 1
            else:
                nxt = self.lines[i + 1] if i + 1 < len(self.lines) else None
                if nxt is not None and (nxt.indent > indent or (nxt.indent == indent and _is_item(nxt))):
                    value, i = self.block(i + 1, nxt.indent)
                else:
                    raise YamlError(self.path, line.number, f"key {key!r} has no value")
            node.entries[key] = value
            node.key_lines[key] = line.number
        if i < len(self.lines) and self.lines[i].indent > indent:
            raise YamlError(self.path, self.lines[i].number, "unexpected indentation")
        return node, i


def parse(text: str, path: str = "<text>"):
    """Parse a whole document; returns its root node (a Map for the decomp's text files)."""
    parser = _Parser(text, path)
    if not parser.lines:
        return Map(1)
    first = parser.lines[0]
    if first.indent != 0:
        raise YamlError(path, first.number, "document must start at column 0")
    node, i = parser.block(0, 0)
    if i != len(parser.lines):
        raise YamlError(path, parser.lines[i].number, "unexpected content")
    return node
