"""Digimon group: per-Digimon data (DIGIMON_DATA), partner care data (RAISE_DATA, SLEEP_PATTERN,
ITEM_TAKE_DISTANCE), model file names (PTR_DIGIMON_FILE_NAMES) and sound bank ids.

Follows specs/digimon.md. Names come from text/main/main.yaml (DIGIMON_NAMES, same index as
DIGIMON_DATA); technique and item names from text/main/item.yaml.
"""

from collections import defaultdict

from .. import tables
from ..cdata import CIndex, Value, describe_type
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText
from ..tables import REFERENCE, enum
from . import moves as moves_group
from . import text as text_group

NAME = "digimon"
SPEC = "specs/digimon.md"
PURPOSE = "Digimon data (size, type, level, elements, drops, techniques), partner care data, model files, sounds"
SOURCE_GLOB = "src/{main/main,main/partner_impl,main/model,main/sound,trn/trn_reward}.c"

MAIN_C = "src/main/main.c"
PARTNER_C = "src/main/partner_impl.c"
MODEL_C = "src/main/model.c"
SOUND_C = "src/main/sound.c"
TRN_C = "src/trn/trn_reward.c"
TAMER_C = "src/main/tamer.c"
HEADERS = ["include/dw/params.h", "include/dw/partner.h"]
NAMES_FILE = "text/main/main.yaml"
ITEMS_FILE = "text/main/item.yaml"

NUM_DIGIMON = 180
NUM_PARTNER = 66            # NUM_PARTNER_DIGIMON (params.h:8): ids 0-65 can be the partner (0 = tamer)
MOVE_ANIM_BASE = 0x2E       # move slot k of DIGIMON_DATA[].moves is animation 0x2e + k (utils2.c:341)
NO_VALUE = 0xFF
NUM_ITEMS = 128             # ITEM_PARA[128] (item.c:745)
NUM_MOVES = 122

TYPES = {0: "none", 1: "data", 2: "vaccine", 3: "virus", NO_VALUE: "none"}
LEVELS = {0: "none", 1: "fresh", 2: "in_training", 3: "rookie", 4: "champion", 5: "ultimate"}
ELEMENTS = moves_group.ELEMENTS

DIGIMON_FIELDS = ["name", "boneCount", "radius", "height", "type", "level", "special", "dropItem", "dropChance",
                  "moves", "padding"]
RAISE_FIELDS = ["hungerTimes", "energyCap", "energyThreshold", "energyUsage", "poopTimer", "unk2", "poopSize",
                "favoriteFood", "sleepCycle", "favoredRegion", "trainingType", "defaultWeight", "viewX", "viewY",
                "viewZ"]
SLEEP_FIELDS = ["sleepyHour", "sleepyMinute", "wakeupHour", "wakeupMinute", "awakeHours", "sleepyHours"]
# model.c:2691-2695 ("CHDAT\\MMD0\\", "CHDAT\\TMD0\\"); the loaders then patch the folder digit:
# path[9] = id / 30 + '0' (model.c:3409, :3445, :3631 for MMD, :3682 for TMD), so ids 30-59 are in MMD1 ...
MODEL_DIRS = {"mmd": "CHDAT/MMD{folder}/{name}.MMD", "tmd": "CHDAT/TMD{folder}/{name}.TMD"}
MODELS_PER_FOLDER = 30
FOLDER_EVIDENCE = ["path[9] = digiType / 30 + '0';", "path[9] = digimonType / 30 + '0';"]
# Battle rules on literal Digimon ids, turned into digimon_data properties (../specs/battle.md §6); the C text
# must still be there (whitespace collapsed).
BTL_C = "src/main/btl.c"
BTL_MAIN_C = "src/btl/battle_main.c"
UTILS2_C = "src/main/utils2.c"
# loadBattleData (btl.c:358): enemy 1 of type 0x73 -> variant 3; an NPC enemy of type 0x43-0x6f ->
# ENEMY_MUSIC_MAPPING[type - 0x43]; any other -> 1 (predefined battles -> 0, a rule of the code).
MUSIC_SPECIAL = {0x73: 3}
MUSIC_FIRST, MUSIC_END, MUSIC_DEFAULT = 0x43, 0x70, 1
# BTL_resetFlatten (battle_main.c:857), BTL_tickStatusEffects: type 0x71's normal scale is 0x1800.
SCALE_DEFAULT, SCALE_SPECIAL = 0x1000, {0x71: 0x1800}
# getOriginalType (effect_common.c:320): ORIGINAL_DIGIMON_TYPES[type], or the type itself when < 0 (and -1 above
# 0xb0); the battle effects pick their per-Digimon bone offsets by it (BTL_checkTechCompatibility).
EFFECT_COMMON_C = "src/main/effect_common.c"
ORIGINAL_LIMIT = 0xB0
ORIGINAL_EVIDENCE = "if ((type < 0) || (type > 0xb0)) { return -1; } originalType = ORIGINAL_DIGIMON_TYPES[type]; if (originalType < 0) { return type; } return originalType;"
# entityGetTechFromAnim (utils2.c:333): type 0x3c's animation 0x3c is technique 0x70.
ANIM_TECHNIQUE = {0x3C: {0x3C: 0x70}}
STD_MAIN = "src/std/std_main.c"
STD_SETUP = "src/std/std_setup.c"
STAND_INS = {0x3F: 0x30, 0x40: 0x36, 0x41: 0x2A}
STAND_IN_EVIDENCE = "if (arg[n] == 0x40) { arg[n] = 0x36; } if (arg[n] == 0x3f) { arg[n] = 0x30; } if (arg[n] == 0x41) { arg[n] = 0x2a; }"
INTRO_LEN_EVIDENCE = "if (entity->type == 0x4e || entity->type == 0x3c) { len = 10; }"
BATTLE_EVIDENCE = [
    (BTL_C, "if (ENTITY_TABLE[COMBAT_DATA_PTR->player.entityIds[1]]->type == 0x73) { playMusic(0x21, 3);"),
    (BTL_C, "if ((ENTITY_TABLE[entityId]->type >= 0x43) && (ENTITY_TABLE[entityId]->type < 0x70L)) { "
            "playMusic(0x21, ENEMY_MUSIC_MAPPING[ENTITY_TABLE[entityId]->type - 0x43]); } else { playMusic(0x21, 1); }"),
    (BTL_MAIN_C, "if (entity->type != 0x71) { entity->posData->scale.vx = 0x1000; entity->posData->scale.vy = 0x1000; "
                 "entity->posData->scale.vz = 0x1000; } else { entity->posData->scale.vx = 0x1800;"),
    (BTL_MAIN_C, "if (entity->type == 0x71) { entity->posData->scale.vx = 0x1800;"),
    (UTILS2_C, "if ((e->type == 0x3cL) && (anim == 0x3c)) { return 0x70; }"),
]

