class_name BattleVisuals
extends RefCounted
## The battle's visuals outside the technique scripts (specs/battle_effects.md §4, §7.6), as
## battle_effect.c keeps them: per kind a pool of the C's size, each live one an object in the
## world's object list (ticked in slot order, a new one taking the first free slot), and the
## tables the battle's loading rolls (loadBattleData, btl.c:427: the item particles' velocities, the
## buff trails, the buff rings' and the finisher aura's sparks).
##
## The battle's visual events start and stop them (on_visual): the statuses (BTL_addStatusEffectVisual),
## the finisher aura, the aura projectiles (which hit: technique 0x79), the item particles, the buff
## disk and rings; the battle's end removes them (BTL_deinitializeCombat). Each visual is a scene
## (BattleVisual) under the view (BattleVisualsView) when there is one.

## kind: [C object id, pool size].
const KINDS := {
	"poison": [0x808, 4], "poison_bubble": [0x805, 12], "confusion": [0x806, 4], "stun": [0x80F, 5],
	"stun_spark": [0x810, 0x19], "finisher_aura": [0x80D, 2], "aura_projectile": [0x179, 8],
	"item_particles": [0x818, 4], "buff_disk": [0x815, 1], "buff_trails": [0x816, 1], "buff_rings": [0x814, 1],
}
const SCENE := "res://scenes/battle/fx/%s.tscn"
## The world's object slots these take (WORLD_OBJECTS is shared with the field's objects; only the
## order among the visuals matters here).
const OBJECTS := 96
## BTL_addStatusEffectVisual's kinds (1 poison, 2 confusion, 3 stun).
const STATUS_KINDS := ["", "poison", "confusion", "stun"]
## The finisher wind-up's aura (battle_main.c:1290, :2447).
const FINISHER_AURA_FRAMES := 0x50
## initializeBuffModel: the disk's two CLUT rows (BUFF_MODEL_MORPH_VALUE 0x7acc, 0x7b0c).
const BUFF_ROWS := [491, 492]
const ITEM_PARTICLES := 0x14
const BUFF_TRAILS := 8
const RING_SPARKS := 0x10
const AURA_SPARKS := 10

var ctx: BattleEffectContext
## The effect engine, for the aura projectiles' hits (addAttackObject).
var host: EffectHost
## Where the visuals' scenes go (null headless).
var view: BattleVisualsView
## A mod's scene for a kind (kind -> path); the others are SCENE % kind.
var scenes := {}

## kind -> Array of BattleVisual or null.
var pools := {}
## The object list: BattleVisual or null.
var objects: Array = []
## fighter->statusFxId per entity (the pool slot of its status visual).
var status_ids := {}
## BTL_FINISHER_AURA_ID.
var finisher_id := -1
## The buff model object (0x501, initializeBuffModelObject): BUFF_MODEL_FRAME, and the disk's CLUT
## row it set this frame.
var buff_model := false
var buff_frame := 0
var buff_row: int = BUFF_ROWS[0]

## The rolled tables.
var item_velocities: Array[Vector3i] = []
var item_drag: Array[Vector2i] = []
var trail_a: Array[Vector2i] = []
var trail_b: Array[Vector2i] = []
var ring_sparks: Array[Vector3i] = []
var aura_sparks: Array[Vector3i] = []

var _dead: Array = []


func _init(context: BattleEffectContext = null) -> void:
	ctx = context
	_reset_pools()


func _reset_pools() -> void:
	for k in KINDS:
		var pool := []
		pool.resize(KINDS[k][1])
		pools[k] = pool
	objects.resize(OBJECTS)
	objects.fill(null)
	status_ids.clear()
	finisher_id = -1


# --- the battle's loading (btl.c:427-453) --------------------------------------------------------

## BTL_initializeBattleItemParticles, BTL_initializeUnk3 (buff trails), BTL_initializeUnk2 (buff
## rings), BTL_initializeFinisherAuraModel, then the poison, confusion and stun pools and the buff
## model object, with the C's rolls in its order.
func initialize() -> void:
	remove_all()
	_reset_pools()
	_roll_item_velocities()
	_roll_buff_trails()
	ring_sparks = _roll_ring_sparks()
	aura_sparks = _roll_aura_sparks()
	buff_model = true
	buff_frame = 0


