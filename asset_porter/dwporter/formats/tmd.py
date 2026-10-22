"""TMD model format (libgs).

Layout (little-endian):
    u32 id = 0x41
    u32 flags          bit 0 FIXP: 1 = offsets are absolute addresses, 0 = relative to the object table
    u32 nobj
    nobj x object:     u32 vert_top, n_vert, normal_top, n_normal, primitive_top, n_primitive; i32 scale
    vertices:          i16 x, y, z, pad
    normals:           i16 x, y, z, pad (4.12 fixed point)
    primitives:        u8 olen, ilen, flag, mode, then ilen * 4 bytes of packet data

Reference: PSXPrev Common/Parsers/TMDParser.cs, TMDHelper.cs (CreateTMDPacketStructure / ParsePrimitiveData).
The packet layout below is derived from the flag/mode bits and checked against `ilen`.
"""

import dataclasses
import struct
from dataclasses import dataclass
from typing import Optional

TMD_ID = 0x41
MAX_OBJECTS = 1024
MAX_ITEMS = 0x10000


class TmdError(ValueError):
    pass


@dataclass(frozen=True)
class Primitive:
    offset: int  # of the 4-byte header, within the source buffer
    olen: int
    ilen: int
    flag: int
    mode: int
    kind: str  # "triangle", "quad", "line", "sprite"
    vertices: tuple  # vertex indices
    normals: tuple  # normal indices (1 for flat, one per vertex for gouraud, empty if unlit)
    uvs: tuple  # (u, v) per vertex, texture-page pixels; empty if untextured
    cba: Optional[int]  # CLUT id (GetClut)
    tsb: Optional[int]  # texture page id (GetTPage)
    colors: tuple  # (r, g, b) per colour entry; empty if none
    size: Optional[tuple] = None  # sprite (w, h)

    @property
    def lit(self) -> bool:
        return not self.flag & 0x1

    @property
    def double_sided(self) -> bool:
        return bool(self.flag & 0x2)

    @property
    def gradation(self) -> bool:
        return bool(self.flag & 0x4)

    @property
    def brightness_off(self) -> bool:  # TGE: texture colour not modulated
        return bool(self.mode & 0x1)

    @property
    def semi_transparent(self) -> bool:
        return bool(self.mode & 0x2)

    @property
    def textured(self) -> bool:
        return bool(self.mode & 0x4)

    @property
    def gouraud(self) -> bool:
        return bool(self.mode & 0x10)

    def tpage_info(self) -> Optional[dict]:
        if self.tsb is None:
            return None
        return {
            "x": (self.tsb & 0xF) * 64,
            "y": ((self.tsb >> 4) & 0x1) * 256,
            "abr": (self.tsb >> 5) & 0x3,
            "bpp": {0: 4, 1: 8, 2: 16}.get((self.tsb >> 7) & 0x3, 16),
        }

    def clut_info(self) -> Optional[dict]:
        if self.cba is None:
            return None
        return {"x": (self.cba & 0x3F) * 16, "y": (self.cba >> 6) & 0x1FF}

    def to_dict(self) -> dict:
        d = {
            "offset": self.offset, "olen": self.olen, "ilen": self.ilen, "flag": self.flag, "mode": self.mode,
            "kind": self.kind, "vertices": list(self.vertices), "normals": list(self.normals),
            "uvs": [list(uv) for uv in self.uvs], "cba": self.cba, "tsb": self.tsb,
            "colors": [list(c) for c in self.colors],
        }
        if self.size is not None:
            d["size"] = list(self.size)
        return d


@dataclass(frozen=True)
class TmdObject:
    index: int
    vert_top: int  # absolute offsets within the source buffer
    normal_top: int
    primitive_top: int
    scale: int
    vertices: tuple  # (x, y, z) raw i16
    normals: tuple  # (x, y, z) raw i16, 4.12 fixed point
    primitives: tuple
    nonzero_pads: int  # vertex/normal pad words that are not zero (should be 0)
    n_vert_declared: int = None  # counts in the object table; fewer than len(vertices/normals) when
    n_normal_declared: int = None  # primitives index past them (lenient parse, see `parse`)

    def header_info(self) -> dict:
        return {
            "index": self.index, "vert_top": self.vert_top, "n_vert": self.n_vert_declared,
            "normal_top": self.normal_top, "n_normal": self.n_normal_declared,
            "n_vert_read": len(self.vertices), "n_normal_read": len(self.normals),
            "primitive_top": self.primitive_top, "n_primitive": len(self.primitives), "scale": self.scale,
        }


