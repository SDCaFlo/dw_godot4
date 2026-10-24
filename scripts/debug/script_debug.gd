class_name ScriptDebug
extends RefCounted
## Debug: runs the sections of the current map's script one after another (key D in the field)
## through the interpreter, so scripts can be checked before their entry points are ported
## (specs/script.md §3.1). Sections below 0x33 are NPC talks (run as events, like checkMapInteraction),
## 0x33-0x6D trigger cells, 0xFE the map entry. Not part of the original.

var interpreter: ScriptInterpreter
var script_id := -1
var map_id := -1
## Section ids of the map's script, in table order, each once.
var sections: Array[int] = []

var _next := 0


## The map's script (MAPHEAD's SET_SCRIPT for the map) and its sections; the interpreter's
## CURRENT_SCRIPT_ID / CURRENT_SCREEN_ID follow it.
func load_map(id: int) -> void:
	map_id = id
	script_id = ScriptFiles.map_script(id)
	sections.clear()
	_next = 0
	if script_id < 0:
		return
	var bytes := interpreter.files.script(script_id)
	var at := 2
	while at + 4 <= bytes.size():
		var section := bytes.decode_u16(at)
		if section == ScriptFiles.END_OF_TABLE:
			break
		if not section in sections:
			sections.append(section)
		at += 4
	interpreter.ctx.current_script_id = script_id
	interpreter.ctx.current_screen_id = id


## Starts the next section (wraps around); a line for the help line.
func play_next() -> String:
	if not interpreter.ctx.is_paused:
		return "script: a section is still running"
	if sections.is_empty():
		return "script: no script for this map"
	var number := _next + 1
	var section := sections[_next]
	_next = (_next + 1) % sections.size()
	var is_event := 1 if section < 0x33 else 0
	interpreter.call_section(script_id, section, is_event)
	return "script %d section 0x%X (%d / %d)" % [script_id, section, number, sections.size()]
