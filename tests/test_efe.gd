extends SceneTree
## The battle effect API and VM (specs/battle_effects.md §5 step 1): PsxMath, the opcodes on a
## hand-made slot, every original technique effect run against two stub fighters, and a mod effect
## through the same API:
##   godot --headless --path . -s res://tests/test_efe.gd
## Exits 1 if a check fails. Prints the "frames to first hit" table (the reference to compare with
## the game, specs/battle_effects.md §6).

## Entities for the effects: id -> {type, location, yaw, hp, hit, on_map, on_screen}.
class StubContext extends BattleEffectContext:
	var entities := {}
	var sounds: Array = []
	var looked := []

	func entity_present(id: int) -> bool:
		return entities.has(id)

	func is_on_map(id: int) -> bool:
		return entities.has(id) and entities[id]["on_map"]

	func is_on_screen(id: int) -> bool:
		return entities.has(id) and entities[id]["on_screen"]

	func digimon_type(id: int) -> int:
		return entities[id]["type"] if entities.has(id) else -1

	func current_hp(id: int) -> int:
		return entities[id]["hp"] if entities.has(id) else 0

	func is_hit(id: int) -> bool:
		return entities.has(id) and entities[id]["hit"]

	func set_hit(id: int, value: bool) -> void:
		if entities.has(id):
			entities[id]["hit"] = value

	func location(id: int) -> Vector3i:
		return entities[id]["location"] if entities.has(id) else Vector3i.ZERO

	func rotation_y(id: int) -> int:
		return entities[id]["yaw"] if entities.has(id) else 0

	## Bone 0 at the feet, the others stacked up to the Digimon's height.
	func bone_matrix(id: int, bone: int) -> PackedInt32Array:
		if not entities.has(id):
			return PsxMath.identity()
		var bones := int(_digimon(id).get("bone_count", 1))
		if bone >= bones:
			bone = 0
		var m := PsxMath.rot_matrix_yxz(Vector3i(0, rotation_y(id), 0))
		return PsxMath.trans_matrix(m, location(id) - Vector3i(0, height(id) * bone / maxi(bones, 1), 0))

	func look_at(id: int, target: int) -> void:
		looked.append([id, target])

	func world_screen_matrix() -> PackedInt32Array:
		return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, 3000))

	func play_sound(bank: int, id: int) -> void:
		sounds.append([bank, id])

	func play_loop(bank: int, id: int) -> int:
		sounds.append([bank, id, "loop"])
		return sounds.size()


## A slot assembler: code at data-base offsets, labels, the header.
class Slot:
	var bytes := PackedByteArray()
	var pc := 0
	var labels := {}
	var fixups := []

	func _init() -> void:
		bytes.resize(EfeEffect.SLOT_SIZE)
		bytes.fill(0)

	func header(field: int, value: int) -> void:
		bytes.encode_s32(field, value)

	func put16(at: int, value: int) -> void:
		bytes.encode_s16(EfeEffect.HEADER + at, value)

	func put32(at: int, value: int) -> void:
		bytes.encode_s32(EfeEffect.HEADER + at, value)

	func org(at: int) -> void:
		pc = at

	func label(name: String) -> void:
		labels[name] = pc

	## One instruction: opcode, flag byte, operand words (a String operand is a label).
	func op(code: int, flags: int, operands := []) -> void:
		put16(pc, code | (flags << 8))
		pc += 2
		for o in operands:
			if o is String:
				fixups.append([pc, o])
				put16(pc, 0)
			else:
				put16(pc, o)
			pc += 2

	func link() -> void:
		for f in fixups:
			put16(f[0], labels[f[1]])


var _failed := 0
var _checks := 0
var data: Node


func _init() -> void:
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available():
		print("SKIP: no data porter output")
		data.free()
		quit(0)
		return
	PsxMath.setup(data)
	Rng.set_seed(1)
	_test_math()
	_test_opcodes()
	_test_mod_effect()
	_test_all_effects()
	data.free()
	print("%s: %d effect checks" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])


# --- PsxMath --------------------------------------------------------------------------------------

