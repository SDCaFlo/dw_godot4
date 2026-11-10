# Data from the disc (distribution step D3)

How the data porter builds its output from the player's own `SLUS_010.32` and `*_REL.BIN` instead of the decomp, so players need only their disc (`../../specs/distribution.md` §2.1). This spec holds the inventory made on 2026-11-09 and the plan in steps. Status: `PROGRESS.md`.

## 1. Rule

- **Values** (stats, names, rules, text) come from the player's binaries at convert time. Never committed.
- **Layouts** (which binary, address, size, C type: fields, offsets, widths, signedness, array shape, enum names, pointer kinds) and **metadata** (`schema`, `source`, `used_by`, `godot`) are facts about the code, generated from the decomp by us and committed. They hold no values and no strings.
- **The decomp stays the trusted source** in our tests: for every table, the output read from the disc equals the output read from the decomp (minus what a US disc can't have, §4), or the table doesn't switch.

## 2. Inventory (2026-11-09)

Found with the US symbol files (`config/us/symbols*.txt`) and the splat configs (`config/us/<binary>.yaml`): file offset = address - load address. Load addresses:

| Binary | File | Load address |
|---|---|---|
| main | `SLUS_010.32` | `0x80090000` (0x800-byte header; text at `0x80090800`) |
| btl, std, vs | `BTL_REL.BIN`, `STD_REL.BIN`, `VS_REL.BIN` | `0x80052AE0` |
| kar | `KAR_REL.BIN` | `0x80053800` |
| eab, endi, evl | `*_REL.BIN` | `0x80060000` |
| doo2, fish | `*_REL.BIN` | `0x80070000` |
| murd | `MURD_REL.BIN` | `0x8007C000` |
| dooa / dget | `*_REL.BIN` | `0x80080000` / `0x80080800` |
| trn, trn2 | `*_REL.BIN` | `0x80088800` |
| mov | `MOV_REL.BIN` | `0x80010000` |

`src/shop/script_menu.c` is linked into **main** (`config/us/main.yaml:132`), not an overlay.

### 2.1 C tables

**Apart from the exceptions below, every C-table source of the 61 non-text tables has a symbol, and every one lies in initialized data inside its file** (none in main's BSS, `0x801353F8`+; none past a file's end; none all zeros). The exceptions, listed below the table: two tables with no symbols (values in code) and one missing symbol (`VS_DEMO_DIGIMON`). Sizes not given have no `size:` in the symbol file; the C type gives them (`tables.size_check` already does).

| Table | Records | Sources: symbol, binary, address (size) |
|---|---|---|
| `digimon/aura_projectile_types` | 129 | `BTL_AURA_PROJECTILE_TYPES` btl `0x8007383C` (0x60c) |
| `digimon/condition_fx_offsets` | 177 | `CONDITION_FX_OFFSETS` main `0x8012A2C4` (0x588) |
| `digimon/digimon_data` | 180 | `DIGIMON_DATA` main `0x8012CEB4` (0x2490) |
| `digimon/file_names` | 180 | `PTR_DIGIMON_FILE_NAMES` main `0x8011D19C` |
| `digimon/item_take_distance` | 66 | `ITEM_TAKE_DISTANCE` main `0x80122D24` (0x42) |
| `digimon/raise_data` | 66 | `RAISE_DATA` main `0x801225BC` (0x738) |
| `digimon/sleep_patterns` | 8 | `SLEEP_PATTERN` main `0x80122CF4` (0x30) |
| `digimon/sound_ids` | 180 | `DIGIMON_VBALL_SOUND_ID` main `0x80127F40`; `DIGIMON_VLALL_SOUND_ID` main `0x80127EFC` (0x42) |
| `digimon/training_animations` | 67 | `TRN_TRAINING_ANIM_IDS` trn `0x8008F050` (0x86) |
| `evolution/item_targets` | 47 | `EVOLUTION_ITEM_TARGET` main `0x80127C5C` |
| `evolution/paths` | 62 | `EVOLUTION_PATHS` main `0x8012B66C` (0x2aa) |
| `evolution/requirements` | 63 | `EVOLUTION_REQS` main `0x8012ABEC` (0x6e4) |
| `evolution/rules` | 28 | (no symbols) |
| `evolution/stat_gains` | 66 | `EVOLUTION_STATS_GAINS` main `0x8012B2D0` (0x39c) |
| `font/ascii` | 95 | `CHAR_MAPPING_NORMAL` main `0x8012F39C` (0xc); `CHAR_MAPPING_SPECIAL` main `0x8012F3A8` (0x84) |
| `font/clut` | 16 | `FONT_CLUT` main `0x80130FE8` |
| `font/en_eu` | 188 | `CHAR_TO_GLYPH_TABLE` main `0x801307E0` (0x9e); `GLYPH_DATA` main `0x80130880` |
| `font/en_us` | 79 | `CHAR_TO_GLYPH_TABLE` main `0x801307E0` (0x9e); `GLYPH_DATA` main `0x80130880` |
| `font/ja` | 992 | `CHAR_TO_GLYPH_TABLE` main `0x801307E0` (0x9e); `GLYPH_DATA` main `0x80130880` |
| `font/text_colors` | 18 | `TEXT_COLORS` main `0x8012B918` (0x33) |
| `items/card_data` | 66 | `CARD_DATA` main `0x8012FFD8` (0x108); `CARD_PRICES` main `0x8012FFC4` |
| `items/healing_values` | 4 | `HEALING_VALUES` main `0x8013435C` (0x8); `HEAL_EFFECT_VARIANT` main `0x80134364` (0x4) |
| `items/inventories` | 2 | `DEFAULT_INVENTORY_TYPES` main `0x80131618` (0x1e); `DEFAULT_INVENTORY_AMOUNTS` main `0x801315F8` (0x1e); `INITIAL_INVENTORY_TYPES` main `0x80125F44` (0x1e); `INITIAL_INVENTORY_AMOUNTS` main `0x80125F24` (0x1e) |
| `items/item_data` | 128 | `ITEM_PARA` main `0x801269DC` (0x1000); `ITEM_FUNCTIONS` main `0x80127C88`; `ITEM_CLUT_DATA` main `0x80127BDC` (0x80) |
| `items/item_effects` | 120 | `ITEM_FUNCTIONS` main `0x80127C88` |
| `items/recyclable_items` | 78 | `RECYCLABLE_ITEMS` main `0x8012FE78` (0x4e) |
| `items/shops` | 1 | `SHOP_MAPS` main `0x8012FE68`; `SHOPKEEP_DIGIMON_TYPES` main `0x8012FE5C` (0xb) |
| `items/sort_orders` | 3 | `ITEM_SORT_ORDER` main `0x8012A9C4` (0x12) |
| `moves/learn_chances` | 58 | `MOVE_LEARN_CHANCES` main `0x80125FA4` (0xae) |
| `moves/move_data` | 122 | `MOVE_DATA` main `0x8012623C` (0x7a0) |
| `moves/training_learning` | 7 | `TRN_D_8008F14C` trn `0x8008F14C` (0x38); `TRN_D_8008F184` trn `0x8008F184` (0x18) |
| `moves/type_factors` | 7 | `TYPE_FACTORS` main `0x80125F70` (0x31) |
| `systems/arena` | 1 | `STD_BRACKET_PATHS` std `0x8007A598` (0xc0); `STD_BRACKET_ROW_Y` std `0x8007A48C` (0x10); `STD_BRACKET_HOP_Y` std `0x8007A474` (0x18); `STD_BRACKET_PROJECTILE_CLUTS` std `0x8007A57C` (0x10); `STD_CAMERA_PRESETS` std `0x8007A390` (0x6c); `STD_RANDOM_VIEWPOINTS` std `0x8007A3FC` (0x1e); `STD_D_8007A41C` std `0x8007A41C` (0x58); `STD_INTRO_NAME_COLORS` std `0x8007A370` (0x1e); `STD_INTRO_NAME_CHAR_SIZES` main `0x80134800` (0x4); `STD_INTRO_NAME_CHAR_OFFSETS` main `0x80134804` (0x4); `STD_COMMAND_LABEL_U` main `0x801348B0` (0x5); `STD_COMMAND_LABEL_W` main `0x801348B8` (0x5); `STD_COMMAND_MENU_LAYOUTS` std `0x8007A6A8` (0x50); `STD_COMMAND_ICON_UVS` std `0x8007A6F8` (0x10); `STD_SPECIAL_ICON_UVS` std `0x8007A708` (0x10); `STD_FINISHER_PULSE` std `0x8007A9A4` (0x30); `STD_FINISHER_SEGMENT_U` main `0x801348C0` (0x8); `STD_FINISHER_SEGMENT_W` main `0x801348C8` (0x8); `STD_FINISHER_SEGMENT_X` main `0x801348D0` (0x8); `STD_CHAMPION_CAMERA_Y` std `0x8007AA30` (0x10); `STD_LOSE_DROP_Y` std `0x8007AA40` (0x30); `STD_LOSE_TILT` std `0x8007AA70` (0x1c); `STD_WIN_X_CURVE` std `0x8007AA8C` (0x24); `STD_VERSUS_MODEL_TARGET_X` main `0x801348DC` (0x8) |
| `systems/babies` | 1 | `BABY_IDS` main `0x801345B4`; `REINCARNATE_BABY_TYPE` main `0x80134BAC` (0x8) |
| `systems/battle_ai` | 8 | `TARGET_ATTACKER_CHANCE` main `0x801346E8` (0x4); `BTL_YOUR_CALL_POWER_PRIO` main `0x801346EC` (0x4); `BTL_YOUR_CALL_MP_PRIO` main `0x801346F0` (0x4); `BTL_YOUR_CALL_WIDE_PRIO` main `0x801346F4` (0x4) |
| `systems/battle_command_lists` | 6 | `BRAIN_TO_COMMAND_MAP` main `0x801346E0` (0x5) |
| `systems/battle_commands` | 6 | `BRAIN_TO_COMMAND_MAP` main `0x801346E0` (0x5); `STD_BRAIN_TO_COMMAND_MAP` main `0x80134880` (0x5) |
| `systems/battle_hud` | 16 | `BTL_COMMAND_MENU_LAYOUTS` btl `0x80072E7C` (0x3c); `BTL_COMMAND_MENU_SLIDE_Y` btl `0x80072EB8` (0x10); `BTL_COMMAND_MENU_SLIDE_X` btl `0x80072EC8` (0x10); `BTL_COMMAND_ICON_UVS` btl `0x80072ED8` (0x10); `BTL_SPECIAL_ICON_UVS` btl `0x80072EE8` (0x10); `BTL_COMMAND_LABEL_U` main `0x80134728` (0x5); `BTL_COMMAND_LABEL_W` main `0x80134730` (0x8); `BTL_SHOUT_HOP_OFFSETS` btl `0x80072E54` (0x14); `BTL_SHOUT_DROP_OFFSETS` btl `0x80072E68` (0x14); `BTL_DEATH_COUNTDOWN_DIGIT_U` main `0x80134738` (0x4); `BTL_DEATH_COUNTDOWN_DIGIT_V` main `0x8013473C` (0x4); `BTL_STATUS_BAR_X` btl `0x80073280` (0x10); `BTL_STATUS_BAR_SPRITES` btl `0x800732C0` (0x3c); `BTL_FINISHER_PULSE` btl `0x80073290` (0x30); `BTL_BATTLE_START_TEXT_POSITIONS` btl `0x80073014` (0x26c); `FLEE_BUBBLE_SCALE` main `0x8012BAD8` (0xa) |
| `systems/birdramon_transport` | 6 | `BIRDRA_TRANSPORT_TARGETS` main `0x8013024C` (0x30) |
| `systems/curling` | 1 | `KAR_D_8005B438` kar `0x8005B438` (0x18); `MAIN_D_80134A08` main `0x80134A08` (0x8); `KAR_D_8005AB8C` kar `0x8005AB8C` (0xa); `KAR_D_8005AB80` kar `0x8005AB80` (0xc); `MAIN_D_80134A4C` main `0x80134A4C` (0x3); `MAIN_D_80134A44` main `0x80134A44` (0x4); `KAR_D_8005B450` kar `0x8005B450` (0x10); `KAR_D_8005B460` kar `0x8005B460` (0x18); `KAR_D_8005B418` kar `0x8005B418` (0x20); `KAR_D_8005B04C` kar `0x8005B04C` (0xa); `KAR_D_8005B40C` kar `0x8005B40C` (0xa); `KAR_D_8005AF58` kar `0x8005AF58` (0xf4); `KAR_D_8005B318` kar `0x8005B318` (0xf4); `MAIN_D_80134A20` main `0x80134A20` (0x8); `KAR_D_8005B478` kar `0x8005B478` (0x14); `KAR_D_8005B48C` kar `0x8005B48C` (0x14); `KAR_D_8005B4A0` kar `0x8005B4A0` (0x2c); `KAR_D_8005B4CC` kar `0x8005B4CC` (0x28); `KAR_D_8005B4F4` kar `0x8005B4F4` (0x64); `KAR_D_8005B558` kar `0x8005B558` (0x14); `KAR_D_8005B56C` kar `0x8005B56C` (0x14) |
| `systems/enemy_music` | 48 | `ENEMY_MUSIC_MAPPING` main `0x8012BAE4` (0x30) |
| `systems/fishing` | 1 | `FISH_KIND_INFO` fish `0x8007AA28` (0xa8); `FISH_BITE_CHANCE` fish `0x8007A3EC` (0xc8); `FISH_BAIT_CHANCES` fish `0x8007A1F4` (0xc); `FISHING_MAP_DATA` fish `0x8007AAD0` (0x70) |
| `systems/flee_chances` | 10 | `FLEE_CHANCES` main `0x8012BB14` (0xc) |
| `systems/item_throw` | 24 | `ITEM_THROW_HEIGHT` main `0x8012F36C` |
| `systems/jukebox` | 63 | `BGM_TRACK_NAMES` main `0x8012FEC8`; `MAIN_D_801303B8` main `0x801303B8` |
| `systems/maps` | 255 | `MAP_ENTRIES` main `0x801292D4` (0xff0); `MAP_NAME_PTR` main `0x801291BC`; `ARENA_MAPS` main `0x801345BC`; `MAP_LIGHT_UPDATE_DATA` main `0x801345C4` |
| `systems/mojyamon_trades` | 4 | `MOJYAMON_ITEMS_GIVE` main `0x80130438`; `MOJYAMON_ITEMS_GET` main `0x80130444` |
| `systems/movies` | 4 | `MOV_MOVIES` mov `0x8001094C` (0xa0) |
| `systems/naming` | 3 | `NAMING_CHAR_PAGES` main `0x80130774` |
| `systems/new_game` | 1 | (no symbols) |
| `systems/psx_math` | 2 | `SIN_LOOKUP_TABLE` main `0x80122480`; `ATAN_LOOKUP_TABLE` main `0x8011FA1C` |
| `systems/script_stat_limits` | 23 | `STATS_LIMIT_ARRAY` main `0x80130318` |
| `systems/slot_machine` | 1 | `TRN_D_8008F1AC` trn `0x8008F1AC` (0x27); `TRN_D_8008F2CC` trn `0x8008F2CC` (0xa) |
| `systems/stat_gain_factors` | 4 | `STAT_GAIN_ENEMY_FACTORS` main `0x801344D0` |
| `systems/toilets` | 10 | `TOILET_DATA` main `0x80122E10` (0x50) |
| `systems/tournament_medals` | 6 | `TOURNAMENT_MEDAL_IDS` main `0x8012BACC`; `MEDAL_NAMES` main `0x80124828` |
| `systems/tournament_schedule` | 30 | `TOURNAMENT_SCHEDULE` main `0x80130198` |
| `systems/tournament_win_chances` | 12 | `STD_WIN_CHANCES` std `0x8007A58C` (0xc) |
| `systems/tournaments` | 23 | `TOURNAMENT_NAMES` main `0x801300E0`; `TOURNAMENT_GRADES` main `0x8013013C`; `STD_GRADES` std `0x80079C24` (0x5c); `STD_OPPONENT_BASE_STATS` std `0x800799B4` (0x30) |
| `systems/training_spots` | 7 | `TRN_TRAINING_SPOTS` trn `0x8008F28C` (0x40) |
| `systems/versus` | 1 | VS_DEMO_DIGIMON — no symbol; `VS__BATTLE_COUNTS` main `0x80134550`; `STD_STAT_BAR_LIMITS` std `0x8007A364` (0xc) |

- `evolution/rules`, `systems/new_game`: values written in code (literals, `switch` cases). They become committed constants with their C source (`docs/porting_checklist.md`), checked against the decomp by a dev test.
- `systems/versus` `VS_DEMO_DIGIMON`: no US symbol; find its address (the VS overlay's demo list) or treat it as a code constant.
- `font/ja`, `font/en_eu`: the inventory script matched them to the US `CHAR_TO_GLYPH_TABLE` / `GLYPH_DATA`, but they are read from the JP and EU releases (`groups/font.py` `LANGUAGES`); they are not on a US disc (§4).
- Function-pointer fields (`ITEM_FUNCTIONS`) read as addresses; the snapshot maps each address to its function name.
- Pointer fields (`PTR_DIGIMON_FILE_NAMES`, `MAP_NAME_PTR`, `BGM_TRACK_NAMES`, …) are followed in the binary to the string.

### 2.2 Text

US strings are stored as C strings: ASCII mixed with 2-byte Shift-JIS, NUL-terminated, with the padding the YAML writes as `\0` (`specs/text.md` §2). Of the 1,240 strings, the US release has 1,117 (123 are `NULL` in US, 15 are empty). Checked against `SLUS_010.32` and the overlays, encoding each string's `en_us` variant as Shift-JIS:

| How the string is found | Strings | Result |
|---|---|---|
| Own symbol (`symbol.address`) | 724 | all equal byte for byte. Nine more strings with symbols (`STR_YEAR_DAY`, `MAIN_D_8013143C`, …, `BTL_STR_DROPPED`) have no YAML `en_us` variant: the text group reads them as C literals (`c_text`, `PROGRESS.md`); they get read at their symbol the same way |
| Embedded in a table (`storage: embedded`: `ITEM_NAMES` in `ITEM_PARA`, `DIGIMON_NAMES` in `DIGIMON_DATA`) | 317 | read with the table's struct |
| No symbol, searched in the block's binary | 18 unique, 20 several hits, 22 none | located once, at snapshot time (below) |
| Aliases (`same_as`) | 7 | point to another string |

The 60 strings with no symbol are short literals (`"Run"`, `"Attack"`, `"10"`, `"#C1#W"`, `" "`, `"Bubble"`) or sit in main's small-data section while their C file belongs to an overlay (`MAIN_D_801349D8` `"Hooked!"` of `fish.c`). The snapshot step finds each one's address once, in every binary, using the C reference (the pointer table, or the instruction that loads it) to pick among several hits, and fails on anything ambiguous; a short list of pinned addresses covers what can't be derived.

## 3. Design: the same groups, another source

The group converters (`dwdata/groups/*.py`) stay as they are: their checks, keys, references and resolved names are the value of the porter. What changes is what answers their questions.

- **Decomp mode** (today, developers): `CIndex`, `Decomp`, `textyaml` read the decomp.
- **Disc mode** (players): a `DiscIndex` / `DiscDecomp` / disc text source answer the same calls (`tables.load`, `index.table`, `index.program(...).structs`, `tables.used_by` / `source` / `diffs` / `size_check`, `decomp.references`, `text.load_file`, `index.switch_cases`) from:
  - the **snapshot**: committed JSON under `dwdata/snapshot/us/`, written by a dev command (`python -m dwdata snapshot`) from the decomp: per table its binary, address, size and C type layout; per string its binary, address and length, or the table field it is embedded in; the metadata the groups otherwise compute from the decomp (`used_by`, `source`, references); the code-only values (§2.1);
  - the **binaries**: values read at the snapshot's addresses with the snapshot's layouts. Only the US release exists in disc mode.
- `python -m dwdata convert all` uses disc mode when given `--disc <folder>` (the disc image later, D4), decomp mode otherwise.
- **The snapshot holds no values**: a dev test fails if any string of the text output, or any table's record values, appear in it.

Where a group walks the decomp in its own way and a facade would be awkward, the group gets an explicit disc path, still checked by the equivalence test.

### 3.1 The snapshot as built (D3a, 2026-11-09)

`python -m dwdata snapshot [--disc <folder>] [--check]` runs every group in decomp mode with `CIndex.table` recorded (`disc.Recorder`), then writes `dwdata/snapshot/us.json`:

| Key | Content |
|---|---|
| `binaries` | per binary: disc file, load address (from `config/us/<binary>.yaml`), sha1 of the US file: `DiscIndex` refuses another file |
| `tables` | per `c_file:name`: binary, address, size, `located` (`symbol`, `search`: the decomp's bytes found once in the C file's binary, or `absent` with `why`), C type, declaration line, element lines, `slots` |
| `structs` | struct layouts by name; same-named structs with another layout and anonymous structs get `#n` keys |
| `pointers` | address → symbol name, read from the developer's binaries where the decomp writes a pointer (then cross-checked with the symbol maps), so strings without a symbol are named too |

`slots` (path → override) cover two things the binary can't say alone: **merged strings** (the compiler stores identical literals once, so one address carries several of the decomp's names: `KAR_D_8005AF58` / `KAR_D_8005B318`'s lines, `{"pointer": [address, name]}`), and **string-id fields** (`ITEM_PARA.name`, `DIGIMON_DATA.name`: the decomp's macro hook writes the string id, the binary holds the text: `{"text_id": id}`; the text read there is kept in `DiscIndex.texts` for D3b).

Findings:
- 448 tables equal the decomp's US values exactly after reading; 1 is **absent**: `VS_DEMO_DIGIMON` (`vs_demo.c` is linked into no US binary; neither its list nor its file paths are on the disc). In disc mode `systems/versus.demo_digimon` has no source; the game doesn't use it.
- `char` arrays are text, `uint8_t` / `int8_t` arrays are numbers (as the decomp gives them).
- Checked with `--check` (committed snapshot = rebuilt) and `tests/test_disc.py`: the reader on synthetic bytes, the snapshot's strings (only identifiers, addresses, paths, hashes), every table read with the disc alone, a wrong file refused, and the equivalence with the decomp.

### 3.2 The strings (D3b, 2026-11-09)

The snapshot's `strings` section gives, per text table, block and string (its id, or `#<index>` for an entry), where the US text is: `{located, binary, address, length}`, or a table field (`{located: "slot", table, path}`, D3a's string-id slots), or another entry of the block (`{alias}`). `DiscText` reads them: `length` bytes at the address, decoded as Shift-JIS, give the en_us variant exactly as the YAML writes it (padding NULs kept). The text group's own output, recorded during the snapshot run, says which strings the US release has.

