class_name TextBoxes
extends RefCounted
## The text boxes and the dialogue box of the event scripts (script_textbox.c, script_value.c;
## specs/text.md §2.6-2.7): TEXTBOX_DATA's six entries, each paired with the UI box of its id, the
## line buffers that script texts are copied into, drawString2, and the dialogue box (box 0) with
## its pages, "next" arrow and choices.
##
## Each game frame the interpreter calls tick_textbox_handling() (tickScript does, before the
## objects); the UI boxes then run the box's tick (tick_script_dialogue_box) and render. The
## interpreter's globals are in `ctx` (ScriptContext).

## playSound(0, id): 2 cursor, 3 confirm, 4 cancel, 11 refused.
signal sound(id: int)

const COUNT := 6
## TEXTBOX_LINE_SIZE (include/dw/script.h:223): bytes per text-area row.
const LINE_SIZES := {"en_eu": 80}
const LINE_SIZE := 64
## TEXTBOX_LINES_BUFFER: one line per text-area row.
const LINE_ROWS := 22
const ROW_HEIGHT := 12
## TextBoxData.flags.
const FLAG_OPEN := 0x1
const FLAG_CLOSE_ANIMATED := 0x40
const FLAG_OPEN_ANIMATED := 0x80
## setupDialogueBox (script_textbox.c:912).
const DIALOGUE_RECT := Rect2i(-0x82, 0x2A, 0x106, 0x3B)
const DIALOGUE_FLAGS := 0x21
## Speaker line colours (showTextbox).
const SPEAKER_COLOURS := {ScriptContext.OWNER_TAMER: 6, ScriptContext.OWNER_PARTNER: 0xA}
const SPECIAL_COLOUR := 5
const NPC_COLOUR := 7
## drawString2's US tab codes: clear that many pixels from x + pos (0x16: from x + pos - 6), then
## pos = the same value.
const TAB_STOPS := {0x16: 0x69, 0x17: 0x69, 0x18: 0x60, 0x19: 0x9C, 0x1A: 0xB4, 0x1B: 0xA0, 0x1C: 0x64}


## TextBoxData (include/dw/ui.h:24).
class Entry:
	var origin := Rect2i()
	var rect := Rect2i()
	var flags := 0
	var write_count := 0
	var render_count := 0
	var flip_count := 0
	var registered := 1
	var page_ready := 0
	var idle := 0
	var double_buffered := 0
	var back_page := 0
	var vram_mode := 0
	var vram_row := 0
	var vram_rows := 0
	var write_row := 0
	## The UI box's tick / render (UIBoxes.Box.tick, .render, .on_render).
	var tick := Callable()
	var render := Callable()
	var on_render := Callable()


var entries: Array[Entry] = []
## TEXTBOX_DATA.usedRows.
var used_rows := 0
## TEXTBOX_LINES_BUFFER.
var lines := PackedByteArray()
var line_size := LINE_SIZE
## DELAY_FRAMES, AUTOCLOSE_FRAMES.
var delay_frames := 0
var autoclose_frames := 0
## MAIN_D_80134F94: the "next" arrow is shown this frame.
var arrow_flag := 0
## DRAW_STRING2_IS_FIXED_WIDTH (US): every glyph advances 12.
var fixed_width := false
## MAIN_D_80135028 (setFreshDialogue): input waits until confirm is released.
var fresh_dialogue := 0
## DIALOGUE_SELECTION: count, current, pointer (target table), end_pointer, cursor_width, cursor_offset_y.
var selection := {"count": 0, "current": 0, "pointer": 0, "end_pointer": 0, "cursor_width": 0, "cursor_offset_y": 0}

var boxes: UIBoxes
var text_area: TextArea
var pad: Pad
var ctx: ScriptContext
var data: Node
var game_state: Node
## The scripts (the MAPHEAD script's lines for the builtin routines); set by the interpreter.
var files: ScriptFiles


func _init(ui_boxes: UIBoxes, area: TextArea, script_ctx: ScriptContext, game_pad: Pad, game_data: Node, state: Node) -> void:
	boxes = ui_boxes
	text_area = area
	ctx = script_ctx
	pad = game_pad
	data = game_data
	game_state = state
	for i in COUNT:
		entries.append(Entry.new())
	set_language(area.font.language if area != null else "en_us")


func set_language(lang: String) -> void:
	line_size = LINE_SIZES.get(lang, LINE_SIZE)
	lines.resize(LINE_ROWS * line_size)
	lines.fill(0)


# --- the entries (script_textbox.c:412-641) --------------------------------------------------------

## initializeTextbox (script_textbox.c:412).
func initialize_textbox() -> void:
	for e in entries:
		e.flags = 0
		e.vram_rows = 0
		e.registered = 1
	used_rows = 0
	delay_frames = 0
	autoclose_frames = 0
	boxes.textbox_open_timer = 0


