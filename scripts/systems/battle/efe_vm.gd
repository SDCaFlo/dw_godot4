class_name EfeVm
extends RefCounted
## The battle effect script VM (BTL_runEFEScript and its handlers, battle_effect.c:4740-5358, and the
## 97 built-ins of BTL_EFE_SUB_OPCODES; specs/battle_effects.md §2.4-2.6). It runs one EfeEffect's
## scripts on that effect's bytes. Addresses are offsets in fx.mem; entities are ids (-1 = NULL).
## The drawing built-ins pop their arguments and hand them to the effect's draw sink
## (fx.draw_calls); everything that changes the script's memory, the entities, the random numbers
## or the hits is reproduced here.

## Opcodes (BTL_jtbl_80073604).
enum { LOAD_IMMEDIATE, LOAD_VARIABLE, LOAD_RANDOM, LOAD_INDEXED, VARIABLE_OPERATOR, STOP_5, STOP_6,
		BRANCH_IF, STOP_8, JUMP, PUSH_IMMEDIATE, PUSH_VARIABLE, PUSH_ADDRESS, CALL, BUILTIN, RETURN,
		POP_TO_VARIABLE, SPAWN_SUB_EFFECT }

## A run that doesn't end within this many instructions is stopped and reported (the C has no
## limit; a script that loops forever would hang the PSX).
const MAX_STEPS := 200000

var fx: EfeEffect
## Problems met (unknown opcodes, bad addresses, runaway runs): for the tests and the debugger.
var faults: Array[String] = []

# The run's registers (EFE_SCRIPT_PTR, EFE_SCRIPT_REGISTER, the stacks, the current context).
var _pc := 0
var _w := 0
var _reg := 0
var _data: Array[int] = []
var _calls: Array = []
var _ctx := -1
var _cur := 0
var _prev := 0
var _section := -1
var _start_attacker := -1
var _start_target := -1


func _init(effect: EfeEffect) -> void:
	fx = effect


func fault(message: String) -> void:
	if faults.size() < 50:
		faults.append("%s (effect %d, pc 0x%X)" % [message, fx.effect_id, _pc])


# --- runs -----------------------------------------------------------------------------------------

## The init script at load (BTL_setupLoadedEFEFile states 0x15 / 0x16): context 0, no instance.
## Returns EFE_ACTIVE_SECTION (< -1: the load failed).
func run_init(script: int) -> int:
	_ctx = 0 if not fx.contexts.is_empty() else -1
	_cur = 0
	_prev = 0
	_section = -1
	_execute(script)
	_after_run()
	return _section


## BTL_runEFESlotScript (BTL_startEFE): the start script; spawns take the attacker and target.
func run_start(script: int, attacker: int, target: int) -> int:
	_ctx = 0 if not fx.contexts.is_empty() else -1
	_cur = 0
	_prev = 0
	_section = -1
	_start_attacker = attacker
	_start_target = target
	_execute(script)
	_after_run()
	return _section


## A sub-effect's tick or draw script (BTL_tickEFEEngine / BTL_renderEFEEngine).
func run(script: int, context: int) -> int:
	_ctx = context
	var c: Dictionary = fx.contexts[context]
	_cur = c["instance"]
	_prev = c["parent"]
	_execute(script)
	_after_run()
	return _section


## BTL_runEFEScript's end: a context whose instance ended is freed.
func _after_run() -> void:
	if _ctx < 0:
		return
	var c: Dictionary = fx.contexts[_ctx]
	if c["instance"] != 0 and fx.frame_of(c["instance"]) == -1:
		c["inst"] = 0


func _execute(script: int) -> void:
	_pc = script
	_data.clear()
	_calls = [0]
	var steps := 0
	while _pc != 0:
		steps += 1
		if steps > MAX_STEPS:
			fault("run did not end")
			return
		if not fx.valid(_pc, 2):
			fault("pc outside the slot")
			return
		_w = fx.mem.decode_s16(_pc)
		_step(_w & 0xFF)


func _arg(k: int) -> int:
	return fx.read(_pc + k * 2, 2)


## The address of a variable: ip[k] in the current instance (scope 0) or the data base.
func _addr(offset: int, scope: int) -> int:
	return offset + (_cur if scope == 0 else EfeEffect.HEADER)


## Value size from the flag nibble: 4 int32, 2 int16, else int8.
static func _size(nibble: int) -> int:
	return 4 if nibble == 4 else (2 if nibble == 2 else 1)


func push(v: int) -> void:
	_data.append(PsxMath.s32(v))


func pop() -> int:
	if _data.is_empty():
		fault("data stack underflow")
		return 0
	return _data.pop_back()


# --- opcodes --------------------------------------------------------------------------------------

