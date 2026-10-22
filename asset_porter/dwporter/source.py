"""Access to the dumped disc files.

Every byte range read through here carries its identity: the file path relative
to the input root, the offset and the size. Converters attach this to their
outputs so any asset can be traced back to the original data.
"""

import hashlib
from dataclasses import dataclass
from pathlib import Path


def sha1(data: bytes) -> str:
    return hashlib.sha1(data).hexdigest()


@dataclass(frozen=True)
class SourceFile:
    root: Path
    path: str  # relative to root, forward slashes, e.g. "CARD/CARD.ALL"
    data: bytes

    @classmethod
    def open(cls, root: Path, path: str) -> "SourceFile":
        path = path.replace("\\", "/")
        data = (root / path).read_bytes()
        return cls(root, path, data)

    @property
    def name(self) -> str:
        return self.path.rsplit("/", 1)[-1]

    @property
    def size(self) -> int:
        return len(self.data)

    def file_identity(self) -> dict:
        return {"path": self.path, "size": self.size, "sha1": sha1(self.data)}

    def span(self, offset: int, size: int) -> "SourceSpan":
        if offset < 0 or size < 0 or offset + size > self.size:
            raise ValueError(f"{self.path}: span 0x{offset:X}+0x{size:X} out of bounds (size 0x{self.size:X})")
        return SourceSpan(self, offset, size)


@dataclass(frozen=True)
class SourceSpan:
    file: SourceFile
    offset: int
    size: int

    @property
    def data(self) -> bytes:
        return self.file.data[self.offset:self.offset + self.size]

    @property
    def asset_id(self) -> str:
        """Stable id, e.g. "CARD/CARD.ALL@0x7000"."""
        return f"{self.file.path}@0x{self.offset:X}"

    @property
    def psxprev_name(self) -> str:
        """Name PSXPrev gives a result found at this offset (hex suffix, none at 0)."""
        return self.file.name if self.offset == 0 else f"{self.file.name}_{self.offset:X}"

    def identity(self) -> dict:
        return {
            "path": self.file.path,
            "offset": self.offset,
            "offset_hex": f"0x{self.offset:X}",
            "size": self.size,
            "sha1": sha1(self.data),
            "file_size": self.file.size,
            "file_sha1": sha1(self.file.data),
        }
