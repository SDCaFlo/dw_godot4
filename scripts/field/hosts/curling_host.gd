class_name CurlingHost
extends Node
## Curling on the field (specs/curling.md §5.2; the KAR_REL overlay, src/kar/kar.c, and its hooks in
## src/main): checkCurlingMap notes at every map load whether the map has curling, digimon routine 1
## (KAR_start) makes the match, the world object 0x1388 (KAR_tickStones, KAR_renderScene's placement)
## ticks in the field's frame, and the tamer's state 12 calls tamer_tick (KAR_tick). The drawing (the
## stones, the HUD, the box's contents) is the view's (step C5).

var tamer: Tamer
var entities: FieldEntities
var field_map: FieldMap
var overlays: MapOverlays
var boxes: UIBoxes
var text_area: TextArea
var interpreter: ScriptInterpreter
var game_state: Node
var data: Node
var sound: Node
## The pad (GameLoop.pad).
var pad: Pad

## The match of KAR_start: null off the curling maps and before routine 1 (and after the next map load).
var match: CurlingMatch
var world: FieldCurlingWorld
## The curling data of the loaded map (GameData.curling_map), {} when it has none.
var map_data := {}


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	if sound == null:
		sound = get_node_or_null("/root/Sound")


## checkCurlingMap (kar.c:7): the curling library is for map 136 (the data says which maps); the last
## map's match goes (the object list is cleared with the map).
func check_map(map_id: int) -> void:
	self.match = null
	world = null
	map_data = data.curling_map(map_id) if data != null and map_id >= 0 else {}


## KAR_start (kar.c:778), from digimon routine 1: the tamer is on the map (isOnMap = 1) and the
## match starts (state 0, the stones set up, the object 0x1388 added).
func start() -> void:
	# Port-only: the C runs routine 1 only on map 136 (script 131), where the overlay is loaded; off a
	# curling map there is nothing to start (the tamer's state 12 then ends at once, below).
	if map_data.is_empty():
		return
	world = FieldCurlingWorld.new()
	world.entities = entities
	world.tamer = tamer
	world.field_map = field_map
	world.overlays = overlays
	world.boxes = boxes
	world.text_area = text_area
	world.data = data
	world.game_state = game_state
	world.sound = sound
	world.interpreter = interpreter
	self.match = CurlingMatch.new(data.curling(), world, pad)
	tamer.on_map = true
	self.match.start()


## The world object 0x1388: KAR_tickStones, then KAR_renderScene's placement of the held stone.
func tick_world() -> void:
	if self.match == null:
		return
	self.match.tick_stones()
	self.match.update_held_stone()


## KAR_tick (kar.c:973), the tamer's state 12.
func tamer_tick() -> void:
	# Port-only: no match (routine 1 off a curling map): the state ends, like fishing's.
	if self.match == null:
		tamer.set_state(Tamer.STATE_FREE)
		return
	self.match.tamer_tick()
