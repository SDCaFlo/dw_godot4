@tool
class_name MapOverlays
extends Node3D
## The map's overlay sprites (specs/map_objects.md): animated 2D details drawn over the background
## and sorted against the 3D models (loadMapObjects, calcMapObjectOrder, renderMapOverlays,
## buildMapOverlayPrim, buildSnowflakePrim; overworld.c:311-776), and what scripts change on them
## (setMapObjectsFlag, resetMapObjectAnimation, tickMoveObjectTo, spawnSpriteAt*,
## updateMapLightState).
##
## Each instance is a quad facing the camera at the view depth of its sprite's 3D point, its
## corners on the background pixels it covers: the camera never moves (the scroll shifts the
## frustum), so the quad stays on the background as it scrolls, and the depth buffer sorts it
## against the models as the C's ordering table does.

## MAP_TILE_DATA.objects[188].
const INSTANCES := 188
const FRAMES := 8
## animSprites values: -1 ends the frame list, -2 is a blank frame.
const END := -1
const BLANK := -2
## setMapObjectsFlag's flags: 1 hidden; bit 0x80 snow; bit 0x10 cleared by loadMapObjectPosition.
const HIDDEN := 1
const SNOW := 0x80
## calcMapObjectOrder: ordering-table entries (view depth / 16, `otz >> 2` of gte_stszotz's SZ / 4).
const OT_UNIT := 16.0
const ORDER_MIN := 0x23
const ORDER_MAX := 0xFF6
## someY 10000: behind every model, just over the background (0xFFF).
const ORDER_BACK := 0xFFE
const BACK_Y := 10000
const ORDER_SNOW := 0x1E
## buildMapOverlayPrim: transparency 4 is opaque; others blend with mode `transparency & 3`.
const OPAQUE := 4
## updateMapLightState: the hours the light entries test (7 <= HOUR < 0x13).
const LIGHT_FROM := 7
const LIGHT_TO := 0x13

## The FieldMap: the projection between world points and background pixels.
var field: FieldMap
## The map's palette (FieldMap.time_of_day), for the sprites on the active TFS palette (clut -1).
var palette := 0
## MAP_LAYER_ENABLED: nothing draws or animates while 0.
var layer_enabled := true

var _sprites: Array = []
## Per instance: {sprites, times, x, y, flag, timer, frame, order, node}.
var _instances: Array = []
## MAP_OBJECT_MOVE_TO_DATA[10], MOVE_OBJECT_DELTA_X/Y[10].
var _move_started: Array = []
var _move_delta: Array = []
## CURRENT_FRAME for the snow's drift (every third frame).
var _frame_count := 0
## Shaders per blend mode, materials per (sprite, palette).
var _shaders := {}
var _materials := {}


func _init() -> void:
	_move_started.resize(10)
	_move_started.fill(false)
	_move_delta.resize(10)
	_move_delta.fill(Vector2i.ZERO)


## clearMapObjects + loadMapObjects + calcMapObjectOrder for a map's map.json; `snow` is the map
## record's snow component ({} none: specs/map_objects.md §2.5).
func load(data: Dictionary, snow: Dictionary = {}) -> void:
	clear()
	_sprites = data.get("objects", [])
	var map_name := str(data.get("map_entry", {}).get("filename", ""))
	var source: Array = data.get("object_instances", [])
	var snow_count := int(snow.get("instances", 0))
	var random_x_from := int(snow.get("random_x_from", snow_count))
	for k in mini(source.size(), INSTANCES):
		var s: Dictionary = source[k]
		var inst := {
			"sprites": (s["sprites"] as Array).map(func(v): return int(v)),
			"times": (s["times"] as Array).map(func(v): return int(v) & 0xFF),
			"x": int(s["x"]), "y": int(s["y"]), "flag": _s8(int(s["flag"])),
			"timer": 0, "frame": -1, "order": 0, "node": null,
		}
		if k < snow_count:
			if k >= random_x_from:
				inst["x"] = randi_range(0, 319)
			inst["y"] = randi_range(0, 239)
			inst["flag"] = _s8(inst["flag"] | SNOW)
		_instances.append(inst)
	for k in _instances.size():
		_order(_instances[k], k, map_name)


## Drops the map's instances.
func clear() -> void:
	for inst in _instances:
		if inst["node"] != null:
			inst["node"].queue_free()
	_instances.clear()
	# a new array, not clear(): _sprites is the map data's own `objects` list (ISSUES.md I-8)
	_sprites = []
	_materials.clear()
	for k in 10:
		_move_started[k] = false


func instance_count() -> int:
	return _instances.size()


