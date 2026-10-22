"""TMD -> glTF conversion (geometry, materials, texture pages). Used by AssetWriter.write_tmd.

See exporters/gltf.py for axis, unit, winding and UV conventions, and specs/tmd.md.
"""

import math
from pathlib import Path

from .exporters import png
from .exporters.gltf import GltfBuilder
from .formats.vram import PAGE_SIZE, Vram

# Corner order per polygon kind (PSX order -> glTF counter-clockwise triangles).
CORNERS = {"triangle": (0, 2, 1), "quad": (0, 2, 1, 1, 2, 3)}


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


def build(base: Path, asset_id: str, tmd, vram: Vram = None) -> dict:
    """Write <base>.gltf/.bin and texture pages under <base>_tex/. Returns output and texture info."""
    tex_dir = base.parent / f"{base.name}_tex"
    builder = GltfBuilder(base.name)

    # Texture pages used by the model, with the UV area each one needs.
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
                "uv_box": [u0, v0, u1, v1], "path": None, "missing_texels_in_uv_box": None, "vram_sources": None}
        if vram is not None:
            rgba, loaded = vram.sample_page(*key)
            path = tex_dir / _texture_name(key)
            png.write(path, png.encode_rgba(PAGE_SIZE, PAGE_SIZE, rgba))
            info["path"] = path
            info["missing_texels_in_uv_box"] = sum(1 for v in range(v0, v1 + 1) for u in range(u0, u1 + 1)
                                                   if not loaded[v * PAGE_SIZE + u])
            width = {4: 64, 8: 128, 16: 256}[key[2]]
            info["vram_sources"] = {
                "page": sorted(set(vram.sources_in(key[0], key[1], width, PAGE_SIZE))),
                "clut": sorted(set(vram.sources_in(key[3], key[4], {4: 16, 8: 256}.get(key[2], 1), 1))),
            }
        textures[key] = info

    materials = {}

    def material_index(p) -> int:
        mkey = _material_key(p)
        if mkey not in materials:
            uri = None
            if p.textured and textures[_texture_key(p)]["path"] is not None:
                uri = f"{tex_dir.name}/{textures[_texture_key(p)]['path'].name}"
            name = f"tsb{p.tsb}_cba{p.cba}" if p.textured else "untextured"
            name += f"_{'lit' if p.lit else 'unlit'}{'_semi' if p.semi_transparent else ''}{'_2side' if p.double_sided else ''}"
            materials[mkey] = builder.material(name, uri, p.double_sided, p.semi_transparent, not p.lit,
                                               _material_extras(p))
        return materials[mkey]

    for obj in tmd.objects:
        scale = 2.0 ** obj.scale
        groups = {}
        for p in obj.primitives:
            groups.setdefault(material_index(p), []).append(p)
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
        builder.node(f"object_{obj.index}", primitives, obj.header_info())

    paths = builder.write(base.with_suffix(".gltf"), {"asset_id": asset_id})
    return {"files": paths, "textures": list(textures.values())}
