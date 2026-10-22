"""Standalone .TMD model files (66). Spec: specs/tmd.md.

Each model is exported to glTF. Its textures are built by loading the texture files the game
has in VRAM when the model is drawn (`textures`), then reading each polygon's texture page and
CLUT like the GPU. Models drawn with map textures have `textures = None` until maps are ported.
"""

from dataclasses import dataclass

from ..assets import AssetWriter
from ..formats import tim as timfmt
from ..formats import tmd as tmdfmt
from ..formats.vram import Vram
from ..source import SourceFile

NAME = "tmd_files"
SOURCE_PATH = "**/*.TMD (66 files)"
SPEC = "specs/tmd.md"
CODE_REFS = [
    "dw_decomp/src/main/map_object.c:295 loadStaticTMD: readFile, GsMapModelingData, GsLinkObject4 (no texture patching)",
    "dw_decomp/src/main/map_object.c:309 loadDoors: \"\\\\DOOR\\\\DOOR\" + 2 digits + \".TMD\"",
    "dw_decomp/src/main/main.c:3434 ETCDAT/ETCTIM.BIN is loaded for the whole field session",
]

ETCTIM = ("ETCDAT/ETCTIM.BIN",)
STDTIM = ("STDDAT/STDTIM.BIN",)
MAP = None  # drawn with map textures (texture page 640/704/512,0 and map CLUT rows 484-486)


@dataclass(frozen=True)
class TmdFile:
    path: str
    description: str
    code_refs: tuple
    textures: tuple  # files loaded into VRAM (all TIMs in each, at their header positions), or MAP
    texture_note: str = ""


DOORS = [TmdFile(f"DOOR/DOOR{i:02d}.TMD", f"Door model {i:02d}",
                 ("dw_decomp/src/main/map_object.c:309 loadDoors",), MAP, "map textures")
         for i in range(33)]

