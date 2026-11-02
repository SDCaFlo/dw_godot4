extends Node
## A tournament in the real field scene (autoloads, models, sound, the arena's view): enters an
## arena map, starts the arena as builtin 0x06 does (Arena.start with a cup and 7 drawn opponents),
## presses nothing (ARENA_PRESS=1: ✕ now and then, which skips the intros), and runs it to its end:
##   godot --headless --fixed-fps 60 --path . res://tests/arena_scan.tscn
## Checks it ends with a result 0-3, the field is given back (its camera current, the map and the
## partner shown again), and that a strong partner wins all three. Exits 1 on a failure or a script
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


func _ready() -> void:
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


func _check(cond: bool, what: String) -> void:
	if not cond:
		_failed = true
		print("FAIL: %s" % what)


func _end() -> void:
	print("arena_scan: %s" % ("FAILED" if _failed else "OK"))
	get_tree().quit(1 if _failed else 0)
