"""Output writing: table JSON files, group manifest, catalog.json, human reports.

Every table file has the same top-level keys (see CLAUDE.md "Output"):
    table    {"name", "purpose"}
    source   decomp files (path, size, sha1) and C symbols / files the values come from
    schema   meaning of every field of the records
    records  the values (original index = id; nothing dropped)
    used_by  C functions / data that read the table (file:line)
    godot    how the Godot side reads it
Output is deterministic (no timestamps, fixed key order) so re-runs give identical files.
"""

import json
import shutil
from pathlib import Path

from . import __version__

TABLE_KEYS = ("table", "source", "schema", "records", "used_by", "godot")


def dump_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


class Check:
    def __init__(self, name: str, passed: bool, detail: str = ""):
        self.name, self.passed, self.detail = name, passed, detail

    def to_dict(self) -> dict:
        return {"name": self.name, "passed": self.passed, "detail": self.detail}


class GroupWriter:
    def __init__(self, output_root: Path, group: str, spec: str, purpose: str):
        self.output_root = Path(output_root).resolve()
        self.group = group
        self.spec = spec
        self.purpose = purpose
        self.dir = self.output_root / group
        self.tables = []   # catalog entries
        self.reports = []
        self.checks = []

    def reset(self) -> None:
        """Delete this group's previous output so stale files never survive a run."""
        if self.dir.exists():
            if self.output_root not in self.dir.resolve().parents:
                raise RuntimeError(f"refusing to delete {self.dir}: not inside {self.output_root}")
            # Empty the folder rather than removing it (Windows cannot remove an open folder).
            for child in self.dir.iterdir():
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        self.dir.mkdir(parents=True, exist_ok=True)

    def check(self, name: str, passed: bool, detail: str = "") -> bool:
        self.checks.append(Check(name, bool(passed), detail))
        return bool(passed)

    @property
    def ok(self) -> bool:
        return all(c.passed for c in self.checks)

    def write_table(self, name: str, table: dict, symbols: list = None) -> Path:
        """Write `<group>/<name>.json`; `name` is the table name relative to the group (e.g. "main/item")."""
        missing = [k for k in TABLE_KEYS if k not in table]
        if missing:
            raise ValueError(f"table {name}: missing keys {missing}")
        ordered = {k: table[k] for k in TABLE_KEYS}
        ordered.update({k: v for k, v in table.items() if k not in TABLE_KEYS})
        path = self.dir / f"{name}.json"
        dump_json(path, ordered)
        self.tables.append({
            "table": f"{self.group}/{name}",
            "group": self.group,
            "file": path.relative_to(self.output_root).as_posix(),
            "purpose": table["table"].get("purpose", ""),
            "spec": self.spec,
            "symbols": symbols or [],
        })
        return path

    def write_report(self, name: str, markdown: str) -> Path:
        """Human-readable sheet (Markdown) for VERIFY.md."""
        path = self.dir / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(markdown, encoding="utf-8")
        self.reports.append(path.relative_to(self.output_root).as_posix())
        return path

    def finish(self, sources: list, extra: dict = None) -> dict:
        """Write `<group>/manifest.json` and merge this group into `catalog.json`."""
        passed = sum(c.passed for c in self.checks)
        manifest = {
            "group": self.group,
            "porter_version": __version__,
            "spec": self.spec,
            "purpose": self.purpose,
            "sources": sources,
            "checks": [c.to_dict() for c in self.checks],
            "tables": [t["table"] for t in self.tables],
            "reports": self.reports,
        }
        if extra:
            manifest.update(extra)
        dump_json(self.dir / "manifest.json", manifest)

        catalog_path = self.output_root / "catalog.json"
        catalog = {}
        if catalog_path.is_file():
            try:
                catalog = json.loads(catalog_path.read_text(encoding="utf-8"))
            except ValueError:
                catalog = {}
        groups = {k: v for k, v in catalog.get("groups", {}).items() if k != self.group}
        groups[self.group] = {
            "purpose": self.purpose,
            "spec": self.spec,
            "manifest": f"{self.group}/manifest.json",
            "reports": self.reports,
            "checks": {"passed": passed, "total": len(self.checks)},
        }
        tables = [t for t in catalog.get("tables", []) if t.get("group") != self.group] + self.tables
        catalog = {
            "generated_by": {"tool": "dwdata", "version": __version__},
            "groups": dict(sorted(groups.items())),
            "tables": sorted(tables, key=lambda t: t["table"]),
        }
        dump_json(catalog_path, catalog)
        return manifest
