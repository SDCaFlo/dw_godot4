"""Standalone .TIM files (everything except CHDAT/ALLTIM.TIM). Spec: specs/tim_files.md.

Each file is one TIM, or several TIMs back to back (arena textures). All are loaded at the
VRAM position in their own header (loadTIMFile / loadTextureFile / arena loaders), so the
sidecar `vram` block is the real placement.
"""

from dataclasses import dataclass

from ..assets import AssetWriter
from ..formats import tim as timfmt
from ..source import SourceFile
from .stacked_tim import loader_step

NAME = "tim_files"
SOURCE_PATH = "**/*.TIM (51 files)"
SPEC = "specs/tim_files.md"
CODE_REFS = [
    "dw_decomp/src/main/file.c:98 loadTIMFile: readFile, LoadImage image (+ CLUT) at the header position",
    "dw_decomp/src/main/file.c:53 loadTextureFile: same, also returns GetTPage/GetClut of the header position",
    "dw_decomp/src/std/std_setup.c:618 STD_loadArenaTIMToVRAM(path, count) / vs_scene.c VS_loadArenaTIMToVRAM: `count` packed TIMs",
    "dw_decomp/src/main/utils2.c:492 loadStackedTIMFile (ETCDAT/ETCTIM.BIN = 9 of these files concatenated)",
]

LOAD_TIM = "loadTIMFile"
LOAD_TEXTURE = "loadTextureFile"
ARENA = "STD_loadArenaTIMToVRAM / VS_loadArenaTIMToVRAM"
NONE = "no direct loader found"


@dataclass(frozen=True)
class TimFile:
    path: str
    size: int  # FILE_OFFSET_TABLE size
    description: str
    loader: str
    code_refs: tuple = ()
    count: int = 1  # TIMs in the file
    identified_by: str = "code"  # "code" or "visual"
    also_in: str = None  # "<path>@0x<offset>": same bytes embedded in another file
    table: tuple = None  # (array name, index) when the game picks the file from a path table


def _etctim(name, size, offset, description, loader=NONE, refs=(), identified_by="visual"):
    refs = refs + ("only loaded through ETCDAT/ETCTIM.BIN",) if loader == NONE else refs
    return TimFile(f"ETCDAT/{name}.TIM", size, description, loader, refs, identified_by=identified_by,
                   also_in=f"ETCDAT/ETCTIM.BIN@0x{offset:X}")


# Order of STD_GRADES[23] (dw_decomp/src/std/std_setup.c:210), indexed by tournament id.
GRADES = ["GRADED", "GRADEC", "GRADEB", "GRADEA", "GRADES", "GRADER", "CAPV1", "CAPV2", "CAPV3", "CAPV4",
          "CAPVO", "FR", "GP", "TW", "CO", "NT", "MT", "DT", "DY", "WI", "AN", "HU", "BT"]
GRADE_SIZES = {"BT": 0x7F20}

