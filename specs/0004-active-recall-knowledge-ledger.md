# Spec 0004: Active Recall and Cross-Session Knowledge Ledger

**Status:** Implemented
**Target version:** 0.7.0
**Date:** 2026-07-11

## Product Thesis

Everything vibe-learn does today is one-directional: it explains things *to*
the user. Capture, `/learn`, `/digest`, Obsidian notes, the session briefing,
and the NotebookLM pack all deliver understanding — but none of them verify
it. A user can read every digest and still be unable to debug their own app.
Summaries feel like learning; they are not proof of it.

This release closes the loop:

1. **Active recall** — a quiz surface that asks the user to explain what was
   built in their own words, graded against the session log.
2. **Knowledge ledger** — a small cross-session record of which concepts the
   user has encountered, been quizzed on, and still finds shaky.

Together they turn vibe-learn from a session summarizer into a
spaced-repetition tutor for the user's own codebase.

The core promise extends:

> Agent writes the system. Docs describe the system. vibe-learn teaches you to
> own the system — **and checks that you actually do.**

## Goals

1. Add a `/quiz` learning command (Claude Code, Codex, OpenCode) that
   generates recall questions grounded in the session log, evaluates the
   user's free-text answers, and records the results.
2. Add `.vibe-learn/knowledge.json` — an assistant-maintained, cross-session
   concept ledger with per-concept recall status.
3. Feed the ledger back into existing surfaces: `/learn` opens with shaky
   concepts touched again this session; `/digest`'s "Things to Study" becomes
   cumulative instead of resetting every session.
4. Keep the ledger mechanical to update: a `scripts/knowledge.sh` helper
   (bash + jq) so command prompts never hand-edit JSON.
5. Preserve all existing hook, command, Obsidian, and briefing behavior.

## Non-Goals

- Do not write to the ledger from any hook. `observe.sh`, `bootstrap.sh`,
  `capture-prompt.sh`, and `pause-summary.sh` are unchanged; the ledger is
  updated only when the user runs a learning command.
- Do not add a scheduler, daemon, or notification system for review
  reminders. "Due for review" is computed on demand when a command runs.
- Do not add external API calls. Question generation and answer grading use
  the assistant's own context window, exactly like `/learn` and `/digest`.
- Do not score or grade the user numerically in stored data beyond a simple
  recall status. This is a tutor, not a report card.
- Do not change the `.vibe-learn/session-log.jsonl` schema.
- Do not require the ledger to exist — every consumer treats a missing
  `knowledge.json` as an empty ledger.

## Feature Design

### `/quiz` Command

