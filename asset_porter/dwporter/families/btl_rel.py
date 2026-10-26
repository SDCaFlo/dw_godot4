"""BTL_REL.BIN: the battle overlay's embedded texture and models (finisher aura, confusion, stun, buff).
Spec: specs/btl_rel.md."""

from ..assets import AssetWriter
from ..formats import tim as timfmt
from ..formats import tmd as tmdfmt
from ..formats.vram import Vram
from ..source import SourceFile

NAME = "btl_rel"
SOURCE_PATH = "BTL_REL.BIN"
SPEC = "specs/btl_rel.md"
CODE_REFS = [
    "dw_decomp/config/us/btl.yaml segments texture 0x0, model_0 0xD20, model_1 0x1D58, model_2 0x2220, model_3 0x2848",
    "dw_decomp/src/main/btl.c:23-27 BTL_FINISHER_TIM / _MODEL, BTL_CONFUSION_MODEL, BTL_STUN_MODEL, BTL_BUFF_MODEL",
    "dw_decomp/src/main/btl.c:427-450 loadBattleData: the initializers",
    "dw_decomp/src/btl/battle_effect.c:5957 BTL_initializeFinisherAuraModel (LoadImage at the TIM's own VRAM place)",
    "dw_decomp/src/btl/battle_effect.c:5534 BTL_initializeConfusionEffect, :5582 BTL_initializeStunEffect",
    "dw_decomp/src/main/buff_model.c initializeBuffModel",
    "dw_decomp/src/main/main.c:3434 ETCDAT/ETCTIM.BIN is in VRAM for the whole field session",
]

FILE_SIZE = 0x2349C                       # FILE_OFFSET_TABLE (file_table_us.c:807)
TEXTURE_OFFSET = 0x0
MODELS = [  # (offset, name, the C symbol, what it is)
    (0xD20, "finisher_aura", "BTL_FINISHER_MODEL", "the aura around a fighter winding up a finisher (5 objects)"),
    (0x1D58, "confusion", "BTL_CONFUSION_MODEL", "the model circling a confused fighter"),
    (0x2220, "stun", "BTL_STUN_MODEL", "the stars over a stunned fighter"),
    (0x2848, "buff", "BTL_BUFF_MODEL", "the buff rings / disk model (initializeBuffModel)"),
]
VRAM_FILES = ("ETCDAT/ETCTIM.BIN",)       # the system textures in VRAM during a battle


def _vram(input_root, overlay_tim, label) -> Vram:
    vram = Vram()
    for path in VRAM_FILES:
        src = SourceFile.open(input_root, path)
        offset = 0
        while offset < src.size and (tim := timfmt.try_parse(src.data, offset)) is not None:
            vram.load_tim(tim, f"{path}@0x{offset:X}")
            offset += tim.size
    vram.load_tim(overlay_tim, label)     # loaded last, as the battle does
    return vram


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    src = SourceFile.open(input_root, SOURCE_PATH)
    out.check("size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, f"0x{src.size:X}")

    tim = timfmt.try_parse(src.data, TEXTURE_OFFSET)
    if not out.check("a TIM at 0x0 (segment `texture`)", tim is not None):
        out.finish([src])
        return out
    out.check("the TIM ends before the first model", TEXTURE_OFFSET + tim.size <= MODELS[0][0],
              f"end 0x{TEXTURE_OFFSET + tim.size:X}")
    out.write_tim("texture", src.span(TEXTURE_OFFSET, tim.size), tim, {
        "runtime_placement": {"loader": "BTL_initializeFinisherAuraModel",
                              "note": "LoadImage at the TIM's own VRAM rect and CLUT"}})
    vram = _vram(input_root, tim, f"{SOURCE_PATH}@0x{TEXTURE_OFFSET:X}")

    ends = [m[0] for m in MODELS[1:]] + [None]
    for (offset, name, symbol, description), end in zip(MODELS, ends):
        label = f"{name} (0x{offset:X})"
        try:
            tmd = tmdfmt.parse(src.data, offset)
        except tmdfmt.TmdError as e:
            out.check(f"{label}: valid TMD", False, str(e))
            continue
        out.check(f"{label}: valid TMD", True, f"{len(tmd.objects)} objects")
        if end is not None:
            out.check(f"{label}: ends before the next segment", offset + tmd.size <= end,
                      f"end 0x{offset + tmd.size:X}, next 0x{end:X}")
        record = out.write_tmd(name, src.span(offset, tmd.size), tmd, vram, {
            "model": {"symbol": symbol, "description": description,
                      "texture_files": list(VRAM_FILES) + [f"{SOURCE_PATH}@0x0"]}})
        missing = [t["missing_texels_in_uv_box"] for t in record["textures"]]
        out.check(f"{label}: texture pages covered by ETCTIM.BIN and the overlay TIM", not any(missing), str(missing))

    out.finish([src])
    return out
