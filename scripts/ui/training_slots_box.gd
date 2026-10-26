class_name TrainingSlotsBox
extends RefCounted
## Box 3 of the Bonus Try (TRN_createSlotMachineBox, TRN_tickSlotMachine's box part,
## TRN_renderSlotMachine; trn/trn_slots.c; specs/training.md §7.2, §7.5): the slot machine's
## window, grown from the station's spot. Its tick runs the SlotMachine with ✕; at the machine's
## state 6 it shrinks back to the spot and closes the script's help box (text box 0). The
## SlotSession opens it (duck-typed: open, is_free).
##
## The textures are the gym map's VRAM (asset porter maps/<NAME>/training/): the symbols through
## palette 3, opaque (no colour has the STP bit); the reel windows through palette 4, every colour
## with STP, so the whole window subtracts. A map without them draws the box without the reels.

const BOX := 3
## SLOTS_UI_START, SLOTS_UI_END (the start rect without a spot).
const RECT := Rect2i(-82, -87, 164, 90)
const NO_SPOT := Rect2i(-8, -8, 16, 16)
## The spot's screen position minus (0xA8, 0x7E) − DRAWING_OFFSET (160, 120).
const SPOT_OFFSET := Vector2i(8, 6)
const SPOT_SIZE := 16
const TEXTURES := "maps/%s/training/slots_p%d"
const SYMBOL_PALETTE := 3
const WINDOW_PALETTE := 4
## TRN_SLOT_SPRITE1: 32 x 32 centred on the reel (mx 0x10); the strip starts at v 0xD8.
const SYMBOL_SIZE := 32
const SYMBOL_MX := 0x10
## TRN_SLOT_SPRITE2: u 0xE0, 8 x 32, scaled x 4 / x 2 around (mx 4, my 0), colour 0x40.
const WINDOW_UV := Rect2(0xE0, 0, 8, 32)
const WINDOW_SIZE := Vector2(32, 64)
const WINDOW_MX := 16
const WINDOW_TINT := Color(0x40 / 128.0, 0x40 / 128.0, 0x40 / 128.0)

var boxes: UIBoxes
var textboxes: TextBoxes
var pad: Pad
var data: Node
## func() -> int: CURRENT_SCREEN, the map whose spots the box grows from.
var map_id := Callable()
## func() -> FieldMap: the field (its map's textures, its camera for the spot), or null.
var field := Callable()

var machine: SlotMachine
## The multiplier's mode of the station (SlotMachine.stat): its spot.
var mode := 0

## The current map's strips (PsxTexture: base = opaque texels, stp = STP texels), null if missing.
var _symbols: PsxTexture
var _window: PsxTexture
var _textures_of := ""
## UIBoxes children drawn after it: the windows' subtractive layer, the symbols' additive layer.
var _sub: Control
var _add: Control


## TRN_createSlotMachineBox's box: box 3 grows from the spot (the machine was opened by the session).
func open(slot_machine: SlotMachine, stat_mode: int) -> void:
	machine = slot_machine
	mode = stat_mode
	_load_textures()
	_add_layers()
	boxes.create_animated(BOX, 0, UIBoxes.FEATURE_HALF_FILL, RECT, spot_rect(), tick, render)


## Box 3 is free (UI_BOX_DATA[3].state == 0): after its closing animation.
func is_free() -> bool:
	return boxes.boxes[BOX].state == UIBoxes.STATE_CLOSED


## TRN_tickSlotMachine with ✕ newly pressed (POLLED_INPUT & ~POLLED_INPUT_PREVIOUS). In state 6 the
## box shrinks back to the spot and the help box closes, as the machine pays its result.
func tick(_id := 0) -> void:
	var pressed := pad != null and (pad.polled & Pad.CONFIRM) != 0 and (pad.polled_previous & Pad.CONFIRM) == 0
	var closing := machine.closing()
	machine.tick(pressed)
	if closing:
		boxes.remove_animated(BOX, spot_rect())
		if textboxes != null:
			textboxes.close_box(0)


## TRN_getTrainingSpotScreenPos(CURRENT_SCREEN, stat) as the box's rect, recomputed at each call.
func spot_rect() -> Rect2i:
	var f: FieldMap = field.call() if field.is_valid() else null
	if f == null or f.camera == null or not f.camera.is_inside_tree() or data == null or not map_id.is_valid():
		return NO_SPOT
	var project := func(p: Vector3) -> Vector2:
		return FieldMap.unproject(f.camera, Content.psx_to_godot([p.x, p.y, p.z]))
	return spot_rect_for(data.training_spots(int(map_id.call())), mode, project)