func _step(op: int) -> void:
	match op:
		LOAD_IMMEDIATE:
			_reg = _arg(1)
			_pc += 6
		LOAD_VARIABLE:
			_reg = fx.read(_addr(_arg(1), _arg(2)), _size((_w >> 8) & 0xF))
			_pc += 6
		LOAD_RANDOM:
			_reg = Rng.rand()
			_pc += 2
		LOAD_INDEXED:
			var idx := fx.read(_addr(_arg(3), _arg(4)), _size((_w >> 12) & 0xF))
			var size := _size((_w >> 8) & 0xF)
			_reg = fx.read(EfeEffect.HEADER + _arg(1) + idx * size, size)
			_pc += 10
		VARIABLE_OPERATOR:
			_operate(_addr(_arg(1), _arg(2)), (_w >> 8) & 0xF, (_w >> 12) & 0xF)
			_pc += 6
		STOP_5, STOP_6, STOP_8:
			_pc = 0
		BRANCH_IF:
			var value := fx.read(_addr(_arg(1), _arg(2)), _size((_w >> 8) & 0xF))
			if _compare(value, (_w >> 12) & 0xF):
				_pc = EfeEffect.HEADER + _arg(3)
			else:
				_pc += 10
		JUMP:
			_pc = EfeEffect.HEADER + _arg(1)
		PUSH_IMMEDIATE:
			push(_arg(1))
			_pc += 6
		PUSH_VARIABLE:
			push(fx.read(_addr(_arg(1), _arg(2)), _size((_w >> 8) & 0xF)))
			_pc += 6
		PUSH_ADDRESS:
			push(_addr(_arg(1), _arg(2)))
			_pc += 6
		CALL:
			_calls.append(fx.host.target_entity_index)
			_calls.append(_ctx)
			_calls.append(_pc + 6)
			_pc = EfeEffect.HEADER + _arg(1)
		BUILTIN:
			_pc += 2
			_builtin((_w >> 8) & 0xFF)
		RETURN:
			_return()
		POP_TO_VARIABLE:
			fx.write(_addr(_arg(1), _arg(2)), 4, pop())
			_pc += 6
		SPAWN_SUB_EFFECT:
			_spawn()
		_:
			fault("unknown opcode %d" % op)
			_pc = 0


## BTL_returnFromEFESubroutine: the outer 0 ends the run.
func _return() -> void:
	_pc = _calls.pop_back() if not _calls.is_empty() else 0
	if _pc != 0:
		_ctx = _calls.pop_back()
		var c: Dictionary = fx.contexts[_ctx]
		_cur = c["instance"]
		_prev = c["parent"]
		fx.host.target_entity_index = _calls.pop_back()


## BTL_EFE_VARIABLE_OPERATORS[size][operator]: sizes 0, 1, 3 int8, 2 int16, 4 int32.
func _operate(addr: int, size_index: int, operator: int) -> void:
	var size := 4 if size_index == 4 else (2 if size_index == 2 else 1)
	var v := fx.read(addr, size)
	var r := _reg
	match operator:
		0: v = r
		1: v += r
		2: v -= r
		3: v *= r
		4: v = PsxMath.div(v, r)
		5: v = PsxMath.mod(v, r)
		6: v = v << (r & 31)
		7: v = v >> (r & 31)
	fx.write(addr, size, v)


## BTL_EFE_COMPARISONS: true (the C's 0) when `value OP register`; a true comparison jumps.
func _compare(value: int, kind: int) -> bool:
	match kind:
		0: return value == _reg
		1: return value != _reg
		2: return value < _reg
		3: return value <= _reg
		4: return value > _reg
		5: return value >= _reg
	fault("unknown comparison %d" % kind)
	return false


## BTL_spawnEFESubEffect (battle_effect.c:4680).
func _spawn() -> void:
	fx.host.target_entity_index = 1
	var n := _arg(1)
	var table := EfeEffect.HEADER + _arg(2)
	var stride := _arg(4)
	var instance := table
	var i := 0
	while i < n:
		if fx.read(instance + EfeEffect.I_FRAME, 4) == -1:
			break
		instance += stride
		i += 1
	if i == n:
		_return()
		return
	if _section == -1:
		_section = i
	var source := -1
	var target := -1
	if _ctx >= 0:
		source = fx.contexts[_ctx]["source"]
		target = fx.contexts[_ctx]["target"]
	var free := maxi(_ctx, 0)
	while free < fx.contexts.size() and fx.contexts[free]["inst"] != 0:
		free += 1
	if free >= fx.contexts.size():
		_return()
		return
	_prev = _cur
	_cur = instance
	_ctx = free
	var c: Dictionary = fx.contexts[free]
	c["instance"] = _cur
	c["parent"] = _prev
	if _prev == 0:
		c["source"] = _start_attacker
		c["target"] = _start_target
	else:
		c["source"] = source
		c["target"] = target
	_pc += 12


# --- built-ins ------------------------------------------------------------------------------------

func _context() -> Dictionary:
	return fx.contexts[_ctx] if _ctx >= 0 else {"source": -1, "target": -1, "bone_offset": 0, "inst": 0}


func _source() -> int:
	return _context()["source"]


func _target() -> int:
	return _context()["target"]


func _ectx() -> BattleEffectContext:
	return fx.ctx


## The current instance's transform.
func _pos() -> Vector3i:
	return fx.read_vec(_cur + EfeEffect.I_POS)


func _set_pos(v: Vector3i) -> void:
	fx.write_vec(_cur + EfeEffect.I_POS, v)


func _rot() -> Vector3i:
	return fx.read_vec(_cur + EfeEffect.I_ROT)


## A drawing built-in: to the effect's draw sink with the current instance (the view reads the
## pointed-to vectors now, as the C does).
func _draw(name: String, args: Array) -> void:
	fx.draw_call(name, args, _cur)


func _pops(n: int) -> Array:
	var out := []
	for i in n:
		out.push_front(pop())
	return out


