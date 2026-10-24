"""TMD -> glTF conversion (geometry, materials, texture pages, skeletons, animations).

Used by AssetWriter.write_tmd (static models) and write_mmd (Digimon models). See
exporters/gltf.py for axis, unit, winding and UV conventions, and specs/tmd.md, specs/mmd.md.
"""

import math
from pathlib import Path

from .exporters import png
from .exporters.gltf import GltfBuilder
from .formats.vram import PAGE_SIZE, Vram

# Corner order per polygon kind (PSX order -> glTF counter-clockwise triangles).
CORNERS = {"triangle": (0, 2, 1), "quad": (0, 2, 1, 1, 2, 3)}
FPS = 20


def _texture_key(p) -> tuple:
    tp, cl = p.tpage_info(), p.clut_info()
    return tp["x"], tp["y"], tp["bpp"], cl["x"], cl["y"]


def _texture_name(key: tuple) -> str:
    px, py, bpp, cx, cy = key
    return f"page_{px}_{py}_{bpp}bpp_clut_{cx}_{cy}.png"


def _material_key(p) -> tuple:
    return (p.textured, p.tsb if p.textured else None, p.cba if p.textured else None,
            p.semi_transparent, p.double_sided, p.lit, p.brightness_off)


def _material_extras(p) -> dict:
    extras = {"lit": p.lit, "double_sided": p.double_sided, "semi_transparent": p.semi_transparent,
              "brightness_off": p.brightness_off, "textured": p.textured}
    if p.textured:
        extras.update({"tsb": p.tsb, "cba": p.cba, "tpage": p.tpage_info(), "clut": p.clut_info()})
    return extras


def _normal(n: tuple) -> tuple:
    x, y, z = n[0] / 4096, -n[1] / 4096, -n[2] / 4096
    length = math.sqrt(x * x + y * y + z * z) or 1.0
    return x / length, y / length, z / length


def _color(c: tuple, textured: bool) -> tuple:
    # Textured polygons modulate the texture (128 = unchanged); untextured ones use the colour as is.
    if textured:
        return tuple(min(v / 128, 1.0) for v in c) + (1.0,)
    return tuple(v / 255 for v in c) + (1.0,)


def _build_textures(tmd, vram: Vram, tex_dir: Path) -> dict:
    """Texture pages used by the model, sampled through `vram` (none written if vram is None)."""
    used = {}
    for obj in tmd.objects:
        for p in obj.primitives:
            if p.textured:
                us, vs = [uv[0] for uv in p.uvs], [uv[1] for uv in p.uvs]
                box = used.setdefault(_texture_key(p), [255, 255, 0, 0])
                box[:] = [min(box[0], *us), min(box[1], *vs), max(box[2], *us), max(box[3], *vs)]

    textures = {}
    for key, (u0, v0, u1, v1) in sorted(used.items()):
        info = {"page": {"x": key[0], "y": key[1], "bpp": key[2]}, "clut": {"x": key[3], "y": key[4]},
                "uv_box": [u0, v0, u1, v1], "path": None, "stp_path": None, "missing_texels_in_uv_box": None,
                "vram_sources": None}
        if vram is not None:
            rgba, loaded, stp = vram.sample_page_stp(*key)
            path = tex_dir / _texture_name(key)
            png.write(path, png.encode_rgba(PAGE_SIZE, PAGE_SIZE, rgba))
            info["path"] = path
            # STP mask (255 = bit set), only when a texel has it: a semi-transparent polygon blends
            # only those texels, the others are opaque (tmd.md "Godot representation").
            if any(stp):
                stp_path = path.with_name(path.stem + ".stp.png")
                png.write(stp_path, png.encode_gray(PAGE_SIZE, PAGE_SIZE, bytes(255 if b else 0 for b in stp)))
                info["stp_path"] = stp_path
            info["missing_texels_in_uv_box"] = sum(1 for v in range(v0, v1 + 1) for u in range(u0, u1 + 1)
                                                   if not loaded[v * PAGE_SIZE + u])
            width = {4: 64, 8: 128, 16: 256}[key[2]]
            info["vram_sources"] = {
                "page": sorted(set(vram.sources_in(key[0], key[1], width, PAGE_SIZE))),
                "clut": sorted(set(vram.sources_in(key[3], key[4], {4: 16, 8: 256}.get(key[2], 1), 1))),
            }
        textures[key] = info
    return textures


