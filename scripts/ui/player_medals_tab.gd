class_name PlayerMedalsTab
extends Node
## The Player screen's medals (renderMedalView, game_menu.c:3664, the cursor in tickPlayerMenu
## :2045, renderDigiviceMedals :4024; specs/status_screens.md §4.3): 15 medal slots; ✕ moves a
## cursor, the selected medal won turns as a 3D model (ETCNA/MEDAL.TMD) beside its name and lines.

## MEDAL_VIEW_TEXT_AREA, MEDAL_DETAIL_AREA.
const TEXT_AREA := Rect2i(0, 12, 256, 200)
const DETAIL_AREA := Rect2i(0, 24, 252, 48)
const COUNT := 15
## MEDAL_NAMES (game_menu.c:1011) and MEDAL_DESCRIPTIONS (US, :1078): three lines a medal,
## "" for STR_OVERWORLD_EMPTY.
const NAMES := ["STR_MEDAL_NAME_GRADE_CUP", "STR_MEDAL_NAME_VERSION_CUP", "STR_MEDAL_NAME_TYPE_CUP",
		"STR_MEDAL_NAME_SPECIAL_CUP", "STR_MEDAL_NAME_100_TIMES", "STR_MEDAL_NAME_TECHNIQUE_MASTER",
		"STR_MEDAL_NAME_DIGIMON_MASTER", "STR_MEDAL_NAME_MAX_ABILITIES", "STR_MEDAL_NAME_PERFECT_CURLING",
		"STR_MEDAL_NAME_100_FISH", "MAIN_D_80134248", "STR_MEDAL_NAME_TOWN_FLOURISHING",
		"STR_MEDAL_NAME_CARD_COMPLETE", "STR_MEDAL_NAME_BITS_MAXED", "STR_MEDAL_NAME_10_YEARS"]
const DESCRIPTIONS := [
		"STR_MEDAL_DESCRIPTION_CUP_D_C_B_A_S", "STR_MEDAL_DESCRIPTION_WIN_IN_ALL", "",
		"STR_MEDAL_DESCRIPTION_WIN_IN_ALL_VER_1_2", "", "",
		"STR_MEDAL_DESCRIPTION_FIRE_GRAPPLE_THUNDER_WIND", "STR_MEDAL_DESCRIPTION_NATURE_COOL_METALLIC_FILTH_CUP",
		"STR_MEDAL_DESCRIPTION_WIN_IN_ALL",
		"", "STR_MEDAL_DESCRIPTION_DINO_WING_ANIMAL_HUMAN_CUP", "STR_MEDAL_DESCRIPTION_WIN_IN_ALL",
		"", "STR_MEDAL_DESCRIPTION_WON_CHAMPIONSHIP_100_TIMES", "",
		"", "STR_MEDAL_DESCRIPTION_MASTERED_56_SWITCH_TECHNIQUES", "",
		"", "STR_MEDAL_DESCRIPTION_RAISED_ALL_61_DIGIMON", "",
		"", "STR_MEDAL_DESCRIPTION_MAXED_ALL_OF_THE_DIGIMONS", "STR_MEDAL_DESCRIPTION_PARAMETERS",
		"", "STR_MEDAL_DESCRIPTION_GOT_A_PERFECT_SCORE_IN_CURLING", "",
		"", "STR_MEDAL_DESCRIPTION_100_FISH_CAUGHT", "",
		"", "STR_MEDAL_DESCRIPTION_FINISHED_THE_GAME", "",
		"", "STR_MEDAL_DESCRIPTION_JIJIMON_SAID_THE_TOWN", "STR_MEDAL_DESCRIPTION_IS_FLOURISHING",
		"", "STR_MEDAL_DESCRIPTION_COLLECTED_ALL_DIGIMON_CARDS", "",
		"", "STR_MEDAL_DESCRIPTION_COLLECTED_999999_BITS", "",
		"", "STR_MEDAL_DESCRIPTION_SURVIVED_FOR_300_DAYS", ""]