FILES = DOORS + [
    TmdFile("ETCDAT/DEFEFF.TMD", "Default effect meshes (smoke)", (), ETCTIM, "DEFEFF.TIM part of ETCTIM.BIN"),
    TmdFile("ETCDAT/EX.TMD", "Effect meshes", ("dw_decomp/src/main/efe_table.c:10 EFEX_PATH_ARRAY",), ("ETCDAT/EX.TIM",)),
    TmdFile("ETCDAT/FEEL_EF.TMD", "Feeling effect mesh (untextured)", ("dw_decomp/src/main/efe_table.c:8 EFEX_PATH_ARRAY",), ()),
    TmdFile("ETCDAT/KARRING.TMD", "Curling (KAR) rink", ("dw_decomp/src/kar/kar.c:786 readFile(KAR_D_8005ABA4)",), MAP,
            "texture page 640,0 / CLUT row 486, loaded by the KAR overlay or map"),
    TmdFile("ETCDAT/SAO.TMD", "Fishing rod", ("dw_decomp/src/fish/fish.c:4604 FISH_loadTMDModel(FISH_PATH_ROD_MODEL)",),
            ("ETCDAT/FISHING.TIM",), "FISHING2.TIM has the same layout"),
    TmdFile("ETCDAT/SEA.TMD", "Seadramon shadow in the water (5 flat semi-transparent segments, fishing)", ("dw_decomp/src/fish/fish.c:2009 FISH_loadTMDModel(FISH_PATH_SEADRAMON_MODEL)",),
            ("ETCDAT/FISHING.TIM",), "FISHING2.TIM has the same layout"),
    TmdFile("ETCDAT/TAMA.TMD", "Digimon eggs (24 objects)", ("dw_decomp/src/dooa/dooa.c:548 readFile(DOOA_EGG_TMD_PATH)",),
            ("ETCDAT/TAMA.TIM",), "TAMA.TIM loaded just before, dooa.c:536"),
    TmdFile("ETCHI/BOSS_EFE.TMD", "Boss effect mesh", ("dw_decomp/src/main/script_interp.c:1842 addFileReadRequestPath",), MAP,
            "texture page 640,0 / CLUT row 486"),
    TmdFile("ETCHI/MAHI.TMD", "Paralysis effect mesh", (), ETCTIM, "BI_IN.TIM part of ETCTIM.BIN"),
    TmdFile("ETCNA/ABOX.TMD", "Angemon pedestal", ("dw_decomp/src/main/map_object.c:781 loadStaticTMD(ANGEMON_PEDESTAL_TMD)",), MAP,
            "map textures"),
    TmdFile("ETCNA/BIGBOX.TMD", "Big box", ("dw_decomp/src/main/map_object.c:672 readFile(BIG_BOX_TMD)",), MAP, "map textures"),
    TmdFile("ETCNA/DOOR.TMD", "Door model (same layout as DOOR/DOOR00.TMD)", (), MAP, "map textures"),
    TmdFile("ETCNA/DOSYA.TMD", "Dirt cart", ("dw_decomp/src/main/map_object.c:425 loadStaticTMD(DIRT_CART_TMD)",), ETCTIM,
            "FEEL_EF.TIM part of ETCTIM.BIN"),
    TmdFile("ETCNA/GAND.TMD", "Gearbox", ("dw_decomp/src/main/map_object.c:756 loadStaticTMD(GEARBOX_TMD)",), MAP, "map textures"),
    TmdFile("ETCNA/HAKO.TMD", "Dirt cart box", ("dw_decomp/src/main/map_object.c:427 loadStaticTMD(DIRT_CART_BOX_TMD)",), ETCTIM,
            "FEEL_EF.TIM part of ETCTIM.BIN"),
    TmdFile("ETCNA/IWA.TMD", "Boulder", ("dw_decomp/src/main/map_object.c:622 loadStaticTMD(BOULDER_TMD)",), ("ETCNA/IWA1.TIM",),
            "IWA1.TIM loaded right after, map_object.c:624"),
    TmdFile("ETCNA/MEDAL.TMD", "Medal", ("dw_decomp/src/main/map_object.c:658 loadStaticTMD(MEDAL_TMD)",), ETCTIM,
            "SBOY.TIM part of ETCTIM.BIN"),
    TmdFile("ETCNA/SMABOX.TMD", "Small box", ("dw_decomp/src/main/map_object.c:673 readFile(SMALL_BOX_TMD)",), MAP, "map textures"),
    TmdFile("ETCNA/TAKA.TMD", "Item box (computer)", ("dw_decomp/src/main/map_object.c:450 readFile(CHEST_TMD)",), ETCTIM,
            "FEEL_EF.TIM part of ETCTIM.BIN; ETCNA/TAKA.TIM covers the same area but has no loader"),
    TmdFile("ETCNA/TRY.TMD", "Training poop", ("dw_decomp/src/main/map_object.c:818 loadStaticTMD(TRAINING_POOP_TMD)",), MAP,
            "map textures"),
    TmdFile("ETCNA/T_YAMA.TMD", "Dirt pile", ("dw_decomp/src/main/map_object.c:1215 loadStaticTMD(DIRT_PILE_TMD)",), MAP,
            "map textures"),
    TmdFile("ETCNA/UNTI.TMD", "Poop", ("dw_decomp/src/main/partner_impl.c:438 readFile(MAIN_D_801225AC)",), ETCTIM,
            "SYSTEM_W.TIM part of ETCTIM.BIN"),
    TmdFile("ETCNA/WARP.TMD", "Warp crystal", ("dw_decomp/src/main/map_object.c:507 readFile(WARP_CRYSTAL_TMD)",), MAP,
            "texture page 384,0 / CLUT row 486"),
    TmdFile("STDDAT/1P2PWIN.TMD", "VS result: 1P / 2P WIN", ("dw_decomp/src/vs/vs_hud.c:1435 readFile(VS_PATH_STDDAT_1P2PWIN_TMD)",),
            STDTIM),
    TmdFile("STDDAT/B_DAI.TMD", "Arena B podium", ("dw_decomp/src/std/std_hud.c:1350 readFile(STD_PATH_STDDAT_B_DAI_TMD)",),
            ("STDDAT/B_TOGI.TIM",)),
    TmdFile("STDDAT/B_TOGI.TMD", "Arena B", ("dw_decomp/src/std/std_main.c:1328 STD_ARENA_MODELS[1]",
                                            "dw_decomp/src/vs/vs_scene.c:1041 VS_ARENA_MODELS[1]"), ("STDDAT/B_TOGI.TIM",)),
    TmdFile("STDDAT/CHAMP.TMD", "Tournament result: CHAMPION", ("dw_decomp/src/std/std_hud.c:1295 readFile(STD_PATH_STDDAT_CHAMP_TMD)",),
            STDTIM),
    TmdFile("STDDAT/DRAW.TMD", "Result: DRAW / VS", ("dw_decomp/src/std/std_hud.c:1144 readFile(STD_VERSUS_MODEL_PATH)",
                                                  "dw_decomp/src/vs/vs_hud.c:436 VS_PATH_STDDAT_DRAW_TMD"), STDTIM),
    TmdFile("STDDAT/E_DAI.TMD", "Arena E podium", (), ("STDDAT/E_TOGI.TIM",), "no loader found; UVs fit E_TOGI.TIM"),
    TmdFile("STDDAT/E_TOGI.TMD", "Arena E (VS mode)", ("dw_decomp/src/vs/vs_scene.c:1042 VS_ARENA_MODELS[2]",), ("STDDAT/E_TOGI.TIM",)),
    TmdFile("STDDAT/T_DAI.TMD", "Arena T podium", ("dw_decomp/src/std/std_hud.c:1352 readFile(STD_PATH_STDDAT_T_DAI_TMD)",),
            ("STDDAT/T_TOGI.TIM",)),
    TmdFile("STDDAT/T_TOGI.TMD", "Arena T", ("dw_decomp/src/std/std_main.c:1327 STD_ARENA_MODELS[0]",
                                            "dw_decomp/src/vs/vs_scene.c:1040 VS_ARENA_MODELS[0]"), ("STDDAT/T_TOGI.TIM",)),
    TmdFile("STDDAT/WIN_LOSE.TMD", "Tournament result: WIN / LOSE", ("dw_decomp/src/std/std_hud.c:1250 readFile(STD_PATH_STDDAT_WIN_LOSE_TMD)",),
            STDTIM),
]


