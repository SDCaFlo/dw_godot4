"""Minimal SoundFont 2 writer (stdlib only), used for preview banks of VAB instruments.

Samples are 16-bit mono. Each preset has one zone pointing at one instrument; each instrument zone
has a key range, root key, fine tune, pan, attenuation, loop mode and its sample.
"""

import struct
from pathlib import Path

# SF2 generator ids
KEY_RANGE, PAN, RELEASE_VOL_ENV, INSTRUMENT, INITIAL_ATTENUATION, FINE_TUNE, SAMPLE_ID, SAMPLE_MODES, \
    ROOT_KEY = 43, 17, 38, 41, 48, 52, 53, 54, 58


def _chunk(kind: bytes, payload: bytes) -> bytes:
    pad = b"\0" if len(payload) % 2 else b""
    return kind + struct.pack("<I", len(payload)) + payload + pad


def _list(kind: bytes, chunks: list) -> bytes:
    body = kind + b"".join(chunks)
    return b"LIST" + struct.pack("<I", len(body)) + body


def _name(s: str, size: int = 20) -> bytes:
    return s.encode("ascii", "replace")[:size - 1].ljust(size, b"\0")


def _gen(op: int, amount: int) -> bytes:
    return struct.pack("<Hh", op, amount)


def _gen_range(lo: int, hi: int) -> bytes:
    return struct.pack("<HBB", KEY_RANGE, lo, hi)


def build(name: str, samples: list, instruments: list, presets: list) -> bytes:
    """samples: dicts {name, data (list of int16), rate, root, loop (start, end) or None}.
    instruments: dicts {name, zones: [{sample, key_lo, key_hi, root, fine_tune, pan, attenuation, loop}]}.
    presets: dicts {name, program, bank, instrument}.
    """
    smpl, shdr = bytearray(), bytearray()
    for s in samples:
        start = len(smpl) // 2
        smpl += struct.pack(f"<{len(s['data'])}h", *s["data"]) + bytes(46 * 2)
        end = start + len(s["data"])
        loop = s.get("loop") or (0, 0)
        ls, le = (start + loop[0], start + loop[1]) if s.get("loop") else (start, start)
        shdr += _name(s["name"]) + struct.pack("<5IBbHH", start, end, ls, le, s["rate"], s["root"], 0, 0, 1)
    shdr += _name("EOS") + bytes(26)

    inst, ibag, igen = bytearray(), bytearray(), bytearray()
    for i in instruments:
        inst += _name(i["name"]) + struct.pack("<H", len(ibag) // 4)
        for z in i["zones"]:
            ibag += struct.pack("<HH", len(igen) // 4, 0)
            igen += _gen_range(z["key_lo"], z["key_hi"])
            igen += _gen(PAN, z["pan"]) + _gen(INITIAL_ATTENUATION, z["attenuation"])
            igen += _gen(RELEASE_VOL_ENV, -2000)  # ~0.3 s release so keys don't ring forever
            igen += _gen(FINE_TUNE, z["fine_tune"]) + _gen(ROOT_KEY, z["root"])
            igen += _gen(SAMPLE_MODES, 1 if z["loop"] else 0) + _gen(SAMPLE_ID, z["sample"])
    inst += _name("EOI") + struct.pack("<H", len(ibag) // 4)
    ibag += struct.pack("<HH", len(igen) // 4, 0)
    igen += bytes(4)

    phdr, pbag, pgen = bytearray(), bytearray(), bytearray()
    for p in presets:
        phdr += _name(p["name"]) + struct.pack("<HHHIII", p["program"], p["bank"], len(pbag) // 4, 0, 0, 0)
        pbag += struct.pack("<HH", len(pgen) // 4, 0)
        pgen += _gen(INSTRUMENT, p["instrument"])
    phdr += _name("EOP") + struct.pack("<HHHIII", 0, 0, len(pbag) // 4, 0, 0, 0)
    pbag += struct.pack("<HH", len(pgen) // 4, 0)
    pgen += bytes(4)

    info = _list(b"INFO", [_chunk(b"ifil", struct.pack("<HH", 2, 1)), _chunk(b"isng", b"EMU8000\0"),
                           _chunk(b"INAM", name.encode("ascii", "replace") + b"\0")])
    sdta = _list(b"sdta", [_chunk(b"smpl", bytes(smpl))])
    pdta = _list(b"pdta", [_chunk(b"phdr", bytes(phdr)), _chunk(b"pbag", bytes(pbag)), _chunk(b"pmod", bytes(10)),
                           _chunk(b"pgen", bytes(pgen)), _chunk(b"inst", bytes(inst)), _chunk(b"ibag", bytes(ibag)),
                           _chunk(b"imod", bytes(10)), _chunk(b"igen", bytes(igen)), _chunk(b"shdr", bytes(shdr))])
    body = b"sfbk" + info + sdta + pdta
    return b"RIFF" + struct.pack("<I", len(body)) + body


def write(path: Path, data: bytes) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(data)
