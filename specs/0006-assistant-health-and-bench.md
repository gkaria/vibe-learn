# Spec 0006: Assistant Health and Bench — Is My Assistant Having a Bad Week?

**Status:** In progress — Phases 2 (identity and history) and 3 (health surfaces) implemented
**Target version:** 0.10.0
**Date:** 2026-09-25
**Mockup:** [`docs/mockups/assistant-health.html`](../docs/mockups/assistant-health.html)

## Product Thesis

Models and harnesses change under you. A harness update ships on a Tuesday, a
provider swaps a model snapshot, a default setting changes — and the only
evidence is a vague sense that the assistant "feels worse this week." Users
have no way to tell a real regression from a run of harder tasks.

vibe-learn already watches every session. That puts it in a unique position to
answer the question with the user's own work instead of a public leaderboard:

1. **Assistant health (passive).** Derive per-session signals — failed
   commands, rework, tool events per prompt, turns to green — from the
   session log that already exists, tag each session with model and harness
   version, and show when those signals move after a change. Free, no new API
   calls, no hook-time cost beyond one row per session. A hint, never proof.
2. **Bench (active, opt-in).** Capture small tasks from the user's own
   sessions — a prompt, a clean starting commit, and a check command that went
   green — and replay them through a harness's headless CLI in a throwaway
   git worktree. A controlled signal, but it spends tokens, so it is
   user-invoked, confirmed, and never on a hook path.

This fits the core principle: you cannot outsource understanding, and part of
understanding your work is knowing how far to trust the tool that did it
today. Health gives the hunch; bench confirms it; `/learn` explains what the
assistant did differently on a failed run.

## Audience

The person using vibe-learn, in three roles:

1. **Checking their own tools** — "is my assistant worse than last week?"
2. **Comparing harnesses** — "is Codex or Claude Code better on my kind of
   work?" This needs data pooled across projects, because people often use
   different harnesses in different repos.
3. **Sharing with their team** — a report a teammate can read without
   vibe-learn installed, with project names optionally redacted.

## Goals

1. Record `model`, `effort`, `harness`, `harness_version`, `git_head`, and
   `git_dirty` in `session-meta.json` at session start, from verified host
   payload fields, and record the model and effort of every turn so a
   mid-session switch is tracked.
2. Compute one health row per session (`scripts/health.sh`) and append it to
   `.vibe-learn/health.jsonl` when `bootstrap.sh` rotates the log, so history
   survives beyond the two sessions the log keeps today.
3. Add `vibe-learn health` (terminal) and a health page plus session-briefing
   card (HTML) that compare a recent window against a pre-change baseline,
   grouped by harness or model, with change markers and a control group.
4. Add `vibe-learn bench capture | add | run | report` for replaying captured
   tasks through Claude Code, Codex, and Grok Build first, then Cursor and
   OpenCode.
5. Make every report shareable: `--save` writes a standalone markdown file,
   `--redact` replaces project names, and the HTML pages are self-contained.
6. Keep every existing constraint: `observe.sh` untouched, bash + jq + git
   only, no network in hooks, hooks never write the knowledge ledger.

## Non-Goals

- A public benchmark suite or leaderboard. The `results.jsonl` format is
  designed so a sibling project could consume it; this repo does not ship one.
- Statistical claims. Health is labeled as hints; bench shows pass counts
  (`2/3`), not percentages or confidence intervals.
- Building a sandbox for bench runs. A run executes an agent with
  auto-approved tools inside a temp worktree. Runners use the harness's own
  sandbox where one exists (Codex `-s workspace-write`); otherwise the
  worktree isolates files but not the network or the machine. This is stated
  in the confirmation prompt and README.
- Scheduled benches (cron, launchd, Cursor Automations). `--yes` makes this
  possible; wiring it up is left to the user.
- Grading with an LLM. Bench grading is the task's own check command exit code.
- Any change to `observe.sh`, the existing session-log events, the knowledge
  ledger, or existing learning commands (apart from the `/learn` bench-run
  pointer in Phase 5). The log gains one new, additive event type
  (`turn_end`); every existing reader filters by event type and ignores it.

## Feature Design

### Identity capture (session start)

`bootstrap.sh` adds five fields to `session-meta.json`:

