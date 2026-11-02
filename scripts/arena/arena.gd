class_name Arena
extends Node
## The arena (specs/arena.md §5.1, step 4): builtin 0x06's tournament (startTournament ->
## STD_tournamentMain). Replaces ArenaStandIn with its API: start(cup, opponents), finished, result
## (matches won). While it runs the field draws and ticks nothing but it (Field._frame): it builds
## its own world in the field's 3D viewport (the arena model, its own fighters, the arena camera,
## the arena's lights) over the hidden field, runs an ArenaSession a frame, and gives the field back
## after. The script warps right after (specs/arena.md §1.1), which reloads the map.
## The HUD is a plain one until step 5 (the original's pieces).

const NPC_SCENE := preload("res://scenes/field/npc.tscn")
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
const VISUALS_VIEW_SCENE := preload("res://scenes/battle/fx/battle_visuals_view.tscn")
const HUD_SCENE := preload("res://scenes/arena/arena_hud.tscn")
## STD_ARENA_MODELS (std_main.c:1326) by the map's arena_model; STD_ARENA_COLLISIONS: B_TOGI.ATR for both.
const ARENA_MODELS := ["tmd_files/STDDAT/T_TOGI.gltf", "tmd_files/STDDAT/B_TOGI.gltf"]
const ARENA_COLLISION := "atr_files/STDDAT/B_TOGI/B_TOGI.json"
## STD_initializeLighting (std_setup.c:474-499): three flat lights (direction, colour 0-255) and
## GsSetAmbient(0x400, ...) (4096 = 1.0).
const LIGHTS := [[[1000, 1000, 1000], [255, 255, 255]], [[-1000, 1000, -1000], [160, 160, 160]],
		[[-20, 20, 200], [96, 96, 96]]]
const AMBIENT := 0x400

## Debug (the Partner tab): >= 0 skips the arena and finishes at once with this result, as the
## stand-in did; -1 plays it.
@export var debug_result := -1

var finished := false
var result := 0
var last_cup := -1
var last_opponents: Array = []
## GAME_STATE 4 / 5: the field runs only the arena's frame.
var active := false
var game_data: Node

## Set by the field: its 3D viewport, what to hide, the fade.
var world: Node
var field_camera: Camera3D
## func() -> Array: the field's nodes to hide while the arena is up (map, background, entities, clock).
var field_nodes := Callable()
var fade: Node
var hud: CanvasLayer
## The field's HUD slot behind the UI boxes (the battle HUD's: BattleHost.hud_slot), the shared text
## area and the UI boxes (the time-out window is box 0).
var hud_slot: Control
var text_area: TextArea
var boxes: UIBoxes
var arena_hud: ArenaHud

var session: ArenaSession
var arena_world: ArenaWorld
var camera: ArenaCamera
var effects: EffectHost
var fx_view: BattleFxView
var visuals_view: BattleVisualsView

var _root: Node3D
var _view: Camera3D
var _collision: FieldMap
var _entities: FieldEntities
var _label: Label
var _hidden := {}
## The field entities paused while the arena runs, with their process mode before.
var _paused := {}
var _pad_previous := 0


func _data() -> Node:
	if game_data != null:
		return game_data
	return get_node_or_null("/root/GameData") if is_inside_tree() else null


## startTournament's STD_tournamentMain(&{cup, opponents[7]}) (utils2.c:661).
func start(cup: int, opponents: Array) -> void:
	last_cup = cup
	last_opponents = opponents.duplicate()
	finished = false
	if debug_result >= 0 or world == null:
		if world == null:
			push_warning("Arena: no field world; finishing with result %d" % maxi(debug_result, 0))
		result = maxi(debug_result, 0)
		finished = true
		return
	# port-only: an opponent 0xFF ("none": an empty pool with no list to fall back on,
	# TournamentCups.draw_opponents) would be a fighter with stats and no body; the C's would be
	# whatever the pool's old memory held. The tournament ends at once with no win.
	for o in opponents:
		if int(o) == TournamentCups.EMPTY:
			push_error("Arena: no opponent for cup %d (no Digimon has joined); the tournament is skipped" % cup)
			result = 0
			finished = true
			return
	var data := _data()
	PsxMath.setup(data)
	var arena_id := int(data.map(GameState.state["world"]["screen"]).get("arena_model", 0))
	_build(arena_id)
	session = ArenaSession.new(arena_world, effects, data, camera)
	session.spawn_opponent = _spawn_opponent
	session.remove_opponents = _remove_opponents
	session.fader = _fade
	session.visual.connect(_on_visual)
	_pad_previous = GameLoop.pad.polled if GameLoop.pad != null else 0
	active = true
	session.begin(cup, opponents, arena_id)


