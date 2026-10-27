class_name BattleStartText
extends RefCounted
## The battle's start text (battle_hud.c:532-850): 155 digit pieces that fly in to spell the
## message, then burst off screen. Their motion lives in the C's draw code and decides when the
## intro ends (BTL_isBattleStartTextFinished), and its set-up draws random numbers, so it is logic
## here; the HUD draws `pieces`.

const PIECES := 155
## The text's projection (BTL_BATTLE_START_TEXT_MATRIX, projection 0x200).
const MATRIX := [0x100A, 0, 0, 0, 0x8E4, -0xD67, 0, 0xD5E, 0x8E9, 0, -2, 0x2D4]
const PROJECTION := 0x200

## Per piece: {x, y, speed (int8 [0x10]), trail ([0x12]), digit ([0x13]), order ([0x11]),
## vx, vy ([6], [7]), rot (Vector3i)}.
var pieces: Array[Dictionary] = []
var finished := false
var bursting := false
## BTL_BATTLE_START_TEXT_TIMER[0] (the finished text's colour cycle).
var timer := 0
var _positions: Array = []


func _init(data: Node) -> void:
	for r in data.system("battle_hud"):
		if r["name"] == "BTL_BATTLE_START_TEXT_POSITIONS":
			for p in r["values"]:
				_positions.append(Vector2i(int(p[0]), int(p[1])))


func target(i: int) -> Vector2i:
	return _positions[i] if i < _positions.size() else Vector2i.ZERO


## BTL_initializeBattleStartText (with BTL_shuffleBattleStartTextPieces).
func start() -> void:
	timer = 0
	finished = false
	bursting = false
	pieces.clear()
	for i in PIECES:
		pieces.append({"order": i, "trail": 0x18, "digit": Rng.random_limit(3), "x": 0, "y": 0, "speed": 0,
				"vx": 0, "vy": 0, "rot": Vector3i.ZERO})
	for i in PIECES:
		var r := Rng.random_limit(PIECES)
		var t: int = pieces[i]["order"]
		pieces[i]["order"] = pieces[r]["order"]
		pieces[r]["order"] = t
	for i in PIECES:
		var p: Dictionary = pieces[i]
		var sgn := 1 if Rng.random_limit(2) == 1 else -1
		var goal := target(i)
		p["y"] = goal.y
		p["speed"] = PsxMath.s8(-sgn * ((Rng.random_limit(3) + 1) << 5))
		var spread := 500 if i < 0x33 else (600 if i < 0x65 else 700)
		p["x"] = sgn * spread + Rng.random_limit(100) - 50
		var r := Rng.random_limit(5)
		p["vx"] = PsxMath.div((r + 8) * goal.x, 8)
		p["vy"] = PsxMath.div((r + 8) * goal.y, 8)
		p["rot"] = Vector3i.ZERO


## BTL_renderBattleStartText's motion: each piece slides to its place, then its trail shrinks;
## the text is finished once every trail is gone.
func tick_assemble() -> void:
	var settled := 0
	for p in pieces:
		if p["trail"] != 0:
			break
		settled += 1
	if settled == PIECES:
		timer += 1
		finished = true
	for i in PIECES:
		var p: Dictionary = pieces[i]
		var goal := target(i)
		if p["x"] != goal.x:
			p["x"] = PsxMath.s16(p["x"] + p["speed"])
			if (p["speed"] > 0 and p["x"] > goal.x) or (p["speed"] <= 0 and p["x"] < goal.x):
				p["x"] = goal.x
		elif p["trail"] != 0:
			p["trail"] = (p["trail"] - 4) & 0xFF


## BTL_initializeBattleStartTextBurst.
func start_burst() -> void:
	finished = false
	bursting = true


## BTL_renderBattleStartTextBurst's motion: each piece spins and flies outward until its corner
## leaves the screen (projected through the text's matrix).
func tick_burst() -> void:
	var dead := 0
	for p in pieces:
		if p["vx"] == 0 and p["vy"] == 0:
			dead += 1
			p["quad"] = []
			continue
		var m := PsxMath.rot_matrix(p["rot"])
		# The four corners as this frame draws them (the HUD's quad), before the piece moves.
		var quad := []
		for c in [Vector3i(-4, -6, 0), Vector3i(4, -6, 0), Vector3i(-4, 6, 0), Vector3i(4, 6, 0)]:
			var corner := PsxMath.apply_matrix_sv(m, c)
			quad.append(project(Vector3i(corner.x + p["x"] - 4, corner.y + p["y"] - 6, corner.z)))
		p["quad"] = quad
		var screen: Vector2i = quad[0]
		var rot: Vector3i = p["rot"]
		match p["digit"]:
			0:
				rot.x += 0x100
				rot.y += 0x100
			1:
				rot.y += 0x100
				rot.z += 0x100
			2:
				rot.x += 0x100
				rot.z += 0x100
		p["rot"] = PsxMath.s16_vec(rot)
		if screen.x < -0xB4 or screen.x >= 0xB5 or screen.y < -0x8C or screen.y >= 0x8D:
			p["vx"] = 0
			p["vy"] = 0
		p["x"] = PsxMath.s16(p["x"] + p["vx"])
		p["y"] = PsxMath.s16(p["y"] + p["vy"])
	if dead == PIECES:
		finished = true


## RotTransPers with the text's matrix: the screen position (centred).
static func project(v: Vector3i) -> Vector2i:
	var m := PackedInt32Array(MATRIX)
	var p := PsxMath.apply_matrix_lv(m, PsxMath.s16_vec(v)) + PsxMath.translation(m)
	var z := maxi(p.z, 1)
	return Vector2i(PsxMath.div(p.x * PROJECTION, z), PsxMath.div(p.y * PROJECTION, z))
