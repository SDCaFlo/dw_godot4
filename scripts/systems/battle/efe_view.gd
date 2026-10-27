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
## - The screen primitives (renderScreenSprite, renderParticleFlashSprite, render2DTexturedQuad,
##   renderScrollingBackground, renderParallaxSprites, renderScreenOverlay, renderScreenFade): the
##   C places them in screen pixels relative to the drawing offset and sorts them into the ordering
##   table with the models at a given slot. They are drawn as screen-aligned quads in 3D at the view
##   depth of that slot (OT z = SZ >> 4, as the sprites' and flashes'), so the fade (slot 0xFFE)
##   darkens the map behind the fighters and the backdrops in front (0x1E) cover them, as on the PSX.
## - The world primitives: render3DTexturedQuad (a POLY_FT4 through addScreenPolyFT4), the radial
##   waves, the ribbon strip and the ring tube, drawn in 3D from the C's points; the lines and
##   wireframes (renderEFELine, renderWireframeBox / Grid), screen lines at their OT slot.
## - drawTMDScreenSpace: a TMD object placed in the camera's space (its position a view-space one).
## - The CLUT rows the scripts rewrite (EfeEffect.clut_rows): the sprites and model surfaces on such
##   a row get textures built from the slot's TIM (EfeTexture) in the row as it is now.

## The TMD culling of drawTMD (the view z of the object's origin).
const NEAR := -0x12C
const FAR := 0x10000
## GsSortSprite's OT range for the projected sprites.
const OT_MIN := 0x20
const OT_MAX := 0x1000
## The calls this view draws; the others are counted in `skipped` (the gallery shows them).
const DRAWN := ["drawTMD", "drawTMDYXZ", "renderProjectedSprite", "setEFEModelObjectColor", "renderScreenSprite",
		"renderParticleFlashSprite", "render2DTexturedQuad", "renderScrollingBackground", "renderParallaxSprites",
		"renderScreenOverlay", "renderScreenFade", "renderEFELine", "renderWireframeBox", "renderWireframeGrid",
		"render3DTexturedQuad", "renderRadialWaves", "renderRibbonStrip", "renderRingTube", "drawTMDScreenSpace",
		"loadClutColors", "addClutLoadPrim"]
## The CLUT row of effect texture place 0 (the porter's model pages): a surface's row is its CLUT y
## minus this.
const CLUT_Y := 488
## The view depth an OT slot stands for (SZ = z << 4), kept inside the camera's range.
const OT_DEPTH_MIN := 20.0
const OT_DEPTH_MAX := 90000.0
## renderScreenFade: SPOT256 (tpage 832,256 8bpp, image v = v - 0x80), CLUT (0, 487), u 0 v 0x80, 3 x 3,
## subtracted, at slot 0xFFE.
const FADE_TEXTURE := "etctim/07_spot256"
const FADE_OT := 0xFFE
## The backdrops' slot (renderScrollingBackground, renderParallaxSprites).
const BACKDROP_OT := 0x1E

## True between begin_frame and end_frame.
var drawing := false
## Calls of kinds not drawn yet, by name (since the effect's load).
var skipped := {}

var _effect: EfeEffect
## Per TMD object: {mesh, materials [the PsxLit material per surface], tinted [bool per surface],
## rows [the CLUT row per surface]}.
var _objects: Array[Dictionary] = []
var _pools: Array = []
var _used: Array[int] = []
var _sprites: WorldSprites
## The slot's TIM by palette (PsxTexture; null when the palette isn't there).
var _textures := {}
## Mirrored flash textures of renderParticleFlashSprite by [palette, u, v, w, h].
var _flashes := {}
var _fade: PsxTexture
var _loaded := false
## The clut_version the textures were built for.
var _clut_seen := 0
var _clut_textures := {}


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
		"setEFEModelObjectColor", "loadClutColors", "addClutLoadPrim":
			pass
		"drawTMDScreenSpace":
			_draw_tmd_screen_space(args, instance)
		"renderScreenSprite":
			_draw_screen_sprite(args)
		"renderParticleFlashSprite":
			_draw_particle_flash_sprite(args)
		"render2DTexturedQuad":
			_draw_2d_quad(args)
		"renderScrollingBackground":
			_draw_scrolling_background(args)
		"renderParallaxSprites":
			_draw_parallax_sprites(args)
		"renderScreenOverlay":
			_draw_screen_overlay(args)
		"renderScreenFade":
			_draw_screen_fade(args)
		"renderEFELine":
			_draw_line(args)
		"renderWireframeBox":
			_draw_wireframe_box(args, instance)
		"renderWireframeGrid":
			_draw_wireframe_grid(args)
		"render3DTexturedQuad":
			_draw_3d_quad(args)
		"renderRadialWaves":
			_draw_radial_waves(args, instance)
		"renderRibbonStrip":
			_draw_ribbon_strip(args, instance)
		"renderRingTube":
			_draw_ring_tube(args)
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
		var entry := {"mesh": null, "materials": [], "tinted": [], "rows": []}
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
				entry["rows"].append(int(e.get("clut", {}).get("y", CLUT_Y)) - CLUT_Y)
		_objects.append(entry)
		_pools.append([])
		_used.append(0)
	# The meshes are kept; the loaded scene's nodes go, without their materials and meshes.
	for node in model.find_children("*", "MeshInstance3D", true, false):
		for s in node.get_surface_override_material_count():
			node.set_surface_override_material(s, null)
		node.mesh = null
	model.free()


