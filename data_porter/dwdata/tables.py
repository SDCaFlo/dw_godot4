"""Helpers shared by the groups that convert C tables (moves, digimon, ...).

- load        read a table in every release through cdata.CIndex, with the standard parse check
- size_check  sizeof(C type) against the US symbol map
- diffs       what other releases change compared to the reference release
- used_by     code references grouped by function, with the struct fields read on those lines
- source      the `source` block of a table file
- enum        {"id", "name"} for a value with known names
- text_ref    {"string_id", "text"} for an entry of a text block (text group's FileModel)
"""

import re

from .cdata import CError, sizeof

REFERENCE = "us"   # release whose values fill the records; other releases only list differences


def enum(value, names: dict) -> dict:
    return {"id": value, "name": names.get(value)}


def text_ref(entry) -> dict:
    """Name of a text entry; unnamed entries take the earlier entry they repeat (`same_as`)."""
    if entry is None or entry.get("null_entry"):
        return None
    sid = entry["id"] or (entry.get("same_as") or {}).get("en_us")
    out = {"string_id": sid, "text": entry["text"]}
    if not entry["id"]:
        out["same_as"] = True
    return out


def load(out, index, c_file: str, name: str, hooks: dict = None):
    """{release: Loaded} or None; adds the check `<name>: parsed in every release`."""
    try:
        loaded = index.table(c_file, name, hooks)
    except CError as e:
        out.check(f"{name}: parsed in every release", False, str(e))
        return None
    missing = [r for r, l in loaded.items() if l is None]
    problems = [f"{r}: {i}" for r, l in loaded.items() if l for i in l.issues]
    problems += [f"{r}: lines {l.unknown_lines} depend on unknown macros" for r, l in loaded.items()
                 if l and l.unknown_lines]
    problems += [f"{r}: {len(l.wrapped)} values converted to the field type" for r, l in loaded.items()
                 if l and l.wrapped]
    problems += [f"{r}: {l.implicit} values missing (zero-filled)" for r, l in loaded.items() if l and l.implicit]
    ok = out.check(f"{name}: parsed in every release", not missing and not problems,
                   "; ".join(([f"not defined in {missing}"] if missing else []) + problems[:10])
                   or f"{loaded[REFERENCE].type.describe()} at {c_file}:{loaded[REFERENCE].decl.line}")
    return loaded if ok else None


def size_check(out, decomp, loaded, binary: str = "main") -> None:
    """sizeof(type) must equal the size in the US symbol map (skipped when the map gives none)."""
    decl, ty = loaded[REFERENCE].decl, loaded[REFERENCE].type
    size = decomp.symbols(binary).get(decl.name, {}).get("size")
    if size is None:
        return
    out.check(f"{decl.name}: size matches the US symbol map", size == sizeof(ty),
              f"sizeof({ty.describe()}) = {sizeof(ty)}, symbol size = {size}")


def diffs(loaded: dict, get) -> dict:
    """{release: changed fields (dicts) or value} where a release differs from the reference."""
    out = {}
    ref = get(loaded[REFERENCE])
    for release, l in loaded.items():
        if release == REFERENCE or l is None:
            continue
        v = get(l)
        if isinstance(ref, dict) and isinstance(v, dict):
            d = {k: v.get(k) for k in ref if v.get(k) != ref[k]}
        else:
            d = v if v != ref else None
        if d:
            out[release] = d
    return out


def used_by(decomp, refs: list, fields: list, loaded) -> list:
    """References grouped by enclosing function; `fields` read on those lines (text match of .f / ->f).

    Macro definitions and the table's own definition are left out.
    """
    texts, grouped = {}, {}
    for r in refs_without_definition(refs, loaded):
        if r["kind"] == "macro":
            continue
        if r["file"] not in texts:
            texts[r["file"]] = (decomp.root / r["file"]).read_text(encoding="utf-8", errors="replace").splitlines()
        line = texts[r["file"]][r["line"] - 1]
        g = grouped.setdefault((r["file"], r["in"]), {"file": r["file"], "in": r["in"], "kind": r["kind"],
                                                       "binary": r["binary"], "lines": [], "fields": set(),
                                                       "releases": set()})
        g["lines"].append(r["line"])
        g["releases"].update(r["releases"])
        g["fields"].update(f for f in fields if re.search(rf"(?:\.|->)\s*{f}\b", line))
    order = list(decomp.releases)
    out = []
    for g in sorted(grouped.values(), key=lambda g: (g["file"], g["lines"][0])):
        g["fields"] = sorted(g["fields"])
        g["releases"] = sorted(g["releases"], key=order.index)
        out.append(g)
    return out


def refs_without_definition(refs: list, loaded) -> list:
    """Drop the reference that is the table's own definition line."""
    decl = loaded[REFERENCE].decl
    return [r for r in refs if not (r["file"] == decl.file and r["line"] == decl.line)]


def source(decomp, loaded, files: list, extra: dict = None, binary: str = "main") -> dict:
    d = loaded[REFERENCE].decl
    s = {"files": files, "c_file": d.file, "symbol": d.name, "line": d.line,
         "c_type": loaded[REFERENCE].type.describe(), "binary": binary, "reference_release": REFERENCE,
         "releases": {r: {"region": rel.region, "date": rel.date} for r, rel in decomp.releases.items()}}
    sym = decomp.symbols(binary).get(d.name)
    if sym:
        s["us_symbol"] = sym
    if extra:
        s.update(extra)
    return s
