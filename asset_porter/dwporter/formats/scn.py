"""SCN event scripts (MAPHEAD.SCN, DG.SCN): container, sections, instructions, text. Spec: specs/scn.md.

Opcode layouts come from dw_decomp/include/dw/script.h and the interpreter (script_interp.c,
script_value.c, script_textbox.c). Every decoded instruction keeps its raw bytes, so a script is
rebuilt exactly by concatenating header, instructions and padding.
"""

import struct

SECTOR = 0x800
END_SECTION = 0xFE
END_SCRIPT = 0xFF

# Field types: pad = alignment byte ("_" in script.h), u8, u16, s16, s32 (two u16, lo then hi).
_SIZES = {"pad": 1, "u8": 1, "u16": 2, "s16": 2, "s32": 4}

_PAD = [("_", "pad")]
_PSTAT_VALUE = [("_", "pad"), ("pstat", "u8"), ("value", "u8")]
_WALK_TO = [("id", "u8"), ("x", "s16"), ("z", "s16"), ("anim", "u8"), ("unk", "u8")]
_WALK_TO_ENTITY = [("id", "u8"), ("anim", "u8"), ("target", "u8")]
_MOVE_TO = [("id", "u8"), ("x", "s16"), ("z", "s16"), ("speed", "u8"), ("unk", "u8")]
_MOVE_TO_ENTITY = [("id", "u8"), ("target", "u8"), ("speed", "u8")]
_MOVE_TO_AXIS = [("id", "u8"), ("target", "s16"), ("axis", "u8"), ("speed", "u8")]

