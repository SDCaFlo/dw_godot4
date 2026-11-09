class_name FieldCurlingWorld
extends CurlingWorld
## CurlingWorld on the field (specs/curling.md §5.2, step C4): the entities by ENTITY_TABLE slot
## (FieldEntities), the camera (FieldMap), the map's ring markers (MapOverlays), UI box 0 (UIBoxes),
## the shared text area, the Sound autoload, the pstats (GameState's script values) and the script's
## sync bit. Positions are PSX world units as the C has them: the Godot position is (x, -y, -z), as in
## FieldFishingWorld and the script interpreter.

## createAnimatedUIBox(0, 0, 2, ...) (kar.c:2035-2099): box 0, colour 0, UI_FEATURE half fill.
const BOX_ID := 0
const BOX_COLOR := 0

var entities: FieldEntities
var tamer: Tamer
var field_map: FieldMap
var overlays: MapOverlays
var boxes: UIBoxes
var text_area: TextArea
var data: Node
var game_state: Node
var sound: Node
var interpreter: ScriptInterpreter


func _entity(slot: int) -> Node3D:
	return entities.entity(slot) if entities != null else null


func location(slot: int) -> Vector3i:
	var e := _entity(slot)
	if e == null:
		return Vector3i.ZERO
	return Vector3i(roundi(e.position.x), roundi(-e.position.y), roundi(-e.position.z))


func set_location_xz(slot: int, x: int, z: int) -> void:
	var e := _entity(slot)
	if e != null:
		e.position.x = x
		e.position.z = -z


func yaw(slot: int) -> int:
	var e := _entity(slot)
	return int(e.get("direction")) if e != null else 0


func set_yaw(slot: int, v: int) -> void:
	var e := _entity(slot)
	if e != null:
		e.set_direction(v)


func start_animation(slot: int, id: int) -> void:
	var e := _entity(slot)
	if e != null:
		e.start_animation(id)


func bone_translation(slot: int, bone: int) -> Vector3i:
	var e := _entity(slot)
	if e == null:
		return Vector3i.ZERO
	var p: Vector3 = e.bone_position(bone)
	return Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z))


## tickCameraMoveTo (map.c:5100): CAMERA_TARGET = (x, the tamer's y, z), then checkCameraMovement; its
## return is 1 once, the call after the pan ended (spec §8 Q2).
func camera_move_to(x: int, z: int, speed: int) -> int:
	if field_map == null:
		return 1
	var y := tamer.position.y if tamer != null else 0.0
	field_map.pan_target = Vector3(x, y, -z)
	return 1 if field_map.check_pan(speed) else 0


## moveCameraByDiff (map.c:5124): the screen motion of the move, with the pad as it is.
func camera_move_by_diff(from: Vector3i, to: Vector3i) -> void:
	if field_map == null:
		return
	var pad_bits := interpreter.pad.polled if interpreter != null and interpreter.pad != null else 0
	field_map.scroll_by(field_map.screen_motion(Vector3(from.x, -from.y, -from.z), Vector3(to.x, -to.y, -to.z)), pad_bits)


## moveCameraByOffset (map.c:5168): the camera and the drawing offset by (dx, dy), then the edge clamp.
func camera_move_by_offset(dx: int, dy: int) -> void:
	if field_map != null:
		field_map.scroll_clamped(Vector2(dx, dy))


func set_map_objects_flag(start: int, count: int, flag: int) -> void:
	if overlays != null:
		overlays.set_flag(start, flag, count)


func box_state() -> int:
	return boxes.boxes[BOX_ID].state if boxes != null else 0


func create_box(final: Rect2i, start: Rect2i) -> void:
	if boxes != null:
		boxes.create_animated(BOX_ID, BOX_COLOR, UIBoxes.FEATURE_HALF_FILL, final, start)


func remove_box() -> void:
	if boxes != null:
		boxes.remove_animated(BOX_ID)


func clear_text_area() -> void:
	if text_area != null:
		text_area.clear_all()


func draw_string(text: String, x: int, y: int) -> void:
	if text_area != null and text != "":
		text_area.draw_string(text, x, y)


func set_text_color(c: int) -> void:
	if text_area != null:
		text_area.set_text_color(c)


func localize(ref: Variant) -> String:
	return data.localize(ref) if data != null and ref != null else ""


func play_sound(bank: int, id: int) -> int:
	return int(sound.play_sound(bank, id)) if sound != null else 0


func stop_sound_mask(mask: int) -> void:
	if sound != null:
		sound.stop_sound_mask(mask)


func read_pstat(i: int) -> int:
	return game_state.script_value(i) if game_state != null else 0


func write_pstat(i: int, v: int) -> void:
	if game_state != null:
		game_state.set_script_value(i, v)


func set_sync_bit(v: int) -> void:
	if interpreter != null:
		interpreter.ctx.sync_bit = v
