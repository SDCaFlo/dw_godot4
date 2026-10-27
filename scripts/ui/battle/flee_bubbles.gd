extends BattleHudPiece
## The bubbles over the Digimon at the battle's start (renderFleeBubble, btl.c:508; specs/battle.md
## §2.1): type 0 joins the fight, 1 runs off. Each rises over its Digimon for 5 frames, then
## pulses (FLEE_BUBBLE_SCALE); the bubble turns its tail to the Digimon, its mark sits in it. They
## go when the loading ends (LOAD_EFE_STATE 0) or after 200 frames.

const SCALE := [0x64, 0x68, 0x6C, 0x70, 0x74, 0x78, 0x74, 0x70, 0x6C, 0x68]
const LAST_FRAME := 0xC8
## The bubble's CLUT row (BI_IN palette 7).
const CLUT := 0x1E7

## entity -> {type, frame}
var bubbles := {}
## What this frame draws: [type, sx, sy, sc, rotate, w].
var _shown: Array = []


func on_visual(kind: String, args: Array) -> void:
	if kind == "flee_bubble":
		bubbles[int(args[0])] = {"type": int(args[1]), "frame": 0}


func tick(_pressed: int) -> void:
	_shown.clear()
	if session != null and session.phase != BattleSession.Phase.LOADING:
		bubbles.clear()
	for e in bubbles.keys():
		var b: Dictionary = bubbles[e]
		_shown.append(_place(e, b))
		b["frame"] += 1
		if b["frame"] == LAST_FRAME:
			bubbles.erase(e)
	queue_redraw()


func _place(entity: int, b: Dictionary) -> Array:
	var frame: int = b["frame"]
	var loc := world.location(entity)
	var height := world.height(entity)
	var y := -height - 0xC8 - (frame + 1) * 50 / 5 if frame < 5 else -height - 0xFA
	var p := world.project(Vector3i(loc.x, y, loc.z))
	var sc := world.projection_distance() * 144 / maxi(p.z, 1)
	if frame < 5:
		sc = sc * (frame + 1) / 5
	else:
		sc = sc * SCALE[(frame - 5) % 10] / 100
	var sx := clampi(p.x, -0x8C, 0x8C)
	var sy := clampi(p.y, -0x64, 0x64)
	var w := 0x18 if sc < 0x30 else 0x17
	var feet := world.project(loc)
	var rotate := PsxMath.atan(-(feet.y - sy), feet.x - sx) * 360
	return [b["type"], sx, sy, sc, rotate, w]


func _draw() -> void:
	var tex := BattleHudDraw.page_896(CLUT)
	for s in _shown:
		var type: int = s[0]
		var w: int = s[5]
		var scale: int = (s[3] << 12) / w
		BattleHudDraw.sprite(self, tex, type * 24 + 0xB8, BattleHudDraw.row(0x80), w, w, s[1], s[2], 0xB, 0xC,
				scale, scale, s[4])
		# The mark, a polygon added before the sprite: drawn over it, half-transparent.
		var size: int = s[3] * 2 / 3
		var cell := 0x10 if w == 0x18 else 0xF
		BattleHudDraw.rect(self, tex, type * 16 + 0xC8, BattleHudDraw.row(0x98), cell, cell,
				s[1] - size / 2, s[2] - size / 2, size, size, Color.WHITE, true)
