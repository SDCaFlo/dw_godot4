"""Output writing: converted files plus identity metadata.

Every asset gets a sidecar `<name>.json` next to its output files, and every run
writes a `manifest.json` for its family. Both are deterministic (sorted keys, no
timestamps), so re-running on the same input gives identical files.

Sidecar schema (keys common to all assets):
    asset_id     "<source path>@0x<offset>", stable across runs
    family       converter that produced it (e.g. "card_all")
    format       original format (e.g. "TIM")
    source       path / offset / size / sha1 of the bytes, plus size / sha1 of the whole file
    psxprev_name name PSXPrev would give the same data, for cross-checking
    outputs      generated files, relative to the family folder
    + format-specific keys (e.g. "tim", "vram"; "tmd", "textures") and family-specific keys
"""

import json
import shutil
from pathlib import Path

from . import __version__
from .exporters import png
from .formats import tim as timfmt
from .source import SourceSpan


def _dump(path: Path, obj) -> None:
    """One top-level key per line (easy to skim), each value as compact JSON."""
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"  {json.dumps(k)}: {json.dumps(v, sort_keys=True, separators=(',', ':'))}" for k, v in sorted(obj.items())]
    path.write_text("{\n" + ",\n".join(lines) + "\n}\n", encoding="utf-8")


def _tmd_record(tmd) -> dict:
    """Raw TMD values: the lossless source of a model (vertices/normals as stored i16)."""
    return {
        "offset": tmd.offset,
        "flags": tmd.flags,
        "size": tmd.size,
        "objects": [dict(o.header_info(), vertices=[list(v) for v in o.vertices],
                         normals=[list(n) for n in o.normals],
                         primitives=[p.to_dict() for p in o.primitives]) for o in tmd.objects],
    }


def _model_outputs(writer, result: dict) -> tuple:
    outputs = [{"path": writer._rel(result["files"][0]), "kind": "model", "encoding": "gltf2"},
               {"path": writer._rel(result["files"][1]), "kind": "model_buffer", "encoding": "gltf2_bin"}]
    textures = []
    for t in result["textures"]:
        t = dict(t)
        if t["path"] is not None:
            t["path"] = writer._rel(t["path"])
            outputs.append({"path": t["path"], "kind": "texture_page", "encoding": "rgba8"})
        if t.get("stp_path") is not None:
            t["stp_path"] = writer._rel(t["stp_path"])
            outputs.append({"path": t["stp_path"], "kind": "stp_mask", "encoding": "gray8"})
        textures.append(t)
    return outputs, textures


class Check:
    def __init__(self, name: str, passed: bool, detail: str = ""):
        self.name, self.passed, self.detail = name, passed, detail

    def to_dict(self) -> dict:
        return {"name": self.name, "passed": self.passed, "detail": self.detail}


