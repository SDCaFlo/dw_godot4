extends SceneTree
## Curling's view (CurlingView, CurlingHud; step C5) against specs/curling.md §5.3's contract: which
## stone is drawn where, with which KARRING object and transform, the stack layer's camera, and the HUD's
## quads from the match's sprites (in the ordering table's drawing order) and aim arrow. The look itself
## is VERIFY.md's. Acceptance checks written by the reviewer; don't change them to make the code pass.
##   godot --headless --path . -s res://tests/test_curling_view.gd
## Exits 1 if a check fails.

var _failed := 0
var _checks := 0
var _started := false


class QuietWorld:
	extends CurlingWorld


func _process(_delta: float) -> bool:
	if _started:
		return false
	_started = true
	var data: Node = load("res://scripts/data/game_data.gd").new()
	if not data.available() or not Content.exists("tmd_files/ETCDAT/KARRING.gltf"):
		print("SKIP: porter output missing")
		quit(0)
		return false
	PsxMath.setup(data)
	var curling: Dictionary = data.curling()
	var holder := Node3D.new()
	root.add_child(holder)
	var view: CurlingView = load("res://scenes/field/curling_view.tscn").instantiate()
	holder.add_child(view)
	var hud := CurlingHud.new()
	root.add_child(hud)
	_stones(view, curling)
	_hud(hud, curling)
	view.queue_free()
	hud.queue_free()
	holder.queue_free()
	data.free()
	print("%s: curling view checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
	quit(1 if _failed else 0)
	return false


func _check(ok: bool, what: String) -> void:
	_checks += 1
	if not ok:
		_failed += 1
		print("FAIL: " + what)


func _match(curling: Dictionary) -> CurlingMatch:
	var m := CurlingMatch.new(curling, QuietWorld.new(), Pad.new())
	m.opponent = 2
	return m


func _near(a: Transform3D, b: Transform3D) -> bool:
	return a.origin.distance_to(b.origin) < 0.01 and a.basis.x.distance_to(b.basis.x) < 0.001 \
			and a.basis.y.distance_to(b.basis.y) < 0.001 and a.basis.z.distance_to(b.basis.z) < 0.001


func _want(s: CurlingStones.Stone) -> Transform3D:
	var m := PsxMath.rot_matrix(s.rotation)
	m[9] = s.pos.x
	m[10] = s.pos.y
	m[11] = s.pos.z
	return Content.psx_transform(m)


func _stones(view: CurlingView, curling: Dictionary) -> void:
	var m := _match(curling)
	m.state = 5
	var ice := m.stones.place(0, 0, 0, CurlingStones.STATE_ICE, Vector3i(100, -50, -1000))
	ice.rotation = Vector3i(0x96, 0x100, 0)
	var stack := m.stones.place(1, 2, 1, CurlingStones.STATE_WAITING, Vector3i(0x2BC, 2 * 0xAA - 0x50, 0))
	stack.rotation = Vector3i(0x96, 0, 0)
	var pegged := m.stones.place(2, 1, 3, CurlingStones.STATE_PEGGED, Vector3i(-200, 0, -1500))
	pegged.model = int(curling["pegged_models"][2])
	var blinking := m.stones.place(0, 1, 0, CurlingStones.STATE_ICE, Vector3i(0, 0, -1700))
	blinking.state += 100
	view.draw_frame(m)
	var n := view.stone_node(0, 0)
	_check(n != null and n.is_visible_in_tree(), "a stone on the ice is shown")
	if n != null:
		_check(_near(n.global_transform, _want(ice)), "its transform is RotMatrix(rotation) + pos in Godot axes")
		_check(n.get_world_3d() != view.stack_viewport.world_3d, "a stone on the ice is in the field's world")
	_check(view.stone_model(0, 0) == ice.model, "it shows its model (%d)" % ice.model)
	var s := view.stone_node(1, 2)
	_check(s != null and s.is_visible_in_tree(), "a waiting stone is shown in its stack")
	if s != null:
		_check(s.get_world_3d() == view.stack_viewport.world_3d, "the stacks are in the stack layer's world")
		_check(_near(s.global_transform, _want(stack)), "a stack stone's transform")
	_check(view.stone_model(2, 1) == int(curling["pegged_models"][2]), "a stuck pegged stone shows the pegged model")
	var b := view.stone_node(0, 1)
	_check(b == null or not b.is_visible_in_tree(), "a blinking stone (state >= 0x65) is hidden")
	var out := view.stone_node(2, 4)
	_check(out == null or not out.is_visible_in_tree(), "an out-of-play stone (state -0x65) is hidden")
	# The opponent's stack is hidden during the introduction (KAR_renderScene :874-881).
	m.state = 1
	view.draw_frame(m)
	s = view.stone_node(1, 2)
	_check(s == null or not s.is_visible_in_tree(), "the opponent's stack is hidden before state 5")
	view.draw_frame(null)
	n = view.stone_node(0, 0)
	_check(n == null or not n.is_visible_in_tree(), "no match: nothing drawn")
	# KAR_D_8005B580 and GsSetProjection(0x200).
	var cam := view.stack_camera
	_check(cam != null and cam.position.distance_to(Vector3(0, 0, 0xCF8)) < 0.01, "the stack camera at Godot (0, 0, 0xCF8)")
	if cam != null:
		_check(absf(cam.fov - rad_to_deg(2.0 * atan(120.0 / 0x200))) < 0.01, "the stack camera's FOV from projection 0x200 (%f)" % cam.fov)
		_check(cam.keep_aspect == Camera3D.KEEP_HEIGHT, "keep height")
		_check(cam.global_transform.basis.z.dot(Vector3(0, 0, 1)) > 0.999, "it looks at the origin")


func _project(v: Vector3i) -> Vector2:
	return Vector2(v.x * 0.1 + 160, v.z * 0.05 + 120)


func _hud(hud: CurlingHud, curling: Dictionary) -> void:
	var m := _match(curling)
	m.stones.place(0, 0, 0, CurlingStones.STATE_HELD, Vector3i(-380, -180, 1350))
	m.stones.rows[0].score = 12
	m.stones.rows[1].score = -2
	m.state = 8
	m.power = 900
	m.tamer_tick()
	hud.draw_frame(m, _project)
	var sprites: Array = m.sprites
	_check(hud.quads.size() == sprites.size(), "one quad per sprite (%d, %d)" % [hud.quads.size(), sprites.size()])
	var ok := true
	for k in mini(hud.quads.size(), sprites.size()):
		var q: Dictionary = hud.quads[k]
		var sp: Dictionary = sprites[sprites.size() - 1 - k]
		if q["rect"] != Rect2(sp["x"] + 160, sp["y"] + 120, sp["w"], sp["h"]) \
				or q["region"] != Rect2(sp["u"], sp["v"], sp["w"], sp["h"]) \
				or q["palette"] != int(sp["clut_x"]) / 16 \
				or not q["color"].is_equal_approx(Color(sp["r"] / 128.0, sp["g"] / 128.0, sp["b"] / 128.0)) \
				or q["angle"] != 0:
			ok = false
			print("  quad %d: %s / sprite %s" % [k, q, sp])
	_check(ok, "the sprites' quads: screen rect, region, palette clut_x / 16, colour / 0x80, last added drawn first")
	var frame := hud.quads.filter(func(q: Dictionary) -> bool: return q["region"] == Rect2(0, 0x18, 0x30, 0x10))
	var bars := hud.quads.filter(func(q: Dictionary) -> bool: return q["region"] == Rect2(0x30, 0x18, 0x10, 0x10))
	_check(frame.size() == 1 and bars.size() == 4 and hud.quads.find(frame[0]) < hud.quads.find(bars[0]),
			"the gauge's frame under its bars (added after them)")
	# The aim arrow in state 6.
	m.state = 6
	m.power = 0
	m.aim = -0x400
	m.tamer_tick()
	hud.draw_frame(m, _project)
	var points: Array = m.arrow.filter(func(p: Dictionary) -> bool: return not p["skip"])
	_check(points.size() == 14, "the arrow: 15 points, one skipped (%d)" % points.size())
	_check(hud.quads.size() == m.sprites.size() + points.size(), "a quad per arrow point and per sprite")
	var arrow_quads := hud.quads.filter(_is_arrow)
	_check(arrow_quads.size() == points.size(), "the arrow's quads: palette 8, the dot or the head")
	var centred := 0
	for p in points:
		var c := _project(p["pos"])
		for q in arrow_quads:
			if q["rect"].get_center().distance_to(c) < 0.6:
				var shade: int = int(p["shade"]) + 0x40
				if q["color"].is_equal_approx(Color(shade / 128.0, shade / 128.0, shade / 128.0)):
					centred += 1
				break
	_check(centred == points.size(), "each arrow quad centred on its projected point, colour shade + 0x40 (%d of %d)" % [centred, points.size()])
	if not arrow_quads.is_empty():
		var others := hud.quads.filter(func(q: Dictionary) -> bool: return not _is_arrow(q))
		_check(hud.quads.find(arrow_quads.back()) < hud.quads.find(others[0]), "the arrow (by depth) is drawn before the slot-10 sprites")


## An arrow quad: palette 8, the dot's region (0x18, 0x38, 16, -16) or the head's (0x28, 0x28, 16 or 15).
## (Name plate 3 also starts at (0x18, 0x38) in palette 8, but it is 0x30 wide.)
func _is_arrow(q: Dictionary) -> bool:
	var r: Rect2 = q["region"]
	return q["palette"] == 8 and absf(r.size.x) <= 16 and (r.position == Vector2(0x18, 0x38) or r.position == Vector2(0x28, 0x28))
