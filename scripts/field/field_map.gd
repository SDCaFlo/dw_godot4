@tool
class_name FieldMap
extends Node3D
## A field map from the porter output (asset_porter/output/maps/<NAME>/, spec asset_porter/specs/map.md):
## pre-rendered background, the game's 3D camera over it, collision grid, warps and doors.
##
## World coordinates are PSX units converted to Godot axes (x, -y, -z); one collision cell is
## 100 units. The camera reproduces GsSetRefView2 + the drawing offset of the original
## (map.c: setupMap, initializeDrawingOffsets, updateDrawingOffsets).

const SCREEN := Vector2(320, 240)
const CELL := 100
const GRID := 100
const NEAR := 10.0
const FAR := 100000.0

var map_name := ""
var data: Dictionary
var background_size := Vector2.ZERO
## Background scroll in pixels (MAP_TILE_DATA.cameraX/Y).
var scroll := Vector2.ZERO
## PLAYER_OFFSET as a scroll: where the scroll would be without the background's edges
## (specs/camera.md §2.1).
var virtual_scroll := Vector2.ZERO
## CAMERA_FOLLOW_PLAYER: the tamer's walk scrolls the camera (§2.2); pans clear and set it.
var camera_follow := true
## CAMERA_REACHED_TARGET: -1 idle, 0 a slot's pan moving, 1 reached (§2.3).
var pan_reached := -1
## CAMERA_TARGET: the Godot point the next pan centres, taken on its first frame.
var pan_target := Vector3.ZERO
var time_of_day := 0

var _eye: Vector3
var _target: Vector3
var _right: Vector3
var _down: Vector3
var _forward: Vector3
var _projection := 1.0
var _collision: PackedByteArray
var _backgrounds: Array[Texture2D] = []

## Background sprite on a canvas layer behind the 3D view (the 3D is rendered into a
## transparent viewport over it, like the PSX drew polygons over the tiles).
@export var background: Sprite2D

@onready var camera: Camera3D = $Camera3D
@onready var _doors: Node3D = $Doors
## The overlay sprites (specs/map_objects.md), made on first use.
var overlays: MapOverlays:
	get:
		if _overlays == null:
			_overlays = MapOverlays.new()
			_overlays.name = "Overlays"
			_overlays.field = self
			add_child(_overlays)
		return _overlays
var _overlays: MapOverlays


func load_map(name: String) -> bool:
	var json = Content.load_json("maps/%s/map.json" % name)
	if json == null:
		return false
	map_name = name
	data = json
	var setup: Dictionary = data["setup"]
	background_size = Vector2(setup["width"], setup["height"]) * 128

	var cam: Dictionary = data["camera"]
	_eye = _vec(cam["eye"])
	_target = _vec(cam["target"])
	_right = _vec(cam["right"])
	_down = _vec(cam["down"])
	_forward = _vec(cam["forward"])
	_projection = cam["projection"]
	_setup_camera()

	_collision = PackedByteArray()
	for v in data["collision"]["values"]:
		_collision.append(int(v))

	_backgrounds.clear()
	var palette := 0
	while Content.exists("maps/%s/background_%d.png" % [name, palette]):
		_backgrounds.append(Content.load_texture("maps/%s/background_%d.png" % [name, palette]))
		palette += 1
	set_time_of_day(time_of_day)

	_load_doors()
	overlays.palette = time_of_day if time_of_day < _backgrounds.size() else 0
	overlays.load(data)
	_pan_speed = 0
	_pan_has_target = false
	return true


## Drops the loaded map (doors, backgrounds, collision); the saved nodes are reset by the Field.
func unload() -> void:
	map_name = ""
	data = {}
	_collision = PackedByteArray()
	_backgrounds.clear()
	for child in _doors.get_children():
		child.queue_free()
	_door_slots.clear()
	if _overlays != null:
		_overlays.clear()


func display_name() -> String:
	var entry: Dictionary = data.get("map_entry", {})
	return "%s (%s)" % [entry.get("display_name", ""), map_name]


