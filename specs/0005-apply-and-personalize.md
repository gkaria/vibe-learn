# Spec 0005: Apply and Personalize — Code Tours, Challenges, and a Ledger-Aware Briefing

**Status:** Proposed
**Target version:** 0.8.0
**Date:** 2026-07-12

## Product Thesis

v0.7.0 completed the ladder from *explain* (`/learn`, `/digest`) to *verify*
(`/quiz`, the knowledge ledger). Two rungs are still missing:

1. **Apply.** Recall proves you remember; it doesn't prove you can act.
   Explaining a file back, finding a planted bug, predicting what a command
   prints — doing is a level above remembering, and nothing in vibe-learn
   asks you to do anything yet.
2. **Personalize.** The knowledge ledger knows what you're shaky on, but only
   `/quiz` and `/learn` consume it. The briefing's study queue and the
   NotebookLM audio pack are still generic — the same output for a user who
   aced every quiz and one who failed them all.

This release adds both: `/explain` for guided code tours, `/challenge` for
ledger-targeted exercises, and a briefing/NotebookLM pack that reads the
ledger — turning `knowledge.json` from quiz storage into the shared
personalization layer for every surface.

The learning ladder becomes: observe → explain → verify → **apply** — with
memory underneath all of it.

## Goals

1. Add an `/explain [file|topic]` learning command (Claude Code, Codex,
   OpenCode) that gives a guided tour of a touched file or subsystem, ends
   with an offer to quiz, and `touch`es the concepts it covered.
2. Add a `/challenge [topic|review]` learning command that generates a small,
   self-contained exercise under `.vibe-learn/challenges/`, derived from the
   session's actual code and targeted at shaky ledger concepts.
3. Make `scripts/briefing.sh` ledger-aware: prioritized study-queue entries,
   a "Your knowledge state" section in the NotebookLM source pack, and an
   audio framing prompt that calls out shaky concepts.
4. Keep every constraint that holds today: no hook-time work, no external
   calls, no build step, bash + jq only in core scripts.
5. Preserve all existing v0.7.x behavior, including ledger semantics.

## Non-Goals

- Do not build interactive sandboxes, web-based playgrounds, or anything
  requiring a server or build step. Challenges are plain files plus
  plain-language checking instructions.
- Do not let challenges touch the user's real working tree. Everything lives
  under `.vibe-learn/challenges/` (already gitignored via `.vibe-learn/`).
- Do not have hooks read or write the ledger or generate challenges.
  `observe.sh` and friends are unchanged.
- Do not auto-run `/explain` or `/challenge` — all learning commands remain
  user-invoked.
- Do not change the `knowledge.json` schema or `knowledge.sh` interface.
- Do not add difficulty levels or beginner/senior calibration in this
  release (still a roadmap item).

## Feature Design

### `/explain` — Guided Code Tours

New markdown command for all three adapters (same distribution pattern as
`/quiz`: Claude Code command, Codex prompt fallback + skill section, OpenCode
command).

| Invocation | Behavior |
|------------|----------|
| `/explain` | Tour the most significant file or subsystem this session touched |
| `/explain <file>` | Tour that file |
| `/explain <topic>` | Tour the files behind a concept (e.g. `auth flow`) |

Tour structure (plain-language instructions the assistant follows):

1. Read the session log to find what was touched and why (user prompts give
   intent); read the target file(s) and their immediate callers/callees.
2. Walk the code top-down as a colleague would at a whiteboard:
   - **Entry point** — where execution starts, what triggers it
   - **The spine** — the 3–5 load-bearing pieces, in order, each with *why
     it's there*, not just what it does
   - **The edges** — error paths, ordering constraints, and anything that
     would break if rearranged
   - **Connections** — what calls this, what this calls, where a change here
     would ripple
3. Keep it grounded: quote real lines with `file:line` references, never
   invent structure the file doesn't have.
4. Close with: `touch` each concept covered (via the knowledge helper, same
   lookup order as `/quiz`), then offer — "Want me to quiz you on this, or
   generate a challenge?"

### `/challenge` — Ledger-Targeted Exercises

New markdown command, same three-adapter distribution.

| Invocation | Behavior |
|------------|----------|
| `/challenge` | Exercise derived from this session's most quiz-worthy change |
| `/challenge <topic>` | Exercise on that topic |
| `/challenge review` | Exercise targeting the shakiest due ledger concept |

Two exercise forms, chosen by what the material supports:

**Find-and-fix.** The assistant copies a small excerpt of real project code
(one file or less) into `.vibe-learn/challenges/<date>-<slug>/`, plants one
deliberate defect of a class the ledger says the user is shaky on (e.g. a
middleware-ordering mistake for a user shaky on `express-middleware-ordering`),
and writes a `README.md` in the challenge directory stating the scenario and
the symptom — but not the location or the fix. The user edits the challenge
copy; the assistant checks the fix by reading it and explains what the defect
was exploiting.

**Predict-then-run.** For command/behavior concepts: the assistant shows a
small command or snippet grounded in the project and asks the user to predict
the outcome *before* running or revealing it. Grading compares prediction to
actual behavior.

Rules (spelled out in the command files):

- Challenge copies are clearly headed with a comment: this is a modified
  training copy, not project source.
- Never modify files outside `.vibe-learn/challenges/`.
- One defect per challenge; keep excerpts under ~100 lines.
- On completion, `record` the concept (`solid` if the user found and fixed
  it cleanly, `shaky` otherwise, with `--notes`) — the same once-per-concept
  semantics as `/quiz`.
- Old challenge directories are the user's to delete; the command offers to
  clean up directories older than 30 days but never deletes silently.

### Ledger-Aware Briefing and NotebookLM Pack

`scripts/briefing.sh` gains one new optional input: `.vibe-learn/knowledge.json`,
read with the same defensive pattern as its other inputs (missing or invalid
file → feature silently absent, never a crash).

Three deterministic additions — no AI at render time, consistent with the
rest of the briefing:

1. **Prioritized study queue.** For each ledger concept with status `shaky`
   (or `new` with `sessions >= 2`), prepend a study-queue item:
   `"<label>" is marked <status> (last quizzed <date>) — review it before
   extending this code.` Shaky items render with the existing `priority`
   styling. Cap at 5 ledger-derived items; existing heuristic items follow.
2. **"Your knowledge state" section in the NotebookLM pack.** After the
   existing sections, a table of up to 10 concepts (label, status,
   last quizzed, sessions), split into "solid" and "needs attention".
3. **Adaptive audio framing.** When any shaky concepts exist, the suggested
   audio prompt gains one sentence: `Spend extra time on the concepts listed
   under "Your knowledge state — needs attention"; the listener has struggled
   with these before.`

The briefing HTML gets a matching "Knowledge state" card in the session page
(same visual language: thin borders, status chips, no new assets).

### Codex Skill and Docs Surface

- `SKILL.md` gains Explain Mode and Challenge Mode sections mirroring the
  command files, with the natural-language invocations:
  - `Use vibe-learn to explain the auth middleware.`
  - `Use vibe-learn to give me a challenge on what's shaky.`
- `templates/instructions.md`, README, GETTING_STARTED, and CLAUDE.md list
  the new commands (same placement pattern as `/quiz` in 0.7.0).

## Change Manifest

### New Files

| File | Purpose |
|------|---------|
| `specs/0005-apply-and-personalize.md` | This spec |
| `adapters/claude-code/commands/explain.md` | `/explain` for Claude Code |
| `adapters/claude-code/commands/challenge.md` | `/challenge` for Claude Code |
| `adapters/codex/prompts/explain.md` | Codex prompt-file fallback |
| `adapters/codex/prompts/challenge.md` | Codex prompt-file fallback |
| `adapters/opencode/commands/explain.md` | `/explain` for OpenCode |
| `adapters/opencode/commands/challenge.md` | `/challenge` for OpenCode |
| `tests/explain.bats` | Command content + install tests |
| `tests/challenge.bats` | Command content + install tests |
| `tests/briefing-knowledge.bats` | Ledger-aware briefing tests |

### Modified Files

| File | What Changes |
|------|-------------|
| `scripts/briefing.sh` | Read `knowledge.json`; prioritized study queue, knowledge-state card, pack section, adaptive audio prompt |
| `adapters/*/install.sh` | Install the two new command/prompt files |
| `scripts/setup.sh` | Add new files to the `FILES` array |
| `scripts/install.sh` | Mention `/explain` and `/challenge` in final output |
| `adapters/codex/skills/vibe-learn/SKILL.md` | Explain Mode + Challenge Mode sections |
| `techpack.yaml` | `cmd-explain` and `cmd-challenge` components |
| `templates/instructions.md` | List new commands and `.vibe-learn/challenges/` |
| `.claude/commands/` | Dogfood copies kept in sync (tested) |

### Deleted Files

None.

## Documentation Updates Checklist