## BTL_initializeItemParticleVelocities (battle_effect.c:6193).
func _roll_item_velocities() -> void:
	item_velocities.clear()
	item_drag.clear()
	for i in ITEM_PARTICLES:
		var rot := Vector3i((Rng.rand() % 1000) - 0x1F4, 0, 0)
		rot.y = Rng.rand() % 0x1000
		var out := PsxMath.s16_vec(PsxMath.apply_matrix_sv(PsxMath.rot_matrix_zyx(rot), Vector3i(0, -0x230, 0)))
		item_velocities.append(out)
		var r := PsxMath.lerp_int(0x3C, 0x1E, 0, 0x226, absi(rot.x))
		item_drag.append(Vector2i(PsxMath.div(out.x, r), PsxMath.div(out.z, r)))


## BTL_initializeBuffTrails (battle_effect.c:6340): eight directions in a shuffled order.
func _roll_buff_trails() -> void:
	trail_a.clear()
	trail_b.clear()
	var pool := [0, 1, 2, 3, 4, 5, 6, 7]
	for i in BUFF_TRAILS:
		var r := Rng.rand() % (BUFF_TRAILS - i)
		var k: int = pool[r]
		pool.remove_at(r)
		var s := ((Rng.rand() % 0x14) + 0x50) * 200 / 100
		var rot := Vector3i(0, (k * 0x1000 / 8) + (Rng.rand() % 0x200), 0)
		var m := PsxMath.rot_matrix_zyx(rot)
		var a := PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(0x1E, 0, s)))
		var b := PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(-0x1E, 0, s)))
		trail_a.append(Vector2i(a.x, a.z))
		trail_b.append(Vector2i(b.x, b.z))


## BTL_initializeUnk2 (battle_effect.c:6676): 16 pairs of spark points, a vector turned by a
## random rotation (RotMatrixZYX) and its x-mirror.
func _roll_ring_sparks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in RING_SPARKS:
		var v := Vector3i((Rng.rand() % 0x32) + 0x32, 0, 0)
		v.z = (Rng.rand() % 0x190) + 0x320
		var rot := Vector3i(PsxMath.s16(Rng.rand()), 0, 0)
		rot.y = PsxMath.s16(Rng.rand())
		rot.z = PsxMath.s16(Rng.rand())
		_spark_pair(out, v, rot)
	return out


## BTL_initializeFinisherAuraModel (battle_effect.c:5997): 10 pairs, tilted up to half a turn.
func _roll_aura_sparks() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for i in AURA_SPARKS:
		var v := Vector3i((Rng.rand() % 30) + 30, 0, 0)
		v.z = (Rng.rand() % 0x190) + 0x320
		var rot := Vector3i(PsxMath.s16(Rng.rand() % 0x1000 * 180 / 360), 0, 0)
		rot.y = PsxMath.s16(Rng.rand())
		_spark_pair(out, v, rot)
	return out


static func _spark_pair(out: Array[Vector3i], v: Vector3i, rot: Vector3i) -> void:
	var m := PsxMath.rot_matrix_zyx(rot)
	out.append(PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, v)))
	out.append(PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(-v.x, v.y, v.z))))


# --- the pools and the object list ----------------------------------------------------------------

## The C's add function of a kind: the first free slot of its pool, its scene started with `args`
## and put in the object list. The slot, or -1 when the pool is full.
func add(kind: String, entity: int, args: Array = []) -> int:
	if not pools.has(kind):
		return -1
	var pool: Array = pools[kind]
	var i := pool.find(null)
	if i < 0:
		return -1
	var path: String = scenes.get(kind, SCENE % kind)
	var visual := load(path).instantiate() as BattleVisual
	if visual == null:
		return -1
	visual.visuals = self
	visual.ctx = ctx
	visual.kind = kind
	visual.index = i
	visual.entity = entity
	pool[i] = visual
	visual.start(args)
	var slot := objects.find(null)
	if slot >= 0:
		objects[slot] = visual
	if view != null:
		view.add_child(visual)
	return i


