class_name MapProps
extends RefCounted
## The field props' logic (specs/map_events.md §4.1.1): positions, matrices, lids, pedestal,
## pile counter, unload, and daytime removal.
## Mirrors map_object.c loadStaticTMD / drawObject props (cart, pile, boulder, boxes, gearbox, pedestal).

## map_object.c:73, 74, 76, 80, 85, 86, 88, 90
const MODELS := {
	&"cart": "tmd_files/ETCNA/DOSYA.gltf",
	&"cart_box": "tmd_files/ETCNA/HAKO.gltf",
	&"pile": "tmd_files/ETCNA/T_YAMA.gltf",
	&"boulder": "tmd_files/ETCNA/IWA.gltf",
	&"big_box": "tmd_files/ETCNA/BIGBOX.gltf",
	&"small_box": "tmd_files/ETCNA/SMABOX.gltf",
	&"gearbox": "tmd_files/ETCNA/GAND.gltf",
	&"pedestal": "tmd_files/ETCNA/ABOX.gltf",
}

## map_object.c:81
const BOULDER_TEXTURE := "ETCNA/IWA1.TIM"

## map_object.c:75
const DIRT_PILE_LOCATION := Vector3i(2037, 0, 849)

## map_object.c:626-628
const BOULDER_SPAWN_TRANSLATION := Vector3i(-300, -500, 2000)

## map_object.c:79, 96
const BOULDER_SCALE := Vector3i(0x1000, 0x1000, 0x1000)

## map_object.c:83
const BIG_BOX_LOCATION := Vector3i(500, -600, 600)

## map_object.c:84
const SMALL_BOX_LOCATION := Vector3i(-400, -400, 600)

## map_object.c:87
const GEARBOX_LOCATION := Vector3i(-100, 0, 1700)

## map_object.c:784, 785
const PEDESTAL_START_X := 0
const PEDESTAL_START_Z := 1500

## map_object.c:1169, 1178
const PEDESTAL_STEP_Z := 10
const PEDESTAL_END_Z := 2000

## map_object.c:715-717, 728-730
const LID_STEP := 100
const LID_OPEN_FLOOR := -0x400

## Session dictionary holding persistent runtime state (dirt_pile_size).
var session: Dictionary

## map_object.c:51 (ACTIVE_DIRT_CART_MODEL: 0 cart, 1 box, 2 none)
var cart_model: int = 2

## map_object.c:626-631 (MAP_3D_OBJ[0])
var boulder_translation: Vector3i = Vector3i.ZERO
var boulder_rotation: Vector3i = Vector3i.ZERO

## map_object.c:55 (TOY_TOWN_SELECTED_BOX: 0 none, 1 big, 2 small)
var selected_box: int = 0

## map_object.c:54 (BOX_LID_PROGRESS)
var big_lid: int = 0
var small_lid: int = 0

## map_object.c:57-58 (ANGEMON_PEDESTAL_PROGRESS_X / Z)
var pedestal_x: int = 0
var pedestal_z: int = 0

## Prop group -> loaded bool (cart, pile, boulder, boxes, gearbox, pedestal)
var loaded: Dictionary = {
	&"cart": false,
	&"pile": false,
	&"boulder": false,
	&"boxes": false,
	&"gearbox": false,
	&"pedestal": false,
}


func _init(p_session: Dictionary) -> void:
	session = p_session


## loadDirtCartModel (map_object.c:423)
func load_dirt_cart() -> void:
	loaded[&"cart"] = true
	cart_model = 2


## setDirtCartModel (map_object.c:1186)
func set_dirt_cart_model(m: int) -> void:
	cart_model = PsxMath.s8(m)


## loadDirtPileModel (map_object.c:1205)
func load_dirt_pile() -> void:
	loaded[&"pile"] = true


## DIRT_PILE_SIZE_COUNTER (map_object.c:69)
func dirt_pile_size() -> int:
	return int(session.get("dirt_pile_size", 15))


## decreaseDirtPileSize (map_object.c:1109)
func decrease_dirt_pile() -> void:
	session["dirt_pile_size"] = PsxMath.s8(dirt_pile_size() - 1)


## spawnBoulder (map_object.c:616)
func spawn_boulder() -> void:
	loaded[&"boulder"] = true
	boulder_translation = BOULDER_SPAWN_TRANSLATION
	boulder_rotation = Vector3i.ZERO


## moveBoulder (map_object.c:1130)
func move_boulder(dx: int, dz: int) -> void:
	boulder_translation.y += PsxMath.s16(dx)
	boulder_translation.z += PsxMath.s16(dz)
	boulder_rotation.x = PsxMath.s16(boulder_rotation.x - 10)


## Opcode 0x78 / unloadMapParts (map_object.c:923)
func despawn_boulder() -> void:
	loaded[&"boulder"] = false


## spawnToyTownBoxes (map_object.c:662)
func spawn_toy_town_boxes() -> void:
	loaded[&"boxes"] = true
	big_lid = 0
	small_lid = 0
	selected_box = 0


