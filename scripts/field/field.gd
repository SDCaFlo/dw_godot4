@tool
extends Node
## Field scene: one map, the tamer walking on it, warps between maps, the game clock
## (specs/clock.md) with its HUD and the day / evening / night fades.
##
## Debug keys: [ / ] previous / next map, T one hour later, Z the menu's Sleep, C the care panel,
## D the next section of the map's script, L text language, H toggle the help line.
##
## In the editor the scene previews start_map / start_spawn / time_of_day from the porter output
## (pick them in the Inspector). The preview is only in memory: before each save it is cleared
## from the saved nodes, so no game content is written into field.tscn.

@export var start_map := "MAYO04A":
	set(value):
		start_map = value
		_refresh_preview()
@export var start_spawn := 0:
	set(value):
		start_spawn = value
		_refresh_preview()
## Editor preview only: 0 day, 1 evening, 2 night (maps with one palette always show the day).
## In the game the clock decides.
@export_enum("day", "evening", "night") var time_of_day := 0:
	set(value):
		time_of_day = value
		_refresh_preview()
## Debug: a Digimon key (e.g. "dw1:greymon") to use as the partner instead of the game state's.
@export var debug_partner := ""
## Editor only: show the map in the editor viewports.
@export var editor_preview := true:
	set(value):
		editor_preview = value
		_refresh_preview()

var _maps: PackedStringArray
var _clock: Clock
var _partner: Partner
## The entity table: the tamer, the partner, the map's NPCs (specs/npc.md).
var _entities: FieldEntities
## TALKED_TO_ENTITY: the entity (2-9) of the last NPC talk.
var _talked_to_entity := 0
var _care: Care
var _fade: Fade
var _poop: PoopPiles
var _panel: CareDebugPanel
## The text area and the six UI boxes everything that shows text shares (specs/text.md).
var _text_area: TextArea
var _boxes: UIBoxes
## The script state, the text boxes, the interpreter and its debug runner (specs/script.md).
var _script_ctx: ScriptContext
var _textboxes: TextBoxes
var _interpreter: ScriptInterpreter
var _script_debug: ScriptDebug
## The map name during a map change, and scriptTickChangeMap's SCRIPT_MAP_CHANGE_STATE.
var _map_name: MapName
var _script_change_state := 0
var _message := ""
var _message_frames := 0

@onready var _field: FieldMap = $World/SubViewport/FieldMap
@onready var _tamer: Tamer = $World/SubViewport/Tamer
@onready var _label: Label = $Hud/Label
@onready var _camera: Camera3D = $World/SubViewport/FieldMap/Camera3D
@onready var _background: Sprite2D = $World/SubViewport/Background/Sprite2D


func _ready() -> void:
	_maps = DirAccess.get_directories_at(Content.path("maps"))
	_tamer.field = _field
	if Engine.is_editor_hint():
		_refresh_preview()
		return
	if _maps.is_empty():
		_label.text = "No maps in %s.\nRun: python -m dwporter convert maps mmd_files" % Content.path("maps")
		return
	# The tamer (entity 0) and the partner tick before the clock, as in the original's object list
	# (specs/care.md §2.1).
	GameLoop.frame.connect(_tamer.tick)
	_start_partner()
	_start_npcs()
	_start_clock()
	_start_text()
	_start_care()
	_begin(start_map if start_map in _maps else _maps[0], start_spawn)


## initializePartner's model part: the partner of the game state follows the tamer
## (specs/partner.md).
func _start_partner() -> void:
	_partner = Partner.new()
	_partner.name = "Partner"
	$World/SubViewport.add_child(_partner)
	_partner.field = _field
	_partner.tamer = _tamer
	_partner.game_state = GameState
	if debug_partner != "":
		GameState.state["partner"]["digimon"] = debug_partner
	if not _partner.load_digimon(GameData, GameState.state["partner"]["digimon"]):
		_partner.queue_free()
		_partner = null
		return
	GameLoop.frame.connect(_partner.tick)


