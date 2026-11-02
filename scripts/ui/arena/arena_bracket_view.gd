extends ArenaHudPiece
## The bracket and its intro (specs/arena.md §4.7): STD_renderBracket's STD_drawBracket and the
## sprites (std_main.c:3187-3189, 3212-3310, 3341-3392), the projectiles' and hit flashes' prims
## (drawn in their ticks: ArenaBracket.drawn_projectiles / drawn_flashes), and
## STD_renderBracketIntro (3704: the bracket picture, the subtractive overlay, the cup's title).
## Reads the tournament's ArenaBracket after its frame; up while its object is (the "bracket" /
## "bracket_intro" events). The names are built and never added in the US release (§8.1).

const PICTURE := "stdtim/05_bracket"
const ICONS := {0x380: "stdtim/00_digimon_icons_a", 0x3C0: "stdtim/01_digimon_icons_b"}
const ICONS_B := "stdtim/01_digimon_icons_b"
## The CLUT rows (GetClut(x, 0x1E0 + n)): palette n of the STDTIM images.
const CLUT := 0x1E0
## The title's CLUT (GetClut(0, 0x1E6)): the grade TIM's own row.
const TITLE_CLUT := 0x1E6
## STD_drawBracket (3297-3309): the picture (0, 0x78) 0xFF x 0x87 at (-0x80, -0x61), the box fill.
const PICTURE_UV := Rect2i(0, 0x78, 0xFF, 0x87)
const PICTURE_AT := Vector2i(-0x80, -0x61)
const SCREEN := Rect2i(-0xA0, -0x78, 0x140, 0xF0)
const BOX_GREY := 0x20
const NEUTRAL := 0x80
## STD_renderBracketDigimon: 16 x 16 cells, 15 at u / v 0xF0.
const CELL := 0x10
const CELL_EDGE := 0xF0
## STD_renderBracketProjectile (3623): v 0xC0, 8 x 8, the second one 8 below.
const SHOT_V := 0xC0
const SHOT := 8
## STD_tickBracketHitFlash (3594-3597): u 0, v 0xC8, 16 x 16, palette 0.
const FLASH_UV := Rect2i(0, 0xC8, 0x10, 0x10)
## STD_renderBracketIntro: the title (0, 0) 0xFF x 0x80 (0x7D in arena 1) at (-0x80, -0x40).
const TITLE_AT := Vector2i(-0x80, -0x40)
const TITLE_W := 0xFF
const TITLE_H := [0x80, 0x7D]
## The tpage modes (GetTPage's abr): the bracket and the title add, the overlay subtracts.
const ADD := 1
const SUBTRACT := 2

## The tournament (ArenaSession).
var tournament: Object
## "", "intro" or "bracket".
var mode := ""

var _title := ""


func on_visual(kind: String, args: Array) -> void:
	match kind:
		"bracket_intro":
			if bool(args[0]):
				mode = "intro"
			elif mode == "intro":
				mode = ""
		"bracket":
			if bool(args[0]):
				mode = "bracket"
			elif mode == "bracket":
				mode = ""
	shown = mode != ""


func tick(_pressed: int) -> void:
	prims.clear()
	if shown and tournament != null and tournament.bracket != null:
		build()
	queue_redraw()


func build() -> void:
	var b: Object = tournament.bracket
	var fade := int(b.fade)
	var added := []
	# STD_updateBracket's sprites (added first in layer 5, so drawn over the picture).
	if mode == "bracket":
		for i in 8:
			added.append(_sprite(i, fade))
	# STD_drawBracket: the picture, then the box fill (added last: drawn first).
	var pic := ft4(PICTURE, CLUT, PICTURE_UV.position.x, PICTURE_UV.position.y, PICTURE_UV.size.x, PICTURE_UV.size.y,
			PICTURE_AT.x, PICTURE_AT.y, 0, 0, BattleHudDraw.grey(NEUTRAL - fade))
	pic["kind"] = "picture"
	if fade != 0:
		pic.merge({"semi": true, "abr": ADD}, true)
	added.append(pic)
	var box := fill(SCREEN, Color8(BOX_GREY, BOX_GREY, BOX_GREY), true)
	box["kind"] = "box"
	added.append(box)
	added.reverse()
	prims = added
	if mode == "bracket":
		prims.append_array(_shots())
		prims.append_array(_flashes())
	else:
		prims.append_array(_intro(b, fade))


