extends BattleHudPiece
## The battle's start text (battle_hud.c: BTL_renderBattleStartText, BTL_renderBattleStartTextBurst):
## 155 small digit pieces (BI_IN, 8 x 8 at u 0x80 + digit * 8) that fly in from the sides with a
## half-transparent trail to spell the message, flash through palettes 8-10 once in place, then
## spin and burst off the screen. Their motion is BattleStartText's (logic: it ends the intro);
## this piece draws them through the text's own projection, each with a black shadow 2 px
## down-right behind every piece.

const V := 0x80
const CLUT := 488

var _shadows: Array = []
var _layer: Array = []


func tick(_pressed: int) -> void:
	_shadows.clear()
	_layer.clear()
	if session == null:
		queue_redraw()
		return
	var text: BattleStartText = session.start_text
	match session.start_text_state():
		1:
			_assemble(text)
		2:
			_burst(text)
	queue_redraw()


func _assemble(text: BattleStartText) -> void:
	var clut := CLUT
	if text.finished:
		clut = CLUT + (text.timer - 1) % 6 / 2
	for i in BattleStartText.PIECES:
		var p: Dictionary = text.pieces[i]
		var x: int = p["x"]
		var y: int = p["y"]
		var q := [BattleStartText.project(Vector3i(x, y, 0)), BattleStartText.project(Vector3i(x + 8, y, 0)),
				BattleStartText.project(Vector3i(x, y + 0xC, 0)), BattleStartText.project(Vector3i(x + 8, y + 0xC, 0))]
		var parts := []
		if not text.finished:
			var trail: int = p["trail"]
			var t := []
			var uv: Rect2
			if p["speed"] > 0:
				t = [Vector3i(x - trail, y, 0), Vector3i(x, y, 0), Vector3i(x - trail, y + 0xC, 0), Vector3i(x, y + 0xC, 0)]
				uv = Rect2(0x9E, BattleHudDraw.row(V), -24, 8)
			else:
				t = [Vector3i(x + 8, y, 0), Vector3i(x + 8 + trail, y, 0), Vector3i(x + 8, y + 0xC, 0),
						Vector3i(x + 8 + trail, y + 0xC, 0)]
				uv = Rect2(0x86, BattleHudDraw.row(V), 24, 8)
			# The trail is added after the digit: drawn before it.
			parts.append([clut, uv, t.map(func(v: Vector3i) -> Vector2i: return BattleStartText.project(v)), true])
		parts.append([clut, Rect2(p["digit"] * 8 + 0x80, BattleHudDraw.row(V), 8, 8), q, false])
		_layer.push_front(parts)
		_shadows.push_front(q)


func _burst(text: BattleStartText) -> void:
	for i in BattleStartText.PIECES:
		var p: Dictionary = text.pieces[i]
		var q: Array = p.get("quad", [])
		if q.is_empty():
			continue
		_layer.push_front([[CLUT, Rect2(p["digit"] * 8 + 0x80, BattleHudDraw.row(V), 8, 8), q, false]])
		_shadows.push_front(q)


func _draw() -> void:
	# Layer 6: the shadows (POLY_F4, black), then layer 5: the pieces, the last added first.
	for q in _shadows:
		var pts := PackedVector2Array()
		for k in [0, 1, 3, 2]:
			pts.append(BattleHudDraw.CENTRE + Vector2(q[k]) + Vector2(2, 2))
		draw_primitive(pts, PackedColorArray([Color.BLACK, Color.BLACK, Color.BLACK, Color.BLACK]), PackedVector2Array())
	for parts in _layer:
		for part in parts:
			var pts := []
			for v in part[2]:
				pts.append(Vector2(v))
			BattleHudDraw.quad(self, BattleHudDraw.page_896(part[0]), part[1], pts, Color.WHITE, part[3])
