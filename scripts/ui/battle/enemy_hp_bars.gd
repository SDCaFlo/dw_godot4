extends BattleHudPiece
## The enemies' HP bars (BTL_renderEnemyHPBars, battle_main.c:2242; BTL_initializeEnemyHPBarSprites):
## a 50-px bar in a green frame beside each enemy's head, with a line down to it and the HP above.
## A bar shows for 21 frames after its last damage, or always with the Select toggle (the dead
## ones excepted): Battle.bars_shown, which the damage step fills. The bar's colour goes from
## green to red as it shortens, recomputed when its width changes. Shown from the set-up to the
## end of the fight (BTL_addEnemyHPBars … BTL_removeEnemyHPBars).

## The frame and line colour (drawLine3P 0xAB40A).
const LINE := 0x0AB40A
## The bar's sprite: page (960, 256), BTLCOMND palette 3 (CLUT row 0x1F3), u 0x58, v 0xEC, 3 high.
const CLUT := 0x1F3
const U := 0x58
const V := 0xEC
const SHOWN_PHASES := [BattleSession.Phase.INTRO, BattleSession.Phase.INTRO_BURST, BattleSession.Phase.FIGHT]

## Per enemy slot: the sprite's {w, r, g, b} (PlayerDataSub as a GsSPRITE).
var sprites: Array = []
## What this frame draws: [x, y, head (Vector2i), w, tint, hp].
var _shown: Array = []


func _init() -> void:
	for i in 4:
		sprites.append({"w": 0x32, "r": 0x80, "g": 0xFF, "b": 0x80})


func tick(_pressed: int) -> void:
	_shown.clear()
	if battle == null or not session.phase in SHOWN_PHASES:
		queue_redraw()
		return
	for i in range(1, battle.enemy_count + 1):
		if not battle.bars_shown[i]:
			continue
		var f := battle.fighters[i]
		var head := world.screen_position(f.entity, 1)
		var y := -0x64 if head.y < -0x4A else head.y - 0x1A
		var x := 0x55 if head.x >= 0x42 else head.x + 0x14
		var w := f.hp() * 50 / f.max_hp() if f.max_hp() != 0 else 0
		var s: Dictionary = sprites[i]
		if w != s["w"]:
			s["w"] = w
			if w >= 0xF:
				s["r"] = (0x32 - w) * 127 / 35 + 0x80
				s["g"] = 0xFF
			elif w >= 5:
				s["r"] = 0xFF
				s["g"] = 0xFF - (0xF - w) * 127 / 10
			else:
				s["r"] = 0xFF
				s["g"] = 0x80
			s["b"] = 0x80
		_shown.append([x, y, head, w, BattleHudDraw.rgb(s["r"], s["g"], s["b"]), f.hp()])
	queue_redraw()


func _draw() -> void:
	var tex := BattleHudDraw.page_960(CLUT, V)
	for b in _shown:
		var x: int = b[0]
		var y: int = b[1]
		var head: Vector2i = b[2]
		# Added lines, sprite, number into one layer: drawn number, sprite, lines.
		BattleHudDraw.entity_text(self, text_area.tint(0) if text_area != null else Color.WHITE, b[5], x + 0x21, y - 9)
		BattleHudDraw.rect(self, tex, U, BattleHudDraw.row(V), b[3], 3, x + 2, y + 2, b[3], 3, b[4])
		PsxDraw.line2(self, LINE, x, y + 6, head.x, head.y)
		PsxDraw.line3(self, LINE, x, y + 1, x, y + 6, x + 0x35, y + 6)
		PsxDraw.line3(self, LINE, x, y, x + 0x36, y, x + 0x36, y + 6)