# Care rules on literal Digimon ids (partner_impl.c), turned into raise_data properties (../specs/content.md §4,
# ../specs/care.md §4). The C text must still be there (compared with whitespace collapsed).
# initializePartner: equipped animation and learned technique of the starters
FIRST_TECHNIQUE = [
    (3, 0x2E, 2, "if (type == 3) { PARTNER_ENTITY.digimonEntity.stats.base.moves[0] = 0x2e; learnMove(2); }"),
    (0x11, 0x30, 0x2B, "if (type == 0x11) { PARTNER_ENTITY.digimonEntity.stats.base.moves[0] = 0x30; "
                       "learnMove(0x2b); }"),
]
# tickPoopDetection: only these walk to poop and eat it
POOP_EATERS = ({0xB, 0x27}, "if ((PARTNER_ENTITY.digimonEntity.entity.type != 0xb) && "
                            "(PARTNER_ENTITY.digimonEntity.entity.type != 0x27)) { return; }")
# createPoopPile: pooping raises the virus bar, except for this one
NO_VIRUS_BAR = ({0x27}, "if (PARTNER_ENTITY.digimonEntity.entity.type != 0x27) PARTNER_PARA.virusBar++;")
# tamerTickPraiseScold (tamer.c:1625): the low pat (animation 0x26) below Champion and for these small Ultimates
PRAISE_PAT_LOW = ({0xD, 0x1B, 0x38}, 4, "if ((DIGIMON_DATA[type].level < 4) || (type == 0xd) || (type == 0x1b) || "
                                        "(type == 0x38)) { startAnimation(&TAMER_ENTITY.entity, 0x26);")


def _collapsed(text: str) -> str:
    return " ".join(text.split())

TABLE_PURPOSES = {
    "digimon_data": "Every Digimon: name, bones, collision size, type, level, elements, drop item, technique slots",
    "raise_data": "Partner Digimon care data: hunger hours, energy, poop, favourite food, sleep cycle, training type, "
                  "weight, menu view position",
    "sleep_patterns": "Sleep cycles referenced by raise_data.sleep_cycle: sleepy / wake-up time, hours awake / asleep",
    "item_take_distance": "Partner: distance at which it takes an item thrown to it (index = Digimon id - 1)",
    "file_names": "Model / texture file name of every Digimon (CHDAT/MMD<id / 30>/<name>.MMD, CHDAT/TMD<id / 30>/<name>.TMD)",
    "sound_ids": "Sound banks of every Digimon: VBALL bank (all Digimon), VLALL voice bank (partners)",
    "training_animations": "Partner Digimon: the strike animation and the frame its hit lands at the Offense training "
                           "stations (TRN_TRAINING_ANIM_IDS)",
    "condition_fx_offsets": "Per original Digimon: the bone and offset the status effects (poison bubbles, confusion) "
                            "and condition bubbles are placed at (CONDITION_FX_OFFSETS)",
    "aura_projectile_types": "Per original Digimon: the sprite column of the aura projectile a flattened fighter fires "
                             "(BTL_AURA_PROJECTILE_TYPES)",
}
NUM_TRAINING_ANIMS = 67     # TRN_TRAINING_ANIM_IDS[67][2] (trn_reward.c:55), indexed by the partner's type
# Tables indexed by getOriginalType(type): CONDITION_FX_OFFSETS[177] (effect_common.c:69, read by
# translateConditionFXToEntity :307) and BTL_AURA_PROJECTILE_TYPES[129] (battle_effect.c:1308, read by
# BTL_addAuraProjectile :6146 and BTL_renderAuraProjectile :6119).
BTL_EFFECT_C = "src/btl/battle_effect.c"
NUM_CONDITION_FX = 177
NUM_AURA_TYPES = 129


def _name_hook(args, release, tok):
    # DIGIMON_PARA_NAME(STR_X): the name inside DIGIMON_DATA; EU has no name field (params.h:19)
    return [] if release == "eu" else [Value(args[0], tok.line)]


def _fields_check(out, index, c_file, type_name, expected, per_release=None):
    problems = []
    for release in index.releases:
        st = index.program(c_file, release).structs.get(type_name)
        want = per_release(release) if per_release else expected
        got = [f.name for f in st.fields] if st else None
        if got != want:
            problems.append(f"{release}: {got}")
    out.check(f"struct {type_name} has the fields the spec maps", not problems, "; ".join(problems) or
              ", ".join(expected))


def _bad(bad, check, what):
    bad[check].append(what)


def _report(digimon, raise_rows, patterns) -> str:
    out = ["# Digimon report", "",
           "Generated by `python -m dwdata convert digimon`. US values; release differences are listed under each "
           "table. Elements / type / level names are labels (see `specs/digimon.md`). Techniques are listed by "
           "slot: animation id = 0x2e + slot.", "",
           "## Digimon (`digimon/digimon_data.json`)", "",
           "| id | name (en_us) | level | type | elements | bones | radius | height | drop (chance %) | techniques |",
           "|---|---|---|---|---|---|---|---|---|---|"]
    diffs = []
    for d in digimon:
        els = ", ".join(e["name"] for e in d["elements"] if e["id"] != NO_VALUE) or "—"
        drop = f"{d['drop']['item']['name']} ({d['drop']['chance']})" if d["drop"]["chance"] else "—"
        techs = ", ".join(f"{m['move']['name'] or m['move']['id']}" for m in d["moves"]) or (
            "— (all slots 0)" if d.get("no_technique_list") else "—")
        out.append(f"| {d['id']} | {d['name']['text']['en_us'] if d['name'] else '—'} | {d['level']['name']} | "
                   f"{d['type']['name']} | {els} | {d['bone_count']} | {d['radius']} | {d['height']} | {drop} | "
                   f"{techs} |")
        for release, diff in d.get("release_values", {}).items():
            diffs.append(f"- {d['id']} {d['name']['text']['en_us']}: {release} " +
                         ", ".join(f"`{k}` = {v} (us: {d['c'][k]})" for k, v in diff.items()))
    out += ["", "Release differences:", ""] + (diffs or ["- none"]) + [""]
    out += ["## Partner care (`digimon/raise_data.json`)", "",
            "| id | name | hunger hours | energy cap / threshold / usage | poop timer / size | favourite food | "
            "sleep cycle | training type | weight | favoured region |",
            "|---|---|---|---|---|---|---|---|---|---|"]
    for r in raise_rows:
        p = r["sleep_cycle"]
        out.append(f"| {r['id']} | {r['name']} | {', '.join(map(str, r['hunger_hours'])) or '—'} | "
                   f"{r['energy_cap']} / {r['energy_threshold']} / {r['energy_usage']} | {r['poop_timer']} / "
                   f"{r['poop_size']} | {r['favorite_food']['name']} | {p['id']} ({p['summary']}) | "
                   f"{r['training_type']} | {r['default_weight']} | {r['favored_region']} |")
    out += ["", "## Sleep cycles (`digimon/sleep_patterns.json`)", "",
            "| id | sleepy | wake up | hours awake | hours asleep |", "|---|---|---|---|---|"]
    for p in patterns:
        out.append(f"| {p['id']} | {p['sleepy_hour']:02}:{p['sleepy_minute']:02} | {p['wakeup_hour']:02}:"
                   f"{p['wakeup_minute']:02} | {p['awake_hours']} | {p['sleepy_hours']} |")
    return "\n".join(out) + "\n"


def _pattern_summary(p: dict) -> str:
    return f"{p['sleepyHour']:02}:{p['sleepyMinute']:02}-{p['wakeupHour']:02}:{p['wakeupMinute']:02}"


