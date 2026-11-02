class_name ArenaScenes
extends RefCounted
## The arena's model scenes (specs/arena.md §4.7): object 0x19D's versus / draw, win, lose and
## champion scenes, and the podium. Logic only: where each object is, its rotation, whether it is
## shown, the lose scene's wipe and the champion's VRAM columns; the views draw them
## (scripts/ui/arena/arena_scene_view.gd, the podium in Arena). The lose scene rolls randomLimit
## when it is added (the camera's mode 5), so it lives here and not in a view.
## The session owns one (ArenaSession.scenes) and gives it to each match; both tick it in their
## objects. The champion's timeline is the session's (STD_tickChampionScene): it calls
## champion_letters (state 0) and champion_rise (state 1).

## STD_loadVersusSceneModel (std_hud.c:1157-1163): the start of the 4 DRAW.TMD objects.
const VERSUS_START := Vector3i(0x3E8, 0x78, 0x280)
## STD_tickVersusModelScene (1173): -200 a frame, object i after timer > 5i;
## STD_isVersusModelSceneFinished (1214): timer >= 0x51.
const VERSUS_STEP := 200
const VERSUS_DELAY := 5
const VERSUS_FRAMES := 0x51
## GsSetProjection in the renders: versus / champion 0x200 (std_hud.c:1196, std_effect.c:1356),
## win / lose 0x15E (std_effect.c:1495, 1581).
const PROJECTION_VERSUS := 0x200
const PROJECTION_RESULT := 0x15E

## STD_addWinScene (std_effect.c:1520-1531): objects 0-3's x, y 0, z -0x30C.
const WIN_X := [-0xFA, -0x32, 0x64, 0x104]
const WIN_Z := -0x30C
## STD_tickWinScene (1541): the timer stops at 0xA0; object i moves once timer > 6i + 0x3C, z +0x32
## up to 0xDC, its step up to 0x14.
const WIN_TIMER_MAX := 0xA0
const WIN_DELAY := 0x3C
const WIN_DELAY_STEP := 6
const WIN_Z_STEP := 0x32
const WIN_Z_END := 0xDC
const WIN_STEPS := 0x14
## STD_loadWinLoseModel (std_hud.c:1234-1246): the tables for i 0x14..0x28.
const WIN_TABLE_FIRST := 0x14
const WIN_ROT_X := 0x2000
const WIN_ROT_Y := 0x800
const WIN_ROT_DIV := 40
const WIN_FIRST_OFFSET := 0xE6
const WIN_LAST_OFFSET := 0x118
const WIN_CURVE_SPLIT := 0x24

## STD_loadWinLoseModel (std_hud.c:1258-1268): objects 4-7 at (0, -0x2BC, 0xDC).
const LOSE_START := Vector3i(0, -0x2BC, 0xDC)
## STD_addLoseScene / STD_tickLoseScene (std_effect.c:1401-1470).
const LOSE_COLUMNS := 0x20
const LOSE_TIMER_MAX := 0x8C
const LOSE_DELAY := 0x3D
const LOSE_DELAY_STEP := 3
const LOSE_STEPS := 0x16
const LOSE_WIPE_FROM := 0xB
const LOSE_WIPE_STEP := 0x3C
const LOSE_WIPE_MAX := 0xF0
const LOSE_TILT_FROM := 0x74
const LOSE_TILT_TO := 0x82
const LOSE_RESTART := 0x7F
const LOSE_FALL_FROM := 0x80
const LOSE_FALL_OFFSET := 0x320
## STD_renderLoseScene (1485): the columns 10 wide from x -0xA0, y -0x78.
const LOSE_COLUMN_W := 0xA

