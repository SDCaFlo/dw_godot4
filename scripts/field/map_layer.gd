class_name MapLayer
## setMapLayerEnabled (utils2.c:487): the map's objects (doors, overlay sprites, dropped items, chests,
## poop) aren't drawn while it is off (readers map_object.c:383, item.c:2429, clock.c:104). Moved
## out of DeathHost; the field's hosts (death, evolution) call it with Field.map_layer_nodes().

## The node's own `visible`, kept while the layer is off (so the layer isn't forgotten by a second off).
const META := "map_layer_was_visible"


## Off: every node hidden, each one's `visible` remembered. On: each back as it was.
static func set_enabled(nodes: Array, enabled: bool) -> void:
	for n in nodes:
		if n == null or not is_instance_valid(n):
			continue
		var node := n as CanvasItem
		var node3d := n as Node3D
		if node == null and node3d == null:
			continue
		if not enabled:
			if not (n as Node).has_meta(META):
				(n as Node).set_meta(META, node.visible if node != null else node3d.visible)
			_show(n, false)
		elif (n as Node).has_meta(META):
			_show(n, bool((n as Node).get_meta(META)))
			(n as Node).remove_meta(META)


static func _show(n: Node, on: bool) -> void:
	if n is CanvasItem:
		(n as CanvasItem).visible = on
	else:
		(n as Node3D).visible = on
