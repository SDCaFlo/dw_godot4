"""Disc mode for the groups (specs/from_disc.md §3, step D3c): the same group converters, run on the
player's US binaries instead of the decomp.

Values come from the binaries: C tables through DiscIndex (D3a), text through DiscText (D3b). Everything
else a group asks the decomp is metadata (references, symbols, struct layouts, file identities, `used_by`)
or the result of reading C code (constants, check outcomes): those answers are recorded while the groups
run on the decomp (`python -m dwdata snapshot`, `record()`), stored in the snapshot's `memo`, and replayed
in disc mode (`replay()`). The C source itself is never stored: a group reads it only inside `code(key,
fn)`, whose result is what gets recorded.

    with discmode.replay(disc_root):          # groups now read the disc
        GROUPS["moves"].convert(NO_DECOMP, out_dir)
"""

import contextlib
import hashlib
import json
from pathlib import Path

from . import cdata, decomp as decomp_mod, disc, source as source_mod, tables
from .cdata import CError
from .cpp import Release

# What a group gets as its decomp root in disc mode: a path that doesn't exist, so a read the layer
# doesn't cover fails loudly instead of finding a decomp by accident.
NO_DECOMP = Path("<no decomp: disc mode>")

_memo = None      # the active Memo while recording or replaying, else None (plain decomp mode)


# -- values that survive JSON ------------------------------------------------------------------

def _enc(v):
    """JSON with the Python shapes the groups use: tuples, sets and dicts with non-string keys tagged."""
    if isinstance(v, dict):
        if all(isinstance(k, str) for k in v):
            return {k: _enc(x) for k, x in v.items()}
        return {"\u0000dict": [[_enc(k), _enc(x)] for k, x in v.items()]}
    if isinstance(v, tuple):
        return {"\u0000tuple": [_enc(x) for x in v]}
    if isinstance(v, (set, frozenset)):
        return {"\u0000set": [_enc(x) for x in sorted(v, key=repr)]}
    if isinstance(v, list):
        return [_enc(x) for x in v]
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    raise CError(f"memo: can't record a {type(v).__name__}")


def _dec(v):
    if isinstance(v, dict):
        if len(v) == 1:
            (k, x), = v.items()
            if k == "\u0000dict":
                return {_dec(a): _dec(b) for a, b in x}
            if k == "\u0000tuple":
                return tuple(_dec(a) for a in x)
            if k == "\u0000set":
                return {_dec(a) for a in x}
        return {k: _dec(x) for k, x in v.items()}
    if isinstance(v, list):
        return [_dec(x) for x in v]
    return v


class Memo:
    def __init__(self, data: dict = None, recording: bool = False):
        self.data = {} if data is None else data
        self.recording = recording

    def get(self, key: str, fn):
        if self.recording:
            value = fn()
            enc = _enc(value)
            if key in self.data and self.data[key] != enc:
                raise CError(f"memo {key}: two different answers")
            self.data[key] = enc
            return _dec(enc)
        if key not in self.data:
            raise CError(f"disc mode: {key} was not recorded (python -m dwdata snapshot)")
        return _dec(self.data[key])


def code(key: str, fn):
    """A result computed from the decomp's C code (a parsed constant table, whether a check holds): fn()
    in decomp mode, recorded while snapshotting, replayed in disc mode. Groups read C source only in fn."""
    return fn() if _memo is None else _memo.get(f"code|{key}", fn)


def source(decomp, path: str, collapse: bool = False) -> str:
    """A decomp C file's text, for use inside code() only (it fails in disc mode: no decomp)."""
    text = (decomp.root / path).read_text(encoding="utf-8", errors="replace")
    return " ".join(text.split()) if collapse else text


def has(group: str, decomp, path: str, needle: str, collapse: bool = False) -> bool:
    """code(): whether a C file still contains a piece of code (the groups' "still in the code" checks)."""
    return code(f"{group}|has|{path}|{needle}", lambda: needle in source(decomp, path, collapse))


class Code:
    """A C file for `needle in file` checks: each answer recorded / replayed through has(). Any other
    use of the text needs code(key, fn) around it."""

    def __init__(self, group: str, decomp, path: str, collapse: bool = False):
        self.group, self.decomp, self.path, self.collapse = group, decomp, path, collapse

    def __contains__(self, needle: str) -> bool:
        return has(self.group, self.decomp, self.path, needle, self.collapse)


def active() -> bool:
    return _memo is not None and not _memo.recording