func _builtin(id: int) -> void:
	match id:
		0: _check_tech_compatibility()
		1: _initialize_uv_anim()
		2: _initialize_sub_effect_instructions()
		3: _draw("drawTMD", _pops(2))
		4: _render_centered_sprite()
		5: _initialize_transform()
		6:
			push(-1)
			_apply_box_attack_hit()
		7: _rotate_vector()
		8: _set_transform_to_target_bone()
		9: _add_attack_object_to_target()
		10: _get_scattered_spawn_position()
		11: _pops(2)
		12: _interpolate_vector()
		13: _steer_transform_toward_point()
		14: _copy_target_entity_position()
		15: _set_model_object_color()
		16: _add_particle_emitter()
		17: _select_next_target_entity()
		18: _create_flash()
		19:
			var v := fx.read_vec(pop())
			_ectx().effect("cloud", [v])
		20: _draw("renderScreenSprite", _pops(13))
		21: _project_position_to_screen()
		22: _draw("renderParticleFlashSprite", _pops(9))
		23: _get_digimon_size(_target())
		24: _draw("renderProjectedSprite", _pops(13))
		25: _calculate_polar_offset()
		26: _copy_from_parent_transform()
		27:
			var timer := pop()
			_ectx().effect("entity_particles", [_source(), timer])
		28: fx.host.play_effect_sound(fx, _ctx, pop())
		29: _set_transform_to_bone_offset()
		30: _draw("renderScrollingBackground", _pops(5))
		31: _draw("renderParallaxSprites", _pops(3))
		32: _set_transform_to_source_bone()
		33: _rotate_transform_toward_point()
		34: _check_target_collision()
		35: _get_uv_anim_timer()
		36: _apply_homing_movement()
		37: _get_digimon_size(_source())
		38: _sine(true)
		39: _sine(false)
		40: _interpolate_value()
		41: _get_random_in_range()
		42: pop()
		43: _get_vector_euler_angles()
		44: _find_hit_entity()
		45, 58: _normalize_rotation_angles()
		46: _set_target_to_hit_entity()
		47: _get_vector_length()
		48, 49, 50, 51, 52, 53, 54: _vector_op(id)
		55: _center_transform_on_entities()
		56: _get_bone_transform(_target())
		57: _rotate_vector_by_angles()
		59: _combine_rotations()
		60: _draw("renderEFELine", _pops(7))
		61: _copy_to_parent_transform()
		62: _get_bone_transform(_source())
		63: _ectx().set_fixed_camera(true)
		64: _ectx().set_fixed_camera(false)
		65: _draw("render2DTexturedQuad", _pops(12))
		66: _draw("renderWireframeGrid", _pops(10))
		67: pop()
		68: _draw("renderWireframeBox", _pops(3))
		69: _set_transform_to_bone_matrix()
		70: _draw("render3DTexturedQuad", _pops(11))
		71, 72, 73: _vector_scalar_op(id)
		74: _convert_to_view_space()
		75: _select_random_target_entity()
		76: _get_camera_rotation()
		77: _draw("drawTMDYXZ", _pops(2))
		78: _load_clut_colors()
		79: _draw("drawTMDScreenSpace", _pops(2))
		80: _add_clut_load_prim()
		81, 94: fx.write(pop(), 4, _ectx().viewport_distance())
		82: _draw("renderRadialWaves", _pops(1))
		83: _initialize_ribbon_points()
		84: _tick_ribbon_points()
		85: _draw("renderRibbonStrip", _pops(3))
		86: _draw("renderRingTube", _pops(6))
		87: _draw("renderScreenOverlay", _pops(3))
		88:
			if _target() >= 0:
				_ectx().look_at(_source(), _target())
		89: _apply_line_attack_hit()
		90: _apply_radius_attack_hit()
		91: _apply_box_attack_hit()
		92: _draw("renderScreenFade", _pops(1))
		93: _ectx().set_map_layer(false)
		95: fx.host.mark_finished()
		96:
			var out := pop()
			fx.write(out, 4, 1 if not _ectx().is_hit(_target()) else 0)
		_:
			fault("unknown built-in %d" % id)
			_pc = 0


# --- built-ins: setup ------------------------------------------------------------------------------

## BTL_checkTechCompatibility: the bone-offset entry (EfeTechBoneOffset, 10 bytes: type, bone,
## x, y, z) of the source's original type; none → the run ends with -1.
func _check_tech_compatibility() -> void:
	var entry := pop()
	var type := PsxMath.s16(_ectx().original_type(_source()))
	while fx.read(entry, 2) != type:
		if fx.read(entry, 2) < 0:
			_section = -1
			_pc = 0
			break
		entry += 10
	fx.host.bone_offset = entry + 2
	if _ctx >= 0:
		fx.contexts[_ctx]["bone_offset"] = entry + 2


## BTL_initializeUVAnim.
func _initialize_uv_anim() -> void:
	var ptr := pop()
	var value := pop()
	var idx := pop()
	if idx < 0 or idx >= fx.num_objects:
		_section = -2
		_pc = 0
		return
	var a: Dictionary = fx.uv_anims[idx]
	a["active"] = value
	if ptr == -1:
		return
	a["keyframes"] = fx.read(ptr, 4)
	a["table"] = ptr + 4
	a["uv_frame"] = 0
	a["keyframe"] = 0
	a["frame"] = 1
	var total := 0
	for i in a["keyframes"]:
		total += fx.read(ptr + 4 + i * 4, 2)
	a["frames"] = total


## BTL_initializeSubEffectInstructions: the instance's tick and draw entry points.
func _initialize_sub_effect_instructions() -> void:
	var draw := pop()
	var tick := pop()
	if _cur != 0:
		fx.write(_cur + EfeEffect.I_FRAME, 4, 0)
	if _ctx >= 0:
		fx.contexts[_ctx]["inst"] = tick
		fx.contexts[_ctx]["draw"] = draw


## The bone offset of the context: {bone, position}.
func _bone_offset() -> Dictionary:
	var at: int = _context()["bone_offset"]
	if at == 0:
		return {"bone": 0, "position": Vector3i.ZERO}
	return {"bone": fx.read(at, 2), "position": Vector3i(fx.read(at + 2, 2), fx.read(at + 4, 2), fx.read(at + 6, 2))}


## BTL_initializeEFETransform: the parent's transform, or the source's bone offset.
func _initialize_transform() -> void:
	if _prev == 0:
		_set_transform_to_bone_offset()
		return
	for k in 6:
		fx.write(_cur + 4 + k * 4, 4, fx.read(_prev + 4 + k * 4, 4))


