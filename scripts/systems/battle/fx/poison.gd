extends BattleVisual
## BTL_addPoisonEffect / BTL_tickPoisonEffect (battle_effect.c:5427, :5454): while the fighter is
## poisoned, a bubble (poison_bubble) every 30 frames; it draws nothing itself.

const CYCLE := 0x1E


func start(_args: Array) -> void:
	frame = 0


func tick() -> void:
	frame = (frame + 1) % CYCLE
	if frame == 1:
		visuals.add("poison_bubble", entity)