# -- recording (decomp mode, during the snapshot run) ------------------------------------------

class _RecordingDict(dict):
    """A dict that records the keys read through it (symbol maps, struct tables)."""

    def __init__(self, real: dict, on_read):
        super().__init__(real)
        self._on_read = on_read

    def get(self, key, default=None):
        self._on_read(key, super().get(key))
        return super().get(key, default)

    def __getitem__(self, key):
        self._on_read(key, super().get(key))
        return super().__getitem__(key)

    def __contains__(self, key):
        self._on_read(key, super().get(key))
        return super().__contains__(key)


@contextlib.contextmanager
def record(memo: Memo, structs: dict):
    """Patches the decomp-facing calls so their answers go into `memo`; struct layouts read by the groups
    go into `structs` (the snapshot's)."""
    global _memo
    D, C, S = decomp_mod.Decomp, cdata.CIndex, source_mod.SourceText
    saved = {"references": D.references, "symbols": D.symbols, "binary_of": D.binary_of,
             "identity": S.identity, "program": C.program, "switch_cases": C.switch_cases,
             "struct_source": C.struct_source, "table": C.table, "used_by": tables.used_by}
    depth = [0]

    def references(self, names):
        found = saved["references"](self, names)
        for n in names:
            memo.get(f"refs|{n}", lambda n=n: found.get(n, []))
        return found

    def symbols(self, binary):
        real = saved["symbols"](self, binary)
        memo.get("binaries", lambda: dict(self.binaries))
        return _RecordingDict(real, lambda k, v: memo.get(f"sym|{binary}|{k}", lambda: v))

    def binary_of(self, src_rel):
        return memo.get(f"bin|{src_rel}", lambda: saved["binary_of"](self, src_rel))

    def identity(self):
        return memo.get(f"file|{self.path}", lambda: saved["identity"](self))

    def table(self, c_rel, name, hooks=None):
        depth[0] += 1
        try:
            return saved["table"](self, c_rel, name, hooks)
        finally:
            depth[0] -= 1

    def program(self, c_rel, release, hooks=None):
        prog = saved["program"](self, c_rel, release, hooks)
        if depth[0] == 0 and release == disc.RELEASE:
            def on_read(k, ty):
                key = disc.type_to_json(ty, structs)["struct"] if isinstance(ty, cdata.Struct) else None
                memo.get(f"struct|{c_rel}|{k}", lambda: key)
            prog.structs = _RecordingDict(prog.structs, on_read)
        return prog

    def switch_cases(self, c_rel, function, variable, release):
        if release != disc.RELEASE:   # disc mode only has the US release
            return saved["switch_cases"](self, c_rel, function, variable, release)
        return memo.get(f"switch|{c_rel}|{function}|{variable}|{release}",
                        lambda: saved["switch_cases"](self, c_rel, function, variable, release))

    def struct_source(self, c_rel, release, type_name):
        if release != disc.RELEASE:
            return saved["struct_source"](self, c_rel, release, type_name)
        return memo.get(f"struct_source|{c_rel}|{release}|{type_name}",
                        lambda: saved["struct_source"](self, c_rel, release, type_name))

    def used_by(decomp, refs, fields, loaded):
        return memo.get(_used_by_key(refs, fields, loaded), lambda: saved["used_by"](decomp, refs, fields, loaded))

    D.references, D.symbols, D.binary_of = references, symbols, binary_of
    S.identity = identity
    C.table, C.program, C.switch_cases, C.struct_source = table, program, switch_cases, struct_source
    tables.used_by = used_by
    _memo = memo
    try:
        yield memo
    finally:
        _memo = None
        D.references, D.symbols, D.binary_of = saved["references"], saved["symbols"], saved["binary_of"]
        S.identity = saved["identity"]
        C.table, C.program = saved["table"], saved["program"]
        C.switch_cases, C.struct_source = saved["switch_cases"], saved["struct_source"]
        tables.used_by = saved["used_by"]


def _used_by_key(refs, fields, loaded) -> str:
    decl = loaded[tables.REFERENCE].decl
    digest = hashlib.sha1(json.dumps(refs, sort_keys=True, default=str).encode()).hexdigest()[:16]
    return f"used_by|{decl.file}|{decl.name}|{','.join(fields)}|{digest}"


# -- replay (disc mode) ------------------------------------------------------------------------

