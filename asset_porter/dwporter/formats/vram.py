"""A copy of PSX VRAM (1024x512 16-bit words) for building textures the way the GPU samples them.

Models do not point at texture files: each polygon names a texture page (TSB) and a CLUT (CBA)
and gives UVs inside the page. To turn that into a normal texture we load the TIMs the game
would have loaded (at their VRAM positions) and read the page through the CLUT, like the GPU.
"""

from . import psx

PAGE_SIZE = 256  # texture page in pixels (u, v range)


class Vram:
    def __init__(self):
        self.words = [0] * (psx.VRAM_WIDTH * psx.VRAM_HEIGHT)
        self.loaded = [False] * (psx.VRAM_WIDTH * psx.VRAM_HEIGHT)
        self.sources = []  # (label, rect) in load order

    def _write(self, x: int, y: int, w: int, h: int, values) -> None:
        it = iter(values)
        for row in range(h):
            base = (y + row) * psx.VRAM_WIDTH + x
            for col in range(w):
                self.words[base + col] = next(it)
                self.loaded[base + col] = True

    def load_tim(self, tim, label: str) -> None:
        """Upload a parsed TIM at its header position (LoadImage of image and CLUT)."""
        import struct

        words = struct.unpack(f"<{len(tim.pixels) // 2}H", tim.pixels)
        self._write(tim.x, tim.y, tim.stride, tim.height, words)
        self.sources.append((label, {"x": tim.x, "y": tim.y, "w": tim.stride, "h": tim.height}))
        if tim.clut:
            colors = [c for p in tim.clut.palettes for c in p]
            self._write(tim.clut.x, tim.clut.y, tim.clut.width, tim.clut.height, colors)
            self.sources.append((f"{label} CLUT", {"x": tim.clut.x, "y": tim.clut.y,
                                                  "w": tim.clut.width, "h": tim.clut.height}))

    def word(self, x: int, y: int):
        if 0 <= x < psx.VRAM_WIDTH and 0 <= y < psx.VRAM_HEIGHT:
            i = y * psx.VRAM_WIDTH + x
            return self.words[i], self.loaded[i]
        return 0, False

    def sample_page(self, page_x: int, page_y: int, bpp: int, clut_x: int = 0, clut_y: int = 0):
        """Return (rgba, loaded) for a 256x256 texture page read through a CLUT.

        `rgba` has 4 bytes per texel; `loaded` has 1 byte per texel, 0 where the texel or its CLUT
        entry reads VRAM that nothing was loaded into (those texels are transparent), so callers
        can tell a complete texture from a partial one.
        """
        out = bytearray(PAGE_SIZE * PAGE_SIZE * 4)
        loaded = bytearray(PAGE_SIZE * PAGE_SIZE)
        for v in range(PAGE_SIZE):
            for u in range(PAGE_SIZE):
                if bpp == 4:
                    word, ok = self.word(page_x + u // 4, page_y + v)
                    color, ok2 = self.word(clut_x + ((word >> ((u % 4) * 4)) & 0xF), clut_y)
                elif bpp == 8:
                    word, ok = self.word(page_x + u // 2, page_y + v)
                    color, ok2 = self.word(clut_x + ((word >> ((u % 2) * 8)) & 0xFF), clut_y)
                else:
                    color, ok = self.word(page_x + u, page_y + v)
                    ok2 = True
                if ok and ok2:
                    i = v * PAGE_SIZE + u
                    out[i * 4:i * 4 + 4] = bytes(psx.color_to_rgba(color))
                    loaded[i] = 1
        return bytes(out), bytes(loaded)

    def sources_in(self, x: int, y: int, w: int, h: int) -> list:
        """Labels of loaded rects overlapping the given VRAM rect."""
        return [label for label, r in self.sources
                if r["x"] < x + w and x < r["x"] + r["w"] and r["y"] < y + h and y < r["y"] + r["h"]]
