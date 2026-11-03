class_name EabView
extends Node
## What Machinedramon's build-up and spawn draw (specs/map_events.md §3.3 E1, E3, E7-E10, §4.3.2), from
## an EabScene after its tick:
## - `rings`: three BOSS_EFE.TMD object-0 instances in the 3D world (EAB_renderBuildupRing /
##   EAB_renderSpawnRing, eab.c:255, :312), tinted 0x3C / 128 (EAB_setModelColor, :159: all 12 quads
##   are 0x2F, so all are coloured);
## - `backdrop` and `lines` on the field's background layer: OT 0xFA0 and 0xF9F, behind every model
##   (EAB_renderBackdrop :540, EAB_renderParticle :608), the lines over the backdrop;
## - `flash`: EAB_renderFlash (:471), full-screen quads over the 3D world (stand-in: a canvas layer
##   over the world, under the HUD, for OT 0xA).
## The flash and the backdrop are POLY_FT4, abr 2 (subtract), on SPOT256's texel 255 (0xFFFF, §8.3).

## script_interp.c:157 (MAIN_D_80130394): the TMD; its texture is the map's VRAM, so the porter writes
## a textured copy per map that loads it (asset_porter maps/<NAME>/props/).
const MODEL := "tmd_files/ETCHI/BOSS_EFE.gltf"
const MAP_MODEL := "maps/%s/props/BOSS_EFE.gltf"
## eab.c:628-629: an edge is drawn when both ends' depth (worldPosToScreenPos >> 4) is in the window.
const DEPTH_MIN := 0x20
const DEPTH_MAX := 0x1000
## SPOT256 index 255 = 0xFFFF: 31 per channel (specs/map_events.md §8.3).
const TEXEL := 0x1F
## EAB_renderBackdrop's colour (EAB_D_800617C0, eab.c:152).
const BACKDROP_COLOR := 0xFF
## stand-in: the flash's canvas layer over the 3D world (OT 0xA).
const FLASH_LAYER := 1

const PARTICLES_SCENE := preload("res://scenes/field/evolution/evl_particles.tscn")

var rings: Array[Node3D] = []
var backdrop: ColorRect
var lines: EvlParticlesView
var flash: Control

var _world: Node
var _flash_layer: CanvasLayer
var _flash_levels: Array = []
var _model_of := ""


## texel × colour / 128, saturated (the GPU's texture modulation): the amount the quad subtracts, 0-31.
static func subtract_level(c: int) -> int:
	return mini(TEXEL, (TEXEL * c) >> 7)


## renderTMDModel (effect_common.c:579): RotMatrix(rot), ScaleMatrix(scale), TransMatrix(trans).
static func ring_matrix(scale: Vector3i, location: Vector3i) -> PackedInt32Array:
	return PsxMath.trans_matrix(PsxMath.scale_matrix(PsxMath.rot_matrix(EabScene.RING_ROTATION), scale), location)


## The map's own copy of the ring model when the porter wrote one, else the plain TMD's.
static func model_path(map_name: String) -> String:
	var per_map := MAP_MODEL % map_name
	return per_map if Content.exists(per_map) else MODEL


## EAB_renderParticle (eab.c:608-643): each live particle's square (corners pos ± size in x and z),
## projected; an edge when both ends' depth is in the window. [from, to, Color] in screen pixels
## (`project`: FieldMap.world_to_screen, `offset`: the drawing offset).
static func particle_lines(scene: EabScene, project: Callable, offset: Vector2) -> Array:
	var out := []
	for i in scene.particles.size():
		var p: Dictionary = scene.particles[i]
		if int(p["timer"]) < 0:
			continue
		var size := scene.particle_size(i)
		var pos: Vector3i = p["pos"]
		var corners := [
			Vector3i(pos.x + size, pos.y, pos.z + size),
			Vector3i(pos.x + size, pos.y, pos.z - size),
			Vector3i(pos.x - size, pos.y, pos.z - size),
			Vector3i(pos.x - size, pos.y, pos.z + size),
		]
		var screen := []
		var depth := []
		for c: Vector3i in corners:
			var r: Dictionary = project.call(c)
			screen.append(Vector2(r["screen"]) + offset)
			depth.append(int(r["sz"]) >> 4)
		var c3 := scene.particle_color(i)
		var color := Color8(c3.x & 0xFF, c3.y & 0xFF, c3.z & 0xFF)
		for k in 4:
			var j := (k + 1) % 4
			if depth[k] > DEPTH_MIN and depth[k] < DEPTH_MAX and depth[j] > DEPTH_MIN and depth[j] < DEPTH_MAX:
				out.append([screen[k], screen[j], color])
	return out


