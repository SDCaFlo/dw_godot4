import struct
import unittest
import zlib

from dwporter.exporters import png
from dwporter.formats import psx
from dwporter.formats import tim as timfmt
from dwporter.paths import DEFAULT_INPUT


def make_tim(bpp, width, height, pixels, palettes=None, x=640, y=0, cx=0, cy=480):
    pmode = {4: 0, 8: 1, 16: 2, 24: 3}[bpp]
    out = struct.pack("<II", 0x10, pmode | (0x8 if palettes else 0))
    if palettes:
        cw = len(palettes[0])
        colors = b"".join(struct.pack(f"<{cw}H", *p) for p in palettes)
        out += struct.pack("<IHHHH", 12 + len(colors), cx, cy, cw, len(palettes)) + colors
    stride = width * bpp // 16
    out += struct.pack("<IHHHH", 12 + len(pixels), x, y, stride, height) + pixels
    return out


def png_rows(data):
    """Decode an unfiltered PNG written by our encoder: returns (header, raw rows)."""
    pos, idat, header = 8, b"", None
    while pos < len(data):
        (length,) = struct.unpack_from(">I", data, pos)
        kind = data[pos + 4:pos + 8]
        payload = data[pos + 8:pos + 8 + length]
        if kind == b"IHDR":
            header = struct.unpack(">IIBBBBB", payload)
        elif kind == b"IDAT":
            idat += payload
        pos += 12 + length
    return header, zlib.decompress(idat)


class TimTests(unittest.TestCase):
    def test_4bpp_nibble_order_and_palette(self):
        palette = [0x0000, 0x001F] + [0x7FFF] * 14
        tim_bytes = make_tim(4, 4, 1, bytes([0x10, 0x32]), [palette])
        tim = timfmt.parse(tim_bytes)
        self.assertEqual((tim.bpp, tim.width, tim.height, tim.size), (4, 4, 1, len(tim_bytes)))
        self.assertEqual(timfmt.indices(tim), bytes([0, 1, 2, 3]))  # low nibble first
        rgba = timfmt.palette_rgba(tim)
        self.assertEqual(rgba[0], (0, 0, 0, 0))  # 0x0000 is transparent
        self.assertEqual(rgba[1], (255, 0, 0, 255))

    def test_16bpp_stp_mask(self):
        pixels = struct.pack("<2H", 0x8000, 0x7C00)  # black + STP (opaque), pure blue
        tim = timfmt.parse(make_tim(16, 2, 1, pixels))
        rgba, stp = timfmt.direct_rgba(tim)
        self.assertEqual(rgba, bytes([0, 0, 0, 255, 0, 0, 255, 255]))
        self.assertEqual(stp, bytes([255, 0]))

    def test_colour_expansion_is_reversible(self):
        for v in range(32):
            self.assertEqual(psx.expand5(v) >> 3, v)

    def test_vram_ids_match_libgpu(self):
        # Values used by renderCardImage in game_menu.c.
        self.assertEqual(psx.get_tpage(1, 0, 576, 256), 0x99)
        self.assertEqual(psx.get_clut(448, 511), (511 << 6) | 28)

    def test_rejects_garbage(self):
        self.assertIsNone(timfmt.try_parse(b"\x10\x00\x00\x00\x04\x00\x00\x00" + b"\x00" * 32))
        self.assertIsNone(timfmt.try_parse(b"\x11" + b"\x00" * 40))
        self.assertIsNone(timfmt.try_parse(make_tim(8, 2, 1, b"\x00\x00")[:-1]))  # truncated / no CLUT

    def test_scan_finds_embedded_tims(self):
        a = make_tim(16, 2, 1, b"\x01\x00\x02\x00")
        data = b"\xAA" * 8 + a + b"\x00" * 4 + a
        self.assertEqual([t.offset for t in timfmt.scan(data)], [8, 8 + len(a) + 4])

    def test_indexed_png_keeps_indices(self):
        palette = [(i, i, i, 255) for i in range(16)]
        data = png.encode_indexed(4, 2, bytes(range(8)), palette)
        (w, h, depth, color_type, *_), raw = png_rows(data)
        self.assertEqual((w, h, depth, color_type), (4, 2, 8, 3))
        self.assertEqual(raw, b"\x00" + bytes(range(4)) + b"\x00" + bytes(range(4, 8)))


@unittest.skipUnless((DEFAULT_INPUT / "CARD" / "CARD.ALL").exists(), "dumped game files not available")
class CardAllTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import card_all

        with tempfile.TemporaryDirectory() as tmp:
            out = card_all.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), card_all.EXPECTED_CARDS)


class DigimonTableTests(unittest.TestCase):
    def test_table(self):
        from dwporter.data.digimon import DIGIMON_TYPES, mmd_path

        self.assertEqual(len(DIGIMON_TYPES), 180)
        self.assertEqual(DIGIMON_TYPES[3][::2], ("AGUM", "Agumon"))
        self.assertEqual(mmd_path(3), "CHDAT/MMD0/AGUM.MMD")
        self.assertEqual(mmd_path(179), "CHDAT/MMD5/CEMG.MMD")


@unittest.skipUnless((DEFAULT_INPUT / "CHDAT" / "ALLTIM.TIM").exists(), "dumped game files not available")
class AllTimTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import alltim

        with tempfile.TemporaryDirectory() as tmp:
            out = alltim.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), alltim.TYPE_COUNT)

    def test_runtime_slots_match_code(self):
        from dwporter.families.alltim import RUNTIME_SLOTS

        # model.c: tamer pixelPage 0x15 / clutPage 0x7A00, partner pixelOffsetY 0x80, via uploadModelTexture.
        self.assertEqual(RUNTIME_SLOTS["tamer"], {"image": {"x": 320, "y": 256}, "clut": {"x": 0, "y": 488}})
        self.assertEqual(RUNTIME_SLOTS["partner"]["image"], {"x": 320, "y": 384})


class StackedTimTests(unittest.TestCase):
    def test_loader_step_equals_size_for_packed_tim(self):
        from dwporter.families.stacked_tim import loader_step

        tim = timfmt.parse(make_tim(4, 4, 2, bytes(4), [[0] * 16, [0] * 16]))
        self.assertEqual(loader_step(tim), tim.size)

    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import etctim, stdtim

        for module, count in ((etctim, 9), (stdtim, 6)):
            if not (DEFAULT_INPUT / module.SOURCE_PATH).exists():
                self.skipTest("dumped game files not available")
            with tempfile.TemporaryDirectory() as tmp:
                out = module.convert(DEFAULT_INPUT, Path(tmp))
                self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
                self.assertEqual(len(out.assets), count)


if __name__ == "__main__":
    unittest.main()
