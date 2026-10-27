class_name BattleVisualsView
extends Node3D
## Where the battle visuals (BattleVisuals, specs/battle_effects.md §7.6) draw: one WorldSprites
## for their sprites and polygons, and the overlay's models (asset porter `btl_rel/`: the finisher
## aura, the confusion and stun models, the buff model) as TmdObjects. Each visual's scene is a
## child of it and draws through it in its draw(); the C's helpers are here:
## - render_tmd: renderTMDModel (RotMatrix, ScaleMatrix, TransMatrix, under a parent coordinate);
## - gs_sprite / render_sprite: GsSortSprite / renderSprite, a screen sprite at an OT slot;
## - fx_particle: renderFXParticle, a DEFEFF dot (palette 1) added;
## - poly: addScreenPolyFT3 / addScreenPolyFT4, a textured polygon from world points.
## Its scene is scenes/battle/fx/battle_visuals_view.tscn; the battle host adds it to the world and
## calls draw_frame once per game frame.

const MODELS := {"finisher_aura": "btl_rel/finisher_aura.gltf", "confusion": "btl_rel/confusion.gltf",
		"stun": "btl_rel/stun.gltf", "buff": "btl_rel/buff.gltf"}
## BTL_initializeFinisherAuraModel: BTL_setTMDObjectColor of objects 0-2 and 4 (BTL_D_8007380C)
## and 3 (BTL_D_8007381C).
const FINISHER_COLORS := {0: Vector3i(0x3C, 0x3C, 0x3C), 1: Vector3i(0x3C, 0x3C, 0x3C), 2: Vector3i(0x3C, 0x3C, 0x3C),
		3: Vector3i(0x5A, 0x5A, 0x5A), 4: Vector3i(0x3C, 0x3C, 0x3C)}
## DEFEFF (etctim/02_defeff, tpage 768,256 at v 0x80): palette n = CLUT row 488 + n.
const DEFEFF := "etctim/02_defeff"
const DEFEFF_ROW := 488
const DEFEFF_V := 0x80
## The buff model's disk (object 5): morphBuffModel's two CLUTs (0x7acc = row 491, 0x7b0c = 492).
const BUFF_DISK := 5
const BUFF_DISK_ROWS := [491, 492]
## The OT slot's depth (OT z = SZ >> 4), clamped like EfeView's.
const OT_DEPTH_MIN := 20.0
const OT_DEPTH_MAX := 90000.0

var visuals: BattleVisuals
var sprites: WorldSprites

var _models := {}
var _defeff := {}
var _disk_pages := {}
var _disk_row := -1


func _ready() -> void:
	sprites = WorldSprites.new()
	sprites.name = "Sprites"
	add_child(sprites)
	for name in MODELS:
		var m := TmdObjects.new()
		m.name = name.capitalize().replace(" ", "")
		add_child(m)
		if m.load_model(MODELS[name]):
			_models[name] = m
	if _models.has("finisher_aura"):
		for k in FINISHER_COLORS:
			_models["finisher_aura"].set_color(k, FINISHER_COLORS[k])


func ctx() -> BattleEffectContext:
	return visuals.ctx if visuals != null else null


## One frame: what the visuals show after this frame's tick.
func draw_frame() -> void:
	if sprites == null:
		return
	sprites.begin()
	for m in _models.values():
		m.begin_frame()
	if visuals != null and ctx() != null:
		_buff_disk_palette()
		visuals.draw(self)
	for m in _models.values():
		m.end_frame()
	sprites.end()


func shown() -> int:
	var n := sprites.used() if sprites != null else 0
	for m in _models.values():
		n += m.shown()
	return n


# --- models -------------------------------------------------------------------------------------

## renderTMDModel(model, object, coord, super, trans, rot, scale): RotMatrix(rot) scaled and moved,
## under `parent` (the super coordinate's world matrix) when given. Returns the coordinate's world
## matrix (a child's parent).
func render_tmd(model: String, object: int, trans: Vector3i, rot: Vector3i, scale: Vector3i,
		parent := PackedInt32Array()) -> PackedInt32Array:
	var local := PsxMath.trans_matrix(PsxMath.scale_matrix(PsxMath.rot_matrix(rot), scale), trans)
	var world := PsxMath.gs_mul_coord0(parent, local) if not parent.is_empty() else local
	if _models.has(model):
		_models[model].draw(object, world)
	return world


## morphBuffModel: the disk's CLUT this frame (BattleVisuals.buff_row).
func _buff_disk_palette() -> void:
	var row := visuals.buff_row
	if row == _disk_row or not _models.has("buff"):
		return
	_disk_row = row
	if not _disk_pages.has(row):
		_disk_pages[row] = _defeff_page(row - DEFEFF_ROW)
	var page: Array = _disk_pages[row]
	if not page.is_empty():
		_models["buff"].set_textures(BUFF_DISK, page[0], page[1])


## DEFEFF in one palette on its 256 x 256 texture page (at v 0x80), as the porter's model pages:
## [albedo, STP mask].
func _defeff_page(palette: int) -> Array:
	var t := defeff(palette)
	if t == null or t.base == null:
		return []
	var base := t.base.get_image()
	var stp := t.stp.get_image() if t.stp != null else null
	var albedo := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	var mask := Image.create(256, 256, false, Image.FORMAT_RGBA8)
	for y in mini(base.get_height(), 256 - DEFEFF_V):
		for x in mini(base.get_width(), 256):
			var c := base.get_pixel(x, y)
			if stp != null and stp.get_pixel(x, y).a > 0.0:
				c = stp.get_pixel(x, y)
				mask.set_pixel(x, y + DEFEFF_V, Color.WHITE)
			if c.a > 0.0:
				albedo.set_pixel(x, y + DEFEFF_V, c)
	return [ImageTexture.create_from_image(albedo), ImageTexture.create_from_image(mask)]


