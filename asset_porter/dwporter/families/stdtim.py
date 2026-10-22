"""STDDAT/STDTIM.BIN: tournament (stadium) graphics, 6 stacked TIMs. Spec: specs/stacked_tim.md."""

from .stacked_tim import Entry, StackedFile, convert_stacked

NAME = "stdtim"
SOURCE_PATH = "STDDAT/STDTIM.BIN"
SPEC = "specs/stacked_tim.md"

DESC = StackedFile(
    family=NAME,
    source_path=SOURCE_PATH,
    spec=SPEC,
    file_size=0x20D80,  # dw_decomp/src/main/file_table_us.c:775
    code_refs=[
        "dw_decomp/src/std/std_setup.c:236 STD_PATH_STDDAT_STDTIM_BIN = \"\\\\STDDAT\\\\STDTIM.BIN\"",
        "dw_decomp/src/std/std_setup.c:270 STD_tournamentMain: STD_loadTIMToVRAM(STDTIM.BIN)",
        "dw_decomp/src/std/std_setup.c:501 STD_loadTIMToVRAM: readFile, then LoadImage image + CLUT for exactly 6 TIMs",
        "dw_decomp/src/vs/vs_scene.c:1180 VS_loadTIMToVRAM(VS_PATH_STDDAT_STDTIM_BIN)",
        "dw_decomp/src/vs/vs_demo.c:177 loadStackedTIMFile(VS_PATH_DEMO_STDDAT_STDTIM_BIN)",
    ],
    entries=[
        Entry("digimon_icons_a", "Digimon icons (set A)", (896, 0), (288, 480)),
        Entry("digimon_icons_b", "Digimon icons (set B), also used by bracket animations", (960, 0), (304, 480),
              ("dw_decomp/src/std/std_main.c:3594 STD_tickBracketHitFlash: GetClut(0x130, 0x1e0)",
               "dw_decomp/src/std/std_main.c:3630 STD_renderBracketProjectile: GetTPage(0, 2, 0x3c0, 0)"),
              identified_by="code"),
        Entry("time_up", "TIME UP banner, counter digits and backgrounds", (832, 0), (16, 480),
              ("dw_decomp/src/std/std_main.c:2878 STD_renderCounterDigits: GetClut(0x10, 0x1e0)",),
              identified_by="code"),
        Entry("font_large", "Large Latin and katakana font", (768, 0), (0, 480)),
        Entry("font_small", "Small Latin and katakana font (bracket names)", (832, 256), (48, 480),
              ("dw_decomp/src/std/std_main.c:3428 STD_renderBracketGlyph: GetTPage(0, 1, 0x340, 0x100), GetClut(48, 480)",),
              identified_by="code"),
        Entry("bracket", "Tournament bracket lines and boxes", (832, 120), (32, 480),
              ("dw_decomp/src/std/std_main.c:3301 STD_drawBracket: GetTPage(0, 1, 0x340, 0) (page shared with time_up)",
               "dw_decomp/src/std/std_main.c:3302 STD_drawBracket: GetClut(32, 480)"),
              identified_by="code"),
    ],
)


def convert(input_root, output_root):
    return convert_stacked(DESC, input_root, output_root)
