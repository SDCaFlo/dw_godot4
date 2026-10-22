"""MMD (Digimon model) format and its animation ("momentum") instructions.

Layout:
    u32 tmd_offset      -> a TMD (see tmd.py), file offset
    u32 anim_offset     -> animation table: u32 offsets relative to the table, 0 = no animation.
                           The table has no count; it ends where the first animation starts.

Animation (all i16/u16):
    u16 frame_count     bit 15 = has scale
    per bone 1..n-1:    [scale x, y, z] rot x, y, z  loc x, y, z   (initial pose; bone 0 = root)
    instructions until a 0x0000 word:
      0x0fff keyframe   (frame) then entries while word & 0x8000:
                        u16 0x8000 | axes << 6 | bone, i16 divisor, one i16 value per set axis bit
                        axes bit 8..0 = scale x, y, z, rot x, y, z, loc x, y, z
      0x1nnn loop start (count = low byte; 0 and 0xFF loop forever)
      0x2fff loop end   (frame) then u16 frame to jump back to
      0x3fff texture    (frame) then u16 src x<<8|y, u16 w<<8|h, u16 dest x<<8|y  (MoveImage in the model's VRAM slot)
      0x4fff sound      (frame) then u16 bank<<8|sound

The bone count is not stored in the file (it comes from DIGIMON_DATA[type].boneCount), so
animations can only be parsed with it. `simulate` is a direct port of the game code, see
specs/mmd.md for the references.
"""

import math
import struct
from dataclasses import dataclass, field

from . import tmd as tmdfmt

AXES = ("scale_x", "scale_y", "scale_z", "rot_x", "rot_y", "rot_z", "loc_x", "loc_y", "loc_z")
FPS = 20  # main loop VSync(3) on NTSC
MAX_TICKS = 20000


class MmdError(ValueError):
    pass


@dataclass
class Animation:
    index: int
    offset: int  # file offset of the frame count word
    frame_count: int
    has_scale: bool
    initial: list  # per bone 1..n-1: [sx, sy, sz, rx, ry, rz, lx, ly, lz]
    instructions: list  # dicts, see parse_animation
    words_offset: int  # file offset of the first instruction word
    end: int  # file offset after the 0x0000 terminator


@dataclass
class Mmd:
    tmd_offset: int
    anim_offset: int
    tmd: tmdfmt.Tmd
    table: list  # per animation id: offset relative to the table, 0 = none
    animations: dict = field(default_factory=dict)  # offset -> Animation (shared offsets parsed once)

    def animation(self, anim_id: int):
        rel = self.table[anim_id]
        return self.animations.get(rel) if rel else None


def _u16(data: bytes, pos: int) -> int:
    return struct.unpack_from("<H", data, pos)[0]


def _i16(data: bytes, pos: int) -> int:
    return struct.unpack_from("<h", data, pos)[0]


def parse_animation(data: bytes, offset: int, index: int, bone_count: int) -> Animation:
    words = _u16(data, offset)
    has_scale = bool(words & 0x8000)
    frame_count = words & 0x7FFF
    pos = offset + 2
    initial = []
    for _ in range(1, bone_count):
        values = [4096, 4096, 4096] if not has_scale else []
        for _ in range(9 if has_scale else 6):
            values.append(_i16(data, pos))
            pos += 2
        initial.append(values)

    start = pos
    instructions = []
    while True:
        if pos + 2 > len(data):
            raise MmdError(f"animation at 0x{offset:X}: no terminator")
        word = _u16(data, pos)
        at = pos
        pos += 2
        if word == 0:
            break
        op = word & 0xF000
        frame = word & 0x0FFF
        if op == 0x0000:
            entries = []
            while _u16(data, pos) & 0x8000:
                head = _u16(data, pos)
                divisor = _i16(data, pos + 2)
                pos += 4
                axes = {}
                for i in range(9):
                    if head & (0x4000 >> i):
                        axes[AXES[i]] = _i16(data, pos)
                        pos += 2
                if divisor == 0:
                    raise MmdError(f"animation at 0x{offset:X}: zero divisor at 0x{at:X}")
                entries.append({"bone": head & 0x3F, "divisor": divisor, "axes": axes})
            instructions.append({"op": "keyframe", "offset": at, "frame": frame, "entries": entries})
        elif op == 0x1000:
            instructions.append({"op": "loop_start", "offset": at, "count": word & 0xFF})
        elif op == 0x2000:
            instructions.append({"op": "loop_end", "offset": at, "frame": frame, "jump_to": _u16(data, pos)})
            pos += 2
        elif op == 0x3000:
            a, b, c = struct.unpack_from("<3H", data, pos)
            pos += 6
            instructions.append({"op": "texture", "offset": at, "frame": frame, "src": [a >> 8, a & 0xFF],
                                 "size": [b >> 8, b & 0xFF], "dest": [c >> 8, c & 0xFF]})
        elif op == 0x4000:
            w = _u16(data, pos)
            pos += 2
            instructions.append({"op": "sound", "offset": at, "frame": frame, "bank": w >> 8, "sound": w & 0xFF})
        else:
            raise MmdError(f"animation at 0x{offset:X}: unknown instruction 0x{word:04X} at 0x{at:X}")
    return Animation(index, offset, frame_count, has_scale, initial, instructions, start, pos)


