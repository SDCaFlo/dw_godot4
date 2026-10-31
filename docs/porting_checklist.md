# Porting checklist

Go through this before each commit of a ported step, whoever does the work (the main session or a sub-agent, Claude or another model). It gathers the rules that live in `specs/scenes.md`, `specs/content.md` and `docs/agent_workflow.md`, in the order you meet them.

Written on 2026-10-30, after the review of step 6 (death and reincarnation; the findings R1–R13 in `PLANS.md`). Each rule names the finding it would have caught.

## 1. Every value has a C source

**Every constant and timeline in a spec gets a table row: the C function, the line and the value. A value with no source in the C is marked `port-only` or `stand-in`. Until every row has one or the other, the step isn't done.** This makes guessing visible.

| What | C source (`file.c:line`, function) | Value | Status |
|---|---|---|---|
| Iris closes | `murd.c:199`, `MURD_tickScene` | `0x23` frames | ported |
| Hearts spacing | `murd.c:730`, `MURD_renderLivesBox` | `x = i * 0x22 - 0xb` | ported |
| Screen black after a map load | none | `Fade.hold(LOAD_FRAMES)` | port-only: the original's load time has no Godot equivalent |
| Partner dissolve | `model.c:3003`, `renderWireframed` | `partner_dissolve.gdshader` | stand-in until `PLANS.md` 6-2 |

- **ported:** the code does what the C line does.
- **port-only:** the C has no such value, and the port needs one (an engine difference). Say why.
- **stand-in:** a placeholder for something the C does that isn't ported yet. Say what will replace it and when (a `PLANS.md` step). Never describe a stand-in as accurate (R12).
- The same status goes in the code comment next to the constant (`## murd.c:512`, `## stand-in (PLANS 6-2)`), so a reader of the code sees it too.

**Why:** in step 6 a spec paraphrased the C ("a white flash rises") instead of citing it, and every slip went straight into the code. The C darkens the screen (R13). Also: an invented 20-frame delay (R2), invented timelines (R6), signals that didn't exist (R7), wrong map names and a wrong heart spacing (R13).

## 2. The spec comes before the code, and someone else checks it

- The spec is written from the decomp and approved by the user before code starts (`docs/agent_workflow.md` "The flow").
- **The model that implements a step doesn't write its spec or review its own result.** A step done by a cheaper model has its spec and its review done by a stronger one.
- An open question stays in the spec's "Open questions" until the C answers it. It is never filled in with a guess.

## 3. Port the routine, not the effect

- A script opcode or routine sets what the C sets, and nothing more. Example: `CALL_DIGIMON_ROUTINE` 3/4/7/9/10 only set states; the states do the work (R1, R6).
- Port the states and their sub-states with the C's own frame numbers. Don't write a "cutscene" that looks similar.
- Don't skip an opcode as "unported" when the scene depends on it. In step 6, `WAIT_FOR_ENTITY 0xD5` was skipped, so the dialogue started during the death scene.
- Port every side effect of a C function, even ones you can't see: flags cleared, timers reset, stats set. Step 6 missed `IS_NATURAL_DEATH` (R3), the timer resets and the reincarnation stats (R5, R8).

## 4. When the user reports a bug

1. **Re-read the C function behind it before changing anything.**
2. Find where the port differs from the C, and fix that.
3. Never add behaviour that isn't in the C to make the symptom go away, such as the step-6 rebirth "hop" and "fast evolution delay" (R6, R2). If the port really needs something extra, it is `port-only` (§1), and the spec says why.
4. Log it in `ISSUES.md` with the evidence and the cause you found.

## 5. Godot structure (`specs/scenes.md` §3, `specs/content.md` §4)

- Calls go down, signals go up. References are injected or come from `@export` / fixed child names. No lookups across the tree (R9).
- Autoloads: inject them, falling back to `get_node_or_null("/root/<Name>")` in `_ready`. Never `Engine.has_singleton`, which doesn't see autoloads (R4).
- Moddable parts are scenes that their owner instantiates. A scene file that exists must be used (R10).
- Shaders go in `.gdshader` files, not strings (R10): `shaders/`, or next to the scene that owns them. Variants that differ only in `render_mode` are small files sharing a `.gdshaderinc`.
- Logic reads properties, never ids: record ids live in the data, which the data porter derives from the C and checks (R11).
- Logic classes stay testable headless. The frame order stays in `Field._frame`.

## 6. Tests the implementer doesn't write alone

- The **acceptance checks come from the spec**: values from its §1 table, end-to-end runs in the real field (`tests/exit_scan.tscn`, a step scan like `tests/death_scan.tscn`). When a sub-agent does the step, the main session writes them first, and the agent doesn't change them.
- A test that only repeats the implementation's own constants proves nothing. Test against the C's numbers.
- Run **every** suite and the scans, not just the new one:
  - `godot --headless --path . -s res://tests/test_<name>.gd` for each suite, `tests/test_rules.gd` included;
  - `godot --headless --fixed-fps 60 --path . res://tests/exit_scan.tscn` and the step's scans;
  - the porters' `python -m unittest discover -s tests -t .` when data changed.

## 7. Checked by `tests/test_rules.gd`

A script can check part of §5, so `tests/test_rules.gd` does. It fails on:
- a lookup across the tree (`get_tree().root`, `get_tree().current_scene`, `get_parent()` / `owner` searches, groups outside `scripts/debug/`), or a `/root/` path that isn't an autoload;
- `Engine.has_singleton` / `Engine.get_singleton`;
- a shader written as a string;
- a record id compared with a number in logic (`digimon_id == 15`), or kept as a constant (`BABY_IDS := [...]`).

It would have caught R4, R9, R10 and R11 in step 6. When it fails, fix the code. Add an exception to the test only for a real one, with the reason.

## 8. Before you say "done"

- [ ] The spec's value table has a source or a status for every row (§1).
- [ ] The spec's "As built" notes match the code, and the stand-ins are listed as stand-ins.
- [ ] All suites and scans pass (§6), with the output in the report.
- [ ] `VERIFY.md` has short in-game checks for the user. No movies.
- [ ] `PLANS.md` is updated. Every new bug is in `ISSUES.md`.
