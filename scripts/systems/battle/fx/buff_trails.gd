extends BattleVisual
## BTL_addBuffTrails / BTL_tickBuffTrails / BTL_renderBuffTrails (battle_effect.c:6433-6515): with the
## buff disk, for 59 frames a ribbon a frame (in turn in eight directions, BattleVisuals.trail_a /
## trail_b, scaled by the partner's radius) rising from its feet, its top faster than its bottom,
## each living 8 frames and fading green. DEFEFF palette 1, added.

const TRAILS := 8
const FRAMES := 0x3B
const LIFE := 8
const UVS := [Vector2(0x5F, 0xA0), Vector2(0x5F, 0xA7), Vector2(0x30, 0xA0), Vector2(0x30, 0xA7)]

## Per trail: {life, p: [4 Vector3i]}.
var trails: Array[Dictionary] = []


func start(_args: Array) -> void:
	frame = 0
	trails.clear()
	for j in TRAILS:
		trails.append({"life": -1, "p": [Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO, Vector3i.ZERO]})


func tick() -> void:
	if frame >= 0 and frame < FRAMES:
		var k := frame % TRAILS
		var r: Dictionary = trails[k]
		r["life"] = LIFE
		var radius := ctx.radius(entity)
		var t := PsxMath.translation(ctx.bone_matrix(entity, 0))
		var a := PsxMath.s16_vec(Vector3i(t.x + PsxMath.div(radius * visuals.trail_a[k].x, 200), t.y,
				t.z + PsxMath.div(radius * visuals.trail_a[k].y, 200)))
		var b := PsxMath.s16_vec(Vector3i(t.x + PsxMath.div(radius * visuals.trail_b[k].x, 200), t.y,
				t.z + PsxMath.div(radius * visuals.trail_b[k].y, 200)))
		r["p"] = [a, b, a, b]
	for r in trails:
		r["life"] -= 1
		var p: Array = r["p"]
		p[0].y = PsxMath.s16(p[0].y - 100)
		p[1].y = PsxMath.s16(p[1].y - 100)
		p[2].y = PsxMath.s16(p[2].y - 0x25)
		p[3].y = PsxMath.s16(p[3].y - 0x25)
	frame += 1


func draw(view: BattleVisualsView) -> void:
	for r in trails:
		var life: int = r["life"]
		if life > 0:
			var color := Color((life * 200 / 8) / 128.0, (life * 255 / 8) / 128.0, (life * 180 / 8) / 128.0)
			view.poly(view.defeff(1), PsxLit.ADD, r["p"], UVS, color)
