extends BattleHudPiece
## The partner's HP and MP bars and the finisher gauge (battle_hud.c:860-1080:
## BTL_tickPartnerStatusBars, BTL_renderPartnerStatusBars, BTL_renderFinisherGauge…). They slide
## in with the command menu (HP first, MP from step 3) and out when it closes. The damage the C's
## draw applies (damageTick, the MP buffer) is the battle's (Battle.apply_damage_buffers).

const STEPS := 7
## The bars' tables (systems/battle_hud): BTL_STATUS_BAR_X (x per slide step),
## BTL_STATUS_BAR_SPRITES (per bar, HP then MP: the frame, the icon, the fill: a 2 x 2 texel
## stretched to the value), BTL_FINISHER_PULSE (the full gauge's brightness cycle).
const BAR_Y := [-0x64, -0x58]
const SEGMENT_U := [0, 6, 10, 18, 22, 30, 38, 43]
const SEGMENT_W := [6, 4, 8, 4, 8, 8, 5, 5]

## BTL_STATUS_BARS_STEP, BTL_HP_BAR_STEP, BTL_MP_BAR_STEP.
var step := 0
var hp_step := 0
var mp_step := 0
## BTL_FINISHER_FULL_FRAMES, _PULSE_FRAME, _BRIGHTNESS, _SEGMENTS, _READY.
var full_frames := 0
var pulse_frame := 0xB
var brightness := 0
var segments := 0
var finisher_ready := false
var shown := true
## The gauge as this frame draws it: segments, ready icon.
var _gauge := 0
var _ready_icon := false


func on_visual(kind: String, args: Array) -> void:
	if kind == "status_bars" and not bool(args[0]):
		shown = false


## BTL_tickPartnerStatusBars, then the gauge's counters of BTL_renderFinisherGauge.
func tick(_pressed: int) -> void:
	if session == null:
		return
	if not session.command_menu_active():
		if step != 0:
			step -= 1
		if mp_step != 0:
			mp_step -= 1
		if step < 5 and hp_step != 0:
			hp_step -= 1
	else:
		if step < STEPS:
			step += 1
		if step != 0 and hp_step < STEPS:
			hp_step += 1
		if step >= 3 and mp_step < STEPS:
			mp_step += 1
	_tick_gauge()
	queue_redraw()


func _tick_gauge() -> void:
	_gauge = 0
	_ready_icon = false
	if step != STEPS or battle == null or battle.fighters.is_empty():
		return
	var f := battle.fighters[0]
	var hp := f.finisher_progress * 6 / f.finisher_goal if f.finisher_goal != 0 else 0
	if segments != hp:
		pulse_frame = 0
		segments = hp
	brightness = int(BattleHudDraw.table(data, "BTL_FINISHER_PULSE")[pulse_frame])
	if pulse_frame < 0xB:
		pulse_frame += 1
	if hp == 6:
		if full_frames < 0xA:
			full_frames += 1
		if full_frames >= 3:
			hp += 1
		if full_frames >= 5:
			hp += 1
			_ready_icon = true
			if full_frames == 0xA:
				finisher_ready = true
				pulse_frame %= 0xB
	_gauge = hp


func _draw() -> void:
	if not shown or battle == null or battle.fighters.is_empty():
		return
	var f := battle.fighters[0]
	var values := [[f.hp(), f.max_hp()], [f.mp(), f.max_mp()]]
	var bar_x := BattleHudDraw.table(data, "BTL_STATUS_BAR_X")
	var bar_sprites := BattleHudDraw.table(data, "BTL_STATUS_BAR_SPRITES")
	if bar_x.size() < 8 or bar_sprites.size() < 6:
		return
	for bar in 2:
		var x0 := int(bar_x[hp_step if bar == 0 else mp_step])
		var y0: int = BAR_Y[bar]
		var cur: int = values[bar][0]
		var fill: int = cur * 50 / values[bar][1] if values[bar][1] != 0 else 0
		# Added fill, icon, frame into one layer: drawn frame, icon, fill; the number last.
		for k in 3:
			var p: Dictionary = bar_sprites[bar * 3 + k]
			var w: int = fill if k == 2 else int(p["w"])
			BattleHudDraw.rect(self, BattleHudDraw.page_896(int(p["clut"])), int(p["u"]), BattleHudDraw.row(int(p["v"])),
					int(p["w"]), int(p["h"]), x0 + int(p["x"]), y0 + int(p["y"]), w, int(p["h"]))
		BattleHudDraw.hud_number(self, 4, x0 + 0x49, y0 - 3, cur)
	_draw_gauge()


## BTL_renderFinisherGaugeSegment / BTL_renderFinisherReadyIcon.
func _draw_gauge() -> void:
	var finishing := battle.current_command == Battle.CMD_FINISHER
	var lit := BattleHudDraw.grey(brightness)
	if _ready_icon:
		var tint := lit if finisher_ready and not finishing else Color.WHITE
		# GsBOXF's colour is the colour itself (not a tint), half-transparent (mode 0).
		var level := brightness if finisher_ready and not finishing else 0x80
		var box := Color8(level, level, level, 128)
		draw_rect(Rect2(BattleHudDraw.CENTRE + Vector2(0x6C, -0x4C), Vector2(0x29, 0xB)), box)
		BattleHudDraw.rect(self, BattleHudDraw.page_896(482), 0x80, BattleHudDraw.row(0x88), 37, 9, 0x6E, -0x4B, 37, 9, tint)
	var f := battle.fighters[0]
	var hp := f.finisher_progress * 6 / f.finisher_goal if f.finisher_goal != 0 else 0
	for i in _gauge:
		var tint := lit if (hp - 1 == i or finisher_ready) and not finishing else Color.WHITE
		BattleHudDraw.rect(self, BattleHudDraw.page_896(492), SEGMENT_U[i], BattleHudDraw.row(0x9D), SEGMENT_W[i], 15,
				SEGMENT_U[i] + 0x37, -0x4F, SEGMENT_W[i], 15, tint)
