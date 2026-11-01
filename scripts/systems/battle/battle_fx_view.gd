class_name BattleFxView
extends Node3D
## The battle's shared effects drawn in 3D (specs/battle_effects.md §7.3): the BattleFx of an
## EffectHost's context and the host's 4 particle emitters, each as its C renders it:
## - the hit sparks (renderParticleFX, efe.c:536): on the burst's third frame its flashes
##   (renderParticleFlash: the SPOT256 quarter mirrored four ways), then its DEFEFF particles
##   fading out (renderFXParticle);
## - the entity particles (renderEntityParticleFX, efe.c:658): a DEFEFF sprite on a bone;
## - the dust clouds (renderCloudFX, efe.c:745), as CloudFX;
## - the flashes (renderEFEFlash, efe.c:898): growing and fading, added or subtracted;
## - the emitters (BTL_renderParticleEmitters, battle_effect.c:1958): streaks or dots.
## Its scene is scenes/battle/effects/battle_fx_view.tscn; the battle host (and the debugger's
## gallery) add it to the world and call draw_frame once per game frame.

## renderParticleFlash's sprite: SPOT256 (etctim/07_spot256: tpage 832,256 8bpp, image v = v - 0x80),
## CLUT (0, 487) = palette 0, 64 x 64 quarters: u 0x40 (MAIN_D_8013421C's 0x40) or u 0.
const SPOT_TEXTURE := "etctim/07_spot256"
const FLASH_SIZE := 0x40
## DEFEFF (etctim/02_defeff on tpage 768,256: image v = v - 0x80): palettes 0 (clouds, CLUT 192,488),
## 1 (renderFXParticle, 192,489), 2 (the entity particles, 192,490).
const DEFEFF := "etctim/02_defeff"
const FX_PARTICLE_REGION := Rect2(0, 32, 15, 15)
const FX_PARTICLE_SIZE := 0x28
const EMITTER_PARTICLE_SIZE := 0x19
## ENTITY_PARTICLE_FX_MODES: width, height, baseU, baseV, spanU, spanV.
const ENTITY_SPRITES := [[0x78, 0x50, 0x80, 0x80, 0x0F, 0x0F], [0x78, 0x50, 0xC0, 0x80, 0x0F, 0x0F],
		[0xC8, 0x50, 0x80, 0x90, 0x1F, 0x07], [0xC8, 0x96, 0x80, 0x80, 0x0F, 0x0F], [0xC8, 0x96, 0xC0, 0x80, 0x0F, 0x0F],
		[0xFA, 0x64, 0x80, 0x90, 0x1F, 0x07], [0x64, 0x64, 0x80, 0x80, 0x0F, 0x0F], [0x64, 0x64, 0xC0, 0x80, 0x0F, 0x0F],
		[0xC8, 0x64, 0x80, 0x90, 0x1F, 0x07]]
## The emitters: a particle nearer than this (SZ / 4) may be a dot; else a streak.
const EMITTER_DOT_DEPTH := 0x3E8

var host: EffectHost
## Optional, for a scene outside the battle (the death scene, specs/death_scene.md §5): the BattleFx
## drawn instead of the host's, and the projection (world_to_screen / viewport_distance, e.g. the
## FieldMap) instead of the host context's. Unset: the battle's.
var fx: BattleFx
var projector: Object

var _sprites: WorldSprites
var _lines: MeshInstance3D
var _line_mesh: ImmediateMesh
## SPOT256's flashes by u (0x40, 0), mirrored; DEFEFF by palette.
var _spots := {}
var _defeff := {}


func _ready() -> void:
	_sprites = WorldSprites.new()
	_sprites.name = "Sprites"
	add_child(_sprites)
	_line_mesh = ImmediateMesh.new()
	_lines = MeshInstance3D.new()
	_lines.name = "Lines"
	_lines.mesh = _line_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.vertex_color_is_srgb = true
	_lines.material_override = line_material
	add_child(_lines)


## One frame: what the effects show after this frame's tick.
func draw_frame() -> void:
	_sprites.begin()
	_line_mesh.clear_surfaces()
	if fx != null:
		_draw_flashes(fx)
	elif host != null and host.ctx != null:
		var shared := host.ctx.fx
		if shared != null:
			_draw_bursts(shared)
			_draw_entity_particles(shared)
			_draw_clouds(shared)
			_draw_flashes(shared)
		_draw_emitters()
	_sprites.end()


func shown() -> int:
	return _sprites.used()


# --- the C's projection -------------------------------------------------------------------------

## worldPosToScreenPos's depth (SZ) of a PSX point; 0 behind the camera.
func _depth(psx: Vector3i) -> int:
	var source: Object = projector if projector != null else host.ctx
	return maxi(int(source.world_to_screen(PsxMath.s16_vec(psx))["sz"]), 0)