def _original_type(digimon_id: int, table: list) -> int:
    if digimon_id < 0 or digimon_id > ORIGINAL_LIMIT:
        return -1
    value = table[digimon_id] if digimon_id < len(table) else -1
    return digimon_id if value < 0 else value


def _battle_music(digimon_id: int, mapping: list) -> int:
    if digimon_id in MUSIC_SPECIAL:
        return MUSIC_SPECIAL[digimon_id]
    if MUSIC_FIRST <= digimon_id < MUSIC_END:
        return mapping[digimon_id - MUSIC_FIRST]
    return MUSIC_DEFAULT


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    index = CIndex(decomp)
    sources = [SourceText(decomp.root, p).identity() for p in
               [MAIN_C, PARTNER_C, MODEL_C, SOUND_C, TAMER_C, TRN_C] + HEADERS + [NAMES_FILE, ITEMS_FILE]]

    _fields_check(out, index, MAIN_C, "DigimonPara", DIGIMON_FIELDS,
                  lambda r: DIGIMON_FIELDS[1:] if r == "eu" else DIGIMON_FIELDS)
    _fields_check(out, index, PARTNER_C, "RaiseData", RAISE_FIELDS)
    _fields_check(out, index, PARTNER_C, "SleepPattern", SLEEP_FIELDS)

    hooks = {"DIGIMON_PARA_NAME": _name_hook}
    data = tables.load(out, index, MAIN_C, "DIGIMON_DATA", hooks)
    raise_ = tables.load(out, index, PARTNER_C, "RAISE_DATA")
    sleep = tables.load(out, index, PARTNER_C, "SLEEP_PATTERN")
    take = tables.load(out, index, PARTNER_C, "ITEM_TAKE_DISTANCE")
    files = tables.load(out, index, MODEL_C, "PTR_DIGIMON_FILE_NAMES")
    vball = tables.load(out, index, SOUND_C, "DIGIMON_VBALL_SOUND_ID")
    vlall = tables.load(out, index, SOUND_C, "DIGIMON_VLALL_SOUND_ID")
    strikes = tables.load(out, index, TRN_C, "TRN_TRAINING_ANIM_IDS")
    music = tables.load(out, index, BTL_C, "ENEMY_MUSIC_MAPPING")
    originals = tables.load(out, index, EFFECT_COMMON_C, "ORIGINAL_DIGIMON_TYPES")
    condition_fx = tables.load(out, index, EFFECT_COMMON_C, "CONDITION_FX_OFFSETS")
    auras = tables.load(out, index, BTL_EFFECT_C, "BTL_AURA_PROJECTILE_TYPES")
    sources.append(SourceText(decomp.root, EFFECT_COMMON_C).identity())
    effect_c = " ".join((decomp.root / EFFECT_COMMON_C).read_text(encoding="utf-8", errors="replace").split())
    out.check("getOriginalType is still the table lookup", ORIGINAL_EVIDENCE in effect_c, ORIGINAL_EVIDENCE[:60])
    sources += [SourceText(decomp.root, p).identity() for p in (BTL_C, BTL_MAIN_C, UTILS2_C, STD_MAIN, STD_SETUP)]
    battle_text = {p: " ".join((decomp.root / p).read_text(encoding="utf-8", errors="replace").split())
                   for p in (BTL_C, BTL_MAIN_C, UTILS2_C)}
    missing = [f"{p}: {needle[:60]}" for p, needle in BATTLE_EVIDENCE if " ".join(needle.split()) not in battle_text[p]]
    out.check("the battle rules on Digimon ids are still in the code", not missing,
              "; ".join(missing) or f"{len(BATTLE_EVIDENCE)} rules")

    std_setup_c = " ".join((decomp.root / STD_SETUP).read_text(encoding="utf-8", errors="replace").split())
    std_main_c = " ".join((decomp.root / STD_MAIN).read_text(encoding="utf-8", errors="replace").split())
    out.check("arena stand-in types (0x40 -> 0x36, 0x3f -> 0x30, 0x41 -> 0x2a) in STD_tournamentMain",
              STAND_IN_EVIDENCE in std_setup_c, STAND_IN_EVIDENCE)
    out.check("arena intro text length (10 for 0x4e and 0x3c) in STD_addIntroText",
              INTRO_LEN_EVIDENCE in std_main_c, INTRO_LEN_EVIDENCE)

    sprite_clut = tables.load(out, index, STD_MAIN, "STD_DIGIMON_SPRITE_CLUT")
    bracket_icons = tables.load(out, index, STD_MAIN, "STD_BRACKET_PROJECTILE_ICONS")
    intro_names_t = index.table(STD_MAIN, "STD_INTRO_DIGIMON_NAMES")
    out.check("STD_INTRO_DIGIMON_NAMES: parsed in US", intro_names_t.get("us") is not None, "US intro names")

    names_model = text_group.load_file(decomp, NAMES_FILE)
    items_model = text_group.load_file(decomp, ITEMS_FILE)
    names = text_group.block_of(names_model, "DIGIMON_NAMES")
    move_names = text_group.block_of(items_model, "MOVE_NAMES")
    item_names = text_group.block_of(items_model, "ITEM_NAMES")
    out.check("names found (DIGIMON_NAMES, MOVE_NAMES, ITEM_NAMES)",
              all(b is not None for b in (names, move_names, item_names))
              and not names_model.issues and not items_model.issues,
              "; ".join((names_model.issues + items_model.issues)[:5]))
    loaded_all = [data, raise_, sleep, take, files, vball, vlall, strikes, sprite_clut, bracket_icons]
    if not music or not originals or not all(loaded_all) or not (names and move_names and item_names) or intro_names_t.get("us") is None:
        out.finish(sources)
        return out
    for loaded in loaded_all[:7]:
        tables.size_check(out, decomp, loaded)
    tables.size_check(out, decomp, strikes, binary="trn")
    tables.size_check(out, decomp, sprite_clut, binary="std")
    tables.size_check(out, decomp, bracket_icons, binary="std")

    counts = {"DIGIMON_DATA": len(data[REFERENCE].value), "DIGIMON_NAMES": len(names["items"]),
              "PTR_DIGIMON_FILE_NAMES": len(files[REFERENCE].value),
              "DIGIMON_VBALL_SOUND_ID": len(vball[REFERENCE].value)}
    out.check(f"{NUM_DIGIMON} entries in every per-Digimon table", set(counts.values()) == {NUM_DIGIMON}, str(counts))
    pcounts = {"RAISE_DATA": len(raise_[REFERENCE].value), "ITEM_TAKE_DISTANCE": len(take[REFERENCE].value),
               "DIGIMON_VLALL_SOUND_ID": len(vlall[REFERENCE].value)}
    out.check(f"{NUM_PARTNER} entries in every per-partner table", set(pcounts.values()) == {NUM_PARTNER},
              str(pcounts))

    def item_ref(item_id):
        e = item_names["items"][item_id] if item_id < len(item_names["items"]) else None
        return {"id": item_id, "name": (tables.text_ref(e) or {}).get("text", {}).get("en_us")}

    def move_ref(move_id):
        e = move_names["items"][move_id] if move_id < len(move_names["items"]) else None
        return {"id": move_id, "name": (tables.text_ref(e) or {}).get("text", {}).get("en_us")}

    def digimon_ref(digi_id):
        e = names["items"][digi_id] if digi_id < len(names["items"]) else None
        return {"id": digi_id, "name": (tables.text_ref(e) or {}).get("text", {}).get("en_us")}

    # -- digimon_data -------------------------------------------------------------------------
    bad = defaultdict(list)
    digimon = []
    us = data[REFERENCE]
    for i, raw in enumerate(us.value):
        entry = names["items"][i] if i < len(names["items"]) else None
        name = tables.text_ref(entry)
        if raw.get("name") != (entry or {}).get("id"):
            _bad(bad, "the embedded name is DIGIMON_NAMES[id]", f"{i}: {raw.get('name')} vs {(entry or {}).get('id')}")
        if raw["type"] not in TYPES:
            _bad(bad, "type is a known value", f"{i}: {raw['type']}")
        if raw["level"] not in LEVELS:
            _bad(bad, "level is a known value", f"{i}: {raw['level']}")
        if any(s not in ELEMENTS for s in raw["special"]):
            _bad(bad, "elements are known values", f"{i}: {raw['special']}")
        if any(m != NO_VALUE and m >= NUM_MOVES for m in raw["moves"]):
            _bad(bad, "technique slots hold technique ids or 0xff", f"{i}: {raw['moves']}")
        if raw["dropItem"] >= NUM_ITEMS:
            _bad(bad, "drop item is an item id", f"{i}: {raw['dropItem']}")
        if raw["dropChance"] > 100:
            _bad(bad, "drop chance is a percentage", f"{i}: {raw['dropChance']}")
        if raw["padding"]:
            _bad(bad, "padding is 0", str(i))
        rec = {"id": i, "name": name, "partner": i < NUM_PARTNER,
               "line": us.element_lines[i] if us.element_lines else None,
               "bone_count": raw["boneCount"], "radius": raw["radius"], "height": raw["height"],
               "type": enum(raw["type"], TYPES), "level": enum(raw["level"], LEVELS),
               "elements": [enum(s, ELEMENTS) for s in raw["special"]],
               "drop": {"item": item_ref(raw["dropItem"]), "chance": raw["dropChance"]},
               "moves": [{"slot": k, "anim": MOVE_ANIM_BASE + k, "move": move_ref(m)}
                         for k, m in enumerate(raw["moves"]) if m != NO_VALUE],
               "padding": raw["padding"],
               "battle_music": _battle_music(i, music[REFERENCE].value),
               "battle_scale": SCALE_SPECIAL.get(i, SCALE_DEFAULT),
               "original_type": _original_type(i, originals[REFERENCE].value)}
        if i in ANIM_TECHNIQUE:
            rec["anim_technique"] = {str(a): t for a, t in ANIM_TECHNIQUE[i].items()}
        if i < 0x70:
            us_name = (entry.get("text") or {}).get("en_us") or ""
            intro_len = 10 if i in (0x4E, 0x3C) else len(us_name) // 2
            rec["arena_name"] = {
                "glyphs": intro_names_t["us"].value[i],
                "length": intro_len,
            }
            rec["bracket_sprite_clut"] = sprite_clut[REFERENCE].value[i]
            rec["bracket_icon"] = bracket_icons[REFERENCE].value[i]
        if i in STAND_INS:
            rec["arena_stand_in"] = digimon_ref(STAND_INS[i])
        rec["c"] = raw
        if all(m == 0 for m in raw["moves"]):
            # 16 x technique 0 (NPCs, unused ids): no technique list; real lists end with 0xff
            rec["moves"] = []
            rec["no_technique_list"] = True
        rd = tables.diffs(data, lambda l, i=i: {k: v for k, v in l.value[i].items() if k != "name"})
        if rd:
            rec["release_values"] = rd
        digimon.append(rec)
    tables.keys(out, digimon, "digimon", tables.name_base("STR_DIGIMON_NAME_"))
    for check in ("the embedded name is DIGIMON_NAMES[id]", "type is a known value", "level is a known value",
                  "elements are known values", "technique slots hold technique ids or 0xff",
                  "drop item is an item id", "drop chance is a percentage", "padding is 0"):
        out.check(f"DIGIMON_DATA: {check}", not bad[check], "; ".join(bad[check][:10]) or f"{len(digimon)} records")

    refs = decomp.references(["DIGIMON_DATA", "RAISE_DATA", "SLEEP_PATTERN", "ITEM_TAKE_DISTANCE",
                              "PTR_DIGIMON_FILE_NAMES", "DIGIMON_VBALL_SOUND_ID", "DIGIMON_VLALL_SOUND_ID",
                              "TRN_TRAINING_ANIM_IDS"])
    struct = index.program(MAIN_C, REFERENCE).structs["DigimonPara"]
    status = "implemented (scripts/data/game_data.gd)"
    out.write_table("digimon_data", {
        "table": {"name": "digimon/digimon_data", "purpose": TABLE_PURPOSES["digimon_data"]},
        "source": tables.source(decomp, data, sources, {"struct": f"include/dw/params.h:{struct.line}",
                                                        "names": f"{NAMES_FILE} DIGIMON_NAMES"}),
        "schema": {
            "id": {"meaning": "Digimon id (entity type) = index in DIGIMON_DATA, DIGIMON_NAMES, the model / sound tables"},
            "key": tables.KEY_SCHEMA,
            "name": {"meaning": "DIGIMON_NAMES[id] (text/main/main.json); embedded in the struct as `name` "
                                "(char[20]) except in EU, where the struct has no name field", "ref": "text/main/main"},
            "partner": {"meaning": "id < 66 (NUM_PARTNER_DIGIMON): has raise_data, voice bank and can be the partner"},
            "line": {"meaning": "line of the record in src/main/main.c"},
            "bone_count": {"c_name": "boneCount", "c_type": "int32_t", "meaning": "number of model nodes animated"},
            "radius": {"c_name": "radius", "c_type": "int16_t", "unit": "world units",
                       "meaning": "collision / contact radius, drop shadow size"},
            "height": {"c_name": "height", "c_type": "int16_t", "unit": "world units",
                       "meaning": "height: collision box, bubbles and battle markers above the head"},
            "type": {"c_name": "type", "c_type": "uint8_t", "values": TYPES,
                     "meaning": "Data / Vaccine / Virus; picks the flee chance (FLEE_CHANCES) and the menu icon"},
            "level": {"c_name": "level", "c_type": "uint8_t", "values": LEVELS,
                      "meaning": "evolution stage; drives care timers, training gains, hit chance (< 3 always hit)"},
            "elements": {"c_name": "special", "c_type": "uint8_t[3]", "values": ELEMENTS,
                         "meaning": "defender elements for TYPE_FACTORS; technique learning matches them"},
            "drop": {"c_name": "dropItem, dropChance", "meaning": "item dropped after a won battle with chance %"},
            "moves": {"c_name": "moves", "c_type": "uint8_t[16]",
                      "meaning": "technique slots: slot k is animation 0x2e + k and holds a technique id; "
                                 "0xff slots are left out here (kept in `c`)", "ref": "moves/move_data"},
            "battle_music": {"derived": "loadBattleData (btl.c:358): 3 for type 0x73, ENEMY_MUSIC_MAPPING[id - 0x43] "
                                        "for 0x43-0x6f, else 1",
                             "meaning": "variant of battle song 0x21 when this Digimon is the opponent (a "
                                        "predefined battle plays 0, a rule of the code)"},
            "battle_scale": {"derived": "BTL_resetFlatten (battle_main.c:857): 0x1800 for type 0x71, else 0x1000",
                             "unit": "4096 = 1.0", "meaning": "the model scale battles restore after a flatten"},
            "original_type": {"c_name": "ORIGINAL_DIGIMON_TYPES", "derived": "getOriginalType (effect_common.c:320)",
                              "meaning": "the Digimon this one is a variant of (NPC copies -> the partner Digimon), "
                                         "or itself; -1 above 0xb0. The battle effects choose their bone offsets "
                                         "by it (BTL_checkTechCompatibility)"},
            "anim_technique": {"derived": "entityGetTechFromAnim (utils2.c:333)",
                               "meaning": "{animation id (decimal string): technique id} overriding moves[anim - 0x2e]; "
                                          "absent = none"},
            "arena_name": {"c_name": "STD_INTRO_DIGIMON_NAMES[id]",
                           "meaning": "{glyphs: [14 uint8], length: len(US name) // 2 (10 for 0x4e and 0x3c)}; id < 0x70 only"},
            "bracket_sprite_clut": {"c_name": "STD_DIGIMON_SPRITE_CLUT[id]", "c_type": "uint8_t",
                                    "meaning": "CLUT index of the 16x16 bracket sprite; id < 0x70 only"},
            "bracket_icon": {"c_name": "STD_BRACKET_PROJECTILE_ICONS[id]", "c_type": "uint8_t",
                             "meaning": "projectile icon index on the bracket; id < 0x70 only"},
            "arena_stand_in": {"derived": "STD_tournamentMain (std_setup.c:530-540)",
                               "meaning": "Digimon that fights instead in tournaments (0x3f -> 0x30, 0x40 -> 0x36, 0x41 -> 0x2a); absent = self",
                               "ref": "digimon/digimon_data"},
            "no_technique_list": {"meaning": "all 16 slots are 0 (NPCs and unused ids): `moves` is empty"},
            "padding": {"c_name": "padding", "c_type": "uint8_t", "meaning": "0 everywhere"},
            "c": {"meaning": "the record as the C initializer gives it (name = the string id)"},
            "release_values": {"meaning": "C fields that differ in another release: {release: {field: value}}"},
            "_struct": {"c_type": "DigimonPara", "fields": describe_type(struct)},
        },
        "records": digimon,
        "used_by": tables.used_by(decomp, refs["DIGIMON_DATA"], DIGIMON_FIELDS, data),
        "godot": {"status": status, "access": "GameData.digimon(id)",
                  "notes": "Keep 180 records and their ids: maps, scripts and the asset files use them. Technique "
                           "slots are addressed by animation id (0x2e + slot) at runtime."},
    }, symbols=["DIGIMON_DATA"])

    # -- raise_data / sleep_patterns ----------------------------------------------------------
    patterns = []
    for i, p in enumerate(sleep[REFERENCE].value):
        patterns.append({"id": i, "line": (sleep[REFERENCE].element_lines or [None] * 8)[i],
                         "sleepy_hour": p["sleepyHour"], "sleepy_minute": p["sleepyMinute"],
                         "wakeup_hour": p["wakeupHour"], "wakeup_minute": p["wakeupMinute"],
                         "awake_hours": p["awakeHours"], "sleepy_hours": p["sleepyHours"], "c": p})
    raise_rows = []
    rbad = defaultdict(list)
    for i, r in enumerate(raise_[REFERENCE].value):
        hours = [h for h in r["hungerTimes"] if h != -1]
        tail = r["hungerTimes"][len(hours):]
        if any(h != -1 for h in tail) or any(not 0 <= h < 24 for h in hours) or hours != sorted(hours):
            _bad(rbad, "hunger hours are ascending hours, then -1", f"{i}: {r['hungerTimes']}")
        if r["sleepCycle"] >= len(patterns):
            _bad(rbad, "sleep cycle is a SLEEP_PATTERN index", f"{i}: {r['sleepCycle']}")
        if r["favoriteFood"] >= NUM_ITEMS:
            _bad(rbad, "favourite food is an item id", f"{i}: {r['favoriteFood']}")
        p = patterns[r["sleepCycle"]] if r["sleepCycle"] < len(patterns) else None
        raise_rows.append({
            "id": i, "name": digimon[i]["name"]["text"]["en_us"] if digimon[i]["name"] else None,
            "line": (raise_[REFERENCE].element_lines or [None] * NUM_PARTNER)[i],
            "hunger_hours": hours, "energy_cap": r["energyCap"], "energy_threshold": r["energyThreshold"],
            "energy_usage": r["energyUsage"], "poop_timer": r["poopTimer"], "unk2": r["unk2"],
            "poop_size": r["poopSize"], "favorite_food": item_ref(r["favoriteFood"]),
            "sleep_cycle": {"id": r["sleepCycle"], "summary": _pattern_summary(p["c"]) if p else None},
            "favored_region": r["favoredRegion"], "training_type": r["trainingType"],
            "default_weight": r["defaultWeight"], "view": {"x": r["viewX"], "y": r["viewY"], "z": r["viewZ"]},
            "c": r})
    for check in ("hunger hours are ascending hours, then -1", "sleep cycle is a SLEEP_PATTERN index",
                  "favourite food is an item id"):
        out.check(f"RAISE_DATA: {check}", not rbad[check], "; ".join(rbad[check][:10]) or f"{len(raise_rows)} records")

    # -- care properties (literal ids of partner_impl.c) --------------------------------------
    partner_c = _collapsed((decomp.root / PARTNER_C).read_text(encoding="utf-8", errors="replace"))
    rules = [needle for *_, needle in FIRST_TECHNIQUE] + [POOP_EATERS[1], NO_VIRUS_BAR[1]]
    missing = [needle for needle in rules if _collapsed(needle) not in partner_c]
    out.check("the care rules on literal Digimon ids are still in partner_impl.c", not missing,
              "; ".join(missing) or f"{len(rules)} rules")
    tamer_c = _collapsed((decomp.root / TAMER_C).read_text(encoding="utf-8", errors="replace"))
    out.check("the praise's low-pat rule is still in tamer.c", _collapsed(PRAISE_PAT_LOW[2]) in tamer_c,
              PRAISE_PAT_LOW[2])
    first = {}
    for type_id, anim, move, _ in FIRST_TECHNIQUE:
        slot = anim - MOVE_ANIM_BASE
        first[type_id] = {"slot": slot, "anim": anim, "move": move_ref(move)}
    wrong = [f"{t}: slot {f['slot']} holds {data[REFERENCE].value[t]['moves'][f['slot']]}, learns {f['move']['id']}"
             for t, f in first.items() if data[REFERENCE].value[t]["moves"][f["slot"]] != f["move"]["id"]]
    out.check("the starters' equipped slot holds the technique they learn", not wrong,
              "; ".join(wrong) or ", ".join(f"{t}: slot {f['slot']} = {f['move']['name']}" for t, f in first.items()))
    for r in raise_rows:
        r["first_technique"] = first.get(r["id"])
        r["eats_poop"] = r["id"] in POOP_EATERS[0]
        r["raises_virus_bar"] = r["id"] not in NO_VIRUS_BAR[0]
        r["praise_pat_low"] = (data[REFERENCE].value[r["id"]]["level"] < PRAISE_PAT_LOW[1]
                               or r["id"] in PRAISE_PAT_LOW[0])

    raise_struct = index.program(PARTNER_C, REFERENCE).structs["RaiseData"]
    out.write_table("raise_data", {
        "table": {"name": "digimon/raise_data", "purpose": TABLE_PURPOSES["raise_data"]},
        "source": tables.source(decomp, raise_, sources, {"struct": f"include/dw/partner.h:{raise_struct.line}"}),
        "schema": {
            "id": {"meaning": "Digimon id (0-65)", "ref": "digimon/digimon_data"},
            "name": {"meaning": "Digimon name (en_us), for reading"},
            "hunger_hours": {"c_name": "hungerTimes", "c_type": "int8_t[8]", "unit": "hour of day",
                             "meaning": "hours the partner gets hungry (Rookie and up; Fresh every 2 h, In-Training "
                                        "every 3 h, setFoodTimer); -1 padding left out (kept in `c`)"},
            "energy_cap": {"c_name": "energyCap", "c_type": "uint8_t", "meaning": "maximum energy (food fills up to it)"},
            "energy_threshold": {"c_name": "energyThreshold", "c_type": "uint8_t",
                                 "meaning": "energy at start; at or above it the partner counts as full; below it "
                                            "when a hunger call ends unfed = care mistake"},
            "energy_usage": {"c_name": "energyUsage", "c_type": "uint8_t",
                             "meaning": "energy lost every 1200 frames (and per training session)"},
            "poop_timer": {"c_name": "poopTimer", "c_type": "int16_t",
                           "meaning": "start value of PARTNER_PARA.poopLevel (US doubles it after a toilet / wild poop)"},
            "unk2": {"c_name": "unk2", "c_type": "int16_t", "meaning": "not read by any code"},
            "poop_size": {"c_name": "poopSize", "c_type": "uint8_t",
                          "meaning": "size of the poop pile left on the map; weight lost = (size + 0..3) / 4"},
            "favorite_food": {"c_name": "favoriteFood", "c_type": "uint8_t", "ref": "text/main/item ITEM_NAMES",
                              "meaning": "item id: ×1.4 energy and +2 happiness when eaten"},
            "sleep_cycle": {"c_name": "sleepCycle", "c_type": "uint8_t", "ref": "digimon/sleep_patterns",
                            "meaning": "SLEEP_PATTERN index (Rookie and up use its times; Fresh / In-Training only "
                                       "its hours asleep)"},
            "favored_region": {"c_name": "favoredRegion", "c_type": "uint8_t",
                               "meaning": "region id matched against the map's liked / disliked region bytes "
                                          "(map.c:4188); liked: sleep recovery x1.2, disliked: x0.8 "
                                          "(partner_impl.c:1354)"},
            "training_type": {"c_name": "trainingType", "c_type": "uint8_t",
                              "meaning": "0-4: gain factor per gym stat (×0.8 / 0.9 / 1.0 / 1.1, trn_reward.c:603)"},
            "default_weight": {"c_name": "defaultWeight", "c_type": "uint8_t", "unit": "g (as shown)",
                               "meaning": "weight after evolving / at start"},
            "view": {"c_name": "viewX, viewY, viewZ", "c_type": "int16_t",
                     "meaning": "model position in the Digimon menu view (game_menu.c:3989)"},
            "first_technique": {"derived": "initializePartner (partner_impl.c:499-506): `type == 3` / `type == 0x11`",
                                "meaning": "a new partner of this kind starts with technique slot `slot` equipped "
                                           "(battle animation `anim` = 0x2e + slot) and the technique `move` learned; "
                                           "null = none (../specs/care.md §2.15)"},
            "eats_poop": {"derived": "tickPoopDetection (partner_impl.c:1697): type 0xb or 0x27",
                          "meaning": "walks to a poop pile near the tamer and eats it"},
            "raises_virus_bar": {"derived": "createPoopPile (partner_impl.c:1319): type != 0x27",
                                 "meaning": "each poop pile adds 1 to the virus bar (16 = Sukamon)"},
            "praise_pat_low": {"derived": "tamerTickPraiseScold (tamer.c:1625): level < 4 (Champion) or type 0xd, "
                                          "0x1b, 0x38",
                               "meaning": "the tamer praises it with the low pat (animation 0x26), else the high one "
                                          "(0x27) (../specs/game_menu.md §2.5)"},
            "c": {"meaning": "the record as the C initializer gives it"},
            "_struct": {"c_type": "RaiseData", "fields": describe_type(raise_struct)},
        },
        "records": raise_rows,
        "release_values": {i: d for i in range(NUM_PARTNER) if (d := tables.diffs(raise_, lambda l, i=i: l.value[i]))},
        "used_by": tables.used_by(decomp, refs["RAISE_DATA"], RAISE_FIELDS, raise_),
        "godot": {"status": status, "access": "GameData.raise_data(id)",
                  "notes": "Only ids 0-65. Care logic (partner_impl.c) is ported with the partner system."},
    }, symbols=["RAISE_DATA"])

    sleep_struct = index.program(PARTNER_C, REFERENCE).structs["SleepPattern"]
    out.write_table("sleep_patterns", {
        "table": {"name": "digimon/sleep_patterns", "purpose": TABLE_PURPOSES["sleep_patterns"]},
        "source": tables.source(decomp, sleep, sources, {"struct": f"{PARTNER_C}:{sleep_struct.line}"}),
        "schema": {"id": {"meaning": "index used by raise_data.sleep_cycle"},
                   "sleepy_hour": {"c_name": "sleepyHour"}, "sleepy_minute": {"c_name": "sleepyMinute"},
                   "wakeup_hour": {"c_name": "wakeupHour"}, "wakeup_minute": {"c_name": "wakeupMinute"},
                   "awake_hours": {"c_name": "awakeHours", "meaning": "hoursAwakeDefault"},
                   "sleepy_hours": {"c_name": "sleepyHours", "meaning": "hoursAsleepDefault"},
                   "_struct": {"c_type": "SleepPattern", "fields": describe_type(sleep_struct)}},
        "records": patterns,
        "release_values": tables.diffs(sleep, lambda l: l.value),
        "used_by": tables.used_by(decomp, refs["SLEEP_PATTERN"], SLEEP_FIELDS, sleep),
        "godot": {"status": status, "access": "GameData.sleep_pattern(id)",
                  "notes": "Ids 6 and 7 (zero times) are used by the Fresh / In-Training partners (setSleepTimes)."},
    }, symbols=["SLEEP_PATTERN"])

    # -- item_take_distance -------------------------------------------------------------------
    take_rows = [{"index": i, "digimon": {"id": i + 1, "name": digimon[i + 1]["name"]["text"]["en_us"]
                                          if i + 1 < len(digimon) and digimon[i + 1]["name"] else None},
                  "distance": v} for i, v in enumerate(take[REFERENCE].value)]
    out.write_table("item_take_distance", {
        "table": {"name": "digimon/item_take_distance", "purpose": TABLE_PURPOSES["item_take_distance"]},
        "source": tables.source(decomp, take, sources),
        "schema": {"index": {"meaning": "C index = Digimon id - 1 (partner.c:434 reads [type - 1])"},
                   "digimon": {"meaning": "the Digimon the entry applies to", "ref": "digimon/digimon_data"},
                   "distance": {"c_type": "int8_t", "meaning": "distance passed to the partner's reach test when "
                                                              "an item is given (partner.c:434-456)"}},
        "records": take_rows,
        "release_values": tables.diffs(take, lambda l: l.value),
        "used_by": tables.used_by(decomp, refs["ITEM_TAKE_DISTANCE"], [], take),
        "godot": {"status": status, "access": "GameData.item_take_distance(digimon_id)",
                  "notes": "Indexed by id - 1; the last entry (Digimon 66) is never read by a partner (ids 1-65)."},
    }, symbols=["ITEM_TAKE_DISTANCE"])

    # -- file_names ---------------------------------------------------------------------------
    file_rows, fbad = [], []
    for i, sym in enumerate(files[REFERENCE].value):
        name = None
        try:
            got = index.table(MODEL_C, sym)
            name = got[REFERENCE] and got[REFERENCE].value
        except Exception as e:   # noqa: BLE001 - reported by the check below
            fbad.append(f"{i}: {sym}: {e}")
        if not isinstance(name, str):
            fbad.append(f"{i}: {sym} is not a string")
            name = None
        file_rows.append({"id": i, "name": digimon[i]["name"]["text"]["en_us"] if digimon[i]["name"] else None,
                          "symbol": sym, "file_name": name,
                          **{k: fmt.format(folder=i // MODELS_PER_FOLDER, name=name)
                             for k, fmt in MODEL_DIRS.items() if name}})
    out.check("every PTR_DIGIMON_FILE_NAMES entry points to a file name string", not fbad, "; ".join(fbad[:10]) or
              f"{len(file_rows)} names")
    model_c = (decomp.root / MODEL_C).read_text(encoding="utf-8", errors="replace")
    out.check("the model loaders pick the folder as id / 30 (model.c path[9])",
              all(e in model_c for e in FOLDER_EVIDENCE), " / ".join(FOLDER_EVIDENCE))
    out.write_table("file_names", {
        "table": {"name": "digimon/file_names", "purpose": TABLE_PURPOSES["file_names"]},
        "source": tables.source(decomp, files, sources, {"strings": f"{MODEL_C} STR_DIGIMON_FILE_NAME_*"}),
        "schema": {"id": {"meaning": "Digimon id", "ref": "digimon/digimon_data"},
                   "symbol": {"meaning": "C string the pointer refers to"},
                   "file_name": {"meaning": "file name stem used to build the model / texture paths (model.c:3405)"},
                   "mmd": {"meaning": "model + animation file CHDAT\\MMD<id / 30>\\<name>.MMD (the loaders patch the "
                                      "folder digit of \"CHDAT\\MMD0\\\", model.c:3409); the asset porter's "
                                      "mmd_files/MMD<n>/<name>.gltf"},
                   "tmd": {"meaning": "model-only file CHDAT\\TMD<id / 30>\\<name>.TMD (model.c:3682); not on the "
                                      "US disc"}},
        "records": file_rows,
        "used_by": tables.used_by(decomp, refs["PTR_DIGIMON_FILE_NAMES"], [], files),
        "godot": {"status": status, "access": "GameData.digimon_file(id) -> asset_porter output name",
                  "notes": "Links the data to the asset porter's Digimon models."},
    }, symbols=["PTR_DIGIMON_FILE_NAMES"])

    # -- sound_ids ----------------------------------------------------------------------------
    vb, vl = vball[REFERENCE].value, vlall[REFERENCE].value
    sound_rows = [{"id": i, "name": digimon[i]["name"]["text"]["en_us"] if digimon[i]["name"] else None,
                   "vball": vb[i], "vlall": vl[i] if 0 < i < NUM_PARTNER else None} for i in range(len(vb))]
    out.write_table("sound_ids", {
        "table": {"name": "digimon/sound_ids", "purpose": TABLE_PURPOSES["sound_ids"]},
        "source": tables.source(decomp, vball, sources, {"also": "DIGIMON_VLALL_SOUND_ID " +
                                                         f"{SOUND_C}:{vlall[REFERENCE].decl.line}"}),
        "schema": {"id": {"meaning": "Digimon id", "ref": "digimon/digimon_data"},
                   "vball": {"c_name": "DIGIMON_VBALL_SOUND_ID[id]", "c_type": "uint8_t",
                             "meaning": "bank in VBALL (7 sectors each, read at sector vball * 7; sound.c:702)"},
                   "vlall": {"c_name": "DIGIMON_VLALL_SOUND_ID[id]", "c_type": "uint8_t",
                             "meaning": "partner voice bank in VLALL (15 sectors each; sound.c:681); only ids 1-65 "
                                        "read it, others use bank 15; null here when not read"}},
        "records": sound_rows,
        "raw": {"DIGIMON_VLALL_SOUND_ID": vl},
        "release_values": {"vball": tables.diffs(vball, lambda l: l.value),
                           "vlall": tables.diffs(vlall, lambda l: l.value)},
        "used_by": tables.used_by(decomp, refs["DIGIMON_VBALL_SOUND_ID"] + refs["DIGIMON_VLALL_SOUND_ID"], [], vball),
        "godot": {"status": status, "access": "GameData.digimon_sounds(id)",
                  "notes": "Bank numbers index the asset porter's VBALL / VLALL sound banks."},
    }, symbols=["DIGIMON_VBALL_SOUND_ID", "DIGIMON_VLALL_SOUND_ID"])

    # -- training_animations ------------------------------------------------------------------
    strike_rows, sbad = [], []
    for i, (anim, hit) in enumerate(strikes[REFERENCE].value):
        if i and not (MOVE_ANIM_BASE <= anim < MOVE_ANIM_BASE + 16 and hit > 0):
            sbad.append(f"{i}: {anim}, {hit}")
        strike_rows.append({"id": i, "digimon": {"id": i, "key": digimon[i].get("key"),
                                                 "name": digimon[i]["name"]["text"]["en_us"]
                                                 if digimon[i]["name"] else None},
                            "strike_anim": anim, "hit_frame": hit, "c": [anim, hit]})
    out.check(f"TRN_TRAINING_ANIM_IDS has {NUM_TRAINING_ANIMS} entries",
              len(strike_rows) == NUM_TRAINING_ANIMS, str(len(strike_rows)))
    out.check("TRN_TRAINING_ANIM_IDS: the strikes are technique animations (0x2e-0x3d) with a hit frame > 0 "
              "(entry 0, the tamer, is 0, 0)", not sbad, "; ".join(sbad[:10]) or f"{len(strike_rows)} records")
    out.write_table("training_animations", {
        "table": {"name": "digimon/training_animations", "purpose": TABLE_PURPOSES["training_animations"]},
        "source": tables.source(decomp, strikes, sources, binary="trn"),
        "schema": {"id": {"meaning": "C index = the partner's Digimon id"},
                   "digimon": {"meaning": "the Digimon the entry applies to", "ref": "digimon/digimon_data"},
                   "strike_anim": {"c_name": "[0]", "c_type": "int8_t",
                                   "meaning": "animation started for each strike (one of its technique animations, "
                                              "0x2e + slot; trn_off.c:121, :151)"},
                   "hit_frame": {"c_name": "[1]", "c_type": "int8_t",
                                 "meaning": "frames from the strike's start to the hit: sparks, sound and the "
                                            "target's shake (trn_off.c:136, :210)"},
                   "c": {"meaning": "the C pair"}},
        "records": strike_rows,
        "release_values": tables.diffs(strikes, lambda l: l.value),
        "used_by": tables.used_by(decomp, refs["TRN_TRAINING_ANIM_IDS"], [], strikes),
        "godot": {"status": status, "access": "GameData.training_animation(digimon)",
                  "notes": "Only the Offense stations read it. A Digimon without a record strikes with 0x2e and "
                           "hits at frame 10 (the table's most common values)."},
    }, symbols=["TRN_TRAINING_ANIM_IDS"])

    # -- condition_fx_offsets, aura_projectile_types (indexed by the original type) ---------------
    by_original = defaultdict(list)
    for d in digimon:
        if d.get("original_type", -1) >= 0:
            by_original[d["original_type"]].append(d["id"])
    if condition_fx and auras:
        sources += [SourceText(decomp.root, BTL_EFFECT_C).identity()]
        tables.size_check(out, decomp, condition_fx)
        tables.size_check(out, decomp, auras, binary="btl")
        refs2 = decomp.references(["CONDITION_FX_OFFSETS", "BTL_AURA_PROJECTILE_TYPES"])
        fx_rows = [{"id": i, "digimon": by_original.get(i, []),
                    "offset": {"x": v["vx"], "y": v["vy"], "z": v["vz"]}, "bone": v["pad"], "c": v}
                   for i, v in enumerate(condition_fx[REFERENCE].value)]
        out.check(f"CONDITION_FX_OFFSETS has {NUM_CONDITION_FX} entries", len(fx_rows) == NUM_CONDITION_FX,
                  str(len(fx_rows)))
        bad_bone = [f"{r['id']}: {r['bone']}" for r in fx_rows if not 0 <= r["bone"] < 32]
        out.check("CONDITION_FX_OFFSETS: the bones (pad) are bone indices 0-31", not bad_bone,
                  "; ".join(bad_bone[:10]) or f"{len(fx_rows)} records")
        out.write_table("condition_fx_offsets", {
            "table": {"name": "digimon/condition_fx_offsets", "purpose": TABLE_PURPOSES["condition_fx_offsets"]},
            "source": tables.source(decomp, condition_fx, sources),
            "schema": {"id": {"meaning": "C index = getOriginalType(type) (digimon_data.original_type)"},
                       "digimon": {"meaning": "the Digimon whose original type this is (ids)",
                                   "ref": "digimon/digimon_data"},
                       "offset": {"c_name": "vx, vy, vz", "c_type": "int16_t", "unit": "PSX units, bone space",
                                  "meaning": "the point in the bone's space (ApplyMatrixSV with its world matrix)"},
                       "bone": {"c_name": "pad", "c_type": "int16_t",
                                "meaning": "the bone whose world matrix places it (posData[pad].posMatrix.workm)"},
                       "c": {"meaning": "the C SVECTOR"}},
            "records": fx_rows,
            "release_values": tables.diffs(condition_fx, lambda l: l.value),
            "used_by": tables.used_by(decomp, refs2["CONDITION_FX_OFFSETS"], [], condition_fx),
            "godot": {"status": status, "access": "GameData.condition_fx_offset(digimon)",
                      "notes": "translateConditionFXToEntity: bone matrix · offset + the bone's translation. The "
                               "battle's poison bubbles and confusion (specs/battle_effects.md) read it."},
        }, symbols=["CONDITION_FX_OFFSETS"])
        aura_rows = [{"id": i, "digimon": by_original.get(i, []), "type": v["type"], "u": v["u"],
                      "unk2": v["unk2"], "unk4": v["unk4"], "unk6": v["unk6"], "unk8": v["unk8"], "c": v}
                     for i, v in enumerate(auras[REFERENCE].value)]
        out.check(f"BTL_AURA_PROJECTILE_TYPES has {NUM_AURA_TYPES} entries", len(aura_rows) == NUM_AURA_TYPES,
                  str(len(aura_rows)))
        bad_type = [str(r["id"]) for r in aura_rows[:-1] if r["type"] != r["id"]]
        out.check("BTL_AURA_PROJECTILE_TYPES: entry i is type i (the last is the -1 end mark)",
                  not bad_type and aura_rows[-1]["type"] == -1, ", ".join(bad_type[:10]) or "ok")
        out.write_table("aura_projectile_types", {
            "table": {"name": "digimon/aura_projectile_types", "purpose": TABLE_PURPOSES["aura_projectile_types"]},
            "source": tables.source(decomp, auras, sources, binary="btl"),
            "schema": {"id": {"meaning": "C index = getOriginalType(type) (digimon_data.original_type)"},
                       "digimon": {"meaning": "the Digimon whose original type this is (ids)",
                                   "ref": "digimon/digimon_data"},
                       "type": {"c_type": "int16_t", "meaning": "the original type again (-1: the end mark)"},
                       "u": {"c_type": "int16_t",
                             "meaning": "the sprite's u - 0x60 on the DEFEFF page (setUVWH(u + 0x60, 0xa0, 7, 7)); "
                                        "-1 gives u 0x5f"},
                       "unk2": {"c_type": "int16_t", "meaning": "not read"},
                       "unk4": {"c_type": "int16_t", "meaning": "not read"},
                       "unk6": {"c_type": "int16_t", "meaning": "not read"},
                       "unk8": {"c_type": "int16_t", "meaning": "not read"},
                       "c": {"meaning": "the C struct (EfeAuraType, include/dw/efe.h)"}},
            "records": aura_rows,
            "release_values": tables.diffs(auras, lambda l: l.value),
            "used_by": tables.used_by(decomp, refs2["BTL_AURA_PROJECTILE_TYPES"], ["u"], auras),
            "godot": {"status": status, "access": "GameData.aura_projectile_type(digimon)",
                      "notes": "Only `u` is read (the sprite drawn). A Digimon of original type past the table "
                               "would read past it in the C; the port gives {}."},
        }, symbols=["BTL_AURA_PROJECTILE_TYPES"])

    out.write_report("report.md", _report(digimon, raise_rows, patterns))
    out.finish(sources, extra={"counts": {"digimon": len(digimon), "partners": len(raise_rows),
                                          "levels": {name: sum(1 for d in digimon if d["level"]["id"] == k)
                                                     for k, name in LEVELS.items()},
                                          "no_technique_list": sum(1 for d in digimon if d.get("no_technique_list"))},
                               "release_differences": {d["id"]: d["release_values"] for d in digimon
                                                       if "release_values" in d}})
    return out