class _ReplayDict(dict):
    """Answers reads from the memo (a symbol map or a program's structs)."""

    def __init__(self, lookup):
        super().__init__()
        self._lookup = lookup

    def get(self, key, default=None):
        v = self._lookup(key)
        return default if v is None else v

    def __getitem__(self, key):
        v = self._lookup(key)
        if v is None:
            raise KeyError(key)
        return v

    def __contains__(self, key):
        return self._lookup(key) is not None


class DiscDecomp:
    """What a group sees as `Decomp(root)` in disc mode."""

    def __init__(self, root=None):
        self.root = NO_DECOMP

    def exists(self) -> bool:
        return True

    def rel(self, path) -> str:
        return Path(path).as_posix()

    @property
    def releases(self) -> dict:
        r = _memo.get("release|us", lambda: None)
        return {disc.RELEASE: Release(disc.RELEASE, r["id"], r["date"], r["region"])}

    @property
    def binaries(self) -> dict:
        return _memo.get("binaries", lambda: None)

    def binary_of(self, src_rel: str) -> str:
        return _memo.get(f"bin|{src_rel}", lambda: None)

    def symbols(self, binary: str) -> dict:
        return _ReplayDict(lambda k: _memo.get(f"sym|{binary}|{k}", lambda: None))

    def references(self, names) -> dict:
        return {n: _memo.get(f"refs|{n}", lambda: None) for n in names}

    def c_files(self):
        raise CError("disc mode: no decomp to scan")


class DiscSourceText:
    def __init__(self, root, rel: str):
        self.path = rel.replace("\\", "/")

    def identity(self) -> dict:
        return _memo.get(f"file|{self.path}", lambda: None)

    @property
    def text(self):
        raise CError(f"disc mode: {self.path} is decomp source (read it inside discmode.code)")


class _DiscProgram:
    def __init__(self, index, c_rel: str):
        def lookup(name):
            key = _memo.get(f"struct|{c_rel}|{name}", lambda: None)
            return disc.type_from_json({"struct": key}, index.snapshot["structs"], index._cache) if key else None
        self.structs = _ReplayDict(lookup)


class DiscCIndex(disc.DiscIndex):
    """What a group sees as `CIndex(decomp)` in disc mode."""

    shared = None   # the DiscIndex of the running replay (one per run: the binaries are read once)

    def __new__(cls, decomp=None):
        return cls.shared

    def __init__(self, decomp=None):
        pass   # the shared index is already set up

    def program(self, c_rel: str, release: str, hooks: dict = None):
        return _DiscProgram(self, c_rel)

    def switch_cases(self, c_rel, function, variable, release):
        return _memo.get(f"switch|{c_rel}|{function}|{variable}|{release}", lambda: None)

    def struct_source(self, c_rel, release, type_name):
        return _memo.get(f"struct_source|{c_rel}|{release}|{type_name}", lambda: None)


def _replay_used_by(decomp, refs, fields, loaded):
    return _memo.get(_used_by_key(refs, fields, loaded), lambda: None)


# Output files a US disc can't give (specs/from_disc.md §4).
NOT_FROM_A_US_DISC = ("font/ja.json", "font/en_eu.json", "font/ja.png", "font/en_eu.png")


def convert(disc_root: Path, output_root: Path, groups=None, snapshot: dict = None) -> list:
    """Runs the groups in disc mode; returns their GroupWriters."""
    from .groups import GROUPS
    outs = []
    with replay(disc_root, snapshot):
        for name in (groups or GROUPS):
            outs.append(GROUPS[name].convert(NO_DECOMP, output_root))
    return outs