## STD_loadChampionModels (std_hud.c:1297-1342): 9 letters, scale (1, 2, 1), y 0xC8, z 0x7BC; x
## 0xC8 i - 0x2F8 for i < 5, then CHAMPION_X; the UV shift (8 - i) * -24, v + 0x30.
const CHAMPION_LETTERS := 9
const CHAMPION_SCALE := Vector3i(0x1000, 0x2000, 0x1000)
const CHAMPION_Y := 0xC8
const CHAMPION_Z := 0x7BC
const CHAMPION_X_STEP := 0xC8
const CHAMPION_X0 := -0x2F8
const CHAMPION_X := {5: 0xBE, 6: 0x168, 7: 0x230, 8: 0x2E4}
const CHAMPION_UV_V := 0x30
const CHAMPION_UV_U := -24
## STD_initializeChampionScene / STD_tickChampionScene (std_hud.c:1386-1395, std_effect.c:1271-1294):
## the VRAM columns (0x348 + 6i, 0x30) from (0x378 - (step + 1) * 2, 0), 6 x 0x30 words, column i
## from timer >= i + 0x3D for 0xB steps (the last from 0x378); a letter is shown at timer 5i + 5 and
## spins 0x200 a frame until 5i + 0x14. State 1: y +0x32 up to 0x258 (std_effect.c:1299-1302).
const COLUMN_SOURCE := 0x378
const COLUMN_PAGE := 0x340
const COLUMN_DELAY := 0x3D
const COLUMN_STEPS := 0xB
const COLUMN_LAST := 0xA
const LETTER_SHOW := 5
const LETTER_SPIN := 0x200
const LETTER_SPIN_END := 0x14
const RISE_STEP := 0x32
const RISE_END := 0x258
## The podium: STD_loadChampionModels (std_hud.c:1365) y -0x1E; state 1 -0x19 a frame (std_effect.c:1305).
const PODIUM_Y := -0x1E
const PODIUM_RISE := 0x19

## func(limit) -> int: randomLimit.
var roll: Callable = Rng.random_limit
## "", "versus", "win", "lose" or "champion" (the object 0x19D).
var active := ""
## STD_WIN_LOSS_DRAW_TIMER (the versus, win and lose scenes'; the champion's is the session's).
var timer := 0
## The scene's objects: STD_VERSUS_MODEL_OBJECTS (versus, champion) or STD_RESULT_MODEL_OBJECTS
## (win 0-3, lose 4-7): {location, rotation, scale: Vector3i, visible}.
var objects: Array[Dictionary] = []
## STD_MODEL_SCENE_STEPS.
var steps: Array[int] = []
## The lose scene: STD_LOSE_WIPE_HEIGHTS, STD_LOSE_WIPE_ORDER.
var wipe_heights: Array[int] = []
var wipe_order: Array[int] = []
## The champion's 9 VRAM columns: the page u each was last copied from.
var columns: Array[int] = []
var podium := false
var podium_y := PODIUM_Y

var _versus_target: Array = [-273, -86, 94, 272]
var _win_curve: Array = []
var _drop_y: Array = []
var _tilt: Array = []
var _win_rot_x: Array[int] = []
var _win_rot_y: Array[int] = []
var _win_first_x: Array[int] = []
var _win_last_x: Array[int] = []
## STD_RESULT_MODEL_OBJECTS 4-7 keep their state between scenes (set once a tournament).
var _lose_objects: Array[Dictionary] = []


func _init(game_data: Node) -> void:
	var recs: Array = game_data.system("arena") if game_data != null else []
	if not recs.is_empty():
		var s: Dictionary = recs[0].get("scenes", {})
		_versus_target = s.get("versus_target_x", _versus_target)
		_win_curve = s.get("win_x_curve", [])
		_drop_y = s.get("lose_drop_y", [])
		_tilt = s.get("lose_tilt", [])
	_load_win_lose()


static func _object(location: Vector3i, scale := Vector3i(0x1000, 0x1000, 0x1000), visible := true) -> Dictionary:
	return {"location": location, "rotation": Vector3i.ZERO, "scale": scale, "visible": visible}


## Which projection the current scene sets.
func projection() -> int:
	return PROJECTION_RESULT if active in ["win", "lose"] else PROJECTION_VERSUS


# --- the versus / draw scene (std_hud.c:1138-1225) -------------------------------------------------

## STD_loadVersusSceneModel + STD_addVersusModelScene.
func add_versus() -> void:
	timer = 0
	objects.clear()
	for i in 4:
		objects.append(_object(VERSUS_START))
	active = "versus"


func versus_finished() -> bool:
	return timer >= VERSUS_FRAMES


func remove_versus() -> void:
	if active == "versus":
		active = ""


