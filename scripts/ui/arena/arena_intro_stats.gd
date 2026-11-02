extends ArenaHudPiece
## The intro's stats (STD_drawStatLabelText, STD_addIntroStats, STD_renderIntroStats,
## STD_renderIntroStatBar, STD_renderIntroStatNumber; std_main.c:1609-1748, 2009-2060): six rows 16
## apart from y -28, the label (renderString from the text area's row i * 12, layer 0), a green bar
## value * 100 / STD_STAT_BAR_LIMITS (at least 1 px) at (-0x32, i * 16 - 0x1A), and, once every value
## has counted up, the numbers (4 places, 12 apart from x 52, STDTIM page (832, 0) palette 0, 12 x 12 at
## u = digit * 12, v 32). The counting (and its sound) is ArenaMatch's (STD_tickIntroStats).

const PAGE := "stdtim/02_time_up"
const CLUT := 480
const BAR_COLOR := Color8(0x50, 0xC8, 0x50)
## STD_drawStatLabelText: "ＨＰ", "ＭＰ" (std_main.c:717, 719), MAIN_D_80124C0C[2..5] (the stat names),
## MAIN_D_80124C54 at row 0xF0.
const HP_TEXT := "ＨＰ"
const MP_TEXT := "ＭＰ"
const STAT_TEXT := ["STR_STAT_LABEL_OFFENSE", "STR_STAT_LABEL_DEFENSE", "STR_STAT_LABEL_SPEED", "STR_STAT_LABEL_BRAINS"]

var entity := -1


func on_visual(kind: String, args: Array) -> void:
	match kind:
		"stat_labels":
			_draw_labels()
		"intro_stats":
			entity = int(args[0])
			shown = bool(args[1])


## STD_drawStatLabelText (1609): into the text area, once per match intro.
func _draw_labels() -> void:
	if text_area == null or data == null:
		return
	text_area.clear_all()
	text_area.draw_string(HP_TEXT, 0, 0)
	text_area.draw_string(MP_TEXT, 0, 12)
	for i in STAT_TEXT.size():
		text_area.draw_string(data.text(STAT_TEXT[i]), 0, (i + 2) * 12)
	text_area.draw_string(data.text("STR_BITS"), 0, 0xF0)


func build() -> void:
	if not session.intro_stats_active or data == null:
		return
	var limits: Array = data.system("arena")[0]["intro"]["stat_bar_limits"]
	var values: Array = session.intro_stats
	var s: Dictionary = world.stats(int(session.intro_stats_entity))
	var target := [int(s["current"]["hp"]), int(s["current"]["mp"]), int(s["base"]["offense"]),
			int(s["base"]["defense"]), int(s["base"]["speed"]), int(s["base"]["brains"])]
	var done := true
	for i in 6:
		if int(values[i]) != target[i]:
			done = false
	var labels := []
	var layer3 := []
	for i in 6:
		var label := text(0, -100, i * 16 - 28, 48, 12, 0, i * 12)
		label["kind"] = "label"
		labels.append(label)
		var w := maxi(int(values[i]) * 100 / int(limits[i]), 1)
		var bar := fill(Rect2i(-0x32, i * 16 - 0x1A, w, 8), BAR_COLOR)
		bar.merge({"kind": "bar", "stat": i})
		layer3.append(bar)
	if done:
		for i in 6:
			var digits := digit_prims(int(values[i]), 4, 52, 12,
					func(d: int, x: int) -> Dictionary: return ft4(PAGE, CLUT, d * 12, 32, 12, 12, x, i * 16 - 28))
			digits.reverse()
			for p in digits:
				p.merge({"kind": "digit", "stat": i})
			layer3.append_array(digits)
	layer3.reverse()
	labels.reverse()
	# Layer 3 behind the labels' layer 0.
	prims = layer3 + labels