## getVRAMModeCoords (script_textbox.c:512): [x, width] of a vram mode in the text area.
static func vram_mode_coords(mode: int) -> Array:
	if mode == 0:
		return [0, 0xFF]
	if mode == 1:
		return [0, 0x7F]
	return [0x80, 0x7F]


## createTextbox (script_textbox.c:562).
func create_textbox(id: int, flags: int, rect: Rect2i, origin: Rect2i, tick: Callable, render: Callable, on_render := Callable()) -> void:
	var e := entries[id]
	if e.flags & 0xF == FLAG_OPEN:
		close_textbox(id)
	e.flags = flags
	e.rect = rect
	e.origin = origin
	e.tick = tick
	e.render = render
	e.on_render = on_render
	set_fresh_dialogue()


## registerTextbox (script_textbox.c:603).
func register_textbox(id: int, row: int, rows: int, double_buffer: int, mode: int) -> void:
	var e := entries[id]
	e.vram_row = row
	e.vram_rows = rows
	e.write_row = 0
	e.vram_mode = mode
	e.back_page = 0
	e.double_buffered = double_buffer
	e.write_count = 0
	e.render_count = 0
	e.flip_count = 0
	e.registered = 1
	e.page_ready = 0
	e.idle = 1
	var rows_used := e.vram_rows << 1 if e.double_buffered == 1 else e.vram_rows
	used_rows += rows_used
	text_area.set_text_color(1)
	var coords := vram_mode_coords(e.vram_mode)
	text_area.clear(Rect2i(coords[0], e.vram_row * ROW_HEIGHT, coords[1], rows_used * ROW_HEIGHT))


## clearTextboxLineCount (script_textbox.c:207).
func clear_textbox_line_count(id: int) -> void:
	var e := entries[id]
	var rows := e.vram_rows << 1 if e.double_buffered == 1 else e.vram_rows
	e.vram_rows = 0
	e.registered = 1
	used_rows -= rows


## closeTextbox (script_textbox.c:527): only an open (or opening) UI box.
func close_textbox(id: int, target = null) -> void:
	var state := boxes.boxes[id].state
	if state != UIBoxes.STATE_CLOSED and state != UIBoxes.STATE_CLOSING:
		if entries[id].flags & FLAG_CLOSE_ANIMATED == 0:
			boxes.remove_static(id)
		else:
			boxes.remove_animated(id, target)
		clear_textbox_line_count(id)


## triggerBoxCloseFlag (script_textbox.c:589): the entry no longer wants its box open.
func trigger_box_close_flag(id: int) -> void:
	var e := entries[id]
	if e.flags & 0xF != 0:
		e.flags &= 0xF0


## closeBox (script_textbox.c:855).
func close_box(id: int) -> void:
	trigger_box_close_flag(id)
	close_textbox(id)


## closeAllTextboxes (script_textbox.c:543).
func close_all_textboxes() -> void:
	for i in COUNT:
		var flags := entries[i].flags
		if flags & 0xF != 0:
			if flags & FLAG_CLOSE_ANIMATED:
				ctx.active_instruction = ScriptContext.INSTRUCTION_ENDED
				ctx.is_paused = false
			close_box(i)


## setFreshDialogue / isXPressedAfterDialogue (script_common.c:1305): after a new box, input counts
## only once confirm has been released.
func set_fresh_dialogue() -> void:
	fresh_dialogue = 1


func is_x_pressed_after_dialogue() -> bool:
	if fresh_dialogue != 0:
		if pad.polled & Pad.CONFIRM != 0:
			return false
		fresh_dialogue = 0
	return true


# --- each frame (script_textbox.c:430) --------------------------------------------------------------