## BTL_setTransformToBoneOffset.
func _set_transform_to_bone_offset() -> void:
	var b := _bone_offset()
	var m := _ectx().bone_matrix(_source(), b["bone"])
	_set_pos(PsxMath.apply_matrix_sv(m, b["position"]) + PsxMath.translation(m))
	fx.write_vec(_cur + EfeEffect.I_ROT, Vector3i(0, _ectx().rotation_y(_source()), 0))


## BTL_setTransformToBoneMatrix.
func _set_transform_to_bone_matrix() -> void:
	var b := _bone_offset()
	var m := _ectx().bone_matrix(_source(), b["bone"])
	_set_pos(PsxMath.apply_matrix_sv(m, b["position"]) + PsxMath.translation(m))
	fx.write_vec(_cur + EfeEffect.I_ROT, PsxMath.matrix_to_euler2(m))


## BTL_setTransformToSourceBone / BTL_setTransformToTargetBone: the bone's position, the entity's
## yaw, pushed `r` forward (25 for the source).
func _set_transform_to_bone(entity: int, bone: int, r: int) -> void:
	var t := PsxMath.translation(_ectx().bone_matrix(entity, bone))
	var yaw := _ectx().rotation_y(entity)
	var s1 := PsxMath.sin512(-(yaw >> 3))
	var s2 := PsxMath.sin512(-(((yaw >> 3) + 0x80) & 0x1FF))
	_set_pos(Vector3i(t.x + ((r * s1) >> 12), t.y, t.z + ((r * s2) >> 12)))
	fx.write_vec(_cur + EfeEffect.I_ROT, Vector3i(0, yaw, 0))


func _set_transform_to_source_bone() -> void:
	_set_transform_to_bone(_source(), pop(), 25)


func _set_transform_to_target_bone() -> void:
	var r := pop()
	var bone := pop()
	_set_transform_to_bone(_target(), bone, r)


# --- built-ins: maths -------------------------------------------------------------------------------

## EFERotateVector (efe.c:763): vec = RotMatrixZYX(rot) · vec (SVECTORs).
func _rotate_vector() -> void:
	var vp := pop()
	var rp := pop()
	fx.write_vec(vp, PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(fx.read_vec(rp)), fx.read_vec(vp)))


func _interpolate_vector() -> void:
	var out := pop()
	var t := pop()
	var t1 := pop()
	var t0 := pop()
	var b := fx.read_vec(pop())
	var a := fx.read_vec(pop())
	fx.write_vec(out, Vector3i(PsxMath.lerp_int(a.x, b.x, t0, t1, t), PsxMath.lerp_int(a.y, b.y, t0, t1, t),
			PsxMath.lerp_int(a.z, b.z, t0, t1, t)))


func _calculate_polar_offset() -> void:
	var r := pop()
	var ang := pop()
	var out := pop()
	fx.write(out + 8, 4, (r * PsxMath.sin512(0x80 - ang)) >> 12)
	fx.write(out, 4, (r * PsxMath.cos512(0x80 - ang)) >> 12)


func _sine(sine: bool) -> void:
	var out := pop()
	var scale := pop()
	var angle := pop()
	var f := PsxMath.rsin(angle & 0xFFF) if sine else PsxMath.rcos(angle & 0xFFF)
	fx.write(out, 4, (scale * f) >> 12)


func _interpolate_value() -> void:
	var end := pop()
	var start := pop()
	var t := pop()
	var hi := pop()
	var lo := pop()
	var out := pop()
	if hi < lo:
		var tmp := lo
		lo = hi
		hi = tmp
	t = clampi(t, lo, hi)
	fx.write(out, 4, start if lo == hi else start + PsxMath.div((t - lo) * (end - start), hi - lo))


func _get_random_in_range() -> void:
	var a := pop()
	var b := pop()
	fx.write(pop(), 4, Rng.custom_random(b, a))


func _get_vector_euler_angles() -> void:
	var v := fx.read_vec(pop())
	fx.write_vec(pop(), PsxMath.to_euler_angles(v.x, v.y, v.z))


## BTL_normalizeRotationAngles and BTL_normalizeRotationAngles2 (the same code): YXZ angles back
## through matrixToEuler1.
func _normalize_rotation_angles() -> void:
	var v := PsxMath.s16_vec(fx.read_vec(pop()))
	var out := pop()
	fx.write_vec(out, PsxMath.matrix_to_euler1(PsxMath.rot_matrix_yxz(v)))


## BTL_setTargetToHitEntity: ENTITY_TABLE[EFE_HIT_ENTITY_INDEX] (NULL outside the table).
func _set_target_to_hit_entity() -> void:
	if _ctx < 0:
		return
	var h := fx.host.hit_entity_index
	var present := h >= 0 and h < BattleEffectContext.ENTITIES and _ectx().entity_present(h)
	fx.contexts[_ctx]["target"] = h if present else -1


func _get_vector_length() -> void:
	var v := fx.read_vec(pop())
	fx.write(pop(), 4, PsxMath.get_distance(v.x, v.y, v.z))


## BTL_copyVector … BTL_shiftVectorsRight (ids 48-54): a op= b, element-wise.
func _vector_op(id: int) -> void:
	var b_addr := pop()
	var a_addr := pop()
	var a := fx.read_vec(a_addr)
	var b := fx.read_vec(b_addr)
	var out := a
	match id:
		48: out = b
		49: out = a + b
		50: out = a - b
		51: out = Vector3i(a.x * b.x, a.y * b.y, a.z * b.z)
		52: out = Vector3i(PsxMath.div(a.x, b.x), PsxMath.div(a.y, b.y), PsxMath.div(a.z, b.z))
		53: out = Vector3i(a.x & b.x, a.y & b.y, a.z & b.z)
		54: out = Vector3i(a.x >> (b.x & 31), a.y >> (b.y & 31), a.z >> (b.z & 31))
	fx.write_vec(a_addr, out)


