"""CARD/CARD.ALL: the 66 trading card images. Spec: specs/card_all.md."""

from ..assets import AssetWriter
from ..formats import tim as timfmt
from ..formats import psx
from ..paths import SECTOR_SIZE
from ..source import SourceFile

NAME = "card_all"
SOURCE_PATH = "CARD/CARD.ALL"
SPEC = "specs/card_all.md"
CODE_REFS = [
    "dw_decomp/src/main/game_menu.c:461 MAIN_D_80123E78 = \"\\\\CARD\\\\CARD.ALL\"",
    "dw_decomp/src/main/game_menu.c:2380 loadCardImage(id): loadStackedTIMEntry(path, TEXTURE_BUFFER, id * 0xe, 0xe)",
    "dw_decomp/src/main/game_menu.c:2386 renderCardImage: GetTPage(1, 0, 576, 256), GetClut(448, 511), 150x180",
    "dw_decomp/src/main/file.c:116 loadStackedTIMEntry: readFileSectors + LoadImage(image) + LoadImage(clut)",
    "dw_decomp/src/main/file_table_us.c:8 { 0x19, 0x1ce000, \"CARD.ALL\" }",
]

# From the code above.
SLOT_SECTORS = 0xE
SLOT_SIZE = SLOT_SECTORS * SECTOR_SIZE  # 0x7000
FILE_SIZE = 0x1CE000
EXPECTED_CARDS = 66
TPAGE = psx.get_tpage(1, 0, 576, 256)
CLUT = psx.get_clut(448, 511)
DRAW_SIZE = (0x96, 0xB4)  # renderRectPolyFT4 width/height in pixels


def convert(input_root, output_root) -> AssetWriter:
    src = SourceFile.open(input_root, SOURCE_PATH)
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()

    out.check("file size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, f"0x{src.size:X}")
    out.check("file is a whole number of slots", src.size % SLOT_SIZE == 0, f"0x{src.size:X} / 0x{SLOT_SIZE:X}")
    count = src.size // SLOT_SIZE
    out.check(f"{EXPECTED_CARDS} slots", count == EXPECTED_CARDS, str(count))

    for card_id in range(count):
        offset = card_id * SLOT_SIZE
        tim = timfmt.try_parse(src.data, offset)
        label = f"card {card_id}"
        if not out.check(f"{label}: valid TIM", tim is not None, f"at 0x{offset:X}"):
            continue
        vram = tim.vram_info()
        out.check(f"{label}: fits in slot", tim.size <= SLOT_SIZE, f"0x{tim.size:X}")
        out.check(f"{label}: 8bpp", tim.bpp == 8, str(tim.bpp))
        out.check(f"{label}: tpage matches renderCardImage", vram.get("tpage") == TPAGE, str(vram.get("tpage")))
        out.check(f"{label}: clut matches renderCardImage", vram.get("clut_ids") == [CLUT], str(vram.get("clut_ids")))
        out.check(f"{label}: size matches renderCardImage", (tim.width, tim.height) == DRAW_SIZE,
                  f"{tim.width}x{tim.height}")
        padding = src.data[offset + tim.size:offset + SLOT_SIZE]
        out.check(f"{label}: slot padding is zero", not any(padding), f"{len(padding)} bytes")

        span = src.span(offset, tim.size)
        out.write_tim(f"card_{card_id:02d}", span, tim, {
            "card": {
                "id": card_id,
                "slot": {
                    "offset": offset,
                    "size": SLOT_SIZE,
                    "sector": card_id * SLOT_SECTORS,
                    "sectors": SLOT_SECTORS,
                },
                "loader": "loadCardImage(id)",
            },
        })

    out.finish([src])
    return out
