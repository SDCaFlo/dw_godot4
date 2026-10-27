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

var _target: OptionButton
var _partner: Label
var _status: Label


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


func _evolve() -> void:
	var blocker := DebugPartnerTools.evolve(care, _target.get_selected_id())
	_status.text = "Evolving into %s." % _target.get_item_text(_target.selected).strip_edges() \
			if blocker == "" else "Can't evolve now: %s." % blocker


func _learn(moves: Array, which: String) -> void:
	var added := DebugPartnerTools.learn(game_state, moves)
	_status.text = "Learnt %s technique (%d new)." % [which, added] if which == "every" \
			else "Learnt its techniques (%d new)." % added
