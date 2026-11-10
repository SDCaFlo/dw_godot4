@tool
extends VBoxContainer
## "DW Data" dock: browse the content registry (GameData: the dw1 pack and any packs) inside the
## editor, with model / image previews from Content. Read-only. Guide: docs/dw_data_dock.md.

const GAME_DATA := preload("res://scripts/data/game_data.gd")
## List entries: label, entity kind (GameData.ENTITIES) or a special page.
const KINDS := [
	["Overview", "overview"], ["Digimon", "digimon"], ["Techniques", "move"], ["Items", "item"],
	["Cards", "card"], ["Maps", "map"], ["Tournaments", "tournament"], ["Tables", "tables"],
]
## Record fields hidden unless "Raw values" is on: C initializer values and source lines.
const RAW_FIELDS := ["c", "line", "_struct"]
## A reference {"id", "name"} (or an int) under one of these field names links to that kind.
const REF_KINDS := {
	"move": "move", "item": "item", "digimon": "digimon", "target": "digimon", "favorite_food": "item",
	"from": "digimon", "to": "digimon", "map": "map", "shopkeepers": "digimon",
}
const PREVIEW_SIZE := Vector2i(256, 256)

var _data: Node
var _kind := "overview"
## Records shown in the list (filtered), as [ref, label].
var _rows: Array = []
var _history: Array = []
var _current := []
var _show_raw := false
var _asset_report := ""

var _kind_button: OptionButton
var _language_button: OptionButton
var _search: LineEdit
var _list: ItemList
var _preview_box: VBoxContainer
var _image: TextureRect
var _viewport: SubViewport
var _model_root: Node3D
var _camera: Camera3D
var _anim_button: OptionButton
var _player: AnimationPlayer
var _source_label: Label
var _detail: RichTextLabel


func _ready() -> void:
	name = "DW Data"
	_data = GAME_DATA.new()
	_build_ui()
	_select_kind("overview")


func _exit_tree() -> void:
	if _data != null:
		_data.free()
		_data = null


func _process(delta: float) -> void:
	if _player != null and _viewport.get_parent().visible:
		_player.advance(delta)
	if _model_root != null and _model_root.get_child_count() > 0:
		_model_root.rotate_y(delta * 0.5)


# --- UI ----------------------------------------------------------------------------------------

func _build_ui() -> void:
	size_flags_vertical = SIZE_EXPAND_FILL
	var row := HBoxContainer.new()
	add_child(row)
	_kind_button = OptionButton.new()
	for k in KINDS:
		_kind_button.add_item(k[0])
	_kind_button.size_flags_horizontal = SIZE_EXPAND_FILL
	_kind_button.item_selected.connect(func(i): _select_kind(KINDS[i][1]))
	row.add_child(_kind_button)
	row.add_child(_button("◀", "Back", _back))
	row.add_child(_button("⟳", "Reload the data (after re-running a porter or changing packs)", _reload))
	var raw := CheckButton.new()
	raw.text = "Raw"
	raw.tooltip_text = "Show the C initializer values (c) and source lines"
	raw.toggled.connect(func(on): _show_raw = on; _refresh_detail())
	row.add_child(raw)

	var row2 := HBoxContainer.new()
	add_child(row2)
	_search = LineEdit.new()
	_search.placeholder_text = "Search name, key or id"
	_search.clear_button_enabled = true
	_search.size_flags_horizontal = SIZE_EXPAND_FILL
	_search.text_changed.connect(func(_t): _fill_list())
	row2.add_child(_search)
	_language_button = OptionButton.new()
	# The languages this output has (en_us only from a US disc, data_porter/specs/from_disc.md §4).
	var languages: PackedStringArray = _data.languages()
	for lang in languages:
		_language_button.add_item(lang)
	_language_button.select(languages.find(_data.language))
	_language_button.item_selected.connect(func(i): _data.set_language(languages[i]); _fill_list(); _refresh_detail())
	row2.add_child(_language_button)

	var split := VSplitContainer.new()
	split.size_flags_vertical = SIZE_EXPAND_FILL
	add_child(split)
	_list = ItemList.new()
	_list.custom_minimum_size.y = 160
	_list.item_selected.connect(func(i): _open(_kind, _rows[i][0]))
	split.add_child(_list)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	split.add_child(scroll)
	var detail_box := VBoxContainer.new()
	detail_box.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(detail_box)

	_preview_box = VBoxContainer.new()
	detail_box.add_child(_preview_box)
	_image = TextureRect.new()
	_image.custom_minimum_size = Vector2(0, 160)
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_preview_box.add_child(_image)
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(PREVIEW_SIZE)
	container.stretch = true
	_preview_box.add_child(container)
	_viewport = SubViewport.new()
	_viewport.size = PREVIEW_SIZE
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_WHEN_VISIBLE
	container.add_child(_viewport)
	_camera = Camera3D.new()
	_viewport.add_child(_camera)
	_model_root = Node3D.new()
	_viewport.add_child(_model_root)
	_anim_button = OptionButton.new()
	_anim_button.item_selected.connect(func(i): _play(_anim_button.get_item_text(i)))
	_preview_box.add_child(_anim_button)
	_source_label = Label.new()
	_source_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview_box.add_child(_source_label)

	_detail = RichTextLabel.new()
	_detail.bbcode_enabled = true
	_detail.fit_content = true
	_detail.selection_enabled = true
	_detail.size_flags_horizontal = SIZE_EXPAND_FILL
	_detail.meta_clicked.connect(_on_link)
	detail_box.add_child(_detail)


