class_name DebugEffectsTab
extends VBoxContainer
## The debugger window's "Effects" tab, not part of the original: the technique gallery
## (EffectGallery, specs/battle_effects.md §7.4). Pick a technique (the caster defaults to a
## Digimon that has it), a caster, a target and their distance (a share of the technique's range: a
## fighter starts it anywhere within); Place puts them on the map, Play starts the effect
## (again to replay), Close ends the gallery. Below: the effect's frame, its hits and its draw calls.

var gallery: EffectGallery
var data: Node

var _technique: OptionButton
var _caster: OptionButton
var _target: OptionButton
var _distance: SpinBox
var _status: Label


func _init() -> void:
	name = "Effects"


func _ready() -> void:
	if data == null:
		data = get_node_or_null("/root/GameData")
	if data == null:
		return
	_technique = _option("Technique")
	for t in EffectGallery.techniques(data):
		_technique.add_item("%d  %s" % [t[0], t[1]], t[0])
	_technique.item_selected.connect(func(_i): _pick_caster())
	var digimon := EffectGallery.digimon_list(data)
	_caster = _option("Caster")
	_target = _option("Target")
	for d in digimon:
		_caster.add_item("%d  %s" % [d[0], d[1]], d[0])
		_target.add_item("%d  %s" % [d[0], d[1]], d[0])
	_select(_target, 17)
	_pick_caster()
	var distance_row := HBoxContainer.new()
	add_child(distance_row)
	var distance_label := Label.new()
	distance_label.text = "Distance, % of the technique's range"
	distance_row.add_child(distance_label)
	_distance = SpinBox.new()
	_distance.min_value = 10
	_distance.max_value = 100
	_distance.step = 5
	_distance.value = 100
	distance_row.add_child(_distance)
	var row := HBoxContainer.new()
	add_child(row)
	for b in [["Place", _place], ["Play", _play], ["Close", _close]]:
		var button := Button.new()
		button.text = b[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(b[1])
		row.add_child(button)
	_status = Label.new()
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_status)


func _process(_delta: float) -> void:
	if _status != null and is_visible_in_tree():
		_status.text = gallery.status() if gallery != null else "No field: the gallery runs on a map."


func _option(label_text: String) -> OptionButton:
	var label := Label.new()
	label.text = label_text
	add_child(label)
	var option := OptionButton.new()
	option.fit_to_longest_item = false
	add_child(option)
	return option


func _select(option: OptionButton, id: int) -> void:
	var i := option.get_item_index(id)
	if i >= 0:
		option.select(i)


func _pick_caster() -> void:
	var user := EffectGallery.user_of(data, _technique.get_selected_id())
	if user >= 0:
		_select(_caster, user)


func _place() -> void:
	if gallery == null:
		return
	gallery.open(_technique.get_selected_id(), _caster.get_selected_id(), _target.get_selected_id(), int(_distance.value))


func _play() -> void:
	if gallery != null:
		gallery.play()


func _close() -> void:
	if gallery != null:
		gallery.close()
