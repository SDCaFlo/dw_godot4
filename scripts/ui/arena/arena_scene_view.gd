extends ArenaHudPiece
## The arena's model scenes (specs/arena.md §4.7): versus / draw (DRAW.TMD), win and lose
## (WIN_LOSE.TMD), the champion's letters (CHAMP.TMD), drawn from the tournament's ArenaScenes.
## The C draws them with their own projection and GsWSMATRIX (STD_MODEL_SCENE_MATRIX) into an OT
## sorted at the main OT's layer 4, over the 3D world and under the HUD: here its own SubViewport
## (its camera, the arena's lights through the PsxLit globals) between the bracket and the HUD
## pieces. The lose scene's black columns (layer 5) are this piece's own prims, drawn under the
## viewport. The champion's VRAM column scroll (MoveImage) is a copy of the letters' texture page
## with the columns blitted in.

const MODELS := {"versus": "tmd_files/STDDAT/DRAW.gltf", "result": "tmd_files/STDDAT/WIN_LOSE.gltf",
		"champion": "tmd_files/STDDAT/CHAMP.gltf"}
const OBJECT_COUNTS := {"versus": 4, "result": 8, "champion": 9}
## CHAMP.TMD's texture: page (832, 0) through CLUT row 482, as the porter built it.
const CHAMPION_PAGE := "tmd_files/STDDAT/CHAMP_tex/page_832_0_4bpp_clut_16_482.png"
## STD_initializeChampionScene / STD_tickChampionScene's MoveImage: 6 x 0x30 VRAM words (24 x 48
## texels) to (0x348 + 6i, 0x30), page u 32 + 24i, v 48.
const COLUMN_W := 24
const COLUMN_H := 0x30
const COLUMN_U0 := 32
const COLUMN_V := 0x30
## STD_MODEL_SCENE_MATRIX (std_hud.c:390): x and z scaled 0x1004 / 0x1000, translation z 1000.
const SCENE_SCALE := Vector3(0x1004 / 4096.0, 1.0, 0x1004 / 4096.0)
const SCENE_Z := 1000
const SCENE_MATRIX := [0x1004, 0, 0, 0, 0x1000, 0, 0, 0, 0x1004, 0, 0, SCENE_Z]
## STD_renderLoseScene: the columns 10 wide from (-0xA0, -0x78).
const WIPE_X := -0xA0
const WIPE_Y := -0x78
const WIPE_W := 0xA

var tournament: Object
var champion_source: Image
var champion_image: Image

var _viewport: SubViewport
var _camera: Camera3D
var _root: Node3D
var _models := {}
var _nodes := {}
var _champion_texture: ImageTexture
var _columns: Array = []
## Per kind, per TMD object: its primitives' vertices (the sidecar's), for libgs's drop rule.
var _tmd := {}
## Per MeshInstance3D: its surfaces' arrays, each triangle's TMD primitive, the dropped set drawn.
var _cut := {}
## Per "kind:i": the indexes of the TMD primitives dropped at the last tick.
var _dropped := {}


func _ready() -> void:
	super._ready()
	_build_view()


## The viewport, built once (in _ready, or at the first tick when that comes first: a headless
## SceneTree script ticks before the tree's _ready).
func _build_view() -> void:
	if _viewport != null:
		return
	var container := SubViewportContainer.new()
	container.name = "View"
	container.stretch = true
	container.mouse_filter = MOUSE_FILTER_IGNORE
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = Vector2i(FieldMap.SCREEN)
	_viewport.transparent_bg = true
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)
	_root = Node3D.new()
	_root.scale = SCENE_SCALE
	_viewport.add_child(_root)
	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_HEIGHT
	_camera.position = Content.psx_to_godot([0, 0, -SCENE_Z])
	_viewport.add_child(_camera)
	_camera.current = true
	container.visible = false


func projection() -> int:
	return tournament.scenes.projection() if _scenes() != null else ArenaScenes.PROJECTION_VERSUS


func _scenes() -> ArenaScenes:
	return tournament.scenes if tournament != null else null


## The node of a scene object: kind "versus" (DRAW), "result" (WIN_LOSE), "champion" (CHAMP).
func object_node(kind: String, i: int) -> Node3D:
	_build_view()
	_load(kind)
	var list: Array = _nodes.get(kind, [])
	return list[i] if i < list.size() else null