## The entity table and the map's NPCs (specs/npc.md): created by SET_DIGIMON, ticked after the
## partner in slot order (the NPC objects come after the tamer's and the partner's).
func _start_npcs() -> void:
	_entities = FieldEntities.new()
	_entities.tamer = _tamer
	_entities.partner = _partner
	_entities.npc_factory = _create_npc
	if _partner != null:
		_partner.entities = _entities
	GameLoop.frame.connect(_tick_npcs)


func _create_npc(slot: int) -> Npc:
	var npc := Npc.new()
	npc.name = "Npc%d" % slot
	npc.slot = slot
	npc.field = _field
	npc.entities = _entities
	npc.tamer = _tamer
	npc.talk = _npc_autotalk
	$World/SubViewport.add_child(npc)
	if not npc.load_digimon(GameData, int(_entities.slots[slot]["type"])):
		npc.queue_free()
		return null
	return npc


func _tick_npcs() -> void:
	for npc in _entities.npcs:
		if npc != null:
			npc.tick()


## NPCEntityTickOverworld's autotalk (overworld.c:1328): while no script runs, the NPC's section.
func _npc_autotalk(npc: Npc) -> void:
	if _interpreter != null and _script_ctx.is_paused:
		_talk_to(npc)


## TALKED_TO_ENTITY and callScriptSection(CURRENT_SCRIPT_ID, npc.scriptId, 1).
func _talk_to(npc: Npc) -> void:
	_talked_to_entity = npc.slot + 2
	_interpreter.call_section(_script_ctx.current_script_id, npc.script_id(), 1)


## The text area, the UI boxes and the tamer's message box (specs/text.md). The boxes run their
## frame after the tamer, the partner and the script, which open and close them. They go into the
## HUD in _start_care, after the clock and the bars: their ordering-table layers (1-6) are in front
## of the HUD's (13-15).
func _start_text() -> void:
	if not GameData.available():
		return
	_text_area = TextArea.new(GameData, GameData.language)
	_boxes = UIBoxes.new()
	_script_ctx = ScriptContext.new()
	_script_ctx.game_state = GameState
	_script_ctx.data = GameData
	_script_ctx.entity_screen_position = _entity_screen_position
	_textboxes = TextBoxes.new(_boxes, _text_area, _script_ctx, GameLoop.pad, GameData, GameState)
	GameData.language_changed.connect(func(_lang):
		_text_area.set_language(GameData, GameData.language)
		_textboxes.set_language(GameData.language))
	_script_ctx.world_screen_position = func(p: Array):
		var s := _camera.unproject_position(Content.psx_to_godot(p))
		return Vector2i(roundi(s.x) - 160, roundi(s.y) - 120)
	# The interpreter (specs/script.md) ticks where gameLoop calls tickScript: before the objects,
	# so before the UI boxes' frame.
	_interpreter = ScriptInterpreter.new(_script_ctx, ScriptFiles.new(), _textboxes)
	_interpreter.game_state = GameState
	_interpreter.data = GameData
	_interpreter.clock = _clock
	_interpreter.tamer = _tamer
	_interpreter.partner = _partner
	_interpreter.entities = _entities
	_interpreter.field = _field
	_interpreter.pad = GameLoop.pad
	if _partner != null:
		_partner.data = GameData
		_partner.script_ctx = _script_ctx
	_script_ctx.entity_type = _entity_type
	_interpreter.unported.connect(func(_op, what): _show_message("script: not ported yet: " + what))
	# Map entry goes through MAPHEAD (specs/script.md §3): SET_SCRIPT loads the map, the end of
	# the setup section sets it up, script warps run the map change.
	_interpreter.load_map = _script_load_map
	_interpreter.setup_map = _script_setup_map
	_interpreter.tick_map_change = _tick_script_map_change
	# gameLoop: updateTournamentRegistration's updateMapLightState, then tickScript
	# (specs/map_objects.md §2.4).
	GameLoop.frame.connect(_update_map_light_state)
	GameLoop.frame.connect(_interpreter.tick_script)
	# The camera's pans (tickCameraMovement), after the script and the partner that start them
	# (specs/camera.md §6).
	GameLoop.frame.connect(_field.tick_pan)
	# The overlay sprites animate where the map renders, after the ticks.
	GameLoop.frame.connect(_field.overlays.tick)
	_map_name = MapName.new()
	_map_name.name = "MapName"
	_map_name.text_area = _text_area
	_map_name.data = GameData
	_map_name.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tamer.change_map = _change_map
	_tamer.show_map_name = func(map_id: int):
		if map_id >= 0:
			_map_name.show_name(map_id)
		else:
			_map_name.hide_name()
	_tamer.map_interaction = _check_map_interaction
	# Debug: run the map's script sections (key D) until their entry points are ported.
	_script_debug = ScriptDebug.new()
	_script_debug.interpreter = _interpreter
	_boxes.name = "UIBoxes"
	_boxes.set_anchors_preset(Control.PRESET_FULL_RECT)
	_tamer.camera = _camera
	_tamer.partner = _partner
	_tamer.clock = _clock
	_tamer.pad = GameLoop.pad
	_tamer.message_box = MessageBox.new(_boxes, _text_area)


