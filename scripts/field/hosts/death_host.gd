class_name DeathHost
extends Node
## The death and lives scenes (specs/death_reincarnation.md §9; scenes/field/hosts/death_host.tscn).
## Its children are the logic: MurdScene (a life lost) and DooaScene (the dissolution and the
## rebirth), ticked by the field's frame order as objects; the tamer's states 17 / 19 and the
## partner's 8 / 14 start them and wait for them, as in the C. The host wires them and draws them:
## the iris and the background's darkening (DeathIris, on the background layer), MURD's full-screen
## darkening (DeathDarken, in the HUD), and, until the shards are ported, a stand-in dissolve on the
## partner's model (partner_dissolve.gdshader) and the egg model in the room.

const IRIS_SCENE := preload("res://scenes/field/death/death_iris.tscn")
const DARKEN_SCENE := preload("res://scenes/field/death/death_darken.tscn")
const DISSOLVE_SHADER := preload("res://scenes/field/death/partner_dissolve.gdshader")
## DOOA_EGG_TMD_PATH: the eggs' model (one per egg slot, as the C's GsLinkObject4 index).
const EGG_MODEL := "tmd_files/ETCDAT/TAMA.gltf"
## The stand-in dissolve: the faces sink over the shard waves (0x69-0xBF) and fade by 0xD1.
const SINK_START := 0x69
const SINK_END := 0xBF
const WIRE_COLOR := Color(0.85, 0.85, 0.95, 1.0)

var camera: Camera3D
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var evolution: Evolution
var boxes: UIBoxes
var script_ctx: ScriptContext
var game_state: Node
var data: Node
var sound: Node
## changeMap(map, exit) (MapSession.change_map).
var change_map := Callable()
## The map layer's nodes (Field.map_layer_nodes): setMapLayerEnabled hides them.
var map_layer_nodes := Callable()
## The world the egg is added to.
var world: Node
## The field's fade: the map change holds it black while the map loads (Fade.hold, not in the C).
var fade: Fade

@onready var murd: MurdScene = $MurdScene
@onready var dooa: DooaScene = $DooaScene
## Made in start(); the field adds the iris to the background layer, the darkening to the HUD.
var iris: DeathIris
var darken: ColorRect

var _hidden_layer := {}
var _wireframes: Array[MeshInstance3D] = []
var _dissolve_meshes: Array[MeshInstance3D] = []
var _dissolve_materials: Array[Material] = []
var _dissolve_shaders: Array[ShaderMaterial] = []
var _egg: Node3D


## Hands the logic its references and gives the tamer and the partner their scenes.
func start() -> void:
	for scene: Node in [murd, dooa]:
		scene.set("partner", partner)
		scene.set("tamer", tamer)
		scene.set("entities", entities)
		scene.set("game_state", game_state)
		scene.set("sound", sound)
		scene.set("change_map", _change_to_death_map)
		scene.set("map_layer", _set_map_layer)
	murd.boxes = boxes
	murd.dooa = dooa
	murd.screen_point = _screen_point
	dooa.evolution = evolution
	dooa.data = data
	dooa.phase_changed.connect(_on_dooa_phase)
	tamer.murd = murd
	tamer.dooa = dooa
	tamer.script_ctx = script_ctx
	partner.dooa = dooa
	iris = IRIS_SCENE.instantiate()
	darken = DARKEN_SCENE.instantiate()


## The objects' frame (their place in the object list: after the script's objects).
func tick_objects() -> void:
	murd.tick()
	dooa.tick()


## Draws the scenes' state every frame (the C's render functions).
func _process(_delta: float) -> void:
	if iris == null:
		return
	_draw_iris()
	var level := murd.darken if murd.active else 0
	darken.visible = level > 0
	darken.color = Color(level / 255.0, level / 255.0, level / 255.0)
	if dooa.sequence == DooaScene.DISSOLVE:
		_draw_dissolve()
	if _egg != null:
		_egg.visible = dooa.egg_fade > 0


## MURD_renderScene (timer < 0x24) and DOOA_renderDissolve (frame < 36): the window closing on the
## partner; the map background's darkness while either scene holds it.
func _draw_iris() -> void:
	var radius := -1.0
	if murd.active and murd.timer >= 0 and murd.timer < MurdScene.IRIS_DRAWN:
		radius = _iris_radius(murd.timer, MurdScene.IRIS_END)
	elif dooa.sequence == DooaScene.DISSOLVE and dooa.frame >= 0 and dooa.frame < DooaScene.IRIS_DRAWN:
		radius = _iris_radius(dooa.frame, DooaScene.IRIS_END)
	var darkness := 0
	if murd.active:
		darkness = murd.darkness
	if dooa.darkness > darkness:
		darkness = dooa.darkness
	if radius < 0.0 and darkness == 0:
		iris.hide_iris()
		return
	var center := _screen_point(_partner_centre()) + FieldMap.SCREEN / 2
	iris.show_iris(center, maxf(radius, 0.0) if radius >= 0.0 else DeathIris.MAX_RADIUS * 2, darkness)


static func _iris_radius(t: int, end: int) -> float:
	return 2.0 * PsxMath.lerp_int(200, 0, 0, end, mini(t, end))


## The partner's middle: its location raised by half its height (MURD_renderIris).
func _partner_centre() -> Vector3:
	var height := 0
	if data != null and partner.digimon != "":
		height = int(data.digimon(partner.digimon).get("height", 0))
	return partner.global_position + Vector3(0, height / 2.0, 0)