| Located | Strings | How |
|---|---|---|
| `symbol` | 725 | the string's own US symbol |
| `slot` | 308 | a char field of `ITEM_PARA` / `DIGIMON_DATA` (names) |
| `pointer` | 32 | the address a C table's pointer to it holds (D3a's pointers and slots): the curling dialogue lines |
| `search` | 17 | its bytes + NUL found once in the block's binary or main, between the nearest strings of the same file with an address |
| `array` | 16 | entry k of the block's `char *` array (`MOVE_NAMES`' unnamed entries) |
| `copy` | 14 | found several times (the command labels "Run", "Attack", …, "HP", "MP", "5"): the nearest copy. Any copy reads the same text, because `DiscIndex` accepts only the US files (sha1) |
| `row` | 4 | row k of the block's `char[n][m]` (`ITEM_MENU_LABELS`) |
| `empty` | 1 | an empty string nothing points to (`MAIN_D_80134A43`) |

Every byte location is checked when the snapshot is built: the bytes at the address are the string, followed by a NUL. All 1,117 US strings read from the binaries equal the decomp's (`tests/test_disc.py`).

**Found on the way:** the data porter's YAML reader trimmed every Unicode space around plain scalars; YAML trims only spaces and tabs. The naming screen's last lowercase row is `ｚ` + four U+3000 in the YAML and in the binary, and the output had `ｚ`. Fixed in `textyaml.py` (`tests/test_textyaml.py`); no other string changed.

