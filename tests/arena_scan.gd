extends Node
## A tournament in the real field scene (autoloads, models, sound, the arena's view): enters an
## arena map, starts the arena as builtin 0x06 does (Arena.start with a cup and 7 drawn opponents),
## presses nothing (ARENA_PRESS=1: ✕ now and then, which skips the intros), and runs it to its end:
##   godot --headless --fixed-fps 60 --path . res://tests/arena_scan.tscn
## Checks it ends with a result 0-3, the field is given back (its camera current, the map and the
## partner shown again), and that a strong partner wins all three. Also ArenaWorld's effect side
## (specs/arena.md §4.8, needs the autoloads), and that a CLUT dim reaches the arena model's materials. Exits 1 on a failure or a script
## error. Env: ARENA_MAP=BETL02 (arena 1) instead of ROOM13; ARENA_WEAK=1 a weak partner (loses);
## ARENA_DEBUG=1 prints the phases.

## Game frames the map may take to set up, and a whole tournament.
const SETTLE := 90
const TIMEOUT := 40000
## Grade D (cup 0) and seven Rookies (Patamon, Kunemon, Agumon, Gabumon, Patamon, Kunemon, Agumon).
const CUP := 0
const OPPONENTS := [0x1F, 0x20, 0x03, 0x11, 0x1F, 0x20, 0x03]

var _field: Node
var _start := 0
var _running := false
var _failed := false
var _phase := -1
var _strong := true
## What the step-6 parts showed during the run (specs/arena.md §4.7).
var _seen := {}
## The palette check during the first fight (§4.8): 0 not yet, 1 dimmed at frame _palette_frame, 2 back
## to 0 at _palette_frame, 3 done.
var _palette_step := 0
var _palette_frame := 0


func _ready() -> void:
	_check_effect_world()
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	_strong = OS.get_environment("ARENA_WEAK") == ""
	var b: Dictionary = GameState.state["partner"]["stats"]["base"]
	if _strong:
		for k in ["offense", "defense", "speed"]:
			b[k] = 900
		b["max_hp"] = 9000
		b["max_mp"] = 3000
		b["brains"] = 300
		var moves: Array = GameData.digimon(GameState.state["partner"]["digimon"]).get("moves", [])
		if not moves.is_empty():
			b["moves"][0] = int(moves[0]["anim"])
	else:
		for k in ["offense", "defense", "speed", "brains"]:
			b[k] = 1
		b["max_hp"] = 20
	GameState.state["partner"]["stats"]["current"]["hp"] = int(b["max_hp"])
	GameState.state["partner"]["stats"]["current"]["mp"] = int(b["max_mp"])
	var map := OS.get_environment("ARENA_MAP") if OS.get_environment("ARENA_MAP") != "" else "ROOM13"
	_field.map_session.debug_change_map(map, 0)
	_start = GameLoop.frame_count


func _process(_delta: float) -> void:
	var frames := GameLoop.frame_count - _start
	var arena: Arena = _field.arena
	if not _running:
		if frames < SETTLE:
			return
		print("arena_scan: starting cup %d" % CUP)
		arena.debug_result = -1
		arena.start(CUP, OPPONENTS)
		_check(arena.active, "the arena is running")
		_check_backdrop(arena)
		_running = true
		_start = GameLoop.frame_count
		return
	# Nothing pressed by default: the intros must end on their own (a skipped intro hid a hang once).
	if OS.get_environment("ARENA_PRESS") != "" and frames % 7 == 0:
		GameLoop.press("pad_cross")
	if arena.active and _field.entities.partner.process_mode != Node.PROCESS_MODE_DISABLED:
		_check(false, "the field partner is paused while the arena runs (no step sounds)")
	if arena.active and arena.session != null and arena.session.phase == ArenaSession.Phase.MATCH and arena.arena_hud == null:
		_check(false, "the arena HUD is up during a match")
	if arena.active and arena.arena_hud != null and arena.arena_hud.get_parent() != _field.battle_host.hud_slot:
		_check(false, "the arena HUD is in the field's HUD slot")
	if arena.active and arena.session != null:
		_watch(arena)
	if arena.session != null and arena.session.phase != _phase:
		_phase = arena.session.phase
		if OS.get_environment("ARENA_DEBUG") != "":
			print("  frame %d: %s (match %d)" % [frames, ArenaSession.Phase.keys()[_phase], arena.session.played + 1])
	if arena.finished:
		print("arena_scan: finished after %d frames, result %d" % [frames, arena.result])
		_check(arena.result >= 0 and arena.result <= 3, "result in 0-3")
		if _strong:
			_check(arena.result == 3, "a strong partner wins all three")
		else:
			_check(arena.result == 0, "a weak partner loses the first match")
		_check(not arena.active, "the arena stopped")
		_check(arena.arena_hud == null, "the arena HUD is gone")
		_check(_field.map_session.field_map.visible, "the field map is shown again")
		_check(_field.entities.partner.visible, "the field partner is shown again")
		_check(_field.entities.partner.process_mode != Node.PROCESS_MODE_DISABLED, "the field partner runs again")
		var cam: Camera3D = _field.map_session.field_map.get_node("Camera3D")
		_check(cam.current, "the field camera is current again")
		_check(_seen.has("bracket"), "the bracket view drew the bracket")
		_check(_seen.has("intro"), "the bracket view drew the intro's title")
		_check(_palette_step == 3, "the palette check ran in the first fight (step %d)" % _palette_step)
		if _strong:
			_check(_seen.has("podium"), "the podium shown in the champion scene")
			_check(_seen.has("champion"), "the champion's letters shown")
		var after: int = Arena.AFTER_BRACKET[arena.last_arena]
		if after >= 0:
			var seq: Array = _seen.get("object_after_bracket", [])
			_check(seq.size() >= 2 and seq[0] == false and seq[1] == true,
					"arena 1's object %d hidden under the bracket, shown in the match (%s)" % [after, _seen.get("object_after_bracket", [])])
		var left: Node = _field.get_node("World/SubViewport").get_node_or_null("Arena")
		_check(left == null or left.is_queued_for_deletion(), "the arena's world is gone")
		_end()
		return
	if frames > TIMEOUT:
		_check(false, "the tournament ends within %d frames (phase %s)" % [TIMEOUT, ArenaSession.Phase.keys()[_phase]])
		_end()


