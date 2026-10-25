class_name AnimationSounds
extends RefCounted
## A model's animation sound events (renderAnimation's 0x4000 instruction, anim.c:336; the asset
## porter's glTF animation extras `events` of type "sound": bank, sound, time): `update(player)`
## after each advance emits `sound` for the events the animation passed since the last update,
## across a loop's wrap too. The entity decides whether to play it (on screen, bank 4 = its slot).

signal sound(bank: int, value: int)

## animation name -> [[time, bank, sound], ...] sorted by time
var _events := {}
var _animation := ""
var _position := -1.0


func _init(gltf: Variant) -> void:
	for animation in (gltf.get("animations", []) if gltf is Dictionary else []):
		var list := []
		for e in animation.get("extras", {}).get("events", []):
			if e.get("type") == "sound":
				list.append([float(e["time"]), int(e["bank"]), int(e["sound"])])
		if not list.is_empty():
			list.sort_custom(func(a, b): return a[0] < b[0])
			_events[animation["name"]] = list


func has_events() -> bool:
	return not _events.is_empty()


## Starts watching from the animation's beginning (a restarted animation plays its events again).
func restart() -> void:
	_animation = ""


func update(player: AnimationPlayer) -> void:
	if player == null:
		return
	var anim_name := String(player.current_animation if player.current_animation != "" else player.assigned_animation)
	var position := player.current_animation_position if player.current_animation != "" else _position
	if anim_name != _animation:
		_animation = anim_name
		_position = -1.0
	var list: Array = _events.get(anim_name, [])
	if list.is_empty():
		_position = position
		return
	if position < _position:
		# wrapped (a loop): the events after the old position, then from the start
		for e in list:
			if e[0] > _position:
				sound.emit(e[1], e[2])
		_position = -1.0
	for e in list:
		if e[0] > _position and e[0] <= position:
			sound.emit(e[1], e[2])
	_position = position
