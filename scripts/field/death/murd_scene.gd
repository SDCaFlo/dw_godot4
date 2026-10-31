class_name MurdScene
extends Node
## The MURD overlay (src/murd/murd.c; specs/death_reincarnation.md §3): a life lost. The iris closes
## on the partner, the lives box shows the lost heart, then either (lives left) the screen darkens,
## the map changes to the death map and lightens again, or (no life left) the box closes and DOOA's
## dissolution starts. MURD_tick / MURD_tickScene on the C's frame timeline. Logic only: DeathHost
## draws the iris and the full-screen darkening from `timer` and `darken`; the lives box is a UI box
## (MurdBox). Not ported: the lights it sets for the partner (GsSetFlatLight).

const PHASE_IRIS := 0
const PHASE_BOX := 1
const PHASE_WAIT := 2
const PHASE_DARKEN := 3
const PHASE_BLACK := 4
const PHASE_MAP_CHANGE := 5
const PHASE_HOLD := 6
const PHASE_LIGHTEN := 7
const PHASE_BOX_OUT := 0x64
const PHASE_TO_DOOA := 0x65
## The iris closes over frames 0-0x23 and is drawn while timer < 0x24 (MURD_renderScene).
const IRIS_END := 0x23
const IRIS_DRAWN := 0x24
## The timer once the object is removed (scene->timer = -0xA): MURD_tick(.., 1) < 0.
const OVER := -0xA
## MURD_renderFullscreenFade's levels (MURD_FLASH_*: subtractive, 0xFF = black).
const DARKEN_MAX := 0xA0
const BLACK := 0xFF
## The lives box: its start rect around the partner's screen point (MURD_LIVES_BOX_START_POS,
## MURD_LIVES_BOX_TARGET_POS).
const BOX_AROUND := Rect2i(-8, -6, 16, 12)

var partner: Partner
var tamer: Tamer
var entities: FieldEntities
var game_state: Node
var boxes: UIBoxes
var sound: Node
## The dissolution MURD hands over to with no life left (DOOA_tick(.., 0)).
var dooa: DooaScene
## changeMap(map, exit) and setMapLayerEnabled(enabled), as DooaScene's.
var change_map := Callable()
var map_layer := Callable()
## func(world: Vector3) -> Vector2: worldPosToScreenPos (centred PSX pixels); null: the centre.
var screen_point := Callable()

## MURD_SCENE: timer (OVER once removed; -1 before the first start), phase, the lives.
var timer := -1
var phase := PHASE_IRIS
var lives := 0
var death_map := DooaScene.DEATH_MAP_EARLY
## The full-screen darkening this frame (MURD_renderFullscreenFade's colour), 0 = none.
var darken := 0
## fadeoutCLUT1 on the map's background: 0xFF from the lives box until the map changes.
var darkness := 0
var active := false
var lives_box := MurdBox.new()


## MURD_tick(partner, 0) (murd.c:760): the scene object; with lives left the death map is chosen
## now (setDeathMap), with none DOOA's overlay is loaded.
func start() -> void:
	timer = 0
	phase = PHASE_IRIS
	lives = int(game_state.state["partner"]["lives"])
	darken = 0
	darkness = 0
	active = true
	if lives != 0:
		death_map = DooaScene.choose_death_map(game_state)


## MURD_tickScene (murd.c:189): one game frame of the object.
func tick() -> void:
	if not active:
		return
	timer += 1
	match phase:
		PHASE_IRIS:
			if timer < IRIS_END:
				return
			phase = PHASE_BOX
			darkness = BLACK
			_hide_others()
			_open_box()
			if sound != null:
				sound.music.stop_bgm()
			if map_layer.is_valid():
				map_layer.call(false)
		PHASE_BOX, PHASE_WAIT:
			partner.visible = true
			if timer < 0x5F:
				return
			if lives == 0:
				phase = PHASE_BOX_OUT
				lives_box.close(_around_partner())
				return
			phase = PHASE_DARKEN
		PHASE_DARKEN:
			darken = PsxMath.lerp_int(0, DARKEN_MAX, 0x5F, 0x87, timer)
			if timer < 0x87:
				return
			phase = PHASE_BLACK
			lives_box.remove_static()
		PHASE_BLACK:
			darken = BLACK
			if boxes == null or boxes.boxes[MurdBox.BOX_ID].state == UIBoxes.STATE_CLOSED:
				phase = PHASE_MAP_CHANGE
		PHASE_MAP_CHANGE:
			darken = BLACK
			if change_map.is_valid():
				change_map.call(death_map, DooaScene.DEATH_MAP_EXIT)
			darkness = 0
			# tamerSetFullState(0x13, 1): he keeps waiting for this object; the partner idles.
			tamer.state = Tamer.STATE_BATTLE_LOST_LIFE
			tamer.sub_state = 1
			partner.set_state(Partner.STATE_IDLE)
			tamer.visible = true
			phase = PHASE_HOLD
		PHASE_HOLD:
			darken = BLACK
			if timer < 0x91:
				return
			phase = PHASE_LIGHTEN
			if map_layer.is_valid():
				map_layer.call(true)
		PHASE_LIGHTEN:
			darken = PsxMath.lerp_int(DARKEN_MAX, 0, 0x91, 0xB9, timer)
			if timer < 0xB9:
				return
			_end()
		PHASE_BOX_OUT:
			if boxes == null or boxes.boxes[MurdBox.BOX_ID].state == UIBoxes.STATE_CLOSED:
				phase = PHASE_TO_DOOA
		PHASE_TO_DOOA:
			_end()
			if dooa != null:
				dooa.start_dissolve()
			partner.visible = false


func _end() -> void:
	active = false
	timer = OVER
	darken = 0


## MURD_createLivesBox (murd.c:418): box 3 grows from the partner's screen point.
func _open_box() -> void:
	lives_box.boxes = boxes
	lives_box.open(lives, _around_partner())


func _around_partner() -> Rect2i:
	var p := Vector2.ZERO
	if screen_point.is_valid():
		p = screen_point.call(partner.position)
	return Rect2i(BOX_AROUND.position + Vector2i(p), BOX_AROUND.size)


## MURD_setOtherEntitiesVisible(0) (murd.c:388): every entity but the partner off (the map change
## brings the new map's entities; the C never restores them).
func _hide_others() -> void:
	var table: Array = entities.table() if entities != null else [tamer, partner]
	for e in table:
		if e != null and e != partner:
			e.visible = false
