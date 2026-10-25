"""The music renderer: SPU envelope / interpolation / ADPCM loops and the libsnd sequencer and
voice formulas (specs/sound.md "Music render"). Values worked out by hand from the rules quoted
there; no game data needed."""

import unittest

from dwporter.formats import libsnd, spu

# A pitch table of the right shape (_svm_ptable: 0x1000 at the centre, 0x2000 one octave up).
PTABLE = [round(0x1000 * 2 ** (i / 192)) for i in range(193)]


def block(nibbles, flags=0, shift=0, filt=0) -> bytes:
    """One ADPCM block of 28 nibbles."""
    data = bytes([(filt << 4) | shift, flags])
    for a, b in zip(nibbles[0::2], nibbles[1::2]):
        data += bytes([(a & 0xF) | ((b & 0xF) << 4)])
    return data


class EnvelopeTest(unittest.TestCase):
    def test_linear_attack_fastest_rate_steps_every_sample(self):
        # attack rate 0: shift 0, step +7 << 11 = 14336, counter increment 0x8000
        env = spu.Envelope(0x0000, 0x0000)
        self.assertEqual(env.levels(4), [0, 14336, 28672, 0x7FFF])
        self.assertEqual(env.phase, spu.DECAY)

    def test_attack_shift_above_11_steps_less_often(self):
        # attack rate 13 << 2 = 52: shift 13, step 7, increment 0x8000 >> 2 -> a step every 4 cycles
        env = spu.Envelope(52 << 8, 0)
        self.assertEqual(env.levels(9), [0, 0, 0, 0, 7, 7, 7, 7, 14])

    def test_rate_all_ones_never_steps(self):
        env = spu.Envelope(0x7F << 8, 0)
        self.assertEqual(env.levels(1000), [0] * 1000)

    def test_decay_is_exponential_and_stops_at_the_sustain_level(self):
        # instant attack, decay shift 0 (step -8 << 11 scaled by level), sustain level field 7 (0x4000)
        env = spu.Envelope(0x0007, 0x7F << 6)
        levels = env.levels(60)
        self.assertEqual(levels[3], 0x7FFF)
        self.assertEqual(levels[4], 0x7FFF + ((-0x4000 * 0x7FFF) >> 15))
        self.assertEqual(env.phase, spu.SUSTAIN)
        self.assertLessEqual(env.level >> 11, 7)

    def test_release_reaches_zero_and_turns_off(self):
        env = spu.Envelope(0x000F, 0x7F << 6)  # sustain never moving
        env.levels(10)
        start = env.level
        env.key_off()  # release rate 0: linear -8 << 11 per sample
        levels = env.levels(6)
        self.assertEqual(levels[:2], [start, max(0, start - 0x4000)])
        self.assertEqual(env.phase, spu.OFF)

    def test_mute_is_silent_at_once(self):
        env = spu.Envelope(0, 0)
        env.levels(5)
        env.mute()
        self.assertEqual(env.levels(3), [0, 0, 0])


class InterpolationTest(unittest.TestCase):
    def test_gauss_groups_sum_to_about_0x8000(self):
        g = spu.GAUSS
        sums = {g[i] + g[0xFF - i] + g[0x100 + i] + g[0x1FF - i] for i in range(256)}
        self.assertTrue(all(0x7F7F <= s <= 0x7F81 for s in sums), sums)

    def test_constant_input_comes_out_nearly_unchanged(self):
        # nibble 1 with shift 0 -> sample 0x1000; filter 0
        stream = spu.AdpcmStream(block([1] * 28, flags=1))
        out = spu.Resampled(stream, 0x1000)
        out.ensure(10)
        # the 4 taps sum to 0x7F7F..0x7F81 and each product is floored: a few units under the input
        self.assertTrue(all(0x1000 - 24 <= x <= 0x1000 for x in out.out[3:10]), list(out.out))


class AdpcmTest(unittest.TestCase):
    def test_end_without_repeat_mutes_after_the_block(self):
        stream = spu.AdpcmStream(block(list(range(14)) * 2, flags=1) + block([5] * 28))
        stream.ensure(100)
        self.assertEqual((len(stream.pcm), stream.mute_at), (28, 28))

    def test_loop_end_with_repeat_jumps_to_the_loop_start(self):
        a = block([1] * 28, flags=0)
        b = block([2] * 28, flags=4)  # loop start
        c = block([3] * 28, flags=3)  # loop end + repeat
        stream = spu.AdpcmStream(a + b + c)
        stream.ensure(28 * 5)
        values = [stream.pcm[k * 28] for k in range(5)]
        self.assertEqual(values, [0x1000, 0x2000, 0x3000, 0x2000, 0x3000])
        self.assertIsNone(stream.mute_at)

    def test_filter_history_carries_across_the_loop_jump(self):
        # filter 1 (60/64 of the previous sample) on the loop block: its first sample differs
        # between the first pass (history from block a) and the repeat (history from itself)
        a = block([0] * 28)
        b = block([1] * 28, flags=7, filt=1)  # loop start + end + repeat: a one-block loop
        stream = spu.AdpcmStream(a + b)
        stream.ensure(28 * 3)
        self.assertNotEqual(stream.pcm[28], stream.pcm[56])


