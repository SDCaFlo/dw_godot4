"""PSX SPU emulation for rendering music offline: ADPCM voices with loops, 4-point Gaussian
interpolation, the ADSR envelope, voice volumes and the reverb unit. Spec: specs/sound.md "Music
render" (hardware rules from psx-spx, "Sound Processing Unit (SPU)").

Everything is integer math like the hardware. Rendering works on blocks of samples (one libsnd
tick, ~184 samples) to keep pure Python fast enough:
- `AdpcmStream`: the voice's decoded samples from key-on on, with the loop jumps unrolled.
- `resampled(stream, pitch)`: the voice output before the envelope, cached per (sample, pitch),
  since it only depends on those two while the pitch doesn't change.
- `Envelope.levels(n)`: the ADSR level of each of the next n samples.
- `Reverb.process(left, right)`: the reverb unit at 22.05 kHz with the FIR resampling.
"""

from array import array

RATE = 44100

# 4-point Gaussian interpolation table (psx-spx "4-Point Gaussian Interpolation").
GAUSS = [
    -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001, -0x001,
    0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0001, 0x0001, 0x0001, 0x0001, 0x0002, 0x0002, 0x0002, 0x0003, 0x0003,
    0x0003, 0x0004, 0x0004, 0x0005, 0x0005, 0x0006, 0x0007, 0x0007, 0x0008, 0x0009, 0x0009, 0x000A, 0x000B, 0x000C, 0x000D, 0x000E,
    0x000F, 0x0010, 0x0011, 0x0012, 0x0013, 0x0015, 0x0016, 0x0018, 0x0019, 0x001B, 0x001C, 0x001E, 0x0020, 0x0021, 0x0023, 0x0025,
    0x0027, 0x0029, 0x002C, 0x002E, 0x0030, 0x0033, 0x0035, 0x0038, 0x003A, 0x003D, 0x0040, 0x0043, 0x0046, 0x0049, 0x004D, 0x0050,
    0x0054, 0x0057, 0x005B, 0x005F, 0x0063, 0x0067, 0x006B, 0x006F, 0x0074, 0x0078, 0x007D, 0x0082, 0x0087, 0x008C, 0x0091, 0x0096,
    0x009C, 0x00A1, 0x00A7, 0x00AD, 0x00B3, 0x00BA, 0x00C0, 0x00C7, 0x00CD, 0x00D4, 0x00DB, 0x00E3, 0x00EA, 0x00F2, 0x00FA, 0x0101,
    0x010A, 0x0112, 0x011B, 0x0123, 0x012C, 0x0135, 0x013F, 0x0148, 0x0152, 0x015C, 0x0166, 0x0171, 0x017B, 0x0186, 0x0191, 0x019C,
    0x01A8, 0x01B4, 0x01C0, 0x01CC, 0x01D9, 0x01E5, 0x01F2, 0x0200, 0x020D, 0x021B, 0x0229, 0x0237, 0x0246, 0x0255, 0x0264, 0x0273,
    0x0283, 0x0293, 0x02A3, 0x02B4, 0x02C4, 0x02D6, 0x02E7, 0x02F9, 0x030B, 0x031D, 0x0330, 0x0343, 0x0356, 0x036A, 0x037E, 0x0392,
    0x03A7, 0x03BC, 0x03D1, 0x03E7, 0x03FC, 0x0413, 0x042A, 0x0441, 0x0458, 0x0470, 0x0488, 0x04A0, 0x04B9, 0x04D2, 0x04EC, 0x0506,
    0x0520, 0x053B, 0x0556, 0x0572, 0x058E, 0x05AA, 0x05C7, 0x05E4, 0x0601, 0x061F, 0x063E, 0x065C, 0x067C, 0x069B, 0x06BB, 0x06DC,
    0x06FD, 0x071E, 0x0740, 0x0762, 0x0784, 0x07A7, 0x07CB, 0x07EF, 0x0813, 0x0838, 0x085D, 0x0883, 0x08A9, 0x08D0, 0x08F7, 0x091E,
    0x0946, 0x096F, 0x0998, 0x09C1, 0x09EB, 0x0A16, 0x0A40, 0x0A6C, 0x0A98, 0x0AC4, 0x0AF1, 0x0B1E, 0x0B4C, 0x0B7A, 0x0BA9, 0x0BD8,
    0x0C07, 0x0C38, 0x0C68, 0x0C99, 0x0CCB, 0x0CFD, 0x0D30, 0x0D63, 0x0D97, 0x0DCB, 0x0E00, 0x0E35, 0x0E6B, 0x0EA1, 0x0ED7, 0x0F0F,
    0x0F46, 0x0F7F, 0x0FB7, 0x0FF1, 0x102A, 0x1065, 0x109F, 0x10DB, 0x1116, 0x1153, 0x118F, 0x11CD, 0x120B, 0x1249, 0x1288, 0x12C7,
    0x1307, 0x1347, 0x1388, 0x13C9, 0x140B, 0x144D, 0x1490, 0x14D4, 0x1517, 0x155C, 0x15A0, 0x15E6, 0x162C, 0x1672, 0x16B9, 0x1700,
    0x1747, 0x1790, 0x17D8, 0x1821, 0x186B, 0x18B5, 0x1900, 0x194B, 0x1996, 0x19E2, 0x1A2E, 0x1A7B, 0x1AC8, 0x1B16, 0x1B64, 0x1BB3,
    0x1C02, 0x1C51, 0x1CA1, 0x1CF1, 0x1D42, 0x1D93, 0x1DE5, 0x1E37, 0x1E89, 0x1EDC, 0x1F2F, 0x1F82, 0x1FD6, 0x202A, 0x207F, 0x20D4,
    0x2129, 0x217F, 0x21D5, 0x222C, 0x2282, 0x22DA, 0x2331, 0x2389, 0x23E1, 0x2439, 0x2492, 0x24EB, 0x2545, 0x259E, 0x25F8, 0x2653,
    0x26AD, 0x2708, 0x2763, 0x27BE, 0x281A, 0x2876, 0x28D2, 0x292E, 0x298B, 0x29E7, 0x2A44, 0x2AA1, 0x2AFF, 0x2B5C, 0x2BBA, 0x2C18,
    0x2C76, 0x2CD4, 0x2D33, 0x2D91, 0x2DF0, 0x2E4F, 0x2EAE, 0x2F0D, 0x2F6C, 0x2FCC, 0x302B, 0x308B, 0x30EA, 0x314A, 0x31AA, 0x3209,
    0x3269, 0x32C9, 0x3329, 0x3389, 0x33E9, 0x3449, 0x34A9, 0x3509, 0x3569, 0x35C9, 0x3629, 0x3689, 0x36E8, 0x3748, 0x37A8, 0x3807,
    0x3867, 0x38C6, 0x3926, 0x3985, 0x39E4, 0x3A43, 0x3AA2, 0x3B00, 0x3B5F, 0x3BBD, 0x3C1B, 0x3C79, 0x3CD7, 0x3D35, 0x3D92, 0x3DEF,
    0x3E4C, 0x3EA9, 0x3F05, 0x3F62, 0x3FBD, 0x4019, 0x4074, 0x40D0, 0x412A, 0x4185, 0x41DF, 0x4239, 0x4292, 0x42EB, 0x4344, 0x439C,
    0x43F4, 0x444C, 0x44A3, 0x44FA, 0x4550, 0x45A6, 0x45FC, 0x4651, 0x46A6, 0x46FA, 0x474E, 0x47A1, 0x47F4, 0x4846, 0x4898, 0x48E9,
    0x493A, 0x498A, 0x49D9, 0x4A29, 0x4A77, 0x4AC5, 0x4B13, 0x4B5F, 0x4BAC, 0x4BF7, 0x4C42, 0x4C8D, 0x4CD7, 0x4D20, 0x4D68, 0x4DB0,
    0x4DF7, 0x4E3E, 0x4E84, 0x4EC9, 0x4F0E, 0x4F52, 0x4F95, 0x4FD7, 0x5019, 0x505A, 0x509A, 0x50DA, 0x5118, 0x5156, 0x5194, 0x51D0,
    0x520C, 0x5247, 0x5281, 0x52BA, 0x52F3, 0x532A, 0x5361, 0x5397, 0x53CC, 0x5401, 0x5434, 0x5467, 0x5499, 0x54CA, 0x54FA, 0x5529,
    0x5558, 0x5585, 0x55B2, 0x55DE, 0x5609, 0x5632, 0x565B, 0x5684, 0x56AB, 0x56D1, 0x56F6, 0x571B, 0x573E, 0x5761, 0x5782, 0x57A3,
    0x57C3, 0x57E2, 0x57FF, 0x581C, 0x5838, 0x5853, 0x586D, 0x5886, 0x589E, 0x58B5, 0x58CB, 0x58E0, 0x58F4, 0x5907, 0x5919, 0x592A,
    0x593A, 0x5949, 0x5958, 0x5965, 0x5971, 0x597C, 0x5986, 0x598F, 0x5997, 0x599E, 0x59A4, 0x59A9, 0x59AD, 0x59B0, 0x59B2, 0x59B3,
]
assert len(GAUSS) == 512

