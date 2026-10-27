class_name EffectGallery
extends Node
## The technique gallery (specs/battle_effects.md §7.4), not part of the original: one technique's
## effect run on the current map without a battle, to see every technique and compare it with the
## original. Two Digimon stand at the C's attack distance across the screen where the tamer is (the
## tamer and the partner hide meanwhile); play() starts the effect, again to replay. Its own
## EffectHost and BattleFxView, over a GalleryWorld; the battle's sound bank in slot 8 while open.
## The debugger's Effects tab drives it; the field ticks it once per game frame.
##
## A hit is listed, and its victim's isHit cleared HIT_FRAMES later (in a battle the fighter's
## hit reaction decides), so a technique that hits several times shows each.

const DIGIMON_SCENE := preload("res://scenes/field/digimon.tscn")
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
const HIT_FRAMES := 10
## Battle.ANIM_MOVE: the first technique slot's animation.
const ANIM_MOVE := 0x2E

## Set by the debug host: the 3D world, the map, its camera, and the nodes to hide while open
## (func() -> Array: the tamer, the partner).
var world: Node
var field_map: FieldMap
var camera: Camera3D
var hidden_nodes := Callable()
var map_layer_nodes := Callable()
## What went wrong at the last open(), for the tab.
var last_error := ""

var active := false
var technique := -1
var caster_type := -1
var target_type := -1
var ctx: GalleryWorld
var host: EffectHost
var fx_view: BattleFxView
var effect: EfeEffect
var slot := -1
## Frames since the last play(); the hits [frame, victim].
var frame := 0
var hits: Array = []
var _hit_timers := {}
var _running := false
var _shown := {}
var _hidden: Array = []


## Every technique with an effect slot: [[id, name]].
static func techniques(data: Node) -> Array:
	var out := []
	for r in data.records("moves/move_data"):
		var id := int(r.get("id", -1))
		if id >= 0 and EffectHost.efe_folder(id) != "":
			out.append([id, data.localize(r.get("name")).strip_edges()])
	return out


## Every Digimon with a model: [[id, name]].
static func digimon_list(data: Node) -> Array:
	var out := []
	for r in data.records("digimon/digimon_data"):
		var id := int(r.get("id", -1))
		if id >= 0 and String(data.digimon_file(id).get("mmd", "")) != "":
			out.append([id, data.localize(r.get("name")).strip_edges()])
	return out


## A Digimon that has the technique (its list or its anim_technique), so its bone table takes it.
static func user_of(data: Node, id: int) -> int:
	for r in data.records("digimon/digimon_data"):
		for m in r.get("moves", []):
			if m.get("move") != null and int(m["move"]["id"]) == id:
				return int(r["id"])
		for t in r.get("anim_technique", {}).values():
			if int(t) == id:
				return int(r["id"])
	return -1


## Places the two Digimon and loads the technique, `percent` of the C's attack distance apart (a
## fighter starts a technique anywhere within it). "" or what went wrong (also in last_error).
func open(technique_id: int, caster: int, target: int, percent := 100) -> String:
	last_error = _open(technique_id, caster, target, percent)
	return last_error


func _open(technique_id: int, caster: int, target: int, percent: int) -> String:
	close()
	PsxMath.setup(GameData)
	technique = technique_id
	caster_type = caster
	target_type = target
	var move: Dictionary = GameData.move(technique)
	var radii := int(GameData.digimon(caster).get("radius", 0)) + int(GameData.digimon(target).get("radius", 0))
	var reach := radii
	if int(move.get("range", {}).get("id", 1)) != 1:
		reach = int(sqrt(float(int(move.get("distance_squared", 0)) + radii * radii)))
	reach = maxi(radii, reach * clampi(percent, 1, 100) / 100)
	ctx = GalleryWorld.new()
	ctx.data = GameData
	ctx.field_map = field_map
	ctx.camera = camera
	ctx.game_state = GameState
	ctx.sound = Sound
	ctx.map_layer_nodes = map_layer_nodes
	_hidden = hidden_nodes.call() if hidden_nodes.is_valid() else []
	# Across the screen at the tamer's place, facing each other.
	var centre: Vector3 = _hidden[0].global_position if not _hidden.is_empty() and _hidden[0] != null else Vector3.ZERO
	var right := camera.global_basis.x if camera != null else Vector3.RIGHT
	right = Vector3(right.x, 0.0, right.z).normalized()
	for i in [1, 2]:
		var d: FieldDigimon = DIGIMON_SCENE.instantiate()
		d.name = "GalleryDigimon%d" % i
		d.field = field_map
		world.add_child(d)
		if not d.load_digimon(GameData, caster if i == 1 else target):
			close()
			return "no model for Digimon %d" % (caster if i == 1 else target)
		d.global_position = centre + right * (reach * (-0.5 if i == 1 else 0.5))
		ctx.digimon[i] = d
		ctx.types[i] = caster if i == 1 else target
	ctx.look_at_location(1, ctx.location(2))
	ctx.look_at_location(2, ctx.location(1))
	for n in _hidden:
		if n != null:
			n.visible = false
	host = EffectHost.new(ctx)
	host.world = world
	slot = host.load_moves([{"technique": technique, "caster": 0}])[0]
	if slot < 0:
		var reason := "the effect didn't load (its bone table doesn't take this caster?)"
		close()
		return reason
	effect = host.slots[slot] as EfeEffect
	if effect != null:
		effect.record_draws = true
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.host = host
	world.add_child(fx_view)
	Sound.load_battle_sounds()
	active = true
	return ""


