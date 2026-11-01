class_name EvlShardsView
extends MeshInstance3D
## Draws the evolution's shard sets (EVL_renderShardSet, EVL_renderTri/QuadShard, evl.c:882-1161;
## specs/evolution_scene.md E4-E9): each face a flat, unlit textured polygon with the set's grey / 128,
## double-sided (addScreenPolyFT3 / FT4 don't cull), semi-transparent half / half with the model's
## tpage (pixelPage 0x16 + k / 2: abr 0). A semi-transparent polygon blends only the texels whose
## colour has the STP bit: the model's own until the brighten's first non-start frame, every
## non-black colour after it (E8: `translucent`). Rebuilt every frame. Scene:
## scenes/field/evolution/evl_shards.tscn.

## E7: the tpage's abr (model.c:3400, pixelPage's bits 5-6 are 0).
const ABR := PsxLit.HALF

## Per (texture, translucent, grey): the material.
var _materials := {}
## Each face's {"texture", "stp"}, looked up once per set (bone, face).
var _source_of := {}
var _faces := 0


func _ready() -> void:
	mesh = ArrayMesh.new()


## The faces drawn by the last draw().
func shown_faces() -> int:
	return _faces


func clear() -> void:
	(mesh as ArrayMesh).clear_surfaces()
	_faces = 0


## The live sets with their face materials (PartnerWireframe.bone_materials: the faces' textures
## and STP masks); `translucent`: every non-black texel blends (E8).
func draw(sets: EvlShardSets, materials_of: Callable, translucent: bool) -> void:
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	_faces = 0
	if sets == null:
		return
	var groups := {}
	for s: Dictionary in sets.drawn():
		var g := EvlShardSets.grey(int(s["timer"]))
		var prims: Array = s["object"].get("primitives", [])
		for face: Dictionary in sets.faces(s):
			var src := _source(int(s["bone"]), int(face["face"]), materials_of)
			var key := [src["texture"], src["stp"], g]
			if not groups.has(key):
				groups[key] = {"v": [], "uv": []}
			var group: Dictionary = groups[key]
			var points: Array = face["points"]
			var uvs: Array = prims[int(face["face"])].get("uvs", [])
			var order := [0, 1, 2] if points.size() == 3 else [0, 1, 2, 1, 3, 2]
			for k in order:
				var p: Vector3i = points[k]
				group["v"].append(Vector3(p.x, -p.y, -p.z))
				group["uv"].append(Vector2(uvs[k][0], uvs[k][1]) / TmdFaceGroups.PAGE if k < uvs.size() else Vector2.ZERO)
			_faces += 1
	for key: Array in groups:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(groups[key]["v"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(groups[key]["uv"])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		am.surface_set_material(am.get_surface_count() - 1, _material(key[0], key[1], translucent, key[2]))


## The face's texture and STP mask, from its model material (cached: the wireframe that knows
## them moves to the new model at the apply).
func _source(bone: int, face: int, materials_of: Callable) -> Dictionary:
	var key := Vector2i(bone, face)
	if not _source_of.has(key):
		var mats: Array = materials_of.call(bone) if materials_of.is_valid() else []
		var m: Material = mats[face] if face < mats.size() else null
		var out := {"texture": null, "stp": null}
		if m is ShaderMaterial:
			out["texture"] = (m as ShaderMaterial).get_shader_parameter("albedo_texture")
			if (m as ShaderMaterial).get_shader_parameter("use_stp"):
				out["stp"] = (m as ShaderMaterial).get_shader_parameter("stp_texture")
		elif m is BaseMaterial3D:
			out["texture"] = (m as BaseMaterial3D).albedo_texture
		_source_of[key] = out
	return _source_of[key]


## E7 / E8: unlit and double-sided; before the brighten only the model's STP texels blend, after it
## every texel (the transparent black ones are cut by the alpha test); the grey / 128 as `tint`.
func _material(texture: Texture2D, stp: Texture2D, translucent: bool, grey: int) -> ShaderMaterial:
	var key := [texture, stp, translucent, grey]
	if not _materials.has(key):
		var m: ShaderMaterial
		if translucent:
			m = PsxLit.blended(texture, ABR, true, false)
		else:
			m = PsxLit.material(texture, true, 0.5, ABR, stp, false)
		var pass_material: Material = m
		while pass_material is ShaderMaterial:
			(pass_material as ShaderMaterial).set_shader_parameter("tint", Vector3.ONE * grey / 128.0)
			pass_material = pass_material.next_pass
		_materials[key] = m
	return _materials[key]
