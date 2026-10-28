class_name DeathHost
extends Node
## Coordinates death cutscenes, lives loss, hospital recovery, and reincarnation
## (specs/death_reincarnation.md; src/murd/murd.c, src/dooa/dooa.c).
##
## Features:
## 1. Iris transition onto partner on life loss / collapse with edgeless full black wipe.
## 2. MurdBox presentation with heart blink/loss animation with partner visible on screen.
## 3. Hospital warp to Centar Clinic (Map 213) or Jijimon's House (Map 205 / 218) with recovery states.
## 4. Digital shard dissolution (textures falling into floor leaving wireframe, PSX dooa.c / doo2.c).
## 5. Digitama in center of Jijimon's room on 0 lives, hatching baby and moving to player.

const MAP_JIJIMON_HOUSE_EARLY := 218   # ROOM08
const MAP_JIJIMON_HOUSE_LATE := 205    # ROOM10
const MAP_CLINIC := 213                # Centar Clinic (Centarumon)

const TRIGGER_JIJIMON_EXTENDED := 0xDC
const TRIGGER_CLINIC_OPEN := 0xD6

const MurdBox := preload("res://scripts/ui/murd_box.gd")
const DeathIris := preload("res://scripts/ui/death_iris.gd")
const ContentClass := preload("res://scripts/content/content.gd")

## Injected field dependencies
var field_map: FieldMap
var camera: Camera3D
var tamer: Tamer
var partner: Partner
var clock: Clock
var fade: Fade
var script_ctx: ScriptContext
var interpreter: ScriptInterpreter
var boxes: UIBoxes
var game_state: Node

var murd_box: MurdBox
var iris: DeathIris

## Active scene execution state
var is_active := false
var scene_phase := 0
var scene_timer := 0
var routine_id := 0

## Dissolution and rebirth visuals
var _wireframe_nodes: Array[Node] = []
var _dissolve_materials: Array[ShaderMaterial] = []
var _dissolve_meshes: Array[MeshInstance3D] = []
var _dissolve_orig_materials: Array[Material] = []
var _egg_node: Node3D = null
var _baby_key := ""


func _init() -> void:
	murd_box = MurdBox.new()
	iris = DeathIris.new()


func configure(p_boxes: UIBoxes, p_fade: Fade, p_tamer: Tamer, p_partner: Partner,
		p_ctx: ScriptContext, p_interp: ScriptInterpreter, p_camera: Camera3D, p_gs: Node = null) -> void:
	boxes = p_boxes
	fade = p_fade
	tamer = p_tamer
	partner = p_partner
	script_ctx = p_ctx
	interpreter = p_interp
	camera = p_camera
	game_state = p_gs if p_gs != null else (p_ctx.game_state if p_ctx != null else null)
	if murd_box != null:
		murd_box.boxes = boxes


## Start MURD or DOOA cutscene for the given routine
func start_scene(routine: int) -> void:
	routine_id = routine
	is_active = true
	scene_phase = 0
	scene_timer = 0

	# Disable camera follow on player during cutscene
	if tamer != null:
		tamer.camera_follow = false

	# Center iris on partner's screen position
	var screen_center := Vector2(0.5, 0.5)
	if camera != null and partner != null:
		if not camera.is_position_behind(partner.global_position):
			var pos_2d := camera.unproject_position(partner.global_position)
			var cam_vp := camera.get_viewport()
			if cam_vp != null and cam_vp.size.x > 0 and cam_vp.size.y > 0:
				screen_center = Vector2(
					clampf(pos_2d.x / float(cam_vp.size.x), 0.2, 0.8),
					clampf(pos_2d.y / float(cam_vp.size.y), 0.2, 0.8)
				)

	match routine:
		ScriptInterpreter.ROUTINE_COLLAPSE, ScriptInterpreter.ROUTINE_BATTLE_LOSS:
			if tamer != null:
				tamer.visible = false
			iris.start_iris_in(screen_center)
			scene_phase = 1
		ScriptInterpreter.ROUTINE_DYING:
			# Natural death: wireframe & texture fall dissolution
			if tamer != null:
				tamer.visible = false
			_start_dissolution()
			scene_phase = 10
		ScriptInterpreter.ROUTINE_REBIRTH:
			# Egg hatching into baby
			scene_phase = 20


