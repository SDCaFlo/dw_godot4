class_name CurlingView
extends Node3D
## What KAR_renderScene draws (kar.c:860-943; specs/curling.md §2.1 "Drawing", §5.3; step C5), from
## the match once per game frame (draw_frame): the 15 stones of KARRING.TMD, each one object
## (`stone.model`) posed by RotMatrix(rotation) + TransMatrix(pos) (kar.c:906-907).
## - A stone with state >= 0 is in the field's view (GsSetRefView2(&GS_VIEWPOINT), the field's ordering
##   table at shift 2, kar.c:914-915, :932): this node's own children, in the field's 3D world.
## - A stone with state < 0 (the side stacks) is seen by KAR_D_8005B580 (eye (0, 0, -0xCF8) looking at
##   the origin) with GsSetProjection(0x200) (kar.c:910-912) into the overlay's 10-slot ordering table
##   (kar.c:868, :927), which GsSortOt links into the field's at slot 10 (kar.c:940), the HUD sprites'
##   slot, under the UI boxes (slots 1-6). Here: `stack_viewport`, a second 3D layer with its own
##   World3D and `stack_camera`, which the host shows over the field and under the HUD.
## Both layers are lit by the map's lights (GsSetLightMatrix with the stone's local-world matrix,
## kar.c:917-919): KARRING's PsxLit materials read FieldLighting's global lights with the world
## normals, the same in either World3D.

const MODEL := "tmd_files/ETCDAT/KARRING.gltf"
## KAR_renderScene's state rules (kar.c:924, :929): a stack stone below -0x64 (out of play, -0x65) and
## a stone on the ice at 0x65 and above (blinking off in the tally) are not drawn.
const STACK_HIDDEN_BELOW := -0x64
const ICE_HIDDEN_FROM := 0x65
## The stones: KAR_D_8005B5A0[3], 5 each (kar.c:871-873).
const ROWS := CurlingStones.ROWS
const PER_ROW := CurlingStones.PER_ROW
## The stack camera's clip planes: FieldMap's (port-only: the GTE has no far plane; the stacks are
## 0xCF8 from the eye).
const NEAR := FieldMap.NEAR
const FAR := FieldMap.FAR

## The stack layer: its own World3D (the scene's), seen by stack_camera; the host shows its texture.
@onready var stack_viewport: SubViewport = $StackViewport
## KAR_D_8005B580 (kar.c:664) with projection 0x200 (kar.c:911).
@onready var stack_camera: Camera3D = $StackViewport/StackCamera
@onready var _field_root: Node3D = $Stones
@onready var _stack_root: Node3D = $StackViewport/Stones

## Per stone (row * 5 + i), per layer (0 field, 1 stack): KARRING's object_0 .. object_11 of its copy.
var _objects: Array = []
## Per stone: the node shown this frame (null when not drawn) and the model it shows.
var _shown: Array[Node3D] = []
var _models := PackedInt32Array()
var _stack_drawn := true


func _ready() -> void:
	stack_camera.near = NEAR
	stack_camera.far = FAR
	var source := Content.load_model(MODEL)
	for k in ROWS * PER_ROW:
		var layers := []
		for root: Node3D in [_field_root, _stack_root]:
			var copy := source.duplicate() as Node3D
			copy.name = "Stone%d_%d" % [k / PER_ROW, k % PER_ROW]
			root.add_child(copy)
			var parts: Array[Node3D] = []
			var j := 0
			while copy.find_child("object_%d" % j, true, false) != null:
				var part := copy.find_child("object_%d" % j, true, false) as Node3D
				part.top_level = true
				part.visible = false
				parts.append(part)
				j += 1
			layers.append(parts)
		_objects.append(layers)
		_shown.append(null)
		_models.append(0)
	source.free()
	draw_frame(null)


## KAR_D_8005B580 from the data (GameData.curling()["stack_view"]: eye, target in PSX axes, rz 0,
## projection 0x200). The scene holds the same values.
func setup(stack_view: Dictionary) -> void:
	var eye: Array = stack_view["eye"]
	var target: Array = stack_view["target"]
	stack_camera.position = Content.psx_to_godot(eye)
	stack_camera.look_at(Content.psx_to_godot(target), Vector3.UP)
	stack_camera.fov = projection_fov(int(stack_view["projection"]))


## The vertical FOV of GsSetProjection(h) on the 240-line screen: 2 atan(120 / h), keep height.
static func projection_fov(h: int) -> float:
	return rad_to_deg(2.0 * atan((FieldMap.SCREEN.y / 2.0) / h))


## The stack layer at the field's render scale (320 x 240 x scale).
func set_render_scale(scale: int) -> void:
	stack_viewport.size = Vector2i(FieldMap.SCREEN) * scale


## KAR_renderScene for this frame; `m` null (no match, or the object removed): nothing.
func draw_frame(m: CurlingMatch) -> void:
	var stack_drawn := false
	for p in ROWS:
		for i in PER_ROW:
			var k := p * PER_ROW + i
			if _shown[k] != null:
				_shown[k].visible = false
				_shown[k] = null
			if m == null:
				continue
			var s: CurlingStones.Stone = m.stones.rows[p].stones[i]
			_models[k] = s.model
			# The row / timer skips come first (kar.c:874-885), then the state rules (:924, :929).
			if m.skipped(p, i):
				continue
			var layer := 1 if s.state < 0 else 0
			if layer == 1 and s.state < STACK_HIDDEN_BELOW:
				continue
			if layer == 0 and s.state >= ICE_HIDDEN_FROM:
				continue
			var parts: Array[Node3D] = _objects[k][layer]
			var node := parts[s.model]
			# RotMatrix(&rotation), TransMatrix(&pos) (kar.c:906-907).
			var mat := PsxMath.rot_matrix(s.rotation)
			mat[9] = s.pos.x
			mat[10] = s.pos.y
			mat[11] = s.pos.z
			node.global_transform = Content.psx_transform(mat)
			node.visible = true
			_shown[k] = node
			stack_drawn = stack_drawn or layer == 1
	# Port-only: the stack layer renders only while it shows a stone (one more frame to clear it).
	if stack_drawn != _stack_drawn:
		_stack_drawn = stack_drawn
		stack_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if stack_drawn else SubViewport.UPDATE_ONCE


## The node showing stone `i` of row `row` this frame (null when it is not drawn).
func stone_node(row: int, i: int) -> Node3D:
	return _shown[row * PER_ROW + i]


## The KARRING object stone `i` of row `row` showed in the last frame with a match.
func stone_model(row: int, i: int) -> int:
	return _models[row * PER_ROW + i]