_FILTERS = [(0, 0), (60, 0), (115, -52), (98, -55), (122, -60)]


def _clamp16(v: int) -> int:
    return -0x8000 if v < -0x8000 else (0x7FFF if v > 0x7FFF else v)


class AdpcmStream:
    """A sample's decoded PCM from key-on, block by block like the SPU: the loop-start flag (bit 2)
    sets the loop address, loop end (bit 0) with repeat (bit 1) jumps there with the ADPCM filter
    history carried on, loop end without repeat mutes the voice (envelope 0) after that block.
    `pcm` grows on demand; `mute_at` is the sample index where the voice is muted (None if it
    loops forever)."""

    def __init__(self, data: bytes):
        self.data = data
        self.blocks = len(data) // 16
        self.pcm = array("i")
        self.mute_at = None
        self._block = 0
        self._loop = 0
        self._s1 = self._s2 = 0

    def ensure(self, n: int) -> None:
        """Decode until at least n samples exist or the voice is muted."""
        pcm, data = self.pcm, self.data
        while len(pcm) < n and self.mute_at is None:
            b = self._block
            if b >= self.blocks:  # ran off the data (no end flag): silence, like an empty voice
                self.mute_at = len(pcm)
                return
            p = b * 16
            shift, filt, flags = data[p] & 0x0F, data[p] >> 4, data[p + 1]
            if shift > 12:
                shift = 9
            f0, f1 = _FILTERS[filt] if filt <= 4 else (0, 0)
            if flags & 4:
                self._loop = b
            s1, s2 = self._s1, self._s2
            for byte in data[p + 2:p + 16]:
                for nibble in (byte & 0x0F, byte >> 4):
                    s = nibble << 12
                    if s & 0x8000:
                        s -= 0x10000
                    s = (s >> shift) + ((s1 * f0 + s2 * f1 + 32) >> 6)
                    s = -32768 if s < -32768 else (32767 if s > 32767 else s)
                    pcm.append(s)
                    s2, s1 = s1, s
            self._s1, self._s2 = s1, s2
            if flags & 1:
                if flags & 2:
                    self._block = self._loop
                else:
                    self.mute_at = len(pcm)
            else:
                self._block = b + 1