## setupBoxOrigin's getEntityScreenPos(entity, 1) for a script id: the tamer, the partner, an NPC
## on the map (null without one: the box opens without growing).
func _entity_screen_position(script_id: int):
	if script_id == ScriptContext.OWNER_TAMER:
		return _tamer.screen_position()
	if script_id == ScriptContext.OWNER_PARTNER and _partner != null:
		var p := _camera.unproject_position(_partner.global_position)
		return Vector2i(roundi(p.x) - 160, roundi(p.y) - 120)
	var npc := _entities.entity_from_script_id(script_id) if _entities != null else null
	if npc is Npc:
		return npc.screen_position(_camera)
	return null


## The Digimon type of a script id's entity (the speaker's name): the partner's, an NPC's; -1.
func _entity_type(script_id: int) -> int:
	if script_id == ScriptContext.OWNER_PARTNER:
		return GameData.id_of("digimon/digimon_data", GameState.state["partner"]["digimon"])
	var slot := _entities.npc_slot_for_script_id(script_id) if _entities != null else -1
	return int(_entities.slots[slot]["type"]) if slot >= 0 else -1


## The care rules and the fade they use (specs/care.md §3). A new game's partner gets
## initializePartner's care values; a loaded game keeps its own.
func _start_care() -> void:
	_fade = Fade.new()
	_fade.name = "Fade"
	_fade.clock = _clock
	GameLoop.frame.connect(_tick_message)
	if _partner != null:
		_care = Care.new()
		_care.name = "Care"
		add_child(_care)
		_care.game_state = GameState
		_care.data = GameData
		_care.clock = _clock
		_care.field = _field
		_care.partner = _partner
		_care.tamer = _tamer
		_care.fade = _fade
		_care.text_area = _text_area
		if _interpreter != null:
			_interpreter.care = _care
		_care.script_requested.connect(_on_script_requested)
		_partner.care = _care
		_partner.clock = _clock
		_partner.fade = _fade
		if GameState.state["boot_mode"] == GameState.BOOT_NEW_GAME or debug_partner != "":
			_care.initialize_partner()
		_start_care_visuals()
	# The windows in front of the HUD; last in the HUD and in the frame: the fade covers everything
	# (a render object in the original).
	if _boxes != null:
		$Hud.add_child(_boxes)
	$Hud.add_child(_fade)
	_tamer.fade = _fade
	# The map name of a map change shows on the black screen (renderString on layer 0).
	if _map_name != null:
		$Hud.add_child(_map_name)
	GameLoop.frame.connect(_fade.tick)


