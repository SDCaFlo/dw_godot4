"""libsnd (Psy-Q sound library) sequencer and voice manager, on the SPU emulation of spu.py, to
render the game's songs offline. Spec: specs/sound.md "Music render".

Reproduced from DW's libsnd (dw_decomp/asm/us/main/psyq/libsnd.s), read with the matched C of the
same library in sotn-decomp (src/main/psxsdk/libsnd/) as an aid; the differences found in DW's
assembly are noted where they apply:
- sequencer: _SsInitSoundSeq, _SsSeqPlay, _SsGetSeqData, _SsNoteOn, _SsSetControlChange,
  _SsContDataEntry, _SsContNrpn2, _SsSetPitchBend, _SsGetMetaEvent, _SsReadDeltaValue;
- voice manager: _SsVmKeyOn, _SsVmAlloc, _SsVmDoAllocate, _SsVmKeyOnNow, _SsVmKeyOff, _SsVmSetVol,
  _SsVmPBVoice, note2pitch, note2pitch2, _SsVmSeqKeyOff, _SsVmFlush;
- SsSeqCalledTbyT: _SsVmFlush, then the sequence's tick, 240 times a second (SS_TICK240).
"""

from . import spu

TICKS_PER_SECOND = 240  # SsSetTickMode(SS_TICK240) (sound.c:521), VBLANK_MINUS
VOICES = 24
SEQ_OWNER = 0  # the sequence's access number (the only one open)


def _cdiv(a: int, b: int) -> int:
    """C integer division (truncates toward zero)."""
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b > 0) else -q


def _cmod(a: int, b: int) -> int:
    return a - b * _cdiv(a, b)


def tick_increment(resolution: int, bpm: int):
    """(unk70, unk6E): the delta units (ticks x 10) the sequence advances per libsnd tick, and the
    slow-tempo countdown (-1 when unused). _SsInitSoundSeq / _SsGetMetaEvent 0x51."""
    v = resolution * bpm * 10
    if v < TICKS_PER_SECOND * 60:
        n = (TICKS_PER_SECOND * 600) // (resolution * bpm)
        return n, n
    inc = v // (TICKS_PER_SECOND * 60)
    if TICKS_PER_SECOND * 30 < v % (TICKS_PER_SECOND * 60):
        inc += 1
    return inc, -1


