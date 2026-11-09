class_name CurlingWorld
extends RefCounted
## What curling's match logic (CurlingMatch, CurlingAi; specs/curling.md §5.1, step C3) asks of the
## rest of the game: the entities, the camera, the map's ring markers, UI box 0, the text area, the
## sounds, the pstats and the script's sync bit. The field implements it (step C4, FieldCurlingWorld);
## the tests use a fake. Positions are PSX world units (Vector3i, the C's axes: +z towards the camera),
## angles 12-bit. Slots are ENTITY_TABLE indices: 0 the tamer, 1 the partner, 2 / 3 the opponent.


## ENTITY_TABLE[slot]->posData->location.
func location(_slot: int) -> Vector3i:
	return Vector3i.ZERO


## ENTITY_TABLE[slot]->posData->location.vx / .vz = x / z (y is kept).
func set_location_xz(_slot: int, _x: int, _z: int) -> void:
	pass


## ENTITY_TABLE[slot]->posData->rotation.vy.
func yaw(_slot: int) -> int:
	return 0


## ENTITY_TABLE[slot]->posData->rotation.vy = v.
func set_yaw(_slot: int, _v: int) -> void:
	pass


## startAnimation(ENTITY_TABLE[slot], id).
func start_animation(_slot: int, _id: int) -> void:
	pass


## ENTITY_TABLE[slot]->posData[bone].posMatrix.workm.t: the bone's world translation (kar.c:893, :898,
## :2534, :2676).
func bone_translation(_slot: int, _bone: int) -> Vector3i:
	return Vector3i.ZERO


## tickCameraMoveTo(x, z, speed) (map.c:5100): 1 on the frame the camera arrives (spec §8 Q2).
func camera_move_to(_x: int, _z: int, _speed: int) -> int:
	return 1


## moveCameraByDiff(&from, &to) (map.c:5124).
func camera_move_by_diff(_from: Vector3i, _to: Vector3i) -> void:
	pass


## moveCameraByOffset(dx, dy) (map.c:5168).
func camera_move_by_offset(_dx: int, _dy: int) -> void:
	pass


## setMapObjectsFlag(start, count, flag): the map's overlay objects (the ring markers, kar.c:1294).
func set_map_objects_flag(_start: int, _count: int, _flag: int) -> void:
	pass


## UI_BOX_DATA[0].state: 0 closed, 1 open (other values while it animates).
func box_state() -> int:
	return 0


## createAnimatedUIBox(0, 0, 2, &final, &start, NULL, NULL).
func create_box(_final: Rect2i, _start: Rect2i) -> void:
	pass


## removeAnimatedUIBox(0, NULL).
func remove_box() -> void:
	pass


## clearTextArea().
func clear_text_area() -> void:
	pass


## drawString(text, x, y) into the shared text area. An empty string draws nothing (a NULL string in
## the C, spec §8 Q1).
func draw_string(_text: String, _x: int, _y: int) -> void:
	pass


## setTextColor(c).
func set_text_color(_c: int) -> void:
	pass


## The text of a string reference from the data (a hint line, the menu: {string_id, text}); null (the
## C's NULL) gives "".
func localize(_ref: Variant) -> String:
	return ""


## playSound(bank, id) / playSound2(bank, id): returns the voice mask (playSound2's value).
func play_sound(_bank: int, _id: int) -> int:
	return 0


## thunkStopSoundMask(mask).
func stop_sound_mask(_mask: int) -> void:
	pass


## readPStat(i).
func read_pstat(_i: int) -> int:
	return 0


## writePStat(i, v).
func write_pstat(_i: int, _v: int) -> void:
	pass


## SOME_SCRIPT_SYNC_BIT = v (the script's WAIT_FOR_ENTITY goes on at 1).
func set_sync_bit(_v: int) -> void:
	pass