class _Materials:
    def __init__(self, builder: GltfBuilder, textures: dict, tex_dir: Path):
        self.builder, self.textures, self.tex_dir, self.cache = builder, textures, tex_dir, {}

    def index(self, p) -> int:
        mkey = _material_key(p)
        if mkey not in self.cache:
            uri = None
            extras = _material_extras(p)
            if p.textured and self.textures[_texture_key(p)]["path"] is not None:
                uri = f"{self.tex_dir.name}/{self.textures[_texture_key(p)]['path'].name}"
                stp_path = self.textures[_texture_key(p)]["stp_path"]
                if p.semi_transparent and stp_path is not None:
                    extras["stp_texture"] = f"{self.tex_dir.name}/{stp_path.name}"
            name = f"tsb{p.tsb}_cba{p.cba}" if p.textured else "untextured"
            name += f"_{'lit' if p.lit else 'unlit'}{'_semi' if p.semi_transparent else ''}{'_2side' if p.double_sided else ''}"
            self.cache[mkey] = self.builder.material(name, uri, p.double_sided, p.semi_transparent, not p.lit,
                                                     extras)
        return self.cache[mkey]


def _object_primitives(builder: GltfBuilder, obj, materials: _Materials) -> list:
    scale = 2.0 ** obj.scale
    groups = {}
    for p in obj.primitives:
        groups.setdefault(materials.index(p), []).append(p)
    primitives = []
    for mat, prims in sorted(groups.items()):
        pos, nrm, uvs, col = [], [], [], []
        for p in prims:
            n = len(p.vertices)
            for c in CORNERS[p.kind]:
                x, y, z = obj.vertices[p.vertices[c]]
                pos.append((x * scale, -y * scale, -z * scale))
                if p.normals:
                    nrm.append(_normal(obj.normals[p.normals[c if len(p.normals) == n else 0]]))
                if p.uvs:
                    uvs.append((p.uvs[c][0] / PAGE_SIZE, p.uvs[c][1] / PAGE_SIZE))
                if p.colors:
                    col.append(_color(p.colors[c if len(p.colors) == n else 0], p.textured))
        primitives.append(builder.mesh_primitive(pos, nrm, uvs, col, mat,
                                                 {"psx_primitive_offsets": [p.offset for p in prims]}))
    return primitives


def build(base: Path, asset_id: str, tmd, vram: Vram = None) -> dict:
    """Static model: one root node per TMD object. Writes <base>.gltf/.bin and <base>_tex/."""
    tex_dir = base.parent / f"{base.name}_tex"
    builder = GltfBuilder(base.name)
    textures = _build_textures(tmd, vram, tex_dir)
    materials = _Materials(builder, textures, tex_dir)
    for obj in tmd.objects:
        builder.node(f"object_{obj.index}", _object_primitives(builder, obj, materials), obj.header_info())
    paths = builder.write(base.with_suffix(".gltf"), {"asset_id": asset_id})
    return {"files": paths, "textures": list(textures.values())}


# Skeletal models -----------------------------------------------------------------------------

def _quat_mul(a, b):
    ax, ay, az, aw = a
    bx, by, bz, bw = b
    return (aw * bx + ax * bw + ay * bz - az * by, aw * by - ax * bz + ay * bw + az * bx,
            aw * bz + ax * by - ay * bx + az * bw, aw * bw - ax * bx - ay * by - az * bz)


def _axis_quat(axis: int, angle: float):
    s, c = math.sin(angle / 2), math.cos(angle / 2)
    q = [0.0, 0.0, 0.0, c]
    q[axis] = s
    return tuple(q)


def pose_rotation(rx: int, ry: int, rz: int) -> tuple:
    """glTF quaternion (x, y, z, w) of libgte RotMatrix = Rx*Ry*Rz after the (x, -y, -z) axis flip."""
    k = 2 * math.pi / 4096
    return _quat_mul(_quat_mul(_axis_quat(0, rx * k), _axis_quat(1, -ry * k)), _axis_quat(2, -rz * k))


def pose_trs(pose: list) -> tuple:
    sx, sy, sz, rx, ry, rz, lx, ly, lz = pose
    return (lx, -ly, -lz), pose_rotation(rx, ry, rz), (sx / 4096, sy / 4096, sz / 4096)


def _keep_keys(values: list, linear) -> list:
    """Indices of keys to keep: first, last, and every key that is not exactly reproduced by
    interpolating its neighbours (`linear(prev, cur, next)` decides)."""
    if len(values) <= 2:
        return list(range(len(values)))
    keep = [0]
    for i in range(1, len(values) - 1):
        if not linear(values[keep[-1]], values[i - 1], values[i], values[i + 1]):
            keep.append(i)
    keep.append(len(values) - 1)
    return keep