```json
{
  "session_id": "abc123",
  "started_at": "2026-09-25T09:12:00Z",
  "harness": "claude-code",
  "harness_version": "2.5.0",
  "model": "claude-opus-5.5",
  "effort": "high",
  "transcript_path": "/Users/.../abc123.jsonl",
  "git_head": "3f2c1ab",
  "git_dirty": false,
  "event_count": 0,
  "current_turn": 0,
  "config": { "log_dir": ".vibe-learn" }
}
```

Sources, checked 2026-09-25. "Documented" means the host's official docs or
published types; "observed" means seen in local files written by the tool
(Claude Code 2.1.222, Codex CLI 0.153.0, Grok Build 1.0.13, OpenCode 1.18.5)
but not documented, so it may change without notice:

| Host | `model` | `effort` | `harness_version` |
|------|---------|----------|-------------------|
| Claude Code | SessionStart `model` (documented; optional, missing after `/clear` or recovery). Fallback: last assistant line's `message.model` in the transcript (observed) | `effort.level` on Stop and tool events, when the model supports it (documented) | Transcript lines carry `version`, e.g. `"2.1.222"` (observed) |
| Codex | `model` on every hook, a Codex extension (documented) | Transcript `turn_context` lines carry `payload.model` and `payload.effort` per turn, e.g. `"low"` (observed). The hook payload has no effort field | Transcript first line `session_meta.payload.cli_version` (observed) |
| Cursor | `model_id` if present, else `model`, on every hook (documented) | `model_params` entry for thinking/effort, when present (documented) | `cursor_version` on every hook (documented) |
| OpenCode | Plugin hook `chat.message` input `model: {providerID, modelID}`, recorded as `providerID/modelID` (documented in `@opencode-ai/plugin` types) | Same hook's `variant`, which OpenCode defines as "provider-specific reasoning effort, e.g. high, max, minimal" (documented) | `session.created` event's `info.version`, the OpenCode version that created the session (documented `Session` type; e.g. `"1.16.2"` in the local database), so no subprocess is needed |
| Grok Build | Not in the hook envelope; the common fields are `hookEventName`, `sessionId`, `cwd`, `workspaceRoot`, `timestamp`, `permissionMode`, `promptId` (documented). Read `current_model_id` from `$GROK_HOME/sessions/<url-encoded workspaceRoot>/<sessionId>/summary.json` (observed) | `reasoning_effort` in the same `summary.json` (observed) | `grok --version`, a native binary that answers in about 40 ms, e.g. `grok 1.0.13 (5e9a585) [stable]` (documented CLI) |

Effort is recorded because it changes results as much as a model swap: a
session on low effort would otherwise look like a regression.

Observed sources are read defensively: a missing file or field gives `null`,
never an error, and each one is pinned by a fixture test so a format change
shows up as a failing test rather than silently wrong data. Harness
resolution order, first match wins:

1. `VIBE_LEARN_HARNESS` environment variable (explicit override).
2. `harness` field in the payload — set by the Cursor shim and the OpenCode
   plugin, which already translate payloads.
3. `GROK_HOOK_EVENT` set → `grok`.
4. `transcript_path` under `~/.codex/` → `codex`; under `~/.claude/` →
   `claude-code`.
5. Otherwise `unknown`.

`harness_version` for Claude Code and Codex is read from the transcript at
rotation time (below), not at session start, because the transcript may be
empty when `SessionStart` fires. The read is `head -n 1` or `tail -n 50` plus
one `jq` call. Grok's `grok --version` runs at session start; OpenCode's
version comes from the plugin.

`git_head` / `git_dirty` come from `git rev-parse --short HEAD` and
`git status --porcelain` in `cwd`; both are `null` outside a git repo.

### Per-turn configuration (mid-session switches)

Users switch models mid-session (`/model` in Claude Code, the model picker in
Cursor). Claude Code's `UserPromptSubmit` payload carries no model, but every
host exposes the model that *answered* by the end of the turn, so the Stop
hook records it. `pause-summary.sh` appends one line per turn:

```json
{"timestamp":"...","event":"turn_end","turn":7,"model":"claude-opus-5.5","effort":"high"}
```

Sources:

- **Claude Code** — `message.model` of the last assistant line in
  `tail -n 20` of the transcript, and `effort.level` from the Stop payload.
