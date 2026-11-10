class_name ConverterProcess
extends RefCounted
## Runs dw_convert (or any command) without blocking the game: two threads read its stdout and
## stderr line by line, the owner calls poll() every frame, which emits the lines and, at the
## end, the exit code (specs/launcher.md §3).

signal line(text: String)
signal finished(exit_code: int)

var pid := -1
var _threads: Array[Thread] = []
var _mutex := Mutex.new()
var _lines: PackedStringArray = []
var _open := 0
var _done := false
var _killed := false


## Starts command[0] with command[1..] + args. False if it couldn't start.
func start(command: PackedStringArray, args: PackedStringArray) -> bool:
	var all := command.slice(1)
	all.append_array(args)
	var proc := OS.execute_with_pipe(command[0], all)
	if proc.is_empty():
		return false
	pid = proc["pid"]
	_open = 2
	for pipe in [proc["stdio"], proc["stderr"]]:
		var t := Thread.new()
		t.start(_read.bind(pipe))
		_threads.append(t)
	return true


func running() -> bool:
	return pid != -1 and not _done


## Stops the process (Cancel).
func kill() -> void:
	if running():
		_killed = true
		OS.kill(pid)


## Emits the lines read since the last call; when both pipes are closed and the process has
## ended, emits finished once (exit code -1 if it was killed).
func poll() -> void:
	_mutex.lock()
	var lines := _lines
	_lines = PackedStringArray()
	var open := _open
	_mutex.unlock()
	for l in lines:
		line.emit(l)
	if pid == -1 or _done or open > 0 or OS.is_process_running(pid):
		return
	_done = true
	for t in _threads:
		t.wait_to_finish()
	finished.emit(-1 if _killed else OS.get_process_exit_code(pid))


func _read(pipe: FileAccess) -> void:
	while true:
		var text := pipe.get_line()
		if text == "" and pipe.get_error() != OK:
			break
		_mutex.lock()
		_lines.append(text.strip_edges(false, true))
		_mutex.unlock()
	_mutex.lock()
	_open -= 1
	_mutex.unlock()
