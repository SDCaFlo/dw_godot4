class_name Release
## The release this build is (specs/distribution.md §4, §6): its version numbers (res://version.json)
## and where an exported game finds the converted dw1 pack.
##
## In the editor (and the headless tests) the content stays where the porters write it
## (asset_porter/output, data_porter/output); in an exported game it is what dw_convert wrote into
## user://content/dw1/ (assets/, data/, content.json, dw_convert/specs/convert.md §2).

const VERSION_FILE := "res://version.json"
## The dw1 pack in an exported game.
const CONTENT_DIR := "user://content/dw1"
## The launcher's settings (the disc image, the update check, the developer tools).
const SETTINGS_FILE := "user://settings.cfg"
## The command-line switch that turns the developer tools on in an exported game.
const DEV_ARG := "--dev"


## True in an exported game (no editor in the binary).
static func exported() -> bool:
	return not OS.has_feature("editor")


## {"game": "0.1.0", "content_format": 1, "mod_api": 0, "repo": "owner/dw_godot4"}; {} if the file is missing.
static func version() -> Dictionary:
	var json = JSON.parse_string(FileAccess.get_file_as_string(VERSION_FILE))
	return json if json is Dictionary else {}


## The release ("0.1.0"), "" if unknown.
static func game() -> String:
	return str(version().get("game", ""))


## The GitHub repository ("owner/name") the launcher checks for releases; "" turns the check off.
static func repo() -> String:
	return str(version().get("repo", ""))


## The shape of dw_convert's output this build reads (dw_convert run.CONTENT_FORMAT).
static func content_format() -> int:
	return int(version().get("content_format", 0))


## The default folder of the asset porter output (Content) or of the data porter output (GameData):
## `sub` is "assets" or "data", `dev_dir` the editor's folder.
static func default_dir(sub: String, dev_dir: String, is_exported: bool = exported()) -> String:
	return CONTENT_DIR.path_join(sub) if is_exported else dev_dir


## The developer tools (the debugger window, the debug keys, the full help line; DebugHost): always
## in the editor; in an exported game only with --dev on the command line or the launcher's
## "Developer tools" setting ([dev] tools=true), so players don't get them (port-only).
static func dev_tools(is_exported: bool = exported(), args: PackedStringArray = OS.get_cmdline_args() + OS.get_cmdline_user_args(),
		settings_path: String = SETTINGS_FILE) -> bool:
	if not is_exported or DEV_ARG in args:
		return true
	var cfg := ConfigFile.new()
	cfg.load(settings_path)   # a missing file leaves it empty
	return bool(cfg.get_value("dev", "tools", false))


## content.json of the converted pack ({} if not converted yet).
static func content_info() -> Dictionary:
	var json = JSON.parse_string(FileAccess.get_file_as_string(CONTENT_DIR.path_join("content.json")))
	return json if json is Dictionary else {}