# --- the arena's world ----------------------------------------------------------------------------

func _build(arena_id: int) -> void:
	var data := _data()
	_hide_field()
	_root = Node3D.new()
	_root.name = "Arena"
	world.add_child(_root)
	var model := Content.load_model(ARENA_MODELS[arena_id])
	if model != null:
		model.name = "ArenaModel"
		_root.add_child(model)
	_collision = FieldMap.new()
	_collision.name = "ArenaCollision"
	var atr = Content.load_json(ARENA_COLLISION)
	if atr is Dictionary:
		_collision.load_collision(atr["collision"]["values"])
	_view = Camera3D.new()
	_view.name = "ArenaCamera"
	_view.keep_aspect = Camera3D.KEEP_HEIGHT
	_root.add_child(_view)
	_view.current = true
	_entities = FieldEntities.new()
	_entities.partner = _make_fighter(GameState.state["partner"]["digimon"], 1)
	_apply_lights()
	arena_world = ArenaWorld.new()
	arena_world.data = data
	arena_world.entities = _entities
	arena_world.field_map = _collision
	arena_world.game_state = GameState
	arena_world.sound = Sound
	arena_world.fader = func(frames: int) -> void: _fade("out", frames)
	arena_world.view_camera = _view
	camera = ArenaCamera.new(arena_world, 1)
	arena_world.arena_camera = camera
	effects = EffectHost.new(arena_world)
	effects.world = world
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.host = effects
	world.add_child(fx_view)
	visuals_view = VISUALS_VIEW_SCENE.instantiate()
	visuals_view.visuals = effects.ctx.visuals
	effects.ctx.visuals.view = visuals_view
	world.add_child(visuals_view)
	arena_hud = HUD_SCENE.instantiate()
	arena_hud.world = arena_world
	arena_hud.text_area = text_area
	arena_hud.boxes = boxes
	arena_hud.data = data
	if hud_slot != null:
		hud_slot.add_child(arena_hud)
	_label = Label.new()
	_label.name = "ArenaHud"
	_label.position = Vector2(8, 196)
	_label.add_theme_font_size_override("font_size", 9)
	if hud != null:
		hud.add_child(_label)


## An arena fighter: an NPC entity nobody ticks (STD_tickNPCTournament removes its object; the
## partner's tick is tickAnimation): it only animates, on the arena's collision.
func _make_fighter(ref: Variant, entity: int) -> Npc:
	var npc: Npc = NPC_SCENE.instantiate()
	npc.name = "Fighter%d" % entity
	npc.slot = maxi(entity - 2, 0)
	npc.field = _collision
	npc.entities = _entities
	_root.add_child(npc)
	if not npc.load_digimon(_data(), ref):
		npc.queue_free()
		return null
	npc.animation_sound.connect(func(bank: int, value: int) -> void: Sound.play_sound(bank, value))
	return npc


## STD_initializeOpponent's entity (ENTITY_TABLE[slot + 2], isOnMap / isOnScreen 1).
func _spawn_opponent(slot: int, type: int, stats: Dictionary) -> int:
	var s: Dictionary = _entities.slots[slot]
	s["type"] = type
	s["stats"] = stats
	var npc := _make_fighter(type, slot + 2)
	_entities.npcs[slot] = npc
	var key: String = str(_data().digimon(type).get("key", type))
	if npc == null:
		push_error("Arena: match %d: the opponent %s has no model" % [slot + 1, key])
	else:
		print("Arena: match %d: %s (HP %d)" % [slot + 1, key, int(stats["base"]["max_hp"])])
	return slot + 2


## removeMapEntities.
func _remove_opponents() -> void:
	for i in FieldEntities.NPC_SLOTS:
		var n: Node = _entities.npcs[i]
		if n != null:
			n.queue_free()
		_entities.npcs[i] = null
	_entities.clear_map_digimon()


func _apply_lights() -> void:
	var lights := []
	for l in LIGHTS:
		lights.append({"direction": l[0], "color": l[1]})
	FieldLighting.apply(lights, FieldLighting.DAY)
	var a := AMBIENT / 4096.0
	RenderingServer.global_shader_parameter_set("psx_ambient", Vector3(a, a, a))
	FieldLighting.current["psx_ambient"] = Vector3(a, a, a)


