"""WAV writer (16-bit PCM), with an optional `smpl` chunk for loop points. Stdlib only."""

import struct
from pathlib import Path


def encode(samples: list, rate: int, loop: tuple = None, root_note: int = 60, channels: int = 1) -> bytes:
    """`samples` interleaved when channels > 1; `loop` = (start, end) in frames, end exclusive."""
    data = struct.pack(f"<{len(samples)}h", *samples)
    fmt = struct.pack("<HHIIHH", 1, channels, rate, rate * 2 * channels, 2 * channels, 16)
    chunks = b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    if loop is not None:
        start, end = loop
        smpl = struct.pack("<9I", 0, 0, round(1e9 / rate), root_note, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, start, end - 1, 0, 0)  # forward loop, end inclusive
        chunks += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    return b"RIFF" + struct.pack("<I", 4 + len(chunks)) + b"WAVE" + chunks


def encode_stereo(left: list, right: list, rate: int) -> bytes:
    inter = [0] * (2 * len(left))
    inter[0::2], inter[1::2] = left, right
    return encode(inter, rate, channels=2)


def write(path: Path, wav: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(wav)
