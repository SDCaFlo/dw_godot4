class_name FieldDigimon
extends Node3D
## A Digimon entity on the field: what the partner and the NPCs share (specs/npc.md §3.1). The
## model of a Digimon type with its PSX animations; the animation's root motion moves it every
## Godot frame; entityCheckCollision probes its next step against the map and the other entities
## (the entity table, FieldEntities).

## COLLISION_GRACE_ROTATION (map.c:346): directions collisionGrace tries, by rotation / 512.
const GRACE := [
	[0x000, 0x400, 0xC00, 0x800], [0x400, 0x000, 0x800, 0xC00], [0x400, 0x800, 0x000, 0xC00],
	[0x800, 0x400, 0xC00, 0x000], [0x800, 0xC00, 0x400, 0x000], [0xC00, 0x800, 0x000, 0x400],
	[0xC00, 0x000, 0x800, 0x400], [0x000, 0xC00, 0x400, 0x800],
]
## entityCheckCollision results: -1 free, 0-9 the entity hit (0 the tamer), 10 the map.
const FREE := -1
const HIT_TAMER := 0
const HIT_MAP := 10

var field: FieldMap
## The entity table (ENTITY_TABLE); null: only the entities of _fallback_entities collide.
var entities: FieldEntities
## The Digimon type's key.
var digimon := ""
## DIGIMON_DATA.radius.
var radius := 100
## PSX rotation.vy (4096 per turn).
var direction := 0
var animator: PsxAnimator
## isOnScreen (entityIsOffScreen, 320 x 240), set by the entity's tick.
var on_screen := true
## isOnMap: 0 once a script unloaded it.
var on_map := true
## Ground distance the root motion moved during the last game frame: the step entityMoveForward
## probes with (the animation's forward momentum; 0 while idling).
var step := 0.0
## animFlag & 2: the root motion is held this frame (the step ran into the tamer).
var step_blocked := false

var _skeleton: Skeleton3D
var _model: Node3D


## Loads the model of a Digimon (key or id) through its files component.
func load_digimon(data: Node, ref: Variant) -> bool:
	var record: Dictionary = data.digimon(ref)
	var mmd: String = data.digimon_file(ref).get("mmd", "")
	if record.is_empty() or mmd == "":
		push_error("%s: no model for %s" % [name, ref])
		return false
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var model := Content.load_model(rel)
	if model == null:
		return false
	if _model != null:
		_model.queue_free()
	_model = model
	add_child(model)
	digimon = record.get("key", str(ref))
	radius = int(record["radius"])
	_skeleton = model.find_children("*", "Skeleton3D", true, false)[0]
	var player: AnimationPlayer = model.find_children("*", "AnimationPlayer", true, false)[0]
	var anim_root := player.get_node(player.root_node)
	player.root_motion_track = NodePath("%s:bone_0" % anim_root.get_path_to(_skeleton))
	animator = PsxAnimator.new(player, Content.load_json(rel))
	start_animation(0)
	return true


func _process(delta: float) -> void:
	if animator == null or field == null:
		return
	var motion := _skeleton.global_basis * animator.advance(delta)
	if step_blocked:
		return
	step += Vector2(motion.x, motion.z).length()
	_move(motion)


## startAnimation.
func start_animation(id: int) -> void:
	if animator != null:
		animator.play(id)


## entityLookAtLocation (map.c:3389): rotation.vy = _atan(dz, dx) = 0x800 + atan2(dx, dz).
func look_at_psx(target_x: int, target_z: int) -> void:
	var dx := target_x - int(position.x)
	var dz := target_z - int(-position.z)
	if dx == 0 and dz == 0:
		return
	_set_direction((0x800 + roundi(atan2(dx, dz) * 0x800 / PI)) & 0xFFF)


## The root motion (applyRootMomentum): nothing tests the map here (specs/partner.md §3); an
## axis-aligned rotation moves on its axis only.
func _move(motion: Vector3) -> void:
	var dx := motion.x
	var dz := -motion.z
	if direction == 0x400 or direction == 0xC00:
		dz = 0.0
	if direction == 0 or direction == 0x800:
		dx = 0.0
	position.x += dx
	position.z -= dz


# --- entityCheckCollision (map.c:3400) ------------------------------------------------------------

