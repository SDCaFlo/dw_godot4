class_name FishingView
extends Node3D
## What FISH_renderFishingWorld draws in the world (fish.c:4442; specs/fishing.md §2.2-2.5, §2.13;
## step F5), from the logic's state once per game frame (draw_frame): the fish's shadows (flat
## sprites, subtractive), Seadramon (SEA.TMD's 5 segments), the ripples (additive), the markers, the
## rod (SAO.TMD's 4 segments), the bobber, the line and the bait / catch icon. The sprites are
## FISH_drawSprite3D's quads on WorldSprites, so the 3D models hide them as the ordering table does.

const ROD_MODEL := "tmd_files/ETCDAT/SAO.gltf"
const SEADRAMON_MODEL := "tmd_files/ETCDAT/SEA.gltf"
const ITEM_ICONS := "tim_files/ETCDAT/ITEM"
const TIM_FAMILY := "tim_files/"
## FISH_drawFishSprite's frames (fish.c:2850-2866): swimming MAIN_D_801349A4[(phase / 3) & 7] (size
## ≥ 100) / MAIN_D_801349AC[(phase / 4) & 3]; struggling MAIN_D_801349B0 / B8[phase % 6] at size
## × 170 / × 0x155.
const BIG_SIZE := 0x64
const SWIM_BIG: Array[int] = [39, 40, 41, 40, 39, 45, 44, 45]
const SWIM_SMALL: Array[int] = [33, 34, 33, 35]
const STRUGGLE_BIG: Array[int] = [41, 42, 40, 44, 43, 45]
const STRUGGLE_SMALL: Array[int] = [34, 36, 34, 35, 37, 35]
const STRUGGLE_SCALE_BIG := 170
const STRUGGLE_SCALE_SMALL := 0x155
## Flat on the water: rotation (−0x400, heading, 0) (fish.c:2871).
const FLAT := -0x400
## The shade: transparency × 30 / 128, as grey (fish.c:2868).
const SHADE := 30
## A hooked fish from this state on struggles (fish.c:3465).
const STRUGGLE_STATE := 0x1F
## The bobber: FISH_SPRITES[sprite − 1 + 0x11] with the old rod, + 0x18 with the amazing rod (fish.c:2462).
const BOBBER_OLD_ROD := 0x11
const BOBBER_AMAZING_ROD := 0x18
## The ripples: kind 0 FISH_SPRITES[sprite − 1], the others [sprite + 4] (fish.c:1889-1893).
const RIPPLE_OTHER := 4
## FISH_D_8007A56C: where each Seadramon segment starts from the last (fish.c:489).
const SEADRAMON_LINKS: Array[Vector3i] = [Vector3i(0, 0, -0xC8), Vector3i(0, 0, -0xAF), Vector3i(0, 0, -0x7D),
		Vector3i(0, 0, -0x8C), Vector3i.ZERO]
## The amazing rod's MoveImage (fish.c:4611-4612): VRAM (0x1C0, 0x1E4, 0x1C × 8) → (0x1C0, 0x1DC), i.e.
## the rod's page rows 0xE4-0xEB onto 0xDC-0xE3, u 0-0x6F.
const ROD_SWAP_FROM := Rect2i(0, 0xE4, 0x70, 8)
const ROD_SWAP_TO := Vector2i(0, 0xDC)
## The PSX blend modes (flags & 3 with setSemiTrans(flags >> 2)): the fish 6 (subtract), the ripples 5
## (add), the bobber 0 (opaque).
const ABR_FISH := PsxLit.SUBTRACT
const ABR_RIPPLE := PsxLit.ADD
const OPAQUE := -1

var data: Node
var sprites: WorldSprites
## GameData.fishing()["sprites"] (FISH_SPRITES).
var sprite_table: Array = []
var _sprite_file := ""
## The TIM's image starts at this v of its page (vram.uv_origin), its CLUT rows at clut_rect.y.
var uv_origin_v := 0
var _clut_y := 0
var _textures := {}
var _icons := {}
var _rod: Node3D
var _rod_parts: Array[Node3D] = []
var _seadramon: Node3D
var _seadramon_parts: Array[Node3D] = []
## The rod's textures as loaded, by material, and which rod they show (1 old, 2 amazing).
var _rod_textures := {}
var _rod_shown := 1


func _ready() -> void:
	sprites = get_node_or_null("Sprites")
	if sprites == null:
		sprites = WorldSprites.new()
		sprites.name = "Sprites"
		add_child(sprites)
	_rod = _model(ROD_MODEL, "Rod", _rod_parts, 4)
	_seadramon = _model(SEADRAMON_MODEL, "Seadramon", _seadramon_parts, 5)
	for node in _rod.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i in mesh.mesh.get_surface_count() if mesh.mesh != null else 0:
			var m := mesh.get_surface_override_material(i) as ShaderMaterial
			if m != null:
				_rod_textures[m] = m.get_shader_parameter("albedo_texture")
	hide_all()


