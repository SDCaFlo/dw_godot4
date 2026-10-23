"""Moves group: techniques (MOVE_DATA), element factors (TYPE_FACTORS), learn chances (MOVE_LEARN_CHANCES).

Follows specs/moves.md. All three tables are C initializers in src/main/item.c, read per release
with cdata.CIndex; technique names come from text/main/item.yaml (MOVE_NAMES, same index).
"""

import math
from collections import defaultdict

from .. import tables
from ..cdata import CIndex, describe_type
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText
from ..tables import REFERENCE, enum as _enum
from . import text as text_group

NAME = "moves"
SPEC = "specs/moves.md"
PURPOSE = "Techniques (power, MP, range, element, status), element damage factors, technique learn chances"
SOURCE_GLOB = "src/main/item.c"
C_FILE = "src/main/item.c"
TEXT_FILE = "text/main/item.yaml"
STRUCT_HEADER = "include/dw/move.h"

# Move struct fields (include/dw/move.h) -> JSON name; the converter checks the struct still matches.
FIELDS = [
    ("distance", "distance_squared"), ("power", "power"), ("mpCost", "mp_cost"), ("iframes", "iframes"),
    ("range", "range"), ("special", "element"), ("status", "status"), ("accuracy", "accuracy"),
    ("statusChance", "status_chance"), ("unk3", "flags"), ("unk4", "unk4"), ("unk5", "unk5"),
]
RANGES = {0: "none", 1: "melee", 2: "ranged", 3: "area", 4: "self"}
ELEMENTS = {0: "fire", 1: "battle", 2: "air", 3: "earth", 4: "ice", 5: "mech", 6: "filth", 255: "none"}
STATUSES = {0: "none", 1: "poison", 2: "confusion", 3: "stun", 4: "flatten"}
FLAG_BITS = {0: "needs_target", 1: "shared_cooldown"}
FACTORS = (2, 5, 10, 15, 20)   # the values BTL_calculateElementBonus handles (battle_main.c:3570)

# Id ranges, from the code that tests them (spec §2).
TECHNIQUE_END = 0x3A      # learnedMoves bits / MOVE_LEARN_CHANCES rows / usedMoves (battle_main.c:2551)
FINISHER_END = 0x71       # `(tech >= 0x3a) && (tech < 0x71)` (battle_main.c:2334, ...)
COUNTER = 0x2D            # special-cased everywhere (battle_main.c:2006, 2116, 2330)
GENERIC = 0x79            # BTL_getAttackTech: effect 0x179 -> tech 0x79 (battle_main.c:1881)
EVIDENCE = [
    ("src/btl/battle_main.c", "(tech >= 0x3a) && (tech < 0x71)"),
    ("src/btl/battle_main.c", "if (tech == 0x2d)"),
    ("src/btl/battle_main.c", "tech = 0x79;"),
    ("src/main/utils2.c", "move == 0x2C || move == 0x30"),
]
# learnMove (utils2.c:320): these pairs are learned together (same technique, two ids).
LEARNED_TOGETHER = {0x2C: 0x30, 0x30: 0x2C, 0x37: 0x39, 0x39: 0x37}

TABLE_PURPOSES = {
    "move_data": "Techniques: power, MP cost, preferred distance, range, element, status effect, accuracy, flags",
    "type_factors": "Element damage factors: attacker technique element x defender element (10 = x1.0)",
    "learn_chances": "Chance (%) to learn a technique seen in battle, by which of the partner's 3 elements matches",
}

