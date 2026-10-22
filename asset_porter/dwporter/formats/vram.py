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
        per_word = {4: 4, 8: 2}.get(bpp, 1)
        shifts = [i * (16 // per_word) for i in range(per_word)]
        mask = (1 << (16 // per_word)) - 1
        transparent = bytes(4)
        if bpp in (4, 8):
            palette = []
            for i in range(1 << (16 // per_word)):
                color, ok = self.word(clut_x + i, clut_y)
                palette.append((bytes(psx.color_to_rgba(color)) if ok else transparent, ok))
        out, loaded = [], bytearray()
        for v in range(PAGE_SIZE):
            for w in range(PAGE_SIZE // per_word):
                word, ok = self.word(page_x + w, page_y + v)
                if bpp in (4, 8):
                    for s in shifts:
                        rgba, ok2 = palette[(word >> s) & mask]
                        good = ok and ok2
                        out.append(rgba if good else transparent)
                        loaded.append(good)
                else:
                    out.append(bytes(psx.color_to_rgba(word)) if ok else transparent)
                    loaded.append(ok)
        return b"".join(out), bytes(loaded)

    def sources_in(self, x: int, y: int, w: int, h: int) -> list:
        """Labels of loaded rects overlapping the given VRAM rect."""
        return [label for label, r in self.sources
                if r["x"] < x + w and x < r["x"] + r["w"] and r["y"] < y + h and y < r["y"] + r["h"]]
