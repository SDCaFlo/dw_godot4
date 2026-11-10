"""Disc mode (specs/from_disc.md, distribution step D3a): C tables read from the player's US binaries
(SLUS_010.32, *_REL.BIN) instead of the decomp.

- The snapshot (dwdata/snapshot/us.json, committed) holds, per C table the groups load, where it lives
  (binary, address, size) and its C type layout, plus the names of the symbols its pointers point to. It
  is written from the decomp by `python -m dwdata snapshot` and holds no values: a dev test checks that.
- DiscIndex answers CIndex.table() from the snapshot and the binaries, for the US release only.
- `snapshot --check` (and tests/test_disc.py) compare every table read from the binaries with the
  decomp's US value.
"""

import hashlib
import json
import re
from pathlib import Path

from . import cdata
from .cdata import Array, CError, Pointer, Scalar, Struct, Field, alignof, sizeof

RELEASE = "us"
FORMAT = 1
SNAPSHOT = Path(__file__).resolve().parent / "snapshot" / f"{RELEASE}.json"

# Disc file of each binary (config/us/<binary>.yaml target_path; SLUS_010.32 is PSX.EXE in the file table).
BINARY_FILES = {
    "main": "SLUS_010.32", "btl": "BTL_REL.BIN", "dget": "DGET_REL.BIN", "doo2": "DOO2_REL.BIN",
    "dooa": "DOOA_REL.BIN", "eab": "EAB_REL.BIN", "endi": "ENDI_REL.BIN", "evl": "EVL_REL.BIN",
    "fish": "FISH_REL.BIN", "kar": "KAR_REL.BIN", "mov": "MOV_REL.BIN", "murd": "MURD_REL.BIN",
    "std": "STD_REL.BIN", "trn": "TRN_REL.BIN", "trn2": "TRN2_REL.BIN", "vs": "VS_REL.BIN",
}


# Tables the decomp defines that are not on a US disc (the snapshot records them as absent; DiscIndex gives
# None for the US release, as CIndex does for a table a release doesn't define).
ABSENT = {
    "src/vs/vs_demo.c:VS_DEMO_DIGIMON": "vs_demo.c is linked into no US binary (config/us/*.yaml has no entry "
                                        "for it); neither its list nor its file paths are in SLUS_010.32 or "
                                        "the overlays (checked 2026-11-09)",
}


# -- types <-> JSON ----------------------------------------------------------------------------

def type_to_json(ty, structs: dict, ids: dict = None):
    """A cdata type as JSON; structs go by key into `structs` (each written once). `ids` (id(struct) ->
    key, shared across calls) keeps two different structs with the same name, or two anonymous
    structs, apart."""
    if ids is None:
        ids = structs.setdefault("\0ids", {})
    if isinstance(ty, Scalar):
        return {"scalar": ty.name, "size": ty.size, "signed": ty.signed}
    if isinstance(ty, Pointer):
        return {"pointer": ty.target}
    if isinstance(ty, Array):
        return {"array": type_to_json(ty.elem, structs, ids), "n": ty.n}
    if isinstance(ty, Struct):
        if id(ty) in ids:
            return {"struct": ids[id(ty)]}
        body = {"union": ty.union, "file": ty.file, "line": ty.line,
                "fields": [{"name": f.name, "type": type_to_json(f.type, structs, ids), "bits": f.bits}
                           for f in ty.fields]}
        base = ty.name if ty.name and not ty.name.startswith("<") else "anonymous"
        key, n = base, 1
        while key in structs and structs[key] != body:   # same name, other layout: a new key
            n += 1
            key = f"{base}#{n}"
        ids[id(ty)] = key
        structs[key] = body
        return {"struct": key}
    raise CError(f"type_to_json: {ty!r}")


def type_from_json(d, structs: dict, cache: dict = None):
    cache = {} if cache is None else cache
    if "scalar" in d:
        return Scalar(d["scalar"], d["size"], d["signed"])
    if "pointer" in d:
        return Pointer(d["pointer"])
    if "array" in d:
        return Array(type_from_json(d["array"], structs, cache), d["n"])
    key = d["struct"]
    if key not in cache:
        s = structs[key]
        st = Struct(key, [], s["union"], s["file"], s["line"])
        cache[key] = st
        st.fields = [Field(f["name"], type_from_json(f["type"], structs, cache), f["bits"]) for f in s["fields"]]
    return cache[key]