FILES = [
    _etctim("BI_IN", 0x2220, 0x0, "UI sprites: digit fonts, PUSH label, star burst, toggles"),
    _etctim("BTLCOMND", 0x2220, 0x2220, "Battle command / condition icons"),
    _etctim("DEFEFF", 0x18C0, 0x4440, "Default effects: smoke / dust strip"),
    TimFile("ETCDAT/EX.TIM", 0xD20, "Effect texture strip", "EFEX table (populated, never read)",
            ("dw_decomp/src/main/efe_table.c:9 EFEX_PATH_ARRAY",)),
    _etctim("FEEL_EF", 0x2220, 0x5D00, "Feeling effects: speech bubbles, poop, computer props"),
    TimFile("ETCDAT/FISHING.TIM", 0x3BA0, "Fishing sprites: fish, rod, bobber, water rings", "fishing overlay",
            ("dw_decomp/src/fish/fish.c:823 FISH_PATH_FISHING_TIM", "dw_decomp/src/fish/fish.c:911")),
    TimFile("ETCDAT/FISHING2.TIM", 0x3BA0, "Fishing sprites, variant (same VRAM as FISHING.TIM)", "fishing overlay",
            ("dw_decomp/src/fish/fish.c:825 FISH_PATH_FISHING2_TIM", "dw_decomp/src/fish/fish.c:930")),
    _etctim("FI_INFO", 0x2220, 0x7F20, "Field info: game clock face and digits", LOAD_TIM,
            ("dw_decomp/src/main/main.c:3409 loadTIMFile(MAIN_D_8012CE64)",
             "dw_decomp/src/main/clock.c:280 renderGameClock: GetTPage(0, 0, 896, 448), GetClut(256, 496)"), "code"),
    _etctim("ITEM", 0x4320, 0x12360, "Item icons, 24 palettes"),
    _etctim("SBOY", 0x8220, 0xA140, "Digimon portrait icons and medal discs", LOAD_TIM,
            ("dw_decomp/src/std/std_setup.c:451 loadTIMFile(STD_PATH_ETCDAT_SBOY_TIM)",), "code"),
    TimFile("ETCDAT/SLOT.TIM", 0x1060, "Slot machine symbols", NONE, identified_by="visual"),
    _etctim("SPOT256", 0x4220, 0x16680, "8bpp spotlight / glow gradients", NONE,
            ("dw_decomp/src/main/map.c:5524 tickMeramonShake: GetClut(0, 0x1e7)",), "code"),
    _etctim("SYSTEM_W", 0x4220, 0x1A8A0, "System window: menu labels and frames", LOAD_TIM,
            ("dw_decomp/src/vs/vs_demo.c:112 loadTIMFile(VS_PATH_DEMO_ETCDAT_SYSTEM_W_TIM)",
             "dw_decomp/src/vs/vs_select.c:282 loadTIMFile(VS__PATH_ETCDAT_SYSTEM_W_TIM)",
             "dw_decomp/src/main/script_textbox.c:1008 renderUIBox: GetTPage(0, 1, 320, 128)"), "code"),
    TimFile("ETCDAT/TAMA.TIM", 0x2A20, "Digimon egg sprites", "inline readFile + LoadImage (DOOA overlay)",
            ("dw_decomp/src/dooa/dooa.c:285 DOOA_EGG_TIM_PATH", "dw_decomp/src/dooa/dooa.c:536")),
    TimFile("ETCHI/LIFE.TIM", 0x580, "Hearts and LIFE label", LOAD_TEXTURE,
            ("dw_decomp/src/murd/murd.c:778 loadTextureFile(MURD_LIFE_TIM_PATH)",)),
    TimFile("ETCHI/OP.TIM", 0x3500, "Water / waterfall strip and light orb", LOAD_TEXTURE,
            ("dw_decomp/src/main/script_interp.c:1849 loadTextureFile(MAIN_D_801303A8)",)),
    TimFile("ETCNA/IWA1.TIM", 0x240, "Boulder texture", LOAD_TEXTURE,
            ("dw_decomp/src/main/map_object.c:624 loadTextureFile(BOULDER_TIM)",)),
    TimFile("ETCNA/TAKA.TIM", 0xDC0, "Treasure chest texture (pairs with TAKA.TMD, CHEST_TMD in map_object.c:77)",
            NONE, identified_by="visual"),
    TimFile("ETCNA/TITLE2.TIM", 0x12E20, "Title screen 320x240, 8bpp", LOAD_TIM,
            ("dw_decomp/src/main/main.c:3696 loadTIMFile(MAIN_D_8012CEA0)",
             "dw_decomp/src/vs/vs_demo.c:493", "dw_decomp/src/vs/vs_select.c:474")),
    TimFile("ETCNA/TITLE256.TIM", 0x14220, "Title screen 320x256, 8bpp", LOAD_TIM,
            ("dw_decomp/src/main/main.c:3412 loadTIMFile(MAIN_D_8012CE78)", "dw_decomp/src/vs/vs_demo.c:152")),
    TimFile("STDDAT/16TAISEN.TIM", 0x80C0, "VS mode Digimon icons", LOAD_TIM,
            ("dw_decomp/src/vs/vs_scene.c:1181", "dw_decomp/src/vs/vs_select.c:285", "dw_decomp/src/vs/vs_demo.c:355")),
    TimFile("STDDAT/B_TOGI.TIM", 0x168C0, "Arena textures: B_TOGI stage", ARENA,
            ("dw_decomp/src/std/std_main.c:1336 STD_ARENA_TIMS[1]", "dw_decomp/src/vs/vs_scene.c:1051 VS_ARENA_TIMS[1]",
             "dw_decomp/src/std/std_setup.c:132 STD_ARENA_COUNTS.timCount[1] = 1"), table=("STD_ARENA_TIMS", 1)),
    TimFile("STDDAT/E_TOGI.TIM", 0x6D20, "Arena textures: E_TOGI stage (VS mode only)", ARENA,
            ("dw_decomp/src/vs/vs_scene.c:1051 VS_ARENA_TIMS[2]", "dw_decomp/src/vs/vs_scene.c:166 VS_ARENA_TIM_COUNTS[2] = 1"),
            table=("VS_ARENA_TIMS", 2)),
    TimFile("STDDAT/T_TOGI.TIM", 0x1AB40, "Arena textures: T_TOGI stage (4 TIMs)", ARENA,
            ("dw_decomp/src/std/std_main.c:1336 STD_ARENA_TIMS[0]", "dw_decomp/src/vs/vs_scene.c:1051 VS_ARENA_TIMS[0]",
             "dw_decomp/src/std/std_setup.c:132 STD_ARENA_COUNTS.timCount[0] = 4"), count=4, table=("STD_ARENA_TIMS", 0)),
    TimFile("STDDAT/TAISEN1.TIM", 0x8220, "VS mode panels and buttons", LOAD_TIM,
            ("dw_decomp/src/vs/vs_demo.c:114", "dw_decomp/src/vs/vs_select.c:283")),
    TimFile("STDDAT/TAISEN2.TIM", 0x2460, "VS MODE label and stat icons (HP, MP, AP, DP, SP, INT)", LOAD_TIM,
            ("dw_decomp/src/vs/vs_demo.c:354", "dw_decomp/src/vs/vs_select.c:284")),
    TimFile("STDDAT/TAISEN_F.TIM", 0x8220, "VS mode font, menu labels and battle portraits", LOAD_TIM,
            ("dw_decomp/src/vs/vs_demo.c:356", "dw_decomp/src/vs/vs_select.c:286")),
    TimFile("STDDAT/TIME.TIM", 0x99A, "Battle timer frame", LOAD_TIM,
            ("dw_decomp/src/std/std_setup.c:271 loadTIMFile(STD_PATH_STDDAT_TIME_TIM)",
             "dw_decomp/src/vs/vs_demo.c:113", "dw_decomp/src/vs/vs_select.c:287")),
] + [
    TimFile(f"STDDAT/GRADE/{g}.TIM", GRADE_SIZES.get(g, 0x8220), f"Tournament title card {g}", LOAD_TIM,
            ("dw_decomp/src/std/std_setup.c:210 STD_GRADES", "dw_decomp/src/std/std_setup.c:269 loadTIMFile(STD_GRADES[arg[0]])"),
            table=("STD_GRADES", i))
    for i, g in enumerate(GRADES)
]


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()

    on_disc = sorted(p.relative_to(input_root).as_posix() for p in input_root.rglob("*.TIM")
                     if p.relative_to(input_root).parts[0] != "CHDAT")
    listed = sorted(f.path for f in FILES)
    out.check("every standalone .TIM on disc is listed", on_disc == listed,
              f"unlisted: {sorted(set(on_disc) - set(listed))}, missing: {sorted(set(listed) - set(on_disc))}")

    sources = []
    for entry in sorted(FILES, key=lambda f: f.path):
        src = SourceFile.open(input_root, entry.path)
        sources.append(src)
        label = entry.path
        out.check(f"{label}: size matches FILE_OFFSET_TABLE", src.size == entry.size, f"0x{src.size:X}")

        tims, offset = [], 0
        while offset < src.size and len(tims) < entry.count:
            tim = timfmt.try_parse(src.data, offset)
            if not out.check(f"{label}: TIM {len(tims)} valid", tim is not None, f"at 0x{offset:X}"):
                break
            out.check(f"{label}: TIM {len(tims)} packed", loader_step(tim) == tim.size, f"0x{tim.size:X}")
            tims.append(tim)
            offset += tim.size
        out.check(f"{label}: {entry.count} TIM(s)", len(tims) == entry.count, str(len(tims)))
        out.check(f"{label}: rest of file is zero", not any(src.data[offset:]), f"{src.size - offset} bytes")

        if entry.also_in:
            other_path, other_offset = entry.also_in.split("@")
            other = (input_root / other_path).read_bytes()
            start = int(other_offset, 16)
            out.check(f"{label}: identical to {entry.also_in}", other[start:start + src.size] == src.data, "")

        base = entry.path.rsplit(".", 1)[0]
        for index, tim in enumerate(tims):
            name = base if entry.count == 1 else f"{base}_{index:02d}"
            out.write_tim(name, src.span(tim.offset, tim.size), tim, {
                "file": {
                    "description": entry.description,
                    "loader": entry.loader,
                    "code_refs": list(entry.code_refs),
                    "identified_by": entry.identified_by,
                    "tim_index": index,
                    "tim_count": entry.count,
                    "also_in": entry.also_in,
                    "table": {"name": entry.table[0], "index": entry.table[1]} if entry.table else None,
                },
            })

    out.finish(sources)
    return out
