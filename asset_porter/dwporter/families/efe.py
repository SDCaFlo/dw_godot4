"""ETCHI/EFEDAT.EFE: battle technique effects (script, model, texture, UV animations). Spec: specs/efe.md."""

import dataclasses
import re

from ..assets import AssetWriter, _dump
from ..data.moves import MOVE_NAMES
from ..formats import efe as efefmt
from ..formats import tim as timfmt
from ..formats import tmd as tmdfmt
from ..formats.vram import Vram
from ..source import SourceFile

NAME = "efe"
SOURCE_PATH = "ETCHI/EFEDAT.EFE"
SPEC = "specs/efe.md"
CODE_REFS = [
    "dw_decomp/src/main/efe.c:1043 getEFEDATEntry(id): sector = start + (id - 256) * 10",
    "dw_decomp/src/main/btl.c:466 effect id = DIGIMON_DATA[type].moves[...] + 0x100 (technique id + 0x100)",
    "dw_decomp/src/btl/battle_effect.c:1574 BTL_loadNextEFEFile (0x5000 bytes), :1688 BTL_setupLoadedEFEFile (TIM slot, TMD patch, init script)",
    "dw_decomp/src/btl/battle_effect.c:5341 BTL_runEFEScript; :1134 BTL_jtbl_80073604 (18 opcodes); :993 BTL_EFE_SUB_OPCODES (97 built-ins)",
    "dw_decomp/src/main/graphics.c:156 updateTMDTextureData",
    "dw_decomp/include/dw/efe.h EfeFileHeader, EfeUvAnim, EfeSubEffect",
]

FILE_SIZE = 0x262000
SLOTS = 122
FILL_SLOT = 121  # all 0xCD
STALE_SLOT = 110  # another build of effect 344 (slot 88)
# Effect texture slot 0 (BTL_setupLoadedEFEFile, i = 0): page 0x19 = (576, 256), y offset 0, CLUT (128, 488)
TEX_SLOT = {"index": 0, "pixel_page": 0x19, "image": (576, 256), "clut": (128, 488), "clut_page": (488 << 6) | 8}


def _slug(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9]+", "_", name or "none").strip("_")


def _operand_text(insn: dict) -> str:
    o = insn["operands"]

    def where(off_key, scope_key):
        return f"{'data' if o[scope_key] else 'inst'}+0x{o[off_key] & 0xFFFF:X}"

    op = insn["op"]
    if op in (0, 10):
        return str(o["value"])
    if op in (1, 11, 16, 12):
        return where("offset", "scope") + (f" ({o['size']})" if "size" in o else "")
    if op == 3:
        return f"data+0x{o['table'] & 0xFFFF:X}[{where('index_offset', 'index_scope')}] ({o['size']}, index {o['index_size']})"
    if op == 4:
        return f"{where('offset', 'scope')} {o['operator']}= register ({o['size']})"
    if op == 7:
        return f"if not ({where('offset', 'scope')} {o['compare']} register) goto L_{o['target'] & 0xFFFF:04X} ({o['size']})"
    if op in (9, 13):
        return f"L_{o['target'] & 0xFFFF:04X}"
    if op == 14:
        return f"{o['builtin']} {o['builtin_name']}"
    if op == 17:
        return f"count={o['count']} instances=data+0x{o['instances'] & 0xFFFF:X} stride={o['stride']}"
    return ""