## 0 day, 1 evening, 2 night (updateTimeOfDay); maps with one palette always show palette 0.
## Ends a running fade, as updateTimeOfDay removes the transition object (map.c:4307).
func set_time_of_day(value: int) -> void:
	time_of_day = value
	_end_transition()
	# The lights change with the palette (specs/lighting.md §2.1); maps without a time of day (flag
	# 0x40) keep the map's.
	if not data.is_empty():
		var no_time: bool = data.get("map_entry", {}).get("no_time_cycle", false)
		FieldLighting.apply(data["setup"].get("lights", []), FieldLighting.DAY if no_time else value)
	if _backgrounds.is_empty():
		background.texture = null
		return
	background.texture = _background(value)
	if _overlays != null:
		_overlays.set_palette(value if value < _backgrounds.size() else 0)


func palette_count() -> int:
	return _backgrounds.size()


# --- Day / evening / night fade (tickDaytimeTransition, map.c:4527; specs/clock.md §2.5) --------

## Frames into the running fade, -1 when none (DAYTIME_TRANSITION_FRAME).
var _transition_frame := -1
var _transition_target := 0
var _overlay: Sprite2D


## initializeDaytimeTransition's effect on the map: fade to `palette` over 25 game frames.
func start_daytime_transition(palette: int) -> void:
	if _backgrounds.size() <= 1:
		return
	_end_transition()
	_transition_target = palette
	_transition_frame = 0
	_overlay = Sprite2D.new()
	_overlay.centered = false
	_overlay.texture_filter = background.texture_filter
	_overlay.texture = _background(palette)
	background.add_child(_overlay)
	_overlay.modulate.a = Clock.transition_weight(0)


## One game frame of the fade: the target palette weighs 1/6, 1/5, 1/4, 1/3, 1/2 (5 frames
## each), then replaces the old one at frame 25. The original moves each 5-bit palette channel by
## that fraction; the port cross-fades the converted pictures.
func tick_daytime_transition() -> void:
	if _transition_frame < 0:
		return
	_transition_frame += 1
	if _transition_frame >= 25:
		set_time_of_day(_transition_target)
		return
	_overlay.modulate.a = Clock.transition_weight(_transition_frame)


func is_in_daytime_transition() -> bool:
	return _transition_frame >= 0


func _end_transition() -> void:
	_transition_frame = -1
	if _overlay != null:
		_overlay.queue_free()
		_overlay = null


func _background(palette: int) -> Texture2D:
	return _backgrounds[palette if palette < _backgrounds.size() else 0]


# --- Entities -------------------------------------------------------------------------------

## Spawn point i of the map entities (MapEntities.spawn*): Godot position and PSX rotation.vy.
func spawn(i: int) -> Dictionary:
	var s: Dictionary = data["spawns"][i]
	return {"position": Content.psx_to_godot([s["x"], s["y"], s["z"]]), "rotation": int(s["rotation"])}


## Warp for a trigger value 110..119 (tamer.c checkMapInteraction): {"map_name", "spawn"} or {}.
func warp_for_trigger(trigger: int) -> Dictionary:
	if trigger < 110 or trigger >= 120:
		return {}
	var w: Dictionary = data["warps"][trigger - 110]
	if w["map_name"] == null:
		return {}
	return w


## getMapRotation (tamer.c:595): _atan(eye.z - target.z, eye.x - target.x), the rotation.vy
## that faces the camera. _atan(dy, dx) (math.c:32) = 0x800 + atan2(dx, dy) in 4096 units.
func map_rotation() -> int:
	var dz := _eye.z - _target.z
	var dx := _eye.x - _target.x
	return (0x800 + roundi(atan2(dx, dz) * 0x800 / PI)) & 0xFFF


# --- Doors (loadDoors, renderDoors, tickRotateDoor; map_object.c:309-1040, specs/map_objects.md §2.6)

## MAP_3D_OBJ[6]: per slot {model, translation, rotation (PSX vx, vy), direction, nodes}, or null
## (model 255).
const DOOR_SLOTS := 6
## renderDoors draws model 10 twice: a double door, the copy mirrored 680 along z.
const DOUBLE_DOOR := 10
const DOUBLE_DOOR_OFFSET := 680
## The models whose swing ends back on `direction`.
const DOORS_SWING_BACK := [9, 0xA, 0xB, 0xC, 0xD, 0x10, 0x11, 0x12, 0x13]
var _door_slots: Array = []
## MAP_OBJ_ROTATE_TIMER: one for every door, reset by loadDoors and when a move is done.
var _rotate_timer := 0


