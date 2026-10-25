@tool
class_name DebugHost
extends Node
## The field's debug tools, not part of the original (specs/scenes.md §4.2): the help line, the
## debug keys, the care panel, the script debugger and the debugger window. A tool script: in the
## editor it only fills the help line of the preview.
##
## Debug keys: [ / ] previous / next map, T one hour later, Z the menu's Sleep, C the care panel,
## D the next section of the map's script, L text language, H toggle the help line, F1 the debugger
## window (DebugWindow: the status, a map list to teleport to, the 3D render scale).

const HELP := "arrows move, shift run, [ ] map, T +1 hour, Z sleep, C care, D script, L language, H hide"

## Set by the field (in the editor only label and field_map).
var label: Label
var field_map: FieldMap
var maps: PackedStringArray
var map_session: MapSession
var scripts: ScriptHost
var care_host: CareHost
var clock: Clock
## The debugger window's settings at start (the field's exports).
var render_scale := 4
var ui_filter := true
var show_window := true

## The debugger window; the field connects its settings.
var window: DebugWindow
## Runs the map's script sections (key D) until their entry points are ported.
var script_debug: ScriptDebug
## The care values (key C); the field puts it into the HUD. null without care.
var panel: CareDebugPanel

var _message := ""
var _message_frames := 0


func start() -> void:
	if clock != null:
		# The clock takes the top-left corner: the help line moves to the bottom.
		label.offset_top = 200
		label.offset_bottom = 238
		label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	if scripts != null and scripts.interpreter != null:
		script_debug = ScriptDebug.new()
		script_debug.interpreter = scripts.interpreter
	if care_host != null and care_host.care != null:
		panel = CareDebugPanel.new()
		panel.name = "CareDebugPanel"
		panel.care = care_host.care
		panel.clock = clock
		panel.partner = care_host.partner
		panel.game_state = GameState
		panel.sleep_action = menu_sleep
		panel.visible = false
	window = DebugWindow.new()
	window.maps = maps
	window.map_label = func(map_name: String) -> String: return _map_list_label(map_name)
	window.teleport = func(map_name: String, exit: int) -> void: map_session.debug_change_map(map_name, exit)
	window.render_scale = render_scale
	window.ui_filter = ui_filter
	window.visible = show_window
	add_child(window)


## A map was loaded: the script debugger's sections, the help line.
func on_map_loaded(map_id: int) -> void:
	if script_debug != null:
		script_debug.load_map(map_id)
	update_label()


## Stand-in for the text box: a message in the help line for a few seconds.
func show_message(text: String) -> void:
	_message = text
	_message_frames = 100
	update_label()


func tick_message() -> void:
	if _message_frames > 0:
		_message_frames -= 1
		if _message_frames == 0:
			_message = ""
			update_label()


func tick_panel() -> void:
	if panel != null:
		panel.tick()


## The menu's "Sleep" (debug key until the menus exist).
func menu_sleep() -> void:
	if care_host == null or not care_host.menu_sleep():
		show_message("Sleep: only while the partner is sleepy")


func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not event.is_pressed() or event.is_echo() or maps.is_empty() or map_session == null:
		return
	match event.keycode:
		KEY_BRACKETLEFT, KEY_BRACKETRIGHT:
			var step := 1 if event.keycode == KEY_BRACKETRIGHT else -1
			var index := (maps.find(field_map.map_name) + step + maps.size()) % maps.size()
			map_session.debug_change_map(maps[index])
		KEY_T:
			var values: Dictionary = GameState.state["clock"]
			# % 24: advanceToTime starts a new day only for an earlier hour (specs/clock.md §2.4).
			clock.advance_to_time((values["hour"] + 1) % 24, values["minute"])
		KEY_L:
			var languages := GameData.LANGUAGES
			GameData.set_language(languages[(languages.find(GameData.language) + 1) % languages.size()])
			update_label()
		KEY_H:
			label.visible = not label.visible
		KEY_Z:
			menu_sleep()
		KEY_C:
			if panel != null:
				panel.visible = not panel.visible
		KEY_D:
			if script_debug != null:
				show_message(script_debug.play_next())
		KEY_F1:
			if window != null:
				window.visible = not window.visible


func update_label() -> void:
	var time: String = ["day", "evening", "night"][field_map.time_of_day] if field_map.palette_count() > 1 else "no time cycle"
	if clock != null:
		var values: Dictionary = GameState.state["clock"]
		if clock.map_has_time_of_day:
			time = {Clock.TIME_DAY: "day", Clock.TIME_EVENING: "evening", Clock.TIME_NIGHT: "night"}[clock.current_time_of_day]
		time = "year %d day %d %02d:%02d (%s)" % [values["year"], values["day"], values["hour"], values["minute"], time]
	var help := _message if _message != "" else HELP
	label.text = "%s\n%s\n%s" % [_map_label(), time, help]
	if window != null:
		window.set_status("%s\n%s\n%s" % [_map_label(), time, _message])


## Map name from the data porter (MAP_ENTRIES + map.yaml) in the GameData language; the asset
## porter's English name if the data output is missing (and in the editor).
func _map_label() -> String:
	if Engine.is_editor_hint():
		return field_map.display_name()
	var id := GameData.map_id(field_map.map_name) if GameData.available() else -1
	if id < 0:
		return field_map.display_name()
	var area := GameData.localize(GameData.map(id).get("name")).strip_edges()
	if area == "":
		return field_map.display_name()
	return "%s (%s, %s)" % [area, field_map.map_name, GameData.language]


## A map's line in the debugger's list: file name and area name.
func _map_list_label(map_name: String) -> String:
	var id := GameData.map_id(map_name) if GameData.available() else -1
	var area := GameData.localize(GameData.map(id).get("name")).strip_edges() if id >= 0 else ""
	return "%s  %s" % [map_name, area]
