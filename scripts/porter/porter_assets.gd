@tool
class_name PorterAssets
## Runtime access to the asset porter output (asset_porter/output, see asset_porter/CLAUDE.md).
##
## The output is loaded from disk at runtime instead of being imported by Godot: it is
## generated, gitignored and large (asset_porter/.gdignore keeps the editor from importing it).
## Override the folder with the DW_PORTER_OUTPUT environment variable or the
## "dw/porter/output_dir" project setting.

const SETTING := "dw/porter/output_dir"
const DEFAULT_DIR := "res://asset_porter/output"

## PSX angles: 0x1000 units per turn.
const PSX_TURN := 4096.0


static func root() -> String:
	var env := OS.get_environment("DW_PORTER_OUTPUT")
	if env != "":
		return env
	return ProjectSettings.globalize_path(ProjectSettings.get_setting(SETTING, DEFAULT_DIR))


static func path(rel: String) -> String:
	return root().path_join(rel)


static func exists(rel: String) -> bool:
	return FileAccess.file_exists(path(rel))


static func load_json(rel: String) -> Variant:
	var text := FileAccess.get_file_as_string(path(rel))
	if text == "":
		push_error("PorterAssets: cannot read %s (run the asset porter first)" % path(rel))
		return null
	return JSON.parse_string(text)


static func load_texture(rel: String) -> ImageTexture:
	var image := Image.load_from_file(path(rel))
	if image == null:
		push_error("PorterAssets: cannot load image %s" % path(rel))
		return null
	return ImageTexture.create_from_image(image)


## Loads a porter glTF as a node tree. Materials get the PSX look: nearest filtering, unshaded
## (the game's field lighting is not reproduced yet).
static func load_model(rel: String) -> Node3D:
	var document := GLTFDocument.new()
	var state := GLTFState.new()
	# Textures stay in memory. The default (extract) makes the editor try to copy them into the
	# project for import, which would put game content under res://.
	state.handle_binary_image = GLTFState.HANDLE_BINARY_EMBED_AS_UNCOMPRESSED
	var err := document.append_from_file(path(rel), state)
	if err != OK:
		push_error("PorterAssets: cannot load glTF %s (error %d)" % [path(rel), err])
		return null
	var scene := document.generate_scene(state) as Node3D
	_psx_materials(scene)
	return scene


static func _psx_materials(node: Node) -> void:
	if node is MeshInstance3D and node.mesh != null:
		for i in node.mesh.get_surface_count():
			var material := node.mesh.surface_get_material(i) as BaseMaterial3D
			if material != null:
				material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
				material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	for child in node.get_children():
		_psx_materials(child)


## PSX world position (+Y down) to Godot (+Y up): (x, -y, -z), as in the porter's glTF files.
static func psx_to_godot(v: Array) -> Vector3:
	return Vector3(v[0], -v[1], -v[2])


## PSX rotation around Y (rotation.vy, 4096 per turn) to a Godot yaw in radians.
static func psx_yaw(vy: float) -> float:
	return -vy * TAU / PSX_TURN