## Starts the effect (again): the caster plays the technique's animation if it has the technique.
func play() -> void:
	if not active or slot < 0:
		return
	frame = 0
	hits.clear()
	_hit_timers.clear()
	_shown.clear()
	for i in [1, 2]:
		ctx.set_hit(i, false)
	var moves: Array = GameData.digimon(caster_type).get("moves", [])
	for k in moves.size():
		if moves[k].get("move") != null and int(moves[k]["move"]["id"]) == technique:
			ctx.start_animation(1, ANIM_MOVE + k)
	var self_target := int(GameData.move(technique).get("range", {}).get("id", 1)) == 4
	host.start(slot, 1, 1 if self_target else 2)
	_running = true


## One game frame: the engine's tick and render, the shared effects, the hits.
func tick() -> void:
	if not active:
		return
	host.tick()
	host.draw()
	fx_view.draw_frame()
	if _running:
		frame += 1
		if effect != null:
			for c in effect.draw_calls:
				_shown[c[0]] = int(_shown.get(c[0], 0)) + 1
		if not host.slots[slot].is_running() and host.ctx.fx.active_count() == 0:
			_running = false
	for victim in [1, 2]:
		while true:
			var h := host.pop_attack_object(victim)
			if h.is_empty():
				break
			hits.append([frame, victim])
			_hit_timers[victim] = HIT_FRAMES
	for victim in _hit_timers.keys():
		_hit_timers[victim] -= 1
		if _hit_timers[victim] <= 0:
			ctx.set_hit(victim, false)
			_hit_timers.erase(victim)


func close() -> void:
	if host != null:
		host.unload_all()
		host = null
	effect = null
	if fx_view != null:
		fx_view.queue_free()
		fx_view = null
	if ctx != null:
		ctx.restore_view()
		for d in ctx.digimon.values():
			if is_instance_valid(d):
				d.queue_free()
		ctx = null
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = true
	_hidden.clear()
	if active:
		Sound.load_map_sounds(int(GameData.map(GameState.state["world"]["screen"]).get("sound_bank", 0)))
	active = false
	slot = -1
	_running = false


## What the tab shows.
func status() -> String:
	if not active:
		return last_error if last_error != "" else "Pick a technique and two Digimon, then Place."
	var lines := ["%s (technique %d, slot %s)" % [GameData.localize(GameData.move(technique).get("name")).strip_edges(),
			technique, EffectHost.efe_folder(technique)]]
	var subs := 0
	if effect != null:
		for c in effect.contexts:
			subs += 1 if c["inst"] != 0 else 0
	lines.append("frame %d, %s, %d live sub-effects, %d shared effects" % [frame,
			"running" if _running else "ended", subs, host.ctx.fx.active_count()])
	var hit_text := []
	for h in hits:
		hit_text.append("%d on %s" % [h[0], "caster" if h[1] == 1 else "target"])
	lines.append("hits: %s" % (", ".join(hit_text) if not hit_text.is_empty() else "none"))
	var drawn := []
	for k in _shown:
		drawn.append("%s %d" % [k, _shown[k]])
	lines.append("draw calls: %s" % (", ".join(drawn) if not drawn.is_empty() else "none"))
	if effect != null and effect.view != null and not effect.view.skipped.is_empty():
		lines.append("not drawn yet: %s" % str(effect.view.skipped))
	if effect != null and not effect.faults().is_empty():
		lines.append("faults: %s" % str(effect.faults()))
	return "\n".join(lines)