## STD_renderArena0 / 1's sub-OTs: the back objects' priorities.
func _check_backdrop(arena: Arena) -> void:
	var model: Node = arena.get("_model")
	if model == null:
		_check(false, "the arena model loaded")
		return
	var order: Dictionary = Arena.BACKDROP[arena.last_arena]
	for i in 3:
		var obj := model.find_child("object_%d" % i, true, false)
		var mi: MeshInstance3D = obj if obj is MeshInstance3D else (obj.find_children("*", "MeshInstance3D", true, false)[0] if obj != null else null)
		var m: Material = mi.get_active_material(0) if mi != null else null
		_check(m != null and m.render_priority == int(order.get(i, 0)),
				"arena object %d's render priority %s (want %d)" % [i, m.render_priority if m != null else "none", int(order.get(i, 0))])


func _watch(arena: Arena) -> void:
	var hud: Node = arena.arena_hud
	var phase: int = arena.session.phase
	if hud != null:
		var bv: Node = hud.get_node("BracketView")
		var kinds: Array = bv.prims.map(func(p: Dictionary) -> String: return p.get("kind", ""))
		if phase == ArenaSession.Phase.BRACKET and "sprite" in kinds:
			_seen["bracket"] = true
		if phase == ArenaSession.Phase.BRACKET_INTRO and "title" in kinds:
			_seen["intro"] = true
		var sv: Node = hud.get_node("Scenes")
		var letter: Node3D = sv.object_node("champion", 0) if phase == ArenaSession.Phase.CHAMPION else null
		if letter != null and letter.visible:
			_seen["champion"] = true
	_watch_palette(arena)
	var podium: Node3D = arena.get("_podium")
	if podium != null and podium.visible and phase == ArenaSession.Phase.CHAMPION:
		_seen["podium"] = true
	var after: int = Arena.AFTER_BRACKET[arena.last_arena]
	var model: Node = arena.get("_model")
	if after >= 0 and model != null and phase in [ArenaSession.Phase.BRACKET, ArenaSession.Phase.MATCH]:
		var shown: bool = (model.find_child("object_%d" % after, true, false) as Node3D).visible
		var list: Array = _seen.get("object_after_bracket", [])
		if list.is_empty() or list[-1] != shown:
			list.append(shown)
		_seen["object_after_bracket"] = list


