class_name ArenaBracket
extends RefCounted
## Arena bracket logic (specs/arena.md §3.2, §5.2). Port of STD_updateBracket,
## projectile and hit-flash ticking, and intro timer/fade animation.

## std_main.c:2986: state 0 (idle) lasts 0x29 frames.
const STATE_0_IDLE := 0x29
## std_main.c:3016: state 2 (face-off) shoots after 0x29 frames.
const STATE_2_FACE_OFF := 0x29
## std_main.c:3057: state 3 ends the shot pose after 0x15 frames.
const STATE_3_WAIT_HIT := 0x15
## std_main.c:3086, :3095: state 4 (hit) lasts 0x1F frames.
const STATE_4_HIT_LOSER := 0x1F
## std_main.c:3105: state 5 (the loser's hop) lasts 0x18 frames (STD_BRACKET_HOP_Y).
const STATE_5_HOP := 0x18
## std_main.c:3181: state 7 (final) ends the bracket after 0x3D frames.
const STATE_7_FINAL := 0x3D
## std_main.c:3688: the intro timer stops at 0x78.
const INTRO_MAX_TIMER := 0x78
## std_main.c:3691: the intro fades from frame 0x65.
const INTRO_FADE_START := 0x65

signal sound(bank: int, id: int)

var game_data: Node
var player_slot: int
var round1: Array
var round2: Array

var match: int = 1
var fade: int = 0
var finished: bool = false
var slots: Array[Dictionary] = []
var projectiles: Dictionary = {}
var flashes: Array = []

## What the projectiles' and hit flashes' ticks drew this frame (they draw in their tick, before
## STD_updateBracket): {slot, x, y, flag, facing} / {slot, x, y}, by slot (specs/arena.md §4.7).
var drawn_projectiles: Array = []
var drawn_flashes: Array = []

var intro_timer: int = 0
var intro_overlay: int = 0
var intro_title: int = 0

var _projectile_owners: Array[int] = [0, 0, 0, 0, 0, 0, 0, 0]
var _paths: Array
var _row_y: Array
var _hop_y: Array


## STD_initializeBracket (std_main.c:3444-3462).
func _init(p_game_data: Node, p_player_slot: int, p_round1: Array, p_round2: Array) -> void:
	game_data = p_game_data
	player_slot = p_player_slot
	round1 = p_round1
	round2 = p_round2
	_init_bracket()


func _init_bracket() -> void:
	self.match = 1
	fade = 0
	finished = false
	slots.clear()
	var bracket_data: Dictionary = game_data.system("arena")[0]["bracket"]
	_paths = bracket_data["paths"]
	_row_y = bracket_data["row_y"]
	_hop_y = bracket_data["hop_y"]
	var paths := _paths
	var row_y := _row_y
	for i in range(8):
		slots.append({
			"x": int(paths[i]["x"][0]),
			"y": int(row_y[0]),
			"frame": 0,
			"row": 1,
			"facing": int(paths[i]["facing"][0]),
			"state": 0,
			"timer": 0,
			"timer2": 0,
			"hit": 0,
			"mode": 0,
			"loser": 0,
		})


## STD_addBracket (std_main.c:3544-3554).
func begin() -> void:
	finished = false
	fade = 0


## STD_addBracketIntro (std_main.c:3672-3684).
func begin_intro() -> void:
	fade = 0x80
	intro_overlay = 0x80
	intro_title = 0x80
	intro_timer = 0


## STD_tickBracketIntro (std_main.c:3686-3702).
func intro_frame() -> void:
	if intro_timer < INTRO_MAX_TIMER:
		intro_timer += 1
	if intro_timer >= INTRO_FADE_START:
		if fade != 0:
			fade -= 8
		if intro_overlay >= 9:
			intro_overlay -= 8
		if intro_title != 0:
			intro_title -= 8


## STD_addBracketProjectile (std_main.c:3314-3334).
func _add_projectile(i: int, owner: int, flag: int) -> void:
	var px := 0
	var py := 0
	if slots[i]["facing"] == 1:
		px = int(slots[i]["x"]) + 0x10
		py = int(slots[i]["y"])
		if flag == 1:
			slots[owner]["loser"] = 1
	else:
		px = int(slots[i]["x"]) - 8
		if flag == 0:
			py = int(slots[i]["y"]) + 8
		else:
			py = int(slots[i]["y"])
			slots[owner]["loser"] = 1
	projectiles[i] = {
		"x": px,
		"y": py,
		"flag": flag,
		"owner": owner,
	}
	_projectile_owners[i] = owner


