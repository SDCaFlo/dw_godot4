extends ArenaHudPiece
## Both fighters' HP and MP bars (STD_addFighterStatusBars(0 / 1), STD_renderFighterStatusBars,
## std_hud.c:1016-1096): no slide as in the field, the partner's at x -0x8C, the opponent's at 0x24;
## HP at y -0x64, MP at -0x58; each bar the number (BTL_renderNumber's 4 places at x0 + 0x49, y0 - 3),
## then the fill (50 px at full), the icon and the frame (STD_STATUS_BAR_SPRITES = the battle's
## BTL_STATUS_BAR_SPRITES, systems/battle_hud). The damage the C's draw applies is
## ArenaBattle.apply_damage_buffers. All on layer 8, the partner's object first.

const X0 := [-0x8C, 0x24]
const Y0 := [-0x64, -0x58]
## BTL_renderNumber: BI_IN palette 12, 7 x 11 digits at u = digit * 7, v 172.
const NUMBER_CLUT := 492
const NUMBER_V := 172


func on_visual(kind: String, args: Array) -> void:
	if kind == "status_bars":
		shown = bool(args[0])


func build() -> void:
	if battle == null or battle.fighters.size() < 2:
		return
	var sprites := BattleHudDraw.table(data, "BTL_STATUS_BAR_SPRITES")
	if sprites.size() < 6:
		return
	var added := []
	for id in 2:
		var f: BattleFighter = battle.fighters[id]
		var values := [[f.hp(), f.max_hp()], [f.mp(), f.max_mp()]]
		for bar in 2:
			var x0: int = X0[id]
			var y0: int = Y0[bar]
			var cur: int = values[bar][0]
			var fill_w: int = cur * 50 / values[bar][1] if values[bar][1] != 0 else 0
			var digits := digit_prims(cur, 4, x0 + 0x49, 7,
					func(d: int, x: int) -> Dictionary: return ft4(BattleHudDraw.BI_IN, NUMBER_CLUT, d * 7, NUMBER_V, 7, 11, x, y0 - 3))
			digits.reverse()
			for p in digits:
				p.merge({"kind": "digit", "fighter": id, "bar": bar})
			added.append_array(digits)
			# p = &STD_STATUS_BAR_SPRITES[bar * 3 + 2], then p-- : the fill, the icon, the frame.
			for k in 3:
				var s: Dictionary = sprites[bar * 3 + 2 - k]
				var w := int(s["w"])
				var p := ft4(BattleHudDraw.BI_IN, int(s["clut"]), int(s["u"]), int(s["v"]), w, int(s["h"]),
						x0 + int(s["x"]), y0 + int(s["y"]), fill_w if k == 0 else w, int(s["h"]))
				p.merge({"kind": ["fill", "icon", "frame"][k], "fighter": id, "bar": bar})
				added.append(p)
	added.reverse()
	prims = added