## tickTextboxHandling: new texts are drawn into their pages, one line a frame, and the UI boxes
## follow the entries' wanted state.
func tick_textbox_handling() -> void:
	if ctx.active_instruction == ScriptContext.INSTRUCTION_ENDED:
		# The C loop: setTextColor(1) and IS_SCRIPT_PAUSED for each box until one is still shown.
		for i in COUNT:
			if boxes.boxes[i].state != UIBoxes.STATE_CLOSED:
				break
			text_area.set_text_color(1)
			ctx.is_paused = true
		return
	var drew := 0
	for i in COUNT:
		var e := entries[i]
		if e.vram_rows == 0:
			continue
		if e.registered == 1 and e.write_count != e.render_count:
			if e.double_buffered == 1:
				e.write_row = (e.back_page ^ 1) * e.vram_rows
				var coords := vram_mode_coords(e.vram_mode)
				text_area.clear(Rect2i(coords[0], (e.vram_row + e.write_row) * ROW_HEIGHT, coords[1], e.vram_rows * ROW_HEIGHT))
				e.registered = 0
			else:
				e.write_row = 0
				e.registered = 0
		if drew == 0 and e.registered == 0:
			drew = draw_textbox_strings(i)
		var ui := boxes.boxes[i]
		if e.flags & 0xF != ui.state:
			if e.flags & 0xF == FLAG_OPEN:
				if e.registered == 1 and ui.state == UIBoxes.STATE_CLOSED:
					var features := (e.flags >> 4) & 3
					var color := 1 if features == 0 else 0
					if e.flags & FLAG_OPEN_ANIMATED == 0:
						boxes.create_static(i, color, features, e.rect, e.tick, e.render, e.on_render)
					else:
						boxes.create_animated(i, color, features, e.rect, e.origin, e.tick, e.render, e.on_render)
			elif ui.state == UIBoxes.STATE_OPEN:
				close_textbox(i)
	if delay_frames != 0:
		delay_frames -= 1
	if autoclose_frames != 0:
		autoclose_frames -= 1
	boxes.textbox_open_timer = (boxes.textbox_open_timer + 1) & 0xFF
	arrow_flag = 0


## drawTextboxStrings (script_textbox.c:147): the next line(s) of an entry's text; at its end the
## page is complete.
func draw_textbox_strings(id: int) -> int:
	var e := entries[id]
	if e.write_count == e.render_count:
		return 0
	var coords := vram_mode_coords(e.vram_mode)
	var px: int = coords[0]
	var row := e.vram_row + e.write_row
	var offset := row * line_size + (line_size / 2 if px != 0 else 0)
	var y := row * ROW_HEIGHT
	var count := 1 if e.vram_mode == 0 else 2
	while count != 0:
		var done := draw_string2(offset, px, y)
		e.write_row += 1
		if done != 0:
			e.write_count = 1
			e.render_count = 1
			e.flip_count = 0
			e.registered = 1
			break
		y += ROW_HEIGHT
		offset += line_size
		count -= 1
	return 1


## drawString2 (script_textbox.c:644): one line of a line buffer (from `offset`) into the text area
## at (x, y). Returns 1 at the end of the text (00), 0 at the end of the line (0D).
func draw_string2(offset: int, x: int, y: int) -> int:
	var lang := text_area.font.language
	var pos := 0
	var adv := 0
	var i := offset
	while true:
		var ch := _line_byte(i)
		i += 1
		match ch:
			0:
				return 1
			3:
				i += 3
			2:
				i += 1
			1:
				text_area.set_text_color(_line_byte(i))
				i += 1
			0xC:
				i += 1
				var cell := 8 if lang == "en_eu" else 12
				var cells := 13 if lang == "en_eu" else 8
				var rem := pos / cell % cells
				if rem != 0:
					rem = (cells - rem) * cell
					text_area.clear(Rect2i(x + pos, y, rem, ROW_HEIGHT))
					pos += rem
			0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C:
				if lang != "en_us":
					# Not a code outside US: a 2-byte glyph.
					pos = _draw_code((ch << 8) | _line_byte(i), x, y, pos, lang)
					i += 1
					continue
				i += 1
				var stop: int = TAB_STOPS[ch]
				text_area.clear(Rect2i(x + pos - (6 if ch == 0x16 else 0), y, stop, ROW_HEIGHT))
				pos = stop
			0xE:
				i += 1
				var rem := pos / 12 % 0xB
				if rem != 0:
					rem = (0xB - rem) * 12
					text_area.clear(Rect2i(x + pos, y, rem, ROW_HEIGHT))
					pos += rem
			0xF:
				i += 1
				var w := 8 if lang == "en_eu" else 6
				text_area.clear(Rect2i(x + pos, y, w, ROW_HEIGHT))
				pos += w
			0xD:
				return 0
			_:
				var code := 0
				if lang == "en_us" and ch < 0x80:
					code = text_area.font.encode(char(ch), false)[0]
				else:
					code = (ch << 8) | _line_byte(i)
					i += 1
				if code == PsxFont.SPACE:
					var w := 8 if lang == "en_eu" else 12
					text_area.clear(Rect2i(x + pos, y, w, ROW_HEIGHT))
					if lang == "en_eu":
						pos += 8
				else:
					if lang == "en_eu":
						pos += text_area.draw_glyph(code, (x + pos) & 0xFFFF, y)
					elif lang == "ja":
						text_area.draw_glyph(code, (x + pos) & 0xFFFF, y)
					else:
						adv = text_area.draw_glyph(code, (x + pos) & 0xFFFF, y)
						if fixed_width:
							adv = 12
				# US: pos += adv also after the full-width space, with the previous glyph's advance
				# (adv isn't set for it: quirk kept, script_textbox.c:780-804). JP: 12 a glyph.
				if lang == "en_us":
					pos += adv
				elif lang == "ja":
					pos += 12
	return 1


