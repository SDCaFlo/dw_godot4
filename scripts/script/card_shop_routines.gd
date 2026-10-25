class_name CardShopRoutines
extends MenuRoutines
## Builtin 0x0E, the card shops (specs/card_shops.md §2.2-2.4): with trigger 3 set, selling cards
## (openSellCardMenu, shop/script_menu.c:753); else with trigger 4 set, one card from the shop's
## slots (openBuyCardMenu, :711); else a pack of 3 random cards (rollCardPack, :679). A child of
## ScriptRoutines (scenes/script/card_shop_routines.tscn).

const CARD_SHOP := 0x0E
var routines: Array = [CARD_SHOP]

const TRIGGER_SELL := 3
const TRIGGER_SINGLE := 4
## rollCard (:1414): r = randomLimit(100) picks the first class whose bound is above it (1 %, 4 %,
## 15 %, 30 %), else the last (50 %).
const RARITY_BOUNDS := [1, 5, 0x14, 0x32]
const LAST_RARITY := 4
## The card, then its Digimon (the lines' {digimon_name 249}).
const PSTAT_CARD := 249


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	if game_state.is_trigger_set(TRIGGER_SELL):
		_sell()
	elif game_state.is_trigger_set(TRIGGER_SINGLE):
		_buy()
	else:
		_pack()


## rollCardPack.
func _pack() -> void:
	match ctx.state_2:
		0:
			_show_card(2)
		2:
			_show_card(3)
		3:
			_show_card(4)
		4:
			ctx.active_instruction = 0


func _show_card(next: int) -> void:
	game_state.set_script_value(PSTAT_CARD, roll_card())
	_card_line()
	_then(next)


## rollCard: a class, then one of its cards (the cards whose rarity is that class, in id order).
func roll_card() -> int:
	var r := Rng.random_limit(100)
	var rarity := LAST_RARITY
	for i in RARITY_BOUNDS.size():
		if r < RARITY_BOUNDS[i]:
			rarity = i
			break
	var cards := []
	for record in data.records("items/card_data"):
		if int(record.get("rarity", -1)) == rarity:
			cards.append(int(record["id"]))
	return cards[Rng.random_limit(cards.size())]


## showCardTextbox (:1327): the line by how many are held (and the rarity of a new one); the count
## + 1 below 9; value 249 = the card's Digimon.
func _card_line() -> void:
	var card := ctx.read_pstat(PSTAT_CARD)
	var held: int = game_state.card_count(card)
	var line := 6
	if held == 0:
		var rarity := menu.card_rarity(card)
		line = 2 if rarity == 0 else (3 if rarity == 1 else 4)
	elif held < 6:
		line = 5
	if held < ItemMenu.CARD_SHOP_LIMIT:
		game_state.set_card_count(card, held + 1)
	game_state.set_script_value(PSTAT_CARD, int(data.card(card).get("digimon", {}).get("id", 0)))
	_line(line, ScriptContext.OWNER_TAMER, ItemMenu.CARD_SECTION)


## openBuyCardMenu.
func _buy() -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xB2, 0x18, 6, 0x5A)
			if menu.fill_card_shop():
				_now(3)
			else:
				_line(1, _owner(), ItemMenu.CARD_SECTION)
				_then(2)
		2:
			_end()
		3:
			_open_list(ItemMenu.TYPE_CARD_BUY, 0)
		4:
			_close_card_list()


## openSellCardMenu.
func _sell() -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xD2, 0x18, 6, 0x5A)
			menu.fill_cards()
			_now(3)
		2:
			_end()
		3:
			_open_list(ItemMenu.TYPE_CARD_SELL, 8)
		4:
			_close_card_list()


func _open_list(type: int, line: int) -> void:
	_repeat(true)
	menu.type = type
	menu.create_card_menu()
	_line(line, _owner(), ItemMenu.CARD_SECTION)
	_wait_list()


func _close_card_list() -> void:
	_repeat(false)
	_close_list()
	ctx.state_2 = 2