## BTL_multiplyVectorByScalar, divide, mask (ids 71-73).
func _vector_scalar_op(id: int) -> void:
	var k := pop()
	var addr := pop()
	var v := fx.read_vec(addr)
	match id:
		71: v = v * k
		72: v = Vector3i(PsxMath.div(v.x, k), PsxMath.div(v.y, k), PsxMath.div(v.z, k))
		73: v = Vector3i(v.x & k, v.y & k, v.z & k)
	fx.write_vec(addr, v)


func _rotate_vector_by_angles() -> void:
	var v_addr := pop()
	var w := PsxMath.s16_vec(fx.read_vec(pop()))
	fx.write_vec(v_addr, PsxMath.apply_matrix_lv(PsxMath.rot_matrix_yxz(w), fx.read_vec(v_addr)))


func _combine_rotations() -> void:
	var b := PsxMath.s16_vec(fx.read_vec(pop()))
	var a_addr := pop()
	var a := PsxMath.s16_vec(fx.read_vec(a_addr))
	fx.write_vec(a_addr, PsxMath.multiply_rotations(a, b))


func _convert_to_view_space() -> void:
	var rot := PsxMath.s16_vec(fx.read_vec(pop()))
	var trans := fx.read_vec(pop())
	var out2 := pop()
	var out1 := pop()
	var m1 := PsxMath.trans_matrix(PsxMath.rot_matrix_yxz(rot), trans)
	var m2 := PsxMath.gs_mul_coord0(_ectx().world_screen_matrix(), m1)
	fx.write_vec(out1, PsxMath.translation(m2))
	fx.write_vec(out2, PsxMath.matrix_to_euler2(m2))


func _get_camera_rotation() -> void:
	fx.write_vec(pop(), PsxMath.matrix_to_euler2(PsxMath.transpose(_ectx().world_screen_matrix())))


func _project_position_to_screen() -> void:
	var depth_out := pop()
	var y_out := pop()
	var x_out := pop()
	var pos := PsxMath.s16_vec(fx.read_vec(pop()))
	var p := _ectx().world_to_screen(pos)
	# worldPosToScreenPos returns OTZ (SZ3 >> 2) << 2; the built-in keeps >> 4 of it.
	fx.write(depth_out, 4, ((int(p["sz"]) >> 2) << 2) >> 4)
	fx.write(x_out, 4, p["screen"].x)
	fx.write(y_out, 4, p["screen"].y)


# --- built-ins: transforms and entities ------------------------------------------------------------

## BTL_getScatteredSpawnPosition.
func _get_scattered_spawn_position() -> void:
	var r := pop()
	var out := pop()
	var v := Vector3i.ZERO
	if _prev == 0:
		v = PsxMath.translation(_ectx().bone_matrix(_source(), _bone_offset()["bone"]))
	else:
		v = fx.read_vec(_prev + EfeEffect.I_POS)
	if r > 0:
		v.x += PsxMath.mod(Rng.rand(), r) - (r >> 1)
		v.y += PsxMath.mod(Rng.rand(), r) - (r >> 1)
		v.z += PsxMath.mod(Rng.rand(), r) - (r >> 1)
	fx.write_vec(out, v)


## BTL_steerTransformTowardPoint.
func _steer_transform_toward_point() -> void:
	var turn := pop()
	var speed := pop()
	var target := fx.read_vec(pop())
	var pos := _pos()
	var rot := _rot()
	var local := PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(0, -rot.y, 0)),
			Vector3i(target.x - pos.x, 0, target.z - pos.z))
	var d := ((-(PsxMath.atan(local.x, local.z) - 0x400)) & 0xFFF)
	if d >= 0x801:
		d -= 0x1000
	if d > 0:
		if d < turn:
			turn = d
	elif -d < turn:
		turn = d
	else:
		turn = -turn
	var yaw := rot.y + turn
	fx.write(_cur + EfeEffect.I_ROT + 4, 4, yaw)
	var step := PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(rot.x, yaw, rot.z)), Vector3i(0, 0, -speed * 8))
	_set_pos(pos + Vector3i(step.x >> 3, step.y >> 3, step.z >> 3))


## BTL_copyTargetEntityPosition: the target's root world position.
func _copy_target_entity_position() -> void:
	fx.write_vec(pop(), PsxMath.translation(_ectx().bone_matrix(_target(), 0)))


func _get_digimon_size(entity: int) -> void:
	var out := pop()
	var r := PsxMath.s16(_ectx().radius(entity))
	fx.write_vec(out, Vector3i(r, PsxMath.s16(_ectx().height(entity)), r))


## BTL_copyFromParentTransform / BTL_copyToParentTransform (sizes 12, 8 (to only), 4, 2, 1).
func _copy_from_parent_transform() -> void:
	var size := pop()
	var off := pop()
	var dst := pop()
	_copy_bytes(_prev + off, dst, size, false)


func _copy_to_parent_transform() -> void:
	var size := pop()
	var off := pop()
	var src := pop()
	_copy_bytes(src, _prev + off, size, true)


func _copy_bytes(src: int, dst: int, size: int, allow_8: bool) -> void:
	match size:
		12:
			fx.write_vec(dst, fx.read_vec(src))
		8:
			if allow_8:
				fx.write(dst, 4, fx.read(src, 4))
				fx.write(dst + 4, 4, fx.read(src + 4, 4))
		4, 2, 1:
			fx.write(dst, size, fx.read(src, size))


## BTL_rotateTransformTowardPoint: the yaw to a point.
func _rotate_transform_toward_point() -> void:
	var p := fx.read_vec(pop())
	var q := _pos()
	fx.write(_cur + EfeEffect.I_ROT + 4, 4, (-(PsxMath.atan(p.x - q.x, p.z - q.z) - 0x400)) & 0xFFF)


