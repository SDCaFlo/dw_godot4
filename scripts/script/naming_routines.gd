class_name NamingRoutines
extends MenuRoutines
## Builtin 0x20, the naming screen, and the new game's questions (initializeNamingBuffer,
## newGameStateMachine, shop/script_menu.c:1122-1294; specs/new_game.md §2.3-2.5). The script runs
## it with script value 0xFE as its flags (3: rename the partner); NewGameScene runs the same
## machine from step 0 (new_game_tick). The naming screen is a NamingBox. A child of ScriptRoutines
## (scenes/script/naming_routines.tscn).

const NAMING := 0x20
var routines: Array = [NAMING]

## Jijimon's lines (MAPHEAD section 0x4D6) and their box (setupNewGameDialogueBox).
const SECTION := 0x4D6
const DIALOGUE_RECT := Rect2i(-130, -78, 262, 59)
const DIALOGUE_FLAGS := 0x81
## setInputRepeatMask(0xF000) while the naming screen is open.
const NAMING_REPEAT := Pad.DIRECTIONS
## NAMING_BOX_FLAG bits.
const FLAG_PARTNER := 1
const FLAG_RENAME := 2
## The questions' answer (script value 0xFE: 0 or 1, the partner of systems/new_game).
const ANSWER_VALUE := 0xFE

var naming: NamingBox
## func(digimon type) -> Vector2i or null: the screen position (bone 1, from the screen centre) of
## the last entity 2-9 of that Digimon type (the C's loops over ENTITY_TABLE); the boxes grow from
## it. Set by the host; without it, or without such an entity, the screen centre.
var guide_screen_position := Callable()


func configure(routine_host: ScriptRoutines) -> void:
	super(routine_host)
	naming = NamingBox.new(textboxes, ctx, data)


## initializeNamingBuffer(readPStat(0xFE)).
func start(_routine: int) -> bool:
	initialize_naming_buffer(_owner())
	return true


func tick(_routine: int) -> void:
	if new_game_state_machine():
		ctx.active_instruction = 0


## The intro's setup (newGameScene): initializeNamingBuffer(0).
func new_game_start() -> void:
	initialize_naming_buffer(0)


## One frame of the intro's machine: true once it is done.
func new_game_tick() -> bool:
	return new_game_state_machine()


## initializeNamingBuffer: flags 0 / 1 run the whole intro from step 0; with bit 1 the naming
## screen opens at once (step 0x14) on the current name.
func initialize_naming_buffer(flags: int) -> void:
	if flags & FLAG_RENAME == 0:
		naming.partner = false
		naming.renaming = false
		ctx.state_2 = 0
		naming.buffer = ""
	else:
		textboxes.close_box(0)
		naming.partner = flags & FLAG_PARTNER != 0
		naming.renaming = true
		ctx.state_2 = 0x14
		naming.buffer = to_full_width(_name())
	ctx.active_instruction = ScriptContext.OP_CALL_ROUTINE
	ctx.textbox_mode = 0