- **Codex** — `payload.model` and `payload.effort` of the last
  `turn_context` line in `tail -n 50` of the transcript, falling back to the
  Stop payload's `model`.
- **Cursor** — the shim forwards `model_id`/`model` and `model_params` on
  `stop`.
- **OpenCode** — the plugin remembers the last `chat.message` model and
  `variant` and passes them to `pause-summary.sh` on `session.idle`.
- **Grok Build** — `current_model_id` and `reasoning_effort` from the
  session's `summary.json`, read at Stop. Grok's extra end-of-session Stop
  (already ignored by `pause-summary.sh`) writes nothing.

Unknown values are `null`.

`health.sh` then splits a session into **segments** wherever the turn's
`(model, effort)` changes, and writes **one row per segment**. Rows from the
same session share `session_id` and carry
`"segment": {"index": 2, "count": 2, "first_turn": 8, "last_turn": 16}`.
A session with no switch is a single segment, so the common case looks the
same as a plain per-session row. Segments below `health.min_events` are kept
but excluded from baselines, like short sessions.

### Health row (`scripts/health.sh`)

A pure function: reads `session-log.jsonl` and `session-meta.json` from a
`.vibe-learn/` directory and prints one JSON line per segment (usually one).
A single `jq -s` pass over the log; no other work.

```json
{
  "version": 1,
  "session_id": "abc123",
  "segment": { "index": 1, "count": 1, "first_turn": 1, "last_turn": 16 },
  "started_at": "2026-09-25T09:12:00Z",
  "ended_at": "2026-09-25T10:40:12Z",
  "harness": "claude-code",
  "harness_version": "2.5.0",
  "model": "claude-opus-5.5",
  "effort": "high",
  "git_head": "3f2c1ab",
  "metrics": {
    "prompts": 16,
    "turns": 16,
    "tool_events": 147,
    "events_per_prompt": 9.2,
    "bash_runs": 17,
    "bash_failures": 4,
    "bash_fail_rate": 0.24,
    "failed_file_ops": 1,
    "files_touched": 11,
    "files_reworked": 3,
    "rework_rate": 0.27,
    "check_runs": 6,
    "check_recoveries": 1,
    "check_unrecovered": 0,
    "turns_to_green": 3
  }
}
```

Metric definitions:

- Turns are numbered by counting `user_prompt` lines in the log, not from the
  stored `turn` fields: those come from `session-meta.json`, and once that
  file is emptied (seen in the wild) every later prompt is stored as turn 1.
  Events before the first prompt belong to turn 1.

- `events_per_prompt` = `tool_events / max(prompts, 1)`.
- `bash_fail_rate` = `bash_failures / bash_runs`; `null` when `bash_runs < 3`.
- `files_reworked` = distinct files edited in 3 or more distinct turns;
  `rework_rate` = `files_reworked / files_touched`, `null` when
  `files_touched < 3`.
- A **check command** matches
  `(^|[ /])(test|pytest|jest|vitest|bats|mocha|rspec|tsc|eslint|ruff|mypy)\b|go test|cargo (test|check|clippy)|npm (run )?(test|lint|build)|pnpm (test|lint|build)|yarn (test|lint|build)|make (test|check)`.
  Checks are keyed by their command string.
- `turns_to_green` = for each check key that failed, the turn gap to its next
  passing run; the row stores the mean, `null` when nothing recovered.
  `check_unrecovered` counts check keys whose last run failed.

Rows with fewer than `health.min_events` tool events (default 5) are written
but excluded from baselines, so a "what does this file do?" session doesn't
distort the numbers.

### Durable history (rotation)

`bootstrap.sh` already moves `session-log.jsonl` to `.prev.jsonl`. Before
that `mv`, and before `session-meta.json` is overwritten, it runs:

```bash
bash "$SCRIPT_DIR/health.sh" "$LOG_DIR" >> "$LOG_DIR/health.jsonl" 2>/dev/null || true
```

`health.jsonl` is append-only, like the session log. Failures are swallowed;
bootstrap's behavior and output are otherwise unchanged. Cost is bounded by
`max_log_size_mb` (10 MB) and stays well inside the 5 s `SessionStart`
timeout.