static func _button(text: String, tooltip: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tooltip
	b.flat = true
	b.pressed.connect(action)
	return b


# --- Navigation --------------------------------------------------------------------------------

func _select_kind(kind: String) -> void:
	_kind = kind
	for i in KINDS.size():
		if KINDS[i][1] == kind:
			_kind_button.select(i)
	_search.text = ""
	_fill_list()
	if kind == "overview":
		_open("overview", null)
	else:
		_clear_preview()
		_detail.text = "Select an entry above."


func _fill_list() -> void:
	_rows.clear()
	_list.clear()
	var query := _search.text.strip_edges().to_lower()
	for row in _list_rows(_kind):
		if query == "" or row[1].to_lower().contains(query):
			_rows.append(row)
			_list.add_item(row[1])


func _list_rows(kind: String) -> Array:
	if kind == "overview":
		return []
	if kind == "tables":
		return _catalog().get("tables", []).map(func(t): return [t["table"], t["table"]])
	var rows := []
	for record in _data.records(GAME_DATA.ENTITIES[kind]):
		var ref = record.get("key", record.get("id"))
		var id_text := "%3d" % int(record["id"]) if record.get("id") != null else "  +"
		rows.append([ref, "%s  %s   %s" % [id_text, _label(kind, record), record.get("key", "")]])
	return rows


## Opens a page: an entity (kind, key or id), a table ("tables", name) or the overview.
func _open(kind: String, ref: Variant, remember := true) -> void:
	if remember and not _current.is_empty():
		_history.append(_current)
	_current = [kind, ref]
	_refresh_detail()


func _back() -> void:
	if _history.is_empty():
		return
	var page: Array = _history.pop_back()
	if page[0] != _kind and page[0] != "overview":
		_kind = page[0]
		for i in KINDS.size():
			if KINDS[i][1] == _kind:
				_kind_button.select(i)
		_fill_list()
	_open(page[0], page[1], false)


func _reload() -> void:
	_data.reload()
	_fill_list()
	_refresh_detail()


func _on_link(meta: Variant) -> void:
	var text := str(meta)
	var kind := text.get_slice(":", 0)
	var rest := text.substr(kind.length() + 1)
	match kind:
		"spec":
			OS.shell_open(ProjectSettings.globalize_path("res://").path_join(rest))
		"action":
			if rest == "check_assets":
				_asset_report = check_assets()
				_refresh_detail()
		"tables":
			_open("tables", rest)
		_:
			_open(kind, int(rest) if rest.is_valid_int() else rest)


func _refresh_detail() -> void:
	if _current.is_empty():
		return
	var kind: String = _current[0]
	_clear_preview()
	if kind == "overview":
		_detail.text = _overview_text()
	elif kind == "tables":
		_detail.text = _table_text(_current[1])
	else:
		_detail.text = entity_text(kind, _current[1])
		_preview(kind, _data.entity(kind, _current[1]))


# --- Pages -------------------------------------------------------------------------------------

## BBCode page of one entity: headline, components, cards, spec and C users of its main table.
func entity_text(kind: String, ref: Variant) -> String:
	var view: Dictionary = _data.entity(kind, ref)
	if view.is_empty():
		return "[color=red]No %s %s.[/color]" % [kind, ref]
	var main: Dictionary = view[kind]
	var table: String = GAME_DATA.ENTITIES[kind]
	var out := "[font_size=18][b]%s[/b][/font_size]  [code]%s[/code]  id %s\n" % [
		_label_name(kind, main), view["key"], view["id"] if view["id"] >= 0 else "— (added by a pack)"]
	out += _headline(kind, main) + "\n"
	var packs: PackedStringArray = _data.changed_by(table, ref)
	if not packs.is_empty():
		out += "[color=orange]Changed by: %s[/color]\n" % ", ".join(packs)
	for component in view:
		if component in ["kind", "key", "id"]:
			continue
		out += "\n[b]%s[/b]%s\n" % [component.capitalize(), "  [color=gray](%s)[/color]" % table if component == kind else ""]
		out += _format(view[component], component, 1)
	if kind == "digimon":
		var cards: Array = _data.cards_of(view["id"]) if view["id"] >= 0 else []
		out += "\n[b]Cards[/b]\n" + ("\t—\n" if cards.is_empty() else "".join(cards.map(
			func(c): return "\t[url=card:%s]%s[/url]  rarity %s, %s bits\n" % [c["key"], c["key"], _num(c.get("rarity")), _num(c.get("price"))])))
	out += _table_footer(table)
	return out


func _headline(kind: String, r: Dictionary) -> String:
	match kind:
		"digimon":
			var elements: Array = r.get("elements", []).filter(func(e): return e["name"] != "none").map(func(e): return e["name"])
			return "%s · %s · %s" % [_name_of(r.get("level")).capitalize(), _name_of(r.get("type")).capitalize(),
				" / ".join(elements.map(func(e): return e.capitalize()))]
		"move":
			return "%s · power %s · MP %s · %s · %s" % [str(r.get("category", "")).capitalize(), _num(r.get("power")), _num(r.get("mp")),
				_name_of(r.get("element")), _name_of(r.get("range"))]
		"item":
			return "%s bits · use: %s · %s" % [_num(r.get("price")), _name_of(r.get("usable")), _data.localize(r.get("description"))]
		"card":
			return "shows [url=digimon:%d]%s[/url] · rarity %s · %s bits" % [int(r["digimon"]["id"]), r["digimon"]["name"], _num(r.get("rarity")), _num(r.get("price"))]
		"map":
			return "file %s · %s%s" % [r.get("file", ""), "toilet · " if r.get("toilet") != null else "", "wild Digimon" if r.get("wild_digimon") else "no wild Digimon"]
		"tournament":
			return "grade %s · opponents' base stat %s" % [_data.localize(r.get("grade")), r.get("opponent_base_stat")]
	return ""


func _overview_text() -> String:
	var catalog := _catalog()
	var out := "[font_size=18][b]DW Data[/b][/font_size]\n"
	out += "Data: [code]%s[/code] %s\n" % [_data.root(), "" if _data.available() else "[color=red](missing: run python -m dwdata convert all)[/color]"]
	out += "Assets: [code]%s[/code] %s\n" % [Content.root(), "" if DirAccess.dir_exists_absolute(Content.root()) else "[color=red](missing: run python -m dwporter convert all)[/color]"]
	var mirrored := DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(Content.MIRROR_DIR))
	out += "Editor mirror: [code]%s[/code] %s\n" % [Content.MIRROR_DIR, "present" if mirrored else "not made (Project > Tools > DW: Mirror dw1 assets)"]
	out += "Packs: %s\n" % ", ".join(_data.packs())
	out += "\n[b]Data porter checks[/b]\n"
	var groups: Dictionary = catalog.get("groups", {})
	for group in groups:
		var checks: Dictionary = groups[group]["checks"]
		var ok: bool = checks["passed"] == checks["total"]
		out += "\t[color=%s]%s[/color] %s: %d/%d  [url=spec:data_porter/%s]%s[/url]\n" % [
			"green" if ok else "red", "✔" if ok else "✘", group, checks["passed"], checks["total"], groups[group]["spec"], groups[group]["spec"]]
	out += "\n[b]Entities[/b]\n"
	for k in KINDS:
		if GAME_DATA.ENTITIES.has(k[1]):
			out += "\t%s: %d\n" % [k[0], _data.records(GAME_DATA.ENTITIES[k[1]]).size()]
	out += "\n[url=action:check_assets][b]▶ Check assets[/b][/url]  every Digimon model, map background and card image the data points to\n"
	if _asset_report != "":
		out += _asset_report
	return out


