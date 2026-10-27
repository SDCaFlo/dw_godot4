extends BattleVisual
## BTL_addAuraProjectile / BTL_tickAuraProjectile / BTL_renderAuraProjectile (battle_effect.c:
## 6051-6178): what a flattened fighter fires, half its height up and ahead, flying 0x23 units a
## frame along its facing for 58 frames. The first entity (from 1, not its owner) whose box it
## enters and that isn't hit yet takes a hit (addAttackObject with effect 0x179: the generic
## technique 0x79, specs/battle.md §2.11) and the projectile ends. Drawn as a 100 x 100 square
## standing along its path: DEFEFF palette 4 (CLUT 192,492), u = the owner's
## aura_projectile_types.u + 0x60, v 0xa0, 7 x 7, added.

const FRAMES := 0x3A
const SPEED := -0x23
const EXTENT := Vector3i(0x2D, 0xC8, 0x2D)
const EFFECT := 0x179
const PALETTE := 4
const VERTICES := [Vector3i(0, -50, -50), Vector3i(0, -50, 50), Vector3i(0, 50, -50), Vector3i(0, 50, 50)]

var psx_position := Vector3i.ZERO
var psx_rotation := Vector3i.ZERO
var velocity := Vector3i.ZERO
var u := -1


func start(_args: Array) -> void:
	frame = 0
	var m := ctx.bone_matrix(entity, 0)
	var half := PsxMath.div(-ctx.height(entity) * 50, 100)
	psx_position = PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, PsxMath.s16_vec(Vector3i(0, half, half))))
	psx_position = PsxMath.s16_vec(psx_position + PsxMath.s16_vec(PsxMath.translation(m)))
	psx_rotation = Vector3i(0, ctx.rotation_y(entity), 0)
	velocity = PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, Vector3i(0, 0, SPEED)))
	if ctx.data != null and ctx.digimon_type(entity) >= 0:
		u = int(ctx.data.aura_projectile_type(ctx.digimon_type(entity)).get("u", -1))


func tick() -> void:
	frame += 1
	if frame >= FRAMES:
		remove()
		return
	psx_position = PsxMath.s16_vec(psx_position + velocity)
	var hit := ctx.find_aabb_entity(psx_position, EXTENT, entity, 1)
	if hit == -1 or ctx.is_hit(hit):
		return
	# The caster is the owner's ENTITY_TABLE index (searched from 1).
	ctx.set_hit(hit, true)
	visuals.add_attack_object(hit, psx_position, EFFECT, entity if entity >= 1 and entity < BattleEffectContext.ENTITIES else 10)
	remove()


func draw(view: BattleVisualsView) -> void:
	var m := PsxMath.rot_matrix(psx_rotation)
	var points := []
	for v in VERTICES:
		points.append(PsxMath.s16_vec(PsxMath.apply_matrix_sv(m, v) + psx_position))
	var u0 := (u + 0x60) & 0xFF
	view.poly(view.defeff(PALETTE), PsxLit.ADD, points,
			[Vector2(u0, 0xA0), Vector2(u0 + 7, 0xA0), Vector2(u0, 0xA7), Vector2(u0 + 7, 0xA7)], Color.WHITE)
