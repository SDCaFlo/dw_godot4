"""TIM texture format.

Layout (all little-endian):
    u32 id          0x10 (low byte), version and reserved bytes zero
    u32 flag        bits 0-2 pmode (0=4bpp, 1=8bpp, 2=16bpp, 3=24bpp), bit 3 has CLUT
    [CLUT block]    u32 size (incl. this header), u16 x, u16 y, u16 w, u16 h, w*h u16 colours
    image block     u32 size (incl. this header), u16 x, u16 y, u16 stride (16-bit units), u16 h, data

Coordinates are in VRAM 16-bit units. Reference: PSXPrev Common/Parsers/TIMParser.cs.
"""

import struct
from dataclasses import dataclass
from typing import Optional

from . import psx

TIM_ID = 0x10
MAX_RESOLUTION = 1024


class TimError(ValueError):
    pass


@dataclass(frozen=True)
class Clut:
    block_size: int
    x: int
    y: int
    width: int
    height: int
    palettes: tuple  # `height` tuples of `width` raw u16 colours


@dataclass(frozen=True)
class Tim:
    offset: int  # within the source buffer
    flag: int
    bpp: int
    clut: Optional[Clut]
    image_block_size: int
    x: int
    y: int
    stride: int  # 16-bit units per row
    height: int
    pixels: bytes  # raw image data, stride * 2 * height bytes

    @property
    def pmode(self) -> int:
        return self.flag & 0x7

    @property
    def width(self) -> int:
        return self.stride * 16 // self.bpp

    @property
    def size(self) -> int:
        return 8 + (self.clut.block_size if self.clut else 0) + self.image_block_size

    def vram_info(self) -> dict:
        """Where the texture lands in VRAM and the GPU ids the game code uses for it."""
        info = {
            "image_rect": {"x": self.x, "y": self.y, "w": self.stride, "h": self.height},
            "texture_page": {"x": self.x // 64, "y": self.y // 256},
            "uv_origin": {"u": (self.x % 64) * 16 // self.bpp, "v": self.y % 256},
        }
        tp = {4: 0, 8: 1, 16: 2}.get(self.bpp)
        if tp is not None:
            info["tpage"] = psx.get_tpage(tp, 0, self.x, self.y)
        if self.clut:
            info["clut_rect"] = {"x": self.clut.x, "y": self.clut.y, "w": self.clut.width, "h": self.clut.height}
            info["clut_ids"] = [psx.get_clut(self.clut.x, self.clut.y + i) for i in range(self.clut.height)]
        return info

    def header_info(self) -> dict:
        info = {
            "flag": self.flag,
            "pmode": self.pmode,
            "bpp": self.bpp,
            "width": self.width,
            "height": self.height,
            "stride": self.stride,
            "size": self.size,
            "image_block_size": self.image_block_size,
        }
        if self.clut:
            info["clut"] = {
                "block_size": self.clut.block_size,
                "width": self.clut.width,
                "height": self.clut.height,
                # Raw 15-bit colours, STP bit included: the lossless source of every palette.
                "palettes": [list(p) for p in self.clut.palettes],
            }
        return info


def _bpp(pmode: int, clut_width: Optional[int]) -> int:
    # Some files claim a direct-colour pmode but still carry a CLUT (noted in PSXPrev / jpsxdec).
    if clut_width is not None and pmode == 2:
        return 4 if clut_width < 256 else 8
    if clut_width is not None and pmode == 3:
        return 8
    return {0: 4, 1: 8, 2: 16, 3: 24}[pmode]


def parse(data: bytes, offset: int = 0, strict: bool = True) -> Tim:
    """Parse a TIM starting at `offset`. Raises TimError if it is not a valid TIM."""
    end = len(data)

    def read(fmt: str, pos: int) -> tuple:
        if pos + struct.calcsize(fmt) > end:
            raise TimError("truncated")
        return struct.unpack_from(fmt, data, pos)

    header, flag = read("<II", offset)
    if header & 0xFF != TIM_ID or (header >> 8) & 0xFF != 0:
        raise TimError("bad id")
    if strict and header >> 16 != 0:
        raise TimError("reserved bits set")
    pmode = flag & 0x7
    if pmode > 3:
        raise TimError(f"unsupported pmode {pmode}")
    if strict and flag & ~0xF:
        raise TimError("flag high bits set")

    pos = offset + 8
    clut = None
    if flag & 0x8:
        size, cx, cy, cw, ch = read("<IHHHH", pos)
        if not (1 <= cw <= 256 and 1 <= ch <= 256) or size < 12 + cw * ch * 2:
            raise TimError("bad CLUT block")
        if cx + cw > psx.VRAM_WIDTH or cy + ch > psx.VRAM_HEIGHT:
            raise TimError("CLUT outside VRAM")
        colors = read(f"<{cw * ch}H", pos + 12)
        palettes = tuple(tuple(colors[i * cw:(i + 1) * cw]) for i in range(ch))
        clut = Clut(size, cx, cy, cw, ch, palettes)
        pos += size

    bpp = _bpp(pmode, clut.width if clut else None)
    if bpp <= 8 and clut is None:
        raise TimError("indexed TIM without CLUT")

    size, x, y, stride, height = read("<IHHHH", pos)
    if stride == 0 or height == 0 or size < 12 + stride * height * 2:
        raise TimError("bad image block")
    width = stride * 16 // bpp
    if width > MAX_RESOLUTION or height > MAX_RESOLUTION:
        raise TimError("image too large")
    if x + stride > psx.VRAM_WIDTH or y + height > psx.VRAM_HEIGHT:
        raise TimError("image outside VRAM")
    data_start = pos + 12
    if data_start + stride * height * 2 > end:
        raise TimError("truncated image data")
    pixels = bytes(data[data_start:data_start + stride * height * 2])

    return Tim(offset, flag, bpp, clut, size, x, y, stride, height, pixels)


def try_parse(data: bytes, offset: int = 0, strict: bool = True) -> Optional[Tim]:
    try:
        return parse(data, offset, strict)
    except TimError:
        return None


def scan(data: bytes, align: int = 4, strict: bool = True, skip_matches: bool = True):
    """Yield every TIM found in `data`, like PSXPrev's scanner (only at `align`ed offsets)."""
    pos = 0
    magic = b"\x10\x00\x00\x00" if strict else b"\x10\x00"
    while True:
        pos = data.find(magic, pos)
        if pos < 0:
            return
        if pos % align:
            pos += 1
            continue
        tim = try_parse(data, pos, strict)
        if tim is None:
            pos += 1
            continue
        yield tim
        pos = pos + tim.size if skip_matches else pos + 1


# Pixel decoding

def indices(tim: Tim) -> bytes:
    """Palette index per pixel (4/8bpp), row-major, one byte each."""
    row_bytes = tim.stride * 2
    out = bytearray()
    for y in range(tim.height):
        row = tim.pixels[y * row_bytes:(y + 1) * row_bytes]
        if tim.bpp == 4:
            for b in row:  # low nibble is the left pixel
                out.append(b & 0xF)
                out.append(b >> 4)
        elif tim.bpp == 8:
            out += row
        else:
            raise TimError("not an indexed TIM")
    return bytes(out)


def palette_rgba(tim: Tim, index: int = 0) -> list:
    size = 16 if tim.bpp == 4 else 256
    colors = list(tim.clut.palettes[index])[:size]
    colors += [0] * (size - len(colors))  # missing entries are transparent black, as in PSXPrev
    return [psx.color_to_rgba(c) for c in colors]


def direct_rgba(tim: Tim) -> tuple:
    """RGBA bytes for 16/24bpp TIMs, plus an STP mask (one byte per pixel, 255 = STP set) or None."""
    out = bytearray()
    stp = bytearray()
    row_bytes = tim.stride * 2
    for y in range(tim.height):
        row = tim.pixels[y * row_bytes:(y + 1) * row_bytes]
        if tim.bpp == 16:
            for (color,) in struct.iter_unpack("<H", row):
                out += bytes(psx.color_to_rgba(color))
                stp.append(255 if color & 0x8000 else 0)
        elif tim.bpp == 24:
            for i in range(tim.width):
                out += row[i * 3:i * 3 + 3] + b"\xff"
        else:
            raise TimError("not a direct-colour TIM")
    has_stp = tim.bpp == 16 and any(stp)
    return bytes(out), (bytes(stp) if has_stp else None)
