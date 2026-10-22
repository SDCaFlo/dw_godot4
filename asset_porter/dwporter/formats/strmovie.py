"""PSX STR movies: sector layout, MDEC video bitstream (v2/v3) and XA ADPCM audio. Spec: specs/movies.md.

The dumped files keep each sector's payload: 2048 bytes for video sectors (32-byte STR header +
2016 bytes of bitstream) and 2324 bytes for XA audio sectors; a few empty 2048-byte sectors at the end.

Video bitstream (libpress DecDCTvlc, decoded by the MDEC): per frame an 8-byte header
(u16 MDEC code count / 2 rounded up to 32, u16 0x3800, u16 quantisation scale, u16 version),
then 16-bit little-endian words read MSB first. Macroblocks are 16x16, column by column; each has
6 blocks: Cr, Cb, Y top-left, top-right, bottom-left, bottom-right. Block = DC (v2: 10-bit signed;
v3: differential size code like MPEG-1) + AC run/level codes (MPEG-1 table B.14 with sign bit,
escape 000001 + 6-bit run + 10-bit level), end of block "10".

numpy, when installed, only speeds up the IDCT and colour conversion (same maths).
"""

import math
import struct

VIDEO_MAGIC = b"\x60\x01\x01\x80"
VIDEO_SECTOR = 2048
AUDIO_SECTOR = 2324
RAW_SECTOR = 2336  # FILE_OFFSET_TABLE counts STR sectors at this size
STR_HEADER = 32

try:  # optional accelerator
    import numpy as _np
except ImportError:  # pragma: no cover - stdlib fallback
    _np = None


class StrError(ValueError):
    pass


# --- sectors -----------------------------------------------------------------------------------

AUDIO_EVERY = 8  # interleave: 7 video sectors, then 1 XA audio sector


def split_sectors(data: bytes) -> list:
    """[(kind, offset, size)]: every 8th sector is XA audio (2324 bytes); the others are video
    (2048 bytes, STR header) or empty (2048 zero bytes, at the end of the stream)."""
    out, p, i = [], 0, 0
    while p < len(data):
        if i % AUDIO_EVERY == AUDIO_EVERY - 1:
            kind, size = "audio", AUDIO_SECTOR
        else:
            kind, size = ("video" if data[p:p + 4] == VIDEO_MAGIC else "empty"), VIDEO_SECTOR
            if kind == "empty" and any(data[p:p + size]):
                raise StrError(f"sector {i} at 0x{p:X} is neither video nor empty")
        if p + size > len(data):
            raise StrError(f"sector {i} at 0x{p:X} runs past the file")
        out.append((kind, p, size))
        p += size
        i += 1
    return out


def video_header(data: bytes, p: int) -> dict:
    (magic, chunk, chunks, frame, size, width, height, codes, x3800, qscale, version,
     reserved) = struct.unpack_from("<4sHHIIHHHHHHI", data, p)
    return {"chunk": chunk, "chunks": chunks, "frame": frame, "frame_size": size, "width": width, "height": height,
            "codes": codes, "magic3800": x3800, "qscale": qscale, "version": version, "reserved": reserved}


# --- video bitstream -----------------------------------------------------------------------------