## The care on screen (specs/care.md §3.2): happiness / discipline bars next to the clock, the
## condition bubbles over the partner, the poop piles on the map.
func _start_care_visuals() -> void:
	var bars := StatusBars.new()
	bars.name = "StatusBars"
	bars.clock = _clock
	bars.care = _care
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(bars)
	var bubbles := ConditionBubbles.new()
	bubbles.name = "ConditionBubbles"
	bubbles.partner = _partner
	bubbles.camera = _camera
	bubbles.field = _field
	bubbles.data = GameData
	bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(bubbles)
	_care.bubble_shown.connect(bubbles.show_bubble)
	_care.butterfly_changed.connect(_on_butterfly_changed.bind(bubbles))
	_poop = PoopPiles.new()
	_poop.name = "PoopPiles"
	_poop.game_state = GameState
	_poop.partner = _partner
	$World/SubViewport.add_child(_poop)
	_care.poop_changed.connect(_poop.refresh)
	_panel = CareDebugPanel.new()
	_panel.name = "CareDebugPanel"
	_panel.care = _care
	_panel.clock = _clock
	_panel.partner = _partner
	_panel.game_state = GameState
	_panel.sleep_action = _menu_sleep
	_panel.visible = false
	$Hud.add_child(_panel)


## setButterfly removes the bubble first (handleConditionBubble, partner_impl.c:1590). The
## butterfly itself (butterfly.c) isn't drawn yet.
func _on_butterfly_changed(shown: bool, bubbles: ConditionBubbles) -> void:
	if shown:
		bubbles.remove_current()


## Stand-in for script section 0x4DE (the partner collapses or dies; scripts milestone): the values
## partnerTickDying leaves (partner.c:674-676), then the script is over.
func _on_script_requested(section: int) -> void:
	var care: Dictionary = GameState.state["partner"]["care"]
	care["remaining_lifetime"] = 360
	care["sickness_timer"] = 0
	care["injury_timer"] = 0
	_care.script_running = false
	_show_message("script 0x%X (partner collapses): not ported yet" % section)


## Stand-in for the text box: a message in the help line for a few seconds.
func _show_message(text: String) -> void:
	_message = text
	_message_frames = 100
	_update_label()


func _tick_message() -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message = ""
			_update_label()


## addClock (clock.c:90): the clock and its HUD run while the field is played.
func _start_clock() -> void:
	_clock = Clock.new()
	_clock.name = "Clock"
	add_child(_clock)
	_clock.time_of_day_changed.connect(_field.set_time_of_day)
	_clock.daytime_transition.connect(_field.start_daytime_transition)
	_clock.minute_passed.connect(_update_label)
	var hud := ClockHud.new()
	hud.name = "ClockHud"
	hud.clock = _clock
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	$Hud.add_child(hud)
	# The clock takes the top-left corner: the help line moves to the bottom.
	_label.offset_top = 200
	_label.offset_bottom = 238
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	GameLoop.frame.connect(_field.tick_daytime_transition)


## The map without scripts: the editor preview, and maps the scripts don't know.
func _enter(map_name: String, spawn: int) -> void:
	if not _load_map_at_exit(map_name, spawn):
		return
	_field.follow(_tamer.global_position)
	if _clock != null:
		_script_setup_map()


## The game's start or a loaded game: runMapHeadScript(map) with CURRENT_EXIT = the spawn
## (main.c:3455-3483). Without the map's scripts the map is entered directly.
func _begin(map_name: String, spawn: int) -> void:
	var id := GameData.map_id(map_name) if GameData.available() else -1
	if _interpreter == null or id < 0 or ScriptFiles.map_script(id) < 0:
		_enter(map_name, spawn)
		return
	GameState.state["world"]["exit"] = spawn
	_interpreter.run_map_head(id)


## SET_SCRIPT's loadMap(map) (map.c:4020): the map, the tamer and the partner at CURRENT_EXIT
## (loadMapEntities, tamer.c:379), the area response (loadMapSetup), CURRENT_SCREEN.
func _script_load_map(map_id: int) -> void:
	_load_map_at_exit(str(GameData.map(map_id).get("file", "")), int(GameState.state["world"]["exit"]))


