"""EFEDAT.EFE battle effects: slot header and the effect-script VM bytecode. Spec: specs/efe.md.

Opcodes from src/btl/battle_effect.c (BTL_jtbl_80073604, BTL_EFE_SUB_OPCODES). Every decoded
instruction keeps its raw bytes; bytes of the script area the control flow never reaches are gaps.
"""

import struct

SLOT_SIZE = 0x5000
HEADER_SIZE = 0x34
HEADER_FIELDS = ("start_script", "init_script", "uv_anims", "uv_anims_end", "sub_effects", "tmd_start",
                 "tmd_end", "tim_start", "tim_end", "data_end", "unk28", "num_sub_effects", "effect_id")
UV_ANIM_SIZE = 32
SUB_EFFECT_SIZE = 28

# op -> (name, size in bytes, operand names); "-" = unused word
OPCODES = {
    0: ("LOAD_IMMEDIATE", 6, ("value", "-")),
    1: ("LOAD_VARIABLE", 6, ("offset", "scope")),
    2: ("LOAD_RANDOM", 2, ()),
    3: ("LOAD_INDEXED", 10, ("table", "-", "index_offset", "index_scope")),
    4: ("VARIABLE_OPERATOR", 6, ("offset", "scope")),
    5: ("STOP", 2, ()),
    6: ("STOP", 2, ()),
    7: ("BRANCH_IF", 10, ("offset", "scope", "target", "-")),
    8: ("STOP", 2, ()),
    9: ("JUMP", 4, ("target",)),
    10: ("PUSH_IMMEDIATE", 6, ("value", "-")),
    11: ("PUSH_VARIABLE", 6, ("offset", "scope")),
    12: ("PUSH_ADDRESS", 6, ("offset", "scope")),
    13: ("CALL", 6, ("target", "-")),
    14: ("BUILTIN", 2, ()),
    15: ("RETURN", 2, ()),
    16: ("POP_TO_VARIABLE", 6, ("offset", "scope")),
    17: ("SPAWN_SUB_EFFECT", 12, ("count", "instances", "-", "stride", "-")),
}
ENDS_FLOW = {5, 6, 8, 9, 15}
OPERATORS = ("set", "add", "sub", "mul", "div", "mod", "shl", "shr")
COMPARES = ("==", "!=", "<", "<=", ">", ">=")

# BTL_EFE_SUB_OPCODES: built-in id -> handler name
BUILTINS = {
    0: "checkTechCompatibility", 1: "initializeUVAnim", 2: "initializeSubEffectInstructions", 3: "drawTMD",
    4: "renderCenteredSprite", 5: "initializeEFETransform", 6: "checkCollisionWithDefaultPower", 7: "EFERotateVector",
    8: "setTransformToTargetBone", 9: "addAttackObjectToTarget", 10: "getScatteredSpawnPosition",
    11: "discardEFEOperandPair", 12: "interpolateVector", 13: "steerTransformTowardPoint",
    14: "copyTargetEntityPosition", 15: "setEFEModelObjectColor", 16: "addParticleEmitter",
    17: "selectNextTargetEntity", 18: "EFECreateFlash", 19: "addCloudEffect", 20: "renderScreenSprite",
    21: "projectPositionToScreen", 22: "renderParticleFlashSprite", 23: "getTargetDigimonSize",
    24: "renderProjectedSprite", 25: "calculatePolarOffset", 26: "copyFromParentTransform",
    27: "addSourceEntityParticleFX", 28: "playEFESound", 29: "setTransformToBoneOffset",
    30: "renderScrollingBackground", 31: "renderParallaxSprites", 32: "setTransformToSourceBone",
    33: "rotateTransformTowardPoint", 34: "checkTargetCollision", 35: "getUVAnimTimer", 36: "applyHomingMovement",
    37: "getSourceDigimonSize", 38: "calculateSine", 39: "calculateCosine", 40: "interpolateValue",
    41: "getRandomInRange", 42: "printDebugValue", 43: "getVectorEulerAngles", 44: "findHitEntity",
    45: "normalizeRotationAngles", 46: "setTargetToHitEntity", 47: "getVectorLength", 48: "copyVector",
    49: "addVectors", 50: "subtractVectors", 51: "multiplyVectors", 52: "divideVectors", 53: "maskVectors",
    54: "shiftVectorsRight", 55: "centerTransformOnEntities", 56: "getTargetBoneTransform",
    57: "rotateVectorByAngles", 58: "normalizeRotationAngles2", 59: "combineRotations", 60: "renderEFELine",
    61: "copyToParentTransform", 62: "getSourceBoneTransform", 63: "setupFixedCamera", 64: "restoreCameraView",
    65: "render2DTexturedQuad", 66: "renderWireframeGrid", 67: "discardEFEOperand", 68: "renderWireframeBox",
    69: "setTransformToBoneMatrix", 70: "render3DTexturedQuad", 71: "multiplyVectorByScalar",
    72: "divideVectorByScalar", 73: "maskVectorByScalar", 74: "convertToViewSpace", 75: "selectRandomTargetEntity",
    76: "getCameraRotation", 77: "drawTMDYXZ", 78: "loadClutColors", 79: "drawTMDScreenSpace",
    80: "addClutLoadPrim", 81: "getViewportDistance", 82: "renderRadialWaves", 83: "initializeRibbonPoints",
    84: "tickRibbonPoints", 85: "renderRibbonStrip", 86: "renderRingTube", 87: "renderScreenOverlay",
    88: "faceTargetEntity", 89: "applyLineAttackHit", 90: "applyRadiusAttackHit", 91: "applyBoxAttackHit",
    92: "renderScreenFade", 93: "disableMapLayer", 94: "getViewportDistance2", 95: "markEFEFinished",
    96: "isTargetUnhit",
}