## The rect of a map's spot for `stat_mode` (training_spots record), `project` taking a PSX world
## position to PSX screen pixels (0-320, 0-240); NO_SPOT without one.
static func spot_rect_for(spots: Dictionary, stat_mode: int, project: Callable) -> Rect2i:
	var stat_name: String = Training.MODE_NAMES[stat_mode]
	for s in spots.get("spots", []):
		if str(s["stat"]) != stat_name:
			continue
		var p: Array = s["position"]
		var screen: Vector2 = project.call(Vector3(p[0], p[1], p[2]))
		return Rect2i(roundi(screen.x) - 160 - SPOT_OFFSET.x, roundi(screen.y) - 120 - SPOT_OFFSET.y,
				SPOT_SIZE, SPOT_SIZE)
	return NO_SPOT


# --- TRN_renderSlotMachine ------------------------------------------------------------------------

## The opaque texels (symbols, then windows), on the boxes' canvas after the frame. The C sorts per reel the window, then
## the four rows, all on layer 6 − 3 and before the frame: the ordering table draws them in
## reverse after the frame, so the symbols come first and the window (on its subtractive layer,
## drawn after the boxes) darkens them.
func render(canvas: CanvasItem, _id: int) -> void:
	_draw_reels(canvas, false)
	_draw_windows(canvas, false)


func _draw_reels(canvas: CanvasItem, stp: bool) -> void:
	if machine == null:
		return
	for i in range(SlotMachine.REELS - 1, -1, -1):
		var x := SlotMachine.reel_x(i)
		var rows := machine.rows(i)
		if _symbols != null:
			var tex := _symbols.stp if stp else _symbols.base
			for k in range(rows.size() - 1, -1, -1):
				var row: Dictionary = rows[k]
				if not row["visible"] or int(row["h"]) <= 0:
					continue
				var h := int(row["h"])
				canvas.draw_texture_rect_region(tex,
						Rect2(PsxDraw.CENTRE + Vector2(x - SYMBOL_MX, int(row["y"])), Vector2(SYMBOL_SIZE, h)),
						Rect2(int(row["u"]), int(row["v"]) - SlotMachine.SYMBOL_V, SYMBOL_SIZE, h))


## The windows: their STP texels subtract (mode 2), their others are opaque.
func _draw_windows(canvas: CanvasItem, stp: bool) -> void:
	if machine == null or _window == null:
		return
	for i in range(SlotMachine.REELS - 1, -1, -1):
		var at := PsxDraw.CENTRE + Vector2(SlotMachine.reel_x(i) - WINDOW_MX, SlotMachine.WINDOW_TOP)
		canvas.draw_texture_rect_region(_window.stp if stp else _window.base, Rect2(at, WINDOW_SIZE), WINDOW_UV, WINDOW_TINT)


func _shown() -> bool:
	return boxes != null and boxes.boxes[BOX].drawn == UIBoxes.DRAWN_STATIC and boxes.boxes[BOX].render == render


func _draw_sub() -> void:
	if _shown():
		_draw_windows(_sub, true)


## The symbols' STP texels add (mode 1; none in the original's palette).
func _draw_add() -> void:
	if _shown():
		_draw_reels(_add, true)


func _add_layers() -> void:
	if is_instance_valid(_sub):
		return
	_add = _layer("add", _draw_add)
	_sub = _layer("sub", _draw_sub)


func _layer(blend: String, draw: Callable) -> Control:
	var layer := Control.new()
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.material = PsxUiFilter.material(blend)
	layer.draw.connect(draw)
	boxes.add_child(layer)
	return layer


# --- textures ------------------------------------------------------------------------------------

func _load_textures() -> void:
	var f: FieldMap = field.call() if field.is_valid() else null
	var map_name := f.map_name if f != null else ""
	if map_name == _textures_of:
		return
	_textures_of = map_name
	_symbols = load_strip(map_name, SYMBOL_PALETTE)
	_window = load_strip(map_name, WINDOW_PALETTE)


## A map's slot strip through a palette, split by its STP mask; null when the map has none.
static func load_strip(map_name: String, palette: int) -> PsxTexture:
	var rel := TEXTURES % [map_name, palette]
	if map_name == "" or not Content.exists(rel + ".png"):
		return null
	var texture := Content.load_texture(rel + ".png")
	if texture == null:
		return null
	var image := texture.get_image()
	if image.is_compressed():
		image.decompress()
	image.convert(Image.FORMAT_RGBA8)
	var mask: Image = null
	if Content.exists(rel + ".stp.png"):
		var m := Content.load_texture(rel + ".stp.png")
		mask = m.get_image() if m != null else null
		if mask != null and mask.is_compressed():
			mask.decompress()
	var base := image.duplicate()
	var stp := Image.create(image.get_width(), image.get_height(), false, Image.FORMAT_RGBA8)
	if mask != null:
		for y in image.get_height():
			for x in image.get_width():
				if mask.get_pixel(x, y).r > 0.5 and image.get_pixel(x, y).a > 0.0:
					stp.set_pixel(x, y, image.get_pixel(x, y))
					base.set_pixel(x, y, Color(0, 0, 0, 0))
	var result := PsxTexture.new()
	result.base = ImageTexture.create_from_image(base)
	result.stp = ImageTexture.create_from_image(stp)
	return result