# --- the projection -------------------------------------------------------------------------------

## worldPosToScreenPos: {screen (relative to the drawing offset), sz}.
func project(psx: Vector3i) -> Dictionary:
	return ctx().world_to_screen(PsxMath.s16_vec(psx))


func viewport_distance() -> int:
	return ctx().viewport_distance()


static func godot(psx: Vector3i) -> Vector3:
	return Content.psx_to_godot([psx.x, psx.y, psx.z])


func _ot_depth(z: int) -> float:
	return clampf(float(z << 4), OT_DEPTH_MIN, OT_DEPTH_MAX)


# --- sprites and polygons -------------------------------------------------------------------------

func defeff(palette: int) -> PsxTexture:
	if not _defeff.has(palette):
		_defeff[palette] = PsxTexture.load_palette(DEFEFF, palette)
	return _defeff[palette]


## A GsSPRITE through GsSortSprite: texel (mx, my) on `at` (screen, relative to the drawing offset),
## w x h texels scaled (4096 = 1), at OT slot `z`.
func gs_sprite(texture: PsxTexture, abr: int, at: Vector2, region: Rect2, anchor: Vector2, scale_x: int,
		scale_y: int, z: int, tint := Color.WHITE) -> void:
	if texture == null or z < 0 or z >= 0x1000:
		return
	var sx := scale_x / 4096.0
	var sy := scale_y / 4096.0
	var depth := _ot_depth(z)
	var corners := []
	for c in [Vector2(0, 0), Vector2(region.size.x, 0), Vector2(0, region.size.y), region.size]:
		corners.append(ctx().screen_to_world(at + Vector2((c.x - anchor.x) * sx, (c.y - anchor.y) * sy), depth))
	sprites.quad(texture, abr, corners, region, tint)


## renderSprite (effect_common.c:518): scaled by width · H / distance, at OT distance >> 4.
func render_sprite(texture: PsxTexture, abr: int, at: Vector2, region: Rect2, anchor: Vector2, distance: int,
		width: int, height: int) -> void:
	if distance <= 0:
		return
	var h := viewport_distance()
	gs_sprite(texture, abr, at, region, anchor, width * h / distance, height * h / distance, distance >> 4)


## renderFXParticle (effect_common.c:761): a `size`-unit DEFEFF dot (palette 1, u 0 v 160, 15 x 15),
## added; culled at the OT depth (SZ >> 4) - 0x37 (addFXPrim).
func fx_particle(at: Vector3i, size: int, color: Color) -> void:
	var depth := maxi(int(project(at)["sz"]), 0)
	var ot := (depth >> 4) - 0x37
	if depth <= 0 or ot <= 0x20 or ot >= 0x1000:
		return
	sprites.sprite(defeff(1), PsxLit.ADD, godot(at), Vector2(size, size), Rect2(0, 160 - DEFEFF_V, 15, 15), color)


## addScreenPolyFT3 / addScreenPolyFT4: a polygon from world points (FT4: top-left, top-right,
## bottom-left, bottom-right; FT3 as a quad whose last corner repeats the third), with per-corner
## texels on a DEFEFF palette; culled at the average OT depth (0x20, 0x1000).
func poly(texture: PsxTexture, abr: int, points: Array, uvs: Array, tint: Color) -> void:
	if texture == null:
		return
	var sum := 0
	for p in points:
		sum += int(project(p)["sz"])
	var ot := (sum / points.size()) >> 4
	if ot <= 0x20 or ot >= 0x1000:
		return
	var corners := points.duplicate()
	var texels := uvs.duplicate()
	if corners.size() == 3:
		corners.append(corners[2])
		texels.append(texels[2])
	sprites.quad(texture, abr, corners.map(func(p): return godot(p)), Rect2(), tint,
			texels.map(func(uv): return Vector2(uv.x, uv.y - DEFEFF_V)))


## BTL_renderFinisherAuraSpark / BTL_renderBuffRingsSpark (battle_effect.c:5930, :6649): a thin
## triangle from `pos` to the pair's two points scaled (4096 = 1), DEFEFF palette 1 (u 0x30-0x37,
## v 0xa8-0xaf), added in `color` (128 = 1.0).
func spark(pos: Vector3i, scale: int, d0: Vector3i, d1: Vector3i, color: Vector3i) -> void:
	var a := PsxMath.s16_vec(Vector3i(PsxMath.div(d0.x * scale, 4096), PsxMath.div(d0.y * scale, 4096),
			PsxMath.div(d0.z * scale, 4096)) + pos)
	var b := PsxMath.s16_vec(Vector3i(PsxMath.div(d1.x * scale, 4096), PsxMath.div(d1.y * scale, 4096),
			PsxMath.div(d1.z * scale, 4096)) + pos)
	poly(defeff(1), PsxLit.ADD, [pos, a, b], [Vector2(0x30, 0xA8), Vector2(0x37, 0xA8), Vector2(0x30, 0xAF)],
			Color((color.x & 0xFF) / 128.0, (color.y & 0xFF) / 128.0, (color.z & 0xFF) / 128.0))