## An instance's state, for the tests and the debug views: {sprites, times, x, y, flag, timer,
## frame, order}.
func instance(k: int) -> Dictionary:
	return _instances[k] if k >= 0 and k < _instances.size() else {}


## Whether instance k is drawn this frame (renderMapOverlays' test, without the off-screen cull).
func is_drawn(k: int) -> bool:
	var inst := instance(k)
	if inst.is_empty() or inst["frame"] < 0:
		return false
	var sprite: int = inst["sprites"][inst["frame"]]
	return sprite >= 0 and inst["flag"] != HIDDEN


# --- calcMapObjectOrder (overworld.c:420) --------------------------------------------------------

func _order(inst: Dictionary, k: int, map_name: String) -> void:
	var sprite := _first_sprite(inst, true)
	var order := ORDER_MAX
	if sprite >= 0 and sprite < _sprites.size() and field != null:
		var p: Array = _sprites[sprite]["pos3d"]
		order = clampi(int(field.view_depth(Content.psx_to_godot(p)) / OT_UNIT), ORDER_MIN, ORDER_MAX)
		if int(p[1]) == BACK_Y:
			order = ORDER_BACK
	if inst["flag"] & SNOW:
		order = ORDER_SNOW
	inst["order"] = order
	inst["frame"] = 0
	var node := MeshInstance3D.new()
	node.name = "Overlay%d" % k
	node.mesh = QuadMesh.new()
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# On a tie the C draws the lower index on top (AddPrim puts it at the head of its list).
	node.sorting_offset = (INSTANCES - k) * 0.01
	node.visible = false
	add_child(node)
	inst["node"] = node
	_show(inst)


## The instance's first frame that isn't the end or a blank (calcMapObjectOrder skips both;
## spawnSpriteAtLocation only blanks: `skip_end` false).
func _first_sprite(inst: Dictionary, skip_end: bool) -> int:
	for v in inst["sprites"]:
		if v == BLANK or (skip_end and v == END):
			continue
		return v
	return END


# --- renderMapOverlays (overworld.c:468), every game frame ---------------------------------------

func tick() -> void:
	_frame_count += 1
	if not layer_enabled:
		return
	for inst in _instances:
		var start: int = inst["frame"]
		if start < 0 or inst["sprites"][start] == END:
			continue
		if inst["sprites"][start] != BLANK and inst["flag"] != HIDDEN and inst["flag"] & SNOW:
			_tick_snow(inst)
		inst["timer"] = (inst["timer"] + 1) & 0xFF
		# u8 timer: times 0 wraps after 256 frames, then the frame advances (kept).
		if inst["timer"] == inst["times"][start]:
			inst["frame"] += 1
			inst["timer"] = 0
			if inst["frame"] >= FRAMES or inst["sprites"][inst["frame"]] == END:
				inst["frame"] = 0
		_show(inst)


## Places, sizes and textures an instance's quad for its current frame.
func _show(inst: Dictionary) -> void:
	var node: MeshInstance3D = inst["node"]
	if node == null:
		return
	var frame: int = inst["frame"]
	var sprite: int = inst["sprites"][frame] if frame >= 0 else END
	node.visible = layer_enabled and sprite >= 0 and sprite < _sprites.size() and inst["flag"] != HIDDEN
	if not node.visible or field == null:
		return
	var obj: Dictionary = _sprites[sprite]
	var size := Vector2(int(obj["width"]), int(obj["height"]))
	var corner := Vector2(inst["x"], inst["y"])
	if inst["flag"] & SNOW:
		# buildSnowflakePrim: screen coordinates, not scrolled.
		corner = field.scroll + Vector2(inst["x"] + inst.get("drift", 0), inst["y"])
	var depth: float = inst["order"] * OT_UNIT
	node.transform = Transform3D(field.camera.global_transform.basis,
			field.world_at_pixel(corner + size / 2, depth))
	(node.mesh as QuadMesh).size = size * depth / field.projection()
	node.material_override = _material(sprite)


# --- buildSnowflakePrim (overworld.c:665) --------------------------------------------------------

func _tick_snow(inst: Dictionary) -> void:
	var first: int = inst["sprites"][0]
	var spread := 0
	var fall := 0
	if first in [0, 3, 4]:
		spread = 6
		fall = 3
	elif first in [1, 5, 6]:
		spread = 2
		fall = 1
	elif first == 2:
		spread = 4
		fall = 10
	var drift := randi_range(0, spread - 1) if spread > 0 else 0
	if drift > spread / 2:
		drift = -(drift % (spread / 2))
	if first in [0, 3, 4]:
		if _frame_count % 3 == 0:
			inst["x"] += drift
		if inst["x"] >= 0x141:
			inst["x"] = 0
		if inst["x"] < 0:
			inst["x"] = 0x140
	inst["drift"] = drift
	inst["y"] += fall
	if inst["y"] >= 0x83 and first != 2:
		if randi_range(0, 9) < 2 and inst["frame"] == 0:
			inst["frame"] += 1
			inst["timer"] = 0
		var next: int = inst["frame"] + 1
		if inst["frame"] >= 2 and (next >= FRAMES or inst["sprites"][next] == END):
			inst["frame"] = 0
			inst["y"] = 0
	if inst["y"] >= 0xF1:
		inst["y"] = 0