## worldPosToScreenPos: centred PSX screen pixels.
func _screen_point(world_point: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	return FieldMap.unproject(camera, world_point) - FieldMap.SCREEN / 2


## changeToDeathMap: the field's map change, then the fade released. MapSession.change_map holds
## the screen black for the load (Fade.hold, port-only) until a fade in; the C's death map change
## has no fade (MURD and DOOA darken the screen themselves), so the fade clears at once after the
## hold.
func _change_to_death_map(map: int, exit: int) -> void:
	if change_map.is_valid():
		change_map.call(map, exit)
	if fade != null:
		fade.fade_from_black(0)


## setMapLayerEnabled (as FieldBattleWorld's): the map's objects hidden, then back as they were.
func _set_map_layer(enabled: bool) -> void:
	if not enabled:
		var nodes: Array = map_layer_nodes.call() if map_layer_nodes.is_valid() else []
		for n in nodes:
			if n != null and is_instance_valid(n) and not _hidden_layer.has(n):
				_hidden_layer[n] = n.visible
				n.visible = false
	else:
		for n in _hidden_layer:
			if is_instance_valid(n):
				n.visible = _hidden_layer[n]
		_hidden_layer.clear()


# --- the stand-ins --------------------------------------------------------------------------------

func _on_dooa_phase(phase: int) -> void:
	match phase:
		DooaScene.PHASE_SHARDS:
			_start_dissolve()
		DooaScene.PHASE_RISE:
			_end_dissolve()
		DooaScene.PHASE_EGG:
			_spawn_egg()
		DooaScene.PHASE_BABY_FADE:
			if _egg != null:
				_egg.queue_free()
				_egg = null


func _draw_dissolve() -> void:
	var progress := clampf(float(dooa.frame - SINK_START) / (SINK_END - SINK_START), 0.0, 1.0)
	for mat in _dissolve_shaders:
		mat.set_shader_parameter("fall_progress", progress)
		mat.set_shader_parameter("alpha", 1.0 - progress)
	partner.scale = Vector3(dooa.squash.y, dooa.squash.x, dooa.squash.y)


## The partner's meshes get the sinking material and a wireframe copy (its triangles' edges) that
## follows the same skeleton.
func _start_dissolve() -> void:
	_end_dissolve()
	var model := partner.get_node_or_null("Model")
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null or mesh_instance in _wireframes:
			continue
		var wire := _wireframe(mesh_instance)
		if wire != null:
			mesh_instance.get_parent().add_child(wire)
			_wireframes.append(wire)
		var original := mesh_instance.material_override
		if original == null:
			original = mesh_instance.get_surface_override_material(0)
		var texture: Texture2D = null
		if original is ShaderMaterial:
			texture = (original as ShaderMaterial).get_shader_parameter("albedo_texture")
		elif original is BaseMaterial3D:
			texture = (original as BaseMaterial3D).albedo_texture
		var sink := ShaderMaterial.new()
		sink.shader = DISSOLVE_SHADER
		if texture != null:
			sink.set_shader_parameter("albedo_texture", texture)
		_dissolve_meshes.append(mesh_instance)
		_dissolve_materials.append(mesh_instance.material_override)
		_dissolve_shaders.append(sink)
		mesh_instance.material_override = sink


func _wireframe(source: MeshInstance3D) -> MeshInstance3D:
	var wire_mesh := ArrayMesh.new()
	for s in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(s)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
		var lines := PackedInt32Array()
		for t in range(0, indices.size() - 2, 3):
			lines.append_array([indices[t], indices[t + 1], indices[t + 1], indices[t + 2], indices[t + 2], indices[t]])
		if lines.is_empty():
			continue
		var line_arrays := []
		line_arrays.resize(Mesh.ARRAY_MAX)
		line_arrays[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
		line_arrays[Mesh.ARRAY_INDEX] = lines
		line_arrays[Mesh.ARRAY_BONES] = arrays[Mesh.ARRAY_BONES]
		line_arrays[Mesh.ARRAY_WEIGHTS] = arrays[Mesh.ARRAY_WEIGHTS]
		wire_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)
	if wire_mesh.get_surface_count() == 0:
		return null
	var wire := MeshInstance3D.new()
	wire.mesh = wire_mesh
	wire.skin = source.skin
	wire.skeleton = source.skeleton
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = WIRE_COLOR
	wire.material_override = mat
	return wire


func _end_dissolve() -> void:
	for wire in _wireframes:
		if is_instance_valid(wire):
			wire.queue_free()
	_wireframes.clear()
	for i in _dissolve_meshes.size():
		if is_instance_valid(_dissolve_meshes[i]):
			_dissolve_meshes[i].material_override = _dissolve_materials[i]
	_dissolve_meshes.clear()
	_dissolve_materials.clear()
	_dissolve_shaders.clear()
	if partner != null:
		partner.scale = Vector3.ONE


## DOOA phase 0x66: the egg model at the room's centre (shown while it fades in, DOO2_fadeClut).
func _spawn_egg() -> void:
	if _egg != null:
		_egg.queue_free()
	_egg = Content.load_model(EGG_MODEL) if Content.exists(EGG_MODEL) else null
	if _egg == null or world == null:
		return
	_egg.name = "Digitama"
	_egg.position = Vector3.ZERO
	_egg.visible = false
	world.add_child(_egg)
