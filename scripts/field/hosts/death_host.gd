class_name DeathHost
extends Node
## The death and lives scenes (specs/death_reincarnation.md §9, specs/death_scene.md §5;
## scenes/field/hosts/death_host.tscn). Its children MurdScene (a life lost) and DooaScene (the
## dissolution and the rebirth) are the logic, ticked by the field's frame order as objects; the
## tamer's states 17 / 19 and the partner's 8 / 14 start them and wait for them, as in the C. The host
## wires them and draws them, each view a scene a mod may replace:
## - PartnerWireframe (the body in outlines), DeathShards, RebirthEgg (with its pieces), SparkStreaks
##   and a BattleFxView for DOOA's flashes, in the 3D world;
## - the iris over the world (DeathIris, its canvas layer 1), with the partner drawn over it once it
##   is larger than the window (an overlay viewport on layer 2 that sees only the partner);
## - the map background's darkening (BackgroundDark, on the background layer) and MURD's full-screen
##   darkening (DeathDarken, in the HUD);
## - the palette fades (PaletteFade) and the squash (the partner's scale).
## The camera moves through FieldMap's view hook (DooaScene's view callables).

const IRIS_SCENE := preload("res://scenes/field/death/death_iris.tscn")
const DARKEN_SCENE := preload("res://scenes/field/death/death_darken.tscn")
const BACKGROUND_DARK_SCENE := preload("res://scenes/field/death/background_dark.tscn")
const SHARDS_SCENE := preload("res://scenes/field/death/death_shards.tscn")
const EGG_SCENE := preload("res://scenes/field/death/rebirth_egg.tscn")
const STREAKS_SCENE := preload("res://scenes/field/death/spark_streaks.tscn")
const FX_VIEW_SCENE := preload("res://scenes/battle/effects/battle_fx_view.tscn")
## The render layer the partner moves to while it is drawn over the iris.
const FRONT_LAYER := 1 << 19

var camera: Camera3D
var field_map: FieldMap
var tamer: Tamer
var partner: Partner
var entities: FieldEntities
var evolution: Evolution
var boxes: UIBoxes
var script_ctx: ScriptContext
var game_state: Node
var data: Node
var sound: Node
## changeMap(map, exit) (MapSession.change_map).
var change_map := Callable()
## The map layer's nodes (Field.map_layer_nodes): setMapLayerEnabled hides them.
var map_layer_nodes := Callable()
## The world SubViewport: the 3D views go in it, the iris layers over it.
var world: Node
## The field's fade: the map change holds it black while the map loads (Fade.hold, not in the C).
var fade: Fade

@onready var murd: MurdScene = $MurdScene
@onready var dooa: DooaScene = $DooaScene
@onready var wireframe: PartnerWireframe = $PartnerWireframe
## Made in start(): the field adds the background darkening to its background layer, the
## darkening to the HUD; the rest goes into the world here.
var iris: DeathIris
var darken: ColorRect
var background_dark: ColorRect
var egg: RebirthEgg
var shards_view: DeathShards
var streaks: SparkStreaks
var fx_view: BattleFxView

var _hidden_layer := {}
var _iris_layer: CanvasLayer
var _front_layer: CanvasLayer
var _overlay: SubViewport
var _overlay_camera: Camera3D
var _overlay_rect: TextureRect
## The partner's visual nodes' layers while it is drawn in front.
var _front_layers := {}
## The palette level last applied to each entity (PaletteFade).
var _fades := {}
var _egg_threshold := -1


## Hands the logic its references and makes the views.
func start() -> void:
	for scene: Node in [murd, dooa]:
		scene.set("partner", partner)
		scene.set("tamer", tamer)
		scene.set("entities", entities)
		scene.set("game_state", game_state)
		scene.set("sound", sound)
		scene.set("change_map", _change_to_death_map)
		scene.set("map_layer", _set_map_layer)
	murd.boxes = boxes
	murd.dooa = dooa
	murd.screen_point = _screen_point
	murd.data = data
	dooa.evolution = evolution
	dooa.data = data
	if field_map != null:
		for scene: Node in [murd, dooa]:
			scene.set("project", field_map.world_to_screen)
			scene.set("get_view", field_map.view)
		dooa.set_view = field_map.set_view
		dooa.restore_view = field_map.restore_map_view
	dooa.phase_changed.connect(_on_dooa_phase)
	dooa.wave_spawned.connect(_on_wave)
	tamer.murd = murd
	tamer.dooa = dooa
	tamer.script_ctx = script_ctx
	partner.dooa = dooa
	iris = IRIS_SCENE.instantiate()
	darken = DARKEN_SCENE.instantiate()
	background_dark = BACKGROUND_DARK_SCENE.instantiate()
	shards_view = SHARDS_SCENE.instantiate()
	shards_view.materials_of = wireframe.bone_materials
	egg = EGG_SCENE.instantiate()
	streaks = STREAKS_SCENE.instantiate()
	fx_view = FX_VIEW_SCENE.instantiate()
	fx_view.fx = dooa.fx
	fx_view.projector = field_map
	if world != null:
		for view: Node in [shards_view, egg, streaks, fx_view]:
			world.add_child(view)
		_make_layers()
	if camera != null:
		camera.cull_mask &= ~FRONT_LAYER