def parse(data: bytes, bone_count: int = None) -> Mmd:
    if len(data) < 8:
        raise MmdError("truncated")
    tmd_offset, anim_offset = struct.unpack_from("<II", data, 0)
    tmd = tmdfmt.parse(data, tmd_offset, strict=False)

    table, count, i = [], None, 0
    while count is None or i < count:
        if anim_offset + 4 * i + 4 > len(data):
            raise MmdError("animation table runs past the file")
        rel = struct.unpack_from("<I", data, anim_offset + 4 * i)[0]
        table.append(rel)
        if rel:
            count = rel // 4 if count is None else min(count, rel // 4)
        i += 1
        if count is None and i > 256:
            break  # no animations at all
    if count is not None:
        table = table[:count]

    mmd = Mmd(tmd_offset, anim_offset, tmd, table)
    if bone_count is not None:
        for index, rel in enumerate(table):
            if rel and rel not in mmd.animations:
                mmd.animations[rel] = parse_animation(data, anim_offset + rel, index, bone_count)
    return mmd


# Simulation ---------------------------------------------------------------------------------

def _wrap16(v: int) -> int:
    return (v + 0x8000) % 0x10000 - 0x8000


def _cdiv(a: int, b: int) -> int:
    q = abs(a) // abs(b)
    return q if (a >= 0) == (b >= 0) else -q