class AssetWriter:
    def __init__(self, output_root: Path, family: str, spec: str = None, code_refs: list = None):
        self.output_root = output_root.resolve()
        self.family = family
        self.dir = self.output_root / family
        self.spec = spec
        self.code_refs = code_refs or []
        self.assets = []
        self.checks = []

    def reset(self) -> None:
        """Delete this family's previous output so stale files never survive a run."""
        if self.dir.exists():
            if self.output_root not in self.dir.resolve().parents:
                raise RuntimeError(f"refusing to delete {self.dir}: not inside {self.output_root}")
            # Empty the folder rather than removing it: on Windows a folder that is open in a
            # shell, Explorer or the Godot editor cannot be removed, but its contents can.
            for child in self.dir.iterdir():
                if child.is_dir():
                    shutil.rmtree(child)
                else:
                    child.unlink()
        self.dir.mkdir(parents=True, exist_ok=True)

    def check(self, name: str, passed: bool, detail: str = "") -> bool:
        self.checks.append(Check(name, bool(passed), detail))
        return bool(passed)

    def write_tim(self, name: str, span: SourceSpan, tim: timfmt.Tim, extra: dict = None) -> dict:
        """Write a TIM as PNG(s) + sidecar. `name` is relative to the family folder, without extension."""
        outputs = []
        base = self.dir / name

        if tim.bpp <= 8:
            pixels = timfmt.indices(tim)
            for i in range(tim.clut.height):
                suffix = "" if i == 0 else f".p{i}"
                path = base.with_name(f"{base.name}{suffix}.png")
                png.write(path, png.encode_indexed(tim.width, tim.height, pixels, timfmt.palette_rgba(tim, i)))
                outputs.append({"path": self._rel(path), "kind": "image", "encoding": f"indexed{tim.bpp}", "palette": i})
        else:
            rgba, stp = timfmt.direct_rgba(tim)
            path = base.with_name(f"{base.name}.png")
            png.write(path, png.encode_rgba(tim.width, tim.height, rgba))
            outputs.append({"path": self._rel(path), "kind": "image", "encoding": "rgba8"})
            if stp is not None:
                path = base.with_name(f"{base.name}.stp.png")
                png.write(path, png.encode_gray(tim.width, tim.height, stp))
                outputs.append({"path": self._rel(path), "kind": "stp_mask", "encoding": "gray8"})

        record = {
            "asset_id": span.asset_id,
            "family": self.family,
            "format": "TIM",
            "source": span.identity(),
            "psxprev_name": span.psxprev_name,
            "outputs": outputs,
            "tim": tim.header_info(),
            "vram": tim.vram_info(),
        }
        if extra:
            record.update(extra)
        _dump(base.with_name(f"{base.name}.json"), record)
        self.assets.append({"asset_id": span.asset_id, "sidecar": self._rel(base.with_name(f"{base.name}.json")),
                            "outputs": [o["path"] for o in outputs]})
        return record

    def write_tmd(self, name: str, span: SourceSpan, tmd, vram=None, extra: dict = None) -> dict:
        """Write a TMD as glTF (+ texture pages built from `vram`) + sidecar with the full raw model data."""
        from . import models

        base = self.dir / name
        result = models.build(base, span.asset_id, tmd, vram)
        outputs, textures = _model_outputs(self, result)

        record = {
            "asset_id": span.asset_id,
            "family": self.family,
            "format": "TMD",
            "source": span.identity(),
            "psxprev_name": span.psxprev_name,
            "outputs": outputs,
            "textures": textures,
            "tmd": _tmd_record(tmd),
        }
        if extra:
            record.update(extra)
        sidecar = base.with_name(f"{base.name}.json")
        _dump(sidecar, record)
        self.assets.append({"asset_id": span.asset_id, "sidecar": self._rel(sidecar),
                            "outputs": [o["path"] for o in outputs]})
        return record

    def write_mmd(self, name: str, span: SourceSpan, mmd, vram, skeleton: list, rest: list, animations: list,
                  extra: dict = None) -> dict:
        """Write a Digimon model as glTF with bone hierarchy and animations + sidecar with all raw data."""
        from . import models

        base = self.dir / name
        result = models.build_skeletal(base, span.asset_id, mmd.tmd, vram, skeleton, rest, animations,
                                       {"digimon": (extra or {}).get("digimon")})
        outputs, textures = _model_outputs(self, result)
        record = {
            "asset_id": span.asset_id,
            "family": self.family,
            "format": "MMD",
            "source": span.identity(),
            "psxprev_name": span.psxprev_name,
            "outputs": outputs,
            "textures": textures,
            "animation_keys": result["animation_keys"],
            "mmd": {
                "tmd_offset": mmd.tmd_offset,
                "anim_offset": mmd.anim_offset,
                "anim_table": mmd.table,
                # Raw animations (header + instructions with file offsets), keyed by table offset.
                "animations": {str(rel): {"offset": a.offset, "frame_count": a.frame_count,
                                          "has_scale": a.has_scale, "initial": a.initial,
                                          "instructions": a.instructions, "end": a.end}
                               for rel, a in sorted(mmd.animations.items())},
            },
            "tmd": _tmd_record(mmd.tmd),
        }
        if extra:
            record.update(extra)
        sidecar = base.with_name(f"{base.name}.json")
        _dump(sidecar, record)
        self.assets.append({"asset_id": span.asset_id, "sidecar": self._rel(sidecar),
                            "outputs": [o["path"] for o in outputs]})
        return record

    def finish(self, sources: list, extra: dict = None) -> dict:
        manifest = {
            "family": self.family,
            "porter_version": __version__,
            "spec": self.spec,
            "code_refs": self.code_refs,
            "sources": [s.file_identity() for s in sources],
            "checks": [c.to_dict() for c in self.checks],
            "assets": sorted(self.assets, key=lambda a: a["asset_id"]),
        }
        if extra:
            manifest.update(extra)
        _dump(self.dir / "manifest.json", manifest)
        return manifest

    @property
    def ok(self) -> bool:
        return all(c.passed for c in self.checks)

    def _rel(self, path: Path) -> str:
        return path.resolve().relative_to(self.dir).as_posix()