# opcode -> (name, fields); fields None = variable layout handled in _decode_special.
OPCODES = {
    0x10: ("SET_SELECTION", None),
    0x11: ("UNUSED_11", _PAD),
    0x12: ("UNUSED_12", _PAD),
    0x13: ("JUMP_AND_LINK", [("_", "pad"), ("offset", "u16")]),
    0x14: ("JUMP_TO_FILE_AND_LINK", [("_", "pad"), ("script", "u16"), ("section", "u16")]),
    0x15: ("JUMP_RETURN", _PAD),
    0x16: ("JUMP_TO", [("_", "pad"), ("offset", "u16")]),
    0x17: ("JUMP_TO_FILE", [("_", "pad"), ("script", "u16"), ("section", "u16")]),
    0x18: ("SWITCH", None),
    0x19: ("IF", None),
    0x1A: ("SHOW_TEXTBOX", None),
    0x1B: ("SET_DIALOG_OWNER", [("id", "u8")]),
    0x1C: ("SET_TRIGGER", [("_", "pad"), ("trigger", "u16")]),
    0x1D: ("UNSET_TRIGGER", [("_", "pad"), ("trigger", "u16")]),
    0x1E: ("SET_PSTAT", _PSTAT_VALUE),
    0x1F: ("ADD_TO_PSTAT", _PSTAT_VALUE),
    0x20: ("REDUCE_PSTAT", _PSTAT_VALUE),
    0x21: ("STORE_MAP_ID", [("pstat", "u8")]),
    0x22: ("STORE_DIGIMON_TYPE", [("pstat", "u8")]),
    0x23: ("SET_INVENTORY_SIZE", [("size", "u8")]),
    0x24: ("STORE_RANDOM", [("_", "pad"), ("pstat", "u8"), ("max", "u8")]),
    0x25: ("STORE_DATE", [("pstat", "u8")]),
    0x26: ("SET_TEXTBOX_SIZE", [("origin", "u8"), ("cols", "u8"), ("rows", "u8")]),
    0x27: ("FADEOUT_HUD", [("box", "u8")]),
    0x28: ("GIVE_ITEM", [("_", "pad"), ("item", "u8"), ("amount", "u8")]),
    0x29: ("REMOVE_ITEM", [("_", "pad"), ("item", "u8"), ("amount", "u8")]),
    0x2A: ("ADD_MONEY", [("_", "pad"), ("amount", "s32")]),
    0x2B: ("REDUCE_MONEY", [("_", "pad"), ("amount", "s32")]),
    0x2C: ("COMPARE_DATE", [("pstat", "u8"), ("trigger", "u16"), ("compare", "u8"), ("year", "u8"),
                            ("day", "u8"), ("hour", "u8"), ("minute", "u8"), ("_", "pad")]),
    0x2D: ("LEARN_MOVE", [("move", "u8")]),
    0x2E: ("UNUSED_2E", [("value", "u8")]),
    0x2F: ("GIVE_CARD", [("card", "u8")]),
    0x30: ("TAKE_CARD", [("card", "u8")]),
    0x31: ("SET_MERIT", [("_", "pad"), ("value", "u16")]),
    0x32: ("ADD_MERIT", [("_", "pad"), ("value", "u16")]),
    0x33: ("REDUCE_MERIT", [("_", "pad"), ("value", "u16")]),
    0x34: ("SET_STAT", [("stat", "u8"), ("value", "u16")]),
    0x35: ("ADD_STAT", [("stat", "u8"), ("value", "u16")]),
    0x36: ("REDUCE_STAT", [("stat", "u8"), ("value", "u16")]),
    0x37: ("ADVANCE_TO_DATE_AT", [("pstat", "u8")]),
    0x38: ("ADD_MINUTES_TO_DATE_AT", [("pstat", "u8"), ("minutes", "s32")]),
    0x39: ("ADD_MINUTES_TO_DATE_AT_2", [("pstat", "u8"), ("minutes", "s32")]),
    0x3A: ("UNUSED_3A", [("_", "pad"), ("a", "u8"), ("b", "u8")]),
    0x3B: ("UNUSED_3B", [("_", "pad"), ("a", "u8"), ("b", "u8")]),
    0x3C: ("UNUSED_3C", [("_", "pad"), ("a", "u8"), ("b", "u8")]),
    0x3D: ("UNUSED_3D", [("value", "u8")]),
    0x3E: ("UNUSED_3E", [("value", "u8")]),
    0x3F: ("STORE_DIGIMON_VALUE", [("_", "pad"), ("pstat_digimon", "u8"), ("pstat_out", "u8")]),
    0x46: ("LOAD_DIGIMON", [("digimon", "u8")]),
    0x47: ("SET_DIGIMON", [("digimon", "u8"), ("slot", "u8"), ("autotalk", "u8")]),
    0x48: ("UNLOAD_ENTITY", [("id", "u8")]),
    0x49: ("CALL_DIGIMON_ROUTINE", [("routine", "u8")]),
    0x4A: ("WAIT_FOR_ENTITY", [("id", "u8")]),
    0x4B: ("WARP_TO", [("screen", "u8"), ("exit", "u8"), ("section", "u8")]),
    0x4C: ("ENTITY_LOOK_AT_ENTITY", [("_", "pad"), ("id", "u8"), ("target", "u8")]),
    0x4D: ("ENTITY_SET_ROTATION", [("id", "u8"), ("rotation", "s16")]),
    0x4E: ("ENTITY_WALK_TO", _WALK_TO),
    0x4F: ("MOVE_CAMERA_TO", [("speed", "u8"), ("x", "s16"), ("z", "s16")]),
    0x50: ("MOVE_CAMERA_TO_ENTITY", [("_", "pad"), ("id", "u8"), ("speed", "u8")]),
    0x51: ("ENTITY_WALK_TO_ENTITY", _WALK_TO_ENTITY),
    0x52: ("ENTITY_WALK_TO_WITH_CAMERA", _WALK_TO),
    0x53: ("ENTITY_WALK_TO_ENTITY_WITH_CAMERA", _WALK_TO_ENTITY),
    0x54: ("RESET_ENTITY_ORIGIN", [("id", "u8")]),
    0x55: ("SET_TEXTBOX_ORIGIN", [("_", "pad"), ("x", "s16"), ("y", "s16"), ("z", "s16")]),
    0x56: ("PLAY_ANIMATION", [("_", "pad"), ("id", "u8"), ("anim", "u8")]),
    0x57: ("SET_OBJ_VISIBILITY", [("_", "pad"), ("object", "u8"), ("flag", "u8")]),
    0x58: ("TELEPORT", [("pstat", "u8")]),
    0x5A: ("PLAY_SOUND", [("_", "pad"), ("bank", "u8"), ("sound", "u8")]),
    0x5B: ("UNUSED_5B", [("value", "u8")]),
    0x5C: ("UNUSED_5C", [("value", "u8")]),
    0x5D: ("SET_BGM", [("bgm", "u8")]),
    0x5E: ("STOP_BGM", [("value", "u8")]),
    0x5F: ("UNUSED_5F", [("value", "u8")]),
    0x64: ("CALL_ROUTINE", [("builtin", "u8")]),
    0x65: ("REMOVE_CONDITION", [("mask", "u8")]),
    0x66: ("START_BATTLE", [("value", "u8")]),
    0x67: ("DELAY", [("_", "pad"), ("frames", "u16")]),
    0x68: ("SET_TEXTBOX_MODE", [("_", "pad"), ("mode", "u8"), ("frames", "u8")]),
    0x69: ("DEAL_DAMAGE", [("pstat", "u8")]),
    0x6A: ("SET_AUTOTALK", [("_", "pad"), ("id", "u8"), ("autotalk", "u8")]),
    0x6B: ("DATA", None),
    0x6C: ("ENTITY_MOVE_TO", _MOVE_TO),
    0x6D: ("ENTITY_MOVE_TO_ENTITY", _MOVE_TO_ENTITY),
    0x6E: ("ENTITY_MOVE_TO_WITH_CAMERA", _MOVE_TO),
    0x6F: ("ENTITY_MOVE_TO_ENTITY_WITH_CAMERA", _MOVE_TO_ENTITY),
    0x70: ("ROTATE_3D_OBJECT", [("door", "u8"), ("unk", "u8"), ("target", "u8")]),
    0x71: ("MOVE_OBJECT_TO", [("slot", "u8"), ("id", "u8"), ("speed", "u8"), ("angle", "u8"), ("_", "pad"),
                              ("x", "s16"), ("z", "s16")]),
    0x72: ("ENTITY_MOVE_TO_AXIS", _MOVE_TO_AXIS),
    0x73: ("ENTITY_MOVE_TO_AXIS_WITH_CAMERA", _MOVE_TO_AXIS),
    0x74: ("SPAWN_ITEM", [("item", "u8"), ("x", "s16"), ("z", "s16")]),
    0x75: ("SPAWN_CHEST", [("item", "u8"), ("x", "s16"), ("y", "s16"), ("z", "s16"), ("w", "s16"),
                           ("trigger", "u16")]),
    0x76: ("SPAWN_BOULDER", [("value", "u8")]),
    0x77: ("MOVE_BOULDER", [("value", "u8"), ("x", "s16"), ("z", "s16")]),
    0x78: ("DESPAWN_BOULDER", [("value", "u8")]),
    0x79: ("UNLOAD_DIGIMON", [("digimon", "u8")]),
    0x7A: ("COPY_PSTAT", [("_", "pad"), ("from", "u8"), ("to", "u8")]),
    0x7B: ("SECTION_ON_EXIT", [("section", "u8")]),
    0x7C: ("SET_RECT_IMPASSABLE", [("value", "u8"), ("x", "s16"), ("z", "s16"), ("w", "u8"), ("h", "u8")]),
    0x7D: ("SPAWN_SPRITE_AT_LOCATION", [("sprite", "u8"), ("x", "s16"), ("y", "s16"), ("z", "s16"), ("w", "s16")]),
    0x7E: ("SPAWN_SPRITE_AT_ENTITY", [("id", "u8"), ("node", "u8"), ("sprite", "u8")]),
    0xFB: ("SET_SCRIPT", [("_", "pad"), ("script", "u16"), ("map", "u16")]),
    0xFC: ("UNUSED_FC", _PAD),
    0xFD: ("UNUSED_FD", _PAD),
    0xFE: ("END_SECTION", _PAD),
    0xFF: ("END_SCRIPT", _PAD),
}