## The iris's canvas layer over the world and the partner's overlay over it.
func _make_layers() -> void:
	_iris_layer = CanvasLayer.new()
	_iris_layer.name = "DeathIrisLayer"
	_iris_layer.layer = 1
	_iris_layer.add_child(iris)
	world.add_child(_iris_layer)
	_front_layer = CanvasLayer.new()
	_front_layer.name = "DeathFrontLayer"
	_front_layer.layer = 2
	_overlay = SubViewport.new()
	_overlay.name = "PartnerOverlay"
	_overlay.transparent_bg = true
	_overlay.render_target_update_mode = SubViewport.UPDATE_DISABLED
	if world is Viewport:
		_overlay.world_3d = (world as Viewport).find_world_3d()
		_overlay.size = (world as SubViewport).size if world is SubViewport else Vector2i(FieldMap.SCREEN)
	_overlay_camera = Camera3D.new()
	_overlay_camera.cull_mask = FRONT_LAYER
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	_overlay_camera.environment = env
	_overlay.add_child(_overlay_camera)
	_front_layer.add_child(_overlay)
	_overlay_rect = TextureRect.new()
	_overlay_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_overlay_rect.stretch_mode = TextureRect.STRETCH_SCALE
	_overlay_rect.size = FieldMap.SCREEN
	_overlay_rect.texture = _overlay.get_texture()
	_overlay_rect.visible = false
	_front_layer.add_child(_overlay_rect)
	world.add_child(_front_layer)


## The field's render scale (Field.set_render_scale): the layers keep the PSX size.
func set_render_scale(value: int) -> void:
	for layer in [_iris_layer, _front_layer]:
		if layer != null:
			layer.scale = Vector2.ONE * value
	if _overlay != null:
		_overlay.size = Vector2i(FieldMap.SCREEN) * value


## The objects' frame (their place in the object list: after the script's objects), then what
## the C draws that frame (its render functions roll rand() too: the wireframe greys, the egg's,
## the streaks; specs/death_scene.md §5 "Order in the frame").
func tick_objects() -> void:
	murd.tick()
	dooa.tick()
	_draw_frame()


func _draw_frame() -> void:
	var dissolving := dooa.sequence == DooaScene.DISSOLVE
	var rebirth := dooa.sequence == DooaScene.REBIRTH
	# The wireframe body (A3, A5).
	if wireframe.is_attached():
		wireframe.set_share(dooa.wireframe_total if dissolving else PartnerWireframe.TOTAL)
		if wireframe.share != PartnerWireframe.TOTAL:
			wireframe.roll_greys(dooa.wire_color_min, dooa.wire_color_max)
	# The shards (F19–F22).
	if dooa.shards_active:
		shards_view.draw(dooa.shards)
	else:
		shards_view.clear()
	# The egg, its pieces and the streaks (G, H, I).
	if rebirth:
		if dooa.egg_threshold != _egg_threshold:
			_egg_threshold = dooa.egg_threshold
			egg.set_threshold(_egg_threshold)
		for i in RebirthEgg.PIECES:
			egg.set_piece_shown(i, dooa.piece_flags[i] == 0)
		egg.roll_greys(dooa.wire_color_min, dooa.wire_color_max, dooa.piece_flags)
		var at := partner.position
		var origin := Vector3i(roundi(at.x), roundi(-at.y) - 100, roundi(-at.z))
		streaks.draw_streaks(SparkStreaks.roll(dooa.fade_level, origin) if dooa.fade_level > 0 else [])
	else:
		streaks.draw_streaks([])
		egg.visible = false
	egg.draw_pieces(dooa.pieces)
	fx_view.draw_frame()
	# The squash (C3): the partner's root scale while DOOA runs.
	partner.scale = Vector3(dooa.scale) / DooaScene.ONE if dooa.sequence != DooaScene.NONE else Vector3.ONE
	# The palette fades (J): Jijimon in the dissolution, the tamer and entities 3 / 4 at the rebirth.
	if dissolving:
		_fade(_entity(2), dooa.jijimon_fade)
	if rebirth:
		_fade(tamer, dooa.tamer_fade)
		_fade(_entity(3), dooa.others_fade)
		_fade(_entity(4), dooa.others_fade)


func _entity(i: int) -> Node3D:
	return entities.entity(i) if entities != null else null


## A palette level on an entity's materials; level 0 gives its own back.
func _fade(entity: Node3D, level: int) -> void:
	if entity == null or _fades.get(entity) == level:
		return
	_fades[entity] = level
	if level <= 0:
		PaletteFade.clear(entity)
		_fades.erase(entity)
	else:
		PaletteFade.apply(entity, PaletteFade.factor(level))