## newGameStateMachine: 1 when done (the intro's end, or a renaming once box 1 has closed).
func new_game_state_machine() -> bool:
	match ctx.state_2:
		0:
			# Trigger 49: a choice can't be cancelled while the questions run.
			game_state.set_trigger(ScriptContext.TRIGGER_NO_CANCEL)
			game_state.state["tamer"]["name"] = ""
			_dialogue_box()
			_say(0x10, 2)
		2:
			_say(0x11, 3)
		3:
			_ask(0x12, 4)
		4:
			_say(0x13, 6)
		5:
			_say(0x16, 10)
		6:
			_say(0x14, 7)
		7:
			_ask(0x15, 8)
		8:
			game_state.set_script_value(ANSWER_VALUE, 0)
			ctx.state_2 = 0x11
		9:
			game_state.set_script_value(ANSWER_VALUE, 1)
			ctx.state_2 = 0x11
		10:
			_say(0x17, 0xB)
		0xB:
			_ask(0x18, 8)
		0x11:
			_say(0x19, 0x12)
		0x12:
			_say(0x1A, 0x13)
		0x13:
			textboxes.close_box(0)
			ctx.state_2 = 0x14
		0x14:
			textboxes.pad.set_repeat_mask(NAMING_REPEAT)
			naming.open(_origin())
			ctx.state_2 = 1
		0x15:
			textboxes.pad.set_repeat_mask(0)
			_set_name(from_full_width(naming.buffer))
			naming.close()
			textboxes.fixed_width = false
			ctx.state_2 = 0x16
		0x16:
			if naming.renaming:
				return textboxes.boxes.boxes[NamingBox.SELECTOR_BOX].state == UIBoxes.STATE_CLOSED
			_dialogue_box()
			if not naming.partner:
				_say(0x1B, 0x17)
			else:
				_say(0x1E, 0x1B)
		0x17:
			_ask(0x1C, 0x18)
		0x18:
			_say(0x1D, 0x1A)
		0x19:
			ctx.state_2 = 0x13
		0x1A:
			naming.partner = true
			naming.buffer = ""
			ctx.state_2 = 0x13
		0x1B:
			_ask(0x1C, 0x1C)
		0x1C:
			_say(0x1F, 0x1E)
		0x1D:
			ctx.state_2 = 0x13
		0x1E:
			_say(0x20, 0x1F)
		0x1F:
			textboxes.close_box(0)
			game_state.clear_trigger(ScriptContext.TRIGGER_NO_CANCEL)
			return true
	return false


## setupNewGameDialogueBox: box 0 from the guide, rows 0-3, not fixed width.
func _dialogue_box() -> void:
	textboxes.fixed_width = false
	textboxes.create_textbox(0, DIALOGUE_FLAGS, DIALOGUE_RECT, _origin(), textboxes.tick_script_dialogue_box,
			textboxes.render_script_dialogue_box, textboxes._on_render_dialogue)
	textboxes.register_textbox(0, 0, 4, 1, 0)


## showNewGameDialogue: the line as speaker 0xFE (keep the owner), then mode 1.
func _say(index: int, next: int) -> void:
	textboxes.show_maphead_textbox(index, TextBoxes.OWNER_KEEP, 0, SECTION)
	_then(next)


## showNewGameSelection: two choices, then `next` + the choice (mode 2).
func _ask(index: int, next: int) -> void:
	textboxes.show_maphead_selection(index, TextBoxes.OWNER_KEEP, 2, false, SECTION)
	ctx.state_2 = 1
	ctx.next_state_2 = next
	ctx.textbox_mode = 2


## The boxes' origin: a 10 x 10 rect at the guide's screen position.
func _origin() -> Rect2i:
	var guide := -1
	if data != null:
		var record: Array = data.system("new_game")
		if not record.is_empty():
			guide = int(record[0]["guide"]["id"])
	var p = guide_screen_position.call(guide) if guide_screen_position.is_valid() and guide >= 0 else null
	if p == null:
		p = Vector2i.ZERO
	return Rect2i(p.x, p.y, 10, 10)


func _name() -> String:
	return str(game_state.state["partner" if naming.partner else "tamer"]["name"])


func _set_name(text: String) -> void:
	game_state.state["partner" if naming.partner else "tamer"]["name"] = text
	game_state.changed.emit("partner" if naming.partner else "tamer")


## A typed name as the game state keeps it: full-width ASCII becomes ASCII, the full-width space a
## space; other characters (kana) stay. Drawn full width again (PsxFont.to_bytes(name, true)).
static func from_full_width(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text.unicode_at(i)
		if c >= 0xFF01 and c <= 0xFF5E:
			out += char(c - 0xFEE0)
		elif c == 0x3000:
			out += " "
		else:
			out += text[i]
	return out


## The reverse, for a name the naming screen starts from (renaming), at most 6 letters.
static func to_full_width(text: String) -> String:
	var out := ""
	for i in mini(text.length(), NamingBox.LETTERS):
		var c := text.unicode_at(i)
		if c >= 0x21 and c <= 0x7E:
			out += char(c + 0xFEE0)
		elif c == 0x20:
			out += NamingBox.SPACE
		else:
			out += text[i]
	return out