def sized(ty, value):
    """The type with every unsized array given its length from the value (char[] = "..." included)."""
    if isinstance(ty, Array):
        n = ty.n
        if n is None:
            n = len(value.encode("shift_jis")) + 1 if isinstance(value, str) else len(value)
        elem = ty.elem
        if isinstance(value, list) and value and not isinstance(elem, (Scalar, Pointer)):
            elem = sized(elem, value[0])
        return Array(elem, n)
    return ty


def is_text(ty) -> bool:
    """A char array holds text (the decomp gives a string); uint8_t / int8_t arrays hold numbers."""
    return isinstance(ty, Array) and isinstance(ty.elem, Scalar) and ty.elem.name == "char"


# -- reading values from bytes -----------------------------------------------------------------

class _Reader:
    """Values from bytes, laid out on a type. `slots` (path -> entry) is the table's snapshot overrides:
    {"pointer": [address, name]} where the compiler merged identical strings, so one address carries
    several of the decomp's names, and {"text_id": id} where the decomp writes a string id (a macro
    hook) in a char array that the binary holds as text. The text read there is kept in `texts`."""

    def __init__(self, data: bytes, base: int, pointers: dict, slots: dict = None):
        self.data, self.base, self.pointers, self.slots = data, base, pointers, slots or {}
        self.unknown_pointers = []
        self.slot_problems = []
        self.texts = {}

    def value(self, ty, off: int, path: str = ""):
        if isinstance(ty, Scalar):
            return int.from_bytes(self.data[off:off + ty.size], "little", signed=ty.signed)
        if isinstance(ty, Pointer):
            addr = int.from_bytes(self.data[off:off + 4], "little")
            if addr == 0:
                return None
            key = f"0x{addr:08X}"
            slot = self.slots.get(path)
            if slot and "pointer" in slot:
                if slot["pointer"][0] != key:
                    self.slot_problems.append(f"{path}: {key}, the snapshot has {slot['pointer'][0]}")
                return slot["pointer"][1]
            name = self.pointers.get(key)
            if name is None:
                self.unknown_pointers.append(key)
                return key
            return name
        if isinstance(ty, Array):
            if is_text(ty):
                raw = self.data[off:off + ty.n]
                text = raw.split(b"\0", 1)[0].decode("shift_jis", errors="replace")
                slot = self.slots.get(path)
                if slot and "text_id" in slot:
                    self.texts[path] = text
                    return slot["text_id"]
                return text
            step = sizeof(ty.elem)
            return [self.value(ty.elem, off + k * step, f"{path}[{k}]") for k in range(ty.n)]
        if isinstance(ty, Struct):
            if any(f.bits is not None for f in ty.fields):
                raise CError(f"{ty.name}: bit fields not supported")
            if ty.union:
                f = ty.fields[0]
                return {f.name: self.value(f.type, off, f"{path}.{f.name}")}
            out, pos = {}, 0
            for f in ty.fields:
                a = alignof(f.type)
                pos = (pos + a - 1) // a * a
                out[f.name] = self.value(f.type, off + pos, f"{path}.{f.name}")
                pos += sizeof(f.type)
            return out
        raise CError(f"read: {ty!r}")


def encode(ty, value) -> bytes:
    """The bytes a decomp value compiles to (numbers only: no pointers or text), to find a table that
    has no symbol."""
    if isinstance(ty, Scalar):
        return int(value).to_bytes(ty.size, "little", signed=ty.signed)
    if isinstance(ty, Array) and not is_text(ty):
        return b"".join(encode(ty.elem, v) for v in value)
    if isinstance(ty, Struct) and not ty.union:
        out = bytearray()
        for f in ty.fields:
            a = alignof(f.type)
            out += bytes((-len(out)) % a)
            out += encode(f.type, value[f.name])
        return bytes(out + bytes((-len(out)) % alignof(ty)))
    raise CError(f"encode: {ty.describe()} (only numbers can be searched)")


