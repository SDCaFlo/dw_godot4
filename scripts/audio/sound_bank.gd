class_name SoundBank
extends RefCounted
## A VAB loaded into a slot (specs/sound.md §2.1): the asset porter's bank.json (programs and their
## tones, as libsnd reads them) and its samples, loaded on first use.

## The bank folder in the porter output (e.g. "sound/SS", "sound/ESALL/set_03").
var folder := ""
var master_volume := 127
## program number -> {"volume", "pan", "tones": [tone dictionaries]}
var programs := {}
## vag number -> sample file (porter-output relative, "" when empty)
var sample_files := {}
var _streams := {}


static func from_json(bank_folder: String, json: Dictionary) -> SoundBank:
	var bank := SoundBank.new()
	bank.folder = bank_folder
	bank.master_volume = int(json.get("vab_header", {}).get("master_volume", 127))
	for p in json.get("programs", []):
		bank.programs[int(p["index"])] = {"volume": int(p["volume"]), "pan": int(p["pan"]),
				"tones": p.get("tone_list", [])}
	for s in json.get("samples", []):
		bank.sample_files[int(s["vag"])] = str(s["file"]) if s.get("file") != null else ""
	return bank


static func load_folder(bank_folder: String) -> SoundBank:
	var json = Content.load_json(bank_folder.path_join("bank.json"))
	if not json is Dictionary:
		return null
	return from_json(bank_folder, json)


## The sample of VAG `vag` (null if the bank has none or the file is missing).
func stream(vag: int) -> AudioStreamWAV:
	if not _streams.has(vag):
		var file: String = sample_files.get(vag, "")
		_streams[vag] = Content.load_audio("sound".path_join(file)) if file != "" else null
	return _streams[vag]
