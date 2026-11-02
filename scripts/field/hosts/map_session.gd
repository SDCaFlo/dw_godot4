@tool
class_name MapSession
extends Node
## The map being played (specs/script.md §2.2, §3; specs/scenes.md §4.2): entering a map through
## its MAPHEAD script, loading it with its entities, items and chests, the map changes (warp
## cells, script warps, the debug keys) and the tamer's map interaction (NPCs, trigger cells,
## chests). Also the editor preview's map (a tool script: only the field map and the tamer are set
## there).

## A map was loaded (its id, -1 without the game data): the help line and the script debugger.
signal map_loaded(map_id: int)

## Set by the field (in the editor only field_map, tamer, world).
var world: Node
var field_map: FieldMap
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var scripts: ScriptHost
var clock: Clock
var care_host: CareHost

## The items on the ground and the chests (specs/map_items.md).
var map_items: MapItems
var map_chests: MapChests
## The props logic and 3D view (specs/map_events.md §4.1.2).
var map_props: MapProps
var map_props_view: MapPropsView
## The screen effects (specs/map_events.md §4.2.2).
var map_effects: MapEffects
## scriptTickChangeMap's SCRIPT_MAP_CHANGE_STATE.
var _script_change_state := 0


## DROPPED_ITEMS and CHEST_ARRAY (specs/map_items.md): in the 3D world with the models.
func start_map_items() -> void:
	map_items = MapItems.new()
	map_items.name = "MapItems"
	map_items.field = field_map
	map_items.data = GameData
	world.add_child(map_items)
	map_chests = MapChests.new()
	map_chests.name = "MapChests"
	map_chests.field = field_map
	map_chests.game_state = GameState
	world.add_child(map_chests)
	map_props = MapProps.new(GameState.session)
	map_props_view = MapPropsView.new()
	map_props_view.name = "MapProps"
	map_props_view.props = map_props
	map_props_view.partner = partner
	world.add_child(map_props_view)
	map_effects = MapEffects.new()
	map_effects.name = "MapEffects"
	map_effects.field_map = field_map
	map_effects.game_state = GameState
	add_child(map_effects)
	field_map.daytime_transition_removed.connect(_on_daytime_transition_removed)
	tamer.map_items = map_items
	tamer.map_chests = map_chests


## The map without scripts: the editor preview, and maps the scripts don't know.
func enter(map_name: String, spawn: int) -> void:
	if not _load_map_at_exit(map_name, spawn):
		return
	field_map.follow(tamer.global_position)
	if clock != null:
		script_setup_map()


## The game's start or a loaded game: runMapHeadScript(map) with CURRENT_EXIT = the spawn
## (main.c:3455-3483). Without the map's scripts the map is entered directly.
func begin(map_name: String, spawn: int) -> void:
	var id := GameData.map_id(map_name) if GameData.available() else -1
	if _interpreter() == null or id < 0 or ScriptFiles.map_script(id) < 0:
		enter(map_name, spawn)
		return
	GameState.state["world"]["exit"] = spawn
	_interpreter().run_map_head(id)


## SET_SCRIPT's loadMap(map) (map.c:4020): the map, the tamer and the partner at CURRENT_EXIT
## (loadMapEntities, tamer.c:379), the area response (loadMapSetup), CURRENT_SCREEN.
func script_load_map(map_id: int) -> void:
	_load_map_at_exit(str(GameData.map(map_id).get("file", "")), int(GameState.state["world"]["exit"]))