MOVE_SCHEMA = {
    "id": {"meaning": "technique id = index in MOVE_DATA and MOVE_NAMES; DIGIMON_DATA[].moves hold these ids"},
    "key": tables.KEY_SCHEMA,
    "name": {"meaning": "MOVE_NAMES[id] (text/main/item.json): string id and text per language; unnamed entries "
                        "repeat an earlier entry (same_as)", "ref": "text/main/item"},
    "category": {"meaning": "from the id ranges the code tests: technique (0x00-0x39, learnable), finisher "
                            "(0x3a-0x70, no MP, finisher charge-up), other (0x71-0x79)",
                 "values": ["technique", "finisher", "other"]},
    "line": {"meaning": "line of the record in src/main/item.c"},
    "power": {"c_name": "power", "c_type": "int16_t",
              "meaning": "damage base (BTL_calculateDamage); also subtracted from the fighter's speed buffer when the "
                         "technique starts, and the charge needed in charge mode 1"},
    "mp_cost": {"c_name": "mpCost", "c_type": "uint8_t", "meaning": "raw MP cost; the game always uses mp_cost * 3"},
    "mp": {"derived": "mp_cost * 3", "meaning": "MP shown in the menus and spent in battle (before the partner's "
                                                "brain discount / sickness surcharge)"},
    "distance_squared": {"c_name": "distance", "c_type": "int32_t", "unit": "world units squared",
                         "meaning": "preferred attack distance squared, added to (radius_a + radius_b)^2 "
                                    "(BTL_tickRangedAttack); 0 = at contact"},
    "distance": {"derived": "sqrt(distance_squared)", "unit": "world units (100 = one map tile)"},
    "iframes": {"c_name": "iframes", "c_type": "uint8_t", "unit": "frames",
                "meaning": "invulnerability of the target after a hit; hit particle lifetime = iframes + 16"},
    "range": {"c_name": "range", "c_type": "uint8_t", "values": RANGES,
              "meaning": "1 melee (walk to contact), 2 ranged, 3 ranged, preferred by the AI against several "
                         "enemies, 4 self (buff on the user); 0 only on id 0x79"},
    "element": {"c_name": "special", "c_type": "uint8_t", "values": ELEMENTS,
                "meaning": "row of TYPE_FACTORS; matched against the partner's 3 elements to learn it"},
    "status": {"c_name": "status", "c_type": "uint8_t", "values": STATUSES,
               "meaning": "status inflicted on hit (BTL_applyMoveStatus)"},
    "accuracy": {"c_name": "accuracy", "c_type": "uint8_t", "unit": "%",
                 "meaning": "base hit chance, reduced by the defender's speed (BTL_calculateHitChance)"},
    "status_chance": {"c_name": "statusChance", "c_type": "uint8_t", "unit": "%",
                      "meaning": "chance to inflict `status` on hit; 0 = never"},
    "flags": {"c_name": "unk3", "c_type": "uint8_t", "bits": FLAG_BITS,
              "meaning": "bit 0 needs_target: unusable without a target, auto-targets when cast without one; "
                         "bit 1 shared_cooldown: starting one blocks all bit-1 techniques for 110 frames"},
    "unk4": {"c_name": "unk4", "c_type": "uint8_t", "meaning": "not read by any code; 0 in every record"},
    "unk5": {"c_name": "unk5", "c_type": "uint8_t", "meaning": "not read by any code; 0 in every record"},
    "c": {"meaning": "the record exactly as the C initializer gives it (C field names)"},
    "release_values": {"meaning": "fields whose value differs in another release: {release: {c field: value}}"},
}


def _category(move_id: int) -> str:
    if move_id < TECHNIQUE_END:
        return "technique"
    if move_id < FINISHER_END:
        return "finisher"
    return "other"


