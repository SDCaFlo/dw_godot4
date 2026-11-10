"""PSX disc images: sectors, the ISO 9660 file tree, file extraction (specs/disc_image.md). Standard
library only."""

import os
import re
import struct
from pathlib import Path

RAW = 2352
COOKED = 2048
FORM2 = 2324
SYNC = b"\x00" + b"\xff" * 10 + b"\x00"


class ImageError(Exception):
    pass


class Image:
    """A data track: read_sector(lba) -> (data, form). form is 1 or 2 (mode 2), 1 for mode 1 and cooked."""

    def __init__(self, path: Path, sector_size: int, mode: int, offset: int = 0):
        self.path, self.sector_size, self.mode, self.offset = Path(path), sector_size, mode, offset
        self._f = open(self.path, "rb")
        self.sectors = (os.path.getsize(self.path) - offset) // sector_size

    def close(self):
        self._f.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()

    def raw(self, lba: int) -> bytes:
        if not 0 <= lba < self.sectors:
            raise ImageError(f"sector {lba} outside the image ({self.sectors} sectors)")
        self._f.seek(self.offset + lba * self.sector_size)
        return self._f.read(self.sector_size)

    def read_sector(self, lba: int) -> tuple:
        s = self.raw(lba)
        if self.sector_size == COOKED:
            return s, 1
        if self.mode == 1:
            return s[16:16 + COOKED], 1
        submode = s[18]
        if submode & 0x20:
            return s[24:24 + FORM2], 2
        return s[24:24 + COOKED], 1


def _msf_to_frames(msf: str) -> int:
    m, s, f = (int(x) for x in msf.split(":"))
    return (m * 60 + s) * 75 + f


def open_image(path) -> Image:
    """A .cue, .bin / .img or .iso (specs/disc_image.md §1)."""
    path = Path(path)
    ext = path.suffix.lower()
    if ext == ".cue":
        return _open_cue(path)
    if ext in (".bin", ".img", ".iso"):
        size = os.path.getsize(path)
        if ext != ".iso" and size % RAW == 0:
            with open(path, "rb") as f:
                f.seek(16 * RAW)
                head = f.read(16)
            if head[:12] == SYNC:
                return Image(path, RAW, head[15])
        if size % COOKED == 0:
            return Image(path, COOKED, 1)
        raise ImageError(f"{path.name}: {size} bytes is neither 2352- nor 2048-byte sectors")
    raise ImageError(f"{path.name}: {ext or 'no extension'} images are not supported; use .cue / .bin or .iso "
                     "(convert .chd, .ecm or .pbp to .bin / .cue first)")


def _open_cue(cue: Path) -> Image:
    text = cue.read_text(encoding="utf-8", errors="replace")
    files = re.findall(r'^\s*FILE\s+"?(.+?)"?\s+(\w+)\s*$', text, re.M)
    if not files:
        raise ImageError(f"{cue.name}: no FILE line")
    tracks = re.findall(r"^\s*TRACK\s+(\d+)\s+(\S+)\s*$", text, re.M)
    if not tracks:
        raise ImageError(f"{cue.name}: no TRACK line")
    _, kind = tracks[0]
    kinds = {"MODE2/2352": (RAW, 2), "MODE1/2352": (RAW, 1), "MODE1/2048": (COOKED, 1)}
    if kind.upper() not in kinds:
        raise ImageError(f"{cue.name}: the first track is {kind}, not a data track (MODE2/2352, MODE1/2352, MODE1/2048)")
    index = re.search(r"^\s*INDEX\s+01\s+(\d+:\d+:\d+)", text, re.M)
    if index and _msf_to_frames(index.group(1)) != 0:
        raise ImageError(f"{cue.name}: the data track starts at {index.group(1)}, expected 00:00:00")
    data = (cue.parent / files[0][0])
    if not data.is_file():
        raise ImageError(f"{cue.name}: {files[0][0]} not found next to it")
    size, mode = kinds[kind.upper()]
    return Image(data, size, mode)


# -- ISO 9660 ----------------------------------------------------------------------------------

class Entry:
    def __init__(self, path: str, lba: int, length: int, is_dir: bool):
        self.path, self.lba, self.length, self.is_dir = path, lba, length, is_dir

    def __repr__(self):
        return f"Entry({self.path!r}, lba={self.lba}, length={self.length})"


def _records(img: Image, lba: int, length: int):
    for k in range((length + COOKED - 1) // COOKED):
        data, _ = img.read_sector(lba + k)
        o = 0
        while o < COOKED and data[o]:
            n = data[o]
            yield data[o:o + n]
            o += n


def files(img: Image) -> list:
    """Every file of the image (no directories), sorted by path."""
    pvd, _ = img.read_sector(16)
    if pvd[:6] != b"\x01CD001":
        raise ImageError("no ISO 9660 volume descriptor at sector 16")
    root = pvd[156:156 + 34]
    out, todo = [], [("", struct.unpack_from("<I", root, 2)[0], struct.unpack_from("<I", root, 10)[0])]
    seen = set()
    while todo:
        prefix, lba, length = todo.pop()
        if lba in seen:
            raise ImageError(f"directory loop at sector {lba}")
        seen.add(lba)
        for rec in _records(img, lba, length):
            name = rec[33:33 + rec[32]]
            if name in (b"\x00", b"\x01"):
                continue
            name = name.decode("ascii", errors="replace").split(";")[0]
            e_lba, e_len, flags = struct.unpack_from("<I", rec, 2)[0], struct.unpack_from("<I", rec, 10)[0], rec[25]
            path = f"{prefix}{name}"
            if flags & 2:
                todo.append((path + "/", e_lba, e_len))
            else:
                out.append(Entry(path, e_lba, e_len, False))
    return sorted(out, key=lambda e: e.path)


def read_file(img: Image, entry: Entry) -> bytes:
    """A file's bytes as the dump has them (§3): each sector's data part; cut at the data length when the
    file has no form 2 sector."""
    parts, form2 = [], False
    for k in range((entry.length + COOKED - 1) // COOKED):
        data, form = img.read_sector(entry.lba + k)
        form2 |= form == 2
        parts.append(data)
    out = b"".join(parts)
    return out if form2 else out[:entry.length]


def has_form2(img: Image, entry: Entry) -> bool:
    return img.sector_size == RAW and img.mode == 2 and any(
        img.read_sector(entry.lba + k)[1] == 2 for k in range((entry.length + COOKED - 1) // COOKED))


def extract(img: Image, dest, skip=(), progress=None) -> list:
    """Writes every file under dest (folder structure kept); returns the paths written. `skip`: path
    prefixes to leave out ("MOVIE/"); progress(done, total, path) after each file."""
    dest = Path(dest)
    todo = [e for e in files(img) if not any(e.path.startswith(p) for p in skip)]
    written = []
    for k, e in enumerate(todo):
        target = dest / e.path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(read_file(img, e))
        written.append(e.path)
        if progress:
            progress(k + 1, len(todo), e.path)
    return written
