class_name MapEffects
extends Node
## The map's screen effects (specs/map_events.md §3.2, §4.2.2): Meramon's shake (map.c:5472-5541),
## Ninjamon's sprites (overworld.c:777-830) and Monochromon's mood bubble (script_common.c:1220,
## 3038), started by routines 0x22, 0x26 and 0x1C (script_interp.c:1783, 1814, 1838). The C never
## removes them on a map change (unloadMap, map.c:4446).

var shake := MeramonShake.new()
var ninjamon := NinjamonEffect.new()
var bubble := MoodBubble.new()

var field_map: FieldMap
## The script entities (script value 0xF7 -> the bubble's entity).
var interpreter: ScriptInterpreter
var game_state: Node

var shake_running := false
var ninjamon_running := false
## The bubble's last render: [{"offset", "scale"}] per render object (MoodBubble.render).
var bubble_draws: Array = []
## The entity the bubble is drawn at; null when off the map.
var bubble_entity: Node3D = null


## createMeramonShake (map.c:5472), routine 0x22.
func start_meramon_shake() -> void:
	shake.start(Vector2i(field_map.offset_shake))
	shake_running = true


## createNinjamonEffect (overworld.c:777), routine 0x26.
func start_ninjamon() -> void:
	ninjamon.start(field_map.overlays.store_positions(0, NinjamonEffect.COUNT))
	ninjamon_running = true


## createMonochromonMoodBubble (script_common.c:3038), routine 0x1C: entity script value 0xF7, mood
## script value 0xF8.
func create_mood_bubble() -> void:
	var entity := interpreter.entity_for_script_id(game_state.script_value(0xF7))
	bubble.create(entity != null, game_state.script_value(0xF8))


## One game frame, after MapPropsView.render (port-only place: the C ticks the shake with the tick
## objects and the other two with the render objects, in the same frame).
func tick() -> void:
	if shake_running:
		# tickMeramonShake (map.c:5482): DRAWING_OFFSET_X += the step (S5).
		field_map.set_offset_shake(field_map.offset_shake + Vector2(shake.tick(), 0))
		if shake.done:
			# map.c:5537 (S6): the saved offsets back. stand-in: the port's offset follows the
			# scroll, so only the shake part is restored.
			field_map.set_offset_shake(Vector2(shake.saved_offset))
			shake_running = false
	if ninjamon_running:
		# renderNinjamonEffect (overworld.c:801), S8.
		var done := ninjamon.tick()
		field_map.overlays.set_positions(ninjamon.positions, 0, NinjamonEffect.ORDER)
		if done:
			field_map.overlays.set_flag(0, 1, NinjamonEffect.COUNT)
			ninjamon_running = false
	# renderMonochromonMoodBubble (script_common.c:1220): the entity read each frame (S11).
	bubble_entity = interpreter.entity_for_script_id(game_state.script_value(0xF7))
	bubble_draws = bubble.render(bubble_entity != null)
