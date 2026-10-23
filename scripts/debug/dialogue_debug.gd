class_name DialogueDebug
extends Node
## Debug stand-in for the event-script interpreter's text instructions (key D in the field), so the
## dialogue box can be checked before the interpreter exists (specs/text.md §3). It plays the
## current map's script texts on the real script bytes (asset porter scripts/DG/script_NNN.json),
## one run at a time: SET_DIALOG_OWNER, SHOW_TEXTBOX, SET_SELECTION, SET_TEXTBOX_SIZE and
## SET_TEXTBOX_MODE as the interpreter executes them (script_interp.c); any other instruction ends
## the run and closes the boxes. Not part of the original.

## A run finished: what happened (for the help line).
signal finished(summary: String)

const TEXT_OPS := {"SET_DIALOG_OWNER": true, "SHOW_TEXTBOX": true, "SET_SELECTION": true, "SET_TEXTBOX_SIZE": true,
		"SET_TEXTBOX_MODE": true}

var textboxes: TextBoxes
var ctx: ScriptContext
var tamer: Tamer
## Stopped while a run plays, as a script's scriptPauseGame stops game time.
var clock: Clock
var running := false
## Script offsets where a run of text instructions starts.
var starts: Array[int] = []
var script_name := ""

var _bytes := PackedByteArray()
var _next := 0
## script id -> Digimon type of the map's Digimon (getSpeakerName).
var _types := {}


## The map's script and Digimon (its map.json `digimon`: script_id -> type).
func load_map(map_name: String, map_data: Dictionary) -> void:
	starts.clear()
	_bytes = PackedByteArray()
	_next = 0
	_types.clear()
	for d in map_data.get("digimon", []):
		_types[int(d["script_id"])] = int(d["type"])
	var index = Content.load_json("scripts/index.json")
	if not index is Dictionary:
		return
	var script_id := -1
	for m in index.get("maps", []):
		if m["map_name"] == map_name:
			script_id = int(m["script"])
	if script_id < 0:
		return
	script_name = "script_%03d" % script_id
	var script_json = Content.load_json("scripts/DG/%s.json" % script_name)
	if not script_json is Dictionary:
		return
	var instructions: Array = script_json["instructions"]
	var size := 0
	for ins in instructions:
		size = maxi(size, int(ins["offset"]) + int(ins["size"]))
	_bytes.resize(size)
	var previous_is_text := false
	var run_start := -1
	var run_has_text := false
	for ins in instructions:
		var raw := str(ins["raw"]).hex_decode()
		var offset := int(ins["offset"])
		for i in raw.size():
			_bytes[offset + i] = raw[i]
		var is_text: bool = TEXT_OPS.has(ins["name"])
		if is_text and not previous_is_text:
			run_start = offset
			run_has_text = false
		if is_text and ins["name"] in ["SHOW_TEXTBOX", "SET_SELECTION"]:
			if not run_has_text:
				starts.append(run_start)
			run_has_text = true
		previous_is_text = is_text


## Starts the next run of the map's texts (wraps around).
func play_next() -> String:
	if running:
		return "dialogue: already playing"
	if starts.is_empty():
		return "dialogue: no script texts on this map"
	var number := _next + 1
	var start := starts[_next]
	_next = (_next + 1) % starts.size()
	ctx.code = _bytes
	ctx.pointer = start
	ctx.active_instruction = 0
	ctx.text_owner_mode = 0
	ctx.textbox_close_mode = 0
	ctx.is_paused = false
	ctx.entity_type = func(script_id: int) -> int: return _types.get(script_id, -1)
	textboxes.initialize_textbox()
	# callScriptSection starts with the tamer as the owner; in the game an earlier
	# SET_DIALOG_OWNER has set the box up, here a run may start with the text itself.
	ctx.dialogue_owner = 0xFE
	if ctx.byte_at(start) != ScriptContext.OP_SET_DIALOG_OWNER:
		textboxes.set_dialogue_owner(ScriptContext.OWNER_TAMER)
	if tamer != null:
		tamer.set_state(Tamer.STATE_STILL)
	if clock != null:
		clock.running = false
	running = true
	return "dialogue %d / %d (%s @%d)" % [number, starts.size(), script_name, start]


## One game frame of tickScript: tickTextboxHandling, then the instructions while none waits.
func tick() -> void:
	if not running:
		return
	textboxes.tick_textbox_handling()
	var guard := 0
	while running and ctx.active_instruction == 0 and guard < 16:
		_step()
		guard += 1


func _step() -> void:
	var op := ctx.byte_at(ctx.pointer)
	match op:
		ScriptContext.OP_SET_DIALOG_OWNER:
			ctx.pointer += 1
			var owner := ctx.next_byte()
			ctx.text_owner_mode = 0
			if textboxes.boxes.boxes[0].state != UIBoxes.STATE_OPEN:
				ctx.dialogue_owner = (owner - 1) & 0xFF
			textboxes.set_dialogue_owner(owner)
		ScriptContext.OP_SHOW_TEXTBOX:
			ctx.pointer += 2
			textboxes.show_textbox(0, ScriptContext.OWNER_NONE if ctx.text_owner_mode == 2 else ctx.dialogue_owner)
		ScriptContext.OP_SET_SELECTION:
			ctx.pointer += 1
			textboxes.script_show_selection()
		ScriptContext.OP_SET_TEXTBOX_SIZE:
			ctx.pointer += 1
			textboxes.script_set_textbox_size()
		ScriptContext.OP_SET_TEXTBOX_MODE:
			ctx.pointer += 2
			var mode := ctx.next_byte()
			var frames := ctx.next_byte()
			ctx.textbox_close_mode = mode
			if mode == 2:
				textboxes.autoclose_frames = frames
		_:
			_end("dialogue: ended at instruction 0x%02X (offset %d), option %d" % [op, ctx.pointer,
					textboxes.selection["current"]])


func _end(summary: String) -> void:
	textboxes.close_all_textboxes()
	running = false
	if tamer != null:
		tamer.set_state(Tamer.STATE_FREE)
	if clock != null:
		clock.running = true
	finished.emit(summary)
