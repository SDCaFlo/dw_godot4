class_name EndingHost
extends Node
## The ending's tamer scene (specs/map_events.md §3.4, §4.4.2; endi.c). Its EndingScene is the logic,
## ticked as an object of the field's frame (tick_objects); routine 0x34 loads (load_scene), the
## tamer's state 16 (routine 0x35, digimon routine 6) starts it and waits for it (start, result). The
## host does the rest of ENDI_tickEnding (the tamer semi-transparent, his shadow off) and draws each
## frame: the tamer's colour fade (a tint: stand-in for ENDI_fadeClut), his scale, the sparks
## (FxParticles, renderFXParticle).

## loadMapSounds2(0x14) (script_interp.c:1851).
const MAP_SOUNDS := 0x14
## ENDI_setModelSemiTrans: tpage abr bits -> 1 (endi.c:137, :143).
const ABR := 1

var tamer: Tamer
var field_map: FieldMap
var sound: Node
var data: Node
var map_layer_nodes := Callable()
## The 3D views' parent (the world SubViewport).
var world: Node

var scene := EndingScene.new()
var particles: FxParticles
## The particles drawn this frame (EndingScene.render).
var drawn: Array = []

var _ghost := false


func _ready() -> void:
	particles = FxParticles.new()
	particles.name = "EndingParticles"


## Routine 0x34 (script_interp.c:1848-1852): the map's sound set 0x14. loadTextureFile(OP.TIM) lands at
## VRAM (576, 256), which nothing in endi.c reads; the REL has nothing to port.
func load_scene() -> void:
	if sound != null:
		sound.load_map_sounds(MAP_SOUNDS)


## tamerTickEnding's sub-state 0 (tamer.c:1686): ENDI_tickEnding(ENTITY_TABLE[0], 0).
func start() -> void:
	if tamer == null:
		return
	scene.bone_count = int(data.digimon(0).get("bone_count", 2)) if data != null else 2
	scene.bone_matrix = _bone_matrix
	scene.start()
	# ENDI_setClutStp + ENDI_setModelSemiTrans(ENTITY_TABLE[0]): every polygon additive, black clear.
	PsxLit.semi_transparent(tamer, ABR)
	_ghost = true
	# PLAYER_SHADOW_ENABLED = 0 (endi.c:426).
	var shadow := tamer.get_node_or_null("DropShadow") as DropShadow
	if shadow != null:
		shadow.enabled = false
	_run_events()
	_draw_frame()


## ENDI_tickEnding(entity, 1): -1 once over (or never started).
func result() -> int:
	return scene.result()


## The objects' frame: ENDI_updateEnding, its events, then ENDI_renderParticles.
func tick_objects() -> void:
	if not scene.active and drawn.is_empty():
		return
	scene.tick()
	_run_events()
	_draw_frame()


func _run_events() -> void:
	for ev in scene.events:
		if ev is Array and ev[0] == "sound":
			if sound != null:
				sound.play_sound(int(ev[1]), int(ev[2]))
		elif ev == "stop_sound":
			if sound != null:
				sound.stop_sound()
	scene.events.clear()


func _draw_frame() -> void:
	if tamer == null:
		return
	if _ghost:
		_tint(EndingScene.fade_factor(scene.fade_frame))
	# posData->scale (endi.c:186-192): the tamer's root, 4096 = 1.
	tamer.scale = Vector3.ONE * scene.scale / float(EndingScene.SCALE_ONE)
	drawn = scene.render()
	if not particles.is_inside_tree():
		(world if world != null else self).add_child(particles)
	particles.begin()
	if field_map != null:
		for p: Dictionary in drawn:
			particles.particle(field_map, p["pos"], int(p["size"]), p["color"])
	particles.end()


## ENDI_fadeClut's colours on every pass of the tamer's (semi-transparent) materials.
func _tint(f: float) -> void:
	for node in tamer.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi is DropShadow or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var m := mi.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				m.set_shader_parameter("tint", Vector3(f, f, f))


## calculateBoneMatrix(tamer, bone) / posMatrix.workm: the bone's world matrix in PSX units.
func _bone_matrix(bone: int) -> PackedInt32Array:
	var p := tamer.bone_position(bone)
	var m := Content.psx_matrix(tamer.bone_basis(bone))
	return PsxMath.trans_matrix(m, Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z)))