def search(decomp, c_rel: str, ty, value, data: bytes, base: int) -> int:
    """Address of a table with no symbol: its bytes found exactly once in its C file's binary."""
    needle = encode(ty, value)
    hits, at = [], data.find(needle)
    while at >= 0 and len(hits) < 3:
        hits.append(at)
        at = data.find(needle, at + 1)
    if len(hits) != 1:
        raise CError(f"no symbol, and its {len(needle)} bytes are found {len(hits)} times in the binary")
    if hits[0] % alignof(ty):
        raise CError(f"no symbol, and its bytes are found at an unaligned offset {hits[0]:#x}")
    return base + hits[0]


STRING_ID = re.compile(r"[A-Z][A-Z0-9_]*")


def collect_slots(ty, value, data: bytes, off: int, pointers: dict, slots: dict, problems: list,
                  path: str = "") -> None:
    """Walks a decomp value over the binary: pointer addresses paired with the symbol names the decomp
    writes there (the first name an address gets goes in `pointers`, later different names become slot
    overrides), and char arrays where the decomp has a string id instead of the stored text."""
    if isinstance(ty, Pointer):
        addr = int.from_bytes(data[off:off + 4], "little")
        if value is None:
            if addr != 0:
                problems.append(f"{path}: NULL in the decomp, 0x{addr:08X} in the binary")
            return
        if not isinstance(value, str):
            return
        key = f"0x{addr:08X}"
        if pointers.setdefault(key, value) != value:
            slots[path] = {"pointer": [key, value]}
    elif isinstance(ty, Array):
        if is_text(ty):
            text = data[off:off + ty.n].split(b"\0", 1)[0].decode("shift_jis", errors="replace")
            if isinstance(value, str) and value.split("\0", 1)[0] != text and STRING_ID.fullmatch(value):
                slots[path] = {"text_id": value}
            return
        if isinstance(value, list):
            step = sizeof(ty.elem)
            for k, v in enumerate(value):
                collect_slots(ty.elem, v, data, off + k * step, pointers, slots, problems, f"{path}[{k}]")
    elif isinstance(ty, Struct) and isinstance(value, dict):
        if ty.union:
            f = ty.fields[0]
            collect_slots(f.type, value.get(f.name), data, off, pointers, slots, problems, f"{path}.{f.name}")
            return
        pos = 0
        for f in ty.fields:
            a = alignof(f.type)
            pos = (pos + a - 1) // a * a
            collect_slots(f.type, value.get(f.name), data, off + pos, pointers, slots, problems, f"{path}.{f.name}")
            pos += sizeof(f.type)


def pointer_targets(ty, value, out: set) -> None:
    """Symbol names a decomp value's pointers point to."""
    if isinstance(ty, Pointer):
        if isinstance(value, str):
            out.add(value)
    elif isinstance(ty, Array) and isinstance(value, list):
        for v in value:
            pointer_targets(ty.elem, v, out)
    elif isinstance(ty, Struct) and isinstance(value, dict):
        for f in ty.fields:
            if f.name in value:
                pointer_targets(f.type, value[f.name], out)


# -- comparing ---------------------------------------------------------------------------------

def normalize(ty, value):
    """The decomp's value as the binary stores it: char arrays as stored text (no trailing NUL),
    scalars wrapped to their width (cdata already wraps), unions as their first field."""
    if isinstance(ty, Array):
        if cdata._is_char_array(ty):
            return value.split("\0", 1)[0] if isinstance(value, str) else value
        return [normalize(ty.elem, v) for v in value]
    if isinstance(ty, Struct):
        fields = ty.fields[:1] if ty.union else ty.fields
        return {f.name: normalize(f.type, value.get(f.name)) for f in fields}
    return value


def differences(ty, a, b, path: str = "", out: list = None, limit: int = 10) -> list:
    out = [] if out is None else out
    if len(out) >= limit:
        return out
    if isinstance(ty, Array) and not is_text(ty):
        if not isinstance(a, list) or not isinstance(b, list) or len(a) != len(b):
            out.append(f"{path}: {a!r:.60} != {b!r:.60}")
            return out
        for k, (x, y) in enumerate(zip(a, b)):
            differences(ty.elem, x, y, f"{path}[{k}]", out, limit)
        return out
    if isinstance(ty, Struct):
        for f in (ty.fields[:1] if ty.union else ty.fields):
            differences(f.type, (a or {}).get(f.name), (b or {}).get(f.name), f"{path}.{f.name}", out, limit)
        return out
    if a != b:
        out.append(f"{path}: decomp {a!r:.60} != disc {b!r:.60}")
    return out


