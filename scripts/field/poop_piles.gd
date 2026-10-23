class_name PoopPiles
extends Node3D
## The poop piles of the current map (renderPoop, partner_impl.c:529; specs/care.md §2.10): the
## model ETCNA/UNTI.TMD (asset porter tmd_files/ETCNA/UNTI.gltf) at each pile's tile centre, at the
## partner's height, scaled size / 10. Piles live in GameState.state.world.poop.

const MODEL := "tmd_files/ETCNA/UNTI.gltf"

var game_state: Node
var partner: Node3D

var _models: Array[Node3D] = []


## Rebuilds the models (map load, a pile added or eaten).
func refresh() -> void:
	for model in _models:
		model.queue_free()
	_models.clear()
	if game_state == null:
		return
	var world: Dictionary = game_state.state["world"]
	for pile in world["poop"]:
		if pile == null or pile["map"] != world["screen"] or int(pile["size"]) == 0:
			continue
		var model := Content.load_model(MODEL)
		if model == null:
			return
		var centre := FieldMap.tile_centre(Vector2i(int(pile["x"]), int(pile["y"])))
		model.position = Vector3(centre.x, 0, -centre.y)
		model.scale = Vector3.ONE * float(pile["size"]) / 10.0
		add_child(model)
		_models.append(model)
	_follow_partner_height()


func _process(_delta: float) -> void:
	_follow_partner_height()


## renderPoop draws every pile at the partner's current height (location.vy).
func _follow_partner_height() -> void:
	if partner == null:
		return
	for model in _models:
		model.position.y = partner.position.y