def _report(moves: list, factors: list, chances: list) -> str:
    out = ["# Moves report", "",
           "Generated by `python -m dwdata convert moves`. Values of the US release; differences of other releases "
           "are listed under the table. MP = mp_cost × 3 (what the menus show). Distance = √distance_squared. "
           "Flags: T = needs_target (bit 0), C = shared_cooldown (bit 1). See `specs/moves.md`.", "",
           "## Techniques (`moves/move_data.json`)", "",
           "| id | hex | name (en_us) | category | power | MP | range | element | status | status % | accuracy | "
           "iframes | distance | flags |",
           "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|"]
    diffs = []
    for m in moves:
        flags = "".join(c for c, bit in (("T", "needs_target"), ("C", "shared_cooldown")) if m["flags"][bit]) or "-"
        name = m["name"]["text"]["en_us"] if m["name"] else "—"
        out.append(f"| {m['id']} | {m['id']:#04x} | {name or '—'} | {m['category']} | {m['power']} | {m['mp']} | "
                   f"{m['range']['name']} | {m['element']['name']} | {m['status']['name']} | {m['status_chance']} | "
                   f"{m['accuracy']} | {m['iframes']} | {m['distance']} | {flags} |")
        for release, d in m.get("release_values", {}).items():
            diffs.append(f"- {m['id']} {name}: {release} " + ", ".join(f"`{k}` = {v}" for k, v in d.items())
                         + f" (us: " + ", ".join(f"{m['c'][k]}" for k in d) + ")")
    out += ["", "Release differences:", ""] + (diffs or ["- none"]) + [""]
    names = [ELEMENTS[i] for i in range(7)]
    out += ["## Element factors (`moves/type_factors.json`)", "",
            "Rows: element of the technique; columns: element of the defender. 10 = ×1.0.", "",
            "| technique \\ defender | " + " | ".join(names) + " |", "|---|" + "---|" * 7]
    for row in factors:
        out.append(f"| {row['attacker']['name']} | " + " | ".join(str(c["factor"]) for c in row["against"]) + " |")
    out += ["", "## Learn chances (`moves/learn_chances.json`)", "",
            "Chance (%) to learn a technique the enemies used, by which of the partner's 3 elements "
            "(`DIGIMON_DATA[].special[0..2]`) matches the technique's element.", "",
            "| id | name | 1st element | 2nd element | 3rd element |", "|---|---|---|---|---|"]
    for c in chances:
        out.append(f"| {c['id']} | {c['name']} | " + " | ".join(str(x) for x in c["chances"]) + " |")
    return "\n".join(out) + "\n"


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    index = CIndex(decomp)
    src = SourceText(decomp.root, C_FILE)
    sources = [src.identity(), SourceText(decomp.root, STRUCT_HEADER).identity(),
               SourceText(decomp.root, TEXT_FILE).identity()]

    # Struct layout must be the one the spec maps.
    struct = index.program(C_FILE, REFERENCE).structs.get("Move")
    c_fields = [f.name for f in struct.fields] if struct else []
    out.check("struct Move has the fields the spec maps", c_fields == [c for c, _ in FIELDS],
              f"{STRUCT_HEADER}: {c_fields}")
    for release in decomp.releases:
        other = index.program(C_FILE, release).structs.get("Move")
        if not other or [f.name for f in other.fields] != c_fields:
            out.check(f"struct Move is the same in {release}", False, str(other and [f.name for f in other.fields]))

    for path, needle in EVIDENCE:
        text = (decomp.root / path).read_text(encoding="utf-8", errors="replace")
        out.check(f"code still tests the id ranges: {needle}", needle in text, path)

    move_data = tables.load(out, index, C_FILE, "MOVE_DATA")
    type_factors = tables.load(out, index, C_FILE, "TYPE_FACTORS")
    learn = tables.load(out, index, C_FILE, "MOVE_LEARN_CHANCES")

    names_model = text_group.load_file(decomp, TEXT_FILE)
    names_block = text_group.block_of(names_model, "MOVE_NAMES")
    out.check("MOVE_NAMES found in " + TEXT_FILE, names_block is not None and not names_model.issues,
              "; ".join(names_model.issues[:5]))
    if not (move_data and type_factors and learn and names_block):
        out.finish(sources)
        return out

    refs = decomp.references(["MOVE_DATA", "TYPE_FACTORS", "MOVE_LEARN_CHANCES"])
    us = move_data[REFERENCE]
    counts = {r: len(l.value) for r, l in move_data.items()}
    out.check("MOVE_DATA has one record per MOVE_NAMES entry in every release",
              all(n == len(names_block["items"]) for n in counts.values()),
              f"MOVE_DATA {counts}, MOVE_NAMES {len(names_block['items'])}")
    for loaded in (move_data, type_factors, learn):
        tables.size_check(out, decomp, loaded)

    # -- move_data ----------------------------------------------------------------------------
    entries = names_block["items"]
    records, bad = [], defaultdict(list)
    for i, raw in enumerate(us.value):
        name = tables.text_ref(entries[i] if i < len(entries) else None)
        dist = raw["distance"]
        root = math.isqrt(dist) if dist >= 0 else None
        if root is None or root * root != dist:
            bad["distance_squared is a perfect square"].append(f"{i}: {dist}")
        if raw["range"] not in RANGES:
            bad["range is a known value"].append(f"{i}: {raw['range']}")
        if raw["special"] not in ELEMENTS:
            bad["element is a known value"].append(f"{i}: {raw['special']}")
        if raw["status"] not in STATUSES:
            bad["status is a known value"].append(f"{i}: {raw['status']}")
        if (raw["status"] == 0) != (raw["statusChance"] == 0):
            bad["status and status_chance are both set or both 0"].append(str(i))
        if raw["unk3"] & ~0b11:
            bad["flags use only bits 0-1"].append(f"{i}: {raw['unk3']}")
        if raw["unk4"] or raw["unk5"]:
            bad["unk4 / unk5 are 0"].append(str(i))
        if _category(i) != "other" and name is None:
            bad["techniques and finishers have a name"].append(str(i))
        rec = {"id": i, "name": name, "category": _category(i),
               "line": us.element_lines[i] if us.element_lines else None,
               "power": raw["power"], "mp_cost": raw["mpCost"], "mp": raw["mpCost"] * 3,
               "distance_squared": dist, "distance": root if root is not None and root * root == dist else None,
               "iframes": raw["iframes"], "range": _enum(raw["range"], RANGES),
               "element": _enum(raw["special"], ELEMENTS), "status": _enum(raw["status"], STATUSES),
               "accuracy": raw["accuracy"], "status_chance": raw["statusChance"],
               "flags": {"value": raw["unk3"], **{n: bool(raw["unk3"] >> b & 1) for b, n in FLAG_BITS.items()}},
               "unk4": raw["unk4"], "unk5": raw["unk5"]}
        if i in LEARNED_TOGETHER:
            rec["learned_with"] = LEARNED_TOGETHER[i]
        rec["c"] = raw
        rd = tables.diffs(move_data, lambda l, i=i: l.value[i])
        if rd:
            rec["release_values"] = rd
        records.append(rec)
    tables.keys(out, records, "move", tables.name_base("STR_MOVE_NAME_"))
    for check in ("distance_squared is a perfect square", "range is a known value", "element is a known value",
                  "status is a known value", "status and status_chance are both set or both 0",
                  "flags use only bits 0-1", "unk4 / unk5 are 0", "techniques and finishers have a name"):
        out.check(f"MOVE_DATA: {check}", not bad[check], "; ".join(bad[check][:10]) or f"{len(records)} records")

    move_fields = [c for c, _ in FIELDS]

    def source_of(loaded, extra=None):
        return tables.source(decomp, loaded, sources, extra)

    schema = dict(MOVE_SCHEMA)
    schema["_struct"] = {"c_type": "Move", "header": f"{STRUCT_HEADER}:{struct.line}",
                         "fields": describe_type(struct)}
    out.write_table("move_data", {
        "table": {"name": "moves/move_data", "purpose": TABLE_PURPOSES["move_data"]},
        "source": source_of(move_data, {"struct": f"{STRUCT_HEADER}:{struct.line}", "names": f"{TEXT_FILE} MOVE_NAMES"}),
        "schema": schema,
        "records": records,
        "used_by": tables.used_by(decomp, refs["MOVE_DATA"], move_fields, move_data),
        "godot": {"status": "implemented (scripts/data/game_data.gd)",
                  "access": "GameData.move(id) -> record; GameData.text_entry(\"main/item\", \"MOVE_NAMES\", id) for "
                            "the name",
                  "notes": "Battle code uses mp (= mp_cost * 3), distance_squared as the C code does, and the id "
                           "ranges in `category` (finishers 0x3a-0x70 skip MP and AI). Keep 122 records."},
    }, symbols=["MOVE_DATA"])

    # -- type_factors -------------------------------------------------------------------------
    grid = type_factors[REFERENCE].value
    shape_ok = len(grid) == 7 and all(len(r) == 7 for r in grid)
    out.check("TYPE_FACTORS is 7 x 7 and uses only the factors the code handles",
              shape_ok and all(v in FACTORS for r in grid for v in r),
              f"values {sorted({v for r in grid for v in r})}, handled {list(FACTORS)}")
    factor_records = []
    for a, row in enumerate(grid):
        factor_records.append({"attacker": _enum(a, ELEMENTS), "line": (type_factors[REFERENCE].element_lines or
                                                                         [None] * 7)[a],
                               "against": [{"defender": _enum(d, ELEMENTS), "factor": v, "multiplier": v / 10}
                                           for d, v in enumerate(row)]})
    tf_diff = tables.diffs(type_factors, lambda l: l.value)
    out.write_table("type_factors", {
        "table": {"name": "moves/type_factors", "purpose": TABLE_PURPOSES["type_factors"]},
        "source": source_of(type_factors),
        "schema": {"attacker": {"meaning": "element of the technique (first index)", "values": ELEMENTS},
                   "against": {"meaning": "one cell per defender element (second index)"},
                   "factor": {"c_type": "uint8_t", "meaning": "TYPE_FACTORS[attacker][defender]; damage uses "
                              "(f1 + f2 + f3) / 30 over the defender's 3 elements, 10 for an empty slot (0xff)",
                              "values": list(FACTORS)},
                   "multiplier": {"derived": "factor / 10"}},
        "records": factor_records,
        "release_values": tf_diff,
        "used_by": tables.used_by(decomp, refs["TYPE_FACTORS"], [], type_factors),
        "godot": {"status": "implemented (scripts/data/game_data.gd)", "access": "GameData.type_factor(attacker_element, defender_element)",
                  "notes": "Keep 7 x 7: element ids index it directly."},
    }, symbols=["TYPE_FACTORS"])

    # -- learn_chances ------------------------------------------------------------------------
    rows = learn[REFERENCE].value
    out.check("MOVE_LEARN_CHANCES has one row per technique id (0x00-0x39)", len(rows) == TECHNIQUE_END,
              f"{len(rows)} rows, techniques 0x00-{TECHNIQUE_END - 1:#04x}")
    chance_records = []
    for i, row in enumerate(rows):
        chance_records.append({"id": i, "name": records[i]["name"]["text"]["en_us"] if records[i]["name"] else None,
                               "chances": row})
    out.write_table("learn_chances", {
        "table": {"name": "moves/learn_chances", "purpose": TABLE_PURPOSES["learn_chances"]},
        "source": source_of(learn),
        "schema": {"id": {"meaning": "technique id (first index)", "ref": "moves/move_data"},
                   "name": {"meaning": "technique name (en_us), for reading"},
                   "chances": {"c_type": "uint8_t[3]", "unit": "%",
                               "meaning": "index = which of the partner's 3 elements (DIGIMON_DATA[].special[0..2]) "
                                          "equals the technique's element; learned if chance > randomLimit(100)"}},
        "records": chance_records,
        "release_values": tables.diffs(learn, lambda l: l.value),
        "used_by": tables.used_by(decomp, refs["MOVE_LEARN_CHANCES"], [], learn),
        "godot": {"status": "implemented (scripts/data/game_data.gd)", "access": "GameData.learn_chance(move_id, element_slot)",
                  "notes": "Only techniques 0x00-0x39 can be learned this way."},
    }, symbols=["MOVE_LEARN_CHANCES"])

    out.write_report("report.md", _report(records, factor_records, chance_records))
    out.finish(sources, extra={"counts": {"moves": len(records), "categories": {
        c: sum(1 for r in records if r["category"] == c) for c in ("technique", "finisher", "other")}},
        "release_differences": {r["id"]: r["release_values"] for r in records if "release_values" in r}})
    return out
