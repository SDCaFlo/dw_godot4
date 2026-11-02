class_name ArenaStandIn
extends Node
## stand-in until PLANS 4e-4: keeps tournament start parameters and returns a stand-in result
## (specs/tournament_entry.md §5.2, §5.4).

@export var stand_in_result := 0
var finished := false
var result := 0
var last_cup := -1
var last_opponents: Array = []
var game_data: Node


func _ready() -> void:
	if game_data == null and is_inside_tree():
		game_data = get_node_or_null("/root/GameData")


func start(cup: int, opponents: Array) -> void:
	last_cup = cup
	last_opponents = opponents.duplicate()
	var gd: Node = game_data
	if gd == null and is_inside_tree():
		gd = get_node_or_null("/root/GameData")

	var cup_name := str(cup)
	var opp_names: Array[String] = []
	if gd != null and gd.available():
		var cup_rec: Dictionary = gd.tournament(cup)
		if not cup_rec.is_empty():
			cup_name = gd.localize(cup_rec.get("name"))
			if cup_name.is_empty():
				cup_name = cup_rec.get("key", str(cup))
		for opp in opponents:
			var opp_id := int(opp)
			var opp_rec: Dictionary = gd.digimon(opp_id)
			var opp_name: String = gd.localize(opp_rec.get("name")) if not opp_rec.is_empty() else ""
			if opp_name.is_empty():
				opp_name = opp_rec.get("key", str(opp_id))
			opp_names.append(opp_name)
	else:
		for opp in opponents:
			opp_names.append(str(opp))

	push_warning("arena not ported (4e-4): cup %s, opponents %s" % [cup_name, ", ".join(opp_names)])
	result = stand_in_result
	finished = true
