class_name SlotMachine
extends RefCounted
## The training slot machine of the Bonus Try (trn/trn_slots.c: TRN_createSlotMachineBox,
## TRN_startSlotSpin, TRN_tickSlotMachine, TRN_chooseReelStop, and the numbers of
## TRN_renderSlotMachine; specs/training.md §7.3-7.5). Logic only: the box (a UI part) ticks it
## with the pad's ✕ while box 3 is open and draws `rows(i)`. The reels, the assist draw, the
## symbols and the payouts are the data table systems/slot_machine (GameData.slot_machine()).

const REELS := 3
const STRIP := 13
## The reels' spin speed; `>> 6` is the pixels a frame (16).
const SPIN_SPEED := 0x400
const SPEED_SHIFT := 6
## A symbol is 32 pixels tall; a reel scrolls this far before the next symbol comes in.
const SYMBOL_HEIGHT := 0x20
## TRN_tickSlotMachine's states: waiting, spinning (1-4: the state minus one reels were told to stop),
## the payout, closing.
const STATE_WAITING := 0
const STATE_SPINNING := 1
const STATE_LAST_REEL := 4
const STATE_PAYOUT := 5
const STATE_CLOSING := 6
## The payout shows for 30 frames, or until ✕.
const RESULT_FRAMES := 0x1E
## playSound(8, …): the spin starts, ✕ stops a reel, a reel stops.
const SOUND_START := 6
const SOUND_PRESS := 7
const SOUND_STOP := 8
## The render (TRN_renderSlotMachine): the windows at x = REEL_STEP * i - REEL_STEP, the first row
## starts at ROW_ORIGIN, the window shows y from WINDOW_TOP to WINDOW_BOTTOM (centred coordinates),
## and the symbols' pictures start at v = SYMBOL_V.
const REEL_STEP := 41
const ROW_ORIGIN := -0x7A
const WINDOW_TOP := -0x4A
const WINDOW_BOTTOM := -9
const SYMBOL_V := 0xD8
const ROWS := 4
## The settled reel is drawn 2 lower instead of at its speed's step.
const SETTLE_STEP := 2

## The GameData node (an autoload's name isn't there in -s tests).
var data: Node
## Called with the id of every playSound(8, id) of the machine.
var sound := Callable()

## SlotMachine.state, reelPos[3], scrollY[3], spinSpeed[3], stopSteps[3], targetSymbol[3],
## settling[3] (the render only), assist, stat (the multiplier's mode), autoStart, resultTimer,
## payout, result (−1 until it is paid out).
var state := 0
var reel_pos: Array[int] = [0, 0, 0]
var scroll_y: Array[int] = [0, 0, 0]
var spin_speed: Array[int] = [0, 0, 0]
var stop_steps: Array[int] = [0, 0, 0]
## Not reset when the machine opens (the C leaves it): reels 0 and 1 set it before reel 2 reads it.
var target: Array[int] = [0, 0, 0]
var settling: Array[int] = [0, 0, 0]
var assist := 0
var stat := 0
var auto_start := -1
var result_timer := 0
var payout := -1
var result := -1

var _table := {}


## TRN_createSlotMachineBox's part for the machine (not the box): the assist and the reels' start.
func open(stat_mode: int) -> void:
	_table = data.slot_machine() if data != null else {}
	result = -1
	payout = -1
	state = STATE_WAITING
	stat = stat_mode
	auto_start = -1
	var draw: Array = _table["assist_draw"]
	assist = int(draw[Rng.rand() % draw.size()])
	for i in REELS:
		reel_pos[i] = Rng.rand() % STRIP
		scroll_y[i] = 0
		spin_speed[i] = 0
		settling[i] = 0


## TRN_startSlotSpin: the station calls it when the partner reaches its point.
func start_spin() -> void:
	auto_start = 0


## The box must close now: state 6 (removeAnimatedUIBox + closeBox(0) are the box's).
func closing() -> bool:
	return state == STATE_CLOSING


func _play(id: int) -> void:
	if sound.is_valid():
		sound.call(id)


## The symbol on reel `i` at the strip index `k`.
func _symbol_at(i: int, k: int) -> int:
	return int(_table["reels"][i][k])