func tick(_pressed: int) -> void:
	_build_view()
	prims.clear()
	var sc := _scenes()
	var kind := ""
	if sc != null:
		kind = {"versus": "versus", "win": "result", "lose": "result", "champion": "champion"}.get(sc.active, "")
	for k in _models:
		_models[k].visible = k == kind
		if k != kind:
			for n in _nodes[k]:
				if n != null:
					n.visible = false
	get_node("View").visible = kind != ""
	if kind != "":
		_load(kind)
		_models[kind].visible = true
		_place(kind, sc)
		var h := float(sc.projection())
		_camera.set_frustum(FieldMap.SCREEN.y * FieldMap.NEAR / h, Vector2.ZERO, FieldMap.NEAR, FieldMap.FAR)
		if kind == "champion":
			_scroll_columns(sc)
		if sc.active == "lose":
			for i in sc.wipe_heights.size():
				var p := fill(Rect2i(WIPE_X + WIPE_W * i, WIPE_Y, WIPE_W, sc.wipe_heights[i]), Color.BLACK, true)
				p.merge({"kind": "wipe", "index": i})
				prims.append(p)
	queue_redraw()


## setupModelMatrix for each object: translation, RotMatrix, ScaleMatrix; GsDOFF hides it.
func _place(kind: String, sc: ArenaScenes) -> void:
	var nodes: Array = _nodes[kind]
	for i in nodes.size():
		var node: Node3D = nodes[i]
		if node == null:
			continue
		var shown := i < sc.objects.size() and bool(sc.objects[i]["visible"])
		if kind == "result":
			shown = shown and (i < 4) == (sc.active == "win")
		node.visible = shown
		if i >= sc.objects.size():
			continue
		var o: Dictionary = sc.objects[i]
		var loc: Vector3i = o["location"]
		var m := PsxMath.rot_matrix(o["rotation"])
		var sv: Vector3i = o["scale"]
		var scl := [sv.x, sv.y, sv.z]
		for r in 3:
			for c in 3:
				m[r * 3 + c] = m[r * 3 + c] * scl[c] / 4096
		node.transform = Transform3D(_godot_basis(m), Content.psx_to_godot([loc.x, loc.y, loc.z]))
		if shown:
			var lw := PsxMath.trans_matrix(PsxMath.scale_matrix(PsxMath.rot_matrix(o["rotation"]), sv), loc)
			_drop_polygons(kind, i, node, PsxMath.gs_mul_coord0(PackedInt32Array(SCENE_MATRIX), lw), sc.projection())


## The TMD primitives of object i of a kind that the last tick dropped (GsSortObject4J's rule).
func dropped_polygons(kind: String, i: int) -> Array:
	return _dropped.get("%s:%d" % [kind, i], [])


## GsSortObject4J skips each polygon a vertex of which sets the GTE's FLAG bit 31
## (PsxMath.gs_polygon_dropped): e.g. the WIN letters' front faces, held at SZ 175 with h 0x15E until
## they fly back (specs/arena.md §4.7). Dropped triangles become degenerate; rebuilt when the set changes.
func _drop_polygons(kind: String, i: int, node: Node3D, ls: PackedInt32Array, h: int) -> void:
	var objs: Array = _tmd.get(kind, [])
	if i >= objs.size():
		return
	var prims: Array = objs[i]
	var dropped := PackedByteArray()
	dropped.resize(prims.size())
	for p in prims.size():
		dropped[p] = 1 if PsxMath.gs_polygon_dropped(ls, prims[p], h) else 0
	var list := []
	for p in dropped.size():
		if dropped[p] == 1:
			list.append(p)
	_dropped["%s:%d" % [kind, i]] = list
	for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
		if mi is MeshInstance3D and mi.mesh != null:
			_cut_mesh(mi, prims, dropped)


func _cut_mesh(mi: MeshInstance3D, prims: Array, dropped: PackedByteArray) -> void:
	var id := mi.get_instance_id()
	if not _cut.has(id):
		_cut[id] = _triangle_prims(mi.mesh, prims)
	var c: Dictionary = _cut[id]
	if c["drawn"] == dropped:
		return
	c["drawn"] = dropped
	var mats := []
	for s in mi.mesh.get_surface_count():
		mats.append(mi.get_surface_override_material(s))
	var mesh := ArrayMesh.new()
	for s in c["arrays"].size():
		var arrays: Array = c["arrays"][s].duplicate()
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX].duplicate()
		var tri: PackedInt32Array = c["tri"][s]
		for t in tri.size():
			if tri[t] >= 0 and dropped[tri[t]] == 1:
				idx[t * 3 + 1] = idx[t * 3]
				idx[t * 3 + 2] = idx[t * 3]
		arrays[Mesh.ARRAY_INDEX] = idx
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		mesh.surface_set_material(s, c["mesh"].surface_get_material(s))
	mi.mesh = mesh
	for s in mats.size():
		mi.set_surface_override_material(s, mats[s])


