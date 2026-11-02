extends ArenaHudPiece
## The 1P / 2P markers (STD_initializePlayerMarker, STD_renderPlayerMarker, std_main.c:5476, 5674),
## shown only when both fighters are the same Digimon (STD_initializeCombat 4140): over each fighter's
## bone 1, offset right by VIEWPORT_DISTANCE * (radius / 2) / (otz * 4), 0x20 up; the large-font page
## (768, 0), CLUT (0, 0x1E1) (palette 1), u = id * 48 + 0xA0, v 0xE0, 48 (47 for 2P) x 31; sorted at
## the fighter's depth (otz): drawn here in the HUD, over the 3D scene.

const PAGE := "stdtim/03_font_large"
const CLUT := 0x1E1


func on_visual(kind: String, args: Array) -> void:
	if kind == "player_marker":
		shown = bool(args[0])


func build() -> void:
	if battle == null or battle.fighters.size() < 2:
		return
	var added := []
	for id in 2:
		var e: int = battle.fighters[id].entity
		var s: Dictionary = world.world_to_screen(world.bone_location(e, 1))
		var otz := maxi(int(s["sz"]) / 4, 1)
		var screen: Vector2i = s["screen"]
		var x := screen.x + world.viewport_distance() * (world.radius(e) / 2) / (otz * 4)
		var w := 0x30 if id == 0 else 0x2F
		var p := ft4(PAGE, CLUT, id * 48 + 0xA0, 0xE0, w, 31, x, screen.y - 0x20)
		p.merge({"kind": "marker", "index": id})
		added.append(p)
	prims = added
