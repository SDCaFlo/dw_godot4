"""STDDAT/*.ATR: arena collision grids (100 x 100, like field map collision). Spec: specs/atr.md."""

import collections

from ..assets import AssetWriter, _dump
from ..exporters import png
from ..exporters.gltf import GltfBuilder
from ..source import SourceFile

NAME = "atr_files"
SOURCE_PATH = "STDDAT/*.ATR"
SPEC = "specs/atr.md"
CODE_REFS = [
    "dw_decomp/src/vs/vs_scene.c:1061 VS_ARENA_COLLISIONS[3] = B_TOGI, B_TOGI, E_TOGI; :1695 VS_loadArenaAssets readFile -> MAP_COLLISION_DATA",
    "dw_decomp/src/std/std_main.c:1344 STD_ARENA_COLLISIONS[3] = B_TOGI, B_TOGI, NULL; std_setup.c:655 readFile -> MAP_COLLISION_DATA",
    "dw_decomp/src/main/map_collision.c:57 checkMapCollisionX/Z, :32 getTileTrigger (cell layout)",
    "dw_decomp/src/main/file_table_us.c:766 B_TOGI.ATR 0x2710, :772 E_TOGI.ATR 0x2710",
]

SIZE = 100
CELL = 100
FILE_SIZE = SIZE * SIZE
# stage -> arena model (TMD) for each table that loads the file (specs/atr.md).
USAGE = {
    "B_TOGI": {"vs_stages": [0, 1], "std_stages": [0, 1], "arena_models": ["STDDAT/T_TOGI.TMD", "STDDAT/B_TOGI.TMD"]},
    "E_TOGI": {"vs_stages": [2], "std_stages": [], "arena_models": ["STDDAT/E_TOGI.TMD"]},
}


def _preview(values: bytes) -> bytes:
    scale = 4
    px = bytearray()
    for tz in range(SIZE):
        row = bytearray()
        for tx in range(SIZE):
            v = values[tx + tz * SIZE]
            colour = (235, 235, 235, 255) if v == 0 else (40, 40, 48, 255) if v == 0x80 else (255, 140, 0, 255)
            row += bytes(colour) * scale
        px += bytes(row) * scale
    return png.encode_rgba(SIZE * scale, SIZE * scale, bytes(px))


def _cells_gltf(base, values: bytes, asset_id: str) -> list:
    """Walkable cells as flat quads at y = 0, in the porter's glTF axes (x, -y, -z)."""
    builder = GltfBuilder(base.name)
    positions = []
    for tz in range(SIZE):
        for tx in range(SIZE):
            if values[tx + tz * SIZE] != 0:
                continue
            x0, x1 = (tx - 50) * CELL, (tx - 50) * CELL + CELL
            z0, z1 = (50 - tz) * CELL - CELL, (50 - tz) * CELL
            a, b, c, d = (x0, 0.0, -z0), (x1, 0.0, -z0), (x1, 0.0, -z1), (x0, 0.0, -z1)
            positions += [a, c, b, a, d, c]  # counter-clockwise seen from +Y
    material = builder.material("walkable", double_sided=True)
    prim = builder.mesh_primitive(positions, [(0.0, 1.0, 0.0)] * len(positions), [], [], material)
    builder.node("walkable_cells", [prim], {"cell": CELL, "grid": SIZE})
    return builder.write(base.with_suffix(".gltf"), {"asset_id": asset_id})


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    sources = []
    on_disc = sorted(p.stem for p in (input_root / "STDDAT").glob("*.ATR"))
    out.check("ATR files on disc are the ones the code loads", on_disc == sorted(USAGE), str(on_disc))

    for name in sorted(USAGE):
        path = f"STDDAT/{name}.ATR"
        src = SourceFile.open(input_root, path)
        sources.append(src)
        values = src.data
        out.check(f"{name}: size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, str(src.size))
        counts = collections.Counter(values)
        out.check(f"{name}: only walkable (0) and blocked (0x80) cells", set(counts) <= {0, 0x80},
                  str(sorted(counts.items())))
        walk = [(i % SIZE, i // SIZE) for i, v in enumerate(values) if v == 0]
        box = {"tx": [min(x for x, _ in walk), max(x for x, _ in walk)],
               "tz": [min(z for _, z in walk), max(z for _, z in walk)]} if walk else None
        out.check(f"{name}: walkable area away from the grid edges",
                  box is not None and box["tx"][0] > 0 and box["tz"][0] > 0
                  and box["tx"][1] < SIZE - 1 and box["tz"][1] < SIZE - 1, str(box))

        folder = out.dir / "STDDAT" / name
        span = src.span(0, src.size)
        png.write(folder / "collision.png", png.encode_gray(SIZE, SIZE, values))
        png.write(folder / "preview.png", _preview(values))
        gltf_files = _cells_gltf(folder / "collision_cells", values, span.asset_id)
        outputs = [{"path": out._rel(folder / "collision.png"), "kind": "collision", "encoding": "gray8 raw values"},
                   {"path": out._rel(folder / "preview.png"), "kind": "preview (human check)"},
                   {"path": out._rel(gltf_files[0]), "kind": "walkable cells (human check)", "encoding": "gltf2"}]
        record = {
            "asset_id": span.asset_id,
            "family": NAME,
            "format": "ATR",
            "source": span.identity(),
            "psxprev_name": span.psxprev_name,
            "outputs": outputs,
            "collision": {"size": SIZE, "cell": CELL, "values": list(values),
                          "counts": {str(k): v for k, v in sorted(counts.items())}, "walkable_box": box},
            "usage": USAGE[name],
        }
        _dump(folder / f"{name}.json", record)
        out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(folder / f"{name}.json"),
                           "outputs": [o["path"] for o in outputs]})
    out.finish(sources)
    return out
