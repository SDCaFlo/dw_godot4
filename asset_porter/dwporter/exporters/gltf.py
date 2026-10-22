"""glTF 2.0 writer for TMD models (standard library only). Output: <name>.gltf + <name>.bin.

Conventions (see specs/tmd.md):
- Axes: PSX is +Y down, +Z into the screen; glTF is +Y up. Positions and normals are written as
  (x, -y, -z) (a 180-degree rotation about X, so handedness and winding are preserved).
- Units: raw PSX model units times 2^scale of the object; no other scaling.
- Winding: PSX polygons are clockwise relative to their stored normal; triangles are emitted as
  (0, 2, 1) and quads as (0, 2, 1) + (1, 2, 3) so glTF's counter-clockwise front face matches.
- UVs: texture-page pixels / 256. Textures are 256x256 texture pages built through the VRAM copy.
- Every node, mesh primitive and material keeps its PSX data in `extras`.
"""

import json
import struct
from pathlib import Path

FLOAT, UINT32 = 5126, 5125
ARRAY_BUFFER, ELEMENT_ARRAY_BUFFER = 34962, 34963
NEAREST = 9728


class GltfBuilder:
    def __init__(self, name: str):
        self.name = name
        self.bin = bytearray()
        self.doc = {
            "asset": {"version": "2.0", "generator": "dwporter"},
            "scene": 0, "scenes": [{"nodes": []}], "nodes": [], "meshes": [], "materials": [],
            "textures": [], "images": [], "samplers": [{"magFilter": NEAREST, "minFilter": NEAREST}],
            "accessors": [], "bufferViews": [], "buffers": [],
        }
        self._images = {}
        self._uses_unlit = False

    def _view(self, data: bytes, target: int) -> int:
        while len(self.bin) % 4:
            self.bin.append(0)
        self.doc["bufferViews"].append({"buffer": 0, "byteOffset": len(self.bin), "byteLength": len(data),
                                        "target": target})
        self.bin += data
        return len(self.doc["bufferViews"]) - 1

    def _accessor(self, values: list, kind: str, component: int, target: int, minmax: bool = False) -> int:
        width = {"SCALAR": 1, "VEC2": 2, "VEC3": 3, "VEC4": 4}[kind]
        fmt = "f" if component == FLOAT else "I"
        flat = [c for v in values for c in (v if width > 1 else (v,))]
        acc = {"bufferView": self._view(struct.pack(f"<{len(flat)}{fmt}", *flat), target),
               "componentType": component, "count": len(values), "type": kind}
        if minmax:
            acc["min"] = [min(v[i] for v in values) for i in range(width)]
            acc["max"] = [max(v[i] for v in values) for i in range(width)]
        self.doc["accessors"].append(acc)
        return len(self.doc["accessors"]) - 1

    def image(self, uri: str) -> int:
        if uri not in self._images:
            self.doc["images"].append({"uri": uri})
            self.doc["textures"].append({"sampler": 0, "source": len(self.doc["images"]) - 1})
            self._images[uri] = len(self.doc["textures"]) - 1
        return self._images[uri]

    def material(self, name: str, texture_uri: str = None, double_sided: bool = False, blend: bool = False,
                 unlit: bool = False, extras: dict = None) -> int:
        m = {"name": name, "doubleSided": double_sided, "pbrMetallicRoughness": {"metallicFactor": 0.0, "roughnessFactor": 1.0}}
        if texture_uri:
            m["pbrMetallicRoughness"]["baseColorTexture"] = {"index": self.image(texture_uri)}
            m["alphaMode"] = "BLEND" if blend else "MASK"
            if not blend:
                m["alphaCutoff"] = 0.5
        elif blend:
            m["alphaMode"] = "BLEND"
        if unlit:
            m["extensions"] = {"KHR_materials_unlit": {}}
            self._uses_unlit = True
        if extras:
            m["extras"] = extras
        self.doc["materials"].append(m)
        return len(self.doc["materials"]) - 1

    def mesh_primitive(self, positions, normals, uvs, colors, material: int, extras: dict = None) -> dict:
        """Non-indexed corners (3 per triangle). Lists may be empty when the attribute is absent."""
        attrs = {"POSITION": self._accessor(positions, "VEC3", FLOAT, ARRAY_BUFFER, minmax=True)}
        if normals:
            attrs["NORMAL"] = self._accessor(normals, "VEC3", FLOAT, ARRAY_BUFFER)
        if uvs:
            attrs["TEXCOORD_0"] = self._accessor(uvs, "VEC2", FLOAT, ARRAY_BUFFER)
        if colors:
            attrs["COLOR_0"] = self._accessor(colors, "VEC4", FLOAT, ARRAY_BUFFER)
        indices = self._accessor(list(range(len(positions))), "SCALAR", UINT32, ELEMENT_ARRAY_BUFFER)
        prim = {"attributes": attrs, "indices": indices, "material": material, "mode": 4}
        if extras:
            prim["extras"] = extras
        return prim

    def node(self, name: str, primitives: list, extras: dict = None) -> int:
        node = {"name": name}
        if primitives:
            self.doc["meshes"].append({"name": name, "primitives": primitives})
            node["mesh"] = len(self.doc["meshes"]) - 1
        if extras:
            node["extras"] = extras
        self.doc["nodes"].append(node)
        index = len(self.doc["nodes"]) - 1
        self.doc["scenes"][0]["nodes"].append(index)
        return index

    def write(self, gltf_path: Path, extras: dict = None) -> list:
        """Write <name>.gltf and <name>.bin; returns the written paths."""
        bin_path = gltf_path.with_suffix(".bin")
        self.doc["buffers"] = [{"uri": bin_path.name, "byteLength": len(self.bin)}]
        if self._uses_unlit:
            self.doc["extensionsUsed"] = ["KHR_materials_unlit"]
        for key in ("textures", "images", "materials"):
            if not self.doc[key]:
                del self.doc[key]
        if "textures" not in self.doc:
            del self.doc["samplers"]
        if extras:
            self.doc["extras"] = extras
        gltf_path.parent.mkdir(parents=True, exist_ok=True)
        bin_path.write_bytes(bytes(self.bin))
        gltf_path.write_text(json.dumps(self.doc, indent=1, sort_keys=True) + "\n", encoding="utf-8")
        return [gltf_path, bin_path]
