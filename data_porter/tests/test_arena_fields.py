"""Step 4e-4, step 1 (specs/arena.md §5.0): the arena tables (systems/arena), the Digimon's arena
properties and the maps' arena_model. Acceptance checks written from the C by the reviewer; don't change them
to make the code pass. Step 1 is built: the tests always run (DW_STEP_4E_4=0 skips them)."""

import json
import os
import tempfile
import unittest
from pathlib import Path

from dwdata.groups import digimon, systems
from dwdata.paths import DEFAULT_INPUT

STEP = int(os.environ.get("DW_STEP_4E_4", "1") or 1)

AGUMON = 3
BOTAMON = 1
MEGADRAMON = 0x36
LEOMON = 0x30
ETEMON = 0x2A
PANJYAMON = 0x3F
GIGADRAMON = 0x40
METALETEMON = 0x41
HKABUTERIMON = 0x3C
JMOJYAMON = 0x4E


def _id(v):
    return v["id"] if isinstance(v, dict) else v


@unittest.skipUnless(STEP >= 1, "PENDING (DW_STEP_4E_4 < 1)")
@unittest.skipUnless((DEFAULT_INPUT / "src" / "std" / "std_main.c").is_file(), "dw_decomp not available")
class ArenaFieldsTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.systems = systems.convert(DEFAULT_INPUT, Path(cls.tmp.name))
        cls.digimon = digimon.convert(DEFAULT_INPUT, Path(cls.tmp.name))
        root = Path(cls.tmp.name)
        cls.arena = json.loads((root / "systems" / "arena.json").read_text(encoding="utf-8"))["records"]
        cls.maps = json.loads((root / "systems" / "maps.json").read_text(encoding="utf-8"))["records"]
        cls.mons = json.loads((root / "digimon" / "digimon_data.json").read_text(encoding="utf-8"))["records"]

    @classmethod
    def tearDownClass(cls):
        cls.tmp.cleanup()

    def test_checks_pass(self):
        for out in (self.systems, self.digimon):
            self.assertTrue(out.ok, [f"{c.name}: {c.detail}" for c in out.checks if not c.passed])

    def rec(self):
        self.assertEqual(len(self.arena), 1)
        self.assertEqual(self.arena[0]["key"], "dw1:arena")
        return self.arena[0]

    def test_music(self):
        # STD_initializeTournament (std_setup.c:245-249); STD_addBracket / STD_addBracketIntro (playMusic(0x1d, ...)).
        m = self.rec()["music"]
        self.assertEqual(m["arena_fonts"], [0x1E, 0x20])
        self.assertEqual(m["bracket_font"], 0x1D)

    def test_bracket(self):
        b = self.rec()["bracket"]
        # STD_BRACKET_PATHS (std_main.c:1450): signed x, facing.
        self.assertEqual(len(b["paths"]), 8)
        self.assertEqual(b["paths"][0]["x"], [-129, -129, -110, -110, -76, -76, -7, -7])
        self.assertEqual(b["paths"][0]["facing"], [1] * 8)
        self.assertEqual(b["paths"][5]["x"], [46, 46, 28, 28, 61, 61, -7, -7])
        self.assertEqual(b["paths"][5]["facing"], [0, 0, 1, 1, 0, 0, 0, 0])
        self.assertEqual(b["paths"][7]["facing"], [0] * 8)
        # STD_BRACKET_ROW_Y (1395), STD_BRACKET_HOP_Y (1389), STD_BRACKET_PROJECTILE_CLUTS (1440).
        self.assertEqual(b["row_y"], [27, 1, 1, -25, -25, -51, -51, -72])
        self.assertEqual(b["hop_y"], [0, 0, 0, 1, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20, 23, 26, 24, 23, 24, 26])
        self.assertEqual(b["projectile_cluts"], [3, 0, 0, 0, 2, 0, 3, 2, 0, 2, 3, 3, 0, 3, 2, 0])

    def test_camera(self):
        c = self.rec()["camera"]
        # STD_CAMERA_PRESETS (1360): rotation x, y, z, translation x, y, z.
        self.assertEqual(len(c["presets"]), 9)
        self.assertEqual(c["presets"][0], [0xE0, 0x140, 0, 0, 0xC8, 0x5DC])
        self.assertEqual(c["presets"][3], [0xFA0, 0xEC0, 0, 0, 0x104, 0x4B0])
        self.assertEqual(c["presets"][8], [0xE0, 0x800, 0, 0, 0x208, 0xBB8])
        # STD_RANDOM_VIEWPOINTS (1372): signed.
        self.assertEqual(c["random_viewpoints"], [[-512, -512, -1200], [512, -512, -1200], [-512, -512, 1200],
                                                  [512, -512, 1200], [3000, -1500, 3000]])
        # STD_D_8007A41C (1380): the intro camera's 22 keys.
        self.assertEqual(c["intro_keys"], [-1, 0, 30, 45, 60, 80, 100, 120, 140, 160, 180, 200, 220, 240, 260,
                                           280, 300, 320, 340, 360, 0, 0])
        # The SVECTORs (std_main.c:720-729), x y z.
        v = c["vectors"]
        self.assertEqual(v["intro_stage1_rot"], [0, -1592, 0])
        self.assertEqual(v["chase_rotation"], [0, -1592, 0])
        self.assertEqual(v["intro_stage2_rot"], [-227, 1479, 0])
        for name in ("intro_stage1_pos", "chase_offset", "intro_offset", "intro_rotation", "intro_stage2_pos"):
            self.assertEqual(v[name], [0, 0, 0], name)

    def test_intro(self):
        i = self.rec()["intro"]
        # STD_INTRO_NAME_COLORS (1350), STD_INTRO_NAME_CHAR_SIZES / OFFSETS (714-715), STD_STAT_BAR_LIMITS (1346).
        self.assertEqual(len(i["name_colors"]), 10)
        self.assertEqual(i["name_colors"][0], [0x80, 0x80, 0x80])
        self.assertEqual(i["name_colors"][3], [0xD0, 0x1E, 0x50])
        self.assertEqual(i["name_colors"][6], [0x32, 0xB4, 0xC8])
        self.assertEqual(i["char_sizes"], [64, 44, 38, 32])
        self.assertEqual(i["char_offsets"], [16, 7, 3, 0])
        self.assertEqual(i["stat_bar_limits"], [9999, 9999, 999, 999, 999, 999])

    def test_command_menu(self):
        m = self.rec()["command_menu"]
        # STD_COMMAND_LABEL_U / W, STD_COMMAND_MENU_LAYOUTS, STD_COMMAND_ICON_UVS, STD_SPECIAL_ICON_UVS (std_main.c:1500-1545).
        self.assertEqual(m["label_u"], [0, 11, 25, 39, 50])
        self.assertEqual(m["label_w"], [11, 14, 14, 11, 11])
        self.assertEqual(len(m["layouts"]), 8)
        self.assertEqual(m["layouts"][0], [0, 4, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])
        self.assertEqual(m["layouts"][7], [0, 1, 2, 1, 2, 1, 2, 1, 3, 0xFF])
        self.assertEqual(m["icon_uvs"][0], [0, 0xC0])
        self.assertEqual(m["icon_uvs"][6], [0xC0, 0xC0])
        self.assertEqual(m["special_icon_uvs"][3], [0x60, 0xD0])
        self.assertEqual(len(m["icon_uvs"]), 8)

    def test_finisher_gauge(self):
        g = self.rec()["finisher_gauge"]
        # std_hud.c:375 STD_FINISHER_PULSE, :422-424 the segments.
        self.assertEqual(g["pulse"], [0x20, 0x40, 0x60, 0x80, 0xA0, 0xC0, 0xE0, 0xFF, 0xE0, 0xC0, 0xA0, 0x80])
        self.assertEqual(g["segment_u"], [0, 6, 10, 18, 22, 30, 38, 43])
        self.assertEqual(g["segment_w"], [6, 4, 8, 4, 8, 8, 5, 5])
        self.assertEqual(g["segment_x"], [0, 6, 10, 18, 22, 30, 38, 43])

    def test_scenes(self):
        s = self.rec()["scenes"]
        # std_hud.c:399-426.
        self.assertEqual(s["champion_camera_y"], [-368, -517, -645, -754, -842, -912, -991, -1000])
        self.assertEqual(len(s["lose_drop_y"]), 24)
        self.assertEqual(s["lose_drop_y"][:3], [-700, -692, -668])
        self.assertEqual(s["lose_drop_y"][10:12], [100, 67])
        self.assertEqual(s["lose_tilt"], [5, 20, 47, 83, 130, 188, 256, 334, 423, 522, 632, 752, 882, 1024])
        self.assertEqual(s["win_x_curve"], [0, 1, 5, 11, 20, 31, 45, 61, 80, 101, 125, 151, 180, 211, 245, 281, 320, 0])
        self.assertEqual(s["versus_target_x"], [-273, -86, 94, 272])

    def test_arena_name(self):
        # STD_INTRO_DIGIMON_NAMES (std_main.c:870, 112 x 14 raw glyph bytes); the length is
        # strlen(DIGIMON_DATA[type].name) / 2 (US name), 10 for 0x4E and 0x3C (STD_addIntroText 1650-1653).
        mons = self.mons
        self.assertEqual(mons[BOTAMON]["arena_name"]["glyphs"], [0x1F, 0x2C, 0x18, 0x34, 0x15] + [0] * 9)
        self.assertEqual(mons[AGUMON]["arena_name"]["glyphs"], [0x00, 0x1F, 0x0A, 0x34, 0x15] + [0] * 9)  # row 3, std_main.c:883
        self.assertEqual(mons[0x1D]["arena_name"]["glyphs"], [0x25, 0x2C, 0x3C, 0x34, 0x15] + [0] * 9)  # Poyomon, row 29, :987
        self.assertEqual(mons[AGUMON]["arena_name"]["length"], 3)        # "Agumon"
        self.assertEqual(mons[BOTAMON]["arena_name"]["length"], 3)       # "Botamon"
        self.assertEqual(mons[MEGADRAMON]["arena_name"]["length"], 5)    # "Megadramon"
        self.assertEqual(mons[HKABUTERIMON]["arena_name"]["length"], 10)
        self.assertEqual(mons[JMOJYAMON]["arena_name"]["length"], 10)
        for r in mons:
            if r["id"] < 0x70:
                self.assertEqual(len(r["arena_name"]["glyphs"]), 14, r["key"])
            else:
                self.assertNotIn("arena_name", r, r["key"])

    def test_bracket_sprite_and_icon(self):
        # STD_DIGIMON_SPRITE_CLUT (1406), STD_BRACKET_PROJECTILE_ICONS (1422), 112 each.
        mons = self.mons
        self.assertEqual([mons[i]["bracket_sprite_clut"] for i in range(8)], [0, 0, 0, 0, 1, 1, 3, 1])
        self.assertEqual(mons[0x40]["bracket_sprite_clut"], 6)
        self.assertEqual([mons[i]["bracket_icon"] for i in range(8)], [0, 0, 0, 3, 4, 2, 6, 5])
        self.assertEqual(mons[0x6F]["bracket_icon"], 0x0C)
        for r in mons:
            if r["id"] >= 0x70:
                self.assertNotIn("bracket_sprite_clut", r, r["key"])
                self.assertNotIn("bracket_icon", r, r["key"])

    def test_arena_stand_in(self):
        # STD_tournamentMain (std_setup.c:530-540): 0x40 -> 0x36, 0x3F -> 0x30, 0x41 -> 0x2A.
        mons = self.mons
        self.assertEqual(_id(mons[GIGADRAMON]["arena_stand_in"]), MEGADRAMON)
        self.assertEqual(_id(mons[PANJYAMON]["arena_stand_in"]), LEOMON)
        self.assertEqual(_id(mons[METALETEMON]["arena_stand_in"]), ETEMON)
        self.assertEqual(sorted(r["id"] for r in mons if "arena_stand_in" in r), [PANJYAMON, GIGADRAMON, METALETEMON])

    def test_map_arena(self):
        # STD_tournamentMain (std_setup.c:544): CURRENT_SCREEN == 0x6A (BETL02) -> arena 1, else 0.
        by_id = {r["id"]: r for r in self.maps}
        self.assertEqual(by_id[0x6A]["key"], "dw1:betl02")
        self.assertEqual(by_id[0x6A]["arena_model"], 1)
        self.assertEqual(by_id[208]["arena_model"], 0)
        self.assertEqual(by_id[223]["arena_model"], 0)
        self.assertEqual([r["id"] for r in self.maps if r["arena_model"] == 1], [0x6A])
        # The existing ARENA_MAPS flag stays (the dget overlay maps, checkArenaMap).
        self.assertEqual(sorted(r["id"] for r in self.maps if r["arena"] is True), [0xD0, 0xDF])


if __name__ == "__main__":
    unittest.main()