## One 2-byte glyph of a non-US drawString2 (JP: +12; EU: its width).
func _draw_code(code: int, x: int, y: int, pos: int, lang: String) -> int:
	if code == PsxFont.SPACE:
		text_area.clear(Rect2i(x + pos, y, 8 if lang == "en_eu" else 12, ROW_HEIGHT))
		return pos + (8 if lang == "en_eu" else 12)
	var w := text_area.draw_glyph(code, (x + pos) & 0xFFFF, y)
	return pos + (w if lang == "en_eu" else 12)


func _line_byte(i: int) -> int:
	return lines[i] if i >= 0 and i < lines.size() else 0


# --- pages (script_textbox.c:814-910) -----------------------------------------------------------------

## flipTextboxPage (script_common.c:2536): true while the rows are drawn; a finished page flips.
## Where the C falls off its end after the flip (no return value), the port counts that frame busy.
func flip_textbox_page(id: int) -> bool:
	var e := entries[id]
	if e.double_buffered == 0:
		return false
	if e.registered == 0:
		return true
	if e.write_count != e.render_count:
		return true
	if e.page_ready == 0:
		return false
	e.back_page ^= 1
	e.flip_count += 1
	e.page_ready = 0
	return true


## flipIdleTextboxPage (script_textbox.c:814): 1 while the entry is busy (drawing, or flipping now).
func flip_idle_textbox_page(id: int) -> int:
	var e := entries[id]
	if e.double_buffered == 0:
		return 0
	if e.registered == 0:
		return 1
	if e.write_count != e.render_count:
		return 1
	if e.idle == 0:
		return 0
	if e.render_count == 0:
		return 1
	e.idle = 0
	e.back_page ^= 1
	e.flip_count += 1
	if e.page_ready == 0:
		ctx.active_instruction = 0
	boxes.textbox_open_timer = 0
	return 1


## advanceTextbox (script_textbox.c:881): 1 when the last page was confirmed.
func advance_textbox(id: int) -> int:
	var e := entries[id]
	if e.registered == 0:
		return 0
	if e.page_ready == 1:
		if e.render_count != e.flip_count:
			e.back_page ^= 1
		else:
			e.idle = 1
			e.page_ready = 0
			ctx.active_instruction = 0
			return 1
	else:
		e.back_page ^= 1
		ctx.active_instruction = 0
	e.flip_count += 1
	boxes.textbox_open_timer = 0
	return 0


## tickBackgroundDialogue (script_textbox.c:861).
func tick_background_dialogue() -> int:
	var e := entries[0]
	if flip_idle_textbox_page(0) != 0:
		return 0
	if e.render_count == e.flip_count:
		e.idle = 1
		e.page_ready = 0
		return 1
	return 0


# --- showTextbox and its values (script_textbox.c:1054, script_value.c) ---------------------------

## showTextboxReady (script_textbox.c:1275).
func show_textbox_ready(id: int, speaker: int) -> int:
	entries[id].page_ready = 1
	return show_textbox(id, speaker)


## showTextbox (script_textbox.c:1054): the script text at ctx.pointer into the entry's line buffers
## (its back page). Returns the widest line in columns.
func show_textbox(id: int, speaker: int) -> int:
	var e := entries[id]
	var base := e.vram_row * line_size
	if e.vram_mode == 2:
		base += line_size / 2
	if e.double_buffered == 1:
		base += ((e.back_page ^ 1) * e.vram_rows) * line_size
	var out := base
	var col := 0
	var max_col := 0
	var row := 0
	if speaker != ScriptContext.OWNER_NONE:
		out = _put(out, [1, _speaker_colour(speaker)])
		var name_bytes := speaker_name(speaker)
		out = _put(out, name_bytes)
		out = _put(out, [1, 1, 0xD, 0])
		row += 1
		out = base + row * line_size
	while true:
		var ctrl := ctx.next_byte()
		match ctrl:
			3:
				out = _put(out, [ctrl, ctx.next_byte(), ctx.next_byte(), ctx.next_byte()])
			4:
				out = _put(out, int_to_string_sjis(ctx.read_pstat(ctx.next_byte()), 3, 1))
			5:
				ctx.next_byte()
				var b := speaker_name(ScriptContext.OWNER_TAMER)
				out = _put(out, b)
				col += b.size() >> 1
			6:
				ctx.next_byte()
				var b := speaker_name(ScriptContext.OWNER_PARTNER)
				out = _put(out, b)
				col += b.size() >> 1
			7, 8, 9, 17, 18:
				var b := _name_bytes(ctrl, ctx.read_pstat(ctx.next_byte()))
				out = _put(out, b)
				col += b.size() >> 1
			10:
				ctx.next_byte()
				out = _put(out, int_to_string_sjis(int(game_state.state["money"]) if game_state else 0, 6, 0))
			11:
				ctx.next_byte()
				out = _put(out, int_to_string_sjis(int(game_state.state["merit"]) if game_state else 0, 4, 0))
			16:
				ctx.next_byte()
				out = _put(out, int_to_string_sjis(ctx.shop_variable, 5, 1))
			19, 20, 21:
				ctx.next_byte()
				var counter: String = {19: "tournaments_won", 20: "tournament_wins", 21: "tournaments_lost"}[ctrl]
				out = _put(out, int_to_string_sjis(int(game_state.state["counters"][counter]) if game_state else 0, 3, 1))
			12, 14, 1, 2:
				out = _put(out, [ctrl, ctx.next_byte()])
			13:
				out = _put(out, [ctrl, ctx.next_byte()])
				if col > max_col:
					max_col = col
				col = 0
				if ctx.byte_at(ctx.pointer) == 0:
					ctx.pointer += 2
					out -= 2
					_set_line_byte(out, 0)
					if ctx.byte_at(ctx.pointer) != ScriptContext.OP_SHOW_TEXTBOX:
						e.page_ready = 1
					break
				row += 1
				out = base + row * line_size
			_:
				out = _put(out, [ctrl, ctx.next_byte()])
				col += 1
	e.write_count += 1
	ctx.active_instruction = ScriptContext.OP_SHOW_TEXTBOX
	return max_col


