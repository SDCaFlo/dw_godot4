extends Node
## Plays an evolution in the real field scene (specs/evolution_scene.md §7): Agumon -> Greymon on
## MAYO01 through Evolution.start (partner state 13, the loading, the evl sequence), until the
## partner is back in state 1. Checks the step 5f-2 acceptance points (all of them since step 6;
## DW_STEP_5F_2 is no longer needed):
##   godot --headless --fixed-fps 60 --path . res://tests/evolution_scan.tscn
## Exits 1 if a check fails.

const START_MAP := "MAYO01"
const TARGET := 5
const NEW_DIGIMON := "dw1:greymon"
const TIMEOUT := 3000
## C7: Agumon's middle ends at the drawing offset (160, 120 + lerp(0, 20, 0, 200, 250)).
const CENTRE := Vector2(160, 124)

var _field: Node
var _step := 0
## 0 entering the map, 1 walking up / loading, 2 the sequence, 3 done.
var _phase := 0
var _start_frame := 0
var _failed: Array[String] = []
var _pending: Array[String] = []
var _seen := {}
var _view_before := {}
var _shown_before := {}
var _layer_before := {}
var _shard_faces := 0
var _ring_lines := 0
var _last_frame := -2


func _ready() -> void:
	# Every step's checks run (the gates were removed with step 6; the glow adds nothing here).
	_step = 5
	for gate in [[1, "hand-over, centred, end"], [2, "outlines, new body"], [3, "shards"], [4, "rings behind"], [5, "no tint left"]]:
		if _step < gate[0]:
			_pending.append("step %d: %s" % gate)
	if _step < 1:
		_report()
		return
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	GameState.new_game("dw1:agumon")
	_field.map_session.partner.load_digimon(GameData, "dw1:agumon")
	_field.map_session.debug_change_map(START_MAP, 0)
	_start_frame = GameLoop.frame_count


func _host() -> Node:
	return _field.get_node_or_null("Systems/EvolutionHost")


func _sequence() -> Object:
	var host := _host()
	var scene: Node = host.get_node_or_null("EvolutionScene") if host != null else null
	return scene.get("sequence") if scene != null else null


func _process(_delta: float) -> void:
	if _phase == 3 or _field == null:
		return
	var tamer: Tamer = _field.map_session.tamer
	var partner: Partner = _field.map_session.partner
	var frames := GameLoop.frame_count - _start_frame
	if frames > TIMEOUT:
		_fail("stuck (phase %d, partner %d/%d, sequence timer %s)" % [_phase, partner.state, partner.sub_state,
				_sequence().get("timer") if _sequence() != null else "none"])
		_done()
		return
	match _phase:
		0:
			var ctx: ScriptContext = _field.scripts.script_ctx
			if frames % 4 == 0 and not ctx.is_paused:
				GameLoop.press("pad_cross")
			if _screen() != START_MAP or not ctx.is_paused or tamer.state != Tamer.STATE_FREE \
					or _field.care_host.fade.in_current <= 0x13:
				return
			if _host() == null:
				_fail("Systems/EvolutionHost exists (spec §5)")
				_done()
				return
			# Partner next to the tamer, then EVOLUTION_TARGET and states 6 / 13 (Evolution.start).
			partner.position = tamer.position + Vector3(60, 0, 0)
			_view_before = _field.map_session.field_map.view()
			for e in _field.entities.entities.table():
				if e != null and e != partner:
					_shown_before[e] = e.visible
			for n in _field.map_layer_nodes():
				if n != null:
					_layer_before[n] = n.visible
			_field.care_host.evolution.start(TARGET)
			_phase = 1
		1:
			if _sequence() != null:
				_phase = 2
		2:
			var seq := _sequence()
			var f := int(seq.get("timer")) - 1
			if f != _last_frame and f >= 0:
				_last_frame = f
				_track(seq, f, partner)
			if int(seq.get("timer")) == -1 and partner.state == Partner.STATE_NORMAL:
				_check_end(seq, partner, tamer)
				_done()