func _load_map_at_exit(map_name: String, exit: int) -> bool:
	if not field_map.load_map(map_name):
		return false
	# changeMap's clearDroppedItems, unloadMap's emptyChests: the map's setup spawns them again.
	if map_items != null:
		map_items.clear()
		map_chests.clear()
	if map_props != null:
		map_props.unload()
	# changeMap's removeMapEntities, then loadMap's clearMapDigimon + loadMapDigimon (the NPCs
	# appear when the MAPHEAD section's SET_DIGIMON places them).
	if entities != null:
		entities.remove_map_entities()
		entities.clear_map_digimon()
		var entry: Dictionary = field_map.data.get("map_entry", {})
		entities.load_map_digimon(field_map.data.get("digimon", []), bool(entry.get("has_digimon", false)))
	var spawn_point := field_map.spawn(clampi(exit, 0, field_map.data["spawns"].size() - 1))
	tamer.place(spawn_point)
	# loadMap's initializeTamerWaypoints (map.c:4091): the way back starts at the entry.
	tamer.initialize_waypoints()
	if partner != null:
		partner.place_for_spawn(spawn_point)
	var id := -1 if Engine.is_editor_hint() or not GameData.available() else GameData.map_id(map_name)
	# loadMap (map.c:4084): the map's sound set into slot 8.
	if id >= 0:
		Sound.load_map_sounds(int(GameData.map(id).get("sound_bank", 0)))
	# loadMapObjects' snow maps: a property of the map record (specs/map_objects.md §2.5).
	var snow: Dictionary = GameData.map(id).get("snow", {}) if id >= 0 else {}
	if not snow.is_empty():
		field_map.overlays.load(field_map.data, snow)
	if clock != null:
		var world_state: Dictionary = GameState.state["world"]
		if id >= 0:
			world_state["screen"] = GameData.key_of("systems/maps", id)
		world_state["exit"] = exit
		clock.map_has_time_of_day = id < 0 or not GameData.map(id).get("no_time_of_day", false)
		clock.active = true
	var care := care_host.care if care_host != null else null
	if care != null:
		var setup: Dictionary = field_map.data["setup"]
		care.set_area_response(setup.get("liked_regions", []), setup.get("disliked_regions", []))
	if care_host != null and care_host.poop != null:
		care_host.poop.refresh()
	map_loaded.emit(id)
	return true


## updateMapLightState (utils2.c:553) on the current map's light_objects, every frame. Called by
## TournamentHost when the tournament registration tick permits it (specs/tournament_entry.md §4.7).
func update_map_light_state() -> void:
	var screen = GameState.state["world"].get("screen")
	if screen == null or field_map.data.is_empty():
		return
	var lights: Array = GameData.map(screen).get("light_objects", [])
	if not lights.is_empty():
		field_map.overlays.update_light_state(lights, int(GameState.state["clock"]["hour"]), GameState.is_trigger_set)


## setupMap (map.c:4225), at the end of the MAPHEAD section: the time of day (updateTimeOfDay),
## the camera follows the tamer.
func script_setup_map() -> void:
	clock.update_time_of_day()
	tamer.camera_follow = true
	field_map.follow(tamer.global_position)


## changeMap (map.c:5326): the previous map (with the map's change_map_previous rules instead of
## the C's literal ids), CURRENT_EXIT, then the new map's MAPHEAD section.
func change_map(map_id: int, exit: int) -> void:
	var world_state: Dictionary = GameState.state["world"]
	world_state["previous_screen"] = world_state["screen"]
	for rule in GameData.map(world_state["screen"]).get("change_map_previous", []):
		if int(rule["to"]) == map_id:
			world_state["previous_screen"] = GameData.key_of("systems/maps", int(rule["previous_screen"]))
			if rule["previous_exit"] != null:
				world_state["previous_exit"] = int(rule["previous_exit"])
	world_state["exit"] = exit
	if care_host != null and care_host.fade != null:
		care_host.fade.hold(Fade.LOAD_FRAMES)
	if _interpreter() == null or ScriptFiles.map_script(map_id) < 0:
		enter(str(GameData.map(map_id).get("file", "")), exit)
		return
	_interpreter().run_map_head(map_id)