func _load_map_at_exit(map_name: String, exit: int) -> bool:
	if not _field.load_map(map_name):
		return false
	# changeMap's removeMapEntities, then loadMap's clearMapDigimon + loadMapDigimon (the NPCs
	# appear when the MAPHEAD section's SET_DIGIMON places them).
	if _entities != null:
		_entities.remove_map_entities()
		_entities.clear_map_digimon()
		var entry: Dictionary = _field.data.get("map_entry", {})
		_entities.load_map_digimon(_field.data.get("digimon", []), bool(entry.get("has_digimon", false)))
	var spawn_point := _field.spawn(clampi(exit, 0, _field.data["spawns"].size() - 1))
	_tamer.place(spawn_point)
	if _partner != null:
		_partner.place_for_spawn(spawn_point)
	var id := -1 if Engine.is_editor_hint() or not GameData.available() else GameData.map_id(map_name)
	# loadMapObjects' snow maps: a property of the map record (specs/map_objects.md §2.5).
	var snow: Dictionary = GameData.map(id).get("snow", {}) if id >= 0 else {}
	if not snow.is_empty():
		_field.overlays.load(_field.data, snow)
	if _clock != null:
		var world: Dictionary = GameState.state["world"]
		if id >= 0:
			world["screen"] = GameData.key_of("systems/maps", id)
		world["exit"] = exit
		_clock.map_has_time_of_day = id < 0 or not GameData.map(id).get("no_time_of_day", false)
		_clock.active = true
	if _care != null:
		var setup: Dictionary = _field.data["setup"]
		_care.set_area_response(setup.get("liked_regions", []), setup.get("disliked_regions", []))
	if _poop != null:
		_poop.refresh()
	if _script_debug != null:
		_script_debug.load_map(id)
	_update_label()
	return true


## updateMapLightState (utils2.c:553) on the current map's light_objects, every frame. The
## tournament registration that may return before it isn't ported (§2.4).
func _update_map_light_state() -> void:
	var screen = GameState.state["world"].get("screen")
	if screen == null or _field.data.is_empty():
		return
	var lights: Array = GameData.map(screen).get("light_objects", [])
	if not lights.is_empty():
		_field.overlays.update_light_state(lights, int(GameState.state["clock"]["hour"]), GameState.is_trigger_set)


## setupMap (map.c:4225), at the end of the MAPHEAD section: the time of day (updateTimeOfDay),
## the camera follows the tamer.
func _script_setup_map() -> void:
	_clock.update_time_of_day()
	_tamer.camera_follow = true
	_field.follow(_tamer.global_position)


## changeMap (map.c:5326): the previous map (with the map's change_map_previous rules instead of
## the C's literal ids), CURRENT_EXIT, then the new map's MAPHEAD section.
func _change_map(map_id: int, exit: int) -> void:
	var world: Dictionary = GameState.state["world"]
	world["previous_screen"] = world["screen"]
	for rule in GameData.map(world["screen"]).get("change_map_previous", []):
		if int(rule["to"]) == map_id:
			world["previous_screen"] = GameData.key_of("systems/maps", int(rule["previous_screen"]))
			if rule["previous_exit"] != null:
				world["previous_exit"] = int(rule["previous_exit"])
	world["exit"] = exit
	if _fade != null:
		_fade.hold(Fade.LOAD_FRAMES)
	if _interpreter == null or ScriptFiles.map_script(map_id) < 0:
		_enter(str(GameData.map(map_id).get("file", "")), exit)
		return
	_interpreter.run_map_head(map_id)


