class_name EfeEffect
extends BattleEffect
## The original techniques' effect (specs/battle_effects.md §3.2): one EFEDAT slot, run by EfeVm on
## a private copy of its 0x5000 bytes (asset porter efe/<slot>/effect.bin). This is the C's EfeSlot
## (BTL_setupLoadedEFEFile, BTL_startEFE, BTL_stopEFESubEffect and the slot's part of
## BTL_tickEFEEngine / BTL_renderEFEEngine). Addresses are offsets in `mem`; the data base
## (EFE_SCRIPT_HEAD) is HEADER.

const SLOT_SIZE := 0x5000
const HEADER := 0x34
## EfeFileHeader (13 x int32), offsets relative to the data base.
const H_START_SCRIPT := 0
const H_INIT_SCRIPT := 4
const H_UV_ANIMS := 8
const H_SUB_EFFECTS := 16
const H_TMD_START := 20
const H_TMD_END := 24
const H_TIM_START := 28
const H_TIM_END := 32
const H_NUM_SUB_EFFECTS := 44
const H_EFFECT_ID := 48
## The technique's effect id = technique + 0x100; EFEDAT holds 0x17A - 0x100 slots of ids.
const EFFECT_BASE := 0x100
const EFFECT_END := 0x17A
## Instance fields (EfeInstance): frame, then the transform.
const I_FRAME := 0
const I_POS := 4
const I_ROT := 0x10

## The host (EffectHost): the engine's shared state (globals, texture places, sounds, emitters).
var host: EffectHost
var mem := PackedByteArray()
var effect_id := -1
var num_sub_effects := 0
## TMD objects (one UV animation each).
var num_objects := 0
## EfeSubEffect per sub-effect: {inst, draw, instance, parent, source, target, bone_offset};
## addresses in `mem` (0 = NULL), entities as ids (-1 = NULL).
var contexts: Array[Dictionary] = []
## EfeUvAnim per object: {active, keyframes, table, keyframe, uv_frame, frame, frames, du, dv}
## (du / dv: the primitive UV offset accumulated by BTL_offsetEFEPrimitiveUVs, for the view).
var uv_anims: Array[Dictionary] = []
## The effect texture place the host gave it (UNKNOWN_MODEL_TAKEN index), or -1 without a TIM.
var texture_place := -1
## Draw calls of the last draw() ([builtin name, args...]); filled while `record_draws` is set (the
## tests, the debugger's gallery).
var record_draws := false
var draw_calls: Array = []
## setEFEModelObjectColor's colours by TMD object (Vector3i, 128 = 1.0): they rewrite the slot's
## own model, so they last for the slot's later uses. Objects never coloured keep the porter's.
var object_colors := {}
## The draw sink that draws (EfeView, the scene's `View` child): used while the effect is in the
## tree; headless the draw calls go nowhere.
var view: EfeView
## The folder of the slot in the asset porter output (efe/<slot>_<name>/).
var folder := ""

var _vm: EfeVm
## The use's last start result (EFE_ACTIVE_SECTION), for start().
var _loaded := false


func _init() -> void:
	_vm = EfeVm.new(self)


# --- memory ---------------------------------------------------------------------------------------

func valid(addr: int, size: int) -> bool:
	return addr >= 0 and addr + size <= mem.size()


func read(addr: int, size: int) -> int:
	if not valid(addr, size):
		_vm.fault("read of %d bytes at 0x%X" % [size, addr])
		return 0
	match size:
		4:
			return mem.decode_s32(addr)
		2:
			return mem.decode_s16(addr)
	return mem.decode_s8(addr)


func write(addr: int, size: int, value: int) -> void:
	if not valid(addr, size):
		_vm.fault("write of %d bytes at 0x%X" % [size, addr])
		return
	match size:
		4:
			mem.encode_s32(addr, PsxMath.s32(value))
		2:
			mem.encode_s16(addr, PsxMath.s16(value))
		_:
			mem.encode_s8(addr, PsxMath.s8(value))


func read_vec(addr: int) -> Vector3i:
	return Vector3i(read(addr, 4), read(addr + 4, 4), read(addr + 8, 4))


func write_vec(addr: int, v: Vector3i) -> void:
	write(addr, 4, v.x)
	write(addr + 4, 4, v.y)
	write(addr + 8, 4, v.z)


func header(field: int) -> int:
	return mem.decode_s32(field)


func frame_of(instance: int) -> int:
	return read(instance + I_FRAME, 4) if instance != 0 else 0


# --- the API --------------------------------------------------------------------------------------

## BTL_loadNextEFEFile + BTL_setupLoadedEFEFile (battle_effect.c:1574-1858) for one slot: the
## bytes, the id check, a texture place, the contexts and UV anims, then the init script.
func setup(technique_id: int, caster: int, context: BattleEffectContext) -> int:
	super.setup(technique_id, caster, context)
	var id := technique_id + EFFECT_BASE
	if id < EFFECT_BASE or id >= EFFECT_END:
		return ERR_ID_RANGE
	var bytes := _slot_bytes(technique_id)
	if bytes.size() != SLOT_SIZE:
		return ERR_NO_MODEL
	return load_bytes(bytes, id)