# --- What the scripts change ---------------------------------------------------------------------

## setMapObjectsFlag(start, count, flag) (overworld.c:930): the whole flag (SET_OBJ_VISIBILITY:
## 0 shown, 1 hidden).
func set_flag(start: int, flag: int, count := 1) -> void:
	for k in range(start, start + count):
		if k >= 0 and k < _instances.size():
			_instances[k]["flag"] = _s8(flag)
			_show(_instances[k])


## resetMapObjectAnimation (overworld.c:1002), CALL_ROUTINE 0x15.
func reset_animation(start: int, count: int) -> void:
	for k in range(start, start + count):
		if k >= 0 and k < _instances.size():
			_instances[k]["timer"] = 0
			_instances[k]["frame"] = 0
			_show(_instances[k])


## tickMoveObjectTo (overworld.c:874), slot type 13: the first frame takes (target - position) /
## steps per axis (C division); every frame moves by it; an axis past its target, or with a delta
## of 0, snaps to it; done on both. `slot` is MOVE_OBJECT_TO's slot (0-9), whose flag and delta
## are its own.
func tick_move_to(k: int, slot: int, steps: int, target_x: int, target_y: int) -> bool:
	if k < 0 or k >= _instances.size() or slot < 0 or slot >= 10:
		return true
	var inst: Dictionary = _instances[k]
	if not _move_started[slot]:
		# steps 0 divides by zero on the PSX; the scripts never use it: one step.
		var n := steps if steps != 0 else 1
		_move_delta[slot] = Vector2i((target_x - inst["x"]) / n, (target_y - inst["y"]) / n)
		_move_started[slot] = true
	var delta: Vector2i = _move_delta[slot]
	inst["x"] += delta.x
	inst["y"] += delta.y
	inst["x"] = _snap(inst["x"], delta.x, target_x)
	inst["y"] = _snap(inst["y"], delta.y, target_y)
	_show(inst)
	if inst["x"] == target_x and inst["y"] == target_y:
		_move_started[slot] = false
		return true
	return false


static func _snap(value: int, delta: int, target: int) -> int:
	if delta > 0:
		return target if value >= target else value
	if delta < 0:
		return target if value <= target else value
	return target


## storeMapObjectPosition (overworld.c:790): the x / y of `count` instances from `start`.
func store_positions(start: int, count: int) -> Array:
	var out := []
	for k in range(start, start + count):
		var inst := instance(k)
		out.append(Vector2i(int(inst.get("x", 0)), int(inst.get("y", 0))))
	return out


## loadMapObjectPosition (overworld.c:832): the positions back; the flag loses bit 0x10.
func load_positions(positions: Array, start: int) -> void:
	for i in positions.size():
		var k := start + i
		if k < 0 or k >= _instances.size():
			continue
		var inst: Dictionary = _instances[k]
		inst["x"] = positions[i].x
		inst["y"] = positions[i].y
		inst["flag"] = _s8(inst["flag"] & ~0x10)
		_show(inst)


## moveMapObjectsWithLimit (overworld.c:844) without its limit test (the stations ignore it):
## `count` instances from `start` move by (dx, dy) background pixels.
func move(start: int, count: int, dx: int, dy: int) -> void:
	for k in range(start, start + count):
		if k < 0 or k >= _instances.size():
			continue
		var inst: Dictionary = _instances[k]
		inst["x"] += dx
		inst["y"] += dy
		_show(inst)


## spawnSpriteAtLocation (overworld.c:952): `count` instances from `start` get their top-left
## corner half their first non-blank sprite above-left of the background pixel; the flag loses bit
## 0x10 (loadMapObjectPosition). They aren't shown: the scripts show them.
func place_at(pixel: Vector2i, start: int, count := 1) -> void:
	for k in range(start, start + count):
		if k < 0 or k >= _instances.size():
			continue
		var inst: Dictionary = _instances[k]
		var sprite := _first_sprite(inst, false)
		var size := Vector2i.ZERO
		if sprite >= 0 and sprite < _sprites.size():
			size = Vector2i(int(_sprites[sprite]["width"]), int(_sprites[sprite]["height"]))
		inst["x"] = pixel.x - size.x / 2
		inst["y"] = pixel.y - size.y / 2
		inst["flag"] = _s8(inst["flag"] & ~0x10)
		_show(inst)