## openToyTownBox (map_object.c:1148)
func open_box(b: int) -> void:
	selected_box = PsxMath.s8(b)


## somethingToyTown (map_object.c:1156)
func set_box(b: int, trigger_350: bool) -> bool:
	selected_box = PsxMath.s8(b)
	return selected_box == 0 and trigger_350


## spawnGearbox (map_object.c:749)
func spawn_gearbox() -> void:
	loaded[&"gearbox"] = true
	selected_box = 0


## spawnAngemonPedestal (map_object.c:775)
func spawn_pedestal() -> void:
	loaded[&"pedestal"] = true
	pedestal_x = PEDESTAL_START_X
	pedestal_z = PEDESTAL_START_Z


## moveAngemonPedestal (map_object.c:1167)
func move_pedestal() -> bool:
	pedestal_z = PsxMath.s16(pedestal_z + PEDESTAL_STEP_Z)
	pedestal_x = 5 if pedestal_z % 20 == 0 else -5
	if pedestal_z > 1999:
		pedestal_z = PEDESTAL_END_Z
		return true
	return false


## unloadMapParts (map_object.c:917)
func unload() -> void:
	for g in [&"cart", &"pile", &"boulder", &"boxes", &"gearbox", &"pedestal"]:
		loaded[g] = false


## updateTimeOfDay (map.c:4307-4308), stand-in: pedestal slot < daytime transition slot
func on_daytime_removal(target: int) -> bool:
	if target == 0 and loaded.get(&"pedestal", false):
		loaded[&"pedestal"] = false
		return true
	return false


## renderToyTownBoxes (map_object.c:713-738)
func tick_render(map_layer_on: bool) -> void:
	if not map_layer_on:
		return
	if selected_box == 1:
		big_lid = maxi(LID_OPEN_FLOOR, big_lid - LID_STEP)
	elif selected_box == 2:
		small_lid = maxi(LID_OPEN_FLOOR, small_lid - LID_STEP)


## render* (map_object.c:430, 437, 650, 713, 769, 798)
func drawn(prop: StringName) -> bool:
	match prop:
		&"cart":
			return loaded.get(&"cart", false) and cart_model != 2
		&"pile":
			return loaded.get(&"pile", false) and dirt_pile_size() >= 6
		&"boulder":
			return loaded.get(&"boulder", false)
		&"big_box", &"big_lid", &"small_box", &"small_lid":
			return loaded.get(&"boxes", false)
		&"gearbox":
			return loaded.get(&"gearbox", false)
		&"pedestal":
			return loaded.get(&"pedestal", false)
		_:
			return false


## Returns the PSX 3x4 transform matrix for a prop (not cart).
func transform(prop: StringName) -> PackedInt32Array:
	match prop:
		&"pile":
			# loadDirtPileModel (map_object.c:1218-1225)
			var s := PsxMath.s16(PsxMath.div(dirt_pile_size() * 0x1000, 15))
			return PsxMath.trans_matrix(
				PsxMath.scale_matrix(PsxMath.rot_matrix(Vector3i.ZERO), Vector3i(s, s, s)),
				DIRT_PILE_LOCATION
			)
		&"boulder":
			# projectPosition (map_object.c:639)
			return PsxMath.trans_matrix(
				PsxMath.scale_matrix(PsxMath.rot_matrix(boulder_rotation), BOULDER_SCALE),
				boulder_translation
			)
		&"big_box":
			# spawnToyTownBoxes (map_object.c:698)
			return PsxMath.trans_matrix(PsxMath.identity(), BIG_BOX_LOCATION)
		&"small_box":
			# spawnToyTownBoxes (map_object.c:700)
			return PsxMath.trans_matrix(PsxMath.identity(), SMALL_BOX_LOCATION)
		&"big_lid":
			# renderToyTownBoxes (map_object.c:723)
			return PsxMath.rot_matrix(Vector3i(big_lid, 0, 0))
		&"small_lid":
			# renderToyTownBoxes (map_object.c:736)
			return PsxMath.rot_matrix(Vector3i(small_lid, 0, 0))
		&"gearbox":
			# spawnGearbox (map_object.c:759)
			return PsxMath.trans_matrix(PsxMath.identity(), GEARBOX_LOCATION)
		&"pedestal":
			# renderAngemonPedestal (map_object.c:802)
			return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(pedestal_x, 0, pedestal_z))
		_:
			return PsxMath.identity()


## renderDirtCartModel (map_object.c:1256-1265)
func cart_transform(location: Vector3i, rotation: Vector3i, radius: int) -> PackedInt32Array:
	var m := PsxMath.rot_matrix(rotation)
	var w := PsxMath.apply_matrix_lv(m, Vector3i(0, 0, radius + 100))
	w.x += location.x
	w.z += location.z
	return PsxMath.trans_matrix(m, w)
