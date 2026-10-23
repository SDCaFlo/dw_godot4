extends SceneTree
## Content (scripts/content/content.gd) against the real asset porter output:
##   godot --headless --path . -s res://tests/test_content.gd
## Runtime loading always; imported copies only if the editor mirror exists and is imported
## (Project > Tools > "DW: Mirror dw1 assets"). Exits 1 if a check fails.

const MODELS := ["mmd_files/MMD0/BOYS.gltf", "mmd_files/MMD0/AGUM.gltf"]
## Rotation tolerance (rad) and position / scale tolerance between the two loaders.
const TOLERANCE := 0.01

var _failed := 0


func _init() -> void:
	var content: Script = load("res://scripts/content/content.gd")
	if not DirAccess.dir_exists_absolute(content.root()):
		print("SKIP: no asset porter output in %s" % content.root())
		quit(0)
		return

	# Runtime loading keeps the porter's keys: BOYS anim_00, bone_1 is (0, 167, 1) at 0.25 s
	# (a 30 fps resample or the key optimizer would give 167.5 / 1.5).
	var raw: Node3D = content._load_gltf(content.path(MODELS[0]))
	var raw_anim: Animation = _player(raw).get_animation("anim_00")
	_eq(_sample(raw_anim, raw_anim.find_track(NodePath("Skeleton3D:bone_1"), Animation.TYPE_POSITION_3D), Animation.TYPE_POSITION_3D, 0.25), Vector3(0, 167, 1), "raw loader keeps the 20 fps keys")
	_eq(raw.find_children("*", "MeshInstance3D", true, false).size(), 14, "raw tamer meshes")
	raw.free()

	var model: Node3D = content.load_model(MODELS[0])
	var mesh: MeshInstance3D = model.find_children("*", "MeshInstance3D", true, false)[0]
	_eq(mesh.get_surface_override_material(0) != null, true, "PSX material is a per-instance override")
	model.free()

	if content.imported(MODELS[0]) == "":
		print("SKIP imported checks: no editor mirror in %s" % content.MIRROR_DIR)
	else:
		for rel in MODELS:
			_compare(content, rel)
		_eq(content.load_texture("maps/MAYO04A/background_0.png") is CompressedTexture2D, true, "background from the mirror")

	print("%s: Content checks" % ("FAILED %d" % _failed if _failed else "OK"))
	quit(1 if _failed else 0)


## Every position / rotation / scale track of every animation, sampled at the 20 fps frames:
## the imported copy must play like the runtime-loaded file.
func _compare(content: Script, rel: String) -> void:
	var imported: Node3D = content.load_model(rel)
	var raw: Node3D = content._load_gltf(content.path(rel))
	var untextured := imported.find_children("*", "MeshInstance3D", true, false).filter(
		func(m): return m.get_surface_override_material(0) == null or m.get_surface_override_material(0).albedo_texture == null)
	_eq(untextured.size(), 0, rel + ": every imported mesh has its texture")
	var pa := _player(imported)
	var pb := _player(raw)
	_eq(pa.get_animation_list(), pb.get_animation_list(), rel + ": same animations")
	var worst := 0.0
	var where := ""
	for anim_name in pa.get_animation_list():
		var a: Animation = pa.get_animation(anim_name)
		var b: Animation = pb.get_animation(anim_name)
		for track in a.get_track_count():
			var type := a.track_get_type(track)
			if not type in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				continue
			var other := b.find_track(a.track_get_path(track), type)
			if other < 0:
				worst = INF
				where = "%s %s missing in the raw model" % [anim_name, a.track_get_path(track)]
				continue
			for frame in int(round(a.length * content.ANIMATION_FPS)) + 1:
				var time: float = frame / content.ANIMATION_FPS
				var va: Variant = _sample(a, track, type, time)
				var vb: Variant = _sample(b, other, type, time)
				var d: float = va.angle_to(vb) if type == Animation.TYPE_ROTATION_3D else va.distance_to(vb)
				if d > worst:
					worst = d
					where = "%s %s at %.2f s: %s vs %s" % [anim_name, a.track_get_path(track), time, va, vb]
	if worst > TOLERANCE:
		_failed += 1
		print("FAIL %s: imported differs from raw by %s (%s)" % [rel, worst, where])
	imported.free()
	raw.free()


static func _player(model: Node) -> AnimationPlayer:
	return model.find_children("*", "AnimationPlayer", true, false)[0]


static func _sample(anim: Animation, track: int, type: int, time: float) -> Variant:
	match type:
		Animation.TYPE_POSITION_3D:
			return anim.position_track_interpolate(track, time)
		Animation.TYPE_ROTATION_3D:
			return anim.rotation_track_interpolate(track, time)
	return anim.scale_track_interpolate(track, time)


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	if actual != expected:
		_failed += 1
		print("FAIL %s: %s != %s" % [what, actual, expected])