## Checks that every Digimon, map and card links to an asset Content can load. Returns BBCode.
func check_assets() -> String:
	var missing := {"digimon": [], "map": [], "card": []}
	var imported := {"digimon": 0, "map": 0, "card": 0}
	var total := {"digimon": 0, "map": 0, "card": 0}
	for kind in missing:
		for record in _data.records(GAME_DATA.ENTITIES[kind]):
			var rel := asset_path(kind, record)
			if rel == "":
				continue
			total[kind] += 1
			if not Content.exists(rel):
				missing[kind].append("[url=%s:%s]%s[/url]" % [kind, record.get("key", ""), record.get("key", rel)])
			elif Content.imported(rel) != "":
				imported[kind] += 1
	var out := "\n[b]Assets[/b]  (imported = loaded from the editor mirror)\n"
	for kind in missing:
		var bad: Array = missing[kind]
		out += "\t[color=%s]%s[/color] %s: %d/%d found, %d imported%s\n" % [
			"green" if bad.is_empty() else "orange", "✔" if bad.is_empty() else "!", kind,
			total[kind] - bad.size(), total[kind], imported[kind], ("; missing: " + ", ".join(bad)) if not bad.is_empty() else ""]
	return out + "\tKnown gaps of the original disc: Digimon 62 (WereGarurumon) and 114 have no model; maps YAKA01 and YAKA21 have no files (docs/dw_data_dock.md).\n"