def _rot_matrix(rx: int, ry: int, rz: int) -> list:
    """Rx * Ry * Rz (libgte RotMatrix), angles in 1/4096 turns."""
    ax, ay, az = (r * 2 * math.pi / 4096 for r in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(ax), math.sin(ax), math.cos(ay), math.sin(ay), math.cos(az), math.sin(az)
    rxm = [[1, 0, 0], [0, cx, -sx], [0, sx, cx]]
    rym = [[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]]
    rzm = [[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]]
    mul = lambda a, b: [[sum(a[i][k] * b[k][j] for k in range(3)) for j in range(3)] for i in range(3)]  # noqa: E731
    return mul(mul(rxm, rym), rzm)


def simulate(data: bytes, anim: Animation, bone_count: int, anim_id: int = None) -> dict:
    """Run the animation like startAnimation/tickAnimation and return one pose per tick.

    Returns {"frames": [[[sx,sy,sz,rx,ry,rz,lx,ly,lz] per bone] per tick], "frame_numbers": [animation
    frame per tick], "root_location": [(x,y,z) per tick, float], "events": [...], "loop": {...} or None,
    "quirks": n}. Tick t is shown at time (t - 1) / FPS.
    Bone 0 starts at rest (scale 4096, rotation 0) at the origin; the game starts it from the
    entity's current pose instead.
    """
    anim_id = anim.index if anim_id is None else anim_id
    pose = [[4096, 4096, 4096, 0, 0, 0, 0, 0, 0]] + [list(v) for v in anim.initial]
    # Per bone, per axis: delta, sub_delta, reload, counter, sign (MomentumData).
    mom = [[[0, 0, 0, 0, 0] for _ in range(9)] for _ in range(bone_count)]
    root_loc = [0, 0, 0]  # locX/Y/Z: 1/32768 units

    def word(pos):
        return _u16(data, pos)

    instr = anim.words_offset
    frame, loop_end_frame, loop_count, loop_start = 1, 1, 0, None
    frames, frame_numbers, root_track, events, quirks, loop = [], [], [], [], 0, None
    tick = 0

    while True:
        tick += 1
        frame_numbers.append(frame)
        if tick > MAX_TICKS:
            raise MmdError(f"animation {anim_id}: no end after {MAX_TICKS} ticks")

        # tickMomentum
        for b in range(bone_count):
            for j in range(9):
                m = mom[b][j]
                if m[0] == 0 and m[1] == 0:
                    continue
                if b == 0 and j >= 6:
                    break
                value = pose[b][j] + m[0]
                if m[1]:
                    m[3] -= m[1]
                    if m[3] <= 0:
                        m[3] += m[2]
                        value += m[4]
                pose[b][j] = _wrap16(value) if 3 <= j < 6 else value
            if b == 0:
                # applyRootMomentum
                base = [0, 0, 0]
                for i in range(3):
                    m = mom[0][6 + i]
                    if i == 0 and anim_id in (0x23, 0x24):
                        continue
                    if m[1]:
                        m[3] -= m[1]
                        if m[3] <= 0:
                            base[i] = (m[0] + m[4]) << 15
                            m[3] += m[2]
                            continue
                    base[i] = m[0] << 15
                rot = _rot_matrix(*pose[0][3:6])
                for i in range(3):
                    root_loc[i] += sum(rot[i][k] * pose[0][k] / 4096 * base[k] for k in range(3))

        # tickAnimation: the game tests & 0x1000 here, not the opcode.
        w = word(instr)
        if w & 0x1000:
            if w & 0xF000 != 0x1000:
                quirks += 1
            loop_count = w & 0xFF
            instr += 2
            loop_start = instr
            loop_end_frame = word(instr) & 0xFFF

        while frame == loop_end_frame:
            w = word(instr)
            op = w & 0xF000
            if op == 0x0000:
                if w == 0:
                    break  # terminator: nothing more can match
                instr += 2
                while word(instr) & 0x8000:
                    head, divisor = word(instr), _i16(data, instr + 2)
                    instr += 4
                    for i in range(9):
                        if head & (0x4000 >> i):
                            value = _i16(data, instr)
                            instr += 2
                            m = mom[head & 0x3F][i]
                            m[0] = _cdiv(value, divisor)
                            m[1] = value - m[0] * divisor
                            if m[1]:
                                m[4] = 1 if m[1] > 0 else -1
                                m[1] = abs(m[1])
                                m[2] = m[3] = divisor
            elif op == 0x1000:
                loop_count = w & 0xFF
                instr += 2
                loop_start = instr
            elif op == 0x2000:
                if loop_count != 0xFF:
                    loop_count = (loop_count - 1) & 0xFF
                if loop_count == 0:
                    instr += 4
                else:
                    jump_to = word(instr + 2)
                    if loop_count == 0xFF and loop is None:
                        loop = {"start_frame": jump_to, "end_frame": frame, "end_tick": tick}
                    frame = jump_to
                    instr = loop_start
            elif op == 0x3000:
                a, b2, c = word(instr + 2), word(instr + 4), word(instr + 6)
                events.append({"tick": tick, "type": "texture", "src": [a >> 8, a & 0xFF],
                               "size": [b2 >> 8, b2 & 0xFF], "dest": [c >> 8, c & 0xFF]})
                instr += 8
            elif op == 0x4000:
                v = word(instr + 2)
                events.append({"tick": tick, "type": "sound", "bank": v >> 8, "sound": v & 0xFF})
                instr += 4
            loop_end_frame = word(instr) & 0xFFF

        frames.append([list(p) for p in pose])
        root_track.append(tuple(v / 32768 for v in root_loc))

        if loop is not None:
            break  # endless loop: one pass recorded
        if frame == anim.frame_count:
            break
        frame += 1

    if loop is not None:
        # The loop replays the ticks after the last one that showed `start_frame`.
        starts = [t for t, f in enumerate(frame_numbers, 1) if f == loop["start_frame"] and t <= loop["end_tick"]]
        loop["start_tick"] = starts[-1] if starts else 1
    return {"frames": frames, "frame_numbers": frame_numbers, "root_location": root_track, "events": events,
            "loop": loop, "quirks": quirks}