func start_rebirth_sequence(baby_key: String) -> void:
	_baby_key = baby_key
	is_active = true
	scene_phase = 20
	scene_timer = 0
	if script_ctx != null:
		script_ctx.sync_bit = 0


func tick() -> void:
	if not is_active:
		return

	scene_timer += 1
	match scene_phase:
		# 1: Iris closing in on partner (partner visible on top of black)
		1:
			if iris.tick():
				# Phase 2: Open MurdBox
				scene_phase = 2
				scene_timer = 0
				var current_lives: int = int(_get_game_state().state["partner"].get("lives", 0)) if _get_game_state() != null else 0
				murd_box.open(current_lives)
		# 2: MurdBox ticking (heart blinking/fade; partner visible beneath)
		2:
			murd_box.tick()
			# At frame 60, finish MurdBox and proceed
			if scene_timer >= 60:
				murd_box.close()
				var current_lives: int = int(_get_game_state().state["partner"].get("lives", 0)) if _get_game_state() != null else 0
				if current_lives == 0:
					# 0 lives: start dissolution (textures fall to floor leaving wireframe)
					_start_dissolution()
					scene_phase = 10
					scene_timer = 0
				else:
					# Remaining lives: warp to recovery map
					scene_phase = 3
					scene_timer = 0
		# 3: Recovery map warp (Centar Clinic or Jijimon's House)
		3:
			_warp_to_recovery_hospital()
			scene_phase = 4
			scene_timer = 0
		# 4: Wait after warp, set sync bit
		4:
			if scene_timer >= 10:
				_finish_scene()

		# 10..12: Death Dissolution (Wireframe & Texture Fall)
		10:
			# Progressively melt/fall textures down to floor level over 35 frames
			var p := clampf(float(scene_timer) / 35.0, 0.0, 1.0)
			for mat in _dissolve_materials:
				mat.set_shader_parameter("fall_progress", p)
			if scene_timer >= 40:
				if Engine.has_singleton("Sound"):
					Engine.get_singleton("Sound").play_sound(8, 2)
				scene_phase = 11
				scene_timer = 0
		11:
			# Wireframe flickers and floor puddle fades out
			var alpha := clampf(1.0 - float(scene_timer) / 20.0, 0.0, 1.0)
			for mat in _dissolve_materials:
				mat.set_shader_parameter("alpha", alpha)
			var visible_toggle := (scene_timer % 2 == 0)
			for wf in _wireframe_nodes:
				if is_instance_valid(wf):
					wf.visible = visible_toggle
			if scene_timer >= 20:
				_cleanup_dissolution()
				if Engine.has_singleton("Sound"):
					Engine.get_singleton("Sound").play_sound(8, 3)
				if partner != null:
					partner.visible = false
				_warp_to_recovery_hospital()
				scene_phase = 12
				scene_timer = 0
		12:
			if scene_timer >= 10:
				_finish_scene()

		# 20..22: Rebirth Digitama Hatching & Hop to Player (Point 3)
		20:
			# Digitama egg wobbles / shakes in the center of the room
			if _egg_node != null and is_instance_valid(_egg_node):
				_egg_node.rotation.z = sin(float(scene_timer) * 0.8) * 0.25
			if scene_timer >= 30:
				if _egg_node != null and is_instance_valid(_egg_node):
					_egg_node.queue_free()
					_egg_node = null

				# Load baby model at room center (0, 0, 0)
				var d: Node = _get_data()
				if partner != null and d != null and _baby_key != "":
					partner.load_digimon(d, _baby_key)
					partner.position = Vector3(0, 0, 0)
					partner.visible = true
					if tamer != null:
						partner.look_at_psx(int(tamer.position.x), int(-tamer.position.z))
					partner.start_animation(Partner.ANIM_WALK)

				if Engine.has_singleton("Sound"):
					Engine.get_singleton("Sound").play_sound(8, 6)

				scene_phase = 21
				scene_timer = 0
		21:
			# Baby moves towards tamer
			if partner != null and tamer != null:
				var to_tamer := tamer.position - partner.position
				var dist_xz := Vector2(to_tamer.x, to_tamer.z).length()
				if dist_xz > 60.0 and scene_timer < 120:
					var step_dir := Vector3(to_tamer.x, 0, to_tamer.z).normalized()
					partner.position += step_dir * 4.0
					partner.look_at_psx(int(tamer.position.x), int(-tamer.position.z))
				else:
					partner.start_animation(Partner.ANIM_IDLE)
					partner.look_at_psx(int(tamer.position.x), int(-tamer.position.z))
					partner.set_state(Partner.STATE_NORMAL)
					scene_phase = 22
					scene_timer = 0
			else:
				scene_phase = 22
				scene_timer = 0
		22:
			if scene_timer >= 10:
				_finish_scene()