func _load_doors() -> void:
	for child in _doors.get_children():
		child.queue_free()
	_door_slots.clear()
	_door_slots.resize(DOOR_SLOTS)
	var doors: Array = data.get("doors", [])
	for k in doors.size():
		var door: Dictionary = doors[k]
		var slot := int(door.get("slot", k))
		var rel := "maps/%s/doors/door_%02d.gltf" % [map_name, int(door["model"])]
		if slot < 0 or slot >= DOOR_SLOTS or not Content.exists(rel):
			continue
		var p: Array = door["position"]
		var d := {"model": int(door["model"]), "translation": Vector3i(int(p[0]), int(p[1]), int(p[2])),
				"rotation": Vector2i(0, int(door["rotation"])), "direction": int(door["rotation"]), "nodes": []}
		for c in (2 if d["model"] == DOUBLE_DOOR else 1):
			var model := Content.load_model(rel)
			_doors.add_child(model)
			d["nodes"].append(model)
		_door_slots[slot] = d
		_place_door(d)
	# loadDoors runs only on maps with doors: elsewhere the timer keeps its value.
	if not doors.is_empty():
		_rotate_timer = 0


## projectPosition for a door, and renderDoors' copy of model 10.
func _place_door(d: Dictionary) -> void:
	var t: Vector3i = d["translation"]
	var r: Vector2i = d["rotation"]
	for c in d["nodes"].size():
		var node: Node3D = d["nodes"][c]
		var pos := t
		var vy := r.y
		if c == 1:
			pos.z -= (1 if vy < 0 else -1) * DOUBLE_DOOR_OFFSET
			vy = -vy
		node.position = Content.psx_to_godot([pos.x, pos.y, pos.z])
		# RotMatrix with vz 0: the x tilt (model 0x1A), then the yaw.
		node.rotation = Vector3(r.x * TAU / 4096.0, Content.psx_yaw(vy), 0)


## Door slot k's state, for the tests: {model, translation, rotation, direction} or {}.
func door(k: int) -> Dictionary:
	if k < 0 or k >= _door_slots.size() or _door_slots[k] == null:
		return {}
	return _door_slots[k]


## tickRotateDoor(door, target) (map_object.c:932), slot type 12, by the door's model: the timer
## counts first; the frame it passes the limit moves nothing, resets it and is done (model 0x1A
## moves first). Any other model, or an empty slot, never ends.
func tick_rotate_door(k: int, target: int) -> bool:
	var d := door(k)
	var model: int = d.get("model", -1)
	var limit := 0
	match model:
		0, 9, 0xA, 0xB, 0xC, 0xD, 0xE, 0xF, 0x10, 0x11, 0x12, 0x13:
			limit = 32
		5, 0x1F, 0x20, 0x14, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1B, 0x1C, 0x1D, 0x1E:
			limit = 9
		0x1A:
			limit = 19
		_:
			return false
	_rotate_timer += 1
	if model == 0x1A:
		d["rotation"].x = clampi(d["rotation"].x - target * 110, -0x400, 0)
		_place_door(d)
	if _rotate_timer > limit:
		_rotate_timer = 0
		if model in DOORS_SWING_BACK:
			d["rotation"].y = d["direction"]
			_place_door(d)
		return true
	match model:
		0:
			d["rotation"].y -= target * 33
		5, 0x1F, 0x20:
			d["translation"].y -= target * 200
		0x15, 0x16, 0x18, 0x1B, 0x1D:
			_slide_door(d, 30)
		0x14, 0x17, 0x19, 0x1C, 0x1E:
			_slide_door(d, -30)
		0x1A:
			return false
		_:
			d["rotation"].y += target * 33
	_place_door(d)
	return false


## The sliding gates move along x, or along z on map 0x81 (the C tests CURRENT_SCREEN).
func _slide_door(d: Dictionary, amount: int) -> void:
	if int(data.get("map_entry", {}).get("id", -1)) == 0x81:
		d["translation"].z += amount
	else:
		d["translation"].x += amount


# --- Collision (map_collision.c) ------------------------------------------------------------

## setImpassableRect (map_collision.c:190), SET_RECT_IMPASSABLE: cells [x, x + w) x [z, z + h)
## blocked (0x80) until the map is loaded again.
func set_impassable_rect(x: int, z: int, w: int, h: int) -> void:
	for tz in range(z, z + h):
		for tx in range(x, x + w):
			var i := tx + tz * GRID
			if i >= 0 and i < _collision.size():
				_collision[i] = 0x80

func _cell(tx: int, tz: int) -> int:
	if tx < 0 or tz < 0 or tx >= GRID or tz >= GRID:
		return 0x80
	return _collision[tx + tz * GRID]