## BTL_checkTargetCollision: the target within `r` (xz) of the instance.
func _check_target_collision() -> void:
	var r := pop()
	var flag := pop()
	var out2 := pop()
	var out := pop()
	var t := PsxMath.translation(_ectx().bone_matrix(_target(), 0))
	var pos := _pos()
	var d0 := pos.x - t.x
	var d1 := pos.z - t.z
	if r * r < d0 * d0 + d1 * d1:
		fx.write(flag, 4, 0)
		return
	fx.write(flag, 4, 1)
	var ang := PsxMath.s16(((-(PsxMath.atan(d0, d1) - 0x400)) & 0xFFF))
	fx.write(out2, 4, ang + 0x800)
	ang = PsxMath.s16(ang + 0x800) >> 3
	fx.write(out + 8, 4, (r * PsxMath.sin512(0x80 - ang)) >> 12)
	fx.write(out, 4, (r * PsxMath.cos512(0x80 - ang)) >> 12)


func _get_uv_anim_timer() -> void:
	var idx := pop()
	var out := pop()
	var frame := 0
	if idx >= 0 and idx < fx.uv_anims.size():
		frame = fx.uv_anims[idx]["frame"]
	fx.write(out, 4, frame)


## BTL_applyHomingMovement.
func _apply_homing_movement() -> void:
	var limit := pop()
	var speed_addr := pop()
	pop()
	var max_speed := pop()
	var min_speed := pop()
	var target := fx.read_vec(pop())
	var pos := _pos()
	var rot := _rot()
	var local := PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(0, -rot.y, 0)), target - pos)
	var yaw := (-(PsxMath.atan(local.x, local.z) - 0x400)) & 0xFFF
	if yaw >= 0x801:
		yaw -= 0x1000
	var dy := yaw if absi(yaw) < limit else (limit if yaw > 0 else -limit)
	rot.y += dy
	fx.write(_cur + EfeEffect.I_ROT + 4, 4, rot.y)
	var pitch := (PsxMath.atan(local.y, local.z) - 0x400 - rot.z) & 0xFFF
	if pitch >= 0x801:
		pitch -= 0x1000
	var dp := pitch if absi(pitch) < limit else (limit if pitch > 0 else -limit)
	rot.z += dp
	if (rot.z & 0xFFF) >= 0x400 and (rot.z & 0xFFF) < 0xC00:
		rot.z = 0x800 - rot.z
	fx.write(_cur + EfeEffect.I_ROT + 8, 4, rot.z)
	var speed := fx.read(speed_addr, 4)
	if PsxMath.div(limit * 40, 100) >= absi(dp) + absi(dy):
		speed = mini(PsxMath.div(speed * 130, 100), max_speed)
	else:
		speed = maxi(PsxMath.div(speed * 82, 100), min_speed)
	fx.write(speed_addr, 4, speed)
	var out := PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(rot.z, 0, 0)), Vector3i(0, 0, -speed << 3))
	out = PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(0, rot.y, 0)), out)
	_set_pos(pos + Vector3i(out.x >> 3, out.y >> 3, out.z >> 3))


## BTL_getSourceBoneTransform / BTL_getTargetBoneTransform.
func _get_bone_transform(entity: int) -> void:
	var rot_out := pop()
	var pos_out := pop()
	var bone := pop()
	var m := _ectx().bone_matrix(entity, bone)
	fx.write_vec(rot_out, PsxMath.matrix_to_euler2(m))
	fx.write_vec(pos_out, PsxMath.translation(m))


## BTL_centerTransformOnEntities: the average root position of the others on the map.
func _center_transform_on_entities() -> void:
	var sum := Vector3i.ZERO
	var count := 0
	for i in range(1, BattleEffectContext.ENTITIES):
		if not _ectx().entity_present(i) or i == _source() or not _ectx().is_on_map(i):
			continue
		count += 1
		sum += PsxMath.translation(_ectx().bone_matrix(i, 0))
	fx.write_vec(_cur + EfeEffect.I_ROT, Vector3i.ZERO)
	_set_pos(Vector3i(PsxMath.div(sum.x, count), PsxMath.div(sum.y, count), PsxMath.div(sum.z, count)))


## BTL_selectNextTargetEntity: the next living, visible entity other than the source.
func _select_next_target_entity() -> void:
	var out := pop()
	var host := fx.host
	if host.target_entity_index >= BattleEffectContext.ENTITIES:
		fx.write(out, 4, -1)
		return
	while host.target_entity_index < BattleEffectContext.ENTITIES:
		var e := host.target_entity_index
		if _ectx().entity_present(e) and e != _source() and _ectx().is_on_map(e) and _ectx().is_on_screen(e) \
				and _ectx().current_hp(e) > 0:
			break
		host.target_entity_index += 1
	if host.target_entity_index >= BattleEffectContext.ENTITIES:
		fx.write(out, 4, -1)
		return
	if _ctx >= 0:
		fx.contexts[_ctx]["target"] = host.target_entity_index
	fx.write(out, 4, host.target_entity_index)
	host.target_entity_index += 1


## BTL_selectRandomTargetEntity.
func _select_random_target_entity() -> void:
	var exclude_self := pop()
	var host := fx.host
	var entity := -1
	var n := PsxMath.mod(Rng.rand(), 8)
	var guard := 0
	while n >= 0:
		host.target_entity_index += 1
		while true:
			guard += 1
			if guard > 1000:
				fault("selectRandomTargetEntity found no entity")
				return
			var found := false
			while host.target_entity_index < BattleEffectContext.ENTITIES:
				var e := host.target_entity_index
				if _ectx().entity_present(e) and _ectx().is_on_map(e) and _ectx().current_hp(e) > 0 \
						and (exclude_self != 0 or e != _source()):
					entity = e
					found = true
					break
				host.target_entity_index += 1
			if found:
				break
			host.target_entity_index += 1
			if host.target_entity_index >= BattleEffectContext.ENTITIES:
				host.target_entity_index = 1
		n -= 1
	if _ctx >= 0:
		fx.contexts[_ctx]["target"] = entity