func _speaker_colour(speaker: int) -> int:
	if SPEAKER_COLOURS.has(speaker):
		return SPEAKER_COLOURS[speaker]
	return SPECIAL_COLOUR if speaker >= ScriptContext.OWNER_SPECIAL else NPC_COLOUR


func _put(out: int, bytes) -> int:
	for b in bytes:
		_set_line_byte(out, b)
		out += 1
	return out


func _set_line_byte(i: int, b: int) -> void:
	if i >= 0 and i < lines.size():
		lines[i] = b & 0xFF


## getSpeakerName (script_value.c:60) as the C string's bytes.
func speaker_name(speaker: int) -> PackedByteArray:
	var font := text_area.font
	if speaker == ScriptContext.OWNER_NONE:
		return PackedByteArray()
	if speaker == ScriptContext.OWNER_PARTNER:
		return font.to_bytes(str(game_state.state["partner"]["name"]) if game_state else "", true)
	if speaker == ScriptContext.OWNER_TAMER:
		# DIGIMON_NAME(0): the player's name (the savegame's playerName).
		return font.to_bytes(str(game_state.state["tamer"]["name"]) if game_state else "", true)
	if speaker < ScriptContext.OWNER_SPECIAL:
		var type := ctx.type_of(speaker)
		return _name_bytes(7, type) if type >= 0 else PackedByteArray()
	var special: Dictionary = data.find("text/main/script_value", "block", "SPEAKERS")
	var strings: Array = special.get("strings", [])
	var index := speaker - ScriptContext.OWNER_SPECIAL
	if index >= strings.size():
		return PackedByteArray()
	return font.to_bytes(str((strings[index]["text"] as Dictionary).get(data.language, "")))


## The names showTextbox copies: 7 Digimon, 8 technique, 9 item, 17 BGM track, 18 tournament.
func _name_bytes(code: int, id: int) -> PackedByteArray:
	var text := ""
	match code:
		7:
			text = data.localize(data.digimon(id).get("name"))
			if id == 0 and game_state != null:
				return text_area.font.to_bytes(str(game_state.state["tamer"]["name"]), true)
		8:
			text = data.text_entry("main/item", "MOVE_NAMES", id)
		9:
			text = data.localize(data.item(id).get("name"))
		17:
			# BGM_TRACK_NAMES as the C array lists them (systems/jukebox: US has Mt. Panorama's
			# theme at 45 where the other releases have Mt. Infinity's).
			var tracks: Array = data.system("jukebox")
			if id >= 0 and id < tracks.size():
				text = data.localize(tracks[id].get("name"))
		18:
			# TOURNAMENT_NAMES: the same order as its text block (checked against script_common.c:507).
			var block: Dictionary = data.find("text/main/script_common", "block", "TOURNAMENT_NAMES")
			var strings: Array = block.get("strings", [])
			if id >= 0 and id < strings.size():
				text = str((strings[id]["text"] as Dictionary).get(data.language, ""))
	return text_area.font.to_bytes(text)


