extends ArenaHudPiece
## The arena's command menu (STD_addCommandMenu, STD_tickCommandMenu, STD_renderCommandMenu,
## STD_renderMoveName, STD_setCommandIconUV; std_main.c:1750-1850, 7467-7556): the labels from the
## left (STD_COMMAND_MENU_LAYOUTS by the command count), the command icons from the right, alternating
## up and down, the hovered one blinking (ArenaMatch.menu_blink), and while fighting (GAME_STATE 4) the
## cursor and the hovered command's name above. Tables: systems/arena command_menu. Layer 7. Fighter
## 0 only (the C's index `id` is 0 in the arena).

## STD_addCommandMenu: STD_COMMAND_MENU_TOP 0x44, BOTTOM TOP + 0x20.
const TOP := 0x44
const BOTTOM := TOP + 0x20
## STD_renderCommandMenu: the base x for id 0 (id * 0xA6 - 0x8C), the step 0xE, the labels from -0x8F.
const BASE_X := -0x8C
const STEP := 0xE
const LABEL_X := -0x8F
## Page (960, 256): the cursor at CLUT (282, 497), the icons (272, 496), the labels (272, 497).
const CURSOR_CLUT := 497
const ICON_CLUT := 496
const LABEL_CLUT := 497
## STD_renderMoveName: the text area's row 0xD8 (id 0), 0x90 x 0xC, drawn 0xE above the menu.
const NAME_V := 0xD8
const NAME_W := 0x90
const NAME_H := 0xC
## STD_COMMAND_NAMES[cmd - 1] (std_main.c:1498): text/std/std_main.yaml.
const COMMAND_TEXT := ["STD_STR_COMMAND_RUN", "STD_STR_COMMAND_ATTACK", "STD_STR_COMMAND_AUTO",
		"STD_STR_COMMAND_MODERATE", "STD_STR_COMMAND_DISTANCE", "STD_STR_COMMAND_DEFENSIVE",
		"STD_STR_COMMAND_CHANGE"]

var _name := ""


func on_visual(kind: String, args: Array) -> void:
	if kind == "command_menu":
		shown = bool(args[0])
		_name = ""


func build() -> void:
	if battle == null or data == null:
		return
	var cm: Dictionary = data.system("arena")[0]["command_menu"]
	var cmds: Array = battle.available_commands
	var n := cmds.size()
	if n < 2:
		return
	var count := n - 1
	var hovered: int = battle.hovered_command
	var base := BASE_X + count * STEP
	var fighting: bool = battle.game_state == ArenaMatch.GAME_FIGHT
	var added := []
	if fighting:
		added.append(_move_name(cmds[clampi(hovered, 0, n - 1)]))
		var x := base - hovered * STEP
		var top_first := (hovered % 2 == 0) if count % 2 == 0 else (hovered % 2 == 1)
		var p := ft4(BattleHudDraw.BTLCOMND, CURSOR_CLUT, 0x3D, 0xE0, 0x16, 0x16, x - 3, TOP if top_first else TOP + 0xA)
		p["kind"] = "cursor"
		added.append(p)
	for i in range(1, n):
		var uv := _icon_uv(cm, int(cmds[i]))
		if i == hovered and int(session.menu_blink) == 1:
			uv.position.x += 0x10
		var x := base - i * STEP
		var up := (i % 2 == 0) if count % 2 == 0 else (i % 2 == 1)
		var y0 := TOP + 3 if up else TOP + 0xD
		var y1 := BOTTOM - 0xD if up else BOTTOM - 3
		var p := ft4_quad(BattleHudDraw.BTLCOMND, ICON_CLUT, uv,
				[Vector2i(x, y0), Vector2i(x + 0x10, y0), Vector2i(x, y1), Vector2i(x + 0x10, y1)])
		p.merge({"kind": "icon", "index": i})
		added.append(p)
	var layout: Array = cm["layouts"][clampi(n - 2, 0, 7)]
	for i in n:
		var l := int(layout[i])
		var row_y := (i - 1) * STEP + 0xB if i > 0 else 0
		var width := 0xB if i == 0 or i == n - 1 else STEP
		var x := row_y + LABEL_X
		var p := ft4_quad(BattleHudDraw.BTLCOMND, LABEL_CLUT, Rect2i(int(cm["label_u"][l]), 0xE0, int(cm["label_w"][l]), 31),
				[Vector2i(x, TOP), Vector2i(x + width, TOP), Vector2i(x, BOTTOM), Vector2i(x + width, BOTTOM)], Color.WHITE, true)
		p.merge({"kind": "label", "index": i})
		added.append(p)
	added.reverse()
	prims = added


## STD_setCommandIconUV: a technique command (8-11) shows its technique's special icon, the others
## STD_COMMAND_ICON_UVS[cmd - 1]; 16 x 15.
func _icon_uv(cm: Dictionary, cmd: int) -> Rect2i:
	if cmd >= Battle.CMD_TECHNIQUE_0 and cmd <= Battle.CMD_FINISHER:
		var t := _technique(cmd)
		var special := int(battle.move(t).get("c", {}).get("special", 0)) if t != 0xFF else 0
		var s: Array = cm["special_icon_uvs"][clampi(special, 0, 7)]
		return Rect2i(int(s[0]), int(s[1]), 0x10, 0xF)
	var c: Array = cm["icon_uvs"][clampi(cmd - 1, 0, 7)]
	return Rect2i(int(c[0]), int(c[1]), 0x10, 0xF)


func _technique(cmd: int) -> int:
	var f: BattleFighter = battle.fighters[0]
	return battle.technique_of(f.entity, f.move_anim(cmd - Battle.CMD_TECHNIQUE_0))


## STD_renderMoveName: the name into the text area's row (cleared first), then renderString above
## the menu (color 0, layer 7, flag 1).
func _move_name(cmd: int) -> Dictionary:
	var name := ""
	if cmd >= Battle.CMD_TECHNIQUE_0 and cmd <= Battle.CMD_FINISHER:
		var t := _technique(cmd)
		name = str(data.localize(battle.move(t).get("name"))) if t != 0xFF else ""
	elif cmd >= 1 and cmd <= COMMAND_TEXT.size():
		name = data.text(COMMAND_TEXT[cmd - 1])
	if text_area != null and name != _name:
		text_area.clear(Rect2i(0, NAME_V, NAME_W, NAME_H))
		text_area.draw_string(name, 0, NAME_V)
	_name = name
	var p := text(0, BASE_X, TOP - 0xE, NAME_W, NAME_H, 0, NAME_V)
	p["kind"] = "name"
	return p
