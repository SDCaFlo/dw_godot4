extends SceneTree
## The battle HUD (scenes/battle/battle_hud.tscn, scripts/ui/battle/; specs/battle.md §4) on whole
## battles of the stub world of test_battle.gd: the HUD is in the tree, so its pieces draw every
## engine frame, one game frame per engine frame. Checks the pieces' C state (the shout's 20
## frames, the numbers' 31, the start text's 155 pieces, the bubbles going with the loading, the
## bars' slide, the end boxes and their text, the countdown), and that the HUD's hooks end the
## battle:
##   godot --headless --path . -s res://tests/test_battle_hud.gd
## Exits 1 if a check fails.

const TestBattle := preload("res://tests/test_battle.gd")
const HUD := preload("res://scenes/battle/battle_hud.tscn")

var _failed := 0
var _checks := 0
var data: Node
var boxes: UIBoxes
var area: TextArea
var hud: BattleHud
var session: BattleSession
var world: BattleWorld
var _frame := 0
var _stage := 0
var _pad_previous := 0
## What the frames saw.
var seen := {}


func _process(_delta: float) -> bool:
	if _stage == 0:
		data = load("res://scripts/data/game_data.gd").new()
		if not data.available():
			print("SKIP: no data porter output")
			quit(0)
			return false
		PsxMath.setup(data)
		area = TextArea.new(data, "en_us")
		boxes = UIBoxes.new()
		root.add_child(boxes)
		_start_battle({}, {})
		_stage = 1
		return false
	if _stage == 1:
		if _step(_win_press()):
			_check_win()
			_free_battle()
			_start_battle({"max_hp": 30, "max_mp": 0, "offense": 1, "defense": 1, "speed": 1},
					{"max_hp": 5000, "offense": 900, "defense": 900, "speed": 300})
			_stage = 2
		return false
	if _stage == 2:
		if _step(0):
			_check_loss()
			_free_battle()
			data.free()
			print("%s: battle HUD checks (%d run)" % ["FAILED %d" % _failed if _failed else "OK", _checks])
			quit(1 if _failed else 0)
			_stage = 3
	return false


func _eq(actual: Variant, expected: Variant, what: String) -> void:
	_checks += 1
	if actual == expected:
		return
	_failed += 1
	push_error("FAIL %s: got %s, expected %s" % [what, actual, expected])


func _anim_of(type: int, category: String) -> Variant:
	for m in data.digimon(type).get("moves", []):
		if data.move(int(m["move"]["id"])).get("category", "") == category:
			return int(m["anim"])
	return null


func _start_battle(partner: Dictionary, enemy: Dictionary) -> void:
	var w = TestBattle.StubWorld.new()
	w.data = data
	var p := {"max_hp": 800, "max_mp": 400, "offense": 300, "defense": 200, "speed": 200, "brains": 150,
			"moves": [_anim_of(3, "technique"), null, null, _anim_of(3, "finisher")], "moves_prio": [0, 0, 0, 0]}
	p.merge(partner, true)
	var e := {"max_hp": 60, "max_mp": 300, "offense": 40, "defense": 30, "speed": 30, "brains": 20,
			"moves": [_anim_of(17, "technique"), null, null, null], "moves_prio": [10, 0, 0, 0]}
	e.merge(enemy, true)
	w.add(0, -1, Vector3i(0, 0, 0))
	w.add(1, 3, Vector3i(0, 0, -200), p)
	w.add(2, 17, Vector3i(0, 0, -900), e, {"bits": 25, "targets_partner": false, "flee": [0, 0, -3000]})
	world = w
	session = BattleSession.new(w, EffectHost.new(w), data)
	hud = HUD.instantiate()
	hud.session = session
	hud.world = w
	hud.text_area = area
	hud.boxes = boxes
	hud.data = data
	root.add_child(hud)
	session.battle.visual.connect(hud.on_visual)
	session.boxes_open = hud.end_boxes_open
	session.end_text_done = hud.end_text_done
	session.battle.visual.connect(func(kind: String, _args: Array) -> void:
		seen[kind] = int(seen.get(kind, 0)) + 1)
	Rng.set_seed(42)
	_frame = 0
	seen = {}
	session.begin(2)


func _free_battle() -> void:
	hud.queue_free()
	for i in 3:
		if boxes.boxes[i].state != UIBoxes.STATE_CLOSED:
			boxes.remove_static(i)