func _start_dissolution() -> void:
	_cleanup_dissolution()
	if partner == null:
		return

	var mesh_instances := partner.find_children("*", "MeshInstance3D", true, false)
	for mi in mesh_instances:
		var mesh_instance := mi as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue

		var m := mesh_instance.mesh
		# 1. Build wireframe mesh
		var wire_mesh := ArrayMesh.new()
		for s in m.get_surface_count():
			var arrays := m.surface_get_arrays(s)
			if arrays.is_empty():
				continue
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var line_indices := PackedInt32Array()
			for t in range(0, indices.size(), 3):
				if t + 2 < indices.size():
					var a := indices[t]
					var b := indices[t + 1]
					var c := indices[t + 2]
					line_indices.append_array([a, b, b, c, c, a])

			var line_arrays := []
			line_arrays.resize(Mesh.ARRAY_MAX)
			line_arrays[Mesh.ARRAY_VERTEX] = arrays[Mesh.ARRAY_VERTEX]
			line_arrays[Mesh.ARRAY_INDEX] = line_indices
			if arrays[Mesh.ARRAY_BONES] != null:
				line_arrays[Mesh.ARRAY_BONES] = arrays[Mesh.ARRAY_BONES]
			if arrays[Mesh.ARRAY_WEIGHTS] != null:
				line_arrays[Mesh.ARRAY_WEIGHTS] = arrays[Mesh.ARRAY_WEIGHTS]
			wire_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, line_arrays)

		var wire_inst := MeshInstance3D.new()
		wire_inst.mesh = wire_mesh
		wire_inst.skin = mesh_instance.skin
		wire_inst.skeleton = mesh_instance.skeleton
		var wire_mat := StandardMaterial3D.new()
		wire_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		wire_mat.albedo_color = Color(0.85, 0.85, 0.95, 1.0)
		wire_inst.material_override = wire_mat
		mesh_instance.get_parent().add_child(wire_inst)
		_wireframe_nodes.append(wire_inst)

		# 2. Setup texture fall shader on the original mesh
		var orig_mat := mesh_instance.material_override
		if orig_mat == null and mesh_instance.get_surface_override_material(0) != null:
			orig_mat = mesh_instance.get_surface_override_material(0)
		_dissolve_meshes.append(mesh_instance)
		_dissolve_orig_materials.append(orig_mat)

		var tex: Texture2D = null
		if orig_mat is ShaderMaterial:
			tex = (orig_mat as ShaderMaterial).get_shader_parameter("albedo_texture")
		elif orig_mat is BaseMaterial3D:
			tex = (orig_mat as BaseMaterial3D).albedo_texture

		var fall_shader := Shader.new()
		fall_shader.code = """shader_type spatial;
render_mode cull_disabled;
uniform sampler2D albedo_texture : source_color, filter_nearest;
uniform float fall_progress : hint_range(0.0, 1.0) = 0.0;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;

void vertex() {
	if (fall_progress > 0.0) {
		float p = clamp(fall_progress, 0.0, 1.0);
		VERTEX.y = mix(VERTEX.y, 0.0, p);
		float seed = float(VERTEX_ID);
		VERTEX.x += (fract(sin(seed * 12.9898) * 43758.5453) - 0.5) * p * 0.15;
		VERTEX.z += (fract(cos(seed * 78.233) * 43758.5453) - 0.5) * p * 0.15;
	}
}

void fragment() {
	vec4 col = texture(albedo_texture, UV);
	ALBEDO = col.rgb;
	ALPHA = col.a * alpha;
}
"""
		var fall_mat := ShaderMaterial.new()
		fall_mat.shader = fall_shader
		if tex != null:
			fall_mat.set_shader_parameter("albedo_texture", tex)
		fall_mat.set_shader_parameter("fall_progress", 0.0)
		fall_mat.set_shader_parameter("alpha", 1.0)
		mesh_instance.material_override = fall_mat
		_dissolve_materials.append(fall_mat)