## getTileTrigger: 0 walkable, -1 blocked, otherwise the trigger value of the cell under pos.
func tile_trigger(pos: Vector3) -> int:
	var x := int(pos.x)
	var z := int(-pos.z)
	var tx := x / CELL + 50 - (1 if x < 0 else 0)
	var tz := 50 - z / CELL - (1 if z > 0 else 0)
	var value := _cell(tx, tz)
	if value == 0:
		return 0
	if value == 0x80:
		return -1
	return value if value < 128 else value - 256


## checkMapCollision (map.c:3719) for a move by (dx, dz) in PSX axes, entity at PSX (x, z).
func blocked(x: int, z: int, dx: int, dz: int, radius: int) -> bool:
	if dz > 0 and _blocked_row(x, z + radius, radius):
		return true
	if dz < 0 and _blocked_row(x, z - radius, radius):
		return true
	if dx < 0 and _blocked_column(x - radius, z, radius):
		return true
	if dx > 0 and _blocked_column(x + radius, z, radius):
		return true
	return false


# checkMapCollisionX: cells from x - r/2 to x + r/2 on the row at edge_z.
func _blocked_row(x: int, edge_z: int, radius: int) -> bool:
	var row := _tile_z(edge_z)
	for tx in range(_tile_x(x - radius / 2), _tile_x(x + radius / 2) + 1):
		if _cell(tx, row) & 0x80:
			return true
	return false


# checkMapCollisionZ: cells from z + r/2 to z - r/2 on the column at edge_x.
func _blocked_column(edge_x: int, z: int, radius: int) -> bool:
	var column := _tile_x(edge_x)
	for tz in range(_tile_z(z + radius / 2), _tile_z(z - radius / 2) + 1):
		if _cell(column, tz) & 0x80:
			return true
	return false


## getModelTile (map_collision.c:148): the collision tile of a PSX position.
static func model_tile(psx_x: int, psx_z: int) -> Vector2i:
	return Vector2i(psx_x / CELL + 50 - (1 if psx_x < 0 else 0), 50 - psx_z / CELL - (1 if psx_z > 0 else 0))


## Centre of a tile in PSX units (entityLookAtTile, utils2.c:344).
static func tile_centre(tile: Vector2i) -> Vector2i:
	return Vector2i((tile.x - 50) * CELL + 50, (50 - tile.y) * CELL - 50)


## isLinearPathBlocked (map.c:3156): walks the grid from one tile to another (end included, start
## excluded) and reports a blocking cell (value & 0x80).
func is_linear_path_blocked(from: Vector2i, to: Vector2i) -> bool:
	var x1 := clampi(from.x, 0, GRID - 1)
	var y1 := clampi(from.y, 0, GRID - 1)
	var x2 := clampi(to.x, 0, GRID - 1)
	var y2 := clampi(to.y, 0, GRID - 1)
	if x1 == x2 and y1 == y2:
		return false
	var dx := x2 - x1
	var dy := y2 - y1
	var x := x1
	var y := y1
	var major_x := absi(dx) >= absi(dy)
	var dist := absi(dx) if major_x else absi(dy)
	var minor := dy if major_x else dx
	var quot := minor / dist
	var rem := minor % dist
	var minor_sign := -1 if rem < 0 else 1
	rem = absi(rem)
	var acc := dist
	for i in dist:
		var step := 0
		if rem != 0:
			acc -= rem
			if acc <= 0:
				step = minor_sign
				acc += dist
		else:
			step = quot
		if major_x:
			y += step
			x += 1 if dx > 0 else -1
		else:
			x += step
			y += 1 if dy > 0 else -1
		if _cell(x, y) & 0x80:
			return true
	return false


## isFiveTileWidePathBlocked (map.c:3133): 5 parallel lines, +-2 tiles across the main axis; any
## blocked line counts.
func is_five_tile_wide_path_blocked(from: Vector2i, to: Vector2i) -> bool:
	var across := Vector2i(0, 1) if absi(to.x - from.x) >= absi(to.y - from.y) else Vector2i(1, 0)
	for i in range(-2, 3):
		if is_linear_path_blocked(from + across * i, to + across * i):
			return true
	return false


