class_name BattleFighter
extends RefCounted
## One fighter (FighterData, combat.h): fighter 0 is the partner, 1-3 the enemies. `entity` is its
## ENTITY_TABLE index; `stats` its stats dictionary (BattleWorld.stats), read and written in place.

const POISONED := 1 << 0
const CONFUSED := 1 << 1
const STUNNED := 1 << 2
const FLATTENED := 1 << 3
const KNOCKED_BACK := 1 << 4
const ATTACKING := 1 << 5
## FIGHTER_FLAG_TRANSFORMING: busy with a queued technique / an action the AI must not replace.
const BUSY := 1 << 6
const BLOCKING := 1 << 7
const PROTECTED := 1 << 8
const FLAG_9 := 1 << 9
## FIGHTER_FLAG_10: the target was given by a hit (BTL_selectFighterTarget's retarget).
const RETARGETED := 1 << 10
const ON_CHARGEUP := 1 << 11
const ON_COOLDOWN := 1 << 12
## FIGHTER_FLAG_SENILE: distracted, ignoring orders.
const SENILE := 1 << 13
const FLAG_14 := 1 << 14
const DEAD := 1 << 15
const STATUSES := POISONED | CONFUSED | STUNNED | FLATTENED
## blocked-attack table size (table1 / table2).
const BLOCKED := 150
## No target.
const NO_TARGET := 0xFF
## No technique in a slot.
const NO_MOVE := 0xFF

var entity := -1
var stats: Dictionary = {}

var status_fx := -1
var effect_slot: Array[int] = [-1, -1, -1, -1]
var active_effect_slot := -1
var finisher_goal := 0
var finisher_progress := 0
var poison_timer := 0
var confusion_timer := 0
var stun_timer := 0
var flat_timer := 0
var flat_attack_timer := 0
var invulnerable_timer := 0
var cooldown := 0
var senile_timer := 0
## unk15: frames spent outside the ranged band.
var band_frames := 0
var hp_damage := 0
var mp_damage := 0
var speed_buffer := 100
var flags := 0
var move_range := 0
var target := NO_TARGET
var queued_anim := 0
var buffs_remaining := 0
var buff_prio_timer := 0
var collided_while_distancing := 0
## The blocked attacks (table1 / table2): [effect, sub_effect] pairs.
var blocked: Array = []


func base() -> Dictionary:
	return stats["base"]


func current() -> Dictionary:
	return stats["current"]


func has(flag: int) -> bool:
	return flags & flag != 0


func hp() -> int:
	return int(current()["hp"])


func set_hp(value: int) -> void:
	current()["hp"] = value


func mp() -> int:
	return int(current()["mp"])


func set_mp(value: int) -> void:
	current()["mp"] = value


func max_hp() -> int:
	return int(base()["max_hp"])


func offense() -> int:
	return int(base()["offense"])


func defense() -> int:
	return int(base()["defense"])


func speed() -> int:
	return int(base()["speed"])


func brains() -> int:
	return int(base()["brains"])


## stats.base.moves[slot]: the animation id (0x2E + technique slot), or NO_MOVE.
func move_anim(slot: int) -> int:
	var m = base()["moves"][slot]
	return NO_MOVE if m == null else int(m)


func clear_move(slot: int) -> void:
	base()["moves"][slot] = null


func move_prio(slot: int) -> int:
	return int(base()["moves_prio"][slot])


func charge_mode() -> int:
	return int(current()["charge_mode"])


func set_charge_mode(value: int) -> void:
	current()["charge_mode"] = value


func is_hit() -> bool:
	return int(current()["is_hit"]) != 0


func set_hit(value: bool) -> void:
	current()["is_hit"] = 1 if value else 0