## The objects' UV offsets and colours, every pass of every surface; after a CLUT write, the
## textures of the surfaces on a rewritten row.
func _update_materials() -> void:
	if _effect.clut_version != _clut_seen:
		_clut_seen = _effect.clut_version
		_retexture()
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
	if _effect != null and _effect.clut_rows.has(palette):
		var key := [palette, _effect.clut_version]
		if not _clut_textures.has(key):
			var tim := _effect.tim()
			_clut_textures[key] = EfeTexture.sprite_texture(tim, _effect.clut_row(palette)) if not tim.is_empty() else null
		return _clut_textures[key]
	if not _textures.has(palette):
		var t: PsxTexture = null
		if _effect != null and _effect.folder != "" and palette >= 0:
			t = PsxTexture.load_palette("efe/%s/texture" % _effect.folder, palette)
		_textures[palette] = t
	return _textures[palette]


# --- the screen primitives ----------------------------------------------------------------------

func _ot_depth(z: int) -> float:
	return clampf(float(z << 4), OT_DEPTH_MIN, OT_DEPTH_MAX)


## A screen rectangle (pixels relative to the drawing offset) at an OT slot.
func _screen_rect(texture: PsxTexture, abr: int, rect: Rect2, z: int, region: Rect2, tint := Color.WHITE) -> void:
	_screen_quad(texture, abr, [rect.position, Vector2(rect.end.x, rect.position.y), Vector2(rect.position.x, rect.end.y),
			rect.end], z, region, tint)


## A screen quad (its four corners: top-left, top-right, bottom-left, bottom-right) at an OT slot.
func _screen_quad(texture: PsxTexture, abr: int, corners: Array, z: int, region: Rect2, tint := Color.WHITE) -> void:
	var ctx := _effect.ctx
	if ctx == null:
		return
	var depth := _ot_depth(z)
	var world := []
	for c in corners:
		world.append(ctx.screen_to_world(c, depth))
	_sprites.quad(texture, abr, world, region, tint)


func _color(address: int) -> Color:
	var c := _effect.read_vec(address)
	return Color((c.x & 0xFF) / 128.0, (c.y & 0xFF) / 128.0, (c.z & 0xFF) / 128.0)


## BTL_renderScreenSprite (battle_effect.c:4192). Pushed: x, y, u, v, w, h, mx, my, rotate (degrees),
## OT slot, scale x, scale y, flip. A negative flip puts the sprite relative to the screen's centre
## (the drawing offset taken back) and is the CLUT row's offset negated; the sprite is added (abr 1).
func _draw_screen_sprite(args: Array) -> void:
	var z: int = args[9]
	if z < 0 or z >= 0x1000:
		return
	var flip: int = args[12]
	var at := Vector2(args[0], args[1])
	if flip < 0:
		var ofs := _effect.ctx.drawing_offset() if _effect.ctx != null else Vector2i(160, 120)
		at += Vector2(0xA0 - ofs.x, 0x78 - ofs.y)
	var texture := _texture(-flip if flip < 0 else flip)
	if texture == null:
		return
	_gs_sprite(texture, PsxLit.ADD, at, args[2], args[3], args[4], args[5], args[6], args[7], args[8], args[10], args[11],
			z, Color.WHITE)


