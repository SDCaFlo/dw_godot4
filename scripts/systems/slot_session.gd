class_name SlotSession
extends RefCounted
## The slot session of a Bonus Try (TRN_startSlotSession, TRN_tickSlotSession, TRN_getSlotSessionResult;
## trn/trn_slots.c, trn/trn_hud.c:345; specs/training.md §7.2): a small object a station starts. It
## opens the machine in box 3, waits for its payout and for the box to close, and then holds the
## payout (5, 20, 40 or 100) as its result. The station reads `result()`; −1 until then.
##
## `box` is the UI part (TrainingSlotsBox), duck-typed:
##   open(machine: SlotMachine, mode: int)   opens box 3 with the machine, which the box ticks
##   is_free() -> bool                       box 3 is closed (UI_BOX_DATA[3].state == 0)
## Without a box the session treats it as free, and nothing ticks the machine.

const STATE_OPEN := 0
const STATE_WAIT_MACHINE := 1
const STATE_WAIT_BOX := 2

var machine := SlotMachine.new()
var box: Object
## The session object is in the list (addObject … removeObject).
var active := false
## MAIN_D_801353A0: result, state, stat, payout.
var state := 0
var stat := 0
var payout := -1
var _result := -1


## The GameData node and the sound for the machine (playSound(8, id)).
func configure(game_data: Node, play: Callable) -> void:
	machine.data = game_data
	machine.sound = play


## TRN_startSlotSession(stat): `mode` is the multiplier's mode of the station's stat.
func start(mode: int) -> void:
	_result = -1
	state = STATE_OPEN
	stat = mode
	active = true


## TRN_getSlotSessionResult.
func result() -> int:
	return _result


## TRN_tickSlotSession.
func tick() -> void:
	if not active:
		return
	match state:
		STATE_OPEN:
			machine.open(stat)
			if box != null:
				box.open(machine, stat)
			state = STATE_WAIT_MACHINE
		STATE_WAIT_MACHINE:
			payout = machine.result
			if payout != -1:
				state = STATE_WAIT_BOX
		STATE_WAIT_BOX:
			if box == null or box.is_free():
				_result = payout
				active = false
