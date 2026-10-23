"""Systems group: the remaining game-rule tables, each used by one system.

Follows specs/systems.md. Areas: battle (AI, commands, flee, stat gains, music), arena
(tournaments, schedule, win chances, medals), world (maps, toilets, Birdramon transport,
training spots), minigames and misc (fishing, Mojyamon trades, babies, jukebox, versus mode).
Rendering, effect and UI-layout tables are left out (asset / UI work).
"""

from collections import defaultdict

from .. import tables
from ..cdata import CError, CIndex, Value, describe_type
from ..decomp import Decomp
from ..output import GroupWriter
from ..source import SourceText
from ..tables import REFERENCE, enum
from . import text as text_group

NAME = "systems"
SPEC = "specs/systems.md"
PURPOSE = "Battle AI / commands / flee / stat gains, tournaments, maps, transport, training spots, fishing, trades, misc"
SOURCE_GLOB = "src/**/*.c (see specs/systems.md)"

BTL_MAIN, BTL_SETUP, BTL_C, BATTLE_UI = ("src/btl/battle_main.c", "src/btl/battle_setup.c", "src/main/btl.c",
                                         "src/main/battle_ui.c")
STD_MAIN, STD_SETUP, VS_MAIN, VS_SELECT, VS_DEMO, VS_INTRO = (
    "src/std/std_main.c", "src/std/std_setup.c", "src/vs/vs_main.c", "src/vs/vs_select.c", "src/vs/vs_demo.c",
    "src/vs/vs_intro.c")
SCRIPT_C, TOURNAMENT_C, GAME_MENU = "src/main/script_common.c", "src/main/tournament.c", "src/main/game_menu.c"
MAP_C, TOILET_C, TRN_HUD, TRN2_HUD = "src/main/map.c", "src/main/toilet_data.c", "src/trn/trn_hud.c", "src/trn2/trn2_hud.c"
FISH_C, SHOP_MENU, DOOA_C = "src/fish/fish.c", "src/shop/script_menu.c", "src/dooa/dooa.c"
MAIN_C = "src/main/main.c"

STYLES = {0: "attack as soon as charged", 1: "wait for the technique's power", 2: "wait for a full charge, keep away"}
TYPES = {1: "data", 2: "vaccine", 3: "virus"}
STATS = ["hp", "mp", "offense", "defense", "speed", "brain"]
TRAINING_STATS = {0: "hp", 1: "mp", 2: "offense", 3: "defense", 4: "speed", 5: "brain"}
MAP_FLAG_SOUND, MAP_FLAG_NO_TIME, MAP_FLAG_DIGIMON = 0x1F, 0x40, 0x80   # map.c:4214, :3968; overworld.c:1036
ENEMY_MUSIC_FIRST, ENEMY_MUSIC_END = 0x43, 0x70                         # btl.c:366
BRAIN_ALL_COMMANDS = 500                                                # battle_setup.c:125
SCHEDULE_DAYS, SCHEDULE_SLOTS = 30, 6                                   # dget.c:112
FISH_DEPTH_FIRST, FISH_DEPTH_END, FISH_KINDS_ROW = 0x26, 0x47, 6        # fish.c:3080-3084
TRADE_SET = 3                                                           # script_menu.c:1765 (PSTAT_249 * 3)
# Copies of the battle tables in the std (arena) and vs (versus) overlays: must match the btl ones.
COPIES = [
    (BTL_MAIN, "BTL_YOUR_CALL_POWER_PRIO", STD_MAIN, "STD_YOUR_CALL_POWER_PRIO"),
    (BTL_MAIN, "BTL_YOUR_CALL_MP_PRIO", STD_MAIN, "STD_YOUR_CALL_MP_PRIO"),
    (BTL_MAIN, "BTL_YOUR_CALL_WIDE_PRIO", STD_MAIN, "STD_YOUR_CALL_WIDE_PRIO"),
    (BTL_MAIN, "BTL_YOUR_CALL_POWER_PRIO", VS_MAIN, "VS_YOUR_CALL_POWER_PRIO"),
    (BTL_MAIN, "BTL_YOUR_CALL_MP_PRIO", VS_MAIN, "VS_YOUR_CALL_MP_PRIO"),
    (BTL_MAIN, "BTL_YOUR_CALL_WIDE_PRIO", VS_MAIN, "VS_YOUR_CALL_WIDE_PRIO"),
    (TRN_HUD, "TRN_TRAINING_SPOTS", TRN2_HUD, "TRN2_TRAINING_SPOTS"),
    (STD_MAIN, "STD_STAT_BAR_LIMITS", VS_SELECT, "STAT_LIMITS"),
    (STD_MAIN, "STD_STAT_BAR_LIMITS", VS_INTRO, "VS__STAT_BAR_LIMITS"),
]
EVIDENCE = [
    (BTL_SETUP, "COMBAT_DATA_PTR->player.numCommands[0] = BRAIN_TO_COMMAND_MAP[brains / 100];"),
    (BTL_SETUP, "if (brains < 0x1f4) {"),
    (BTL_SETUP, "COMBAT_DATA_PTR->player.numCommands[0] = 9;"),
    (STD_MAIN, "COMBAT_DATA_PTR->player.numCommands[0] = STD_BRAIN_TO_COMMAND_MAP[brains / 100];"),
    (STD_MAIN, "COMBAT_DATA_PTR->player.numCommands[0] = 7;"),
    (BTL_C, "&FLEE_CHANCES[(DIGIMON_DATA[PARTNER_ENTITY.digimonEntity.entity.type].type - 1) * 3]"),
    (BTL_C, "playMusic(0x21, ENEMY_MUSIC_MAPPING[ENTITY_TABLE[entityId]->type - 0x43]);"),
    (BATTLE_UI, "STAT_GAIN_ENEMY_FACTORS[ENEMY_COUNT - 1]"),
    (BTL_MAIN, "TARGET_ATTACKER_CHANCE[digimon->stats.current.chargeMode] - PARTNER_PARA.discipline"),
    ("src/dget/dget.c", "data = &TOURNAMENT_SCHEDULE[(day % 30) * 6];"),
    (STD_MAIN, "STD_WIN_CHANCES[DIGIMON_DATA[PARTICIPANT_TYPES[i * 2]].level - 3]"),
    (STD_SETUP, "base = STD_OPPONENT_BASE_STATS[tier];"),
    ("src/main/partner.c", "toiletId = MAP_ENTRIES[CURRENT_SCREEN].toiletId - 1;"),
    (MAP_C, "return MAP_ENTRIES[mapId].flags & 0x1f;"),
    (MAP_C, "skipTimeOfDay = MAP_ENTRIES[CURRENT_SCREEN].flags & 0x40;"),
    ("src/main/overworld.c", "if (MAP_ENTRIES[mapId].flags & 0x80) {"),
    (FISH_C, "if (FISHING_DATA_PTR->rod.bait != FISH_KIND_INFO[f->kind].bait) {"),
    (SHOP_MENU, "ITEM_MENU_TYPE = readPStat(PSTAT_249) * 3;"),
]

