class_name DebugPartnerTab
extends VBoxContainer
## The debugger window's "Partner" tab, not part of the original (DebugPartnerTools):
## - Digivolve to: any Digimon a partner can be; the partner walks to the tamer and the evolution
##   scene plays, as for a real evolution (with its gains). Only from the partner's normal state
##   with the tamer free.
## - Learn: the techniques of the partner's Digimon, or every technique; then equip them in the
##   Digimon screen (Techniques) to use them in battle.

## Set by the window (default: the autoloads); `care` by the debug host (null without a field).
var game_state: Node
var data: Node
var care: Care
## The arena (null without a field): its debug result skips the tournament.
var arena: Node:
	set(value):
		arena = value
		if is_inside_tree() and arena != null:
			_build_tournament_ui()

var _target: OptionButton
var _partner: Label
var _status: Label
var _tournament_box: Control
var _registration_label: Label


func _init() -> void:
	name = "Partner"


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if data == null or game_state == null:
		return
	_partner = Label.new()
	add_child(_partner)
	add_child(HSeparator.new())
	_title("Digivolve to")
	_target = OptionButton.new()
	_target.fit_to_longest_item = false
	for d in DebugPartnerTools.candidates(data):
		_target.add_item("%d  %s  (%s)" % d, d[0])
	add_child(_target)
	_button("Digivolve", _evolve)
	add_child(HSeparator.new())
	_title("Techniques")
	_button("Learn its techniques", func(): _learn(DebugPartnerTools.digimon_moves(data, _digimon()), "its"))
	_button("Learn every technique", func(): _learn(DebugPartnerTools.every_move(data), "every"))
	var note := Label.new()
	note.text = "Equip them in the Digimon screen (Techniques)."
	add_child(note)
	add_child(HSeparator.new())
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_status)
	if arena != null:
		_build_tournament_ui()
	game_state.changed.connect(func(_section): _refresh())
	_refresh()


func _title(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	add_child(label)


func _button(text: String, action: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	add_child(button)


func _digimon() -> String:
	return str(game_state.state["partner"]["digimon"])


func _refresh() -> void:
	if _partner == null:
		return
	var learned: Array = game_state.state["partner"]["learned_moves"]
	_partner.text = "Partner: %s\nTechniques learnt: %d" % [
			data.localize(data.digimon(_digimon()).get("name")).strip_edges(), learned.size()]
	_refresh_tournament()


func _build_tournament_ui() -> void:
	if _tournament_box != null or arena == null:
		return
	_tournament_box = VBoxContainer.new()
	add_child(_tournament_box)
	_tournament_box.add_child(HSeparator.new())

	var label := Label.new()
	label.text = "Tournament"
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_tournament_box.add_child(label)

	var row := HBoxContainer.new()
	var spin_label := Label.new()
	spin_label.text = "Tournament result (-1: play it)"
	row.add_child(spin_label)
	var spin := SpinBox.new()
	spin.min_value = -1
	spin.max_value = 3
	spin.step = 1
	spin.value = arena.get("debug_result") if arena != null else -1
	spin.value_changed.connect(func(v: float) -> void:
		if arena != null:
			arena.set("debug_result", int(v))
	)
	row.add_child(spin)
	_tournament_box.add_child(row)

	_registration_label = Label.new()
	_registration_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_tournament_box.add_child(_registration_label)

	var refresh_btn := Button.new()
	refresh_btn.text = "Refresh"
	refresh_btn.pressed.connect(_refresh_tournament)
	_tournament_box.add_child(refresh_btn)

	visibility_changed.connect(func() -> void:
		if visible:
			_refresh_tournament()
	)
	_refresh_tournament()


func _refresh_tournament() -> void:
	if _registration_label == null or arena == null or game_state == null:
		return
	var cup_id: int = game_state.script_value(3)
	var cup_name := "None"
	if cup_id != 0xFF:
		var rec: Dictionary = data.tournament(cup_id) if data != null else {}
		if not rec.is_empty():
			cup_name = data.localize(rec.get("name"))
			if cup_name.is_empty():
				cup_name = rec.get("key", str(cup_id))
		else:
			cup_name = str(cup_id)
	var day_raw: int = game_state.script_value(2)
	var is_tomorrow := (day_raw & 0x80) != 0
	var day_num := day_raw & 0x7F
	var day_text := "%d tomorrow" % day_num if is_tomorrow else str(day_num)
	var t37 := "on" if game_state.is_trigger_set(37) else "off"
	var t38 := "on" if game_state.is_trigger_set(38) else "off"
	var t39 := "on" if game_state.is_trigger_set(39) else "off"
	var t40 := "on" if game_state.is_trigger_set(40) else "off"
	_registration_label.text = "Registration: %s, Day %s (37: %s, 38: %s, 39: %s, 40: %s)" % [
		cup_name, day_text, t37, t38, t39, t40
	]


func _evolve() -> void:
	var blocker := DebugPartnerTools.evolve(care, _target.get_selected_id())
	_status.text = "Evolving into %s." % _target.get_item_text(_target.selected).strip_edges() \
			if blocker == "" else "Can't evolve now: %s." % blocker


func _learn(moves: Array, which: String) -> void:
	var added := DebugPartnerTools.learn(game_state, moves)
	_status.text = "Learnt %s technique (%d new)." % [which, added] if which == "every" \
			else "Learnt its techniques (%d new)." % added
