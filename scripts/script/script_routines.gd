class_name ScriptRoutines
extends Node
## The builtin routines of CALL_ROUTINE that are ported (script_interp.c:421-561, :1658-1891;
## specs/shops.md §3): a node under Systems/ScriptHost whose children are the routine nodes. Each
## child lists the builtins it runs (`routines`) and has `start(routine) -> bool` (true: the
## routine waits, ticked each frame until it sets ACTIVE_INSTRUCTION to 0) and `tick(routine)`.
## A mod adds or replaces a builtin with a node here; builtins without one stay unported.

## Set by the host (configure).
var ctx: ScriptContext
var textboxes: TextBoxes
var game_state: Node
var data: Node
## The SoundSystem (its `music`: the jukebox); null in tests without one.
var sound: Node
## Set by the host after configure: the interpreter (the training stations walk, pan and move the
## map's sprites through it) and the dust clouds (CloudFX). Null in tests without a field.
var interpreter: ScriptInterpreter
var clouds: CloudFX
## The one script item menu (the C's item menu is global): every routine node uses it, so the bits
## box of builtin 0x0F sees what a later routine buys.
var menu: ItemMenu


## Hands the script state to the routine nodes (after the ScriptHost made it).
func configure(script_ctx: ScriptContext, text_boxes: TextBoxes, state: Node, game_data: Node,
		sound_system: Node = null) -> void:
	ctx = script_ctx
	sound = sound_system
	textboxes = text_boxes
	game_state = state
	data = game_data
	menu = ItemMenu.new(textboxes, game_state, data)
	if sound != null and "music" in sound:
		menu.music = sound.music
	for child in get_children():
		if child.has_method("configure"):
			child.configure(self)


## The routines' objects (the training stations), one game frame: Field._frame calls it after the
## script and the camera's pans.
func tick_objects() -> void:
	for child in get_children():
		if child.has_method("tick_objects"):
			child.tick_objects()


## The node running a builtin (the last child listing it, so a mod's node added later wins).
func node_for(routine: int) -> Node:
	var found: Node = null
	for child in get_children():
		var list = child.get("routines")
		if list is Array and routine in list:
			found = child
	return found


func handles(routine: int) -> bool:
	return ctx != null and node_for(routine) != null


func start(routine: int) -> bool:
	return node_for(routine).start(routine)


func tick(routine: int) -> void:
	node_for(routine).tick(routine)