COMPARE = {0: "==", 1: "!=", 2: ">=", 3: "<=", 4: ">", 5: "<"}
SPEAKERS = {0xFF: "none", 0xFD: "tamer", 0xFC: "partner", 0xC8: "Sign", 0xC9: "Box", 0xCA: "Betamon", 0xCB: "Coelamon",
            0xCC: "Tanemon", 0xCD: "Palmon"}

# Text control codes (showTextbox, drawString2): code -> (token kind, takes a pstat argument).
_TEXT_CODES = {
    0x01: "color", 0x02: "ctrl_02", 0x04: "pstat_number", 0x05: "tamer_name", 0x06: "partner_name",
    0x07: "digimon_name", 0x08: "move_name", 0x09: "item_name", 0x0A: "money", 0x0B: "merit",
    0x0C: "tab_8", 0x0E: "tab_11", 0x10: "shop_value", 0x11: "bgm_name", 0x12: "tournament_name",
    0x13: "tournaments_won", 0x14: "tournament_wins", 0x15: "tournaments_lost",
    0x16: "tab_stop", 0x17: "tab_stop", 0x18: "tab_stop", 0x19: "tab_stop", 0x1A: "tab_stop",
    0x1B: "tab_stop", 0x1C: "tab_stop",
}
_TEXT_ARG = {0x01, 0x02, 0x04, 0x07, 0x08, 0x09, 0x11, 0x12}  # second byte is meaningful