## A GsSPRITE on the screen: texel (mx, my) on `at`, w x h texels scaled (4096 = 1), turned about it
## (clockwise on screen, as the projected sprites).
func _gs_sprite(texture: PsxTexture, abr: int, at: Vector2, u: int, v: int, w: int, h: int, mx: int, my: int,
		rotate: int, scale_x: int, scale_y: int, z: int, tint: Color) -> void:
	var sx := scale_x / 4096.0
	var sy := scale_y / 4096.0
	var angle := deg_to_rad(float(rotate))
	var corners := []
	for c in [Vector2(0, 0), Vector2(w, 0), Vector2(0, h), Vector2(w, h)]:
		var d := Vector2((c.x - mx) * sx, (c.y - my) * sy)
		corners.append(at + Vector2(d.x * cos(angle) - d.y * sin(angle), d.x * sin(angle) + d.y * cos(angle)))
	_screen_quad(texture, abr, corners, z, Rect2(u & 0xFF, v & 0xFF, w, h), tint)


## BTL_renderParticleFlashSprite (battle_effect.c:4142) -> renderParticleFlash: the region (u, v,
## w, h) of the slot's texture, palette n, mirrored around the point, half size (scale · (w - 1)
## >> 10) + 1 pixels, added. Pushed: x, y, u, v, w, h, scale, OT slot, palette.
func _draw_particle_flash_sprite(args: Array) -> void:
	var z: int = args[7]
	if z < 0x21 or z >= 0x1000:
		return
	var w: int = args[4] & 0xFF
	var h: int = args[5] & 0xFF
	var key := [args[8], args[2], args[3], w, h]
	if not _flashes.has(key):
		var t := _texture(args[8])
		if t != null:
			var mirrored := PsxTexture.new()
			mirrored.base = ParticleFX.mirrored(t.base, Rect2(args[2], args[3], w, h))
			mirrored.stp = ParticleFX.mirrored(t.stp, Rect2(args[2], args[3], w, h))
			t = mirrored
		_flashes[key] = t
	var texture: PsxTexture = _flashes[key]
	if texture == null:
		return
	var scale := PsxMath.s16(args[6])
	var half_x := (scale * ((w - 1) & 0xFF)) >> 10
	var half_y := (scale * ((h - 1) & 0xFF)) >> 10
	if half_x <= 0 or half_y <= 0:
		return
	var at := Vector2(args[0], args[1])
	var half := Vector2(half_x + 1, half_y + 1)
	_screen_rect(texture, PsxLit.ADD, Rect2(at - half, half * 2), z, Rect2(0, 0, 2 * w, 2 * h))


## BTL_render2DTexturedQuad (battle_effect.c:3130). Pushed: a, b, c, d, OT slot, colour*, u, v, du,
## dv, CLUT row, semi. A negative `semi` makes a..d pointers to the four corners (int32 x, y); else
## they are x, y, w, h. `semi` is tpage bits: abr (semi >> 5) & 3, semi-transparent when non-zero.
func _draw_2d_quad(args: Array) -> void:
	var z: int = args[4]
	if z <= 0x20 or z >= 0x1000:
		return
	var semi: int = args[11]
	var corners := []
	if semi < 0:
		semi = -semi & 0xFFFF
		for k in 4:
			corners.append(Vector2(_effect.read(args[k], 4), _effect.read(args[k] + 4, 4)))
	else:
		var r := Rect2(args[0], args[1], args[2], args[3])
		corners = [r.position, Vector2(r.end.x, r.position.y), Vector2(r.position.x, r.end.y), r.end]
	var texture := _texture(args[10])
	if texture == null:
		return
	_screen_quad(texture, (semi >> 5) & 3 if semi != 0 else -1, corners, z,
			Rect2(args[6] & 0xFF, args[7] & 0xFF, args[8], args[9]), _color(args[5]))