## removeObject: the visual's slot and object are freed (the node at the end of the frame's work).
func remove(visual: BattleVisual) -> void:
	if visual == null or not pools.has(visual.kind):
		return
	var pool: Array = pools[visual.kind]
	if visual.index >= 0 and visual.index < pool.size() and pool[visual.index] == visual:
		pool[visual.index] = null
	var slot := objects.find(visual)
	if slot >= 0:
		objects[slot] = null
	if not visual in _dead:
		_dead.append(visual)


## The C's remove(i, entity): only when slot i holds that entity's.
func remove_at(kind: String, i: int, entity: int) -> void:
	var visual := get_at(kind, i)
	if visual != null and visual.entity == entity:
		remove(visual)


func get_at(kind: String, i: int) -> BattleVisual:
	var pool: Array = pools.get(kind, [])
	return pool[i] if i >= 0 and i < pool.size() else null


func remove_kind(kind: String) -> void:
	for visual in pools.get(kind, []):
		if visual != null:
			remove(visual)


## How many of a kind are live.
func live(kind: String) -> int:
	var pool: Array = pools.get(kind, [])
	return pool.size() - pool.count(null)


## Every visual, its slots free.
func remove_all() -> void:
	for k in KINDS:
		remove_kind(k)
	buff_model = false
	_flush()


func _flush() -> void:
	for visual in _dead:
		if is_instance_valid(visual):
			if visual.is_inside_tree():
				visual.queue_free()
			else:
				visual.free()
	_dead.clear()


# --- each frame ------------------------------------------------------------------------------------

## The objects' ticks in slot order (a visual added during the loop into a later slot ticks this
## frame too, as in the C's loop); the buff model's morph.
func tick() -> void:
	for i in objects.size():
		var visual: BattleVisual = objects[i]
		if visual != null:
			visual.tick()
	if buff_model:
		buff_row = BUFF_ROWS[buff_frame & 1]
		buff_frame += 1
	_flush()


## The objects' renders in slot order.
func draw(view_node: BattleVisualsView) -> void:
	for visual in objects:
		if visual != null and is_instance_valid(visual):
			visual.draw(view_node)


# --- the battle's events ------------------------------------------------------------------------

func on_visual(event: String, args: Array) -> void:
	match event:
		"status":
			_status(int(args[0]), int(args[1]), bool(args[2]), int(args[3]) if args.size() > 3 else 0)
		"finisher_aura":
			if bool(args[1]):
				finisher_id = add("finisher_aura", int(args[0]), [FINISHER_AURA_FRAMES])
			else:
				var visual := get_at("finisher_aura", finisher_id)
				if visual != null:
					remove(visual)
		"aura_projectile":
			add("aura_projectile", int(args[0]))
		"item_particles":
			add("item_particles", int(args[0]))
		"buff_disk":
			# BTL_addBuffDiskEffect, then BTL_addBuffTrails in the same slot.
			if add("buff_disk", int(args[0])) >= 0:
				add("buff_trails", int(args[0]))
		"buff_rings":
			add("buff_rings", int(args[1]), [int(args[0])])
		"clear_effects":
			_deinitialize()
	_flush()


## BTL_addStatusEffectVisual / BTL_removeStatusEffectVisual: the fighter's one status visual.
func _status(entity: int, status: int, on: bool, stun_timer: int) -> void:
	if status <= 0 or status >= STATUS_KINDS.size():
		return
	var kind: String = STATUS_KINDS[status]
	if on:
		if not status_ids.has(entity):
			var i := add(kind, entity, [stun_timer])
			if i >= 0:
				status_ids[entity] = i
		return
	if status_ids.has(entity):
		remove_at(kind, int(status_ids[entity]), entity)
		status_ids.erase(entity)


## BTL_deinitializeCombat (battle_main.c:823-831): every visual but confusion (the statuses' own
## removal takes it), and the buff model object.
func _deinitialize() -> void:
	for k in ["finisher_aura", "poison", "poison_bubble", "stun", "stun_spark", "buff_rings", "buff_disk",
			"buff_trails", "item_particles", "aura_projectile"]:
		remove_kind(k)
	buff_model = false


# --- the aura projectiles' hits -----------------------------------------------------------------

## addAttackObject(victim, 1, pos, 0x179, 0, caster).
func add_attack_object(victim: int, position: Vector3i, effect: int, caster: int) -> void:
	if host != null:
		host.add_attack_object(victim, position, effect, 0, caster)
