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


## One pass: opaque, or blended (the STP texels, with the PSX's blend in gamma values).
static func _pass(blended: bool, double_sided: bool, texture: Texture2D, alpha_cutoff: float, lit: bool) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _SHADERS[blended][double_sided]
	m.set_shader_parameter("albedo_texture", texture)
	m.set_shader_parameter("use_texture", texture != null)
	m.set_shader_parameter("alpha_cutoff", alpha_cutoff)
	m.set_shader_parameter("lit", lit)
	return m
