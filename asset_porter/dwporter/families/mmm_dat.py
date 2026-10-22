"""MMM.DAT: 27 MB of zeros that no code reads (disc filler). Spec: specs/sound.md ("MMM.DAT").

Nothing to convert; the family only proves the file is empty, so its identity is recorded and the
file can be rebuilt from its size.
"""

from ..assets import AssetWriter
from ..paths import SECTOR_SIZE
from ..source import SourceFile

NAME = "mmm_dat"
SOURCE_PATH = "MMM.DAT"
SPEC = "specs/sound.md"
CODE_REFS = [
    "dw_decomp/src/main/file_table_us.c:824 { 0x244bc, 0x1a5e000, \"MMM.DAT\" } (listed, never opened: no reference in src/)",
]
FILE_SIZE = 0x1A5E000


def convert(input_root, output_root) -> AssetWriter:
    out = AssetWriter(output_root, NAME, SPEC, CODE_REFS)
    out.reset()
    src = SourceFile.open(input_root, SOURCE_PATH)
    out.check("size matches FILE_OFFSET_TABLE", src.size == FILE_SIZE, f"0x{src.size:X}")
    nonzero = next((i for i in range(0, src.size, SECTOR_SIZE) if any(src.data[i:i + SECTOR_SIZE])), None)
    out.check("every byte is zero (disc filler)", nonzero is None,
              "all zero" if nonzero is None else f"first non-zero sector at 0x{nonzero:X}")
    out.finish([src], {"content": {"sectors": src.size // SECTOR_SIZE, "all_zero": nonzero is None,
                                   "rebuild": "bytes(size)"}})
    return out
