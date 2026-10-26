class_name TrainingRoutines
extends MenuRoutines
## Builtins 0x07, training, and 0x27, loadTrainingLibrary (script_interp.c:1682-1727, :459-463,
## map.c:5457; specs/training.md §2.1, §3). 0x07 starts the station of the current map for the stat
## in script value 0xFE (its children: TrainingStation scenes) and waits until it is done
## (isTrainingComplete). With no station for them, nothing starts and the script waits, as in the C.
## A child of ScriptRoutines (scenes/script/training_routines.tscn).

const TRAINING := 0x07
const LOAD_LIBRARY := 0x27
var routines: Array = [TRAINING, LOAD_LIBRARY]

const PSTAT_STAT := 0xFE
## 1: Bonus Try (the slot machine, 4d-3).
const PSTAT_SLOTS := 0xF6

var training := Training.new()
var stats_box := TrainingStatsBox.new()
## The station running (its object in the list), or null.
var station: TrainingStation


func configure(routine_host: ScriptRoutines) -> void:
	super.configure(routine_host)
	training.game_state = game_state
	training.data = data
	training.stats_box = stats_box
	stats_box.training = training
	stats_box.boxes = textboxes.boxes
	stats_box.text_area = textboxes.text_area
	stats_box.pad = textboxes.pad
	stats_box.data = data
	stats_box.origin = _partner_on_screen


## getEntityScreenPos(partner, bone 1), centred, for the box to grow from.
func _partner_on_screen() -> Vector2i:
	if ctx.entity_screen_position.is_valid():
		var p = ctx.entity_screen_position.call(ScriptContext.OWNER_PARTNER)
		if p is Vector2i:
			return p
	return Vector2i.ZERO


## The station for a map and stat (the last child listing them, so a mod's station wins).
func station_for(map_id: int, stat_id: int) -> TrainingStation:
	var found: TrainingStation = null
	for child in get_children():
		if child is TrainingStation and child.matches(map_id, stat_id):
			found = child
	return found


func start(routine: int) -> bool:
	if routine == LOAD_LIBRARY:
		training.complete = false
		return false
	var interpreter := host.interpreter
	if interpreter != null:
		training.clock = interpreter.clock
		training.care = interpreter.care
	var found := station_for(ctx.current_screen_id, ctx.read_pstat(PSTAT_STAT))
	if found != null:
		found.training = training
		found.interpreter = interpreter
		found.clouds = host.clouds
		found.pad = textboxes.pad
		found.sound = host.sound
		found.game_state = game_state
		found.data = data
		found.start(ctx.read_pstat(PSTAT_SLOTS) == 1)
		station = found
	return true


func tick(_routine: int) -> void:
	if training.is_training_complete():
		station = null
		ctx.active_instruction = 0


## The station's object, one game frame (the field calls it after the script and the pans).
func tick_objects() -> void:
	if station != null and station.running:
		station.tick()