## STD_renderBracketDigimon(i).
func _sprite(i: int, fade: int) -> Dictionary:
	var sl: Dictionary = tournament.bracket.slots[i]
	var type := int(tournament.participants["participants"][i])
	var rec: Dictionary = data.digimon(type) if data != null else {}
	var cell: Dictionary = rec.get("bracket_sprite", {"page": 0x380, "u": 0, "v": 0})
	var frame := int(sl["frame"])
	var u := (int(cell["u"]) + (frame & 1) * CELL) & 0xFF
	var v := (int(cell["v"]) + (frame / 2) * CELL) & 0xFF
	var w := CELL - 1 if u == CELL_EDGE else CELL
	var h := CELL - 1 if v == CELL_EDGE else CELL
	var p := ft4(ICONS.get(int(cell["page"]), ICONS_B), CLUT + int(rec.get("bracket_sprite_clut", 0)), u, v, w, h,
			int(sl["x"]), int(sl["y"]), 0, 0, BattleHudDraw.grey(NEUTRAL - fade))
	if int(sl["facing"]) == 1:
		_mirror(p)
	if fade != 0:
		p.merge({"semi": true, "abr": ADD}, true)
	p.merge({"kind": "sprite", "index": i})
	return p


## Facing 1: x0 <-> x1, x2 <-> x3 (STD_setFlippedUV moves u one left so the PSX samples the same
## texels mirrored: the uv stays the cell).
static func _mirror(p: Dictionary) -> void:
	var pts: Array = p["pts"]
	p["pts"] = [pts[1], pts[0], pts[3], pts[2]]


## The projectiles' prims, layer 4 (each tick adds one, two with flag; drawn in reverse).
func _shots() -> Array:
	var out := []
	var cluts: Array = data.system("arena")[0]["bracket"]["projectile_cluts"] if data != null else []
	for d in tournament.bracket.drawn_projectiles:
		var slot := int(d["slot"])
		var icon := int(data.digimon(int(tournament.participants["participants"][slot])).get("bracket_icon", 1))
		var clut := int(cluts[icon - 1]) if icon >= 1 and icon - 1 < cluts.size() else 0
		for k in (2 if int(d["flag"]) == 1 else 1):
			var p := ft4(ICONS_B, CLUT + clut, icon * SHOT - SHOT, SHOT_V, SHOT, SHOT, int(d["x"]), int(d["y"]) + k * SHOT)
			if int(d["facing"]) == 1:
				_mirror(p)
			p.merge({"kind": "projectile", "index": slot})
			out.append(p)
	out.reverse()
	return out


## The hit flashes' prims, layer 3.
func _flashes() -> Array:
	var out := []
	for d in tournament.bracket.drawn_flashes:
		var p := ft4(ICONS_B, CLUT, FLASH_UV.position.x, FLASH_UV.position.y, FLASH_UV.size.x, FLASH_UV.size.y,
				int(d["x"]), int(d["y"]))
		p.merge({"kind": "flash", "index": int(d["slot"])})
		out.append(p)
	out.reverse()
	return out


## STD_renderBracketIntro's overlay (layer 3: FI_INFO's white texel, subtractive) and title (layer 2).
func _intro(b: Object, fade: int) -> Array:
	var overlay := fill(SCREEN, BattleHudDraw.grey(int(b.intro_overlay)), true)
	overlay.merge({"kind": "overlay", "abr": SUBTRACT})
	var arena := clampi(int(tournament.arena), 0, 1)
	var title := ft4(_title_image(), TITLE_CLUT, 0, 0, TITLE_W, TITLE_H[arena], TITLE_AT.x, TITLE_AT.y, 0, 0,
			BattleHudDraw.grey(int(b.intro_title)))
	title["kind"] = "title"
	if fade != NEUTRAL:
		title.merge({"semi": true, "abr": ADD}, true)
	return [overlay, title]


## The cup's grade_image (STD_GRADES[cup], loaded by STD_initializeTournament) as an asset path.
func _title_image() -> String:
	if _title == "" and data != null:
		for r in data.system("tournaments"):
			if int(r["id"]) == int(tournament.cup):
				var file := str(r.get("grade_image", "")).replace("\\", "/").trim_prefix("/")
				_title = "tim_files/" + file.get_basename()
	return _title