## checkMapInteraction (tamer.c:660): the NPCs (touching one holds his step; ✕ or its autotalk
## starts its section), then the cells: 120 the toilet, 110-119 warps, 51-79 scripts on entering,
## 80-109 scripts on ✕. (Chests come with the items.)
func _check_map_interaction() -> void:
	if _field.data.is_empty():
		return
	var paused := _script_ctx == null or _script_ctx.is_paused
	if _entities != null:
		# entityCheckCollision(partner, tamer) clears animFlag & 2 first.
		_tamer.step_blocked = false
		var pad := GameLoop.pad
		var confirm_now := (pad.polled & ~pad.polled_previous & Pad.CONFIRM) != 0
		var hit := _entities.tamer_collision(confirm_now, _tamer.animation_id() == 0)
		if hit >= 2 and hit < 10:
			_tamer.step_blocked = true
			var npc: Npc = _entities.entity(hit)
			var autotalk := npc.autotalk()
			if (autotalk == 1 or (autotalk == 0 and pad.is_changed(Pad.CONFIRM))) and paused and _interpreter != null:
				_talk_to(npc)
				# The C goes on to the cells, with the script now running (IS_SCRIPT_PAUSED 0).
				paused = _script_ctx.is_paused
	if _tamer.state != Tamer.STATE_FREE:
		return
	var trigger := _field.tile_trigger(_tamer.position)
	if trigger == 120:
		if GameState.has_condition(GameState.CONDITION_POOPY) and paused and _interpreter != null:
			_interpreter.call_section(ScriptFiles.MAPHEAD, 0x4E2, 0)
	elif trigger >= 110 and trigger < 120:
		var warp := _field.warp_for_trigger(trigger)
		if warp.is_empty():
			return
		var world: Dictionary = GameState.state["world"]
		_tamer.target_map = GameData.map_id(warp["map_name"])
		_tamer.target_exit = int(warp["spawn"])
		world["exit"] = _tamer.target_exit
		world["previous_exit"] = trigger - 110
		_tamer.set_state(Tamer.STATE_CHANGE_MAP)
		_tamer.camera_follow = false
		_clock.running = false
	elif trigger > 50 and trigger < 80:
		if paused and _interpreter != null:
			_interpreter.call_section(_script_ctx.current_script_id, trigger, 0)
	elif trigger >= 80 and trigger < 110:
		if GameLoop.pad.is_changed(Pad.CONFIRM) and paused and _interpreter != null:
			_interpreter.call_section(_script_ctx.current_script_id, trigger, 0)


## scriptTickChangeMap (map.c:5277): a script's WARP_TO / TELEPORT. Fade to black (the map name at
## frame 10 if shown), changeMap at frame 20, the tamer still, fade in.
func _tick_script_map_change(map_id: int, exit: int, show_name: int) -> bool:
	var world: Dictionary = GameState.state["world"]
	match _script_change_state:
		0:
			_fade.fade_to_black(20)
			_script_change_state = 1
			world["previous_exit"] = world["exit"]
		1:
			if show_name == 1 and _fade.out_current == 10:
				_map_name.show_name(map_id)
			if _fade.out_current >= 20:
				_change_map(map_id, exit)
				if show_name == 1:
					_map_name.hide_name()
				_tamer.set_state(Tamer.STATE_STILL)
				_fade.fade_from_black(20)
				_script_change_state = 0
				if _script_ctx.is_paused:
					if _partner != null:
						_partner.set_state(Partner.STATE_NORMAL)
					_tamer.set_state(Tamer.STATE_FREE)
					_tamer.camera_follow = true
				_check_map_interaction()
				return true
	return false


## The debug keys [ / ]: a map change like a warp cell's, to the map's exit 0.
func _debug_change_map(map_name: String) -> void:
	var id := GameData.map_id(map_name) if GameData.available() else -1
	if id < 0 or _tamer.state != Tamer.STATE_FREE or _interpreter == null:
		_enter(map_name, 0)
		return
	_tamer.target_map = id
	_tamer.target_exit = 0
	GameState.state["world"]["exit"] = 0
	_tamer.set_state(Tamer.STATE_CHANGE_MAP)
	_tamer.camera_follow = false
	_clock.running = false


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_pressed() or event.is_echo() or _maps.is_empty():
		return
	match event.keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var step := 1 if event.keycode == KEY_BRACKETRIGHT else -1
			var index := (_maps.find(_field.map_name) + step + _maps.size()) % _maps.size()
			_debug_change_map(_maps[index])
		KEY_T:
			var clock: Dictionary = GameState.state["clock"]
			# % 24: advanceToTime starts a new day only for an earlier hour (specs/clock.md §2.4).
			_clock.advance_to_time((clock["hour"] + 1) % 24, clock["minute"])
		KEY_L:
			var languages := GameData.LANGUAGES
			GameData.set_language(languages[(languages.find(GameData.language) + 1) % languages.size()])
			_update_label()
		KEY_H:
			_label.visible = not _label.visible
		KEY_Z:
			_menu_sleep()
		KEY_C:
			if _panel != null:
				_panel.visible = not _panel.visible
		KEY_D:
			if _script_debug != null:
				_show_message(_script_debug.play_next())


