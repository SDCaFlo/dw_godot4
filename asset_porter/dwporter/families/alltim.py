"""CHDAT/ALLTIM.TIM: one model texture per Digimon type (180). Spec: specs/alltim.md."""

from ..assets import AssetWriter
from ..data.digimon import DIGIMON_TYPES, mmd_path
from ..formats import tim as timfmt
from ..paths import SECTOR_SIZE
from ..source import SourceFile

NAME = "alltim"
SOURCE_PATH = "CHDAT/ALLTIM.TIM"
SPEC = "specs/alltim.md"
CODE_REFS = [
    "dw_decomp/src/main/model.c:2506 MAIN_D_8011D190 = \"ALLTIM.TIM\"",
    "dw_decomp/src/main/model.c:3285 loadDigimonTexture(digiType, ...): readFileSectors(\"ALLTIM.TIM\", buf, digiType * 9, 9) + uploadModelTexture",
    "dw_decomp/src/main/model.c:3557 uploadModelTexture: replaces the TIM's VRAM position with the model slot's pixelPage/offset/clutPage",
    "dw_decomp/src/main/model.c:3400 NPC slot k: pixelPage = k / 2 + 0x16, pixelOffsetY = (k % 2) << 7, clutPage = (k + 2) | 0x7A00",
    "dw_decomp/src/main/model.c:3424 tamer: pixelPage 0x15, clutPage 0x7A00; partner: pixelPage 0x15, offsetY 0x80, clutPage 0x7A01",
    "dw_decomp/src/main/model.c:3621 loadMMDAsync: same read (digimonType * 9 sectors, imageSize 0x4800)",
    "dw_decomp/src/main/model.c:2508 PTR_DIGIMON_FILE_NAMES[180] (model file per type)",
    "dw_decomp/src/main/file_table_us.c:9 { 0x3b6, 0x32a000, \"ALLTIM.TIM\" }",
]

# From the code above.
SLOT_SECTORS = 9
SLOT_SIZE = SLOT_SECTORS * SECTOR_SIZE  # 0x4800
FILE_SIZE = 0x32A000
TYPE_COUNT = 0xB4  # loaders reject digimonType >= 0xB4
MAX_WIDTH, MAX_HEIGHT = 256, 128  # one VRAM slot: half a 4bpp texture page
MAX_CLUT_ROWS = 16
# Types whose model file is not on the disc (lower-case names in PTR_DIGIMON_FILE_NAMES).
KNOWN_MISSING_MODELS = {62: "wEAG", 114: "tAKA"}


def _vram(page: int, off_x: int, off_y: int, clut_page: int) -> dict:
    """VRAM position computed by uploadModelTexture for a model slot."""
    return {
        "image": {"x": ((page % 16) << 6) + off_x, "y": ((page // 16) << 8) + off_y},
        "clut": {"x": (clut_page & 0x3F) << 4, "y": clut_page >> 6},
    }


RUNTIME_SLOTS = {
    "tamer": _vram(0x15, 0, 0, 0x7A00),
    "partner": _vram(0x15, 0, 0x80, 0x7A01),
    **{f"npc{k}": _vram(k // 2 + 0x16, 0, (k % 2) << 7, (k + 2) | 0x7A00) for k in range(5)},
}


def convert(input_root, output_root) -> AssetWriter:
    src = SourceFile.open(input_root, SOURCE_PATH)
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()

    out.check("file size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, f"0x{src.size:X}")
    out.check("file is a whole number of slots", src.size % SLOT_SIZE == 0, f"0x{src.size:X} / 0x{SLOT_SIZE:X}")
    count = src.size // SLOT_SIZE
    out.check(f"{TYPE_COUNT} slots (one per digimon type)", count == TYPE_COUNT == len(DIGIMON_TYPES), str(count))

    for type_id in range(min(count, len(DIGIMON_TYPES))):
        file_name, string_id, display_name = DIGIMON_TYPES[type_id]
        offset = type_id * SLOT_SIZE
        label = f"type {type_id} {file_name}"
        tim = timfmt.try_parse(src.data, offset)
        if not out.check(f"{label}: valid TIM", tim is not None, f"at 0x{offset:X}"):
            continue
        out.check(f"{label}: fits in slot", tim.size <= SLOT_SIZE, f"0x{tim.size:X}")
        out.check(f"{label}: 4bpp, 16-colour CLUT", tim.bpp == 4 and tim.clut.width == 16,
                  f"{tim.bpp}bpp, clut width {tim.clut.width}")
        out.check(f"{label}: fits a model VRAM slot", tim.width <= MAX_WIDTH and tim.height <= MAX_HEIGHT
                  and tim.clut.height <= MAX_CLUT_ROWS, f"{tim.width}x{tim.height}, {tim.clut.height} palettes")
        padding = src.data[offset + tim.size:offset + SLOT_SIZE]
        out.check(f"{label}: slot padding is zero", not any(padding), f"{len(padding)} bytes")

        model = mmd_path(type_id)
        model_exists = (input_root / model).exists()
        expected_missing = type_id in KNOWN_MISSING_MODELS
        out.check(f"{label}: model file presence", model_exists != expected_missing,
                  f"{model} {'exists' if model_exists else 'missing'}")

        span = src.span(offset, tim.size)
        out.write_tim(f"{type_id:03d}_{file_name}", span, tim, {
            "digimon": {
                "type": type_id,
                "file_name": file_name,
                "string_id": string_id,
                "name": display_name,
                "model": model if model_exists else None,
            },
            "slot": {"offset": offset, "size": SLOT_SIZE, "sector": type_id * SLOT_SECTORS, "sectors": SLOT_SECTORS},
            "loader": "loadDigimonTexture(type) / loadMMDAsync(type)",
            # The game ignores the TIM's own VRAM position (see "vram"); uploadModelTexture
            # puts it in the model slot's area, listed in manifest.json "runtime_slots".
            "vram_position_overridden": True,
        })

    out.finish([src], {"runtime_slots": RUNTIME_SLOTS})
    return out
