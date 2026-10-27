extends Node
## A battle in the real field scene (autoloads, NPCs, camera, sound): enters maps with wild
## Digimon, starts a battle on the first enemy on the map (BattleHost.start_battle, as START_BATTLE
## does) with a strong partner, and runs it to its end:
##   godot --headless --fixed-fps 60 --path . res://tests/battle_scan.tscn
## Prints each battle's outcome and frames; exits 1 if one doesn't end or the script errors.
## Env: BATTLE_MAPS=MAYO04A,TROP00 other maps; BATTLE_RAW=1 keeps the new game's partner as it is;
## BATTLE_DEBUG=1 prints the fighters every 100 frames; BATTLE_TALK=1 talks to the enemy (its talk
## section runs, ✕ closes its text, its START_BATTLE starts the fight) instead of starting it directly;
## BATTLE_ENTITY=3 picks the enemy; BATTLE_SECTION=51 runs that section of the map's script instead (a
## trigger cell's key fight; BATTLE_VALUES=1:50 sets script values first); BATTLE_AT=x,z moves the enemy there first (PSX units).

const DEFAULT_MAPS := ["TROP01", "TROP02", "MAYO03"]
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
var MAPS: Array = DEFAULT_MAPS
## Game frames a fighter stood on a blocking map cell (out of the walkable map) this battle.
var _outside := 0
var _printed_start := false