## BTL_renderScrollingBackground (battle_effect.c:3917): 11 x 9 tiles of 32 pixels scrolled by
## (sx, sy), each tile's u from pal[tiles[...]], added, at slot 0x1E. Pushed: tiles*, pal*, sx, sy,
## colour.
func _draw_scrolling_background(args: Array) -> void:
	var texture := _texture(0)
	if texture == null:
		return
	var sx: int = PsxMath.mod(args[2], 0x140)
	var tx := PsxMath.mod(sx >> 5, 11)
	if sx < 0:
		sx += 0x140
		tx += 10
	var sy: int = PsxMath.mod(args[3], 0x100)
	var ty := PsxMath.mod(sy >> 5, 9)
	if sy < 0:
		sy += 0x100
		ty += 8
	var c: float = (args[4] & 0xFF) / 128.0
	var y0 := (sy & 0x1F) - 0x98
	for row in 9:
		var x0 := (sx & 0x1F) - 0xC0
		var uy := ((ty + row) % 9) * 11
		for col in 11:
			var ux := (tx + col) % 11
			var tile := _effect.read(args[0] + uy + ux, 1) & 0xFF
			var u := _effect.read(args[1] + tile * 2, 2)
			_screen_rect(texture, PsxLit.ADD, Rect2(x0, y0, 0x20, 0x20), BACKDROP_OT, Rect2(u & 0xFF, 0, 0x1F, 0x1F),
					Color(c, c, c))
			x0 += 0x20
		y0 += 0x20


## BTL_renderParallaxSprites (battle_effect.c:3869): EfeParallaxSprite {size, x, y, depth, u} (int16)
## until a negative size, each moved by (ox, oy) times its depth, wrapped as the C wraps it,
## opaque, palette 1, at slot 0x1E. Pushed: list*, ox, oy.
func _draw_parallax_sprites(args: Array) -> void:
	var texture := _texture(1)
	if texture == null:
		return
	var p: int = args[0]
	for n in 64:
		var size := _effect.read(p, 2)
		if size < 0:
			break
		var depth := _effect.read(p + 6, 2)
		var x := PsxMath.s16((depth * (_effect.read(p + 2, 2) + args[1])) >> 7)
		var y := PsxMath.s16((depth * (_effect.read(p + 4, 2) + args[2])) >> 7)
		x = PsxMath.mod(x, 400)
		y = PsxMath.mod(y, 320)
		if x < 0:
			x += 360
		if y < 0:
			y += 280
		x -= 0xC8
		y -= 0xA0
		var sz := PsxMath.s16((size * depth) >> 8)
		_screen_rect(texture, -1, Rect2(x, y, sz, sz), BACKDROP_OT, Rect2(_effect.read(p + 8, 2) & 0xFF, 0, 0x1F, 0x1F))
		p += 10


## BTL_renderScreenOverlay (battle_effect.c:2434): the 320 x 240 screen in a flat colour at an OT
## slot; `mode` bit 2 semi-transparent, bits 0-1 the abr. Pushed: slot, colour*, mode.
func _draw_screen_overlay(args: Array) -> void:
	var mode: int = args[2]
	var semi := (mode >> 2) & 1 == 1
	_screen_rect(WorldSprites.solid(semi), mode & 3 if semi else -1, Rect2(-0xA0, -0x78, 320, 240), args[0],
			Rect2(0, 0, 1, 1), _color(args[1]))


## BTL_renderScreenFade (battle_effect.c:2239): the whole screen darkened by `c` (SPOT256's corner
## texels, subtracted) at slot 0xFFE, behind the fighters. Pushed: c.
func _draw_screen_fade(args: Array) -> void:
	if _fade == null:
		_fade = PsxTexture.load_palette(FADE_TEXTURE, 0)
	if _fade == null or _effect.ctx == null:
		return
	var ofs := _effect.ctx.drawing_offset()
	var c: float = (args[0] & 0xFF) / 128.0
	_screen_rect(_fade, PsxLit.SUBTRACT, Rect2(-ofs.x, -ofs.y, 320, 240), FADE_OT, Rect2(0, 0, 3, 3), Color(c, c, c))


# --- the world primitives -----------------------------------------------------------------------

## BTL_LINE_OFFSET_X / Y, BTL_WIREFRAME_BOX_SIGN_X / Y / Z, BTL_WIREFRAME_BOX_LINES (4 polylines of 4
## corners), BTL_RADIAL_WAVE_UVS (3 sets of 4 (u, v)), BTL_RIBBON_UVS, BTL_RIBBON_COLORS.
const LINE_OFFSET_X := [1, 0, -1, 0]
const LINE_OFFSET_Y := [0, 1, 0, -1]
const BOX_SIGN_X := [-1, 1, 1, -1, -1, 1, 1, -1]
const BOX_SIGN_Y := [-1, -1, 1, 1, -1, -1, 1, 1]
const BOX_SIGN_Z := [-1, -1, -1, -1, 1, 1, 1, 1]
const BOX_LINES := [0, 1, 2, 3, 5, 4, 7, 6, 1, 5, 6, 2, 4, 0, 3, 7]
const BOX_OT := 0x22
const GRID_OT := 0xFFD
const WAVE_UVS := [[Vector2(7, 0x10), Vector2(7, 0x1F), Vector2(0, 0x10), Vector2(0, 0x1F)],
		[Vector2(8, 0), Vector2(8, 0xF), Vector2(0x17, 0), Vector2(0x17, 0xF)],
		[Vector2(0x17, 0), Vector2(0x17, 0xF), Vector2(8, 0), Vector2(8, 0xF)]]
