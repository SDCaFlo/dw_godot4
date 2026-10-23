class_name PsxAnimator
extends RefCounted
## The original animation state of an entity (startAnimation / tickAnimation, anim.c:201-357;
## specs/partner.md §2.5) over a model's AnimationPlayer, so ported code can read what the C code
## reads: anim_id, frame, frame_count, loop_count, playing (animFlag & 1).
##
## The data comes from the asset porter's glTF animation extras (asset_porter/specs/mmd.md):
## `frame_count`, and `loop` (start / end frame) for endless loops. Endless animations loop in
## Godot; finish_loop() (the original's "loopCount = 1") plays to the end and stops. Loops that
## cover only part of an animation are approximated by looping the whole animation.

const FPS := 20.0
const ENDLESS := 0xFF

var player: AnimationPlayer
var anim_id := -1
## animFrame: 1 .. frame_count.
var frame := 1
var frame_count := 0
## 0xFF while in an endless loop, 1 after finish_loop(), 0 for no loop / loop left.
var loop_count := 0
## animFlag & 1: cleared when the animation has played to its end.
var playing := false

## anim id -> {"frames": int, "loop": bool}
var _info := {}


func _init(animation_player: AnimationPlayer, gltf: Variant) -> void:
	player = animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation in (gltf.get("animations", []) if gltf is Dictionary else []):
		var extras: Dictionary = animation.get("extras", {})
		if extras.has("anim_id") and player.has_animation(animation["name"]):
			_info[int(extras["anim_id"])] = {"name": animation["name"], "frames": int(extras.get("frame_count", 1)),
					"loop": extras.get("loop") != null}


## The model has animation `id` (animTable[id] != 0).
func has(id: int) -> bool:
	return _info.has(id)


## startAnimation: does nothing for an animation the model doesn't have, like the original.
func play(id: int) -> bool:
	if not has(id):
		return false
	var info: Dictionary = _info[id]
	anim_id = id
	frame = 1
	frame_count = info["frames"]
	playing = true
	loop_count = ENDLESS if info["loop"] else 0
	player.get_animation(info["name"]).loop_mode = Animation.LOOP_LINEAR if info["loop"] else Animation.LOOP_NONE
	player.stop()
	player.play(info["name"])
	player.advance(0.0)
	return true


## loopCount = 1 on an endless loop: leave it at its next end and play to the end.
func finish_loop() -> void:
	if loop_count == ENDLESS:
		loop_count = 1
		player.get_animation(_info[anim_id]["name"]).loop_mode = Animation.LOOP_NONE


## Advances the pose by `delta` seconds and updates the state; returns the root motion.
func advance(delta: float) -> Vector3:
	if not playing:
		return Vector3.ZERO
	player.advance(delta)
	var motion := player.get_root_motion_position()
	if not player.is_playing() or player.current_animation_position >= player.current_animation_length:
		frame = frame_count
		playing = false
		if loop_count == 1:
			loop_count = 0
	else:
		frame = mini(int(player.current_animation_position * FPS) + 1, frame_count)
	return motion
