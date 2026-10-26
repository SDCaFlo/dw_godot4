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
TRN_SLOTS = "src/trn/trn_slots.c"
FISH_C, SHOP_MENU, DOOA_C = "src/fish/fish.c", "src/shop/script_menu.c", "src/dooa/dooa.c"
MAIN_C = "src/main/main.c"
OVERWORLD_C = "src/main/overworld.c"
SCRIPT_VALUE_C, SCRIPT_H = "src/main/script_value.c", "include/dw/script.h"
# changeMap (map.c:5326-5396): (map left, map entered, PREVIOUS_SCREEN, PREVIOUS_EXIT or None).
CHANGE_MAP_PREVIOUS = [
    (0xCF, 0x26, 0x58, 2), (0xCF, 0x46, 0x45, 2), (0xCF, 0x4F, 0x11, 1), (0xCF, 0x5D, 0x5A, 0),
    (0xCF, 0x77, 0x76, 1), (0xCF, 0x69, 0x6A, 0), (0x2B, 0x2A, 0x29, 1), (6, 0x69, 0x6A, None),
    (0x8E, 0x87, 0x84, 1), (5, 0xC, 0xD, 1),
]
# loadMapObjects (overworld.c:364): the snow maps, whose first SNOW_INSTANCES object instances fall
# as snow (flag 0x80, buildSnowflakePrim; specs/map_objects.md §2.5). Ranges [first, end).
SNOW_MAPS = [(0x58, 0x61), (0x84, 0x88)]
SNOW_INSTANCES = 0x23
SNOW_EVIDENCE = ("if (((mapId >= 0x58 && mapId < 0x61) || (mapId >= 0x84 && mapId < 0x88)) && k < 0x23) "
                 "{ if (k >= 0x14) { mapObjects->x = randomLimit(320); } mapObjects->y = randomLimit(240); "
                 "mapObjects->flag |= 0x80; }")
