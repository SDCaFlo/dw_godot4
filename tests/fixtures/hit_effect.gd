extends BattleEffect
## A minimal mod effect for tests/test_efe.gd: each use hits its target on its 10th tick, then ends.

var _uses: Array[Dictionary] = []


func start(attacker: int, target: int) -> int:
	_uses.append({"attacker": attacker, "target": target, "frame": 0})
	return _uses.size() - 1


func stop(sub_effect: int) -> void:
	if sub_effect >= 0 and sub_effect < _uses.size():
		_uses[sub_effect]["frame"] = -1


func tick() -> void:
	for i in _uses.size():
		var u: Dictionary = _uses[i]
		if u["frame"] < 0:
			continue
		u["frame"] += 1
		if u["frame"] == 10 and not ctx.is_hit(u["target"]):
			ctx.set_hit(u["target"], true)
			hit.emit(u["target"], ctx.location(u["target"]), i, u["attacker"])
			u["frame"] = -1
			finished.emit(i)


func is_running() -> bool:
	for u in _uses:
		if u["frame"] >= 0:
			return true
	return false
