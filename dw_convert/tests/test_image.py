"""Disc images (specs/disc_image.md, distribution step D4).

Synthetic images built here: a small ISO 9660 tree in raw mode 2 sectors (form 1 and form 2) and as a
2048-byte .iso. With the developer's image (DW_DISC_IMAGE, or the usual place; skipped if missing): the US
check, and every file equal to game_dumped_files/.
    python -m unittest discover -s tests -t .
"""

import hashlib
import json
import os
import struct
import tempfile
import unittest
from pathlib import Path

from dwconvert import identify, image
from dwconvert.__main__ import DEFAULT_DUMP, PROJECT_ROOT, main

REAL = Path(os.environ.get("DW_DISC_IMAGE") or
            PROJECT_ROOT.parent / "original isos" / "Digimon World (USA)" / "Digimon World (USA).cue")


def _record(name: bytes, lba: int, length: int, is_dir: bool) -> bytes:
    n = 33 + len(name)
    n += n % 2
    rec = bytearray(n)
    rec[0] = n
    struct.pack_into("<I", rec, 2, lba)
    struct.pack_into(">I", rec, 6, lba)
    struct.pack_into("<I", rec, 10, length)
    struct.pack_into(">I", rec, 14, length)
    rec[25] = 2 if is_dir else 0
    rec[32] = len(name)
    rec[33:33 + len(name)] = name
    return bytes(rec)


def build(cooked: bool = False, many: int = 60) -> tuple:
    """(image bytes, {path: expected bytes}). Layout: PVD 16, root 18, DIR (2 sectors) 19-20, files from 21:
    A.TXT (short), DIR/F<k>.BIN (enough to need a second directory sector), MIX.STR (form 1 + form 2)."""
    sectors = {}

    def put(lba, data, form=1):
        sectors[lba] = (data, form)

    expected, files = {}, []
    lba = 21
    a = b"hello disc\n"
    files.append(("", b"A.TXT;1", lba, a))
    put(lba, a.ljust(2048, b"\0"))
    expected["A.TXT"] = a
    lba += 1
    for k in range(many):
        body = bytes([k]) * (100 + k)
        files.append(("DIR", f"F{k:02d}.BIN;1".encode(), lba, body))
        put(lba, body.ljust(2048, b"\0"))
        expected[f"DIR/F{k:02d}.BIN"] = body
        lba += 1
    mix_lba, mix = lba, b""
    for k in range(4):   # video, video, audio, video
        if k == 2:
            data = bytes([0xA0 + k]) * 2324
            put(lba, data, 2)
        else:
            data = bytes([0x10 + k]) * 2048
            put(lba, data)
        mix += data
        lba += 1
    files.append(("", b"MIX.STR;1", mix_lba, mix))
    expected["MIX.STR"] = mix

    def directory(entries, self_lba, parent_lba, n_sectors):
        recs = [_record(b"\x00", self_lba, n_sectors * 2048, True), _record(b"\x01", parent_lba, 2048, True)]
        recs += entries
        out, cur = [], b""
        for r in recs:
            if len(cur) + len(r) > 2048:
                out.append(cur.ljust(2048, b"\0"))
                cur = b""
            cur += r
        out.append(cur.ljust(2048, b"\0"))
        assert len(out) == n_sectors, len(out)
        return out

    def flen(name, body):
        return len(body) if name != b"MIX.STR;1" else 4 * 2048

    root_entries = [_record(n, l, flen(n, b), False) for d, n, l, b in files if d == ""]
    root_entries.insert(1, _record(b"DIR", 19, 2 * 2048, True))
    dir_entries = [_record(n, l, flen(n, b), False) for d, n, l, b in files if d == "DIR"]
    put(18, directory(root_entries, 18, 18, 1)[0])
    for k, s in enumerate(directory(dir_entries, 19, 18, 2)):
        put(19 + k, s)
    pvd = bytearray(2048)
    pvd[0:6] = b"\x01CD001"
    pvd[156:156 + 34] = _record(b"\x00", 18, 2048, True)
    put(16, bytes(pvd))

    total = lba
    out = bytearray()
    for n in range(total):
        data, form = sectors.get(n, (bytes(2048), 1))
        if cooked:
            out += data[:2048] if form == 1 else data[:2048]
            continue
        sub = bytes([0, 0, 0x20 if form == 2 else 0x08, 0]) * 2
        raw = image.SYNC + bytes([0, 2, n % 75, 2]) + sub + data
        out += raw.ljust(image.RAW, b"\0")
    return bytes(out), expected


