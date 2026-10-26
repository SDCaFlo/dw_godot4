class_name DebugWindow
extends Window
## The debugger (ISSUES.md D-1), not part of the original: its own OS window next to the game, at
## a readable size, so the game keeps its 4:3 picture. Toggled with F1 on the field.
##
## - Status: the map, the clock, the last message, the debug keys.
## - Maps: every converted map, filtered by name; double-click (or Go) teleports through the
##   field's debug map change, to the exit chosen.
## - Render: the 3D view's resolution (ISSUES.md I-3), 1x (the PSX's) to 4x; the text and windows'
##   upscaling filter (ISSUES.md D-3).
## - State: triggers, script values, bits / merit, items, cards and data-built unlock presets
##   (DebugStateTab), to test what the story gates.

signal render_scale_changed(value: int)
signal ui_filter_changed(on: bool)

const FONT_SIZE := 15
const KEYS := "Keys (in the game window):\narrows move, shift run\n[ / ] previous / next map\nT +1 hour, Z sleep\nC care panel, D next script section\nL language, H help line, F1 this window"

## The field's maps (folder names) and its callbacks: a list line for a map, a teleport.
var maps: PackedStringArray
var map_label: Callable
var teleport: Callable
var render_scale := 4
var ui_filter := true

var _status: Label
var _filter: LineEdit
var _list: ItemList
var _exit: SpinBox
var _scale: OptionButton


func _init() -> void:
	title = "DW debugger"
	size = Vector2i(460, 760)
	position = Vector2i(40, 60)
	wrap_controls = false
	close_requested.connect(func(): visible = false)


func _ready() -> void:
	var theme := Theme.new()
	theme.default_font_size = FONT_SIZE
	var root := PanelContainer.new()
	root.theme = theme
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(root)
	var tabs := TabContainer.new()
	root.add_child(tabs)
	tabs.add_child(_status_tab())
	tabs.add_child(_maps_tab())
	tabs.add_child(_render_tab())
	tabs.add_child(DebugStateTab.new())
	_fill_list("")


func _status_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Status"
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(_status)
	box.add_child(HSeparator.new())
	var keys := Label.new()
	keys.text = KEYS
	box.add_child(keys)
	return box


func _maps_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Maps"
	_filter = LineEdit.new()
	_filter.placeholder_text = "filter (file or area name)"
	_filter.text_changed.connect(_fill_list)
	box.add_child(_filter)
	_list = ItemList.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_list.item_activated.connect(func(_i): _go())
	box.add_child(_list)
	var row := HBoxContainer.new()
	box.add_child(row)
	var exit_label := Label.new()
	exit_label.text = "exit"
	row.add_child(exit_label)
	_exit = SpinBox.new()
	_exit.min_value = 0
	_exit.max_value = 9
	row.add_child(_exit)
	var go := Button.new()
	go.text = "Go"
	go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	go.pressed.connect(_go)
	row.add_child(go)
	return box


func _render_tab() -> Control:
	var box := VBoxContainer.new()
	box.name = "Render"
	var label := Label.new()
	label.text = "3D render scale (ISSUES.md I-3)\n1x is the PSX's 320 x 240; more renders the models\nsmoother, like an emulator. The background stays as it is."
	box.add_child(label)
	_scale = OptionButton.new()
	for k in [1, 2, 3, 4]:
		_scale.add_item("%dx  (%d x %d)" % [k, 320 * k, 240 * k], k)
	_scale.select(_scale.get_item_index(render_scale))
	_scale.item_selected.connect(func(i): render_scale_changed.emit(_scale.get_item_id(i)))
	box.add_child(_scale)
	box.add_child(HSeparator.new())
	var filter := CheckBox.new()
	filter.text = "Text and windows: upscaling filter (Scale4x)"
	filter.button_pressed = ui_filter
	filter.toggled.connect(func(on): ui_filter_changed.emit(on))
	box.add_child(filter)
	var note := Label.new()
	note.text = "Off: the PSX's square pixels. (ISSUES.md D-3)"
	box.add_child(note)
	return box


## The field's status: map, clock, last message.
func set_status(text: String) -> void:
	if _status != null:
		_status.text = text


func _fill_list(filter: String) -> void:
	if _list == null:
		return
	_list.clear()
	var needle := filter.strip_edges().to_lower()
	for map_name in maps:
		var line: String = map_label.call(map_name) if map_label.is_valid() else map_name
		if needle == "" or line.to_lower().contains(needle):
			_list.add_item(line)
			_list.set_item_metadata(_list.item_count - 1, map_name)


func _go() -> void:
	var selected := _list.get_selected_items()
	if selected.is_empty() or not teleport.is_valid():
		return
	teleport.call(str(_list.get_item_metadata(selected[0])), int(_exit.value))
