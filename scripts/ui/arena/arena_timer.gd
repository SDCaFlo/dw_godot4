extends ArenaHudPiece
## The arena's timer (STD_addFighterCounter, STD_renderFighterCounter -> STD_renderCounterDigits(-0xD,
## -0x61, 2, STD_TIMER, 3), std_main.c:2867-2945): two side pieces and the digits from the STDTIM
## page (832, 0) (time_up, palette 0: GetClut(0x10, 0x1E0)), on TIME.TIM's frame (GetTPage(1, 0,
## 0x2C0, 0), GetClut(0x200, 0xFF)). The countdown itself is ArenaMatch's (STD_tickFighterCounter).

const PAGE := "stdtim/02_time_up"
const FRAME := "tim_files/STDDAT/TIME"
const CLUT := 480
const FRAME_CLUT := 255
const X := -0xD
const Y := -0x61


func on_visual(kind: String, args: Array) -> void:
	if kind == "timer":
		shown = bool(args[0])


func build() -> void:
	var added := [
		ft4(PAGE, CLUT, 0x78, 0x30, 8, 0x12, -0x1C, -0x63),
		ft4(PAGE, CLUT, 0x88, 0x30, 8, 0x12, 0x14, -0x63),
	]
	var digits := digit_prims(int(session.timer), 2, X, 14,
			func(d: int, x: int) -> Dictionary: return ft4(PAGE, CLUT, d * 12, 0x30, 0xC, 0xF, x, Y))
	digits.reverse()
	added.append_array(digits)
	added.append(ft4(FRAME, FRAME_CLUT, 0, 0x78, 0x42, 0x1D, -0x21, -0x68))
	added.reverse()
	prims = added
