class_name DebugStateTab
extends ScrollContainer
## The debugger window's "State" tab, not part of the original: reads and changes the game state
## (GameState) to test what the story gates (specs/game_state.md):
## - triggers: one by number, set / clear, and the list of the set ones;
## - script values (readPStat / writePStat), bits and merit points;
## - items (give / remove) and cards (their count);
## - the partner's six base stats (to try the training thresholds);
## - unlocks: presets built from the data (every trigger a table gates on, e.g. all of Birdramon's
##   destinations), so a mod's tables give their own presets.

## The GameState script, for its sizes (its autoload name isn't there in -s tests).
const State := preload("res://scripts/state/game_state.gd")

## Set by the window (default: the autoloads).
var game_state: Node
var data: Node

var _trigger: SpinBox
var _trigger_state: Label
var _set_list: Label
var _value_index: SpinBox
var _value: SpinBox
var _money: SpinBox
var _merit: SpinBox
var _item: OptionButton
var _item_amount: SpinBox
var _item_held: Label
var _card: OptionButton
var _card_count: SpinBox
## The partner's base stats, in Training.STATS order.
var _stats: Array[SpinBox] = []


func _init() -> void:
	name = "State"


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(box)
	_triggers_part(box)
	box.add_child(HSeparator.new())
	_values_part(box)
	box.add_child(HSeparator.new())
	_stats_part(box)
	box.add_child(HSeparator.new())
	_items_part(box)
	box.add_child(HSeparator.new())
	_unlocks_part(box)
	if game_state != null:
		game_state.changed.connect(func(_section): refresh())
	refresh()


# --- the parts ----------------------------------------------------------------------------------

