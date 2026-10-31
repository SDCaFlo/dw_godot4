class_name MapItems
extends Node3D
## The items lying on the field (specs/map_items.md §2.1): DROPPED_ITEMS[11] (item.c:61), put there
## by SPAWN_ITEM (spawnItem, item.c:2437) and taken by the tamer (checkItemPickup, pickupItem).
##
## Each item is its ITEM.TIM icon facing the camera at the tile's centre (renderOverworldItem,
## item.c:2478): a 128-unit square at its depth, so the models sort against it by depth as on the
## PSX. Under it a 200 x 200 subtractive shadow on the ground (renderDroppedItemShadow), with the
## entities' shadow material (DropShadow).

## DROPPED_ITEMS' slots.
const SLOTS := 11
## The icon shows a 128-unit square of the world at its depth (width = VIEWPORT_DISTANCE << 7 / SZ).
const ICON_SIZE := 128.0
## renderOverworldItem: from 0x20 pixels wide the UV is 15 x 15 (the icon's last row and column go).
const NEAR_WIDTH := 0x20
const SHADOW_SIZE := 200.0
const ICONS := "tim_files/ETCDAT/ITEM%s.png"

## The icon's shader (a mod may replace it).
const _ICON_SHADER := preload("res://shaders/map_item_icon.gdshader")

## The field map (camera, tiles).
var field: FieldMap
## The GameData node (item records).
var data: Node
## slot -> {"item": key, "id": int, "tile": Vector2i, "point": Vector3 (PSX), "icon", "shadow"};
## null when empty.
var slots: Array = []

var _icon_textures := {}


func _init() -> void:
	slots.resize(SLOTS)


## spawnItem (item.c:2437): the first empty slot takes the item at the tile's centre, at the
## tamer's height `y`; none free: nothing.
func spawn(item: Variant, tile: Vector2i, y := 0) -> int:
	for k in SLOTS:
		if slots[k] != null:
			continue
		var record: Dictionary = data.item(item) if data != null else {}
		var point := Vector3((tile.x - 50) * 100 + 50, y, (50 - tile.y) * 100 - 50)
		var slot := {"item": record.get("key", str(item)), "id": int(record.get("id", item if item is int else 0)),
				"clut": int(record.get("icon_clut", 0)), "tile": tile, "point": point}
		slots[k] = slot
		_make_nodes(slot)
		return k
	return -1


## checkItemPickup's test (tamer.c:618): the first item within one tile of `tile`, or -1.
func near(tile: Vector2i) -> int:
	for k in SLOTS:
		var slot = slots[k]
		if slot != null and absi(slot["tile"].x - tile.x) <= 1 and absi(slot["tile"].y - tile.y) <= 1:
			return k
	return -1


## deleteDroppedItem (item.c:2462).
func remove(k: int) -> void:
	var slot = slots[k]
	if slot == null:
		return
	for part in ["icon", "shadow"]:
		if slot.get(part) != null:
			slot[part].queue_free()
	slots[k] = null


## clearDroppedItems (item.c:2468): changeMap drops every item.
func clear() -> void:
	for k in SLOTS:
		remove(k)


func item_at(k: int) -> String:
	return slots[k]["item"] if k >= 0 and k < SLOTS and slots[k] != null else ""


func _make_nodes(slot: Dictionary) -> void:
	if field == null:
		return
	var icon := MeshInstance3D.new()
	icon.mesh = QuadMesh.new()
	icon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	icon.material_override = _icon_material(slot)
	add_child(icon)
	slot["icon"] = icon
	var shadow := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(SHADOW_SIZE, SHADOW_SIZE)
	quad.orientation = PlaneMesh.FACE_Y
	shadow.mesh = quad
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	shadow.material_override = DropShadow.material()
	shadow.position = Content.psx_to_godot([slot["point"].x, 0, slot["point"].z]) + Vector3(0, DropShadow.LIFT, 0)
	add_child(shadow)
	slot["shadow"] = shadow
	_place(slot)


## The icon faces the camera at its point; renderOverworldItem's 15 x 15 UV when it is drawn at
## least 0x20 pixels wide.
func _place(slot: Dictionary) -> void:
	var icon: MeshInstance3D = slot.get("icon")
	if icon == null or field == null or field.camera == null:
		return
	var world := Content.psx_to_godot([slot["point"].x, slot["point"].y, slot["point"].z])
	icon.transform = Transform3D(field.camera.global_transform.basis, world)
	(icon.mesh as QuadMesh).size = Vector2(ICON_SIZE, ICON_SIZE)
	var depth := field.view_depth(world)
	var width := field.projection() * ICON_SIZE / depth if depth > 0 else 0.0
	var cell := 15.0 if width >= NEAR_WIDTH else 16.0
	var id: int = slot["id"]
	var u := (id % 16) * 16.0
	var v := (id / 16) * 16.0
	# setItemTexture: 15 texels on the last row / column
	var w := 15.0 if u == 0xF0 else cell
	var h := 15.0 if v == 0xF0 else cell
	var mat := icon.material_override as ShaderMaterial
	mat.set_shader_parameter("region", Vector4(u / 256.0, v / 128.0, w / 256.0, h / 128.0))
	icon.visible = depth > 0


## Every frame: the icons keep facing the camera (the camera moves with the scroll).
func _process(_delta: float) -> void:
	for slot in slots:
		if slot != null:
			_place(slot)


func _icon_material(slot: Dictionary) -> ShaderMaterial:
	var clut: int = slot["clut"]
	if not _icon_textures.has(clut):
		_icon_textures[clut] = Content.load_texture(ICONS % ("" if clut == 0 else ".p%d" % clut))
	var m := ShaderMaterial.new()
	m.shader = _ICON_SHADER
	m.set_shader_parameter("tex", _icon_textures[clut])
	return m

