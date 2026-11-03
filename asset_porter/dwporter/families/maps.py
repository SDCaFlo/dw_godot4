"""MAP/MAP*/*.MAP + *.TFS: field maps. Spec: specs/map.md.

Per MAP_ENTRIES entry with files on disc: background images (one per palette = time of day),
collision grid, map object sprites, doors (glTF, textured from the map's VRAM), all map data as
JSON, and an overview image (projected collision, spawns, NPCs, doors, objects) for checking.
"""

import struct

from ..assets import AssetWriter, _dump
from ..data.digimon import DIGIMON_TYPES
from ..exporters import png
from ..formats import map as mapfmt
from ..formats import psx
from ..formats import tim as timfmt
from ..formats import tmd as tmdfmt
from ..formats.vram import PAGE_SIZE, Vram
from ..source import SourceFile
from . import mmd_files

NAME = "maps"
SOURCE_PATH = "MAP/MAP*/*.MAP + *.TFS"
SPEC = "specs/map.md"
CODE_REFS = [
    "dw_decomp/src/main/map.c:4020 loadMap: header offsets, setup, images, objects, entities, doors, collision",
    "dw_decomp/src/main/map.c:4143 loadMapSetup; :4217 readMapTFS; :4229 setupMap (TFS palettes -> CLUT rows 481+, tiles)",
    "dw_decomp/src/main/map.c:4301 updateTimeOfDay: palette 0 day, 1 evening (16-20h), 2 night (20-6h) -> CLUT row 480",
    "dw_decomp/src/main/overworld.c:380 loadMapImage1 (8bpp), :394 loadMapImage2 (4bpp, first image's CLUT -> row 486)",
    "dw_decomp/src/main/overworld.c:331 loadMapObjects; :732 buildMapOverlayPrim (object tpage/CLUT rules)",
    "dw_decomp/src/main/tamer.c:379 loadMapEntities (spawns, warps); overworld.c:1026 loadMapDigimon",
    "dw_decomp/src/main/map_collision.c:23 loadMapCollisionData (100x100 cells of 100 units)",
    "dw_decomp/src/main/map_object.c:309 loadDoors; door_mapdata.c DOOR_MAPDATA; toilet_data.c TOILET_DATA",
    "dw_decomp/src/main/map.c:5457 loadTrainingLibrary; trn/trn_slots.c TRN_SLOT_SPRITE1/2 (slot strip in the map's 4bpp page)",
]

