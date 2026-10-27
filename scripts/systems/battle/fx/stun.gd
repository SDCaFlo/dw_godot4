extends BattleVisual
## BTL_addStunEffect / BTL_tickStunEffect / BTL_renderStunEffect (battle_effect.c:5606-5805): over
## the fighter's head, the stun's countdown (two big and two small digits, (duration - frame) · 5)
## with its frame, a star (stun_spark) every 6 frames; at 0 the frame flashes for 8 frames (CLUT
## row 480 / 481), then shrinks in 5 and the visual ends itself.
## The sprites are on BI_IN (etctim/00_bi_in, VRAM 896,384: v - 0x80), at OT slot 0x22, added.

const TEXTURE := "etctim/00_bi_in"
const OT := 0x22
const V0 := 0x80
## [u, v, w, h, mx, my] of BTL_D_8007376C, BTL_D_80073790 (the frame, two pieces).
const FRAME_PIECES := [[0x00, 0x80, 0x28, 0x16, 0x14, 0x2C], [0x28, 0x80, 0x0C, 0x16, 0x06, 0x16]]
## BTL_STUN_DIGIT_SPRITE (8 x 9 at v 0xb7, my 0x26) and BTL_STUN_SMALL_DIGIT_SPRITE (4 x 7 at v
## 0x96, my 0x25), CLUT row 0x1e2.
const DIGIT := [0xB7, 8, 9, 0x26]
const SMALL_DIGIT := [0x96, 4, 7, 0x25]
const DIGIT_PALETTE := 2

static var _textures := {}

var duration := 0
var state := 0


func start(args: Array) -> void:
	frame = 0
	duration = PsxMath.s16(int(args[0]) if not args.is_empty() else 0)
	state = 0


func tick() -> void:
	frame += 1
	match state:
		0:
			if frame % 6 == 0:
				visuals.add("stun_spark", entity)
			if frame >= duration:
				state = 1
				frame = 1
		1:
			if frame >= 8:
				state = 2
				frame = 1
		2:
			if frame >= 5:
				# BTL_removeStunEffect(i, entity).
				remove()


func draw(view: BattleVisualsView) -> void:
	var value := 0
	var scale := 0x1000
	var cy := 0
	match state:
		0:
			value = PsxMath.div((duration - frame) * 100, 20)
		1:
			cy = frame % 2
		2:
			scale = PsxMath.lerp_int(0x1000, 0xCC, 0, 5, frame)
	var loc := ctx.location(entity)
	var pos := Vector3i(loc.x, PsxMath.div(-ctx.height(entity) * 113, 100), loc.z)
	var at := Vector2(view.project(pos)["screen"])
	var digits := _texture(DIGIT_PALETTE)
	_digit(view, digits, at, DIGIT, PsxMath.mod(PsxMath.div(value, 1000), 10) * 8, 0xE, scale)
	_digit(view, digits, at, DIGIT, PsxMath.mod(PsxMath.div(value, 100), 10) * 8, 7, scale)
	_digit(view, digits, at, SMALL_DIGIT, PsxMath.mod(PsxMath.div(value, 10), 10) * 4, -2, scale)
	_digit(view, digits, at, SMALL_DIGIT, PsxMath.mod(value, 10) * 4, -8, scale)
	var frame_texture := _texture(cy)
	for piece in FRAME_PIECES:
		view.gs_sprite(frame_texture, PsxLit.ADD, at, Rect2(piece[0], piece[1] - V0, piece[2], piece[3]),
				Vector2(piece[4], piece[5]), scale, scale, OT)


func _digit(view: BattleVisualsView, texture: PsxTexture, at: Vector2, sprite: Array, u: int, mx: int, scale: int) -> void:
	view.gs_sprite(texture, PsxLit.ADD, at, Rect2(u, sprite[0] - V0, sprite[1], sprite[2]), Vector2(mx, sprite[3]),
			scale, scale, OT)


static func _texture(palette: int) -> PsxTexture:
	if not _textures.has(palette):
		_textures[palette] = PsxTexture.load_palette(TEXTURE, palette)
	return _textures[palette]