## 4. What a US disc can't give

| Output | Decomp mode | Disc mode |
|---|---|---|
| Text | `ja`, `en_us`, `en_eu` + release overrides | `en_us` only |
| Fonts | `en_us`, `ja`, `en_eu` | `en_us` only |
| `release_values`, `diffs` | other releases' values | absent |

`GameData` must work with only `en_us` (the language setting and the debug `L` key offer only the languages present). Supporting a JP or EU disc later means one snapshot per release.

## 5. Steps

| Step | What | Rating |
|---|---|---|
| D3a (done 2026-11-09) | Snapshot command and format; the disc source for C tables (`DiscIndex`: struct layouts, arrays, pointers, function-pointer names); an equivalence check comparing, table by table, the US values read from the binary with `CIndex`'s US values | Hard (Opus) |
| D3b (done 2026-11-09) | Text from the disc: string addresses (symbols, embedded, the 60 located at snapshot time), the disc text source, en_us only; equivalence on every US string | Medium |
| D3c | Groups to disc mode one at a time, each with its equivalence test: moves, items, digimon, evolution (+ `rules`), font (US), systems (+ `new_game`, `VS_DEMO_DIGIMON`) | Medium each |
| D3d | `convert all --disc`; the whole output equal to decomp mode minus §4; the test suite run with the decomp hidden; `GameData` with en_us only | Medium |

## 6. Open questions

- Q1: ~~The shop-text string whose symbol didn't match.~~ Resolved 2026-11-09: a counting slip in the check; every string read at its symbol matches.
- Q2: ~~`VS_DEMO_DIGIMON`'s address.~~ Resolved 2026-11-09: not on a US disc (§3.1).
- Q3: Whether the metadata (`used_by`, `source`) goes in the snapshot, or disc-mode output drops it and the editor dock reads it from a committed copy. The D3a snapshot holds only what `CIndex.table` gives; decide in D3c with the first group. The output's shape for the game (`records`, `schema`, `godot`) must not change.