EXE_LOAD = mmd_files.EXE_LOAD
# dw_decomp/config/us/symbols.txt
MAP_ENTRIES = 0x801292D4  # MapEntry[255], 16 bytes
MAP_NAME_PTR = 0x801291BC  # char *[]
DOOR_MAPDATA = 0x80122E60  # DoorStruct[24], 54 bytes
TOILET_DATA = 0x80122E10  # ToiletData[10], 8 bytes
TIME_OF_DAY = {0: "day", 1: "evening", 2: "night"}
# Maps whose used sprites read VRAM that nothing in the map loads (event scripts / leftover VRAM),
# see specs/map.md: GIAS06B uses CLUT row 485; ICSA05 (warp-crystal map) uses 4bpp pages 448/512.
KNOWN_UNLOADED_CLUT = {"GIAS06B", "ICSA05"}
# Maps that load the TRN overlay (dw_decomp/src/main/map.c:5459 loadTrainingLibrary): TRAI00,
# GIAS09, MIST05. Its slot machine (trn_slots.c TRN_SLOT_SPRITE1/2) draws from the map's VRAM:
# 4bpp page (704, 0), v 0xD8-0xF7; symbols tpage 0x2B + CLUT (48, 486), window tpage 0x4B + CLUT (64, 486).
TRAINING_MAPS = {0x70, 0x4E, 0x77}
SLOT_PAGE, SLOT_V, SLOT_H = (704, 0), 0xD8, 0x20
# Script-spawned props whose TMDs have no texture of their own: they read the map's VRAM (tmd.md "map
# textures"), so they are exported per map like the doors, on the maps whose scripts spawn them
# (../../specs/map_events.md §1; scripts/index.json gives the script each map's MAPHEAD sets).
PROP_TMDS = {
    "TUNN05": ["ETCNA/T_YAMA.TMD"],                       # script 29, routine 0x1B (loadDirtPileModel, map_object.c:1205)
    "OMOC08": ["ETCNA/BIGBOX.TMD", "ETCNA/SMABOX.TMD"],    # script 145, routine 0x2B (spawnToyTownBoxes, :662)
    "OMOC03": ["ETCNA/GAND.TMD"],                         # script 140, routine 0x29 (spawnGearbox, :749)
    "ICSA01": ["ETCNA/ABOX.TMD"],                         # script 93, routine 0x31 (spawnAngemonPedestal, :775)
    "MGEN99": ["ETCHI/BOSS_EFE.TMD"],                     # script 184, routine 0x33 (Machinedramon's rings, eab.c:255)
}
# Monochromon's mood bubble (createMonochromonMoodBubble: routine 0x1C in scripts 199-202, which script
# 49 jumps to, on GCAN11, the Monochrome Shop). Its sprite (script_common.c:271 MONOCHROMON_BUBBLE_SPRITE)
# reads the map's VRAM: 4bpp page (640, 0), u = mood * 32 (moods 0-4), v 0, 32 x 32, CLUT (0, 486),
# attribute 0x50000000 (semi-transparent, rate 1: the STP texels add). GCAN11's 4bpp image 0 is exactly
# that rect (640, 0, 40 x 32 words = 160 x 32 texels).
MOOD_BUBBLE_MAPS = {"GCAN11"}
MOOD_PAGE, MOOD_W, MOOD_H, MOOD_CLUT, MOOD_TPAGE = (640, 0), 5 * 32, 32, (0, 486), 0x0A
SLOT_STRIPS = {3: {"clut": (48, 486), "tpage": 0x2B, "sprite": "TRN_SLOT_SPRITE1 (symbols, u = (symbol - 1) * 32)"},
               4: {"clut": (64, 486), "tpage": 0x4B, "sprite": "TRN_SLOT_SPRITE2 (reel window, u 0xE0, 8 x 32)"}}


def map_path(map_id: int, name: str, ext: str) -> str:
    """buildMapPath (map.c): MAP\\MAP<id/15+1>\\<NAME><ext>."""
    return f"MAP/MAP{map_id // 15 + 1}/{name}{ext}"


def read_tables(exe: bytes) -> dict:
    def at(addr):
        return addr - EXE_LOAD

    entries = []
    for i in range(255):
        raw = exe[at(MAP_ENTRIES) + 16 * i:at(MAP_ENTRIES) + 16 * i + 16]
        num8, num4, flags, doors, toilet, loading = struct.unpack_from("<bbBbbb", raw, 10)
        entries.append({"id": i, "filename": raw[:10].split(b"\0")[0].decode("ascii"), "num_8bpp": num8,
                        "num_4bpp": num4, "flags": flags, "sound_id": flags & 0x1F, "no_time_cycle": bool(flags & 0x40),
                        "has_digimon": bool(flags & 0x80), "doors_id": doors, "toilet_id": toilet, "loading_name": loading})

    def string(addr):
        start = at(addr)
        return exe[start:exe.index(b"\0", start)].decode("ascii", "replace").strip()

    for e in entries:
        ptr = struct.unpack_from("<I", exe, at(MAP_NAME_PTR) + 4 * e["loading_name"])[0]
        e["display_name"] = string(ptr) if ptr else ""
    doors = []
    for i in range(24):
        base = at(DOOR_MAPDATA) + 54 * i
        ids = list(exe[base:base + 6])
        pos = struct.unpack_from("<24h", exe, base + 6)
        doors.append([{"model": ids[k], "position": [pos[k], pos[6 + k], pos[12 + k]], "rotation": pos[18 + k]}
                      for k in range(6)])
    toilets = [list(struct.unpack_from("<4h", exe, at(TOILET_DATA) + 8 * i)) for i in range(10)]
    return {"entries": entries, "doors": doors, "toilets": toilets}


