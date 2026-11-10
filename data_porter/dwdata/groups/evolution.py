"""Evolution group: requirements (EVOLUTION_REQS), paths (EVOLUTION_PATHS), stat gains
(EVOLUTION_STATS_GAINS) and evolution item targets (EVOLUTION_ITEM_TARGET).

Follows specs/evolution.md. The selection logic (evolution.c) is code: the spec documents it,
and the converter checks that the constants it relies on are still in the code.
"""

from collections import defaultdict

from .. import discmode, tables
from ..cdata import CIndex, Value, describe_type
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText
from ..tables import REFERENCE
from . import text as text_group

NAME = "evolution"
SPEC = "specs/evolution.md"
PURPOSE = "Evolution requirements, paths, stat gains and evolution item targets"
SOURCE_GLOB = "src/main/evolution.c"

EVO_C = "src/main/evolution.c"
ITEM_C = "src/main/item.c"
MAIN_C = "src/main/main.c"
EVL_C = "src/evl/evl.c"
HEADER = "include/dw/evl.h"
NAMES_TEXT = "text/main/main.yaml"
ITEMS_TEXT = "text/main/item.yaml"

NONE = -1
STATS = ["hp", "mp", "offense", "defense", "speed", "brain"]
REQ_FIELDS = ["digimon", "hp", "mp", "offense", "defense", "speed", "brain", "care", "weight", "discipline",
              "happiness", "battles", "techs", "flags", "padding"]
GAIN_FIELDS = ["hp", "mp", "offense", "defense", "speed", "brains", "targetDigimon"]
FLAG_MAX_BATTLES, FLAG_MAX_CARE = 0x01, 0x10          # evolution.c:709-710
WEIGHT_RANGE = 5                                       # evolution.c:959
ROOKIE_LEVEL = 3
FIRST_EVO_ITEM, CONSTANT_EVO_ITEMS = 0x47, {0x7D: 0x40, 0x7E: 0x3F, 0x7F: 0x41}   # item.c:2194-2209
SCALE_TARGETS = [0x0B, 0x27, 0x35, 6]                  # evl.c:1357: stats scaled instead of gained
# Constants of the selection code (spec §2); each must still be in the file.
EVIDENCE = [
    (EVO_C, "if (bestScore < requirementScore && requirementScore >= 3)"),
    (EVO_C, "reqs->weight - 5 <= partner->weight"),
    (EVO_C, "if (currentBestDigimon == -1 && PARTNER_PARA.evoTimer >= 96)"),
    (EVO_C, "currentBestDigimon = 11;"),
    ("src/main/partner_impl.c", "if (level == 1 && evoTimer >= 6)"),
    ("src/main/partner_impl.c", "else if (level == 2 && evoTimer >= 24)"),
    ("src/main/partner_impl.c", "else if (level == 3 && evoTimer >= 72)"),
    ("src/main/partner_impl.c", "else if (level == 4 && evoTimer >= 144)"),
    ("src/main/partner_impl.c", "if (level == 4 && evoTimer == 360)"),
    ("src/main/partner_impl.c", "if (PARTNER_PARA.virusBar >= 16) {"),
    (EVL_C, "if (digimonId == 0x0b || digimonId == 0x27 || digimonId == 0x35 || digimonId == 6 ||"),
    (EVL_C, "stats->base.hp += (int16_t)(gains->hp / 10);"),
    (EVL_C, "stats->base.hp = (gains->hp + stats->base.hp) / 2;"),
]
# getFreshEvolutionTarget (evolution.c:674-688): fixed In-Training form of each Fresh.
FRESH_TARGETS = {0x01: 0x02, 0x0F: 0x10, 0x1D: 0x1E, 0x2B: 0x2C}
PARTNER_IMPL_C = "src/main/partner_impl.c"
ELEMENTS = {0: "fire", 1: "battle", 2: "air", 3: "earth", 4: "ice", 5: "mech", 6: "filth"}
# The rules the code writes as literals (specs/evolution.md, ../specs/evolution.md §3.3): each with
# the C text it comes from, checked by the converter.
HOURS = [  # tickConditions (partner_impl.c:2108-2119): level, evo_timer threshold, selection
    (1, "fresh", 6, "fixed"), (2, "in_training", 24, "best_score"), (3, "rookie", 72, "best_average"),
    (4, "champion", 144, "best_average")]
