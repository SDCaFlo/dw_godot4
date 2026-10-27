extends BattleVisual
## BTL_addFinisherAura / BTL_tickFinisherAura / BTL_renderFinisherAura (battle_effect.c:5855-6034):
## the finisher wind-up's aura (btl_rel/finisher_aura) around the fighter, growing out of it in 10
## frames and breathing: one of objects 0-2 (in turn every 2 frames), object 3, and object 4 wider
## and turned at random each frame; for its first 7 frames, 10 sparks flying out (fading gold).
## The C rolls the random turn in its render; here the tick rolls it, one roll a frame as there.

const AURA_COLOR := Vector3i(0xCC, 0xA8, 0x28)
const SCALE := Vector3i(0x1000, 0x1000, 0x1000)

var duration := 0
## This frame's rand() turn of object 4.
var spin := 0


func start(args: Array) -> void:
	frame = 0
	duration = int(args[0]) if not args.is_empty() else 0x50


func tick() -> void:
	frame += 1
	if frame > duration:
		remove()
		return
	spin = PsxMath.s16(Rng.rand())


func draw(view: BattleVisualsView) -> void:
	var radius := ctx.radius(entity)
	var height := ctx.height(entity)
	var sx := 0x1000
	if frame < 10:
		var a := PsxMath.lerp_int(0, 0x80, 0, 9, frame)
		sx = PsxMath.div((0x1000 - PsxMath.cos512(a)) * 0xB34, 0x1000) + 0x4CC
	sx = PsxMath.div(sx * radius, 150)
	var t := PsxMath.lerp_int(0, 0x200, 0, 0x10, frame)
	var sy := frame * 0x1000 / 4 if frame < 5 else 0x1000
	sy = PsxMath.div(sy * height, 350)
	sy = PsxMath.div(sy * 85, 100) + PsxMath.div(PsxMath.div(sy * 15, 100) * PsxMath.sin512(t), 0x1000)
	var loc := ctx.location(entity)
	var scale := Vector3i(sx, sy, sx)
	view.render_tmd("finisher_aura", (frame / 2) % 3, loc, Vector3i.ZERO, scale)
	view.render_tmd("finisher_aura", 3, loc, Vector3i.ZERO, scale)
	var wide := PsxMath.div(sx * 140, 100)
	view.render_tmd("finisher_aura", 4, loc, Vector3i(0, spin, 0), Vector3i(wide, sy, wide))
	if frame < 7:
		var s := PsxMath.div(frame * 0x1000 / 7 * radius, 150)
		var col := AURA_COLOR * (7 - frame) / 7
		var sparks := visuals.aura_sparks
		for i in range(0, sparks.size(), 2):
			view.spark(PsxMath.s16_vec(loc), s, sparks[i], sparks[i + 1], col)
