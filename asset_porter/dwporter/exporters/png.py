"""Minimal PNG writer (standard library only).

Writes indexed images (palette + per-entry alpha) so that palette indices are
kept exactly, and RGBA images for direct-colour data.
"""

import struct
import zlib
from pathlib import Path


def _chunk(kind: bytes, payload: bytes) -> bytes:
    return struct.pack(">I", len(payload)) + kind + payload + struct.pack(">I", zlib.crc32(kind + payload) & 0xFFFFFFFF)


def _encode(width: int, height: int, color_type: int, rows: list, extra_chunks: list) -> bytes:
    header = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    raw = b"".join(b"\x00" + bytes(row) for row in rows)
    return (
        b"\x89PNG\r\n\x1a\n"
        + _chunk(b"IHDR", header)
        + b"".join(extra_chunks)
        + _chunk(b"IDAT", zlib.compress(raw, 9))
        + _chunk(b"IEND", b"")
    )


def encode_indexed(width: int, height: int, indices: bytes, palette_rgba: list) -> bytes:
    """indices: one byte per pixel, row-major. palette_rgba: list of (r, g, b, a)."""
    if len(indices) != width * height:
        raise ValueError("index buffer size does not match dimensions")
    if not 1 <= len(palette_rgba) <= 256:
        raise ValueError("palette must have 1..256 entries")
    rows = [indices[y * width:(y + 1) * width] for y in range(height)]
    plte = bytes(c for r, g, b, _ in palette_rgba for c in (r, g, b))
    trns = bytes(a for *_, a in palette_rgba)
    chunks = [_chunk(b"PLTE", plte)]
    if any(a != 255 for a in trns):
        chunks.append(_chunk(b"tRNS", trns.rstrip(b"\xff")))
    return _encode(width, height, 3, rows, chunks)


def encode_rgba(width: int, height: int, pixels: bytes) -> bytes:
    """pixels: 4 bytes (r, g, b, a) per pixel, row-major."""
    if len(pixels) != width * height * 4:
        raise ValueError("pixel buffer size does not match dimensions")
    stride = width * 4
    rows = [pixels[y * stride:(y + 1) * stride] for y in range(height)]
    return _encode(width, height, 6, rows, [])


def encode_gray(width: int, height: int, pixels: bytes) -> bytes:
    if len(pixels) != width * height:
        raise ValueError("pixel buffer size does not match dimensions")
    rows = [pixels[y * width:(y + 1) * width] for y in range(height)]
    return _encode(width, height, 0, rows, [])


def write(path: Path, png: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(png)
