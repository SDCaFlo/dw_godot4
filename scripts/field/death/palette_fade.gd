class_name PaletteFade
## The death scene's palette fades as a colour multiply (specs/death_scene.md §3 J, §4.9): the C
## scales an entity's CLUT tile by (end - level) / (end - start) (DOO2_fadeClut, doo2.c:372;
## DOOA_fadeModelClut / DOOA_fadeShardClut, dooa.c:1229–1303); the port sets PsxLit's `tint` on
## every pass of the entity's materials. A level: 255 black, 0 full colour.

const META := "palette_fade_source"


static func factor(level: int) -> float:
	return (255 - clampi(level, 0, 255)) / 255.0


## Tints every PsxLit pass under `entity` (copies of its materials, kept until clear()).
static func apply(entity: Node3D, f: float) -> void:
	if entity == null:
		return
	for node in entity.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var current := mi.get_surface_override_material(i)
			if current == null:
				continue
			if not current.has_meta(META):
				var copy := current.duplicate(true) as Material
				copy.set_meta(META, current)
				mi.set_surface_override_material(i, copy)
				current = copy
			var pass_material: Material = current
			while pass_material != null:
				if pass_material is ShaderMaterial:
					(pass_material as ShaderMaterial).set_shader_parameter("tint", Vector3(f, f, f))
				elif pass_material is BaseMaterial3D:
					(pass_material as BaseMaterial3D).albedo_color = Color(f, f, f, (pass_material as BaseMaterial3D).albedo_color.a)
				pass_material = pass_material.next_pass


## The entity's own materials back.
static func clear(entity: Node3D) -> void:
	if entity == null:
		return
	for node in entity.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		for i in mi.get_surface_override_material_count():
			var current := mi.get_surface_override_material(i)
			if current != null and current.has_meta(META):
				mi.set_surface_override_material(i, current.get_meta(META))