## Each triangle of the mesh's surfaces: the TMD primitive holding its three vertices (-1: none).
func _triangle_prims(src: Mesh, prims: Array) -> Dictionary:
	var out := {"mesh": src, "arrays": [], "tri": [], "drawn": PackedByteArray()}
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var pos: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		if idx.is_empty():
			idx = PackedInt32Array(range(pos.size()))
			arrays[Mesh.ARRAY_INDEX] = idx
		var tri := PackedInt32Array()
		for t in idx.size() / 3:
			var found := -1
			for p in prims.size():
				var ok := true
				for k in 3:
					var v := pos[idx[t * 3 + k]]
					if not prims[p].has(Vector3i(roundi(v.x), roundi(-v.y), roundi(-v.z))):
						ok = false
						break
				if ok:
					found = p
					break
			tri.append(found)
		out["arrays"].append(arrays)
		out["tri"].append(tri)
	return out


## A PSX matrix (4096 = 1) as a Godot basis through the porter's flip (x, -y, -z), as EfeView's.
static func _godot_basis(m: PackedInt32Array) -> Basis:
	var f := [1.0, -1.0, -1.0]
	var cols: Array[Vector3] = []
	for j in 3:
		cols.append(Vector3(f[0] * m[j] * f[j], f[1] * m[3 + j] * f[j], f[2] * m[6 + j] * f[j]) / 4096.0)
	return Basis(cols[0], cols[1], cols[2])


func _load(kind: String) -> void:
	if _models.has(kind) or not MODELS.has(kind):
		return
	var model := Content.load_model(MODELS[kind])
	var nodes: Array = []
	if model == null:
		model = Node3D.new()
	model.name = kind.capitalize()
	model.visible = false
	_root.add_child(model)
	_models[kind] = model
	for i in OBJECT_COUNTS[kind]:
		nodes.append(model.find_child("object_%d" % i, true, false))
	_nodes[kind] = nodes
	_tmd[kind] = _tmd_primitives(MODELS[kind].get_basename() + ".json")
	if kind == "champion":
		_prepare_champion(nodes)


## The sidecar's TMD objects: per object, per primitive, its vertices (TMD units, PSX axes).
static func _tmd_primitives(rel: String) -> Array:
	var out := []
	var side: Variant = Content.load_json(rel)
	if not (side is Dictionary) or not side.has("tmd"):
		return out
	for obj in side["tmd"]["objects"]:
		var verts: Array = obj["vertices"]
		var prims := []
		for p in obj["primitives"]:
			var vs := []
			for vi in p["vertices"]:
				var v: Array = verts[int(vi)]
				vs.append(Vector3i(int(v[0]), int(v[1]), int(v[2])))
			prims.append(vs)
		out.append(prims)
	return out


## CHAMP.TMD: each letter's UVs shifted (STD_offsetTMDObjectUVs) and its texture the page copy.
func _prepare_champion(nodes: Array) -> void:
	var tex := Content.load_texture(CHAMPION_PAGE)
	if tex == null:
		return
	champion_source = tex.get_image()
	if champion_source.is_compressed():
		champion_source.decompress()
	champion_source.convert(Image.FORMAT_RGBA8)
	champion_image = champion_source.duplicate()
	_champion_texture = ImageTexture.create_from_image(champion_image)
	_columns = []
	for i in nodes.size():
		var node: Node = nodes[i]
		if node == null:
			continue
		for mi in [node] + node.find_children("*", "MeshInstance3D", true, false):
			if mi is MeshInstance3D:
				_shift_uvs(mi, i)


func _shift_uvs(mi: MeshInstance3D, letter: int) -> void:
	var src := mi.mesh
	if src == null:
		return
	var mesh := ArrayMesh.new()
	var mats := []
	for s in src.get_surface_count():
		var arrays := src.surface_get_arrays(s)
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		for k in uvs.size():
			var uv := ArenaScenes.champion_uv(roundi(uvs[k].x * 256.0), roundi(uvs[k].y * 256.0), letter)
			uvs[k] = Vector2(uv) / 256.0
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		mesh.add_surface_from_arrays(src.surface_get_primitive_type(s), arrays)
		mats.append(mi.get_active_material(s))
	mi.mesh = mesh
	for s in mats.size():
		var m: Material = mats[s]
		if m is ShaderMaterial:
			m = m.duplicate()
			m.set_shader_parameter("albedo_texture", _champion_texture)
		elif m is BaseMaterial3D:
			m = m.duplicate()
			m.albedo_texture = _champion_texture
		mi.set_surface_override_material(s, m)


## The MoveImage columns: column i's 24 x 48 texels from page u `columns[i]`, v 0.
func _scroll_columns(sc: ArenaScenes) -> void:
	if champion_image == null or str(_columns) == str(sc.columns):
		return
	for i in sc.columns.size():
		champion_image.blit_rect(champion_source, Rect2i(sc.columns[i], 0, COLUMN_W, COLUMN_H),
				Vector2i(COLUMN_U0 + COLUMN_W * i, COLUMN_V))
	_columns = sc.columns.duplicate()
	_champion_texture.update(champion_image)
