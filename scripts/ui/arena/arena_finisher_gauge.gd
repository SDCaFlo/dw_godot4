extends ArenaHudPiece
## The partner's finisher gauge (STD_renderFighterHPBar(0), STD_renderHPBarDigits,
## STD_renderFinisherReadyIcon, std_hud.c:906-997): only fighter 0's is drawn (STD_renderFighterStatusBars
## calls it for id 0 only, :1092-1093), and only while fighting (GAME_STATE 4). The segments
## (systems/arena finisher_gauge: u, w, x) pulse with STD_FINISHER_PULSE when they change; full, the
## gauge grows two more segments and the ready icon. Quirk kept: the icon's box is at x -0x58 whatever the
## id. Its counters are this piece's (the C keeps them in the render), drawn on layer 8.

const ID := 0
## The segments' x: SEGMENT_X - 0x8D for fighter 0 (+ 0x37 for 1, never drawn); y -0x4F, 15 high.
const SEGMENT_X0 := -0x8D
const SEGMENT_Y := -0x4F
const SEGMENT_V := 0x9D
## setEntityTextDigit(prim, 0x100, 0x1EC) / (0x100, 0x1E2): BI_IN palettes 12 and 2.
const SEGMENT_CLUT := 0x1EC
const ICON_CLUT := 0x1E2
const ICON_X := -0x56
const ICON_Y := -0x4B
const BOX := Rect2i(-0x58, -0x4C, 0x29, 0xB)

var segments := 0
var pulse_frame := 0
var brightness := 0
var full_frames := 0
var finisher_ready := false


func on_visual(kind: String, args: Array) -> void:
	if kind == "status_bars":
		shown = bool(args[0])
		if shown:
			segments = 0
			pulse_frame = 0
			full_frames = 0
			finisher_ready = false


func build() -> void:
	if battle == null or battle.fighters.is_empty() or battle.game_state != ArenaMatch.GAME_FIGHT:
		return
	var g: Dictionary = data.system("arena")[0]["finisher_gauge"] if data != null else {}
	if g.is_empty():
		return
	var f: BattleFighter = battle.fighters[ID]
	var n := f.finisher_progress * 6 / f.finisher_goal if f.finisher_goal != 0 else 0
	if segments != n:
		pulse_frame = 0
		segments = n
	brightness = int(g["pulse"][pulse_frame])
	if pulse_frame < 0xB:
		pulse_frame += 1
	var added := []
	var finishing := battle.current_command == Battle.CMD_FINISHER
	var drawn := n
	if n == 6:
		if full_frames < 0xA:
			full_frames += 1
		if full_frames >= 3:
			drawn += 1
		if full_frames >= 5:
			drawn += 1
			added.append_array(_ready_icon(finishing))
			if full_frames == 0xA:
				finisher_ready = true
				pulse_frame %= 0xB
	var lit := BattleHudDraw.grey(brightness)
	for i in drawn:
		var tint := lit if ((n - 1) == i or finisher_ready) and not finishing else Color.WHITE
		var p := ft4(BattleHudDraw.BI_IN, SEGMENT_CLUT, int(g["segment_u"][i]), SEGMENT_V, int(g["segment_w"][i]), 15,
				int(g["segment_x"][i]) + SEGMENT_X0, SEGMENT_Y, 0, 0, tint)
		p.merge({"kind": "segment", "index": i, "fighter": ID})
		added.append(p)
	added.reverse()
	prims = added


## STD_renderFinisherReadyIcon: the icon (added first) then the box (GsSortBoxFill, semi-transparent).
func _ready_icon(finishing: bool) -> Array:
	var on := finisher_ready and not finishing
	var icon := ft4(BattleHudDraw.BI_IN, ICON_CLUT, 0x80, 0x88, 37, 9, ICON_X, ICON_Y, 0, 0,
			BattleHudDraw.grey(brightness) if on else Color.WHITE)
	icon.merge({"kind": "ready", "fighter": ID})
	var level := brightness if on else 0x80
	var box := fill(BOX, Color8(level, level, level), true)
	box["fighter"] = ID
	return [icon, box]
