extends Node
## A battle in the real field scene (autoloads, NPCs, camera, sound): enters maps with wild
## Digimon, starts a battle on the first enemy on the map (BattleHost.start_battle, as START_BATTLE
## does) with a strong partner, and runs it to its end:
##   godot --headless --fixed-fps 60 --path . res://tests/battle_scan.tscn
## Prints each battle's outcome and frames; exits 1 if one doesn't end or the script errors.

const MAPS := ["TROP01", "TROP02", "MAYO03"]
## Game frames a battle may take.
const TIMEOUT := 4000
## Game frames to let the map set up before the battle.
const SETTLE := 90

var _field: Node
var _index := -1
var _start := 0
var _fighting := false
var _failed := false
var _checked_intro := false


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	var b: Dictionary = GameState.state["partner"]["stats"]["base"]
	for k in ["offense", "defense", "speed"]:
		b[k] = 600
	b["max_hp"] = 3000
	b["max_mp"] = 3000
	b["brains"] = 300
	# The partner's first technique equipped in slot 0 (a new game's partner may have none).
	var moves: Array = GameData.digimon(GameState.state["partner"]["digimon"]).get("moves", [])
	if not moves.is_empty():
		b["moves"][0] = int(moves[0]["anim"])
	GameState.state["partner"]["stats"]["current"]["hp"] = 3000
	GameState.state["partner"]["stats"]["current"]["mp"] = 3000
	_next()


func _next() -> void:
	_index += 1
	_fighting = false
	if _index >= MAPS.size():
		print("battle_scan: %s" % ("FAILED" if _failed else "OK"))
		get_tree().quit(1 if _failed else 0)
		return
	_field.map_session.debug_change_map(MAPS[_index], 0)
	_start = GameLoop.frame_count


func _process(_delta: float) -> void:
	if _index >= MAPS.size():
		return
	var frames := GameLoop.frame_count - _start
	var host: BattleHost = _field.battle_host
	if not _fighting:
		if frames < SETTLE:
			return
		var npc := -1
		for i in range(2, 10):
			var n: Node3D = _field.entities.entities.entity(i)
			if n != null and n.on_map and int(_field.entities.entities.slots[i - 2].get("record", {}).get("hp", 0)) > 0:
				npc = i
				break
		if npc < 0:
			print("%s: no enemy on the map" % MAPS[_index])
			_next()
			return
		# Far from the map entry (his start tile), as after walking about: the intro sends him back
		# towards it, and the combat area must stop him on screen.
		var tamer: Tamer = _field.map_session.tamer
		var enemy: Node3D = _field.entities.entities.entity(npc)
		tamer.position = enemy.position + Vector3(0, 0, 400)
		_field.entities.entities.partner.position = enemy.position + Vector3(0, 0, 250)
		_field.map_session.field_map.follow(tamer.position) if _field.map_session.field_map.has_method("follow") else null
		host.start_battle(npc)
		_fighting = true
		_checked_intro = false
		_start = GameLoop.frame_count
		return
	if OS.get_environment("BATTLE_DEBUG") != "" and frames % 100 == 0 and host.session != null and host.session.battle.fighters.size() > 1:
		var b := host.session.battle
		var line := "%d %s" % [frames, BattleSession.Phase.keys()[host.session.phase]]
		for f in b.fighters:
			line += " | e%d hp %d dmg %d mp %d anim %x flags %x tgt %d range %d pos %s yaw %d" % [f.entity, f.hp(), f.hp_damage, f.mp(),
				host.battle_world.animation_id(f.entity), f.flags, f.target, f.move_range, host.battle_world.location(f.entity), host.battle_world.rotation_y(f.entity)]
		print(line, " queue ", host.effects.attack_objects.size())
	# The intro's combat area (specs/battle.md §2.4): the tamer stops at its edge, on screen.
	if not _checked_intro and host.session != null and host.session.phase == BattleSession.Phase.FIGHT:
		_checked_intro = true
		var off := host.battle_world.is_off_screen(0, 320, 240)
		print("%s: the tamer is %s when the fight begins (at %s)" % [MAPS[_index], "OFF SCREEN" if off else "on screen",
				host.battle_world.location(0)])
		if off:
			_failed = true
	if host.battle_done():
		print("%s: outcome %d after %d frames" % [MAPS[_index], host.battle_outcome(), frames])
		_next()
	elif frames > TIMEOUT:
		print("%s: STUCK in phase %s after %d frames" % [MAPS[_index], BattleSession.Phase.keys()[host.session.phase], frames])
		_failed = true
		_next()
