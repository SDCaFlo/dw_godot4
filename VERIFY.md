# Verifying the Godot game systems (human checks)

The porters have their own checklists (`asset_porter/VERIFY.md`, `data_porter/VERIFY.md`); this file covers the game systems ported to GDScript. Every system has a headless test that must print `OK` (run from `dw_godot/`, Godot 4.7, after both porters):

```
godot --headless --path . -s res://tests/test_script.gd
godot --headless --path . -s res://tests/test_npc.gd
godot --headless --path . -s res://tests/test_game_menu.gd
godot --headless --path . -s res://tests/test_inventory.gd
godot --headless --path . -s res://tests/test_digimon_screen.gd
godot --headless --path . -s res://tests/test_player_screen.gd
godot --headless --path . -s res://tests/test_shops.gd
godot --headless --path . -s res://tests/test_card_shops.gd
godot --headless --path . -s res://tests/test_town_services.gd
godot --headless --path . -s res://tests/test_debug_state.gd
godot --headless --path . -s res://tests/test_training.gd
godot --headless --path . -s res://tests/test_evolution.gd
godot --headless --path . -s res://tests/test_camera.gd
godot --headless --path . -s res://tests/test_map_objects.gd
godot --headless --path . -s res://tests/test_lighting.gd
godot --path . -s res://tests/render_check.gd -- MAYO01 0 260 140   # not headless: renders a frame
godot --headless --path . -s res://tests/test_text.gd
godot --headless --path . -s res://tests/test_care.gd
godot --headless --path . -s res://tests/test_partner.gd
godot --headless --path . -s res://tests/test_clock.gd
godot --headless --path . -s res://tests/test_save_system.gd
godot --headless --path . -s res://tests/test_game_state.gd
godot --headless --path . -s res://tests/test_game_data.gd
godot --headless --path . -s res://tests/test_content.gd
godot --headless --path . -s res://tests/test_data_dock.gd
```