func _tick_versus() -> void:
	timer += 1
	for i in 4:
		if timer > i * VERSUS_DELAY:
			var target := int(_versus_target[i])
			var loc: Vector3i = objects[i]["location"]
			if loc.x != target:
				loc.x = maxi(loc.x - VERSUS_STEP, target)
				objects[i]["location"] = loc


# --- the win and lose scenes (std_hud.c:1227-1271, std_effect.c:1401-1600) -------------------------

## STD_loadWinLoseModel's tables and objects 4-7 (STD_initializeTournament, once a tournament).
func _load_win_lose() -> void:
	_win_rot_x.clear()
	_win_rot_y.clear()
	_win_first_x.clear()
	_win_last_x.clear()
	for i in range(WIN_TABLE_FIRST, 0x29):
		_win_rot_x.append((i * WIN_ROT_X / WIN_ROT_DIV) & 0xFFF)
		_win_rot_y.append((i * WIN_ROT_Y / WIN_ROT_DIV + 0x800) & 0xFFF)
		var c := 0
		if _win_curve.size() > 0x10:
			c = int(_win_curve[WIN_CURVE_SPLIT - i]) if i < 0x25 else int(_win_curve[i - WIN_CURVE_SPLIT])
		_win_first_x.append(c - WIN_FIRST_OFFSET)
		_win_last_x.append(WIN_LAST_OFFSET - c)
	_lose_objects.clear()
	for i in 4:
		_lose_objects.append(_object(LOSE_START))


## The 8 STD_RESULT_MODEL_OBJECTS (0-3 the win scene's, 4-7 the lose scene's).
func _result_objects(win: Array[Dictionary]) -> void:
	objects.clear()
	objects.append_array(win)
	objects.append_array(_lose_objects)


## STD_addWinScene (std_effect.c:1516).
func add_win() -> void:
	timer = 0
	var win: Array[Dictionary] = []
	steps.assign([0, 0, 0, 0])
	for i in 4:
		win.append(_object(Vector3i(WIN_X[i], 0, WIN_Z)))
	_result_objects(win)
	active = "win"


func _tick_win() -> void:
	if timer < WIN_TIMER_MAX:
		timer += 1
	for i in 4:
		if timer > i * WIN_DELAY_STEP + WIN_DELAY:
			var o: Dictionary = objects[i]
			var loc: Vector3i = o["location"]
			if loc.z < WIN_Z_END:
				loc.z += WIN_Z_STEP
			if steps[i] < WIN_STEPS:
				steps[i] += 1
			o["rotation"] = Vector3i(_win_rot_x[steps[i]], _win_rot_y[steps[i]], 0)
			if i == 0:
				loc.x = _win_first_x[steps[i]]
			if i == 3:
				loc.x = _win_last_x[steps[i]]
			o["location"] = loc


## STD_addLoseScene (std_effect.c:1401): the wipe order rolled here (32 randomLimit(0x20)).
func add_lose() -> void:
	wipe_heights.clear()
	wipe_order.clear()
	for i in LOSE_COLUMNS:
		wipe_heights.append(0)
		wipe_order.append(i)
	for i in LOSE_COLUMNS:
		var j: int = roll.call(LOSE_COLUMNS)
		var t := wipe_order[i]
		wipe_order[i] = wipe_order[j]
		wipe_order[j] = t
	timer = 0
	steps.assign([0, 0, 0, 0])
	var win: Array[Dictionary] = []
	for i in 4:
		# Objects 0-3 aren't drawn by the lose scene (STD_renderLoseScene sorts 4-7).
		win.append(_object(Vector3i(WIN_X[i], 0, WIN_Z), Vector3i(0x1000, 0x1000, 0x1000), false))
	_result_objects(win)
	active = "lose"


func _drop(step: int) -> int:
	return int(_drop_y[step]) if step < _drop_y.size() else 0


