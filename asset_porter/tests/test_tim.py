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


@unittest.skipUnless((DEFAULT_INPUT / "ETCDAT" / "ITEM.TIM").exists(), "dumped game files not available")
class TimFilesTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import tim_files

        with tempfile.TemporaryDirectory() as tmp:
            out = tim_files.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), sum(f.count for f in tim_files.FILES))
            self.assertEqual(len(tim_files.FILES), 51)


def make_tmd(prims_bytes: bytes, n_prims: int, vertices, normals) -> bytes:
    """One-object TMD (flags 0: offsets relative to the object table)."""
    vblock = b"".join(struct.pack("<hhhH", *v, 0) for v in vertices)
    nblock = b"".join(struct.pack("<hhhH", *n, 0) for n in normals)
    table_size = 28
    vert_top = table_size
    normal_top = vert_top + len(vblock)
    prim_top = normal_top + len(nblock)
    table = struct.pack("<6Ii", vert_top, len(vertices), normal_top, len(normals), prim_top, n_prims, 0)
    return struct.pack("<III", 0x41, 0, 1) + table + vblock + nblock + prims_bytes


class TmdTests(unittest.TestCase):
    def test_textured_lit_flat_triangle(self):
        from dwporter.formats import tmd as tmdfmt

        # mode 0x24 (polygon, textured, triangle), flag 0 (lit, flat): uv/cba/tsb, normal, 3 vertices
        packet = bytes([1, 2, 0x03, 0x7F, 4, 5, 0x0A, 0x00, 6, 7, 0, 0]) + struct.pack("<4H", 0, 0, 1, 2)
        prim = bytes([7, len(packet) // 4, 0x00, 0x24]) + packet
        data = make_tmd(prim, 1, [(0, 0, 0), (100, 0, 0), (0, 100, 0)], [(0, 0, -4096)])
        tmd = tmdfmt.parse(data)
        p = tmd.objects[0].primitives[0]
        self.assertEqual((p.kind, p.vertices, p.normals, p.uvs), ("triangle", (0, 1, 2), (0,), ((1, 2), (4, 5), (6, 7))))
        self.assertEqual((p.cba, p.tsb), (0x7F03, 0x0A))
        self.assertEqual(p.tpage_info()["x"], 640)
        self.assertEqual(tmd.end, len(data))

    def test_layout_must_match_ilen(self):
        from dwporter.formats import tmd as tmdfmt

        prim = bytes([7, 3, 0x00, 0x24]) + bytes(12)  # ilen 3 but the layout needs 5 words
        with self.assertRaises(tmdfmt.TmdError):
            tmdfmt.parse(make_tmd(prim, 1, [(0, 0, 0)] * 3, [(0, 0, 4096)]))

    def test_gltf_winding_follows_normal(self):
        """Exported triangles are counter-clockwise around their (converted) normal."""
        import json
        import tempfile
        from pathlib import Path

        from dwporter import models
        from dwporter.formats import tmd as tmdfmt

        # Untextured lit flat triangle (mode 0x20, flag 0): rgb+mode, normal, 3 vertices, no pad.
        packet = bytes([255, 0, 0, 0x20]) + struct.pack("<4H", 0, 0, 1, 2)
        prim = bytes([4, len(packet) // 4, 0x00, 0x20]) + packet
        # PSX order is clockwise around the stored normal (as found in all game models).
        # (v1 - v0) x (v2 - v0) = (0, 0, -10000), opposite to the stored normal.
        verts, normal = [(0, 0, 0), (0, 100, 0), (100, 0, 0)], (0, 0, 4096)
        tmd = tmdfmt.parse(make_tmd(prim, 1, verts, [normal]))
        with tempfile.TemporaryDirectory() as tmp:
            models.build(Path(tmp) / "m", "test@0x0", tmd)
            doc = json.loads((Path(tmp) / "m.gltf").read_text())
            buf = (Path(tmp) / "m.bin").read_bytes()
        prim = doc["meshes"][0]["primitives"][0]
        pos_view = doc["bufferViews"][doc["accessors"][prim["attributes"]["POSITION"]]["bufferView"]]
        nrm_view = doc["bufferViews"][doc["accessors"][prim["attributes"]["NORMAL"]]["bufferView"]]
        p = [struct.unpack_from("<3f", buf, pos_view["byteOffset"] + 12 * i) for i in range(3)]
        n = struct.unpack_from("<3f", buf, nrm_view["byteOffset"])
        e1 = [p[1][i] - p[0][i] for i in range(3)]
        e2 = [p[2][i] - p[0][i] for i in range(3)]
        cross = (e1[1] * e2[2] - e1[2] * e2[1], e1[2] * e2[0] - e1[0] * e2[2], e1[0] * e2[1] - e1[1] * e2[0])
        self.assertGreater(sum(cross[i] * n[i] for i in range(3)), 0)


@unittest.skipUnless((DEFAULT_INPUT / "ETCNA" / "TAKA.TMD").exists(), "dumped game files not available")
class TmdFilesTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import tmd_files

        with tempfile.TemporaryDirectory() as tmp:
            out = tmd_files.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), 66)


class MmdTests(unittest.TestCase):
    def _anim(self, bones, frame_count, initial, words):
        """Build an MMD-style animation blob: header + initial poses + instruction words."""
        data = struct.pack("<H", frame_count)
        for pose in initial:
            data += struct.pack("<6h", *pose)
        return data + struct.pack(f"<{len(words)}H", *[w & 0xFFFF for w in words])

    def test_momentum_with_remainder_is_exact(self):
        from dwporter.formats import mmd as mmdfmt

        # Bone 1 rot_x: value 10 over divisor 4 -> per tick +2, plus +1 on two of every four ticks.
        # keyframe@1; entry: marker | axis bit for index 3 (rot_x, 0x4000 >> 3) | bone 1; divisor 4; value 10
        words = [0x0001, 0x8000 | 0x0800 | 1, 4, 10, 0x0000]
        data = self._anim(2, 9, [[0, 0, 0, 0, 0, 0]], words)
        anim = mmdfmt.parse_animation(data, 0, 0, 2)
        self.assertEqual(anim.instructions[0]["entries"][0], {"bone": 1, "divisor": 4, "axes": {"rot_x": 10}})
        sim = mmdfmt.simulate(data, anim, 2, 0)
        rot_x = [f[1][3] for f in sim["frames"]]
        # Tick 1 shows the initial pose; the keyframe takes effect from tick 2; every 4 ticks add 10.
        self.assertEqual(rot_x[0], 0)
        self.assertEqual(rot_x[4] - rot_x[0], 10)
        self.assertEqual(rot_x[8] - rot_x[4], 10)
        self.assertEqual(len(sim["frames"]), 9)

    def test_endless_loop(self):
        from dwporter.formats import mmd as mmdfmt

        words = [0x0001, 0x1000, 0x2004, 0x0002, 0x0000]  # keyframe@1 (no entries), loop start (endless), loop end@4 -> 2
        data = self._anim(1, 10, [], words)
        anim = mmdfmt.parse_animation(data, 0, 0, 1)
        sim = mmdfmt.simulate(data, anim, 1, 0)
        self.assertEqual(sim["loop"]["start_frame"], 2)
        self.assertEqual(sim["loop"]["end_frame"], 4)
        self.assertEqual(len(sim["frames"]), 4)

    def test_rotation_matches_rotmatrix(self):
        """pose_rotation(a, b, c) == F * Rx(a) Ry(b) Rz(c) * F (libgte RotMatrix, axis flip F)."""
        import math

        from dwporter.models import pose_rotation

        def mat(a, b, c):
            k = 2 * math.pi / 4096
            cx, sx, cy, sy, cz, sz = (f(v * k) for v in (a, b, c) for f in (math.cos, math.sin))
            # Rx * Ry * Rz; the entries checked in asm/us/main/psyq/libgte.s RotMatrix match this.
            return [[cz * cy, -sz * cy, sy], [sz * cx + cz * sy * sx, cz * cx - sz * sy * sx, -cy * sx],
                    [sz * sx - cz * sy * cx, cz * sx + sz * sy * cx, cy * cx]]

        for a, b, c in ((300, 0, 0), (0, 700, 0), (0, 0, -900), (123, 456, 789), (-2000, 1500, 100)):
            m = mat(a, b, c)
            f = [[m[i][j] * (1 if i == 0 else -1) * (1 if j == 0 else -1) for j in range(3)] for i in range(3)]
            x, y, z, w = pose_rotation(a, b, c)
            q = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                 [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                 [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
            for i in range(3):
                for j in range(3):
                    self.assertAlmostEqual(q[i][j], f[i][j], places=9)

    def test_key_reduction_is_exact(self):
        from dwporter.models import _keep_keys, _linear_ints, _linear_rotation

        values = [(0,), (2,), (4,), (6,), (7,), (8,), (8,)]
        self.assertEqual(_keep_keys(values, _linear_ints), [0, 3, 5, 6])
        # Two axes changing together must not be reduced; long single-axis runs are split before 90 degrees.
        two_axes = [(i, i, 0) for i in range(5)]
        self.assertEqual(_keep_keys(two_axes, _linear_rotation), [0, 1, 2, 3, 4])
        spin = [(0, 0, 300 * i) for i in range(10)]
        kept = _keep_keys(spin, _linear_rotation)
        self.assertTrue(all(spin[b][2] - spin[a][2] < 1024 for a, b in zip(kept, kept[1:])))


@unittest.skipUnless((DEFAULT_INPUT / "CHDAT" / "MMD0" / "AGUM.MMD").exists(), "dumped game files not available")
class MmdFilesTests(unittest.TestCase):
    def test_convert_subset(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import mmd_files

        with tempfile.TemporaryDirectory() as tmp:
            out = mmd_files.convert(DEFAULT_INPUT, Path(tmp), types={0, 3, 45, 62})
            self.assertTrue(out.ok, [c.name for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), 3)


class MapTests(unittest.TestCase):
    def test_tfs(self):
        from dwporter.formats import map as mapfmt

        tile = bytes(range(256)) * 64
        data = struct.pack("<HHI", 2, 1, 1) + struct.pack("<256H", *range(256)) + struct.pack("<I", 7) + tile
        tfs = mapfmt.parse_tfs(data, 1)
        self.assertEqual((tfs.width, tfs.height, len(tfs.palettes), tfs.end), (2, 1, 1, len(data)))
        self.assertEqual(tfs.tiles[0][1], 7)

    def test_minimal_map(self):
        from dwporter.formats import map as mapfmt

        # header: setup, entities, collision (no images -> no objects word); setup: 1x1 layout, tile -1
        setup =struct.pack("<38i", *([0] * 36 + [1, 1])) + struct.pack("<i", -1)
        entities = struct.pack("<60h", *range(60)) + struct.pack("<h", 0)
        entities_off = 12 + len(setup)
        collision_off = entities_off + len(entities)
        header = struct.pack("<3I", 12, entities_off, collision_off)
        data = header + setup + entities + bytes(10000)
        m = mapfmt.parse_map(data, 0, 0, True)
        self.assertEqual(m["setup"]["tiles"], [-1])
        self.assertEqual(m["spawns"][1], {"x": 1, "y": 11, "z": 21, "rotation": 31})
        self.assertEqual(m["warps"][2], {"map": 42, "spawn": 52})
        self.assertEqual(m["spans"][-1], (collision_off, len(data)))

    def test_projection_centre(self):
        from dwporter.formats import map as mapfmt

        cam = mapfmt.camera({"viewpoint": [0, -500, -500], "reference": [0, 0, 0], "projection": 300})
        # The look-at point projects to the background centre.
        self.assertEqual(tuple(round(c) for c in mapfmt.project(cam, (0, 0, 0), (640, 480))), (320, 240))
        # +X world appears to the right; a point above the target (smaller y) appears higher.
        self.assertGreater(mapfmt.project(cam, (100, 0, 0), (640, 480))[0], 320)
        self.assertLess(mapfmt.project(cam, (0, -100, 0), (640, 480))[1], 240)


@unittest.skipUnless((DEFAULT_INPUT / "MAP" / "MAP1" / "MAYO04A.MAP").exists(), "dumped game files not available")
class MapsFamilyTests(unittest.TestCase):
    def test_convert_subset(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import maps

        with tempfile.TemporaryDirectory() as tmp:
            out = maps.convert(DEFAULT_INPUT, Path(tmp), map_ids={3, 8})
            self.assertTrue(out.ok, [(c.name, c.detail) for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), 2)


def sjis(text: str) -> bytes:
    """ASCII text as the game stores it: full-width Shift-JIS."""
    return "".join(chr(ord(c) + 0xFEE0) if "!" <= c <= "~" else "　" for c in text).encode("shift_jis")


class ScnTests(unittest.TestCase):
    def make_script(self):
        from dwporter.formats import scn

        body = bytearray()
        body += bytes([0x1B, 0xFD])                                        # SET_DIALOG_OWNER tamer
        body += bytes([0x1A, 0]) + sjis("Hi") + b"\x01\x06" + sjis("X")    # SHOW_TEXTBOX "Hi{color 6}X\n"
        body += b"\x0d\x00\x00\x00"
        body += bytes([0x19, 0, 0x09, 0, 7, 3])                            # IF pstat 7 != 3
        body += bytes([0x18, 0]) + struct.pack("<H", 0)                    #    jump_if_false -> patched
        body += bytes([0x19, 0])
        body += bytes([0x28, 0, 5, 2])                                     # GIVE_ITEM 5 x2
        end = len(body)
        body += bytes([scn.END_SECTION, 0, scn.END_SCRIPT, 0])
        header = struct.pack("<HHHH", 8, 1, 8, 0xFFFF)                     # one section (id 1) at 8
        data = bytearray(header + body)
        jump = data.index(bytes([0x18, 0])) + 2
        struct.pack_into("<H", data, jump, 8 + end)                        # -> END_SECTION
        return bytes(data)

    def test_disassemble_round_trip(self):
        from dwporter.formats import scn

        data = self.make_script() + b"junk"
        dis = scn.disassemble(data)
        names = [i["name"] for i in dis["instructions"]]
        self.assertEqual(names, ["SET_DIALOG_OWNER", "SHOW_TEXTBOX", "IF", "GIVE_ITEM", "END_SECTION", "END_SCRIPT"])
        self.assertEqual(dis["instructions"][1]["args"]["text"], "Hi{color 6}X")
        cond = dis["instructions"][2]["args"]["conditions"]
        self.assertEqual((cond[0]["kind"], cond[0]["compare"], cond[1]["kind"]), ("pstat", "!=", "jump_if_false"))
        self.assertEqual(dis["instructions"][3]["args"], {"item": 5, "amount": 2})
        self.assertEqual(dis["padding"], b"junk")
        starts = {i["offset"] for i in dis["instructions"]}
        self.assertTrue(all(t in starts for i in dis["instructions"] for t in scn.jump_targets(i)))
        rebuilt = data[:8] + b"".join(bytes.fromhex(i["raw"]) for i in dis["instructions"]) + dis["padding"]
        self.assertEqual(rebuilt, data)

    def test_selection_embeds_its_textbox(self):
        from dwporter.formats import scn

        sel = bytes([0x10, 2]) + struct.pack("<HH", 0x20, 0x24) + bytes([0x1A, 0]) + sjis("Yes")
        sel += b"\x0d\x00" + sjis("No") + b"\x0d\x00\x00\x00"
        insn = scn.decode_instruction(sel + bytes([0xFE, 0]), 0)
        self.assertEqual(insn["size"], len(sel))
        self.assertEqual(insn["args"]["targets"], [0x20, 0x24])
        self.assertEqual(insn["args"]["text"], "Yes\nNo")

    def test_data_block_ends_at_ff(self):
        from dwporter.formats import scn

        insn = scn.decode_instruction(bytes([0x6B, 0, 3, 4, 0x11, 0xFF, 0x6B]), 0)
        self.assertEqual((insn["size"], insn["args"]["values"]), (6, [3, 4, 0x11]))


class SoundFormatTests(unittest.TestCase):
    def test_adpcm_low_nibble_first_and_loop_flags(self):
        from dwporter.formats import vab

        # shift 12, filter 0: each nibble decodes to its signed value; low nibble first
        block1 = bytes([0x0C, 0x04]) + bytes([0x21, 0xF3]) + bytes(12)   # loop start here
        block2 = bytes([0x0C, 0x03]) + bytes(14)                         # end + repeat
        r = vab.decode_adpcm(block1 + block2 + bytes(16))
        self.assertEqual(r["samples"][:4], [1, 2, 3, -1])
        self.assertEqual((r["loop_start"], r["loop_end"], r["end_block"]), (0, 56, 1))
        self.assertEqual(len(r["samples"]), 56)  # decoding stops at the end flag

    def test_seq_to_midi(self):
        from dwporter.formats import seq

        body = bytes([0x00, 0xC0, 5, 0x00, 0x90, 60, 100, 0x83, 0x60, 60, 0])  # running status note off (vel 0)
        body += bytes([0x00, 0xFF, 0x51, 0x07, 0xA1, 0x20, 0x00, 0xFF, 0x2F])
        data = b"pQES" + struct.pack(">IH", 1, 480) + (500000).to_bytes(3, "big") + bytes([1, 4]) + body
        s = seq.parse(data)
        self.assertEqual((s["size"], s["ticks"], s["notes"], s["channels"]), (len(data), 480, 1, [0]))
        midi = seq.to_midi(s)
        self.assertEqual(midi[:4], b"MThd")
        self.assertEqual(struct.unpack_from(">H", midi, 12)[0], 480)
        self.assertTrue(midi.endswith(b"\xFF\x2F\x00"))
        self.assertIn(b"\xFF\x51\x03\x07\xA1\x20", midi)  # SEQ tempo meta gets its length byte


@unittest.skipUnless((DEFAULT_INPUT / "SOUND" / "VHB" / "SS.VHB").exists(), "dumped game files not available")
class SoundFamilyTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import mmm_dat, sound

        with tempfile.TemporaryDirectory() as tmp:
            out = sound.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [(c.name, c.detail) for c in out.checks if not c.passed][:5])
            self.assertEqual(len(out.assets), 145)
            out = mmm_dat.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [(c.name, c.detail) for c in out.checks if not c.passed])


@unittest.skipUnless((DEFAULT_INPUT / "SCN" / "DG.SCN").exists(), "dumped game files not available")
class ScriptsFamilyTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import scripts

        with tempfile.TemporaryDirectory() as tmp:
            out = scripts.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [(c.name, c.detail) for c in out.checks if not c.passed][:5])
            self.assertEqual(len(out.assets), 223)


@unittest.skipUnless((DEFAULT_INPUT / "STDDAT" / "B_TOGI.ATR").exists(), "dumped game files not available")
class AtrFilesTests(unittest.TestCase):
    def test_convert(self):
        import tempfile
        from pathlib import Path

        from dwporter.families import atr_files

        with tempfile.TemporaryDirectory() as tmp:
            out = atr_files.convert(DEFAULT_INPUT, Path(tmp))
            self.assertTrue(out.ok, [(c.name, c.detail) for c in out.checks if not c.passed])
            self.assertEqual(len(out.assets), 2)


if __name__ == "__main__":
    unittest.main()