## entityCheckCollision as a probe: one step (entityMoveForward: the animation's forward motion of
## a game frame, `step`) along `rotation_vy` from here. FREE, the entity hit (0-9) or HIT_MAP; the
## position is not changed. `source` is skipped, as the C's first argument.
func probe(rotation_vy: int, source: Node3D = null) -> int:
	var angle := (rotation_vy - 0x800) * PI / 0x800
	# The C deltas are whole units: a step under 1 unit (idling) probes nothing.
	var dx := float(int(sin(angle) * step))
	var dz := float(int(cos(angle) * step))
	if rotation_vy == 0x400 or rotation_vy == 0xC00:
		dz = 0.0
	if rotation_vy == 0 or rotation_vy == 0x800:
		dx = 0.0
	var x := position.x
	var z := -position.z
	if _blocked(x + dx, z + dz, dx, dz):
		return HIT_MAP
	return hit_entity(x + dx, z + dz, dx, dz, source)


## The entity loop of entityCheckCollision: the first entity of the table the step to (x, z)
## touches, skipping itself, `source` and the invisible ones (isInvisible).
func hit_entity(x: float, z: float, dx: float, dz: float, source: Node3D = null) -> int:
	var table := entities.table() if entities != null else _fallback_entities()
	for i in table.size():
		var other: Node3D = table[i]
		if other == null or other == self or other == source or FieldEntities.is_invisible(other):
			continue
		if hits_square(other, x, z, dx, dz):
			return i
	return FREE


## The entity table without FieldEntities (tests): index -> entity.
func _fallback_entities() -> Array:
	return []


## entityCheckEntityCollision (map.c:3740), the non-tamer branch: after the step to (x, z), the
## box edge on the side it moves touches the other's square (isRectInRect).
func hits_square(other: Node3D, x: float, z: float, dx: float, dz: float) -> bool:
	var other_radius := radius_of(other)
	var ox := other.position.x
	var oz := -other.position.z
	var square := Rect2(ox - other_radius, oz - other_radius, other_radius * 2, other_radius * 2)
	var left := x - radius
	var right := x + radius
	var near := z - radius
	var far := z + radius
	if dx < 0 and touches(square, left, near, left, far):
		return true
	if dx > 0 and touches(square, right, near, right, far):
		return true
	if dz < 0 and touches(square, left, near, right, near):
		return true
	if dz > 0 and touches(square, left, far, right, far):
		return true
	return false


## DIGIMON_DATA[type].radius of another entity.
func radius_of(other: Node3D) -> int:
	var r = other.get("radius")
	return int(r) if r != null else 0


## isRectInRect: the segment (x1, z1)-(x2, z2) touches the square (edges included).
static func touches(square: Rect2, x1: float, z1: float, x2: float, z2: float) -> bool:
	return x2 >= square.position.x and x1 <= square.end.x and z2 >= square.position.y and z1 <= square.end.y


## collisionGrace (map.c:3466): try the 4 directions of COLLISION_GRACE_ROTATION and turn at
## most 0x50 per frame towards the first free one; with none free, turn 32. `source` is skipped
## by the probes (the partner passes the tamer, so bumping only him keeps the old rotation).
func collision_grace(source: Node3D = null) -> void:
	if probe(direction, source) == FREE:
		return
	var start := direction
	for candidate: int in GRACE[start / 512]:
		if probe(candidate, source) == FREE:
			var clockwise: int = start - candidate
			if clockwise < 0:
				clockwise = (clockwise + 0x1000) & 0xFFF
			var counter: int = candidate - start
			if counter < 0:
				counter = (counter + 0x1000) & 0xFFF
			if clockwise - counter < 0:
				_set_direction(start + 0xFB0 if clockwise >= 0x51 else start + 0x1000 - clockwise)
			else:
				_set_direction(start + 0x50 if counter >= 0x51 else start + counter)
			return
	_set_direction(start + 32)


func _blocked(x: float, z: float, dx: float, dz: float) -> bool:
	return field.blocked(int(x), int(z), int(signf(dx)), int(signf(dz)), radius)


func _set_direction(vy: int) -> void:
	direction = vy & 0xFFF
	rotation.y = Content.psx_yaw(direction)


## PSX rotation.vy, for the scripts (ENTITY_SET_ROTATION, tickLookAtEntity).
func set_direction(vy: int) -> void:
	_set_direction(vy)


## getModelTile.
func tile() -> Vector2i:
	return _tile(position)


static func _tile(p: Vector3) -> Vector2i:
	return FieldMap.model_tile(int(p.x), int(-p.z))


static func _psx(p: Vector3) -> Array:
	return [int(p.x), int(-p.y), int(-p.z)]
