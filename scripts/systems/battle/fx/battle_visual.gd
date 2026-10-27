class_name BattleVisual
extends Node3D
## One battle visual outside the technique scripts (specs/battle_effects.md §4, §7.6): a poison
## bubble, a stun star, the finisher aura, an aura projectile… Each is its own scene
## (scenes/battle/fx/<kind>.tscn) whose script is the C's: start() is its add function (the rolls it
## makes), tick() its tick (logic only, run headless), draw() its render (through the view). A mod
## replaces a visual by giving BattleVisuals another scene for its kind.

## The host, its context, the kind and the pool slot (the C's instance id).
var visuals: BattleVisuals
var ctx: BattleEffectContext
var kind := ""
var index := -1
## The entity it belongs to (ENTITY_TABLE index), -1 for none.
var entity := -1
var frame := 0


## The C's add function, after the host took the slot: `args` as the battle's visual event gives them.
func start(_args: Array) -> void:
	pass


## The C's tick.
func tick() -> void:
	pass


## The C's render.
func draw(_view: BattleVisualsView) -> void:
	pass


## removeObject: the slot is free again.
func remove() -> void:
	if visuals != null:
		visuals.remove(self)
