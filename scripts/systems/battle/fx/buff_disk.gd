extends BattleVisual
## BTL_addBuffDiskEffect / BTL_tickBuffDisk / BTL_renderBuffDisk (battle_effect.c:6394-6551): when a
## stat item is used in battle (main.c:4405), the buff model's disk (btl_rel/buff, object 5) turning
## at the partner's feet: it grows from a third in 15 frames, holds, shrinks to a tenth from frame
## 55 and ends at 67, with its trails (buff_trails, started with it, ended with it). Its CLUT
## flickers between two rows every frame (the buff model object, BattleVisuals.buff_row).

const END := 0x43
const OBJECT := 5

var psx_rotation := Vector3i.ZERO
var scale_xz := 0
var scale_y := 0
var target_xz := 0
var target_y := 0


func start(_args: Array) -> void:
	frame = 0
	psx_rotation = Vector3i.ZERO
	scale_xz = 0
	target_xz = PsxMath.div(ctx.radius(entity) * 0xBB8, 200)
	target_y = PsxMath.div(ctx.height(entity) * 0xB22, 200)


func tick() -> void:
	if frame >= END:
		# BTL_removeBuffDiskEffect: the disk and BTL_removeBuffTrails(i).
		var trails := visuals.get_at("buff_trails", index)
		if trails != null:
			visuals.remove(trails)
		remove()
		return
	if frame < 0xF:
		scale_xz = PsxMath.lerp_int(target_xz / 3, target_xz, 0, 0xF, frame)
		scale_y = PsxMath.lerp_int(target_y / 3, target_y, 0, 0xF, frame)
	elif frame < 0x37:
		scale_xz = target_xz
		scale_y = target_y
	else:
		scale_xz = PsxMath.lerp_int(target_xz, PsxMath.div(target_xz * 10, 100), 0x37, END, frame)
		scale_y = PsxMath.lerp_int(target_y, PsxMath.div(target_y * 10, 100), 0x37, END, frame)
	psx_rotation.y = PsxMath.s16(psx_rotation.y + 0x32)
	frame += 1


func draw(view: BattleVisualsView) -> void:
	view.render_tmd("buff", OBJECT, PsxMath.translation(ctx.bone_matrix(entity, 0)), psx_rotation,
			Vector3i(scale_xz, scale_y, scale_xz))
