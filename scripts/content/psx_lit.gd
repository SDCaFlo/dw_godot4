class_name PsxLit
## The PSX look of a TMD polygon's material (specs/lighting.md):
## - the field lighting of the lit polygons: the GTE lights each vertex with the map's 3 lights and
##   the ambient (GsSetFlatLight, GsSetAmbient), the colour is interpolated, and the GPU multiplies
##   the texel by it (128 = 1.0), clamped per channel. The lights are global shader parameters
##   (project.godot [shader_globals]), set by FieldLighting;
## - semi-transparency: a semi-transparent polygon blends only the texels whose colour has the STP
##   bit, with its tpage's abr mode (0 half / half, 1 add, 2 subtract, 3 add a quarter); the other
##   texels are opaque (asset_porter/specs/tmd.md "STP masks"). One pass each. The blend is the
##   PSX's, in its gamma values (shaders/common/psx_gamma_blend.gdshaderinc);
## - the battle effects' per-object state (specs/battle_effects.md §7.3): a UV offset added to the
##   byte UVs (BTL_offsetEFEPrimitiveUVs: each vertex's u / v wraps at 256, so the wrap is per
##   vertex, not per pixel), and a colour (setEFEModelObjectColor, 128 = 1.0).

## The tpage's semi-transparency modes (abr).
const HALF := 0
const ADD := 1
const SUBTRACT := 2
const ADD_QUARTER := 3

## The PSX blends in its own (gamma) colour values; Godot's 3D blends in linear light, where an
## added texel brightens a lit background far less (ISSUES.md I-30: the techniques looked almost
## invisible over the bright maps) and a halved one darkens it more. So a blended pass does the
## PSX's sum itself (res://shaders/common/psx_gamma_blend.gdshaderinc, shared with WorldSprites and
## like DropShadow's); `abr` is the shader's mode uniform.

## The shaders (res://shaders/psx_lit/, a mod may replace them): [blended pass][double-sided].
const _SHADERS := {
	false: {false: preload("res://shaders/psx_lit/opaque.gdshader"),
			true: preload("res://shaders/psx_lit/opaque_double.gdshader")},
	true: {false: preload("res://shaders/psx_lit/blended.gdshader"),
			true: preload("res://shaders/psx_lit/blended_double.gdshader")},
}


## The material for a glTF material's texture and modes. `abr` -1: not semi-transparent (or no STP
## mask: every texel opaque). `lit` false: the texel as is (an unlit semi-transparent polygon).
static func material(texture: Texture2D, double_sided: bool, alpha_cutoff := 0.5, abr := -1,
		stp_texture: Texture2D = null, lit := true) -> ShaderMaterial:
	var semi := abr >= 0 and stp_texture != null
	var base := _pass(false, double_sided, texture, alpha_cutoff, lit)
	if not semi:
		return base
	base.set_shader_parameter("use_stp", true)
	base.set_shader_parameter("stp_texture", stp_texture)
	var blended := _pass(true, double_sided, texture, alpha_cutoff, lit)
	blended.set_shader_parameter("use_stp", true)
	blended.set_shader_parameter("stp_texture", stp_texture)
	blended.set_shader_parameter("blended_pass", true)
	blended.set_shader_parameter("abr", abr & 3)
	base.next_pass = blended
	return base


## Lights a loaded model with its own light instead of the map's (`dir` the Godot direction the
## light travels, `color` 0-1, like FieldLighting's): copies of its PsxLit materials, every pass.
static func use_own_light(model: Node, dir: Vector3, color: Vector3) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		for i in mesh_instance.get_surface_override_material_count():
			var source := mesh_instance.get_active_material(i)
			if not source is ShaderMaterial:
				continue
			var copy := (source as ShaderMaterial).duplicate(true) as ShaderMaterial
			var pass_material: Material = copy
			while pass_material is ShaderMaterial:
				pass_material.set_shader_parameter("own_light", true)
				pass_material.set_shader_parameter("own_light_dir", dir)
				pass_material.set_shader_parameter("own_light_color", color)
				pass_material = pass_material.next_pass
			mesh_instance.set_surface_override_material(i, copy)