# MPEG-1 table B.14 (dct_coeff_next): code -> (run, level); a sign bit follows each code.
_AC = {
    "11": (0, 1), "011": (1, 1), "0100": (0, 2), "0101": (2, 1), "00101": (0, 3), "00111": (3, 1),
    "00110": (4, 1), "000110": (1, 2), "000111": (5, 1), "000101": (6, 1), "000100": (7, 1),
    "0000110": (0, 4), "0000100": (2, 2), "0000111": (8, 1), "0000101": (9, 1),
    "00100110": (0, 5), "00100001": (0, 6), "00100101": (1, 3), "00100100": (3, 2), "00100111": (10, 1),
    "00100011": (11, 1), "00100010": (12, 1), "00100000": (13, 1),
    "0000001010": (0, 7), "0000001100": (1, 4), "0000001011": (2, 3), "0000001111": (4, 2),
    "0000001001": (5, 2), "0000001110": (14, 1), "0000001101": (15, 1), "0000001000": (16, 1),
    "000000011101": (0, 8), "000000011000": (0, 9), "000000010011": (0, 10), "000000010000": (0, 11),
    "000000011011": (1, 5), "000000010100": (2, 4), "000000011100": (3, 3), "000000010010": (4, 3),
    "000000011110": (6, 2), "000000010101": (7, 2), "000000010001": (8, 2), "000000011111": (17, 1),
    "000000011010": (18, 1), "000000011001": (19, 1), "000000010111": (20, 1), "000000010110": (21, 1),
    "0000000011010": (0, 12), "0000000011001": (0, 13), "0000000011000": (0, 14), "0000000010111": (0, 15),
    "0000000010110": (1, 6), "0000000010101": (1, 7), "0000000010100": (2, 5), "0000000010011": (3, 4),
    "0000000010010": (5, 3), "0000000010001": (9, 2), "0000000010000": (10, 2), "0000000011111": (22, 1),
    "0000000011110": (23, 1), "0000000011101": (24, 1), "0000000011100": (25, 1), "0000000011011": (26, 1),
    "00000000011111": (0, 16), "00000000011110": (0, 17), "00000000011101": (0, 18), "00000000011100": (0, 19),
    "00000000011011": (0, 20), "00000000011010": (0, 21), "00000000011001": (0, 22), "00000000011000": (0, 23),
    "00000000010111": (0, 24), "00000000010110": (0, 25), "00000000010101": (0, 26), "00000000010100": (0, 27),
    "00000000010011": (0, 28), "00000000010010": (0, 29), "00000000010001": (0, 30), "00000000010000": (0, 31),
    "000000000011000": (0, 32), "000000000010111": (0, 33), "000000000010110": (0, 34),
    "000000000010101": (0, 35), "000000000010100": (0, 36), "000000000010011": (0, 37),
    "000000000010010": (0, 38), "000000000010001": (0, 39), "000000000010000": (0, 40),
    "000000000011111": (1, 8), "000000000011110": (1, 9), "000000000011101": (1, 10),
    "000000000011100": (1, 11), "000000000011011": (1, 12), "000000000011010": (1, 13),
    "000000000011001": (1, 14), "0000000000010011": (1, 15), "0000000000010010": (1, 16),
    "0000000000010001": (1, 17), "0000000000010000": (1, 18), "0000000000010100": (6, 3),
    "0000000000011010": (11, 2), "0000000000011001": (12, 2), "0000000000011000": (13, 2),
    "0000000000010111": (14, 2), "0000000000010110": (15, 2), "0000000000010101": (16, 2),
    "0000000000011111": (27, 1), "0000000000011110": (28, 1), "0000000000011101": (29, 1),
    "0000000000011100": (30, 1), "0000000000011011": (31, 1),
}
EOB, ESCAPE = "10", "000001"
# MPEG-1 DC size codes (v3): code -> size
_DC_LUMA = {"100": 0, "00": 1, "01": 2, "101": 3, "110": 4, "1110": 5, "11110": 6, "111110": 7, "1111110": 8}
_DC_CHROMA = {"00": 0, "01": 1, "10": 2, "110": 3, "1110": 4, "11110": 5, "111110": 6, "1111110": 7,
              "11111110": 8}

ZIGZAG = [0, 1, 8, 16, 9, 2, 3, 10, 17, 24, 32, 25, 18, 11, 4, 5, 12, 19, 26, 33, 40, 48, 41, 34, 27, 20, 13, 6, 7,
          14, 21, 28, 35, 42, 49, 56, 57, 50, 43, 36, 29, 22, 15, 23, 30, 37, 44, 51, 58, 59, 52, 45, 38, 31, 39,
          46, 53, 60, 61, 54, 47, 55, 62, 63]
# PSX default intra quantisation matrix (MPEG-1 intra matrix with DC = 2), natural order
QUANT = [2, 16, 19, 22, 26, 27, 29, 34, 16, 16, 22, 24, 27, 29, 34, 37, 19, 22, 26, 27, 29, 34, 34, 38,
         22, 22, 26, 27, 29, 34, 37, 40, 22, 26, 27, 29, 32, 35, 40, 48, 26, 27, 29, 32, 35, 40, 48, 58,
         26, 27, 29, 34, 38, 46, 56, 69, 27, 29, 35, 38, 46, 56, 69, 83]