FALLBACK = {"level": 3, "evo_timer_at_least": 96, "target": 11}   # getRookieEvolutionTarget
VIRUS = {"bar_at_least": 16, "target": 0x27, "backup_value": 5}   # tickConditions :2122-2135
# handleSpecialEvolutions (evolution.c:852-925), in C order: mode, roll < chance (None: no roll),
# from, conditions, target, the C lines.
SPECIAL = [
    (2, 30, [0x15, 0x0A], {"discipline": 100, "happiness": 100, "tiredness": 0}, 7,
     ["if ((type == 0x15 || type == 0x0a) && discipline == 100 &&", "happiness == 100 && tiredness == 0) {",
      "evoTarget = 7;"]),
    (2, 30, [0x19], {"battles_at_least": 50, "discipline": 100}, 58,
     ["if (type == 0x19 && battles >= 50 && discipline == 100) {", "evoTarget = 58;"]),
    (2, 30, [0x26], {"defense_at_least": 500, "discipline": 100}, 47,
     ["if (type == 0x26 && def >= 500 && discipline == 100) {", "evoTarget = 47;"]),
    (2, 50, [0x02, 0x1E, 0x10, 0x2C], {"map": 1}, 32,
     ["(type == 0x02 || type == 0x1E || type == 0x10 || type == 0x2c) &&", "CURRENT_SCREEN == 1) {",
      "evoTarget = 32;"]),
    (3, 30, [0x18, 0x23], {"level": 4, "evo_timer": 200}, 49,
     ["if ((type == 0x18 || type == 0x23) && level == 4 && evotimer == 200 &&", "evoTarget = 49;"]),
    (3, None, [], {"nanimon_trigger": True}, 53,
     ["if (NANIMON_TRIGGER == 1) {", "evoTarget = 53;", "NANIMON_TRIGGER = 0;"]),
    (3, 50, [], {"level": 4, "evo_timer_at_least": 240}, 28,
     ["if (level == 4 && evotimer >= 240 && rand < 50) {", "evoTarget = 28;"]),
]
SPECIAL_EVIDENCE = ["case 2: {", "if (rand < 30) {", "if (rand < 50 &&", "case 3: {", "rand < 30) {"]
# EVL_applyEvolution (evl.c:1418-1440): the first technique id of each element's block; the block
# is base .. base + 8, inclusive.
TECHNIQUE_BASES = {0: 0, 1: 40, 2: 8, 3: 32, 4: 16, 5: 24, 6: 49}
TECHNIQUE_SPAN = 8

TABLE_PURPOSES = {
    "requirements": "What each Digimon needs to be evolved into: stats, care mistakes, weight, one bonus condition",
    "paths": "Evolution chart: which Digimon each one comes from and can evolve into",
    "stat_gains": "Stats an evolution adds (or the factor it scales them by), per target Digimon",
    "item_targets": "Digimon each evolution item turns the partner into",
    "rules": "The evolution rules the code writes as literals: hourly thresholds, fixed and fallback targets, the "
             "virus bar, scaled targets, special evolutions, technique blocks",
}


def _key(name: str) -> str:
    return "dw1:" + "".join(c if c.isalnum() else "_" for c in (name or "").lower()).strip("_")