func _h() -> int:
	return projector.viewport_distance() if projector != null else host.ctx.viewport_distance()


static func _godot(psx: Vector3i) -> Vector3:
	return Content.psx_to_godot([psx.x, psx.y, psx.z])


func _spot(u: int) -> PsxTexture:
	if not _spots.has(u):
		var t := PsxTexture.load_palette(SPOT_TEXTURE, 0)
		if t != null:
			var region := Rect2(u, 64, FLASH_SIZE, FLASH_SIZE)
			t.base = ParticleFX.mirrored(t.base, region)
			t.stp = ParticleFX.mirrored(t.stp, region)
		_spots[u] = t
	return _spots[u]


func _defeff_palette(palette: int) -> PsxTexture:
	if not _defeff.has(palette):
		_defeff[palette] = PsxTexture.load_palette(DEFEFF, palette)
	return _defeff[palette]


## renderParticleFlash: the flash's half size on screen is (scale · 63 >> 10) + 1 pixels; the whole
## mirrored flash is drawn twice that, centred on the point.
func _flash(texture: PsxTexture, abr: int, at: Vector3i, depth: int, scale: int, color: Color,
		shift := Vector3.ZERO) -> void:
	var half := (scale * (FLASH_SIZE - 1)) >> 10
	if half <= 0:
		return
	half += 1
	var world := 2.0 * half * depth / _h()
	_sprites.sprite(texture, abr, _godot(at) + shift, Vector2(world, world), Rect2(0, 0, 2 * FLASH_SIZE, 2 * FLASH_SIZE), color)


## renderEFEFlash's offset (efe.c:916–923) as a Godot move: a mode >= 0 adds offset · H / depth
## pixels, which is `offset` world units along the camera's right / down axes; a negative mode adds
## the pixels themselves (offset · depth / H units).
func _flash_shift(f: Dictionary, depth: int) -> Vector3:
	var ox: int = f.get("offset_x", 0)
	var oy: int = f.get("offset_y", 0)
	if ox == 0 and oy == 0:
		return Vector3.ZERO
	var camera := get_viewport().get_camera_3d() if get_viewport() != null else null
	if camera == null:
		return Vector3.ZERO
	var units := Vector2(ox, oy) if int(f["mode"]) >= 0 else Vector2(ox, oy) * depth / _h()
	return camera.global_basis.x * units.x - camera.global_basis.y * units.y


## renderFXParticle / addFXPrim: a `size`-unit DEFEFF dot (palette 1), added; culled at the OT depth
## (SZ >> 4) - 0x37.
func _fx_particle(at: Vector3i, size: int, color: Color) -> void:
	var depth := _depth(at)
	var ot := (depth >> 4) - 0x37
	if depth <= 0 or ot <= 0x20 or ot >= 0x1000:
		return
	_sprites.sprite(_defeff_palette(1), PsxLit.ADD, _godot(at), Vector2(size, size), FX_PARTICLE_REGION, color)


# --- the effects --------------------------------------------------------------------------------

func _draw_bursts(fx: BattleFx) -> void:
	for b in fx.bursts.effects:
		var state: int = b["state"]
		if state < 0:
			continue
		var c: Array = b["color"]
		if state == ParticleBursts.FLASH_STATE:
			for s in b["spread"]:
				var at := Vector3i(b["position"]) + Vector3i(s[0], s[1], s[2])
				var depth := _depth(at)
				if depth <= 0 or (depth >> 4) <= 0x20 or (depth >> 4) >= 0x1000:
					continue
				var scale := (int(s[3]) * (_h() * 8)) / depth
				_flash(_spot(0x40), PsxLit.ADD, at, depth, scale, Color(c[0] / 128.0, c[1] / 128.0, c[2] / 128.0))
		if state >= b["timer"] or ParticleBursts.directions.is_empty():
			continue
		var shade := Color(ParticleBursts.lerp_c(c[0], 0, 0, b["timer"], state) / 128.0,
				ParticleBursts.lerp_c(c[1], 0, 0, b["timer"], state) / 128.0,
				ParticleBursts.lerp_c(c[2], 0, 0, b["timer"], state) / 128.0)
		for i in ParticleBursts.PARTICLE_COUNT[b["mode"]]:
			_fx_particle(ParticleBursts.particle_position(b, i), FX_PARTICLE_SIZE, shade)


func _draw_entity_particles(fx: BattleFx) -> void:
	for p in fx.entity_particles:
		if p["timer"] < 0:
			continue
		var at := PsxMath.translation(host.ctx.bone_matrix(p["owner"], p["bone"]))
		var depth := _depth(at)
		var ot := (depth >> 4) - 0x37
		if depth <= 0 or ot <= 0x20 or ot >= 0x1000:
			continue
		var s: Array = ENTITY_SPRITES[p["sprite"]]
		var u: int = s[2] + (s[4] + 1) * (p["timer"] % 4)
		_sprites.sprite(_defeff_palette(2), PsxLit.ADD, _godot(at), Vector2(s[0], s[1]),
				Rect2(u, s[3] - 0x80, s[4], s[5]))


