class_name DebugPartnerTools
## The debugger's partner tools, not part of the original (DebugPartnerTab): evolve the partner
## into any Digimon through the evolution rules' own start (Evolution.start: partner state 13, the
## evolution scene, EVL_applyEvolution), and learn techniques (GameState.learn_move), to try any
## Digimon and its techniques in battle. Static, so the tests run them without a window.

## The Digimon a partner can be (digimon_data `partner`, with a level: not the tamer), as
## [id, name, level name], in id order.
static func candidates(data: Node) -> Array:
	var out := []
	for record in data.records("digimon/digimon_data"):
		var level: Dictionary = record.get("level", {})
		if record.get("partner", false) and int(level.get("id", 0)) > 0:
			out.append([int(record["id"]), data.localize(record.get("name")).strip_edges(),
					str(level.get("name", ""))])
	return out


## Why the partner can't evolve now ("" when it can): the evolution starts from the partner's
## normal state with the tamer free, as the C's own starts (specs/evolution.md).
static func evolve_blocker(care: Care) -> String:
	if care == null or care.evolution == null:
		return "no partner"
	if care.evolution_target != -1 or (care.partner != null and care.partner.state == Partner.STATE_EVOLVING):
		return "already evolving"
	if care.partner != null and care.partner.state != Partner.STATE_NORMAL:
		return "the partner is busy (state %d)" % care.partner.state
	if care.tamer != null and care.tamer.state != Tamer.STATE_FREE:
		return "the tamer is busy (state %d)" % care.tamer.state
	return ""


## Starts the evolution into `target` (its scene plays, then EVL_applyEvolution with the usual
## gains). Returns the blocker, "" when it started.
static func evolve(care: Care, target: int) -> String:
	var blocker := evolve_blocker(care)
	if blocker == "":
		care.evolution.start(target)
	return blocker


## The techniques a Digimon can learn (its digimon_data `moves`), finishers left out: they are
## equipped by evolving, never learnt.
static func digimon_moves(data: Node, digimon: Variant) -> Array:
	var out := []
	for entry in data.digimon(digimon).get("moves", []):
		var move = entry.get("move")
		if move != null and data.move(int(move["id"])).get("category") != "finisher":
			out.append(int(move["id"]))
	return out


## Every technique of the Techniques screen (move_data `menu_cell`).
static func every_move(data: Node) -> Array:
	var out := []
	for record in data.records("moves/move_data"):
		if record.get("menu_cell") != null:
			out.append(int(record["id"]))
	return out


## Learns the techniques (learnMove, each with its pair); returns how many were new.
static func learn(game_state: Node, moves: Array) -> int:
	var before: int = game_state.state["partner"]["learned_moves"].size()
	for id in moves:
		game_state.learn_move(id)
	return game_state.state["partner"]["learned_moves"].size() - before