## The views into the world (rings, flash layer) and the background layer (backdrop, then lines).
func attach(world: Node, background: Node) -> void:
	_world = world
	backdrop = ColorRect.new()
	backdrop.name = "EabBackdrop"
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	backdrop.size = FieldMap.SCREEN
	backdrop.material = _subtract()
	var level := subtract_level(BACKDROP_COLOR) / float(TEXEL)
	backdrop.color = Color(level, level, level)
	backdrop.visible = false
	lines = PARTICLES_SCENE.instantiate()
	lines.name = "EabLines"
	if background != null:
		background.add_child(backdrop)
		background.add_child(lines)
	_flash_layer = CanvasLayer.new()
	_flash_layer.name = "EabFlashLayer"
	_flash_layer.layer = FLASH_LAYER
	flash = Control.new()
	flash.name = "EabFlash"
	flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	flash.material = _subtract()
	flash.draw.connect(_draw_flash)
	_flash_layer.add_child(flash)
	if world != null:
		world.add_child(_flash_layer)


static func _subtract() -> CanvasItemMaterial:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_SUB
	return m


## Routine 0x33's model: three ring instances for the map (none if the model is missing).
func load_model(map_name: String) -> void:
	var path := model_path(map_name)
	if path == _model_of and rings.size() == EabScene.RINGS:
		return
	_free_rings()
	_model_of = path
	if not Content.exists(path) or _world == null:
		return
	for i in EabScene.RINGS:
		var ring: Node3D = Content.load_model(path)
		if ring == null:
			continue
		ring.name = "EabRing%d" % i
		ring.visible = false
		_world.add_child(ring)
		PaletteFade.apply(ring, EabScene.MODEL_COLOR.x / 128.0)
		rings.append(ring)


func _free_rings() -> void:
	for r in rings:
		if is_instance_valid(r):
			r.queue_free()
	rings.clear()
	_model_of = ""


## This frame's drawing: `buildup_at` / `spawn_at` the rings' entities' locations (fx->entity).
func draw_frame(scene: EabScene, buildup_at: Vector3i, spawn_at: Vector3i, project: Callable, offset: Vector2) -> void:
	for i in rings.size():
		var r: Dictionary = scene.rings[i]
		var live := int(r["timer"]) >= 0
		rings[i].visible = live
		if live:
			var at := buildup_at if r["kind"] == EabScene.RING_BUILDUP else spawn_at
			rings[i].transform = Content.psx_transform(ring_matrix(scene.ring_scale(i), at))
	lines.set_lines(particle_lines(scene, project, offset) if project.is_valid() else [])
	backdrop.visible = scene.backdrop
	_flash_levels.clear()
	for c in scene.flashes_drawn:
		_flash_levels.append(subtract_level(c))
	flash.queue_redraw()


## Nothing drawn.
func clear() -> void:
	for r in rings:
		r.visible = false
	lines.clear()
	backdrop.visible = false
	_flash_levels.clear()
	flash.queue_redraw()


## The levels of this frame's flash quads (0-31 each).
func flash_levels() -> Array:
	return _flash_levels.duplicate()


func _draw_flash() -> void:
	for level in _flash_levels:
		var f: float = level / float(TEXEL)
		flash.draw_rect(Rect2(Vector2.ZERO, flash.size), Color(f, f, f))


func _exit_tree() -> void:
	_free_rings()
	for n: Node in [backdrop, lines, _flash_layer]:
		if n != null and is_instance_valid(n):
			n.queue_free()
