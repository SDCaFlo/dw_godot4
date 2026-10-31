# Delegating work to sub-agents

Notes from 2026-10-26 on handing a spec'd step to Claude sub-agents. The first trial is 4d-3, the slot machine (`specs/training.md` §7).

## The flow

1. **The spec is written in the main session**, from the decomp, because that is where the context is. The user approves it, as always.
2. **The main session rates the step and picks the model:**
   - **Medium** (logic, tables, hooks; a literal spec): Sonnet 5.5, medium effort.
   - **Complex** (rendering, VRAM / textures, unclear original behaviour, many systems): Opus 5.5, medium effort.
   - A step can be split by kind: e.g. 4d-3's logic, data and station hooks on Sonnet, and its textures and render on Opus.
3. **The main session writes each agent's brief** and the step's acceptance checks (`docs/porting_checklist.md` §6). It then reviews the result against the spec, runs every suite itself and reports to the user. **Agents never commit**; the user says "commit".
4. **Roles stay apart.** The model that implements a step doesn't write its spec, its acceptance checks or its review. This holds for every model, including models other than Claude working in their own worktree.

## What a spec must carry

**Require a C reference for every value. Each constant and timeline in a spec gets a table row: C function, line, value. Anything with no source must be marked "port-only" or "stand-in", or the step isn't done. This makes guessing visible.**

The table format, the meaning of each status and an example are in `docs/porting_checklist.md` §1. The reviewer checks the table row by row against the decomp before code starts, and again against the code at the end.

## What a brief must carry

A sub-agent starts cold: it doesn't see the conversation.
- **The task:** the spec section and the exact list of files it owns, so that parallel agents don't touch the same files.
- **The standing rules:**
  - `external-resources/` is read-only;
  - no commits, no game art in git;
  - the porters use the Python standard library only;
  - game logic reads properties, never id ranges;
  - scenes and composition;
  - match the surrounding code's style;
  - update VERIFY / PROGRESS / the spec's "As built" notes.
- **The checklist:** `docs/porting_checklist.md`, to go through before reporting. Its §4 matters most for fix rounds: when the user reports a bug, re-read the C first, and never add behaviour that isn't in the C.
- **How to test:**
  - every suite, `tests/test_rules.gd` included, plus `tests/exit_scan.tscn` and the step's scans;
  - the Godot 4.7 exe (Steam: `F:\SteamLibrary\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe`), `--headless --path . -s res://tests/test_<name>.gd`;
  - the porters: `python -m unittest discover -s tests -t .`.
- **Visual checks:** no movies (the user's call, 2026-10-26). The agent lists short in-game checks the user can do (how to get there fast, what to look for), and VERIFY.md gets them. Never screenshot the desktop.
- **What to read first:** the classes it builds on.

The more exact the spec (states, constants, C line numbers), the better a cheaper model does.

## Where the agents work

- **For now: a branch in the main worktree** (`feat/<step>`), with the main session not editing meanwhile. The gitignored outputs Godot needs to run are already there:
  - `asset_porter/output/`;
  - `data_porter/output/`;
  - `content/dw1/`;
  - `.godot/`.
- **Parallel agents on one branch** must own disjoint files. A porter re-run rewrites outputs that the others' tests read, so it should touch only its own family.
- **Git worktrees** (`isolation: worktree`) need those gitignored outputs too. To decide later:
  - copy them (large);
  - link them with Windows junctions (`mklink /J <worktree>\asset_porter\output <main>\asset_porter\output`, the same for the others). The catch is that a porter run in one worktree changes them for all.
  - or teach `Content` / `GameData` to read an outside output root (a setting or an environment variable).

## First trial: 4d-3 (2026-10-26)

- Sonnet (logic, data, hooks) and Opus (textures, then the box) in parallel on one branch, with disjoint files and a defined interface (the session's `box`): it worked, and Opus's look at the exported textures caught three spec errors before the render was written.
- **Cost: about 575k tokens** (Sonnet 206k, Opus 370k over two phases), likely more than doing the step in the main session. Each agent starts at ~60k (system prompt, tool definitions, CLAUDE.md) before reading anything.
- Sonnet ran `git stash` by mistake while Opus was editing (popped at once). Briefs must forbid `git stash`, `checkout`, `reset` and other tree-wide git commands.
- Small doc slips (counts, log order) needed a fix in review.

## Second trial: step 6, death and reincarnation (2026-10-27 to 10-30)

- One agent (Gemini Flash 3.8, in the `dw_godot_secondary_develop` worktree) did the whole step: it wrote the spec (`f558e5f`) and then the code, the tests and 7 fix rounds after the user's in-game reports. It had the same documents and the decomp.
- The review found 13 problems (`PLANS.md` step 6, R1–R13), and play found two more (the dialogue starting during the scene, and I-37's black screen). The causes:
  - **No second reader.** The spec paraphrased the C instead of citing it ("a white flash rises": the C darkens the screen). Spec, code, tests and review came from one model, so each slip went through to the end. Fixed by the C-reference table ("What a spec must carry") and by keeping roles apart (flow step 4).
  - **Tests checked its own guesses.** The suite asserted the invented timelines and passed. The end-to-end scans weren't run. Fixed by acceptance checks written outside the implementer (checklist §6).
  - **Symptom fixes.** Each user report got a patch that made the symptom go away (a rebirth hop, a shorter evolution delay, hiding all entities) instead of a new look at `dooa.c`. Fixed by checklist §4.
  - **Rules as prose.** The `specs/scenes.md` / `specs/content.md` rules were read but not applied while writing code (R4, R9, R10, R11). Fixed by `tests/test_rules.gd`, which fails on 15 lines of that branch's code.
- **Model choice:** a Flash-class model fits "medium" steps with a literal, reviewed spec. A step with long C timelines, several interacting systems and visuals is "complex": its spec and review need a strong model, whoever writes the code.

## Ideas to cut the cost

- Delegate only big, separable steps; do small ones in the main session.
- Put the facts the agent needs in the brief (the exact functions, interfaces, file excerpts and line numbers) so it reads less.
- One agent per step rather than two, unless the halves are truly independent.
- Lower effort for mechanical work; a custom agent type (`.claude/agents/*.md`) with a short fixed prompt and fewer tools.

## Open points

- Whether an agent's cold start (re-reading code) costs less on Sonnet than doing the step in the main session.
- Visual bugs (4d-2's showed up only on screen) are now caught by the user's in-game checks, not by movies.