const RIBBON_UVS := [Vector2(104, 0), Vector2(135, 0), Vector2(104, 31), Vector2(135, 31)]
const RIBBON_COLORS := [Vector3i(0x7C, 0x7C, 0x7C), Vector3i(0, 0x7C, 0x7C), Vector3i(0x3C, 0x7C, 0x3C)]


static func _godot(psx: Vector3i) -> Vector3:
	return Content.psx_to_godot([psx.x, psx.y, psx.z])


## worldPosToScreenPos: the screen position (relative to the drawing offset) and SZ of a PSX point.
func _project(psx: Vector3i) -> Dictionary:
	return _effect.ctx.world_to_screen(PsxMath.s16_vec(psx))


## The wireframes' screen shift: (0xA0, 0x78) minus the drawing offset (the C assumes the
## projection centre at the screen's centre).
func _centre_shift() -> Vector2:
	var ofs := _effect.ctx.drawing_offset()
	return Vector2(0xA0 - ofs.x, 0x78 - ofs.y)


## A screen line (pixels relative to the drawing offset) at an OT slot.
func _screen_line(a: Vector2, b: Vector2, z: int, color: Color, abr := -1) -> void:
	var depth := _ot_depth(z)
	_sprites.line(_effect.ctx.screen_to_world(a, depth), _effect.ctx.screen_to_world(b, depth), color, abr)


static func _rgb(c: Vector3i, percent := 100) -> Color:
	return Color8(((c.x * percent / 100) & 0xFF), ((c.y * percent / 100) & 0xFF), ((c.z * percent / 100) & 0xFF))


## BTL_renderEFELine (battle_effect.c:3269): drawLine2P between two screen points. Flag 0x20: four
## lines one pixel around, half the colour, added (mode 5). Pushed: x0, y0, x1, y1, colour*, OT
## slot, flags.
func _draw_line(args: Array) -> void:
	var z: int = args[5]
	if z <= 0x20 or z >= 0x1000 or _effect.ctx == null:
		return
	var c := _effect.read_vec(args[4])
	var a := Vector2(args[0], args[1])
	var b := Vector2(args[2], args[3])
	if args[6] & 0x20:
		for i in 4:
			var d := Vector2(LINE_OFFSET_X[i], LINE_OFFSET_Y[i])
			_screen_line(a + d, b + d, z, _rgb(c, 50), PsxLit.ADD)
	else:
		_screen_line(a, b, z, _rgb(c))


## BTL_renderWireframeBox (battle_effect.c:2978): a box of half extents ext* around base*, turned by
## the instance's rotation (RotMatrixZYX), its 8 corners projected and drawn as 4 polylines at slot
## 0x22. Pushed: base*, ext*, colour*.
func _draw_wireframe_box(args: Array, instance: int) -> void:
	if _effect.ctx == null:
		return
	var m := PsxMath.rot_matrix_zyx(PsxMath.s16_vec(_effect.read_vec(instance + EfeEffect.I_ROT)))
	var ext := PsxMath.s16_vec(_effect.read_vec(args[1]))
	var base := PsxMath.s16_vec(_effect.read_vec(args[0]))
	var shift := _centre_shift()
	var pts: Array[Vector2] = []
	for i in 8:
		var p := PsxMath.apply_matrix_sv(m, Vector3i(ext.x * BOX_SIGN_X[i], ext.y * BOX_SIGN_Y[i], ext.z * BOX_SIGN_Z[i]))
		pts.append(Vector2(_project(PsxMath.s16_vec(p + base))["screen"]) + shift)
	var color := _rgb(_effect.read_vec(args[2]))
	for k in 4:
		for s in 3:
			_screen_line(pts[BOX_LINES[k * 4 + s]], pts[BOX_LINES[k * 4 + s + 1]], BOX_OT, color)


