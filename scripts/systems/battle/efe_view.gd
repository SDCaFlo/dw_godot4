class_name EfeView
extends Node3D
## The view of an original technique (specs/battle_effects.md §7.3): EfeEffect's draw sink, its
## `View` child (scenes/battle/effects/efe_view.tscn, so a mod can restyle the original techniques
## without touching their logic). Each render pass is one frame: begin_frame, the draw scripts'
## calls, end_frame; what a frame's scripts didn't draw is hidden.
##
## - drawTMD / drawTMDYXZ: one TMD object of the slot's model (the porter's model.gltf, mesh
##   `object_N`) at the instance's transform: RotMatrix / RotMatrixYXZ of its rotation, scaled by a
##   script vector (4096 = 1), culled as the C (view z < -300 or >= 0x10000). Its materials are
##   PsxLit, unlit, with the object's UV offset (its UV animation) and, on its 0x2D / 0x2F polygons
##   (the porter's "brightness_off" materials), the colour of setEFEModelObjectColor.
## - renderProjectedSprite / renderCenteredSprite: a GsSPRITE of the slot's texture at a world
##   point, in WorldSprites, sized and culled as the C.
## Not here yet (5d-5b): the screen-space sprites and quads, lines, wireframes, waves, ribbons, the
## ring tube, the overlay, the fade, the CLUT writes, drawTMDScreenSpace.

## The TMD culling of drawTMD (the view z of the object's origin).
const NEAR := -0x12C
const FAR := 0x10000
## GsSortSprite's OT range for the projected sprites.
const OT_MIN := 0x20
const OT_MAX := 0x1000
## The calls this view draws; the others are counted in `skipped` (the gallery shows them).
const DRAWN := ["drawTMD", "drawTMDYXZ", "renderProjectedSprite", "setEFEModelObjectColor"]

## True between begin_frame and end_frame.
var drawing := false
## Calls of kinds not drawn yet, by name (since the effect's load).
var skipped := {}

var _effect: EfeEffect
## Per TMD object: {mesh, materials [the PsxLit material per surface], tinted [bool per surface]}.
var _objects: Array[Dictionary] = []
var _pools: Array = []
var _used: Array[int] = []
var _sprites: WorldSprites
## The slot's TIM by palette (PsxTexture; null when the palette isn't there).
var _textures := {}
var _loaded := false


func _ready() -> void:
	_effect = get_parent() as EfeEffect
	_sprites = WorldSprites.new()
	_sprites.name = "Sprites"
	add_child(_sprites)


func begin_frame() -> void:
	if not _loaded:
		_load()
	drawing = true
	for i in _used.size():
		_used[i] = 0
	_sprites.begin()
	_update_materials()


func end_frame() -> void:
	drawing = false
	for i in _pools.size():
		var pool: Array = _pools[i]
		for k in range(_used[i], pool.size()):
			pool[k].visible = false
	_sprites.end()


## The number of nodes this frame shows (the tests, the gallery).
func shown() -> int:
	var n := _sprites.used()
	for u in _used:
		n += u
	return n


func draw_call(name: String, args: Array, instance: int) -> void:
	match name:
		"drawTMD":
			_draw_tmd(args, instance, false)
		"drawTMDYXZ":
			_draw_tmd(args, instance, true)
		"renderProjectedSprite":
			_draw_projected_sprite(args)
		"setEFEModelObjectColor":
			pass
		_:
			skipped[name] = int(skipped.get(name, 0)) + 1


# --- the model ----------------------------------------------------------------------------------

func _load() -> void:
	_loaded = true
	if _effect == null or _effect.folder == "":
		return
	var rel := "efe/%s/model.gltf" % _effect.folder
	if not Content.exists(rel):
		return
	var model := Content.load_model(rel)
	if model == null:
		return
	var extras := Content._material_extras(rel)
	for k in _effect.num_objects:
		var node := model.find_child("object_%d" % k, true, false) as MeshInstance3D
		var entry := {"mesh": null, "materials": [], "tinted": []}
		if node != null and node.mesh != null:
			entry["mesh"] = node.mesh
			for s in node.mesh.get_surface_count():
				var source := node.mesh.surface_get_material(s) as BaseMaterial3D
				var e: Dictionary = extras.get(source.resource_name, {}) if source != null else {}
				var abr := int(e.get("tpage", {}).get("abr", 0)) if e.get("semi_transparent", false) else -1
				var texture: Texture2D = source.albedo_texture if source != null else null
				entry["materials"].append(PsxLit.material(texture, bool(e.get("double_sided", false)), 0.5, abr,
						e.get("stp"), false))
				entry["tinted"].append(bool(e.get("brightness_off", false)))
		_objects.append(entry)
		_pools.append([])
		_used.append(0)
	# The meshes are kept; the loaded scene's nodes go, without their materials and meshes.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for s in node.get_surface_override_material_count():
			node.set_surface_override_material(s, null)
		node.mesh = null
	model.free()


## The objects' UV offsets and colours, every pass of every surface.
func _update_materials() -> void:
	for k in _objects.size():
		var anim: Dictionary = _effect.uv_anims[k] if k < _effect.uv_anims.size() else {}
		var offset := Vector2(int(anim.get("du", 0)), int(anim.get("dv", 0)))
		var color: Variant = _effect.object_colors.get(k)
		var entry: Dictionary = _objects[k]
		for s in entry["materials"].size():
			var tint := Vector3.ONE
			if color != null and entry["tinted"][s]:
				tint = Vector3(color.x & 0xFF, color.y & 0xFF, color.z & 0xFF) / 128.0
			var pass_material: Material = entry["materials"][s]
			while pass_material is ShaderMaterial:
				pass_material.set_shader_parameter("uv_offset", offset)
				pass_material.set_shader_parameter("tint", tint)
				pass_material = pass_material.next_pass


