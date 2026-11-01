class_name EvolutionScene
extends Node
## The evolution's scene, started by partner state 13 (specs/evolution.md §2.8, specs/evolution_scene.md):
## getEvoSequenceState and tickEvoSequenceLoading (main/evl.c) as in the C, then the evl sequence
## (EvlSequence: EVL_initEvoSequence / EVL_tickEvoSequence). Its tick() is the object tick of the
## frame (the EvolutionHost calls it, A1); partner state 13 only reads `timer`, the C's one
## EVO_SEQUENCE_DATA.timer: the loading's, then the sequence's, -1 at the end.

## A sequence has just been made (the loading's end, A2): its owner wires its views to it.
signal sequence_started(sequence: EvlSequence)

## tickEvoSequenceLoading: each loading state waits until its timer passes 55.
const LOADING_FRAMES := 55
const TIMER_MAX := 30000
const ANIM_IDLE := 0
const ANIM_EVOLVING := 1
const ANIM_POSE := 0xB
## addConditionBubble(7) over the partner.
const BUBBLE := 7
## loadMapSounds2(18): the evolution's sound set.
const SOUND_SET := 18
const STATE_LOADING := 0
const STATE_LOADED := 1
const STATE_SEQUENCE := 2
const STATE_DONE := 3
## The sidecar's "no object" marker for a bone (skeleton.bones[b][0]); -1 in the C (objIndex).
const NO_OBJECT := 255

var partner: Partner
var evolution: Evolution
var game_state: Node
var data: Node
## The Sound node (sound sets, the music); null: silent (the tests).
var sound: Node
var bubbles: ConditionBubbles
## The sequence (EvlSequence); null until the loading ends.
var sequence: EvlSequence

## EVO_SEQUENCE_DATA: timer, state, the evolution target and its stat_gains Digimon.
var timer := -1
var state := STATE_DONE
var target := -1
var digimon_id := -1


## getEvoSequenceState(..., 0): the scene's data, the partner's idle, the sounds stopped, the
## evolution's sound set and the new Digimon's voice loaded.
func start(evolution_target: int) -> void:
	timer = 0
	state = STATE_LOADING
	target = evolution_target
	sequence = null
	digimon_id = int(data.evolution_gains(target).get("target", target))
	partner.start_animation(ANIM_IDLE)
	if sound != null:
		sound.stop_sound()
		sound.load_map_sounds(SOUND_SET)
		sound.load_partner_sounds(data.digimon_sounds(digimon_id))


## One game frame, as an object of the frame: the loading object (tickEvoSequenceLoading), then the
## sequence object (EVL_tickEvoSequence). The sequence's first tick is the frame after the loading's
## end (A2). Returns the timer (getEvoSequenceState(..., 1)).
func tick() -> int:
	match state:
		STATE_LOADING:
			if timer > LOADING_FRAMES:
				state = STATE_LOADED
				timer = 0
				partner.start_animation(ANIM_EVOLVING)
				if bubbles != null:
					bubbles.show_bubble(BUBBLE)
		STATE_LOADED:
			if timer > LOADING_FRAMES:
				# removeObject(0x809), stopBGM, EVL_initEvoSequence: the timer is now the sequence's.
				if sound != null:
					sound.music.stop_bgm()
				_start_sequence()
				return timer
		STATE_SEQUENCE:
			sequence.tick()
			timer = sequence.timer
			if timer == -1:
				state = STATE_DONE
			return timer
		STATE_DONE:
			return timer
	timer = mini(timer + 1, TIMER_MAX)
	return timer


## EVL_initEvoSequence's call (main/evl.c:48): the sequence from the partner's body (bone count,
## location, rotation, size) and the new Digimon's size.
func _start_sequence() -> void:
	var old: Dictionary = data.digimon(partner.digimon)
	var new: Dictionary = data.digimon(digimon_id)
	var count := int(old.get("bone_count", 0))
	# The camera's rotation matrices read the sine table (idempotent).
	PsxMath.setup(data)
	var location := Vector3i(roundi(partner.position.x), roundi(-partner.position.y), roundi(-partner.position.z))
	sequence = EvlSequence.new()
	sequence.apply_evolution = _apply
	sequence.start_animation = _start_animation
	sequence.animation_done = _animation_done
	sequence.play_sound = _play_sound
	sequence.stop_sound = _stop_sound
	sequence.ended.connect(_on_ended)
	sequence.init(count, _bone_objects(count), location, partner.direction,
			Vector2i(int(old.get("radius", 0)), int(old.get("height", 0))),
			Vector2i(int(new.get("radius", 0)), int(new.get("height", 0))))
	state = STATE_SEQUENCE
	timer = sequence.timer
	sequence_started.emit(sequence)


## The partner's bones' objects from its model's sidecar (DIGIMON_SKELETONS[type][bone].objIndex):
## the object index, -1 for none (skeleton.bones[b][0] = 255). Without a sidecar no bone has one.
func _bone_objects(count: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(count)
	out.fill(-1)
	var mmd: String = data.digimon_file(partner.digimon).get("mmd", "")
	if mmd == "":
		return out
	var rel := "mmd_files/%s/%s.json" % [mmd.get_slice("/", 1), mmd.get_file().get_basename()]
	var sidecar: Variant = Content.load_json(rel)
	if not sidecar is Dictionary:
		return out
	var bones: Array = sidecar.get("skeleton", {}).get("bones", [])
	for b in mini(count, bones.size()):
		var object := int(bones[b][0])
		out[b] = -1 if object == NO_OBJECT else object
	return out


## EVL_applyEvolution (evl.c:540): the evolution's changes, the new model at the same place.
func _apply() -> void:
	var key := evolution.apply_evolution(target)
	partner.load_digimon(data, key)


## startAnimation on the partner: an animation the model lacks plays to its end at once (as 5f-1's
## pose did), so a wait for it ends.
func _start_animation(id: int) -> void:
	partner.start_animation(id)
	if partner.animator != null and partner.animator.anim_id != id:
		partner.animator.frame = partner.animator.frame_count


## animFrame == frameCount; the pose (0xB) loops endlessly, so it is let play to its end
## (PsxAnimator.finish_loop, as the partner's other end-of-animation waits).
func _animation_done() -> bool:
	var animator := partner.animator
	if animator == null:
		return true
	if animator.anim_id == ANIM_POSE and animator.loop_count == PsxAnimator.ENDLESS:
		animator.finish_loop()
	return animator.frame >= animator.frame_count


func _play_sound(slot: int, value: int) -> void:
	if sound != null:
		sound.play_sound(slot, value)


func _stop_sound() -> void:
	if sound != null:
		sound.stop_sound()


## The sequence's state 3 (evl.c:572-576): forceUpdateBGM and loadMapSounds2(the map's sound set).
func _on_ended() -> void:
	if sound != null:
		sound.load_map_sounds(int(data.map(game_state.state["world"]["screen"]).get("sound_bank", 0)))
		sound.music.force_update_bgm()