## STD_tickBracketProjectile (std_main.c:3603-3621) & STD_renderBracketProjectile hit test (std_main.c:3659-3669).
func _tick_projectiles() -> void:
	var d := 1
	if self.match < 5:
		d = 1
	elif self.match < 7:
		d = 3
	drawn_projectiles.clear()
	var ids: Array = projectiles.keys()
	ids.sort()
	for id in ids:
		if not projectiles.has(id):
			continue
		var proj: Dictionary = projectiles[id]
		if slots[id]["facing"] == 1:
			proj["x"] += d
		else:
			proj["x"] -= d
		# STD_renderBracketProjectile: drawn, then the hit test (so also on the frame it hits).
		drawn_projectiles.append({"slot": int(id), "x": int(proj["x"]), "y": int(proj["y"]),
				"flag": int(proj["flag"]), "facing": int(slots[id]["facing"])})
		var owner: int = int(proj["owner"])
		if slots[id]["facing"] == 1:
			if slots[owner]["x"] - proj["x"] < 9:
				slots[owner]["hit"] = 1
				projectiles.erase(id)
		else:
			if proj["x"] - slots[owner]["x"] < 0x11:
				slots[owner]["hit"] = 1
				projectiles.erase(id)


## STD_addBracketHitFlash (std_main.c:3336-3339).
func _add_hit_flash(idx: int) -> void:
	if not flashes.has(idx):
		flashes.append(idx)


## STD_tickBracketHitFlash (std_main.c:3582-3600).
func _tick_flashes() -> void:
	drawn_flashes.clear()
	var list: Array = flashes.duplicate()
	list.sort()
	for idx in list:
		if slots[idx]["timer"] >= 0x10:
			flashes.erase(idx)
		# Drawn after the removal test, so also on the frame it goes.
		if int(slots[idx]["timer"]) % 5 == 4:
			drawn_flashes.append({"slot": int(idx), "x": int(slots[idx]["x"]), "y": int(slots[idx]["y"])})


## STD_battleTickFrame running projectile/flash ticks then STD_updateBracket in render.
func frame(match_result: int) -> void:
	_tick_projectiles()
	_tick_flashes()
	_update_bracket(match_result)