## The model's object_0 .. object_<n - 1> nodes, posed one by one (GsSortObject4J per object).
func _model(rel: String, node_name: String, parts: Array[Node3D], count: int) -> Node3D:
	var root := Content.load_model(rel) if Content.exists(rel) else null
	if root == null:
		root = Node3D.new()
	root.name = node_name
	add_child(root)
	for i in count:
		var part := root.find_child("object_%d" % i, true, false) as Node3D
		parts.append(part)
		if part != null:
			part.top_level = true
	return root


## The map's sprite file (ETCDAT/FISHING.TIM or FISHING2.TIM) and FISH_SPRITES.
func setup(sprite_file: String, table: Array) -> void:
	sprite_table = table
	_sprite_file = TIM_FAMILY + sprite_file.get_basename()
	_textures.clear()
	var sidecar = Content.load_json(_sprite_file + ".json")
	if sidecar is Dictionary:
		uv_origin_v = int(sidecar["vram"]["uv_origin"]["v"])
		_clut_y = int(sidecar["vram"]["clut_rect"]["y"])


func hide_all() -> void:
	if sprites != null:
		sprites.begin()
		sprites.end()
	_rod.visible = false
	_seadramon.visible = false


## FISH_renderFishingWorld for this frame.
func draw_frame(f: Fishing, rod: FishingRod) -> void:
	if f == null or f.disabled or f.partner_evolving:
		hide_all()
		return
	sprites.begin()
	var seadramon_drawn := false
	for fish in f.fish:
		if fish.active:
			seadramon_drawn = _draw_fish(f, fish, false) or seadramon_drawn
	if rod != null and rod.hooked.active:
		seadramon_drawn = _draw_fish(f, rod.hooked, rod.hooked.state >= STRUGGLE_STATE) or seadramon_drawn
	_seadramon.visible = seadramon_drawn
	for r in f.ripples:
		if r.active and r.sprite > 0:
			var index := r.sprite - 1 if r.kind == 0 else r.sprite + RIPPLE_OTHER
			_sprite3d(f, index, r.pos, Vector3i.ZERO, (int(f.map["scale"]) * r.scale) >> 12, Color.WHITE, ABR_RIPPLE)
	for m in f.markers:
		if m.active:
			_sprite2d_at(f, m.sprite, m.pos)
	var rod_shown := rod != null and rod.display_rod and rod.display_swimmer
	_rod.visible = rod_shown
	if rod_shown:
		_set_rod_texture(rod.rod_type)
		for i in _rod_parts.size():
			if _rod_parts[i] != null:
				_rod_parts[i].global_transform = Content.psx_transform(rod.segment_matrices[i])
		if rod.swimmer_sprite > 0:
			var base := BOBBER_OLD_ROD if rod.rod_type == 1 else BOBBER_AMAZING_ROD
			_sprite3d(f, rod.swimmer_sprite - 1 + base, rod.swimmer_pos, Vector3i.ZERO, int(f.map["scale"]), Color.WHITE, OPAQUE)
	if rod != null and rod.display_rod:
		if rod.display_line:
			sprites.line(_godot(rod.line_start), _godot(rod.swimmer_pos), rod.tension_color)
		if rod.item_shown and rod.item_pos.y < 0:
			_draw_bait(f, rod)
	sprites.end()


## FISH_drawFishSprite (fish.c:2837); true when it was Seadramon (its model is posed).
func _draw_fish(f: Fishing, fish: Fishing.Fish, struggling: bool) -> bool:
	if fish.kind == Fishing.SEADRAMON:
		_pose_seadramon(f, fish.pos)
		return true
	var index := 0
	var scale := 0
	var big := fish.size >= BIG_SIZE
	var fish_scale: Dictionary = f.map["fish_scale"]
	if not struggling:
		index = SWIM_BIG[(fish.anim_phase / 3) & 7] if big else SWIM_SMALL[(fish.anim_phase / 4) & 3]
		scale = fish.size * int(fish_scale["large" if big else "small"])
	else:
		index = STRUGGLE_BIG[fish.anim_phase % 6] if big else STRUGGLE_SMALL[fish.anim_phase % 6]
		scale = fish.size * (STRUGGLE_SCALE_BIG if big else STRUGGLE_SCALE_SMALL)
	var shade := (fish.transparency * SHADE / 128) & 0xFF
	var tint := Color(shade / 128.0, shade / 128.0, shade / 128.0)
	_sprite3d(f, index, fish.pos, Vector3i(FLAT, fish.rotation.y, 0), scale, tint, ABR_FISH)
	return false


## FISH_drawSeadramon (fish.c:2568): segment i turned by the history's i-th rotation (x + 0x800, z
## mirrored), each starting where the last one ends.
func _pose_seadramon(f: Fishing, start: Vector3i) -> void:
	var pos := start
	for i in _seadramon_parts.size():
		var h: Vector3i = f.seadramon_history[i]
		var shown := Vector3i(PsxMath.s16(h.x + 0x800), h.y, PsxMath.s16(0x800 - h.z))
		var m := PsxMath.rot_matrix_yxz(shown)
		m[9] = pos.x
		m[10] = pos.y
		m[11] = pos.z
		if _seadramon_parts[i] != null:
			_seadramon_parts[i].global_transform = Content.psx_transform(m)
		pos += PsxMath.apply_matrix_lv(PsxMath.rot_matrix_yxz(h), SEADRAMON_LINKS[i])


