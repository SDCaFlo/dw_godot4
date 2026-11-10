"""SCN/MAPHEAD.SCN + SCN/DG.SCN: event scripts. Spec: specs/scn.md.

One JSON + one readable listing per script; index.json links maps to their scripts (from the
SET_SCRIPT instruction that starts each MAPHEAD section).
"""

import re
import struct

from ..assets import AssetWriter, _dump
from ..data.digimon import DIGIMON_TYPES
from ..formats import scn
from ..source import SourceFile
from . import maps, mmd_files

NAME = "scripts"
SOURCE_PATH = "SCN/MAPHEAD.SCN + SCN/DG.SCN"
SPEC = "specs/scn.md"
## A cup with requirement type 1 needs the Grade A Cup won: isTournamentEnabled's case 1 is
## isTriggerSet(TRIGGER_GRADE_A_CUP_WON) (dget/dget.c:397-398), TRIGGER_18 (include/dw/trigger.h:808),
## tournament id 18 - 15 = 3 (specs/scn.md). Checked against the decomp by tests/test_decomp_constants.py.
WON_TOURNAMENT = 3
CODE_REFS = [
    "dw_decomp/include/dw/script.h: opcodes and argument layouts",
    "dw_decomp/src/main/script_interp.c:2190 initializeScripts (MAPHEAD -> MAPHEAD_SCRIPT_BUFFER, DG table -> SCRIPT_OFFSET_TABLE)",
    "dw_decomp/src/main/script_interp.c:647 getScript (DG.SCN [table[id], table[id+1]) -> MAP_SCRIPT_BUFFER); :671 getScriptSection",
    "dw_decomp/src/main/script_interp.c:390 tickScript (dispatch), :692/:1090/:1297/:1550/:1640/:2833 opcode handlers",
    "dw_decomp/src/main/script_interp.c:907 scriptIfInstruction; script_value.c scriptCompare*",
    "dw_decomp/src/main/script_textbox.c:1017 scriptShowSelection, :1054 showTextbox (text codes), :644 drawString2",
    "dw_decomp/src/main/script_interp.c:2235 runMapHeadScript (MAPHEAD section = map id); tamer.c:688 trigger cells -> sections",
    "dw_decomp/src/main/file_table_us.c:754 DG.SCN 0xC4800, :755 MAPHEAD.SCN 0x606E",
    "dw_decomp/src/main/tournament.c:146 getCupDataJumpTable, :157 getCupDataJumpTableEntry",
    "dw_decomp/src/dget/dget.c:331 tournamentCheckFair, :350 isTournamentEnabled, :429 tournamentCheckEligible",
    "dw_decomp/include/dw/trigger.h:805 TRIGGER_D_RANK_CUP_WON..TRIGGER_ANIMAL_CUP_WON",
]

MAPHEAD = "SCN/MAPHEAD.SCN"
DG = "SCN/DG.SCN"
MAPHEAD_SIZE = 0x606E
DG_SIZE = 0xC4800
MAPHEAD_BUFFER = 0x61A8
MAP_SCRIPT_BUFFER = 0x4000

ARENA_SCRIPT = 168
CUP_COPIES = (213, 102, 209)
CUPS = 23


def _u16(b: bytes, offset: int) -> int:
    return b[offset] | (b[offset + 1] << 8)


def _script_section(b: bytes, section_id: int):
    p = 2
    while p + 4 <= len(b):
        sid = _u16(b, p)
        if sid == 0xFFFF:
            return None
        if sid == section_id:
            return _u16(b, p + 2)
        p += 4
    return None


def _read_data_list(b: bytes, entry_off: int) -> list:
    out = []
    p = entry_off + 2
    while p < len(b) and b[p] < 0xFE:
        out.append(b[p])
        p += 1
    return out


def _read_cups_from_script(b: bytes, dis: dict) -> tuple:
    s_a = _script_section(b, 0x0A)
    s_b = _script_section(b, 0x0B)
    b_list = _read_data_list(b, s_b) if s_b is not None else []
    by_offset = {i["offset"]: i for i in dis["instructions"]}

    cups = []
    for cup_id in range(CUPS):
        tbl = _u16(b, s_a + cup_id * 4 + 2)
        entries = [_u16(b, tbl + k * 4 + 2) for k in range(5)]
        c_values = list(b[entries[1] + 2:entries[1] + 5])
        overleveled = _read_data_list(b, entries[2])
        eligible = _read_data_list(b, entries[3])
        opponents = None if b[entries[4] + 2] >= 0xFE else _read_data_list(b, entries[4])
        info_insn = by_offset[entries[0]]
        cups.append({
            "id": cup_id,
            "table": tbl,
            "entries": entries,
            "c_values": c_values,
            "overleveled": overleveled,
            "eligible": eligible,
            "opponents": opponents,
            "info_raw": info_insn["raw"],
            "info_text": info_insn["args"]["text"],
            "info_offset": entries[0],
        })
    return cups, b_list


