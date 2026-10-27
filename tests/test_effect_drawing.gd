extends SceneTree
## The logic under the battle effects' drawing (step 5d-5a, specs/battle_effects.md §7): the hit
## sparks' rolls in the C's order and their entity parts (ParticleBursts), the shared effects
## (BattleFx: entity particles, clouds, flashes), the slot state the drawing reads (object colours,
## the flash's arguments read through their pointers), the PSX -> Godot basis of the effect
## models, and the map camera's GsWSMATRIX:
##   godot --headless --path . -s res://tests/test_effect_drawing.gd
## Exits 1 if a check fails. The drawing itself is checked in the field by tests/effect_scan.tscn.

const TestEfe := preload("res://tests/test_efe.gd")

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
	_test_spark_rolls()
	_test_spark_entity_parts()
	_test_battle_fx()
	_test_slot_state()
	_test_basis()
	_test_world_screen_matrix()
	data.free()
	print("%s: effect drawing checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])


func _rolls(seed_value: int, n: int) -> Array:
	Rng.set_seed(seed_value)
	var out := []
	for i in n:
		out.append(Rng.rand())
	return out


## createParticleFX fills spread[coordinate][flash] flash by flash: dx, dy, dz, size.
func _test_spark_rolls() -> void:
	var r := _rolls(5, 13)
	Rng.set_seed(5)
	var b := ParticleBursts.new()
	b.create(2, 0, Vector3i(10, 20, 30))
	var fx: Dictionary = b.effects[0]
	_eq(fx["spread"][0], [r[0] % 200 - 100, r[1] % 200 - 100, r[2] % 200 - 100, r[3] % 170 + 250],
			"the first flash's spread: dx, dy, dz, then its size")
	_eq(fx["spread"][1], [r[4] % 200 - 100, r[5] % 200 - 100, r[6] % 200 - 100, r[7] % 170 + 250], "the second flash's")
	_eq(Rng.rand(), r[8], "mode 0 rolls 8 times")
	r = _rolls(6, 13)
	Rng.set_seed(6)
	b.create(0, 1, Vector3i.ZERO)
	_eq(b.effects[1]["spread"][2], [r[8] % 200 - 100, r[9] % 200 - 100, r[10] % 200 - 100, r[11] % 200 + 300],
			"mode 1's third flash, its size rand % 200 + 300")
	r = _rolls(7, 9)
	Rng.set_seed(7)
	b.create(9, 0, Vector3i.ZERO)
	_eq([b.active_count(), Rng.rand()], [2, r[8]], "an unknown kind uses its 8 rolls and no slot")


## tickParticleFX with an entity: entity particles on frames 10 and 13, mode 1's dust clouds over
## its last frames, then the end.
func _test_spark_entity_parts() -> void:
	var added := []
	var clouds := []
	var b := ParticleBursts.new()
	b.add_entity_particles = func(entity: int, timer: int) -> void: added.append([entity, timer])
	b.create_cloud = func(at: Vector3i) -> void: clouds.append(at)
	b.entity_ground = func(_entity: int) -> Vector3i: return Vector3i(1000, 2000, 100)
	Rng.set_seed(3)
	b.create(1, 0, Vector3i.ZERO, 0x11, 4)
	for i in 10:
		b.tick()
	_eq(added, [[4, 0xE], [4, 0xE], [4, 0xE]], "mode 0, frame 10: three entity particles of 14 frames")
	for i in 3:
		b.tick()
	_eq(added.size(), 5, "frame 13: two more")
	added.clear()
	b = ParticleBursts.new()
	b.add_entity_particles = func(entity: int, timer: int) -> void: added.append([entity, timer])
	b.create_cloud = func(at: Vector3i) -> void: clouds.append(at)
	b.entity_ground = func(_entity: int) -> Vector3i: return Vector3i(1000, 2000, 100)
	b.create(1, 1, Vector3i.ZERO, 20, 2)
	var n := 0
	while b.active_count() > 0 and n < 100:
		b.tick()
		n += 1
	_eq(added, [[2, 0x16], [2, 0x16], [2, 0x16], [2, 0x16], [2, 0xE]], "mode 1: 0x16 three times, then 0x16 and 0xE")
	# end_frame = lifetime + 4 = 24 counts down; frames with end_frame 3, 2, 1, 0 scatter 5, 4, 3, 2.
	_eq(clouds.size(), 14, "mode 1 scatters end_frame + 2 clouds on each of its last 4 frames")
	var near := true
	for c in clouds:
		var d := Vector2(c.x - 1000, c.z - 2000).length()
		near = near and d >= 99 and d <= 151
	_eq(near, true, "the clouds lie radius + rand % (radius / 2) from the entity")
	_eq(n, 25, "the burst ends once its timer and lifetime have run out")


func _ctx() -> TestEfe.StubContext:
	var ctx := TestEfe.StubContext.new()
	ctx.data = data
	ctx.entities = {1: {"type": 3, "location": Vector3i.ZERO, "yaw": 0, "hp": 10, "hit": false, "on_map": true,
			"on_screen": true}}
	return ctx


func _test_battle_fx() -> void:
	var fx := BattleFx.new(_ctx())
	var bones := int(data.digimon(3)["bone_count"])
	Rng.set_seed(11)
	var r := _rolls(11, 4)
	Rng.set_seed(11)
	_eq(fx.add_entity_particles(1, 8), 0, "an entity particle takes slot 0")
	_eq(fx.entity_particles[0]["bone"], r[0] % (bones - 1) + 1, "on a random bone 1 to boneCount - 1")
	fx.tick()
	_eq([fx.entity_particles[0]["bone"], fx.entity_particles[0]["sprite"]], [r[1] % (bones - 1) + 1, r[2] % 9],
			"every 4th frame a new bone and sprite")
	for i in 8:
		fx.tick()
	_eq(fx.entity_particles[0]["timer"], -1, "it ends after its timer")
	fx.create_cloud(Vector3i(5, 0, 6))
	for i in 13:
		fx.tick()
	_eq(fx.clouds[0]["state"], 13, "a cloud's 14 states")
	fx.tick()
	_eq(fx.clouds[0]["state"], -1, "then it goes")
	_eq(fx.create_flash(2, Vector3i.ZERO, 0, 5, 1, 2, Vector3i.ONE, Vector3i.ONE), -1, "flash mode 2 is unknown")
	_eq(fx.create_flash(-0x20, Vector3i.ZERO, 0, 5, 1, 2, Vector3i.ONE, Vector3i.ONE), 0, "a negative mode is |mode|")
	for i in 4:
		fx.tick()
	_eq(fx.flashes[0]["progress"], 4, "a flash counts its frames")
	fx.tick()
	_eq(fx.active_count(), 0, "and ends at its frame count")


## setEFEModelObjectColor keeps the colour in the slot; EFECreateFlash reads its vectors now.
func _test_slot_state() -> void:
	var s := TestEfe.Slot.new()
	s.header(EfeEffect.H_START_SCRIPT, 0)
	s.header(EfeEffect.H_UV_ANIMS, 0x400)
	s.header(12, 0x400)
	s.header(EfeEffect.H_SUB_EFFECTS, 0x400)
	# A TMD header of 2 objects at data + 0x438.
	s.header(EfeEffect.H_TMD_START, 0x438)
	s.header(EfeEffect.H_TMD_END, 0x450)
	for f in [EfeEffect.H_TIM_START, EfeEffect.H_TIM_END, 36]:
		s.header(f, 0x450)
	s.put32(0x438 + 8, 2)
	s.header(EfeEffect.H_NUM_SUB_EFFECTS, 1)
	s.header(EfeEffect.H_EFFECT_ID, 0x100)
	s.put32(0x100, 0x60)
	s.put32(0x104, 0x40)
	s.put32(0x108, 0x20)
	s.put32(0x110, 300)
	s.put32(0x114, -50)
	s.put32(0x118, 700)
	s.put32(0x120, 0x80)
	s.put32(0x124, 0x80)
	s.put32(0x128, 0x80)
	s.org(0x200)
	s.header(EfeEffect.H_INIT_SCRIPT, 0x200)
	s.op(10, 0, [1, 0])                      # PUSH_IMMEDIATE 1 (object)
	s.op(12, 0, [0x100, 1])                  # PUSH_ADDRESS colour
	s.op(14, 15, [])                         # setEFEModelObjectColor
	s.op(10, 0, [0x20, 0])                   # mode
	s.op(12, 0, [0x110, 1])                  # position*
	s.op(10, 0, [0, 0])                      # fixed depth
	s.op(10, 0, [12, 0])                     # frames
	s.op(10, 0, [10, 0])                     # scale min
	s.op(10, 0, [40, 0])                     # scale max
	s.op(12, 0, [0x100, 1])                  # colour min*
	s.op(12, 0, [0x120, 1])                  # colour max*
	s.op(14, 18, [])                         # EFECreateFlash
	s.op(5, 0, [])
	s.link()
	var ctx := _ctx()
	var host := EffectHost.new(ctx)
	var fx := EfeEffect.new()
	fx.host = host
	fx.ctx = ctx
	_eq(fx.load_bytes(s.bytes, 0x100), BattleEffect.OK_LOADED, "the slot with a 2-object TMD loads")
	_eq(fx.object_colors, {1: Vector3i(0x60, 0x40, 0x20)}, "object 1's colour stays in the slot")
	var f: Dictionary = ctx.fx.flashes[0]
	_eq([f["mode"], f["position"], f["t_max"], f["scale_min"], f["scale_max"], f["color_min"], f["color_max"]],
			[0x20, Vector3i(300, -50, 700), 12, 10, 40, Vector3i(0x60, 0x40, 0x20), Vector3i(0x80, 0x80, 0x80)],
			"the flash took its position and colours through their pointers")
	fx.free()


## The effect models' transform: F · M · F (F the porter's flip); a turn about y matches the
## entities' yaw (Content.psx_yaw).
func _test_basis() -> void:
	_eq(EfeView._godot_basis(PsxMath.identity()).is_equal_approx(Basis.IDENTITY), true, "identity stays identity")
	var yaw := EfeView._godot_basis(PsxMath.rot_matrix(Vector3i(0, 1024, 0)))
	_eq(yaw.is_equal_approx(Basis(Vector3.UP, Content.psx_yaw(1024))), true,
			"a quarter turn about y turns like the entities (%s)" % yaw)
	var scaled := EfeView._godot_basis(PsxMath.scale_matrix(PsxMath.identity(), Vector3i(8192, 4096, 2048)))
	_eq(scaled.get_scale().is_equal_approx(Vector3(2, 1, 0.5)), true, "the script's scale vector")


## GsWSMATRIX from the map's camera: a point on the camera's axis has view x = y = 0 and z its
## distance.
func _test_world_screen_matrix() -> void:
	var map := FieldMap.new()
	map._eye = Vector3(100, -50, 200)
	map._forward = Vector3(0, 0.6, 0.8)
	map._down = Vector3(0, 0.8, -0.6)
	map._right = Vector3(1, 0, 0)
	var m := map.world_screen_matrix()
	var p := Vector3(100, -50, 200) + Vector3(0, 0.6, 0.8) * 1000
	var v := PsxMath.apply_matrix_lv(m, Vector3i(roundi(p.x), roundi(p.y), roundi(p.z))) + PsxMath.translation(m)
	_eq(absi(v.x) <= 1 and absi(v.y) <= 1 and absi(v.z - 1000) <= 1, true, "a point 1000 ahead is at view (0, 0, 1000) (%s)" % v)
	map.free()