def note2pitch(ptable: list, note: int, center: int, shift: int) -> int:
    """note2pitch: the key-on pitch (the tone's fine tune `shift` / 8, max 15)."""
    n = note + 60 - center
    octave, pos = _cdiv(n, 12), _cmod(n, 12)
    fine = min(shift // 8, 15)
    p = ptable[max(0, pos * 16 + fine)]
    octave -= 5
    if octave > 0:
        p <<= octave
    elif octave < 0:
        p >>= -octave
    return p & 0xFFFF


def note2pitch2(ptable: list, note: int, fine: int, center: int, shift: int) -> int:
    """note2pitch2: pitch with a fine part (pitch bend), (fine + shift) / 8 carrying into the note."""
    a3 = (fine + shift) // 8
    carry = 0
    if a3 >= 16:
        carry, a3 = 1, a3 - 16
    n = note + 60 - center + carry
    octave, pos = _cdiv(n, 12), _cmod(n, 12)
    p = ptable[max(0, pos * 16 + a3)]
    octave -= 5
    if octave > 0:
        p <<= octave
    elif octave < 0:
        p >>= -octave
    return p & 0xFFFF


def _pan(l: int, r: int, pan: int):
    """One pan stage of _SsVmKeyOnNow / _SsVmSetVol (/ 63)."""
    if pan < 0x40:
        return l, r * pan // 63
    return l * (127 - pan) // 63, r


def seq_volume(velocity: int, ch_vol: int, mvol: int, prog_vol: int, tone_vol: int, seq_l: int, seq_r: int,
               tone_pan: int, prog_pan: int, ch_pan: int):
    """The voice volume registers (L, R) of a sequence note (_SsVmKeyOn + _SsVmKeyOnNow, DW asm):
    integer steps in the code's order, squared at the end (sequence notes only)."""
    v = velocity * ch_vol // 127
    v = v * (mvol * 0x3FFF) // (127 * 127)
    v = v * prog_vol * tone_vol // (127 * 127)
    l, r = v * seq_l // 127, v * seq_r // 127
    l, r = _pan(l, r, tone_pan)
    l, r = _pan(l, r, prog_pan)
    l, r = _pan(l, r, ch_pan)
    return l * l // 0x3FFF, r * r // 0x3FFF


class Bank:
    """A VAB as libsnd sees it: programs (by program number) with their tone block, and the
    samples' ADPCM bytes by VAG number."""

    def __init__(self, vh: dict, vag_data: dict):
        self.mvol = vh["header"]["master_volume"]
        self.programs = {}
        k = 0
        for p in vh["programs"]:
            if p["tones"]:
                self.programs[p["index"]] = (p, vh["tones"][k][:p["tones"]])
                k += 1
        self.vag_data = vag_data
        self._streams = {}
        self._cache = {}

    def resampled(self, vag: int, pitch: int) -> "spu.Resampled":
        key = (vag, pitch)
        r = self._cache.get(key)
        if r is None:
            r = spu.Resampled(self.stream(vag), pitch)
            self._cache[key] = r
        return r

    def stream(self, vag: int) -> "spu.AdpcmStream":
        s = self._streams.get(vag)
        if s is None:
            s = spu.AdpcmStream(self.vag_data.get(vag, b""))
            self._streams[vag] = s
        return s


class Voice:
    """One SPU voice: libsnd's bookkeeping (_svm_voice) and the hardware state."""

    __slots__ = ("keyed", "age", "envx", "prior", "owner", "note", "prog", "tone", "vel", "pan_arg", "vag",
                 "tone_attr", "prog_attr", "env", "src", "pos", "pitch", "vol_l", "vol_r", "reverb", "on",
                 "pend")

    def __init__(self):
        self.keyed = 0  # unk1b
        self.age = 0  # unk2
        self.envx = 0  # unk6: ENVX read at the last flush
        self.prior = 0  # unk18
        self.owner = -1  # unke
        self.note = self.prog = self.tone = self.vel = self.pan_arg = self.vag = 0
        self.tone_attr = self.prog_attr = None
        self.env = None
        self.src = None
        self.pos = 0
        self.pitch = 0
        self.vol_l = self.vol_r = 0
        self.reverb = False
        self.on = False
        self.pend = {}


class Renderer:
    """One song on one bank: the sequencer, the voice manager and the SPU mix."""

    def __init__(self, seq: bytes, bank: Bank, ptable: list, reverb: "spu.Reverb", seq_vol: int = 0x50,
                 play_once: bool = False):
        self.d, self.bank, self.ptable, self.reverb = seq, bank, ptable, reverb
        self.seq_l = self.seq_r = seq_vol
        self.play_count = 1 if play_once else 0  # unk46: SsSeqPlay l_count (0 = SSPLAY_INFINITY)
        self.voices = [Voice() for _ in range(VOICES)]
        self.kon, self.koff = set(), set()
        self.envx_hist = [0] * 16
        self.hist_index = 0
        self.jumps = []  # (kind, tick) of loop jumps and restarts
        self.ended = False
        self.tick_count = 0
        self._open()

    # --- sequencer -----------------------------------------------------------------------------
    def _open(self):
        d = self.d
        if d[0:4] != b"pQES" or d[7] != 1:
            raise ValueError("not SEQ data (pQES, version 1)")
        p = 8
        self.resolution = (d[p] << 8) | d[p + 1]
        tempo = (d[p + 2] << 16) | (d[p + 3] << 8) | d[p + 4]
        self.bpm = 60000000 // tempo + (1 if tempo // 2 < 60000000 % tempo else 0)
        self.pos = p + 5 + 2
        self.programs = list(range(16))
        self.vol = [0x7F] * 16
        self.panpot = [0x40] * 16
        self.channel = 0
        self.status = 0
        self.loop_pending = 0  # 0x1C
        self.loop_set = 0  # 0x15
        self.loop_count = 0  # 0x1D
        self.played = 0  # unk48
        self.delta = self._read_delta()
        self.start_pos = self.loop_pos = self.pos
        self.inc, self.slow = tick_increment(self.resolution, self.bpm)

    def _read_delta(self) -> int:
        d = self.d
        v = d[self.pos]
        self.pos += 1
        if v == 0:
            return 0
        if v & 0x80:
            v &= 0x7F
            while True:
                b = d[self.pos]
                self.pos += 1
                v = (v << 7) + (b & 0x7F)
                if not b & 0x80:
                    break
        return v * 10

    def _seq_tick(self):
        """_SsSeqPlay."""
        if self.delta - self.inc > 0:
            if self.slow > 0:
                self.slow -= 1
            elif self.slow == 0:
                self.slow = self.inc
                self.delta -= 1
            else:
                self.delta -= self.inc
        elif self.delta <= self.inc:
            acc = self.delta
            while not self.ended:
                self._event()
                while self.delta == 0 and not self.ended:
                    self._event()
                acc += self.delta
                if acc >= self.inc:
                    break
            self.delta = acc - self.inc

    def _event(self):
        """_SsGetSeqData: one event, then its delta."""
        d = self.d
        b = d[self.pos]
        self.pos += 1
        if b & 0x80:
            self.channel = b & 0x0F
            kind = b & 0xF0
            self.status = 0xFF if kind == 0xF0 else kind
            if kind == 0x90:
                note, vel = d[self.pos], d[self.pos + 1]
                self.pos += 2
                self.delta = self._read_delta()
                self._note_on(note, vel)
            elif kind == 0xB0:
                c = d[self.pos]
                self.pos += 1
                self._control(c)
            elif kind == 0xC0:
                self.programs[self.channel] = d[self.pos]
                self.pos += 1
                self.delta = self._read_delta()
            elif kind == 0xE0:
                self.pos += 1
                self._pitch_bend()
            elif kind == 0xF0:
                m = d[self.pos]
                self.pos += 1
                self._meta(m)
            else:
                raise ValueError(f"SEQ status 0x{b:02X} at {self.pos - 1}")
        else:
            s = self.status
            if s == 0x90:
                vel = d[self.pos]
                self.pos += 1
                self.delta = self._read_delta()
                self._note_on(b, vel)
            elif s == 0xB0:
                self._control(b)
            elif s == 0xC0:
                self.programs[self.channel] = b
                self.delta = self._read_delta()
            elif s == 0xE0:
                self._pitch_bend()  # b was the LSB; the MSB follows
            elif s == 0xFF:
                self._meta(b)
            else:
                raise ValueError(f"running status without status at {self.pos - 1}")

    def _control(self, c: int):
        """_SsSetControlChange (the data byte follows the controller number)."""
        val = self.d[self.pos]
        self.pos += 1
        ch = self.channel
        if c == 6:  # _SsContDataEntry: the count after NRPN 20 (DW asm: 0x1C pending, 0x15 set, 0x1D count)
            if self.loop_pending == 1 and self.loop_set == 0:
                self.loop_count = val
                self.loop_pending = 0
                self.loop_set = 1
        elif c == 7:
            self.vol[ch] = val
            self._set_vol(self.programs[ch], val, self.panpot[ch])
        elif c == 10:
            self.panpot[ch] = val
            self._set_vol(self.programs[ch], self.vol[ch], val)
        elif c == 99:  # _SsContNrpn2
            if val == 20:
                self.loop_pending = 1
                self.delta = self._read_delta()
                self.loop_pos = self.pos
                self.jumps.append(("loop_start", self.tick_count))
                return
            if val == 30:
                if self.loop_count == 0:
                    self.loop_set = 0
                    self.delta = self._read_delta()
                elif self.loop_count < 0x7F:
                    self.loop_count -= 1
                    self.delta = self._read_delta()
                    if self.loop_count:
                        self.pos = self.loop_pos
                        self.jumps.append(("loop", self.tick_count))
                    else:
                        self.loop_set = 0
                else:
                    self._read_delta()
                    self.delta = 0
                    self.pos = self.loop_pos
                    self.jumps.append(("loop", self.tick_count))
                return
        self.delta = self._read_delta()

    def _pitch_bend(self):
        msb = self.d[self.pos]
        self.pos += 1
        self._pitch_bend_value(msb)

    def _pitch_bend_value(self, msb: int):
        """_SsSetPitchBend -> _SsVmPitchBend -> _SsVmPBVoice: only the MSB, for the channel
        program's sounding voices (a note started later is not bent)."""
        prog = self.programs[self.channel]
        b = msb - 0x40
        for i, v in enumerate(self.voices):
            if v.owner != SEQ_OWNER or v.prog != prog or v.tone_attr is None:
                continue
            t = v.tone_attr
            if b > 0:
                note = v.note + (b * t["pitchbend_max"]) // 63
                fine = ((b * t["pitchbend_max"]) % 63) * 2
            elif b < 0:
                x = b * t["pitchbend_min"]
                note = v.note + _cdiv(x, 64) - 1
                fine = _cmod(x, 64) * 2 + 0x7F
            else:
                note, fine = v.note, 0
            v.pend["pitch"] = note2pitch2(self.ptable, note, fine, t["center"], t["shift"])
        self.delta = self._read_delta()

    def _meta(self, m: int):
        """_SsGetMetaEvent: 0x51 tempo, 0x2F end."""
        d = self.d
        if m == 0x51:
            tempo = (d[self.pos] << 16) | (d[self.pos + 1] << 8) | d[self.pos + 2]
            self.pos += 3
            self.bpm = 60000000 // tempo
            self.inc, self.slow = tick_increment(self.resolution, self.bpm)
            self.delta = self._read_delta()
        elif m == 0x2F:
            self.played += 1
            if self.play_count == 0 or self.played < self.play_count:
                self.loop_pending = 0
                self.delta = 0
                self.pos = self.start_pos
                self.jumps.append(("restart", self.tick_count))
                return
            self._seq_key_off()
            self.ended = True
            self.delta = self.inc
            self.jumps.append(("end", self.tick_count))
        else:
            raise ValueError(f"SEQ meta 0x{m:02X}")

    # --- voice manager -------------------------------------------------------------------------
    def _note_on(self, note: int, vel: int):
        """_SsNoteOn -> _SsVmKeyOn / _SsVmKeyOff."""
        if self.seq_l == 0:
            return
        ch = self.channel
        prog = self.programs[ch]
        if vel == 0:
            self._key_off(prog, note)
            return
        entry = self.bank.programs.get(prog)
        if entry is None:
            return
        p, tones = entry
        for k, t in enumerate(tones):
            if not (t["min"] <= note <= t["max"]):
                continue
            n = self._alloc(t["priority"])
            if n >= VOICES:
                continue
            v = self.voices[n]
            v.keyed, v.age, v.owner, v.prog, v.tone, v.note = 1, 0, SEQ_OWNER, prog, k, note
            v.vel, v.pan_arg, v.prior, v.vag = vel, self.panpot[ch], t["priority"], t["vag"]
            v.tone_attr, v.prog_attr = t, p
            # _SsVmDoAllocate
            v.envx = 0x7FFF
            for i in range(16):
                self.envx_hist[i] &= ~(1 << n)
            v.pend["adsr"] = (t["adsr1"], t["adsr2"])
            v.pend["vag"] = t["vag"]
            # _SsVmKeyOnNow
            v.pend["vol"] = seq_volume(vel, self.vol[ch], self.bank.mvol, p["volume"], t["volume"], self.seq_l,
                                       self.seq_r, t["pan"], p["pan"], self.panpot[ch])
            v.pend["pitch"] = note2pitch(self.ptable, note, t["center"], t["shift"])
            v.pend["reverb"] = bool(t["mode"] & 4)
            self.kon.add(n)
            self.koff.discard(n)

    def _alloc(self, prior: int) -> int:
        """_SsVmAlloc."""
        channel, best, cand, t3, t0 = 99, 99, 0, 0xFFFF, 0
        for i, v in enumerate(self.voices):
            if v.keyed == 0 and v.envx == 0:
                channel = i
                break
            if v.prior < prior:
                prior, best, t3, t0, cand = v.prior, i, v.envx, v.age, 1
            elif v.prior == prior:
                cand += 1
                if v.envx < t3:
                    t0, t3, best = v.age, v.envx, i
                elif v.envx == t3 and t0 < v.age:
                    t0, best = v.age, i
        if channel == 99:
            channel = VOICES if cand == 0 else best
        if channel < VOICES:
            for v in self.voices:
                v.age += 1
            self.voices[channel].age = 0
            self.voices[channel].prior = prior
        return channel

    def _key_off(self, prog: int, note: int):
        """_SsVmKeyOff."""
        for i, v in enumerate(self.voices):
            if v.note == note and v.prog == prog and v.owner == SEQ_OWNER:
                v.keyed = 0
                self.koff.add(i)
                self.kon.discard(i)

    def _seq_key_off(self):
        """_SsVmSeqKeyOff: all the sequence's voices."""
        for i, v in enumerate(self.voices):
            if v.owner == SEQ_OWNER:
                v.keyed = 0
                self.koff.add(i)
                self.kon.discard(i)

    def _set_vol(self, prog: int, vol: int, pan: int):
        """_SsVmSetVol (CC 7 / 10): the channel program's sounding voices get new volumes. DW's
        asm reads the voice's own tone (program block * 16 + tone), unlike sotn-decomp's."""
        for v in self.voices:
            if v.owner == SEQ_OWNER and v.prog == prog and v.tone_attr is not None:
                t, p = v.tone_attr, v.prog_attr
                v.pend["vol"] = seq_volume(v.vel, vol, self.bank.mvol, p["volume"], t["volume"], self.seq_l,
                                           self.seq_r, t["pan"], p["pan"], pan)

    def _flush(self):
        """_SsVmFlush: ENVX history (a voice whose envelope read 0 over the last 15 entries is
        freed), then the buffered register writes, key-offs, key-ons."""
        self.hist_index = (self.hist_index + 1) & 0xF
        mask = 0
        for i, v in enumerate(self.voices):
            v.envx = v.env.level if (v.on and v.env is not None) else 0
            if v.envx == 0:
                mask |= 1 << i
        self.envx_hist[self.hist_index] = mask
        env_mask = 0xFFFFFFFF
        for i in range(15):
            env_mask &= self.envx_hist[i]
        for i, v in enumerate(self.voices):
            if env_mask & (1 << i):
                v.keyed = 0
        starts = {}
        for i, v in enumerate(self.voices):
            pend = v.pend
            if not pend:
                continue
            v.pend = {}
            if "vol" in pend:
                v.vol_l, v.vol_r = pend["vol"]
            if "reverb" in pend:
                v.reverb = pend["reverb"]
            if "pitch" in pend:
                pitch = pend["pitch"]
                if i not in self.kon and v.on and pitch != v.pitch:
                    # a sounding voice changes pitch: continue from its exact counter position
                    if isinstance(v.src, spu.Resampled):
                        v.src = spu.LiveResampler(v.src.stream, v.pos * v.src.pitch, pitch)
                    else:
                        v.src.pitch = min(pitch, 0x4000)
                v.pitch = pitch
            if "adsr" in pend:
                starts[i] = (pend["adsr"], pend["vag"])
        for i in self.koff:
            v = self.voices[i]
            if v.on:
                v.env.key_off()
        for i in self.kon:
            v = self.voices[i]
            adsr, vag = starts.get(i, ((v.tone_attr["adsr1"], v.tone_attr["adsr2"]), v.vag))
            v.env = spu.Envelope(*adsr)
            v.src = self.bank.resampled(vag, v.pitch)
            v.pos = 0
            v.on = True
        self.kon, self.koff = set(), set()

    # --- mixing ------------------------------------------------------------------------------
    def _mix(self, n: int):
        out_l, out_r = [0] * n, [0] * n
        rev_l, rev_r = [0] * n, [0] * n
        any_rev = False  # some reverb input this tick
        for v in self.voices:
            if not v.on:
                continue
            env = v.env
            if env.phase == spu.OFF:
                v.on = False
                continue
            src = v.src
            if isinstance(src, spu.Resampled):
                src.ensure(v.pos + n)
                end = v.pos + n if src.mute_at is None else min(v.pos + n, src.mute_at)
                seg = src.out[v.pos:end]
                v.pos += n
            else:
                seg = src.take(n)
            levels = env.levels(len(seg))
            if len(seg) < n:
                env.mute()
                levels += [0] * (n - len(seg))
                seg = list(seg) + [0] * (n - len(seg))
            vl, vr = v.vol_l * 2, v.vol_r * 2
            mono = [(s * e) >> 15 for s, e in zip(seg, levels)]
            if vl:
                vals_l = [(x * vl) >> 15 for x in mono]
                out_l = [a + b for a, b in zip(out_l, vals_l)]
            else:
                vals_l = None
            if vr:
                vals_r = [(x * vr) >> 15 for x in mono]
                out_r = [a + b for a, b in zip(out_r, vals_r)]
            else:
                vals_r = None
            if v.reverb:
                any_rev = True
                if vals_l:
                    rev_l = [a + b for a, b in zip(rev_l, vals_l)]
                if vals_r:
                    rev_r = [a + b for a, b in zip(rev_r, vals_r)]
        if self.reverb is not None:
            if any_rev:
                rev_l = [spu._clamp16(x) for x in rev_l]
                rev_r = [spu._clamp16(x) for x in rev_r]
            wl, wr = self.reverb.process(rev_l, rev_r)
            out_l = [a + b for a, b in zip(out_l, wl)]
            out_r = [a + b for a, b in zip(out_r, wr)]
        mv = 0x7FFE  # SsSetMVol(127, 127): main volume 0x3FFF (x2)
        out_l = [spu._clamp16((x * mv) >> 15) for x in out_l]
        out_r = [spu._clamp16((x * mv) >> 15) for x in out_r]
        return out_l, out_r

    def active_voices(self) -> int:
        return sum(1 for v in self.voices if v.on and v.env is not None and v.env.phase != spu.OFF)

    def run(self, until, max_seconds: float = 900.0):
        """Render tick by tick until `until(self)` is true (checked after each tick) or the cap.
        Returns (left, right, tick_starts) with the first sample of every tick."""
        left, right, starts = [], [], []
        acc = 0
        max_ticks = int(max_seconds * TICKS_PER_SECOND)
        while self.tick_count < max_ticks:
            # SsSeqCalledTbyT: flush first, then the sequence
            self._flush()
            if not self.ended:
                self._seq_tick()
            acc += spu.RATE
            n = acc // TICKS_PER_SECOND
            acc %= TICKS_PER_SECOND
            starts.append(len(left))
            l, r = self._mix(n)
            left += l
            right += r
            self.tick_count += 1
            if until(self):
                break
        return left, right, starts


def render_song(seq: bytes, bank: Bank, ptable: list, reverb_regs: dict, reverb_size: int, play_once: bool,
                depth: int = 0x7000, max_seconds: float = 900.0) -> dict:
    """Render a song like the game plays it (playMusic: SsSeqSetVol 0x50, SSPLAY_INFINITY or once).

    Looping songs: rendered through the intro and the loop body twice; the loop is the second pass
    (from the tick after the first jump back to the tick after the second), so it already holds
    the first pass's tails and reverb. Songs played once: until every voice is off and the reverb
    has rung out. The sample of a tick's events is the next tick's first sample (_SsVmFlush runs
    before the sequence)."""
    reverb = spu.Reverb(reverb_regs, reverb_size, depth, depth) if reverb_regs else None
    r = Renderer(seq, bank, ptable, reverb, play_once=play_once)
    state = {"quiet": 0}

    def jumps(rr):
        return [j for j in rr.jumps if j[0] in ("loop", "restart")]

    def until(rr):
        if play_once:
            if rr.ended and rr.active_voices() == 0:
                state["quiet"] += 1
                return state["quiet"] > 2 * TICKS_PER_SECOND  # 2 s of reverb tail
            return False
        return len(jumps(rr)) >= 2

    left, right, starts = r.run(until, max_seconds)
    result = {"left": left, "right": right, "ticks": r.tick_count, "jumps": r.jumps,
              "resolution": r.resolution, "bpm_start": None, "loop": None, "capped": False}
    js = jumps(r)
    if not play_once:
        if len(js) >= 2:
            a, b = js[0][1] + 1, js[1][1] + 1
            if b < len(starts):
                result["loop"] = {"start": starts[a], "end": starts[b], "start_tick": a, "end_tick": b}
            else:
                result["loop"] = {"start": starts[a], "end": len(left), "start_tick": a, "end_tick": r.tick_count}
                # the second jump's tick is the last one rendered: its events sound from the next
                # sample on, which is the loop's start again
        else:
            result["capped"] = True
    if play_once and not r.ended:
        result["capped"] = True
    return result