## BTL_renderWireframeGrid (battle_effect.c:3063) + BTL_renderParallelLines (:5165): two sets of
## parallel lines on a turned plane, behind everything (slot 0xFFD). Pushed: base*, rotation*,
## colour* (3 int32), x1, x2, n1, z1, z2, n2, y.
func _draw_wireframe_grid(args: Array) -> void:
	if _effect.ctx == null:
		return
	var m := PsxMath.rot_matrix_zyx(PsxMath.s16_vec(_effect.read_vec(args[1])))
	var y: int = args[9]
	var p0 := PsxMath.apply_matrix_sv(m, Vector3i(args[3], y, args[6]))
	var p1 := PsxMath.apply_matrix_sv(m, Vector3i(args[4], y, args[6]))
	var p2 := PsxMath.apply_matrix_sv(m, Vector3i(args[3], y, args[7]))
	var base := _effect.read_vec(args[0])
	var color := _rgb(_effect.read_vec(args[2]))
	var c0 := PsxMath.s16_vec(base + p0)
	_parallel_lines(c0, PsxMath.s16_vec(base + p2), PsxMath.s16(args[5]), p0, p1, color)
	_parallel_lines(PsxMath.s16_vec(base + p0), PsxMath.s16_vec(base + p1), PsxMath.s16(args[8]), p0, p2, color)


func _parallel_lines(a: Vector3i, b: Vector3i, n: int, from: Vector3i, to: Vector3i, color: Color) -> void:
	if n <= 0:
		return
	var d := PsxMath.s16_vec(Vector3i(PsxMath.div(to.x - from.x, n), PsxMath.div(to.y - from.y, n),
			PsxMath.div(to.z - from.z, n)))
	var shift := _centre_shift()
	for i in n + 1:
		var pa := _project(a)
		if pa["sz"] > 0x200 and pa["sz"] < 0x10000:
			var pb := _project(b)
			if pb["sz"] > 0x200 and pb["sz"] < 0x10000:
				_screen_line(Vector2(pa["screen"]) + shift, Vector2(pb["screen"]) + shift, GRID_OT, color)
		a = PsxMath.s16_vec(a + d)
		b = PsxMath.s16_vec(b + d)


## BTL_render3DTexturedQuad (battle_effect.c:2902) -> addScreenPolyFT4: four world corners, culled at
## OT (SZ / 16) 0x21-0xFFF. Pushed: p1*, p2*, p3*, p4*, colour*, u, v, du, dv, CLUT row, semi.
func _draw_3d_quad(args: Array) -> void:
	if _effect.ctx == null:
		return
	var corners := []
	var sz := 0
	for k in 4:
		var p := PsxMath.s16_vec(_effect.read_vec(args[k]))
		sz += int(_project(p)["sz"])
		corners.append(_godot(p))
	var ot := (sz / 4) >> 4
	if ot <= 0x20 or ot >= 0x1000:
		return
	var texture := _texture(args[9])
	if texture == null:
		return
	var semi: int = args[10]
	_sprites.quad(texture, (semi >> 5) & 3 if semi != 0 else -1, corners, Rect2(args[5] & 0xFF, args[6] & 0xFF, args[7],
			args[8]), _color(args[4]))


## BTL_interpolateClamped (battle_effect.c:5205).
static func _interpolate_clamped(lo: int, hi: int, t: int, start: int, end: int) -> int:
	if hi < lo:
		var tmp := lo
		lo = hi
		hi = tmp
	t = clampi(t, lo, hi)
	if lo >= t:
		return start
	return start + PsxMath.div((end - start) * (t - lo), hi - lo)


## The instance's matrix as drawTMDYXZ builds it (RotMatrixYXZ, ScaleMatrix), with `yaw` added.
func _instance_matrix(instance: int, scale: Vector3i, yaw := 0) -> PackedInt32Array:
	var rot := _effect.read_vec(instance + EfeEffect.I_ROT)
	rot.y += yaw
	var m := PsxMath.scale_matrix(PsxMath.rot_matrix_yxz(rot), scale)
	return PsxMath.trans_matrix(m, _effect.read_vec(instance + EfeEffect.I_POS))


