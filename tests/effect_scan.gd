extends Node
## Every technique through the debugger's gallery (EffectGallery) in the real field scene: placed
## on a map, played to its end with its views in the tree (specs/battle_effects.md §7.4):
##   godot --headless --fixed-fps 60 --path . res://tests/effect_scan.tscn
## Prints per technique the frames, the hits, the most nodes its view showed in a frame (models and
## sprites), the most the shared effects showed, the calls not drawn yet and the VM's faults.
## Exits 1 if the script errors, an effect faults, or a technique with a model or sprites draws
## nothing. Env: EFFECT_IDS=0,2,17 some techniques; EFFECT_MAP=TROP01 the map; EFFECT_TRACE=1 prints
## every 5th frame each live instance's position relative to the target (where a technique goes);
## EFFECT_DISTANCE=50 stands the target at that share of the technique's range (default 100).

const MAP := "TROP01"
## Game frames to let the map set up, and a technique's longest run.
const SETTLE := 60
const TIMEOUT := 600

var _field: Node
var _gallery: EffectGallery
var _ids: Array = []
var _index := -1
var _start := 0
var _played := false
var _failed := false
var _most_view := 0
var _most_fx := 0
var _calls := {}
## The camera before the technique (no technique moves it), and a fixed view left on between frames
## (DG Dimension brackets its primitives with it within a pass).
var _camera := Transform3D()
var _fixed_seen := false


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	var map := OS.get_environment("EFFECT_MAP") if OS.get_environment("EFFECT_MAP") != "" else MAP
	_field.map_session.debug_change_map(map, 0)
	if OS.get_environment("EFFECT_IDS") != "":
		for s in OS.get_environment("EFFECT_IDS").split(","):
			_ids.append(int(s))
	else:
		for t in EffectGallery.techniques(GameData):
			_ids.append(t[0])
	_start = GameLoop.frame_count


func _process(_delta: float) -> void:
	_gallery = _field.debug.gallery
	var frames := GameLoop.frame_count - _start
	if _index < 0:
		if frames >= SETTLE:
			_next()
		return
	if _index >= _ids.size():
		return
	if not _played:
		_played = true
		_gallery.play()
		return
	if _gallery.effect != null and _gallery.effect.view != null:
		_most_view = maxi(_most_view, _gallery.effect.view.shown())
	if _gallery.fx_view != null:
		_most_fx = maxi(_most_fx, _gallery.fx_view.shown())
	if _gallery.effect != null:
		for c in _gallery.effect.draw_calls:
			_calls[c[0]] = true
	if _gallery.ctx != null and _gallery.ctx._fixed:
		_fixed_seen = true
	if OS.get_environment("EFFECT_TRACE") != "" and _gallery.effect != null and _gallery.frame % 5 == 0:
		var target := _gallery.ctx.location(2)
		var caster := _gallery.ctx.location(1)
		var live := []
		for c in _gallery.effect.contexts:
			if c["inst"] != 0:
				live.append(_gallery.effect.read_vec(c["instance"] + EfeEffect.I_POS) - target)
		print("  f%d caster-target %s, instances - target %s" % [_gallery.frame, caster - target, live])
	if not _gallery._running or frames > TIMEOUT:
		_report(frames)
		_next()


func _next() -> void:
	_index += 1
	_played = false
	_most_view = 0
	_most_fx = 0
	_calls.clear()
	if _index >= _ids.size():
		_gallery.close()
		print("effect_scan: %s" % ("FAILED" if _failed else "OK"))
		get_tree().quit(1 if _failed else 0)
		return
	var id: int = _ids[_index]
	var caster := EffectGallery.user_of(GameData, id)
	var percent := int(OS.get_environment("EFFECT_DISTANCE")) if OS.get_environment("EFFECT_DISTANCE") != "" else 100
	var error := _gallery.open(id, caster if caster >= 0 else 3, 17 if caster != 17 else 3, percent)
	if error != "":
		print("%3d: %s" % [id, error])
		_next()
		return
	_start = GameLoop.frame_count
	_camera = _gallery.camera.global_transform
	_fixed_seen = false


func _report(frames: int) -> void:
	var id: int = _ids[_index]
	var effect := _gallery.effect
	var faults: Array = effect.faults() if effect != null else []
	var skipped: Dictionary = effect.view.skipped if effect != null and effect.view != null else {}
	var drawable := false
	for k in _calls:
		if k in EfeView.DRAWN and k != "setEFEModelObjectColor":
			drawable = true
	var line := "%3d %-22s %4d frames, hits %d, view %3d, shared %3d" % [id,
			GameData.localize(GameData.move(id).get("name")).strip_edges(), frames, _gallery.hits.size(), _most_view, _most_fx]
	if not skipped.is_empty():
		line += ", not drawn yet %s" % str(skipped.keys())
	if not faults.is_empty():
		line += ", FAULTS %s" % str(faults)
		_failed = true
	if drawable and _most_view == 0:
		line += ", DREW NOTHING"
		_failed = true
	if frames > TIMEOUT:
		line += " (timeout)"
	if _fixed_seen:
		line += ", FIXED VIEW LEFT ON"
		_failed = true
	_gallery.close()
	if not _gallery.camera.global_transform.is_equal_approx(_camera):
		line += ", CAMERA NOT RESTORED"
		_failed = true
	print(line)