class Resampled:
    """A voice's interpolated output from key-on at a fixed pitch (before envelope and volume).
    The pitch counter starts at 0; each output sample uses counter bits 12+ (sample) and 4–11
    (Gaussian index), then the counter advances by the pitch (max 0x4000). `out` grows on demand;
    `mute_at` is the output index where the stream's mute point is reached."""

    def __init__(self, stream: AdpcmStream, pitch: int):
        self.stream = stream
        self.pitch = min(pitch, 0x4000)
        self.out = array("i")
        self.mute_at = None
        self._counter = 0

    def ensure(self, n: int) -> None:
        out, step = self.out, self.pitch
        if len(out) >= n or self.mute_at is not None:
            return
        stream = self.stream
        count = n - len(out)
        last = (self._counter + step * count) >> 12
        stream.ensure(last + 1)
        pcm, g = stream.pcm, GAUSS
        mute = stream.mute_at
        c = self._counter
        for _ in range(count):
            k = c >> 12
            if mute is not None and k >= mute:
                self.mute_at = len(out)
                break
            i = (c >> 4) & 0xFF
            s0 = pcm[k]
            s1 = pcm[k - 1] if k >= 1 else 0
            s2 = pcm[k - 2] if k >= 2 else 0
            s3 = pcm[k - 3] if k >= 3 else 0
            out.append(((g[0xFF - i] * s3) >> 15) + ((g[0x1FF - i] * s2) >> 15)
                       + ((g[0x100 + i] * s1) >> 15) + ((g[i] * s0) >> 15))
            c += step
        self._counter = c