def _speaker(value: int) -> str:
    return scn.SPEAKERS.get(value, f"npc {value}")


def _fmt_args(insn: dict) -> str:
    a = insn["args"]
    if insn["op"] in (0x10, 0x1A):
        text = a["text"].replace("\n", "\\n")
        prefix = f"targets={[f'L_{t:04X}' for t in a['targets']]} " if insn["op"] == 0x10 else ""
        return f'{prefix}"{text}"'
    if insn["op"] == 0x19:
        parts = []
        for c in a["conditions"]:
            if c["kind"] == "end":
                continue
            comb = {"and": "&& ", "or": "|| ", "set": ""}[c["combine"]]
            if c["kind"] in ("jump_if_true", "jump_if_false"):
                parts.append(f"{c['kind']} L_{c['offset']:04X}")
            else:
                fields = " ".join(f"{k}={v}" for k, v in c.items() if k not in ("op", "combine", "kind", "raw"))
                parts.append(f"{comb}{c['kind']}({fields})")
        return "; ".join(parts)
    if insn["op"] == 0x18:
        return f"pstat={a['pstat']} " + str([f"L_{o:04X}" for o in a["offsets"]])
    if insn["op"] in (0x13, 0x16):
        return f"L_{a['offset']:04X}"
    out = []
    for k, v in a.items():
        if k == "id" or (k == "target" and insn["op"] not in (0x72, 0x73)):
            out.append(f"{k}={_speaker(v)}")
        elif k == "digimon" and v < len(DIGIMON_TYPES):
            out.append(f"{k}={v} ({DIGIMON_TYPES[v][2]})")
        else:
            out.append(f"{k}={v}")
    return " ".join(out)


def listing(title: str, dis: dict) -> str:
    sections = {}
    for s in dis["header"]["sections"]:
        sections.setdefault(s["offset"], []).append(s["id"])
    labels = {t for i in dis["instructions"] for t in scn.jump_targets(i)}
    lines = [f"; {title}", f"; code_start 0x{dis['header']['code_start']:04X}, "
             f"{len(dis['header']['sections'])} sections, {len(dis['instructions'])} instructions", ""]
    for insn in dis["instructions"]:
        off = insn["offset"]
        if off in sections:
            lines.append("")
            lines.append(f"section {', '.join(f'0x{s:X} ({s})' for s in sections[off])}:")
        if off in labels:
            lines.append(f"L_{off:04X}:")
        lines.append(f"  {off:04X}  {insn['name']:<34} {_fmt_args(insn)}".rstrip())
    lines.append("")
    lines.append(f"; padding after END_SCRIPT: {len(dis['padding'])} bytes")
    return "\n".join(lines) + "\n"


