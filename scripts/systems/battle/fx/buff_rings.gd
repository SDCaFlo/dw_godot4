extends BattleVisual
## BTL_addBuffRingsEffect / BTL_tickBuffRings / BTL_renderBuffRings (battle_effect.c:6581-6743): when
## a status is cured in battle (BTL_healStatusEffect, battle_main.c:2968), five rings of the buff
## model (btl_rel/buff, objects 3, 0, 1, 2, 4, each under the previous one's coordinate, so their
## turns and growth add up) spinning around the partner's bone 1 for 57 frames; then 16 sparks in
## the cure's colour flying out for 8. The kind picks the colour (0 poison, 1 stun, 2 confusion,
## 3 flatten).

const OBJECTS := [3, 0, 1, 2, 4]
const COLOR_R := [180, 100, 235, 180]
const COLOR_G := [20, 20, 150, 180]
const COLOR_B := [255, 255, 220, 180]
const RINGS_END := 0x39
const END := 0x41

var buff := 0
var ring_scale := 0
var target := 0
var rotations: Array[Vector3i] = []
var color := Vector3i.ZERO


func start(args: Array) -> void:
	frame = 0
	buff = clampi(int(args[0]) if not args.is_empty() else 0, 0, 3)
	ring_scale = 0
	rotations.clear()
	for j in 5:
		rotations.append(Vector3i(0x258, 0, 0x258))
	color = Vector3i(COLOR_R[buff], COLOR_G[buff], COLOR_B[buff])
	target = 0x1000 - PsxMath.div((0xC8 - ctx.radius(entity)) * 400, 200)


func tick() -> void:
	if frame >= END:
		remove()
		return
	if frame < RINGS_END:
		if frame < 0xF:
			ring_scale = PsxMath.lerp_int(target / 3, target, 0, 0xF, frame)
		elif frame < 0x2D:
			ring_scale = target
		else:
			ring_scale = PsxMath.lerp_int(target, PsxMath.div(target * 70, 100), 0x2D, RINGS_END, frame)
		for j in 5:
			var r := rotations[j]
			r.x = PsxMath.s16(r.x - (8 - j * 4 * 5))
			r.y = 0
			r.z = PsxMath.s16(r.z + (8 - j * 4) * 5)
			rotations[j] = r
	frame += 1


func draw(view: BattleVisualsView) -> void:
	var bone := PsxMath.translation(ctx.bone_matrix(entity, 1))
	if frame < RINGS_END:
		var parent := PackedInt32Array()
		var trans := bone
		for j in 5:
			var s := ring_scale * (j + 10) / 10
			parent = view.render_tmd("buff", OBJECTS[j], trans, rotations[j], Vector3i(s, s, s), parent)
			trans = Vector3i.ZERO
		return
	var v := PsxMath.lerp_int(0, target, RINGS_END, END, frame)
	var d := target - v
	var col := Vector3i(PsxMath.div(color.x * d, target) & 0xFF, PsxMath.div(color.y * d, target) & 0xFF,
			PsxMath.div(color.z * d, target) & 0xFF) if target != 0 else Vector3i.ZERO
	var sparks := visuals.ring_sparks
	for j in range(0, sparks.size(), 2):
		view.spark(PsxMath.s16_vec(bone), v, sparks[j], sparks[j + 1], col)
