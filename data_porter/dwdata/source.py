"""Source text files of the decomp, carrying their identity (path relative to the decomp, sha1)."""

import hashlib
from pathlib import Path


class SourceText:
    def __init__(self, root: Path, rel: str):
        self.root = Path(root)
        self.path = rel.replace("\\", "/")
        data = (self.root / self.path).read_bytes()
        self.sha1 = hashlib.sha1(data).hexdigest()
        self.size = len(data)
        self.text = data.decode("utf-8")

    @property
    def lines(self) -> list:
        return self.text.splitlines()

    def identity(self) -> dict:
        return {"path": self.path, "size": self.size, "sha1": self.sha1}

    def ref(self, line: int) -> str:
        return f"{self.path}:{line}"