func _table_text(table_name: String) -> String:
	var info: Dictionary = {}
	for t in _catalog().get("tables", []):
		if t["table"] == table_name:
			info = t
	var table: Dictionary = _data.table(table_name)
	var out := "[font_size=18][b]%s[/b][/font_size]\n%s\n" % [table_name, info.get("purpose", "")]
	out += "%d records%s · C: %s\n" % [table.get("records", []).size(), " · keyed" if info.get("keyed") else "", ", ".join(info.get("symbols", []))]
	var godot: Dictionary = table.get("godot", {})
	if godot.has("access"):
		out += "Godot: [code]%s[/code]\n" % godot["access"]
	if godot.get("notes", "") != "":
		out += "[i]%s[/i]\n" % godot["notes"]
	out += "\n[b]Fields[/b]\n"
	var schema: Dictionary = table.get("schema", {})
	for field in schema:
		if field.begins_with("_") or not schema[field] is Dictionary:
			continue
		out += "\t[b]%s[/b]  %s\n" % [field, schema[field].get("meaning", schema[field].get("c_name", ""))]
	var rows: Array = table.get("records", [])
	out += "\n[b]First records[/b]\n"
	for i in min(3, rows.size()):
		out += "\t[u]#%d[/u]\n%s" % [i, _format(rows[i], "", 2)]
	return out + _table_footer(table_name)


