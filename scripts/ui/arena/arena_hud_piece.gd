class_name ArenaHudPiece
extends BattleHudPiece
## One piece of the arena's HUD (specs/arena.md §4.6): BattleHudPiece's API, with `session` the
## current ArenaMatch. Each frame `tick` lists what the C draws in `prims`, in drawing order (the
## ordering table's layers back to front, a layer's primitives in reverse of the C's AddPrim), and
## `_draw` only draws that list (the tests read it):
## - a POLY_FT4: {"image", "palette", "uv": Rect2i (the C's page u, v, w, h), "pts": [4 points in
##   the C's order: top-left, top-right, bottom-left, bottom-right], "color", "semi"} (+ the piece's
##   own keys: "kind", "index", …);
## - a POLY_F4 / GsBOXF: {"fill": Color, "rect": Rect2i, "semi"};
## - either with "abr" (0-3): semi-transparent with that tpage mode (add, subtract, ...) instead of the
##   50 / 50 of "semi" alone; drawn through child canvas items, one per run of a mode;
## - a renderString: {"text": true, "color", "rect": Rect2i (the screen place), "u", "v", "shadow"}.
## Screen coordinates are the C's, relative to the screen centre.

## The texture pages the arena HUD draws from, as converted images: the image's first page v (its
## rows start there) and its first CLUT row (palette 0).
const IMAGES := {
	"stdtim/02_time_up": {"v": 0, "clut": 480},
	"stdtim/03_font_large": {"v": 0, "clut": 480},
	"tim_files/STDDAT/TIME": {"v": 0x78, "clut": 255},
	BattleHudDraw.BI_IN: {"v": 0x80, "clut": BattleHudDraw.BI_IN_CLUT},
	BattleHudDraw.BTLCOMND: {"v": 0xC0, "clut": BattleHudDraw.BTLCOMND_CLUT},
	"stdtim/00_digimon_icons_a": {"v": 0, "clut": 480},
	"stdtim/01_digimon_icons_b": {"v": 0, "clut": 480},
	"stdtim/05_bracket": {"v": 0x78, "clut": 480},
}

var prims: Array = []
## Whether the C object is up (its add / remove events).
var shown := false


func tick(_pressed: int) -> void:
	prims.clear()
	if shown and session != null:
		build()
	queue_redraw()


## Fills `prims` for this frame (the C's render function).
func build() -> void:
	pass


## A POLY_FT4 from setUVWH / setXYWH (`dw`, `dh` the drawn size; 0: the texel size).
func ft4(image: String, clut_y: int, u: int, v: int, w: int, h: int, x: int, y: int, dw := 0, dh := 0,
		color := Color.WHITE, semi := false) -> Dictionary:
	dw = w if dw == 0 else dw
	dh = h if dh == 0 else dh
	return ft4_quad(image, clut_y, Rect2i(u, v, w, h),
			[Vector2i(x, y), Vector2i(x + dw, y), Vector2i(x, y + dh), Vector2i(x + dw, y + dh)], color, semi)


## A POLY_FT4 on free corners (setXY4).
func ft4_quad(image: String, clut_y: int, uv: Rect2i, pts: Array, color := Color.WHITE, semi := false) -> Dictionary:
	var info: Dictionary = IMAGES.get(image, {"v": 0, "clut": clut_y})
	return {"image": image, "palette": clut_y - int(info["clut"]), "uv": uv, "pts": pts, "color": color, "semi": semi}


## A POLY_F4 or GsBOXF.
func fill(rect: Rect2i, color: Color, semi := false) -> Dictionary:
	return {"fill": color, "rect": rect, "semi": semi}


## renderString(color, x, y, w, h, u, v, layer, flag): the text area's (u, v) w x h at (x, y).
func text(color: int, x: int, y: int, w: int, h: int, u: int, v: int, shadow := true) -> Dictionary:
	return {"text": true, "color": color, "rect": Rect2i(x, y, w, h), "u": u, "v": v, "shadow": shadow}


## The C's digits right-aligned in `places` cells `step` apart (convertValueToDigits: the least
## significant at the right, no leading zeros), each a POLY_FT4 from `make(digit, x)`; added most
## significant first (i = count - 1 .. 0), so drawn least significant first.
func digit_prims(value: int, places: int, x: int, step: int, make: Callable) -> Array:
	var d := BattleHudDraw.digits(value, places)
	var out := []
	for k in d.size():
		var i := d.size() - 1 - k
		out.append(make.call(d[k], x + ((places - 1) - i) * step))
	out.reverse()
	return out


