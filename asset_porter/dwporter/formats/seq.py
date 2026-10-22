"""Sony SEQ sequences ("pQES", libsnd SsSeqOpen) and their conversion to Standard MIDI. Spec: specs/sound.md.

Layout: "pQES", u32 BE version, u16 BE resolution (ticks per quarter), u24 BE tempo (us per quarter),
u8 rhythm numerator, u8 rhythm denominator (power of two), then a MIDI event stream (delta time as
variable-length, running status). Meta events differ from SMF: tempo is FF 51 + 3 bytes and the end
is FF 2F, both without a length byte.
"""

import struct

MAGIC = b"pQES"
HEADER_SIZE = 15
# libsnd loop markers: NRPN (CC 99) value 20 = loop start, 30 = loop end; CC 6 = loop count.
NRPN_LOOP_START = 20
NRPN_LOOP_END = 30


class SeqError(ValueError):
    pass


def _varlen(data: bytes, p: int) -> tuple:
    value = 0
    for _ in range(4):
        b = data[p]
        p += 1
        value = (value << 7) | (b & 0x7F)
        if not b & 0x80:
            return value, p
    raise SeqError(f"bad variable-length number at 0x{p:X}")


def _encode_varlen(value: int) -> bytes:
    out = [value & 0x7F]
    value >>= 7
    while value:
        out.append(0x80 | (value & 0x7F))
        value >>= 7
    return bytes(reversed(out))


def parse(data: bytes, offset: int = 0) -> dict:
    """Parse one SEQ at `offset`; returns header fields, events (with absolute ticks) and its size."""
    if data[offset:offset + 4] != MAGIC:
        raise SeqError(f"no pQES at 0x{offset:X}")
    version = struct.unpack_from(">I", data, offset + 4)[0]
    resolution = struct.unpack_from(">H", data, offset + 8)[0]
    tempo = int.from_bytes(data[offset + 10:offset + 13], "big")
    numerator, denominator = data[offset + 13], data[offset + 14]
    p, tick, status, events = offset + HEADER_SIZE, 0, None, []
    channels, notes, loops = set(), 0, []
    while True:
        delta, p = _varlen(data, p)
        tick += delta
        b = data[p]
        if b & 0x80:
            status = b
            p += 1
        elif status is None:
            raise SeqError(f"running status without a status byte at 0x{p:X}")
        if status == 0xFF:
            kind = data[p]
            if kind == 0x2F:
                events.append({"tick": tick, "meta": "end"})
                p += 1
                break
            if kind == 0x51:
                value = int.from_bytes(data[p + 1:p + 4], "big")
                events.append({"tick": tick, "meta": "tempo", "value": value})
                p += 4
                continue
            raise SeqError(f"unknown meta 0x{kind:02X} at 0x{p:X}")
        kind = status & 0xF0
        size = 1 if kind in (0xC0, 0xD0) else 2
        if kind == 0xF0:
            raise SeqError(f"system message 0x{status:02X} at 0x{p:X}")
        args = list(data[p:p + size])
        p += size
        channels.add(status & 0x0F)
        if kind == 0x90 and args[1]:
            notes += 1
        if kind == 0xB0 and args[0] == 99 and args[1] in (NRPN_LOOP_START, NRPN_LOOP_END):
            loops.append({"tick": tick, "kind": "start" if args[1] == NRPN_LOOP_START else "end"})
        events.append({"tick": tick, "status": status, "args": args})
    return {"offset": offset, "size": p - offset, "version": version, "resolution": resolution,
            "tempo": tempo, "rhythm": [numerator, denominator], "events": events, "ticks": tick,
            "channels": sorted(channels), "notes": notes, "loop_markers": loops}


def to_midi(seq: dict) -> bytes:
    """Standard MIDI file (format 0) with the same events; SEQ metas get their SMF length bytes.

    No time signature is written: the SEQ rhythm bytes (e.g. 01 04) do not map to SMF's encoding
    and do not affect playback; they stay in the JSON.
    """
    track = bytearray()
    track += b"\x00\xFF\x51\x03" + seq["tempo"].to_bytes(3, "big")
    last = 0
    for e in seq["events"]:
        track += _encode_varlen(e["tick"] - last)
        last = e["tick"]
        if e.get("meta") == "end":
            track += b"\xFF\x2F\x00"
        elif e.get("meta") == "tempo":
            track += b"\xFF\x51\x03" + e["value"].to_bytes(3, "big")
        else:
            track += bytes([e["status"]] + e["args"])
    header = b"MThd" + struct.pack(">IHHH", 6, 0, 1, seq["resolution"])
    return header + b"MTrk" + struct.pack(">I", len(track)) + bytes(track)


def parse_table(data: bytes) -> list:
    """FAALL sequence section: u32 offsets (count = first offset / 4), each to a SEQ."""
    count = struct.unpack_from("<I", data, 0)[0] // 4
    return list(struct.unpack_from(f"<{count}I", data, 0))