def _prefix_table(codes: dict) -> tuple:
    """(lookup by 8-bit peek -> (length, value) for codes <= 8 bits, codes longer than 8 bits)."""
    short, long_ = {}, {}
    for code, value in codes.items():
        if len(code) <= 8:
            for tail in range(1 << (8 - len(code))):
                key = code + format(tail, f"0{8 - len(code)}b") if len(code) < 8 else code
                short[key] = (len(code), value)
        else:
            long_[code] = value
    return short, long_


_AC_SHORT, _AC_LONG = _prefix_table(dict(_AC, **{EOB: "eob", ESCAPE: "escape"}))
_AC_LONG_LENGTHS = sorted({len(c) for c in _AC_LONG})


def _bits(data: bytes) -> str:
    """16-bit little-endian words, MSB first, as a '0'/'1' string."""
    n = len(data) // 2
    words = struct.unpack_from(f"<{n}H", data, 0)
    return "".join(format(w, "016b") for w in words)


def decode_bitstream(frame: bytes, width: int, height: int) -> dict:
    """Bitstream -> per block 64 dequantised coefficients (natural order) + statistics."""
    codes_field, x3800, qscale, version = struct.unpack_from("<HHHH", frame, 0)
    if version not in (2, 3):
        raise StrError(f"unsupported bitstream version {version}")
    bits = _bits(frame[8:])
    pos, n_bits = 0, len(bits)
    bits += "0" * 32  # lookahead past the last code
    mb_w, mb_h = (width + 15) // 16, (height + 15) // 16
    blocks, mdec_codes = [], 0
    last_dc = [0, 0, 0]  # v3 predictors: Y, Cb, Cr
    for _ in range(mb_w * mb_h):
        for b in range(6):  # Cr, Cb, Y0..Y3
            coeffs = [0] * 64
            if version == 2:
                dc = int(bits[pos:pos + 10], 2)
                pos += 10
                if dc >= 512:
                    dc -= 1024
            else:
                component = 2 if b == 0 else 1 if b == 1 else 0
                table = _DC_LUMA if component == 0 else _DC_CHROMA
                for length in range(2, 9):
                    size = table.get(bits[pos:pos + length])
                    if size is not None:
                        pos += length
                        break
                else:
                    raise StrError(f"bad DC code at bit {pos}")
                diff = 0
                if size:
                    raw = int(bits[pos:pos + size], 2)
                    pos += size
                    diff = raw if raw >> (size - 1) else raw - (1 << size) + 1
                last_dc[component] += diff * 4
                dc = last_dc[component]
            coeffs[0] = dc * QUANT[0]
            mdec_codes += 1
            k = 0
            while True:
                if pos >= n_bits:
                    raise StrError("bitstream ended inside a block")
                entry = _AC_SHORT.get(bits[pos:pos + 8])
                if entry is None:
                    for length in _AC_LONG_LENGTHS:
                        value = _AC_LONG.get(bits[pos:pos + length])
                        if value is not None:
                            entry = (length, value)
                            break
                    else:
                        raise StrError(f"bad AC code at bit {pos}")
                length, value = entry
                pos += length
                mdec_codes += 1
                if value == "eob":
                    break
                if value == "escape":
                    run = int(bits[pos:pos + 6], 2)
                    level = int(bits[pos + 6:pos + 16], 2)
                    pos += 16
                    if level >= 512:
                        level -= 1024
                else:
                    run, level = value
                    if bits[pos] == "1":
                        level = -level
                    pos += 1
                k += run + 1
                if k > 63:
                    raise StrError(f"coefficient index {k} past the block")
                j = ZIGZAG[k]
                coeffs[j] = (level * QUANT[j] * qscale + 4) >> 3
            blocks.append(coeffs)
    return {"blocks": blocks, "version": version, "qscale": qscale, "codes_field": codes_field, "x3800": x3800,
            "mdec_codes": mdec_codes, "bits_used": pos, "bits_total": n_bits}


# --- IDCT + colour ---------------------------------------------------------------------------------

_COS = [[(math.sqrt(0.125) if u == 0 else 0.5) * math.cos((2 * x + 1) * u * math.pi / 16) for u in range(8)]
        for x in range(8)]


