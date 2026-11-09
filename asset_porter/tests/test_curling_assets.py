"""Step 4g-K, C1 (../specs/curling.md §4): what curling reads from the disc. Acceptance checks written
from the C by the reviewer; don't change them to make the code pass.

- FRZL17 (map 136) has one 4bpp TIM, map image 1: VRAM (640, 0), 64 x 88 units = 256 x 88 texels, a
  CLUT block of 16 rows that loadMapImage2 (overworld.c:394) spreads to (row * 16, 486). It holds the
  HUD sprites (KarSprite: tpage getTPage(0, 0, 640, 0), CLUT (x, 0x1E6), kar.c:480-662, 2755) and the
  textures of ETCDAT/KARRING.TMD (tpage (640, 0), CLUT row 486).
- The maps family writes it as maps/FRZL17/curling/sheet.png (indexed, palette 0), sheet.pNN.png (RGBA,
  one per CLUT row; colour 0x0000 transparent) and sheet.json (the sidecar).
- tmd_files binds KARRING.TMD's textures to FRZL17's VRAM (it was "textures_bound": false); its 12
  objects are the stones: model type * 3 + {2, 1, 0}[row] (kar.c:733, KAR_D_8005AB80) for types 0-3.

DW_STEP_4G_K=0 skips them (PENDING)."""

import json
import os
import struct
import tempfile
import unittest
from pathlib import Path

from dwporter.families import maps, tmd_files
from dwporter.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4G_K", "1") or 1)
MAP = DEFAULT_INPUT / "MAP" / "MAP10" / "FRZL17.MAP"
KARRING = DEFAULT_INPUT / "ETCDAT" / "KARRING.TMD"
SHEET_W, SHEET_H, PALETTES = 256, 88, 16
# The CLUT x of every curling sprite (kar.c:480-662 and the overrides in KAR_renderPowerMeter :1162-1170,
# KAR_renderAimArrow :1092): palettes 1, 3, 7, 8, 9, 10, 11, 12.
SPRITE_CLUTS = [0x10, 0x30, 0x70, 0x80, 0x90, 0xA0, 0xB0, 0xC0]


def _map_tim(data: bytes, index: int):
    """The MAP header's image `index` (u32 setup, then u32 per 8bpp / 4bpp image): FRZL17 has 1 + 1."""
    off = struct.unpack_from("<I", data, 4 + 4 * index)[0]
    flag = struct.unpack_from("<I", data, off + 4)[0]
    pos = off + 8
    clut = None
    if flag & 8:
        blk, cx, cy, cw, ch = struct.unpack_from("<IHHHH", data, pos)
        clut = (cx, cy, cw, ch, [list(struct.unpack_from(f"<{cw}H", data, pos + 12 + r * cw * 2)) for r in range(ch)])
        pos += blk
    blk, ix, iy, iw, ih = struct.unpack_from("<IHHHH", data, pos)
    return {"clut": clut, "rect": (ix, iy, iw, ih), "pixels": data[pos + 12:pos + 12 + iw * 2 * ih]}


def _png_size(path: Path):
    head = path.read_bytes()[:24]
    return struct.unpack(">II", head[16:24])