class Synthetic(unittest.TestCase):

    def _write(self, d, name, data):
        p = Path(d) / name
        p.write_bytes(data)
        return p

    def test_raw_mode2_with_cue(self):
        data, expected = build()
        with tempfile.TemporaryDirectory() as d:
            self._write(d, "game.bin", data)
            cue = self._write(d, "game.cue", b'FILE "game.bin" BINARY\n  TRACK 01 MODE2/2352\n    INDEX 01 00:00:00\n')
            with image.open_image(cue) as img:
                self.assertEqual((img.sector_size, img.mode), (image.RAW, 2))
                found = {e.path: image.read_file(img, e) for e in image.files(img)}
                self.assertEqual(found, expected, "every file, the directory over two sectors, form 2 payloads")
                self.assertTrue(image.has_form2(img, next(e for e in image.files(img) if e.path == "MIX.STR")))
                out = Path(d) / "out"
                written = image.extract(img, out, skip=("MIX",))
                self.assertNotIn("MIX.STR", written)
                self.assertEqual((out / "DIR" / "F59.BIN").read_bytes(), expected["DIR/F59.BIN"])

    def test_bin_without_cue(self):
        data, expected = build()
        with tempfile.TemporaryDirectory() as d:
            with image.open_image(self._write(d, "game.bin", data)) as img:
                self.assertEqual(img.sector_size, image.RAW)
                self.assertEqual(image.read_file(img, image.files(img)[0]), expected["A.TXT"])

    def test_cooked_iso_loses_form2(self):
        data, expected = build(cooked=True)
        with tempfile.TemporaryDirectory() as d:
            with image.open_image(self._write(d, "game.iso", data)) as img:
                self.assertEqual(img.sector_size, image.COOKED)
                found = {e.path: image.read_file(img, e) for e in image.files(img)}
                self.assertEqual({k: v for k, v in found.items() if k != "MIX.STR"},
                                 {k: v for k, v in expected.items() if k != "MIX.STR"})
                self.assertNotEqual(found["MIX.STR"], expected["MIX.STR"], "a 2048 image has no form 2 audio")
                self.assertFalse(image.has_form2(img, next(e for e in image.files(img) if e.path == "MIX.STR")))

    def test_refused(self):
        with tempfile.TemporaryDirectory() as d:
            for name, body in (("game.chd", b"x"), ("odd.bin", b"x" * 1000)):
                with self.assertRaises(image.ImageError):
                    image.open_image(self._write(d, name, body))
            self._write(d, "a.bin", b"\0" * image.RAW * 20)
            cue = self._write(d, "audio.cue", b'FILE "a.bin" BINARY\n  TRACK 01 AUDIO\n    INDEX 01 00:00:00\n')
            with self.assertRaises(image.ImageError):
                image.open_image(cue)

    def test_not_us(self):
        data, _ = build()
        with tempfile.TemporaryDirectory() as d:
            with image.open_image(self._write(d, "game.bin", data)) as img:
                r = identify.identify(img)
                self.assertFalse(r.ok)
                self.assertIn("not a PlayStation game disc", r.message())


@unittest.skipUnless(REAL.is_file(), "no Digimon World (USA) image")
class RealImage(unittest.TestCase):

    def test_identify(self):
        with image.open_image(REAL) as img:
            r = identify.identify(img)
            self.assertEqual(r.boot, "SLUS_010.32")
            self.assertTrue(r.ok, r.message())

    @unittest.skipUnless(DEFAULT_DUMP.is_dir(), "no game_dumped_files")
    def test_every_file_equals_the_dump(self):
        with image.open_image(REAL) as img:
            entries = image.files(img)
            self.assertEqual(len(entries), 818)
            bad = [e.path for e in entries if image.read_file(img, e) != (DEFAULT_DUMP / e.path).read_bytes()]
            self.assertEqual(bad, [])

    @unittest.skipUnless(DEFAULT_DUMP.is_dir(), "no game_dumped_files")
    def test_us_files_up_to_date(self):
        self.assertEqual(identify.file_list(DEFAULT_DUMP), identify.known_files(),
                         "dwconvert/us_files.json is stale: python -m dwconvert files")

    def test_extract_command(self):
        with tempfile.TemporaryDirectory() as d:
            self.assertEqual(main(["extract", str(REAL), d]), 0)
            out = Path(d)
            self.assertFalse((out / "MOVIE").exists(), "movies skipped by default")
            self.assertEqual(hashlib.sha1((out / "SLUS_010.32").read_bytes()).hexdigest(),
                             identify.known_files()["SLUS_010.32"]["sha1"])
            self.assertEqual(sum(1 for p in out.rglob("*") if p.is_file()), 814)


if __name__ == "__main__":
    unittest.main()
