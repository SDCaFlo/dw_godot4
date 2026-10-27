extends SceneTree
## The battle visuals outside the scripts (scripts/systems/battle/fx/, specs/battle_effects.md §7.6):
## the loading's rolls, the pools and their timings, the aura projectile's hit, the battle's end,
## and each visual drawn once:
##   godot --headless --path . -s res://tests/test_battle_visuals.gd
## Exits 1 if a check fails.

class StubContext extends BattleEffectContext:
	var entities := {}
	var offset := Vector2i(160, 120)

	func drawing_offset() -> Vector2i:
		return offset

	func entity_present(id: int) -> bool:
		return entities.has(id)

	func digimon_type(id: int) -> int:
		return entities[id]["type"] if entities.has(id) else -1

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
		var m := PsxMath.rot_matrix_yxz(Vector3i(0, rotation_y(id), 0))
		return PsxMath.trans_matrix(m, location(id) - Vector3i(0, height(id) * mini(bone, 4) / 5, 0))

	func world_screen_matrix() -> PackedInt32Array:
		return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, 3000))


var _failed := 0
var _checks := 0
var _started := false
var data: Node
var ctx: StubContext
var host: EffectHost
var v: BattleVisuals


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	return false


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual != expected:
		_failed += 1
		print("FAIL: %s: got %s, expected %s" % [what, actual, expected])


