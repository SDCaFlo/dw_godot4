class_name JukeboxRoutines
extends MenuRoutines
## Builtin 0x09, the jukebox (openJukebox, shop/script_menu.c:947; specs/town_services.md §2.2): a
## track picked plays at once (ItemMenu.tick_music_menu); leaving gives the map's music back. A
## child of ScriptRoutines (scenes/script/jukebox_routines.tscn).

const JUKEBOX := 0x09
var routines: Array = [JUKEBOX]

const SECTION := ItemMenu.SERVICE_SECTION


func start(_routine: int) -> bool:
	return true


func tick(_routine: int) -> void:
	match ctx.state_2:
		0:
			menu.left = ItemMenu.allocate(6, 0xD2, 0x18, 6, 0x5A)
			menu.fill_tracks()
			_line(3, _owner(), SECTION)
			_then(3)
		2:
			# playBGM(ACTIVE_BGM_FONT): the map's music again (the C passes the font as the id);
			# readMapTFS reloads what the music's loading overwrote in VRAM: nothing to do here.
			if menu.music != null:
				menu.music.play_bgm(menu.music.active_bgm_font)
			_end()
		3:
			_repeat(true)
			menu.create_music_menu()
			_line(0, _owner(), SECTION)
			_wait_list()
		4:
			_repeat(false)
			_close_list()
			_line(1, _owner(), SECTION)
			_then(2)
