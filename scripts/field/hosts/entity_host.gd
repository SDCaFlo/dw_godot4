class_name EntityHost
extends Node
## The field's entities (specs/scenes.md §4.2): the partner of the game state and the entity table
## with the map's NPCs (specs/npc.md), instanced from the entity scenes (§4.1) into the 3D world.
## Their animation sounds go to Sound. Ticked by the field's frame order (Field._frame).

## NPCEntityTickOverworld's autotalk (overworld.c:1328): an NPC asks for its section; the script
## host decides.
signal npc_autotalk(npc: Npc)

## The entity scenes (specs/scenes.md §4.1).
const PARTNER_SCENE := preload("res://scenes/field/partner.tscn")
const NPC_SCENE := preload("res://scenes/field/npc.tscn")

## Set by the field before start.
var world: Node
var field_map: FieldMap
var tamer: Tamer
## Debug: a Digimon key (e.g. "dw1:greymon") to use as the partner instead of the game state's.
var debug_partner := ""

## null when the game state's partner has no model.
var partner: Partner
## The entity table: the tamer, the partner, the map's NPCs (specs/npc.md).
var entities: FieldEntities


## initializePartner's model part: the partner of the game state follows the tamer
## (specs/partner.md).
func start_partner() -> void:
	partner = PARTNER_SCENE.instantiate()
	partner.name = "Partner"
	world.add_child(partner)
	partner.field = field_map
	partner.tamer = tamer
	partner.game_state = GameState
	if debug_partner != "":
		GameState.state["partner"]["digimon"] = debug_partner
	if not partner.load_digimon(GameData, GameState.state["partner"]["digimon"]):
		partner.queue_free()
		partner = null
		return
	# loadPartnerSounds (partner_impl.c:466): the partner's voice and sound sets.
	Sound.load_partner_sounds(GameData.digimon_sounds(GameState.state["partner"]["digimon"]))
	partner.animation_sound.connect(play_sound)


## The entity table and the map's NPCs (specs/npc.md): created by SET_DIGIMON, ticked after the
## partner in slot order (the NPC objects come after the tamer's and the partner's).
func start_npcs() -> void:
	entities = FieldEntities.new()
	entities.tamer = tamer
	entities.partner = partner
	entities.npc_factory = _create_npc
	if partner != null:
		partner.entities = entities


func _create_npc(slot: int) -> Npc:
	var npc: Npc = NPC_SCENE.instantiate()
	npc.name = "Npc%d" % slot
	npc.slot = slot
	npc.field = field_map
	npc.entities = entities
	npc.tamer = tamer
	npc.talk = func(n: Npc) -> void: npc_autotalk.emit(n)
	world.add_child(npc)
	if not npc.load_digimon(GameData, int(entities.slots[slot]["type"])):
		npc.queue_free()
		return null
	npc.animation_sound.connect(play_sound)
	return npc


## playSound for the entities' animation sounds and the windows' clicks.
func play_sound(slot: int, value: int) -> void:
	Sound.play_sound(slot, value)


## The partner's object (after the tamer's).
func tick_partner() -> void:
	if partner != null:
		partner.tick()


## The NPC objects, in slot order.
func tick_npcs() -> void:
	if entities == null:
		return
	for npc in entities.npcs:
		if npc != null:
			npc.tick()
