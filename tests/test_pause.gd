extends SceneTree
## The pause (scripts/systems/pause.gd, scripts/field/hosts/pause_host.gd) against specs/pause.md:
##   godot --headless --path . -s res://tests/test_pause.gd
## Exits 1 if a check fails.

var _failed := 0
var _run := 0
var _pad := 0
var _sounds: Array = []


class SoundStub:
	extends Node
	var calls: Array

	func play_sound(slot: int, value: int) -> int:
		calls.append([slot, value])
		return 0


var _started := false


## Runs in the first frame: the autoloads and the host need the tree.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run_all()
	return false


func _run_all() -> void:
	_gate()
	_toggle()
	_blocked_keeps_previous()
	_host()
	_game_loop_stops()
	print("%s: pause checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _run])
	quit(1 if _failed else 0)


func _check(ok: bool, what: String) -> void:
	_run += 1
	if not ok:
		_failed += 1
		print("FAIL: ", what)


## handlePause's early returns (utils2.c:408-413).
func _gate() -> void:
	_check(not Pause.is_blocked(true, 0, true, false), "field, no script, time running: the pause works")
	_check(Pause.is_blocked(true, 3, true, false), "field, a script has taken over (value 0 = 3): blocked")
	_check(Pause.is_blocked(true, 0, false, false), "field, game time stopped: blocked")
	_check(Pause.is_blocked(true, 0, true, true), "field, fading to black: blocked")
	_check(not Pause.is_blocked(false, 3, false, false), "battle / match: the script and the time don't matter")
	_check(Pause.is_blocked(false, 0, true, true), "battle / match, fading to black: blocked")


## START newly down toggles; the box opens once and closes on the next handle.
func _toggle() -> void:
	var p := Pause.new()
	var created := [0]
	var removed := [0]
	p.box_created.connect(func() -> void: created[0] += 1)
	p.box_removed.connect(func() -> void: removed[0] += 1)
	_check(not p.handle(0, false), "no START: not paused")
	_check(p.handle(Pad.START, false), "START pressed: paused")
	_check(created[0] == 1 and p.box_visible == 1 and p.box_shown, "the box opens (PAUSE_BOX_VISIBLE 1)")
	_check(p.poll(Pad.START), "START still held in the wait loop: still paused")
	_check(p.poll(0), "released: still paused")
	_check(not p.poll(Pad.START), "START again: the wait loop ends")
	_check(not p.handle(Pad.START, false), "next frame, START still held: no new pause")
	_check(removed[0] == 1 and p.box_visible == 0 and not p.box_shown, "the next handle removes the box")
	p.remove_box()
	_check(removed[0] == 1, "removePauseBox with no box does nothing")
	_check(not p.handle(Pad.START | Pad.CROSS, false), "held START with other buttons: still no edge")
	_check(p.handle(Pad.CROSS, false) == false and p.handle(Pad.START, false), "released then pressed: paused again")


## A blocked frame returns before PadRead: PAUSE_INPUT_PREVIOUS keeps its old value, so START held
## through a script pauses on the first free frame (as in the C).
func _blocked_keeps_previous() -> void:
	var p := Pause.new()
	p.handle(0, false)
	_check(not p.handle(Pad.START, true), "START during a script: no pause")
	_check(p.input_previous == 0, "the blocked frame didn't read the pad")
	_check(p.handle(Pad.START, false), "START still held when the script ends: paused")


func _host() -> void:
	var boxes := UIBoxes.new()
	root.add_child(boxes)
	var sound := SoundStub.new()
	root.add_child(sound)
	var host := PauseHost.new()
	host.boxes = boxes
	host.sound = sound
	host.read_pad = func() -> int: return _pad
	root.add_child(host)
	_check(host.process_mode == Node.PROCESS_MODE_ALWAYS, "the host runs while the tree is paused")

	_pad = 0
	host.frame(true, false)
	_check(not paused and not host.is_frozen(), "no START: the game goes on")
	_pad = Pad.START
	host.frame(true, false)
	var b: UIBoxes.Box = boxes.boxes[Pause.BOX_ID]
	_check(paused and host.is_frozen(), "START: the tree is paused")
	_check(b.registered and not b.animated and b.color == Pause.BOX_COLOR and b.final == Pause.BOX_RECT,
			"box 5 is static, colour 1, at (-26, -14, 56, 24)")
	_check(b.drawn == UIBoxes.DRAWN_STATIC, "pauseFrame drew the box before the freeze")
	_check(sound.calls == [[0, 3]], "playSound(0, 3) when it opens")
	host._process(0.016)
	_check(paused, "START held: still frozen")
	_pad = 0
	host._process(0.016)
	_pad = Pad.START
	host._process(0.016)
	_check(not paused and not host.is_frozen(), "START again: the game goes on")
	_check(b.registered, "the box stays for the next frame")
	host.frame(true, false)
	_check(not b.registered, "the next frame's handlePause removes the box")
	_check(sound.calls == [[0, 3], [0, 3]], "playSound(0, 3) when it closes")
	_check(not paused, "START still held: no second pause")

	_pad = 0
	host.frame(true, false)
	_pad = Pad.START
	host.frame(true, true)
	_check(not paused and not b.registered, "blocked: no pause")

	# A loop ending while the box shows (removePauseBox after BTL_battleMain's loop).
	_pad = 0
	host.frame(true, false)
	_pad = Pad.START
	host.frame(true, false)
	_pad = 0
	host._process(0.016)
	_pad = Pad.START
	host._process(0.016)
	_check(not paused and b.registered, "unpaused, the box still up")
	host.frame(false, false)
	_check(not b.registered and host.pause.box_visible == 0, "outside the loop the box closes")

	host.free()
	sound.free()
	boxes.free()


## GameLoop runs no more frames once the pause froze the tree, even in a catch-up step.
func _game_loop_stops() -> void:
	var loop: Node = root.get_node("GameLoop")
	var count := [0]
	var on_frame := func() -> void:
		count[0] += 1
		paused = true
	loop.frame.connect(on_frame)
	var was_paused: bool = loop.paused
	loop.paused = false
	loop._process(3.0 / loop.FRAME_RATE)
	_check(count[0] == 1, "one frame ran, then the loop stopped (ran %d)" % count[0])
	loop.frame.disconnect(on_frame)
	paused = false
	loop.paused = was_paused
