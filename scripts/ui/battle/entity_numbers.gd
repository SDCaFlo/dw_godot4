extends BattleHudPiece
## The numbers over the fighters (entity_text.c: addEntityText, renderEntityText): damage (colour 0),
## poison (0xC), heals and buffs (0xB) with an icon. Each fighter slot shows up to 8, one after
## another: a number starts once the one before it has risen 11 frames, moves by
## ENTITY_TEXT_Y_OFFSETS for 21 frames and goes after 31. Outside the arena (GAME_STATE 4) a
## number stays where its fighter was when it appeared.

const SLOTS := 4
const ENTRIES := 8
const Y_OFFSETS := [0, -7, -5, -5, -2, -1, 1, 2, 5, 5, 7, -4, -3, -2, 0, -1, 1, 0, 2, 3, 0, 0, 0, 0]
## ENTITY_TEXT_ICON_U: the icon's u, by icon - 1 (1 HP, 2 MP, 3 Off, 4 Def, 5 Speed).
const ICON_U := [0xB0, 0xC8, 0xB8, 0xC0, 0xD0, 0, 0, 0]
const FRAMES := 31
const MOVE_FRAMES := 21
const NEXT_AFTER := 11

## Per slot: {"entries": [{value, x, y, frame (-1 free), color, icon}] x 8, "order": [entry...],
## "count": activeElements}.
var slots: Array = []
## What tick decided to draw this frame: [color, value, x, y, icon].
var _shown: Array = []


func _init() -> void:
	clear()


func clear() -> void:
	slots.clear()
	for s in SLOTS:
		var entries := []
		for i in ENTRIES:
			entries.append({"frame": -1})
		slots.append({"entries": entries, "order": [], "count": 0})
	_shown.clear()


func on_visual(kind: String, args: Array) -> void:
	match kind:
		"number":
			add(int(args[0]), int(args[1]), int(args[2]), int(args[3]), int(args[4]))
		"clear_numbers":
			clear()


## addEntityText(entity, slot, color, value, icon).
func add(entity: int, slot: int, color: int, value: int, icon: int) -> void:
	if slot < 0 or slot >= SLOTS:
		return
	var s: Dictionary = slots[slot]
	if s["count"] == ENTRIES:
		return
	var i := 0
	while i < ENTRIES and s["entries"][i]["frame"] != -1:
		i += 1
	# setCombatTextPosition: the entity's screen position (bone 0), 8 px up.
	var at := world.screen_position(entity, 0) if world != null else Vector2i.ZERO
	s["entries"][i] = {"value": value, "color": color, "icon": icon, "frame": 0,
			"x": at.x + s["count"] * 4, "y": at.y - 8 + s["count"] * 4}
	s["order"].append(i)
	s["count"] += 1


## renderEntityText's motion, per slot.
func tick(_pressed: int) -> void:
	_shown.clear()
	for s in slots:
		if s["count"] == 0:
			continue
		var order: Array = s["order"]
		var k := 0
		while k < order.size():
			var e: Dictionary = s["entries"][order[k]]
			if e["frame"] == -1:
				break
			if k != 0 and s["entries"][order[k - 1]]["frame"] < NEXT_AFTER:
				break
			if e["frame"] < MOVE_FRAMES:
				e["y"] += Y_OFFSETS[e["frame"]]
			_shown.append([e["color"], e["value"], e["x"], e["y"], e["icon"]])
			e["frame"] += 1
			if e["frame"] >= FRAMES:
				e["frame"] = -1
				order[k] = -1
			k += 1
		# Once the first is gone, the others move up (the C shifts only the first gap).
		if not order.is_empty() and order[0] == -1:
			order.remove_at(0)
		while order.has(-1):
			order.erase(-1)
		if order.is_empty():
			# removeEntityText
			s["count"] = 0
			for i in ENTRIES:
				s["entries"][i] = {"frame": -1}
	queue_redraw()


func _draw() -> void:
	for n in _shown:
		var tint := text_area.tint(n[0]) if text_area != null else Color.WHITE
		BattleHudDraw.entity_text(self, tint, n[1], n[2], n[3])
		if n[4] != 0:
			BattleHudDraw.entity_text_icon(self, ICON_U[n[4] - 1], n[2] - 8, n[3])