# -- the snapshot ------------------------------------------------------------------------------

def load_addresses(decomp) -> dict:
    """{binary: load address} from config/us/<binary>.yaml: the vram of the segment at file offset 0."""
    out = {}
    for name in BINARY_FILES:
        text = (decomp.root / "config" / "us" / f"{name}.yaml").read_text(encoding="utf-8")
        m = re.search(r"start:\s*0x0+\s*\n\s*vram:\s*(0x[0-9A-Fa-f]+)", text)
        if not m:
            raise CError(f"config/us/{name}.yaml: no segment at offset 0")
        out[name] = int(m.group(1), 16)
    return out


class Recorder:
    """Wraps cdata.CIndex.table while the groups convert, keeping each table's US Loaded. After the run,
    `text` holds the text group's output tables (text name -> table JSON), the source of the strings'
    locations (D3b)."""

    def __init__(self):
        self.tables = {}   # (c_rel, name) -> (decomp, Loaded)
        self.text = {}
        self._orig = None

    def __enter__(self):
        self._orig = cdata.CIndex.table
        rec = self

        def table(index, c_rel, name, hooks=None):
            result = rec._orig(index, c_rel, name, hooks)
            if result.get(RELEASE) is not None:
                rec.tables.setdefault((c_rel, name), (index.decomp, result[RELEASE]))
            return result

        cdata.CIndex.table = table
        return self

    def __exit__(self, *exc):
        cdata.CIndex.table = self._orig


def record_groups(decomp_root: Path, work_dir: Path, groups=None) -> Recorder:
    """Runs the groups in decomp mode into work_dir and records the C tables they load."""
    from .groups import GROUPS
    with Recorder() as rec:
        for name in (groups or GROUPS):
            GROUPS[name].convert(decomp_root, work_dir)
    text_dir = Path(work_dir) / "text"
    for path in sorted(text_dir.rglob("*.json")):
        if path.name != "manifest.json":
            rec.text[path.relative_to(text_dir).with_suffix("").as_posix()] = json.loads(path.read_text(encoding="utf-8"))
    return rec


def locate(decomp, c_rel: str, name: str) -> tuple:
    """(binary, address, size) of a table's symbol: the C file's binary first, then any binary
    (overlays' small data lives in main). Raises CError when missing or ambiguous."""
    own = decomp.binary_of(c_rel)
    hit = decomp.symbols(own).get(name) if own in BINARY_FILES else None
    if hit:
        return own, int(hit["address"], 16), hit["size"]
    hits = [(b, decomp.symbols(b)[name]) for b in BINARY_FILES if name in decomp.symbols(b)]
    if len(hits) != 1:
        raise CError(f"{name}: {'no' if not hits else len(hits)} US symbols")
    b, h = hits[0]
    return b, int(h["address"], 16), h["size"]