## updateMapLightState (utils2.c:553) for the map record's light_objects: each entry's instances
## are shown or hidden by the hour (mode 0 shown from 7:00 to 18:59, mode 1 hidden then), while
## its trigger is set (null always).
func update_light_state(lights: Array, hour: int, is_trigger_set: Callable) -> void:
	for light in lights:
		var trigger = light.get("trigger")
		if trigger != null and not is_trigger_set.call(int(trigger)):
			continue
		var day := hour >= LIGHT_FROM and hour < LIGHT_TO
		var shown := (int(light["mode"]) == 0) == day
		var start := int(light["start"])
		for k in range(start, start + int(light["count"])):
			if k < _instances.size() and _instances[k]["flag"] != (0 if shown else HIDDEN):
				set_flag(k, 0 if shown else HIDDEN)


## A new palette (time of day): the clut -1 sprites follow the background.
func set_palette(value: int) -> void:
	if value == palette:
		return
	palette = value
	_materials.clear()
	for inst in _instances:
		_show(inst)


# --- Materials -----------------------------------------------------------------------------------

## The texels without the STP bit are opaque; with it, a semi-transparent sprite blends them
## (tim.md): one pass each. 50 / 50 is a mix at half alpha, +25 % an add of a quarter.
const _SHADER := """shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, %s;
uniform sampler2D tex : source_color, filter_nearest;
uniform sampler2D stp : filter_nearest;
uniform bool use_stp = false;
uniform bool blended_pass = false;
uniform float alpha_scale = 1.0;
uniform float color_scale = 1.0;
void fragment() {
	vec4 c = texture(tex, UV);
	bool semi = use_stp && texture(stp, UV).r > 0.5;
	if (c.a < 0.5 || semi != blended_pass) {
		discard;
	}
	ALBEDO = c.rgb * color_scale;
	ALPHA = blended_pass ? alpha_scale : 1.0;
}
"""


func _material(sprite: int) -> Material:
	var key := Vector2i(sprite, palette)
	if _materials.has(key):
		return _materials[key]
	var obj: Dictionary = _sprites[sprite]
	var files: Array = obj.get("files", [])
	var stp_files: Array = obj.get("stp_files", [])
	# One file per TFS palette for the clut -1 sprites (they read the active palette, row 480).
	var variant := clampi(palette, 0, files.size() - 1) if files.size() > 1 else 0
	var tex := _texture(str(files[variant]) if not files.is_empty() else "")
	var stp_tex: Texture2D = null
	if variant < stp_files.size() and stp_files[variant] != null:
		stp_tex = _texture(str(stp_files[variant]))
	var transparency := int(obj.get("transparency", OPAQUE))
	# The STP bit only matters on a semi-transparent polygon: an opaque sprite (SetSemiTrans 0) draws
	# all its texels in the opaque pass (ISSUES.md I-1: MAYO01's bush has STP texels).
	if transparency == OPAQUE:
		stp_tex = null
	var opaque := _pass("blend_mix", tex, stp_tex, false)
	if transparency != OPAQUE and stp_tex != null:
		var mode := transparency & 3
		var blend: String = ["blend_mix", "blend_add", "blend_sub", "blend_add"][mode]
		var semi := _pass(blend, tex, stp_tex, true)
		semi.set_shader_parameter("alpha_scale", 0.5 if mode == 0 else 1.0)
		semi.set_shader_parameter("color_scale", 0.25 if mode == 3 else 1.0)
		opaque.next_pass = semi
	_materials[key] = opaque
	return opaque


func _pass(blend: String, tex: Texture2D, stp_tex: Texture2D, blended: bool) -> ShaderMaterial:
	if not _shaders.has(blend):
		var shader := Shader.new()
		shader.code = _SHADER % blend
		_shaders[blend] = shader
	var m := ShaderMaterial.new()
	m.shader = _shaders[blend]
	m.set_shader_parameter("tex", tex)
	m.set_shader_parameter("use_stp", stp_tex != null)
	if stp_tex != null:
		m.set_shader_parameter("stp", stp_tex)
	m.set_shader_parameter("blended_pass", blended)
	return m


## The sprite PNGs, from the porter's raw output (the editor mirror leaves them out); `files` are
## relative to the maps family folder.
func _texture(rel: String) -> Texture2D:
	if rel == "":
		return null
	return Content.load_texture("maps/" + rel)


static func _s8(v: int) -> int:
	return ((v & 0xFF) ^ 0x80) - 0x80