def listing(title: str, header: dict, dis: dict, gaps: list) -> str:
    targets = {i["operands"]["target"] & 0xFFFF for i in dis["instructions"].values() if i["op"] in (7, 9, 13)}
    gap_at = {g["offset"]: g for g in gaps}
    lines = [f"; {title}", f"; init_script 0x{header['init_script']:04X}, start_script 0x{header['start_script']:04X}, "
             f"{len(dis['instructions'])} instructions, {sum(g['size'] for g in gaps)} gap bytes", ""]
    for off in sorted(set(dis["instructions"]) | set(gap_at)):
        if off in gap_at:
            lines.append(f"  {off:04X}  ; gap {gap_at[off]['size']} bytes: {gap_at[off]['hex'][:48]}")
            continue
        insn = dis["instructions"][off]
        if off in dis["entries"]:
            lines.append("")
            lines.append(f"{dis['entries'][off]} 0x{off:04X}:")
        elif off in targets:
            lines.append(f"L_{off:04X}:")
        lines.append(f"  {off:04X}  {insn['name']:<18} {_operand_text(insn)}".rstrip())
    return "\n".join(lines) + "\n"


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    src = SourceFile.open(input_root, SOURCE_PATH)
    out.check("size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, f"0x{src.size:X}")
    out.check(f"{SLOTS} slots of 0x5000 bytes", src.size == SLOTS * efefmt.SLOT_SIZE)
    out.check("one technique name per slot", len(MOVE_NAMES) == SLOTS, str(len(MOVE_NAMES)))
    index, unused = [], []

    for i in range(SLOTS):
        off = i * efefmt.SLOT_SIZE
        slot = src.data[off:off + efefmt.SLOT_SIZE]
        label = f"slot {i}"
        if i == FILL_SLOT:
            out.check(f"{label}: unused slot is all 0xCD fill", set(slot) == {0xCD})
            unused.append({"slot": i, "fill": "0xCD", "technique": MOVE_NAMES[i]})
            continue
        h = efefmt.parse_header(slot)
        out.check(f"{label}: effect id = 256 + slot (slot {STALE_SLOT} is a stale copy of 344)",
                  h["effect_id"] == 256 + i or (i == STALE_SLOT and h["effect_id"] == 344), str(h["effect_id"]))
        order = [h["uv_anims"], h["uv_anims_end"], h["sub_effects"], h["tmd_start"], h["tmd_end"], h["tim_start"], h["tim_end"]]
        out.check(f"{label}: sections ascending inside the slot",
                  all(a <= b for a, b in zip(order, order[1:])) and h["tim_end"] == h["data_end"]
                  and h["data_end"] + efefmt.HEADER_SIZE <= efefmt.SLOT_SIZE, str(order))
        out.check(f"{label}: sub-effect table = 28 * numSubEffects",
                  h["tmd_start"] - h["sub_effects"] == efefmt.SUB_EFFECT_SIZE * h["num_sub_effects"])
        base = slot[efefmt.HEADER_SIZE:]
        technique = MOVE_NAMES[i]
        folder_name = f"{i:03d}_{_slug(technique)}"
        folder = out.dir / folder_name
        outputs = []

        # texture: TIM placed in effect texture slot 0
        vram, tim_info = None, None
        if h["tim_end"] > h["tim_start"]:
            tim = timfmt.parse(base, h["tim_start"])
            out.check(f"{label}: TIM ends at timEnd", h["tim_start"] + tim.size == h["tim_end"])
            out.check(f"{label}: TIM fits the 32-row effect texture slot", tim.height <= 32 and tim.bpp == 4,
                      f"{tim.width}x{tim.height} {tim.bpp}bpp")
            placed = dataclasses.replace(tim, x=TEX_SLOT["image"][0], y=TEX_SLOT["image"][1],
                                         clut=dataclasses.replace(tim.clut, x=TEX_SLOT["clut"][0], y=TEX_SLOT["clut"][1]))
            vram = Vram()
            vram.load_tim(placed, f"{SOURCE_PATH}@0x{off + efefmt.HEADER_SIZE + h['tim_start']:X} (effect texture slot 0)")
            tim_span = src.span(off + efefmt.HEADER_SIZE + h["tim_start"], tim.size)
            tim_info = out.write_tim(f"{folder_name}/texture", tim_span, tim, {
                "runtime_placement": {"loader": "BTL_setupLoadedEFEFile", "texture_slot": TEX_SLOT,
                                      "note": "the TIM's own VRAM position is ignored; slot i: page 0x19 + i/8, "
                                              "y offset (i % 8) * 32, CLUT (128 + i/4*16, 488 + (i%4)*6)"}})
            outputs += tim_info["outputs"]

        # model: TMD patched like updateTMDTextureData for texture slot 0
        n_objects = 0
        if h["tmd_end"] > h["tmd_start"]:
            tmd = tmdfmt.parse(base, h["tmd_start"])
            n_objects = len(tmd.objects)
            out.check(f"{label}: TMD ends at tmdEnd", tmd.offset + tmd.size == h["tmd_end"])
            patched = tmdfmt.update_texture_data(tmd, TEX_SLOT["pixel_page"], (0, 0), TEX_SLOT["clut_page"] - 0x7A08)
            tmd_span = src.span(off + efefmt.HEADER_SIZE + h["tmd_start"], tmd.size)
            rec = out.write_tmd(f"{folder_name}/model", tmd_span, patched, vram, {
                "texture_slot": TEX_SLOT, "patch": "updateTMDTextureData(page 0x19, offset (0, 0), CLUT delta 0)"})
            missing = [t.get("missing_texels_in_uv_box") for t in rec["textures"]]
            out.check(f"{label}: model textures covered by the effect TIM", not any(missing), str(missing))
            outputs += [o["path"] for o in rec["outputs"]]
        out.check(f"{label}: one UV anim record per TMD object",
                  h["uv_anims_end"] - h["uv_anims"] == efefmt.UV_ANIM_SIZE * n_objects, f"{n_objects} objects")

        # script
        dis = efefmt.disassemble(base, [h["init_script"], h["start_script"]], h["uv_anims"])
        out.check(f"{label}: script disassembles (known opcodes, flow stays in the script area)",
                  not dis["errors"], str(dis["errors"][:2]))
        insns = dis["instructions"]
        code_start = min(insns) if insns else h["uv_anims"]
        covered = sorted((p, p + x["size"]) for p, x in insns.items())
        gaps, pos = [], code_start
        for a, b in covered + [(h["uv_anims"], h["uv_anims"])]:
            if a > pos:
                gaps.append({"offset": pos, "size": a - pos, "hex": base[pos:a].hex()})
            pos = max(pos, b)
        uv_tables = []
        for t in dis["uv_tables"]:
            try:
                uv_tables.append(efefmt.uv_keyframes(base, t))
            except (efefmt.EfeError, Exception) as e:  # noqa: BLE001 - recorded, not fatal
                uv_tables.append({"offset": t, "error": str(e)})

        title = f"EFEDAT slot {i}: technique {i} {technique} (effect id {h['effect_id']})"
        if i == STALE_SLOT:
            title += " - stale copy of effect 344, never loaded"
        record = {
            "asset_id": src.span(off, efefmt.SLOT_SIZE).asset_id,
            "family": NAME,
            "format": "EFE",
            "source": src.span(off, efefmt.SLOT_SIZE).identity(),
            "title": title,
            "technique": {"id": i, "name": technique, "effect_id": h["effect_id"]},
            "header": h,
            "base_offset_in_slot": efefmt.HEADER_SIZE,
            "data_area": {"offset": 0, "size": code_start, "hex": base[:code_start].hex()},
            "script": {"entries": {f"0x{k:X}": v for k, v in sorted(dis["entries"].items())},
                       "instructions": [insns[p] for p in sorted(insns)], "gaps": gaps,
                       "builtins_used": sorted({x["flags"] for x in insns.values() if x["op"] == 14})},
            "uv_anims": [base[h["uv_anims"] + k * 32:h["uv_anims"] + (k + 1) * 32].hex() for k in range(n_objects)],
            "uv_keyframe_tables": uv_tables,
            "sub_effects": [base[h["sub_effects"] + k * 28:h["sub_effects"] + (k + 1) * 28].hex()
                            for k in range(h["num_sub_effects"])],
            "slot_tail": {"offset": h["data_end"], "hex": base[h["data_end"]:].hex()},
            "outputs": outputs + [f"{folder_name}/effect.txt"],
        }
        if i == STALE_SLOT:
            record["note"] = "header says effect 344 (slot 88): getEFEDATEntry never returns this slot for 344"
        _dump(folder / "effect.json", record)
        (folder / "effect.txt").write_text(listing(title, h, dis, gaps), encoding="utf-8")
        out.assets.append({"asset_id": record["asset_id"], "sidecar": out._rel(folder / "effect.json"),
                           "outputs": record["outputs"]})
        index.append({"slot": i, "technique": technique, "effect_id": h["effect_id"], "folder": folder_name,
                      "model": n_objects > 0, "texture": tim_info is not None, "instructions": len(insns),
                      "gap_bytes": sum(g["size"] for g in gaps)})

    _dump(out.dir / "index.json", {"effects": index, "unused_slots": unused})
    out.finish([src], {"unused_slots": unused})
    return out