def build_snapshot(rec: Recorder, dump_root: Path) -> tuple:
    """(snapshot dict, problems). The developer's US binaries (dump_root) give the pointer addresses
    (paired with the decomp's symbol names, cross-checked with the symbol maps) and the files' sha1."""
    structs, tables, problems = {}, {}, []
    pointers, decomp, loads, data = {}, None, None, {}
    for (c_rel, name), (dec, loaded) in sorted(rec.tables.items()):
        if decomp is None:
            decomp, loads = dec, load_addresses(dec)
        located = "symbol"
        try:
            ty = sized(loaded.type, loaded.value)
            size = sizeof(ty)
            try:
                binary, address, sym_size = locate(dec, c_rel, name)
            except CError:
                binary, sym_size, located = dec.binary_of(c_rel), None, "search"
                if binary not in data:
                    data[binary] = (Path(dump_root) / BINARY_FILES[binary]).read_bytes()
                address = search(dec, c_rel, ty, loaded.value, data[binary], loads[binary])
        except CError as e:
            key = f"{c_rel}:{name}"
            if key in ABSENT:
                tables[key] = {"c_file": c_rel, "name": name, "located": "absent", "why": ABSENT[key]}
            else:
                problems.append(f"{c_rel} {name}: {e}")
            continue
        if sym_size is not None and sym_size != size:
            problems.append(f"{c_rel} {name}: sizeof {size:#x} != symbol size {sym_size:#x}")
        if binary not in data:
            data[binary] = (Path(dump_root) / BINARY_FILES[binary]).read_bytes()
        slots = {}
        collect_slots(ty, loaded.value, data[binary], address - loads[binary], pointers, slots, problems, "")
        tables[f"{c_rel}:{name}"] = {
            "c_file": c_rel, "name": name, "binary": binary, "address": f"0x{address:08X}", "size": size,
            "located": located,
            "type": type_to_json(ty, structs),
            "decl": {"file": loaded.decl.file, "line": loaded.decl.line},
            "element_lines": loaded.element_lines,
            "slots": slots,
        }
    if decomp is not None:
        for addr, sym in pointers.items():
            known = [info["address"] for b in BINARY_FILES for n, info in decomp.symbols(b).items() if n == sym]
            if known and addr not in known:
                problems.append(f"pointer target {sym}: {addr} in the binary, {known} in the symbol maps")
    structs.pop("\0ids", None)
    problems += [f"{k}: listed as absent but not loaded by any group" for k in ABSENT if k not in tables]

    def read_binary(b):
        if b not in data:
            data[b] = (Path(dump_root) / BINARY_FILES[b]).read_bytes()

    strings, string_problems = locate_strings(rec.text, tables, pointers, data, loads, read_binary)
    problems += string_problems
    binaries = {b: {"file": BINARY_FILES[b], "load": f"0x{loads[b]:08X}",
                    "sha1": hashlib.sha1(data[b]).hexdigest()} for b in sorted(data)}
    snap = {"format": FORMAT, "release": RELEASE, "generated_by": "python -m dwdata snapshot",
            "binaries": binaries, "tables": tables, "structs": structs,
            "pointers": dict(sorted(pointers.items())), "strings": strings}
    return snap, problems


# -- text (D3b) ---------------------------------------------------------------------------------

def us_strings(text_tables: dict):
    """(text table, block, key, decomp record, item, raw US value) of every string the US release has:
    the en_us variant as the YAML writes it (padding NULs kept) or, where only the C file defines it, the
    C text (`c_text`). Key: the string id, or "#<index>" for an entry."""
    for table, js in sorted(text_tables.items()):
        for rec in js["records"]:
            for item in rec.get("strings") or rec.get("entries") or []:
                if item.get("null_entry") or item["text"].get("en_us") is None:
                    continue
                v = item["variants"]
                raw = v.get("en_us@us", v.get("en_us"))
                if raw is None:
                    raw = ((item.get("c_text") or {}).get(RELEASE) or {}).get("text")
                if isinstance(raw, list):
                    raise CError(f"{table} {rec['block']}: a US string in lines")
                key = item["id"] if rec["kind"] != "entries" else f"#{item['index']}"
                yield table, rec["block"], key, rec, item, raw


def _storage_us(rec: dict):
    st = rec.get("options", {}).get("storage")
    return st.get(RELEASE, st.get("default")) if isinstance(st, dict) else st


def _binary_at(address: int, preferred: str, data: dict, loads: dict) -> str:
    """The binary whose loaded range holds an address: the preferred one (the block's), else main."""
    for b in (preferred, "main"):
        if b in data and 0 <= address - loads[b] < len(data[b]):
            return b
    raise CError(f"0x{address:08X} is in neither {preferred} nor main")


