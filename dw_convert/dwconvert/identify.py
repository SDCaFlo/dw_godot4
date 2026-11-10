"""Is this the US disc? (specs/disc_image.md §4): the boot file named by SYSTEM.CNF, then every file's
sha1 against the committed list of the US disc's files (hashes only, no content)."""

import hashlib
import json
import re
from pathlib import Path

from . import image

US_BOOT = "SLUS_010.32"
US_FILES = Path(__file__).resolve().parent / "us_files.json"


class Report:
    def __init__(self):
        self.boot = None
        self.us = False
        self.missing, self.different, self.extra = [], [], []

    @property
    def ok(self) -> bool:
        return self.us and not self.missing and not self.different

    def message(self) -> str:
        if self.boot is None:
            return "no SYSTEM.CNF boot line: not a PlayStation game disc"
        if not self.us:
            return f"this disc boots {self.boot}: only the US release of Digimon World (SLUS-01032) is supported"
        if self.ok:
            return "Digimon World, US release (SLUS-01032): every file as expected" + (
                f" ({len(self.extra)} extra files ignored)" if self.extra else "")
        parts = []
        if self.missing:
            parts.append(f"{len(self.missing)} files missing ({', '.join(self.missing[:5])})")
        if self.different:
            parts.append(f"{len(self.different)} files differ from the US disc ({', '.join(self.different[:5])})")
        return "Digimon World US, but " + "; ".join(parts) + ": a bad or modified dump"


def boot_file(img: image.Image, entries: list):
    cnf = next((e for e in entries if e.path.upper() == "SYSTEM.CNF"), None)
    if cnf is None:
        return None
    text = image.read_file(img, cnf).decode("ascii", errors="replace")
    m = re.search(r"BOOT\s*=\s*cdrom:\\?([^;\s]+)", text, re.I)
    return m.group(1).upper() if m else None


def known_files() -> dict:
    return json.loads(US_FILES.read_text(encoding="utf-8"))["files"]


def identify(img: image.Image, skip=()) -> Report:
    """The boot file, then each file's sha1 (files under a `skip` prefix aren't hashed: they won't be
    extracted)."""
    r = Report()
    entries = image.files(img)
    r.boot = boot_file(img, entries)
    r.us = r.boot == US_BOOT
    if not r.us:
        return r
    known = known_files()
    by_path = {e.path: e for e in entries}
    for path, want in known.items():
        if any(path.startswith(p) for p in skip):
            continue
        e = by_path.get(path)
        if e is None:
            r.missing.append(path)
            continue
        data = image.read_file(img, e)
        if len(data) != want["size"] or hashlib.sha1(data).hexdigest() != want["sha1"]:
            r.different.append(path)
    r.extra = sorted(p for p in by_path if p not in known)
    return r


def file_list(folder: Path) -> dict:
    """{path: {size, sha1}} of the disc files in a dump folder (`python -m dwconvert files`)."""
    folder = Path(folder)
    out = {}
    for p in sorted(folder.rglob("*")):
        if p.is_file() and p.name != "RESOURCE_DEFINITION.md":
            data = p.read_bytes()
            out[p.relative_to(folder).as_posix()] = {"size": len(data), "sha1": hashlib.sha1(data).hexdigest()}
    return out