func _test_math() -> void:
	_eq([PsxMath.sin512(0), PsxMath.sin512(128), PsxMath.sin512(256), PsxMath.sin512(384)], [0, 4096, 0, -4096],
			"_sin quadrants")
	_eq(PsxMath.cos512(0), 4096, "_cos(0)")
	_eq(PsxMath.atan(0, 1), (1023 + 2048) & 0xFFF, "_atan along +x")
	_eq(PsxMath.atan(1, 0), (0 + 2048) & 0xFFF, "_atan along +y")
	_eq(PsxMath.get_distance(3, 4, 0), 5, "getDistance small")
	_eq(PsxMath.get_distance(300, 400, 0), 500, "getDistance with refinement")
	_eq(PsxMath.get_distance(0, 0, 0), 0, "getDistance zero")
	_eq([PsxMath.rsin(1024), PsxMath.rcos(0), PsxMath.rsin(2048)], [4096, 4096, 0], "rsin / rcos")
	var m := PsxMath.rot_matrix_yxz(Vector3i(0, 1024, 0))
	_eq([m[0], m[2], m[4], m[6], m[8]], [0, 4096, 4096, -4096, 0], "RotMatrixYXZ quarter yaw")
	_eq(PsxMath.matrix_to_euler2(PsxMath.rot_matrix_yxz(Vector3i(200, 700, -300))), Vector3i(200, 700, -300),
			"matrixToEuler2 inverts RotMatrixYXZ")
	_eq(PsxMath.matrix_to_euler1(PsxMath.rot_matrix(Vector3i(200, 700, -300))), Vector3i(200, 700, -300),
			"matrixToEuler1 inverts RotMatrix")
	_eq(PsxMath.apply_matrix_sv(m, Vector3i(0, 0, 100)), Vector3i(100, 0, 0), "ApplyMatrixSV")
	_eq(PsxMath.lerp_int(0, 100, 0, 10, 5), 50, "lerp")
	_eq([PsxMath.div(-7, 2), PsxMath.mod(-7, 2), PsxMath.s16(0x18000), PsxMath.s8(200)], [-3, -1, -0x8000, -56],
			"C division and casts")
	Rng.set_seed(5)
	var a := Rng.custom_random(-15, 15)
	Rng.set_seed(5)
	_eq(Rng.custom_random(-15, 15), a, "customRandom repeats after a reseed")
	_eq(a >= -15 and a <= 15, true, "customRandom range")


# --- the opcodes on a hand-made slot --------------------------------------------------------------

const VAR := 0x80
const CODE := 0x100


func _slot() -> Slot:
	var s := Slot.new()
	s.header(EfeEffect.H_START_SCRIPT, 0)
	s.header(EfeEffect.H_UV_ANIMS, 0x400)
	s.header(12, 0x400)
	s.header(EfeEffect.H_SUB_EFFECTS, 0x400)
	for f in [EfeEffect.H_TMD_START, EfeEffect.H_TMD_END, EfeEffect.H_TIM_START, EfeEffect.H_TIM_END, 36]:
		s.header(f, 0x438)
	s.header(EfeEffect.H_NUM_SUB_EFFECTS, 2)
	s.header(EfeEffect.H_EFFECT_ID, 0x100)
	# two free instances of 0x40 bytes at data + 0
	s.put32(0, -1)
	s.put32(0x40, -1)
	return s


func _effect(s: Slot, host: EffectHost) -> EfeEffect:
	var fx := EfeEffect.new()
	fx.host = host
	fx.ctx = host.ctx
	fx.slot_index = 0
	fx.hit.connect(host._on_hit)
	host.slots[0] = fx
	host.loaded[0] = 0x100
	_eq(fx.load_bytes(s.bytes, 0x100), BattleEffect.OK_LOADED, "hand-made slot loads")
	return fx


