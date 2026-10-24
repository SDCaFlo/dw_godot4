class_name MapName
extends Control
## The map name shown during a map change (addMapNameObject, renderMapName; map.c:5318, :5426):
## drawn into text-area row 0 and shown at the screen centre, in front of the fade (layer 0).

var text_area: TextArea
var data: Node

## strlen of the name: the C string's length (US ASCII 1 byte, JP / EU 2 per character).
var _length := 0


func _ready() -> void:
	mouse_filter = MOUSE_FILTER_IGNORE
	visible = false
	# The text and windows' upscaling filter (PsxUiFilter, ISSUES.md D-3).
	material = PsxUiFilter.material()


## addMapNameObject(mapId): clearTextArea, the name (MAP_NAME_PTR[loadingName]) at (0, 0).
func show_name(map_id: int) -> void:
	var name_text: String = data.localize(data.map(map_id).get("name"))
	text_area.clear_all()
	text_area.draw_string(name_text, 0, 0)
	_length = text_area.font.to_bytes(name_text).size()
	visible = true
	queue_redraw()


## removeObject(0xFA1, mapId).
func hide_name() -> void:
	visible = false


## renderMapName per release: centred by the string's length.
func _draw() -> void:
	if text_area == null:
		return
	match text_area.font.language:
		"en_eu":
			text_area.render_string(self, 0, -((_length / 2) * 4), -6, (_length / 2) * 8, 12, 0, 0)
		"ja":
			text_area.render_string(self, 0, -12 - (_length / 2) * 6, -6, (_length / 2) * 12, 12, 0, 0)
		_:
			text_area.render_string(self, 0, 12 - (_length / 2) * 8, -6, _length * 8 + 4, 12, 0, 0)