## isTileOffScreen (map.c:3649): the tile centre projected more than 200 / 160 px from the
## screen centre.
func is_tile_off_screen(tile: Vector2i) -> bool:
	var centre := tile_centre(tile)
	var screen := background_pixel(Content.psx_to_godot([centre.x, 0, centre.y])) - scroll - SCREEN / 2
	return absf(screen.x) > 200 or absf(screen.y) > 160


## A Godot position is on the visible screen (the partner's isOnScreen).
func is_on_screen(world: Vector3) -> bool:
	var screen := background_pixel(world) - scroll
	return screen.x >= 0 and screen.y >= 0 and screen.x < SCREEN.x and screen.y < SCREEN.y


func _tile_x(x: int) -> int:
	return x / CELL + 50 - (1 if x < 0 else 0)


func _tile_z(z: int) -> int:
	return 49 - z / CELL + (1 if z < 0 else 0)


# --- Camera ----------------------------------------------------------------------------------

func _setup_camera() -> void:
	var up := -Content.psx_to_godot([_down.x, _down.y, _down.z])
	var back := -Content.psx_to_godot([_forward.x, _forward.y, _forward.z])
	var right := Content.psx_to_godot([_right.x, _right.y, _right.z])
	camera.transform = Transform3D(Basis(right, up, back), Content.psx_to_godot([_eye.x, _eye.y, _eye.z]))
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	follow(Content.psx_to_godot(data["setup"]["reference"]) * 2.0)


## Background pixel where a Godot world point is drawn (specs/map.md, "Camera").
func background_pixel(world: Vector3) -> Vector2:
	var v := Vector3(world.x, -world.y, -world.z) - _eye
	var depth := v.dot(_forward)
	return background_size / 2 + _projection * Vector2(v.dot(_right), v.dot(_down)) / depth


## The 3D view's resolution as a multiple of the PSX's 320 x 240 (ISSUES.md I-3, set by the field):
## the 3D renders at 320 x 240 x this and is shown at the PSX size, like an emulator's upscaling.
static var render_scale := 1


## Camera3D.unproject_position in PSX screen pixels (0-320, 0-240), whatever the render scale.
static func unproject(cam: Camera3D, world: Vector3) -> Vector2:
	return cam.unproject_position(world) / render_scale


## The view depth of a Godot point: along the camera's forward axis, in PSX units.
func view_depth(world: Vector3) -> float:
	return (Vector3(world.x, -world.y, -world.z) - _eye).dot(_forward)


## The Godot point at a view depth that projects onto a background pixel (background_pixel's
## inverse).
func world_at_pixel(pixel: Vector2, depth: float) -> Vector3:
	var p := pixel - background_size / 2
	var psx := _eye + _forward * depth + (_right * p.x + _down * p.y) * depth / _projection
	return Vector3(psx.x, -psx.y, -psx.z)


## The projection distance H: pixels per unit at depth 1.
func projection() -> float:
	return _projection


## initializeDrawingOffsets: the scroll that centres `world` becomes the virtual scroll, and the
## scroll is that clamped to the background edges.
func follow(world: Vector3) -> void:
	virtual_scroll = (background_pixel(world) - SCREEN / 2).round()
	scroll = virtual_scroll
	_clamp_scroll()
	_apply_scroll()


## The background-pixel motion of a move from one Godot point to another, as the C takes it: the
## difference of the two projections, each rounded to whole pixels (gte_stsxy). Over a walk the
## steps add up to the rounded end minus the rounded start.
func screen_motion(from: Vector3, to: Vector3) -> Vector2:
	return background_pixel(to).round() - background_pixel(from).round()


## The scroll moves by `motion`, then updateDrawingOffsets (map.c:4616): the clamp, the virtual
## scroll takes the whole motion, and on an axis the clamp left free, the step is undone when the
## held direction (`held`: Pad bits, POLLED_INPUT) points away from where the virtual scroll is.
## The follow (tickCameraFollowPlayer) and moveCameraByDiff (specs/camera.md §2.2, §2.4).
func scroll_by(motion: Vector2, held: int) -> void:
	scroll += motion
	var free := _clamp_scroll()
	virtual_scroll += motion
	if free[0]:
		if held & Pad.LEFT:
			if virtual_scroll.x > scroll.x:
				scroll.x -= motion.x
		elif held & Pad.RIGHT:
			if virtual_scroll.x < scroll.x:
				scroll.x -= motion.x
	if free[1]:
		if held & Pad.UP:
			if virtual_scroll.y > scroll.y:
				scroll.y -= motion.y
		elif held & Pad.DOWN:
			if virtual_scroll.y < scroll.y:
				scroll.y -= motion.y
	_apply_scroll()