class LiveResampler:
    """A voice whose pitch changed after key-on (pitch bend): continues from the exact counter
    position the cached stream had reached, at the new pitch."""

    def __init__(self, stream: AdpcmStream, counter: int, pitch: int):
        self.stream = stream
        self.counter = counter
        self.pitch = min(pitch, 0x4000)
        self.muted = False

    def take(self, n: int) -> list:
        """The next outputs, up to n: fewer when the mute point is reached (then `muted`)."""
        if self.muted:
            return []
        stream, c, step = self.stream, self.counter, self.pitch
        stream.ensure(((c + step * n) >> 12) + 1)
        pcm, g, mute = stream.pcm, GAUSS, stream.mute_at
        res = []
        for _ in range(n):
            k = c >> 12
            if mute is not None and k >= mute:
                self.muted = True
                break
            i = (c >> 4) & 0xFF
            s1 = pcm[k - 1] if k >= 1 else 0
            s2 = pcm[k - 2] if k >= 2 else 0
            s3 = pcm[k - 3] if k >= 3 else 0
            res.append(((g[0xFF - i] * s3) >> 15) + ((g[0x1FF - i] * s2) >> 15)
                       + ((g[0x100 + i] * s1) >> 15) + ((g[i] * pcm[k]) >> 15))
            c += step
        self.counter = c
        return res


# Envelope phases
ATTACK, DECAY, SUSTAIN, RELEASE, OFF = range(5)


class Envelope:
    """The SPU ADSR (psx-spx "Envelope Operation depending on Shift/Step/Mode/Direction"). Level
    0..0x7FFF; one counter step per 44.1 kHz cycle, a level step when counter bit 15 is set (the
    counter is then reset)."""

    __slots__ = ("adsr1", "adsr2", "phase", "level", "counter", "sustain_field")

    def __init__(self, adsr1: int, adsr2: int):
        self.adsr1, self.adsr2 = adsr1, adsr2
        self.sustain_field = adsr1 & 0xF
        self.phase, self.level, self.counter = ATTACK, 0, 0

    def key_off(self) -> None:
        if self.phase != OFF:
            self.phase, self.counter = RELEASE, 0

    def mute(self) -> None:
        """ADPCM end without repeat: release with level 0, which is silent at once (OFF)."""
        self.phase, self.level, self.counter = OFF, 0, 0

    def _params(self):
        """(rate, decreasing, exponential) of the current phase."""
        a1, a2 = self.adsr1, self.adsr2
        if self.phase == ATTACK:
            return (a1 >> 8) & 0x7F, False, bool(a1 & 0x8000)
        if self.phase == DECAY:
            return ((a1 >> 4) & 0xF) << 2, True, True
        if self.phase == SUSTAIN:
            return (a2 >> 6) & 0x7F, bool(a2 & 0x4000), bool(a2 & 0x8000)
        return (a2 & 0x1F) << 2, True, bool(a2 & 0x20)

    def _step(self):
        """(level step, counter increment) for the current phase and level; increment 0 = never."""
        rate, dec, exp = self._params()
        shift, value = rate >> 2, rate & 3
        step = (-8 + value) if dec else (7 - value)
        step <<= max(0, 11 - shift)
        inc = 0x8000 >> max(0, shift - 11)
        if exp and not dec and self.level > 0x6000:
            if shift < 10:
                step >>= 2
            elif shift >= 11:
                inc >>= 2
            else:
                step >>= 1
                inc >>= 1
        elif exp and dec:
            step = (step * self.level) >> 15
        all_ones = rate == 0x7F or (self.phase in (DECAY, RELEASE) and rate == 0x1F << 2)
        if all_ones:
            return 0, 0
        return step, max(inc, 1)

    def _advance_phase(self) -> None:
        if self.phase == ATTACK and self.level >= 0x7FFF:
            self.phase, self.counter = DECAY, 0
        elif self.phase == DECAY and (self.level >> 11) <= self.sustain_field:
            self.phase, self.counter = SUSTAIN, 0
        elif self.phase == RELEASE and self.level <= 0:
            self.phase, self.level = OFF, 0

    def levels(self, n: int) -> list:
        """The level for each of the next n samples (the level is read, then the envelope ticks)."""
        out = []
        while len(out) < n:
            if self.phase == OFF:
                out.extend([0] * (n - len(out)))
                break
            step, inc = self._step()
            left = n - len(out)
            if inc == 0:
                out.extend([self.level] * left)
                break
            # cycles until counter bit 15 is set
            run = (0x8000 - self.counter + inc - 1) // inc
            if run > left:
                out.extend([self.level] * left)
                self.counter += inc * left
                break
            out.extend([self.level] * run)
            self.counter = 0
            level = self.level + step
            if self.phase in (DECAY, RELEASE) or (self.phase == SUSTAIN and step < 0):
                level = max(level, 0)
            else:
                level = min(max(level, -0x8000), 0x7FFF)
            self.level = level
            self._advance_phase()
        return out


