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
	return true


## Drops the loaded map (doors, backgrounds, collision); the saved nodes are reset by the Field.
func unload() -> void:
	map_name = ""
	data = {}
	_collision = PackedByteArray()
	_backgrounds.clear()
	for child in _doors.get_children():
		child.queue_free()


func display_name() -> String:
	var entry: Dictionary = data.get("map_entry", {})
	return "%s (%s)" % [entry.get("display_name", ""), map_name]


## 0 day, 1 evening, 2 night (updateTimeOfDay); maps with one palette always show palette 0.
func set_time_of_day(value: int) -> void:
	time_of_day = value
	if _backgrounds.is_empty():
		background.texture = null
		return
	background.texture = _backgrounds[value if value < _backgrounds.size() else 0]


func palette_count() -> int:
	return _backgrounds.size()


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


func _load_doors() -> void:
	for child in _doors.get_children():
		child.queue_free()
	for door in data.get("doors", []):
		var rel := "maps/%s/doors/door_%02d.gltf" % [map_name, int(door["model"])]
		if not Content.exists(rel):
			continue
		var model := Content.load_model(rel)
		model.position = Content.psx_to_godot(door["position"])
		model.rotation.y = Content.psx_yaw(door["rotation"])
		_doors.add_child(model)


# --- Collision (map_collision.c) ------------------------------------------------------------

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


## Scrolls the background to keep `world` centred, clamped to the background edges
## (initializeDrawingOffsets), and shifts the 3D projection centre to match (DRAWING_OFFSET).
func follow(world: Vector3) -> void:
	var target := (background_pixel(world) - SCREEN / 2).round()
	scroll = target.clamp(Vector2.ZERO, (background_size - SCREEN).max(Vector2.ZERO))
	background.position = -scroll
	# Screen position of the projection centre, relative to the screen centre.
	var centre := background_size / 2 - scroll - SCREEN / 2
	var scale := NEAR / _projection
	camera.set_frustum(SCREEN.y * scale, Vector2(-centre.x, centre.y) * scale, NEAR, FAR)


static func _vec(v: Array) -> Vector3:
	return Vector3(v[0], v[1], v[2])