## FISH_drawSprite3D (fish.c:1660): the sprite's quad around its origin (ox, oy), scaled (4096 = one
## texel a unit), turned by `rot` (RotMatrixYXZ) at `pos`.
func _sprite3d(f: Fishing, index: int, pos: Vector3i, rot: Vector3i, scale: int, tint: Color, abr: int) -> void:
	if index < 0 or index >= sprite_table.size():
		return
	var desc: Dictionary = sprite_table[index]
	var uv: Array = desc["uv"]
	var origin: Array = desc["origin"]
	var u0 := int(uv[0])
	var v0 := int(uv[1])
	var u1 := int(uv[2])
	var v1 := int(uv[3])
	var ox := int(origin[0])
	var oy := int(origin[1])
	var x0 := (-ox * scale) >> 12
	var x1 := (scale * (-ox + absi(u1 - u0))) >> 12
	var y0 := (-oy * scale) >> 12
	var y1 := (scale * (-oy + absi(v1 - v0))) >> 12
	var m := PsxMath.rot_matrix_yxz(rot)
	var corners := []
	for c in [Vector3i(x0, y0, 0), Vector3i(x1, y0, 0), Vector3i(x0, y1, 0), Vector3i(x1, y1, 0)]:
		var w: Vector3i = pos + PsxMath.apply_matrix_lv(m, c)
		# RotTransPers4's flag: a corner behind the camera drops the sprite.
		if f.camera.project(w) == null:
			return
		corners.append(_godot(w))
	sprites.quad(sprite_texture(desc), abr, corners, Rect2(u0, v0 - uv_origin_v, u1 - u0, v1 - v0), tint)


## FISH_drawSprite2D at a point's projection (the markers, fish.c:1725): screen pixels shown as
## world units at the point's depth (size × z / H).
func _sprite2d_at(f: Fishing, index: int, pos: Vector3i) -> void:
	if index < 0 or index >= sprite_table.size():
		return
	var v := PsxMath.apply_matrix_lv(f.camera.ws, pos) + PsxMath.translation(f.camera.ws)
	if v.z <= 0 or v.z >= 0x10000:
		return
	var desc: Dictionary = sprite_table[index]
	var uv: Array = desc["uv"]
	var origin: Array = desc["origin"]
	var w := absi(int(uv[2]) - int(uv[0]))
	var h := absi(int(uv[3]) - int(uv[1]))
	var per_px := float(v.z) / f.camera.h
	var size := Vector2(w, h) * per_px
	var offset := Vector2(w / 2.0 - int(origin[0]), h / 2.0 - int(origin[1])) * per_px
	sprites.sprite(sprite_texture(desc), OPAQUE, _godot(pos), size,
			Rect2(int(uv[0]), int(uv[1]) - uv_origin_v, int(uv[2]) - int(uv[0]), int(uv[3]) - int(uv[1])), Color.WHITE, offset)


## FISH_drawBaitSprite (fish.c:2244): the item's icon, a square of radius unk8 at its point.
func _draw_bait(f: Fishing, rod: FishingRod) -> void:
	if data == null:
		return
	var record: Dictionary = data.item(rod.item_sprite)
	if record.is_empty():
		return
	var clut := int(record.get("icon_clut", 0))
	if not _icons.has(clut):
		_icons[clut] = PsxTexture.load_palette(ITEM_ICONS, clut)
	var id := int(record.get("id", 0))
	var radius := int(f.map.get("bait_radius", 0))
	sprites.sprite(_icons[clut], OPAQUE, _godot(rod.item_pos), Vector2(radius, radius) * 2,
			Rect2((id % 16) * 16, (id / 16) * 16, 16, 16))


## The sprite's palette page: CLUT row − the TIM's first row.
func sprite_texture(desc: Dictionary) -> PsxTexture:
	var palette := int(desc["clut_xy"][1]) - _clut_y
	if not _textures.has(palette):
		_textures[palette] = PsxTexture.load_palette(_sprite_file, palette)
	return _textures[palette]


## The amazing rod's colours (the MoveImage of FISH_loadFishing) on the rod's texture.
func _set_rod_texture(rod_type: int) -> void:
	var wanted := 2 if rod_type == 2 else 1
	if wanted == _rod_shown:
		return
	_rod_shown = wanted
	for m in _rod_textures:
		var original: Texture2D = _rod_textures[m]
		if original == null:
			continue
		if wanted == 1:
			m.set_shader_parameter("albedo_texture", original)
			continue
		var image := original.get_image()
		if image.is_compressed():
			image.decompress()
		image.blit_rect(image.duplicate(), ROD_SWAP_FROM, ROD_SWAP_TO)
		m.set_shader_parameter("albedo_texture", ImageTexture.create_from_image(image))


static func _godot(v: Vector3i) -> Vector3:
	return Content.psx_to_godot([v.x, v.y, v.z])
