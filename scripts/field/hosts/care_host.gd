class_name CareHost
extends Node
## The partner's care while the field is played (specs/care.md §3, specs/scenes.md §4.2): the care
## rules, the fade they use, and the care on screen (the happiness / discipline bars, the condition
## bubbles, the poop piles). Ticked by the field's frame order (Field._frame); the field puts the
## bars, the bubbles and the fade into the HUD.

## A line for the help line (the script sections not ported yet).
signal message(text: String)

## Set by the field before start.
var world: Node
var field_map: FieldMap
var camera: Camera3D
var tamer: Tamer
var partner: Partner
var clock: Clock
var text_area: TextArea
var interpreter: ScriptInterpreter
## Debug: the field's partner override; it gets initializePartner's care values like a new game.
var debug_partner := ""

## The fade covers everything (a render object in the original).
var fade: Fade
## null without a partner, and the visuals with it.
var care: Care
var bars: StatusBars
var bubbles: ConditionBubbles
var poop: PoopPiles


## The care rules and the fade they use (specs/care.md §3). A new game's partner gets
## initializePartner's care values; a loaded game keeps its own.
func start() -> void:
	fade = Fade.new()
	fade.name = "Fade"
	fade.clock = clock
	if partner != null:
		care = Care.new()
		care.name = "Care"
		add_child(care)
		care.game_state = GameState
		care.data = GameData
		care.clock = clock
		care.field = field_map
		care.partner = partner
		care.tamer = tamer
		care.fade = fade
		care.text_area = text_area
		if interpreter != null:
			interpreter.care = care
		care.script_requested.connect(_on_script_requested)
		partner.care = care
		partner.clock = clock
		partner.fade = fade
		if GameState.state["boot_mode"] == GameState.BOOT_NEW_GAME or debug_partner != "":
			care.initialize_partner()
		_start_visuals()
	tamer.fade = fade


## The care on screen (specs/care.md §3.2): happiness / discipline bars next to the clock, the
## condition bubbles over the partner, the poop piles on the map.
func _start_visuals() -> void:
	bars = StatusBars.new()
	bars.name = "StatusBars"
	bars.clock = clock
	bars.care = care
	bars.set_anchors_preset(Control.PRESET_FULL_RECT)
	bubbles = ConditionBubbles.new()
	bubbles.name = "ConditionBubbles"
	bubbles.partner = partner
	bubbles.camera = camera
	bubbles.field = field_map
	bubbles.data = GameData
	bubbles.set_anchors_preset(Control.PRESET_FULL_RECT)
	care.bubble_shown.connect(bubbles.show_bubble)
	care.butterfly_changed.connect(_on_butterfly_changed)
	poop = PoopPiles.new()
	poop.name = "PoopPiles"
	poop.game_state = GameState
	poop.partner = partner
	world.add_child(poop)
	care.poop_changed.connect(poop.refresh)


## The bars' slide, then the bubbles; with the menu open (IS_IN_MENU, bubble.c:482, :619) the
## bubbles are neither ticked nor drawn.
func tick_visuals(in_menu := false) -> void:
	if bars != null:
		bars.tick()
		bubbles.visible = not in_menu
		if not in_menu:
			bubbles.tick()


## The fade, last in the frame.
func tick_fade() -> void:
	if fade != null:
		fade.tick()


## setButterfly removes the bubble first (handleConditionBubble, partner_impl.c:1590). The
## butterfly itself (butterfly.c) isn't drawn yet.
func _on_butterfly_changed(shown: bool) -> void:
	if shown:
		bubbles.remove_current()


## Stand-in for script section 0x4DE (the partner collapses or dies; scripts milestone): the values
## partnerTickDying leaves (partner.c:674-676), then the script is over.
func _on_script_requested(section: int) -> void:
	var values: Dictionary = GameState.state["partner"]["care"]
	values["remaining_lifetime"] = 360
	values["sickness_timer"] = 0
	values["injury_timer"] = 0
	care.script_running = false
	message.emit("script 0x%X (partner collapses): not ported yet" % section)
