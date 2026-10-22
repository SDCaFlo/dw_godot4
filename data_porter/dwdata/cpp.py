"""Minimal C preprocessor condition handling: which releases compile a given source line.

The decomp builds every release from one source tree, selecting code with
`#if VERSION_IS(EU)`, `#if !VERSION_IS(US)`, `#if VERSION_REGION_IS(PAL)`,
`#if VERSION_EQUAL_OR_NEWER(US)`, ... (include/dw/version.h). ConditionTracker
follows #if/#ifdef/#ifndef/#elif/#else/#endif line by line and tells, per release,
whether the current line is compiled: True, False, or None when the condition uses
something unknown (compiler macros such as __MWERKS__, include guards).
"""

import re

TOKEN_RE = re.compile(r"\s*(?:(\d+)|(\w+)|(&&|\|\||==|!=|>=|<=|[!()<>]))")


class Release:
    def __init__(self, name: str, id_: int, date: int, region: str):
        self.name, self.id, self.date, self.region = name, id_, date, region

    def __repr__(self):
        return f"Release({self.name})"


def _tokens(expr: str) -> list:
    out, pos = [], 0
    expr = expr.strip()
    while pos < len(expr):
        m = TOKEN_RE.match(expr, pos)
        if not m or m.end() == pos:
            raise ValueError(f"cannot tokenize {expr[pos:]!r}")
        out.append(m.group(1) or m.group(2) or m.group(3))
        pos = m.end()
    return out


def evaluate(expr: str, release: Release, releases: dict):
    """Value of a #if expression for `release` (int / bool), or None if it depends on unknown macros."""
    toks = _tokens(expr)
    pos = [0]

    def peek():
        return toks[pos[0]] if pos[0] < len(toks) else None

    def take(expected=None):
        t = peek()
        if expected is not None and t != expected:
            raise ValueError(f"expected {expected!r} in {expr!r}, got {t!r}")
        pos[0] += 1
        return t

    def call_arg():
        take("(")
        arg = take()
        take(")")
        return arg

    def primary():
        t = take()
        if t is None:
            raise ValueError(f"unexpected end of {expr!r}")
        if t == "(":
            v = or_expr()
            take(")")
            return v
        if t == "!":
            v = primary()
            return None if v is None else int(not v)
        if t.isdigit():
            return int(t)
        if t == "defined":
            has_paren = peek() == "("
            if has_paren:
                take("(")
            name = take()
            if has_paren:
                take(")")
            m = re.fullmatch(r"VERSION_(\w+)", name)
            if m and m.group(1).lower() in releases:
                return int(m.group(1).lower() == release.name)
            return None
        if t == "VERSION_IS":
            return int(call_arg().lower() == release.name)
        if t == "VERSION_REGION_IS":
            return int(call_arg() == release.region)
        if t in ("VERSION_EQUAL_OR_NEWER", "VERSION_EQUAL_OR_OLDER"):
            other = releases[call_arg().lower()]
            return int(release.date >= other.date if t.endswith("NEWER") else release.date <= other.date)
        if peek() == "(":  # unknown function-like macro
            call_arg()
        return None

    def compare():
        v = primary()
        while peek() in ("==", "!=", "<", ">", "<=", ">="):
            op, w = take(), primary()
            if v is None or w is None:
                v = None
            else:
                v = int({"==": v == w, "!=": v != w, "<": v < w, ">": v > w, "<=": v <= w, ">=": v >= w}[op])
        return v

    def and_expr():
        v = compare()
        while peek() == "&&":
            take()
            w = compare()
            if v == 0 or w == 0:
                v = 0
            elif v is None or w is None:
                v = None
            else:
                v = 1
        return v

    def or_expr():
        v = and_expr()
        while peek() == "||":
            take()
            w = and_expr()
            if (v is not None and v != 0) or (w is not None and w != 0):
                v = 1
            elif v is None or w is None:
                v = None
            else:
                v = 0
        return v

    value = or_expr()
    if peek() is not None:
        raise ValueError(f"trailing tokens in {expr!r}")
    return value


def _not(v):
    return None if v is None else (not v)


def _and(a, b):
    if a is False or b is False:
        return False
    if a is None or b is None:
        return None
    return True


def _or(a, b):
    if a is True or b is True:
        return True
    if a is None or b is None:
        return None
    return False


class ConditionTracker:
    """Feed every line of a C file to `line()`; `active` is then {release: True/False/None}."""

    DIRECTIVE_RE = re.compile(r"\s*#\s*(if|ifdef|ifndef|elif|else|endif)\b(.*)")

    def __init__(self, releases: dict):
        self.releases = releases
        # Stack frames: (parent_active, taken_so_far, current_branch, condition text)
        self.stack = []

    def _eval(self, expr: str) -> dict:
        expr = re.sub(r"/\*.*?\*/|//.*", "", expr).strip()
        out = {}
        for name, rel in self.releases.items():
            try:
                v = evaluate(expr, rel, self.releases)
            except (ValueError, KeyError):
                v = None
            out[name] = None if v is None else bool(v)
        return out

    @property
    def active(self) -> dict:
        if not self.stack:
            return {name: True for name in self.releases}
        parent, _, branch, _ = self.stack[-1]
        return {n: _and(parent[n], branch[n]) for n in self.releases}

    @property
    def conditions(self) -> list:
        return [f[3] for f in self.stack]

    def line(self, text: str) -> bool:
        """Process one line; returns True if it was a conditional directive."""
        m = self.DIRECTIVE_RE.match(text)
        if not m:
            return False
        kind, rest = m.group(1), m.group(2).strip()
        if kind in ("if", "ifdef", "ifndef"):
            if kind == "ifdef":
                rest = f"defined({rest})"
            elif kind == "ifndef":
                rest = f"!defined({rest})"
            cond = self._eval(rest)
            self.stack.append((self.active, cond, cond, f"#if {rest}"))
        elif kind == "elif":
            parent, taken, _, text_ = self.stack.pop()
            cond = self._eval(rest)
            branch = {n: _and(_not(taken[n]), cond[n]) for n in self.releases}
            taken = {n: _or(taken[n], cond[n]) for n in self.releases}
            self.stack.append((parent, taken, branch, f"{text_} / #elif {rest}"))
        elif kind == "else":
            parent, taken, _, text_ = self.stack.pop()
            branch = {n: _not(taken[n]) for n in self.releases}
            self.stack.append((parent, taken, branch, f"{text_} / #else"))
        else:  # endif
            if self.stack:
                self.stack.pop()
        return True
