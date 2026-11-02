class_name MapPropsView
extends Node3D
## The 3D view for field props (specs/map_events.md §4.1.2): cart, pile, boulder, boxes,
## gearbox and pedestal.
## Mirrors map_object.c render* functions (435, 648, 708, 767, 794, 1232).

## MapProps group -> model keys (map_object.c:73, 74, 76, 80, 85, 86, 88, 90)
const GROUPS := {
	&"cart": [&"cart", &"cart_box"],
	&"pile": [&"pile"],
	&"boulder": [&"boulder"],
	&"boxes": [&"big_box", &"small_box"],
	&"gearbox": [&"gearbox"],
	&"pedestal": [&"pedestal"],
}

## The logic state (positions, matrices, timers).
var props: MapProps
## The partner (FieldDigimon: position, direction, radius); the cart is placed in front of it.
var partner: FieldDigimon

var _nodes: Dictionary = {}


## render* (map_object.c:435, 648, 708, 767, 794, 1232): update model loading, visibility and transforms.
func render() -> void:
	if props == null:
		return

	# 1. tick_render (P13, P19): map layer is this node's visible
	props.tick_render(visible)

	# 2. Per group: load model when group is loaded, free when unloaded (P20)
	for group: StringName in GROUPS:
		var is_loaded: bool = props.loaded.get(group, false)
		var model_keys: Array = GROUPS[group]
		if is_loaded:
			for model_key: StringName in model_keys:
				if not _nodes.has(model_key):
					var model_path: String = MapProps.MODELS[model_key]
					var model: Node3D = Content.load_model(model_path) if Content.exists(model_path) else null
					if model == null:
						continue
					model.name = String(model_key)
					add_child(model)
					_nodes[model_key] = model
		else:
			for model_key: StringName in model_keys:
				if _nodes.has(model_key):
					var node_to_free: Node3D = _nodes[model_key]
					if node_to_free != null:
						node_to_free.queue_free()
					_nodes.erase(model_key)

	# 3. Model visibility
	# Cart group: cart at cart_model == 0, cart_box at 1 (P2, P3)
	if _nodes.has(&"cart"):
		_nodes[&"cart"].visible = props.drawn(&"cart") and props.cart_model == 0
	if _nodes.has(&"cart_box"):
		_nodes[&"cart_box"].visible = props.drawn(&"cart") and props.cart_model == 1

	for model_key: StringName in [&"pile", &"boulder", &"big_box", &"small_box", &"gearbox", &"pedestal"]:
		if _nodes.has(model_key):
			_nodes[model_key].visible = props.drawn(model_key)

	# 4. Placement
	# renderDirtCartModel (1232): in front of the partner, turned with it.
	if partner != null and (_nodes.has(&"cart") or _nodes.has(&"cart_box")):
		var p := partner.position
		var loc := Vector3i(roundi(p.x), roundi(-p.y), roundi(-p.z))
		var cart_tf := Content.psx_transform(props.cart_transform(loc, Vector3i(0, partner.direction, 0), partner.radius))
		for model_key: StringName in [&"cart", &"cart_box"]:
			if _nodes.has(model_key):
				_nodes[model_key].transform = cart_tf

	for model_key: StringName in [&"pile", &"boulder", &"big_box", &"small_box", &"gearbox", &"pedestal"]:
		if _nodes.has(model_key):
			_nodes[model_key].transform = Content.psx_transform(props.transform(model_key))

	if _nodes.has(&"big_box"):
		var big_lid := _nodes[&"big_box"].find_child("object_1", true, false) as Node3D
		if big_lid != null:
			big_lid.transform = Content.psx_transform(props.transform(&"big_lid"))

	if _nodes.has(&"small_box"):
		var small_lid := _nodes[&"small_box"].find_child("object_1", true, false) as Node3D
		if small_lid != null:
			small_lid.transform = Content.psx_transform(props.transform(&"small_lid"))


## Model node for a prop (P1-P18), or null when not loaded.
func node(prop: StringName) -> Node3D:
	return _nodes.get(prop, null)