- [ ] **`CLAUDE.md`** — Add `/explain` and `/challenge` to Learning
      Interfaces; document `.vibe-learn/challenges/` and the
      never-touch-project-source rule under Architecture Constraints;
      update the briefing section for ledger awareness
- [ ] **`README.md`** — Extend "What it looks like" with a short `/explain`
      excerpt; add a "Practice on your own code" section for `/challenge`
- [ ] **`GETTING_STARTED.md`** — Add explain/challenge steps after the quiz
      walkthrough; renumber
- [ ] **`templates/instructions.md`** — New commands + session-data entry
- [ ] **`AGENTS.md`** — Review for needed updates
- [ ] **`CHANGELOG.md`** — Narrative 0.8.0 section (the release workflow now
      syncs release notes from it)

## Backward Compatibility Checklist

- `briefing.sh` output is byte-identical to v0.7.x when `knowledge.json` is
  absent; malformed ledger JSON degrades to the no-ledger rendering with a
  stderr warning, never a crash.
- `/quiz`, `/learn`, `/digest`, Obsidian flows, and `knowledge.sh` semantics
  unchanged.
- Hooks unchanged; no new work on any hook path.
- All installs (`setup.sh`, `install.sh`, every `--assistant` value,
  techpack) remain idempotent; existing Bats suite stays green.
- Challenge generation writes only under `.vibe-learn/challenges/`; nothing
  new is ever committed to the user's repo.

## Test Plan

- **Briefing (bash-testable, the bulk of automated coverage):**
  - no ledger → no knowledge-state section, output matches v0.7.x fixtures
  - ledger with shaky concepts → prioritized study-queue items, capped at 5
  - knowledge-state section present in pack with correct solid/needs-attention
    split
  - adaptive sentence present in audio prompt iff shaky concepts exist
  - malformed ledger → warning on stderr, page still renders
- **Commands (grep-level content tests, matching quiz.bats style):**
  - explain/challenge files exist per adapter, reference the session log,
    the knowledge helper lookup order, and the challenges directory rule
  - challenge files state the never-touch-project-source rule
  - dogfood `.claude/commands/` copies match adapter copies
- **Install:** each adapter installs both files (project + global);
  `setup.sh` copies them; techpack lists them; idempotency.
- **Full regression:** `bats tests/` green.

## Rollout Phases

### Phase 1: Spec Only

- Add this spec. No runtime changes.

### Phase 2: Ledger-Aware Briefing

- `briefing.sh` + fixtures + tests. Pure bash/jq, independently shippable.

### Phase 3: `/explain`

- Command files for all adapters, installer wiring, skill section, tests.

### Phase 4: `/challenge`

- Command files, challenge-directory conventions, ledger recording, tests.

### Phase 5: Docs and Compatibility Sweep

- README, CLAUDE.md, GETTING_STARTED, templates, techpack.
- Full regression and manual smoke on all three assistants.

## Verification

1. `bats tests/` — green, including new suites.
2. Seed a ledger with shaky concepts, run `vibe-learn briefing`: study queue
   leads with ledger items, pack contains the knowledge-state table, audio
   prompt contains the adaptive sentence. Remove the ledger, regenerate:
   output matches v0.7.x.
3. `/explain` on a session-touched file produces a grounded tour with real
   `file:line` references, touches concepts, and offers quiz/challenge.
4. `/challenge review` with a shaky ledger concept creates a challenge
   directory with a planted defect and README; fixing it records `solid`.
5. Confirm nothing outside `.vibe-learn/` changed after a full
   explain → challenge → briefing cycle (`git status` clean).
6. Manual smoke via the Codex skill and OpenCode commands.

## Open Questions

- Should `/explain` tours be savable to Obsidian (`/explain obsidian <file>`)
  like learn/digest? (Lean: yes, but as a fast-follow — keep 0.8.0 scoped.)
- Should challenge results use a distinct ledger marker (e.g. a
  `last_challenged` note) or reuse `record` semantics as specced? (Lean:
  reuse — one recall model until proven insufficient.)
- Cap for ledger-derived study-queue items: 5 feels right, but should it be
  configurable in `knowledge-defaults.json`?

## Out of Scope

Future extensions, not part of v0.8.0:

- Interactive/browser-based challenge environments
- Multi-file or multi-defect challenges
- Obsidian export of tours and challenge results
- A rendered "knowledge map" visualization in the briefing
- Difficulty calibration (beginner/intermediate/senior)
- Cross-project knowledge aggregation
