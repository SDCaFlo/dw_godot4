shader_type spatial;
// The arena's back objects (specs/arena.md 4.7): sorted into sub-OTs drawn behind everything, so
// they write no depth; their render_priority puts them first in the opaque pass.
render_mode unshaded, depth_draw_never;
#include "res://shaders/psx_lit/psx_lit.gdshaderinc"