def _idct_py(c: list) -> list:
    tmp = [0.0] * 64
    for v in range(8):  # columns of coefficients -> rows
        row = c[v * 8:v * 8 + 8]
        if not any(row):
            continue
        for x in range(8):
            cx = _COS[x]
            tmp[v * 8 + x] = sum(cx[u] * row[u] for u in range(8))
    out = [0.0] * 64
    for y in range(8):
        cy = _COS[y]
        for x in range(8):
            out[y * 8 + x] = sum(cy[v] * tmp[v * 8 + x] for v in range(8))
    return out


def render(decoded: dict, width: int, height: int) -> bytes:
    """Blocks -> RGB24 frame (PSX MDEC colour: signed samples + 128)."""
    mb_w, mb_h = (width + 15) // 16, (height + 15) // 16
    blocks = decoded["blocks"]
    if _np is not None:
        cos = _np.array(_COS)
        coeffs = _np.array(blocks, dtype=_np.float64).reshape(-1, 8, 8)
        pix = _np.einsum("xu,nvu,yv->nyx", cos, coeffs, cos).reshape(mb_w * mb_h, 6, 8, 8)
        cr, cb = pix[:, 0], pix[:, 1]
        y = _np.zeros((mb_w * mb_h, 16, 16))
        y[:, :8, :8], y[:, :8, 8:], y[:, 8:, :8], y[:, 8:, 8:] = pix[:, 2], pix[:, 3], pix[:, 4], pix[:, 5]
        cr = cr.repeat(2, 1).repeat(2, 2)
        cb = cb.repeat(2, 1).repeat(2, 2)
        rgb = _np.stack([y + 1.402 * cr, y - 0.3437 * cb - 0.7143 * cr, y + 1.772 * cb], -1) + 128
        rgb = _np.clip(_np.rint(rgb), 0, 255).astype(_np.uint8)
        frame = rgb.reshape(mb_w, mb_h, 16, 16, 3).transpose(1, 2, 0, 3, 4).reshape(mb_h * 16, mb_w * 16, 3)
        return frame[:height, :width].tobytes()
    out = bytearray(mb_w * 16 * mb_h * 16 * 3)
    stride = mb_w * 16 * 3
    for m in range(mb_w * mb_h):
        mx, my = divmod(m, mb_h)
        cr, cb, *ys = [_idct_py(blocks[m * 6 + b]) for b in range(6)]
        for py in range(16):
            for px in range(16):
                yv = ys[(py // 8) * 2 + px // 8][(py % 8) * 8 + px % 8]
                c = (py // 2) * 8 + px // 2
                r, g, b_ = yv + 1.402 * cr[c], yv - 0.3437 * cb[c] - 0.7143 * cr[c], yv + 1.772 * cb[c]
                o = (my * 16 + py) * stride + (mx * 16 + px) * 3
                out[o:o + 3] = bytes(max(0, min(255, round(v + 128))) for v in (r, g, b_))
    rows = [bytes(out[y * stride:y * stride + width * 3]) for y in range(height)]
    return b"".join(rows)


# --- XA audio --------------------------------------------------------------------------------------

_XA_K0 = (0, 60, 115, 98)
_XA_K1 = (0, 0, -52, -55)
XA_GROUPS = 18
XA_GROUP = 128


def decode_xa(sector: bytes, state: list) -> tuple:
    """One 2324-byte XA sector, 4-bit stereo: returns (left, right) sample lists. `state` keeps
    [l1, l2, r1, r2] between sectors."""
    left, right = [], []
    for g in range(XA_GROUPS):
        group = sector[g * XA_GROUP:(g + 1) * XA_GROUP]
        for unit in range(8):
            param = group[4 + unit]
            shift, filt = param & 0x0F, (param >> 4) & 0x03
            if shift > 12:
                shift = 9
            k0, k1 = _XA_K0[filt], _XA_K1[filt]
            ch = unit & 1
            s1, s2 = state[ch * 2], state[ch * 2 + 1]
            dst = right if ch else left
            for i in range(28):
                nibble = (group[16 + i * 4 + unit // 2] >> ((unit & 1) * 4)) & 0x0F
                s = (nibble << 12) & 0xFFFF
                if s & 0x8000:
                    s -= 0x10000
                s = (s >> shift) + ((s1 * k0 + s2 * k1 + 32) >> 6)
                s = max(-32768, min(32767, s))
                dst.append(s)
                s2, s1 = s1, s
            state[ch * 2], state[ch * 2 + 1] = s1, s2
    return left, right