## The checks by frame: `f` is the frame the sequence just ticked.
func _track(seq: Object, f: int, partner: Partner) -> void:
	var host := _host()
	if f == 0x20:
		_seen["hand-over"] = true
		var shown := []
		for e in _shown_before:
			if is_instance_valid(e) and e.visible:
				shown.append(e.name)
		var layer := []
		for n in _layer_before:
			if is_instance_valid(n) and n.visible:
				layer.append(n.name)
		if not shown.is_empty() or not layer.is_empty() or not partner.visible:
			_fail("hand-over: still shown at 0x20: %s, map layer %s, partner %s" % [shown, layer, partner.visible])
		if seq.get("saved_view") != _view_before:
			_fail("hand-over: saved view %s, the map's was %s" % [seq.get("saved_view"), _view_before])
	if f >= 0x60 and f <= 0x6A:
		_seen["centred"] = true
		var h := int(GameData.digimon("dw1:agumon").get("height", 0))
		var got := FieldMap.unproject(_field.map_session.field_map.camera, partner.global_position + Vector3(0, h / 2.0, 0))
		if got.distance_to(CENTRE) > 1.5 and not _seen.has("centred failed"):
			_seen["centred failed"] = true
			_fail("centred: at 0x%X the partner's middle at %s, want %s" % [f, got, CENTRE])
	if _step >= 2:
		var wire: Variant = host.get("wireframe")
		if f == 0xA3:
			_seen["outlines"] = true
			var objects: Array = wire.get("_objects") if wire != null else []
			var solid := objects.filter(func(e): return int(e.get("share", 16)) != 0).map(func(e): return e.get("bone"))
			if objects.is_empty() or not solid.is_empty():
				_fail("outlines: at 0xA3 bones not in outlines: %s (%d objects)" % [solid, objects.size()])
		if f == 0x11C:
			_seen["new body"] = true
			if partner.digimon != NEW_DIGIMON or wire == null or not wire.is_attached() or int(wire.get("share")) != 0:
				_fail("new body: at 0x11C partner %s, wireframe %s share %s" % [partner.digimon,
						"attached" if wire != null and wire.is_attached() else "detached", wire.get("share") if wire != null else "-"])
		if f == 0x14F and wire != null and int(wire.get("share")) != 16:
			_fail("new body: share %s at 0x14F, want 16" % wire.get("share"))
	if _step >= 3:
		var view: Variant = host.get("shards_view")
		if view != null:
			_shard_faces = maxi(_shard_faces, int(view.call("shown_faces")))
	if _step >= 4:
		var rings: Variant = host.get("particles_view")
		if rings != null:
			_ring_lines = maxi(_ring_lines, int(rings.call("shown_lines")))
			var background: Node = _field.get_node_or_null("World/SubViewport/Background")
			if background == null or not background.is_ancestor_of(rings):
				if not _seen.has("rings failed"):
					_seen["rings failed"] = true
					_fail("rings behind: particles_view isn't under the background layer")


func _check_end(seq: Object, partner: Partner, tamer: Tamer) -> void:
	_seen["end"] = true
	for name in ["hand-over", "centred"] + (["outlines", "new body"] if _step >= 2 else []):
		if not _seen.has(name):
			_fail("%s: never reached" % name)
	var left := []
	var field_map: FieldMap = _field.map_session.field_map
	if field_map.view() != _view_before:
		left.append("the view %s (was %s)" % [field_map.view(), _view_before])
	for e in _shown_before:
		if is_instance_valid(e) and e.visible != _shown_before[e]:
			left.append("%s shown %s" % [e.name, e.visible])
	for n in _layer_before:
		if is_instance_valid(n) and n.visible != _layer_before[n]:
			left.append("map layer %s shown %s" % [n.name, n.visible])
	var fx: Variant = seq.get("fx")
	if fx is BattleFx and (fx as BattleFx).flashes.any(func(x): return x["progress"] >= 0):
		left.append("flashes")
	if partner.digimon != NEW_DIGIMON or partner.state != Partner.STATE_NORMAL:
		left.append("partner %s state %d" % [partner.digimon, partner.state])
	if tamer.state != Tamer.STATE_FREE or not tamer.camera_follow:
		left.append("tamer state %d, follow %s" % [tamer.state, tamer.camera_follow])
	if _step >= 2:
		var wire: Variant = _host().get("wireframe")
		if wire != null and wire.is_attached() and int(wire.get("share")) != 16:
			left.append("wireframe share %s" % wire.get("share"))
		if not partner.scale.is_equal_approx(Vector3.ONE):
			left.append("partner scale %s" % partner.scale)
	if _step >= 3:
		var sets: Variant = seq.get("shards")
		if sets != null and (sets.get("sets") as Array).any(func(x): return int(x["timer"]) >= 0):
			left.append("shard sets")
		if _shard_faces == 0:
			_fail("shards: no shard face ever drawn")
	if _step >= 4:
		for pair in [["sparks", "sparks", "bone"], ["particles", "particles", "timer"]]:
			var logic: Variant = seq.get(pair[0])
			if logic != null and (logic.get(pair[1]) as Array).any(func(x): return int(x[pair[2]]) >= 0):
				left.append(pair[0])
		if _ring_lines == 0:
			_fail("rings behind: no ring line ever drawn")
	if _step >= 5:
		for node in [partner, tamer]:
			for mi in node.find_children("*", "MeshInstance3D", true, false):
				for i in (mi as MeshInstance3D).get_surface_override_material_count():
					var m: Material = (mi as MeshInstance3D).get_surface_override_material(i)
					while m != null:
						if m is ShaderMaterial:
							var tint: Variant = (m as ShaderMaterial).get_shader_parameter("tint")
							var bt: Variant = (m as ShaderMaterial).get_shader_parameter("brighten_t")
							if (tint != null and tint != Vector3.ONE) or (bt != null and int(bt) != -1):
								left.append("%s's material tint %s brighten_t %s" % [node.name, tint, bt])
								m = null
								break
						m = m.next_pass
	if not left.is_empty():
		_fail("end: left over: " + "; ".join(left))


func _fail(what: String) -> void:
	_failed.append(what)


func _done() -> void:
	_phase = 3
	_report()


func _report() -> void:
	for line in _failed:
		print("FAIL: ", line)
	var state := "OK" if _failed.is_empty() else "FAILED %d" % _failed.size()
	if not _pending.is_empty():
		state += "; PENDING (DW_STEP_5F_2=%d): %s" % [_step, ", ".join(_pending)]
	print("%s: evolution scan (Agumon -> Greymon on %s)" % [state, START_MAP])
	get_tree().quit(1 if not _failed.is_empty() else 0)


func _screen() -> String:
	return str(GameData.map(GameState.state["world"]["screen"]).get("file", ""))
