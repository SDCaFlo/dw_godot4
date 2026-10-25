class_name PsxAnimator
extends RefCounted
## The original animation state of an entity (startAnimation / tickAnimation, anim.c:201-357;
## specs/partner.md §2.5) over a model's AnimationPlayer, so ported code can read what the C code
## reads: anim_id, frame, frame_count, loop_count, playing (animFlag & 1).
##
## The data comes from the asset porter's glTF animation extras (asset_porter/specs/mmd.md):
## `frame_count`, and `loop` (start / end frame) for endless loops. A loop over the whole animation
## loops in Godot; a loop over part of it (the tamer holding an item out: anim 5 loops frames 10-11)
## plays once to the loop's end, then wraps back to the loop's start here. finish_loop() (the
## original's "loopCount = 1") plays to the end and stops.

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
## Passes through the end of a looping animation since it started. The C's animFrame equals
## frameCount on the tick of each pass; the port draws several Godot frames per game frame, so a
## game-frame test reads this count instead of catching that one frame (ISSUES.md I-11).
var passes := 0
var _last_position := 0.0

## anim id -> {"name", "frames": int, "loop": bool, "loop_start" / "loop_end": seconds, "partial": bool}
var _info := {}


func _init(animation_player: AnimationPlayer, gltf: Variant) -> void:
	player = animation_player
	player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	for animation in (gltf.get("animations", []) if gltf is Dictionary else []):
		var extras: Dictionary = animation.get("extras", {})
		if extras.has("anim_id") and player.has_animation(animation["name"]):
			var loop = extras.get("loop")
			var info := {"name": animation["name"], "frames": int(extras.get("frame_count", 1)), "loop": loop != null,
					"loop_start": 0.0, "loop_end": 0.0, "partial": false}
			if loop is Dictionary:
				info["loop_start"] = float(loop.get("start_time", 0.0))
				info["loop_end"] = float(loop.get("end_time", 0.0))
				var length := player.get_animation(animation["name"]).length
				info["partial"] = info["loop_start"] > 0.0 or info["loop_end"] < length - 0.001
			_info[int(extras["anim_id"])] = info


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
	var whole_loop: bool = info["loop"] and not info["partial"]
	player.get_animation(info["name"]).loop_mode = Animation.LOOP_LINEAR if whole_loop else Animation.LOOP_NONE
	player.stop()
	player.play(info["name"])
	player.advance(0.0)
	_last_position = 0.0
	passes = 0
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
	var info: Dictionary = _info.get(anim_id, {})
	if loop_count == ENDLESS and info.get("partial", false):
		# A partial loop: past the loop's end, back into the segment.
		var start: float = info["loop_start"]
		var span: float = info["loop_end"] - start
		var position := player.current_animation_position
		if position >= info["loop_end"] or not player.is_playing():
			if not player.is_playing():
				player.play(info["name"])
			player.seek(start + (fmod(position - start, span) if span > 0.0 else 0.0), true)
			# The pass through the loop's end: the C's animFrame reaches frameCount there.
			frame = frame_count
			passes += 1
		else:
			frame = mini(int(player.current_animation_position * FPS) + 1, frame_count)
		_last_position = player.current_animation_position
		return motion
	if not player.is_playing() or player.current_animation_position >= player.current_animation_length:
		frame = frame_count
		playing = false
		if loop_count == 1:
			loop_count = 0
	elif loop_count == ENDLESS and player.current_animation_position < _last_position:
		# A whole loop wrapped: this tick passed its last frame (animFrame >= frameCount in the C).
		frame = frame_count
		passes += 1
	else:
		frame = mini(int(player.current_animation_position * FPS) + 1, frame_count)
	_last_position = player.current_animation_position
	return motion
