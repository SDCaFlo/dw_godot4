extends BattleVisual
## BTL_addConfusionEffect / BTL_tickConfusionEffect / BTL_renderConfusionEffect (battle_effect.c:
## 5501-5568): three copies of the confusion model (btl_rel/confusion) circling above the fighter's
## condition point, each spinning with its own random offset.

const RADIUS := 0x78
const SCALE := Vector3i(0x1000, 0x1000, 0x1000)

var angle := 0
var spin := 0
var offsets: Array[int] = [0, 0, 0]


func start(_args: Array) -> void:
	frame = 0
	angle = 0
	spin = 0
	for i in 3:
		offsets[i] = PsxMath.s16(Rng.rand())


func tick() -> void:
	angle = PsxMath.s16(angle + 7)
	spin = PsxMath.s16(spin + 0x5B)


func draw(view: BattleVisualsView) -> void:
	for i in 3:
		var pos := ctx.condition_fx_position(entity)
		var ang := angle + i * 0xAA
		var trans := Vector3i(pos.x + PsxMath.div(PsxMath.sin512(ang) * RADIUS, 4096), pos.y - RADIUS,
				pos.z + PsxMath.div(PsxMath.cos512(ang) * RADIUS, 4096))
		var rot := Vector3i(0, PsxMath.s16(offsets[i] + (spin - 0x400 + i * 0x555)), 0xE3)
		view.render_tmd("confusion", 0, trans, rot, SCALE)
