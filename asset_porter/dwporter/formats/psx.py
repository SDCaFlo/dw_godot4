"""PSX GPU helpers: 15-bit colours and VRAM addressing."""

VRAM_WIDTH = 1024  # in 16-bit units
VRAM_HEIGHT = 512


def expand5(value: int) -> int:
    """5-bit channel to 8-bit, full range. Reversible with `>> 3`."""
    return (value << 3) | (value >> 2)


def color_to_rgba(color: int) -> tuple:
    """15-bit BGR + STP colour to RGBA.

    0x0000 is the hardware's "transparent" colour, so it gets alpha 0. Every other
    value is opaque; the STP bit (bit 15) is not alpha, it selects per-polygon
    semi-transparency, and is kept separately by the callers.
    """
    r = expand5(color & 0x1F)
    g = expand5((color >> 5) & 0x1F)
    b = expand5((color >> 10) & 0x1F)
    a = 0 if color == 0 else 255
    return r, g, b, a


def get_clut(x: int, y: int) -> int:
    """libgpu GetClut(x, y)."""
    return (y << 6) | ((x >> 4) & 0x3F)


def get_tpage(tp: int, abr: int, x: int, y: int) -> int:
    """libgpu GetTPage(tp, abr, x, y). tp: 0 = 4bpp, 1 = 8bpp, 2 = 16bpp."""
    return ((tp & 0x3) << 7) | ((abr & 0x3) << 5) | ((y & 0x100) >> 4) | ((x & 0x3FF) >> 6)