# Reverb resampling FIR (psx-spx "Reverb Buffer Resampling"), 39 taps.
FIR = [-0x0001, 0x0000, 0x0002, 0x0000, -0x000A, 0x0000, 0x0023, 0x0000, -0x0067, 0x0000, 0x010A, 0x0000,
       -0x0268, 0x0000, 0x0534, 0x0000, -0x0B90, 0x0000, 0x2806, 0x4000, 0x2806, 0x0000, -0x0B90, 0x0000,
       0x0534, 0x0000, -0x0268, 0x0000, 0x010A, 0x0000, -0x0067, 0x0000, 0x0023, 0x0000, -0x000A, 0x0000,
       0x0002, 0x0000, -0x0001]
_FIR_EVEN = [(k, FIR[k]) for k in range(0, 39, 2)]  # the 20 taps on even offsets
_UP = [FIR[k] for k in range(0, 39, 2)]

REVERB_REGS = ["dAPF1", "dAPF2", "vIIR", "vCOMB1", "vCOMB2", "vCOMB3", "vCOMB4", "vWALL", "vAPF1", "vAPF2",
               "mLSAME", "mRSAME", "mLCOMB1", "mRCOMB1", "mLCOMB2", "mRCOMB2", "dLSAME", "dRSAME", "mLDIFF",
               "mRDIFF", "mLCOMB3", "mRCOMB3", "mLCOMB4", "mRCOMB4", "dLDIFF", "dRDIFF", "mLAPF1", "mRAPF1",
               "mLAPF2", "mRAPF2", "vLIN", "vRIN"]


def _s16(v: int) -> int:
    return v - 0x10000 if v & 0x8000 else v


