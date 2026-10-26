# Moves (`MOVE_DATA`, `TYPE_FACTORS`, `MOVE_LEARN_CHANCES`, training learning → `output/moves/`)

Techniques (power, MP, range, element, status), the element damage factors and the technique learn chances. Converter: `dwdata/groups/moves.py` (`python -m dwdata convert moves`), C reader `dwdata/cdata.py`.

## 1. Source

| Table | Where | C type | US symbol |
|---|---|---|---|
| `MOVE_DATA` | `src/main/item.c:124` | `Move[122]` (`include/dw/move.h:6`), 16 bytes each | `0x8012623C`, size 0x7A0 |
| `TYPE_FACTORS` | `src/main/item.c:94` | `uint8_t[7][7]` | `0x80125F70`, size 0x31 |
| `MOVE_LEARN_CHANCES` | `src/main/item.c:104` | `uint8_t[58][3]` | `0x80125FA4`, size 0xAE |
| names | `text/main/item.yaml` → `MOVE_NAMES` (same index) | `char *[122]` | see `specs/text.md` |
| `TRN_D_8008F14C` | `src/trn/trn_reward.c:77` | `uint8_t[56]` (7 elements × 8) | trn overlay |
| `TRN_D_8008F184` | `src/trn/trn_reward.c:87` | `int8_t[8][3]` | trn overlay |

The first three are linked into **main**, the two `TRN_` tables into the training overlay (**trn**). They are read once per release (`#if VERSION_…` branches applied). The only difference between releases: `MOVE_DATA[30]` (Full Potential) has `unk3 = 0` in `jp` and `1` in every later release (`item.c:275–287`).

`struct Move` (`move.h:6`): `int32_t distance; int16_t power; uint8_t mpCost, iframes, range, special, status, accuracy, statusChance, unk3, unk4, unk5;`

## 2. Original usage

The battle code exists three times with the same logic: `src/btl/battle_main.c` (field battles, binary btl), `src/std/std_main.c` (std overlay) and `src/vs/vs_main.c` / `vs_combat.c` (versus mode). Line numbers below are from `battle_main.c`; `move_data.json` → `used_by` lists every function with the fields it reads.

### Ids