class ScnError(ValueError):
    pass


# --- containers ------------------------------------------------------------------------------

def parse_dg_table(data: bytes) -> dict:
    """DG.SCN offset table: one sector of u32; script i = [offsets[i], offsets[i + 1])."""
    first = struct.unpack_from("<I", data, 0)[0]
    if first % 4 or first > len(data) or first == 0:
        raise ScnError(f"bad first offset 0x{first:X}")
    raw = list(struct.unpack_from(f"<{first // 4}I", data, 0))
    used = 1
    while used < len(raw) and raw[used] > raw[used - 1] and raw[used] <= len(data):
        used += 1
    scripts = [(i, raw[i], raw[i + 1] - raw[i]) for i in range(used - 1)]
    return {"table_size": first, "entries": raw, "used_entries": used, "scripts": scripts}


def parse_header(script: bytes) -> dict:
    code_start = struct.unpack_from("<H", script, 0)[0]
    sections, p = [], 2
    while True:
        sid = struct.unpack_from("<H", script, p)[0]
        if sid == 0xFFFF:
            p += 2
            break
        off = struct.unpack_from("<H", script, p + 2)[0]
        sections.append({"id": sid, "offset": off})
        p += 4
    return {"code_start": code_start, "table_end": p, "sections": sections}


# --- text ------------------------------------------------------------------------------------

# Glyphs the US font draws as ASCII punctuation (seen in the English text: "letters here。",
# "No one「s here"). Button symbols (△ ○ × □) are kept.
_US_PUNCTUATION = {"。": ".", "「": "'", "−": "-"}


def _fullwidth_to_ascii(s: str) -> str:
    out = []
    for ch in s:
        o = ord(ch)
        if ch in _US_PUNCTUATION:
            out.append(_US_PUNCTUATION[ch])
        elif 0xFF01 <= o <= 0xFF5E:
            out.append(chr(o - 0xFEE0))
        elif o == 0x3000:
            out.append(" ")
        else:
            out.append(ch)
    return "".join(out)


