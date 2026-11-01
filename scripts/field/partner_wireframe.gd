class_name PartnerWireframe
extends Node
## The partner drawn in wireframe (renderWireframed, model.c:3129; specs/death_scene.md §3 A,
## §4.1): per bone object, face i textured when WIREFRAME_RNG_TABLE[i & 15] < share, else its
## outline in the object's flickering grey; share 16 is the normal model. The DOOA dissolution sets
## PARTNER_WIREFRAME_TOTAL, the evolution scene (5f-2) PARTNER_WIREFRAME_SUB per bone. Its scene is
## scenes/field/partner_wireframe.tscn; its owner calls attach() with the partner's model and
## set_share / roll_greys every game frame.
##
## The meshes are siblings of each bone object's MeshInstance3D (under the same BoneAttachment3D), so
## they follow the animation. The outlines are culled on the CPU each frame as RotNclip culls them
## (A10): a face shows when its first three vertices face the camera.

const TOTAL := 16

## The last total set (PARTNER_WIREFRAME_TOTAL).
var share := TOTAL

## Per bone object: {"bone", "object" (sidecar), "source": MeshInstance3D, "faces": MeshInstance3D,
## "lines": MeshInstance3D, "built" (TmdFaceGroups.build), "meshes": {share: ArrayMesh}, "share",
## "grey"}.
var _objects: Array[Dictionary] = []
var _line_material: StandardMaterial3D


func _init() -> void:
	_line_material = StandardMaterial3D.new()
	_line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_material.vertex_color_use_as_albedo = true
	_line_material.vertex_color_is_srgb = true


## Per TMD object index, one material per face: the model's surface whose glTF primitive lists the
## face's packet offset (the primitive's extras.psx_primitive_offsets; surface k = primitive k),
## single-sided (A10). Objects without a mesh: an empty list.
static func face_materials(model: Node3D, sidecar: Dictionary, gltf: Dictionary) -> Array:
	var objects: Array = sidecar.get("tmd", {}).get("objects", [])
	var out := []
	out.resize(objects.size())
	for i in objects.size():
		out[i] = []
	for node: Dictionary in gltf.get("nodes", []):
		var o := _object_index(node)
		if o < 0 or o >= objects.size() or not node.has("mesh"):
			continue
		var mesh_instance := _mesh_instance(model, str(node.get("name", "")))
		if mesh_instance == null:
			continue
		var surface_of := {}
		var prims: Array = gltf["meshes"][int(node["mesh"])].get("primitives", [])
		for k in prims.size():
			for offset in prims[k].get("extras", {}).get("psx_primitive_offsets", []):
				surface_of[int(offset)] = k
		var cache := {}
		var mats: Array = []
		for face: Dictionary in objects[o].get("primitives", []):
			var k: int = surface_of.get(int(face.get("offset", -1)), -1)
			if k < 0 or k >= mesh_instance.get_surface_override_material_count():
				mats.append(null)
				continue
			if not cache.has(k):
				cache[k] = PsxLit.single_sided(mesh_instance.get_active_material(k))
			mats.append(cache[k])
		out[o] = mats
	return out


## The glTF node's TMD object: a Digimon's bone node (extras.object; null for a bone without one),
## a plain TMD's object node (extras.index); -1 none.
static func _object_index(node: Dictionary) -> int:
	var extras: Dictionary = node.get("extras", {})
	for key in ["object", "index"]:
		var v: Variant = extras.get(key)
		if v is int or v is float:
			return int(v)
	return -1


static func _mesh_instance(model: Node3D, node_name: String) -> MeshInstance3D:
	if node_name == "":
		return null
	for n in model.find_children(node_name, "MeshInstance3D", true, false):
		return n as MeshInstance3D
	return null


## Builds the wireframe meshes for the model's bone objects (all at share 16: hidden).
func attach(model: Node3D, sidecar: Dictionary, gltf: Dictionary) -> void:
	detach()
	var mats := face_materials(model, sidecar, gltf)
	var objects: Array = sidecar.get("tmd", {}).get("objects", [])
	for node: Dictionary in gltf.get("nodes", []):
		var o := _object_index(node)
		if o < 0 or o >= objects.size() or not node.has("mesh"):
			continue
		var source := _mesh_instance(model, str(node.get("name", "")))
		if source == null or source.get_parent() == null:
			continue
		var typed: Array[Material] = []
		for m in mats[o]:
			typed.append(m)
		var built := TmdFaceGroups.build(objects[o], typed, false)
		var faces := MeshInstance3D.new()
		faces.name = "WireFaces"
		faces.transform = source.transform
		faces.visible = false
		var lines := MeshInstance3D.new()
		lines.name = "WireLines"
		lines.transform = source.transform
		lines.mesh = ImmediateMesh.new()
		lines.visible = false
		source.get_parent().add_child(faces)
		source.get_parent().add_child(lines)
		_objects.append({"bone": int(node.get("extras", {}).get("bone", o)), "object": objects[o], "source": source,
				"faces": faces, "lines": lines, "built": built, "mats": mats[o], "meshes": {}, "share": TOTAL, "grey": 0})
	share = TOTAL


func detach() -> void:
	for e in _objects:
		for key in ["faces", "lines"]:
			if is_instance_valid(e[key]):
				e[key].queue_free()
		if is_instance_valid(e["source"]):
			e["source"].visible = true
	_objects.clear()
	share = TOTAL


func is_attached() -> bool:
	return not _objects.is_empty()