## The menu's "Sleep" (handleGameMenuSelection case 6, game_menu.c:2178): only while it is enabled
## (the partner is sleepy) and both are free. Debug key until the menus exist.
func _menu_sleep() -> void:
	if _care == null or not _care.sleep_enabled or _partner.state != Partner.STATE_NORMAL \
			or _tamer.state != Tamer.STATE_FREE:
		_show_message("Sleep: only while the partner is sleepy")
		return
	_partner.set_state(Partner.STATE_SLEEP)
	_clock.running = true


func _update_label() -> void:
	var time: String = ["day", "evening", "night"][_field.time_of_day] if _field.palette_count() > 1 else "no time cycle"
	if _clock != null:
		var clock: Dictionary = GameState.state["clock"]
		if _clock.map_has_time_of_day:
			time = {Clock.TIME_DAY: "day", Clock.TIME_EVENING: "evening", Clock.TIME_NIGHT: "night"}[_clock.current_time_of_day]
		time = "year %d day %d %02d:%02d (%s)" % [clock["year"], clock["day"], clock["hour"], clock["minute"], time]
	var help := _message if _message != "" else "arrows move, shift run, [ ] map, T +1 hour, Z sleep, C care, D script, L language, H hide"
	_label.text = "%s\n%s\n%s" % [_map_label(), time, help]


## Map name from the data porter (MAP_ENTRIES + map.yaml) in the GameData language; the asset
## porter's English name if the data output is missing (and in the editor).
func _map_label() -> String:
	if Engine.is_editor_hint():
		return _field.display_name()
	var id := GameData.map_id(_field.map_name) if GameData.available() else -1
	if id < 0:
		return _field.display_name()
	var area := GameData.localize(GameData.map(id).get("name")).strip_edges()
	if area == "":
		return _field.display_name()
	return "%s (%s, %s)" % [area, _field.map_name, GameData.language]


# --- Editor preview --------------------------------------------------------------------------

## Properties of saved nodes that the preview changes; reset to their class defaults before a save.
const _PREVIEW_PROPERTIES := {
	"background": ["texture", "position"],
	"camera": ["transform", "projection", "keep_aspect", "size", "frustum_offset", "near", "far"],
	"tamer": ["transform"],
	"label": ["text"],
}


func _notification(what: int) -> void:
	if not Engine.is_editor_hint():
		return
	if what == NOTIFICATION_EDITOR_PRE_SAVE:
		clear_preview()
	elif what == NOTIFICATION_EDITOR_POST_SAVE:
		_refresh_preview()


func _refresh_preview() -> void:
	if not Engine.is_editor_hint() or not is_node_ready():
		return
	clear_preview()
	if not editor_preview or not start_map in _maps:
		return
	_field.time_of_day = time_of_day
	_enter(start_map, start_spawn)


## Puts the saved nodes back to what field.tscn stores (the preview's map, doors and tamer model
## are unowned children and are never saved).
func clear_preview() -> void:
	var nodes := {"background": _background, "camera": _camera, "tamer": _tamer, "label": _label}
	for key in _PREVIEW_PROPERTIES:
		var node: Node = nodes[key]
		for property in _PREVIEW_PROPERTIES[key]:
			node.set(property, ClassDB.class_get_property_default_value(node.get_class(), property))
	_field.unload()


## start_map as a drop-down of the converted maps.
func _validate_property(property: Dictionary) -> void:
	if property["name"] == "start_map":
		if _maps.is_empty():
			_maps = DirAccess.get_directories_at(Content.path("maps"))
		property["hint"] = PROPERTY_HINT_ENUM_SUGGESTION
		property["hint_string"] = ",".join(_maps)
