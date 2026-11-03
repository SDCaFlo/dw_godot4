class_name EvlParticlesView
extends Node2D
## Draws the evolution's rings (EVL_renderParticle, evl.c:1176-1220; specs/evolution_scene.md H5-H7):
## each edge of a ring's square an opaque LINE_F2 in screen pixels, drawn only when both its ends'
## depth (worldPosToScreenPos >> 4) is in (0x20, 0x1000). The C sorts them at OT 0xFA1, behind every
## model: this node sits on the field's background layer, under the 3D world, over BackgroundDark.
## Scene: scenes/field/evolution/evl_particles.tscn.

## evl.c:1204-1205: the depth window.
const DEPTH_MIN := 0x20
const DEPTH_MAX := 0x1000

## [from, to, colour] per line, in screen pixels.
var _lines: Array = []


## The lines drawn by the last draw().
func shown_lines() -> int:
	return _lines.size()


## `project`: FieldMap.world_to_screen ({"screen" from the projection centre, "sz"}); `offset`: the
## drawing offset (the GPU adds it to the primitive's coordinates).
func draw_particles(particles: EvlParticles, project: Callable, offset: Vector2) -> void:
	_lines.clear()
	if particles != null and project.is_valid():
		for p: Dictionary in particles.drawn():
			var corners: Array = EvlParticles.corners(p)
			var screen := []
			var depth := []
			for c: Vector3i in corners:
				var r: Dictionary = project.call(c)
				screen.append(Vector2(r["screen"]) + offset)
				depth.append(int(r["sz"]) >> 4)
			var c3 := EvlParticles.color(p)
			var color := Color8(c3.x, c3.y, c3.z)
			for i in 4:
				var j := (i + 1) % 4
				if depth[i] > DEPTH_MIN and depth[i] < DEPTH_MAX and depth[j] > DEPTH_MIN and depth[j] < DEPTH_MAX:
					_lines.append([screen[i], screen[j], color])
	queue_redraw()


## [from, to, colour] per line, already culled (EabView.particle_lines: EAB's particles are the same
## LINE_F2 squares, eab.c:613-643).
func set_lines(lines: Array) -> void:
	_lines = lines.duplicate()
	queue_redraw()


func clear() -> void:
	_lines.clear()
	queue_redraw()


func _draw() -> void:
	for l: Array in _lines:
		draw_line(l[0], l[1], l[2], 1.0)