## MAIN_D_8012472C: x1, y1, x2, y2, colour.
const LINES := [[-146, -67, 146, -67, 0], [-147, -66, 147, -66, 1], [-146, -65, 146, -65, 0], [71, -65, 146, -65, 0],
		[69, -64, 69, 12, 0], [70, -65, 70, 15, 1], [71, -64, 71, 14, 0], [-146, 14, 70, 14, 0], [71, 14, 146, 14, 0],
		[-147, 15, 147, 15, 1], [-146, 16, 146, 16, 0], [-147, 79, 145, 79, 0], [-148, 80, 146, 80, 1],
		[-147, 81, 145, 81, 0]]
## The footer (US): colour, x, width, u (row 0x0C, y 0x55).
const FOOTER := [[PlayerScreen.FOOTER_GLYPH1, -0x23, 0x0C, 0x6C], [0, -0x17, 0x18, 0x84], [0, 1, 0x24, 0x9C],
		[PlayerScreen.FOOTER_GLYPH2, 0x2B, 0x0C, 0x78], [0, 0x37, 0x30, 0xC0]]
## The sprites on SBOY, palette row 503 (GetClut(0x70, 0x1F7)).
const SBOY_ROW := 503
## The model (ETCNA/MEDAL.TMD) and its turn per drawn frame (MEDAL_ROTATION.vy += 0x64).
const MODEL := "tmd_files/ETCNA/MEDAL.gltf"
const TURN := 0x64
## activateMedalTexture (map_object.c:1193): MoveImage of the medal's 24 x 32 cell, image
## (24 + (id % 9) * 24, 176 + (id / 9) * 32), to (0, 176), where the model's faces sample.
const CELL := Vector2i(24, 32)
const ACTIVE_CELL := Vector2i(0, 176)

var screen: PlayerScreen
## MEDAL_SELECTOR_INDEX, SELECTED_MEDAL (kept between visits, like the C's globals).
var selector := 0
var selected := 0
## MEDAL_ROTATION.vy, and the medal whose cell is at (0, 176): the page starts with medal 0's.
var rotation := 0
var active_medal := 0
var _page: Image


## drawMedalViewStrings (game_menu.c:4199), one part per frame. True when done.
func draw_strings() -> bool:
	var area := screen.text_area
	var data := screen.data
	var sub := screen.sub_state
	match sub:
		0:
			area.clear(TEXT_AREA)
			MenuDraw.draw_digits(area)
			screen.sub_state = 1
		1:
			area.draw_string(data.text(PlayerScreen.PLAYER_LABELS[1]), 0, 0xC)
			screen.sub_state = 2
		2:
			area.draw_string(data.text(NAMES[selector]), 0, 0x18)
			screen.sub_state = 3
		3, 4, 5:
			var id: String = DESCRIPTIONS[(sub - 3) + selector * 3]
			if id != "":
				area.draw_string(data.text(id), 0, (sub - 3) * 0xC + 0x24)
			screen.sub_state = sub + 1
			if screen.sub_state == 6:
				return true
		6:
			area.clear(DETAIL_AREA)
			screen.sub_state = 2
	return false


## The counting part: the strings (states 0 and 3), the model's turn while it is drawn.
func update() -> void:
	match screen.menu_state:
		0:
			if draw_strings():
				screen.menu_state = 1
		3:
			if draw_strings():
				screen.menu_state = 2
	var view := screen.medal_view
	if view == null:
		return
	if screen.menu_state >= 1 and screen.has_medal(selector):
		if not view.showing:
			view.show_model(MODEL, [0, 0, 0])
			_apply_texture()
		rotation += TURN
		var model := view.model()
		if model != null:
			model.rotation.y = Content.psx_yaw(rotation)
	elif view.showing:
		view.hide_model()


