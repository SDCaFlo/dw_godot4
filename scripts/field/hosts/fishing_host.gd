class_name FishingHost
extends Node
## Fishing on the field (specs/fishing.md §5.2; main/fish.c): made at every map load on a map with
## fishing data (checkFishingMap), ticked as the world object (FISH_tickFishingWorld) in the field's
## frame, the rod ticked by the tamer's state 11 (tamerTickFishing). The two windows are UI boxes 2
## and 3 with the logic's tick functions; their contents are drawn by the view (step F5).

## triggerSeadramonCutscene (script_common.c:3057): callScriptSection(0, 0x4E4, 0).
const SEADRAMON_SECTION := 0x4E4

var field_map: FieldMap
var tamer: Tamer
var partner: Partner
var clock: Clock
var boxes: UIBoxes
var interpreter: ScriptInterpreter
var game_state: Node
var data: Node
var sound: Node
## The pad (GameLoop.pad).
var pad: Pad
## The game frame (VSync(-1) / 3): GameLoop.frame_count.
var frame_count := Callable()

## FISHING_DATA_PTR: null off the fishing maps.
var fishing: Fishing
var rod: FishingRod
var world: FieldFishingWorld
## Emitted when a session starts or ends, for the view (F5).
signal session_changed


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")


## checkFishingMap (main/fish.c:117): the last map's fishing goes; a fishing map gets a fresh one;
## game time runs again (startGameTime, on every map).
func check_map(map_id: int) -> void:
	deinitialize()
	var map_data: Dictionary = data.fishing_map(map_id) if data != null and map_id >= 0 else {}
	if not map_data.is_empty():
		fishing = Fishing.new()
		fishing.setup(map_data, data.fishing()["kinds"])
		_refresh_camera()
		world = FieldFishingWorld.new()
		world.tamer = tamer
		world.field_map = field_map
		world.game_state = game_state
		world.data = data
		world.sound = sound
		rod = FishingRod.new()
		rod.setup(fishing, world, pad, data.fishing()["snagged_items"])
		_connect_boxes()
		session_changed.emit()
	if clock != null:
		clock.running = true


## deinitializeFishing (main/fish.c:109): FISH_deinitialize, then no fishing until the next map.
func deinitialize() -> void:
	if fishing == null:
		return
	# FISH_deinitialize (fish.c:4639): enabled, the object removed, endFishing, the pools and the
	# hooked fish cleared; then FISHING_DATA_PTR = NULL drops it all.
	fishing.disabled = false
	rod.end_fishing()
	rod.hooked.active = false
	fishing = null
	rod = null
	world = null
	session_changed.emit()


## getFishingAvailability (main/fish.c:59): 0 none, 1 the icon disabled (no rod or no food), 2 ready.
func availability() -> int:
	if fishing == null or fishing.disabled:
		return 0
	if world.best_rod() == 0 or not rod.has_food():
		return 1
	return 2


## The menu's Fishing (game_menu.c:2215): initializeFishing (FISH_loadFishing), tamer state 11.
func start_from_menu() -> void:
	if fishing == null:
		return
	rod.load_fishing()
	tamer.set_state(Tamer.STATE_FISHING)


## setFishingDisabled / setFishingEnabled (main/fish.c:45-57).
func set_disabled(on: bool) -> void:
	if fishing != null:
		fishing.disabled = on


## isFishing (main/fish.c:96).
func is_fishing() -> bool:
	return rod != null and rod.is_fishing()


## FISH_tickFishingWorld, once per game frame in the object order.
func tick_world() -> void:
	if fishing == null:
		return
	_refresh_camera()
	fishing.vsync_frame = int(frame_count.call()) if frame_count.is_valid() else 0
	fishing.hour = int(game_state.state["clock"]["hour"]) if game_state != null else 0
	fishing.partner_evolving = partner != null and partner.state == Partner.STATE_EVOLVING
	rod._sync()
	fishing.tick_world()


## tamerTickFishing (main/fish.c:81), the tamer's state 11.
func tamer_tick() -> void:
	if fishing == null:
		tamer.set_state(Tamer.STATE_FREE)
		return
	_refresh_camera()
	match rod.tamer_tick():
		FishingRod.TICK_ENDED:
			tamer.set_state(Tamer.STATE_FREE)
			if clock != null:
				clock.running = true
		FishingRod.TICK_SEADRAMON:
			tamer.set_state(Tamer.STATE_FREE)
			set_disabled(true)
			if interpreter != null:
				interpreter.call_section(0, SEADRAMON_SECTION)


## The camera as the C reads it this frame (GsWSMATRIX, VIEWPORT_DISTANCE, the drawing offset).
func _refresh_camera() -> void:
	if fishing == null or field_map == null:
		return
	var cam := fishing.camera
	cam.ws = field_map.world_screen_matrix()
	cam.h = field_map.viewport_distance()
	cam.background = Vector2i(field_map.background_size)
	cam.offset = Vector2i(field_map.drawing_offset().round())


## The windows as UI boxes with their tick functions (the view adds their contents, F5).
func _connect_boxes() -> void:
	if boxes == null:
		return
	var menu := rod.bait_menu
	menu.box_animating = func() -> bool:
		var b: UIBoxes.Box = boxes.boxes[FishingBaitMenu.BOX_ID]
		return b.state == UIBoxes.STATE_OPENING or b.state == UIBoxes.STATE_CLOSING
	menu.opened.connect(func() -> void:
		boxes.create_animated(FishingBaitMenu.BOX_ID, 0, menu.features(), FishingBaitMenu.BOX_RECT, menu.start_rect,
				func(_id: int) -> void: menu.tick(pad)))
	menu.closed.connect(func() -> void: boxes.remove_animated(FishingBaitMenu.BOX_ID, menu.start_rect))
	var box := rod.text_box
	box.opened.connect(func() -> void:
		boxes.create_static(FishingTextBox.BOX_ID, 0, UIBoxes.FEATURE_HALF_FILL, FishingTextBox.BOX_RECT,
				func(_id: int) -> void: box.tick(pad)))
	box.closed.connect(func() -> void: boxes.remove_static(FishingTextBox.BOX_ID))