## The symbol on the pay line of reel `i` (TRN_D_8008F1AC[i][reelPos[i]]).
func line_symbol(i: int) -> int:
	return _symbol_at(i, reel_pos[i])


## `j` symbols ahead of the line on reel `i` (the strip scrolls down, towards lower indices):
## TRN_D_8008F1AC[i][(reelPos[i] + 13 - j) % 13]. Without help, the reel stops on next_symbol(i, 1).
func next_symbol(i: int, j: int) -> int:
	return _symbol_at(i, (reel_pos[i] + STRIP - j) % STRIP)


## The symbol's record of the table (its stat, or the jackpot flag), or {}.
func symbol_info(symbol: int) -> Dictionary:
	for s in _table["symbols"]:
		if int(s["symbol"]) == symbol:
			return s
	return {}


## The reel's step this frame: spinSpeed >> 6.
func _step(i: int) -> int:
	return spin_speed[i] >> SPEED_SHIFT


## TRN_tickSlotMachine. `confirm_pressed`: ✕ pressed this frame (POLLED_INPUT & ~POLLED_INPUT_PREVIOUS).
func tick(confirm_pressed: bool) -> void:
	match state:
		STATE_WAITING:
			if confirm_pressed or auto_start >= 0:
				state = STATE_SPINNING
				for i in REELS:
					spin_speed[i] = SPIN_SPEED
					stop_steps[i] = 0
				_play(SOUND_START)
		STATE_SPINNING, 2, 3, STATE_LAST_REEL:
			_spin(confirm_pressed)
		STATE_PAYOUT:
			_pay(confirm_pressed)
		STATE_CLOSING:
			result = payout


## States 1-4: the three reels one frame.
func _spin(confirm_pressed: bool) -> void:
	var stopping := state - 1
	for i in REELS:
		settling[i] = 0
		scroll_y[i] += _step(i)
		if scroll_y[i] == SYMBOL_HEIGHT:
			scroll_y[i] -= 1
		if scroll_y[i] >= SYMBOL_HEIGHT:
			scroll_y[i] -= SYMBOL_HEIGHT
			reel_pos[i] = (reel_pos[i] + STRIP - 1) % STRIP
			if i < stopping:
				if stop_steps[i] > 0:
					stop_steps[i] -= 1
				else:
					scroll_y[i] = 0
					spin_speed[i] = 0
					_play(SOUND_STOP)
		if stopping == i and confirm_pressed:
			choose_reel_stop(i)
		# Settling, for the render: the step that would bring the next symbol in is the reel's last.
		var t := scroll_y[i] + _step(i)
		if t == SYMBOL_HEIGHT:
			t -= 1
		if t >= SYMBOL_HEIGHT:
			if i < stopping and stop_steps[i] <= 0:
				settling[i] += 1
			elif i == stopping and stop_steps[i] <= 0 and confirm_pressed:
				settling[i] += 1
	if state < STATE_LAST_REEL and confirm_pressed:
		_play(SOUND_PRESS)
		state += 1
	if spin_speed[0] == 0 and spin_speed[1] == 0 and spin_speed[2] == 0:
		result_timer = 0
		state += 1


## State 5: the payout on its first frame, then 30 frames or ✕.
func _pay(confirm_pressed: bool) -> void:
	if result_timer == 0:
		var kind := _payout_kind()
		var p: Dictionary = _table["payouts"][kind]
		payout = int(p["payout"])
		_play(int(p["sound"]))
	elif result_timer >= RESULT_FRAMES or confirm_pressed:
		state += 1
	result_timer += 1


## Which payout the line pays: "jackpot" (three of the jackpot symbol), "own_stat" (three of the
## station's stat), "other_match", or "none".
func _payout_kind() -> String:
	var s := line_symbol(0)
	if s != line_symbol(1) or s != line_symbol(2):
		return "none"
	var info := symbol_info(s)
	if info.get("jackpot", false):
		return "jackpot"
	if info.get("stat", "") == Training.MODE_NAMES[stat]:
		return "own_stat"
	return "other_match"


# --- TRN_chooseReelStop ---------------------------------------------------------------------------