func _draw_clouds(fx: BattleFx) -> void:
	for c in fx.clouds:
		var state: int = c["state"]
		if state < 0:
			continue
		var at := Vector3i(c["x"], CloudFX.Y[state], c["z"])
		var depth := _depth(at)
		if depth <= 0x200 or depth >= 0x10000:
			continue
		var size: float = CloudFX.SIZE * CloudFX.SCALE[state] / CloudFX.SCALE_ONE
		var shade: float = CloudFX.COLOR[state] / 128.0
		_sprites.sprite(_defeff_palette(0), PsxLit.ADD, _godot(at), Vector2(size, size),
				Rect2(CloudFX.U[state], 0, CloudFX.SIZE, CloudFX.SIZE), Color(shade, shade, shade))


func _draw_flashes(source: BattleFx) -> void:
	for f in source.flashes:
		var progress: int = f["progress"]
		if progress < 0:
			continue
		var at: Vector3i = f["position"]
		var depth := _depth(at)
		if depth <= 0:
			continue
		var mode: int = absi(f["mode"])
		var t_max: int = f["t_max"]
		var lo: Vector3i = f["color_min"]
		var hi: Vector3i = f["color_max"]
		var factor := PsxMath.sin512(ParticleBursts.lerp_c(0x80, 0x14, 0, t_max, progress))
		var color := Color(((ParticleBursts.lerp_c(lo.x, hi.x, 0, t_max, progress) * factor) >> 12) / 128.0,
				((ParticleBursts.lerp_c(lo.y, hi.y, 0, t_max, progress) * factor) >> 12) / 128.0,
				((ParticleBursts.lerp_c(lo.z, hi.z, 0, t_max, progress) * factor) >> 12) / 128.0)
		var scale := (_h() * ParticleBursts.lerp_c(f["scale_min"], f["scale_max"], 0, t_max, progress) * 10) / depth
		scale += ((PsxMath.sin512(ParticleBursts.lerp_c(0, 0x1EB, 0, 0x17, progress)) * 300) >> 12) + 1
		if scale >= 0x8000:
			continue
		var ot: int = depth >> 4 if f["fixed_depth"] <= 0 else f["fixed_depth"]
		if ot <= 0x20 or ot >= 0x1000:
			continue
		_flash(_spot(0 if mode == 1 else 0x40), PsxLit.SUBTRACT if mode == 0x20 else PsxLit.ADD, at, depth, scale,
				color, _flash_shift(f, depth))


## BTL_renderParticleEmitters: each live particle between its two points along its direction.
func _draw_emitters() -> void:
	var lines := []
	for e in host.emitters:
		if e.is_empty():
			continue
		var kind: int = e["type"]
		var start: int = e["start_offset"]
		if start == 0:
			continue
		var c: Vector3i = e["color"]
		var color := Color((c.x & 0xFF) / 255.0, (c.y & 0xFF) / 255.0, (c.z & 0xFF) / 255.0)
		for k in EffectHost.EMITTER_PARTICLES:
			var distance: int = e["distance"][k]
			if distance <= 0:
				continue
			var f0 := 0
			var f1 := 0
			match kind:
				0:
					f0 = distance << 4
					f1 = (distance + 7) << 4
				1:
					f0 = distance << 4
					f1 = distance << 2
				3:
					f0 = (start - distance) << 4
					f1 = (start - distance) << 2
				2:
					f0 = (start - distance) << 4
					f1 = ((start - distance) - 5) << 4
			f0 = PsxMath.div(f0, start)
			f1 = PsxMath.div(f1, start)
			var p: Vector3i = e["position"][k]
			var d: Vector3i = e["direction"][k]
			var a := p + Vector3i((d.x * f0) >> 8, (d.y * f0) >> 8, (d.z * f0) >> 8)
			var b := p + Vector3i((d.x * f1) >> 8, (d.y * f1) >> 8, (d.z * f1) >> 8)
			if (_depth(a) >> 2) < EMITTER_DOT_DEPTH and (kind & 1) != 1:
				_fx_particle(a, EMITTER_PARTICLE_SIZE, Color((c.x & 0xFF) / 128.0, (c.y & 0xFF) / 128.0, (c.z & 0xFF) / 128.0))
			else:
				lines.append([_godot(a), _godot(b), color])
	if lines.is_empty():
		return
	_line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for l in lines:
		_line_mesh.surface_set_color(l[2])
		_line_mesh.surface_add_vertex(l[0])
		_line_mesh.surface_set_color(l[2])
		_line_mesh.surface_add_vertex(l[1])
	_line_mesh.surface_end()