@unittest.skipUnless(STEP >= 1, "PENDING (DW_STEP_4G_K < 1)")
@unittest.skipUnless(MAP.is_file() and KARRING.is_file(), "game dump not available")
class CurlingAssetsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.root = Path(cls.tmp.name)
        cls.maps = maps.convert(DEFAULT_INPUT, cls.root, map_ids={136})  # FRZL17
        cls.tmd = tmd_files.convert(DEFAULT_INPUT, cls.root)
        cls.tim = _map_tim(MAP.read_bytes(), 1)

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def sheet(self):
        return json.loads((self.root / "maps" / "FRZL17" / "curling" / "sheet.json").read_text(encoding="utf-8"))

    def test_checks_pass(self):
        for out in (self.maps, self.tmd):
            failed = [f"{c.name}: {c.detail}" for c in out.checks if not c.passed]
            self.assertFalse(failed, failed)

    def test_the_4bpp_tim_is_where_the_c_draws(self):
        # The disc itself, read here without the porter: image (640, 0, 64, 88), CLUT (0, 486, 16, 16).
        self.assertEqual(self.tim["rect"], (640, 0, 64, 88))
        cx, cy, cw, ch, _ = self.tim["clut"]
        self.assertEqual((cx, cy, cw, ch), (0, 486, 16, 16))

    def test_sheet_files(self):
        folder = self.root / "maps" / "FRZL17" / "curling"
        self.assertEqual(_png_size(folder / "sheet.png"), (SHEET_W, SHEET_H))
        for n in range(PALETTES):
            self.assertEqual(_png_size(folder / f"sheet.p{n:02d}.png"), (SHEET_W, SHEET_H), n)

    def test_sheet_sidecar(self):
        side = self.sheet()
        vram = side["vram"]
        self.assertEqual(vram["page"], {"x": 640, "y": 0, "bpp": 4})
        self.assertEqual(vram["uv_rect"], {"u": 0, "v": 0, "w": SHEET_W, "h": SHEET_H})
        self.assertEqual(vram["rect"], {"x": 640, "y": 0, "w": 64, "h": 88})
        self.assertEqual(vram["clut_row"], 486)
        # loadMapImage2: CLUT row i of the TIM -> (i * 16, 486); palette n is the sprites' CLUT x n * 16.
        self.assertEqual(vram["palettes"], self.tim["clut"][4])
        self.assertEqual(len(vram["palettes"]), PALETTES)
        for x in SPRITE_CLUTS:
            self.assertLess(x // 16, len(vram["palettes"]))
        self.assertEqual(side["source"]["path"], "MAP/MAP10/FRZL17.MAP")
        self.assertTrue(any("overworld.c:394" in r for r in side["code_refs"]), side["code_refs"])
        self.assertTrue(any("kar.c" in r for r in side["code_refs"]), side["code_refs"])

    def test_sheet_indices_are_the_tims_texels(self):
        # Indexed PNG: the PNG's IDAT holds the 4bpp indices; compare through the sidecar's raw copy if
        # the porter keeps one, else decode the PNG (zlib, filter 0 rows) here.
        import zlib
        raw = (self.root / "maps" / "FRZL17" / "curling" / "sheet.png").read_bytes()
        pos, idat, depth, ctype = 8, b"", None, None
        while pos < len(raw):
            length, kind = struct.unpack(">I4s", raw[pos:pos + 8])
            body = raw[pos + 8:pos + 8 + length]
            if kind == b"IHDR":
                depth, ctype = body[8], body[9]
            elif kind == b"IDAT":
                idat += body
            pos += 12 + length
        self.assertEqual(ctype, 3, "indexed PNG")
        rows = zlib.decompress(idat)
        stride = (SHEET_W * depth + 7) // 8
        texels = []
        prev = bytearray(stride)
        for y in range(SHEET_H):
            f, line = rows[y * (stride + 1)], bytearray(rows[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
            for i in range(stride):
                a = line[i - 1] if i else 0
                b = prev[i]
                c = prev[i - 1] if i else 0
                if f == 1:
                    line[i] = (line[i] + a) & 0xFF
                elif f == 2:
                    line[i] = (line[i] + b) & 0xFF
                elif f == 3:
                    line[i] = (line[i] + (a + b) // 2) & 0xFF
                elif f == 4:
                    p = a + b - c
                    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                    line[i] = (line[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 0xFF
            prev = line
            if depth == 8:
                texels += list(line[:SHEET_W])
            else:
                for byte in line:
                    texels += [byte >> 4, byte & 0xF]
                texels = texels[:(y + 1) * SHEET_W]
        expected = []
        for byte in self.tim["pixels"]:
            expected += [byte & 0xF, byte >> 4]  # PSX 4bpp: low nibble first
        self.assertEqual(texels, expected)

    def test_karring_textures_bound(self):
        side = json.loads((self.root / "tmd_files" / "ETCDAT" / "KARRING.json").read_text(encoding="utf-8"))
        self.assertTrue(side["model"]["textures_bound"])
        self.assertTrue(side["textures"])
        for t in side["textures"]:
            self.assertEqual(t["page"], {"x": 640, "y": 0, "bpp": 4})
            self.assertEqual(t["clut"]["y"], 486)
            self.assertIsNotNone(t["path"])
            self.assertEqual(t["missing_texels_in_uv_box"], 0, t)
            self.assertTrue(any("FRZL17.MAP" in s for s in t["vram_sources"]["page"]), t["vram_sources"])
            self.assertTrue(any("FRZL17.MAP" in s for s in t["vram_sources"]["clut"]), t["vram_sources"])

    def test_karring_has_the_twelve_stone_models(self):
        gltf = json.loads((self.root / "tmd_files" / "ETCDAT" / "KARRING.gltf").read_text(encoding="utf-8"))
        # KAR_D_8005AB80 {2, 1, 0} + type * 3 for types 0-3: models 0-11 (kar.c:733); pegged 9-11 (:443).
        self.assertEqual(len(gltf["nodes"]), 12)
        self.assertTrue(all(img.get("uri") for img in gltf.get("images", [])), gltf.get("images"))
        self.assertTrue(gltf.get("images"), "the glTF names its textures")


if __name__ == "__main__":
    unittest.main()