def _map_vram(parsed: dict, tfs, palette: int, label: str) -> Vram:
    """VRAM as loadMap/setupMap leave it, with `palette` as the active (row 480) palette."""
    vram = Vram()
    for i, colors in enumerate(tfs.palettes):
        vram._write(0, 481 + i, 256, 1, colors)
        vram.sources.append((f"{label}.TFS palette {i}", {"x": 0, "y": 481 + i, "w": 256, "h": 1}))
    if tfs.palettes:
        vram._write(0, 480, 256, 1, tfs.palettes[palette])
        vram.sources.append((f"{label}.TFS palette {palette} (active)", {"x": 0, "y": 480, "w": 256, "h": 1}))
    for img in parsed["images"]:
        t = img["tim"]
        name = f"{label}.MAP@0x{img['offset']:X}"
        if img["kind"] == "8bpp":
            if t.clut is not None and t.clut.y == 480:
                vram.load_tim(timfmt.Tim(t.offset, t.flag, t.bpp, None, t.image_block_size, t.x, t.y, t.stride,
                                         t.height, t.pixels), name)
            else:
                vram.load_tim(t, name)
        else:
            vram.load_tim(timfmt.Tim(t.offset, t.flag, t.bpp, None, t.image_block_size, t.x, t.y, t.stride,
                                     t.height, t.pixels), name)
            if img["index"] == 0 and t.clut is not None:
                for row, colors in enumerate(t.clut.palettes):
                    vram._write(row * 16, 486, 16, 1, colors[:16])
                vram.sources.append((f"{name} CLUT -> row 486", {"x": 0, "y": 486, "w": 16 * t.clut.height, "h": 1}))
    return vram