## cameraIsAtEdge (map.c:4818): the scroll clamped to the background; per axis true when it was
## free (the C's atEdge 1).
func _clamp_scroll() -> Array:
	var limit := (background_size - SCREEN).max(Vector2.ZERO)
	var free := [true, true]
	for axis in 2:
		if scroll[axis] < 0:
			scroll[axis] = 0
			free[axis] = false
		elif scroll[axis] > limit[axis]:
			scroll[axis] = limit[axis]
			free[axis] = false
	return free


## The background position, and the 3D projection centre shifted to match (DRAWING_OFFSET, always
## background / 2 - scroll).
func _apply_scroll() -> void:
	background.position = -scroll
	# Screen position of the projection centre, relative to the screen centre.
	var centre := background_size / 2 - scroll - SCREEN / 2
	var scale := NEAR / _projection
	camera.set_frustum(SCREEN.y * scale, Vector2(-centre.x, centre.y) * scale, NEAR, FAR)


# --- Pans (createCameraMovement, checkCameraMovement, tickCameraMovement; specs/camera.md §2.3) ---

## The running pan's speed (its object's instance id: about that many frames); 0 none.
var _pan_speed := 0
## CAMERA_HAS_TARGET, and what its first frame takes: the scroll moves `_pan_total` (CAMERA_DATA -
## CAMERA_MOVE_DIFF) to `_pan_final` (CAMERA_MOVE_FINAL); `_pan_extra` frames left with 1 more
## pixel (CAMERA_MOVE_DELTA).
var _pan_has_target := false
var _pan_total := Vector2i.ZERO
var _pan_final := Vector2.ZERO
var _pan_extra := Vector2i.ZERO


## createCameraMovement (map.c:4844), a scene's pan: centre `target` (Godot) over `speed` frames.
## CAMERA_REACHED_TARGET -1: nothing waits for it.
func start_pan(target: Vector3, speed: int) -> void:
	pan_target = target
	_pan_speed = speed
	pan_reached = -1


## checkCameraMovement (map.c:5080), the camera slot's tick: the first call starts the pan to
## `pan_target`; true once, on the call after the pan ended.
func check_pan(speed: int) -> bool:
	if pan_reached == -1:
		pan_reached = 0
		_pan_speed = speed
		return false
	if pan_reached == 1:
		pan_reached = -1
		return true
	return false


func is_panning() -> bool:
	return _pan_speed != 0


## tickCameraMovement (map.c:4855), once per game frame while a pan runs. A pan started while one
## runs only changes its speed (the C would run two objects on the same globals).
func tick_pan() -> void:
	if _pan_speed == 0:
		return
	var speed := _pan_speed
	if not _pan_has_target:
		# The point's centring scroll: the follow continues from there (PLAYER_OFFSET), the pan
		# ends on it clamped.
		virtual_scroll = (background_pixel(pan_target) - SCREEN / 2).round()
		var limit := (background_size - SCREEN).max(Vector2.ZERO)
		_pan_final = virtual_scroll.clamp(Vector2.ZERO, limit)
		_pan_total = Vector2i(_pan_final - scroll)
		_pan_extra = Vector2i(absi(_pan_total.x % speed), absi(_pan_total.y % speed))
		camera_follow = false
		_pan_has_target = true
	for axis in 2:
		var total := _pan_total[axis]
		# C division (toward 0), then 1 more pixel on the first |total % speed| + 1 frames.
		scroll[axis] += total / speed
		if _pan_extra[axis] >= 0:
			scroll[axis] += 1 if total > 0 else -1
			_pan_extra[axis] -= 1
	var free := _clamp_scroll()
	var done := [true, true]
	for axis in 2:
		if not free[axis]:
			continue
		var total := _pan_total[axis]
		if total > 0:
			if scroll[axis] > _pan_final[axis]:
				scroll[axis] = _pan_final[axis]
		elif scroll[axis] < _pan_final[axis] or total == 0:
			scroll[axis] = _pan_final[axis]
		done[axis] = scroll[axis] == _pan_final[axis]
	_apply_scroll()
	if done[0] and done[1]:
		_pan_has_target = false
		camera_follow = true
		if pan_reached == 0:
			pan_reached = 1
		_pan_speed = 0


static func _vec(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])
