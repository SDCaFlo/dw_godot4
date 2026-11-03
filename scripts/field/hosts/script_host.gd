class_name ScriptHost
extends Node
## The map's scripts and the text on screen (specs/script.md, specs/text.md, specs/scenes.md
## §4.2): the text area, the six UI boxes and the tamer's message boxes, the script state, the text
## boxes, the interpreter, the map name of a map change; talking to NPCs. Ticked by the field's
## frame order (Field._frame); the field wires the interpreter's map hooks to the MapSession.

## A line for the help line (the instructions not ported yet).
signal message(text: String)

## Set by the field before start.
var field_map: FieldMap
var camera: Camera3D
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var clock: Clock
var map_items: MapItems
var map_chests: MapChests
var map_props: MapProps

## The text area and the six UI boxes everything that shows text shares (specs/text.md); the field
## puts the boxes and the map name into the HUD. All null without the game data.
var text_area: TextArea
var boxes: UIBoxes
## The script state, the text boxes, the interpreter (specs/script.md).
var script_ctx: ScriptContext
var textboxes: TextBoxes
var interpreter: ScriptInterpreter
## The map name during a map change.
var map_name: MapName
## The dust clouds of the training stations (CloudFX); the field puts them into the HUD.
var clouds: CloudFX
## The hit sparks of the training stations (ParticleFX); in the HUD too.
var sparks: ParticleFX
## The arena (Arena, builtin 0x06).
var arena: Node
## TALKED_TO_ENTITY: the entity (2-9) of the last NPC talk.
var talked_to_entity := 0


## The text area, the UI boxes and the tamer's message box (specs/text.md), the interpreter. The
## boxes run their frame after the tamer, the partner and the script, which open and close them.
func start() -> void:
	if not GameData.available():
		return
	text_area = TextArea.new(GameData, GameData.language)
	boxes = UIBoxes.new()
	script_ctx = ScriptContext.new()
	script_ctx.game_state = GameState
	script_ctx.data = GameData
	script_ctx.entity_screen_position = _entity_screen_position
	textboxes = TextBoxes.new(boxes, text_area, script_ctx, GameLoop.pad, GameData, GameState)
	GameData.language_changed.connect(func(_lang):
		text_area.set_language(GameData, GameData.language)
		textboxes.set_language(GameData.language))
	script_ctx.world_screen_position = func(p: Array):
		var s := FieldMap.unproject(camera, Content.psx_to_godot(p))
		return Vector2i(roundi(s.x) - 160, roundi(s.y) - 120)
	interpreter = ScriptInterpreter.new(script_ctx, ScriptFiles.new(), textboxes)
	interpreter.game_state = GameState
	interpreter.data = GameData
	interpreter.clock = clock
	interpreter.tamer = tamer
	interpreter.partner = partner
	interpreter.entities = entities
	interpreter.field = field_map
	interpreter.pad = GameLoop.pad
	interpreter.sound = Sound
	# The windows' and text boxes' sounds (ui.c:223, :336; script_textbox.c): playSound(0, id).
	boxes.sound.connect(func(id: int): Sound.play_sound(0, id))
	textboxes.sound.connect(func(id: int): Sound.play_sound(0, id))
	if partner != null:
		partner.data = GameData
		partner.script_ctx = script_ctx
	script_ctx.entity_type = _entity_type
	interpreter.unported.connect(func(_op, what): message.emit("script: not ported yet: " + what))
	map_name = MapName.new()
	map_name.name = "MapName"
	map_name.text_area = text_area
	map_name.data = GameData
	map_name.set_anchors_preset(Control.PRESET_FULL_RECT)
	tamer.show_map_name = func(map_id: int):
		if map_id >= 0:
			map_name.show_name(map_id)
		else:
			map_name.hide_name()
	boxes.name = "UIBoxes"
	boxes.set_anchors_preset(Control.PRESET_FULL_RECT)
	tamer.camera = camera
	tamer.partner = partner
	tamer.clock = clock
	tamer.pad = GameLoop.pad
	tamer.message_box = MessageBox.new(boxes, text_area)
	# The pickup / chest box (renderItemPickupTextbox): box 1 without the arrow.
	tamer.pickup_box = MessageBox.new(boxes, text_area)
	tamer.pickup_box.arrow = false
	tamer.game_state = GameState
	tamer.data = GameData
	tamer.sound = Sound
	interpreter.map_items = map_items
	interpreter.map_chests = map_chests
	interpreter.map_props = map_props
	# The ported builtin routines (shops, ...): the Routines node's children (specs/shops.md §3).
	clouds = CloudFX.new()
	clouds.name = "CloudFX"
	clouds.camera = camera
	clouds.field = field_map
	sparks = ParticleFX.new()
	sparks.name = "ParticleFX"
	sparks.camera = camera
	sparks.field = field_map
	var routines := get_node_or_null("Routines") as ScriptRoutines
	if routines != null:
		routines.configure(script_ctx, textboxes, GameState, GameData, Sound)
		routines.interpreter = interpreter
		routines.clouds = clouds
		routines.sparks = sparks
		routines.arena = arena
		interpreter.routines = routines
		for child in routines.get_children():
			if child is NamingRoutines:
				child.guide_screen_position = _type_screen_position


