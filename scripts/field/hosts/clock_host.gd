class_name ClockHost
extends Node
## The game clock while the field is played (specs/clock.md, specs/scenes.md §4.2): addClock
## (clock.c:90) and its HUD, the day / evening / night changes of the map. Ticked by the field's
## frame order (Field._frame).

## Set by the field before start.
var field_map: FieldMap

var clock: Clock
## renderGameClock's HUD; the field puts it into the HUD.
var hud: ClockHud


func start() -> void:
	clock = Clock.new()
	clock.name = "Clock"
	clock.music = Sound.music
	add_child(clock)
	clock.time_of_day_changed.connect(field_map.set_time_of_day)
	clock.daytime_transition.connect(field_map.start_daytime_transition)
	hud = ClockHud.new()
	hud.name = "ClockHud"
	hud.clock = clock
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)


## The clock and playtime objects, the clock's slide, then the map's daytime fade.
func tick() -> void:
	if clock == null:
		return
	clock.tick()
	hud.tick()
	field_map.tick_daytime_transition()
