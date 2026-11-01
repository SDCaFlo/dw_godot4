class_name DeathShards
extends MeshInstance3D
## Draws DooaShards (DOOA_renderShards, dooa.c:1424; specs/death_scene.md F19–F22): each shard a
## flat, unlit textured triangle or quad with the effect's colour (R, B, G) / 128, or, flickering, a
## flat colour (R, G, B) / 128 (the white texels of SPOT256). Rebuilt every frame; drawn after the
## model, double-sided (addScreenPolyFT3 / FT4 don't cull). Scene: scenes/field/death/death_shards.tscn.

## The face materials of each bone (PartnerWireframe.bone_materials): the shards' textures.
var materials_of := Callable()

## Per texture: the PsxLit material (unlit, double-sided, every texel opaque).
var _by_texture := {}
var _flat: ShaderMaterial


func _ready() -> void:
	mesh = ArrayMesh.new()
	_flat = PsxLit.material(null, true, 0.5, -1, null, false)


func clear() -> void:
	(mesh as ArrayMesh).clear_surfaces()


func draw(shards: DooaShards) -> void:
	var am := mesh as ArrayMesh
	am.clear_surfaces()
	var drawn := shards.drawn()
	if drawn.is_empty():
		return
	var c := shards.color
	# Normal: (R, B, G) (the C swaps G / B, dooa.c:1467); flickering: (R, G, B), untextured.
	var tint := Vector3(c.x, c.y, c.z) / 128.0 if shards.flash else Vector3(c.x, c.z, c.y) / 128.0
	var groups := {}
	for s: Dictionary in drawn:
		var key: Variant = null if shards.flash else _texture(s)
		if not groups.has(key):
			groups[key] = {"v": [], "uv": []}
		var g: Dictionary = groups[key]
		var verts := shards.vertices(s)
		var uvs := _uvs(s)
		var order := [0, 1, 2] if verts.size() == 3 else [0, 1, 2, 1, 3, 2]
		for k in order:
			var p: Vector3i = verts[k]
			g["v"].append(Vector3(p.x, -p.y, -p.z))
			g["uv"].append(uvs[k] if k < uvs.size() else Vector2.ZERO)
	for key in groups:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(groups[key]["v"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(groups[key]["uv"])
		am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		var mat := _flat if key == null else _material(key)
		mat.set_shader_parameter("tint", tint)
		am.surface_set_material(am.get_surface_count() - 1, mat)


## The face's texture (its material's), or null.
func _texture(s: Dictionary) -> Texture2D:
	var mats: Array = materials_of.call(int(s["bone"])) if materials_of.is_valid() else []
	var face := int(s["face"])
	var m: Material = mats[face] if face < mats.size() else null
	if m is ShaderMaterial:
		return (m as ShaderMaterial).get_shader_parameter("albedo_texture")
	if m is BaseMaterial3D:
		return (m as BaseMaterial3D).albedo_texture
	return null


func _material(texture: Texture2D) -> ShaderMaterial:
	if not _by_texture.has(texture):
		_by_texture[texture] = PsxLit.material(texture, true, 0.5, -1, null, false)
	return _by_texture[texture]


## The face's UVs (texture-page pixels / 256, as the glTF's).
static func _uvs(s: Dictionary) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for uv in s.get("uvs", []):
		out.append(Vector2(uv[0], uv[1]) / TmdFaceGroups.PAGE)
	return out