def _rules(out, decomp, dref, to_of, level) -> list:
    """The rule records (../specs/evolution.md §3.3), each checked against the C text."""
    text = {p: discmode.Code(NAME, decomp, p)
            for p in (EVO_C, EVL_C, PARTNER_IMPL_C)}
    missing = []
    rules = []
    for lvl, name, hours, select in HOURS:
        needle = f"level == {lvl} && evoTimer >= {hours})"
        if needle not in text[PARTNER_IMPL_C]:
            missing.append(needle)
        rules.append({"key": f"dw1:hours_{name}", "rule": "hours", "level": lvl, "evo_timer_at_least": hours,
                      "select": select})
    for a, b in FRESH_TARGETS.items():
        rules.append({"key": _key(f"fresh_{dref(a)['name']}"), "rule": "fresh_target", "from": dref(a),
                      "target": dref(b)})
    fresh_paths = [f"{a}->{b}" for a, b in FRESH_TARGETS.items() if to_of.get(a) != [b]]
    out.check("evolution/rules: each fixed Fresh target is its only path", not fresh_paths,
              "; ".join(fresh_paths) or f"{len(FRESH_TARGETS)} Fresh")
    rules.append({"key": _key(f"fallback_{dref(FALLBACK['target'])['name']}"), "rule": "fallback",
                  "level": FALLBACK["level"], "evo_timer_at_least": FALLBACK["evo_timer_at_least"],
                  "target": dref(FALLBACK["target"])})
    rules.append({"key": _key(f"virus_{dref(VIRUS['target'])['name']}"), "rule": "virus",
                  "bar_at_least": VIRUS["bar_at_least"], "target": dref(VIRUS["target"]),
                  "backup_value": VIRUS["backup_value"]})
    for needle in ("if (PARTNER_ENTITY.digimonEntity.entity.type != 0x27L) {", "EVOLUTION_TARGET = 0x27;",
                   "writePStat(5, PARTNER_ENTITY.digimonEntity.entity.type);"):
        if needle not in text[PARTNER_IMPL_C]:
            missing.append(needle)
    for t in SCALE_TARGETS:
        rules.append({"key": _key(f"scaled_{dref(t)['name']}"), "rule": "scaled_target", "target": dref(t)})
    seen = set()
    for mode, chance, sources, conditions, target, needles in SPECIAL:
        base = _key(f"special_{dref(target)['name']}")
        key = base if base not in seen else f"{base}_{len(seen)}"
        seen.add(key)
        rec = {"key": key, "rule": "special", "mode": mode, "chance": chance, "from": [dref(s) for s in sources],
               "conditions": dict(conditions), "target": dref(target)}
        if "map" in conditions:
            rec["conditions"]["map"] = {"id": conditions["map"]}
        rules.append(rec)
        missing += [n for n in needles if n not in text[EVO_C]]
    missing += [n for n in SPECIAL_EVIDENCE if n not in text[EVO_C]]
    for element, first in TECHNIQUE_BASES.items():
        cond = "if (special == 0) {" if element == 0 else f"}} else if (special == {element}) {{"
        if f"{cond}\n\t\tmoveBase = {first};" not in text[EVL_C]:
            missing.append(f"{cond} moveBase = {first}")
        rules.append({"key": f"dw1:technique_block_{ELEMENTS[element]}", "rule": "technique_block",
                      "element": {"id": element, "name": ELEMENTS[element]}, "first": first,
                      "last": first + TECHNIQUE_SPAN})
    if "if (moveBase <= *movePtr && *movePtr <= moveBase + 8) {" not in text[EVL_C]:
        missing.append("moveBase <= *movePtr && *movePtr <= moveBase + 8")
    out.check("evolution/rules: every rule's literals are still in the C", not missing,
              "; ".join(missing)[:400] or f"{len(rules)} rules")
    bad_levels = [r["key"] for r in rules if r["rule"] == "special" and r["from"]
                  and len({level[f["id"]] for f in r["from"]}) != 1]
    out.check("evolution/rules: each special rule's Digimon share one level", not bad_levels,
              "; ".join(bad_levels) or "ok")
    keys = [r["key"] for r in rules]
    out.check("evolution/rules: keys unique", len(keys) == len(set(keys)), str(len(keys)))
    return rules


def _opt(v):
    return None if v == NONE else v


