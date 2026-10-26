class_name EvolutionScene
extends Node
## The evolution's scene, started by partner state 13 (specs/evolution.md §2.8, §2.9):
## getEvoSequenceState and tickEvoSequenceLoading (main/evl.c) as in the C, then, until the evl
## sequence is ported (5f-2), a stand-in: EVL_applyEvolution at once, the new Digimon's pose
## (animation 0xB), the end. tick() returns the scene's timer, -1 once it is over.

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
const STATE_POSE := 2
const STATE_DONE := 3

var partner: Partner
var evolution: Evolution
var game_state: Node
var data: Node
## The Sound node (sound sets, the music); null: silent (the tests).
var sound: Node
var bubbles: ConditionBubbles

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
	digimon_id = int(data.evolution_gains(target).get("target", target))
	partner.start_animation(ANIM_IDLE)
	if sound != null:
		sound.stop_sound()
		sound.load_map_sounds(SOUND_SET)
		sound.load_partner_sounds(data.digimon_sounds(digimon_id))


## One game frame: the loading object (tickEvoSequenceLoading), then the stand-in sequence.
## Returns the timer (getEvoSequenceState(..., 1)).
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
				if sound != null:
					sound.music.stop_bgm()
				_apply()
				return timer
		STATE_POSE:
			if partner.animator != null and partner.animator.loop_count == PsxAnimator.ENDLESS:
				partner.animator.finish_loop()
			if partner.animator == null or partner.animator.frame >= partner.animator.frame_count:
				_end()
				return timer
		STATE_DONE:
			return timer
	timer = mini(timer + 1, TIMER_MAX)
	return timer


## The stand-in of EVL_tickEvoSequence (5f-2): EVL_applyEvolution and the new model at the old one's
## place, then its pose.
func _apply() -> void:
	var key := evolution.apply_evolution(target)
	partner.load_digimon(data, key)
	partner.play_or_skip(ANIM_POSE)
	state = STATE_POSE


## The sequence's end (state 3-4): the music back (forceUpdateBGM), the map's sounds reloaded,
## timer -1.
func _end() -> void:
	state = STATE_DONE
	timer = -1
	if sound != null:
		sound.load_map_sounds(int(data.map(game_state.state["world"]["screen"]).get("sound_bank", 0)))
		sound.music.force_update_bgm()