func _title(box: Control, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	box.add_child(label)


func _row(box: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	box.add_child(row)
	return row


func _spin(row: Control, lo: int, hi: int, width := 90) -> SpinBox:
	var spin := SpinBox.new()
	spin.min_value = lo
	spin.max_value = hi
	spin.custom_minimum_size.x = width
	row.add_child(spin)
	return spin


func _button(row: Control, text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.pressed.connect(action)
	row.add_child(button)
	return button


func _triggers_part(box: Control) -> void:
	_title(box, "Triggers")
	var row := _row(box)
	_trigger = _spin(row, 0, State.TRIGGERS - 1)
	_trigger.value_changed.connect(func(_v): refresh())
	_trigger_state = Label.new()
	_trigger_state.custom_minimum_size.x = 70
	row.add_child(_trigger_state)
	_button(row, "Set", func(): set_trigger(int(_trigger.value), true))
	_button(row, "Clear", func(): set_trigger(int(_trigger.value), false))
	_set_list = Label.new()
	_set_list.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_set_list)


func _values_part(box: Control) -> void:
	_title(box, "Script values (readPStat / writePStat)")
	var row := _row(box)
	var index_label := Label.new()
	index_label.text = "value"
	row.add_child(index_label)
	_value_index = _spin(row, 0, State.SCRIPT_VALUES - 1)
	_value_index.value_changed.connect(func(_v): refresh())
	var eq := Label.new()
	eq.text = "="
	row.add_child(eq)
	_value = _spin(row, 0, 0xFF)
	_button(row, "Write", func(): game_state.set_script_value(int(_value_index.value), int(_value.value)))
	row = _row(box)
	var bits := Label.new()
	bits.text = "bits"
	row.add_child(bits)
	_money = _spin(row, 0, ItemMenu.MONEY_MAX, 110)
	var merit := Label.new()
	merit.text = "merit"
	row.add_child(merit)
	_merit = _spin(row, 0, ItemMenu.MERIT_MAX)
	_button(row, "Apply", func(): set_money(int(_money.value), int(_merit.value)))


func _stats_part(box: Control) -> void:
	_title(box, "Partner base stats (HP MP Off Def Speed Brains)")
	var row := _row(box)
	for i in Training.STATS.size():
		_stats.append(_spin(row, 0, Training.stat_cap(i), 70))
	_button(_row(box), "Apply stats", func(): set_stats(_stats.map(func(spin): return int(spin.value))))


func _items_part(box: Control) -> void:
	_title(box, "Items and cards")
	_item = OptionButton.new()
	_item.fit_to_longest_item = false
	box.add_child(_item)
	if data != null:
		for record in data.records("items/item_data"):
			_item.add_item("%d  %s" % [int(record["id"]), data.localize(record.get("name"))], int(record["id"]))
	_item.item_selected.connect(func(_i): refresh())
	var row := _row(box)
	_item_amount = _spin(row, 1, 99)
	_item_amount.value = 1
	_button(row, "Give", func(): give(_item.get_selected_id(), int(_item_amount.value)))
	_button(row, "Remove", func(): game_state.remove_item(_item.get_selected_id(), int(_item_amount.value)))
	_item_held = Label.new()
	row.add_child(_item_held)
	_card = OptionButton.new()
	_card.fit_to_longest_item = false
	box.add_child(_card)
	if data != null:
		for record in data.records("items/card_data"):
			if record.get("price") == null:
				continue
			var digimon = record.get("digimon", {})
			_card.add_item("card %d  %s" % [int(record["id"]), str(digimon.get("name", ""))], int(record["id"]))
	_card.item_selected.connect(func(_i): refresh())
	row = _row(box)
	var count := Label.new()
	count.text = "held"
	row.add_child(count)
	_card_count = _spin(row, 0, State.MAX_CARD_COUNT)
	_button(row, "Set", func(): set_card(_card.get_selected_id(), int(_card_count.value)))
	_button(row, "All cards", func(): all_cards(1))


func _unlocks_part(box: Control) -> void:
	_title(box, "Unlocks (from the data)")
	for preset in presets():
		var row := _row(box)
		var label := Label.new()
		label.text = preset["name"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(label)
		var triggers: Array = preset["triggers"]
		_button(row, "Set", func(): set_triggers(triggers, true))
		_button(row, "Clear", func(): set_triggers(triggers, false))


# --- what the buttons do (testable without the UI) -----------------------------------------------

func set_trigger(trigger: int, on: bool) -> void:
	if on:
		game_state.set_trigger(trigger)
	else:
		game_state.clear_trigger(trigger)


func set_triggers(triggers: Array, on: bool) -> void:
	for t in triggers:
		set_trigger(int(t), on)


func set_money(money: int, merit: int) -> void:
	game_state.state["money"] = clampi(money, 0, ItemMenu.MONEY_MAX)
	game_state.state["merit"] = clampi(merit, 0, ItemMenu.MERIT_MAX)
	game_state.changed.emit("money")


## The partner's base stats (Training.STATS order), each within its cap.
func set_stats(values: Array) -> void:
	var base: Dictionary = game_state.state["partner"]["stats"]["base"]
	for i in mini(values.size(), Training.STATS.size()):
		base[Training.STATS[i]] = clampi(int(values[i]), 0, Training.stat_cap(i))
	game_state.changed.emit("partner")


func give(item: int, amount: int) -> bool:
	return game_state.give_item(item, amount)


func set_card(card: int, count: int) -> void:
	game_state.set_card_count(card, count)
	game_state.changed.emit("cards")


## Every priced card held `count` times.
func all_cards(count: int) -> void:
	for record in data.records("items/card_data"):
		if record.get("price") != null:
			game_state.set_card_count(int(record["id"]), count)
	game_state.changed.emit("cards")


## The presets: a name and the triggers a table gates on. Built from the data, so new records (a
## mod's destinations, tracks) are included.
func presets() -> Array:
	var out := []
	if data == null:
		return out
	var destinations := []
	var names := []
	for record in data.system("birdramon_transport"):
		destinations.append(int(record["trigger"]))
		names.append(data.localize(record.get("map", {}).get("name")).strip_edges())
	if not destinations.is_empty():
		out.append({"name": "Birdramon: every destination (%s)" % ", ".join(names), "triggers": destinations})
	var tracks := []
	for record in data.system("jukebox"):
		var unlock = record.get("unlock_trigger")
		if unlock != null and not int(unlock) in tracks:
			tracks.append(int(unlock))
	if not tracks.is_empty():
		out.append({"name": "Jukebox: the locked tracks (game beaten: trigger %s)" % ", ".join(tracks.map(str)),
				"triggers": tracks})
	return out


## The labels follow the state (any change of GameState).
func refresh() -> void:
	if game_state == null or _trigger == null:
		return
	_trigger_state.text = "set" if game_state.is_trigger_set(int(_trigger.value)) else "not set"
	var triggers: Array = game_state.state["script"]["triggers"]
	_set_list.text = "Set (%d): %s" % [triggers.size(), ", ".join(triggers.map(str))]
	_value.set_value_no_signal(game_state.script_value(int(_value_index.value)))
	_money.set_value_no_signal(int(game_state.state["money"]))
	_merit.set_value_no_signal(int(game_state.state["merit"]))
	var base: Dictionary = game_state.state["partner"]["stats"]["base"]
	for i in _stats.size():
		_stats[i].set_value_no_signal(int(base.get(Training.STATS[i], 0)))
	if _item.item_count > 0:
		_item_held.text = "held %d" % game_state.item_count(_item.get_selected_id())
	if _card.item_count > 0:
		_card_count.set_value_no_signal(game_state.card_count(_card.get_selected_id()))