# updateMapLightState (utils2.c:553): the hours the light entries test (7 <= HOUR < 0x13).
LIGHT_EVIDENCE = "if ((HOUR >= 7) && (HOUR < 0x13)) { if (p->mode == 0) {"
UTILS2_C = "src/main/utils2.c"
# The C text of those rules (whitespace collapsed).
CHANGE_MAP_EVIDENCE = [
    "if (CURRENT_SCREEN == 0xcf) { if (mapId == 0x26) { PREVIOUS_SCREEN = 0x58; } if (mapId == 0x46) { "
    "PREVIOUS_SCREEN = 0x45; } if (mapId == 0x4f) { PREVIOUS_SCREEN = 0x11; } if (mapId == 0x5d) { PREVIOUS_SCREEN = "
    "0x5a; } if (mapId == 0x77) { PREVIOUS_SCREEN = 0x76; } if (mapId == 0x69) { PREVIOUS_SCREEN = 0x6a; } if ((mapId "
    "== 0x26) || (mapId == 0x46)) { PREVIOUS_EXIT = 2; } if ((mapId == 0x4f) || (mapId == 0x77)) { PREVIOUS_EXIT = 1; "
    "} if ((mapId == 0x5d) || (mapId == 0x69)) { PREVIOUS_EXIT = 0; } }",
    "if ((CURRENT_SCREEN == 0x2b) && (mapId == 0x2A)) { PREVIOUS_SCREEN = 0x29; PREVIOUS_EXIT = 1; }",
    "if ((CURRENT_SCREEN == 6) && (mapId == 0x69)) { PREVIOUS_SCREEN = 0x6a; }",
    "if ((CURRENT_SCREEN == 0x8e) && (mapId == 0x87)) { PREVIOUS_SCREEN = 0x84; PREVIOUS_EXIT = 1; }",
    "if ((CURRENT_SCREEN == 5) && (mapId == 0xc)) { PREVIOUS_SCREEN = 0xd; PREVIOUS_EXIT = 1; }",
]

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
    # jukeboxFillTitleList: the last track only once trigger 50 is set (unlock_trigger), the playing
    # track found by its MAIN_D_801303B8 pair.
    (SHOP_MENU, "unlocked = isTriggerSet(TRIGGER_50);"),
    (SHOP_MENU, "} else if (i != 0x3e && i != 0x3e) {"),
    (SHOP_MENU, "if (MAIN_D_801303B8[track * 2] == getActiveBGMFont() && MAIN_D_801303B8[track * 2 + 1] == getActiveBGMVariant()) {"),
    ("include/dw/trigger.h", "#define TRIGGER_50\t50"),
    (SCRIPT_VALUE_C, "cap = STATS_LIMIT_ARRAY[stat];"),
    (TRN_SLOTS, "st->assist = TRN_D_8008F2CC[rand() % 10];"),
    (TRN_SLOTS, "if (TRN_D_8008F1AC[0][p->reelPos[0]] == 7) {"),
    (TRN_SLOTS, "} else if ((TRN_D_8008F1AC[0][p->reelPos[0]] - 1) == p->stat) {"),
    (TRN_SLOTS, "p->payout = 100;"), (TRN_SLOTS, "p->payout = 0x28;"), (TRN_SLOTS, "p->payout = 0x14;"),
    (TRN_SLOTS, "p->payout = 5;"), (TRN_SLOTS, "playSound(8, 0xc);"), (TRN_SLOTS, "playSound(8, 0xb);"),
    (TRN_SLOTS, "playSound(8, 0xd);"),
]
# TRN_tickSlotMachine state 5 (trn_slots.c): the symbol that pays the jackpot, and what each result pays.
SLOT_JACKPOT = 7
SLOT_PAYOUTS = [("jackpot", 100, 0xC, "three 7s", "p->payout = 100; playSound(8, 0xc);"),
                ("own_stat", 0x28, 0xB, "three of a kind, symbol - 1 == the station's stat",
                 "p->payout = 0x28; playSound(8, 0xb);"),
                ("other_match", 0x14, 0xB, "any other three of a kind", "p->payout = 0x14; playSound(8, 0xb);"),
                ("none", 5, 0xD, "no match", "p->payout = 5; playSound(8, 0xd);")]

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
    "slot_machine": "Training slot machine (Bonus Try): the reels, the assist draw, the symbols and the payouts",
    "fishing": "Fishing: fish kinds, bite chances by depth, items the line can snag, fishing maps",
    "mojyamon_trades": "Mojyamon's item trades: 4 sets of 3 (give -> get)",
    "babies": "Baby Digimon ids (Fresh / In-Training) and the baby each reincarnation egg gives",
    "jukebox": "Jukebox track list (index = track id)",
    "versus": "Versus mode: demo fighters, battle counts, stat bar limits",
    "script_stat_limits": "The stats event scripts change (SET_STAT / ADD_STAT) and their caps (STATS_LIMIT_ARRAY)",
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
                    VS_INTRO, SCRIPT_C, TOURNAMENT_C, GAME_MENU, MAP_C, TOILET_C, TRN_HUD, TRN2_HUD, TRN_SLOTS, FISH_C,
                    SHOP_MENU, DOOA_C, SCRIPT_VALUE_C, SCRIPT_H, OVERWORLD_C, UTILS2_C})
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
            (TRN_HUD, "TRN_TRAINING_SPOTS"), (TRN_HUD, "TRN_D_8008F1AC"), (TRN_SLOTS, "TRN_D_8008F2CC"),
            (FISH_C, "FISH_KIND_INFO"), (FISH_C, "FISH_BITE_CHANCE"),
            (FISH_C, "FISH_BAIT_CHANCES"), (FISH_C, "FISHING_MAP_DATA"), (SHOP_MENU, "MOJYAMON_ITEMS_GIVE"),
            (SHOP_MENU, "MOJYAMON_ITEMS_GET"), (SCRIPT_C, "BABY_IDS"), (DOOA_C, "REINCARNATE_BABY_TYPE"),
            (SCRIPT_C, "BGM_TRACK_NAMES"), (SHOP_MENU, "MAIN_D_801303B8"), (SCRIPT_C, "MAP_LIGHT_UPDATE_DATA"), (VS_DEMO, "VS_DEMO_DIGIMON"), (VS_SELECT, "VS__BATTLE_COUNTS"),
            (SCRIPT_VALUE_C, "STATS_LIMIT_ARRAY"), (SCRIPT_VALUE_C, "MULTIPLE_OF_10")]:
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

    def write(name, symbols, schema, records, godot, extra=None, fields=None, binary="main"):
        main = L[symbols[0]]
        used = sum((tables.used_by(decomp, refs[s], fields or [], L[s]) for s in symbols), [])
        diffs = {s: d for s in symbols if (d := tables.diffs(L[s], lambda l: l.value))}
        table = {"table": {"name": f"systems/{name}", "purpose": TABLE_PURPOSES[name]},
                 "source": tables.source(decomp, main, sources, dict(
                     {"also": [f"{s} {L[s][REFERENCE].decl.file}:{L[s][REFERENCE].decl.line}" for s in symbols[1:]]}
                     if symbols[1:] else {}, **(extra or {})), binary=binary),
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
    # changeMap's literal map ids (map.c:5326-5396) as a property of the map being left.
    map_c = " ".join((decomp.root / MAP_C).read_text(encoding="utf-8", errors="replace").split())
    missing_rules = [needle for needle in CHANGE_MAP_EVIDENCE if needle not in map_c]
    out.check("changeMap's previous-map rules are still in the code", not missing_rules,
              "; ".join(missing_rules[:5]) or f"{len(CHANGE_MAP_PREVIOUS)} rules")
    for source, target, previous, previous_exit in CHANGE_MAP_PREVIOUS:
        maps[source].setdefault("change_map_previous", []).append(
            {"to": target, "previous_screen": previous, "previous_exit": previous_exit})
    # The overlay rules of specs/map_objects.md as map properties (the original tests map ids).
    overworld_c = " ".join((decomp.root / OVERWORLD_C).read_text(encoding="utf-8", errors="replace").split())
    out.check("loadMapObjects' snow maps are still in the code", SNOW_EVIDENCE in overworld_c, SNOW_EVIDENCE[:60])
    for first, end in SNOW_MAPS:
        for k in range(first, end):
            maps[k]["snow"] = {"instances": SNOW_INSTANCES, "random_x_from": 0x14}
    utils2_c = " ".join((decomp.root / UTILS2_C).read_text(encoding="utf-8", errors="replace").split())
    out.check("updateMapLightState's hours are still in the code", LIGHT_EVIDENCE in utils2_c, LIGHT_EVIDENCE)
    for light in us["MAP_LIGHT_UPDATE_DATA"]:
        maps[light["mapId"]].setdefault("light_objects", []).append(
            {"start": light["startId"], "count": light["count"], "mode": light["mode"],
             "trigger": None if light["trigger"] == 0xFFFF else light["trigger"], "c": light})
    # Maps are keyed by file name: the area name is shared by many maps (specs/content.md §2).
    tables.keys(out, maps, "map", lambda r: r["file"].lower() if r["file"] else None)
    map_struct = index.program(MAP_C, REFERENCE).structs["MapEntry"]
    write("maps", ["MAP_ENTRIES", "MAP_NAME_PTR", "ARENA_MAPS", "MAP_LIGHT_UPDATE_DATA"], {
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
        "change_map_previous": {"meaning": "changeMap (map.c:5326) leaving this map for `to`: PREVIOUS_SCREEN becomes "
                                           "`previous_screen` instead of this map, and PREVIOUS_EXIT `previous_exit` "
                                           "(null = unchanged). Fleeing a battle returns to the previous map. The "
                                           "original tests these literal map ids; absent = no rule"},
        "snow": {"meaning": "loadMapObjects (overworld.c:364): the first `instances` object instances are snow "
                            "(flag 0x80, random y; random x from `random_x_from` on). The original tests map ids "
                            "0x58-0x60 and 0x84-0x87; absent = no snow"},
        "light_objects": {"c_name": "MAP_LIGHT_UPDATE_DATA", "meaning": "updateMapLightState (utils2.c:553), every "
                          "frame: object instances start .. start + count - 1 get flag 0 (shown) or 1 (hidden) by the "
                          "hour; mode 0 shown from 7:00 to 18:59, mode 1 hidden then. Only while `trigger` is set "
                          "(null = always). Absent = none"},
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

    # -- training slot machine (Bonus Try) ----------------------------------------------------
    reels, draw = us["TRN_D_8008F1AC"], us["TRN_D_8008F2CC"]
    for ld in (L["TRN_D_8008F1AC"], L["TRN_D_8008F2CC"]):
        tables.size_check(out, decomp, ld, binary="trn")
    symbol_ids = sorted({s for r in reels for s in r})
    slot_bad = []
    if len(reels) != 3 or any(len(r) != 13 for r in reels):
        slot_bad.append(f"reels {[len(r) for r in reels]}")
    if symbol_ids != list(range(1, SLOT_JACKPOT + 1)):
        slot_bad.append(f"symbols {symbol_ids}")
    slot_bad += [f"reel {k} has {sorted(r)}" for k, r in enumerate(reels) if sorted(set(r)) != symbol_ids]
    if len(draw) != 10 or any(a not in (0, 1, 2) for a in draw):
        slot_bad.append(f"assist draw {draw}")
    out.check("slot machine: 3 reels of 13 with symbols 1-7 on each, an assist draw of 10 entries (0-2)",
              not slot_bad, "; ".join(slot_bad) or f"{len(reels)} reels, {len(draw)} draws")
    write("slot_machine", ["TRN_D_8008F1AC", "TRN_D_8008F2CC"], {
        "reels": {"c_name": "TRN_D_8008F1AC[3][13]", "meaning": "the symbols of each reel, in strip order; the "
                  "symbol on the pay line is reels[i][reelPos[i]], and the strip scrolls towards lower indices "
                  "(TRN_tickSlotMachine, TRN_renderSlotMachine)"},
        "assist_draw": {"c_name": "TRN_D_8008F2CC[10]", "meaning": "assist = assist_draw[rand() % 10] when the "
                        "machine opens (TRN_createSlotMachineBox): 0 honest, 1 helps the first symbol, 2 the "
                        "jackpot (TRN_chooseReelStop)"},
        "symbols": {"meaning": "symbol id (1-7, the picture u = (id - 1) * 32) and the stat it stands for: a "
                    "match pays `own_stat` when the stat is the station's (the C tests symbol - 1 == stat, "
                    "stat in the multiplier's mode numbering of training_spots); the jackpot has no stat"},
        "payouts": {"meaning": "the awards' `c` and the sound (playSound(8, sound)) of each result, by the "
                    "line symbols (TRN_tickSlotMachine state 5): c / 10 multiplies the stat gains"},
    }, [{"reels": reels, "assist_draw": draw,
         "symbols": [{"symbol": k, "stat": TRAINING_STATS[k - 1]} if k != SLOT_JACKPOT else
                     {"symbol": k, "jackpot": True} for k in range(1, SLOT_JACKPOT + 1)],
         "payouts": {n: {"payout": v, "sound": snd, "when": w, "c": c} for n, v, snd, w, c in SLOT_PAYOUTS}}],
        {"access": "GameData.slot_machine()"}, binary="trn")

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
    songs = us["MAIN_D_801303B8"]
    bad_songs = [k for k in range(len(tracks)) if not 1 <= songs[k * 2] <= 0x21]
    out.check("jukebox: a (font, variant) pair per track, fonts 1-0x21 (playMusic)",
              len(songs) == 128 and len(tracks) == 63 and not bad_songs,
              f"{len(songs) // 2} pairs, {len(tracks)} names, bad {bad_songs}")
    write("jukebox", ["BGM_TRACK_NAMES", "MAIN_D_801303B8"], {
        "track": {"meaning": "track index of the jukebox list"},
        "name": {"meaning": "BGM_TRACK_NAMES[track]; US lists Mt. Panorama's theme at 45 where other releases list "
                            "Mt. Infinity (script_common.c:409-413)"},
        "font": {"c_name": "MAIN_D_801303B8[track * 2]", "meaning": "playMusic font of the track "
                                                                    "(tickJukeboxMenu, shop/script_menu.c:2421)"},
        "variant": {"c_name": "MAIN_D_801303B8[track * 2 + 1]", "meaning": "playMusic track within the font"},
        "unlock_trigger": {"meaning": "listed only once this trigger is set (jukeboxFillTitleList: track 0x3E and "
                                      "TRIGGER_50, the game beaten once; shop/script_menu.c:1643-1655), null = always"},
    }, [{"track": k, "name": sref(s), "font": songs[k * 2], "variant": songs[k * 2 + 1],
         "unlock_trigger": 50 if k == 0x3E else None} for k, s in enumerate(tracks)],
        {"access": "GameData.system('jukebox')"})

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
    _stat_limits(out, decomp, us, write)
    out.write_report("report.md", _report(maps, us, sref, dref, days_of))
    out.finish(sources, extra={"counts": {"maps": len(maps), "tournaments": len(names_l), "tables": len(out.tables)}})
    return out


def _stat_limits(out, decomp, us, write) -> None:
    """STATS_LIMIT_ARRAY with the stat ids of script.h. The array has 22 entries for 23 stats: the last
    (lives) reads past it, into the next symbol (MULTIPLE_OF_10), whose first int32's low half it gets."""
    import re
    header = (decomp.root / SCRIPT_H).read_text(encoding="utf-8", errors="replace")
    stats = {int(v, 16): n.lower() for n, v in re.findall(r"#define SCRIPT_STAT_(\w+)\s+(0x[0-9A-Fa-f]+)", header)}
    limits = us["STATS_LIMIT_ARRAY"]
    syms = decomp.symbols("main")
    a = int(syms.get("STATS_LIMIT_ARRAY", {}).get("address", "0"), 16)
    b = int(syms.get("MULTIPLE_OF_10", {}).get("address", "0"), 16)
    pow10 = us["MULTIPLE_OF_10"]
    first = (pow10.get("v") if isinstance(pow10, dict) else pow10)[0]
    ids = sorted(stats)
    out.check("script stats: ids 0..n-1, one more than STATS_LIMIT_ARRAY has, the next symbol right after it",
              ids == list(range(len(ids))) and len(ids) == len(limits) + 1 and b == a + 2 * len(limits),
              f"{len(ids)} stats, {len(limits)} limits, STATS_LIMIT_ARRAY {a:#x}, MULTIPLE_OF_10 {b:#x}")
    records = []
    for i in ids:
        rec = {"stat": i, "name": stats[i]}
        if i < len(limits):
            rec["limit"] = limits[i]
        else:
            rec["limit"] = first & 0xFFFF
            rec["read_past_the_array"] = "STATS_LIMIT_ARRAY[%d] is the low half of MULTIPLE_OF_10[0] (%d)" % (i, first)
        records.append(rec)
    write("script_stat_limits", ["STATS_LIMIT_ARRAY"], {
        "stat": {"meaning": "SCRIPT_STAT_* id (include/dw/script.h:128-150), the argument of SET_STAT / ADD_STAT / "
                            "REDUCE_STAT and of IF's stat condition (getStatsPointer, script_value.c:208)"},
        "name": {"meaning": "the SCRIPT_STAT_* name, lower case"},
        "limit": {"meaning": "enforceStatsLimits (script_value.c:356): SET_STAT / ADD_STAT keep the value at most this "
                             "(current HP / MP: the max HP / MP instead). REDUCE_STAT doesn't cap"},
        "read_past_the_array": {"meaning": "quirk: the stat has no entry; the C reads the next symbol"},
    }, records, {"access": "GameData.script_stat_limit(stat)",
                 "notes": "Stat 22 (lives) is capped at 1 by the read past the array: File City's 'Life three' "
                          "section (script 164) sets 3 and gets 1."})


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