def decode_text(data: bytes, p: int) -> tuple:
    """Text at p (showTextbox). Returns (tokens, display string, end offset)."""
    tokens, display, start = [], [], p
    chars = bytearray()

    def flush():
        if chars:
            try:
                s = bytes(chars).decode("shift_jis")
            except UnicodeDecodeError as e:
                raise ScnError(f"bad Shift-JIS at 0x{p:X}: {bytes(chars).hex()}") from e
            tokens.append({"kind": "chars", "raw": bytes(chars).hex(), "text": _fullwidth_to_ascii(s)})
            display.append(_fullwidth_to_ascii(s))
            chars.clear()

    while True:
        if p + 1 >= len(data):
            raise ScnError(f"text runs past the script at 0x{start:X}")
        c = data[p]
        if c >= 0x80 or c == 0x0F or c == 0x00:
            chars += data[p:p + 2]
            p += 2
            continue
        flush()
        if c == 0x03:
            tokens.append({"kind": "ctrl_03", "raw": data[p:p + 4].hex(), "args": list(data[p + 1:p + 4])})
            display.append("{ctrl_03}")
            p += 4
            continue
        if c == 0x0D:
            end = data[p + 2] == 0
            raw = data[p:p + (4 if end else 2)]
            tokens.append({"kind": "end" if end else "newline", "raw": raw.hex()})
            p += len(raw)
            if end:
                return tokens, "".join(display), p
            display.append("\n")
            continue
        kind = _TEXT_CODES.get(c)
        if kind is None:
            raise ScnError(f"unknown text code 0x{c:02X} at 0x{p:X}")
        token = {"kind": kind, "raw": data[p:p + 2].hex()}
        if c in _TEXT_ARG:
            token["arg"] = data[p + 1]
        tokens.append(token)
        display.append("{" + kind + (f" {data[p + 1]}" if c in _TEXT_ARG else "") + "}")
        p += 2


# --- instructions ----------------------------------------------------------------------------

def _read_fields(data: bytes, p: int, fields: list) -> tuple:
    args, pads = {}, 0
    for name, kind in fields:
        if kind == "pad":
            pads += data[p] != 0
            if data[p]:
                args.setdefault("_nonzero_pad", []).append(data[p])
        elif kind == "u8":
            args[name] = data[p]
        elif kind == "u16":
            args[name] = struct.unpack_from("<H", data, p)[0]
        elif kind == "s16":
            args[name] = struct.unpack_from("<h", data, p)[0]
        elif kind == "s32":
            lo, hi = struct.unpack_from("<HH", data, p)
            args[name] = struct.unpack("<i", struct.pack("<I", lo + (hi << 16)))[0]
        p += _SIZES[kind]
    return args, p, pads


def _decode_if(data: bytes, p: int) -> tuple:
    conditions, pads = [], 0
    while True:
        op = data[p]
        pads += data[p + 1] != 0
        q = p + 2
        if op == 0x19:
            conditions.append({"op": op, "kind": "end", "raw": data[p:q].hex()})
            return conditions, q, pads
        kind, sub = op & 0x38, op & 7
        cond = {"op": op, "combine": "and" if op & 0x80 else "or" if op & 0x40 else "set"}
        if kind == 0x00:
            cond.update(kind="trigger", trigger=struct.unpack_from("<H", data, q)[0], negate=sub != 0)
            q += 2
        elif kind == 0x08:
            cond.update(kind="pstat", pstat=data[q], value=data[q + 1], compare=COMPARE.get(sub, sub))
            q += 2
        elif kind == 0x10:
            cond.update(kind="jump_if_true", offset=struct.unpack_from("<H", data, q)[0])
            q += 2
        elif kind == 0x18:
            cond.update(kind="jump_if_false", offset=struct.unpack_from("<H", data, q)[0])
            q += 2
        elif kind == 0x20 and sub == 0:
            stat, cmp_ = data[q], data[q + 1]
            value = struct.unpack_from("<h" if stat == 9 else "<H", data, q + 2)[0]
            cond.update(kind="stat", stat=stat, compare=COMPARE.get(cmp_, cmp_), value=value)
            q += 4
        elif kind == 0x20 and sub in (1, 4):
            cond.update(kind="card" if sub == 1 else "item_count", id=data[q],
                        compare=COMPARE.get(data[q + 1], data[q + 1]), value=struct.unpack_from("<H", data, q + 2)[0])
            q += 4
        elif kind == 0x20 and sub in (2, 3):
            cond.update(kind="knows_move" if sub == 2 else "condition", id=data[q], negate=data[q + 1] != 0)
            q += 2
        elif kind == 0x20 and sub == 5:
            lo, hi = struct.unpack_from("<HH", data, q + 2)
            cond.update(kind="money", compare=COMPARE.get(data[q + 1], data[q + 1]),
                        value=struct.unpack("<i", struct.pack("<I", lo + (hi << 16)))[0])
            pads += data[q] != 0
            q += 6
        else:
            cond.update(kind="unknown")  # no arguments are read by the interpreter
        cond["raw"] = data[p:q].hex()
        conditions.append(cond)
        p = q