func _table_footer(table_name: String) -> String:
	var table: Dictionary = _data.table(table_name)
	var spec := ""
	for t in _catalog().get("tables", []):
		if t["table"] == table_name:
			spec = t["spec"]
	var out := "\n[b]Spec[/b]  [url=spec:data_porter/%s]%s[/url]\n" % [spec, spec] if spec != "" else ""
	var users: Array = table.get("used_by", [])
	if not users.is_empty():
		out += "[b]Used by the C code[/b] (%d)\n" % users.size()
		for u in users.slice(0, 12):
			if u is Dictionary and u.has("in"):
				var lines: Array = u.get("lines", [u.get("line", "")])
				out += "\t[code]%s[/code]  %s:%s%s\n" % [u["in"], u["file"], lines[0] if not lines.is_empty() else "",
					("  reads " + ", ".join(u["fields"])) if not u.get("fields", []).is_empty() else ""]
		if users.size() > 12:
			out += "\t… %d more (the table's used_by)\n" % (users.size() - 12)
	return out


# --- Formatting --------------------------------------------------------------------------------

## A value as indented BBCode lines; references become links, names show the current language.
func _format(value: Variant, key: String, depth: int) -> String:
	var tabs := "\t".repeat(depth)
	if value is Dictionary:
		if value.has("text") and value["text"] is Dictionary:
			return tabs + _data.localize(value) + "\n"
		var out := ""
		for k in value:
			if k in RAW_FIELDS and not _show_raw:
				continue
			var v = value[k]
			if _inline(v, k):
				out += "%s[color=gray]%s:[/color] %s\n" % [tabs, k, _inline_text(v, k)]
			else:
				out += "%s[color=gray]%s:[/color]\n%s" % [tabs, k, _format(v, k, depth + 1)]
		return out
	if value is Array:
		var out := ""
		for i in value.size():
			out += _format(value[i], key, depth) if value[i] is Dictionary and not _is_ref(value[i]) else tabs + _inline_text(value[i], key) + "\n"
		return out
	return tabs + _inline_text(value, key) + "\n"


func _inline(value: Variant, key: String) -> bool:
	if value is Dictionary:
		return _is_ref(value) or (value.has("text") and value["text"] is Dictionary) or value.is_empty()
	if value is Array:
		return value.all(func(v): return not v is Dictionary or _is_ref(v)) and str(value).length() < 160
	return true


func _inline_text(value: Variant, key: String) -> String:
	if value is Dictionary:
		if value.has("text") and value["text"] is Dictionary:
			return _data.localize(value).strip_edges()
		if _is_ref(value):
			return _ref_text(value, key)
		return "—"
	if value is Array:
		return ", ".join(value.map(func(v): return _inline_text(v, key)))
	if value is float and value == floorf(value):
		value = int(value)
	if REF_KINDS.has(key) and (value is int):
		return _link(REF_KINDS[key], value, _label_name(REF_KINDS[key], _data.record(GAME_DATA.ENTITIES[REF_KINDS[key]], value)))
	return "—" if value == null else str(value)


static func _is_ref(value: Variant) -> bool:
	return value is Dictionary and value.has("id") and value.has("name") and value.size() <= 3 and not value["name"] is Dictionary


func _ref_text(ref: Dictionary, key: String) -> String:
	var id := int(ref["id"]) if ref["id"] != null else -1
	if REF_KINDS.has(key) and id >= 0:
		return _link(REF_KINDS[key], id, str(ref["name"]))
	return "%s (%s)" % [ref["name"], id]


func _link(kind: String, id: int, text: String) -> String:
	return "[url=%s:%d]%s[/url] [color=gray]#%d[/color]" % [kind, id, text if text != "" else "?", id]


