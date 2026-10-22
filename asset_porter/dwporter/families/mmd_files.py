"""CHDAT/MMD*/*.MMD: the 178 Digimon models with skeleton and animations. Spec: specs/mmd.md.

Per digimon type: the model (MMD = TMD + animation table), its texture (ALLTIM.TIM slot = type),
its skeleton and bone count (executable tables, see data/skeletons.py). Textures are built the
way the game shows the model in the tamer slot; animations are simulated tick by tick with a
port of the game's animation code (formats/mmd.py).
"""

import dataclasses
import struct

from ..assets import AssetWriter
from ..data.digimon import DIGIMON_TYPES, mmd_path
from ..data import skeletons as skel
from ..formats import mmd as mmdfmt
from ..formats import tim as timfmt
from ..formats.vram import Vram
from ..source import SourceFile
from . import alltim

NAME = "mmd_files"
SOURCE_PATH = "CHDAT/MMD*/*.MMD (178 files)"
SPEC = "specs/mmd.md"
CODE_REFS = [
    "dw_decomp/src/main/model.c:3405 thunkLoadMMD / :3620 loadMMDAsync: path CHDAT\\\\MMD<type/30>\\\\<NAME>.MMD, texture ALLTIM slot",
    "dw_decomp/src/main/model.c:3416 modelPtr = mmd + mmd[0], animTablePtr = mmd + mmd[1]",
    "dw_decomp/src/main/model.c:3557 uploadModelTexture: TIM uploaded at the model slot's pixelPage / clutPage",
    "dw_decomp/src/main/graphics.c:156 updateTMDTextureData: patches TSB page bits, CBA and UVs to the slot",
    "dw_decomp/src/main/model.c:2310 DIGIMON_SKELETONS[180]; dw_decomp/src/main/main.c:254 DIGIMON_DATA[180].boneCount",
    "dw_decomp/src/main/anim.c startAnimation / tickAnimation / tickMomentum / applyRootMomentum (simulated)",
    "dw_decomp/src/main/main.c:3761 main loop VSync(3): 20 animation ticks per second (NTSC)",
]

EXE = "SLUS_010.32"
EXE_LOAD = 0x80090000  # file offset = address - EXE_LOAD (t_addr 0x80090800, 0x800 header)

# The tamer model slot (model.c:3424): image at (320, 256), CLUT (0, 488), no UV offset.
SLOT = {"name": "tamer", "pixel_page": 0x15, "clut_page": 0x7A00, "pixel_offset": (0, 0)}


def _exe_tables(exe: bytes, type_id: int) -> tuple:
    def u32(addr):
        return struct.unpack_from("<I", exe, addr - EXE_LOAD)[0]

    ptr = u32(skel.DIGIMON_SKELETONS_ADDRESS + 4 * type_id)
    bones = struct.unpack_from("<i", exe, skel.DIGIMON_DATA_ADDRESS - EXE_LOAD + skel.DIGIMON_PARA_SIZE * type_id
                               + skel.DIGIMON_PARA_BONE_COUNT_OFFSET)[0]
    pairs = tuple(tuple(exe[ptr - EXE_LOAD + 2 * i:ptr - EXE_LOAD + 2 * i + 2]) for i in range(bones)) if ptr else ()
    return ptr, bones, pairs


def _patch_for_slot(tmd):
    """updateTMDTextureData for SLOT: TSB page bits = pixel page, CBA += slot index, UV += offset.

    Like the game, each object is patched only up to its first untextured primitive.
    """
    du, dv = SLOT["pixel_offset"]
    clut_add = SLOT["clut_page"] - 0x7A00
    objects = []
    for obj in tmd.objects:
        prims, patching = [], True
        for p in obj.primitives:
            patching = patching and p.textured
            if patching:
                p = dataclasses.replace(p, tsb=(p.tsb & 0xFFE0) + SLOT["pixel_page"], cba=p.cba + clut_add,
                                        uvs=tuple(((u + du) & 0xFF, (v + dv) & 0xFF) for u, v in p.uvs))
            prims.append(p)
        objects.append(dataclasses.replace(obj, primitives=tuple(prims)))
    return dataclasses.replace(tmd, objects=tuple(objects))