## A local point through an instance matrix, as a Godot point; `behind` set when it falls behind the
## camera (RotTransPers4's error flag).
func _through(m: PackedInt32Array, local: Vector3i) -> Vector3i:
	return PsxMath.apply_matrix_lv(m, PsxMath.s16_vec(local)) + PsxMath.translation(m)


func _visible(points: Array) -> bool:
	for p in points:
		if int(_project(p)["sz"]) <= 0:
			return false
	return true


## BTL_renderRadialWaves (battle_effect.c:2600): 6 rings of quads turned 0x2AA apart, from radius
## 0xC8 out to 0xBB8, their height a travelling sine wave; palette 1, added. Pushed: scale*.
func _draw_radial_waves(args: Array, instance: int) -> void:
	if _effect.ctx == null:
		return
	var texture := _texture(1)
	if texture == null:
		return
	var scale := _effect.read_vec(args[0])
	var phase := _effect.frame_of(instance) * -400
	var prev := Vector3i.ZERO
	for ring in 6:
		var m := _instance_matrix(instance, scale, 0x2AA * (ring + 1))
		var radius := 0xC8
		while radius < 0xBB8:
			var height: int
			if radius < 0x2EF:
				height = _interpolate_clamped(0xC8, 0x2EE, radius, 0xC8, 0xFA)
			elif radius < 0x8CB:
				height = _interpolate_clamped(0x2EE, 0x8CA, radius, 0xFA, 0x7D)
			else:
				height = _interpolate_clamped(0x8CA, 0xBB8, radius, 0x7D, 0xA)
			var angle := phase + radius * 4 + ring * 0x309
			height = ((height * PsxMath.rsin(angle)) >> 12) - height - 0xC8
			var half := radius / 5
			if radius != 0xC8:
				var points := [_through(m, Vector3i(-half, height, radius)), _through(m, Vector3i(half, height, radius)),
						_through(m, Vector3i(-prev.x, prev.y, prev.z)), _through(m, Vector3i(prev.x, prev.y, prev.z))]
				if _visible(points):
					var uv: Array = WAVE_UVS[1] if radius == 0x12C else (WAVE_UVS[2] if radius >= 0xB54 else WAVE_UVS[0])
					_sprites.quad(texture, PsxLit.ADD, points.map(_godot), Rect2(), Color.WHITE, uv)
			prev = Vector3i(half, height, radius)
			radius += 0x64


## BTL_renderRibbonStrip (battle_effect.c:5225): 9 gouraud quads between 10 points (each a vertical
## edge 0x1F4 up and 0xC8 down), their colour cycling through BTL_RIBBON_COLORS every 10 frames and
## fading in and out, the ends black; palette 2, added. Pushed: points* (SVECTORs), scale*, width.
func _draw_ribbon_strip(args: Array, instance: int) -> void:
	if _effect.ctx == null:
		return
	var texture := _texture(2)
	if texture == null:
		return
	var frame := _effect.frame_of(instance)
	var k := absi(frame / 10) % 3
	var lo: Vector3i = RIBBON_COLORS[k]
	var hi: Vector3i = RIBBON_COLORS[(k + 1) % 3]
	var c := Vector3i(_interpolate_clamped(0, 10, frame % 10, lo.x, hi.x), _interpolate_clamped(0, 10, frame % 10, lo.y, hi.y),
			_interpolate_clamped(0, 10, frame % 10, lo.z, hi.z))
	var fade := _interpolate_clamped(1, 7, frame, 0, 0x1000) if frame < 0xF else _interpolate_clamped(0x17, 0x1E, frame, 0x1000, 0)
	c = Vector3i((c.x * fade) >> 12, (c.y * fade) >> 12, (c.z * fade) >> 12)
	var full := Color((c.x & 0xFF) / 128.0, (c.y & 0xFF) / 128.0, (c.z & 0xFF) / 128.0)
	var half := Color(((c.x >> 1) & 0xFF) / 128.0, ((c.y >> 1) & 0xFF) / 128.0, ((c.z >> 1) & 0xFF) / 128.0)
	var m := _instance_matrix(instance, _effect.read_vec(args[1]))
	var top: Array[Vector3i] = []
	var bottom: Array[Vector3i] = []
	for i in 10:
		var at: int = args[0] + i * 8
		var p := Vector3i(_effect.read(at, 2), _effect.read(at + 2, 2), _effect.read(at + 4, 2))
		top.append(_through(m, p + Vector3i(0, -0x1F4, 0)))
		bottom.append(_through(m, p + Vector3i(0, 0xC8, 0)))
	for i in range(1, 10):
		var points := [top[i - 1], top[i], bottom[i - 1], bottom[i]]
		if not _visible(points):
			continue
		var left := [Color.BLACK, Color.BLACK] if i == 1 else [half, full]
		var right := [Color.BLACK, Color.BLACK] if i == 9 else [half, full]
		_sprites.quad(texture, PsxLit.ADD, points.map(_godot), Rect2(), Color.WHITE, RIBBON_UVS,
				[left[0], right[0], left[1], right[1]])