## The load from the slot's bytes (setup's second half; the tests feed hand-made slots).
func load_bytes(bytes: PackedByteArray, id: int) -> int:
	mem = bytes
	effect_id = mem.decode_s32(HEADER - 4)
	if header(H_TIM_END) > header(H_TIM_START) and host != null:
		texture_place = host.take_texture_place()
		if texture_place < 0:
			return ERR_NO_TEXTURE
	if effect_id != id:
		return ERR_WRONG_ID
	num_sub_effects = header(H_NUM_SUB_EFFECTS)
	var tmd := HEADER + header(H_TMD_START)
	num_objects = mem.decode_s32(tmd + 8) if header(H_TMD_END) > header(H_TMD_START) else 0
	contexts.clear()
	for i in num_sub_effects:
		contexts.append({"inst": 0, "draw": 0, "instance": 0, "parent": 0, "source": -1, "target": -1,
				"bone_offset": 0})
	uv_anims.clear()
	for i in num_objects:
		uv_anims.append({"active": 0, "keyframes": 0, "table": 0, "keyframe": 0, "uv_frame": 0, "frame": 0,
				"frames": 0, "du": 0, "dv": 0, "drawn": 0})
	var section := _vm.run_init(HEADER + header(H_INIT_SCRIPT))
	if section < -1:
		return section
	_loaded = true
	return OK_LOADED


## BTL_startEFE: runs the start script, which spawns the use's first instances.
func start(attacker: int, target: int) -> int:
	if not _loaded:
		return -1
	return _vm.run_start(HEADER + header(H_START_SCRIPT), attacker, target)


## BTL_stopEFESubEffect.
func stop(sub_effect: int) -> void:
	if sub_effect < 0 or sub_effect >= contexts.size():
		return
	var c: Dictionary = contexts[sub_effect]
	c["inst"] = 0
	if c["instance"] != 0:
		write(c["instance"] + I_FRAME, 4, -1)


## This slot's part of BTL_tickEFEEngine: each active sub-effect's frame + 1 and its tick script,
## then the UV animations.
func tick() -> void:
	if not _loaded:
		return
	var was_running := is_running()
	var n := num_sub_effects
	for i in n:
		host.sub_effect_index = i
		var c: Dictionary = contexts[i]
		if c["inst"] == 0:
			continue
		write(c["instance"] + I_FRAME, 4, frame_of(c["instance"]) + 1)
		_vm.run(c["inst"], i)
	host.sub_effect_index = n
	for j in num_objects:
		_tick_uv_anim(j)
	if was_running and not is_running():
		finished.emit(-1)


## This slot's part of BTL_renderEFEEngine: each active sub-effect's draw script, its calls drawn
## by the view as one frame.
func draw() -> void:
	draw_calls.clear()
	if not _loaded:
		return
	var drawing := _drawing_view()
	if drawing != null:
		drawing.begin_frame()
	for j in num_objects:
		uv_anims[j]["drawn"] = 0
	for i in num_sub_effects:
		var c: Dictionary = contexts[i]
		if c["inst"] == 0:
			continue
		_vm.run(c["draw"], i)
	if drawing != null:
		drawing.end_frame()


## A drawing built-in of the VM, with the instance it ran for.
func draw_call(name: String, args: Array, instance: int) -> void:
	if record_draws:
		draw_calls.append([name] + args)
	if view != null and view.drawing:
		view.draw_call(name, args, instance)


func set_object_color(object: int, color: Vector3i) -> void:
	if object >= 0 and object < num_objects:
		object_colors[object] = color


func _drawing_view() -> EfeView:
	if view == null:
		view = get_node_or_null("View") as EfeView
	return view if view != null and view.is_inside_tree() else null


func is_running() -> bool:
	for c in contexts:
		if c["inst"] != 0:
			return true
	return false


## BTL_unloadEFESlot.
func unload() -> void:
	for a in uv_anims:
		a["active"] = 0
		a["keyframes"] = 0
	if host != null and texture_place >= 0:
		host.free_texture_place(texture_place)
	texture_place = -1
	_loaded = false


## The slot's VM faults (unreached bytes, bad addresses): empty when the runs were clean.
func faults() -> Array:
	return _vm.faults


func _slot_bytes(technique_id: int) -> PackedByteArray:
	if folder == "":
		folder = EffectHost.efe_folder(technique_id)
	if folder == "":
		return PackedByteArray()
	var path := Content.path("efe/%s/effect.bin" % folder)
	return FileAccess.get_file_as_bytes(path) if FileAccess.file_exists(path) else PackedByteArray()


## BTL_tickEFEUVAnimation (battle_effect.c:1872).
func _tick_uv_anim(j: int) -> void:
	var a: Dictionary = uv_anims[j]
	if a["keyframes"] == 0:
		return
	a["uv_frame"] += 1
	if a["uv_frame"] >= read(a["table"] + a["keyframe"] * 4, 2):
		a["uv_frame"] = 0
		a["keyframe"] += 1
		if a["keyframe"] >= a["keyframes"]:
			a["keyframe"] = 0
		var entry: int = a["table"] + a["keyframe"] * 4
		a["du"] = (a["du"] + read(entry + 2, 1)) & 0xFF
		a["dv"] = (a["dv"] + read(entry + 3, 1)) & 0xFF
	a["frame"] += 1
	if a["frames"] > 0:
		a["frame"] %= a["frames"]