TABLE_PURPOSES = {
    "battle_ai": "Partner battle AI: chance to retarget its attacker, move priorities of the 'Your call' command",
    "battle_commands": "Number of battle commands the partner understands, by brain",
    "flee_chances": "Chance an enemy joins a battle, by the partner's and the enemy's type",
    "stat_gain_factors": "Stat gain factor after a won battle, by number of enemies",
    "enemy_music": "Battle music for enemies 0x43-0x6f",
    "tournaments": "Arena tournaments: name, grade, grade image, opponent base stat, days held",
    "tournament_schedule": "Which tournaments are held on each day of the 30-day month",
    "tournament_win_chances": "Chance one simulated participant beats another, by their levels",
    "tournament_medals": "Medal given for each tournament achievement",
    "maps": "Every map: file, images, sound bank, time-of-day / wild Digimon flags, toilet, display name",
    "toilets": "Toilet positions (walk-to point, camera point) used by maps' toiletId",
    "birdramon_transport": "Destinations of Birdramon's transport: map, unlock trigger, price",
    "training_spots": "Gym training spots: per gym map, the position of each stat's training spot",
    "fishing": "Fishing: fish kinds, bite chances by depth, items the line can snag, fishing maps",
    "mojyamon_trades": "Mojyamon's item trades: 4 sets of 3 (give -> get)",
    "babies": "Baby Digimon ids (Fresh / In-Training) and the baby each reincarnation egg gives",
    "jukebox": "Jukebox track list (index = track id)",
    "versus": "Versus mode: demo fighters, battle counts, stat bar limits",
}


