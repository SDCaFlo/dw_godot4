class_name CurlingHost
extends Node
## Curling on the field (specs/curling.md §5.2; the KAR_REL overlay, src/kar/kar.c, and its hooks in
## src/main): checkCurlingMap notes at every map load whether the map has curling, digimon routine 1
## (KAR_start) makes the match, the world object 0x1388 (KAR_tickStones, KAR_renderScene's placement)
## ticks in the field's frame, and the tamer's state 12 calls tamer_tick (KAR_tick). The drawing (step
## C5): CurlingView in the 3D world (KAR_renderScene: the stones; its stack layer shown by
## `stack_layer` on the HUD), CurlingHud (KAR_tick's sprites and aim arrow) and CurlingWindows (box 0's
## contents).

## The world part (a mod may replace the scene).
const VIEW_SCENE := preload("res://scenes/field/curling_view.tscn")

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
## The 3D world (World/SubViewport): the view goes in it.
var world_root: Node

var view: CurlingView
## The sprites and the aim arrow; the field adds it to the HUD under the UI boxes.
var hud := CurlingHud.new()
## The view's stack layer (its SubViewport's picture) at the PSX size; the field adds it to the HUD
## under everything else there (the overlay's ordering table is linked at slot 10, kar.c:940).
var stack_layer := TextureRect.new()
var windows := CurlingWindows.new()
## The field's render scale (FieldMap.render_scale), for the stack layer.
var render_scale := 1

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
	hud.name = "CurlingHud"
	stack_layer.name = "CurlingStacks"
	stack_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stack_layer.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stack_layer.stretch_mode = TextureRect.STRETCH_SCALE
	stack_layer.size = FieldMap.SCREEN


## checkCurlingMap (kar.c:7): the curling library is for map 136 (the data says which maps); the last
## map's match goes (the object list is cleared with the map).
func check_map(map_id: int) -> void:
	self.match = null
	world = null
	windows.curling = null
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
	world.box_render = windows.render
	world.box_on_render = windows.on_render
	self.match = CurlingMatch.new(data.curling(), world, pad)
	windows.boxes = boxes
	windows.text_area = text_area
	windows.curling = self.match
	_ensure_view()
	tamer.on_map = true
	self.match.start()


## The world object 0x1388: KAR_tickStones, then KAR_renderScene (the held stone's placement, the
## stones), then the HUD of this frame's KAR_tick.
func tick_world() -> void:
	if self.match != null:
		self.match.tick_stones()
		self.match.update_held_stone()
	if view != null:
		# removeObject(0x1388) in KAR_finishMatch (kar.c:959): no stones after the match.
		view.draw_frame(self.match if self.match != null and self.match.active else null)
	# KAR_tick runs while the tamer is in state 12, until the script's warp (a new map drops the match).
	hud.draw_frame(self.match, _project)


## The field's projection of a PSX world point to the 320 x 240 screen: RotTransPers with GsWSMATRIX
## and VIEWPORT_DISTANCE, plus the drawing offset (the arrow's slots, beyond 0x20, are drawn with
## GsSetOrign's DRAWING_OFFSET, main.c:3658).
func _project(p: Vector3i) -> Vector2:
	return field_map.drawing_offset() + Vector2(field_map.world_to_screen(p)["screen"])


## The view in the 3D world, its stack layer on the HUD (once, on the first match).
func _ensure_view() -> void:
	if view != null:
		return
	view = VIEW_SCENE.instantiate()
	world_root.add_child(view)
	view.setup(data.curling()["stack_view"])
	stack_layer.texture = view.stack_viewport.get_texture()
	set_render_scale(render_scale)


## The stack layer at the field's render scale (Field.set_render_scale), shown at the PSX size.
func set_render_scale(value: int) -> void:
	render_scale = value
	# Like the field's 3D view: a bigger picture is filtered down to the screen.
	stack_layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if value == 1 else CanvasItem.TEXTURE_FILTER_LINEAR
	if view != null:
		view.set_render_scale(value)


## KAR_tick (kar.c:973), the tamer's state 12.
func tamer_tick() -> void:
	# Port-only: no match (routine 1 off a curling map): the state ends, like fishing's.
	if self.match == null:
		tamer.set_state(Tamer.STATE_FREE)
		return
	self.match.tamer_tick()