## The field's objects go (STD_initializeTournament: removeMapEntities, the tamer off screen,
## STD_removeOverworldObjects): hidden, and its entities paused (no animation, no root motion, no
## step sounds: their objects don't tick in the C) until the arena gives the field back.
func _hide_field() -> void:
	_hidden.clear()
	_paused.clear()
	var nodes: Array = field_nodes.call() if field_nodes.is_valid() else []
	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		if "visible" in n:
			_hidden[n] = n.visible
			n.visible = false
		if n is FieldDigimon or n is Tamer:
			_paused[n] = n.process_mode
			n.process_mode = Node.PROCESS_MODE_DISABLED


func _restore_field() -> void:
	for n in _hidden:
		if is_instance_valid(n):
			n.visible = _hidden[n]
	_hidden.clear()
	for n in _paused:
		if is_instance_valid(n):
			n.process_mode = _paused[n]
	_paused.clear()
	if field_camera != null:
		field_camera.current = true


func _fade(kind: String, frames: int) -> void:
	if fade == null:
		return
	if kind == "out" and fade.has_method("fade_to_black"):
		fade.fade_to_black(frames)
	elif kind == "in" and fade.has_method("fade_from_black"):
		fade.fade_from_black(frames)


# --- the frame ------------------------------------------------------------------------------------

## One game frame of the tournament (STD_battleTickFrame for the session's phase).
func frame() -> void:
	if not active:
		return
	var polled: int = GameLoop.pad.polled if GameLoop.pad != null else 0
	var pressed := polled & ~_pad_previous
	_pad_previous = polled
	session.frame(pressed)
	if arena_hud != null:
		if arena_hud.session != session.current_match and session.current_match != null:
			arena_hud.set_match(session.current_match)
		arena_hud.tick(pressed)
	_update_view()
	if fx_view != null:
		fx_view.draw_frame()
	if visuals_view != null:
		visuals_view.draw_frame()
	arena_world.end_frame()
	_update_hud()
	if session.is_done():
		_finish()


## The Godot camera from the arena camera's GsWSMATRIX (rows: right, down, forward; t = -R · eye)
## and its projection (the drawing offset is the screen centre).
func _update_view() -> void:
	if _view == null or camera == null:
		return
	var m := camera.world_screen_matrix()
	var rows: Array[Vector3] = []
	for i in 3:
		rows.append(Vector3(m[i * 3], m[i * 3 + 1], m[i * 3 + 2]) / 4096.0)
	var t := Vector3(m[9], m[10], m[11])
	var eye := -(rows[0] * t.x + rows[1] * t.y + rows[2] * t.z)
	var right := Content.psx_to_godot([rows[0].x, rows[0].y, rows[0].z])
	var up := -Content.psx_to_godot([rows[1].x, rows[1].y, rows[1].z])
	var back := -Content.psx_to_godot([rows[2].x, rows[2].y, rows[2].z])
	_view.transform = Transform3D(Basis(right, up, back).orthonormalized(), Content.psx_to_godot([eye.x, eye.y, eye.z]))
	var h := maxf(float(camera.projection()), 1.0)
	_view.set_frustum(FieldMap.SCREEN.y * FieldMap.NEAR / h, Vector2.ZERO, FieldMap.NEAR, FieldMap.FAR)


## A line naming the parts whose pictures come in step 6 (the bracket, the champion's scene).
const PHASE_TEXT := {
	ArenaSession.Phase.BRACKET_INTRO: "bracket intro (picture: step 6)",
	ArenaSession.Phase.BRACKET: "bracket, before match %d (picture: step 6)",
	ArenaSession.Phase.CHAMPION_BRACKET: "champion's bracket (picture: step 6)",
	ArenaSession.Phase.CHAMPION_IN: "champion (picture: step 6)",
	ArenaSession.Phase.CHAMPION: "champion (picture: step 6)",
}


func _update_hud() -> void:
	if _label == null:
		return
	var text: String = PHASE_TEXT.get(session.phase, "")
	_label.text = text % (session.played + 1) if "%d" in text else text


func _on_visual(kind: String, args: Array) -> void:
	if arena_hud != null:
		arena_hud.on_visual(kind, args)


func _finish() -> void:
	active = false
	result = session.result
	if fx_view != null:
		fx_view.queue_free()
		fx_view = null
	if visuals_view != null:
		effects.ctx.visuals.remove_all()
		effects.ctx.visuals.view = null
		visuals_view.queue_free()
		visuals_view = null
	arena_world.restore_view()
	if _label != null:
		_label.queue_free()
		_label = null
	if arena_hud != null:
		arena_hud.queue_free()
		arena_hud = null
	if _root != null:
		_root.queue_free()
		_root = null
	if _collision != null:
		_collision.free()
		_collision = null
	_restore_field()
	finished = true