def locate_strings(text_tables: dict, tables: dict, pointers: dict, data: dict, loads: dict, read_binary) -> tuple:
    """({table: {block: {key: location}}}, problems). A location is {binary, address, length, located}:
    `symbol` (the string's own US symbol), `pointer` (the address a C table's pointer to it holds, D3a),
    `array` (entry k of the block's char * array), `row` (row k of the block's char array), `search` (its
    bytes + NUL found once in the block's binary or main, between the nearest strings of the same file
    that have an address), `copy` (found several times: the nearest copy; any copy reads the same text,
    since DiscIndex accepts only the US files by their sha1); or {table, path, located: "slot"} (a char
    field of a C table, D3a's text_id slots); {alias: key} (an unnamed entry repeating one); {located:
    "empty", length: 0} (an empty string no table points to). Every byte location is checked: the bytes
    at the address are the raw value, followed by a NUL."""
    slot_of, address_of = {}, {}
    for addr, name in pointers.items():
        address_of.setdefault(name, addr)
    for key, t in tables.items():
        for path, sl in (t.get("slots") or {}).items():
            if "text_id" in sl:
                slot_of.setdefault(sl["text_id"], (key, path))
            if "pointer" in sl:
                address_of.setdefault(sl["pointer"][1], sl["pointer"][0])
    out, problems, pending = {}, [], []
    for table, block, key, rec, item, raw in us_strings(text_tables):
        own = rec["c"]["binary"]
        if own in BINARY_FILES:
            read_binary(own)
        read_binary("main")
        loc = None
        sym = item.get("symbol")
        if sym and "address" not in sym:
            sym = sym.get(item["id"]) or next(iter(sym.values()))
        if sym:
            addr = int(sym["address"], 16)
            loc = {"located": "symbol", "binary": _binary_at(addr, own, data, loads), "address": f"0x{addr:08X}"}
        elif item["id"] in address_of:
            addr = int(address_of[item["id"]], 16)
            loc = {"located": "pointer", "binary": _binary_at(addr, own, data, loads), "address": f"0x{addr:08X}"}
        elif _storage_us(rec) == "embedded":
            sid = item["id"] or (item.get("same_as") or {}).get("en_us")
            if sid in slot_of:
                loc = {"located": "slot", "table": slot_of[sid][0], "path": slot_of[sid][1]}
            elif rec["c"].get("symbol") and rec["c"]["symbol"].get("size"):
                row = rec["c"]["symbol"]["size"] // rec["count"]
                addr = int(rec["c"]["symbol"]["address"], 16) + item["index"] * row
                loc = {"located": "row", "binary": _binary_at(addr, own, data, loads), "address": f"0x{addr:08X}"}
        elif rec["kind"] == "entries" and rec["c"].get("symbol"):
            arr = int(rec["c"]["symbol"]["address"], 16)
            b = _binary_at(arr, own, data, loads)
            at = arr - loads[b] + 4 * item["index"]
            ptr = int.from_bytes(data[b][at:at + 4], "little")
            loc = {"located": "array", "binary": _binary_at(ptr, own, data, loads), "address": f"0x{ptr:08X}"}
        elif item["id"] is None and (item.get("same_as") or {}).get("en_us"):
            loc = {"alias": item["same_as"]["en_us"]}
        if loc is None:
            pending.append((table, block, key, rec, item, raw))
            continue
        out.setdefault(table, {}).setdefault(block, {})[key] = loc
    # Searched strings: between the nearest strings of the same file with a byte location.
    order = {}
    for table, block, key, *_ in us_strings(text_tables):
        order.setdefault(table, []).append((block, key))
    for table, block, key, rec, item, raw in pending:
        if raw == "":
            out.setdefault(table, {}).setdefault(block, {})[key] = {"located": "empty", "length": 0}
            continue
        enc = raw.encode("shift_jis") + b"\0"
        own = rec["c"]["binary"] if rec["c"]["binary"] in BINARY_FILES else "main"
        seq = order[table]
        k = seq.index((block, key))

        def bound(rng, b):
            for j in rng:
                loc = out.get(table, {}).get(seq[j][0], {}).get(seq[j][1])
                if loc and loc.get("binary") == b:
                    return int(loc["address"], 16) - loads[b]
            return None

        found = None
        for b in dict.fromkeys((own, "main")):
            read_binary(b)
            lo, hi = bound(range(k - 1, -1, -1), b), bound(range(k + 1, len(seq)), b)
            lo, hi = (lo or 0), (hi if hi is not None else len(data[b]))
            if lo > hi:
                lo, hi = 0, len(data[b])
            hits, at = [], data[b].find(enc, lo, hi + len(enc))
            while at >= 0 and len(hits) < 3:
                hits.append(at)
                at = data[b].find(enc, at + 1, hi + len(enc))
            if len(hits) == 1:
                found = {"located": "search", "binary": b, "address": f"0x{loads[b] + hits[0]:08X}"}
                break
            if len(hits) > 1:
                found = {"located": "copy", "binary": b, "address": f"0x{loads[b] + hits[0]:08X}"}
                break
        if isinstance(found, dict):
            out.setdefault(table, {}).setdefault(block, {})[key] = found
        else:
            problems.append(f"text/{table} {block} {key} {raw!r:.30}: {found or 'not found'}")
    # Lengths and the byte check.
    for table, block, key, rec, item, raw in us_strings(text_tables):
        loc = out.get(table, {}).get(block, {}).get(key)
        if loc is None or "binary" not in loc:
            continue
        enc = raw.encode("shift_jis")
        b = loc["binary"]
        off = int(loc["address"], 16) - loads[b]
        loc["length"] = len(enc)
        tail = data[b][off + len(enc):off + len(enc) + 1]
        if data[b][off:off + len(enc)] != enc or (loc["located"] != "row" and tail != b"\0"):
            problems.append(f"text/{table} {block} {key}: the bytes at {loc['address']} ({b}) are not the string")
    return out, problems


