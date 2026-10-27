extends BattleHudPiece
## The command menu (command_menu.c: BTL_tickCommandMenu, BTL_renderCommandMenu,
## BTL_drawHoveredCommandName): the label strip (BTL_COMMAND_MENU_LAYOUTS) and the commands' icons
## in a staggered row at the top left, unfolding with the slide (BattleSession's steps: SLIDE_Y
## then SLIDE_X, which the C's quads use as their top and bottom edges). While fighting
## (GAME_STATE 1) the hovered icon blinks every 8 frames, the cursor frames it and its name shows
## under the menu. A technique command shows its element's icon.

## Page (960, 256), BTLCOMND: icons palette 0, labels and cursor palette 1.
const ICON_CLUT := 496
const LABEL_CLUT := 497
const CURSOR_UV := Rect2i(0x3D, 0xE0, 0x16, 0x16)
const LABEL_V := 0xE0
## The hovered command's name: text-area row 0xD8, 0x90 x 0xC, at (-0x8C, -0x42), shadowed.
const NAME_ROW := 0xD8
const NAME_RECT := Rect2i(0, NAME_ROW, 0x90, 0xC)
const LAYOUTS := {3: 0, 4: 1, 5: 2, 7: 3, 8: 4, 9: 5}

## BTL_COMMAND_MENU_TIMER, BTL_COMMAND_MENU_BLINK.
var timer := 0
var blink := 0
var _name_drawn := ""


func tick(_pressed: int) -> void:
	if battle == null:
		return
	timer = (timer + 1) & 0xFF
	if session.command_menu_active() and battle.game_state == 1 and timer % 8 == 0:
		blink = (blink + 1) & 1
	if battle.game_state == 1:
		_draw_hovered_name()
	queue_redraw()


## BTL_drawHoveredCommandName: the command's name (a technique's for 8-11) into the text area.
func _draw_hovered_name() -> void:
	if text_area == null or battle.available_commands.is_empty():
		return
	var cmd := battle.available_commands[clampi(battle.hovered_command, 0, battle.available_commands.size() - 1)]
	var text := ""
	if cmd >= Battle.CMD_TECHNIQUE_0 and cmd < Battle.CMD_TECHNIQUE_0 + 4:
		var f := battle.fighters[0]
		var tech := battle.technique_of(f.entity, f.move_anim(cmd - Battle.CMD_TECHNIQUE_0))
		text = data.localize(battle.move(tech).get("name")) if tech != 0xFF else ""
	else:
		text = data.text("BTL_STR_COMMAND_%s" % ["RUN", "ATTACK", "YOUR_CALL", "MODERATE", "DISTANCE", "DEFENSIVE",
				"CHANGE"][cmd - 1]) if cmd >= 1 and cmd <= 7 else ""
	if text != _name_drawn:
		_name_drawn = text
		text_area.clear(NAME_RECT)
		text_area.draw_string(text.strip_edges(), 0, NAME_ROW)


func _icon_uv(cmd: int) -> Vector2i:
	var uvs: Array
	var index := cmd - 1
	if cmd >= Battle.CMD_TECHNIQUE_0 and cmd < Battle.CMD_TECHNIQUE_0 + 4:
		var f := battle.fighters[0]
		var tech := battle.technique_of(f.entity, f.move_anim(cmd - Battle.CMD_TECHNIQUE_0))
		uvs = BattleHudDraw.table(data, "BTL_SPECIAL_ICON_UVS")
		index = int(battle.move(tech).get("element", {}).get("id", 0)) if tech != 0xFF else 0
	else:
		uvs = BattleHudDraw.table(data, "BTL_COMMAND_ICON_UVS")
	if index < 0 or index >= uvs.size():
		return Vector2i.ZERO
	return Vector2i(int(uvs[index][0]), int(uvs[index][1]))


func _draw() -> void:
	if battle == null or session.phase == BattleSession.Phase.LOADING or session.phase == BattleSession.Phase.DONE:
		return
	var n := battle.available_commands.size()
	if n == 0:
		return
	var steps := session.command_menu_steps()
	var slide_x := BattleHudDraw.table(data, "BTL_COMMAND_MENU_SLIDE_X")
	var slide_y := BattleHudDraw.table(data, "BTL_COMMAND_MENU_SLIDE_Y")
	if slide_x.size() < 8 or slide_y.size() < 8:
		return
	# The C's BTL_COMMAND_MENU_X / _Y, used as the quads' top and bottom.
	var top := int(slide_x[steps.x])
	var bottom := int(slide_y[steps.y])
	var count := n - 1
	var base := count * 0xE - 0x8C
	var fighting := battle.game_state == 1
	# One layer, in reverse of the adds: the labels, the icons (last first), the cursor.
	var layout: Array = BattleHudDraw.table(data, "BTL_COMMAND_MENU_LAYOUTS")[LAYOUTS.get(n, 0)]
	var label_u := BattleHudDraw.table(data, "BTL_COMMAND_LABEL_U")
	var label_w := BattleHudDraw.table(data, "BTL_COMMAND_LABEL_W")
	for i in range(n - 1, -1, -1):
		var row_x := (i - 1) * 0xE + 0xB if i > 0 else 0
		var width := 0xB if i == 0 or i == n - 1 else 0xE
		var kind := int(layout[i])
		var x := row_x - 0x8F
		BattleHudDraw.quad(self, BattleHudDraw.page_960(LABEL_CLUT, LABEL_V),
				Rect2(int(label_u[kind]), BattleHudDraw.row(LABEL_V), int(label_w[kind]), 31),
				[Vector2(x, top), Vector2(x + width, top), Vector2(x, bottom), Vector2(x + width, bottom)], Color.WHITE, true)
	for i in range(n - 1, 0, -1):
		var uv := _icon_uv(battle.available_commands[i])
		if i == battle.hovered_command and blink == 1:
			uv.x += 0x10
		var x := base - i * 0xE
		var up := (i % 2 == 0) if count % 2 == 0 else (i % 2 == 1)
		var y0 := top + 3 if up else top + 0xD
		var y1 := bottom - 0xD if up else bottom - 3
		BattleHudDraw.quad(self, BattleHudDraw.page_960(ICON_CLUT, uv.y), Rect2(uv.x, BattleHudDraw.row(uv.y), 0x10, 0xF),
				[Vector2(x, y0), Vector2(x + 0x10, y0), Vector2(x, y1), Vector2(x + 0x10, y1)])
	if fighting:
		var h := battle.hovered_command
		var x := base - h * 0xE
		var up := (h % 2 == 0) if count % 2 == 0 else (h % 2 == 1)
		var y := -0x64 if up else -0x5A
		BattleHudDraw.rect(self, BattleHudDraw.page_960(LABEL_CLUT, CURSOR_UV.position.y), CURSOR_UV.position.x,
				BattleHudDraw.row(CURSOR_UV.position.y), CURSOR_UV.size.x, CURSOR_UV.size.y, x - 3, y, 0x16, 0x16)
		if text_area != null:
			text_area.render_string(self, 0, -0x8C, -0x42, NAME_RECT.size.x, NAME_RECT.size.y, 0, NAME_ROW, true)
