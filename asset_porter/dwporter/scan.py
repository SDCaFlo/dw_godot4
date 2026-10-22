"""Generic scan: find standard blocks (TIM) anywhere in a file, like PSXPrev.

Used to explore a file before writing its spec, and to cross-check PSXPrev.
Output goes to output/scan/<source path>/<psxprev name>.png + .json.
"""

from .assets import AssetWriter
from .formats import tim as timfmt
from .source import SourceFile


def scan_files(input_root, output_root, paths: list, align: int = 4, dry_run: bool = False) -> list:
    results = []
    for path in paths:
        src = SourceFile.open(input_root, path)
        out = AssetWriter(output_root, f"scan/{src.path}", code_refs=[])
        if not dry_run:
            out.reset()
        found = list(timfmt.scan(src.data, align=align))
        for tim in found:
            span = src.span(tim.offset, tim.size)
            if not dry_run:
                out.write_tim(span.psxprev_name, span, tim)
        if not dry_run:
            out.finish([src])
        results.append((src, found))
    return results