With the Steam build of Godot the executable is `godot.windows.opt.tools.64.exe` in the Steam library folder (`steamapps\common\Godot Engine\`); call it as `& "<path>" --headless --path . -s res://tests/test_game_state.gd` from PowerShell. Godot 4.7 prints a "GDScript backtrace" under each error or warning, including the tests' expected ones.

The tests prove the code does what the spec says. What they can't prove is that the spec matches the game. That is what the checks below are for: compare with what you know of the game.

Sections are added as systems are ported (`PLANS.md`).

## Text and windows (`scripts/ui/`, `specs/text.md`, guide `docs/ui.md`)

`test_text.gd` prints `OK: text checks`. Run the project (F5), open the care panel (`C`) and press **"injured 12h"**: on the next frame Agumon gets sick and the message box opens.

1. **The box:**
   - it grows from the tamer as a grey outline in 5 quick steps, to a strip near the bottom of the screen;
   - the frame is black / light blue / blue lines with small corner pieces, and the inside is half dark (you see the field through it);
   - a small button sprite blinks in the bottom-right corner (3 frames).
   - Compare with any message in the game, e.g. when a partner gets sick: colours, size and place should match.
2. **The text:**
   - the partner's name in orange (colour 10), then "is Sick!" in light grey;
   - the letters are the game's own font: 12 px capitals, narrow lowercase (`i` 4 px), no anti-aliasing.
   - **Gap after the name:** there is a gap between the name and "is Sick!". The C code places the text at 12 px per letter of the name, and the US letters are narrower (`specs/text.md` §2.5). If you remember the game showing "Agumon is sick!" without a gap, say so: that would mean the US build differs from the decomp here.
3. **While it is open:**
   - game time stops (the clock and bars slide away);
   - the tamer can't walk and Agumon stands idle.
   - Press ✕ (Enter / Space): the box shrinks back to the tamer, the clock comes back, you can walk. As in the C, it reacts to ✕ being held, so holding ✕ when the box appears closes it at once.
   - Wrong if: the box never closes, or you stay frozen after it.
4. **Language (`L`):** press `L` before "injured 12h":
   - `ja`: the name in the JP font's full-width Latin letters, then the Japanese text;
   - `en_eu`: the EU font, all letters 8 px apart, so the gap after the name is smaller (8 px per letter).
5. **Dialogue:** see the Scripts section: the dialogue box is checked with the script sections that use it.
6. **Not there yet:** the medal and tamer-level messages, the sounds.

## Controller (`scripts/core/pad.gd`, `tamer.gd`; `specs/text.md` §2.8)

`test_text.gd` checks the pad actions, `test_camera.gd` the direction chain. With a gamepad plugged in:

1. **✕ on text boxes:** talk to an NPC and press the pad's bottom button (✕ / A): the pages turn and the box closes, as with Enter. △ (top button) cancels in choices.
2. **Facing after the stick:** walk with the left stick in each direction and let go: the tamer keeps facing where he walked, never turns down on release. Same with the d-pad.
3. **Running:** hold the right shoulder (R1) or △ while walking: he runs. On the keyboard Shift still runs.
4. **Keyboard:** arrows, Enter / Space and Shift work as before.

## Sound (`scripts/audio/`, `specs/sound.md`; the songs: `asset_porter/specs/sound.md` "Music render")

`test_sound.gd` prints `OK: sound checks`. The songs must be rendered first: in `asset_porter/`, `python -m dwporter convert sound music` (a few minutes; ~0.9 GB in `output/music/`). Then run the project (F5), ideally next to the game in an emulator at the same place and hour.

1. **Map music:** Native Forest (MAYO04A) plays its song at once; walking into another area changes the song (the map's `SET_BGM`). The same song restarts when you change map, as in the game (`playBGM` stops first).
2. **Day / night:** press `T` until 21:00: the song switches to its night version at that hour, back to the day one at 6:00.
3. **The music itself:** tempo, instruments, the envelopes (no notes hanging on, no chirping in battle tracks later), the reverb tail, the loudness against the emulator. The loop: listen through the end of a song; it goes back into its loop without a jump or a click.
4. **Text boxes and windows:** talk to an NPC: the window opening and closing sounds, ✕ on each page, △ / choice moves in choices.
5. **Footsteps:** walk and run: the tamer's and the partner's steps (only when they are on screen).
6. **Script sounds:** scenes with `PLAY_SOUND`, e.g. the Grey Lord's Mansion book scene (YAKA24, VERIFY "Map changes" 5) or Toy Town's doors.
7. **Ambience:** maps whose set loops a sound until the script stops it.
8. **Reverb on effects:** an approximation (Godot's reverb); say if a sound effect sounds too wet or too dry next to the emulator.
9. **NPC sounds (to check in the game):** in the original, does an NPC ever make an odd system sound while it animates (specs/sound.md §6)? The port plays none of their bank-4 sounds.

## Items and chests (`scripts/field/map_items.gd`, `map_chests.gd`, `tamer.gd`; `specs/map_items.md`)

`test_map_items.gd` prints `OK: map item checks`. The maps' setups spawn them: most Native Forest maps have items (some at random), Dragon Eye Lake (MAYO10) a chest near its item boxes. `DW_START_MAP=MAYO10` starts the field on that map (`DW_START_HOUR=22` at that hour).
1. **An item on the ground:** its icon floats at the tile, the size of a small square at its depth, models in front of it hide it; a faint dark ring of its shadow around it.
2. **Picking it up:** walk next to it: the tamer stops (his pick-up animation), the box grows from him: the item's name in yellow, "Woah!" below; ✕ (after a few frames): the click and the "got it" sound, the box shrinks, the item is gone and in the bag.
3. **Bag full** (an item already at 99): "I can't hold anymore."; the item stays. It doesn't start again until you step away and come back.
4. **A chest:** the model (the white box), its cells blocked. Stand in front of it (the side the tray faces) and press ✕: the tamer turns to it, Agumon stops, the tray slides out, the box shows the item; hold ✕: the item goes into the bag as the box closes.
5. **Again:** ✕ at the same chest, now or after leaving the map and coming back: the tray is out and "Hey! It's empty!".
6. **Chest with a full bag:** "I can't hold anymore.", the tray slides back in; the chest can be opened later.
7. **Award box sound:** the "<name> is sick" box (Care) now plays its sound when it opens.

## Scenes (`scenes/field/`, `specs/scenes.md`)

1. **Nothing changed in play:** the tamer, Agumon and the NPCs look, move and sound as before (the refactor steps are behaviour-neutral).
2. **In the editor:** open `scenes/field/partner.tscn` and `npc.tscn`: both are inherited from `digimon.tscn` (Model, AnimationSounds, DropShadow); `tamer.tscn` has the same parts, and `field.tscn` shows the Tamer as an instance of it.
3. **The field's hosts:** `field.tscn` has `Systems` (Entities, MapSession, ScriptHost, CareHost, ClockHost) and `Debug`. The editor preview still shows the start map, the tamer and the help line's map name; changing `start_map` or `time_of_day` in the Inspector updates it, and saving writes no map content into `field.tscn`.
4. **In the game, nothing changed:** the clock slides in and runs, the bars, bubbles and fade work, map changes (walking and `[` `]`), NPC talks, the debug keys (T, Z, C, D, L, H, F1) and the debugger's map list and render scale behave as before.

## The △ menu (`scripts/ui/game_menu.gd`, `scenes/ui/game_menu.tscn`, `scripts/field/hosts/menu_host.gd`; `specs/game_menu.md`)

`test_game_menu.gd` prints `OK: game menu checks`. In the game (F5), on the start map:
1. **Opening:** △ (Esc, or the pad's Y) while walking. The tamer stops, the box grows out of him, the clock and the bars slide away. It shows "Year 1  Day 1" (the date + 1) over a blue line, and two rows of icons: ITEM, DIGIMON, PLAYER / PRAISE, SCOLD, SLEEP. Agumon stands still, NPCs freeze, condition bubbles vanish.
2. **Cursor:** a yellow frame around the selected icon, which blinks. Arrows move it with a click; up / down jump between rows, left / right wrap around the six.
3. **Sleep:** dimmed unless Agumon is sleepy (from 19:00, `T` to get there): ✕ on it gives the refusal sound; when sleepy, ✕ closes the menu and the sleep scene plays (with its sound now).
4. **Praise / Scold:** ✕ closes the menu, Agumon walks up, the tamer pats it (a short pat: Agumon is a Rookie) or scolds it (his own sound), Agumon reacts, then both are free. The care panel (`C`) shows discipline / happiness change: praise -5 / up, scold +2 / -10.
5. **Item / Digimon / Player:** the click, and the help line says the screen isn't ported yet; the menu stays open.
6. **△ again** closes it with the refusal sound; time runs again.
7. **Compare with the game:** the icons and labels (the PRAISE label looked odd in a capture: check it), how dark the disabled Sleep icon is, the blink speed, and the praise / scold sounds. `Z` and the care panel's Sleep still work, through the menu's Sleep.

## The Player screen (`scripts/ui/player_screen.gd` and its tabs, `digivice_view.gd`; `specs/status_screens.md` §4)

`test_player_screen.gd` prints `OK: player screen checks`. In the game (F5), △, then ✕ on PLAYER (a new game has little to show: the debug keys or a save with Digimon raised, medals and cards help):
1. **Opening:** the △ menu shrinks away, the window grows out of the tamer with four tabs: Player, Chart, Med., Card. The tamer and Agumon leave the field.
2. **Info:** Name, Level and its title (Amateur at 0), Raised, Bits (50000 at the start), Time ("0 : 0" style, hours : minutes), Items (icons of the key items you have), Medals (count), and the tamer's model on the left.
3. **Tabs:** → / ← switch (a click); △ on any tab goes back to the △ menu.
4. **Chart:** five coloured level columns of grey cells, the icons of the Digimon raised. ✕: a yellow cursor; the icon under it blinks; ✕ on a raised one opens the detail (where it comes from on the left, what it becomes on the right, coloured lines, its level and name; icons only for the ones raised); △ closes it; ✕ on an empty or unraised cell: the refusal sound.
5. **Medals:** 15 slots, the won ones as small gold medals. The selected won medal turns as a 3D medal on the right with its name and description below. ✕: a cursor; moving onto another won medal changes the 3D medal's face. Known original quirk: right after ✕ the cursor is on the first medal but the 3D medal keeps the last face shown until you move.
6. **Cards:** 11 × 6 cells, the icons of the cards owned. ✕: a cursor; ✕ on an owned card opens its picture and the count beside it; △ closes them.
7. **Back:** △ on a tab: the window shrinks into the tamer, the tamer and Agumon come back, the △ menu opens again.
8. **Compare with the game:** the layouts, the chart's colours and lines, the medal's size and speed, the card picture's place. Check also the card pictures' text: the porter's `card_all` images show Japanese names (e.g. card 04) — compare with what the US game shows.

## The Digimon screen (`scripts/ui/digimon_screen.gd` and its tabs, `menu_draw.gd`, `digivice_view.gd`; `specs/status_screens.md` §3)

`test_digimon_screen.gd` prints `OK: digimon screen checks`. In the game (F5), △, then ✕ on DIGIMON:
1. **Opening:** the △ menu shrinks away, a big window grows out of the tamer with two tabs, Status and Tech. The tamer and Agumon disappear from the field (Agumon is shown in the window).
2. **Status:** the partner's name and Digimon, age, weight, the specialty icons (fire, battle) and type (vaccine), the active time ("day"), the three lives, condition icons when sick / hungry / ..., the happiness and discipline bars, HP / MP / stats with their bars, and Agumon's model standing behind the condition rows.
3. **Tabs:** → / ← switch (a click); the current tab's label is white.
4. **Tech:** the equipped techniques (Spit Fire: power, MP, range), the finisher (Pepper Breath), the help lines. ✕: the window squeezes and opens the grid: 7 element rows × 8 columns, the learned techniques' icons, the equipped one red, the ones Agumon can't use darker; a data panel on the side away from the cursor shows the technique under the cursor.
5. **Equipping:** ✕ on an equipped technique removes it; ✕ on a learned one Agumon can use equips it (up to 3); others give the refusal sound. △ leaves the grid only with an attack equipped. □ opens the help page; △ closes it.
6. **Back:** △ on a tab: the window shrinks into the tamer, the tamer and Agumon come back, the △ menu opens again.
7. **Compare with the game:** the layout of both tabs, the model's place and size, the darker cells (the port approximates the PSX's subtracted boxes), and the colours.

## Training (`scripts/systems/training.gd`, `scripts/training/`, `scripts/script/training_routines.gd`, `scripts/ui/training_stats_box.gd`, `scripts/ui/training_brains_box.gd`, `scripts/ui/training_slots_box.gd`, `scripts/systems/slot_machine.gd`, `slot_session.gd`, `scripts/field/cloud_fx.gd`, `scripts/field/particle_fx.gd`; `specs/training.md`)

`test_training.gd` prints `OK: training checks`. In the game (F5), at the Green Gym (TRAI00; the debugger's Maps tab):
1. **The HP station** ("Boulder Moving", the boulder by the sign): Begin, then Normal.
   - The tamer cheers and faces the partner. The partner walks to the boulder while the camera pans there.
   - It pushes: the boulder shakes, steps forward every 6 seconds, and dust rises at its feet, with the pushing sounds.
2. **The end:** after a minute, or at once while you hold △. The camera goes back to the tamer.
   - The stats box opens from the partner: HP and Offense have blue bars and "+" gains. After about 5 seconds they count up one point a frame, with a ticking sound.
   - ✕ or △ adds the rest at once.
3. **After the box:** the partner walks back, the boulder is in its place again, and you can move. The partner's HP and Offense went up (a Rookie with training type 0: +80 / +2), the clock moved one hour from when the session started, and the partner is more tired.
4. **Bonus Try** (the HP station: Begin, then Bonus Try; any station has it):
   - The "Slot Game" help text opens, and box 3 grows as an outline from the station's spot (the boulder) to the upper middle of the screen, with the box's opening sound.
   - It shows three reels: icons on light squares (heart, ring, Offense, Defense, arrows, bulb, poop), each reel darker at its top and bottom edges than on the middle line. When the partner reaches the boulder they spin, with the start sound.
   - Each ✕ stops the next reel (a press sound, then a stop sound as it lands; the reels stop on whole symbols). △ does nothing. **Open question:** the help text says "Use △" in the script listing and draws a cross in the port, but the code reads ✕ (`specs/training.md` §7.9).
   - After the third reel, the payout sound plays. About 1.5 seconds later (or on ✕) the box shrinks back to the boulder and the help text closes.
   - The session ends on the payout (not after a minute, and △ does not end it): the partner stops, the camera goes back, and the stats box counts gains of Normal × c / 10. No match: c = 5 (half). Three of another stat's icon: 20 (× 2). Three of the station's own icon: 40 (× 4). Three poops: 100 (× 10). A Rookie at HP gets +40 / +160 / +320 / +800 HP.
   - On GIAS09 and MIST05 the reels look the same (same textures).
5. **The other Green Gym stations** (Begin, Normal; hold △ to end each sooner). The gains are those of a Rookie with training type 0:
   - **Tree Striking** (the tree by the boulder): the partner strikes the tree with one of its technique animations. At each hit, three sparks flash and burst, and the tree shakes. △ only ends the session after a hit. Offense +8, Speed +2.
   - **Running** (by the middle sign): the partner runs off in its direction. Once off screen it comes back from the course's start, every 3 seconds. HP +10, Speed +8. After it walks back, the tamer stays turned to it until the script ends.
   - **Punching Glove:** the glove punches the guarding partner: sparks, a punch sound, and the partner is knocked back with dust. The glove swings back, and the partner walks to its point for the next punch. △ ends the session only once it is back at the point. Defense +8, Brains +2.
   - **Waterfall:** the partner walks under the fall by its approach. The fall pours on it, with the splash at its head and the water's sound. At the end the fall is calm again and the partner stays at the approach, without walking back. MP +80, Defense +2.
   - **Classroom:** the tamer walks to the blackboard, then the partner sits in front of him. He teaches (a sound every 1.5 seconds) and it listens. MP +10, Brains +8; nobody walks back.
6. **Gear Savanna** (GIAS09): Striking Special (the pillar: the flash and sparks at each strike; HP +10, Offense +8, no "revision" bonus) and Savanna Course (the run comes back from the course's far end; HP +10, Speed +8).
7. **Misty Trees** (MIST05): Cherrymon, "Please train". The tamer walks to his place, the partner faces Cherrymon, and Cherrymon teaches in a loop. The gains are the Classroom's (MP +10, Brains +8), as in the original.
8. **Brains boxes:** under the stats box, a second box opens from the tamer.
   - **New orders:** when Brains cross 100, 200, 300, 400 or 500, it shows the order ("Give it all you got!" …) and "New orders!".
   - **A technique:** at 150, 250, 350, 450, 550, 650, 750, 800, 850, 900, 950 or exactly 999, the partner may learn one; the box then shows its name and "was mastered!". Its sizes come from the Japanese text, so the US lines may be cut off: compare with the game. The technique appears in the Digimon screen.
   - The box closes when the station ends.
   - To try it: give the partner 95 Brains (the debugger's State tab, "Partner base stats", Apply stats), then do the Classroom.

## Item keeper, jukebox, Birdramon (`scripts/script/item_keeper_routines.gd`, `jukebox_routines.gd`, `birdramon_routines.gd`, `scripts/ui/keeper_menu.gd`; `specs/town_services.md`)

`test_town_services.gd` prints `OK: town service checks`. In the game (F5), in File City:
1. **Item keeper** (ROOM02):
   - Yes opens two boxes side by side, "Keeping" (left) and "In hand" (right). The active side's title bar is lit blue; ← → switch sides.
   - ✕ moves one item to the other side, ○ ten, □ as many as fit (99 a stack). Holding ✕ keeps moving. Red rows can't move: storage full at 99, or no room in the inventory.
   - Both lists follow the moved item. START shows the item's description. △ ends: "Come to this shop when you need it."
2. **Jukebox** (ROOM05B): the track list opens on the song now playing (its row in the highlight colour).
   - ✕ on a track: "{track}, right?", and it starts playing.
   - △: "Help me on my next request.", then the room's music comes back.
   - The last track appears only once the game has been beaten.
   - **To compare with the game:** the long US names run past the box's right edge here (`specs/town_services.md` §5).
3. **Birdramon** (ROOM12): the bits box, the destinations unlocked so far with their prices (red when too dear).
   - ✕ → "Are you sure? Once you go, I can't take you back." → I know: the bits go down, "Hold on tight!", and you arrive in the area.
   - Cancel or △: "I think that going yourself may be the best way."
4. **Compare with the game:** the boxes' places, the labels' positions, the sounds.

## Card shops, merit shop, Mojyamon (`scripts/script/card_shop_routines.gd`, `merit_shop_routines.gd`, `mojyamon_routines.gd`, `scripts/ui/trade_menu.gd`; `specs/card_shops.md`)

`test_card_shops.gd` prints `OK: card shop checks`. In the game (F5):
1. **Card shop** (Gear Savanna, GIAS06B, the Market Manager):
   - **A pack (500 bits):** three lines as the tamer, one card each: "This is a …card." for a new one, "A …card!" for one held 1–5 times, "Another …card." above that. The Player screen's card list counts them; a card stays at 9.
   - **A single card:** the 6 cards on sale with their icons by rarity and their prices. Yellow = not held yet, red = too dear or held 9 times, blank row = sold today. ✕ → "Is it OK? Yes No"; Yes buys it (the bits box goes down; the slot is empty until the next day).
   - **Selling:** a long list with gaps (cards you don't hold), MENU / PRICE / COUNT; ✕ opens the amount box at half the price, up to the count you hold.
   - On this map, buying and selling play the Savannah's extra sound.
2. **Merit shop** (GKYO02, script 135): the Points box at the top left.
   - **Show a Digimon card:** the cards you hold (MENU / COUNT); ✕ → the rarity's line ("This is very rare! …100points."), Give it → the points go up (at most 9999), one card fewer.
   - **Use Merit points:** the merit items with their prices (MENU / MERIT), red if too dear or no room; ✕ → OK / Cancel; OK gives one.
   - △ in a list comes back to the choice; See ya closes the Points box.
3. **Mojyamon** (Freezeland, FRZL14 / FRZL15): "I'm a collector …", then the trade box: "You have" / "Will trade", three rows, red when you don't hold the item, "－" in front of a trade already made. ✕ → "You'll really give me …?" Yeah → the items swap, "Thanks!"; with a full inventory "Too many Items." and nothing changes. △ or "Well..., no" ends the talk.
4. **Compare with the game:** the boxes' places and sizes, the card icons' colours, the column positions, the sounds.

## Shops (`scripts/script/shop_routines.gd`, `scripts/ui/item_menu.gd`, `script_routines.gd`; `specs/shops.md`)

`test_shops.gd` prints `OK: shop checks`. In the game (F5), at a shop (File City's Item Shop, ROOM06, once it has opened; the recycle shop in Gear Savanna's script 126; or any NPC that sells):
1. **Talking:** the keeper's greeting, then the tamer's "Buy / Sell / See ya" (the recycle shop: "Buy / See ya"). The bits box opens at the top left with your bits.
2. **Buy:** a list with MENU / PRICE headers, the item icons, names and prices, and a scroll bar. Items you can't afford, or hold 99 of, are red (grey-red). ↑ ↓ move with repeat, R1 + ↑ / ↓ jump to the top / bottom, START shows the item's description.
3. **Amount:** ✕ on an item opens the amount box (name, unit price, amount, total). ↑ ↓ change it by 1, holding ○ by 10, □ sets the maximum. The maximum is limited by your bits and by 99 minus what you hold. ✕ buys: the bits go down, the bits box updates, the keeper thanks you, and you're back at the choice.
4. **Baby discount:** with a Fresh or In-Training partner, purchases cost 90%, and the keeper says "I'll discount it …".
5. **Sell:** your inventory, half prices; items that can't be dropped show "－－－－" and can't be sold.
6. **Leaving:** △ in the list: "Have anything else?". △ on the choice is See ya: "Come again." if you bought or sold, "That's too bad." otherwise; then the script goes on.
7. **Item picker** (an NPC asking for an item, e.g. a hungry Digimon): the list of your items, ✕ → "Is it OK? Yes No" (← →). Yes gives the item; △ in the list cancels when the script allows it.
8. **Compare with the game:** the boxes' places and sizes, the headers, the amount box layout, the sounds (cursor, confirm, refusal, cancel).

## Items (`scripts/ui/inventory.gd`, `scripts/systems/item_use.gd`, the feeding scene in `partner.gd`; `specs/inventory.md`)

`test_inventory.gd` prints `OK: inventory checks`. In the game (F5), △, then ✕ on ITEM:
1. **The list:** the △ menu shrinks away and the bag opens: two columns of items with their icon, name and amount, the description of the selected one below, a scroll bar on the right. The tamer looks into his bag. Names are coloured by where the item works (field, battle, both, nowhere).
2. **Cursor:** arrows move (held up / down repeats after a moment), with a click; the list scrolls past the 9th row.
3. **Options:** ✕ opens Use / Move / Sort / Drop next to the slot. Use is grey for items that don't work in the field (the battle disks), Drop for items you can't throw away. ✕ on a grey option does nothing; △ closes the options.
4. **Move:** Move, then pick another slot and ✕: the two swap (a sound). △ instead cancels it (another sound).
5. **Sort:** Sort, pick Battle / Raise / Basic: the bag reorders by group, empty slots last.
6. **Drop:** "Are you sure?", on No. No keeps it; Yes (left, ✕) throws the whole stack away.
7. **Back:** △ on the list goes back to the △ menu, on ITEM.
8. **Feeding:** Use on a food: everything closes, Agumon walks up (or first a few steps away if he was too close), the tamer holds the item out (a sound) and Agumon eats it, or refuses it (a shake) and the tamer puts it away. Eaten, one leaves the bag; the care panel (`C`) shows the effect (Meat: energy, and +2 happiness since it is Agumon's favourite).
9. **Refusals:** a recovery floppy may be refused when discipline is low; scold right after (△ menu) and the next item is taken. An evolution item at the right level starts the evolution (see "Evolution").
10. **Compare with the game:** the layout, colours and sounds of the boxes, the walk-up, and when the item disappears from his hand.

## Drop shadows (`scripts/field/drop_shadow.gd`, `scenes/field/drop_shadow.tscn`, `specs/drop_shadow.md`)

In the game (F5), on the start map (Native Forest):
1. **Under every entity:** the tamer, Agumon and each NPC have a soft dark spot on the ground under their feet, about as wide as their body (bigger for bigger Digimon). It follows them as they walk and doesn't turn with them.
2. **Behind the models:** the spot never darkens the entity's own body or a model in front of it.
3. **Blocked cells:** where an entity stands on a cell you can't walk on (an NPC placed on a wall cell, the partner pushed into a corner), it has no spot.
4. **At night** (`T` until night, or start with `DW_START_HOUR=22`): the spot is darker and its fading edge narrower than by day (the PSX subtracts from a darker ground), but still soft, not a hard black square or disc.
5. **Compare with the game:** the darkness and size of the spot, against the item shadow (VERIFY "Items and chests" 1: the same texture and colour). Wrong if: a black or coloured square, a spot that lags behind the entity, or a spot left on the map after an NPC leaves.

## Scripts (`scripts/script/`, `specs/script.md`)

`test_script.gd` prints `OK: script checks`. Besides its synthetic checks it runs every section of every script (1269) and every map setup (255) to its end, played like a player (texts confirmed, choices tried in turn), in about 15 s; it prints the unported instructions it met.

In the game (F5), `D` runs the next section of the current map's script (the help line names it: `script 4 section 0x51 (2 / 7)`). Sections are run as they are written. Entering a map and the trigger cells already start them (see Map changes below); talking to NPCs comes with step 3. Check:
1. **On the start map (Native Forest, MAYO04A):** `D` twice. The first section (0xFE, the map entry) only spawns items, which aren't on the map yet: the help line says `script: not ported yet: SPAWN_ITEM`. The second (0x51) is the sign: "There are engraved letters here." from the tamer (his name "Player" in light blue), then "No one's here! Go home!" and "Is someone living here?" without a speaker. ✕ turns them.
2. **While a section runs:** the tamer can't walk, the partner stands, game time stops (the clock and bars slide away). When it ends everything comes back.
3. **Text details:**
   - the speaker's name on the first row, the text on 3 rows; a text without a speaker uses all 4;
   - words in another colour, the blinking "next" sprite, texts going on to a second page;
   - holding ✕ doesn't skip a new box: it waits until ✕ was released once.
4. **Choices:** at Dragon Eye Lake (press `]` until the help line shows `MAYO06`), `D` twice runs section 0x51, the Lake Guardian's flute scene. It first checks the inventory, so what it shows depends on the items you carry. With the flute: "Will you play the Lake Guardian's **Blue Flute**?" and "I'll play / I won't play". A grey cursor bar covers the option; up and down move it and wrap; ✕ picks; △ leaves the choice.
5. **Unported:** each instruction the port can't run yet is named once in the help line (NPCs, movement, animations, sounds, items on the map, battles, shops). The section goes on without it, as in the original with that system missing.
6. **Compare with the game:** the order of the texts in a scene you know, the speaker colours, when the box closes. Wrong if: a section never ends, texts come in the wrong order, or the game stays frozen after a section.

## Map changes (`scripts/field/field.gd`, `tamer.gd`, `scripts/ui/map_name.gd`, `specs/script.md` §2.2, §3)

Every map is entered through its MAPHEAD script, as in the original. Run the project (F5).
1. **Start:** Native Forest (MAYO04A). The help line names what its setup met and couldn't run (`SET_BGM`, `LOAD_DIGIMON`, `SET_DIGIMON`, `SPAWN_ITEM`); the tamer and Agumon stand at the map's exit 0.
2. **Walking through an exit:**
   - the tamer keeps running straight in his direction while the screen fades to black over 1 s, darkest colours first, fully black by the end (no walls stop him, as in the C); the camera stays where it was;
   - at the half the map's area name appears in the centre ("Coela Point" going to MAYO05) in white, in front of the black;
   - at full black the name goes and the screen stays black for 1 s more (the port's stand-in for the CD load, `Fade.LOAD_FRAMES`); then it fades in over 1 s, with the tamer and Agumon standing still at the exit that matches the one you took;
   - the clock and bars stop during the change and come back after it.
   - Wrong if: the name is off-centre, the fade doesn't cover the tamer and Agumon, you warp back at once (a loop), or you can't move after arriving.
3. **Coming back:** go back through the same exit: you arrive at the exit you left from. A few map changes store another map as the previous one (`change_map_previous` in the data): the Birdra Transport room (ROOM12) to its six destinations, Great Canyon (GCAN08_1 → GCAN07), Dragon Eye Lake → BETL01, Secret Beach Cave (OGRE10 → map 0x87), Coela Point → Tropical Jungle (TROP01, previous = map 13). Where the game uses the previous map (e.g. fleeing a battle), the port uses the same one.
4. **Script walk-outs:** many exits are a script instead of a warp cell (121 of them: File City and its houses, the factory, the mountain paths, …). E.g. Green Gym (TRAI00) toward Jijimon's house: stepping on the exit, the tamer runs on toward a point past the edge (the script's `ENTITY_WALK_TO`) while the screen fades, stops there, and the map changes. Wrong if: he stands still at the exit, or keeps running on the new map.
5. **Exits with a short scene** (17 of them; `tests/exit_scan.tscn` plays them all headless: `godot --headless --fixed-fps 60 --path . res://tests/exit_scan.tscn`, every line `ok`). Teleport with the debugger's Maps tab and watch the scene before the warp:
   - Great Canyon Top (GCAN08_1): the first time, "What?", the walk around, "I felt the ground move."; step off the cell and back: "What? No way!", they sink (the ground objects swap) and fall to GCAN07;
   - Grey Lord's Mansion (YAKA24): at the books, the choice; "I'll take it": the walk, "Huh?", they slide away and land wounded on YAKA15 ("I'm wounded!");
   - Secret Beach Cave (OGRE11): Ogremon's gang scene, then FRZL16 (the battle is skipped until battles are ported);
   - Toy Town (OMOC04–07): the locked door ("It won't open." until trigger 349), then the door rooms: the right door (picked at random on entry) opens and you walk through, a wrong one plays its trap;
   - TOPN01, GCAN10, FACT01: a short walk or turn, then the warp.
   - Skipped for now, by design: sounds, chests, battles and a few built-in routines (0x2B, 0x2C, 0x37), which come with steps 5b–5e.
6. **Trigger cells:** on MAYO04A, stand at the sign and press ✕: the sign's text (section 0x51) runs. Cells that start a scene when stepped on (51–79) run it at once, if their map has one.
7. **Toilet:** step on a toilet while Agumon needs to go: its scene plays (see Camera, item 4).
8. **Debug `[` / `]`:** the previous / next map, with the same fade and name, to its exit 0.

## NPCs (`scripts/field/npc.gd`, `field_entities.gd`, `field_digimon.gd`, `specs/npc.md`)

`test_npc.gd` prints `OK: NPC checks`. In the game (F5), the map setups place the map's Digimon; between talks they wander their paths and react to you by their follow mode (`specs/npc.md` §2.10). Check:
1. **Native Forest (MAYO04A), the start:** by day (7:00–19:00) an Aruraumon walks back and forth between two points by the fence, turning in arcs; at night (`T` advances the hour) a Goburimon instead (after re-entering the map). Wrong if: none appear, two of the same, or it walks on the spot / never turns back.
2. **Talking:** walk into the Aruraumon. It talks on contact (autotalk 1): the tamer stops against it, he and the NPC turn to face each other, and the box opens with its name in yellow ("I guess I can play with you."). Its battle is reported as unported, and the section goes on.
3. **✕ talk:** File City (press `]` to the TWNA maps) or Jijimon's house: walk up to an NPC with autotalk 0, face it and press ✕ from a short distance (the reach is 50 units in front). Its section starts; walking into it without ✕ only stops you.
4. **Blocking:** you can't walk through an NPC; Agumon goes around NPCs as it goes around walls.
5. **Scenes:** sections that walk, turn, slide or animate NPCs play those moves, with the camera pans (see Camera). Compare a scene you know: who turns to whom, who walks where.
6. **The original's slot-7 quirk** (`specs/npc.md` §6, `PLANS.md`): after a scene that animates an NPC, on a map whose last NPC has script id 12 (File City's Whamon), check the real game: can you still talk to that NPC?
7. **Wandering (3b):** on maps with several NPCs (File City, the forests), the walkers go from point to point, stop for a moment (½–4 s), and loop. Against a wall or another Digimon they slide along it and turn away instead of walking into it. Wrong if: one stays pressed into a wall walking on the spot, or walks through walls.
8. **Wild enemies (follow mode 12):** walk into an enemy's range (e.g. MAYO04A's walking Aruraumon, by day, or Goburimon, at night: 300 units around the point where it first stands). It walks, then runs, at the place where you were when it noticed you (it doesn't steer after you). It stops there or when it touches you, waits 2 s, then walks back to its place. Touching you starts its section (the battle is reported). Compare with the game: the moment it notices you, the speed of the charge, the wait.
9. **Looking at you (follow mode 2):** near such an NPC it stops and turns to follow you; when you walk away it goes back to its path.
10. **During a talk:** the NPC you talk to stops; the others keep moving. After the talk it restarts its path from the first point.
11. **Agumon and NPCs:** when Agumon bumps into an NPC it no longer overlaps it: it stops moving towards it and turns along it.

## Camera (`scripts/field/field_map.gd`, `tamer.gd`, `specs/camera.md`; the script's moves `specs/script.md` §2.7 "Step 4")

`test_camera.gd` prints `OK: camera checks`. The camera now moves as the original's: while you hold a direction it scrolls by exactly how far the tamer moved on screen; it doesn't re-centre him. In the game (F5), check:
1. **Plain walking:** the tamer stays where he is on screen while you walk; the camera doesn't move while nothing is held. Wrong if: it jitters, or lags behind and catches up.
2. **Map edges:** walk to an edge of a big map (Native Forest's sides): the camera stops and the tamer walks on towards the screen's edge. Walk back: the camera starts again only once he is back where it stopped (about the screen's centre). Compare with the game: where on screen he is when the camera starts again.
3. **Walk-out exits** (Green Gym towards Jijimon's house): the camera stays put while he runs off, during the fade.
4. **The toilet:** when Agumon needs to go (Care, item 4: about every 4 game hours, then 42 game minutes before the accident), walk onto a toilet cell on a map that has one (MAYO01 does). Then:
   - the camera slides to the toilet over 1 s while Agumon runs there (two legs: to a point near it, then onto it), the tamer turning to follow it;
   - Agumon squats (its animation 10); at the end: not poopy any more, happiness and discipline + 2;
   - the camera slides back to the tamer over 1 s while Agumon walks back to the first point; then the field is free again.
   - Compare with the game: the tamer's facing while Agumon walks back (the C turns him to a garbage point there, `specs/care.md` §6), the timing.
5. **Cutscenes with camera moves:** sections that pan the camera (`MOVE_CAMERA_TO`, `MOVE_CAMERA_TO_ENTITY`; e.g. the File City scenes, Jijimon's house) and walk or slide entities with it. After a pan back to the tamer he is centred again; after a pan elsewhere, the follow carries on from there, so he may stay off-centre until you walk. Compare where the tamer is on screen afterwards with the game.
6. **Rising / sinking** (`ENTITY_MOVE_TO_AXIS` on y, 15 uses): entities slide up or down without changing animation.

## Map objects (`scripts/field/map_overlays.gd`, `field_map.gd`, `specs/map_objects.md`)

`test_map_objects.gd` prints `OK: map object checks`. `render_check.gd` prints `background 0 / 76800 pixels differ` and saves the frame in `user://` (it says where): open it, the map's sprites must sit on the background. In the game (F5), check:
1. **Animated details:** Native Forest's flowers (MAYO01, the lower left), water, torches and smoke on other maps. Walk behind MAYO01's bush by the toilet: it covers the tamer (ISSUES.md I-1). Compare their speed with the game, and the tamer walking in front of and behind the parts of the background that are sprites (tree trunks, roofs). Wrong if: a sprite is offset from the background, flickers, or covers the tamer when he is in front of it.
2. **Brightness:** the glowing (additive) sprites, e.g. File City's lights and the Factorial Town effects. Compare with the game: Godot blends in linear colour, so they may look brighter (`specs/map_objects.md` §6).
3. **File City TWNB04's lights** (instances 49–50): off from 7:00 to 18:59, on otherwise.
4. **Doors:** the Great Canyon gates (GCAN02/03/06/10) sliding apart in their scene before the warp; Grey Lord's Mansion doors (YAKA11A / 11B / 13), with both halves of the double doors (model 10). Compare whether those doors snap shut at the end of their swing as in the port (§6).
5. **Scenes that move sprites:** Amida Forest (TROP06), Secret Beach Cave (OGRE10), Factorial Town (FACT08B).
6. **Digimon Bridge (MAYO08A):** when the bridge is broken, its cells are blocked (the tamer stops before them).
7. **Snow** on Freezeland (FRZL01–16): flakes falling over everything, drifting, melting at the bottom. The scenery in front still hides the tamer (ISSUES.md I-8): walk behind the boulder on FRZL13 and the ice crystals on FRZL12; they cover him and Agumon.
8. **Day / evening / night:** the sprites change palette with the background, at the end of its fade.
9. **No grey dots at night:** the background's transparent texels show black (ISSUES.md I-4), e.g. the rocks of Native Forest at night.

## Field lighting (`scripts/content/psx_lit.gd`, `scripts/field/field_lighting.gd`, `specs/lighting.md`)

`test_lighting.gd` prints `OK: lighting checks`. The models are now lit by the map's light and a fixed ambient, as the original. In the game (F5), check against the original:
1. **By day:** the tamer and the Digimon lit from above: heads and shoulders lighter, sides and the parts facing down darker. Wrong if: lit from below (the light's direction, `specs/lighting.md` §5), or much darker / brighter overall than the game.
2. **Evening (16:00, `T` to advance):** warmer, less green and blue.
3. **Night (20:00):** clearly darker (ISSUES.md I-2, `issues/evidence/dw_night_real_game.png`).
4. **The change:** the models change at the end of the hour's 25-frame fade, with the palette sprites, not during it.
5. **Doors and props** (Grey Lord's Mansion doors, the poop) are lit the same way.
6. **The poop** (ISSUES.md I-5): no dark ring around it; a soft shadow darkens the ground under it instead (compare `issues/evidence/dw_real_poop_look.png`).
7. **Other semi-transparent models** (technique effects, shadows): their glowing or darkening parts blend with what is behind them instead of covering it.

## Debugger and render scale (`scripts/debug/debug_window.gd`, `state_tab.gd`, `partner_tab.gd`, `field.gd`; ISSUES.md D-1, I-3)

In the game (F5):
1. **The windows:** the game opens at 1280 × 960 (4:3); a "DW debugger" window opens beside it (F1 hides / shows it, its close button hides it).
2. **Status tab:** the map, the clock and the last message follow the game.
3. **Maps tab:** type part of a name (`MAYO`, `File City`): the list narrows. Double-click a map (or select it and press Go): the tamer warps there with the fade, at the exit chosen (out-of-range exits are clamped).
4. **Render tab:** 1× is the PSX's blocky 3D, 4× smooth; switching is immediate. At every scale the background is unchanged, and the text boxes, the condition bubbles and the map name sit where they did (they use the models' screen positions).
5. **Textures** (ISSUES.md I-6): Palmon (MAYO03) and Aruraumon (MAYO04A) without speckles or a crawling pattern, at 1× and 4×.
6. **Running** (ISSUES.md I-7): at 4× the picture doesn't shake while the tamer runs; at 1× the scroll is in whole pixels as before.
7. **Text and windows filter** (ISSUES.md D-3, Render tab checkbox, on by default): the text boxes' letters, the box borders, the clock and the status bars have rounded edges instead of square steps, in their own colours (no blur); the box backgrounds still blend with the scene. Off: square PSX pixels.
8. **State tab** (`test_debug_state.gd` prints `OK: debug state checks`):
   - **Triggers:** pick a number; the label says "set" / "not set"; Set / Clear change it, and the list of set triggers below follows.
   - **Script values:** pick a value; its current number shows; Write changes it. Bits and merit: Apply (capped at 999 999 / 9999); the bits box of the next shop shows them.
   - **Partner base stats:** the six numbers show the partner's stats; change them and Apply stats (each capped: HP / MP 9999, the others 999); the Digimon screen shows them.
   - **Items:** pick one, Give / Remove the amount; "held" follows. **Cards:** pick one, Set its count; All cards gives one of each (the Player screen's card list fills).
   - **Unlocks:** "Birdramon: every destination" → Set, then talk to Birdramon (ROOM12): all six places are listed. "Jukebox: the locked tracks" → Set: the jukebox lists 63 tracks.
9. **Partner tab** (`test_partner_tools.gd` prints `OK: partner tools checks`):
   - **Digivolve to:** pick a Digimon (64: every partner Digimon with a level), Digivolve. The partner walks to the tamer, the evolution scene plays, and it is the new Digimon with its evolution gains and first technique. The top line names it. While the partner or the tamer is busy (not in its normal / free state, e.g. during feeding or an evolution) the tab says why it can't, and nothing happens.
   - **Learn its techniques:** the count of learnt techniques goes up; the Digimon screen's Techniques page shows the partner's whole list learnt, ready to equip. **Learn every technique:** all 58 cells of the page are learnt (those the partner's Digimon can't use stay unusable, as in the original).
   - **In battle:** equip a newly learnt technique, start a fight: the partner uses it.

## Care (`scripts/systems/care.gd`, `specs/care.md`)

`test_care.gd` prints `OK: Care checks`. Run the project (F5):

1. **Mood and bars:**
   - a new game's Agumon has happiness 50, so when standing still he plays his happy animation now and then;
   - bottom right, next to the help line, two bars: happiness (smiling face) and discipline;
   - at 50 / 50 the happiness bar is half full (12 of 25 dots) and the discipline bar shows only its background row;
   - the bars slide off to the right whenever the clock slides away (the sleep scene) and come back with it.
2. **Bubbles:** a bubble rises over Agumon's head, bobs, and pops after about 2.5 seconds, then shows again every 3 seconds while the condition lasts:
   - hungry: a piece of meat;
   - poopy: a poop;
   - sleepy: 1–3 Z's;
   - tired, sick, injured: their own icons.
   
   With two conditions the two bubbles take turns. A new game starts with "hungry" counted as already shown, so the very first hungry bubble comes about 3 seconds late (a C quirk, `specs/care.md` §6).
   - Wrong if: the bubble sits on the ground, is far too big or small, or never pops.
   - The bubble is translucent: you see the background through it, the icon is solid.
2. **Sleepy and the sleep scene:**
   - Agumon gets sleepy at 19:00 (press `T` until 19:00).
   - Press `Z` (the menu's "Sleep"). Before 19:00 the help line says it only works while he is sleepy.
   - At 19:00 or later:
     - the clock slides away;
     - the tamer and Agumon face each other, and the tamer plays his animation;
     - Agumon lies down, falls asleep, and the screen fades to black;
     - it fades back in at 04:00 of the next day, the clock returns and both walk again.
   - Wrong if: the scene hangs at a step, the time after it isn't 04:00, or you can't walk after it.
3. **A missed night:** stay awake past 19:00 without pressing `Z` and keep `T` going to 04:00. Agumon simply wakes up (a care mistake); his sleepy walk ends.
4. **Pooping in the wild:** Agumon needs the toilet about every 4 game hours (4 real minutes). It then takes 42 game minutes (about 42 seconds at discipline 50) until the accident:
   - he plays his "need to poop" animation now and then;
   - then you stop, he runs to you, squats and stands up;
   - you can walk again.
   - Try it with Agumon far away too: walk off, or put a wall between you, just before the accident. He runs straight to you, through walls (the original has no wall check in this scene).
   - Wrong if: you stay frozen, or he keeps running without squatting.
   
   A poop pile (a brown swirl with a shadow) stays on the ground in front of where he squatted. It is still there after you leave the map and come back, and there are at most 16 per map.
5. **Hunger:** a hungry bubble at Agumon's hunger hours (1, 5, 9, 13, 17, 21 o'clock; the first call is 09:00 on a new game). It lasts 1.5 game hours if you don't feed him (no feeding yet), then the next call is set.
6. **Debug panel (`C`):** the care values on the right; click the buttons (focus stays with the game, so arrows still move).
   - **Speed:** ×60 makes one game hour pass in a real minute. Every value moves as in the game, only sooner: the clock, food, the poop level every 10 minutes, energy every hour.
   - **Hunger:** "hungry now" shows the meat bubble at once, and "starve" counts down. After 1.5 game hours without food the call ends; with energy below 20 it's a care mistake ("mistakes" + 1).
   - **Poop:** "poop now" starts the accident on the next frame. "toilet" while poopy clears it: poop level 48, happiness and discipline + 2.
   - **Sickness:** toggle "sick" to see its bubble. At ×60, happiness and discipline drop every game hour (−10 / −5) and "timer" rises; at 12 a life is lost and the help line names the collapse script. "injured 12h" makes him sick the original way, with the "<name> is sick" message box (Text section above).
   - **Praise / scold:** praise lowers discipline by 5 and raises happiness; scold raises discipline by 2 and lowers happiness by 10. The bars follow.
   - **Sleep:** "stats", then wait for 19:00 (or "+1 hour") and press "sleep". HP / MP rise during the night: about 70–80 % of the maximum for a full night.
   - **Wrong if:** a value jumps somewhere the game couldn't put it, or the bars and bubbles don't follow the values.
7. **What isn't there yet:**
   - the butterfly over an unhappy partner;
   - feeding, praise / scold, toilets (menus);
   - the collapse / death script (the help line names it), evolution, the butterfly.

## Evolution (`scripts/systems/evolution.gd`, `scripts/field/evolution_scene.gd`, partner state 13 in `partner.gd`; `specs/evolution.md`)

`test_evolution.gd` prints `OK: evolution checks`. The scene is a stand-in until 5f-2 (no shards, no camera orbit). In the game (F5), care panel `C`:
1. **Numemon, the quickest:** with the new game's Agumon, press `evo+12` eight times (evo_timer 96; Agumon's stats are too low for any Champion). At once:
   - the clock stops, the tamer turns to Agumon, and Agumon walks up to him;
   - Agumon idles about 3 s, then plays his next animation with a bubble over him for about 3 s;
   - the music stops; Numemon appears where Agumon stood and plays its pose; the music comes back, the clock runs, you can walk.
   - The panel's first line shows `dw1:numemon`, `evo 0`; the Digimon screen shows Numemon's stats (Agumon's × 0.8 here, Numemon's scale), its technique in slot 1 and its finisher.
   - Wrong if: the game freezes in state 13 (the panel's `state 13.x`), the model doesn't change, or the music never comes back.
2. **The virus bar:** `virus+4` four times: the partner turns into Sukamon the same way.
3. **An item:** the debugger's State tab, Items: give Grey Claws; with a Rookie (a new game's Agumon), △ → ITEM → Use: Agumon takes it, then evolves into Greymon. With a Champion the Grey Claws are refused (a shake).
4. **The Factorial Town remodel** (optional, needs a Mamemon): set the field's `debug_partner` to `dw1:mamemon`, warp to FACT10 (Maps tab) and talk to the remodel shop's owner, Do it (2000 bits): about half the time the partner evolves into MetalMamemon (one in ten Giromon), and the shop's line follows.
5. **Compare with the game:** where the tamer and the partner stand and face, how long the build-up lasts before the change.

## Battles (`scripts/systems/battle/`, `scripts/ui/battle/`, `scripts/field/field_battle_world.gd`, `hosts/battle_host.gd`; `specs/battle.md`)

`test_battle.gd` prints `OK: battle checks`, `test_battle_hud.gd` `OK: battle HUD checks`, `test_efe.gd` `OK: 41 effect checks`; `godot --headless --fixed-fps 60 --path . res://tests/battle_scan.tscn` ends with `battle_scan: OK` (three wins in the real field, with the HUD). The techniques' effects and the status / aura / buff / item visuals aren't drawn yet (5d-5). In the game (F5):
0. **Before fighting:** a new game's partner has 0 stats until the intro is ported (ISSUES.md I-23): in the debugger's **State** tab press **Max all stats**. The help line shows each phase a battle enters ("battle: LOADING", "INTRO", "FIGHT"…): if a battle hangs, note the last one.
1. **Starting a battle:** go to a map with wild Digimon near File City (e.g. Tropical Jungle, TROP01) and walk into one, or let it charge you. Its talk section starts the battle:
   - the music changes to the battle theme; the clock and the care bars slide off; the enemy turns to the partner, which runs up to the tamer (about 2 s);
   - a bubble pops up over each Digimon on screen and turns its tail to it, with one mark for those that join and another for those that run off;
   - the tamer backs off towards where he entered the map, and stops before the screen's edge;
   - the start text: small digit pieces fly in from both sides with trails, spell the message, flash, then spin and burst off the screen.
2. **The HUD while fighting:**
   - top left, the command menu unfolds (down, then across): the label strip and the command icons in a staggered row, a technique command with its element's icon. The hovered icon blinks, a frame marks it and its name shows under the menu;
   - top right, the partner's HP and MP bars slide in (HP first) with their numbers; under them the finisher gauge fills in segments, pulses when one is added and, when full, shows the "ready" sign;
   - after a hit, a green bar with the enemy's HP appears beside its head with a line to it, shortening and turning yellow then red; it hides 1 s after the last damage. **Select** keeps the bars shown;
   - damage numbers jump out over the fighters and fall back (several one after another);
   - a hit pushes the fighter back, but never through a fence or out of the walkable map.
3. **Commands:** ← / → move the hovered command (sound), ✕ gives it: the tamer points and shouts the order over his head ("Attack!", "Your Call!", or the technique's name), which pops up, hops and goes after 1 s. □ with a full gauge orders the finisher: a gauge over the partner fills with L1 / R1 presses for 4 s.
4. **Items:** △ opens the inventory (the tamer takes out his bag; the fight goes on). Battle items have a white Use, field-only ones (food) a grey one; Drop is grey. Use: the tamer throws it, it flies over to the partner in an arc and works when it lands:
   - Sm. recovery: green HP number over the partner; MP floppy: MP number;
   - Off. / Def. / Hispeed disk: +20 to that stat with its icon (capped at 1.3 × the stat at the battle's start; the S. disks +50; the Omni Disk +20 to all three, uncapped);
   - Various cures poison / confusion / stun / flattening; Protection protects from them;
   - Restore on a fainted partner: it gets up with half its HP and the countdown goes.
5. **Running away:** choose Run: the tamer runs back the way he came, the partner follows, the screen fades out and you arrive on the previous map.
6. **Winning:** the enemy falls, the tamer cheers, the partner poses. Two windows grow out of the partner and the tamer: the stats with their bars and the gains (+N, counting into the stats after 2 s; ✕ adds them at once), and the bits counting into your money. Then the final balance. If an item dropped, a technique was learned, the partner was injured or the brains reached a new command, the text types under the bits on ✕ presses (US: each ✕ types the next lines). Then the windows close, the enemy gets up and runs off, the menu folds away. 20 minutes have passed on the clock. The defeated enemy is gone from the map: it doesn't walk back while you stay, and its steps stop once it has run off.
7. **Losing:** with a weak partner the partner falls; a ring with the digits 4-3-2-1 spins over it, then the battle ends and the battle-loss script runs (its scenes come with step 6, "death and lives"). Throwing a Restore before the end gets it back up.
8. **Compare with the game:** the HUD's positions and timing (menu slide, bars, numbers, shout), the start text, the throw's arc, the end windows.
9. **A bubble at the battle's start (I-32):** start a fight while the partner shows a condition bubble (sleepy, hungry…): the bubble finishes its rise (about 2.5 seconds) and goes; no new one appears during the fight. In the field the bubble sways once a second as it floats.
10. **Flattening (I-33):** a flattened fighter squashes, then turns into a small blocky picture of itself, standing upright and flickering between two frames; it shoots aura projectiles; when it ends the model comes back. In the gallery: Visual "Flat sprite (flattened)" toggles it on the caster.

## Battle effects (`scripts/systems/battle/efe_view.gd`, `battle_fx_view.gd`, `world_sprites.gd`, `scripts/debug/effect_gallery.gd`; `specs/battle_effects.md` §7)

The technique gallery (steps 5d-5a, 5d-5b): every technique's drawing (models, sprites, particles, flashes, and the rarer kinds: screen sprites and backdrops, lines, wireframes, waves, ribbons, the ring tube, fades, palette animation).

1. **Open the gallery:** on any map (an open one, e.g. TROP01), F1 opens the debugger: tab **Effects**. Pick a technique (the caster switches to a Digimon that has it), a target, then **Place**: the two Digimon stand facing each other where the tamer was (the tamer and the partner hide). **Play** starts the technique (again to replay); the caster plays its technique animation when it has the technique in its list. **Close** brings the tamer back.
2. **What it shows:** the frame, the live sub-effects, the hits (frame and victim), the draw calls of the run, and the kinds not drawn yet (none now). **Distance**: the share of the technique's range the two stand apart (a fighter starts a technique anywhere within its range); some area techniques reach only part of it.
3. **Spit Fire (2)** with Agumon: a stream of fireballs (sprites) flies to the target; the hit makes sparks (a flash, then particles fading out). Its sound now comes from the battle's bank (ISSUES.md I-27): compare it with the original.
4. **Fire Tower (0)** with Agumon: a column of fire (the effect's model) rises on the target, its texture scrolling. At its end: does the original's tower **fade out** or vanish at once? (The port fades it with the script's colour; the PSX's raw-texture bit may ignore that colour, `specs/battle_effects.md` §7.8.)
5. **A few more to compare:** Electric Cloud, Blue Blaster, Poison Ivy, Static Elect (its sparkles run over the caster's bones), a technique with particle streaks (e.g. Sonic Jab, Tremar: the emitters), a flash (Mega Flame).
6. **Things to look at against the original:** the sprites' size and **rotation direction**, what is hidden behind a Digimon, the colours and the additive / subtractive blending, the textures' scrolling.
7. **The rarer kinds (5d-5b), one technique each to compare:**
   - Winter Blast: a snowy backdrop scrolling in front of everything, covering the whole screen on any map (I-31: it used to land off to one side, on TROP01 off the right edge).
   - Thunder Justice, Solar Ray: screen sprites and flashes.
   - DG Dimension: the screen darkens behind the fighters; a green wireframe grid and boxes.
   - Aurora Freeze: a colour-cycling ribbon and a screen tint.
   - Meltdown: a ring tube.
   - Confused Storm: radial waves, a model hanging in front of the camera, cycling colours.
   - Reverse Prog: its colours change as it plays.
   - Spiral Sword: a textured quad.
8. **Aim:** techniques fired from a mouth or a hand (Frozen Fire Shot, Spit Fire, Fireball) leave along that bone towards the target. Deadly Bomb lobs its bomb far beyond the target: does the original's land that far?
9. **In a real battle:** the partner's technique now draws too, and the hits make sparks; the battle's sounds are the battle bank's (I-27).
9b. **Brightness (I-30):** over a bright map (TROP01, MAYO03) the techniques show about as strong as in the original: Spit Fire's flames, Aurora Freeze's ribbon and the sparks are clearly visible, glowing over the background instead of nearly vanishing. Semi-transparent field models (the poop's shadow) look as before or closer to the original.
10. **The battle visuals (5d-5c).** `test_battle_visuals.gd` prints `OK: battle visuals checks`. In the gallery (Place first), the **Visual** row's Show plays each on the caster; compare with the original:
    - **Poison:** bubbles rise and sway from the Digimon's head, one every second or so. Show again removes it; the bubbles already out finish rising.
    - **Confusion:** three small models circle above the head, each spinning.
    - **Stun:** a countdown in a frame over the head, counting down, with stars falling around the Digimon; at 0 the frame flashes, shrinks and goes by itself.
    - **Finisher aura:** a golden aura grows around the Digimon and breathes for 4 seconds, with sparks flying out at its start.
    - **Aura projectile:** a small square flies from the caster at the target; the hit is listed.
    - **Item particles:** sparks burst up from the head and fall, fading.
    - **Buff disk:** a flickering disk turns at the feet, green ribbons rising around it, for about 3 seconds.
    - **Cure rings** (four colours: poison purple, stun blue, confusion pink, flatten white): five rings spin around the body, then sparks fly out.
11. **In a real battle:**
    - **Statuses:** a poisoned, confused or stunned fighter shows its status' visual until it's cured.
    - **Finishers:** a finisher's wind-up shows the aura.
    - **Items:** a thrown item that lands bursts the item particles. A stat item shows the disk. A cure item shows the rings.
    - **Flattened fighters:** a flattened fighter's attacks fly as aura projectiles and hit.
12. **Healing (I-21):** give the partner a recovery item, in the field or in battle: a ring of yellow-green sparks rises around it to above its head. A bigger recovery item (e.g. Lg. recovery) adds sparks spiralling down.

## New game (`scripts/game/game.gd`, `scripts/new_game/new_game_scene.gd`, `scripts/script/naming_routines.gd`, `scripts/ui/naming_box.gd`, `scripts/movie/movie_player.gd`; `specs/new_game.md`)

0. `godot --headless --path . -s res://tests/test_new_game.gd` prints `OK: new game checks`. `godot --headless --fixed-fps 60 --path . res://tests/new_game_scan.tscn` prints `OK: new game scan`, with the partner's stats becoming 80 / 60 / 70 / 70, 800 / 600 on its way. With `NEW_GAME_INTRO=1` it plays the intro too (✕ through the lines, "AAAAAA" for both names) and checks the names reach the field. The data porter's `python -m dwdata convert systems` passes 107/107.
1. **Start:** run the project (F5; the main scene is now `scenes/game.tscn`). The screen fades in on black; Jijimon walks in from the right, turns to the camera, and the dialogue box grows from him.
2. **The questions:** "Do you have a Digivice?", then "day or night?" (Yes) or "Do you have friends?" (No). The choice lines show no speaker name. △ on a choice plays the refused sound and doesn't cancel.
3. **The naming screen:**
   - **Its look:** two boxes grow from Jijimon. "Name" at the top left, Back and OK below it; A–Z on the left, a–z and 0–9 on the right; the name box at the bottom with an underline under the next letter.
   - **Moving:** the frame cursor moves on the letters and wraps up / down within its half; ← from the first column goes to Back, → from the right half's last column too; ○ jumps to Back, Start to OK.
   - **Typing:** ✕ types; □ clears; △ or Back deletes; a 7th letter replaces the 6th; a space can't be the first letter; OK on an empty name is refused.
4. **The confirmation:** "*name*, right?" No goes back to the naming with the name kept. Yes asks the Digimon's name (the naming starts empty); then "Good Name." and "That's all the questions I have."
5. **The end:** the screen fades out, movie 1 plays (Start skips it; without the porter's `.ogv` it is skipped and the console says so), then File City fades in with the tamer and the partner.
6. **The partner:** Agumon for Digivice Yes + Day or Digivice No + friends Yes, else Gabumon. The Player screen's Evolution chart shows it (I-16). After File City's opening its stats aren't 0 (I-23). The names typed show in the dialogue.
7. **Debug:** `DW_SKIP_INTRO=1` starts in File City at once. Running `scenes/field/field.tscn` (F6) keeps the debug start map.

## Partner (`scripts/field/partner.gd`, `psx_animator.gd`, `specs/partner.md`)

`test_partner.gd` prints `OK: Partner checks`. Then run the project (F5):

1. **Start:** Agumon stands next to the tamer and idles.
2. **Walk away slowly:**
   - he follows, walking when the distance is medium (about 2.5–3.5 Agumon widths);
   - he runs when you get further (hold Shift);
   - when you stop, he finishes his step, stops next to you and idles.
3. **Close:** he doesn't walk into the tamer and stops facing him, also at a diagonal. Run, then stop: once he has caught up he stands still (he must not keep turning on the spot).
4. **Standing still:** after a few seconds he plays another standing animation now and then. Hungry, sleepy, happy and other mood animations need the care step.
5. **Walls:** walk around a corner or a tree so that the wall is between you. He takes the way you walked; he never stays pressed into a wall or corner. On a tight corner he may cut a little into the wall: the original doesn't stop him at walls either (`specs/partner.md` §3). Compare with the game: does Agumon cut corners the same way? If you walk far away while he's off screen, he catches up by appearing on your path.
6. **Map changes:** after a warp he appears 200 units from your spawn point, facing you.
7. **Other Digimon:** select the `Field` node and type a key in **Debug Partner** in the Inspector (e.g. `dw1:gabumon`, `dw1:greymon`; keys are shown in the DW Data dock), then F5: that model follows instead, with its own size. Clear it afterwards (it's saved in the scene).
   - Wrong if: he floats, sinks, slides without animating, runs in place, or gets stuck walking next to the tamer.
8. **What isn't there yet:**
   - care states (sleep, eating, poop), other entity collisions (NPCs), the Health Shoe;
   - the tamer can walk through the partner (the tamer's side of the collision comes with NPCs).

## Clock (`scripts/systems/clock.gd`, `clock_hud.gd`, `specs/clock.md`)

`test_clock.gd` prints `OK: Clock checks`. Then run the project (F5):

1. **HUD:** the alarm clock sits in the top-left corner: two bells, the face (day / evening / night sectors), the minute hand, a small creature on top that moves, and a yellow hour marker on the rim. The game starts at 08:00, so the hand points up and the marker is on the right side.
2. **Time runs:** one game minute per real second. The hand turns 6° per minute; the help line at the bottom shows the year, day and time.
3. **`T`** jumps one hour ahead (debug key). At 17:00 the creature on top switches to its night frame (with a "Z"); at 16:00, 20:00 and 06:00 the background fades over about a second: day → evening → night → day. Maps without a day / night cycle never change (110 of them, e.g. Drill Tunnel `TUNN01`, Grey Lord's Mansion `YAKA02`; use `[` / `]` to get there).
   - Wrong if: the fade jumps instantly, happens at other hours, or happens indoors.
4. **Real time:** waiting from 15:59 to 16:00 without pressing `T` starts the same fade on its own.
5. **Map changes:** walking to another map at night keeps the night background.
6. **What isn't there yet:**
   - the partner's status bars next to the clock (care step);
   - the clock sliding out while scripts stop the time (no scripts yet);
   - the tamer and Digimon don't get darker at night (no field lighting yet).

## Game state (`scripts/state/game_state.gd`, `specs/game_state.md`)

There is no save menu yet, so these checks are about the save file itself.

1. `test_game_state.gd` prints `OK: GameState checks`. Its line `ERROR: Parse JSON failed` is expected: it is the test's broken save being refused.
2. Open the test's save `user://test_game_state_saves/slot_01.json`. On Windows that is `%APPDATA%\Godot\app_userdata\Digimon World GODOT\test_game_state_saves\`; in the editor: Project > Open User Data Folder.
   - It is readable JSON: `preview` (player, partner, area "File City", playtime), then `state` with `clock`, `tamer`, `partner` (with `care`: about 65 fields such as `remaining_lifetime`, `happiness`, `poop_level`), `world`, `money`, `inventory`, `script`.
   - Content is written as keys: `"digimon": "dw1:agumon"`, `"item": "dw1:lrg_recovery"`, `"screen": "dw1:twna01"`.
   - `script.values` has 35 entries (0–34): the original saves only those.
3. New-game values, if you remember the game's start:
   - 08:00 on day 0;
   - the partner has 3 lives and a lifetime of 288;
   - the start is File City.
   
   The 50,000 bits and the full inventory are the C default record, which the intro scripts may replace (`specs/game_state.md` §5).
4. Hand edit: change `money` in `slot_01.json` and load it, e.g. from a script or the debug panel when it exists. The new value is used; a broken edit is refused with a message instead of loading garbage.

## Save and Title Menu (`scripts/ui/title_menu.gd`, `save_slot_box.gd`, `save_routines.gd`, `specs/save.md`)

`test_save_system.gd` prints `OK: save system checks (34 run)`.

1. **Title screen boot:**
   - Run the game (F5). The title screen appears with the native `TITLE2.TIM` background art.
   - The menu shows "NEW GAME", "CONTINUE GAME", and "BATTLE MODE".
   - If there are no save files in `user://saves`, "CONTINUE GAME" is greyed out / dimmed and pressing ✕ plays the error sound.
   - "BATTLE MODE" is stubbed (plays error sound).
   - Selecting "NEW GAME" fades out and transitions into the intro scene with Jijimon.
   - Debug: `DW_SKIP_TITLE=1` skips the title menu straight into a new game.

2. **Save slot box and Continue:**
   - With an existing save game, selecting "CONTINUE GAME" opens the slot selection box.
   - Each saved slot displays the slot number, player name, partner species, area name, and playtime formatted as `HH:MM`.
   - Selecting a valid slot asks for confirmation and loads the save directly into the saved map with restored clock, partner, and tamer state.
   - Pressing △ closes the slot box and returns to the title menu.

3. **In-game Save Machine (builtin 0x30):**
   - Access the save machine in Jijimon's house (TWNA02) or via script builtin `0x30`.
   - The slot box opens in save mode.
   - Selecting an empty slot saves immediately; selecting an existing slot asks "Overwrite this data? YES / NO".
   - Prosperity Points (script value 1) are automatically recalculated before saving based on recruited Digimon.

4. **Partner Sleep Save Prompt:**
   - When the partner goes to sleep (either via Menu > Sleep or naturally when exhausted), while the screen is completely faded to black, a prompt asks "Do you want to save?".
   - Choosing "No" continues waking up the partner normally.
   - Choosing "Yes" opens the slot selection box to save the game before waking up.
