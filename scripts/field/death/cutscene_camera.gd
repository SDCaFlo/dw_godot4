class_name CutsceneCamera
## DOOA's cutscene camera (DOOA_updateCutsceneCamera, dooa.c:728; DOOA_getOrbitPosition,
## dooa.c:1305; specs/death_scene.md §3 D, §4.4): from a start view to an orbit view of the
## partner over [s, e], the reference point first, then the eye. A view is the C's GS_VIEWPOINT,
## drawing offset and VIEWPORT_DISTANCE: {"eye": Vector3i, "ref": Vector3i, "offset": Vector2i,
## "projection": int}, world units (D15). FieldMap shows it (set_view).

## MAIN_D_80134BB4: (0, 0, 0), only read (D1); the orbit turns by the partner's angle + 0x638.
const ORBIT_TURN := 0x638
const CENTRE := Vector2i(160, 120)
const PROJECTION_END := 1000


## The orbit's reference point (the partner's middle) and eye (D2–D4). `distance` -1: DOOA's
## height * 5 + 1200; the evolution scene passes its own (evl.c:731, specs/evolution_scene.md C2).
static func orbit(position: Vector3i, angle: int, height: int, distance := -1) -> Array:
	var ref := Vector3i(position.x, position.y - height / 2, position.z)
	var m := PsxMath.rot_matrix_zyx(Vector3i(0, angle + ORBIT_TURN, 0))
	var eye := PsxMath.apply_matrix_lv(m, Vector3i(0, 0, distance if distance >= 0 else height * 5 + 1200)) + ref
	eye.y += -400 - height * 2
	return [ref, eye]


## The view at frame `f` of [s, e] from `start`, or {} outside it (D5–D7).
static func view(start: Dictionary, position: Vector3i, angle: int, height: int, s: int, e: int, f: int, distance := -1) -> Dictionary:
	if f < s or f > e:
		return {}
	var mid := (s + e) / 2
	var o := orbit(position, angle, height, distance)
	var ref: Vector3i = o[0]
	var eye: Vector3i = o[1]
	var start_eye: Vector3i = start["eye"]
	var start_ref: Vector3i = start["ref"]
	var start_offset: Vector2i = start["offset"]
	var start_projection: int = start["projection"]
	if f <= mid:
		return {"eye": start_eye, "ref": _lerp3(start_ref, ref, s, mid, f),
				"offset": Vector2i(PsxMath.lerp_int(start_offset.x, CENTRE.x, s, mid, f), PsxMath.lerp_int(start_offset.y, CENTRE.y, s, mid, f)),
				"projection": start_projection}
	var offset_y := PsxMath.lerp_int(0, 20, 0, 200, height)
	return {"eye": _lerp3(start_eye, eye, mid, e, f), "ref": ref,
			"offset": Vector2i(CENTRE.x, PsxMath.lerp_int(CENTRE.y, offset_y + CENTRE.y, mid, e, f)),
			"projection": PsxMath.lerp_int(start_projection, PROJECTION_END, mid, e, f)}


static func _lerp3(a: Vector3i, b: Vector3i, t0: int, t1: int, t: int) -> Vector3i:
	return Vector3i(PsxMath.lerp_int(a.x, b.x, t0, t1, t), PsxMath.lerp_int(a.y, b.y, t0, t1, t), PsxMath.lerp_int(a.z, b.z, t0, t1, t))
