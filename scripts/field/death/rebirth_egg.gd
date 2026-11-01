class_name RebirthEgg
extends Node3D
## The rebirth's egg (DOOA_renderRebirth, dooa.c:1169; DOO2_renderWireframeModel, doo2.c:410;
## specs/death_scene.md §3 G, H): the 6 pieces of the chosen egg (TAMA.TMD objects egg × 6 + i) at
## the origin, only the faces whose group is under the threshold (the C builds the outlines but
## never draws them, G3), lit, single-sided. A broken piece is no longer drawn; its fragments
## (EggPieceShards) are drawn by the child `Pieces`. Scene: scenes/field/death/rebirth_egg.tscn.

const MODEL := "tmd_files/ETCDAT/TAMA.gltf"
const SIDECAR := "tmd_files/ETCDAT/TAMA.json"
const PIECES := 6

var slot := -1
var threshold := 0
var _model: Node3D
var _sidecar: Dictionary = {}
var _gltf: Dictionary = {}
## Per piece: {"object", "built", "node": MeshInstance3D, "meshes": {threshold: ArrayMesh}, "shown"}.
var _pieces: Array[Dictionary] = []
var _materials: Array = []
var _pieces_mesh: MeshInstance3D
## The fragments' materials, per texture (half / half, unlit, double-sided: H5).
var _fragment_materials := {}
## A face's texture by its packet offset (unique in the file).
var _texture_by_offset := {}


func _ready() -> void:
	_pieces_mesh = MeshInstance3D.new()
	_pieces_mesh.name = "Pieces"
	_pieces_mesh.mesh = ArrayMesh.new()
	add_child(_pieces_mesh)
	visible = false


func _exit_tree() -> void:
	if _model != null:
		_model.free()
		_model = null


## The egg of `egg_slot`, hidden until the threshold rises.
func load_egg(egg_slot: int) -> void:
	if not Content.exists(MODEL) or not Content.exists(SIDECAR):
		return
	if _model == null:
		_model = Content.load_model(MODEL)
		_sidecar = Content.load_json(SIDECAR)
		_gltf = Content.load_json(MODEL)
		_materials = PartnerWireframe.face_materials(_model, _sidecar, _gltf)
		var objects: Array = _sidecar["tmd"]["objects"]
		for o in objects.size():
			var prims: Array = objects[o]["primitives"]
			for i in prims.size():
				var m: Material = _materials[o][i] if i < _materials[o].size() else null
				var texture: Texture2D = null
				if m is ShaderMaterial:
					texture = (m as ShaderMaterial).get_shader_parameter("albedo_texture")
				elif m is BaseMaterial3D:
					texture = (m as BaseMaterial3D).albedo_texture
				_texture_by_offset[int(prims[i].get("offset", -1))] = texture
	for p in _pieces:
		p["node"].queue_free()
	_pieces.clear()
	slot = egg_slot
	var objects: Array = _sidecar["tmd"]["objects"]
	for i in PIECES:
		var o := egg_slot * PIECES + i
		var typed: Array[Material] = []
		for m in _materials[o]:
			typed.append(m)
		var node := MeshInstance3D.new()
		node.name = "Piece%d" % i
		add_child(node)
		_pieces.append({"object": objects[o], "built": TmdFaceGroups.build(objects[o], typed, false, true),
				"node": node, "meshes": {}, "shown": true})
	set_threshold(0)


## MAIN_D_80135324 (G2).
func set_threshold(t: int) -> void:
	threshold = t
	for p in _pieces:
		p["node"].mesh = _mesh_at(p, t)
	visible = not _pieces.is_empty()


## MAIN_D_80135364[i] == 0 (G8).
func set_piece_shown(i: int, shown: bool) -> void:
	if i >= 0 and i < _pieces.size():
		_pieces[i]["shown"] = shown
		_pieces[i]["node"].visible = shown


## Faces drawn now (the scan's "no egg" check).
func shown_faces() -> int:
	if not visible:
		return 0
	var n := 0
	for p in _pieces:
		if not p["shown"]:
			continue
		for i in int(p["built"]["end"]):
			if TmdFaceGroups.TABLE[i & 15] < threshold:
				n += 1
	return n


## DOO2_renderWireframeModel's grey: one rand() per drawn piece per frame (rolled, unused: G9).
func roll_greys(min_grey: int, max_grey: int, flags: PackedInt32Array) -> void:
	for i in PIECES:
		if i < flags.size() and flags[i] == 0:
			Rng.rand() % maxi(max_grey - min_grey, 1)


func _mesh_at(p: Dictionary, t: int) -> ArrayMesh:
	var meshes: Dictionary = p["meshes"]
	if meshes.has(t):
		return meshes[t]
	var shown := TmdFaceGroups.shown(t)
	var mesh := ArrayMesh.new()
	for surface: Dictionary in p["built"]["surfaces"]:
		if int(surface["group"]) in shown:
			mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface["arrays"])
			mesh.surface_set_material(mesh.get_surface_count() - 1, surface["material"])
	meshes[t] = mesh
	return mesh


## The fragments of the broken pieces (H): flat, half / half, grey (41 - timer) * 74 / 40 + 54.
func draw_pieces(pieces: EggPieceShards) -> void:
	var am := _pieces_mesh.mesh as ArrayMesh
	am.clear_surfaces()
	for s: Dictionary in pieces.sets:
		if int(s["timer"]) < 0:
			continue
		var grey := pieces.grey(s) / 128.0
		var groups := {}
		for f: Dictionary in s["faces"]:
			var texture := _texture_of(f["face"])
			if not groups.has(texture):
				groups[texture] = {"v": [], "uv": []}
			var g: Dictionary = groups[texture]
			var verts := pieces.vertices(s, f)
			var uvs: Array = f["face"].get("uvs", [])
			var order := [0, 1, 2] if verts.size() == 3 else [0, 1, 2, 1, 3, 2]
			for k in order:
				var p: Vector3i = verts[k]
				g["v"].append(Vector3(p.x, -p.y, -p.z))
				var uv: Array = uvs[k] if k < uvs.size() else [0, 0]
				g["uv"].append(Vector2(uv[0], uv[1]) / TmdFaceGroups.PAGE)
		for texture in groups:
			var arrays := []
			arrays.resize(Mesh.ARRAY_MAX)
			arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(groups[texture]["v"])
			arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array(groups[texture]["uv"])
			am.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
			var mat := _fragment_material(texture)
			am.surface_set_material(am.get_surface_count() - 1, mat)
			mat.set_shader_parameter("tint", Vector3(grey, grey, grey))


## The face's texture: its material's, by its packet offset.
func _texture_of(face: Dictionary) -> Texture2D:
	return _texture_by_offset.get(int(face.get("offset", -1)))


func _fragment_material(texture: Texture2D) -> ShaderMaterial:
	if not _fragment_materials.has(texture):
		_fragment_materials[texture] = PsxLit.blended(texture, PsxLit.HALF)
	return _fragment_materials[texture]
