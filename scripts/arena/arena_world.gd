class_name ArenaWorld
extends FieldBattleWorld
## The arena's battle world (specs/arena.md §5.2): FieldBattleWorld on the arena's own fighters (an
## FieldEntities of the arena: the partner, the opponent in its NPC slot) and the arena's collision
## grid (B_TOGI.ATR in a FieldMap's collision, STD_loadArenaAssets); the screen through the arena
## camera (ArenaCamera's GsWSMATRIX and projection, the drawing offset at the screen centre:
## STD_initializeTournament's DRAWING_OFFSET 0xA0, 0x78). No combat area (entityCheckCombatArea
## returns 0 in GAME_STATE 4, map.c:3053).

## DRAWING_OFFSET_X / Y (std_setup.c:247-248).
const CENTRE := Vector2i(0xA0, 0x78)

var arena_camera: ArenaCamera
## The Godot camera the arena draws with (screen_to_world).
var view_camera: Camera3D


func world_screen_matrix() -> PackedInt32Array:
	if _fixed:
		return PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, -FIXED_EYE_Z))
	return arena_camera.world_screen_matrix() if arena_camera != null else PsxMath.identity()


func viewport_distance() -> int:
	if _fixed:
		return FIXED_PROJECTION
	return arena_camera.projection() if arena_camera != null else 500


func projection_distance() -> int:
	return viewport_distance()


func drawing_offset() -> Vector2i:
	return CENTRE


## A screen point relative to the projection centre at view depth `depth`, through the arena's
## Godot camera.
func screen_to_world(relative: Vector2, depth: float) -> Vector3:
	if view_camera == null:
		return super(relative, depth)
	var vp := view_camera.get_viewport()
	var scale := Vector2(vp.get_visible_rect().size) / Vector2(SCREEN)
	return view_camera.project_position((Vector2(CENTRE) + relative) * scale, depth)


## A PSX world point's screen pixel (0-320, 0-240).
func _screen(p: Vector3i) -> Vector2:
	var s: Dictionary = world_to_screen(p)
	return Vector2(s["screen"]) + Vector2(CENTRE)


func screen_position(id: int, bone: int) -> Vector2i:
	var s: Dictionary = world_to_screen(bone_location(id, bone))
	return s["screen"]


func project(pos: Vector3i) -> Vector3i:
	var s: Dictionary = world_to_screen(pos)
	return Vector3i(s["screen"].x, s["screen"].y, int(s["sz"]))


## No combat area in the arena.
func _left_combat_area(_id: int, _here: Vector3i, _next: Vector3i, _w: int, _h: int) -> bool:
	return false


## setEntityPosition (STD_placePlayer1 / 2, STD_setPostIntroPosition, the podium).
func set_location(id: int, loc: Vector3i) -> void:
	var n := _node(id)
	if n != null:
		n.position = Vector3(loc.x, -loc.y, -loc.z)