func _ready() -> void:
	_field = load("res://scenes/field/field.tscn").instantiate()
	_field.debug_window = false
	_field.render_scale = 1
	add_child(_field)
	if OS.get_environment("BATTLE_MAPS") != "":
		MAPS = OS.get_environment("BATTLE_MAPS").split(",")
	if OS.get_environment("BATTLE_RAW") != "":
		# A new game's Agumon after File City's script (DG script 193, section 55: SET_STAT), with
		# the moves the new game gives (technique keys).
		var s: Dictionary = GameState.state["partner"]["stats"]
		s["base"].merge({"offense": 80, "defense": 60, "speed": 70, "brains": 70, "max_hp": 800, "max_mp": 600}, true)
		s["current"]["hp"] = 800
		s["current"]["mp"] = 600
		print("partner moves: %s" % [s["base"]["moves"]])
		_next()
		return
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
			# On the ground: MAYO04A's Etemon waits up in a tree (y -1000) for its ambush.
			if n != null and n.on_map and absf(n.position.y) < 100 					and int(_field.entities.entities.slots[i - 2].get("record", {}).get("hp", 0)) > 0:
				npc = i
				break
		var present := []
		for i in range(2, 10):
			var n: Node3D = _field.entities.entities.entity(i)
			if n != null:
				present.append("%d%s" % [i, "" if n.on_map else " (off the map)"])
		if frames == SETTLE:
			print("%s: entities %s" % [MAPS[_index], present])
		if OS.get_environment("BATTLE_ENTITY") != "":
			npc = int(OS.get_environment("BATTLE_ENTITY"))
		if npc < 0:
			print("%s: no enemy on the map" % MAPS[_index])
			_next()
			return
		# Far from the map entry (his start tile), as after walking about: the intro sends him back
		# towards it, and the combat area must stop him on screen.
		var tamer: Tamer = _field.map_session.tamer
		var enemy: Node3D = _field.entities.entities.entity(npc)
		if OS.get_environment("BATTLE_AT") != "":
			var at := OS.get_environment("BATTLE_AT").split(",")
			enemy.position = Vector3(float(at[0]), 0, -float(at[1]))
		tamer.position = enemy.position + Vector3(0, 0, 400)
		_field.entities.entities.partner.position = enemy.position + Vector3(0, 0, 250)
		_field.map_session.field_map.follow(tamer.position) if _field.map_session.field_map.has_method("follow") else null
		# The NPCs' field tick would update isOnScreen after these moves.
		for i in range(2, 10):
			var n := _field.entities.entities.entity(i) as Npc
			if n != null:
				n.update_on_screen()
		if OS.get_environment("BATTLE_RAW") != "":
			var st: Dictionary = GameState.state["partner"]["stats"]
			st["current"]["hp"] = int(st["base"]["max_hp"])
			st["current"]["mp"] = int(st["base"]["max_mp"])
		if OS.get_environment("BATTLE_SECTION") != "":
			var ctx: ScriptContext = _field.scripts.script_ctx
			if OS.get_environment("BATTLE_VALUES") != "":
				# BATTLE_VALUES=1:50,2:3 sets script values first (a section's condition).
				for kv in OS.get_environment("BATTLE_VALUES").split(","):
					GameState.set_script_value(int(kv.get_slice(":", 0)), int(kv.get_slice(":", 1)))
			print("%s: running section %s" % [MAPS[_index], OS.get_environment("BATTLE_SECTION")])
			_field.scripts.interpreter.call_section(ctx.current_script_id, int(OS.get_environment("BATTLE_SECTION")), 0)
		elif OS.get_environment("BATTLE_TALK") != "":
			var n: Npc = _field.entities.entities.entity(npc)
			print("%s: talking to entity %d (section %d)" % [MAPS[_index], npc, n.script_id()])
			_field.scripts.talk_to(n)
		else:
			host.start_battle(npc)
		_fighting = true
		_outside = 0
		_printed_start = false
		_checked_intro = false
		_start = GameLoop.frame_count
		return
	var every := int(OS.get_environment("BATTLE_DEBUG")) if OS.get_environment("BATTLE_DEBUG").is_valid_int() else 100
	if OS.get_environment("BATTLE_DEBUG") != "" and frames % maxi(every, 1) == 0 and host.session != null and host.session.battle.fighters.size() > 1:
		var b := host.session.battle
		var line := "%d %s" % [frames, BattleSession.Phase.keys()[host.session.phase]]
		for f in b.fighters:
			line += " | e%d hp %d mp %d anim %x flags %x tgt %d range %d spd %d cd %d q %x pos %s" % [f.entity, f.hp(), f.mp(),
				host.battle_world.animation_id(f.entity), f.flags, f.target, f.move_range, f.speed_buffer, f.cooldown, f.queued_anim,
				host.battle_world.location(f.entity)]
		print(line, " queue ", host.effects.attack_objects.size())
	# The end box's text types only on ✕ (the US BTL_drawBattleEndText): tap it now and then.
	var talking := not host.active and not host.battle_done()
	if talking and frames % 200 == 0 and OS.get_environment("BATTLE_DEBUG") != "":
		var ctx: ScriptContext = _field.scripts.script_ctx
		print("%d talk: pointer %04X active %02X paused %s wait entity %d" % [frames, ctx.pointer, ctx.active_instruction,
				ctx.is_paused, ctx.wait_for_entity_id])
	if (talking or host.session != null and host.session.phase == BattleSession.Phase.END_BOX) and frames % 8 == 0:
		GameLoop.press("pad_cross")
	# Hits push fighters back, but the map's walls hold them (BTL_tickFighterAction's probe).
	if host.session != null and host.session.phase == BattleSession.Phase.FIGHT:
		var map: FieldMap = _field.map_session.field_map
		for f in host.session.battle.fighters:
			var at := host.battle_world.location(f.entity)
			var t := FieldMap.model_tile(at.x, at.z)
			if map._cell(t.x, t.y) & 0x80:
				_outside += 1
				if _outside == 1:
					print("%s: entity %d on a blocking cell at %s (anim %x)" % [MAPS[_index], f.entity, at,
							host.battle_world.animation_id(f.entity)])
	if host.session != null and not _printed_start:
		_printed_start = true
		print("%s: fighters %s, predefined %s, bubbles %s, slots %s" % [MAPS[_index], host.session.entity_ids,
				host.session.predefined, host.session.bubbles, [GameState.script_value(0xFA), GameState.script_value(0xFB),
				GameState.script_value(0xFC), GameState.script_value(0xFD)]])
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
		if host.battle_outcome() == 1 and host.session != null and not host.session.battle.no_escape:
			for i in range(1, host.session.entity_ids.size()):
				var e: Node3D = _field.entities.entities.entity(host.session.entity_ids[i])
				if e != null and e.on_map:
					print("%s: the defeated entity %d is still on the map" % [MAPS[_index], host.session.entity_ids[i]])
					_failed = true
				# Off the map it stands still: no animation, no root motion, no steps.
				if e != null and not e.on_map:
					var was: Vector3 = e.global_position
					e._process(0.5)
					if e.global_position != was:
						print("%s: the defeated entity %d still moves off the map" % [MAPS[_index], host.session.entity_ids[i]])
						_failed = true
		if _outside > 0:
			print("%s: a fighter stood out of the map for %d frames" % [MAPS[_index], _outside])
			_failed = true
		_next()
	elif frames > TIMEOUT:
		var where: String = BattleSession.Phase.keys()[host.session.phase] if host.session != null else "the talk (no battle started)"
		print("%s: STUCK in %s after %d frames" % [MAPS[_index], where, frames])
		_failed = true
		_next()
