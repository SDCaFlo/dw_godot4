"""VHB sound files: offset table + VAB bank ("pBAV" header + PSX ADPCM samples). Spec: specs/sound.md.

VHB (game container, sound.c readVHBFile): u32 offsets[], count = offsets[0] / 4; section 0 = VAB
header (VH), section 1 = VAB body (VB, the samples), the last offset = end. FAALL chunks have one more
section (the SEQ table) before the end.

VAB (libsnd SsVabOpenHead): VabHdr (32 bytes), ProgAtr[128] (16 bytes), VagAtr[programs][16]
(32 bytes), u16 vag_sizes[256] (size / 8; entry 0 unused); VB = the samples back to back.
"""

import struct

VAB_MAGIC = b"pBAV"
VAB_HEADER = 32
PROGRAMS = 128
PROG_SIZE = 16
TONES_PER_PROGRAM = 16
TONE_SIZE = 32
VAG_TABLE = 256
BASE_RATE = 44100  # a tone played at its centre note plays the samples at 44.1 kHz (SPU pitch 0x1000)

_FILTERS = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]


class VabError(ValueError):
    pass


def parse_vhb(data: bytes) -> list:
    """Section offsets of a VHB (sound.c reads offsets[0] = VH, offsets[1] = VB)."""
    first = struct.unpack_from("<I", data, 0)[0]
    if first % 4 or first < 12 or first > 64:
        raise VabError(f"bad VHB header size {first}")
    return list(struct.unpack_from(f"<{first // 4}I", data, 0))


def parse_vh(data: bytes, p: int) -> dict:
    if data[p:p + 4] != VAB_MAGIC:
        raise VabError(f"no pBAV at 0x{p:X}")
    (magic, version, vab_id, fsize, rsv0, ps, ts, vs, mvol, pan, attr1, attr2,
     rsv1) = struct.unpack_from("<4sIIIHHHHBBBBI", data, p)
    header = {"version": version, "id": vab_id, "fsize": fsize, "reserved0": rsv0, "programs": ps,
              "tones": ts, "vags": vs, "master_volume": mvol, "master_pan": pan, "attr1": attr1,
              "attr2": attr2, "reserved1": rsv1}
    q = p + VAB_HEADER
    programs = []
    for i in range(PROGRAMS):
        tones, pmvol, prior, mode, mpan, r0, attr, r1, r2 = struct.unpack_from("<BBBBBBhII", data, q + i * PROG_SIZE)
        programs.append({"index": i, "tones": tones, "volume": pmvol, "priority": prior, "mode": mode, "pan": mpan,
                         "reserved0": r0, "attr": attr, "reserved1": r1, "reserved2": r2})
    q += PROGRAMS * PROG_SIZE
    tone_blocks = []
    for prog in range(ps):
        block = []
        for t in range(TONES_PER_PROGRAM):
            f = struct.unpack_from("<16BHHhh4h", data, q + (prog * TONES_PER_PROGRAM + t) * TONE_SIZE)
            block.append({"priority": f[0], "mode": f[1], "volume": f[2], "pan": f[3], "center": f[4],
                          "shift": f[5], "min": f[6], "max": f[7], "vibrato_width": f[8], "vibrato_time": f[9],
                          "portamento_width": f[10], "portamento_time": f[11], "pitchbend_min": f[12],
                          "pitchbend_max": f[13], "reserved1": f[14], "reserved2": f[15], "adsr1": f[16],
                          "adsr2": f[17], "program": f[18], "vag": f[19], "reserved": list(f[20:24])})
        tone_blocks.append(block)
    q += ps * TONES_PER_PROGRAM * TONE_SIZE
    sizes = [s * 8 for s in struct.unpack_from(f"<{VAG_TABLE}H", data, q)]
    q += VAG_TABLE * 2
    return {"header": header, "programs": programs, "tones": tone_blocks, "vag_sizes": sizes, "end": q}


def split_vags(vh: dict, body: bytes) -> list:
    """(offset in VB, bytes) for VAGs 1..vags (vag numbers used by VagAtr.vag)."""
    out, p = [], 0
    for i in range(1, vh["header"]["vags"] + 1):
        size = vh["vag_sizes"][i]
        out.append((p, body[p:p + size]))
        p += size
    return out


def decode_adpcm(data: bytes) -> dict:
    """PSX SPU ADPCM -> 16-bit PCM. Loop points from the block flags (bit 2 loop start, bit 0 end,
    bit 1 repeat). Decoding stops at the first block with the end flag, like the SPU."""
    pcm, s1, s2 = [], 0, 0
    loop_start = loop_end = None
    end_block = None
    for b in range(len(data) // 16):
        block = data[b * 16:b * 16 + 16]
        shift, filt, flags = block[0] & 0x0F, block[0] >> 4, block[1]
        if shift > 12:
            shift = 9  # reserved values behave like 9 on the SPU
        if filt > 4:
            raise VabError(f"bad filter {filt} in block {b}")
        f0, f1 = _FILTERS[filt]
        if flags & 4:
            loop_start = len(pcm)
        for byte in block[2:]:
            for nibble in (byte & 0x0F, byte >> 4):
                s = (nibble << 12) & 0xFFFF
                if s & 0x8000:
                    s -= 0x10000
                s = (s >> shift) + ((s1 * f0 + s2 * f1 + 32) >> 6)
                s = max(-32768, min(32767, s))
                pcm.append(s)
                s2, s1 = s1, s
        if flags & 1:
            end_block = b
            if flags & 2 and loop_start is not None:
                loop_end = len(pcm)
            break
    return {"samples": pcm, "loop_start": loop_start, "loop_end": loop_end, "end_block": end_block,
            "blocks": len(data) // 16}