- A Digimon's moves are stored as **animation ids**: slot `k` of `DIGIMON_DATA[type].moves[16]` is animation `0x2e + k`. `entityGetTechFromAnim` (`utils2.c:333`) turns an animation id into a technique id: `DIGIMON_DATA[type].moves[anim - 0x2e]` (special case: Digimon type 0x3c, animation 0x3c → technique 0x70).
- `0x00–0x39` **techniques**: the learnable ones. The partner's learned set is a bit field indexed by technique id (`hasMove` / `learnMove`, `utils2.c:311–331`). `MOVE_LEARN_CHANCES` has one row per technique (58). Enemies' used techniques below 0x3a are recorded for learning (`BTL_setupMoveExecution`, `:2551`).
- `0x2c`/`0x30` (Dynamite Kick) and `0x37`/`0x39` (Horizontal Kick) are learned together (`learnMove`, `utils2.c:322–327`). The second id is the unnamed `MOVE_NAMES` entry; the output marks the pair as `learned_with`.
- `0x2d` **Counter**: never chosen as a normal technique (`BTL_isMoveUsable`, `:2330`), triggered when a melee attack hits a Digimon that knows it (`BTL_tickAttackHits`, `:2163–2179`: needs MP ≥ 165, chance `speed / level` %), and ignores 70 % of the defender's defense (`BTL_calculateDamage`, `:2006`).
- `0x3a–0x70` **finishers**: `(tech >= 0x3a) && (tech < 0x71)` (`:2334`, `:2436`, `:2526`, …). They cost no MP, stop the AI of everyone else while they run (`NO_AI_FLAG`), always hit, and use their own damage formula.
- `0x71–0x78`: the "Bubble" techniques of baby Digimon (Botamon's first slot is 0x71). `0x79`: the technique of the generic attack effect 0x179 (`BTL_getAttackTech`, `:1881`). Both are `other` in the output.

### Fields

- **`power`** (`int16_t`):
  - Damage of a technique, `BTL_calculateDamage` (`:1988`). For each of the defender's 3 elements `e`, `f = TYPE_FACTORS[move.special][e]`, or 10 if the slot is `0xff`. Then `diff = clamp(off - def, -500, 500)` and `dmg = (f1+f2+f3) * (power + diff * power / 500) / 30 * (90..110) / 100`.
  - Damage of a finisher: `(off + power) * (f1+f2+f3) / 30`. The partner's damage is then scaled by its finisher charge-up (`finisherChargeup[0] / 40` when it reaches 41 or more); enemies' damage gets ×(100..200) / 100. Both then get the ×(90..110) / 100 random factor.
  - Damage is clamped to 1..9999.
  - Power is also **subtracted from the fighter's speed buffer** when the technique starts (`BTL_setupMoveExecution`, `:2580`, minimum −155). In charge mode 1, the fighter waits until the buffer reaches `power` (`BTL_applyChargeRequirement`, `:2409`; `BTL_tickChargeState`, `:1142`).
  - Used by the AI (`BTL_getStrongestMove`, `:3051`), and by evolution: `EVL_applyEvolution` (`evl.c:1418–1449`) teaches the technique with the **lowest non-zero power** of the new Digimon's element block. The blocks start at fire 0, air 8, ice 16, mech 24, earth 32, battle 40, filth 49.
- **`mpCost`**: always used × 3 (`mp` in the output).
  - The menus show `mpCost * 3` (`game_menu.c:2602`, `:3140`).
  - Partner: the cost is `mpCost * 3` raised by half while injured or sick (`PARTNER_PARA.condition & 0x60` = `CONDITION_INJURED | CONDITION_SICK`), then lowered by brain: 999 → ×4/5, ≥ 900 → ×17/20, ≥ 800 → ×9/10, ≥ 700 → ×19/20 (`BTL_setupMoveExecution`, `:2527–2543`; the usability check `BTL_isMoveUsable`, `:2346–2361`, applies the same factors in the other order, with integer steps). The partner's MP is reduced through `mpDamageBuffer`.
  - Enemies: they pay `mpCost * 3` directly unless `FLEE_DISABLED[0]` is set (`:2548`).
  - Finishers never cost MP.
- **`distance`** (`int32_t`): the preferred attack distance **squared**, in world units (100 = one map tile). Every value is a perfect square (0, 100² … 1000²).
  - `BTL_tickRangedAttack` (`:1348–1363`) compares the squared distance to the target with `total = distance + (radius_a + radius_b)²`. The attacker walks closer when it is above `total × 1.3`, backs away when below `total × 0.7`, and attacks in between.
  - Melee techniques ignore it: they walk to contact (`BTL_tickMeleeAttack`, `:1264`).
  - The AI sorts by it (`BTL_getMoveWithHighestDistance`, `:1397`).
- **`iframes`**: frames the target can't be hit again after a hit (`invulnerableTimer`, `:2157`). Hit particle lifetime is `iframes + 16` (`BTL_startHitAnimation`, `:2081`).
- **`range`**: what the fighter does before attacking (`BTL_tickQueuedMove`, `:1188`):
  - `1` melee: walk to contact. Can be countered.
  - `2`, `3` ranged: keep the preferred distance. The AI weights `3` higher when two or more enemies are alive (`VS_selectPartnerMove`, `vs_main.c:1622–1639`), so `3` is read as an area technique (name `area`).
  - `4` self: start at once, targeting the user (`:2503`). Limited by `buffsRemaining`: brain / 100 + 1 below 400 brain, 4 below 600, 5 from 600 (`battle_setup.c:108–113`).
  - `0` only on 0x79.
  - The menus draw the range label from a texture strip at `(range - 1) * 16` (`game_menu.c:2605`).
  - The self techniques are buffs, applied by technique id in `BTL_applyBuffMove` (`:1887`):
    - 0x29 Muscle Charge: Off +30 %
    - 0x2a War Cry: Off +10 %, Def +5 %, Speed +10 %
    - 0x22 Mass Morph: Def +20 %, Speed +10 %
    - 0x15 Aqua Magic: Off +7 %, Def +8 %, Speed +7 %
    - 0x1e Full Potential: Off +25 %, Def +15 %, Speed +15 %
- **`special`** (element): the row of `TYPE_FACTORS` (`:1999`).
  - Learning (`battleMoveLearning`, `battle_ui.c:233–275`): after a won battle, every technique the enemies used that the partner doesn't know, whose element is one of the partner's 3 elements and which is in the partner's 16-slot move list, is a candidate. It is kept when `MOVE_LEARN_CHANCES[id][j] > randomLimit(100)`, where `j` is the index of the matching element. One candidate is learned at random.
  - The menus pick the icon palette by element (`renderDigimonMoveBox`, `game_menu.c:3283`).
  - `0xff` (none) only on 0x79.
- **`status`** / **`statusChance`**: on a hit, if `statusChance > randomLimit(100)` and the target isn't protected (`BTL_applyMoveStatus`, `:3149`):
  - 1 poison: timer 100
  - 2 confusion: timer 200–300
  - 3 stun: timer 200–240
  - 4 flatten
  - The menus draw a status icon at `(status - 1) * 12` (`game_menu.c:2609`).
- **`accuracy`** (`BTL_calculateHitChance`, `:1922`):
  - Always 100 when the defender is below level 3, stunned, flattened or senile, while the partner is sick (`PARTNER_PARA.condition & 0x40` = `CONDITION_SICK`, `params.h:16`; this applies to every attack), when the defender's speed buffer is ≤ 0, or when the defender is in a technique animation (≥ 0x2e).
  - Finishers always hit and break a block. A blocking defender is never hit by anything else.
  - Otherwise `x = accuracy / 2 * (def.speed - att.speed / 10) / 999` (×6/5 while the defender walks, animations 0x21/0x22) and `chance = clamp(accuracy - x, 0, 100)`.
- **`unk3`** (flags; the C name is kept in `c`):
  - Bit 0, `needs_target`: unusable while the fighter has no target (`BTL_isMoveUsable`, `:2342`). If it is started without a target, it auto-targets (the partner for enemies, the last living enemy for the partner; `BTL_setupMoveExecution`, `:2506–2518`).
  - Bit 1, `shared_cooldown`: starting such a technique sets `FLEE_DISABLED[1] = 110`. While that counter is above 0 (it counts down once per battle tick, `:658`), no bit-1 technique can start (`BTL_startQueuedMove`, `:2469`; `BTL_isMoveOnCooldown`, `:2487`).
- **`unk4`, `unk5`**: read nowhere, 0 everywhere.

### Training learning (`TRN_D_8008F14C`, `TRN_D_8008F184`)

`TRN_tryLearnMove(type)` (`trn_reward.c:811`), called by the Brains award when the partner's Brains cross 150, 250, 350, 450, 550, 650, 750, 800, 850, 900, 950 or reach 999 (`:582`):

- For each element slot `i` of the partner (`DIGIMON_DATA[type].special[i]`, 0xff skipped), it walks `TRN_D_8008F14C[special[i] * 8 + k]` for k = 0–7. It skips the techniques the partner has (`hasMove`); the first one in the partner's 16-slot list is that slot's candidate, with weight `TRN_D_8008F184[k][i]`.
- The candidate with the highest weight wins (ties keep the lower slot) and is learnt if `weight > randomLimit(100)`.
- Each element's 8 entries are the techniques of its block in another order (checked). Rank 0 of slot 0 has weight 0.

See `../specs/training.md` §6.8.

### `TYPE_FACTORS[attacker][defender]`

The first index is the element of the technique (or of the attacker, in `BTL_calculateTargetScore`, `:3348`); the second is the defender's element. The values are 2, 5, 10, 15, 20, i.e. ×0.2 to ×2.0. `BTL_calculateElementBonus` (`:3570`) maps them to the AI bonuses 1, 3, 5, 7, 10; `BTL_calculateTargetScore` inverts them for target choice.

## 3. Mapping

`output/moves/move_data.json`, `type_factors.json` and `learn_chances.json`, in the common table shape (`CLAUDE.md`), plus `report.md`.

- The records hold the **US** values (`source.reference_release`). `release_values` lists the C fields that differ in another release: `{release: {c field: value}}`.
- `move_data` record:
  - `id`, `name` (`string_id`, `text` per language from `MOVE_NAMES`; unnamed entries take the id of the earlier entry and `same_as: true`), `category`, `line`
  - the fields of §2 renamed: `distance_squared` (C `distance`), `mp_cost` (C `mpCost`), `element` (C `special`), `status_chance` (C `statusChance`), `flags` (C `unk3`, split into bits plus `value`)
  - derived fields: `mp` = mp_cost × 3, `distance` = √distance_squared
  - enums as `{id, name}`
  - `learned_with` for the two pairs
  - **Battle properties** (`../../specs/battle.md` §6), so the battle code reads properties, not ids:
    - `buff {off, def, speed}`: the self techniques' gains as `[num, den]` (the stat rises by `stat * num / den`, C order), read from the `case` lines of `BTL_applyBuffMove` (`battle_main.c:1887`) with a pattern on each `BTL_buffStats` call; checks: every case is a list of buffs, and the buff techniques are exactly the self-range techniques. Aqua Magic `{off 7/100, def 8/100, speed 7/100}`, Full Potential `{1/4, 3/20, 3/20}`, Mass Morph `{def 1/5, speed 1/10}`, Muscle Charge `{off 3/10}`, War Cry `{1/10, 5/100, 1/10}`;
    - `counter: true` on 0x2D (the code's `tech == 0x2d` tests, already checked as evidence);
    - `effect_scene`: documented in the schema only, for content packs (`../../specs/battle_effects.md` §3.0); no `dw1` record sets it.
  - `menu_cell {row, column}`: the technique's cell in the Digimon screen's grid (`game_menu.c` `getEquippedSlot` / `equipMove` / `renderDigimonMoveBox`; `../specs/status_screens.md` §3.4): grid rows 0–6 show the id blocks 0–7, 0x28–0x2F, 8–0xF, 0x20–0x27, 0x10–0x17, 0x18–0x1F, 0x31–0x38; 0x30 / 0x39 share the cells of 0x2C / 0x37. The converter checks the C's row mapping is still there. The ported screen finds a cell's technique by this property, not by computing ids.
  - `c`: the record with its C field names, exactly as the initializer gives it
- `type_factors`: 7 records (attacker element), each with 7 `against` cells: `defender`, `factor`, `multiplier` (factor / 10).
- `learn_chances`: 58 records: `id`, `name` (en_us, for reading), `chances[3]`.
- `training_learning`: 7 records (one per element): `element {id, name}`, `moves [{rank, move {id, key, name}}]`, `c` (the 8 C ids); the top-level `weights` is `TRN_D_8008F184` as `[rank][slot]`.
- `used_by`: every function that reads the table, its lines, the struct fields used on those lines (a text match of `.field` / `->field`, so fields read through a pointer on another line are missed) and the releases.
- **Element names are labels, not from the decomp.** The ids are certain: they are the TYPE_FACTORS indices, and the technique blocks of `EVL_applyEvolution` match them. The names Fire, Battle, Air, Earth, Ice, Mech, Filth are the game's names for those blocks (the menus draw them from a texture, not from text). The status and range names describe what the code does.

## 4. Godot usage

- `GameData.move(id)` returns the record; the name comes through `GameData.text_entry("main/item", "MOVE_NAMES", id)` or the record's `name`. `GameData.type_factor(attacker, defender)` and `GameData.learn_chance(id, slot)` cover the other two tables. `GameData.training_learning(element)` and `GameData.training_learn_weight(rank, slot)` serve the Brains training (`Training.try_learn_move`).
- The battle system ports the formulas of §2: damage, hit chance, MP with the brain and condition modifiers, status, range behaviour, the shared cooldown and the finisher rules by id range. Each GDScript function names the C function it reproduces.
- **Modding:**
  - Values can change freely within the C types: power ≤ 32767, the other fields ≤ 255.
  - Keep 122 records and the id ranges: finishers 0x3a–0x70, techniques 0x00–0x39 with one learn-chance row each, and the element blocks used by evolution.
  - Keep `distance_squared` squared. The 7 × 7 factor table is indexed by element id.

## 5. Verification

The converter checks:

- the decomp exists, and `struct Move` has the 12 fields the spec maps, in every release;
- the code still tests the id ranges (`(tech >= 0x3a) && (tech < 0x71)`, `tech == 0x2d`, `tech = 0x79`, the learned-together pairs);
- each table parses in every release with no issues: no unknown macros, no value that doesn't fit its field, no zero-filled values (hex literals of signed fields, such as `0xffff` = -1, are read as C reads them and only counted);
- `MOVE_DATA` has one record per `MOVE_NAMES` entry, and each table's size equals the US symbol size (`config/us/symbols.txt`);
- every record has known values: `range` 0–4, element 0–6 or 0xff, `status` 0–4, `distance` a perfect square, `status` and `statusChance` both set or both 0, flags only bits 0–1, `unk4` and `unk5` 0;
- techniques and finishers have a name;
- `TYPE_FACTORS` is 7 × 7 with values in {2, 5, 10, 15, 20} (the cases `BTL_calculateElementBonus` handles);
- `MOVE_LEARN_CHANCES` has 58 rows (techniques 0x00–0x39);
- `TRN_D_8008F14C` has 8 entries per element and `TRN_D_8008F184` is 8 × 3; each element's entries are techniques of that element.

Tests: `tests/test_cdata.py` (reader), `tests/test_moves.py` (a generated decomp with 122 moves, a failing value, and real data when `dw_decomp` is present).

## 6. Open questions

- **Range 3** is called `area` from the AI weighting only. Whether those techniques really hit several targets is decided by their effect (EFE) data, not by `MOVE_DATA`. Check when the battle effects are ported.
- **Range 2 vs 3** behave the same in `BTL_tickQueuedMove`; any other difference would be in the effect code.
- **`0x71–0x79`**: the baby Bubble techniques and the generic technique 0x79 aren't learnable. How 0x79 is chosen beyond effect id 0x179 isn't traced yet.
- **Status 4 (flatten)** sets `flatTimer = -1` and resets the fighter. The flattened state itself is handled in `BTL_tickFlatState`, not traced here.
- **Element names** are the game's names (§3), not text from the decomp. Confirm them in the game's menu.
