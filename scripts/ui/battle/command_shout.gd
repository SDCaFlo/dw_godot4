extends BattleHudPiece
## The tamer's shout when he gives an order (command_shout.c: BTL_drawCommandShout,
## BTL_renderCommandShout): the order ("Run!", "Attack!", … or the technique's name) drawn into
## the text area's row 204, shown over the tamer for 20 frames. It grows over its first 4 frames
## and hops up (or, high on the screen, drops down) by BTL_SHOUT_HOP / DROP_OFFSETS, with a black
## shadow 1 px down-right.

const ROW := 204
const AREA := Rect2i(0, ROW, 168, 12)
const FRAMES := 20
const SHOUTS := ["BTL_STR_SHOUT_RUN", "BTL_STR_SHOUT_ATTACK", "BTL_STR_SHOUT_YOUR_CALL", "BTL_STR_SHOUT_MODERATE",
		"BTL_STR_SHOUT_DISTANCE", "BTL_STR_SHOUT_DEFENSE", "BTL_STR_SHOUT_CHANGE"]

## BTL_COMMAND_SHOUT: frame (-1 none), x, y, width.
var frame := -1
var at := Vector2i.ZERO
var width := 0
## The frame this draw shows (the C's render counts it up).
var _shown := -1


func on_visual(kind: String, args: Array) -> void:
	if kind == "shout":
		shout(int(args[0]))


## BTL_drawCommandShout.
func shout(command: int) -> void:
	frame = 0
	var pos := world.screen_position(BattleSession.TAMER, 4)
	text_area.clear(AREA)
	var label := ""
	if command >= Battle.CMD_TECHNIQUE_0 and command < Battle.CMD_TECHNIQUE_0 + 4:
		var f := battle.fighters[0]
		var tech := battle.technique_of(f.entity, f.move_anim(command - Battle.CMD_TECHNIQUE_0))
		label = data.localize(battle.move(tech).get("name")) if tech != 0xFF else ""
	elif command >= 1 and command <= SHOUTS.size():
		label = data.text(SHOUTS[command - 1])
	text_area.draw_string(label, 0, ROW)
	# US: 12 px per character, whatever the glyphs' widths.
	width = label.length() * 12
	if pos.x - width / 2 < -140:
		pos.x = width / 2 - 140
	if pos.x + width / 2 >= 141:
		pos.x = 140 - width / 2
	at = Vector2i(pos.x, clampi(pos.y, -100, 100))


func tick(_pressed: int) -> void:
	_shown = frame
	if frame != -1:
		frame += 1
		if frame >= FRAMES:
			frame = -1
	queue_redraw()


func _draw() -> void:
	if _shown < 0 or text_area == null:
		return
	var scale := ((_shown * 2 + 2) << 12) / 10 if _shown < 4 else 0x1000
	var offsets := BattleHudDraw.table(data, "BTL_SHOUT_DROP_OFFSETS" if at.y < -40 else "BTL_SHOUT_HOP_OFFSETS")
	var y := at.y + (int(offsets[_shown]) if _shown < offsets.size() else 0)
	var s := scale / 4096.0
	var size := Vector2(width, 12) * s
	# GsSortSprite with its pivot (w / 2, 6) at (x, y): the shadow first (added second), then the text.
	var origin := BattleHudDraw.CENTRE + Vector2(at.x, y) - Vector2(width / 2, 6) * s
	var src := Rect2(0, ROW, width, 12)
	var tex := text_area.texture()
	draw_texture_rect_region(tex, Rect2(origin + Vector2(1, 1), size), src, Color.BLACK)
	draw_texture_rect_region(tex, Rect2(origin, size), src)
