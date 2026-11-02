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
	for p in prims:
		if p.has("fill"):
			var c: Color = p["fill"]
			if p.get("semi", false):
				c.a = 0.5
			draw_rect(Rect2(BattleHudDraw.CENTRE + Vector2(p["rect"].position), Vector2(p["rect"].size)), c)
		elif p.has("text"):
			if text_area != null:
				var r: Rect2i = p["rect"]
				text_area.render_string(self, int(p["color"]), r.position.x, r.position.y, r.size.x, r.size.y,
						int(p["u"]), int(p["v"]), bool(p["shadow"]))
		else:
			var info: Dictionary = IMAGES.get(p["image"], {"v": 0})
			var tex := BattleHudDraw.texture(p["image"], int(p["palette"]))
			var uv: Rect2i = p["uv"]
			var pts := []
			for q in p["pts"]:
				pts.append(Vector2(q))
			BattleHudDraw.quad(self, tex, Rect2(uv.position.x, uv.position.y - int(info["v"]), uv.size.x, uv.size.y),
					pts, p["color"], p["semi"])
