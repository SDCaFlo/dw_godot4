"""Shared converter for files made of back-to-back TIMs (no slots, no padding between them).

The game loads every TIM of such a file at the VRAM position in its own header, so the
header placement is meaningful here (unlike ALLTIM.TIM). Each family module describes its
entries with `Entry` and calls `convert_stacked`. Spec: specs/stacked_tim.md.
"""

from dataclasses import dataclass, field

from ..assets import AssetWriter
from ..formats import tim as timfmt
from ..source import SourceFile


@dataclass(frozen=True)
class Entry:
    name: str  # output base name (without index prefix)
    description: str
    image: tuple  # expected VRAM (x, y) of the image, from the TIM header
    clut: tuple  # expected VRAM (x, y) of the CLUT
    code_refs: tuple = ()  # code that draws from this VRAM area; empty if none found
    identified_by: str = "visual"  # "code" when code_refs confirm the use, else "visual" (guess from the image)
    duplicate_of: str = None  # standalone disc file with identical bytes


@dataclass
class StackedFile:
    family: str
    source_path: str
    spec: str
    file_size: int  # from FILE_OFFSET_TABLE
    entries: list
    code_refs: list = field(default_factory=list)


def loader_step(tim: timfmt.Tim) -> int:
    """Bytes the game skips per TIM: 4 (id) + 16 (flag + image header) + pixels [+ 12 + CLUT]."""
    step = 4 + 16 + tim.stride * tim.height * 2
    if tim.clut:
        step += 12 + tim.clut.width * tim.clut.height * 2
    return step


def _overlaps(a: dict, b: dict) -> bool:
    return a["x"] < b["x"] + b["w"] and b["x"] < a["x"] + a["w"] and a["y"] < b["y"] + b["h"] and b["y"] < a["y"] + a["h"]


def convert_stacked(desc: StackedFile, input_root, output_root) -> AssetWriter:
    src = SourceFile.open(input_root, desc.source_path)
    out = AssetWriter(output_root, desc.family, desc.spec, desc.code_refs)
    out.reset()

    out.check("file size matches FILE_OFFSET_TABLE", src.size == desc.file_size, f"0x{src.size:X}")

    # Walk the file the way loadStackedTIMFile does: while the next word is 0x10.
    tims, offset = [], 0
    while offset + 4 <= src.size and int.from_bytes(src.data[offset:offset + 4], "little") == timfmt.TIM_ID:
        tim = timfmt.try_parse(src.data, offset)
        if not out.check(f"TIM {len(tims)}: valid", tim is not None, f"at 0x{offset:X}"):
            break
        out.check(f"TIM {len(tims)}: packed (loader step == TIM size)", loader_step(tim) == tim.size,
                  f"step 0x{loader_step(tim):X}, size 0x{tim.size:X}")
        tims.append(tim)
        offset += loader_step(tim)
    out.check(f"{len(desc.entries)} TIMs", len(tims) == len(desc.entries), str(len(tims)))
    out.check("rest of file is zero", not any(src.data[offset:]), f"{src.size - offset} bytes after 0x{offset:X}")

    rects = []
    for index, (tim, entry) in enumerate(zip(tims, desc.entries)):
        label = f"TIM {index} {entry.name}"
        vram = tim.vram_info()
        out.check(f"{label}: image position", (tim.x, tim.y) == entry.image, f"({tim.x}, {tim.y})")
        out.check(f"{label}: CLUT position", tim.clut is not None and (tim.clut.x, tim.clut.y) == entry.clut,
                  f"({tim.clut.x}, {tim.clut.y})" if tim.clut else "no CLUT")
        span = src.span(tim.offset, tim.size)
        if entry.duplicate_of:
            other = (input_root / entry.duplicate_of).read_bytes()
            out.check(f"{label}: identical to {entry.duplicate_of}", other == span.data, f"{len(other)} bytes")

        rects.append((label, vram["image_rect"]))
        if "clut_rect" in vram:
            rects.append((f"{label} CLUT", vram["clut_rect"]))

        out.write_tim(f"{index:02d}_{entry.name}", span, tim, {
            "entry": {
                "index": index,
                "name": entry.name,
                "description": entry.description,
                "identified_by": entry.identified_by,
                "code_refs": list(entry.code_refs),
                "duplicate_of": entry.duplicate_of,
            },
            "loader": "loadStackedTIMFile(path)",
        })

    # Everything in the file is in VRAM at the same time, so no two rects may overlap.
    clashes = [f"{a} / {b}" for i, (a, ra) in enumerate(rects) for b, rb in rects[i + 1:] if _overlaps(ra, rb)]
    out.check("no VRAM overlap between TIMs of this file", not clashes, "; ".join(clashes))

    out.finish([src])
    return out
