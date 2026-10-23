# Evolution (`EVOLUTION_REQS`, `EVOLUTION_PATHS`, `EVOLUTION_STATS_GAINS`, `EVOLUTION_ITEM_TARGET` → `output/evolution/`)

Which Digimon the partner can evolve into, what each needs, and what evolving does to the stats. Converter: `dwdata/groups/evolution.py` (`python -m dwdata convert evolution`).

## 1. Source

| Table | Where | C type | US symbol size |
|---|---|---|---|
| `EVOLUTION_REQS` | `src/main/evolution.c:30` | `EvoRequirements[63]` (`include/dw/evl.h:45`), 28 bytes | 1764 |
| `EVOLUTION_STATS_GAINS` | `src/main/evolution.c:348` | `EvoStatsGains[66]` (`evl.h:30`), 14 bytes | 924 |
| `EVOLUTION_PATHS` | `src/main/evolution.c:417` | `EvolutionPath[62]` (`evl.h:40`): `int8_t from[5]`, `to[6]` | 682 |
| `EVOLUTION_ITEM_TARGET` | `src/main/item.c:1923` | `uint8_t[44]` | — |
| selection code | `evolution.c:674–1051`, `partner_impl.c:2106–2140`, `src/evl/evl.c:1353–1525` | | |

- **Indexing:**
  - `EVOLUTION_REQS[id]` and `EVOLUTION_STATS_GAINS[id]` are indexed by the **target** Digimon. Requirements exist for ids 0–62; gains for 0–65, and `targetDigimon` is always the index.
  - `EVOLUTION_PATHS[id - 1]` holds the paths of Digimon `id` (1–62).
  - `EVOLUTION_ITEM_TARGET[item - 0x47]` covers items 0x47–0x72.
- **Release differences:** none. The tables write -1 as `0xffff` / `0xff` in signed fields; the reader converts them as C does (476 + 459 values).

## 2. Original usage

### When the partner evolves

`tickConditions` (`partner_impl.c:2106–2126`) runs on hour changes in the field, while the tamer is idle. `evoTimer` counts game hours (`clock.c:140`, plus hours slept, `partner_impl.c:1172`) and is reset by each evolution.

| Level | Hours | Function |
|---|---|---|
| 1 Fresh | ≥ 6 | `getFreshEvolutionTarget` (`evolution.c:674`): fixed target, Botamon 1 → Koromon 2, Punimon 15 → Tsunomon 16, Poyomon 29 → Tokomon 30, Yuramon 43 → Tanemon 44 |
| 2 In-Training | ≥ 24 | `getInTrainingEvolutionTarget` (`:690`) |
| 3 Rookie | ≥ 72 | `getRookieEvolutionTarget` (`:724`); if no candidate qualifies and `evoTimer ≥ 96`: **Numemon (11)** |
| 4 Champion | ≥ 144 | `getChampionEvolutionTarget` (`:789`) |
| 4 Champion | = 360 | `handleSpecialEvolutions(3)` (`:852`) |

`virusBar ≥ 16` overrides everything: the partner becomes **Sukamon (0x27)**, and its stats are saved in `sukaBackup*` (`partner_impl.c:2127–2140`).

### Requirement score (`calculateRequirementScore`, `evolution.c:928`)

For a candidate target, one point for each of:

1. **Care mistakes:** `careMistakes >= care`, or `<= care` when `flags & 0x10`.
2. **Weight:** within `weight ± 5`.
3. **Stats:**
   - For a **Rookie** target, the partner's highest stat (HP and MP / 10; the last one wins ties) must be one whose requirement is 1.
   - Otherwise, every stat must be ≥ its requirement, again with HP and MP / 10. -1 counts as always met: a signed compare with -1.
4. **Bonus:** any one of these:
   - the current Digimon is `digimon`
   - `discipline >=`
   - `happiness >=`
   - `battles >=`, or `<=` when `flags & 0x01`
   - learned techniques `>= techs` (`getNumMasteredMoves` counts the set bits of `learnedMoves`, `:1038`)
   - Fields at -1 are skipped. Several Rookie targets have `battles = -2` and `techs = 0`, which every partner meets, so they always get the bonus point.