def _slot_texture(input_root, type_id: int):
    src = SourceFile.open(input_root, alltim.SOURCE_PATH)
    offset = type_id * alltim.SLOT_SIZE
    tim = timfmt.parse(src.data, offset)
    slot = alltim.RUNTIME_SLOTS[SLOT["name"]]
    placed = dataclasses.replace(tim, x=slot["image"]["x"], y=slot["image"]["y"],
                                 clut=dataclasses.replace(tim.clut, x=slot["clut"]["x"], y=slot["clut"]["y"]))
    vram = Vram()
    vram.load_tim(placed, f"{alltim.SOURCE_PATH}@0x{offset:X} ({SLOT['name']} slot)")
    return vram


def _covered(data: bytes, mmd) -> tuple:
    """(unexplained bytes, trailing pad bytes): every byte should be header, TMD, table or animation."""
    spans = sorted([(0, 8), (mmd.tmd_offset, mmd.tmd.end), (mmd.anim_offset, mmd.anim_offset + 4 * len(mmd.table))]
                   + [(a.offset, a.end) for a in mmd.animations.values()])
    pos, unexplained = 0, 0
    for start, end in spans:
        if start > pos:
            unexplained += start - pos
        pos = max(pos, end)
    return unexplained, len(data) - pos


def _anim_extras(anim_id: int, anim, sim: dict, shared: list) -> dict:
    loop = sim["loop"]
    events = []
    for e in sim["events"]:
        e = dict(e, time=(e["tick"] - 1) / mmdfmt.FPS)
        if e["type"] == "texture":
            # Slot-relative VRAM units (x in 16-bit words); with the tamer slot these are page UVs / 4.
            e["src_uv"], e["size_uv"], e["dest_uv"] = ([e["src"][0] * 4, e["src"][1]], [e["size"][0] * 4, e["size"][1]],
                                                       [e["dest"][0] * 4, e["dest"][1]])
        events.append(e)
    return {
        "anim_id": anim_id,
        "same_data_as": shared,
        "file_offset": anim.offset,
        "frame_count": anim.frame_count,
        "ticks": len(sim["frames"]),
        "duration": (len(sim["frames"]) - 1) / mmdfmt.FPS,
        "loop": None if loop is None else dict(loop, start_time=(loop["start_tick"] - 1) / mmdfmt.FPS,
                                               end_time=(loop["end_tick"] - 1) / mmdfmt.FPS),
        "events": events,
        "root_motion": any(any(v) for v in sim["root_location"]),
        "quirks": sim["quirks"],
    }