def write_snapshot(snap: dict, path: Path = SNAPSHOT) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(snap, indent=1, ensure_ascii=False) + "\n", encoding="utf-8")


# -- the disc index ----------------------------------------------------------------------------

class _Decl:
    def __init__(self, name, file, line):
        self.name, self.file, self.line = name, file, line


class DiscIndex:
    """CIndex.table() for the US release, values read from the player's binaries."""

    def __init__(self, disc_root: Path, snapshot: dict = None, verify_hashes: bool = True):
        self.root = Path(disc_root)
        self.snapshot = snapshot if snapshot is not None else json.loads(SNAPSHOT.read_text(encoding="utf-8"))
        if self.snapshot.get("format") != FORMAT:
            raise CError(f"snapshot format {self.snapshot.get('format')} (expected {FORMAT})")
        self.releases = {RELEASE: None}
        self._data = {}
        self._types = {}
        self._cache = {}
        self.verify_hashes = verify_hashes
        self.texts = {}   # "c_file:name" -> {path: text} of the text_id slots read (for the text source, D3b)

    def binary(self, name: str) -> bytes:
        if name not in self._data:
            info = self.snapshot["binaries"][name]
            path = self.root / info["file"]
            if not path.is_file():
                raise CError(f"{info['file']} not found in {self.root}")
            data = path.read_bytes()
            if self.verify_hashes and "sha1" in info and hashlib.sha1(data).hexdigest() != info["sha1"]:
                raise CError(f"{info['file']}: not the US release's file (sha1 differs)")
            self._data[name] = data
        return self._data[name]

    def has(self, c_rel: str, name: str) -> bool:
        return f"{c_rel}:{name}" in self.snapshot["tables"]

    def type_of(self, c_rel: str, name: str):
        key = f"{c_rel}:{name}"
        if key not in self._types:
            self._types[key] = type_from_json(self.snapshot["tables"][key]["type"], self.snapshot["structs"], self._cache)
        return self._types[key]

    def read(self, c_rel: str, name: str):
        """(value, unknown pointer addresses) of one table."""
        t = self.snapshot["tables"][f"{c_rel}:{name}"]
        base = int(self.snapshot["binaries"][t["binary"]]["load"], 16)
        data = self.binary(t["binary"])
        off = int(t["address"], 16) - base
        if off < 0 or off + t["size"] > len(data):
            raise CError(f"{name}: {t['address']} + {t['size']:#x} outside {t['binary']}")
        reader = _Reader(data, base, self.snapshot["pointers"], t.get("slots"))
        value = reader.value(self.type_of(c_rel, name), off)
        self.texts[f"{c_rel}:{name}"] = reader.texts
        return value, reader.unknown_pointers + reader.slot_problems

    def table(self, c_rel: str, name: str, hooks: dict = None) -> dict:
        """{"us": Loaded}, like CIndex.table restricted to the US release; hooks are not needed (the
        bytes are already laid out)."""
        key = f"{c_rel}:{name}"
        if key not in self.snapshot["tables"]:
            raise CError(f"{key}: not in the snapshot (python -m dwdata snapshot)")
        t = self.snapshot["tables"][key]
        if t["located"] == "absent":
            return {RELEASE: None}
        value, unknown = self.read(c_rel, name)
        issues = [f"{name}: {a}" for a in unknown]
        decl = _Decl(name, t["decl"]["file"], t["decl"]["line"])
        return {RELEASE: cdata.Loaded(RELEASE, decl, self.type_of(c_rel, name), value, t["element_lines"],
                                      issues, [], 0, [])}