## intToStringSJIS (script_value.c:97): `digits` full-width digits; leading zeros (but the last)
## are dropped (`skip_zeros`) or become full-width spaces.
static func int_to_string_sjis(value: int, digits: int, skip_zeros: int) -> PackedByteArray:
	var out := PackedByteArray()
	var started := false
	while digits != 0:
		var div := int(pow(10, digits - 1))
		var c := 0x824F + ((value / div) & 0xFFFF)
		value = value % div
		if digits != 1:
			if c == 0x824F:
				if not started:
					if skip_zeros != 0:
						digits -= 1
						continue
					c = PsxFont.SPACE
			else:
				started = true
		out.append(c >> 8)
		out.append(c & 0xFF)
		digits -= 1
	return out


# --- the MAPHEAD lines of the builtin routines (script_common.c:1174-1219, :2431, :2971) ------------

## The shopkeepers' line sections: 0x4C4 + the index of the NPC's Digimon in SHOPKEEP_DIGIMON_TYPES,
## 0x4C4 for another NPC, 0x4CE without one (getShopkeeperLine).
const SHOPKEEPER_SECTION := 0x4C4
const NO_SHOPKEEPER_SECTION := 0x4CE
## A routine's line section 0xFF: the shopkeeper's.
const SECTION_SHOPKEEPER := 0xFF
## showMapHeadTextbox's owner "keep the dialogue owner" (0xFE).
const OWNER_KEEP := 0xFE


## getShopkeeperLine's section: by the Digimon of the NPC in script value 0xFE.
func shopkeeper_section() -> int:
	var owner := ctx.read_pstat(0xFE)
	if owner == 0xFF:
		return NO_SHOPKEEPER_SECTION
	var type := ctx.type_of(owner)
	if type >= 0:
		var keepers: Array = data.shops().get("shopkeepers", [])
		for i in keepers.size():
			if int(keepers[i]["id"]) == type:
				return SHOPKEEPER_SECTION + i
	return SHOPKEEPER_SECTION


## resolveMapHeadEntry: the offset of the text of entry `index` of a MAPHEAD section (its entries
## are JUMP_TOs to SHOW_TEXTBOXes; the text is 2 bytes in), -1 if missing.
func maphead_entry(section: int, index: int) -> int:
	if files == null:
		return -1
	var bytes := files.script(ScriptFiles.MAPHEAD)
	if section == SECTION_SHOPKEEPER:
		section = shopkeeper_section()
	var at := ScriptFiles.section(bytes, section)
	if at < 0 or at + index * 4 + 4 > bytes.size():
		return -1
	return bytes.decode_u16(at + index * 4 + 2) + 2


## Runs `f` with the script pointer on a MAPHEAD line, then puts the pointer back (the C swaps
## SCRIPT_POINTER the same way).
func _at_maphead(section: int, index: int, f: Callable) -> Variant:
	var at := maphead_entry(section, index)
	if at < 0:
		return 0
	var saved_code := ctx.code
	var saved_pointer := ctx.pointer
	ctx.code = files.script(ScriptFiles.MAPHEAD)
	ctx.pointer = at
	var result = f.call()
	ctx.code = saved_code
	ctx.pointer = saved_pointer
	return result


## showMapHeadTextbox (script_common.c:2431): a routine's line into a box (box 0: the dialogue, as
## the owner's); the routine keeps waiting (ACTIVE_INSTRUCTION = CALL_ROUTINE).
func show_maphead_textbox(index: int, owner: int, box_id: int, section := SECTION_SHOPKEEPER) -> void:
	if box_id == 0 and owner != OWNER_KEEP:
		set_dialogue_owner(owner)
	var speaker := ScriptContext.OWNER_NONE if owner == OWNER_KEEP else owner
	_at_maphead(section, index, func(): return show_textbox_ready(box_id, speaker))
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE


## showMapheadSelection (script_common.c:2971): a routine's choice of `count` lines in the dialogue
## box; `keep` = the choice was shown before (SHOP_ACTION_SELECTED: the cursor stays).
func show_maphead_selection(index: int, owner: int, count: int, keep: bool, section := SECTION_SHOPKEEPER) -> void:
	if owner != OWNER_KEEP:
		set_dialogue_owner(owner)
	else:
		ctx.dialogue_owner = ScriptContext.OWNER_NONE
		owner = ScriptContext.OWNER_TAMER
	selection["count"] = count
	if not keep:
		selection["current"] = 0
	var cols: int = _at_maphead(section, index, func(): return show_textbox_ready(0, ctx.dialogue_owner))
	selection["cursor_width"] = cols * text_area.font.glyph_width + 2
	selection["cursor_offset_y"] = 0xD if owner != ScriptContext.OWNER_NONE else 0
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE


# --- the dialogue box (script_textbox.c:112-410, 912-1050) ----------------------------------------

## setupDialogueBox (script_textbox.c:912).
func setup_dialogue_box(owner: int) -> void:
	var flags := DIALOGUE_FLAGS
	var origin = setup_box_origin(owner)
	if origin != null:
		flags |= FLAG_OPEN_ANIMATED
	create_textbox(0, flags, DIALOGUE_RECT, origin if origin != null else Rect2i(), tick_script_dialogue_box,
			render_script_dialogue_box, _on_render_dialogue)
	register_textbox(0, 0, 4, 1, 0)