def convert(input_root, output_root) -> GroupWriter:
    out = GroupWriter(output_root, NAME, SPEC, PURPOSE)
    out.reset()
    decomp = Decomp(input_root)
    if not out.check("decomp found", decomp.exists(), str(decomp.root)):
        out.finish([])
        return out
    index = CIndex(decomp)
    files = sorted({BTL_MAIN, BTL_SETUP, BTL_C, BATTLE_UI, STD_MAIN, STD_SETUP, VS_MAIN, VS_SELECT, VS_DEMO,
                    VS_INTRO, SCRIPT_C, TOURNAMENT_C, GAME_MENU, MAP_C, TOILET_C, TRN_HUD, TRN2_HUD, FISH_C,
                    SHOP_MENU, DOOA_C})
    sources = [SourceText(decomp.root, p).identity() for p in files]

    missing = [f"{p}: {needle}" for p, needle in EVIDENCE
               if needle not in (decomp.root / p).read_text(encoding="utf-8", errors="replace")]
    out.check("the code still uses the tables the way the spec documents", not missing,
              "; ".join(missing) or f"{len(EVIDENCE)} uses")

    L = {}

    def load(c_file, name, hooks=None):
        L[name] = tables.load(out, index, c_file, name, hooks)
        return L[name]

    for c_file, name in [
            (BTL_MAIN, "TARGET_ATTACKER_CHANCE"), (BTL_MAIN, "BTL_YOUR_CALL_POWER_PRIO"),
            (BTL_MAIN, "BTL_YOUR_CALL_MP_PRIO"), (BTL_MAIN, "BTL_YOUR_CALL_WIDE_PRIO"),
            (BTL_SETUP, "BRAIN_TO_COMMAND_MAP"), (STD_MAIN, "STD_BRAIN_TO_COMMAND_MAP"), (BTL_C, "FLEE_CHANCES"), (BATTLE_UI, "STAT_GAIN_ENEMY_FACTORS"),
            (BTL_C, "ENEMY_MUSIC_MAPPING"), (SCRIPT_C, "TOURNAMENT_NAMES"), (SCRIPT_C, "TOURNAMENT_GRADES"),
            (SCRIPT_C, "TOURNAMENT_SCHEDULE"), (SCRIPT_C, "ARENA_MAPS"), (STD_SETUP, "STD_GRADES"),
            (STD_SETUP, "STD_OPPONENT_BASE_STATS"), (STD_MAIN, "STD_WIN_CHANCES"), (STD_MAIN, "STD_STAT_BAR_LIMITS"),
            (TOURNAMENT_C, "TOURNAMENT_MEDAL_IDS"), (GAME_MENU, "MEDAL_NAMES"), (MAP_C, "MAP_ENTRIES"),
            (MAP_C, "MAP_NAME_PTR"), (TOILET_C, "TOILET_DATA"), (SCRIPT_C, "BIRDRA_TRANSPORT_TARGETS"),
            (TRN_HUD, "TRN_TRAINING_SPOTS"), (FISH_C, "FISH_KIND_INFO"), (FISH_C, "FISH_BITE_CHANCE"),
            (FISH_C, "FISH_BAIT_CHANCES"), (FISH_C, "FISHING_MAP_DATA"), (SHOP_MENU, "MOJYAMON_ITEMS_GIVE"),
            (SHOP_MENU, "MOJYAMON_ITEMS_GET"), (SCRIPT_C, "BABY_IDS"), (DOOA_C, "REINCARNATE_BABY_TYPE"),
            (SCRIPT_C, "BGM_TRACK_NAMES"), (VS_DEMO, "VS_DEMO_DIGIMON"), (VS_SELECT, "VS__BATTLE_COUNTS")]:
        load(c_file, name)
    digimon_l = tables.load(out, index, MAIN_C, "DIGIMON_DATA",
                            {"DIGIMON_PARA_NAME": lambda a, r, t: [] if r == "eu" else [Value(a[0], t.line)]})
    strings = text_group.string_index(decomp)
    names_model = text_group.load_file(decomp, "text/main/main.yaml")
    items_model = text_group.load_file(decomp, "text/main/item.yaml")
    dnames = text_group.block_of(names_model, "DIGIMON_NAMES")
    inames = text_group.block_of(items_model, "ITEM_NAMES")
    if not all(L.values()) or not digimon_l or not dnames or not inames:
        out.finish(sources)
        return out
    for l in L.values():
        tables.size_check(out, decomp, l)

    copy_bad = []
    for f1, n1, f2, n2 in COPIES:
        try:
            a, b = index.table(f1, n1), index.table(f2, n2)
        except CError as e:
            copy_bad.append(f"{n2}: {e}")
            continue
        for r in decomp.releases:
            va = a[r] and a[r].value
            vb = b[r] and b[r].value
            if n1 == "TRN_TRAINING_SPOTS":   # pointer names differ (TRN_D_ / TRN2_D_): compare map ids
                va = va and [x["mapId"] for x in va]
                vb = vb and [x["mapId"] for x in vb]
            if va != vb:
                copy_bad.append(f"{n2} != {n1} ({r})")
    out.check("std / vs / trn2 copies match the main tables", not copy_bad, "; ".join(copy_bad[:10]) or
              f"{len(COPIES)} copies")

    level = [d["level"] for d in digimon_l[REFERENCE].value]
    dtype = [d["type"] for d in digimon_l[REFERENCE].value]

    def dref(i):
        if i is None or not 0 <= i < len(dnames["items"]):
            return {"id": i, "name": None}
        return {"id": i, "name": (tables.text_ref(dnames["items"][i]) or {}).get("text", {}).get("en_us")}

    def iref(i):
        if i is None or not 0 <= i < len(inames["items"]):
            return {"id": i, "name": None}
        return {"id": i, "name": (tables.text_ref(inames["items"][i]) or {}).get("text", {}).get("en_us")}

    unresolved = []

    def sref(sid):
        s = strings.get(sid)
        if s is None:
            unresolved.append(sid)
        return {"string_id": sid, "text": s and s["text"], "file": s and s["file"]}

    us = {n: l[REFERENCE].value for n, l in L.items()}
    refs = decomp.references(list(L) + ["STD_YOUR_CALL_POWER_PRIO", "VS_YOUR_CALL_POWER_PRIO"])
    status = "implemented (scripts/data/game_data.gd)"
    bad = defaultdict(list)

    def write(name, symbols, schema, records, godot, extra=None, fields=None):
        main = L[symbols[0]]
        used = sum((tables.used_by(decomp, refs[s], fields or [], L[s]) for s in symbols), [])
        diffs = {s: d for s in symbols if (d := tables.diffs(L[s], lambda l: l.value))}
        table = {"table": {"name": f"systems/{name}", "purpose": TABLE_PURPOSES[name]},
                 "source": tables.source(decomp, main, sources, dict(
                     {"also": [f"{s} {L[s][REFERENCE].decl.file}:{L[s][REFERENCE].decl.line}" for s in symbols[1:]]}
                     if symbols[1:] else {}, **(extra or {}))),
                 "schema": schema, "records": records, "used_by": used, "godot": dict(status=status, **godot)}
        if diffs:
            table["release_values"] = diffs
        out.write_table(name, table, symbols=symbols)

    # -- battle -------------------------------------------------------------------------------
    write("battle_ai", ["TARGET_ATTACKER_CHANCE", "BTL_YOUR_CALL_POWER_PRIO", "BTL_YOUR_CALL_MP_PRIO",
                        "BTL_YOUR_CALL_WIDE_PRIO"], {
        "retarget_chance": {"c_name": "TARGET_ATTACKER_CHANCE[chargeMode]", "unit": "%",
                            "meaning": "the partner switches to whoever hit it if randomLimit(100) < value - "
                                       "discipline (BTL_retargetAfterHit, battle_main.c:1979); index = fighting "
                                       "style (stats.current.chargeMode)"},
        "your_call_priorities": {"c_name": "BTL_YOUR_CALL_POWER/MP/WIDE_PRIO[rank]",
                                 "meaning": "weight given to the technique ranked 0 / 1 / 2 by power (style 0), by "
                                            "MP cost (style 2) and, for area techniques, by distance "
                                            "(BTL_selectPartnerMove, battle_main.c:3456-3539)"},
    }, [{"style": k, "style_meaning": STYLES.get(k), "retarget_chance": us["TARGET_ATTACKER_CHANCE"][k]}
        for k in range(len(us["TARGET_ATTACKER_CHANCE"]))] +
        [{"rank": k, "by_power": us["BTL_YOUR_CALL_POWER_PRIO"][k], "by_mp": us["BTL_YOUR_CALL_MP_PRIO"][k],
          "wide": us["BTL_YOUR_CALL_WIDE_PRIO"][k]} for k in range(4)],
        {"access": "GameData.system('battle_ai')", "notes": "The std and vs overlays have identical copies."})

    brain_map, arena_map = us["BRAIN_TO_COMMAND_MAP"], us["STD_BRAIN_TO_COMMAND_MAP"]
    write("battle_commands", ["BRAIN_TO_COMMAND_MAP", "STD_BRAIN_TO_COMMAND_MAP"], {
        "brain": {"meaning": "partner brain range [from, to)"},
        "commands": {"meaning": "numCommands in field battles: how many commands the partner understands "
                                "(BTL_initializeCombat, battle_setup.c:124-175); from brain 500: 9, which adds the "
                                "direct technique commands"},
        "arena_commands": {"c_name": "STD_BRAIN_TO_COMMAND_MAP", "meaning": "the same in arena battles "
                           "(std_main.c:4220-4262): one fewer, the field list's command 1 is never added (no "
                           "running away); from brain 500: 7"},
    }, [{"brain": [k * 100, k * 100 + 100], "commands": v, "arena_commands": arena_map[k]}
        for k, v in enumerate(brain_map)] +
        [{"brain": [BRAIN_ALL_COMMANDS, 1000], "commands": 9, "arena_commands": 7,
          "from": "constants (battle_setup.c:128, std_main.c:4224)"}],
        {"access": "GameData.battle_commands(brain, arena)"})

    fc = us["FLEE_CHANCES"]
    if any(fc[9:]):
        bad["flee"].append(f"padding {fc[9:]}")
    write("flee_chances", ["FLEE_CHANCES"], {
        "partner_type": {"values": TYPES}, "enemy_type": {"values": TYPES},
        "chance": {"unit": "%", "meaning": "FLEE_CHANCES[(partner.type - 1) * 3 + enemy.type - 1]: an extra enemy "
                                           "joins the battle when the roll is below it (btl.c:328-330; the "
                                           "enemy repel / bell shift that roll, see specs/items.md)"},
        "padding": {"meaning": "entries 9-11, not read (0)"},
    }, [{"partner_type": enum(p, TYPES), "enemy_type": enum(e, TYPES), "chance": fc[(p - 1) * 3 + e - 1]}
        for p in (1, 2, 3) for e in (1, 2, 3)] + [{"padding": fc[9:]}],
        {"access": "GameData.flee_chance(partner_type, enemy_type)"})

    write("stat_gain_factors", ["STAT_GAIN_ENEMY_FACTORS"], {
        "enemies": {"meaning": "number of enemies (index + 1)"},
        "factor": {"meaning": "after a won battle, for each stat: best enemy stat e, partner stat p; if e >= p: "
                              "gain = ceil(e * factor / (p * 10)), else 1 point with chance e * factor * 100 / "
                              "(p * 10) % (battleStatsGainsAndDrops, battle_ui.c:126-163)"},
    }, [{"enemies": k + 1, "factor": v} for k, v in enumerate(us["STAT_GAIN_ENEMY_FACTORS"])],
        {"access": "GameData.system('stat_gain_factors')"})

    music = us["ENEMY_MUSIC_MAPPING"]
    write("enemy_music", ["ENEMY_MUSIC_MAPPING"], {
        "digimon": {"meaning": "enemy Digimon id = index + 0x43", "ref": "digimon/digimon_data"},
        "track": {"meaning": "playMusic(0x21, track): battle theme variant; other enemies use 1, special "
                             "battles 0 (loadBattleData, btl.c:360-376)"},
    }, [{"digimon": dref(ENEMY_MUSIC_FIRST + k), "track": v} for k, v in enumerate(music)],
        {"access": "GameData.enemy_music(digimon_id)"})

    # -- arena --------------------------------------------------------------------------------
    names_l, grades_l, images_l = us["TOURNAMENT_NAMES"], us["TOURNAMENT_GRADES"], us["STD_GRADES"]
    base_stats, schedule = us["STD_OPPONENT_BASE_STATS"], us["TOURNAMENT_SCHEDULE"]
    days_of = defaultdict(list)
    for day in range(SCHEDULE_DAYS):
        for t in schedule[day * SCHEDULE_SLOTS:(day + 1) * SCHEDULE_SLOTS]:
            if t == 0xFF:
                break
            days_of[t].append(day)
    image_paths = []
    for sym in images_l:
        try:
            image_paths.append(index.table(STD_SETUP, sym)[REFERENCE].value)
        except CError:
            image_paths.append(None)
            bad["grade images"].append(sym)
    tournaments = [{"id": k, "name": sref(names_l[k]), "grade": sref(grades_l[k]), "grade_image": image_paths[k],
                    "opponent_base_stat": base_stats[k] if k < len(base_stats) else None, "days": days_of.get(k, [])}
                   for k in range(len(names_l))]
    tables.keys(out, tournaments, "tournament", tables.name_base("STR_TOURNAMENT_NAME_"))
    write("tournaments", ["TOURNAMENT_NAMES", "TOURNAMENT_GRADES", "STD_GRADES", "STD_OPPONENT_BASE_STATS"], {
        "id": {"meaning": "tournament id (TOURNAMENT_NAMES index; PSTAT values in scripts)"},
        "key": tables.KEY_SCHEMA,
        "name": {"c_name": "TOURNAMENT_NAMES[id]", "ref": "text/main/script_common"},
        "grade": {"c_name": "TOURNAMENT_GRADES[id]", "meaning": "short grade label of the schedule board"},
        "grade_image": {"c_name": "STD_GRADES[id]", "meaning": "TIM drawn by the arena overlay"},
        "opponent_base_stat": {"c_name": "STD_OPPONENT_BASE_STATS[id]",
                               "meaning": "base b of the opponents' stats: Off/Def/Speed/Brain = b ± 30 %, HP/MP = "
                                          "10 b ± 30 %, x1 (Rookie), x2 (Champion), x2.5 (Ultimate), capped "
                                          "(STD_initializeOpponent, std_setup.c:292-345)"},
        "days": {"meaning": "days of the month (0-29) it is held (TOURNAMENT_SCHEDULE)"},
    }, tournaments,
        {"access": "GameData.tournament(id)"},
        extra={"unused": {"STD_OPPONENT_BASE_STATS": base_stats[len(names_l):]}})

    write("tournament_schedule", ["TOURNAMENT_SCHEDULE"], {
        "day": {"meaning": "day of the month: DAY % 30 (fillEnabledTournamentTable, dget/dget.c:110-122)"},
        "tournaments": {"meaning": "up to 6 tournament ids, 0xff ends the list; isTournamentEnabled filters them"},
    }, [{"day": d, "tournaments": [t for t in schedule[d * SCHEDULE_SLOTS:(d + 1) * SCHEDULE_SLOTS] if t != 0xFF],
         "c": schedule[d * SCHEDULE_SLOTS:(d + 1) * SCHEDULE_SLOTS]} for d in range(SCHEDULE_DAYS)],
        {"access": "GameData.tournaments_on_day(day)"})

    wins = us["STD_WIN_CHANCES"]
    write("tournament_win_chances", ["STD_WIN_CHANCES"], {
        "level_a": {"meaning": "level of participant A (row index + 3)"},
        "level_b": {"meaning": "level of participant B (column + 3)"},
        "chance": {"unit": "%", "meaning": "A wins a simulated match (STD_setupParticipants, std_main.c:3487)"},
    }, [{"level_a": a + 3, "level_b": b + 3, "chance": wins[a][b]} for a in range(len(wins)) for b in range(3)],
        {"access": "GameData.tournament_win_chance(level_a, level_b)",
         "notes": "Row 3 (level 6) is all 0 and never used."})

    medal_ids, medal_names = us["TOURNAMENT_MEDAL_IDS"], us["MEDAL_NAMES"]
    conditions = ["the 6 Grade cups won", "the 5 Version cups won", "the 7 type cups (Fire ... Filth) won",
                  "the 4 special cups (Dino ...) won", "100 tournament wins", "all 66 cards and the game beaten once"]
    write("tournament_medals", ["TOURNAMENT_MEDAL_IDS", "MEDAL_NAMES"], {
        "condition": {"meaning": "result of checkTournamentMedalConditions (tournament.c:167-240): conditions are "
                                 "tested in order, the first fully met one is returned, -1 if its medal is owned"},
        "medal": {"meaning": "medal id unlocked (TOURNAMENT_MEDAL_IDS[condition]) and its name (MEDAL_NAMES)"},
    }, [{"condition": k, "meaning": conditions[k] if k < len(conditions) else None,
         "medal": {"id": m, "name": sref(medal_names[m]) if m < len(medal_names) else None}}
        for k, m in enumerate(medal_ids)],
        {"access": "GameData.system('tournament_medals')"},
        extra={"medal_names": [sref(s) for s in medal_names]})

    # -- world --------------------------------------------------------------------------------
    entries, map_names, toilets = us["MAP_ENTRIES"], us["MAP_NAME_PTR"], us["TOILET_DATA"]
    arena = set(us["ARENA_MAPS"])
    maps = []
    for k, m in enumerate(entries):
        flags = m["flags"] & 0xFF
        if m["toiletId"] and not 0 < m["toiletId"] <= len(toilets):
            bad["maps: toiletId is 0 or a TOILET_DATA index + 1"].append(f"{k}: {m['toiletId']}")
        if not 0 <= m["loadingName"] < len(map_names):
            bad["maps: loadingName is a MAP_NAME_PTR index"].append(f"{k}: {m['loadingName']}")
        maps.append({"id": k, "file": m["filename"], "images_8bpp": m["num8bppImages"],
                     "images_4bpp": m["num4bppImages"], "sound_bank": flags & MAP_FLAG_SOUND,
                     "no_time_of_day": bool(flags & MAP_FLAG_NO_TIME), "wild_digimon": bool(flags & MAP_FLAG_DIGIMON),
                     "flag_0x20": bool(flags & 0x20), "doors_id": m["doorsId"],
                     "toilet": m["toiletId"] - 1 if m["toiletId"] else None,
                     "name": sref(map_names[m["loadingName"]]) if 0 <= m["loadingName"] < len(map_names) else None,
                     "arena": k in arena, "c": m})
    for check in ("maps: toiletId is 0 or a TOILET_DATA index + 1", "maps: loadingName is a MAP_NAME_PTR index"):
        out.check(check, not bad[check], "; ".join(bad[check][:10]) or f"{len(maps)} maps")
    # Maps are keyed by file name: the area name is shared by many maps (specs/content.md §2).
    tables.keys(out, maps, "map", lambda r: r["file"].lower() if r["file"] else None)
    map_struct = index.program(MAP_C, REFERENCE).structs["MapEntry"]
    write("maps", ["MAP_ENTRIES", "MAP_NAME_PTR", "ARENA_MAPS"], {
        "id": {"meaning": "map id (CURRENT_SCREEN; MAP/MAP<id // 15 + 1>/<file>.MAP, see asset_porter specs/map.md)"},
        "key": dict(tables.KEY_SCHEMA, meaning="content key dw1:<file name> (specs/content.md §2)"),
        "file": {"c_name": "filename"}, "images_8bpp": {"c_name": "num8bppImages"},
        "images_4bpp": {"c_name": "num4bppImages"},
        "sound_bank": {"c_name": "flags & 0x1f", "meaning": "map sound bank (map.c:4214)"},
        "no_time_of_day": {"c_name": "flags & 0x40", "meaning": "no day / night cycle (map.c:3968, :4311)"},
        "wild_digimon": {"c_name": "flags & 0x80", "meaning": "map has roaming Digimon (overworld.c:1036)"},
        "flag_0x20": {"meaning": "bit 5, not read by any code found"},
        "doors_id": {"c_name": "doorsId", "meaning": "DOOR_MAPDATA[doorsId - 1] (asset porter)"},
        "toilet": {"c_name": "toiletId - 1", "ref": "systems/toilets", "meaning": "null = no toilet"},
        "name": {"c_name": "MAP_NAME_PTR[loadingName]", "meaning": "area name shown on entry / save screens"},
        "arena": {"c_name": "ARENA_MAPS", "meaning": "entering loads the tournament (dget) overlay"},
        "_struct": {"c_type": "MapEntry", "fields": describe_type(map_struct)},
    }, maps, {"access": "GameData.map(id)", "notes": "Cross-check with the asset porter's map table."})

    write("toilets", ["TOILET_DATA"], {
        "id": {"meaning": "toilet id = MAP_ENTRIES.toiletId - 1"},
        "walk_to": {"c_name": "posX1, posY1", "meaning": "x / z the partner walks to (tickPartnerToilet, partner.c:548)"},
        "camera_to": {"c_name": "posX2, posY2", "meaning": "x / z the camera moves to"},
    }, [{"id": k, "walk_to": [t["posX1"], t["posY1"]], "camera_to": [t["posX2"], t["posY2"]],
         "maps": [m["id"] for m in maps if m["toilet"] == k], "c": t} for k, t in enumerate(toilets)],
        {"access": "GameData.toilet(id)"})

    birdra = us["BIRDRA_TRANSPORT_TARGETS"]
    write("birdramon_transport", ["BIRDRA_TRANSPORT_TARGETS"], {
        "map": {"c_name": "mapId", "ref": "systems/maps"},
        "entrance": {"c_name": "unk_0x1", "meaning": "written to PSTAT_248 with the map (script_menu.c:1032): "
                                                    "the arrival point / exit for the script"},
        "trigger": {"meaning": "listed only when this trigger is set (birdraFillTargetList, script_menu.c:1729)"},
        "cost": {"unit": "bits"},
    }, [{"id": k, "map": {"id": b["mapId"], "name": maps[b["mapId"]]["name"]}, "entrance": b["unk_0x1"],
         "trigger": b["trigger"], "cost": b["cost"], "c": b} for k, b in enumerate(birdra)],
        {"access": "GameData.system('birdramon_transport')"})

    spots = []
    for g in us["TRN_TRAINING_SPOTS"]:
        if g["mapId"] == -1:
            continue
        sp = index.table(TRN_HUD, g["spots"])[REFERENCE].value
        spots.append({"map": {"id": g["mapId"], "name": maps[g["mapId"]]["name"]}, "symbol": g["spots"],
                      "spots": [{"stat": TRAINING_STATS.get(s["stat"]), "position": [s["x"], s["y"], s["z"]]}
                                for s in sp if s["stat"] != -1], "c": sp})
    write("training_spots", ["TRN_TRAINING_SPOTS"], {
        "map": {"meaning": "gym map (TRN_getTrainingSpotScreenPos, trn_hud.c:382)"},
        "spots": {"meaning": "per trained stat (0 hp, 1 mp, 2 off, 3 def, 4 speed, 5 brain): x, y, z of its "
                             "training equipment; -1 ends the list"},
    }, spots, {"access": "GameData.training_spots(map_id)",
               "notes": "trn2 has the same table (TRN2_TRAINING_SPOTS), checked equal."})

    # -- minigames / misc ---------------------------------------------------------------------
    kinds, bite, bait = us["FISH_KIND_INFO"], us["FISH_BITE_CHANCE"], us["FISH_BAIT_CHANCES"]
    rows = (FISH_DEPTH_END - FISH_DEPTH_FIRST)
    fishing = {
        "kinds": [{"kind": k, "item": iref(f["unk0"]) if k < 6 else None, "size": [f["lo"], f["hi"]],
                   "move_delay": [f["moveDelayMin"], f["moveDelayMax"]],
                   "bait": iref(f["bait"]) if f["bait"] != -1 else None, "c": f} for k, f in enumerate(kinds)],
        "bite_chance_by_depth": [{"depth": FISH_DEPTH_FIRST + r, "chances": bite[r * FISH_KINDS_ROW:(r + 1) *
                                                                                 FISH_KINDS_ROW]}
                                 for r in range(rows)],
        "snagged_items": [{"item": iref(b["item"]), "roll_up_to": b["threshold"]} for b in bait],
        "maps": [{k: (v if not isinstance(v, str) else v) for k, v in m.items()} for m in us["FISHING_MAP_DATA"]],
        "unused_bite_values": bite[rows * FISH_KINDS_ROW:],
    }
    write("fishing", ["FISH_KIND_INFO", "FISH_BITE_CHANCE", "FISH_BAIT_CHANCES", "FISHING_MAP_DATA"], {
        "kinds": {"meaning": "fish kinds 0-5 (item = the fish you catch, size range, frames between moves, bait "
                             "that attracts it; null = none needed) and 6 = Seadramon (fish.c:2618-2767)"},
        "bite_chance_by_depth": {"meaning": "FISH_BITE_CHANCE[(depth - 0x26) * 6 + kind]: % chance per check that a "
                                            "fish of that kind bites at this line depth (FISH_findFishToBite, "
                                            "fish.c:3080-3089); Seadramon always 20 %"},
        "snagged_items": {"c_name": "FISH_BAIT_CHANCES",
                          "meaning": "while rod.itemTaken is set (fish.c:3215), every 20 frames a 1000 / 10000 roll "
                                     "snags the line: r = 0..99 picks the first entry with r <= roll_up_to, and the "
                                     "item is given ('something got stuck', FISH_tickRod, fish.c:3991-4004, "
                                     ":4367-4379)"},
        "maps": {"meaning": "FISHING_MAP_DATA as written (pointers are C symbols)"},
    }, [fishing], {"access": "GameData.system('fishing')"}, fields=None)

    give, get = us["MOJYAMON_ITEMS_GIVE"], us["MOJYAMON_ITEMS_GET"]
    write("mojyamon_trades", ["MOJYAMON_ITEMS_GIVE", "MOJYAMON_ITEMS_GET"], {
        "set": {"meaning": "trade set = PSTAT_249 (script_menu.c:1765); 3 trades per set"},
        "trades": {"meaning": "give item -> get item (0 = unused slot)"},
    }, [{"set": s, "trades": [{"give": iref(give[s * TRADE_SET + k]), "get": iref(get[s * TRADE_SET + k])}
                              for k in range(TRADE_SET) if give[s * TRADE_SET + k] or get[s * TRADE_SET + k]]}
        for s in range(len(give) // TRADE_SET)], {"access": "GameData.system('mojyamon_trades')"})

    babies, eggs = us["BABY_IDS"]["b"], us["REINCARNATE_BABY_TYPE"]
    if any(level[b] not in (1, 2) for b in babies) or any(level[e] != 1 for e in eggs):
        bad["babies"].append(f"levels {[level[b] for b in babies]} / {[level[e] for e in eggs]}")
    out.check("babies are Fresh / In-Training, eggs give Fresh Digimon", not bad["babies"],
              "; ".join(bad["babies"]) or "ok")
    write("babies", ["BABY_IDS", "REINCARNATE_BABY_TYPE"], {
        "baby_ids": {"meaning": "isPartnerBaby (script_common.c:1440): partner types treated as babies"},
        "reincarnation_eggs": {"meaning": "egg slot -> Fresh Digimon of the reincarnation (DOOA_tickRebirth, "
                                          "dooa.c:1073-1103)"},
    }, [{"baby_ids": [dref(b) for b in babies],
         "reincarnation_eggs": [{"egg": k, "digimon": dref(e)} for k, e in enumerate(eggs)]}],
        {"access": "GameData.system('babies')"})

    tracks = us["BGM_TRACK_NAMES"]
    write("jukebox", ["BGM_TRACK_NAMES"], {
        "track": {"meaning": "track index of the jukebox list"},
        "name": {"meaning": "BGM_TRACK_NAMES[track]; US lists Mt. Panorama's theme at 45 where other releases list "
                            "Mt. Infinity (script_common.c:409-413)"},
    }, [{"track": k, "name": sref(s)} for k, s in enumerate(tracks)], {"access": "GameData.system('jukebox')"})

    write("versus", ["VS_DEMO_DIGIMON", "VS__BATTLE_COUNTS", "STD_STAT_BAR_LIMITS"], {
        "demo_digimon": {"meaning": "VS_DEMO_DIGIMON: fighters picked at random for the demo (vs_demo.c:184)"},
        "battle_counts": {"meaning": "VS__BATTLE_COUNTS: selectable numbers of matches"},
        "stat_bar_limits": {"meaning": "max of each stat bar (HP, MP, Off, Def, Speed, Brain) in the arena / "
                                       "versus intros"},
    }, [{"demo_digimon": [dref(i) for i in us["VS_DEMO_DIGIMON"]], "battle_counts": us["VS__BATTLE_COUNTS"],
         "stat_bar_limits": dict(zip(STATS, us["STD_STAT_BAR_LIMITS"]))}],
        {"access": "GameData.system('versus')"})

    out.check("every string id of the tables resolves to text", not unresolved, ", ".join(unresolved[:10]) or "ok")
    out.check("FLEE_CHANCES padding (entries 9-11) is 0", not bad["flee"], "; ".join(bad["flee"]) or "ok")
    out.check("every tournament grade image resolves to a path", not bad["grade images"],
              ", ".join(bad["grade images"]) or f"{len(image_paths)} paths")
    out.write_report("report.md", _report(maps, us, sref, dref, days_of))
    out.finish(sources, extra={"counts": {"maps": len(maps), "tournaments": len(names_l), "tables": len(out.tables)}})
    return out


def _report(maps, us, sref, dref, days_of) -> str:
    def t(x):
        return (x or {}).get("text", {}).get("en_us") if isinstance(x, dict) else None
    out = ["# Systems report", "", "Generated by `python -m dwdata convert systems`. US values. See "
           "`specs/systems.md` (one section per table).", "",
           "## Flee chances (`systems/flee_chances.json`)", "", "| partner \\ enemy | data | vaccine | virus |",
           "|---|---|---|---|"]
    fc = us["FLEE_CHANCES"]
    for p, n in TYPES.items():
        out.append(f"| {n} | " + " | ".join(str(fc[(p - 1) * 3 + e - 1]) for e in (1, 2, 3)) + " |")
    out += ["", "## Battle commands by brain", "", ", ".join(f"brain {k * 100}+: {v}" for k, v in
                                                              enumerate(us["BRAIN_TO_COMMAND_MAP"])) +
            f", brain {BRAIN_ALL_COMMANDS}+: 9", "",
            "## Tournaments (`systems/tournaments.json`)", "", "| id | name | grade | opponent base | days |",
            "|---|---|---|---|---|"]
    for k, s in enumerate(us["TOURNAMENT_NAMES"]):
        base = us["STD_OPPONENT_BASE_STATS"][k]
        out.append(f"| {k} | {t(sref(s))} | {t(sref(us['TOURNAMENT_GRADES'][k]))} | {base} | "
                   f"{', '.join(map(str, days_of.get(k, []))) or '—'} |")
    out += ["", "## Maps (`systems/maps.json`)", "", "| id | file | name | sound | no time | wild Digimon | toilet |",
            "|---|---|---|---|---|---|---|"]
    for m in maps:
        name = (t(m["name"]) or "").strip()
        out.append(f"| {m['id']} | {m['file']} | {name} | {m['sound_bank']} | {'yes' if m['no_time_of_day'] else ''} | "
                   f"{'yes' if m['wild_digimon'] else ''} | {m['toilet'] if m['toilet'] is not None else ''} |")
    out += ["", "## Birdramon transport", ""]
    for b in us["BIRDRA_TRANSPORT_TARGETS"]:
        out.append(f"- {(t(maps[b['mapId']]['name']) or '').strip()} (map {b['mapId']}): {b['cost']} bits, "
                   f"trigger {b['trigger']}")
    out += ["", "## Mojyamon trades", ""]
    give, get = us["MOJYAMON_ITEMS_GIVE"], us["MOJYAMON_ITEMS_GET"]
    out.append(", ".join(f"{give[k]} -> {get[k]}" for k in range(len(give)) if give[k] or get[k]))
    return "\n".join(out) + "\n"
