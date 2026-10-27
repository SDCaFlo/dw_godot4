class_name TmdObjects
extends Node3D
## A TMD model's objects drawn the way the C's renderTMDModel (effect_common.c:579) draws them: any
## object, any number of times a frame, each with its own PSX world matrix. The model is the asset
## porter's glTF (one node `object_<k>` per TMD object); its surfaces get PsxLit materials as the
## porter describes them (texture page, STP mask and blend mode, lit or not). The owner calls
## begin_frame(), one draw() per C call, then end_frame(); the meshes are pooled per object.
## Used by the battle visuals (BattleVisualsView, specs/battle_effects.md §7.6).

## Per object: {mesh, materials (one PsxLit material per surface), tinted (its brightness-off
## surfaces: BTL_setTMDObjectColor's polygons)}.
var objects: Array = []

var _pools: Array = []
var _used: Array[int] = []


## Loads the porter's model at `rel` (e.g. "btl_rel/stun.gltf"); false when it isn't there.
func load_model(rel: String) -> bool:
	if not Content.exists(rel):
		return false
	var model := Content.load_model(rel)
	if model == null:
		return false
	var extras := Content._material_extras(rel)
	var k := 0
	while true:
		var node := model.find_child("object_%d" % k, true, false) as MeshInstance3D
		if node == null:
			break
		var entry := {"mesh": node.mesh, "materials": [], "tinted": []}
		if node.mesh != null:
			for s in node.mesh.get_surface_count():
				var source := node.mesh.surface_get_material(s) as BaseMaterial3D
				var e: Dictionary = extras.get(source.resource_name, {}) if source != null else {}
				var abr := int(e.get("tpage", {}).get("abr", 0)) if e.get("semi_transparent", false) else -1
				var texture: Texture2D = source.albedo_texture if source != null else null
				var lit := not bool(e.get("brightness_off", false))
				entry["materials"].append(PsxLit.material(texture, bool(e.get("double_sided", false)), 0.5, abr,
						e.get("stp"), lit))
				entry["tinted"].append(not lit)
		objects.append(entry)
		_pools.append([])
		_used.append(0)
		k += 1
	# The meshes are kept; the loaded scene's nodes go, without their materials and meshes.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for s in node.get_surface_override_material_count():
			node.set_surface_override_material(s, null)
		node.mesh = null
	model.free()
	return true


func begin_frame() -> void:
	for k in _pools.size():
		_used[k] = 0


## Hides the copies not drawn this frame.
func end_frame() -> void:
	for k in _pools.size():
		var pool: Array = _pools[k]
		for i in range(_used[k], pool.size()):
			pool[i].visible = false


## One copy of object `id` placed by a PSX world matrix (rotation · scale, translation; PsxMath).
func draw(id: int, m: PackedInt32Array) -> void:
	if id < 0 or id >= objects.size() or objects[id]["mesh"] == null:
		return
	var node := _take(id)
	var t := PsxMath.translation(m)
	node.transform = Transform3D(EfeView._godot_basis(m), Content.psx_to_godot([t.x, t.y, t.z]))
	node.visible = true


## BTL_setTMDObjectColor (battle_effect.c:5829): the colour of the object's brightness-off
## polygons (128 = the texel as is).
func set_color(id: int, color: Vector3i) -> void:
	if id < 0 or id >= objects.size():
		return
	var tint := Vector3(color.x & 0xFF, color.y & 0xFF, color.z & 0xFF) / 128.0
	var entry: Dictionary = objects[id]
	for s in entry["materials"].size():
		if entry["tinted"][s]:
			_set_param(entry["materials"][s], "tint", tint)


## The object's textures (every surface): another CLUT row of its page (morphBuffModel).
func set_textures(id: int, albedo: Texture2D, stp: Texture2D) -> void:
	if id < 0 or id >= objects.size():
		return
	for material in objects[id]["materials"]:
		_set_param(material, "albedo_texture", albedo)
		_set_param(material, "stp_texture", stp)


func shown() -> int:
	var n := 0
	for k in _used.size():
		n += _used[k]
	return n


static func _set_param(material: Material, param: String, value: Variant) -> void:
	while material is ShaderMaterial:
		material.set_shader_parameter(param, value)
		material = material.next_pass


func _take(id: int) -> MeshInstance3D:
	var pool: Array = _pools[id]
	if _used[id] == pool.size():
		var node := MeshInstance3D.new()
		node.mesh = objects[id]["mesh"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var materials: Array = objects[id]["materials"]
		for s in materials.size():
			node.set_surface_override_material(s, materials[s])
		add_child(node)
		pool.append(node)
	_used[id] += 1
	return pool[_used[id] - 1]