# --- built-ins: effects, ribbons, flashes ----------------------------------------------------------

## BTL_renderCenteredSprite: pushes the sprite's layout and draws it (net: 2 arguments).
func _render_centered_sprite() -> void:
	var y := pop()
	var x := pop()
	for v in [x + 1, y + 1, PsxMath.div(x, 2), PsxMath.div(y, 2), 0, 5, 0]:
		push(v)
	_draw("renderProjectedSprite", _pops(13))


## BTL_addParticleEmitter: one of the host's 4 emitters follows the instance.
func _add_particle_emitter() -> void:
	var frames := pop()
	var color := fx.read_vec(pop())
	var n := pop()
	var kind := pop()
	fx.host.add_emitter(fx, _cur, kind, n, color, frames)


## EFECreateFlash (efe.c:808): the position and colours are read through their pointers now.
func _create_flash() -> void:
	var a := _pops(8)
	_ectx().effect("flash", [a[0], fx.read_vec(a[1]), a[2], a[3], a[4], a[5], fx.read_vec(a[6]), fx.read_vec(a[7])])


## BTL_loadClutColors (battle_effect.c:2744): `count` (1-16) colours, each four int16 (r, g, b, stp)
## packed r + g << 5 + b << 10 + stp << 15 (uint16), into CLUT row y from column x. Pushed: y, x,
## count, colours*.
func _load_clut_colors() -> void:
	var a := _pops(4)
	if a[2] > 0 and a[2] <= 16:
		var colors := []
		for i in a[2]:
			var at: int = a[3] + i * 8
			colors.append((fx.read(at, 2) + (fx.read(at + 2, 2) << 5) + (fx.read(at + 4, 2) << 10)
					+ (fx.read(at + 6, 2) << 15)) & 0xFFFF)
		fx.write_clut(a[0], a[1], colors)
	_draw("loadClutColors", a)


## BTL_addClutLoadPrim (battle_effect.c:2700): a DR_LOAD of 16 raw colours from colours* + 2 · index
## into CLUT row y, at an OT slot: the port applies it at once (the C's later primitives see it
## the same frame, the earlier ones the next). Pushed: OT slot, y, colours*, index.
func _add_clut_load_prim() -> void:
	var a := _pops(4)
	var colors := []
	for i in 16:
		colors.append(fx.read(a[2] + a[3] * 2 + i * 2, 2) & 0xFFFF)
	fx.write_clut(a[1], 0, colors)
	_draw("addClutLoadPrim", a)


## BTL_setEFEModelObjectColor (battle_effect.c:4327): the object's colour (EfeColor: three int32)
## changes the slot's own TMD, so it stays for the slot's later uses.
func _set_model_object_color() -> void:
	var a := _pops(2)
	fx.set_object_color(a[0], fx.read_vec(a[1]))
	_draw("setEFEModelObjectColor", a)


## BTL_initializeRibbonPoints: 10 SVECTORs (8 bytes: x, y, z, pad).
func _initialize_ribbon_points() -> void:
	var q := pop()
	for i in 10:
		var at := q + i * 8
		fx.write(at, 2, i * 0x190 - 0x708)
		fx.write(at + 2, 2, Rng.custom_random(-0x96, 0x96))
		fx.write(at + 6, 2, Rng.custom_random(-0x1E, 0x1E))
		fx.write(at + 4, 2, 0)


## BTL_tickRibbonPoints.
func _tick_ribbon_points() -> void:
	var q := pop()
	var frame := fx.frame_of(_cur)
	for i in 10:
		var at := q + i * 8
		if PsxMath.mod(frame + i * 8, 10) == 0:
			fx.write(at + 6, 2, Rng.custom_random(-0xF, 0xF))
		var pad := fx.read(at + 6, 2)
		fx.write(at + 2, 2, clampi(fx.read(at + 2, 2) + pad, -0x96, 0x96))
		fx.write(at + 4, 2, clampi(fx.read(at + 4, 2) + pad, -0x96, 0x96))


# --- built-ins: hits ------------------------------------------------------------------------------

## The source's entity index as the C finds it (`for (j = 1; j < 10; j++) if (ENTITY_TABLE[j] ==
## source) break;`): 10 when the source isn't an entity 1-9.
func _caster() -> int:
	var s := _source()
	return s if s >= 1 and s < BattleEffectContext.ENTITIES else BattleEffectContext.ENTITIES


func _hit(victim: int, pos: Vector3i, sub_effect: int) -> void:
	_ectx().set_hit(victim, true)
	fx.host.hit_entity_index = victim
	fx.host.report_hit(fx, victim, PsxMath.s16_vec(pos), sub_effect, _caster())


## findAABBHitEntity (aabb.c:48), the context's.
func _find_aabb_entity(center: Vector3i, extent: Vector3i, ignore: int, start: int) -> int:
	return _ectx().find_aabb_entity(center, extent, ignore, start)


## BTL_applyBoxAttackHit (91; 6 pushes r = -1): the first unhit entity in the box.
func _apply_box_attack_hit() -> void:
	var r := pop()
	var out := pop()
	var extent := PsxMath.s16_vec(fx.read_vec(pop()))
	fx.write(out, 4, 0)
	if r < 0:
		r = fx.host.sub_effect_index
	var center := PsxMath.s16_vec(_pos())
	var i := 1
	while true:
		i = _find_aabb_entity(center, extent, _source(), i)
		fx.host.hit_entity_index = i
		if i == -1:
			return
		if not _ectx().is_hit(i):
			_hit(i, center, r)
			fx.write(out, 4, 1)
			return
		i += 1