class LibsndTest(unittest.TestCase):
    def test_tick_increment(self):
        # 480 ticks per quarter at 120 BPM: 480 * 120 * 10 / (240 * 60) = 40 delta units per tick
        self.assertEqual(libsnd.tick_increment(480, 120), (40, -1))
        # remainder above half rounds up: 480 * 121 * 10 = 580800 = 40 * 14400 + 4800 (< 7200) -> 40
        self.assertEqual(libsnd.tick_increment(480, 121)[0], 40)
        self.assertEqual(libsnd.tick_increment(480, 122)[0], 41)

    def test_note2pitch(self):
        self.assertEqual(libsnd.note2pitch(PTABLE, 60, 60, 0), 0x1000)
        self.assertEqual(libsnd.note2pitch(PTABLE, 72, 60, 0), 0x2000)
        self.assertEqual(libsnd.note2pitch(PTABLE, 48, 60, 0), 0x0800)
        self.assertEqual(libsnd.note2pitch(PTABLE, 61, 60, 0), PTABLE[16])
        self.assertEqual(libsnd.note2pitch(PTABLE, 60, 60, 64), PTABLE[8])  # shift / 8
        self.assertEqual(libsnd.note2pitch(PTABLE, 60, 60, 127), PTABLE[15])  # at most 15

    def test_note2pitch2_fine_carries(self):
        # (fine + shift) / 8 >= 16 moves to the next semitone
        self.assertEqual(libsnd.note2pitch2(PTABLE, 60, 0x7F + 2, 60, 0), PTABLE[16])

    def test_sequence_volume(self):
        # full velocity, volumes 127, seq vol 0x50: v = 16383 -> 16383 * 80 / 127 = 10320 -> squared / 0x3FFF
        self.assertEqual(libsnd.seq_volume(127, 127, 127, 127, 127, 0x50, 0x50, 64, 64, 64), (6500, 6500))
        # channel pan 0: the right side goes to 0
        self.assertEqual(libsnd.seq_volume(127, 127, 127, 127, 127, 0x50, 0x50, 64, 64, 0), (6500, 0))

    def _bank(self):
        tone = {"min": 0, "max": 127, "priority": 0, "vag": 1, "adsr1": 0x0000, "adsr2": 0x7F << 6, "volume": 127,
                "pan": 64, "center": 60, "shift": 0, "mode": 4, "pitchbend_min": 2, "pitchbend_max": 2}
        prog = {"index": 0, "tones": 1, "volume": 127, "pan": 64}
        vh = {"header": {"master_volume": 127}, "programs": [prog], "tones": [[tone]]}
        loop = block([1] * 28, flags=7)
        return libsnd.Bank(vh, {1: loop})

    def _seq(self, body: bytes) -> bytes:
        return b"pQES" + b"\x00\x00\x00\x01" + b"\x01\xE0" + b"\x07\xA1\x20" + b"\x04\x02" + body

    def test_loop_markers_render_intro_and_two_passes(self):
        # delta 0; NRPN 20, count 127 (forever); note on, 480 ticks; note off; NRPN 30; end
        body = (b"\x00" + b"\xB0\x63\x14\x00" + b"\x06\x7F\x00" + b"\x90\x3C\x64\x83\x60"
                + b"\x3C\x00\x00" + b"\xB0\x63\x1E\x00" + b"\xFF\x2F")
        res = libsnd.render_song(self._seq(body), self._bank(), PTABLE, None, 0, False, max_seconds=10)
        self.assertFalse(res["capped"])
        kinds = [k for k, _ in res["jumps"]]
        self.assertEqual(kinds[:3], ["loop_start", "loop", "loop"])
        loop = res["loop"]
        # one quarter at 120 BPM = 0.5 s = 120 libsnd ticks per pass
        self.assertEqual(loop["end_tick"] - loop["start_tick"], 120)
        self.assertGreater(max(res["left"]), 0)

    def test_play_once_stops_and_rings_out(self):
        body = b"\x00" + b"\x90\x3C\x64\x83\x60" + b"\x3C\x00\x00" + b"\xFF\x2F"
        res = libsnd.render_song(self._seq(body), self._bank(), PTABLE, None, 0, True, max_seconds=10)
        self.assertFalse(res["capped"])
        self.assertIsNone(res["loop"])
        self.assertEqual(res["jumps"][-1][0], "end")


if __name__ == "__main__":
    unittest.main()