def project(path: str, js):
    """The part of a table file a US disc must reproduce: other releases and languages left out."""
    def walk(v, in_text):
        if isinstance(v, dict):
            out = {}
            for k, x in v.items():
                if k in ("release_values", "release_text", "by_release", "release_note") or k in absent:
                    continue
                if in_text and k == "lines" and isinstance(x, dict):
                    continue
                if isinstance(x, dict) and "en_us" in x and ("ja" in x or "en_eu" in x):
                    out[k] = {"en_us": walk(x.get("en_us"), in_text)}   # {ja, en_us, en_eu}: US only
                    continue
                if isinstance(x, list) and x and all(isinstance(e, dict) and isinstance(e.get("release"), str)
                                                     for e in x):
                    # one entry per release (the naming screen's languages): the US one
                    out[k] = [walk(e, in_text) for e in x if e["release"] == disc.RELEASE]
                    continue
                if isinstance(x, list) and x and all(isinstance(e, dict) and isinstance(e.get("releases"), list)
                                                     for e in x):
                    # per-release entries (TEXT_COLORS): the US ones, as a US disc has them
                    out[k] = [walk(dict(e, releases=[disc.RELEASE]), in_text) for e in x
                              if disc.RELEASE in e["releases"]]
                    continue
                if in_text and k == "variants" and isinstance(x, dict):
                    out[k] = {a: b for a, b in x.items() if a in ("en_us", "en_us@us")}
                    continue
                if in_text and k == "c_text" and isinstance(x, dict):
                    out[k] = {a: b for a, b in x.items() if a == disc.RELEASE}
                    continue
                if k == "releases" and isinstance(x, dict) and disc.RELEASE in x:
                    out[k] = {disc.RELEASE: x[disc.RELEASE]}
                    continue
                out[k] = walk(x, in_text)
            return out
        if isinstance(v, list):
            return [walk(x, in_text) for x in v]
        return v
    absent = set(disc.ABSENT_FIELDS.get(path, []))
    return walk(js, path.startswith("text/"))


def compare(decomp_out: Path, disc_out: Path, groups=None) -> list:
    """Every table file of the decomp-mode output against the disc-mode one, projected (US only).
    Manifests, the catalog and the reports are not compared (checks and sources differ by mode)."""
    problems = []
    skip = {"manifest.json", "catalog.json", "pack.json"}
    for path in sorted(Path(decomp_out).rglob("*")):
        rel = path.relative_to(decomp_out).as_posix()
        if not path.is_file() or path.name in skip or path.suffix not in (".json", ".png"):
            continue
        if groups and rel.split("/")[0] not in groups:
            continue
        other = Path(disc_out) / rel
        if rel in NOT_FROM_A_US_DISC:
            if other.exists():
                problems.append(f"{rel}: written in disc mode (not on a US disc)")
            continue
        if not other.is_file():
            problems.append(f"{rel}: missing in disc mode")
            continue
        if path.suffix == ".png":
            if path.read_bytes() != other.read_bytes():
                problems.append(f"{rel}: differs")
            continue
        a = project(rel, json.loads(path.read_text(encoding="utf-8")))
        b = project(rel, json.loads(other.read_text(encoding="utf-8")))
        if a != b:
            problems.append(f"{rel}: " + "; ".join(_diff(a, b, "")[:5]))
    return problems


def _diff(a, b, path: str, out: list = None) -> list:
    out = [] if out is None else out
    if len(out) >= 5:
        return out
    if isinstance(a, dict) and isinstance(b, dict):
        for k in list(dict.fromkeys(list(a) + list(b))):
            if k not in a or k not in b:
                out.append(f"{path}.{k}: {'only in disc' if k not in a else 'missing in disc'}")
            else:
                _diff(a[k], b[k], f"{path}.{k}", out)
    elif isinstance(a, list) and isinstance(b, list) and len(a) == len(b):
        for k, (x, y) in enumerate(zip(a, b)):
            _diff(x, y, f"{path}[{k}]", out)
    elif a != b:
        out.append(f"{path}: decomp {json.dumps(a, ensure_ascii=False)[:60]} != disc {json.dumps(b, ensure_ascii=False)[:60]}")
    return out


@contextlib.contextmanager
def replay(disc_root: Path, snapshot: dict = None):
    """Runs the groups on the player's binaries: every group module's Decomp, CIndex and SourceText are
    the disc ones while the context is open."""
    global _memo
    from .groups import GROUPS
    from .groups import text as text_group
    index = disc.DiscIndex(disc_root, snapshot)
    DiscCIndex.shared = index
    index.__class__ = DiscCIndex
    memo = Memo(index.snapshot["memo"])
    swaps = []
    for mod in list(GROUPS.values()):
        for name, new in (("Decomp", DiscDecomp), ("CIndex", DiscCIndex), ("SourceText", DiscSourceText)):
            if hasattr(mod, name):
                swaps.append((mod, name, getattr(mod, name)))
                setattr(mod, name, new)
    saved_used_by = tables.used_by
    tables.used_by = _replay_used_by
    text_swap = text_group.disc_mode(disc.DiscText(index))
    _memo = memo
    try:
        yield index
    finally:
        _memo = None
        text_group.disc_mode(text_swap)
        tables.used_by = saved_used_by
        for mod, name, old in swaps:
            setattr(mod, name, old)
        DiscCIndex.shared = None