## STD_updateBracket (std_main.c:2949-3209).
func _update_bracket(match_result: int) -> void:
	var paths := _paths
	var row_y := _row_y
	var hop_y := _hop_y

	var ab := [0, 0]
	if self.match < 5:
		ab[0] = (self.match - 1) * 2
		ab[1] = (self.match - 1) * 2 + 1
	elif self.match < 7:
		ab[0] = round1[(self.match - 5) * 2]
		ab[1] = round1[(self.match - 5) * 2 + 1]
	else:
		ab[0] = round2[0]
		ab[1] = round2[1]

	var is_player_match := 1 if (ab[0] == player_slot or ab[1] == player_slot) else 0

	for i in range(8):
		if i != ab[0] and i != ab[1]:
			continue
		var s: Dictionary = slots[i]
		match s["state"]:
			0:
				s["timer"] += 1
				s["timer2"] += 1
				if s["timer"] % 10 == 0:
					s["frame"] = (s["frame"] + 1) & 1
				if s["timer2"] >= STATE_0_IDLE:
					s["timer2"] = 0
					s["state"] += 1
			1:
				s["timer"] += 1
				s["timer2"] += 1
				if s["timer2"] == 5:
					sound.emit(8, 5)
				var target_y: int = int(row_y[s["row"]])
				if s["y"] != target_y:
					s["y"] -= 1
				if s["timer"] % 10 == 0:
					s["frame"] = (s["frame"] + 1) & 1
				var target_x: int = int(paths[i]["x"][s["row"]])
				if s["y"] == target_y and s["x"] == target_x:
					s["mode"] = 0
					s["timer2"] = 0
					s["state"] += 1
			2:
				s["timer"] += 1
				s["timer2"] += 1
				if s["timer"] % 10 == 0:
					s["frame"] = (s["frame"] + 1) & 1
				if is_player_match == 0:
					if s["timer2"] >= STATE_2_FACE_OFF:
						s["frame"] = 2
						sound.emit(8, 1)
						s["timer"] = 0
						s["timer2"] = 0
						s["hit"] = 0
						var flag := 0
						if self.match < 5:
							if i == round1[self.match - 1]:
								flag = 1
						elif self.match < 7:
							if i == round2[self.match - 5]:
								flag = 1
						var arg: int = ab[1] if i == ab[0] else ab[0]
						_add_projectile(i, arg, flag)
						s["state"] += 1
				else:
					fade += 3
					if fade >= 0x81:
						fade = 0x80
			3:
				if s["frame"] == 2:
					s["timer2"] += 1
				else:
					s["timer"] += 1
					if s["timer"] % 10 == 0:
						s["frame"] = (s["frame"] + 1) & 1
				if s["timer2"] >= STATE_3_WAIT_HIT:
					s["frame"] = 0
					s["timer"] = 0
					s["timer2"] = 0
				if s["hit"] == 1:
					s["mode"] = 3
					s["timer2"] = 0
					s["timer"] = 0
					s["state"] += 1
					if s["mode"] != 3:
						_add_hit_flash(i)
					elif s["loser"] == 1:
						_add_hit_flash(i)
					else:
						s["facing"] = (s["facing"] + 1) & 1
			4:
				s["timer"] += 1
				if s["mode"] != 3:
					s["frame"] = 3
					if s["timer"] >= 0x15:
						s["timer"] = 0
						s["state"] = 2
				elif s["loser"] == 1:
					s["frame"] = 3
					if s["timer"] >= STATE_4_HIT_LOSER:
						s["timer"] = 0
						s["state"] += 1
						sound.emit(8, 3)
				else:
					if s["timer"] == 0x14:
						s["facing"] = (s["facing"] + 1) & 1
					if s["timer"] >= STATE_4_HIT_LOSER:
						s["row"] += 1
						s["state"] += 2
						if s["frame"] == 2:
							s["frame"] = 0
			5:
				if s["timer"] < STATE_5_HOP:
					s["y"] = int(row_y[s["row"]]) + int(hop_y[s["timer"]])
					s["timer"] += 1
					if s["timer"] == 0x14:
						sound.emit(8, 4)
				else:
					s["state"] += 1
			6:
				if is_player_match != 0:
					if match_result == 1:
						if i == player_slot:
							s["x"] = int(paths[i]["x"][s["row"] + 1])
							s["frame"] = 0
							s["facing"] = int(paths[i]["facing"][s["row"] + 1])
							s["row"] += 2
							s["timer2"] = 0
							s["timer"] = 0
							s["state"] = 0
							if self.match < 5:
								round1[player_slot / 2] = player_slot
							if self.match < 7:
								round2[player_slot / 4] = player_slot
							self.match += 1
						else:
							s["y"] = int(row_y[s["row"] - 1])
							s["frame"] = 3
					elif i == player_slot:
						s["y"] = int(row_y[s["row"] - 1])
						s["frame"] = 3
					else:
						s["x"] = int(paths[i]["x"][s["row"] - 1])
						s["frame"] = 0
				elif s["loser"] == 0:
					s["timer"] += 1
					if s["timer"] % 10 == 0:
						s["frame"] = (s["frame"] + 1) & 1
					var owner: int = _projectile_owners[i]
					if slots[owner]["state"] == 6:
						var target_x: int = int(paths[i]["x"][s["row"]])
						if s["x"] > target_x:
							s["x"] -= 1
						if s["x"] < target_x:
							s["x"] += 1
						var target_y: int = int(row_y[s["row"]])
						if s["y"] == target_y and s["x"] == target_x:
							s["facing"] = int(paths[i]["facing"][s["row"]])
							s["row"] += 1
							s["timer2"] = 0
							s["timer"] = 0
							s["frame"] = 0
							s["state"] = 0
							self.match += 1
			7:
				s["timer"] += 1
				if i == player_slot:
					s["x"] = int(paths[i]["x"][7])
					s["y"] = int(row_y[7])
					s["frame"] = 0
					s["facing"] = int(paths[i]["facing"][7])
				else:
					s["x"] = int(paths[i]["x"][4])
					s["y"] = int(row_y[4])
					s["facing"] = int(paths[i]["facing"][4])
					s["frame"] = 3
				if s["timer"] >= STATE_7_FINAL:
					finished = true

	if is_player_match != 0 and fade == 0x80 and slots[player_slot]["state"] == 2:
		var next_state: int = 7 if self.match == 7 else 6
		slots[player_slot]["state"] = next_state
		if self.match == 7:
			slots[player_slot]["timer"] = 0
		var other_slot: int = ab[1] if player_slot == ab[0] else ab[0]
		slots[other_slot]["state"] = next_state
		if self.match == 7:
			slots[other_slot]["timer"] = 0
		finished = true