func _run() -> void:
	data = load("res://scripts/data/game_data.gd").new()
	if not data.available() or data.records("digimon/condition_fx_offsets").is_empty():
		print("SKIP: data porter output missing (or without condition_fx_offsets)")
		data.free()
		quit(0)
		return
	PsxMath.setup(data)
	ctx = StubContext.new()
	ctx.data = data
	ctx.entities[1] = {"type": 3, "location": Vector3i(0, 0, 0), "yaw": 0, "hit": false}
	ctx.entities[2] = {"type": 17, "location": Vector3i(0, 0, -600), "yaw": 0x800, "hit": false}
	host = EffectHost.new(ctx)
	v = ctx.visuals

	_rolls()
	_poison()
	_stun()
	_statuses()
	_aura_projectile()
	_timings()
	_end()
	_data()
	_drawing()
	_healing()
	_screen_origin()

	v.remove_all()
	data.free()
	print("%s: battle visuals checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)


func _ticks(n: int) -> void:
	for i in n:
		v.tick()


## loadBattleData's tables: 20 x 2 + 8 x 3 + 16 x 5 + 10 x 4 rand() calls, in that order.
func _rolls() -> void:
	Rng.set_seed(5)
	v.initialize()
	var after := Rng.rand()
	Rng.set_seed(5)
	for i in 184:
		Rng.rand()
	_eq(after, Rng.rand(), "initialize rolls 184 times")
	_eq(v.item_velocities.size(), 20, "20 item particle velocities")
	_eq(v.trail_a.size(), 8, "8 buff trails")
	_eq(v.ring_sparks.size(), 32, "16 ring spark pairs")
	_eq(v.aura_sparks.size(), 20, "10 aura spark pairs")
	# The velocities point up (y -0x230 turned by under an eighth of a turn).
	_eq(v.item_velocities.all(func(w): return w.y < 0), true, "the item particles burst up")


## A bubble at frame 1 of every 30; each lives 40 frames (2 rolls when added).
func _poison() -> void:
	v.initialize()
	v.on_visual("status", [1, 1, true, 0])
	_eq(v.live("poison"), 1, "poison on")
	_ticks(1)
	_eq(v.live("poison_bubble"), 1, "a bubble at frame 1")
	_ticks(29)
	_eq(v.live("poison_bubble"), 1, "one bubble after 30 frames")
	_ticks(1)
	_eq(v.live("poison_bubble"), 2, "the next at frame 31")
	_ticks(8)
	_eq(v.live("poison_bubble"), 2, "both at frame 39")
	_ticks(1)
	_eq(v.live("poison_bubble"), 1, "the first ends at 40")
	v.on_visual("status", [1, 1, false, 0])
	_eq(v.live("poison"), 0, "poison off")
	_eq(v.live("poison_bubble"), 1, "its bubbles rise on")


## A star every 6 frames until the duration, 8 frames of flashing, 5 of shrinking; then it ends itself.
func _stun() -> void:
	v.initialize()
	v.on_visual("status", [2, 3, true, 12])
	_ticks(12)
	_eq(v.live("stun_spark"), 2, "two stars in 12 frames")
	_eq(v.get_at("stun", 0).state, 1, "flashing at the duration")
	_ticks(10)
	_eq(v.live("stun"), 1, "still there after 22 frames")
	_ticks(1)
	_eq(v.live("stun"), 0, "it ends itself at 23")
	# The battle's later removal finds nothing (the C's entity check on a free slot).
	v.on_visual("status", [2, 3, false, 0])
	_eq(v.live("stun"), 0, "removing it again does nothing")


## One status visual per fighter; removal checks the slot's entity.
func _statuses() -> void:
	v.initialize()
	v.on_visual("status", [1, 2, true, 0])
	v.on_visual("status", [1, 2, true, 0])
	_eq(v.live("confusion"), 1, "one confusion per fighter")
	v.on_visual("status", [2, 2, true, 0])
	_eq(v.live("confusion"), 2, "another fighter's")
	v.on_visual("status", [1, 2, false, 0])
	_eq(v.live("confusion"), 1, "the first one's removed")
	_eq(v.get_at("confusion", 1).entity, 2, "the second stays")


## Fired at the enemy in front: it hits it once (effect 0x179, caster the owner), not its owner.
func _aura_projectile() -> void:
	v.initialize()
	host.attack_objects.clear()
	ctx.entities[2]["hit"] = false
	v.on_visual("aura_projectile", [1])
	var aura := v.get_at("aura_projectile", 0)
	_eq(aura.velocity, Vector3i(0, 0, -0x23), "it flies along the owner's facing")
	_ticks(40)
	_eq(v.live("aura_projectile"), 0, "it ended at the hit")
	_eq(host.attack_objects.size(), 1, "one attack object")
	if not host.attack_objects.is_empty():
		var a: Dictionary = host.attack_objects[0]
		_eq([a["victim"], a["effect"], a["sub_effect"], a["caster"]], [2, 0x179, 0, 1], "the hit's victim, effect, caster")
	_eq(ctx.is_hit(2), true, "the victim is marked hit")
	# A hit victim isn't hit again: the projectile flies on to its 58 frames.
	v.on_visual("aura_projectile", [1])
	_ticks(57)
	_eq(v.live("aura_projectile"), 1, "through a hit victim")
	_ticks(1)
	_eq(v.live("aura_projectile"), 0, "ends at 58 frames")
	_eq(host.attack_objects.size(), 1, "no second hit")
	ctx.entities[2]["hit"] = false
	host.attack_objects.clear()


func _timings() -> void:
	v.initialize()
	# The finisher aura: 0x50 frames, one roll each.
	v.on_visual("finisher_aura", [1, true, 0])
	Rng.set_seed(9)
	_ticks(1)
	var after := Rng.rand()
	Rng.set_seed(9)
	Rng.rand()
	_eq(after, Rng.rand(), "the aura rolls once a frame")
	_ticks(0x4F)
	_eq(v.live("finisher_aura"), 1, "the aura at frame 0x50")
	_ticks(1)
	_eq(v.live("finisher_aura"), 0, "ends after 0x50")
	v.on_visual("finisher_aura", [1, true, 0])
	v.on_visual("finisher_aura", [1, false, -1])
	_eq(v.live("finisher_aura"), 0, "removed when the finisher goes")
	# The item particles: 40 frames.
	v.on_visual("item_particles", [1])
	_ticks(40)
	_eq(v.live("item_particles"), 1, "item particles at 40")
	_ticks(1)
	_eq(v.live("item_particles"), 0, "end at 41")
	# The buff disk and its trails: 67 frames, then both end.
	v.on_visual("buff_disk", [1])
	_eq([v.live("buff_disk"), v.live("buff_trails")], [1, 1], "the disk starts its trails")
	_ticks(0x43)
	_eq(v.live("buff_disk"), 1, "the disk at 67")
	_ticks(1)
	_eq([v.live("buff_disk"), v.live("buff_trails")], [0, 0], "the disk ends its trails")
	# The buff rings: 65 frames.
	v.on_visual("buff_rings", [2, 1])
	_eq(v.get_at("buff_rings", 0).color, Vector3i(235, 150, 220), "confusion's cure colour")
	_ticks(0x41)
	_eq(v.live("buff_rings"), 1, "the rings at 65")
	_ticks(1)
	_eq(v.live("buff_rings"), 0, "end at 66")
	_eq(v.buff_row in BattleVisuals.BUFF_ROWS, true, "the disk's CLUT row")


## BTL_deinitializeCombat: everything but confusion.
func _end() -> void:
	v.initialize()
	v.on_visual("status", [1, 1, true, 0])
	v.on_visual("status", [2, 2, true, 0])
	v.on_visual("finisher_aura", [1, true, 0])
	v.on_visual("buff_disk", [1])
	_ticks(2)
	v.on_visual("clear_effects", [])
	var left := 0
	for k in BattleVisuals.KINDS:
		left += v.live(k)
	_eq(left, 1, "only the confusion is left")
	_eq(v.live("confusion"), 1, "the confusion waits for its status' removal")
	_eq(v.buff_model, false, "the buff model object is removed")
	v.remove_all()


func _data() -> void:
	var fx: Dictionary = data.condition_fx_offset("dw1:agumon")
	_eq(fx.has("bone") and fx.has("offset"), true, "Agumon's condition point")
	var p := ctx.condition_fx_position(1)
	_eq(p != ctx.location(1), true, "the condition point is off the feet")
	_eq(data.aura_projectile_type("dw1:agumon").has("u"), true, "Agumon's aura sprite")


## DR_OFFSET at slot 0x20 (ISSUES.md I-31): the primitives at slot 0x20 and below are drawn from the
## screen centre, the others from the drawing offset (the projection centre).
func _screen_origin() -> void:
	ctx.offset = Vector2i(360, 192)
	_eq(ctx.slot_point(Vector2(-192, -152), 0x1E), Vector2(-392, -224), "a backdrop tile from the screen centre")
	_eq(ctx.slot_point(Vector2(10, 20), 0x20), Vector2(-190, -52), "slot 0x20 too")
	_eq(ctx.slot_point(Vector2(10, 20), 0x22), Vector2(10, 20), "slot 0x22 from the drawing offset")
	ctx.offset = Vector2i(160, 120)
	_eq(ctx.slot_point(Vector2(10, 20), 0x1E), Vector2(10, 20), "no shift with the offset at the centre")


class StubState extends Node:
	var state := {"partner": {"digimon": "dw1:agumon"}}


## The field's healing particles (I-21): 44 frames; per frame 20 size rolls, and 4 x 3 for the
## spiral until frame 38 (every variant rolls them: only the drawing depends on it).
func _healing() -> void:
	var partner := Node3D.new()
	root.add_child(partner)
	partner.global_position = Vector3(100, 0, -200)
	var state := StubState.new()
	var h := HealingParticles.new()
	h.partner = partner
	h.data = data
	h.game_state = state
	_eq(h.add(1), 0, "healing starts")
	_eq(h.add(1), -1, "one at a time")
	var agumon: Dictionary = data.digimon("dw1:agumon")
	_eq(h.off, Vector3i(100, -int(agumon["height"]) - 70, 200), "above the partner's head")
	Rng.set_seed(21)
	for i in 43:
		h.tick()
	var after := Rng.rand()
	Rng.set_seed(21)
	for i in 38 * 32 + 5 * 20:
		Rng.rand()
	_eq(after, Rng.rand(), "the healing's rolls")
	_eq(h.active(), true, "still on at frame 43")
	h.tick()
	_eq(h.active(), false, "ends at 44")
	_eq(h.entries1.all(func(e): return e["counter"] < 0), true, "the ring burnt out")
	h.free()
	state.free()
	partner.free()


## Each visual drawn once in a view: something shows, nothing errs.
func _drawing() -> void:
	# The camera-facing sprites face the viewport's camera.
	var camera := Camera3D.new()
	root.add_child(camera)
	camera.current = true
	var view: BattleVisualsView = load("res://scenes/battle/fx/battle_visuals_view.tscn").instantiate()
	root.add_child(view)
	view.visuals = v
	v.view = view
	v.initialize()
	for kind in ["confusion", "stun_spark", "finisher_aura", "item_particles", "buff_rings", "buff_disk",
			"aura_projectile", "poison_bubble", "stun"]:
		var i := v.add(kind, 1, [30] if kind == "stun" else [])
		_eq(i >= 0, true, "%s added" % kind)
		_ticks(2)
		view.draw_frame()
		_eq(view.shown() > 0, true, "%s draws" % kind)
		v.remove_all()
		v.initialize()
	v.view = null
	view.free()
	camera.free()
