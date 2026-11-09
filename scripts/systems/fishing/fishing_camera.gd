class_name FishingCamera
extends RefCounted
## The projection maths fishing does on the map's camera (specs/fishing.md §2.1, §5.3), in the C's
## integers: FISH_projectPoint (fish.c:1086), mapToWorldPosition (vecmath.c:64), the background
## bounds of FISH_isScreenPointVisible (fish.c:1055) and the view centre. "Projected" points are
## pixels from the projection centre (before the drawing offset), as the GTE gives them. The field
## refreshes the fields from FieldMap (world_screen_matrix, viewport_distance, background_size,
## drawing_offset); the tests set them.

## GsWSMATRIX in PsxMath's layout (rows right, down, forward at 4096 = 1.0; translation -R · eye).
var ws := PsxMath.identity()
## VIEWPORT_DISTANCE.
var h := 300
## MAP_TILE_DATA.width / height × 128: the background in pixels.
var background := Vector2i(320, 240)
## DRAWING_OFFSET_X / Y: where the projection centre is on screen.
var offset := Vector2i(160, 120)


## FISH_projectPoint: GsMulCoord0(GsWSMATRIX, point) then x · H / z. null when z <= 0 or
## z >= 0x10000 (the C returns 0).
func project(point: Vector3i) -> Variant:
	var v := PsxMath.apply_matrix_lv(ws, point) + PsxMath.translation(ws)
	if v.z <= 0 or v.z >= 0x10000:
		return null
	return Vector2i(PsxMath.div(v.x * h, v.z), PsxMath.div(v.y * h, v.z))


## mapToWorldPosition (vecmath.c:64): the point on the ground (y = 0) the projected point (x, y)
## shows. transposeRefMatrix takes SVECTOR differences (16-bit) and ApplyMatrix (>> 12). null when
## the ray doesn't cross the ground (the C leaves the output as it was).
func ground_at(x: int, y: int) -> Variant:
	var eye := _transpose_ref(Vector3i.ZERO)
	var far := _transpose_ref(Vector3i(x, y, h)) - eye
	if eye.y == 0 or far.y == 0 or (eye.y > 0) == (far.y > 0):
		return null
	return Vector3i(PsxMath.div(far.x * eye.y, -far.y) + eye.x, 0, PsxMath.div(far.z * eye.y, -far.y) + eye.z)


## transposeRefMatrix (vecmath.c:52): ApplyMatrix(transpose(GsWSMATRIX), s16(pos - t)).
func _transpose_ref(pos: Vector3i) -> Vector3i:
	var t := PsxMath.translation(ws)
	var v := PsxMath.s16_vec(pos - t)
	return PsxMath.apply_matrix_lv(PsxMath.transpose(ws), v)


## DRAW_OFFSET_LIMIT_X_MAX = width·128 / 2, _X_MIN = 320 − that (map.c:4265-4270); FISH_screenLeft(x)
## = −LIMIT_X_MAX + x, FISH_screenRight(x) = −LIMIT_X_MIN + x (fish.c:939-957).
func screen_left(x: int) -> int:
	return x - background.x / 2


func screen_right(x: int) -> int:
	return x - (320 - background.x / 2)


func screen_top(y: int) -> int:
	return y - background.y / 2


func screen_bottom(y: int) -> int:
	return y - (240 - background.y / 2)


## FISH_viewX / FISH_viewY (fish.c:959): −DRAWING_OFFSET + x.
func view_x(x: int) -> int:
	return x - offset.x


func view_y(y: int) -> int:
	return y - offset.y


## FISH_isScreenPointVisible (fish.c:1055): inside the background (not the screen).
func is_in_background(x: int, y: int) -> bool:
	return x >= screen_left(0) and x <= screen_right(0x140) and y >= screen_top(0) and y <= screen_bottom(0xF0)