def _object_sprite(vram: Vram, obj: dict, cache: dict):
    """Sprite pixels of a map object, sampled like buildMapOverlayPrim draws it."""
    if obj["clut"] == -1:
        bpp, page_x, clut = 8, 384 + (obj["tex_x"] // 256) * 128, (0, 480)
    elif obj["clut"] < 16:
        bpp, page_x, clut = 4, 384 + (obj["tex_x"] // 256) * 64, (obj["clut"] * 16, 486)
    else:
        bpp, page_x, clut = 8, 384 + (obj["tex_x"] // 256) * 128, (0, obj["clut"] + 468)
    key = (page_x, 0, bpp) + clut
    if key not in cache:
        cache[key] = vram.sample_page_stp(*key)
    rgba, loaded, stp_page = cache[key]
    u0, v0 = obj["tex_x"] % 256, obj["tex_y"] % 256
    w, h = max(obj["width"], 1), max(obj["height"], 1)
    out, stp, missing = bytearray(), bytearray(), 0
    for v in range(v0, v0 + h):
        for u in range(u0, u0 + w):
            i = (v % PAGE_SIZE) * PAGE_SIZE + u % PAGE_SIZE  # UVs are 8-bit: they wrap inside the page
            if loaded[i]:
                out += rgba[i * 4:i * 4 + 4]
                stp.append(255 if stp_page[i] else 0)
            else:
                out += bytes(4)
                stp.append(0)
                missing += 1
    where = {"page": {"x": page_x, "y": 0, "bpp": bpp}, "clut": {"x": clut[0], "y": clut[1]},
             "uv_wraps": u0 + w > PAGE_SIZE or v0 + h > PAGE_SIZE}
    return w, h, bytes(out), missing, where, bytes(stp)


def _training_slots(out: AssetWriter, folder, vram: Vram, msrc, parsed: dict, vram_label: str, label: str) -> dict:
    """Slot machine strip (training.md §7.5): rows v 0xD8-0xF7 of the 4bpp page (704, 0) as the
    map's images leave it, one indexed PNG (+ STP mask) per CLUT the TRN sprites use."""
    px, py = SLOT_PAGE
    indices, loaded = vram.page_indices(px, py, 4, 0, SLOT_V, PAGE_SIZE, SLOT_H)
    rect = {"x": px, "y": py + SLOT_V, "w": PAGE_SIZE // 4, "h": SLOT_H}
    writers = vram.sources_in(rect["x"], rect["y"], rect["w"], rect["h"])  # load order: the last one wins
    # The map image whose texels end up in the strip (the last 4bpp TIM covering it).
    holder = [i for i in parsed["images"] if i["kind"] == "4bpp" and f"{vram_label}.MAP@0x{i['offset']:X}" in writers][-1]
    outputs, cluts, missing = [], {}, loaded.count(0)
    for p, info in SLOT_STRIPS.items():
        cx, cy = info["clut"]
        words = [vram.word(cx + i, cy) for i in range(16)]
        missing += sum(1 for _, ok in words if not ok)
        colors = [c for c, _ in words]
        path = folder / "training" / f"slots_p{p}.png"
        png.write(path, png.encode_indexed(PAGE_SIZE, SLOT_H, indices, [psx.color_to_rgba(c) for c in colors]))
        spath = path.with_name(path.stem + ".stp.png")
        png.write(spath, png.encode_gray(PAGE_SIZE, SLOT_H, bytes(255 if colors[i] >> 15 else 0 for i in indices)))
        outputs += [{"path": out._rel(path), "kind": "training_slots", "encoding": "indexed4", "palette": p},
                    {"path": out._rel(spath), "kind": "stp_mask", "encoding": "gray8", "palette": p}]
        cluts[p] = {"clut": {"x": cx, "y": cy}, "clut_id": psx.get_clut(cx, cy), "colors": colors,
                    "clut_sources": vram.sources_in(cx, cy, 16, 1), "tpage": info["tpage"],
                    "tpage_semi_trans": (info["tpage"] >> 5) & 3, "drawn_by": info["sprite"]}
    out.check(f"{label}: training slot strip fully in loaded VRAM", missing == 0, f"{missing} texels/CLUT entries")
    span = msrc.span(holder["offset"], holder["tim"].size)
    sidecar = folder / "training" / "slots.json"
    record = {
        "asset_id": span.asset_id, "family": NAME, "format": "VRAM (MAP 4bpp TIMs)",
        "source": span.identity(), "psxprev_name": span.psxprev_name, "outputs": outputs,
        "vram": {"page": {"x": px, "y": py, "bpp": 4}, "uv_rect": {"u": 0, "v": SLOT_V, "w": PAGE_SIZE, "h": SLOT_H},
                 "rect": rect, "palettes": cluts},
        "source_images": [{"offset": i["offset"], "index": i["index"], "vram": i["tim"].vram_info()}
                          for i in parsed["images"] if f"{vram_label}.MAP@0x{i['offset']:X}" in writers],
        "code_refs": ["dw_decomp/src/trn/trn_slots.c TRN_SLOT_SPRITE1/2, TRN_renderSlotMachine",
                      "dw_decomp/src/main/map.c:5459 loadTrainingLibrary"],
    }
    _dump(sidecar, record)
    out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(sidecar), "outputs": [o["path"] for o in outputs]})
    return {"outputs": outputs, "key": (indices, tuple(tuple(c["colors"]) for c in cluts.values()))}


def _mood_faces(out: AssetWriter, folder, vram: Vram, msrc, parsed: dict, vram_label: str, label: str) -> list:
    """Monochromon's mood faces (../../specs/map_events.md S10): u 0-159, v 0-31 of the 4bpp page
    (640, 0) as the map's images leave it, through CLUT (0, 486), one indexed PNG + STP mask."""
    px, py = MOOD_PAGE
    indices, loaded = vram.page_indices(px, py, 4, 0, 0, MOOD_W, MOOD_H)
    rect = {"x": px, "y": py, "w": MOOD_W // 4, "h": MOOD_H}
    writers = vram.sources_in(rect["x"], rect["y"], rect["w"], rect["h"])  # load order: the last one wins
    holder = [i for i in parsed["images"] if i["kind"] == "4bpp" and f"{vram_label}.MAP@0x{i['offset']:X}" in writers][-1]
    cx, cy = MOOD_CLUT
    words = [vram.word(cx + i, cy) for i in range(16)]
    missing = loaded.count(0) + sum(1 for _, ok in words if not ok)
    colors = [c for c, _ in words]
    path = folder / "mood" / "faces.png"
    png.write(path, png.encode_indexed(MOOD_W, MOOD_H, indices, [psx.color_to_rgba(c) for c in colors]))
    spath = path.with_name("faces.stp.png")
    png.write(spath, png.encode_gray(MOOD_W, MOOD_H, bytes(255 if colors[i] >> 15 else 0 for i in indices)))
    outputs = [{"path": out._rel(path), "kind": "mood_faces", "encoding": "indexed4"},
               {"path": out._rel(spath), "kind": "stp_mask", "encoding": "gray8"}]
    out.check(f"{label}: mood bubble faces fully in loaded VRAM", missing == 0, f"{missing} texels/CLUT entries")
    span = msrc.span(holder["offset"], holder["tim"].size)
    sidecar = folder / "mood" / "faces.json"
    record = {
        "asset_id": span.asset_id, "family": NAME, "format": "VRAM (MAP 4bpp TIMs)",
        "source": span.identity(), "psxprev_name": span.psxprev_name, "outputs": outputs,
        "vram": {"page": {"x": px, "y": py, "bpp": 4}, "uv_rect": {"u": 0, "v": 0, "w": MOOD_W, "h": MOOD_H},
                 "rect": rect, "clut": {"x": cx, "y": cy}, "clut_id": psx.get_clut(cx, cy), "colors": colors,
                 "clut_sources": vram.sources_in(cx, cy, 16, 1), "tpage": MOOD_TPAGE, "attribute": 0x50000000,
                 "sprite_size": 32, "faces": 5},
        "source_images": [{"offset": i["offset"], "index": i["index"], "vram": i["tim"].vram_info()}
                          for i in parsed["images"] if f"{vram_label}.MAP@0x{i['offset']:X}" in writers],
        "code_refs": ["dw_decomp/src/main/script_common.c:271 MONOCHROMON_BUBBLE_SPRITE",
                      "dw_decomp/src/main/script_common.c:1220 renderMonochromonMoodBubble, 3038 createMonochromonMoodBubble"],
    }
    _dump(sidecar, record)
    out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(sidecar), "outputs": [o["path"] for o in outputs]})
    return outputs


def _background(tfs, setup: dict, palette: int) -> tuple:
    width, height = setup["width"] * mapfmt.TILE, setup["height"] * mapfmt.TILE
    colors = [bytes(psx.color_to_rgba(c)) for c in tfs.palettes[palette]]
    rows = [bytearray(width * 4) for _ in range(height)]
    tile_iter = iter(tfs.tiles)
    for ty in range(setup["height"]):
        for tx in range(setup["width"]):
            if setup["tiles"][tx + ty * setup["width"]] == -1:
                continue
            _, _, indices = next(tile_iter)
            for y in range(mapfmt.TILE):
                row = indices[y * mapfmt.TILE:(y + 1) * mapfmt.TILE]
                rows[ty * mapfmt.TILE + y][tx * mapfmt.TILE * 4:(tx + 1) * mapfmt.TILE * 4] = b"".join(colors[i] for i in row)
    return width, height, b"".join(rows)


def _overview(path, bg: tuple, parsed: dict, doors: list, sprites: dict) -> dict:
    """Background with projected collision cells, spawns, NPCs and doors, and object sprites drawn."""
    width, height, rgba = bg
    img = bytearray(rgba)
    for i in range(width * height):  # no alpha in the overview
        if img[i * 4 + 3] == 0:
            img[i * 4:i * 4 + 4] = b"\x20\x20\x30\xff"

    def blend(x, y, color, alpha=1.0):
        if 0 <= x < width and 0 <= y < height:
            i = (y * width + x) * 4
            for k in range(3):
                img[i + k] = int(img[i + k] * (1 - alpha) + color[k] * alpha)

    def mark(p, color, size):
        if p is None:
            return False
        x, y = int(round(p[0])), int(round(p[1]))
        for dx in range(-size, size + 1):
            for dy in range(-size, size + 1):
                if max(abs(dx), abs(dy)) >= size - 1:
                    blend(x + dx, y + dy, color)
        return 0 <= x < width and 0 <= y < height

    # object sprites (instance frame 0) where the game draws them
    for inst in (parsed["objects"] or {}).get("instances", []):
        sprite = sprites.get(inst["sprites"][0])
        if sprite is None:
            continue
        w, h, px = sprite
        for y in range(h):
            for x in range(w):
                a = px[(y * w + x) * 4 + 3]
                if a:
                    blend(inst["x"] + x, inst["y"] + y, px[(y * w + x) * 4:(y * w + x) * 4 + 3], 0.85)

    cam = mapfmt.camera(parsed["setup"])
    counts = {"collision_cells_drawn": 0, "spawns_on_screen": 0, "digimon_on_screen": 0, "doors_on_screen": 0}
    # collision: 0 = walkable (green), 128 = blocked (not drawn), other values = triggers (orange)
    for tz in range(mapfmt.COLLISION_SIZE):
        for tx in range(mapfmt.COLLISION_SIZE):
            value = parsed["collision"][tx + tz * mapfmt.COLLISION_SIZE]
            if value == 128:
                continue
            p = mapfmt.project(cam, mapfmt.collision_cell_center(tx, tz), (width, height))
            if p is None:
                continue
            x, y = int(p[0]), int(p[1])
            if 0 <= x < width and 0 <= y < height:
                counts["collision_cells_drawn"] += 1
                color = (60, 255, 60) if value == 0 else (255, 150, 0)
                for dx in (-1, 0, 1):
                    for dy in (-1, 0, 1):
                        blend(x + dx, y + dy, color, 0.6)
    for s in parsed["spawns"]:
        if any((s["x"], s["y"], s["z"])):
            counts["spawns_on_screen"] += mark(mapfmt.project(cam, (s["x"], s["y"], s["z"]), (width, height)), (0, 255, 255), 4)
    for d in parsed["digimon"]:
        counts["digimon_on_screen"] += mark(mapfmt.project(cam, d["position"], (width, height)), (255, 255, 0), 5)
    for d in doors:
        counts["doors_on_screen"] += mark(mapfmt.project(cam, d["position"], (width, height)), (255, 0, 255), 6)
    png.write(path, png.encode_rgba(width, height, bytes(img)))
    return counts


def convert(input_root, output_root, map_ids=None) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    exe = SourceFile.open(input_root, mmd_files.EXE)
    tables = read_tables(exe.data)
    sources = [exe]
    referenced = set()
    slot_strips = {}  # map name -> (strip indices, CLUT colours) of the training maps

    for entry in tables["entries"]:
        map_id, name = entry["id"], entry["filename"]
        if map_ids is not None and map_id not in map_ids:
            continue
        if not name:
            continue
        mpath, tpath = map_path(map_id, name, ".MAP"), map_path(map_id, name, ".TFS")
        label = f"map {map_id} {name}"
        if not (input_root / mpath).exists():
            out.check(f"{label}: files on disc or known missing", name in ("YAKA01", "YAKA21", "YAKA25"), mpath)
            continue
        referenced.add(mpath)
        msrc, tsrc = SourceFile.open(input_root, mpath), SourceFile.open(input_root, tpath)
        sources += [msrc, tsrc]
        try:
            parsed = mapfmt.parse_map(msrc.data, entry["num_8bpp"], entry["num_4bpp"], entry["has_digimon"])
            n_tiles = sum(1 for t in parsed["setup"]["tiles"] if t != -1)
            tfs = mapfmt.parse_tfs(tsrc.data, n_tiles)
        except (mapfmt.MapError, timfmt.TimError, struct.error) as e:
            out.check(f"{label}: valid MAP/TFS", False, str(e))
            continue
        out.check(f"{label}: valid MAP/TFS", True)
        out.check(f"{label}: TFS ends after its tiles", tfs.end == tsrc.size, f"end 0x{tfs.end:X}, size 0x{tsrc.size:X}")
        pos, gap = 0, 0
        for s0, s1 in parsed["spans"]:
            gap += max(0, s0 - pos)
            pos = max(pos, s1)
        out.check(f"{label}: MAP bytes explained", (gap == 0 or name == "YAKA22") and msrc.size - pos <= 3,
                  f"gap {gap}, trailing {msrc.size - pos}")

        folder = out.dir / name
        outputs = []
        backgrounds = []
        palettes = range(1 if entry["no_time_cycle"] else len(tfs.palettes)) if tfs.palettes else []
        for p in range(len(tfs.palettes)):
            bg = _background(tfs, parsed["setup"], p)
            path = folder / f"background_{p}.png"
            png.write(path, png.encode_rgba(*bg))
            backgrounds.append(bg)
            outputs.append({"path": out._rel(path), "kind": "background", "palette": p,
                            "time_of_day": TIME_OF_DAY.get(p) if not entry["no_time_cycle"] and len(tfs.palettes) >= 3 else None})
        coll = folder / "collision.png"
        png.write(coll, png.encode_gray(mapfmt.COLLISION_SIZE, mapfmt.COLLISION_SIZE, parsed["collision"]))
        outputs.append({"path": out._rel(coll), "kind": "collision", "encoding": "gray8 raw values"})

        # object sprites (per palette when they use the active TFS palette)
        sprites_day, object_info, missing_total = {}, [], 0
        vrams = {p: _map_vram(parsed, tfs, p, f"{mpath[:-4]}") for p in (palettes or [0])}
        caches = {p: {} for p in vrams}
        used = {s for inst in (parsed["objects"] or {}).get("instances", []) for s in inst["sprites"] if s >= 0}
        for k, obj in enumerate((parsed["objects"] or {}).get("definitions", [])):
            variants = list(vrams) if obj["clut"] == -1 else [next(iter(vrams))]
            info = dict(obj, files=[], stp_files=[], used_by_instances=k in used, missing_texels=0)
            for p in variants:
                w, h, px, missing, where, stp = _object_sprite(vrams[p], obj, caches[p])
                info["missing_texels"] += missing
                if k in used and obj["width"] > 0 and obj["height"] > 0:
                    missing_total += missing
                path = folder / "objects" / (f"object_{k:03d}_p{p}.png" if obj["clut"] == -1 else f"object_{k:03d}.png")
                png.write(path, png.encode_rgba(w, h, px))
                info["files"].append(out._rel(path))
                # STP mask (255 = bit set), only when a texel has it: semi-transparent sprites blend
                # only those texels (tim.md; buildMapOverlayPrim's SetSemiTrans).
                if any(stp):
                    spath = path.with_name(path.stem + ".stp.png")
                    png.write(spath, png.encode_gray(w, h, stp))
                    info["stp_files"].append(out._rel(spath))
                else:
                    info["stp_files"].append(None)
                info.update(where)
                if p == variants[0]:
                    sprites_day[k] = (w, h, px)
            object_info.append(info)
        out.check(f"{label}: sprites used by object instances fully in loaded VRAM",
                  missing_total == 0 or name in KNOWN_UNLOADED_CLUT, f"{missing_total} texels")

        # training slot machine textures (4bpp images and CLUTs don't depend on the TFS palette)
        if map_id in TRAINING_MAPS:
            slots = _training_slots(out, folder, vrams[next(iter(vrams))], msrc, parsed, mpath[:-4], label)
            outputs += slots["outputs"]
            slot_strips[name] = slots["key"]
        # Monochromon's mood faces (the CLUT row 486 doesn't depend on the TFS palette either)
        if name in MOOD_BUBBLE_MAPS:
            outputs += _mood_faces(out, folder, vrams[next(iter(vrams))], msrc, parsed, mpath[:-4], label)

        # doors
        door_list = []
        if entry["doors_id"]:
            # The slot index is kept: ROTATE_3D_OBJECT names MAP_3D_OBJ slots, and some tables
            # start with an empty one (specs/map.md "Doors").
            for k, slot in enumerate(tables["doors"][entry["doors_id"] - 1]):
                if slot["model"] == 255:
                    continue
                door_list.append(dict(slot, slot=k))
            for model in sorted({d["model"] for d in door_list}):
                dpath = f"DOOR/DOOR{model:02d}.TMD"
                dsrc = SourceFile.open(input_root, dpath)
                tmd = tmdfmt.parse(dsrc.data)
                from .. import models
                result = models.build(folder / "doors" / f"door_{model:02d}", dsrc.span(0, tmd.size).asset_id, tmd,
                                      vrams[next(iter(vrams))])
                missing = [t["missing_texels_in_uv_box"] for t in result["textures"]]
                out.check(f"{label}: door {model:02d} textures fully covered", not any(missing), str(missing))
                outputs.append({"path": out._rel(result["files"][0]), "kind": "door_model", "door_model": model})

        # script-spawned props textured with this map's VRAM
        for tpath in PROP_TMDS.get(name, []):
            psrc = SourceFile.open(input_root, tpath)
            tmd = tmdfmt.parse(psrc.data)
            from .. import models
            stem = tpath.split("/")[-1][:-4]
            result = models.build(folder / "props" / stem, psrc.span(0, tmd.size).asset_id, tmd, vrams[next(iter(vrams))])
            missing = [t["missing_texels_in_uv_box"] for t in result["textures"]]
            out.check(f"{label}: prop {stem} textures fully covered", not any(missing), str(missing))
            outputs.append({"path": out._rel(result["files"][0]), "kind": "prop_model", "tmd": tpath})

        overview = _overview(folder / "overview.png", backgrounds[0] if backgrounds else (128, 128, bytes(128 * 128 * 4)),
                             parsed, door_list, sprites_day)
        outputs.append({"path": out._rel(folder / "overview.png"), "kind": "overview (human check)"})
        out.check(f"{label}: projected collision lands on the background", overview["collision_cells_drawn"] > 0,
                  str(overview))

        warps = [dict(w, map_name=tables["entries"][w["map"]]["filename"] if 0 <= w["map"] < 255 else None)
                 for w in parsed["warps"]]
        digimon = [dict(d, type_name=DIGIMON_TYPES[d["type"]][2] if 0 <= d["type"] < len(DIGIMON_TYPES) else None)
                   for d in parsed["digimon"]]
        record = {
            "asset_id": msrc.span(0, msrc.size).asset_id,
            "family": NAME,
            "format": "MAP+TFS",
            "source": msrc.span(0, msrc.size).identity(),
            "tfs_source": tsrc.span(0, tsrc.size).identity(),
            "outputs": outputs,
            "map_entry": entry,
            "header": parsed["header"],
            "setup": parsed["setup"],
            "camera": mapfmt.camera(parsed["setup"]),
            "tfs": {"width": tfs.width, "height": tfs.height, "palettes": tfs.palettes,
                    "tile_headers": [h for _, h, _ in tfs.tiles]},
            "images": [{"kind": i["kind"], "index": i["index"], "offset": i["offset"], "tim": i["tim"].header_info(),
                        "vram": i["tim"].vram_info()} for i in parsed["images"]],
            "objects": object_info,
            "object_instances": (parsed["objects"] or {}).get("instances", []),
            "spawns": parsed["spawns"],
            "warps": warps,
            "digimon_count_field": parsed["digimon_count"],
            "digimon": digimon,
            "doors": door_list,
            "toilet": tables["toilets"][entry["toilet_id"] - 1] if entry["toilet_id"] else None,
            "collision": {"size": mapfmt.COLLISION_SIZE, "cell": 100, "values": list(parsed["collision"])},
            "overview": overview,
        }
        _dump(folder / "map.json", record)
        out.assets.append({"asset_id": record["asset_id"], "sidecar": out._rel(folder / "map.json"),
                           "outputs": [o["path"] for o in outputs]})

    if map_ids is None:
        on_disc = {p.relative_to(input_root).as_posix() for p in input_root.rglob("*.MAP")}
        unreferenced = sorted(on_disc - referenced)
        out.check("MAP files not in MAP_ENTRIES", len(unreferenced) <= 1, str(unreferenced))
    # Informational: whether every training map leaves the same slot textures in VRAM.
    strips = {}
    if slot_strips:
        groups = {}
        for n, key in sorted(slot_strips.items()):
            groups.setdefault(key, []).append(n)
        strips = {"maps": sorted(slot_strips), "identical": len(groups) == 1, "groups": sorted(groups.values()),
                  "indices_identical": len({k[0] for k in groups}) == 1}
        out.check("training slot strips identical across maps (informational, not required)", True, str(strips))
    out.finish(sources, {"map_table": tables, "training_slots": strips})
    return out
