class_name ScriptFiles
extends RefCounted
## The event scripts' bytes (getScript, getScriptSection; script_interp.c:647, :671; specs/script.md
## §2.1): MAPHEAD.SCN is script 0, DG.SCN's scripts 1-222. Rebuilt exactly from the asset porter's
## output (asset_porter/specs/scn.md): the header, every instruction's `raw` at its offset, the
## padding.

const MAPHEAD := 0
const END_OF_TABLE := 0xFFFF

var _cache := {}


## getScript(id): the script's bytes (empty if the asset porter output is missing).
func script(id: int) -> PackedByteArray:
	if _cache.has(id):
		return _cache[id]
	var path := "scripts/MAPHEAD/script.json" if id == MAPHEAD else "scripts/DG/script_%03d.json" % id
	var json = Content.load_json(path)
	var bytes := PackedByteArray()
	if json is Dictionary:
		bytes = build(json)
	_cache[id] = bytes
	return bytes


## The bytes of one script JSON: u16 code_start, the section table, 0xFFFF, the instructions, the
## padding.
static func build(json: Dictionary) -> PackedByteArray:
	var size := int(json["source"]["size"])
	var header: Dictionary = json["header"]
	for ins in json["instructions"]:
		size = maxi(size, int(ins["offset"]) + int(ins["size"]))
	var bytes := PackedByteArray()
	bytes.resize(size)
	bytes.encode_u16(0, int(header["code_start"]))
	var at := 2
	for s in header["sections"]:
		bytes.encode_u16(at, int(s["id"]))
		bytes.encode_u16(at + 2, int(s["offset"]))
		at += 4
	bytes.encode_u16(at, END_OF_TABLE)
	for ins in json["instructions"]:
		_put(bytes, int(ins["offset"]), str(ins["raw"]))
	var padding = json.get("padding")
	if padding is Dictionary:
		_put(bytes, int(padding.get("offset", 0)), str(padding.get("hex", "")))
	return bytes


static func _put(bytes: PackedByteArray, offset: int, hex: String) -> void:
	var raw := hex.hex_decode()
	for i in raw.size():
		if offset + i < bytes.size():
			bytes[offset + i] = raw[i]


## getScriptSection(script, id): the offset of the first section with that id, or -1 (NULL).
static func section(bytes: PackedByteArray, id: int) -> int:
	var at := 2
	while at + 4 <= bytes.size():
		var entry := bytes.decode_u16(at)
		if entry == id:
			return bytes.decode_u16(at + 2)
		if entry == END_OF_TABLE:
			return -1
		at += 4
	return -1


## The map script of a map id, from MAPHEAD's SET_SCRIPT (the asset porter's index), or -1.
static func map_script(map_id: int) -> int:
	var index = Content.load_json("scripts/index.json")
	if index is Dictionary:
		for m in index.get("maps", []):
			if int(m["map"]) == map_id:
				return int(m["script"])
	return -1
