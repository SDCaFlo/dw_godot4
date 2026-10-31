class_name PsxUiFilter
## The upscaling filter of the text and windows (ISSUES.md D-3), not part of the original: the PSX
## bitmaps (the font, the boxes, the HUD) are drawn at the window's resolution, so like an
## emulator's 2D filter a shader rebuilds each texel's sub-pixels from its neighbours: Scale4x
## (Scale2x / EPX applied twice), which keeps the art's exact colours and rounds the stair-steps of
## its edges. Off, the texels are drawn as square blocks (the PSX's pixels).
##
## It runs in each UI node's own drawing (CanvasItem materials), so the PSX blend modes of the
## boxes and bubbles keep blending with the scene under them. The global shader parameter
## `psx_ui_filter` (project.godot [shader_globals]) turns it on and off for every node at once:
## `set_enabled`, the debugger's Render tab (later the CONFIG menu, ISSUES.md D-2).

## The shaders by CanvasItemMaterial.BLEND_MODE_* name (res://shaders/ui_filter/, a mod may
## replace them).
const _SHADERS := {
	"mix": preload("res://shaders/ui_filter/mix.gdshader"),
	"add": preload("res://shaders/ui_filter/add.gdshader"),
	"sub": preload("res://shaders/ui_filter/sub.gdshader"),
}

static var _materials := {}


## The shared material for a blend mode ("mix", "add", "sub").
static func material(blend := "mix") -> ShaderMaterial:
	if not _materials.has(blend):
		var m := ShaderMaterial.new()
		m.shader = _SHADERS[blend]
		_materials[blend] = m
	return _materials[blend]


## Turns the filter on or off everywhere.
static func set_enabled(on: bool) -> void:
	RenderingServer.global_shader_parameter_set("psx_ui_filter", on)