@dataclass(frozen=True)
class Tmd:
    offset: int
    flags: int
    objects: tuple
    end: int  # first byte after the last block, relative to the buffer

    @property
    def size(self) -> int:
        return self.end - self.offset


def packet_layout(flag: int, mode: int):
    """Return (kind, fields) for a primitive, fields = list of (name, byte size) in file order."""
    code = (mode >> 5) & 0x7
    lit = not flag & 0x1
    gradation = bool(flag & 0x4)
    textured = bool(mode & 0x4)
    quad = bool(mode & 0x8)
    gouraud = bool(mode & 0x10)

    if code == 3:  # sprite
        fields = [("v0", 2), ("tsb", 2), ("u0", 1), ("v0uv", 1), ("cba", 2)]
        if (mode >> 3) & 0x3 == 0:  # free size
            fields += [("w", 2), ("h", 2)]
        return "sprite", fields
    if code == 2:  # straight line
        fields = []
        for i in range(2 if gouraud else 1):
            fields += [(f"r{i}", 1), (f"g{i}", 1), (f"b{i}", 1), ("mode" if i == 0 else "pad1", 1)]
        return "line", fields + [("vert0", 2), ("vert1", 2)]
    if code != 1:
        raise TmdError(f"unsupported primitive code {code}")

    n = 4 if quad else 3
    fields = []
    if textured:
        extra = ["cba", "tsb", "pad2", "pad2"]
        for i in range(n):
            fields += [(f"u{i}", 1), (f"v{i}", 1), (extra[i], 2)]
    has_colors = not textured or not lit
    if has_colors:
        n_colors = n if gradation or (not lit and gouraud) else 1
        for i in range(n_colors):
            fields += [(f"r{i}", 1), (f"g{i}", 1), (f"b{i}", 1), ("mode" if i == 0 else "pad1", 1)]
    if lit:
        if gouraud:
            for i in range(n):
                fields += [(f"norm{i}", 2), (f"vert{i}", 2)]
        else:
            fields += [("norm0", 2)] + [(f"vert{i}", 2) for i in range(n)]
    else:
        fields += [(f"vert{i}", 2) for i in range(n)]
    if (quad and lit and not gouraud) or (not quad and not lit):
        fields += [("pad2", 2)]
    return ("quad" if quad else "triangle"), fields


def _read_fields(data: bytes, pos: int, fields: list) -> dict:
    values = {}
    for name, size in fields:
        value = data[pos] if size == 1 else struct.unpack_from("<H", data, pos)[0]
        values.setdefault(name, value)  # keep the first "pad2"/"pad1"
        pos += size
    return values


def _primitive(data: bytes, pos: int) -> Primitive:
    olen, ilen, flag, mode = data[pos:pos + 4]
    kind, fields = packet_layout(flag, mode)
    used = sum(size for _, size in fields)
    if (used + 3) // 4 != ilen:
        raise TmdError(f"packet at 0x{pos:X}: layout {used} bytes does not match ilen {ilen} (flag 0x{flag:02X} mode 0x{mode:02X})")
    if pos + 4 + ilen * 4 > len(data):
        raise TmdError("truncated primitive")
    f = _read_fields(data, pos + 4, fields)
    if kind == "sprite":
        siz = (mode >> 3) & 0x3
        size = (f["w"], f["h"]) if siz == 0 else {1: (1, 1), 2: (8, 8), 3: (16, 16)}[siz]
        return Primitive(pos, olen, ilen, flag, mode, kind, (f["v0"],), (), ((f["u0"], f["v0uv"]),),
                         f["cba"], f["tsb"], (), size)
    n = {"triangle": 3, "quad": 4, "line": 2}[kind]
    verts = tuple(f[f"vert{i}"] for i in range(n))
    norms = tuple(f[f"norm{i}"] for i in range(n) if f"norm{i}" in f)
    uvs = tuple((f[f"u{i}"], f[f"v{i}"]) for i in range(n) if f"u{i}" in f)
    colors = tuple((f[f"r{i}"], f[f"g{i}"], f[f"b{i}"]) for i in range(n) if f"r{i}" in f)
    return Primitive(pos, olen, ilen, flag, mode, kind, verts, norms, uvs, f.get("cba"), f.get("tsb"), colors)