## setupBoxOrigin (script_textbox.c:929): a 10 x 10 rect at SET_TEXTBOX_ORIGIN's world point (used
## once, 5 px up-left), else at the owner's bone 1 on screen; null without one.
func setup_box_origin(owner: int):
	if owner == ScriptContext.OWNER_NONE:
		return null
	if ctx.textbox_origin != null:
		var origin: Array = ctx.textbox_origin
		ctx.textbox_origin = null
		if ctx.world_screen_position.is_valid():
			var s = ctx.world_screen_position.call(origin)
			if s != null:
				return Rect2i(s.x - 5, s.y - 5, 10, 10)
		return null
	if not ctx.entity_screen_position.is_valid():
		return null
	var p = ctx.entity_screen_position.call(owner)
	if p == null:
		return null
	return Rect2i(p.x, p.y, 10, 10)


## setDialogueOwner (script_common.c:2959).
func set_dialogue_owner(owner: int) -> void:
	if ctx.dialogue_owner != owner:
		ctx.dialogue_owner = owner
		if ctx.pause_game.is_valid():
			ctx.pause_game.call(owner)
		setup_dialogue_box(owner)


## tickScriptDialogueBox (script_textbox.c:957): box 0's tick while it is open.
func tick_script_dialogue_box(_id := 0) -> void:
	match ctx.active_instruction:
		ScriptContext.OP_SET_SELECTION:
			if tick_selection_dialogue() != 0xFFFF:
				ctx.pointer = ctx.u16_at(selection["pointer"] + selection["current"] * 2)
		ScriptContext.OP_SHOW_TEXTBOX:
			tick_confirm_dialogue()
		ScriptContext.OP_CALL_ROUTINE:
			match ctx.textbox_mode:
				1:
					if tick_confirm_dialogue() == 1:
						ctx.state_2 = ctx.next_state_2
						ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
						ctx.textbox_mode = 0
				2:
					if tick_selection_dialogue() != 0xFFFF:
						ctx.state_2 = ctx.next_state_2 + selection["current"]
						ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
						ctx.textbox_mode = 0
				3:
					if tick_background_dialogue() == 1:
						ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
						ctx.textbox_mode = 0


## tickConfirmDialogue (script_textbox.c:280): 1 when the box was advanced.
func tick_confirm_dialogue() -> int:
	if flip_idle_textbox_page(0) != 0:
		return 0
	if ctx.textbox_close_mode == 0:
		arrow_flag = 1
	if not is_x_pressed_after_dialogue():
		return 0
	match ctx.textbox_close_mode:
		0:
			if not pad.is_key_down(Pad.CONFIRM):
				return 0
			if boxes.boxes[0].state != UIBoxes.STATE_OPEN:
				return 0
			sound.emit(3)
			if entries[0].double_buffered == 1:
				advance_textbox(0)
			else:
				ctx.active_instruction = 0
			return 1
		1, 2:
			if ctx.textbox_close_mode == 2 and autoclose_frames != 0:
				return 0
			if entries[0].double_buffered == 1:
				advance_textbox(0)
			else:
				ctx.active_instruction = 0
			return 1
	return 0


## tickSelectionDialogue (script_textbox.c:226): the picked option, or 0xFFFF.
func tick_selection_dialogue() -> int:
	if flip_idle_textbox_page(0) != 0:
		return 0xFFFF
	if not is_x_pressed_after_dialogue():
		return 0xFFFF
	if pad.is_key_down(Pad.CONFIRM):
		advance_textbox(0)
		sound.emit(3)
		return selection["current"]
	if pad.is_key_down(Pad.CANCEL):
		if not ctx.is_trigger_set(ScriptContext.TRIGGER_NO_CANCEL):
			# The C asks who owns the choice before advanceTextbox clears ACTIVE_INSTRUCTION.
			var routine := ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE
			advance_textbox(0)
			sound.emit(4)
			if not routine:
				ctx.pointer = selection["end_pointer"]
				return 0xFFFF
			selection["current"] = selection["count"] - 1
			return selection["current"]
		sound.emit(0xB)
	elif pad.is_key_down(Pad.UP):
		selection["current"] = selection["count"] - 1 if selection["current"] == 0 else selection["current"] - 1
		sound.emit(2)
	elif pad.is_key_down(Pad.DOWN):
		selection["current"] += 1
		if selection["current"] == selection["count"]:
			selection["current"] = 0
		sound.emit(2)
	return 0xFFFF