func _label(kind: String, record: Dictionary) -> String:
	return _label_name(kind, record)


func _label_name(kind: String, record: Dictionary) -> String:
	if record.is_empty():
		return ""
	match kind:
		"card":
			return "Card: %s" % record["digimon"]["name"]
		"map":
			return "%s (%s)" % [_data.localize(record.get("name")).strip_edges(), record.get("file", "")]
	var name_value = record.get("name")
	return _data.localize(name_value) if name_value is Dictionary else str(name_value)


## A JSON number as an int, "—" for null or anything else.
static func _num(value: Variant) -> String:
	return str(int(value)) if value is float or value is int else "—"


static func _name_of(ref: Variant) -> String:
	return str(ref["name"]) if ref is Dictionary and ref.has("name") else ""


# --- Preview -----------------------------------------------------------------------------------

## Pack-relative asset of an entity record: Digimon model, map background, card image ("" if none).
func asset_path(kind: String, record: Dictionary) -> String:
	match kind:
		"digimon":
			var files: Dictionary = _data.digimon_file(int(record["id"])) if record.get("id") != null else {}
			var mmd: String = files.get("mmd", "")
			return "mmd_files/" + mmd.get_slice("/", 1) + "/" + mmd.get_file().get_basename() + ".gltf" if mmd != "" else ""
		"map":
			return "maps/%s/background_0.png" % record["file"] if record.get("file", "") != "" else ""
		"card":
			return "card_all/card_%02d.png" % int(record["id"]) if record.get("id") != null else ""
	return ""


func _preview(kind: String, view: Dictionary) -> void:
	if view.is_empty():
		return
	var rel := asset_path(kind, view[kind])
	if rel == "":
		return
	_preview_box.visible = true
	if not Content.exists(rel):
		_source_label.text = "Asset %s: not found (neither imported nor in the porter output)." % rel
		return
	_source_label.text = "Asset %s: %s" % [rel, "imported copy " + Content.imported(rel) if Content.imported(rel) != "" else "raw file " + Content.path(rel)]
	if rel.ends_with(".png"):
		_image.texture = Content.load_texture(rel)
		_image.visible = true
		return
	var model := Content.load_model(rel)
	if model == null:
		return
	_model_root.add_child(model)
	_viewport.get_parent().visible = true
	_frame(model)
	var players := model.find_children("*", "AnimationPlayer", true, false)
	if players.is_empty():
		return
	_player = players[0]
	_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_anim_button.clear()
	for anim_name in _player.get_animation_list():
		_anim_button.add_item(anim_name)
	_anim_button.visible = _anim_button.item_count > 0
	if _anim_button.item_count > 0:
		_anim_button.select(0)
		_play(_anim_button.get_item_text(0))


func _play(anim_name: String) -> void:
	if _player == null or not _player.has_animation(anim_name):
		return
	_player.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
	_player.play(anim_name)
	_player.advance(0.0)


## Puts the camera in front of the model's bounding box.
func _frame(model: Node3D) -> void:
	var box := AABB()
	var first := true
	for mesh in model.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mesh.global_transform * mesh.get_aabb()
		box = b if first else box.merge(b)
		first = false
	var radius := maxf(box.size.length() * 0.5, 1.0)
	_camera.near = radius * 0.01
	_camera.far = radius * 20.0
	_camera.position = box.get_center() + Vector3(0, radius * 0.3, radius * 2.6)
	_camera.look_at(box.get_center())


func _clear_preview() -> void:
	_player = null
	for child in _model_root.get_children():
		child.queue_free()
	_model_root.rotation = Vector3.ZERO
	_image.texture = null
	_image.visible = false
	_viewport.get_parent().visible = false
	_anim_button.visible = false
	_source_label.text = ""
	_preview_box.visible = false


func _catalog() -> Dictionary:
	var json = JSON.parse_string(FileAccess.get_file_as_string(_data.root().path_join("catalog.json")))
	return json if json is Dictionary else {}
