extends BattleVisual
## BTL_addItemParticles / BTL_tickItemParticles / BTL_renderItemParticles (battle_effect.c:6226-6315):
## when a thrown item reaches the partner (main.c:4283), 20 sparks burst up from the top of its
## head (the velocities BattleVisuals rolled at the battle's loading), slowed and falling, fading
## out over 25 frames; the effect lasts 40. Positions are kept × 16. All 20 draw with the first
## spark's brightness, as in the C.

const SPARKS := 0x14
const LIFE := 0x19
const TIMER := 0x28
const GRAVITY := 0x36
const SIZE := 0x14

var timer := 0
## Per spark: {life, position (× 16), velocity, brightness, fade}.
var sparks: Array[Dictionary] = []


func start(_args: Array) -> void:
	timer = TIMER
	var t := PsxMath.translation(ctx.bone_matrix(entity, 0))
	sparks.clear()
	for j in SPARKS:
		sparks.append({"life": LIFE, "position": Vector3i(t.x << 4, (t.y - ctx.height(entity)) << 4, t.z << 4),
				"velocity": visuals.item_velocities[j], "brightness": 0xFF0, "fade": PsxMath.div(-0xFF0, LIFE)})


func tick() -> void:
	timer -= 1
	if timer < 0:
		remove()
		return
	for i in SPARKS:
		var s: Dictionary = sparks[i]
		var drag: Vector2i = visuals.item_drag[i]
		var v: Vector3i = s["velocity"]
		s["life"] -= 1
		v.x = PsxMath.s16(v.x - drag.x)
		v.y = PsxMath.s16(v.y + GRAVITY)
		v.z = PsxMath.s16(v.z - drag.y)
		s["velocity"] = v
		s["position"] += v
		s["brightness"] = PsxMath.s16(s["brightness"] + s["fade"])


func draw(view: BattleVisualsView) -> void:
	var b: int = (int(sparks[0]["brightness"]) >> 4) & 0xFF
	var color := Color(b / 128.0, b / 128.0, b / 128.0)
	for s in sparks:
		if s["life"] >= 0:
			var p: Vector3i = s["position"]
			view.fx_particle(PsxMath.s16_vec(Vector3i(p.x >> 4, p.y >> 4, p.z >> 4)), SIZE, color)