class Reverb:
    """The SPU reverb (psx-spx "Reverb Formula") on a work area of `size` bytes, processed at
    22.05 kHz, its input and output resampled with the 39-tap FIR. `regs` are the 32 preset
    registers (u16 as stored); volumes are signed, addresses are in 8-byte units relative to the
    moving buffer address. Output = reverb × depth (EVOLL / EVOLR)."""

    def __init__(self, regs: dict, size: int, depth_l: int, depth_r: int):
        self.r = {k: (_s16(v) if k[0] == "v" else v) for k, v in regs.items()}
        self.words = size // 2
        self.ring = [0] * self.words
        self.pos = 0
        self.depth_l, self.depth_r = depth_l, depth_r
        self.hist_l = [0] * 39  # 44.1 kHz input history, newest last
        self.hist_r = [0] * 39
        self.up_l = [0] * 20  # 22.05 kHz output history, newest last
        self.up_r = [0] * 20
        self.phase = 0
        # word offsets of each address register
        self.o = {k: v * 4 for k, v in self.r.items() if k[0] in "md"}

    def _core(self, lin: int, rin: int):
        r, o, ring, n, p = self.r, self.o, self.ring, self.words, self.pos

        def rd(off):
            return ring[(p + off) % n]

        def wr(off, v):
            ring[(p + off) % n] = -0x8000 if v < -0x8000 else (0x7FFF if v > 0x7FFF else v)

        lin = (lin * r["vLIN"]) >> 15
        rin = (rin * r["vRIN"]) >> 15
        iir, wall = r["vIIR"], r["vWALL"]
        ls, rs, ld, rdf = o["mLSAME"], o["mRSAME"], o["mLDIFF"], o["mRDIFF"]
        lsp, rsp, ldp, rdp = rd(ls - 1), rd(rs - 1), rd(ld - 1), rd(rdf - 1)
        wr(ls, (((lin + ((rd(o["dLSAME"]) * wall) >> 15) - lsp) * iir) >> 15) + lsp)
        wr(rs, (((rin + ((rd(o["dRSAME"]) * wall) >> 15) - rsp) * iir) >> 15) + rsp)
        wr(ld, (((lin + ((rd(o["dRDIFF"]) * wall) >> 15) - ldp) * iir) >> 15) + ldp)
        wr(rdf, (((rin + ((rd(o["dLDIFF"]) * wall) >> 15) - rdp) * iir) >> 15) + rdp)
        c1, c2, c3, c4 = r["vCOMB1"], r["vCOMB2"], r["vCOMB3"], r["vCOMB4"]
        lout = ((c1 * rd(o["mLCOMB1"])) >> 15) + ((c2 * rd(o["mLCOMB2"])) >> 15) \
            + ((c3 * rd(o["mLCOMB3"])) >> 15) + ((c4 * rd(o["mLCOMB4"])) >> 15)
        rout = ((c1 * rd(o["mRCOMB1"])) >> 15) + ((c2 * rd(o["mRCOMB2"])) >> 15) \
            + ((c3 * rd(o["mRCOMB3"])) >> 15) + ((c4 * rd(o["mRCOMB4"])) >> 15)
        a1, a2, d1, d2 = r["vAPF1"], r["vAPF2"], o["dAPF1"], o["dAPF2"]
        x = rd(o["mLAPF1"] - d1)
        lout -= (a1 * x) >> 15
        wr(o["mLAPF1"], lout)
        lout = ((lout * a1) >> 15) + x
        x = rd(o["mRAPF1"] - d1)
        rout -= (a1 * x) >> 15
        wr(o["mRAPF1"], rout)
        rout = ((rout * a1) >> 15) + x
        x = rd(o["mLAPF2"] - d2)
        lout -= (a2 * x) >> 15
        wr(o["mLAPF2"], lout)
        lout = ((lout * a2) >> 15) + x
        x = rd(o["mRAPF2"] - d2)
        rout -= (a2 * x) >> 15
        wr(o["mRAPF2"], rout)
        rout = ((rout * a2) >> 15) + x
        self.pos = (p + 1) % n
        return _clamp16(lout), _clamp16(rout)

    def process(self, left: list, right: list):
        """Reverb output (already × depth) for these input samples (44.1 kHz)."""
        out_l, out_r = [], []
        hl, hr, ul, ur = self.hist_l, self.hist_r, self.up_l, self.up_r
        dl, dr = self.depth_l, self.depth_r
        for xl, xr in zip(left, right):
            hl.append(xl)
            hr.append(xr)
            del hl[0], hr[0]
            if self.phase:
                # downsample: FIR over the last 39 inputs
                il = (sum(c * hl[38 - k] for k, c in _FIR_EVEN) + 0x4000 * hl[19]) >> 15
                ir = (sum(c * hr[38 - k] for k, c in _FIR_EVEN) + 0x4000 * hr[19]) >> 15
                yl, yr = self._core(_clamp16(il), _clamp16(ir))
                ul.append(yl)
                ur.append(yr)
                del ul[0], ur[0]
                # upsample, odd phase: the even taps over the 22.05 kHz outputs (x2 gain)
                vl = (2 * sum(c * ul[19 - j] for j, c in enumerate(_UP))) >> 15
                vr = (2 * sum(c * ur[19 - j] for j, c in enumerate(_UP))) >> 15
            else:
                # even phase: the centre tap (0x4000 x 2 = unity) on the output 10 steps back
                vl, vr = ul[10], ur[10]
            self.phase ^= 1
            out_l.append((_clamp16(vl) * dl) >> 15)
            out_r.append((_clamp16(vr) * dr) >> 15)
        return out_l, out_r