## drawTMD (battle_effect.c:4583) / drawTMDYXZ (:2774): object `args[0]` scaled by the vector at
## `args[1]`, at the instance's position and rotation.
func _draw_tmd(args: Array, instance: int, yxz: bool) -> void:
	var id: int = args[0]
	if id < 0 or id >= _objects.size() or _objects[id]["mesh"] == null:
		return
	var pos := _effect.read_vec(instance + EfeEffect.I_POS)
	var rot := _effect.read_vec(instance + EfeEffect.I_ROT)
	var m := PsxMath.rot_matrix_yxz(rot) if yxz else PsxMath.rot_matrix(rot)
	m = PsxMath.scale_matrix(m, _effect.read_vec(args[1]))
	var ctx := _effect.ctx
	if ctx != null:
		var ws := ctx.world_screen_matrix()
		var z := PsxMath.apply_matrix_lv(ws, pos).z + ws[11]
		if z < NEAR or z >= FAR:
			return
	var node := _take(id)
	node.transform = Transform3D(_godot_basis(m), Content.psx_to_godot([pos.x, pos.y, pos.z]))
	node.visible = true


func _take(id: int) -> MeshInstance3D:
	var pool: Array = _pools[id]
	if _used[id] == pool.size():
		var node := MeshInstance3D.new()
		node.mesh = _objects[id]["mesh"]
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var materials: Array = _objects[id]["materials"]
		for s in materials.size():
			node.set_surface_override_material(s, materials[s])
		add_child(node)
		pool.append(node)
	_used[id] += 1
	return pool[_used[id] - 1]


## A PSX matrix (4096 = 1, y and z down / forward) as a Godot basis: F · M · F with F the porter's
## flip (x, -y, -z), which the glTF's vertices already went through.
static func _godot_basis(m: PackedInt32Array) -> Basis:
	var f := [1.0, -1.0, -1.0]
	var cols: Array[Vector3] = []
	for j in 3:
		cols.append(Vector3(f[0] * m[0 * 3 + j] * f[j], f[1] * m[1 * 3 + j] * f[j], f[2] * m[2 * 3 + j] * f[j]) / 4096.0)
	return Basis(cols[0], cols[1], cols[2])


# --- the sprites --------------------------------------------------------------------------------

## BTL_renderProjectedSprite (battle_effect.c:4086). The arguments as pushed: position*, colour*,
## scale x, scale y, u, v, w, h, mx, my, rotate (degrees), attribute (>> 28), CLUT row offset.
func _draw_projected_sprite(args: Array) -> void:
	var ctx := _effect.ctx
	if ctx == null:
		return
	var texture := _texture(args[12])
	if texture == null:
		skipped["palette %d" % args[12]] = int(skipped.get("palette %d" % args[12], 0)) + 1
		return
	var attribute: int = args[11]
	# GsDOFF (bit 31): not drawn.
	if attribute & 8:
		return
	var pos := PsxMath.s16_vec(_effect.read_vec(args[0]))
	var screen := ctx.world_to_screen(pos)
	var sz: int = screen["sz"]
	if sz <= 0:
		return
	# RotTransPers' otz is SZ / 4; the sprite goes into the OT at (otz - 10) >> 2.
	var otz := sz >> 2
	if otz <= 0 or ((otz - 10) >> 2) < OT_MIN or ((otz - 10) >> 2) >= OT_MAX:
		return
	# The C's scale on screen (4096 = 1): (scale · H) << 5 / otz, an unsigned division; one screen
	# pixel at depth SZ is SZ / H world units.
	var h := ctx.viewport_distance()
	var sx := float(((args[2] * h) << 5) / otz) / 4096.0
	var sy := float(((args[3] * h) << 5) / otz) / 4096.0
	var world_per_pixel := float(sz) / h
	var w: int = args[6]
	var hh: int = args[7]
	var color := _effect.read_vec(args[1])
	var u: int = args[4] & 0xFF
	var v: int = args[5] & 0xFF
	var size := Vector2(w * sx, hh * sy) * world_per_pixel
	# The pivot (mx, my) sits on the point: the quad's centre is (w / 2 - mx, h / 2 - my) texels off.
	var offset := Vector2((w * 0.5 - args[8]) * sx, (hh * 0.5 - args[9]) * sy) * world_per_pixel
	var abr: int = attribute & 3 if attribute & 4 else -1
	_sprites.sprite(texture, abr, Content.psx_to_godot([pos.x, pos.y, pos.z]), size, Rect2(u, v, w, hh),
			Color((color.x & 0xFF) / 128.0, (color.y & 0xFF) / 128.0, (color.z & 0xFF) / 128.0), offset,
			deg_to_rad(float(args[10])))


func _texture(palette: int) -> PsxTexture:
	if not _textures.has(palette):
		var t: PsxTexture = null
		if _effect != null and _effect.folder != "" and palette >= 0:
			t = PsxTexture.load_palette("efe/%s/texture" % _effect.folder, palette)
		_textures[palette] = t
	return _textures[palette]