def convert(input_root, output_root, types=None) -> AssetWriter:
    """Convert all digimon types, or only `types` (ids) when given (used by tests)."""
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    exe = SourceFile.open(input_root, EXE)
    sources = [exe]

    on_disc = sorted(p.relative_to(input_root).as_posix() for p in input_root.rglob("*.MMD"))
    expected = sorted(mmd_path(t) for t in range(len(DIGIMON_TYPES)) if t not in alltim.KNOWN_MISSING_MODELS)
    out.check("every .MMD on disc is a digimon type model", on_disc == expected,
              f"unexpected: {sorted(set(on_disc) - set(expected))}, missing: {sorted(set(expected) - set(on_disc))}")

    for type_id, (file_name, string_id, display_name) in enumerate(DIGIMON_TYPES):
        if types is not None and type_id not in types:
            continue
        skel_name, bones, radius, height = skel.TYPE_PARAMS[type_id]
        ptr, exe_bones, exe_pairs = _exe_tables(exe.data, type_id)
        label = f"type {type_id} {file_name}"
        if skel_name is None:
            out.check(f"{label}: no skeleton and no model", ptr == 0 and exe_bones == 0
                      and type_id in alltim.KNOWN_MISSING_MODELS, f"ptr 0x{ptr:X}, bones {exe_bones}")
            continue
        pairs = skel.SKELETONS[skel_name][:bones]
        out.check(f"{label}: skeleton matches {EXE}", ptr == skel.SKELETON_ADDRESS[skel_name]
                  and exe_bones == bones and exe_pairs == pairs, f"{skel_name} @0x{ptr:X}, {exe_bones} bones")

        src = SourceFile.open(input_root, mmd_path(type_id))
        sources.append(src)
        try:
            mmd = mmdfmt.parse(src.data, bones)
        except (mmdfmt.MmdError, ValueError) as e:
            out.check(f"{label}: valid MMD", False, str(e))
            continue
        nobj = len(mmd.tmd.objects)
        out.check(f"{label}: valid MMD", True)
        out.check(f"{label}: bones use every TMD object once", sorted(o for o, _ in pairs if o != 0xFF) == list(range(nobj)),
                  f"{nobj} objects")
        unexplained, pad = _covered(src.data, mmd)
        out.check(f"{label}: every byte is header/TMD/table/animation (+ alignment pad)", unexplained == 0 and pad <= 2,
                  f"unexplained {unexplained}, trailing {pad}")

        animations, sims, rest = [], {}, None
        by_offset = {}
        for anim_id, rel in enumerate(mmd.table):
            if rel:
                by_offset.setdefault(rel, []).append(anim_id)
        for anim_id, rel in enumerate(mmd.table):
            if not rel:
                continue
            anim = mmd.animation(anim_id)
            try:
                sim = mmdfmt.simulate(src.data, anim, bones, anim_id)
            except (mmdfmt.MmdError, IndexError) as e:
                out.check(f"{label}: animation {anim_id} simulates", False, str(e))
                continue
            sims[anim_id] = sim
            if rest is None:
                rest = sim["frames"][0]
            animations.append({"name": f"anim_{anim_id:02d}", "frames": sim["frames"],
                               "root_location": sim["root_location"],
                               "extras": _anim_extras(anim_id, anim, sim, [i for i in by_offset[rel] if i != anim_id])})
        out.check(f"{label}: all animations simulate without the 0x1000 quirk",
                  len(sims) == sum(1 for r in mmd.table if r) and not any(s["quirks"] for s in sims.values()),
                  f"{len(sims)} animations")
        if rest is None:
            rest = [[4096, 4096, 4096, 0, 0, 0, 0, 0, 0]] * bones

        tmd = _patch_for_slot(mmd.tmd)
        mmd_patched = dataclasses.replace(mmd, tmd=tmd)
        vram = _slot_texture(input_root, type_id)
        record = out.write_mmd(mmd_path(type_id).rsplit(".", 1)[0].split("/", 1)[1], src.span(0, src.size), mmd_patched,
                               vram, list(pairs), rest, animations, {
                                   "digimon": {"type": type_id, "file_name": file_name, "string_id": string_id,
                                               "name": display_name},
                                   "skeleton": {"name": skel_name, "bones": [list(b) for b in pairs],
                                                "radius": radius, "height": height},
                                   "texture_source": {"file": alltim.SOURCE_PATH, "offset": type_id * alltim.SLOT_SIZE,
                                                      "slot": SLOT},
                                   "rest_pose": {"animation": min(sims) if sims else None, "tick": 1},
                                   "lenient_reads": sum(len(o.vertices) - o.n_vert_declared + len(o.normals)
                                                        - o.n_normal_declared for o in mmd.tmd.objects),
                               })
        missing = [t["missing_texels_in_uv_box"] for t in record["textures"]]
        out.check(f"{label}: texture pages fully covered by its ALLTIM slot", not any(missing), str(missing))

    out.finish(sources)
    return out