def _vram(input_root, files: tuple) -> Vram:
    vram = Vram()
    for path in files:
        src = SourceFile.open(input_root, path)
        offset = 0
        while offset < src.size and (tim := timfmt.try_parse(src.data, offset)) is not None:
            vram.load_tim(tim, f"{path}@0x{offset:X}")
            offset += tim.size
    return vram


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()

    on_disc = sorted(p.relative_to(input_root).as_posix() for p in input_root.rglob("*.TMD"))
    listed = sorted(f.path for f in FILES)
    out.check("every .TMD on disc is listed", on_disc == listed,
              f"unlisted: {sorted(set(on_disc) - set(listed))}, missing: {sorted(set(listed) - set(on_disc))}")

    sources = []
    for entry in sorted(FILES, key=lambda f: f.path):
        src = SourceFile.open(input_root, entry.path)
        sources.append(src)
        label = entry.path
        try:
            tmd = tmdfmt.parse(src.data)
        except tmdfmt.TmdError as e:
            out.check(f"{label}: valid TMD (every packet layout matches its ilen)", False, str(e))
            continue
        out.check(f"{label}: valid TMD (every packet layout matches its ilen)", True)
        out.check(f"{label}: blocks end exactly at file end", tmd.end == src.size, f"end 0x{tmd.end:X}, size 0x{src.size:X}")
        out.check(f"{label}: vertex/normal pad words are zero", all(o.nonzero_pads == 0 for o in tmd.objects), "")

        textured = any(p.textured for o in tmd.objects for p in o.primitives)
        vram = _vram(input_root, entry.textures) if entry.textures else None
        record = out.write_tmd(entry.path.rsplit(".", 1)[0], src.span(0, tmd.size), tmd, vram, {
            "model": {
                "description": entry.description,
                "code_refs": list(entry.code_refs),
                "texture_files": list(entry.textures) if entry.textures is not None else None,
                "texture_note": entry.texture_note,
                "textures_bound": vram is not None or not textured,
            },
        })
        if vram is not None:
            missing = [t["missing_texels_in_uv_box"] for t in record["textures"]]
            out.check(f"{label}: texture pages fully covered by {', '.join(entry.textures)}", not any(missing), str(missing))

    out.finish(sources)
    return out
