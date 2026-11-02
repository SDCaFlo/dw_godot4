class_name BattleWorld
extends BattleEffectContext
## What the battle logic (Battle) reads and changes in the world (specs/battle.md §5.1): the effect
## context's view of the entities plus their animations, turning, collision with the combat area,
## the screen, their stats and the sounds and music. The field implements it on its entities
## (FieldBattleWorld, 5d-3b); the tests on stub entities.
##
## Entities are ENTITY_TABLE indices (0 the tamer, 1 the partner, 2-9 the map Digimon).
## Stats are the GameState partner schema for every Digimon (the NPCs get the same layout from their
## map record): {"base": {max_hp, max_mp, offense, defense, speed, brains, moves[4] (animation ids
## or null), moves_prio[4]}, "current": {hp, mp, charge_mode, is_hit, efe_sub_effect, unk1,
## vab_id}}. The battle reads and writes them in place.

## entityCheckCollision's results (map.c:3400): -1 free, 0-9 the entity, 10 the map, 11 the edge
## of the combat area.
const FREE := -1
const HIT_MAP := 10
const HIT_AREA := 11


# --- stats ----------------------------------------------------------------------------------------

func stats(_id: int) -> Dictionary:
	return {}


## The map Digimon's battle record extras (NPC_ENTITIES): {bits, targets_partner (unk1 == 1),
## flee (PSX x, y, z)}.
func npc_record(_id: int) -> Dictionary:
	return {}


## PARTNER_PARA.condition (bits: 0x20 injured, 0x40 sick) and discipline.
func partner_condition() -> int:
	return 0


func partner_discipline() -> int:
	return 0


# --- animation ------------------------------------------------------------------------------------

## startAnimation (nothing if the model hasn't it).
func start_animation(_id: int, _anim: int) -> void:
	pass


## entity->anim.animId.
func animation_id(_id: int) -> int:
	return -1


## animFlag & 1: the animation advances (cleared at its end, or to hold the pose).
func animation_playing(_id: int) -> bool:
	return false


func set_animation_playing(_id: int, _playing: bool) -> void:
	pass


## animFrame / frameCount.
func animation_frame(_id: int) -> int:
	return 0


func animation_frame_count(_id: int) -> int:
	return 0


## animFlag & 2: the root motion held this frame.
func set_step_held(_id: int, _held: bool) -> void:
	pass


## animFlag & 4: the animation ticks twice a frame (NPCEntityTickBattle).
func set_double_speed(_id: int, _on: bool) -> void:
	pass


# --- position and movement ------------------------------------------------------------------------

## rotation.vy.
func set_rotation_y(_id: int, _vy: int) -> void:
	pass


## setEntityPosition / posData->location with the animation's root (anim.locX..Z) (the arena places
## its fighters: STD_placePlayer1 / 2, STD_setPostIntroPosition).
func set_location(_id: int, _location: Vector3i) -> void:
	pass


## entityLookAtLocation (map.c:3389): rotation.vy = _atan(dz, dx).
func look_at_location(id: int, target: Vector3i) -> void:
	var here := location(id)
	set_rotation_y(id, PsxMath.atan(target.z - here.z, target.x - here.x))


## entityCheckCollision(source, entity, w, h): FREE, an entity, HIT_MAP or (w, h non-zero) HIT_AREA.
func check_collision(_id: int, _source: int, _w: int, _h: int) -> int:
	return FREE


## collisionGrace(source, entity, w, h).
func collision_grace(_id: int, _source: int, _w: int, _h: int) -> void:
	pass


## entityIsOffScreen(entity, w, h).
func is_off_screen(_id: int, _w: int, _h: int) -> bool:
	return false


## getEntityTile (FieldMap.model_tile of the location).
func tile(id: int) -> Vector2i:
	var here := location(id)
	return FieldMap.model_tile(here.x, here.z)


## entityLookAtTile.
func look_at_tile(id: int, tile_xy: Vector2i) -> void:
	look_at_location(id, Vector3i((tile_xy.x - 50) * 100 + 50, 0, (50 - tile_xy.y) * 100 - 50))


## isLinearPathBlocked between two tiles.
func path_blocked(_a: Vector2i, _b: Vector2i) -> bool:
	return false


## isFiveTileWidePathBlocked.
func wide_path_blocked(_a: Vector2i, _b: Vector2i) -> bool:
	return false


## The screen position of an entity's bone (getEntityScreenPos), centred on the screen.
func screen_position(_id: int, _bone: int) -> Vector2i:
	return Vector2i.ZERO


