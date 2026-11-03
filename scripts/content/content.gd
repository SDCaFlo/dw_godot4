@tool
class_name Content
## Asset loader for content packs (specs/content.md §6). For the dw1 pack an asset (a pack-relative
## path such as "mmd_files/MMD0/AGUM.gltf") comes from:
##   1. its Godot-imported copy under res://content/dw1/ if there is one (the editor mirror: made
##      by Project > Tools > "DW: Mirror dw1 assets", gitignored, never exported);
##   2. otherwise the asset porter output (asset_porter/output), loaded from disk at runtime.
## JSON always comes from the porter output. The output folder can be moved with the
## DW_PORTER_OUTPUT environment variable or the "dw/porter/output_dir" project setting.

const SETTING := "dw/porter/output_dir"
const DEFAULT_DIR := "res://asset_porter/output"
const MIRROR_DIR := "res://content/dw1"
## What the mirror copies: [folder of the porter output, patterns of paths inside it]. Models,
## map backgrounds / overviews / doors and cards; not the map object sprite frames (19k files),
## movies, sound or scripts.
const MIRROR := [
	["mmd_files", ["*"]],
	["maps", ["*/background_*.png", "*/overview.png", "*/doors/*"]],
	["card_all", ["*.png"]],
]

## Animation sample rate: the PSX main loop runs one animation tick per frame at 20 fps
## (asset_porter/specs/mmd.md). The import defaults in project.godot use the same rate.
const ANIMATION_FPS := 20.0

## Import settings the mirror writes next to each dw1 model (<file>.gltf.import) before the editor
## imports it, so the imported copy plays exactly like the runtime-loaded one:
## - animations baked at the PSX rate (20 fps, not the default 30);
## - constant tracks kept (dropped tracks leave a bone at the previous animation's pose);
## - the AnimationPlayer optimizer off (it drops keys within ~3 units, coarse for PSX integer
##   data); in Godot it is a per-node option, so it can't be a project-wide default;
## - no LOD / shadow meshes (PSX models are tiny).
## Per file rather than project-wide: models of other packs may use other rates.
const MODEL_IMPORT := """[remap]

importer="scene"
importer_version=1

[params]

meshes/generate_lods=false
meshes/create_shadow_meshes=false
animation/fps=20
animation/remove_immutable_tracks=false
_subresources={
"nodes": {
"PATH:AnimationPlayer": {
"optimizer/enabled": false
}
}
}
"""

## PSX angles: 0x1000 units per turn.
const PSX_TURN := 4096.0


## Folder of the asset porter output.
static func root() -> String:
	var env := OS.get_environment("DW_PORTER_OUTPUT")
	if env != "":
		return env
	return ProjectSettings.globalize_path(ProjectSettings.get_setting(SETTING, DEFAULT_DIR))


## Path of an asset in the porter output.
static func path(rel: String) -> String:
	return root().path_join(rel)


## res:// path of the imported copy, or "" if the asset isn't mirrored and imported.
static func imported(rel: String) -> String:
	var res := MIRROR_DIR.path_join(rel)
	return res if ResourceLoader.exists(res) else ""


static func exists(rel: String) -> bool:
	return imported(rel) != "" or FileAccess.file_exists(path(rel))


static func load_json(rel: String) -> Variant:
	var text := FileAccess.get_file_as_string(path(rel))
	if text == "":
		push_error("Content: cannot read %s (run the asset porter first)" % path(rel))
		return null
	return JSON.parse_string(text)


static func load_texture(rel: String) -> Texture2D:
	if imported(rel) != "":
		return load(imported(rel))
	var image := Image.load_from_file(path(rel))
	if image == null:
		push_error("Content: cannot load image %s" % path(rel))
		return null
	return ImageTexture.create_from_image(image)


## Loads a WAV (sound samples, rendered songs). Godot reads the `smpl` loop but keeps its end as
## stored, which is inclusive: one is added so the loop plays its last sample.
static func load_audio(rel: String) -> AudioStreamWAV:
	var stream: AudioStreamWAV
	if imported(rel) != "":
		# a copy: the imported resource is cached and shared, the loop fix must not add up
		stream = (load(imported(rel)) as AudioStreamWAV).duplicate()
	else:
		stream = AudioStreamWAV.load_from_file(path(rel))
	if stream == null:
		push_error("Content: cannot load audio %s" % path(rel))
		return null
	if stream.loop_mode != AudioStreamWAV.LOOP_DISABLED:
		stream.loop_end += 1
	return stream