## tickScript (where gameLoop calls it).
func tick_script() -> void:
	if interpreter != null:
		interpreter.tick_script()


## The routines' objects (the training stations), the dust and the sparks, one game frame.
func tick_objects() -> void:
	if interpreter != null and interpreter.routines != null:
		interpreter.routines.tick_objects()
	if clouds != null:
		clouds.tick()
	if sparks != null:
		sparks.tick()


## The UI boxes' object pass.
func step_boxes() -> void:
	if boxes != null:
		boxes.step()


## NPCEntityTickOverworld's autotalk (overworld.c:1328): while no script runs, the NPC's section.
func npc_autotalk(npc: Npc) -> void:
	if interpreter != null and script_ctx.is_paused:
		talk_to(npc)


## TALKED_TO_ENTITY and callScriptSection(CURRENT_SCRIPT_ID, npc.scriptId, 1).
func talk_to(npc: Npc) -> void:
	talked_to_entity = npc.slot + 2
	script_ctx.talked_to_entity = talked_to_entity
	interpreter.call_section(script_ctx.current_script_id, npc.script_id(), 1)


## setupBoxOrigin's getEntityScreenPos(entity, 1) for a script id: the tamer, the partner, an NPC
## on the map (null without one: the box opens without growing).
func _entity_screen_position(script_id: int):
	if script_id == ScriptContext.OWNER_TAMER:
		return tamer.screen_position()
	if script_id == ScriptContext.OWNER_PARTNER and partner != null:
		var p := FieldMap.unproject(camera, partner.global_position)
		return Vector2i(roundi(p.x) - 160, roundi(p.y) - 120)
	var npc := entities.entity_from_script_id(script_id) if entities != null else null
	if npc is Npc:
		return npc.screen_position(camera)
	return null


## getEntityScreenPos(bone 1) of the last NPC (entities 2-9) of a Digimon type, from the screen
## centre; null without one (the naming boxes' origin, NamingRoutines).
func _type_screen_position(type: int):
	var found = null
	if entities == null:
		return null
	for i in FieldEntities.NPC_SLOTS:
		var npc = entities.npcs[i]
		if npc is Npc and int(entities.slots[i]["type"]) == type:
			found = npc.screen_position(camera)
	return found


## The Digimon type of a script id's entity (the speaker's name): the partner's, an NPC's; -1.
func _entity_type(script_id: int) -> int:
	if script_id == ScriptContext.OWNER_PARTNER:
		return GameData.id_of("digimon/digimon_data", GameState.state["partner"]["digimon"])
	var slot := entities.npc_slot_for_script_id(script_id) if entities != null else -1
	return int(entities.slots[slot]["type"]) if slot >= 0 else -1
