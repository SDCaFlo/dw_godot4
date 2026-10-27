extends BattleVisual
## BTL_addStunSubEffect / BTL_tickStunSubEffect / BTL_renderStunSubEffect (battle_effect.c:5717-5776):
## the stun model (btl_rel/stun) falling from above the head to the feet in 15 frames, growing to
## the fighter's width in its first 4.

const FRAMES := 0x10
## BTL_STUN_SUB_EFFECT_SCALE's y.
const SCALE_Y := 0x3000


func start(_args: Array) -> void:
	frame = 0


func tick() -> void:
	frame += 1
	if frame >= FRAMES:
		remove()


func draw(view: BattleVisualsView) -> void:
	var loc := ctx.location(entity)
	var pos := Vector3i(loc.x, PsxMath.lerp_int(PsxMath.div(-ctx.height(entity) * 113, 100), loc.y, 0, 0xF, frame), loc.z)
	var s := PsxMath.div(ctx.radius(entity) * 0x4000, 350)
	if frame < 4:
		s = PsxMath.lerp_int(PsxMath.div(s * 10, 100), s, 0, 4, frame)
	view.render_tmd("stun", 0, PsxMath.s16_vec(pos), Vector3i.ZERO, Vector3i(s, SCALE_Y, s))