## Loads a model as a node tree. Materials get the PSX look (PsxLit): nearest filtering, the field
## lighting on the lit polygons (specs/lighting.md), the semi-transparency of the STP texels
## (asset_porter/specs/tmd.md "STP masks"); unlit opaque ones stay unshaded. Materials and
## animations are per-instance copies, so code may change them (e.g. loop modes) without touching
## imported resources.
static func load_model(rel: String) -> Node3D:
	if imported(rel) != "":
		return instance_model(load(imported(rel)) as PackedScene, rel)
	var scene := _load_gltf(path(rel))
	if scene != null:
		_psx_materials(scene, _material_extras(rel))
	return scene


## load_model's work on an imported scene already loaded (e.g. by ResourceLoader's threaded
## loader): no load() here, so a worker thread may run it on a model not yet in the tree.
static func instance_model(packed: PackedScene, rel: String) -> Node3D:
	if packed == null:
		return null
	var scene := packed.instantiate() as Node3D
	_own_animations(scene)
	_psx_materials(scene, _material_extras(rel))
	return scene


static func _load_gltf(file: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# Textures stay in memory. The default (extract) makes the editor try to copy them into the
	# project for import, which would put game content under a tracked res:// path.
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	var err := document.append_from_file(file, state)
	if err != OK:
		push_error("Content: cannot load glTF %s (error %d)" % [file, err])
		return null
	# Animations are baked at the PSX animation rate (one frame per 20 fps tick, asset_porter
	# specs/mmd.md): the default 30 fps resampling moves values away from the porter's keys.
	# Constant tracks are kept: dropping them leaves a bone at the previous animation's pose.
	var scene := document.generate_scene(state, ANIMATION_FPS, false, false) as Node3D
	_runtime_meshes(scene)
	return scene


## In the editor GLTFDocument builds ImporterMeshInstance3D nodes (the import pipeline's form),
## which don't render: turn them into MeshInstance3D like a running game gets.
static func _runtime_meshes(node: Node) -> void:
	for child in node.get_children():
		_runtime_meshes(child)
	if node is ImporterMeshInstance3D:
		var mesh := MeshInstance3D.new()
		mesh.name = node.name
		mesh.transform = node.transform
		mesh.mesh = node.mesh.get_mesh() if node.mesh != null else null
		mesh.skin = node.skin
		mesh.skeleton = node.skeleton_path
		node.replace_by(mesh)
		node.free()


static func _own_animations(scene: Node) -> void:
	for player in scene.find_children("*", "AnimationPlayer", true, false):
		for lib_name in player.get_animation_library_list():
			var library: AnimationLibrary = player.get_animation_library(lib_name).duplicate(true)
			player.remove_animation_library(lib_name)
			player.add_animation_library(lib_name, library)


## The porter's material extras by material name (the glTF's `materials[].extras`: lit, semi-
## transparent, tpage.abr, stp_texture relative to the glTF), with the STP mask loaded as `stp`.
static func _material_extras(rel: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path(rel)):
		return out
	var gltf = load_json(rel)
	if not gltf is Dictionary:
		return out
	for m in gltf.get("materials", []):
		var extras: Dictionary = (m.get("extras", {}) as Dictionary).duplicate()
		if extras.has("stp_texture"):
			extras["stp"] = load_texture(rel.get_base_dir().path_join(str(extras["stp_texture"])))
		out[str(m.get("name", ""))] = extras
	return out


static func _psx_materials(node: Node, extras: Dictionary) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(i) as BaseMaterial3D
			if material == null:
				continue
			var e: Dictionary = extras.get(material.resource_name, {})
			var lit := material.shading_mode != BaseMaterial3D.SHADING_MODE_UNSHADED
			var stp: Texture2D = e.get("stp")
			var abr := int(e.get("tpage", {}).get("abr", 0)) if e.get("semi_transparent", false) else -1
			if lit or (abr >= 0 and stp != null):
				# A lit TMD polygon (no KHR_materials_unlit), or a semi-transparent one with STP texels.
				node.set_surface_override_material(i, PsxLit.material(material.albedo_texture,
						material.cull_mode == BaseMaterial3D.CULL_DISABLED, 0.5, abr, stp, lit))
				continue
			material = material.duplicate()
			material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			node.set_surface_override_material(i, material)
	for child in node.get_children():
		_psx_materials(child, extras)


## PSX world position (+Y down) to Godot (+Y up): (x, -y, -z), as in the porter's glTF files.
static func psx_to_godot(v: Array) -> Vector3:
	return Vector3(v[0], -v[1], -v[2])


## PSX rotation around Y (rotation.vy, 4096 per turn) to a Godot yaw in radians.
static func psx_yaw(vy: float) -> float:
	return -vy * TAU / PSX_TURN


## A PSX 3x4 matrix (PackedInt32Array) to a Godot Transform3D (specs/map_events.md §4.1.2).
static func psx_transform(m: PackedInt32Array) -> Transform3D:
	var f := [1.0, -1.0, -1.0]
	var cols: Array[Vector3] = []
	for j in 3:
		cols.append(Vector3(f[0] * m[j] * f[j], f[1] * m[3 + j] * f[j], f[2] * m[6 + j] * f[j]) / 4096.0)
	var basis := Basis(cols[0], cols[1], cols[2])
	var origin := psx_to_godot([m[9], m[10], m[11]])
	return Transform3D(basis, origin)



## A Godot basis as a PSX rotation matrix (4096 = 1.0; int16 entries): F · B · F with F the flip
## (x, -y, -z); psx_transform's inverse for the rotation (moved from FieldBattleWorld).
static func psx_matrix(b: Basis) -> PackedInt32Array:
	var f := [1.0, -1.0, -1.0]
	var m := PsxMath.identity()
	for i in 3:
		for j in 3:
			m[i * 3 + j] = PsxMath.s16(roundi(f[i] * b[j][i] * f[j] * 4096.0))
	return m

# --- Editor mirror ---------------------------------------------------------------------------

## Copies the MIRROR selection of the porter output into res://content/dw1/ (new or changed files
## only, by modification time) and writes MODEL_IMPORT for models that have no import file yet.
## Returns {"copied", "unchanged", "missing"}. The editor imports the copies after a filesystem
## scan (the DW tools plugin does both). Delete res://content/dw1/ to rebuild it from scratch.
static func mirror_dw1() -> Dictionary:
	var result := {"copied": 0, "unchanged": 0, "missing": PackedStringArray()}
	var dest_root := ProjectSettings.globalize_path(MIRROR_DIR)
	for rule in MIRROR:
		var folder: String = rule[0]
		if not DirAccess.dir_exists_absolute(path(folder)):
			result["missing"].append(folder)
			continue
		for rel in _files(path(folder), ""):
			if not rule[1].any(func(pattern): return rel.match(pattern)):
				continue
			var src := path(folder).path_join(rel)
			var dst := dest_root.path_join(folder).path_join(rel)
			if dst.ends_with(".gltf") and not FileAccess.file_exists(dst + ".import"):
				DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
				var import_file := FileAccess.open(dst + ".import", FileAccess.WRITE)
				import_file.store_string(MODEL_IMPORT)
				import_file.close()
			if FileAccess.file_exists(dst) and FileAccess.get_modified_time(dst) >= FileAccess.get_modified_time(src):
				result["unchanged"] += 1
				continue
			DirAccess.make_dir_recursive_absolute(dst.get_base_dir())
			if DirAccess.copy_absolute(src, dst) == OK:
				result["copied"] += 1
	return result


static func _files(dir: String, prefix: String) -> PackedStringArray:
	var out := PackedStringArray()
	for file in DirAccess.get_files_at(dir):
		out.append(prefix + file)
	for sub in DirAccess.get_directories_at(dir):
		out.append_array(_files(dir.path_join(sub), prefix + sub + "/"))
	return out
