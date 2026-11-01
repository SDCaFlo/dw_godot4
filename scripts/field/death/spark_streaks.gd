class_name SparkStreaks
extends MeshInstance3D
## The rebirth's spark streaks (DOOA_renderRebirth, dooa.c:1194–1206; DOO2_renderSparkStreak,
## doo2.c:555; specs/death_scene.md §3 I): `fadeLevel` thin additive triangles a frame, shooting out
## from 100 above the partner. roll() is the logic (the C rolls them while drawing); the node draws
## the last roll (scenes/field/death/spark_streaks.tscn).

## DEFEFF palette 1 (CLUT 192, 489) on tpage (768, 256): the UVs less the page's 0x80 rows (I6).
const TEXTURE := "etctim/02_defeff"
const PALETTE := 1
const UVS := [Vector2(0x5F, 0x20), Vector2(0x5F, 0x27), Vector2(0x30, 0x20)]

var _material: ShaderMaterial
var _texture_size := Vector2(256, 48)
var _streaks: Array = []


## `count` streaks from `origin` (PSX): each {"a", "b", "origin": Vector3i, "grey": int} (I3–I5).
## The draws, in the C's order: customRandom(-170, 1024), rand() (rot x), rand() (rot y),
## customRandom(400, 500), customRandom(-50, 50) × 3, rand() (the grey).
static func roll(count: int, origin: Vector3i) -> Array:
	var out := []
	for i in count:
		var span := Rng.custom_random(-170, 1024)
		var r := Rng.rand()
		# I4: rand() % 0 leaves the dividend on the R3000 (port-only reading).
		var rot := Vector3i(r % span if span != 0 else r, Rng.rand(), 0)
		var length := Rng.custom_random(400, 500)
		var m := PsxMath.rot_matrix_zyx(rot)
		var a := PsxMath.apply_matrix_sv(m, Vector3i(0, 0, length)) + origin
		var b := a + Vector3i(Rng.custom_random(-50, 50), Rng.custom_random(-50, 50), Rng.custom_random(-50, 50))
		out.append({"a": a, "b": b, "origin": origin, "grey": Rng.rand() % 128 + 10})
	return out


func _ready() -> void:
	mesh = ImmediateMesh.new()
	var texture := PsxTexture.load_palette(TEXTURE, PALETTE)
	if texture == null:
		return
	_texture_size = texture.base.get_size()
	# Every texel blends, added (SetSemiTrans 1 on an abr 1 page).
	_material = PsxLit.blended(texture.base, PsxLit.ADD)


## Draws `streaks` (roll()'s), this frame.
func draw_streaks(streaks: Array) -> void:
	_streaks = streaks
	var im := mesh as ImmediateMesh
	im.clear_surfaces()
	if streaks.is_empty() or _material == null:
		return
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES, _material)
	for s: Dictionary in streaks:
		var g := float(s["grey"]) / 128.0
		var color := Color(g, g, g)
		# addScreenPolyFT3(prim, &b, &origin, &a).
		var points: Array[Vector3i] = [s["b"], s["origin"], s["a"]]
		for k in 3:
			im.surface_set_color(color)
			im.surface_set_uv(UVS[k] / _texture_size)
			var p: Vector3i = points[k]
			im.surface_add_vertex(Vector3(p.x, -p.y, -p.z))
	im.surface_end()
