class_name TournamentHost
extends Node
## Tournament registration host under Systems (specs/tournament_entry.md §4.7, §5.2).
## Manages TournamentRegistration on the field and gates map light updates.

var tamer: Tamer
var partner: Partner
var interpreter: ScriptInterpreter
var boxes: UIBoxes
var map_session: MapSession
var game_state: Node
var data: Node

var registration: TournamentRegistration


func _ready() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")


func start() -> void:
	if game_state == null:
		game_state = get_node_or_null("/root/GameState")
	if data == null:
		data = get_node_or_null("/root/GameData")
	registration = TournamentRegistration.new(game_state)
	registration.script_paused = _is_script_paused
	registration.tamer_state = _tamer_state
	registration.partner_state = _partner_state
	registration.partner_type = _partner_type
	registration.boxes_closed = _boxes_closed
	registration.section_requested.connect(_on_section_requested)


## Ticked by Field._frame where update_map_light_state() used to be called (main.c:3941).
## Calls map_session.update_map_light_state() when registration.tick() returns true.
func tick() -> void:
	if registration == null:
		start()
	if registration != null and registration.tick():
		if map_session != null:
			map_session.update_map_light_state()


func _is_script_paused() -> bool:
	if interpreter == null or interpreter.ctx == null:
		return true
	return interpreter.ctx.is_paused


func _tamer_state() -> int:
	return tamer.state if tamer != null else 0


func _partner_state() -> int:
	return partner.state if partner != null else 1


func _partner_type() -> int:
	if data == null or game_state == null:
		return 0
	var partner_dict: Variant = game_state.state.get("partner")
	if partner_dict is Dictionary:
		var species: Variant = partner_dict.get("digimon")
		if species != null:
			return int(data.id_of("digimon/digimon_data", species))
	return 0


func _boxes_closed() -> bool:
	if boxes == null:
		return true
	for b in boxes.boxes:
		if b.state != 0:
			return false
	return true


func _on_section_requested(section: int) -> void:
	if interpreter != null:
		interpreter.call_section(0, section, 1)