func _test_opcodes() -> void:
	var s := _slot()
	# init script: arithmetic, sizes, branches, calls, a built-in, indexed loads
	s.put32(0x94, 1)
	s.put32(0x98, 2)
	s.put32(0x9C, 3)
	s.put32(0xA0, 10)
	s.put32(0xA4, 20)
	s.put32(0xA8, 30)
	s.put16(0xB0, 5)
	s.put16(0xB2, 6)
	s.put16(0xB4, 7)
	s.bytes.encode_s8(EfeEffect.HEADER + 0xB8, 2)
	s.org(CODE)
	s.header(EfeEffect.H_INIT_SCRIPT, CODE)
	s.op(0, 0, [7, 0])                       # LOAD_IMMEDIATE 7
	s.op(4, 0x04, [VAR, 1])                  # var32 = reg
	s.op(0, 0, [3, 0])
	s.op(4, 0x34, [VAR, 1])                  # var32 *= 3 -> 21
	s.op(0, 0, [5, 0])
	s.op(4, 0x54, [VAR, 1])                  # var32 %= 5 -> 1
	s.op(0, 0, [100, 0])
	s.op(4, 0x01, [VAR + 4, 1])              # int8 = 100
	s.op(4, 0x11, [VAR + 4, 1])              # int8 += 100 -> -56
	s.op(0, 0, [1, 0])
	s.op(7, 0x04, [VAR, 1, "skip", 0])       # if var32 == 1 goto skip
	s.op(0, 0, [99, 0])
	s.op(4, 0x04, [VAR + 8, 1])              # (skipped)
	s.label("skip")
	s.op(0, 0, [42, 0])
	s.op(4, 0x04, [VAR + 12, 1])             # var + 12 = 42
	s.op(13, 0, ["sub", 0])                  # CALL sub
	s.op(12, 0, [0x94, 1])                   # PUSH_ADDRESS a
	s.op(12, 0, [0xA0, 1])                   # PUSH_ADDRESS b
	s.op(14, 49, [])                         # addVectors: a += b
	s.op(3, 0x12, [0xB0, 0, 0xB8, 1])        # reg = int16 table[int8 index]
	s.op(4, 0x04, [0xBC, 1])
	s.op(5, 0, [])                           # STOP
	s.label("sub")
	s.op(10, 0, [11, 0])                     # PUSH_IMMEDIATE 11
	s.op(16, 0, [VAR + 0x10, 1])             # POP_TO_VARIABLE
	s.op(15, 0, [])                          # RETURN
	# start script: spawn one instance with a tick and a draw script
	s.label("start")
	s.op(17, 0, [2, 0, 0, 0x40, 0])          # SPAWN count 2, table data + 0, stride 0x40
	s.op(12, 0, ["tick", 1])
	s.op(12, 0, ["draw", 1])
	s.op(14, 2, [])                          # initializeSubEffectInstructions
	s.op(5, 0, [])
	# tick: on frame 3 hit the target and end
	s.label("tick")
	s.op(0, 0, [3, 0])
	s.op(7, 0x04, [0, 0, "hit", 0])          # if frame == 3 goto hit
	s.op(5, 0, [])
	s.label("hit")
	s.op(14, 9, [])                          # addAttackObjectToTarget
	s.op(0, 0, [-1, 0])
	s.op(4, 0x04, [0, 0])                    # frame = -1
	s.op(5, 0, [])
	s.label("draw")
	s.op(10, 0, [1, 0])
	s.op(10, 0, [2, 0])
	s.op(14, 3, [])                          # drawTMD(1, 2)
	s.op(5, 0, [])
	s.link()
	s.header(EfeEffect.H_START_SCRIPT, s.labels["start"])

	var ctx := StubContext.new()
	ctx.data = data
	ctx.entities = {1: _entity(3, Vector3i.ZERO), 2: _entity(17, Vector3i(0, 0, -400))}
	var host := EffectHost.new(ctx)
	var fx := _effect(s, host)
	var h := EfeEffect.HEADER
	_eq(fx.mem.decode_s32(h + VAR), 1, "set, mul, mod on an int32")
	_eq(fx.mem.decode_s8(h + VAR + 4), -56, "int8 wraps")
	_eq(fx.mem.decode_s32(h + VAR + 8), 0, "a true comparison jumps")
	_eq(fx.mem.decode_s32(h + VAR + 12), 42, "after the branch")
	_eq(fx.mem.decode_s32(h + VAR + 0x10), 11, "CALL / RETURN / POP_TO_VARIABLE")
	_eq(fx.read_vec(h + 0x94), Vector3i(11, 22, 33), "built-in 49 addVectors")
	_eq(fx.mem.decode_s32(h + 0xBC), 7, "LOAD_INDEXED")
	_eq(fx.faults(), [], "no faults in the init script")

	fx.record_draws = true
	var finished := []
	fx.finished.connect(func(sub): finished.append(sub))
	_eq(host.start(0, 1, 2), 0, "start spawns instance 0")
	_eq([fx.contexts[0]["source"], fx.contexts[0]["target"]], [1, 2], "the spawn takes the attacker and target")
	var frames := 0
	while fx.is_running() and frames < 10:
		host.tick()
		host.draw()
		frames += 1
	_eq(frames, 3, "the instance ends on its 3rd frame")
	_eq(fx.draw_calls, [], "no draw after the end")
	var hit := host.pop_attack_object(2)
	_eq([hit.get("victim"), hit.get("caster"), hit.get("sub_effect"), hit.get("effect")], [2, 1, 0, 0],
			"the hit's attack object")
	_eq(ctx.is_hit(2), true, "the victim is marked")
	_eq(host.pop_attack_object(2), {}, "one hit only")
	_eq(finished.size(), 1, "finished emitted once")
	ctx.set_hit(2, false)
	host.start(0, 1, 2)
	host.tick()
	host.draw()
	_eq(fx.draw_calls, [["drawTMD", 1, 2]], "the draw script records its call")
	host.unload_all()