func leave() -> void:
	if screen.medal_view != null:
		screen.medal_view.hide_model()


## tickPlayerMenu, PLAYER_MENU_STATE 2 (US: every MENU_STATE from 2).
func tick() -> void:
	var pad := screen.pad
	if pad.is_changed(Pad.LEFT) and selector % 5 != 0:
		selector -= 1
	if pad.is_changed(Pad.RIGHT) and selector % 5 != 4:
		selector += 1
	if pad.is_changed(Pad.UP) and selector >= 5:
		selector -= 5
	if pad.is_changed(Pad.DOWN) and selector < 10:
		selector += 5
	if selected != selector:
		if screen.has_medal(selector):
			activate(selector)
			screen.menu_state = 3
		screen.play_sound(2)
	selected = selector


## activateMedalTexture: the medal's cell becomes the one the model shows.
func activate(medal: int) -> void:
	active_medal = medal
	_apply_texture()


func _apply_texture() -> void:
	var model := screen.medal_view.model() if screen.medal_view != null else null
	if model == null:
		return
	for node in model.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		for i in mesh.get_surface_override_material_count():
			var source := mesh.get_active_material(i) as ShaderMaterial
			if source == null:
				continue
			if _page == null:
				var tex := source.get_shader_parameter("albedo_texture") as Texture2D
				if tex == null:
					continue
				_page = tex.get_image()
				if _page.is_compressed():
					_page.decompress()
			var image := _page.duplicate() as Image
			var from := Vector2i(24 + (active_medal % 9) * 24, 176 + (active_medal / 9) * 32)
			image.blit_rect(_page, Rect2i(from, CELL), ACTIVE_CELL)
			var copy := source.duplicate(true) as ShaderMaterial
			var pass_material: Material = copy
			var texture := ImageTexture.create_from_image(image)
			while pass_material is ShaderMaterial:
				pass_material.set_shader_parameter("albedo_texture", texture)
				pass_material = pass_material.next_pass
			mesh.set_surface_override_material(i, copy)


## renderMedalView in reverse of its adds; the model under the window's contents, the cursor
## (layer 1) over all.
func draw(canvas: CanvasItem) -> void:
	var state := screen.menu_state
	if state == 0:
		return
	var area := screen.text_area
	if screen.medal_view != null:
		screen.medal_view.draw_on(canvas)
	for k in range(FOOTER.size() - 1, -1, -1):
		var f: Array = FOOTER[k]
		area.render_string(canvas, f[0], f[1], 0x55, f[2], 0xC, f[3], 0xC, true)
	MenuDraw.inset_box(canvas, 0x3E, 0x8D, 0xB0, 0xE)
	for i in range(COUNT - 1, -1, -1):
		var x := (i % 5) * 38
		var y := (i / 5) * 24 - 0x3D
		MenuDraw.sboy_sprite(canvas, x - 0x7A, y, 0xF, 0x18, 0xF0, 0xB0, SBOY_ROW)
		if not screen.has_medal(i):
			MenuDraw.sboy_sprite(canvas, x - 0x7C, y, 0xF, 0x18, 0xF0, 0xC8, SBOY_ROW)
		elif selector == i and state != 3:
			for j in range(2, -1, -1):
				area.render_string(canvas, 0, -0x7E, j * 13 + 0x27, 0xFC, 0xC, 0, j * 12 + 0x24, true)
			area.render_string(canvas, 0, -0x5D, 0x17, 0xAC, 0xC, 0, 0x18, true)
	area.render_string(canvas, 3, -0x36, -0x51, 0x6C, 0xC, 0, 0xC, true)
	var lines := LINES.duplicate()
	lines.reverse()
	MenuDraw.lines(canvas, lines)
	if state >= 2:
		MenuDraw.sboy_sprite(canvas, (selector % 5) * 38 - 0x7E, (selector / 5) * 24 - 0x3D, 0x18, 0x18, 0, 0xD0, SBOY_ROW)