## checkMapInteraction (tamer.c:660): the NPCs (touching one holds his step; ✕ or its autotalk
## starts its section), then the cells: 120 the toilet, 110-119 warps, 51-79 scripts on entering,
## 80-109 scripts on ✕; then the chests.
func check_map_interaction() -> void:
	if field_map.data.is_empty():
		return
	var interpreter := _interpreter()
	var script_ctx := scripts.script_ctx if scripts != null else null
	var paused := script_ctx == null or script_ctx.is_paused
	if entities != null:
		# entityCheckCollision(partner, tamer) clears animFlag & 2 first.
		tamer.step_blocked = false
		var pad := GameLoop.pad
		var confirm_now := (pad.polled & ~pad.polled_previous & Pad.CONFIRM) != 0
		var hit := entities.tamer_collision(confirm_now, tamer.animation_id() == 0)
		if hit >= 2 and hit < 10:
			tamer.step_blocked = true
			var npc: Npc = entities.entity(hit)
			var autotalk := npc.autotalk()
			if (autotalk == 1 or (autotalk == 0 and pad.is_changed(Pad.CONFIRM))) and paused and interpreter != null:
				scripts.talk_to(npc)
				# The C goes on to the cells, with the script now running (IS_SCRIPT_PAUSED 0).
				paused = script_ctx.is_paused
	if tamer.state != Tamer.STATE_FREE:
		return
	var trigger := field_map.tile_trigger(tamer.position)
	if trigger == 120:
		if GameState.has_condition(GameState.CONDITION_POOPY) and paused and interpreter != null:
			interpreter.call_section(ScriptFiles.MAPHEAD, 0x4E2, 0)
	elif trigger >= 110 and trigger < 120:
		var warp := field_map.warp_for_trigger(trigger)
		if warp.is_empty():
			return
		var world_state: Dictionary = GameState.state["world"]
		tamer.target_map = GameData.map_id(warp["map_name"])
		tamer.target_exit = int(warp["spawn"])
		world_state["exit"] = tamer.target_exit
		world_state["previous_exit"] = trigger - 110
		tamer.set_state(Tamer.STATE_CHANGE_MAP)
		tamer.camera_follow = false
		clock.running = false
	elif trigger > 50 and trigger < 80:
		if paused and interpreter != null:
			interpreter.call_section(script_ctx.current_script_id, trigger, 0)
	elif trigger >= 80 and trigger < 110:
		if GameLoop.pad.is_changed(Pad.CONFIRM) and paused and interpreter != null:
			interpreter.call_section(script_ctx.current_script_id, trigger, 0)
	# checkChestCollision (tamer.c:714): ✕ next to a chest's front; no IS_SCRIPT_PAUSED test.
	if map_chests != null:
		var chest := map_chests.near(tamer.tile())
		if chest >= 0 and GameLoop.pad.is_changed(Pad.CONFIRM):
			tamer.interacted_chest = chest
			tamer.set_state(Tamer.STATE_CHEST)


## scriptTickChangeMap (map.c:5277): a script's WARP_TO / TELEPORT. Fade to black (the map name at
## frame 10 if shown), changeMap at frame 20, the tamer still, fade in.
func tick_script_map_change(map_id: int, exit: int, show_name: int) -> bool:
	var world_state: Dictionary = GameState.state["world"]
	var fade := care_host.fade
	match _script_change_state:
		0:
			fade.fade_to_black(20)
			_script_change_state = 1
			world_state["previous_exit"] = world_state["exit"]
		1:
			if show_name == 1 and fade.out_current == 10:
				scripts.map_name.show_name(map_id)
			if fade.out_current >= 20:
				change_map(map_id, exit)
				if show_name == 1:
					scripts.map_name.hide_name()
				tamer.set_state(Tamer.STATE_STILL)
				fade.fade_from_black(20)
				_script_change_state = 0
				if scripts.script_ctx.is_paused:
					if partner != null:
						partner.set_state(Partner.STATE_NORMAL)
					tamer.set_state(Tamer.STATE_FREE)
					tamer.camera_follow = true
				check_map_interaction()
				return true
	return false


## The debug keys [ / ] and the debugger's map list: a map change like a warp cell's.
func debug_change_map(map_name: String, exit := 0) -> void:
	var id := GameData.map_id(map_name) if GameData.available() else -1
	if id < 0 or tamer.state != Tamer.STATE_FREE or _interpreter() == null:
		enter(map_name, exit)
		return
	tamer.target_map = id
	tamer.target_exit = exit
	GameState.state["world"]["exit"] = exit
	tamer.set_state(Tamer.STATE_CHANGE_MAP)
	tamer.camera_follow = false
	clock.running = false


func _interpreter() -> ScriptInterpreter:
	return scripts.interpreter if scripts != null else null


## P21: removeObject(0xFBE, target) when a daytime fade ends or updateTimeOfDay cuts it (map.c:4307,
## 4577; world_object.c:51) also finds the pedestal when the target time of day is 0.
func _on_daytime_transition_removed(palette: int) -> void:
	map_props.on_daytime_removal(Clock.PALETTE.find_key(palette))