func _entity(type: int, location: Vector3i, yaw := 0) -> Dictionary:
	return {"type": type, "location": location, "yaw": yaw, "hp": 100, "hit": false, "on_map": true,
			"on_screen": true}


# --- a mod effect -----------------------------------------------------------------------------------

func _test_mod_effect() -> void:
	var ctx := StubContext.new()
	ctx.data = data
	ctx.entities = {1: _entity(3, Vector3i.ZERO), 2: _entity(17, Vector3i(0, 0, -400))}
	var host := EffectHost.new(ctx)
	host.scene_override = "res://tests/fixtures/hit_effect.tscn"
	var slots := host.load_moves([{"technique": 2, "caster": 0}])
	_eq(slots, [0], "a mod effect takes slot 0")
	_eq(host.start(slots[0], 1, 2), 0, "the mod effect starts")
	for i in 12:
		host.tick()
		host.draw()
	var hit := host.pop_attack_object(2)
	_eq([hit.get("victim"), hit.get("caster"), hit.get("effect")], [2, 1, 0], "the mod effect's hit is queued")
	_eq(ctx.is_hit(2), true, "the mod effect marked the victim")
	_eq(host.slots[0].is_running(), false, "the mod effect ended")
	host.unload_all()


# --- every original technique ----------------------------------------------------------------------

## The first Digimon whose technique list (or anim_technique override) holds `technique`, or -1.
func _user_of(technique: int) -> int:
	for id in 180:
		var d: Dictionary = data.digimon(id)
		for m in d.get("moves", []):
			if int(m["move"]["id"]) == technique:
				return id
		for t in d.get("anim_technique", {}).values():
			if int(t) == technique:
				return id
	return -1


func _test_all_effects() -> void:
	var rows := []
	var loaded := 0
	var faults := []
	var no_hit := []
	for technique in 122:
		var move: Dictionary = data.move(technique)
		if move.is_empty() or EffectHost.efe_folder(technique) == "":
			continue
		var user := _user_of(technique)
		if user < 0:
			user = 3
		var ctx := StubContext.new()
		ctx.data = data
		var target_type := 3 if user != 3 else 17
		# Where BTL_tickRangedAttack / BTL_tickMeleeAttack start a technique: contact for melee, else
		# distance² + (radius_a + radius_b)².
		var radii := int(data.digimon(user)["radius"]) + int(data.digimon(target_type)["radius"])
		var reach := radii
		if int(move["range"]["id"]) != 1:
			reach = int(sqrt(float(int(move.get("distance_squared", 0)) + radii * radii)))
		var self_target := int(move["range"]["id"]) == 4
		ctx.entities = {1: _entity(user, Vector3i.ZERO, PsxMath.atan(-reach, 0)),
				2: _entity(target_type, Vector3i(0, 0, -reach), PsxMath.atan(reach, 0))}
		var host := EffectHost.new(ctx)
		Rng.set_seed(technique)
		var slots := host.load_moves([{"technique": technique, "caster": 0}])
		if slots[0] < 0:
			rows.append([technique, move["name"]["text"]["en_us"] if move["name"] else "", "load failed", "", ""])
			continue
		loaded += 1
		var fx: EfeEffect = host.slots[slots[0]]
		var section := host.start(slots[0], 1, 1 if self_target else 2)
		var first := -1
		var hits := 0
		var frames := 0
		while frames < 600:
			host.tick()
			host.draw()
			frames += 1
			for victim in [1, 2]:
				while true:
					var h := host.pop_attack_object(victim)
					if h.is_empty():
						break
					hits += 1
					if first < 0:
						first = frames
				ctx.set_hit(victim, false)
			if not fx.is_running():
				break
		if not fx.faults().is_empty():
			faults.append("%d: %s" % [technique, fx.faults()[0]])
		var damaging: bool = move["category"] != "other" and int(move["power"]) > 0 and not self_target
		if damaging and hits == 0:
			no_hit.append(technique)
		rows.append([technique, move["name"]["text"]["en_us"] if move["name"] else "", section, first, hits, frames])
		host.unload_all()
	print("technique | name | start section | first hit (frame) | hits | frames run")
	for r in rows:
		print(" | ".join(r.map(func(v): return str(v))))
	print("techniques without a hit against the stub target: %s" % [no_hit])
	_eq(loaded, 120, "every technique effect loads (slot 110 is the stale copy, 121 the fill)")
	_eq(faults, [], "no VM faults in any effect")
