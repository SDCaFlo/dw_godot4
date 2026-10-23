class_name CareDebugPanel
extends PanelContainer
## Debug panel for the care (specs/care.md §3.5), not part of the original: the care values, the
## game speed, the condition bits and the care actions whose menus don't exist yet. Toggled with
## `C` on the field. Every action goes through the ported functions (Care, Clock, GameState), so
## the panel can't put the state anywhere the game couldn't.

const SPEEDS := [1, 10, 60]
const CONDITIONS := [["sleepy", Care.SLEEPY], ["tired", Care.TIRED], ["hungry", Care.HUNGRY],
		["poopy", Care.POOPY], ["unhappy", Care.UNHAPPY], ["injured", Care.INJURED], ["sick", Care.SICK]]
const FONT_SIZE := 6

var care: Care
var clock: Clock
var partner: Partner
var game_state: Node
var game_loop: Node
## The menu's "Sleep" of the field (refused unless the partner is sleepy).
var sleep_action: Callable

var _values: Label
var _toggles := {}
var _speed_buttons := {}
var _frames := 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_STOP
	position = Vector2(166, 2)
	custom_minimum_size = Vector2(152, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	add_child(box)
	_values = Label.new()
	_values.add_theme_font_size_override("font_size", FONT_SIZE)
	box.add_child(_values)
	var speeds := _row(box)
	_label(speeds, "speed")
	for value in SPEEDS:
		var button := _button(speeds, "x%d" % value, _set_speed.bind(value))
		button.toggle_mode = true
		_speed_buttons[value] = button
	var flags := HFlowContainer.new()
	box.add_child(flags)
	for entry in CONDITIONS:
		var toggle := _button(flags, entry[0], Callable())
		toggle.toggle_mode = true
		toggle.toggled.connect(_set_condition.bind(entry[1]))
		_toggles[entry[1]] = toggle
	var actions := HFlowContainer.new()
	box.add_child(actions)
	_button(actions, "+1 hour", _skip_hour)
	_button(actions, "sleep", func(): sleep_action.call())
	_button(actions, "praise", func(): care.handle_praise_scold(15))
	_button(actions, "scold", func(): care.handle_praise_scold(4))
	_button(actions, "toilet", _toilet)
	_button(actions, "poop now", _poop_now)
	_button(actions, "hungry now", func(): _care()["food_level"] = 0)
	_button(actions, "stats", _set_stats)
	var values := HFlowContainer.new()
	box.add_child(values)
	for entry in [["happy", "happiness"], ["disc", "discipline"], ["tired", "tiredness"], ["energy", "energy_level"]]:
		_button(values, "%s-" % entry[0], _add.bind(entry[1], -10))
		_button(values, "%s+" % entry[0], _add.bind(entry[1], 10))
	var loop := get_node_or_null("/root/GameLoop")
	if game_loop == null:
		game_loop = loop
	if loop != null:
		loop.frame.connect(_on_frame)
	_refresh()


func _on_frame() -> void:
	_frames += 1
	if visible and _frames % 5 == 0:
		_refresh()


func _care() -> Dictionary:
	return game_state.state["partner"]["care"]


## The values, condition toggles and speed buttons from the state.
func _refresh() -> void:
	if care == null or game_state == null:
		return
	var c := _care()
	var clk: Dictionary = game_state.state["clock"]
	var stats: Dictionary = game_state.state["partner"]["stats"]
	var lines := [
		"%s  state %d.%d  lives %d  area %d" % [game_state.state["partner"]["digimon"],
			partner.state if partner else 0, partner.sub_state if partner else 0,
			game_state.state["partner"]["lives"], care.area_response],
		"%02d:%02d day %d  frame %d  speed x%d" % [clk["hour"], clk["minute"], clk["day"], clk["frame"],
			game_loop.speed if game_loop else 1],
		"happy %d  disc %d  tired %d  weight %d" % [c["happiness"], c["discipline"], c["tiredness"], c["weight"]],
		"energy %d  food %d  next hunger %d  starve %d" % [c["energy_level"], c["food_level"],
			c["next_hunger_hour"], c["starvation_timer"]],
		"sleepy %02d:%02d  wake %02d:%02d  awake %d  sleep timer %d" % [c["sleepy_hour"], c["sleepy_minute"],
			c["wakeup_hour"], c["wakeup_minute"], c["time_awake_today"], c["tiredness_sleep_timer"]],
		"poop %d  pooping %d  virus %d  mistakes %d" % [c["poop_level"], c["pooping_timer"], c["virus_bar"],
			c["care_mistakes"]],
		"sick counter %d tries %d timer %d  injury %d" % [c["sickness_counter"], c["sickness_tries"],
			c["sickness_timer"], c["injury_timer"]],
		"lifetime %d  age %d  evo %d  area timer %d" % [c["remaining_lifetime"], c["age"], c["evo_timer"],
			c["area_effect_timer"]],
		"HP %d/%d  MP %d/%d" % [stats["current"]["hp"], stats["base"]["max_hp"], stats["current"]["mp"],
			stats["base"]["max_mp"]],
	]
	_values.text = "\n".join(lines)
	for flag in _toggles:
		_toggles[flag].set_pressed_no_signal(int(c["condition"]) & flag != 0)
	for value in _speed_buttons:
		_speed_buttons[value].set_pressed_no_signal(game_loop != null and game_loop.speed == value)


func _set_speed(value: int) -> void:
	if game_loop != null:
		game_loop.speed = value
	_refresh()


func _set_condition(on: bool, flag: int) -> void:
	game_state.set_condition(flag, on)
	_refresh()


## skipHours + the clock moving on, as a script's time skip does (script_interp.c:1238).
func _skip_hour() -> void:
	var clk: Dictionary = game_state.state["clock"]
	care.skip_hours(1)
	clock.advance_to_time((int(clk["hour"]) + 1) % 24, int(clk["minute"]))
	_refresh()


func _toilet() -> void:
	if int(_care()["condition"]) & Care.POOPY:
		care.handle_toilet()
	_refresh()


## The pooping timer runs out on the next frame: the wild-poop scene starts.
func _poop_now() -> void:
	game_state.set_condition(Care.POOPY, true)
	_care()["pooping_timer"] = 1
	_refresh()


## Stand-in for the stats the intro scripts give: 500 HP / MP, half of it left (to see sleep recovery).
func _set_stats() -> void:
	var stats: Dictionary = game_state.state["partner"]["stats"]
	stats["base"]["max_hp"] = 500
	stats["base"]["max_mp"] = 500
	stats["current"]["hp"] = 250
	stats["current"]["mp"] = 250
	_refresh()


func _add(field_name: String, amount: int) -> void:
	_care()[field_name] = int(_care()[field_name]) + amount
	care.tick_condition_boundaries()
	_refresh()


func _row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 1)
	parent.add_child(row)
	return row


func _label(parent: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size.x = 34
	label.add_theme_font_size_override("font_size", FONT_SIZE)
	parent.add_child(label)


func _button(parent: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.add_theme_font_size_override("font_size", FONT_SIZE)
	# Compact buttons for the 320 x 240 screen.
	for style_name in ["normal", "hover", "pressed", "hover_pressed"]:
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.45, 0.45, 0.5, 0.9) if style_name.contains("pressed") else Color(0.18, 0.18, 0.2, 0.9)
		if style_name == "hover":
			style.bg_color = Color(0.28, 0.28, 0.32, 0.9)
		style.content_margin_left = 2
		style.content_margin_right = 2
		style.content_margin_top = 0
		style.content_margin_bottom = 0
		button.add_theme_stylebox_override(style_name, style)
	if action.is_valid():
		button.pressed.connect(action)
	parent.add_child(button)
	return button