## A pass that blends every texel with the PSX's `abr` (a primitive drawn SetSemiTrans 1 with no
## STP mask: the death scene's streaks; specs/death_scene.md I6).
static func blended(texture: Texture2D, abr: int, double_sided := true, lit := false) -> ShaderMaterial:
	var m := _pass(true, double_sided, texture, 0.5, lit)
	m.set_shader_parameter("abr", abr & 3)
	return m


## Every polygon of a model made semi-transparent with `abr`, every texel blended (ENDI_setModelSemiTrans
## with ENDI_setClutStp: each non-black colour gets STP, black loses it and is transparent; with abr 1
## a black texel adds nothing, so one blended pass is the same; specs/map_events.md §4.4.2): each
## surface's PsxLit material replaced by one blended pass with its texture, sidedness and lighting.
static func semi_transparent(model: Node, abr: int) -> void:
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mi := node as MeshInstance3D
		if mi is DropShadow or mi.mesh == null:
			continue
		for i in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i) as ShaderMaterial
			if source == null:
				continue
			var double := source.shader == _SHADERS[false][true] or source.shader == _SHADERS[true][true]
			var tex: Texture2D = source.get_shader_parameter("albedo_texture")
			var m := blended(tex, abr, double, bool(source.get_shader_parameter("lit")))
			mi.set_surface_override_material(i, m)


## The opaque shaders without depth writes: [double-sided].
const _BACKDROP := {false: preload("res://shaders/psx_lit/opaque_backdrop.gdshader"),
		true: preload("res://shaders/psx_lit/opaque_double_backdrop.gdshader")}


## Makes a model a back object (a sub-OT drawn behind everything, the arena's STD_renderArena0 / 1:
## specs/arena.md §4.7): copies of its materials that write no depth, with `priority` (lower = drawn
## first in the opaque pass), every pass. What is drawn after it covers it, whatever the depths.
static func as_backdrop(model: Node, priority: int) -> void:
	var nodes: Array = [model] + model.find_children("*", "MeshInstance3D", true, false)
	for node in nodes:
		if not node is MeshInstance3D or node.mesh == null:
			continue
		var mi := node as MeshInstance3D
		for i in mi.mesh.get_surface_count():
			var source := mi.get_active_material(i)
			if source == null:
				continue
			var copy := source.duplicate(true) as Material
			var pass_material: Material = copy
			while pass_material != null:
				pass_material.render_priority = priority
				if pass_material is ShaderMaterial:
					var sm := pass_material as ShaderMaterial
					for double: bool in [false, true]:
						if sm.shader == _SHADERS[false][double]:
							sm.shader = _BACKDROP[double]
				elif pass_material is BaseMaterial3D:
					(pass_material as BaseMaterial3D).depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
				pass_material = pass_material.next_pass
			mi.set_surface_override_material(i, copy)


## A copy of a model's material drawn single-sided, every pass (renderWireframed and
## DOO2_renderWireframeModel cull each face with RotNclip, double-sided ones too: specs/death_scene.md
## A10). Another material: a copy with back faces culled.
static func single_sided(source: Material) -> Material:
	if source == null:
		return null
	var copy := source.duplicate(true) as Material
	var pass_material: Material = copy
	while pass_material != null:
		if pass_material is ShaderMaterial:
			var sm := pass_material as ShaderMaterial
			for blended: bool in _SHADERS:
				if sm.shader == _SHADERS[blended][true]:
					sm.shader = _SHADERS[blended][false]
		elif pass_material is BaseMaterial3D:
			(pass_material as BaseMaterial3D).cull_mode = BaseMaterial3D.CULL_BACK
		pass_material = pass_material.next_pass
	return copy


## One pass: opaque, or blended (the STP texels, with the PSX's blend in gamma values).
static func _pass(blended: bool, double_sided: bool, texture: Texture2D, alpha_cutoff: float, lit: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _SHADERS[blended][double_sided]
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("use_texture", texture != null)
	m.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	m.set_shader_parameter("lit", lit)
	return m
