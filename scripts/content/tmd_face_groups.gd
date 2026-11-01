class_name TmdFaceGroups
## A TMD object's faces split into the 16 groups of the wireframe renderers (specs/death_scene.md
## §3 A, §4.1): renderWireframed (model.c:3129, the partner; the evolution's 5f-2 too) and
## DOO2_renderWireframeModel (doo2.c:410, the egg) draw face i textured when
## WIREFRAME_RNG_TABLE[i & 15] < share, else (the partner only) as its outline. Built from the
## model's sidecar (tmd.objects[i]: the primitives in TMD order), not from the glTF, whose meshes
## group faces by material.

## WIREFRAME_RNG_TABLE (model.c:2501).
const TABLE := [6, 3, 11, 8, 10, 13, 1, 4, 14, 7, 12, 15, 5, 2, 9, 0]
const GROUPS := 16
## The primitive modes renderWireframed draws ((mode & 0xFC) == 0x34 / 0x3C, model.c:3174, 3215);
## another mode ends the object's loop (model.c:3263).
const TRIANGLE := 0x34
const QUAD := 0x3C
## The glTF's UVs: texture-page pixels / 256 (asset_porter/dwporter/exporters/gltf.py).
const PAGE := 256.0


## The groups drawn textured at `share` (A2), ascending.
static func shown(share: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for g in GROUPS:
		if TABLE[g] < share:
			out.append(g)
	return out


## The face index where renderWireframed stops (A7): the first primitive of another kind.
## `exact`: the egg's DOO2_renderWireframeModel compares the mode exactly (doo2.c:457, 499).
static func end_of(object: Dictionary, exact := false) -> int:
	var prims: Array = object.get("primitives", [])
	for i in prims.size():
		var mode := int(prims[i].get("mode", 0))
		if not exact:
			mode &= 0xFC
		if mode != TRIANGLE and mode != QUAD:
			return i
	return prims.size()


## The faces as meshes: {"faces": ArrayMesh, "groups": PackedInt32Array (each surface's group),
## "lines": ArrayMesh, "line_groups": PackedInt32Array, "end": int, "surfaces": [{"group",
## "material", "arrays"}], "line_surfaces": [{"group", "arrays"}]} (the arrays too: a headless
## renderer keeps no mesh data to read back). One textured surface per
## (group, material) with faces; the outlines (`outlines`) as PRIMITIVE_LINES pairs: a triangle
## v0 v1 v2 v0 (A8), a quad v0 v1 v3 v2 v0 (A9). `materials`: one per face (null: none). The
## triangles are in the PSX order, Godot's clockwise front face (the porter's glTF reversed:
## triangles (0, 1, 2), quads (0, 1, 2) + (1, 3, 2)).
static func build(object: Dictionary, materials: Array[Material], outlines: bool, exact := false) -> Dictionary:
	var end := end_of(object, exact)
	var verts: Array = object.get("vertices", [])
	var normals: Array = object.get("normals", [])
	var prims: Array = object.get("primitives", [])
	# (group, material index) -> the arrays being built.
	var surfaces := {}
	var mat_ids := {}
	var lines := {}
	for i in end:
		var p: Dictionary = prims[i]
		var g := i & 15
		var mat: Material = materials[i] if i < materials.size() else null
		var key := Vector2i(g, _mat_id(mat_ids, mat))
		if not surfaces.has(key):
			surfaces[key] = {"material": mat, "v": [], "n": [], "uv": [], "c": []}
		var s: Dictionary = surfaces[key]
		var order := [0, 1, 2] if not _is_quad(p) else [0, 1, 2, 1, 3, 2]
		for c in order:
			_corner(s, p, c, verts, normals)
		if outlines:
			if not lines.has(g):
				lines[g] = []
			var path := [0, 1, 2, 0] if not _is_quad(p) else [0, 1, 3, 2, 0]
			var vi: Array = p["vertices"]
			for k in path.size() - 1:
				lines[g].append(_vertex(verts, vi[path[k]]))
				lines[g].append(_vertex(verts, vi[path[k + 1]]))
	var faces := ArrayMesh.new()
	var groups := PackedInt32Array()
	var out_surfaces := []
	var out_lines := []
	var keys := surfaces.keys()
	keys.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return a.x < b.x or (a.x == b.x and a.y < b.y))
	for key: Vector2i in keys:
		var s: Dictionary = surfaces[key]
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(s["v"])
		arrays[Mesh.ARRAY_NORMAL] = PackedVector3Array(s["n"])
		arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(s["uv"])
		arrays[Mesh.ARRAY_COLOR] = PackedColorArray(s["c"])
		faces.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		if faces.get_surface_count() > 0:
			faces.surface_set_material(faces.get_surface_count() - 1, s["material"])
		groups.append(key.x)
		out_surfaces.append({"group": key.x, "material": s["material"], "arrays": arrays})
	var line_mesh := ArrayMesh.new()
	var line_groups := PackedInt32Array()
	var line_keys := lines.keys()
	line_keys.sort()
	for g in line_keys:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(lines[g])
		line_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
		line_groups.append(g)
		out_lines.append({"group": g, "arrays": arrays})
	return {"faces": faces, "groups": groups, "lines": line_mesh, "line_groups": line_groups, "end": end,
			"surfaces": out_surfaces, "line_surfaces": out_lines}


static func _is_quad(p: Dictionary) -> bool:
	return (int(p.get("mode", 0)) & 0xFC) == QUAD


static func _mat_id(ids: Dictionary, mat: Material) -> int:
	var key: Variant = mat.get_instance_id() if mat != null else 0
	if not ids.has(key):
		ids[key] = ids.size()
	return ids[key]


static func _vertex(verts: Array, index: int) -> Vector3:
	var v: Variant = verts[index] if index < verts.size() else [0, 0, 0]
	if v is Vector3i:
		return Vector3(v.x, -v.y, -v.z)
	return Content.psx_to_godot(v)


static func _corner(s: Dictionary, p: Dictionary, c: int, verts: Array, normals: Array) -> void:
	var vi: Array = p["vertices"]
	s["v"].append(_vertex(verts, vi[c]))
	var ni: Array = p.get("normals", [])
	var n := Vector3.UP
	if c < ni.size() and int(ni[c]) < normals.size():
		var raw: Variant = normals[int(ni[c])]
		n = Content.psx_to_godot(raw).normalized() if raw is Array else n
	s["n"].append(n)
	var uvs: Array = p.get("uvs", [])
	var uv: Array = uvs[c] if c < uvs.size() else [0, 0]
	s["uv"].append(Vector2(uv[0], uv[1]) / PAGE)
	s["c"].append(Color.WHITE)


## The outline points of face `i` (Godot, the object's local space), in drawing order: a closed
## path (A8 / A9).
static func outline(object: Dictionary, i: int) -> PackedVector3Array:
	var p: Dictionary = object["primitives"][i]
	var vi: Array = p["vertices"]
	var verts: Array = object.get("vertices", [])
	var path := [0, 1, 2, 0] if not _is_quad(p) else [0, 1, 3, 2, 0]
	var out := PackedVector3Array()
	for k in path:
		out.append(_vertex(verts, vi[k]))
	return out