func _draw() -> void:
	if not prims.any(func(p: Dictionary) -> bool: return p.has("abr")):
		_hide_runs(0)
		for p in prims:
			_draw_prim(self, p)
		return
	# Some primitives blend with a tpage mode (add, subtract): each run of one mode is drawn by a
	# child canvas item with that blend material, in order. A textured one's opaque texels (no STP
	# bit) and its STP texels go to two runs (the mode applies to the STP texels only).
	var runs: Array = []
	for p in prims:
		if not p.has("abr"):
			_add_run(runs, -1, [p, PART_ALL])
		elif p.has("fill"):
			_add_run(runs, int(p["abr"]), [p, PART_ALL])
		else:
			_add_run(runs, -1, [p, PART_BASE])
			_add_run(runs, int(p["abr"]), [p, PART_STP])
	for i in runs.size():
		var run := _run(i)
		run.visible = true
		run.material = PsxUiFilter.material(BLEND_NAMES[runs[i][0]])
		run.items = runs[i][1]
		run.queue_redraw()
	_hide_runs(runs.size())


const PART_ALL := 0
const PART_BASE := 1
const PART_STP := 2
## The tpage's semi-transparency modes (abr) as PsxUiFilter blends: 0 half (mix at 0.5), 1 add,
## 2 subtract, 3 add a quarter (add at 0.25); -1 opaque.
const BLEND_NAMES := {-1: "mix", 0: "mix", 1: "add", 2: "sub", 3: "add"}

var _runs: Array[Control] = []


class Run extends Control:
	var piece: ArenaHudPiece
	var items: Array = []

	func _draw() -> void:
		for it in items:
			piece._draw_prim(self, it[0], it[1])


static func _add_run(runs: Array, mode: int, item: Array) -> void:
	if runs.is_empty() or runs[-1][0] != mode:
		runs.append([mode, []])
	runs[-1][1].append(item)


func _run(i: int) -> Run:
	while _runs.size() <= i:
		var r := Run.new()
		r.piece = self
		r.mouse_filter = MOUSE_FILTER_IGNORE
		r.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(r)
		_runs.append(r)
	return _runs[i]


func _hide_runs(from: int) -> void:
	for i in range(from, _runs.size()):
		_runs[i].visible = false
		_runs[i].items = []


## One primitive on `canvas` (this piece or one of its runs); `part` the texels drawn.
func _draw_prim(canvas: CanvasItem, p: Dictionary, part := PART_ALL) -> void:
	var abr := int(p.get("abr", -1))
	if p.has("fill"):
		var c: Color = p["fill"]
		if abr == 3:
			c.a = 0.25
		elif p.get("semi", false) and abr <= 0:
			c.a = 0.5
		canvas.draw_rect(Rect2(BattleHudDraw.CENTRE + Vector2(p["rect"].position), Vector2(p["rect"].size)), c)
	elif p.has("text"):
		if text_area != null:
			var r: Rect2i = p["rect"]
			text_area.render_string(canvas, int(p["color"]), r.position.x, r.position.y, r.size.x, r.size.y,
					int(p["u"]), int(p["v"]), bool(p["shadow"]))
	else:
		var info: Dictionary = IMAGES.get(p["image"], {"v": 0})
		var tex := BattleHudDraw.texture(p["image"], int(p["palette"]))
		var uv: Rect2i = p["uv"]
		var pts := []
		for q in p["pts"]:
			pts.append(Vector2(q))
		var rect := Rect2(uv.position.x, uv.position.y - int(info["v"]), uv.size.x, uv.size.y)
		if part == PART_ALL:
			BattleHudDraw.quad(canvas, tex, rect, pts, p["color"], p["semi"])
		elif tex != null:
			var t: Color = p["color"]
			if part == PART_STP and abr == 3:
				t.a *= 0.25
			elif part == PART_STP and abr == 0:
				t.a *= 0.5
			_quad(canvas, tex.base if part == PART_BASE else tex.stp, rect, pts, t)


## BattleHudDraw.quad's mapping, one texture.
static func _quad(canvas: CanvasItem, texture: Texture2D, uv: Rect2, pts: Array, tint: Color) -> void:
	if texture == null:
		return
	var size := texture.get_size()
	var u0 := uv.position.x / size.x
	var u1 := (uv.position.x + uv.size.x) / size.x
	var v0 := uv.position.y / size.y
	var v1 := (uv.position.y + uv.size.y) / size.y
	var c := BattleHudDraw.CENTRE
	canvas.draw_primitive(PackedVector2Array([c + pts[0], c + pts[1], c + pts[3], c + pts[2]]),
			PackedColorArray([tint, tint, tint, tint]),
			PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]), texture)