## In the end box, ✕ every 8 frames (the US text types only after a press).
func _win_press() -> int:
	if session.phase == BattleSession.Phase.END_BOX and _frame % 8 == 0:
		return Pad.CONFIRM
	return 0


## One game frame: the battle, the HUD, the boxes. True when the battle is over (or ran too long).
func _step(polled: int) -> bool:
	var pressed := polled & ~_pad_previous
	_pad_previous = polled
	session.frame(pressed)
	hud.tick(pressed)
	boxes.step()
	(world as TestBattle.StubWorld).advance()
	_frame += 1
	_observe()
	return session.is_done() or _frame > 9000


func _piece(name: String) -> Node:
	return hud.get_node(name)


func _observe() -> void:
	var shout = _piece("CommandShout")
	if session.phase == BattleSession.Phase.FIGHT and not seen.has("shouted"):
		seen["shouted"] = true
		hud.on_visual("shout", [Battle.CMD_ATTACK])
	if shout.frame >= 0:
		seen["shout_max"] = maxi(int(seen.get("shout_max", -1)), shout.frame)
	var text = _piece("StartText")
	if session.phase == BattleSession.Phase.INTRO:
		seen["start_pieces"] = text._shadows.size()
	var bubbles = _piece("FleeBubbles")
	if session.phase == BattleSession.Phase.LOADING and not bubbles.bubbles.is_empty():
		seen["bubbles_loading"] = true
	if session.phase == BattleSession.Phase.FIGHT:
		seen["bubbles_fight"] = int(seen.get("bubbles_fight", 0)) + bubbles.bubbles.size()
		seen["bars_step"] = _piece("PartnerStatusBars").step
		if not _piece("EnemyHpBars")._shown.is_empty():
			seen["enemy_bar"] = true
		if _piece("CommandMenu").blink == 1:
			seen["blink"] = true
	var numbers = _piece("EntityNumbers")
	for s in numbers.slots:
		for e in s["entries"]:
			if e["frame"] >= 0:
				seen["number_max"] = maxi(int(seen.get("number_max", -1)), e["frame"])
	if boxes.boxes[0].state == UIBoxes.STATE_OPEN and boxes.boxes[1].state == UIBoxes.STATE_OPEN:
		seen["end_boxes"] = true
	if boxes.boxes[2].state == UIBoxes.STATE_OPEN:
		seen["balance"] = true
	var countdown = _piece("DeathCountdown")
	if countdown.timer >= 0:
		seen["countdown_max"] = maxi(int(seen.get("countdown_max", -1)), countdown.timer)


func _check_win() -> void:
	_eq(session.outcome, 1, "the battle with the HUD ends in a win (%d frames)" % _frame)
	_eq((world as TestBattle.StubWorld).money, 25, "the bits box counted the bits")
	_eq(seen.get("bubbles_loading", false), true, "a flee bubble shows while loading")
	_eq(int(seen.get("bubbles_fight", 0)), 0, "the bubbles go with the loading")
	_eq(int(seen.get("start_pieces", 0)), BattleStartText.PIECES, "the start text draws its 155 pieces")
	_eq(int(seen.get("bars_step", 0)), 7, "the partner's bars slid in (7 steps)")
	_eq(seen.get("enemy_bar", false), true, "an enemy's HP bar shows after a hit")
	_eq(seen.get("blink", false), true, "the hovered command blinks while fighting")
	_eq(int(seen.get("number_max", -1)), 30, "a number shows for 31 frames")
	_eq(int(seen.get("shout_max", -1)), 19, "a shout shows for 20 frames")
	_eq(seen.get("end_boxes", false), true, "the stats and bits boxes opened")
	_eq(seen.get("balance", false), true, "the final balance box opened")
	_eq(hud.end_text_done(), true, "the end text is through")
	print("win with the HUD: %d frames, events %s" % [_frame, seen])


func _check_loss() -> void:
	_eq(session.outcome, -1, "the battle with the HUD ends in a loss")
	# The digit shows from DEATH_COUNTDOWN 0x14 to 0xAB: its own timer reaches 150 and it goes.
	_eq(int(seen.get("countdown_max", -1)), 0x96, "the countdown's digit runs 150 frames")
	_eq(_piece("DeathCountdown").timer if is_instance_valid(hud) else -1, -1, "the countdown is gone at the end")
	print("loss with the HUD: %d frames" % _frame)
