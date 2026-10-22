"""ETCDAT/ETCTIM.BIN: shared field / menu graphics, 9 stacked TIMs. Spec: specs/stacked_tim.md."""

from .stacked_tim import Entry, StackedFile, convert_stacked

NAME = "etctim"
SOURCE_PATH = "ETCDAT/ETCTIM.BIN"
SPEC = "specs/stacked_tim.md"

DESC = StackedFile(
    family=NAME,
    source_path=SOURCE_PATH,
    spec=SPEC,
    file_size=0x1EAC0,  # dw_decomp/src/main/file_table_us.c:225
    code_refs=[
        "dw_decomp/src/main/main.c:247 MAIN_D_8012CE8C = \"\\\\ETCDAT\\\\ETCTIM.BIN\" (EU: ETCTIM_E.BIN)",
        "dw_decomp/src/main/main.c:3434 loadStackedTIMFile(MAIN_D_8012CE8C) before the main menu, and at 3444/3460/3478 on new game / load / continue",
        "dw_decomp/src/vs/vs_demo.c:115 loadStackedTIMFile(VS_PATH_DEMO_ETCDAT_ETCTIM_BIN) (also :492)",
        "dw_decomp/src/main/utils2.c:492 loadStackedTIMFile: readFile, then LoadImage image + CLUT for each TIM while the word is 0x10",
    ],
    entries=[
        Entry("ui_system", "UI sprites: digit fonts, PUSH label, star burst, toggles", (896, 384), (256, 480)),
        Entry("status_icons", "Condition / emotion icons (faces, drops, effects)", (960, 448), (272, 496)),
        Entry("smoke", "Smoke / dust effect strip", (768, 384), (192, 488)),
        Entry("scene_props", "Computer screens, speech bubbles, poop and misc props", (960, 384), (272, 480)),
        Entry("clock", "Game clock face and digits", (896, 448), (256, 496),
              ("dw_decomp/src/main/clock.c:228 initializeClockData: GetTPage(0, 0, 896, 448)",
               "dw_decomp/src/main/clock.c:280 renderGameClock: GetTPage(0, 0, 896, 448), GetClut(256, 496)"),
              identified_by="code"),
        Entry("digimon_icons", "Digimon portrait icons and medal discs", (512, 256), (112, 488)),
        Entry("items", "Item icons, 24 palettes", (320, 0), (224, 488), duplicate_of="ETCDAT/ITEM.TIM"),
        Entry("glow", "8bpp circular gradients (glow / light)", (832, 384), (0, 487),
              ("dw_decomp/src/main/map.c:5524 tickMeramonShake: GetClut(0, 0x1e7)",),
              identified_by="code"),
        Entry("ui_menu", "Menu labels and frames (types, stats, NAME, HAPPINESS, ...)", (320, 128), (96, 488),
              ("dw_decomp/src/main/script_textbox.c:1008 renderUIBox: GetTPage(0, 1, 320, 128)",),
              identified_by="code"),
    ],
)


def convert(input_root, output_root):
    return convert_stacked(DESC, input_root, output_root)
