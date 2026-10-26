"""Field maps: MAP (setup, images, objects, entities, collision) and TFS (background tiles).

MAP layout (offsets from the file start; counts come from the MAP_ENTRIES table in the executable):
    u32 setup_offset
    u32 image8_offset  x num8bppImages     8bpp TIMs (loadMapImage1)
    u32 image4_offset  x num4bppImages     4bpp TIMs (loadMapImage2)
    u32 objects_offset                     only if any images
    u32 entities_offset
    u32 collision_offset

TFS layout:
    u16 width, u16 height, u32 palette_count, palette_count x 256 u16 colours,
    then one tile per non -1 entry of the MAP tile layout: u32 header + 128 x 128 8bpp indices.

See specs/map.md for the game code each section comes from.
"""

import math
import struct
from dataclasses import dataclass

from . import tim as timfmt

TILE = 128
COLLISION_SIZE = 100  # cells per side, 100 units each, centred on the origin


class MapError(ValueError):
    pass


def _i32s(data: bytes, pos: int, n: int) -> list:
    if pos + 4 * n > len(data):
        raise MapError(f"truncated at 0x{pos:X}")
    return list(struct.unpack_from(f"<{n}i", data, pos))


def _i16s(data: bytes, pos: int, n: int) -> list:
    if pos + 2 * n > len(data):
        raise MapError(f"truncated at 0x{pos:X}")
    return list(struct.unpack_from(f"<{n}h", data, pos))


@dataclass
class TfsFile:
    width: int
    height: int
    palettes: list  # lists of 256 raw u16 colours
    tiles: list  # (offset, header u32, 16384 index bytes)
    end: int


def parse_tfs(data: bytes, tile_count: int) -> TfsFile:
    if len(data) < 8:
        raise MapError("truncated TFS")
    width, height, count = struct.unpack_from("<HHI", data, 0)
    if count > 16:
        raise MapError(f"implausible palette count {count}")
    pos = 8
    palettes = []
    for _ in range(count):
        palettes.append(list(struct.unpack_from("<256H", data, pos)))
        pos += 512
    tiles = []
    for _ in range(tile_count):
        if pos + 4 + TILE * TILE > len(data):
            raise MapError(f"TFS: tile {len(tiles)} truncated")
        tiles.append((pos, struct.unpack_from("<I", data, pos)[0], bytes(data[pos + 4:pos + 4 + TILE * TILE])))
        pos += 4 + TILE * TILE
    return TfsFile(width, height, palettes, tiles, pos)