def _record(asset_span, title: str, dis: dict, extra: dict) -> dict:
    insns = []
    for i in dis["instructions"]:
        i = dict(i)
        if not i["nonzero_pads"]:
            del i["nonzero_pads"]
        insns.append(i)
    rec = {
        "asset_id": asset_span.asset_id,
        "family": NAME,
        "format": "SCN script",
        "source": asset_span.identity(),
        "title": title,
        "header": dis["header"],
        "instructions": insns,
        "padding": {"offset": dis["end"], "size": len(dis["padding"]), "hex": dis["padding"].hex()},
    }
    rec.update(extra)
    return rec


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    mh, dg = SourceFile.open(input_root, MAPHEAD), SourceFile.open(input_root, DG)
    exe = SourceFile.open(input_root, mmd_files.EXE)
    map_names = {e["id"]: e for e in maps.read_tables(exe.data)["entries"]}

    out.check("MAPHEAD.SCN size matches FILE_OFFSET_TABLE", mh.size == MAPHEAD_SIZE, f"0x{mh.size:X}")
    out.check("DG.SCN size matches FILE_OFFSET_TABLE", dg.size == DG_SIZE, f"0x{dg.size:X}")
    out.check("MAPHEAD.SCN fits MAPHEAD_SCRIPT_BUFFER", mh.size <= MAPHEAD_BUFFER, f"0x{mh.size:X}")

    table = scn.parse_dg_table(dg.data)
    scripts = table["scripts"]
    out.check("DG table is one sector", table["table_size"] == scn.SECTOR, f"0x{table['table_size']:X}")
    out.check("DG table ends at the file size", table["entries"][table["used_entries"] - 1] == dg.size,
              f"{table['used_entries']} entries")
    out.check("DG scripts are sector aligned", all(o % scn.SECTOR == 0 for _, o, _ in scripts))
    biggest = max(size for sid, _, size in scripts if sid != 0)  # script 0 is never loaded (getScript(0) = MAPHEAD)
    out.check("every DG script 1+ fits MAP_SCRIPT_BUFFER", biggest <= MAP_SCRIPT_BUFFER, f"largest 0x{biggest:X}")
    out.check("DG script 0 starts with MAPHEAD.SCN", dg.data[scripts[0][1]:scripts[0][1] + mh.size] == mh.data)
    table_tail = dg.data[table["used_entries"] * 4:table["table_size"]]
    leftover_names = [m.decode("ascii") for m in re.findall(rb"\\SCN\\[\x20-\x7e]+?\.SCN", table_tail)]

    # Disassemble everything first: cross-script references are checked afterwards.
    items = [("MAPHEAD", mh, 0, mh.size)] + [(sid, dg, off, size) for sid, off, size in scripts]
    decoded = {}
    for sid, src, off, size in items:
        label = "MAPHEAD" if sid == "MAPHEAD" else f"DG script {sid}"
        data = src.data[off:off + size]
        try:
            dis = scn.disassemble(data)
        except (scn.ScnError, IndexError, ValueError) as e:
            out.check(f"{label}: disassembles to END_SCRIPT", False, str(e))
            continue
        out.check(f"{label}: disassembles to END_SCRIPT", True, f"{len(dis['instructions'])} instructions")
        decoded[sid] = (src, off, size, data, dis)

    sections_of = {sid: {s["id"] for s in d[4]["header"]["sections"]} for sid, d in decoded.items()}
    sections_of[0] = sections_of.get("MAPHEAD", set())  # getScript(0) = MAPHEAD

    # map id -> script (first SET_SCRIPT of the MAPHEAD section with that id)
    map_links = []
    if "MAPHEAD" in decoded:
        dis = decoded["MAPHEAD"][4]
        by_offset = {i["offset"]: i for i in dis["instructions"]}
        for s in dis["header"]["sections"]:
            first = by_offset.get(s["offset"])
            if first and first["op"] == 0xFB:
                entry = map_names.get(first["args"]["map"], {})
                map_links.append({"maphead_section": s["id"], "map": first["args"]["map"],
                                  "map_name": entry.get("filename"), "display_name": entry.get("display_name"),
                                  "script": first["args"]["script"]})
    maps_of = {}
    for link in map_links:
        maps_of.setdefault(link["script"], []).append(link)

    summary = []
    for sid, (src, off, size, data, dis) in decoded.items():
        label = "MAPHEAD" if sid == "MAPHEAD" else f"DG script {sid}"
        insns = dis["instructions"]
        starts = {i["offset"] for i in insns}
        header = dis["header"]
        rebuilt = data[:header["code_start"]] + b"".join(bytes.fromhex(i["raw"]) for i in insns) + dis["padding"]
        out.check(f"{label}: code_start = end of section table", header["code_start"] == header["table_end"],
                  f"0x{header['code_start']:X} / 0x{header['table_end']:X}")
        out.check(f"{label}: header + instructions + padding = script bytes", rebuilt == data)
        bad_sections = [s for s in header["sections"] if s["offset"] not in starts]
        out.check(f"{label}: sections start on instructions", not bad_sections, str(bad_sections[:3]))
        bad_jumps = [(i["offset"], t) for i in insns for t in scn.jump_targets(i) if t not in starts]
        out.check(f"{label}: jump targets start on instructions", not bad_jumps, str(bad_jumps[:3]))
        bad_files = []
        for i in insns:
            if i["op"] in (0x14, 0x17):
                target = i["args"]["script"]
                if target not in sections_of or i["args"]["section"] not in sections_of[target]:
                    bad_files.append((i["offset"], target, i["args"]["section"]))
            elif i["op"] == 0xFB and i["args"]["script"] not in sections_of:
                bad_files.append((i["offset"], i["args"]["script"], None))
        out.check(f"{label}: script/section references exist", not bad_files, str(bad_files[:3]))
        pads = sum(i["nonzero_pads"] for i in insns)
        out.check(f"{label}: alignment bytes are zero", pads == 0, str(pads))

        texts = sum(1 for i in insns if i["op"] in (0x10, 0x1A))
        span = src.span(off, size)
        if sid == "MAPHEAD":
            folder, base, title = out.dir / "MAPHEAD", "script", "MAPHEAD.SCN (script 0: map setup + global sections)"
            extra = {"script_id": 0, "maps": []}
        else:
            linked = maps_of.get(sid, [])
            names = ", ".join(f"map {m['map']} {m['map_name']} ({m['display_name']})" for m in linked) or "no map"
            folder, base, title = out.dir / "DG", f"script_{sid:03d}", f"DG.SCN script {sid} - {names}"
            extra = {"script_id": sid, "maps": linked}
            if sid == 0:
                extra["note"] = "copy of MAPHEAD.SCN + padding; never read (getScript(0) returns MAPHEAD)"
        _dump(folder / f"{base}.json", _record(span, title, dis, extra))
        (folder / f"{base}.txt").write_text(listing(title, dis), encoding="utf-8")
        out.assets.append({"asset_id": span.asset_id, "sidecar": out._rel(folder / f"{base}.json"),
                           "outputs": [out._rel(folder / f"{base}.txt")]})
        summary.append({"script": 0 if sid == "MAPHEAD" else sid, "file": "MAPHEAD" if sid == "MAPHEAD" else "DG",
                        "asset_id": span.asset_id, "json": out._rel(folder / f"{base}.json"),
                        "sections": len(header["sections"]), "instructions": len(insns), "texts": texts,
                        "maps": [m["map"] for m in extra["maps"]]})

    out.check("MAPHEAD map sections: section id = map id = a MAP_ENTRIES slot",
              all(m["maphead_section"] == m["map"] and m["map"] in map_names for m in map_links), str(len(map_links)))
    with_files = {e["id"] for e in map_names.values() if e["filename"]}
    out.check("every named map has a MAPHEAD section", with_files <= {m["map"] for m in map_links},
              str(sorted(with_files - {m["map"] for m in map_links})))
    _dump(out.dir / "index.json", {
        "dg_table": {"entries": table["entries"][:table["used_entries"]], "used_entries": table["used_entries"],
                     "padding_hex": table_tail.hex(), "leftover_file_names": leftover_names},
        "maps": map_links,
        "scripts": sorted(summary, key=lambda s: (s["file"] != "MAPHEAD", s["script"])),
    })

    # Tournament cup table (specs/tournament_entry.md §5.1b) from script 168 sections 0x0A / 0x0B.
    arena_src, arena_off, arena_size, arena_data, arena_dis = decoded[ARENA_SCRIPT]
    base_cups, b_list = _read_cups_from_script(arena_data, arena_dis)

    records = []
    for c in base_cups:
        c_values = c["c_values"]
        min_roster = c_values[0]
        min_wins = c_values[1]
        req_type = c_values[2]
        if req_type == 0:
            also = {"type": "none"}
        elif req_type == 1:
            also = {"type": "won", "tournament": WON_TOURNAMENT}
        elif req_type == 2:
            also = {"type": "count", "list": b_list, "min": min_wins}
        else:
            also = {"type": "count_until", "until": req_type, "min": min_wins}

        records.append({
            "id": c["id"],
            "requirement": {
                "c_values": c_values,
                "min_roster": min_roster,
                "also": also,
            },
            "overleveled": c["overleveled"],
            "eligible": c["eligible"],
            "opponents": c["opponents"],
            "info": {
                "raw": c["info_raw"],
                "text": c["info_text"],
                "offset": c["info_offset"],
            },
            "source": {
                "script": ARENA_SCRIPT,
                "cup_table": c["table"],
                "entries": c["entries"],
            },
        })

    out.check("23 tournament cups", len(records) == CUPS, f"{len(records)} records")

    copies_match = True
    for sid in CUP_COPIES:
        if sid not in decoded:
            copies_match = False
            break
        copy_cups, copy_b_list = _read_cups_from_script(decoded[sid][3], decoded[sid][4])
        if copy_b_list != b_list:
            copies_match = False
            break
        for base_c, copy_c in zip(base_cups, copy_cups):
            if (base_c["c_values"] != copy_c["c_values"] or
                    base_c["overleveled"] != copy_c["overleveled"] or
                    base_c["eligible"] != copy_c["eligible"] or
                    base_c["opponents"] != copy_c["opponents"] or
                    base_c["info_raw"] != copy_c["info_raw"]):
                copies_match = False
                break
        if not copies_match:
            break
    out.check("cup copies agree across scripts 213, 102, 209", copies_match,
              f"scripts {CUP_COPIES} match script {ARENA_SCRIPT}")

    all_ids = []
    for r in records:
        all_ids.extend(r["overleveled"])
        all_ids.extend(r["eligible"])
        if r["opponents"] is not None:
            all_ids.extend(r["opponents"])
    all_ids.extend(b_list)
    all_in_roster = all(0 <= x < 0x70 for x in all_ids)
    out.check("every tournament list id is in roster range (< 0x70)", all_in_roster,
              f"{len(all_ids)} ids checked (max {max(all_ids) if all_ids else 'none'})")

    arena_span = arena_src.span(arena_off, arena_size)
    _dump(out.dir / "tournament_cups.json", {
        "asset_id": f"{arena_span.asset_id}#tournament_cups",
        "family": NAME,
        "format": "tournament_cups",
        "source": arena_span.identity(),
        "copies_checked": list(CUP_COPIES),
        "records": records,
    })

    out.finish([mh, dg, exe])
    return out