func _tick_lose() -> void:
	if timer < LOSE_TIMER_MAX:
		timer += 1
	for k in 4:
		if timer >= LOSE_DELAY + k * LOSE_DELAY_STEP and steps[k] < LOSE_STEPS:
			steps[k] += 1
	for k in 4:
		if steps[k] >= LOSE_WIPE_FROM:
			for j in 8:
				var c := wipe_order[j + k * 8]
				if wipe_heights[c] < LOSE_WIPE_MAX:
					wipe_heights[c] += LOSE_WIPE_STEP
	if timer >= LOSE_TILT_FROM:
		if timer < LOSE_TILT_TO:
			var rx := int(_tilt[timer - LOSE_TILT_FROM]) if timer - LOSE_TILT_FROM < _tilt.size() else 0
			for k in 4:
				var r: Vector3i = objects[4 + k]["rotation"]
				r.x = rx
				objects[4 + k]["rotation"] = r
		if timer == LOSE_RESTART:
			steps[0] = 0
		if timer >= LOSE_FALL_FROM:
			var y := _drop(steps[0]) + LOSE_FALL_OFFSET
			for k in 4:
				_set_y(objects[4 + k], y)
	else:
		for k in 4:
			_set_y(objects[4 + k], _drop(steps[k]))


static func _set_y(o: Dictionary, y: int) -> void:
	var loc: Vector3i = o["location"]
	loc.y = y
	o["location"] = loc


## STD_removeWinScene / STD_removeLoseScene (std_setup.c:574, 578).
func remove_result() -> void:
	if active in ["win", "lose"]:
		active = ""


# --- the champion (std_hud.c:1273-1396, std_effect.c:1251-1398) ----------------------------------

## STD_loadChampionModels' letters and podium.
func load_champion() -> void:
	objects.clear()
	for i in CHAMPION_LETTERS:
		var x: int = CHAMPION_X.get(i, i * CHAMPION_X_STEP + CHAMPION_X0)
		objects.append(_object(Vector3i(x, CHAMPION_Y, CHAMPION_Z), CHAMPION_SCALE, false))
	podium_y = PODIUM_Y


## STD_addPodiumRenderer + STD_initializeChampionScene's columns + STD_addChampionScene.
func init_champion() -> void:
	podium = true
	steps.clear()
	columns.clear()
	for i in CHAMPION_LETTERS:
		steps.append(0)
		columns.append(_page_u(COLUMN_SOURCE))
	active = "champion"


static func _page_u(vram_x: int) -> int:
	return (vram_x - COLUMN_PAGE) * 4


## STD_tickChampionScene state 0's letters and columns, `t` the timer after its increment.
func champion_letters(t: int) -> void:
	for i in CHAMPION_LETTERS:
		if t >= i + COLUMN_DELAY and steps[i] < COLUMN_STEPS:
			var x := COLUMN_SOURCE - (steps[i] + 1) * 2 if steps[i] < COLUMN_LAST else COLUMN_SOURCE
			steps[i] += 1
			columns[i] = _page_u(x)
		if t >= i * LETTER_SHOW:
			var o: Dictionary = objects[i]
			if t == i * LETTER_SHOW + LETTER_SHOW:
				o["visible"] = true
			var r: Vector3i = o["rotation"]
			r.y = 0 if t >= i * LETTER_SHOW + LETTER_SPIN_END else (r.y + LETTER_SPIN) & 0xFFF
			o["rotation"] = r


## STD_tickChampionScene state 1's letters and podium.
func champion_rise() -> void:
	for i in CHAMPION_LETTERS:
		var o: Dictionary = objects[i]
		var loc: Vector3i = o["location"]
		if loc.y < RISE_END:
			loc.y += RISE_STEP
			o["location"] = loc
	podium_y -= PODIUM_RISE


## STD_removePodiumRenderer + STD_removeChampionScene.
func remove_champion() -> void:
	podium = false
	if active == "champion":
		active = ""


## STD_offsetTMDObjectUVs (std_hud.c:1105) on a UV of letter `letter`: the packed (v << 8 | u)
## word += (0x30 << 8) + (8 - letter) * -24 (u's borrow goes into v).
static func champion_uv(u: int, v: int, letter: int) -> Vector2i:
	var word := (v << 8 | u) + (CHAMPION_UV_V << 8) + (CHAMPION_LETTERS - 1 - letter) * CHAMPION_UV_U
	return Vector2i(word & 0xFF, (word >> 8) & 0xFF)


# --- the frame ------------------------------------------------------------------------------------

## The object's tick (the versus, win and lose scenes; the champion's is the session's).
func tick() -> void:
	match active:
		"versus":
			_tick_versus()
		"win":
			_tick_win()
		"lose":
			_tick_lose()