## TRN_chooseReelStop(i): the assist decides where reel `i` stops (`stop_steps`) and what it aims at
## (`target`). The C shares `shift` and `scan` between the reels with gotos.
func choose_reel_stop(i: int) -> void:
	match i:
		0:
			match assist:
				0:
					target[i] = next_symbol(i, 1)
				1:
					_shift(i)
				2:
					_scan(i)
		1:
			match assist:
				0:
					target[i] = next_symbol(i, 1)
				1:
					if target[0] == _table_jackpot():
						_shift(i)
					else:
						_match(i)
				2:
					if target[0] == _table_jackpot():
						_scan(i)
					else:
						target[i] = -2
		2:
			match assist:
				0:
					if target[0] != target[1] or target[0] != next_symbol(i, 1):
						return
					stop_steps[i] = Rng.rand() % 2 + 1
				1:
					if target[0] != target[1]:
						return
					if target[0] != _table_jackpot():
						_match(i)
					elif next_symbol(i, 1) == _table_jackpot():
						stop_steps[i] = Rng.rand() % 2 + 1
				2:
					if target[0] == _table_jackpot() and target[1] == _table_jackpot():
						_scan(i)
					else:
						target[i] = -3


## The jackpot symbol: the one the table marks.
func _table_jackpot() -> int:
	for s in _table["symbols"]:
		if s.get("jackpot", false):
			return int(s["symbol"])
	return -1


## `shift`: the reel stops where it is; it aims at the symbol on the line (or the next one while
## it is between two).
func _shift(i: int) -> void:
	target[i] = next_symbol(i, 0 if scroll_y[i] == 0 else 1)


## `scan`: the first of the next two symbols that is the jackpot; the reel rolls on to it.
func _scan(i: int) -> void:
	var jackpot := _table_jackpot()
	for j in range(1, 3):
		if next_symbol(i, j) == jackpot:
			stop_steps[i] = j - 1
			target[i] = jackpot
			return
	stop_steps[i] = 0
	target[i] = -1


## The match search of reel 1 (assist 1) and reel 2: the first of the next two symbols equal to
## reel 0's; found, the reel rolls on to it; else it aims at −2.
func _match(i: int) -> void:
	for j in range(1, 3):
		if next_symbol(i, j) == target[0]:
			stop_steps[i] = j - 1
			target[i] = target[0]
			return
	stop_steps[i] = 0
	target[i] = -2


# --- TRN_renderSlotMachine ------------------------------------------------------------------------

## The x of reel `i`'s window and symbols (centred coordinates).
static func reel_x(i: int) -> int:
	return REEL_STEP * i - REEL_STEP


## The four rows of reel `i` as the render sorts them, top to bottom:
## {symbol, u, y, v, h, visible, top}. `top` is the row's y before clipping; `y`, `v` and `h` the
## sprite's top, its picture row and its height after clipping to the window (y WINDOW_TOP … −10);
## `visible`: the sprite is drawn at all (y < −9 and its bottom reaches the window). A symbol's
## picture starts at u = (symbol − 1) * 32. The window sprite (32 x 64 at (reel_x − 16, −0x4A)) is
## the box's.
func rows(i: int) -> Array:
	var y := scroll_y[i] + ROW_ORIGIN
	if settling[i] == 0:
		y += _step(i)
		if scroll_y[i] + _step(i) == SYMBOL_HEIGHT:
			y -= 1
	else:
		y += SETTLE_STEP
	var out := []
	for k in ROWS:
		var symbol := _symbol_at(i, (reel_pos[i] + 11 + k) % STRIP)
		var row := {"symbol": symbol, "u": (symbol - 1) << 5, "top": y}
		if y < WINDOW_TOP:
			row["y"] = WINDOW_TOP
			row["v"] = 0x8E - y
			row["h"] = SYMBOL_HEIGHT - (row["v"] - SYMBOL_V)
		elif y + SYMBOL_HEIGHT >= WINDOW_BOTTOM:
			row["y"] = y
			row["v"] = SYMBOL_V
			row["h"] = SYMBOL_HEIGHT - (y + 0x2A)
		else:
			row["y"] = y
			row["v"] = SYMBOL_V
			row["h"] = SYMBOL_HEIGHT
		row["visible"] = y < WINDOW_BOTTOM and y + SYMBOL_HEIGHT >= WINDOW_TOP + 1
		out.append(row)
		y += SYMBOL_HEIGHT
	return out