def parse_map(data: bytes, num8: int, num4: int, has_digimon: bool) -> dict:
    """Parse a MAP file the way loadMap reads it. Returns plain data (all raw values kept)."""
    words = 1 + num8 + num4 + (1 if num8 or num4 else 0) + 2
    header = list(struct.unpack_from(f"<{words}I", data, 0))
    setup_off = header[0]
    image8 = header[1:1 + num8]
    image4 = header[1 + num8:1 + num8 + num4]
    objects_off = header[1 + num8 + num4] if num8 or num4 else None
    entities_off, collision_off = header[-2], header[-1]
    spans = [(0, 4 * words)]

    # loadMapSetup (map.c:4143)
    # words: 0-2 viewpoint, 3-5 reference, 6-23 lights (x, y, z, r, g, b), 24-26 ambient,
    # 27 projection, 28-31 liked regions, 32-35 disliked regions, 36 width, 37 height, then tiles
    s = _i32s(data, setup_off, 38)
    width, height = s[36], s[37]
    if not (0 < width <= 16 and 0 < height <= 16):
        raise MapError(f"implausible tile layout {width}x{height}")
    tiles = _i32s(data, setup_off + 4 * 38, width * height)
    setup = {
        "viewpoint": s[0:3], "reference": s[3:6],  # stored halved; the game doubles them
        "lights": [{"direction": s[6 + 6 * i:9 + 6 * i], "color": s[9 + 6 * i:12 + 6 * i]} for i in range(3)],
        "ambient": s[24:27], "projection": s[27], "liked_regions": s[28:32], "disliked_regions": s[32:36],
        "width": width, "height": height, "tiles": tiles,
    }
    spans.append((setup_off, setup_off + 4 * (38 + width * height)))

    images = []
    for kind, offsets in (("8bpp", image8), ("4bpp", image4)):
        for index, off in enumerate(offsets):
            t = timfmt.parse(data, off)
            images.append({"kind": kind, "index": index, "offset": off, "tim": t})
            spans.append((off, off + t.size))

    objects = None
    if objects_off is not None:
        pos = objects_off
        (count,) = _i16s(data, pos, 1)
        pos += 2
        defs = []
        for _ in range(count):
            v = _i16s(data, pos, 9)
            pos += 18
            defs.append({"tex_x": v[0], "tex_y": v[1], "width": v[2], "height": v[3], "pos3d": v[4:7],
                         "clut": v[7], "transparency": v[8]})
        (inst_count,) = _i16s(data, pos, 1)
        pos += 2
        insts = []
        for _ in range(inst_count):
            v = _i16s(data, pos, 19)
            pos += 38
            insts.append({"sprites": v[0:8], "times": v[8:16], "x": v[16], "y": v[17], "flag": v[18]})
        objects = {"definitions": defs, "instances": insts}
        spans.append((objects_off, pos))

    # loadMapEntities (tamer.c:379) + loadMapDigimon (overworld.c:1026)
    pos = entities_off
    w = _i16s(data, pos, 60)
    pos += 120
    spawns = [{"x": w[i], "y": w[10 + i], "z": w[20 + i], "rotation": w[30 + i]} for i in range(10)]
    warps = [{"map": w[40 + i], "spawn": w[50 + i]} for i in range(10)]
    (digimon_count,) = _i16s(data, pos, 1)
    pos += 2
    digimon = []
    if has_digimon:
        for _ in range(digimon_count):
            v = _i16s(data, pos, 42)
            pos += 84
            n = v[33]
            waypoints = _i16s(data, pos, 3 * n)
            pos += 6 * n
            digimon.append({
                "type": v[0], "follow_mode": v[1], "position": v[2:5], "rotation": v[5:8], "tracking_range": v[8],
                "unk2": v[9], "script_id": v[10], "hp": v[11], "mp": v[12], "current_hp": v[13], "current_mp": v[14],
                "offense": v[15], "defense": v[16], "speed": v[17], "brains": v[18], "bits": v[19],
                "charge_mode": v[20], "unk1": v[21], "targets_partner": v[21] == 1, "moves": v[22:26], "move_priority": v[26:30], "flee": v[30:33],
                "ai_sections": v[34:42], "waypoints": [waypoints[3 * i:3 * i + 3] for i in range(n)],
            })
    spans.append((entities_off, pos))

    if collision_off + COLLISION_SIZE * COLLISION_SIZE > len(data):
        raise MapError("collision data truncated")
    collision = bytes(data[collision_off:collision_off + COLLISION_SIZE * COLLISION_SIZE])
    spans.append((collision_off, collision_off + len(collision)))

    return {"header": header, "setup": setup, "images": images, "objects": objects, "spawns": spawns,
            "warps": warps, "digimon_count": digimon_count, "digimon": digimon, "collision": collision,
            "spans": sorted(spans)}


# Camera ------------------------------------------------------------------------------------

def camera(setup: dict) -> dict:
    """GsSetRefView2 camera (PSX axes, +Y down): eye/target are the setup values doubled."""
    eye = [2 * v for v in setup["viewpoint"]]
    target = [2 * v for v in setup["reference"]]
    f = [t - e for t, e in zip(target, eye)]
    n = math.sqrt(sum(c * c for c in f)) or 1.0
    f = [c / n for c in f]
    down = (0.0, 1.0, 0.0)
    r = [down[1] * f[2] - down[2] * f[1], down[2] * f[0] - down[0] * f[2], down[0] * f[1] - down[1] * f[0]]
    n = math.sqrt(sum(c * c for c in r)) or 1.0
    r = [c / n for c in r]
    d = [f[1] * r[2] - f[2] * r[1], f[2] * r[0] - f[0] * r[2], f[0] * r[1] - f[1] * r[0]]
    return {"eye": eye, "target": target, "right": r, "down": d, "forward": f, "projection": setup["projection"]}


def project(cam: dict, point, bg_size: tuple):
    """World point (PSX axes) -> background pixel (x, y), or None behind the camera.

    Screen = projection * (x/z, y/z) around the screen centre; at load the screen centre shows the
    centre of the background (setupMap: cameraX = width*128/2 - 160, DRAWING_OFFSET = 160, 120).
    """
    rel = [p - e for p, e in zip(point, cam["eye"])]
    z = sum(a * b for a, b in zip(rel, cam["forward"]))
    if z <= 1:
        return None
    x = sum(a * b for a, b in zip(rel, cam["right"]))
    y = sum(a * b for a, b in zip(rel, cam["down"]))
    return bg_size[0] / 2 + cam["projection"] * x / z, bg_size[1] / 2 + cam["projection"] * y / z


def collision_cell_center(tx: int, tz: int) -> tuple:
    """Inverse of getTileTrigger (map_collision.c): cell (tx, tz) -> world (x, 0, z) at its centre."""
    return (tx - 50) * 100 + 50, 0, (50 - tz) * 100 - 50