def _report(reqs, paths, gains, item_targets, names) -> str:
    out = ["# Evolution report", "",
           "Generated by `python -m dwdata convert evolution`. US values (no release differences). `—` = no "
           "requirement. Care: `≤` = at most (flag 0x10), `≥` = at least. Bonus: any one of them counts. "
           "See `specs/evolution.md`.", "",
           "## Requirements (`evolution/requirements.json`)", "",
           "| id | Digimon | level | HP | MP | Off | Def | Speed | Brain | care | weight | bonus: from / disc. / "
           "happy / battles / techs |", "|---|---|---|---|---|---|---|---|---|---|---|---|"]
    for r in reqs:
        if not r["has_requirements"]:
            continue
        st = r["stats"]
        if r["stat_rule"] == "highest":
            cells = ["highest" if st[s] else "—" for s in STATS]
        else:
            cells = [str(st[s]) if st[s] is not None else "—" for s in STATS]
        care = r["care_mistakes"]
        b = r["bonus"]
        bonus = " / ".join([
            names(b["from_digimon"]) if b["from_digimon"] is not None else "—",
            str(b["discipline"]) if b["discipline"] is not None else "—",
            str(b["happiness"]) if b["happiness"] is not None else "—",
            (("≤" if b["battles"]["at_most"] else "≥") + str(b["battles"]["value"])) if b["battles"] else "—",
            str(b["techs"]) if b["techs"] is not None else "—"])
        out.append(f"| {r['id']} | {r['name']} | {r['level']} | " + " | ".join(cells) +
                   f" | {'≤' if care['at_most'] else '≥'}{care['value']} | {r['weight']['value']} | {bonus} |")
    out += ["", "## Paths (`evolution/paths.json`)", "", "| id | Digimon | from | to |", "|---|---|---|---|"]
    for p in paths:
        out.append(f"| {p['id']} | {p['name']} | {', '.join(names(i) for i in p['from']) or '—'} | "
                   f"{', '.join(names(i) for i in p['to']) or '—'} |")
    out += ["", "## Stat gains (`evolution/stat_gains.json`)", "",
            "| id | Digimon | applied as | HP | MP | Off | Def | Speed | Brain |", "|---|---|---|---|---|---|---|---|---|"]
    for g in gains:
        if g["applied_as"] == "scale":
            note = " (never reached; table has unused gains)" if "unused_gains" in g else ""
            out.append(f"| {g['id']} | {g['name']} | scale ×{g['scale']}{note} | | | | | | |")
        else:
            out.append(f"| {g['id']} | {g['name']} | gain | " + " | ".join(str(g["gains"][s]) for s in STATS) + " |")
    out += ["", "## Evolution items (`evolution/item_targets.json`)", "", "| item | target |", "|---|---|"]
    for t in item_targets:
        note = "" if t["can_work"] else " (never works: target level 0)"
        out.append(f"| {t['item']['id']} {t['item']['name']} | {t['target']['id']} {t['target']['name']}{note} |")
    return "\n".join(out) + "\n"


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    index = CIndex(decomp)
    sources = [SourceText(decomp.root, p).identity() for p in
               [EVO_C, ITEM_C, EVL_C, "src/main/partner_impl.c", HEADER, NAMES_TEXT, ITEMS_TEXT]]

    problems = []
    for release in decomp.releases:
        structs = index.program(EVO_C, release).structs
        for type_name, fields in (("EvoRequirements", REQ_FIELDS), ("EvoStatsGains", GAIN_FIELDS),
                                  ("EvolutionPath", ["from", "to"])):
            st = structs.get(type_name)
            if not st or [f.name for f in st.fields] != fields:
                problems.append(f"{type_name} {release}: {st and [f.name for f in st.fields]}")
    out.check("structs EvoRequirements, EvoStatsGains, EvolutionPath have the fields the spec maps",
              not problems, "; ".join(problems) or "ok")
    missing = [f"{path}: {needle}" for path, needle in EVIDENCE
               if needle not in discmode.Code(NAME, decomp, path)]
    out.check("the selection code still has the constants the spec documents", not missing,
              "; ".join(missing) or f"{len(EVIDENCE)} constants")
    fresh_text = discmode.Code(NAME, decomp, EVO_C)
    fresh_missing = [f"{a:#04x}->{b:#04x}" for a, b in FRESH_TARGETS.items()
                     if f"if (currentDigimon == {a:#04x})\n    result = {b:#04x};" not in fresh_text]
    out.check("getFreshEvolutionTarget has the fixed Fresh -> In-Training targets", not fresh_missing,
              f"not found: {fresh_missing}" if fresh_missing else str(FRESH_TARGETS))

    reqs_l = tables.load(out, index, EVO_C, "EVOLUTION_REQS")
    paths_l = tables.load(out, index, EVO_C, "EVOLUTION_PATHS")
    gains_l = tables.load(out, index, EVO_C, "EVOLUTION_STATS_GAINS")
    items_l = tables.load(out, index, ITEM_C, "EVOLUTION_ITEM_TARGET")
    digimon_l = tables.load(out, index, MAIN_C, "DIGIMON_DATA",
                            {"DIGIMON_PARA_NAME": lambda a, r, t: [] if r == "eu" else [Value(a[0], t.line)]})
    names_model = text_group.load_file(decomp, NAMES_TEXT)
    items_model = text_group.load_file(decomp, ITEMS_TEXT)
    dnames = text_group.block_of(names_model, "DIGIMON_NAMES")
    inames = text_group.block_of(items_model, "ITEM_NAMES")
    out.check("names found (DIGIMON_NAMES, ITEM_NAMES)", dnames is not None and inames is not None)
    loaded = [reqs_l, paths_l, gains_l, items_l, digimon_l]
    if not all(loaded) or dnames is None or inames is None:
        out.finish(sources)
        return out
    for l in loaded[:4]:
        tables.size_check(out, decomp, l)

    def dname(i):
        if i is None or not 0 <= i < len(dnames["items"]):
            return None
        return (tables.text_ref(dnames["items"][i]) or {}).get("text", {}).get("en_us")

    def dref(i):
        return {"id": i, "name": dname(i)}

    level = [d["level"] for d in digimon_l[REFERENCE].value]
    raw_reqs, raw_paths = reqs_l[REFERENCE].value, paths_l[REFERENCE].value
    raw_gains, raw_items = gains_l[REFERENCE].value, items_l[REFERENCE].value

    # -- paths --------------------------------------------------------------------------------
    paths = []
    for i, p in enumerate(raw_paths):
        did = i + 1
        rec = {"id": did, "name": dname(did), "line": (paths_l[REFERENCE].element_lines or [None] * 62)[i],
               "from": [x for x in p["from"] if x > 0], "to": [x for x in p["to"] if x > 0], "c": p}
        odd = [x for x in p["from"] + p["to"] if x != NONE and x <= 0]
        if odd:
            rec["ignored_values"] = odd
        paths.append(rec)
    to_of = {p["id"]: p["to"] for p in paths}
    from_of = {p["id"]: p["from"] for p in paths}
    one_way = [f"{a}->{b}" for a, ts in to_of.items() for b in ts if a not in from_of.get(b, [a])]
    chart_only = [f"{a}->{b}" for b, fs in from_of.items() for a in fs if b not in to_of.get(a, [])]
    jumps = [f"{a}->{b}" for a, ts in to_of.items() for b in ts if level[b] != level[a] + 1]
    out.check("every path goes one level up and is listed on both sides (from / to)", not one_way and not jumps,
              "; ".join(one_way + jumps)[:300] or
              f"{sum(len(t) for t in to_of.values())} paths; chart-only `from` entries: {chart_only}")

    # -- requirements -------------------------------------------------------------------------
    bad = defaultdict(list)
    reqs = []
    for i, r in enumerate(raw_reqs):
        if r["flags"] & ~(FLAG_MAX_BATTLES | FLAG_MAX_CARE):
            bad["flags use only bits 0x01 / 0x10"].append(f"{i}: {r['flags']:#x}")
        if r["padding"]:
            bad["padding is 0"].append(str(i))
        rookie = level[i] == ROOKIE_LEVEL
        if rookie and any(r[s] not in (NONE, 1) for s in STATS):
            bad["Rookie stat requirements are flags (1 / -1)"].append(str(i))
        if r["digimon"] != NONE and r["digimon"] not in from_of.get(i, []):
            bad["the bonus Digimon is one this Digimon comes from"].append(f"{i}: {r['digimon']}")
        has = any(r[k] != NONE for k in STATS + ["weight"])
        # Fresh -> In-Training is fixed (getFreshEvolutionTarget); every other path is scored on requirements
        reached = any(i in ts for a, ts in to_of.items() if a not in FRESH_TARGETS)
        if reached and not has:
            bad["every Digimon reached by a scored path has requirements"].append(str(i))
        reqs.append({
            "id": i, "name": dname(i), "level": level[i], "line": (reqs_l[REFERENCE].element_lines or [None] * 63)[i],
            "has_requirements": has,
            "stat_rule": "highest" if rookie else "minimum",
            "stats": {s: r[s] == 1 if rookie else _opt(r[s]) for s in STATS},
            "care_mistakes": {"value": r["care"], "at_most": bool(r["flags"] & FLAG_MAX_CARE)},
            "weight": {"value": _opt(r["weight"]), "range": [r["weight"] - WEIGHT_RANGE, r["weight"] + WEIGHT_RANGE]
                       if r["weight"] != NONE else None},
            "bonus": {"from_digimon": _opt(r["digimon"]), "discipline": _opt(r["discipline"]),
                      "happiness": _opt(r["happiness"]),
                      "battles": {"value": r["battles"], "at_most": bool(r["flags"] & FLAG_MAX_BATTLES)}
                      if r["battles"] != NONE else None,
                      "techs": _opt(r["techs"])},
            "c": r})
    for check in ("flags use only bits 0x01 / 0x10", "padding is 0", "Rookie stat requirements are flags (1 / -1)",
                  "the bonus Digimon is one this Digimon comes from",
                  "every Digimon reached by a scored path has requirements"):
        out.check(f"EVOLUTION_REQS: {check}", not bad[check], "; ".join(bad[check][:10]) or f"{len(reqs)} records")

    # -- stat gains ---------------------------------------------------------------------------
    gains, gbad = [], []
    for i, g in enumerate(raw_gains):
        scale = i in SCALE_TARGETS or level[i] < ROOKIE_LEVEL
        if g["targetDigimon"] != i:
            gbad.append(f"{i}: target {g['targetDigimon']}")
        has_gains = any(g[s] for s in ("hp", "mp", "offense", "defense", "speed"))
        # an item only works when the partner's level is the target's level - 1 (item.c:2205-2207)
        working_items = {t for t in raw_items if level[t] - 1 >= 1}
        reachable = (any(i in ts for ts in to_of.values()) or i in working_items
                     or i in CONSTANT_EVO_ITEMS.values())
        if scale and has_gains and reachable:
            gbad.append(f"{i}: reachable scale target with gains")
        rec = {"id": i, "name": dname(i), "line": (gains_l[REFERENCE].element_lines or [None] * 66)[i],
               "target": g["targetDigimon"], "applied_as": "scale" if scale else "gain"}
        if scale:
            rec["scale"] = g["brains"] / 10
            if has_gains:
                # e.g. WereGarurumon (62): level 0 in DIGIMON_DATA, so the code scales; never reached
                rec["unused_gains"] = {"hp": g["hp"], "mp": g["mp"], "offense": g["offense"],
                                       "defense": g["defense"], "speed": g["speed"], "brain": g["brains"]}
        else:
            rec["gains"] = {"hp": g["hp"], "mp": g["mp"], "offense": g["offense"], "defense": g["defense"],
                            "speed": g["speed"], "brain": g["brains"]}
        rec["c"] = g
        gains.append(rec)
    out.check("EVOLUTION_STATS_GAINS: targetDigimon is the index; reachable scaled targets have no gains", not gbad,
              "; ".join(gbad[:10]) or f"{len(gains)} records, scaled: {[g['id'] for g in gains if g['applied_as'] == 'scale']}")

    # -- item targets -------------------------------------------------------------------------
    def iname(i):
        return (tables.text_ref(inames["items"][i]) or {}).get("text", {}).get("en_us")
    item_targets = [{"item": {"id": FIRST_EVO_ITEM + k, "name": iname(FIRST_EVO_ITEM + k)}, "target": dref(t),
                     "from": f"EVOLUTION_ITEM_TARGET[{k}]", "needs_level": level[t] - 1,
                     "can_work": level[t] - 1 >= 1} for k, t in enumerate(raw_items)]
    item_targets += [{"item": {"id": it, "name": iname(it)}, "target": dref(t),
                      "from": "constant in handleEvoItems (item.c:2194-2203)", "needs_level": None, "can_work": True}
                     for it, t in CONSTANT_EVO_ITEMS.items()]
    item_text = discmode.Code(NAME, decomp, ITEM_C)
    const_missing = [f"{it:#x}" for it, t in CONSTANT_EVO_ITEMS.items()
                     if f"if (item == {it:#x}) {{\n\t\t\tEVOLUTION_TARGET = {t:#x};" not in item_text]
    out.check("evolution item targets: table covers items 0x47-0x72, constants for 0x7d-0x7f",
              len(raw_items) == 0x72 - FIRST_EVO_ITEM + 1 and not const_missing,
              f"{len(raw_items)} entries; missing constants: {const_missing}" if const_missing else
              f"{len(raw_items)} entries (items {FIRST_EVO_ITEM:#x}-{FIRST_EVO_ITEM + len(raw_items) - 1:#x})")

    # -- rules --------------------------------------------------------------------------------
    rules = _rules(out, decomp, dref, to_of, level)

    # -- write --------------------------------------------------------------------------------
    refs = decomp.references(["EVOLUTION_REQS", "EVOLUTION_PATHS", "EVOLUTION_STATS_GAINS", "EVOLUTION_ITEM_TARGET"])
    status = "implemented (scripts/data/game_data.gd)"
    structs = index.program(EVO_C, REFERENCE).structs

    def write(name, loaded_, schema, records, symbol, fields, godot, extra=None):
        st = {"EVOLUTION_REQS": "EvoRequirements", "EVOLUTION_STATS_GAINS": "EvoStatsGains",
              "EVOLUTION_PATHS": "EvolutionPath"}.get(symbol)
        if st:
            schema = dict(schema, _struct={"c_type": st, "header": f"{HEADER}:{structs[st].line}",
                                           "fields": describe_type(structs[st])})
        out.write_table(name, {
            "table": {"name": f"evolution/{name}", "purpose": TABLE_PURPOSES[name]},
            "source": tables.source(decomp, loaded_, sources, extra), "schema": schema, "records": records,
            "used_by": tables.used_by(decomp, refs[symbol], fields, loaded_),
            "godot": dict(status=status, **godot)}, symbols=[symbol])

    write("requirements", reqs_l, {
        "id": {"meaning": "target Digimon id = index (0-62); 63-65 are reached only by items / special rules"},
        "level": {"meaning": "target's level (DIGIMON_DATA); Rookie targets use the highest-stat rule"},
        "has_requirements": {"meaning": "false for Digimon reached only by fixed or special evolutions"},
        "stat_rule": {"meaning": "minimum: partner stat >= value (HP and MP compared / 10) for all set stats; "
                                 "highest: the partner's highest stat must be one marked true"},
        "stats": {"c_name": "hp, mp, offense, defense, speed, brain", "meaning": "null / false = not required"},
        "care_mistakes": {"c_name": "care, flags & 0x10", "meaning": "at_most: careMistakes <= value, else >= value"},
        "weight": {"c_name": "weight", "meaning": "partner weight within value ± 5"},
        "bonus": {"meaning": "one point if any is met: from_digimon (the current Digimon), discipline >=, "
                             "happiness >=, battles (<= if at_most, flags & 0x01, else >=), techs (learned "
                             "techniques >=)"},
        "c": {"meaning": "the record as the C initializer gives it (-1 = none)"},
    }, reqs, "EVOLUTION_REQS", REQ_FIELDS, {"access": "GameData.evolution_requirements(id)"})

    write("paths", paths_l, {
        "id": {"meaning": "Digimon id = index + 1 (EVOLUTION_PATHS[id - 1])"},
        "from": {"c_name": "from[5]", "meaning": "Digimon shown before it in the chart (ids > 0)"},
        "to": {"c_name": "to[6]", "meaning": "evolution candidates, in the order the selection loop reads them"},
        "ignored_values": {"meaning": "entries other than -1 that are not Digimon ids (<= 0); the chart skips them"},
        "c": {"meaning": "the record as the C initializer gives it"},
    }, paths, "EVOLUTION_PATHS", ["from", "to"],
        {"access": "GameData.evolution_paths(id)",
         "notes": "Only Fresh to Champion paths drive evolution; Ultimate entries are read by the chart only."})

    write("stat_gains", gains_l, {
        "id": {"meaning": "target Digimon id = index"},
        "target": {"c_name": "targetDigimon", "meaning": "the Digimon the partner becomes (= id)"},
        "applied_as": {"meaning": "gain: each stat += gain / 10 if already >= gain, else = (gain + stat) / 2; "
                                  "scale: all stats x scale (Fresh / In-Training targets and ids 6, 0x0b, 0x27, 0x35)"},
        "gains": {"c_name": "hp, mp, offense, defense, speed, brains"},
        "scale": {"derived": "brains / 10"},
        "unused_gains": {"meaning": "gain values of a target the code scales instead (level < 3); not applied"},
        "c": {"meaning": "the record as the C initializer gives it"},
    }, gains, "EVOLUTION_STATS_GAINS", GAIN_FIELDS,
        {"access": "GameData.evolution_gains(id)", "notes": "No gains when an evolution item was used."})

    write("item_targets", items_l, {
        "item": {"meaning": "evolution item", "ref": "items/item_data"},
        "target": {"meaning": "Digimon it evolves the partner into", "ref": "digimon/digimon_data"},
        "from": {"meaning": "table entry (index = item id - 0x47) or code constant"},
        "needs_level": {"meaning": "partner level the item requires (target level - 1); null = no check"},
        "can_work": {"meaning": "false when no partner can have needs_level (target level 0: the item does "
                                "nothing)"},
    }, item_targets, "EVOLUTION_ITEM_TARGET", [], {"access": "GameData.evolution_item_target(item_id)"})

    out.write_table("rules", {
        "table": {"name": "evolution/rules", "purpose": TABLE_PURPOSES["rules"]},
        "source": {"files": sources, "c_file": EVO_C, "symbol": None,
                   "functions": ["tickConditions (src/main/partner_impl.c:2106-2149)",
                                 "getFreshEvolutionTarget, getRookieEvolutionTarget, handleSpecialEvolutions "
                                 "(src/main/evolution.c:674-925)", "EVL_applyEvolution (src/evl/evl.c:1332-1470)"],
                   "note": "literals of the code, one record per rule; each checked against the C text"},
        "schema": {
            "key": {"meaning": "content key of the rule (a pack patches or adds rules by key)"},
            "rule": {"values": ["hours", "fresh_target", "fallback", "virus", "scaled_target", "special",
                                "technique_block"]},
            "level": {"meaning": "hours / fallback: the partner's level (DIGIMON_DATA level id)"},
            "evo_timer_at_least": {"meaning": "hours / fallback: evo_timer threshold of the hourly check"},
            "select": {"meaning": "hours: fixed (fresh_target rules), best_score (highest requirement score >= 3), "
                                  "best_average (highest stat average among scores >= 3)"},
            "from": {"meaning": "fresh_target: the Fresh; special: the partner Digimon it applies to (empty: any)",
                     "ref": "digimon/digimon_data"},
            "target": {"meaning": "the Digimon evolved into", "ref": "digimon/digimon_data"},
            "bar_at_least": {"meaning": "virus: virus_bar threshold"},
            "backup_value": {"meaning": "virus: script value storing the partner's Digimon (PSTAT_SUKAMON_BACKUP)"},
            "mode": {"meaning": "special: 2 after waking up, 3 after praise / scold and Champion evo_timer 360"},
            "chance": {"meaning": "special: randomLimit(100) < chance (one roll per call); null: no roll"},
            "conditions": {"meaning": "special: discipline / happiness / tiredness / level / evo_timer equal; "
                                      "battles_at_least / defense_at_least / evo_timer_at_least; map (CURRENT_SCREEN); "
                                      "nanimon_trigger (set; cleared when the rule matches)"},
            "element": {"meaning": "technique_block: special[0] of the new Digimon"},
            "first": {"meaning": "technique_block: first technique id"},
            "last": {"meaning": "technique_block: last id, inclusive (first + 8: reaches the next block's first)"},
        },
        "records": rules, "used_by": [],
        "godot": {"status": status, "access": "GameData.evolution_rules(rule)",
                  "notes": "Records of one rule in table order; special rules apply in order, later ones "
                           "overwriting earlier ones."}}, symbols=[])

    out.write_report("report.md", _report(reqs, paths, gains, item_targets, lambda i: dname(i) or str(i)))
    out.finish(sources, extra={"counts": {"requirements": sum(r["has_requirements"] for r in reqs),
                                          "paths": sum(len(p["to"]) for p in paths), "items": len(item_targets)},
                               "fresh_targets": {f"{a}": b for a, b in FRESH_TARGETS.items()},
                               "chart_only_from": chart_only})
    return out