## specs/arena.md §4.8 E1-E3 on a bare ArenaWorld (no entities needed).
func _check_effect_world() -> void:
	PsxMath.setup(GameData)
	var w := ArenaWorld.new()
	w.data = GameData
	if not (w.has_method("screen_fade") and w.has_method("on_load_moves") and "palette_factor" in w):
		_check(false, "ArenaWorld has palette_factor, screen_fade, on_load_moves")
		return
	var fw := FieldBattleWorld.new()
	_check(fw.call("screen_fade", 0x80) == false, "a field battle draws the fade's quad (screen_fade false)")
	# E1 / E2: modifySomeImage / downloadSomeImage (main/efe.c:975-1015).
	_near(w.palette_factor, 1.0, "a new arena's rows are the TIM's (STD_loadArenaAssets)")
	_check(w.call("screen_fade", 0x80) == true, "the arena dims its CLUT rows instead of drawing the quad")
	_near(w.palette_factor, 127.0 / 255.0, "0x80 dims by (255 - 0x80) / 255")
	w.call("screen_fade", 0x40)
	_near(w.palette_factor, 191.0 / 255.0, "each call rebuilds from the copy (SOME_IMAGE_DATA), not from the last dim")
	w.call("screen_fade", 0xFF)
	_near(w.palette_factor, 0.0, "0xFF: black")
	w.call("screen_fade", 0)
	_near(w.palette_factor, 1.0, "0: the copy back")
	w.call("screen_fade", 0x80)
	w.call("on_load_moves")
	w.call("screen_fade", 0)
	_near(w.palette_factor, 127.0 / 255.0, "downloadSomeImage reads the rows as they are: the dimmed rows become the copy")
	w.call("screen_fade", 0x80)
	_near(w.palette_factor, 127.0 * 127.0 / (255.0 * 255.0), "and the next dim starts from that copy")
	# E2 through the effect host (the arena's match loads its moves this way).
	var w2 := ArenaWorld.new()
	w2.data = GameData
	var host := EffectHost.new(w2)
	w2.call("screen_fade", 0xFF)
	host.load_moves([])
	w2.call("screen_fade", 0)
	_near(w2.palette_factor, 0.0, "EffectHost.load_moves reads the rows back first")
	# E3: the fixed view keeps the arena camera's projection (STD_setupFixedCamera: no
	# GsSetProjection(0x200) in US); the restore is GsSetProjection(VIEWPORT_DISTANCE).
	var aw := ArenaWorld.new()
	aw.data = GameData
	var cam := ArenaCamera.new(aw, 1)
	aw.arena_camera = cam
	if not cam.has_method("set_projection"):
		_check(false, "ArenaCamera.set_projection (GsSetProjection)")
		return
	var before := cam.projection()
	aw.set_fixed_camera(true)
	_check(aw.viewport_distance() == before, "the arena's fixed view keeps the camera's projection (%d, want %d)" % [aw.viewport_distance(), before])
	_check(aw.projection_distance() == before, "projection_distance too")
	_check(aw.world_screen_matrix() == PsxMath.trans_matrix(PsxMath.identity(), Vector3i(0, 0, 0x7D0)),
			"the fixed view's GsWSMATRIX (EFE_FIXED_VIEW: eye z -0x7D0)")
	_check(aw.drawing_offset() == Vector2i(0xA0, 0x78), "the fixed view's drawing offset (0xA0, 0x78)")
	cam.viewport_distance = 0x15E
	aw.set_fixed_camera(false)
	_check(cam.projection() == 0x15E, "STD_restoreCameraView: GsSetProjection(VIEWPORT_DISTANCE) (%d)" % cam.projection())
	_check(aw.viewport_distance() == 0x15E, "the arena's view after the restore")
	fw.set_fixed_camera(true)
	_check(fw.viewport_distance() == 0x200, "a field battle's fixed view still projects at 0x200 (BTL_setupFixedCamera)")


## In the first fight: a dim set on the arena's world shows on every arena model surface the next game
## frame (PsxLit's tint on each pass), and 0 takes it off.
func _watch_palette(arena: Arena) -> void:
	if _palette_step == 3 or arena.arena_world == null or not arena.arena_world.has_method("screen_fade"):
		return
	var m: Variant = arena.session.current_match if arena.session.phase == ArenaSession.Phase.MATCH else null
	if _palette_step == 0:
		if m != null and m.phase == ArenaMatch.Phase.FIGHT:
			arena.arena_world.call("screen_fade", 0xFF)
			_palette_frame = GameLoop.frame_count
			_palette_step = 1
		return
	if GameLoop.frame_count <= _palette_frame:
		return
	var want := 0.0 if _palette_step == 1 else 1.0
	var model: Node = arena.get("_model")
	var bad := []
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for i in mi.get_surface_override_material_count():
			var pass_material: Material = mi.get_surface_override_material(i)
			while pass_material != null:
				if pass_material is ShaderMaterial:
					var t: Variant = (pass_material as ShaderMaterial).get_shader_parameter("tint")
					var tint: Vector3 = t if t is Vector3 else Vector3.ONE
					if not tint.is_equal_approx(Vector3(want, want, want)):
						bad.append("%s/%d %s" % [mi.name, i, tint])
				pass_material = pass_material.next_pass
	_check(bad.is_empty(), "arena model tint %s after screen_fade(%d): %s" % [want, 0xFF if _palette_step == 1 else 0, bad.slice(0, 4)])
	if _palette_step == 1:
		arena.arena_world.call("screen_fade", 0)
		_palette_frame = GameLoop.frame_count
		_palette_step = 2
	else:
		_palette_step = 3


func _near(got: float, want: float, what: String) -> void:
	_check(is_equal_approx(got, want), "%s: got %s, want %s" % [what, got, want])


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failed = true
		print("FAIL: %s" % what)


func _end() -> void:
	print("arena_scan: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)
