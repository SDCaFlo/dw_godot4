@tool
extends EditorPlugin
## Editor tools for the port (guide: docs/dw_data_dock.md):
## - Project > Tools > "DW: Mirror dw1 assets" copies the models, map backgrounds / doors and cards
##   of the asset porter output into res://content/dw1/ (gitignored) and lets the editor import
##   them: FileSystem thumbnails, drag-and-drop, animation preview, and Content loads the imported
##   copies (specs/content.md §6).
## - The "DW Data" dock browses the content registry (GameData) with model / image previews.

const MENU_MIRROR := "DW: Mirror dw1 assets"
const DataDock := preload("res://addons/dw_tools/data_dock.gd")

var _dock: Control


func _enter_tree() -> void:
	add_tool_menu_item(MENU_MIRROR, _mirror)
	_dock = DataDock.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)


func _exit_tree() -> void:
	remove_tool_menu_item(MENU_MIRROR)
	if _dock != null:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _mirror() -> void:
	if not DirAccess.dir_exists_absolute(Content.root()):
		push_error("DW Tools: no asset porter output in %s (run: python -m dwporter convert all)" % Content.root())
		return
	var result := Content.mirror_dw1()
	print("DW Tools: mirrored dw1 assets into %s: %d copied, %d unchanged%s. Importing new files..." % [
		Content.MIRROR_DIR, result["copied"], result["unchanged"],
		", missing in the output: %s" % ", ".join(result["missing"]) if not result["missing"].is_empty() else ""])
	EditorInterface.get_resource_filesystem().scan()