## posData->scale (4096 = 1.0, the three axes).
func set_scale(_id: int, _scale: Vector3i) -> void:
	pass


## entity->flatSprite (-1 none, 0-3 the flattened sprite's frame).
func set_flat_sprite(_id: int, _frame: int) -> void:
	pass


## isOnMap.
func set_on_map(_id: int, _on: bool) -> void:
	pass


## isInvisible (no entity, or not on the map).
func is_invisible(id: int) -> bool:
	return not entity_present(id) or not is_on_map(id)


# --- the session ----------------------------------------------------------------------------------

## isTriggerSet / readPStat (script values).
func trigger(_id: int) -> bool:
	return false


func script_value(_id: int) -> int:
	return 0


## The inventory's item ids (the enemy repel / bell).
func inventory_items() -> Array:
	return []


## CURRENT_SCREEN's map record (systems/maps).
func map_record() -> Dictionary:
	return {}


## playMusic(font, variant), stopBGM, stopSound.
func play_music(_font: int, _variant: int) -> void:
	pass


func stop_music() -> void:
	pass


func stop_sounds() -> void:
	pass


## loadSB: the battle's sound bank into slot 8.
func load_battle_sounds() -> void:
	pass


## A Digimon's VBALL set into a sound bank (readVBALLSection).
func load_digimon_sounds(_bank: int, _digimon: int) -> void:
	pass


# --- the partner and the tamer --------------------------------------------------------------------

func partner_tiredness() -> int:
	return 0


func set_partner_condition_bit(_bit: int) -> void:
	pass


## hasMove / learnMove (the learned techniques).
func has_move(_technique: int) -> bool:
	return false


func learn_move(_technique: int) -> void:
	pass


## MONEY (the final balance box).
func money_held() -> int:
	return 0


## MONEY += n (capped at 999,999).
func add_money(_n: int) -> void:
	pass


## partnerTickCollision while loading (GAME_STATE 3): the partner runs up to the tamer.
func partner_run_in() -> void:
	pass


## partnerTickCollision during the battle (GAME_STATE 1 / 2): its collisions only.
func partner_collision() -> void:
	pass


## BTL_tickPartnerWaypointTrail: the partner's waypoint ring follows its moves.
func partner_waypoint_trail() -> void:
	pass


## The tamer's waypoints (GameState tamer.waypoints: x[30], y[30], start_tile, current, count, active).
func tamer_waypoints() -> Dictionary:
	return {"x": [], "y": [], "start_tile": [0, 0], "current": 0, "count": 0, "active": 0}


## handleCommands / handleFleeing: 3000 units out of the map entry's warp (MAP_WARPS[CURRENT_EXIT]).
func exit_flee_point() -> Vector3i:
	return Vector3i.ZERO


## worldPosToScreenPos with GsWSMATRIX (the HUD's points over the fighters): x, y on the screen
## (relative to its centre) and z the view depth.
func project(pos: Vector3i) -> Vector3i:
	var r := world_to_screen(pos)
	return Vector3i(r["screen"].x, r["screen"].y, r["sz"])


## VIEWPORT_DISTANCE as `project` uses it (the field camera's H).
func projection_distance() -> int:
	return viewport_distance()


## An entity's bone position (posData[bone].posMatrix.workm.t), PSX world units.
func bone_location(id: int, _bone: int) -> Vector3i:
	return location(id)


## The thrown item drawn at `pos` (renderThrownItem: renderOverworldItem); `item` null hides it.
## While it shows, the tamer's hands are taken (TAMER_ITEM), so the inventory won't open.
func show_thrown_item(_item: Variant, _pos: Vector3i) -> void:
	pass


## removeItem(item, 1): one leaves the bag (startThrowingItem).
func remove_item(_item: Variant) -> void:
	pass


## ITEM_FUNCTIONS[item](item) with GAME_STATE 1: the item lands on the partner.
func use_item(_item: Variant) -> void:
	pass


## UI box 0 is open (the inventory).
func inventory_open() -> bool:
	return false


## addInventoryUI (△ in battle).
func open_inventory() -> void:
	pass


## closeInventoryBoxes.
func close_inventory() -> void:
	pass


func fade_to_black(_frames: int) -> void:
	pass


## The map's sound set again (loadMapSounds2(getMapSoundId(CURRENT_SCREEN))).
func reload_map_sounds() -> void:
	pass


## spawnDroppedItems(enemy, item).
func spawn_drop(_entity: int, _item: int) -> void:
	pass


## COMBAT_AREA: the screen centre the fighters' combat-area box is measured from.
func set_combat_area() -> void:
	pass