def parse(data: bytes, offset: int = 0, strict: bool = True) -> Tmd:
    """Parse a TMD at `offset`.

    strict=False accepts primitives that index vertices/normals past the object's declared
    counts: the GTE just reads the following 8-byte entries, so those are read from the buffer
    too (some MMD models rely on this). The declared counts are kept on the object.
    """
    def u32(pos):
        if pos + 4 > len(data):
            raise TmdError("truncated")
        return struct.unpack_from("<I", data, pos)[0]

    if u32(offset) != TMD_ID:
        raise TmdError("bad id")
    flags = u32(offset + 4)
    if flags not in (0, 1):
        raise TmdError(f"bad flags {flags}")
    nobj = u32(offset + 8)
    if not 0 < nobj <= MAX_OBJECTS:
        raise TmdError(f"bad object count {nobj}")
    table = offset + 12
    base = 0 if flags else table
    end = table + nobj * 28

    objects = []
    for i in range(nobj):
        vt, nv, nt, nn, pt, np_, scale = struct.unpack_from("<6Ii", data, table + i * 28)
        if max(nv, nn, np_) > MAX_ITEMS:
            raise TmdError(f"object {i}: too many items")
        vt, nt, pt = vt + base, nt + base, pt + base
        if vt + nv * 8 > len(data) or nt + nn * 8 > len(data) or pt > len(data):
            raise TmdError(f"object {i}: block outside buffer")
        verts, norms, pads = [], [], 0
        for k in range(nv):
            x, y, z, pad = struct.unpack_from("<hhhH", data, vt + k * 8)
            verts.append((x, y, z))
            pads += pad != 0
        for k in range(nn):
            x, y, z, pad = struct.unpack_from("<hhhH", data, nt + k * 8)
            norms.append((x, y, z))
            pads += pad != 0
        prims, pos = [], pt
        for _ in range(np_):
            if pos + 4 > len(data):
                raise TmdError("truncated primitive header")
            p = _primitive(data, pos)
            if any(v >= nv for v in p.vertices) or any(n >= nn for n in p.normals):
                if strict:
                    raise TmdError(f"object {i}: primitive at 0x{pos:X} indexes out of range")
                for block, items, idx in ((vt, verts, max(p.vertices)), (nt, norms, max(p.normals, default=-1))):
                    while len(items) <= idx:
                        if block + len(items) * 8 + 8 > len(data):
                            raise TmdError(f"object {i}: primitive at 0x{pos:X} indexes past the buffer")
                        x, y, z, pad = struct.unpack_from("<hhhH", data, block + len(items) * 8)
                        items.append((x, y, z))
            prims.append(p)
            pos += 4 + p.ilen * 4
        end = max(end, vt + nv * 8, nt + nn * 8, pos)
        objects.append(TmdObject(i, vt, nt, pt, scale, tuple(verts), tuple(norms), tuple(prims), pads, nv, nn))

    return Tmd(offset, flags, tuple(objects), end)


def try_parse(data: bytes, offset: int = 0, strict: bool = True) -> Optional[Tmd]:
    try:
        return parse(data, offset, strict)
    except (TmdError, struct.error):
        return None


def update_texture_data(tmd: Tmd, pixel_page: int, offset: tuple, clut_delta: int) -> Tmd:
    """updateTMDTextureData (graphics.c:156): TSB page bits = pixel_page, CBA += clut_delta,
    UV += offset; like the game, each object is patched only up to its first untextured primitive."""
    du, dv = offset
    objects = []
    for obj in tmd.objects:
        prims, patching = [], True
        for p in obj.primitives:
            patching = patching and p.textured
            if patching:
                p = dataclasses.replace(p, tsb=(p.tsb & 0xFFE0) + pixel_page, cba=p.cba + clut_delta,
                                        uvs=tuple(((u + du) & 0xFF, (v + dv) & 0xFF) for u, v in p.uvs))
            prims.append(p)
        objects.append(dataclasses.replace(obj, primitives=tuple(prims)))
    return dataclasses.replace(tmd, objects=tuple(objects))