If the score is ≥ 3 and another candidate is already the best, the "raised" history adjusts it (`hasDigimonRaised`):

- a target already raised loses to one not raised yet: score 0;
- a target not raised yet beats a raised best: +1.

### Choosing among candidates

The candidates are the `to[6]` list of the current Digimon, in order; -1 entries are skipped.

- **In-Training** (`:690`): the candidate with the highest score ≥ 3 wins. On a tie, the first one stays.
- **Rookie / Champion** (`:724`, `:789`): every candidate with score ≥ 3 gets an average of the stats its requirements name (HP and MP / 10). The highest average wins.
  - **Quirk to keep:** `statTotal` and `statCount` are reset only when a candidate becomes the best. A candidate that doesn't win leaves its sums in place, and they are added into the next candidate's average.

### Special evolutions (`handleSpecialEvolutions`, `evolution.c:852`)

They run only while the tamer is idle.

- **Mode 2**, after waking up (`partner.c:359`):
  - Rolled under 30 %:
    - Birdramon (0x15) or Seadramon (0x0a) with discipline 100, happiness 100 and tiredness 0 → Airdramon (7)
    - Vegiemon (0x19) with ≥ 50 battles and discipline 100 → Ninjamon (58)
    - Drimogemon (0x26) with Def ≥ 500 and discipline 100 → Monochromon (47)
  - Rolled under 50 %, an In-Training (2, 0x10, 0x1e, 0x2c) on map 1 → Kunemon (32).
- **Mode 3**, after a praise / scold (`partner.c:417`) and at `evoTimer == 360`:
  - Whamon (0x18) or Shellmon (0x23) at level 4 with `evoTimer == 200`, rolled under 30 % → Coelamon (49).
  - `NANIMON_TRIGGER` → Nanimon (53). It is set when a Rookie is praised / scolded with discipline 0 and happiness -100 (`partner_impl.c:1149–1155`).
  - Level 4 with `evoTimer ≥ 240`, rolled under 50 % → Vademon (28).
  - The later rules overwrite the earlier ones.

### Evolution items (`handleEvoItems`, `item.c:2190`)

- Items 0x47–0x72 evolve the partner into `EVOLUTION_ITEM_TARGET[item - 0x47]`, only if the partner's level is the target's level − 1.
  - **Two items can never work:** Electo ring (0x53) targets id 0 and Moon mirror (0x72) targets WereGarurumon (62). Both have level 0, so no partner has level −1. Confirmed in play: these items were never implemented in the game.
- Items 0x7d / 0x7e / 0x7f evolve into Gigadramon (0x40), Panjyamon (0x3f) and MetalEtemon (0x41), with no level check.
- Using an item sets `HAS_USED_EVOITEM`: no stat gains, and no +96 lifetime for an Ultimate (`evl.c:1362`, `:1415`).

### Applying an evolution (`EVL_applyEvolution`, `src/evl/evl.c:1353`)

- **Scale:** if the target is Devimon (6), Numemon (0x0b), Sukamon (0x27) or Nanimon (0x35), the target's level is < 3, or the partner is Sukamon, every base stat is scaled: `stat * brains / 10`, using the gains table's `brains` field (`EVL_scaleBaseStats`, `:1495`).
  - Sukamon evolving away instead gets `backup + (stat - backup / 2) / 2` from its saved stats.
- **Gain:** otherwise, if no item was used, each stat becomes `stat + gain / 10` if it is already ≥ the gain, else `(gain + stat) / 2` (`:1363–1397`), then it is clamped.
  - During a script, reaching Champion gives `addTamerLevel(20, 1)` and Ultimate `addTamerLevel(100, 1)`.
- **Then, for every evolution:**
  - weight = `RAISE_DATA[new].defaultWeight`
  - care mistakes and battles are reset
  - Ultimate without an item: +96 lifetime
  - the new technique: see `specs/moves.md` / `specs/digimon.md`