## BTL_renderRingTube (battle_effect.c:2461): n rings of 10 points (radius[i], heights[i] around
## centre*), quads between neighbouring rings, each culled unless its 4 corners are at OT 0x21-0xFFF;
## their u alternates by ring (0 / 24), grey colours[i], palette 0, added. Pushed: centre*, n,
## radius*, heights*, colours*, start.
func _draw_ring_tube(args: Array) -> void:
	var n: int = args[1]
	if n < 2 or _effect.ctx == null:
		return
	var texture := _texture(0)
	if texture == null:
		return
	var centre := _effect.read_vec(args[0])
	var rings := []
	for i in n:
		var r := _effect.read(args[2] + i * 4, 4)
		var ring := []
		for j in 10:
			var ang := j * 0x200 / 10
			var p := PsxMath.s16_vec(Vector3i(centre.x + ((r * PsxMath.cos512(0x80 - ang)) >> 12),
					centre.y + _effect.read(args[3] + i * 4, 4), centre.z + ((r * PsxMath.sin512(0x80 - ang)) >> 12)))
			var z := int(_project(p)["sz"]) >> 4
			ring.append([p, z if z >= 0x21 and z < 0x1000 else -1])
		rings.append(ring)
	for i in n - 1:
		var grey := (_effect.read(args[4] + i * 4, 4) & 0xFF) / 128.0
		var u: int = ((i + args[5]) & 1) * 24
		for j in 10:
			var k := (j + 1) % 10
			var corners := [rings[i + 1][k], rings[i][k], rings[i + 1][j], rings[i][j]]
			var culled := false
			for c in corners:
				culled = culled or c[1] < 0
			if culled:
				continue
			_sprites.quad(texture, PsxLit.ADD, corners.map(func(c): return _godot(c[0])), Rect2(u, 0, 0x17, 0x1F),
					Color(grey, grey, grey))


# --- the CLUT writes and the screen-space model ---------------------------------------------------

## The model surfaces on a rewritten CLUT row get the slot's TIM in that row, on a texture page.
func _retexture() -> void:
	var tim := _effect.tim()
	if tim.is_empty():
		return
	var pages := {}
	for entry in _objects:
		for s in entry["materials"].size():
			var row: int = entry["rows"][s]
			if not _effect.clut_rows.has(row):
				continue
			if not pages.has(row):
				pages[row] = EfeTexture.page_textures(tim, _effect.clut_row(row))
			var pass_material: Material = entry["materials"][s]
			while pass_material is ShaderMaterial:
				pass_material.set_shader_parameter("albedo_texture", pages[row][0])
				pass_material.set_shader_parameter("stp_texture", pages[row][1])
				pass_material = pass_material.next_pass


## BTL_drawTMDScreenSpace (battle_effect.c:2722): object `args[0]`, RotMatrixYXZ of the instance's
## rotation scaled by args[1]*, its position a view-space one moved by (0xA0, 0x78) minus the drawing
## offset: the model hangs in the camera's space (GsSetLsMatrix with that matrix), whatever the
## camera looks at.
func _draw_tmd_screen_space(args: Array, instance: int) -> void:
	var id: int = args[0]
	if id < 0 or id >= _objects.size() or _objects[id]["mesh"] == null or _effect.ctx == null:
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return
	var m := PsxMath.scale_matrix(PsxMath.rot_matrix_yxz(_effect.read_vec(instance + EfeEffect.I_ROT)),
			_effect.read_vec(args[1]))
	var ofs := _effect.ctx.drawing_offset()
	var t := _effect.read_vec(instance + EfeEffect.I_POS) + Vector3i(0xA0 - ofs.x, 0x78 - ofs.y, 0)
	var node := _take(id)
	node.global_transform = camera.global_transform * Transform3D(_godot_basis(m), Vector3(t.x, -t.y, -t.z))
	node.visible = true