def decode_instruction(data: bytes, p: int) -> dict:
    op = data[p]
    if op not in OPCODES:
        raise ScnError(f"unknown opcode 0x{op:02X} at 0x{p:X}")
    name, fields = OPCODES[op]
    insn = {"offset": p, "op": op, "name": name}
    pads = 0
    q = p + 1
    if fields is not None:
        args, q, pads = _read_fields(data, q, fields)
    elif op == 0x10:
        count = data[q]
        targets = list(struct.unpack_from(f"<{count}H", data, q + 1))
        q += 1 + 2 * count
        if data[q] != 0x1A:
            raise ScnError(f"selection at 0x{p:X} without its textbox")
        pads += data[q + 1] != 0
        tokens, display, q = decode_text(data, q + 2)
        args = {"count": count, "targets": targets, "text": display, "tokens": tokens}
    elif op == 0x18:
        pstat, count = data[q], struct.unpack_from("<H", data, q + 1)[0]
        offsets = list(struct.unpack_from(f"<{count}H", data, q + 3))
        args = {"pstat": pstat, "count": count, "offsets": offsets}
        q += 3 + 2 * count
    elif op == 0x19:
        pads += data[q] != 0
        conditions, q, more = _decode_if(data, q + 1)
        pads += more
        args = {"conditions": conditions}
    elif op == 0x1A:
        pads += data[q] != 0
        tokens, display, q = decode_text(data, q + 1)
        args = {"text": display, "tokens": tokens}
    elif op == 0x6B:
        pads += data[q] != 0
        end = data.index(END_SCRIPT, q + 1)
        args = {"values": list(data[q + 1:end])}
        q = end + 1
    if q > len(data):
        raise ScnError(f"instruction at 0x{p:X} runs past the script")
    insn["args"] = args
    insn["size"] = q - p
    insn["raw"] = data[p:q].hex()
    insn["nonzero_pads"] = pads
    return insn


def jump_targets(insn: dict) -> list:
    """Offsets inside the same script that this instruction can jump to."""
    a = insn["args"]
    if insn["op"] in (0x13, 0x16):
        return [a["offset"]]
    if insn["op"] == 0x10:
        return list(a["targets"])
    if insn["op"] == 0x18:
        return list(a["offsets"])
    if insn["op"] == 0x19:
        return [c["offset"] for c in a["conditions"] if c["kind"] in ("jump_if_true", "jump_if_false")]
    return []


def disassemble(script: bytes) -> dict:
    """Header, instructions (until END_SCRIPT) and the padding after it."""
    header = parse_header(script)
    p, insns = header["code_start"], []
    while True:
        insn = decode_instruction(script, p)
        insns.append(insn)
        p += insn["size"]
        if insn["op"] == END_SCRIPT:
            break
    return {"header": header, "instructions": insns, "end": p, "padding": script[p:]}