def _linear_ints(first, prev, cur, nxt) -> bool:
    # Same step on both sides: the run since the last kept key has a constant step per axis.
    return all(c - p == n - c for p, c, n in zip(prev, cur, nxt))


def _linear_rotation(first, prev, cur, nxt) -> bool:
    # Interpolating quaternions reproduces linear Euler steps exactly only when at most one axis
    # changes over the run (see specs/mmd.md).
    if not _linear_ints(first, prev, cur, nxt):
        return False
    changing = [i for i in range(3) if first[i] != nxt[i]]
    # Slerp takes the shortest arc: keep runs well below 180 degrees (1024 = 90 degrees).
    return len(changing) <= 1 and all(abs(nxt[i] - first[i]) < 1024 for i in changing)


def _linear_floats(first, prev, cur, nxt) -> bool:
    return all(abs((c - p) - (n - c)) <= 1e-9 * max(1.0, abs(c)) for p, c, n in zip(prev, cur, nxt))


def _continuous(quats: list) -> list:
    out = []
    for q in quats:
        if out and sum(a * b for a, b in zip(out[-1], q)) < 0:
            q = tuple(-c for c in q)
        out.append(q)
    return out


def build_skeletal(base: Path, asset_id: str, tmd, vram: Vram, skeleton: list, rest: list,
                   animations: list, extras: dict = None) -> dict:
    """Digimon model: one node per bone (mesh = the bone's TMD object), rigid hierarchy.

    skeleton: [(object or 0xFF, parent bone or 0xFF)] per bone. rest: pose per bone
    ([sx, sy, sz, rx, ry, rz, lx, ly, lz]). animations: dicts with "name", "frames" (per tick, per
    bone poses), "root_location" (per tick), "extras".
    """
    tex_dir = base.parent / f"{base.name}_tex"
    builder = GltfBuilder(base.name)
    textures = _build_textures(tmd, vram, tex_dir)
    materials = _Materials(builder, textures, tex_dir)

    nodes = []
    for bone, (obj_index, parent) in enumerate(skeleton):
        t, r, s = pose_trs(rest[bone])
        if bone == 0:
            t = (0.0, 0.0, 0.0)
        prims = _object_primitives(builder, tmd.objects[obj_index], materials) if obj_index != 0xFF else []
        node_extras = {"bone": bone, "object": None if obj_index == 0xFF else obj_index,
                       "parent": None if parent == 0xFF else parent}
        if obj_index != 0xFF:
            node_extras["tmd_object"] = tmd.objects[obj_index].header_info()
        nodes.append(builder.node(f"bone_{bone}", prims, node_extras,
                                  None if parent == 0xFF else nodes[parent], t, r, s))

    builder.skin("skeleton", nodes, nodes[0])

    key_count = 0
    for anim in animations:
        frames = anim["frames"]
        times = [i / FPS for i in range(len(frames))]
        channels = []
        for bone in range(len(skeleton)):
            scales = [tuple(f[bone][0:3]) for f in frames]
            rots = [tuple(f[bone][3:6]) for f in frames]
            if bone == 0:
                locs = [(x, -y, -z) for x, y, z in anim["root_location"]]
                loc_keep = _keep_keys(locs, _linear_floats)
                loc_values = [locs[i] for i in loc_keep]
            else:
                locs = [tuple(f[bone][6:9]) for f in frames]
                loc_keep = _keep_keys(locs, _linear_ints)
                loc_values = [(locs[i][0], -locs[i][1], -locs[i][2]) for i in loc_keep]
            rot_keep = _keep_keys(rots, _linear_rotation)
            scale_keep = _keep_keys(scales, _linear_ints)
            channels.append((nodes[bone], "translation", [times[i] for i in loc_keep], loc_values, "LINEAR"))
            channels.append((nodes[bone], "rotation", [times[i] for i in rot_keep],
                             _continuous([pose_rotation(*rots[i]) for i in rot_keep]), "LINEAR"))
            channels.append((nodes[bone], "scale", [times[i] for i in scale_keep],
                             [tuple(v / 4096 for v in scales[i]) for i in scale_keep], "LINEAR"))
            key_count += len(loc_keep) + len(rot_keep) + len(scale_keep)
        builder.animation(anim["name"], channels, anim.get("extras"))

    root_extras = {"asset_id": asset_id, "fps": FPS}
    if extras:
        root_extras.update(extras)
    paths = builder.write(base.with_suffix(".gltf"), root_extras)
    return {"files": paths, "textures": list(textures.values()), "animation_keys": key_count}
