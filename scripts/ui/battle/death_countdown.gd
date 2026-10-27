extends BattleHudPiece
## The countdown over a fainted partner (command_menu.c:454-580: BTL_initializeDeathCountdown,
## BTL_addDeathCountdown, BTL_tickDeathCountdown, BTL_renderDeathCountdown): a ring (BI_IN,
## palette cycling 13-15) with the digit in it, 4 down to 1, one every 30 frames. Each second the
## digit pops (scale up and back), then both spin and shrink. It stops counting while a thrown item
## is in the air, and goes after 150 frames or when a Restore lands (BTL_removeDeathCountdown).

## The ring: u 0x32, v 0x80, 40 x 40 around its centre; the digit 16 x 16 around (8, 8).
const RING_U := 0x32
const V := 0x80
const CLUT := 0x1ED
const END := 0x96

## BTL_DEATH_COUNTDOWN.data.timer (-1 none) and .step.
var timer := -1
var step := 0
var at := Vector2i.ZERO
## The ring (BTL_DEATH_COUNTDOWN_SPRITE) and the digit (BTL_DEATH_COUNTDOWN.data.sprite).
var ring := {"cy": CLUT, "size": 0x28, "scale": 0x1000, "rotate": 0}
var digit := {"u": 0x58, "v": 0x80, "scale": 0x1000, "rotate": 0}


func on_visual(kind: String, args: Array) -> void:
	if kind != "countdown":
		return
	if bool(args[0]):
		add()
	else:
		timer = -1


## BTL_addDeathCountdown(partner).
func add() -> void:
	if timer != -1:
		return
	timer = 0
	step = 0
	var pos := world.screen_position(battle.fighters[0].entity, 1)
	at = Vector2i(clampi(pos.x, -0x8C, 0x8C), clampi(pos.y, -0x64, 0x64))
	ring["cy"] = CLUT
	ring["rotate"] = 0
	digit["rotate"] = 0


func tick(_pressed: int) -> void:
	# The render removes it after drawing its last frame.
	if timer >= END:
		timer = -1
	if timer != -1 and not session.thrown.active():
		_count()
	queue_redraw()


## BTL_tickDeathCountdown.
func _count() -> void:
	timer += 1
	if timer % 31 == 0:
		step = 0
	step += 1
	var frame := (timer + 0x1D) / 30
	var us := BattleHudDraw.table(data, "BTL_DEATH_COUNTDOWN_DIGIT_U")
	var vs := BattleHudDraw.table(data, "BTL_DEATH_COUNTDOWN_DIGIT_V")
	if frame < 5 and frame >= 1 and us.size() >= 4:
		digit["u"] = int(us[frame - 1])
		digit["v"] = int(vs[frame - 1])
	else:
		digit["u"] = 0x58
		digit["v"] = 0x80
	if step > 0 and step < 0x15:
		if step == 1:
			ring["scale"] = 0x1000
			ring["rotate"] = 0
			digit["rotate"] = 0
		if step >= 2 and step < 5:
			digit["scale"] += 0x199
		elif step >= 5 and step < 8:
			digit["scale"] -= 0x199
		else:
			digit["scale"] = 0x1000
		if step % 3 == 0:
			ring["cy"] += 1
			if ring["cy"] >= 0x1F0:
				ring["cy"] = CLUT
	else:
		var s := ((0x64 - (step - 0x14) * 5) << 0xC) / 100
		digit["scale"] = s
		ring["scale"] = s
		ring["rotate"] += 0x40000
		digit["rotate"] = ring["rotate"]
	ring["size"] = 0x27 if digit["scale"] >= 0x2000 else 0x28


func _draw() -> void:
	if timer == -1:
		return
	# The digit is sorted first: drawn over the ring.
	var size: int = ring["size"]
	BattleHudDraw.sprite(self, BattleHudDraw.page_896(ring["cy"]), RING_U, BattleHudDraw.row(V), size, size,
			at.x, at.y, 0x14, 0x14, ring["scale"], ring["scale"], ring["rotate"])
	BattleHudDraw.sprite(self, BattleHudDraw.page_896(CLUT), digit["u"], BattleHudDraw.row(digit["v"]), 0x10, 0x10,
			at.x, at.y, 8, 8, digit["scale"], digit["scale"], digit["rotate"])
