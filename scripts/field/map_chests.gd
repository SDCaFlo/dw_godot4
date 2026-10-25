class_name MapChests
extends Node3D
## The treasure chests of the map (specs/map_items.md §2.3): CHEST_ARRAY[8] (map_object.c:98),
## put there by SPAWN_CHEST (spawnChest, map_object.c:841), opened by the tamer (tamer state 14).
## The model is ETCNA/TAKA.TMD: the box (object 0) and its tray (object 1), the tray placed
## relative to the box (CHEST_COORDS[1]'s parent is CHEST_COORDS[0]), so it slides out along the
## box's own axis.

const SLOTS := 8
const MODEL := "tmd_files/ETCNA/TAKA.gltf"
## tickOpenChestTray / tickCloseChestTray: 20 a frame, out to -160.
const TRAY_STEP := 20
const TRAY_OUT := -160

## The field map (blocked cells).
var field: FieldMap
## The GameState node (the chests' triggers).
var game_state: Node
## slot -> {"item": int id, "trigger", "taken", "tray", "rotation", "location": Vector3i (PSX),
## "tile": Vector2i (the interaction tile), "node"}; null when empty.
var slots: Array = []


func _init() -> void:
	slots.resize(SLOTS)


## spawnChest (map_object.c:841): the first empty slot. Taken (its trigger set): tray out. The chest
## stands at its tile's centre and blocks the 4 x 4 cells around it (setImpassableSquare(x, y, 2));
## its interaction tile is 4 tiles in front of it, toward the tray.
func spawn(item: int, point: Vector3i, rotation: int, trigger: int) -> int:
	for k in SLOTS:
		if slots[k] != null:
			continue
		var taken: bool = game_state != null and game_state.is_trigger_set(trigger)
		var tile := FieldMap.model_tile(point.x, point.z)
		if field != null:
			# setImpassableSquare (map_collision.c:161, US): x - 2 .. x + 1, y - 2 .. y + 1
			field.set_impassable_rect(tile.x - 2, tile.y - 2, 4, 4)
		var interaction := tile
		if rotation == 0:
			interaction.y += 4
		elif rotation == 0x800:
			interaction.y -= 4
		if rotation == 0x400:
			interaction.x -= 4
		elif rotation == 0xC00:
			interaction.x += 4
		var slot := {"item": item, "trigger": trigger, "taken": taken, "tray": TRAY_OUT if taken else 0,
				"rotation": rotation, "location": Vector3i(tile.x * 100 - 4950, 0, 4950 - tile.y * 100),
				"tile": interaction, "node": null}
		slots[k] = slot
		_make_node(slot)
		return k
	return -1


## checkChestCollision (tamer.c:1287): the first chest whose interaction tile is within one tile
## of `tile`, or -1.
func near(tile: Vector2i) -> int:
	for k in SLOTS:
		var slot = slots[k]
		if slot != null and absi(slot["tile"].x - tile.x) <= 1 and absi(slot["tile"].y - tile.y) <= 1:
			return k
	return -1


func chest(k: int) -> Dictionary:
	return slots[k] if k >= 0 and k < SLOTS and slots[k] != null else {}


## tickOpenChestTray (map_object.c:1083): true (and taken) once the tray is out.
func tick_open(k: int) -> bool:
	var slot: Dictionary = slots[k]
	slot["tray"] -= TRAY_STEP
	var done := false
	if slot["tray"] < TRAY_OUT + 1:
		slot["tray"] = TRAY_OUT
		slot["taken"] = true
		done = true
	_place(slot)
	return done


## tickCloseChestTray (map_object.c:1096): true (and not taken) once the tray is back in.
func tick_close(k: int) -> bool:
	var slot: Dictionary = slots[k]
	slot["tray"] += TRAY_STEP
	var done := false
	if slot["tray"] >= 0:
		slot["tray"] = 0
		slot["taken"] = false
		done = true
	_place(slot)
	return done


## emptyChests (map_object.c:925), when the map is unloaded.
func clear() -> void:
	for k in SLOTS:
		if slots[k] != null and slots[k]["node"] != null:
			slots[k]["node"].queue_free()
		slots[k] = null


func _make_node(slot: Dictionary) -> void:
	if not is_inside_tree() or not Content.exists(MODEL):
		return
	var model := Content.load_model(MODEL)
	if model == null:
		return
	add_child(model)
	slot["node"] = model
	_place(slot)


## renderChest (map_object.c:467): the box at its location and yaw, the tray at (0, 0, tray) of it.
func _place(slot: Dictionary) -> void:
	var model: Node3D = slot["node"]
	if model == null:
		return
	var p: Vector3i = slot["location"]
	model.position = Content.psx_to_godot([p.x, p.y, p.z])
	model.rotation = Vector3(0, Content.psx_yaw(slot["rotation"]), 0)
	var tray := model.find_child("object_1", true, false) as Node3D
	if tray != null:
		tray.position = Content.psx_to_godot([0, 0, slot["tray"]])