## Every frame: the iris, the darkenings, the partner over the iris.
func _process(_delta: float) -> void:
	if iris == null:
		return
	var radius := -1
	var front := false
	if murd.active and murd.timer >= 0 and murd.timer < MurdScene.IRIS_DRAWN:
		radius = DeathIrisMath.radius(0, MurdScene.IRIS_END, murd.timer, false)
		front = murd.partner_front
	elif dooa.sequence == DooaScene.DISSOLVE and dooa.frame >= 0 and dooa.frame < DooaScene.IRIS_DRAWN:
		radius = DeathIrisMath.radius(0, DooaScene.IRIS_END, dooa.frame, true)
		front = dooa.partner_front
	if radius >= 0:
		iris.show_iris(_screen_point(_partner_centre()) + FieldMap.SCREEN / 2, radius)
	else:
		iris.hide_iris()
	_set_front(front and radius >= 0)
	var darkness := murd.darkness if murd.active else 0
	darkness = maxi(darkness, dooa.darkness)
	background_dark.color = Color(0, 0, 0, darkness / 255.0)
	var level := murd.darken if murd.active else 0
	darken.visible = level > 0
	darken.color = Color(level / 255.0, level / 255.0, level / 255.0)


## The partner drawn over the iris (B8, K3): its meshes on FRONT_LAYER, seen by the overlay's
## camera (the field camera's copy) only.
func _set_front(on: bool) -> void:
	if _overlay == null:
		return
	if on:
		if _front_layers.is_empty():
			for node in partner.find_children("*", "VisualInstance3D", true, false):
				var vi := node as VisualInstance3D
				_front_layers[vi] = vi.layers
				vi.layers = FRONT_LAYER
		if camera != null:
			_overlay_camera.global_transform = camera.global_transform
			_overlay_camera.projection = camera.projection
			_overlay_camera.keep_aspect = camera.keep_aspect
			_overlay_camera.size = camera.size
			_overlay_camera.frustum_offset = camera.frustum_offset
			_overlay_camera.near = camera.near
			_overlay_camera.far = camera.far
			_overlay_camera.fov = camera.fov
		_overlay.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		_overlay_rect.visible = true
	elif not _front_layers.is_empty():
		for vi: VisualInstance3D in _front_layers:
			if is_instance_valid(vi):
				vi.layers = _front_layers[vi]
		_front_layers.clear()
		_overlay.render_target_update_mode = SubViewport.UPDATE_DISABLED
		_overlay_rect.visible = false


## The partner's middle: its location raised by half its height (MURD_renderIris).
func _partner_centre() -> Vector3:
	var height := 0
	if data != null and partner.digimon != "":
		height = int(data.digimon(partner.digimon).get("height", 0))
	return partner.global_position + Vector3(0, height / 2.0, 0)


## worldPosToScreenPos: centred PSX screen pixels.
func _screen_point(world_point: Vector3) -> Vector2:
	if camera == null or not camera.is_inside_tree():
		return Vector2.ZERO
	return FieldMap.unproject(camera, world_point) - FieldMap.SCREEN / 2


## changeToDeathMap: the field's map change, then the fade released. MapSession.change_map holds
## the screen black for the load (Fade.hold, port-only) until a fade in; the C's death map change
## has no fade (MURD and DOOA darken the screen themselves), so the fade clears at once after the
## hold.
func _change_to_death_map(map: int, exit: int) -> void:
	if change_map.is_valid():
		change_map.call(map, exit)
	if fade != null:
		fade.fade_from_black(0)


## setMapLayerEnabled (as FieldBattleWorld's): the map's objects hidden, then back as they were.
func _set_map_layer(enabled: bool) -> void:
	if not enabled:
		var nodes: Array = map_layer_nodes.call() if map_layer_nodes.is_valid() else []
		for n in nodes:
			if n != null and is_instance_valid(n) and not _hidden_layer.has(n):
				_hidden_layer[n] = n.visible
				n.visible = false
	else:
		for n in _hidden_layer:
			if is_instance_valid(n):
				n.visible = _hidden_layer[n]
		_hidden_layer.clear()


## The views that start and end with DOOA's phases.
func _on_dooa_phase(phase: int) -> void:
	match phase:
		DooaScene.PHASE_TURN:
			_attach_wireframe()
		DooaScene.PHASE_RISE:
			wireframe.detach()
		DooaScene.PHASE_REBIRTH:
			_egg_threshold = -1
			egg.load_egg(dooa.egg_slot)


## The wireframe on the partner's current model (its sidecar and glTF).
func _attach_wireframe() -> void:
	var model := _partner_model()
	if model == null or data == null:
		return
	var mmd: String = data.digimon_file(partner.digimon).get("mmd", "")
	if mmd == "":
		return
	var rel := "mmd_files/%s/%s.gltf" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var sidecar: Variant = Content.load_json(rel.get_basename() + ".json")
	var gltf: Variant = Content.load_json(rel)
	if sidecar is Dictionary and gltf is Dictionary:
		wireframe.attach(model, sidecar, gltf)


func _partner_model() -> Node3D:
	var slot := partner.get_node_or_null("Model")
	if slot == null or slot.get_child_count() == 0:
		return null
	return slot.get_child(slot.get_child_count() - 1) as Node3D


## DOOA_spawnShardWave (B2): the bones in this frame's pose.
func _on_wave(wave: int) -> void:
	dooa.shards.spawn_wave(wave, wireframe.posed_bones())

