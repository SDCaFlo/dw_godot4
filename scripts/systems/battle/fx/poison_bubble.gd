extends BattleVisual
## BTL_addPoisonBubble / BTL_tickPoisonBubble / BTL_renderPoisonBubble (battle_effect.c:5364-5425):
## a bubble rising from the fighter's condition point (translateConditionFXToEntity) for 40 frames,
## swaying, its six frames animating. BTL_POISON_BUBBLE_SPRITE: FEEL_EF (etctim/03_feel_ef, VRAM
## 960,384: v - 0x80), CLUT 272,487 (palette 7), 16 x 16 at v 0xb0, anchor (8, 8), added.

const FRAMES := 0x28
const FRAME_U := [0, 16, 32, 48, 64, 80]
const TEXTURE := "etctim/03_feel_ef"
const PALETTE := 7
const V := 0xB0 - 0x80
const SIZE := 0x4EA4

static var _texture: PsxTexture

var offset_x := 0
var offset_z := 0


func start(_args: Array) -> void:
	frame = 0
	offset_x = (Rng.rand() % 100) - 0x32
	offset_z = (Rng.rand() % 100) - 0x32


func tick() -> void:
	frame += 1
	if frame >= FRAMES:
		remove()


func draw(view: BattleVisualsView) -> void:
	var pos := ctx.condition_fx_position(entity)
	pos.x += offset_x
	pos.y -= PsxMath.s16(PsxMath.lerp_int(0x32, 0xC8, 0, FRAMES, frame))
	pos.z += offset_z
	var p := view.project(PsxMath.s16_vec(pos))
	var otz: int = p["sz"]
	if otz <= 0x200 or otz >= 0x10000:
		return
	var screen: Vector2i = p["screen"]
	var d := PsxMath.div(PsxMath.sin512(PsxMath.lerp_int(0, 0x500, 0, FRAMES, frame)) * 0x14, 4096)
	screen.x += PsxMath.s16(PsxMath.div(d * view.viewport_distance(), otz))
	if _texture == null:
		_texture = PsxTexture.load_palette(TEXTURE, PALETTE)
	var u: int = FRAME_U[(frame >> 1) % 6] + 0x20
	view.render_sprite(_texture, PsxLit.ADD, Vector2(screen), Rect2(u, V, 16, 16), Vector2(8, 8), otz, SIZE, SIZE)