## DOOA_spawnShardWave's bones (F1, F2): bones 2 .. boneCount - 1 with an object, in order, each
## {"bone", "object", "vertices": Array[Vector3i]} with the object's vertices in this frame's pose
## (PSX world units).
func posed_bones() -> Array:
	var out := []
	for e in _objects:
		if int(e["bone"]) < 2 or not is_instance_valid(e["source"]):
			continue
		var xf: Transform3D = (e["source"] as Node3D).global_transform
		var verts: Array[Vector3i] = []
		for v in e["object"].get("vertices", []):
			var g: Vector3 = xf * Content.psx_to_godot(v)
			verts.append(Vector3i(roundi(g.x), roundi(-g.y), roundi(-g.z)))
		out.append({"bone": e["bone"], "object": e["object"], "vertices": verts})
	out.sort_custom(func(a, b): return a["bone"] < b["bone"])
	return out


## One bone's object in this frame's pose (EVL_buildShardSet, evl.c:1047-1112; specs/evolution_scene.md
## E2, E3): {"bone", "object", "vertices", "normals"}, each an Array of Vector3i in PSX world units:
## the vertices through the bone's global transform, the normals through its basis only (the C's
## ApplyMatrixSV with the bone matrix: rotation and scale, no translation). {} if the bone has no
## object.
func posed_bone(bone: int) -> Dictionary:
	for e in _objects:
		if int(e["bone"]) != bone or not is_instance_valid(e["source"]):
			continue
		var xf: Transform3D = (e["source"] as Node3D).global_transform
		var verts := []
		for v in e["object"].get("vertices", []):
			var g: Vector3 = xf * Content.psx_to_godot(v)
			verts.append(Vector3i(roundi(g.x), roundi(-g.y), roundi(-g.z)))
		var normals := []
		for n in e["object"].get("normals", []):
			var g: Vector3 = xf.basis * Content.psx_to_godot(n)
			normals.append(Vector3i(roundi(g.x), roundi(-g.y), roundi(-g.z)))
		return {"bone": bone, "object": e["object"], "vertices": verts, "normals": normals}
	return {}


## The material of each face of bone `bone`'s object (the shards' textures), or [].
func bone_materials(bone: int) -> Array:
	for e in _objects:
		if e["bone"] == bone:
			return e["mats"]
	return []


## PARTNER_WIREFRAME_TOTAL, or (total 16) PARTNER_WIREFRAME_SUB[bone] (A3).
func set_share(total: int, sub := PackedInt32Array()) -> void:
	share = total
	for e in _objects:
		var s := total
		if total == TOTAL:
			var bone: int = e["bone"]
			s = sub[bone] if bone < sub.size() else TOTAL
		e["share"] = s
		var wire := s != TOTAL
		if is_instance_valid(e["source"]):
			e["source"].visible = not wire
		e["faces"].visible = wire
		e["lines"].visible = wire
		if wire:
			e["faces"].mesh = _mesh_at(e, s)


## renderWireframed's grey (A5): one rand() per object drawn in wireframe this frame, in bone order.
func roll_greys(min_grey: int, max_grey: int) -> void:
	for e in _objects:
		if e["share"] != TOTAL:
			e["grey"] = min_grey + Rng.rand() % maxi(max_grey - min_grey, 1)


## The textured faces of `s`'s groups (built once per share value).
func _mesh_at(e: Dictionary, s: int) -> ArrayMesh:
	var meshes: Dictionary = e["meshes"]
	if meshes.has(s):
		return meshes[s]
	var shown := TmdFaceGroups.shown(s)
	var mesh := ArrayMesh.new()
	for surface: Dictionary in e["built"]["surfaces"]:
		if int(surface["group"]) in shown:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
			mesh.surface_set_material(mesh.get_surface_count() - 1, surface["material"])
	meshes[s] = mesh
	return mesh


## The outlines, culled against this frame's camera.
func _process(_delta: float) -> void:
	if _objects.is_empty() or share == TOTAL and not _objects.any(func(e): return e["share"] != TOTAL):
		return
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	for e in _objects:
		var mesh: ImmediateMesh = e["lines"].mesh
		mesh.clear_surfaces()
		var s: int = e["share"]
		if s == TOTAL:
			continue
		var object: Dictionary = e["object"]
		var end: int = e["built"]["end"]
		var grey: int = e["grey"]
		var color := Color(grey / 255.0, grey / 255.0, grey / 255.0)
		var xf: Transform3D = e["lines"].global_transform
		var eye := camera.global_position if camera != null else Vector3.ZERO
		var started := false
		for i in end:
			if TmdFaceGroups.TABLE[i & 15] < s:
				continue
			var pts := TmdFaceGroups.outline(object, i)
			# NCLIP of v0 v1 v2: a quad's path is v0 v1 v3 v2 v0, so its v2 is the fourth point.
			var v2 := pts[3] if pts.size() == 5 else pts[2]
			if camera != null and not front_facing(xf * pts[0], xf * pts[1], xf * v2, eye):
				continue
			if not started:
				mesh.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
				started = true
			for k in pts.size() - 1:
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(pts[k])
				mesh.surface_set_color(color)
				mesh.surface_add_vertex(pts[k + 1])
		if started:
			mesh.surface_end()


## RotNclip > 0 (A10) for a face's first three vertices (Godot world space, the PSX order: Godot's
## clockwise front face): its front side faces the eye.
static func front_facing(p0: Vector3, p1: Vector3, p2: Vector3, eye: Vector3) -> bool:
	return (p2 - p0).cross(p1 - p0).dot(eye - p0) > 0.0