func _cleanup_dissolution() -> void:
	for node in _wireframe_nodes:
		if is_instance_valid(node):
			node.queue_free()
	_wireframe_nodes.clear()
	for i in range(_dissolve_meshes.size()):
		var mi := _dissolve_meshes[i]
		if is_instance_valid(mi):
			mi.material_override = _dissolve_orig_materials[i]
	_dissolve_meshes.clear()
	_dissolve_orig_materials.clear()
	_dissolve_materials.clear()


func _spawn_digitama() -> void:
	if _egg_node != null and is_instance_valid(_egg_node):
		_egg_node.queue_free()
	_egg_node = null

	var egg: Node3D = null
	if ContentClass.exists("tmd_files/ETCDAT/TAMA.gltf"):
		egg = ContentClass.load_model("tmd_files/ETCDAT/TAMA.gltf")
	if egg == null:
		egg = Node3D.new()
		var mi := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 16.0
		sphere.height = 36.0
		mi.mesh = sphere
		egg.add_child(mi)

	egg.name = "Digitama"
	egg.position = Vector3(0, 0, 0)
	if field_map != null:
		field_map.add_child(egg)
	elif partner != null and partner.get_parent() != null:
		partner.get_parent().add_child(egg)
	_egg_node = egg


func _warp_to_recovery_hospital() -> void:
	if iris != null:
		iris.hide_iris()
	var gs := _get_game_state()
	var current_lives := 0
	if gs != null and gs.state.has("partner"):
		current_lives = int(gs.state["partner"].get("lives", 0))
		if gs.state["partner"].has("care"):
			var care: Dictionary = gs.state["partner"]["care"]
			if int(care.get("remaining_lifetime", 0)) <= 0 and current_lives > 0:
				care["remaining_lifetime"] = 360
	var target_map := determine_death_map()
	if tamer != null and tamer.change_map.is_valid():
		tamer.change_map.call(target_map, 1)
	var f := _get_fade()
	if f != null:
		f.fade_from_black(0x14)
	if partner != null:
		if current_lives == 0:
			partner.visible = false
			_spawn_digitama()
		else:
			partner.visible = true
			partner.set_state(Partner.STATE_IDLE)
	if tamer != null:
		tamer.visible = true


func _finish_scene() -> void:
	is_active = false
	if iris != null:
		iris.hide_iris()
	if tamer != null:
		tamer.camera_follow = true
		tamer.visible = true
	# Set script sync bit to release WAIT_FOR_ENTITY in section 0x4DE / script 212
	if script_ctx != null:
		script_ctx.sync_bit = 1


func _get_data() -> Node:
	if script_ctx != null and script_ctx.data != null:
		return script_ctx.data
	if interpreter != null and interpreter.data != null:
		return interpreter.data
	if Engine.has_singleton("GameData"):
		return Engine.get_singleton("GameData")
	return null


func _get_fade() -> Fade:
	if fade != null:
		return fade
	if tamer != null and tamer.fade != null:
		return tamer.fade
	return null


## Selects destination map according to PSX decompilation (murd.c:781, dooa.c:1734):
## If trigger 0xDC (Centarumon clinic) or 0xD6 (Clinic open) is set, or prosperity (pstat 1) >= 50:
##   target = 0xCD (205, Jijimon's House late)
## Else:
##   target = 0xDA (218, Jijimon's House early)
func determine_death_map() -> int:
	var gs := _get_game_state()
	if gs == null:
		return MAP_JIJIMON_HOUSE_EARLY
	var clinic_open: bool = gs.is_trigger_set(TRIGGER_CLINIC_OPEN) or gs.is_trigger_set(TRIGGER_JIJIMON_EXTENDED)
	var prosperity := int(gs.script_value(1))
	if clinic_open or prosperity >= 50:
		return MAP_JIJIMON_HOUSE_LATE
	return MAP_JIJIMON_HOUSE_EARLY


func _get_game_state() -> Node:
	if game_state != null:
		return game_state
	if script_ctx != null and script_ctx.game_state != null:
		return script_ctx.game_state
	if Engine.has_singleton("GameState"):
		return Engine.get_singleton("GameState")
	return null