- Reincarnation (`reincarnatePartner`, `evolution.c:1054`) starts a new partner from `EVOLUTION_STATS_GAINS[id].targetDigimon`.

### Evolution chart

`renderEvoChartDetail` (`game_menu.c:3465–3610`) draws `from` and `to`. It counts the entries that aren't -1 but draws only ids > 0.

## 3. Mapping

`output/evolution/requirements.json`, `paths.json`, `stat_gains.json` and `item_targets.json`, plus `report.md`. Every record keeps its raw C values in `c`.

- **`requirements`:**
  - `id` (target), `name`, `level`, `has_requirements`
  - `stat_rule`: `highest` for Rookie targets, otherwise `minimum`
  - `stats`: booleans for `highest`, values or null for `minimum`
  - `care_mistakes {value, at_most}`, `weight {value, range}`
  - `bonus {from_digimon, discipline, happiness, battles {value, at_most}, techs}`; null = not used
- **`paths`:** `id`, `from`, `to` (ids > 0, in C order); `ignored_values` keeps the other entries that aren't -1 (Phoenixmon's `to` holds -2 and 0).
- **`stat_gains`:** `applied_as` is `gain` (`gains {hp … brain}`) or `scale` (`scale` = brains / 10). `unused_gains` holds the gain values of a scaled target that also has them (WereGarurumon 62).
- **`item_targets`:** `item`, `target`, `from` (table entry or code constant), `needs_level`, `can_work`.

## 4. Godot usage (planned)

- `GameData.evolution_requirements(id)`, `evolution_paths(id)`, `evolution_gains(id)` and `evolution_item_target(item)` feed a GDScript port of `evolution.c` and `EVL_applyEvolution`.
- The selection rules of §2 are code: hour thresholds, fixed Fresh targets, the Numemon fallback, special evolutions, the Sukamon virus bar, the "raised" priority, and the averaging quirk. Port them function by function.
- **Modding:**
  - Requirements, gains and paths can change within their C types.
  - Keep the indexing (requirements and gains by target id; paths by id - 1) and the level order of paths (one level up).
  - Keep the hard-coded ids of §2 in sync: Numemon 11, Sukamon 0x27, Nanimon 0x35, the scaled targets, the Fresh targets, the special-evolution ids.

## 5. Verification

The converter checks:

- the decomp exists, and the three structs have the mapped fields in every release;
- the selection code still contains the constants this spec documents: the score ≥ 3, the weight ± 5, the Numemon fallback, the hour thresholds, the virus bar, the scaled targets and gain formulas, and the Fresh targets;
- every table parses in every release, and each table's size equals its US symbol size where one is given;
- every path goes one level up and is listed on both sides, except the chart-only `from` entries, which are reported (Leomon, Garurumon, Frigimon, Mojyamon → WereGarurumon);
- requirements:
  - flags use only 0x01 / 0x10, and padding is 0;
  - Rookie stat requirements are 1 or -1;
  - the bonus Digimon is one the target comes from;
  - every target of a scored path (anything but Fresh) has requirements;
- `targetDigimon` equals the index, and the scaled targets that can be reached have no gain values;
- the item table covers items 0x47–0x72, and the constant targets of 0x7d–0x7f are in `handleEvoItems`.

Tests: `tests/test_evolution.py` (real data).

## 6. Open questions

- **WereGarurumon (62)** has level 0, no technique list, requirements, and four chart `from` entries, but no path leads to it, and its item (Moon mirror) can't work. It looks like content cut from the US data; check the other releases' `DIGIMON_DATA` if this matters.
- **Phoenixmon's `to` = {-2, 0}**: never used for evolution (Ultimates have no selection). The chart skips them.
- **Map 1** in the Kunemon rule: which map that is comes from the map list (`CURRENT_SCREEN`); not resolved here.
- **`hasDigimonRaised`** reads the "raised" bit field, which a save file holds; the Godot save system has to keep it.