New markdown command installed alongside `/learn` and `/digest` for all three
adapters. Codex users invoke it via the skill ("Use vibe-learn to quiz me on
this session") with `.codex/prompts/quiz.md` as the prompt-file fallback.

| Invocation | Behavior |
|------------|----------|
| `/quiz` | 3–5 questions drawn from this session's log |
| `/quiz <topic>` | Questions focused on a topic (from this session or the ledger) |
| `/quiz review` | Questions drawn from ledger concepts marked `shaky` or unreviewed for 14+ days |

Command flow (plain-language instructions the assistant follows, same style as
`learn.md`):

1. Read `.vibe-learn/session-log.jsonl` and, when present,
   `.vibe-learn/knowledge.json`.
2. Select 3–5 quizzable moments — decisions, patterns, dependencies, failures
   that were fixed. Prefer "why" and "what would break" questions over trivia:
   - "Why did we install bcrypt instead of hashing manually?"
   - "The Stop hook writes JSON to stdout — what consumes it, and what happens
     if the JSON is malformed?"
   - "If you needed to add a fourth adapter tomorrow, which files would you
     touch?"
3. Ask **one question at a time**. Wait for the user's answer before
   revealing anything.
4. Evaluate each answer against the session log and touched files. Respond
   with: what the user got right, what they missed, and a 1–2 sentence
   correct explanation. Never scold; the tone is a colleague checking
   understanding, not an exam.
5. After the last question, record results via `scripts/knowledge.sh` (see
   below): one `record` call per concept quizzed, with recall status
   `solid` or `shaky` based on the answer.
6. Close with a short recap: concepts confirmed solid, concepts to revisit,
   and (if any) a pointer to `/learn <topic>` for the shakiest one.

### Knowledge Ledger

**File:** `.vibe-learn/knowledge.json` (project-level only — concepts are
per-codebase, so there is no global fallback).

**Schema:**

```json
{
  "version": 1,
  "concepts": [
    {
      "name": "jwt-refresh-tokens",
      "label": "JWT refresh token rotation",
      "first_seen": "2026-06-20",
      "last_seen": "2026-07-11",
      "sessions": 3,
      "last_quizzed": "2026-07-11",
      "status": "shaky",
      "notes": "Confused access-token vs refresh-token expiry"
    }
  ]
}
```

| Field | Type | Purpose |
|-------|------|---------|
| `name` | string | Stable kebab-case key, used for merging |
| `label` | string | Human-readable concept name |
| `first_seen` | date | First session that touched this concept |
| `last_seen` | date | Most recent session that touched it |
| `sessions` | int | Count of sessions that touched it |
| `last_quizzed` | date or null | Most recent quiz covering it |
| `status` | string | `new` (never quizzed), `shaky`, or `solid` |
| `notes` | string | One line on what specifically was shaky (optional) |

Status transitions are simple and forgiving: a correct quiz answer sets
`solid`, an incomplete one sets `shaky`, and touching a concept in a new
session never downgrades status (only quizzing does).

### `scripts/knowledge.sh` Helper

Command prompts must not hand-edit JSON, so all writes go through a helper
the assistant invokes via its shell tool:

```text
knowledge.sh record <name> --label=<text> --status=<new|shaky|solid> [--notes=<text>]
knowledge.sh touch <name> --label=<text>          # bump last_seen/sessions, create if missing
knowledge.sh list [--status=<s>]                  # print ledger as JSON to stdout
knowledge.sh due [--days=14]                      # concepts shaky or unquizzed for N+ days
```

Requirements:

- Bash + jq only, consistent with the rest of the core.
- Merge by `name`: `record`/`touch` update the existing entry or append a new
  one. Never duplicate, never drop other entries.
- Atomic writes: build the new document in a temp file, then `mv` into place.
- Missing file means empty ledger — `list`/`due` print `{"version":1,"concepts":[]}`
  and exit 0; `record`/`touch` create the file.
- Dates come from `date +%Y-%m-%d` at invocation time; the helper is never
  called from hooks, so there is no hot-path latency budget — but keep it
  lightweight anyway.

### Feedback into Existing Surfaces

`/learn` (all adapters):

- Before answering, check `knowledge.sh due`. If a due concept was also
  touched in this session's log, open with one line, e.g. *"Heads up: this
  session touched JWT refresh tokens again — you marked that shaky on
  July 11. Want a quick recap first?"* At most one such line; never block the
  actual answer.

`/digest` (all adapters):

- "Things to Study" merges this session's new topics with unresolved ledger
  items (`shaky`, plus `new` concepts seen in 2+ sessions), oldest first.
- After generating the digest, `touch` each concept the session introduced so
  the ledger accumulates even for users who never run `/quiz`.

Obsidian (`/learn obsidian`, `/digest obsidian`):

- Notes written to the vault gain one frontmatter field, `recall_status`,
  summarizing quizzed concepts when quiz results exist for the session.
  No other note-format changes.

### Learning Ladder (updated)

1. Pause summary: quick recap after a response.
2. `/learn`: focused explanation.
3. `/digest`: full session learning report.
4. **`/quiz`: verification that the explanation stuck.**
5. Briefing / NotebookLM pack: operational comprehension artifacts.
6. **Knowledge ledger: memory that makes all of the above cumulative.**

## Change Manifest

### New Files

| File | Purpose |
|------|---------|
| `specs/0004-active-recall-knowledge-ledger.md` | This spec |
| `scripts/knowledge.sh` | Ledger read/write helper (record, touch, list, due) |
| `adapters/claude-code/commands/quiz.md` | `/quiz` for Claude Code |
| `adapters/codex/prompts/quiz.md` | Codex prompt-file fallback |
| `adapters/opencode/commands/quiz.md` | `/quiz` for OpenCode |
| `config/knowledge-defaults.json` | Reference template (review window, question count) |
| `tests/knowledge.bats` | Helper script tests |
| `tests/quiz.bats` | Command install + prompt content tests |

### Modified Files

| File | What Changes |
|------|-------------|
| `adapters/claude-code/commands/learn.md` | Add due-concept opener; keep all existing modes |
| `adapters/claude-code/commands/digest.md` | Cumulative "Things to Study"; `touch` new concepts |
| `adapters/codex/prompts/learn.md` / `digest.md` | Same changes as Claude Code |
| `adapters/codex/skills/vibe-learn/SKILL.md` | Add quiz and review usage examples |
| `adapters/opencode/commands/learn.md` / `digest.md` | Same changes as Claude Code |
| `adapters/*/install.sh` | Install the new quiz command/prompt file |
| `scripts/setup.sh` | Add new files to the `FILES` array |
| `scripts/install.sh` | Mention `/quiz` in final output |
| `techpack.yaml` | Add knowledge ledger component entry |

### Deleted Files

None.

## Documentation Updates Checklist

- [ ] **`CLAUDE.md`** — Add `/quiz` to Learning Interfaces; document
      `knowledge.json` schema and `knowledge.sh`; note the no-hook-writes
      constraint under Architecture Constraints
- [ ] **`README.md`** — Add "Check Your Understanding" section; update roadmap
- [ ] **`GETTING_STARTED.md`** — Add `/quiz` walkthrough after `/digest`
- [ ] **`templates/instructions.md`** — Add `/quiz` to the commands list
- [ ] **`AGENTS.md`** — Review for needed updates
- [ ] **`CHANGELOG.md`** — Verify release-please entry mentions active recall

## Backward Compatibility Checklist

- Existing `.vibe-learn/session-log.jsonl` files remain readable; schema
  unchanged.
- All hooks unchanged — `bats tests/observe.bats` and friends stay green with
  no timing regression.
- `/learn` and `/digest` behave identically when `knowledge.json` is absent
  (empty-ledger semantics), including all Obsidian modes.
- Existing Obsidian notes without `recall_status` frontmatter remain valid.
- `vibe-learn install` and `scripts/setup.sh` for every `--assistant` value
  keep working; installs remain idempotent.
- Projects that never run `/quiz` see exactly one behavioral change: `/digest`
  begins accumulating "Things to Study" across sessions.

## Test Plan

Add or update Bats tests for:

- `knowledge.sh`:
  - `record` creates the file with a valid document
  - `record` merges by name (no duplicates, other entries preserved)
  - `touch` bumps `last_seen`/`sessions` and creates missing entries
  - `list` and `due` on a missing file print an empty ledger and exit 0
  - `due` respects `--days` and status filtering
  - malformed existing JSON produces a clear error, not silent data loss
  - writes are atomic (temp file + `mv`)
- Install:
  - each adapter installs its quiz command/prompt file (project and global)
  - `setup.sh` copies `knowledge.sh` and `knowledge-defaults.json`
  - idempotency
- Prompt content (grep-level, consistent with existing obsidian.bats style):
  - quiz commands reference the session log and `knowledge.sh`
  - learn/digest commands reference the due-concept and cumulative behavior
- Existing regression: full `bats tests/` stays green.

## Rollout Phases

### Phase 1: Spec Only

- Add this spec. No runtime changes.

### Phase 2: Ledger Foundation

- Add `scripts/knowledge.sh` with tests.
- Add `config/knowledge-defaults.json`.
- Wire into `setup.sh` file list.

### Phase 3: Quiz Command

- Add quiz command/prompt files for all three adapters.
- Update adapter installers and Codex skill.
- Add install tests.

### Phase 4: Feedback Loop

- Update `/learn` and `/digest` prompts (all adapters) for due-concept opener
  and cumulative study list.
- Add Obsidian `recall_status` frontmatter.

### Phase 5: Docs and Compatibility Sweep

- Update README, CLAUDE.md, GETTING_STARTED, templates.
- Run full regression and manual smoke checks.

## Verification

1. `bats tests/` — all tests pass, including new knowledge and quiz suites.
2. In a session with activity, `/quiz` asks one question at a time, grades
   answers against the log, and writes results to `knowledge.json`.
3. `/quiz review` with a seeded ledger selects shaky/stale concepts.
4. `/learn` in a session touching a shaky concept opens with the one-line
   heads-up; `/learn` with no ledger behaves exactly as v0.6.0.
5. `/digest` merges unresolved ledger items into "Things to Study" and
   touches new concepts.
6. `jq . .vibe-learn/knowledge.json` parses after repeated record/touch calls
   with no duplicate names.
7. Manual smoke on Codex ("Use vibe-learn to quiz me") and OpenCode `/quiz`.

## Open Questions

- Should `/quiz review` limit itself to concepts relevant to files that still
  exist in the repo, or quiz on anything in the ledger? (Lean: anything —
  deleted code still teaches.)
- Should quiz question count be configurable in `knowledge-defaults.json` or
  fixed at 3–5? (Lean: configurable ceiling, default 5.)
- Should the ledger eventually sync to Obsidian as a "Knowledge Map" note?
  Deferred — see Out of Scope.

## Out of Scope

Future extensions, not part of v0.7.0:

- Review-reminder scheduling or any daemon/notification mechanism.
- A rendered "knowledge map" section in the session briefing HTML.
- Obsidian knowledge-map note generation from the ledger.
- Multi-project or global knowledge aggregation.
- Difficulty levels or beginner/senior question calibration (candidate for
  the existing "learning levels" roadmap item).