class DiscText:
    """The US strings read from the binaries at the snapshot's locations (D3b): {(text table, block, key):
    raw value}, the raw value being the en_us variant as the decomp's YAML writes it (padding NULs kept)."""

    def __init__(self, index: DiscIndex):
        self.index = index
        self._strings = None

    def _read(self, table: str, block: str, key: str, seen=()):
        loc = self.index.snapshot["strings"][table][block][key]
        if "alias" in loc:
            if loc["alias"] in seen:
                raise CError(f"text/{table} {block} {key}: alias loop")
            target = next((k for k, l in self.index.snapshot["strings"][table][block].items() if k == loc["alias"]),
                          None)
            if target is None:   # an entry repeating a named entry: find it by id among the block's entries
                raise CError(f"text/{table} {block} {key}: alias {loc['alias']} not in the block")
            return self._read(table, block, target, seen + (key,))
        if loc["located"] == "empty":
            return ""
        if loc["located"] == "slot":
            t = self.index.snapshot["tables"][loc["table"]]
            self.index.read(t["c_file"], t["name"])
            return self.index.texts[loc["table"]][loc["path"]]
        base = int(self.index.snapshot["binaries"][loc["binary"]]["load"], 16)
        off = int(loc["address"], 16) - base
        raw = self.index.binary(loc["binary"])[off:off + loc["length"]]
        return raw.decode("shift_jis", errors="replace")

    def strings(self) -> dict:
        if self._strings is None:
            self._strings = {(table, block, key): self._read(table, block, key)
                             for table, blocks in self.index.snapshot["strings"].items()
                             for block, items in blocks.items() for key in items}
        return self._strings


def check_text(rec: Recorder, text: DiscText) -> list:
    """Every US string of the decomp against the one read from the binaries, and nothing extra."""
    problems, want = [], {}
    for table, block, key, _, _, raw in us_strings(rec.text):
        want[(table, block, key)] = raw
    got = {}
    try:
        got = text.strings()
    except CError as e:
        problems.append(str(e))
    for k, raw in want.items():
        if k not in got:
            problems.append(f"text/{k[0]} {k[1]} {k[2]}: not in the snapshot")
        elif got[k] != raw:
            problems.append(f"text/{k[0]} {k[1]} {k[2]}: decomp {raw!r:.40} != disc {got[k]!r:.40}")
    problems += [f"text/{k[0]} {k[1]} {k[2]}: in the snapshot, not a US string" for k in got if k not in want]
    return problems


def check(rec: Recorder, disc: DiscIndex) -> list:
    """Every recorded table: the decomp's US value against the one read from the binaries."""
    problems = []
    for (c_rel, name), (_, loaded) in sorted(rec.tables.items()):
        if not disc.has(c_rel, name):
            problems.append(f"{c_rel} {name}: not in the snapshot")
            continue
        if disc.snapshot["tables"][f"{c_rel}:{name}"]["located"] == "absent":
            continue
        ty = disc.type_of(c_rel, name)
        try:
            value, unknown = disc.read(c_rel, name)
        except CError as e:
            problems.append(f"{c_rel} {name}: {e}")
            continue
        diff = differences(ty, normalize(ty, loaded.value), value)
        if unknown:
            diff.append(f"pointers to unknown symbols: {unknown[:5]}")
        if diff:
            problems.append(f"{c_rel} {name}: " + "; ".join(diff))
    return problems