## scriptShowSelection (script_textbox.c:1017): SET_SELECTION count, targets, text.
func script_show_selection() -> void:
	var count := ctx.next_byte()
	selection["count"] = count
	selection["current"] = 0
	selection["pointer"] = ctx.pointer
	ctx.pointer += (count + 1) * 2
	var width := show_textbox(0, ctx.dialogue_owner) * text_area.font.glyph_width + 2
	if text_area.font.language == "en_us" and width > 0xF0:
		width = 0xF0
	selection["cursor_width"] = width
	ctx.pointer += 2
	selection["end_pointer"] = ctx.pointer
	selection["cursor_offset_y"] = 0xD if ctx.dialogue_owner != ScriptContext.OWNER_NONE else 0
	ctx.active_instruction = ScriptContext.OP_SET_SELECTION


## The "next" arrow when the dialogue waits (renderScriptDialogueBox's renderUIBox(0)).
func _on_render_dialogue(id: int) -> void:
	if arrow_flag != 0:
		boxes.show_next_arrow(id, boxes.textbox_open_timer)


## renderScriptDialogueBox (script_textbox.c:112): the four rows of the shown page, then the
## choice cursor (drawn first: it goes into the ordering table after the text).
func render_script_dialogue_box(canvas: CanvasItem, _id := 0) -> void:
	var e := entries[0]
	var row_px := e.vram_row * ROW_HEIGHT + e.back_page * 48
	var r := boxes.boxes[0].final
	var x := r.position.x + 5
	var y := r.position.y + 4
	if ctx.active_instruction == ScriptContext.OP_SET_SELECTION or \
			(ctx.active_instruction == ScriptContext.OP_CALL_ROUTINE and ctx.textbox_mode == 2):
		render_dialogue_selection_cursor(canvas, x, y)
	for i in 4:
		text_area.render_string(canvas, 0, x, y + 13 * i, 0xFC, 0xC, 0, row_px + 12 * i, true)


## renderDialogueSelectionCursor (script_textbox.c:332).
func render_dialogue_selection_cursor(canvas: CanvasItem, x: int, y: int) -> void:
	if entries[0].idle == 1:
		return
	var cy: int = y + selection["cursor_offset_y"] + selection["current"] * 13
	if text_area.font.language == "en_us":
		cy -= 2
	PsxDraw.selection_cursor(canvas, x - 1, cy, selection["cursor_width"], 0xD)


# --- the custom-sized box (script_textbox.c:351-410, 1248) --------------------------------------------

## scriptSetTextboxSize (script_textbox.c:1248): SET_TEXTBOX_SIZE origin, cols, rows.
func script_set_textbox_size() -> void:
	var origin_id := ctx.next_byte()
	var cols := ctx.next_byte()
	var rows := ctx.next_byte()
	var flags := DIALOGUE_FLAGS
	var origin = setup_box_origin(origin_id)
	if origin != null:
		flags |= FLAG_OPEN_ANIMATED
	var width := (cols * 12 + 10) & 0xFFFF
	var height := (rows * 13 + 7) & 0xFFFF
	var rect := Rect2i((0x140 - width) / 2 - 0xA0, (0xF0 - height) / 2 - 0x78, width, height)
	create_textbox(0, flags, rect, origin if origin != null else Rect2i(), tick_custom_sized_textbox,
			render_custom_sized_textbox)
	register_textbox(0, 0, rows, 1, 0)


## tickCustomSizedTextbox (script_textbox.c:351).
func tick_custom_sized_textbox(_id := 0) -> void:
	if flip_idle_textbox_page(0) != 0:
		return
	if not is_x_pressed_after_dialogue():
		return
	if pad.is_key_down(Pad.CONFIRM):
		if boxes.boxes[0].state != UIBoxes.STATE_OPEN:
			return
		if advance_textbox(0) != 0:
			trigger_box_close_flag(0)
		sound.emit(3)
		return
	if not pad.is_key_down(Pad.CANCEL):
		return
	if boxes.boxes[0].state == UIBoxes.STATE_OPEN:
		# The rest of the text at once.
		var guard := 0
		while entries[0].page_ready == 0 and guard < 64:
			show_textbox(0, ScriptContext.OWNER_NONE)
			guard += 1
		ctx.active_instruction = 0
		entries[0].idle = 1
		trigger_box_close_flag(0)
		sound.emit(4)


## renderCustomSizedTextbox (script_textbox.c:391).
func render_custom_sized_textbox(canvas: CanvasItem, _id := 0) -> void:
	var e := entries[0]
	var page_px := e.vram_rows * ROW_HEIGHT
	var row_px := e.vram_row * ROW_HEIGHT + e.back_page * page_px
	var r := boxes.boxes[0].final
	for i in e.vram_rows:
		text_area.render_string(canvas, 0, r.position.x + 5, r.position.y + 4 + 13 * i, 0xFC, 0xC, 0, row_px + 12 * i, true)
