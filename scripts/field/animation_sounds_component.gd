@tool
class_name AnimationSoundsComponent
extends Node
## An entity's animation sound events (specs/scenes.md §4.1): the AnimationSounds logic of its
## model, as a child node of the entity scene. The entity hands it the model's glTF JSON and its
## AnimationPlayer after each advance; `sound` is emitted for the events passed (the entity decides
## whether to play them: on screen, its VAB slot).

signal sound(bank: int, value: int)

var events: AnimationSounds


## The model's glTF JSON (its animations' `events`).
func set_model(gltf: Variant) -> void:
	events = AnimationSounds.new(gltf)
	events.sound.connect(func(bank: int, value: int): sound.emit(bank, value))


## A restarted animation plays its events again.
func restart() -> void:
	if events != null:
		events.restart()


func update(player: AnimationPlayer) -> void:
	if events != null:
		events.update(player)