class EfeError(ValueError):
    pass


def parse_header(slot: bytes) -> dict:
    return dict(zip(HEADER_FIELDS, struct.unpack_from("<13i", slot, 0)))


def _size_name(flags: int) -> str:
    return {4: "int32", 2: "int16"}.get(flags & 0xF, "int8")


def decode(base: bytes, p: int) -> dict:
    """One instruction at base offset p."""
    word = struct.unpack_from("<H", base, p)[0]
    op, flags = word & 0xFF, word >> 8
    if op not in OPCODES:
        raise EfeError(f"unknown opcode {op} at 0x{p:X}")
    name, size, names = OPCODES[op]
    if p + size > len(base):
        raise EfeError(f"instruction at 0x{p:X} runs past the slot")
    values = struct.unpack_from(f"<{size // 2 - 1}h", base, p + 2) if size > 2 else ()
    insn = {"offset": p, "op": op, "name": name, "flags": flags, "raw": base[p:p + size].hex()}
    operands = {n: v for n, v in zip(names, values) if n != "-"}
    unused = [v for n, v in zip(names, values) if n == "-"]
    if unused:
        operands["unused"] = unused
    if op in (1, 11, 7):
        operands["size"] = _size_name(flags)
    if op == 3:
        operands["size"], operands["index_size"] = _size_name(flags), _size_name(flags >> 4)
    if op == 4:
        operands["size"] = _size_name(flags)
        operands["operator"] = OPERATORS[flags >> 4] if flags >> 4 < len(OPERATORS) else flags >> 4
    if op == 7:
        operands["compare"] = COMPARES[flags >> 4] if flags >> 4 < len(COMPARES) else flags >> 4
    if op == 14:
        operands["builtin"] = flags
        operands["builtin_name"] = BUILTINS.get(flags)
    insn["operands"] = operands
    insn["size"] = size
    return insn


def disassemble(base: bytes, entries: list, code_end: int) -> dict:
    """Follow the control flow from `entries` (offsets in base). Returns instructions by offset,
    entry points found, UV keyframe table addresses and errors."""
    insns, todo = {}, [(e, "entry") for e in entries]
    found_entries, uv_tables, errors = {e: "entry" for e in entries}, set(), []
    while todo:
        p, why = todo.pop()
        history = []
        while p not in insns:
            if not 0 <= p < code_end:
                errors.append(f"flow leaves the script area at 0x{p:X} ({why})")
                break
            try:
                insn = decode(base, p)
            except EfeError as e:
                errors.append(str(e))
                break
            insns[p] = insn
            o, op = insn["operands"], insn["op"]
            if op == 7:
                todo.append((o["target"], "branch"))
            elif op == 9:
                todo.append((o["target"], "jump"))
            elif op == 13:
                todo.append((o["target"], "call"))
                found_entries.setdefault(o["target"], "call")
            elif op == 14 and insn["flags"] in (1, 2):
                pushes = [insns[q] for q in history[-2:] if insns[q]["op"] == 12 and insns[q]["operands"]["scope"]]
                if insn["flags"] == 2:  # initializeSubEffectInstructions(inst, someInst)
                    for q in pushes:
                        todo.append((q["operands"]["offset"], "sub-effect"))
                        found_entries.setdefault(q["operands"]["offset"], "sub-effect")
                elif pushes and history and insns[history[-1]]["op"] == 12:  # initializeUVAnim(..., table)
                    uv_tables.add(insns[history[-1]]["operands"]["offset"])
            if op in ENDS_FLOW:
                break
            history.append(p)
            p += insn["size"]
    return {"instructions": insns, "entries": found_entries, "uv_tables": sorted(uv_tables), "errors": errors}


def uv_keyframes(base: bytes, offset: int) -> dict:
    """UV keyframe table (initializeUVAnim): i32 count, then {i16 frames, i8 du, i8 dv}."""
    count = struct.unpack_from("<i", base, offset)[0]
    if not 0 <= count <= 256:
        raise EfeError(f"bad UV keyframe count {count} at 0x{offset:X}")
    keys = [dict(zip(("frames", "du", "dv"), struct.unpack_from("<hbb", base, offset + 4 + 4 * k))) for k in range(count)]
    return {"offset": offset, "count": count, "keyframes": keys, "size": 4 + 4 * count}
