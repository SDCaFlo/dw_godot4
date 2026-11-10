class_name LauncherLogic
extends RefCounted
## The launcher's decisions (specs/distribution.md §5, §6; specs/launcher.md), without the UI so
## the tests can check them: is the converted dw1 pack usable, where dw_convert is, how its
## progress lines read, when to check for updates and whether a release is newer.
## The settings file (user://settings.cfg) holds the disc image path and the update check.

const SETTINGS_FILE := "user://settings.cfg"
## Seconds between two update checks (§6: at most once a day).
const UPDATE_INTERVAL := 24 * 60 * 60
## The GitHub API's latest release of a repository ("owner/name").
const RELEASES_API := "https://api.github.com/repos/%s/releases/latest"
const IMAGE_EXTENSIONS: PackedStringArray = ["cue", "iso", "bin"]

## What the launcher does with a pack folder:
const READY := "ready"            # play
const CONVERT := "convert"        # no usable pack: convert from the remembered image
const ASK_DISC := "ask_disc"      # no usable pack and no image known: ask for one


## {"action": READY / CONVERT / ASK_DISC, "reason": text for the player}.
## content_dir: the pack folder (content.json, assets/, data/); disc_path: the remembered image.
static func decide(content_dir: String, disc_path: String, content_format: int) -> Dictionary:
	var reason := ""
	var info := read_json(content_dir.path_join("content.json"))
	if info.is_empty():
		reason = "The game content hasn't been converted yet."
	elif not DirAccess.dir_exists_absolute(content_dir.path_join("assets")) \
			or not FileAccess.file_exists(content_dir.path_join("data/catalog.json")):
		reason = "The converted game content is incomplete."
	elif int(info.get("content_format", 0)) != content_format:
		reason = "This version reads the game content differently: it has to be converted again."
	elif not info.get("ok", false) and not info.get("accepted", false):
		reason = "The last conversion reported problems."
	else:
		return {"action": READY, "reason": ""}
	var has_disc := disc_path != "" and FileAccess.file_exists(disc_path)
	return {"action": CONVERT if has_disc else ASK_DISC, "reason": reason}


## [fraction 0..1, message] of a "PROGRESS <fraction> <message>" line, [] for other lines.
static func parse_progress(line: String) -> Array:
	if not line.begins_with("PROGRESS "):
		return []
	var parts := line.substr(9).split(" ", true, 1)
	if parts.is_empty() or not parts[0].is_valid_float():
		return []
	return [clampf(parts[0].to_float(), 0.0, 1.0), parts[1] if parts.size() > 1 else ""]


## The command that runs dw_convert: [program, leading arguments...].
## DW_CONVERT (an exe, or a .py run with python) wins; an exported game uses
## tools/dw_convert/dw_convert.exe next to its exe (§4); the editor the built exe in
## dw_convert/dist/, else the source (python dw_convert/dw_convert.py).
static func converter_command(is_exported: bool = Release.exported()) -> PackedStringArray:
	var env := OS.get_environment("DW_CONVERT")
	if env != "":
		return PackedStringArray(["python", env]) if env.get_extension() == "py" else PackedStringArray([env])
	if is_exported:
		return PackedStringArray([OS.get_executable_path().get_base_dir().path_join("tools/dw_convert/dw_convert.exe")])
	var built := ProjectSettings.globalize_path("res://dw_convert/dist/dw_convert/dw_convert.exe")
	if FileAccess.file_exists(built):
		return PackedStringArray([built])
	return PackedStringArray(["python", ProjectSettings.globalize_path("res://dw_convert/dw_convert.py")])


## A disc image in a folder (the exe's, §5 step 1): .cue first, then .iso, then .bin; "" if none.
static func find_image(folder: String) -> String:
	if folder == "" or not DirAccess.dir_exists_absolute(folder):
		return ""
	var files := DirAccess.get_files_at(folder)
	for ext in IMAGE_EXTENSIONS:
		for f in files:
			if f.get_extension().to_lower() == ext:
				return folder.path_join(f)
	return ""


# --- Updates (§6, U1: notify only) -----------------------------------------------------------

## True when the check is on, a repository is set and the last check is a day old.
static func update_due(enabled: bool, repo: String, last_check: int, now: int) -> bool:
	return enabled and repo != "" and now - last_check >= UPDATE_INTERVAL


## {"version", "notes", "url"} of the GitHub API's release JSON; {} if it has no tag.
static func parse_release(json: Variant) -> Dictionary:
	if not json is Dictionary or str(json.get("tag_name", "")) == "":
		return {}
	return {
		"version": str(json["tag_name"]).trim_prefix("v"),
		"notes": str(json.get("body", "")) if json.get("body") != null else "",
		"url": str(json.get("html_url", "")),
	}


## True when version a ("0.2.0", "v0.2.0", "0.2.0-beta") is newer than b. Pre-release suffixes
## are ignored.
static func newer(a: String, b: String) -> bool:
	var pa := _parts(a)
	var pb := _parts(b)
	for i in maxi(pa.size(), pb.size()):
		var x: int = pa[i] if i < pa.size() else 0
		var y: int = pb[i] if i < pb.size() else 0
		if x != y:
			return x > y
	return false


static func _parts(v: String) -> Array[int]:
	var out: Array[int] = []
	for p in v.trim_prefix("v").split("-")[0].split("."):
		out.append(p.to_int())
	return out


# --- Files ------------------------------------------------------------------------------------

static func read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var json = JSON.parse_string(FileAccess.get_file_as_string(path))
	return json if json is Dictionary else {}


static func load_settings(path: String = SETTINGS_FILE) -> ConfigFile:
	var cfg := ConfigFile.new()
	cfg.load(path)   # a missing file leaves it empty
	return cfg


## Deletes a folder and everything in it (an old or a failed pack). Only inside user://.
static func remove_tree(path: String) -> void:
	if not path.begins_with(ProjectSettings.globalize_path("user://")) and not path.begins_with("user://"):
		push_error("LauncherLogic: refusing to delete %s (outside user://)" % path)
		return
	if not DirAccess.dir_exists_absolute(path):
		return
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	for d in DirAccess.get_directories_at(path):
		remove_tree(path.path_join(d))
	DirAccess.remove_absolute(path)


## Moves a finished conversion (new_dir) into place (dir), deleting the old pack. OK or an error.
static func swap_in(new_dir: String, dir: String) -> Error:
	var old := dir + ".old"
	remove_tree(old)
	if DirAccess.dir_exists_absolute(dir):
		var err := DirAccess.rename_absolute(dir, old)
		if err != OK:
			return err
	var err := DirAccess.rename_absolute(new_dir, dir)
	if err != OK:
		return err
	remove_tree(old)
	return OK