## BTL_findHitEntity (44): the same test without a hit.
func _find_hit_entity() -> void:
	var extent := PsxMath.s16_vec(fx.read_vec(pop()))
	var mode := pop()
	var out := pop()
	fx.write(out, 4, 0)
	var center := PsxMath.s16_vec(_pos())
	var i := 1
	while true:
		i = _find_aabb_entity(center, extent, _source(), i)
		fx.host.hit_entity_index = i
		if i == -1:
			return
		match mode:
			0:
				if not _ectx().is_hit(i):
					fx.write(out, 4, 1)
					return
				i += 1
			1:
				fx.write(out, 4, 1)
				return
			_:
				return


## BTL_calculateAttackHitPosition: on the line from `self` towards `other`, `y` out, at self's top.
func _attack_hit_position(self_id: int, other: int, y: int) -> Vector3i:
	var a := _ectx().location(self_id)
	var b := _ectx().location(other)
	var yaw := (PsxMath.atan(b.z - a.z, b.x - a.x) + 0x800) & 0xFFF
	var out := PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(Vector3i(0, yaw, 0)), Vector3i(0, -_ectx().height(self_id), y))
	return Vector3i(PsxMath.s16(out.x + PsxMath.s16(a.x)), out.y, PsxMath.s16(out.z + PsxMath.s16(a.z)))


func _hittable(i: int) -> bool:
	return _ectx().entity_present(i) and i != _source() and not _ectx().is_hit(i) and _ectx().is_on_map(i)


## BTL_applyRadiusAttackHit (90): every unhit entity within r + its radius (xz).
func _apply_radius_attack_hit() -> void:
	var flag := pop()
	var r := pop()
	fx.write(flag, 4, 0)
	r = r * r
	var pos := _pos()
	for i in range(1, BattleEffectContext.ENTITIES):
		fx.host.hit_entity_index = i
		if not _hittable(i):
			continue
		var radius := _ectx().radius(i)
		var loc := _ectx().location(i)
		var dx := pos.x - loc.x
		var dz := pos.z - loc.z
		if radius * radius + r < dz * dz + dx * dx:
			continue
		var at := _attack_hit_position(i, _source(), radius)
		at.y = PsxMath.s16(-_ectx().height(i) / 2)
		_hit(i, at, fx.host.sub_effect_index)
		fx.write(flag, 4, 1)
	fx.host.hit_entity_index = BattleEffectContext.ENTITIES


## doSomethingWithSomePoints (effect_common.c:679): -1 when the segment crosses the rectangle
## (x0, z0, x1, z1); 0 when it misses.
static func _segment_hits_rect(rect: Array, a: Vector2i, b: Vector2i) -> bool:
	var codes := []
	for p in [a, b]:
		var c := 5 if rect[2] < p.x else (3 if p.x < rect[0] else 4)
		if rect[3] < p.y:
			c += 3
		elif p.y < rect[1]:
			c -= 3
		if c == 4:
			return true
		codes.append(c)
	if codes[0] + codes[1] == 8:
		return true
	if codes[0] / 3 == codes[1] / 3 or codes[0] % 3 == codes[1] % 3:
		return false
	var dx := b.x - a.x
	var dy := b.y - a.y
	var corners := [Vector2i(rect[0], rect[1]), Vector2i(rect[2], rect[1]), Vector2i(rect[0], rect[3]), Vector2i(rect[2], rect[3])]
	var cross: int = dx * (corners[0].y - a.y) - dy * (corners[0].x - a.x)
	for i in range(1, 4):
		if cross * (dx * (corners[i].y - a.y) - dy * (corners[i].x - a.x)) < 0:
			return true
	return false


## BTL_applyLineAttackHit (89): the segment source → instance (xz) against each entity's square.
func _apply_line_attack_hit() -> void:
	pop()
	var out := pop()
	var arg := pop()
	fx.write(out, 4, 0)
	var pos := _pos()
	var src := _ectx().location(_source())
	var a := Vector2i(PsxMath.s16(pos.x), PsxMath.s16(pos.z))
	var b := Vector2i(PsxMath.s16(src.x), PsxMath.s16(src.z))
	for i in range(1, BattleEffectContext.ENTITIES):
		fx.host.hit_entity_index = i
		if not _hittable(i):
			continue
		var r := _ectx().radius(i)
		var loc := _ectx().location(i)
		var rect := [PsxMath.s16(loc.x - r), PsxMath.s16(loc.z - r), PsxMath.s16(loc.x + r), PsxMath.s16(loc.z + r)]
		if not _segment_hits_rect(rect, a, b):
			continue
		if pos.y < -_ectx().height(i) - fx.read(arg + 4, 4):
			continue
		var at := _attack_hit_position(i, _source(), r)
		at.y = PsxMath.s16(pos.y)
		_hit(i, at, fx.host.sub_effect_index)
		fx.write(out, 4, 1)
		return
	fx.host.hit_entity_index = BattleEffectContext.ENTITIES


## BTL_addAttackObjectToTarget (9): the context's target, if unhit, at the instance.
func _add_attack_object_to_target() -> void:
	var target := _target()
	if target < 0 or _ectx().is_hit(target):
		return
	var victim := target if target >= 1 and target < BattleEffectContext.ENTITIES else BattleEffectContext.ENTITIES
	_ectx().set_hit(target, true)
	fx.host.report_hit(fx, victim, PsxMath.s16_vec(_pos()), fx.host.sub_effect_index, _caster())