**Cross-project global log.** By default (`health.global_log: true`) the same
row, plus `"project": "<basename of cwd>"`, is also appended to
`~/.vibe-learn/health.jsonl`. Per-project history alone can't compare
harnesses when each repo uses a different one, and it builds baselines slowly
when work is spread across repos. `vibe-learn health --all` pools the global
log; the per-project view stays the default because pooling mixes different
kinds of work. Rows contain counts and identifiers only — no prompts,
commands, or file paths; the project folder name is the only identifying
detail, and `--redact` removes it from shared reports. Setting
`health.global_log: false` opts out. `setup.sh` prints one line saying the
global log is on and how to turn it off.

The session in progress has no row yet; `vibe-learn health` computes it on the
fly and marks it `current`.

### Baselines and flags

These rules are shared by the terminal report, the health page, and the
session card, so the three can never disagree:

- **Change markers** are placed wherever `harness_version`, `model`, or
  `effort` changes between consecutive rows of the same harness (grouped by
  model: `harness`, `harness_version`, or `effort` of the same model). A
  field going from `null` to a value is not a change. The marker
  label names what changed (for example "claude-code 2.5.0" or "effort
  high → low").
- **Baseline** = the rows of the same harness *before the latest marker*,
  inside the window (all of its rows when there is no marker). Only rows
  with at least `health.min_events` (default 5) tool events count; the
  session in progress never does. It is deliberately not a rolling
  average: a rolling average absorbs a regression and stops flagging it.
- **Flag** when the since-marker mean exceeds the baseline mean by at least
  `health.rate_threshold_pts` (default 10 points) for rates, or
  `health.count_threshold` (default 2) for counts, and both sides have at
  least `health.min_sessions` (default 5) sessions.
- **Control sentence** ("codex stayed flat over the same days") appears only
  when another harness has at least `health.control_min_sessions` (default 3)
  sessions on or after the marker, inside the window, and its mean for the
  lead flagged metric is within the threshold of the flagged harness's
  baseline.
- With fewer than `min_sessions` baseline sessions, surfaces show raw numbers
  and "Building your baseline: N of 5 sessions", never a comparison.

### `vibe-learn health [dir] [--days=14|all] [--by=harness|model] [--all] [--json] [--save] [--redact]`

New `scripts/health-report.sh`, dispatched from `scripts/cli.sh`. It reads
`health.jsonl` plus the live session and prints the "Flagged" block, the
per-group table, and the caveat line, as in the mockup's Terminal tab. The
caveat points at `bench run` only once bench exists (Phase 4). Effort is
left out of labels when every row in the window has the same one. `--json`
prints the computed groups for other tools. A hidden `--views` prints all
four `--by` × `--days` (14, all) combinations in one document; `briefing.sh`
embeds it, so every surface reads one analysis. Read-only.

Sharing: `--save` also writes `.vibe-learn/health-reports/<date>-health.md`
(same pattern as `recap --save`), a standalone file a teammate can read
without vibe-learn. `--redact` replaces project names with `project-1`,
`project-2`, and drops `git_head`. `bench report` accepts the same two flags.
The HTML health and bench pages embed their data and need no server, so they
can be shared as files.

### Briefing surfaces

`scripts/briefing.sh` gains two optional outputs, both absent (and the HTML
byte-identical to 0.9.x) when `health.jsonl` is missing or empty; a malformed
file warns on stderr and is ignored, the same as the knowledge ledger:

1. **`briefing/health.html`** — the mockup's Health trend tab: callout, metric
   / group-by / window controls, inline-SVG per-session chart with baseline
   band and change markers, and the group table. Data is embedded as JSON;
   the only JS is the controls, as in the session page today.
2. **Session card** — an "Assistant health" section and nav entry on the
   session page, after the session brief: four tiles (bash failures, rework,
   events per prompt, turns to green) showing this session's value and the
   usual (the harness baseline from the 14-day view). A delta chip appears
   on a tile only when the trend flags that signal, and carries the trend's
   delta; the value itself turns red only when this session is past the
   threshold on its own. With fewer than `min_sessions` baseline sessions the
   tiles show raw numbers and "Building your baseline: N of 5".

The index sidebar gets one row, "Assistant health: N flagged", linking to the
health page. No sparklines on the index. A stale `health.html` is removed
when `health.jsonl` is gone.

### Bench

All bench state lives under `.vibe-learn/bench/` (already gitignored):

```text
.vibe-learn/bench/
  tasks/<task-id>.json
  results.jsonl
  runs/<run-id>/          session-log.jsonl, session-meta.json, check-output.txt
```

**Task file:**

```json
{
  "version": 1,
  "id": "fix-cart-rounding",
  "prompt": "fix rounding in cart totals",
  "base_commit": "3f2c1ab",
  "setup": "npm ci",
  "check": "npm test -- cart",
  "timeout_s": 600,
  "source": { "session_id": "abc123", "turn": 4, "captured_at": "2026-09-19T15:02:11Z" }
}
```

**`bench capture [--turn=N] [--yes]`** lists turns in the current (or
previous) session where a check command ran and its last run in that turn
passed, showing the prompt, the check, and whether it failed first. The user
picks one, confirms the id / check / timeout, and the task is written.
Capture refuses when `git_dirty` was true at session start, because the
starting point can't be reproduced; the message points at `bench add`.
`base_commit` is the session's `git_head`.

**`bench add`** writes a task from flags (`--id --prompt --base --check
[--setup] [--timeout]`) for hand-written tasks.

**`bench run [--harness=H] [--model=M] [--effort=E] [--runs=3] [--task=ID] [--yes] [--dry-run]`:**

1. Print the plan (tasks × runs, harness, model), a warning that tokens will
   be spent and that the agent runs with auto-approved tools inside a temp
   worktree, and a cost estimate from the last batch for the same harness and
   model ("No cost history yet. Try --runs=1 first." when there is none).
   Ask `[y/N]` unless `--yes`. `--dry-run` prints the plan and exits.
2. For each run: `git worktree add --detach "$TMPDIR/vibe-learn-bench-<run-id>" <base_commit>`,
   run `setup` if set, then the runner, then `check` with `timeout_s`.
   A `trap` always runs `git worktree remove --force` and `git worktree prune`.
   The user's working tree is never touched.
3. If global vibe-learn hooks are installed for that harness they fire inside
   the worktree; `health.sh` on the worktree's `.vibe-learn/` gives the run's
   tool-event metrics. That directory and the check output are copied to
   `runs/<run-id>/` before the worktree is removed.
4. Append one row per run to `results.jsonl` and print a progress line.
5. Finish with the batch summary against the previous batch for the same
   harness and model, and actual spend next to the estimate.

**Runner contract** — `adapters/<harness>/bench-run.sh <worktree> <prompt-file> [--model=M] [--effort=E]`
runs the harness non-interactively in `<worktree>` and prints one JSON line:

```json
{"ok": true, "duration_s": 252, "turns": 14, "tokens": 182000, "cost_usd": 0.61, "harness_version": "2.5.0", "model": "claude-opus-5.5"}
```

Unknown fields are `null`. A non-zero exit means the runner itself failed
(missing CLI, auth error), recorded as `runner_error`, not as a failed check.
The core `scripts/bench.sh` runs the check, never the runner.
`VIBE_LEARN_BENCH_RUNNER=/path/to/stub.sh` overrides the runner so tests
never spend tokens.

Runners. The Codex, OpenCode, and Grok flags were checked against
`--help` and the local docs on 2026-09-25; Claude Code and Cursor flags are
still the intended shape and get checked when those runners are written:

| Harness | Invocation | Model / effort | Spend reported | Own sandbox |
|---------|-----------|----------------|----------------|-------------|
| codex | `codex exec --json -C <worktree> -s workspace-write` | `-m M`, `-c model_reasoning_effort="E"` | Token events in the `--json` stream | Yes: `-s workspace-write` limits writes to the worktree |
| grok | `grok -p <prompt> --output-format json --permission-mode bypassPermissions` | `-m M`, `--effort E` | `total_cost_usd`, `usage`, `num_turns`, `modelUsage` | Grok's sandbox profiles; to be evaluated |
| opencode | `opencode run --format json` | `-m provider/model`, `--variant E` | Per-message `cost` and `tokens` in the JSON events | No |
| claude-code | `claude -p --output-format json` with a non-interactive permission mode, prompt on stdin | `--model M` | `total_cost_usd`, `usage`, `num_turns` | To be checked |
| cursor | `cursor-agent -p --output-format json` with forced tool approval | `--model M` | To be checked | To be checked |

Runners use the harness's own sandbox wherever it has one, so a bench run on
Codex cannot write outside the worktree. `bench run` gains `--effort=E` next
to `--model=M`, so a batch pins both.

**Result row:**

```json
{
  "version": 1,
  "batch_id": "2026-09-25T11:02:00Z-claude-code",
  "run_id": "2026-09-25-fix-cart-rounding-2",
  "task": "fix-cart-rounding",
  "harness": "claude-code",
  "harness_version": "2.5.0",
  "model": "claude-opus-5.5",
  "effort": "high",
  "started_at": "2026-09-25T11:09:40Z",
  "duration_s": 252,
  "passed": false,
  "check_exit": 1,
  "tokens": 182000,
  "cost_usd": 0.61,
  "tool_events": 38,
  "runner_error": null
}
```

**`bench report [--days=30] [--json]`** prints (and `briefing.sh` renders as
`briefing/bench.html` when `results.jsonl` exists) the grid from the mockup:
tasks × harness/model columns (latest batch per column), per-run pass/fail
marks, `passes/runs` counts, and a `!` flag when a task drops by 2 or more
passes — or the batch total by 2 or more — against the previous batch of the
same harness and model. Columns with no previous batch are never flagged.
Clicking a failed run in the HTML shows duration, tool calls, tokens, cost,
the tail of `check-output.txt`, the kept run-log path, and a copyable
`/learn why did bench run <run-id> fail?`.

Run directories older than `bench.keep_run_logs_days` (default 30) are offered
for deletion at the end of `bench run`; nothing is ever deleted silently.

### Configuration

New keys in `config/defaults.json`, which stays a reference template. No
script read that file before this spec, so user settings live in
`~/.vibe-learn/config.json`, overridden key by key by the project's
`.vibe-learn/config.json` (the same global-then-project pattern as
`obsidian.json`). Every key has a default, so existing installs need no
migration:

```json
{
  "health": {
    "enabled": true,
    "min_events": 5,
    "min_sessions": 5,
    "rate_threshold_pts": 10,
    "count_threshold": 2,
    "control_min_sessions": 3,
    "global_log": true
  },
  "bench": {
    "runs": 3,
    "timeout_s": 600,
    "keep_run_logs_days": 30
  }
}
```

`health.enabled: false` stops `bootstrap.sh` from appending rows.

## Change Manifest

### New Files

| File | Purpose |
|------|---------|
| `specs/0006-assistant-health-and-bench.md` | This spec |
| `docs/mockups/assistant-health.html` | Static design mockup (already added; not generated, linked, or tested) |
| `scripts/identity.sh` | Sourced helper: harness, model, effort, version from payloads and host files |
| `scripts/health.sh` | Session log + meta → one health row per segment |
| `scripts/health-report.sh` | `vibe-learn health` |
| `scripts/bench.sh` | `vibe-learn bench capture \| add \| run \| report` |
| `adapters/claude-code/bench-run.sh` | Claude Code headless runner |
| `adapters/codex/bench-run.sh` | Codex headless runner |
| `adapters/cursor/bench-run.sh` | Cursor headless runner (Phase 5) |
| `adapters/grok/bench-run.sh` | Grok Build headless runner |
| `adapters/opencode/bench-run.sh` | OpenCode headless runner (Phase 5) |
| `tests/health.bats` | Metric rows, rotation append, identity per host |
| `tests/health-report.bats` | `vibe-learn health` flags, windows, sharing flags; briefing page, card, and index row |
| `tests/fixtures/health-sample.sh` | The mockup's sample sessions as `health.jsonl` rows, dated relative to today |
| `tests/bench.bats` | Capture, dirty-tree refusal, stub-runner runs, worktree cleanup, report flags |
| `tests/fixtures/bench-stub-runner.sh` | Deterministic runner for tests |

### Modified Files

| File | What Changes |
|------|-------------|
| `scripts/bootstrap.sh` | Identity fields in meta; health row append before rotation |
| `scripts/pause-summary.sh` | Append one `turn_end` line (model, effort) per turn |
| `adapters/cursor/hooks/vibe-learn.sh` | Forward `harness`, `model_id`/`model`, `model_params`, `cursor_version`, `transcript_path` on `sessionStart` and `stop` |
| `adapters/opencode/plugins/vibe-learn.js` | Forward `harness: "opencode"` and `info.version` on `session.created`; add a `chat.message` hook that remembers `providerID/modelID` and `variant`, passed to `pause-summary.sh` on `session.idle` |
| `scripts/cli.sh` | `health` and `bench` subcommands; usage text |
| `scripts/briefing.sh` | Health page, session card, index row, bench page (all optional) |
| `config/defaults.json` | `health` and `bench` blocks |
| `scripts/setup.sh` | New files in the `FILES` array; one line noting the global health log is on and how to opt out |
| `techpack.yaml` | New components |
| `tests/test_helper.bash` | Point `HOME` at a temp dir so no test writes the real `~/.vibe-learn/health.jsonl` |
| `adapters/*/commands/learn.md`, skills, `.claude/commands/learn.md` | One paragraph: a question naming a bench run reads `.vibe-learn/bench/runs/<id>/` (Phase 5) |
| `tests/bootstrap.bats`, `tests/install-cursor.bats`, `tests/cli.bats`, `tests/briefing.bats` | New meta fields, shim forwarding, dispatch, byte-identical no-health output |

### Deleted Files

None.

## Documentation Updates Checklist

- [ ] **`CLAUDE.md`** — session-meta fields; `health.jsonl` and `bench/`
      layout; add to Architecture Constraints: "bench is the only feature that
      spends tokens; it is user-invoked and confirmed, never called from a
      hook", and "`bootstrap.sh` appends one health row per session segment
      at rotation, to the project and global logs"
- [ ] **`README.md`** — "Is my assistant having a bad week?" section with the
      health card screenshot, `vibe-learn health`, and the bench flow,
      including the sandboxing caveat
- [ ] **`GETTING_STARTED.md`** — health after a few sessions; first bench with
      `--runs=1`
- [ ] **`templates/instructions.md`** — new files under `.vibe-learn/`
- [ ] **`AGENTS.md`** — review
- [ ] **`CHANGELOG.md`** — narrative 0.10.0 section

## Backward Compatibility Checklist

- `observe.sh` and `capture-prompt.sh` unchanged. `pause-summary.sh` gains
  one append (the `turn_end` line); its stdout and `pause-summary.txt` are
  unchanged. Existing session-log events are unchanged, and every current
  reader (`briefing.sh`, `recap.sh`, `pause-summary.sh`, the learning
  prompts) filters by event type, so `turn_end` is ignored.
- `session-meta.json` only gains fields; existing readers ignore them.
- `bootstrap.sh` stdout (the `additionalContext` envelope) is unchanged; the
  health append writes only to a file and swallows errors.
- `briefing.sh` output is byte-identical to 0.9.x when `health.jsonl` and
  `bench/results.jsonl` are absent.
- Knowledge ledger and `knowledge.sh` untouched; hooks still never write it.
- Nothing is ever written outside `.vibe-learn/` and
  `~/.vibe-learn/health.jsonl` (the latter skipped when
  `health.global_log` is `false`). Bench worktrees live in
  `$TMPDIR` and are always removed.
- All installers remain idempotent; the full Bats suite stays green.

## Test Plan

- **`health.sh`** — fixture logs produce the expected row; `null` rules for
  small denominators; check-command regex (positive and negative cases);
  `turns_to_green` with recovered, unrecovered, and repeated checks.
- **Rotation** — a second `bootstrap.sh` appends exactly one row for a
  single-model session; an empty or
  missing log appends nothing; a failing `health.sh` doesn't break bootstrap
  or its stdout; `health.enabled: false` appends nothing. The same row lands
  in `$HOME/.vibe-learn/health.jsonl` with `project` set (tests point `HOME`
  at a temp dir); `health.global_log: false` skips it; `--all` pools it and
  `--redact` removes project names and commit hashes.
- **Identity** — payload fixtures for all five hosts populate
  `model`/`effort`/`harness`; Claude and Codex transcript fixtures and a Grok
  `summary.json` fixture (with `GROK_HOME` pointed at a temp dir) populate
  the observed fields; a fake `grok` on `PATH` supplies `--version`; missing
  files or fields become `null`; `VIBE_LEARN_HARNESS` overrides.
- **Mid-session switches** — Stop fixtures append `turn_end` with the right
  model; a log that switches model at turn 8 yields two rows sharing
  `session_id` with correct turn ranges; a log with no `turn_end` lines yields
  one row from `meta.model`; `pause-summary.sh` stdout is unchanged.
- **`vibe-learn health`** — the mockup's sample dataset as a fixture
  reproduces its flags (3 of 4 metrics, control sentence present);
  fewer than 5 sessions prints "Building your baseline".
- **Briefing** — no health file → byte-identical output; with the fixture, the
  health page and card exist and agree on flags; malformed file → warning.
- **Bench** — capture picks the right turn and refuses a dirty session; `run`
  with the stub runner creates and removes a worktree, copies the run
  directory, appends rows, and prints the summary; runner failure is
  recorded as `runner_error`; `--dry-run` creates nothing; report flags a
  seeded regression and never flags a first batch.
- **Full regression** — `bats tests/` green.

## Rollout Phases

1. **Spec and mockup.** This document and `docs/mockups/assistant-health.html`.
2. **Identity and history.** Meta fields, `health.sh`, rotation append,
   tests. No UI. Shipping this early matters: baselines need about five
   sessions per harness before anything can be flagged.
3. **Health surfaces.** `vibe-learn health`, the briefing health page,
   session card, and index row.
4. **Bench core.** `bench.sh` (capture, add, run, report) with Claude Code,
   Codex, and Grok Build runners and the stub runner.
5. **Bench breadth.** Cursor and OpenCode runners, `briefing/bench.html`,
   `/learn` bench-run awareness across adapters.
6. **Docs and compatibility sweep.**

## Verification

1. `bats tests/` — green.
2. Run three sessions each on two harnesses in a scratch repo;
   `.vibe-learn/health.jsonl` and `~/.vibe-learn/health.jsonl` gain one row
   per rotated session (two for a session that switched model) with `model`,
   `harness`, and `harness_version` filled for Claude Code, Codex, and Cursor.
3. Load the mockup's dataset as `health.jsonl`; `vibe-learn health` and
   `vibe-learn briefing` show the same flags as the mockup.
4. `vibe-learn bench capture` on a session where a test went from failing to
   passing writes a task; `bench run --runs=1` completes, leaves
   `git status` and `git worktree list` unchanged, and `bench report` shows it.
5. Delete `.vibe-learn/health.jsonl` and `.vibe-learn/bench/`; the briefing
   matches 0.9.x output.

## Open Questions

- **Observed sources.** Four identity sources are undocumented files: the
  Claude Code and Codex transcripts, and Grok's `summary.json`. They work
  today and are pinned by fixture tests, but a host update could move them.
  Worth asking the Codex and Grok teams to expose model and effort in the
  hook payload, as Cursor does.
- **Frequent effort switching.** Every effort change is a marker, so a user
  who toggles effort often will rarely reach 5 baseline rows. Acceptable for
  now ("Building your baseline" is honest); revisit if it proves common.
- **Permission mode for runners.** Auto-approval is required for unattended
  runs; should `bench run` refuse to start unless the user has run it once
  interactively with `--i-understand-auto-approve`? Lean: the `[y/N]` prompt
  text is enough, with the caveat in the README.
- **Pause summary.** Should the Stop-hook summary mention a health flag? Lean:
  no — hooks stay mechanical, and the flag appears in the briefing and
  `vibe-learn health`.
- **Tool and skill mix.** The health row could carry per-session counts of
  tool families (read, search, shell, edit, web, subagent, `mcp:<server>`)
  and skills used, so a report can show that a regression coincided with,
  say, far more search calls or a skill no longer loading. Every host
  exposes this, but under different names. Lean: count from the transcript
  at rotation, next to the existing identity reads, rather than widening
  `observe.sh` matchers. Store family and skill names only, never arguments
  or MCP tool arguments.

## Out of Scope

- A fixed public canary suite or hosted leaderboard
- Scheduled bench runs and notifications
- LLM-graded or rubric-graded tasks
- Container or VM sandboxing for bench runs
- Health signals derived from transcripts beyond model, effort, and version (for
  example refusals or response length)
