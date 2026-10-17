# How it works

Part of [vibe-learn](../README.md). The learning commands read a local session log. This page is what writes that log, and what else the same files are used for.

---

## What happens automatically

After every AI response that touches files or runs commands, vibe-learn:

- Appends every action to `.vibe-learn/session-log.jsonl`
- Writes a pause summary to `.vibe-learn/pause-summary.txt`
- Injects that summary into your assistant's context at the start of the next session (Claude Code and GitHub Copilot CLI), if the session that just ended wrote it
- When the next session starts, saves one row of [assistant health](health.md) counts for the one that just ended, and builds that session's briefing in the background

The briefing is also rebuilt when you run `vibe-learn briefing`, and `/learn` and `/digest` refresh it first when the session has moved on. Nothing heavier than the summary runs after each response.

The summary covers the whole session so far: the goal (the first substantial prompt), commands that failed and have not passed since, the last turn's actions, and up to ten of the files touched, with paths relative to the project (on a session over 5000 log lines, those of its last 5000). Learning commands (`/learn`, `/digest`, `/quiz`, `/explain`) are left out, and a turn that only ran one of them keeps the previous summary. It is capped at `pause_summary_max_lines` (default 20; set it in `~/.vibe-learn/config.json` or the project's `.vibe-learn/config.json`). The last line switches to `/vibe-learn:…` under the plugin install:

```
⏸ vibe-learn — this session so far:
Goal: add JWT auth middleware to the user routes

⚠ 1 command(s) still failing — worth checking before continuing:
  ✗ npm test (exit 1)

Last turn: wire the middleware into /profile
  ✦ Edited src/routes/user.ts
  ✦ Ran: npm test [failed ✗]

Files this session (2):
  src/middleware/auth.ts — created, edited ×2
  src/routes/user.ts — edited

 /learn [question]  ·  /digest  ·  /quiz  ·  vibe-learn briefing  ·  vibe-learn audio-prep
```

---

## Four lifecycle hooks

All fast and offline:

| Hook | Script | What it does |
|------|--------|--------------|
| `SessionStart` / `sessionStart` | `bootstrap.sh` | Creates `.vibe-learn/`, rotates previous log, starts its briefing detached |
| `UserPromptSubmit` / `userPromptSubmitted` | `capture-prompt.sh` | Logs your prompt with a turn counter |
| `PostToolUse` / `postToolUse` | `observe.sh` | Appends one JSONL line per tool event (<50ms) |
| `Stop` / `agentStop` | `pause-summary.sh` | Writes the summary file (injected at the next session start) |

On-demand (never from hooks, apart from the one detached briefing at rotation): `vibe-learn briefing`, `vibe-learn recap`, `vibe-learn audio-prep`, `vibe-learn health`, and the knowledge helper `scripts/knowledge.sh`.

All data stays in `.vibe-learn/` inside your project. No network calls, no external services.

---

## Configuration

vibe-learn reads two optional files: `~/.vibe-learn/config.json` for every project, and `.vibe-learn/config.json` inside a project, which wins key by key. Create either one with only the keys you want to change:

```json
{ "capture_prompts": false, "pause_summary_max_lines": 12, "health": { "global_log": false } }
```

| Key | Default | Effect |
|-----|---------|--------|
| `capture_prompts` | `true` | `false` keeps prompt text out of the log; turns are still counted |
| `pause_summary_max_lines` | `20` | Line cap for `pause-summary.txt` (minimum 4) |
| `health.enabled`, `health.global_log` | `true` | Turn [assistant health](health.md) rows off, or keep them per project |
| `health.min_events`, `min_sessions`, `rate_threshold_pts`, `count_threshold`, `control_min_sessions` | see `config/defaults.json` | Thresholds for `vibe-learn health` |

`config/defaults.json` in the install lists every key with its default. It is a reference; editing it has no effect.

---

## Knowledge ledger

Reading a digest feels like learning; answering questions proves it. `/quiz` asks 3–5 recall questions grounded in what actually happened this session — one at a time, then tells you what you got right and what you missed.

Results go into `.vibe-learn/knowledge.json`, a small cross-session knowledge ledger. Concepts you answered shakily come back: `/quiz review` re-quizzes anything shaky or unreviewed for two weeks, `/learn` gives you a one-line heads-up when a shaky concept resurfaces in a new session, and `/digest`'s "Things to Study" accumulates across sessions instead of resetting.

The ledger is updated only by the learning commands (via `scripts/knowledge.sh`) — never by hooks, never over the network.

### Share what you learned

```bash
vibe-learn recap            # this week, to stdout
vibe-learn recap --days=30  # wider window
vibe-learn recap --save     # also writes .vibe-learn/recaps/<date>-recap.md
```

A markdown rollup built from the ledger, the session logs, and any saved digests — what you confirmed solid, what's still shaky, what you met but haven't been quizzed on, plus days active and files touched. Made to paste into a standup note, a learning journal, or a post:

```
# What I learned this week — my-api
2026-07-05 → 2026-07-11

**3 active day(s) · 7 prompt(s) · 14 file(s) touched · 22 command(s) run · quizzed on 2 day(s)**

## Confirmed solid (2)
- JWT verification — quizzed 2026-07-11
- Fail-closed auth — quizzed 2026-07-11

## Still shaky — revisit (1)
- Express middleware ordering — quizzed 2026-07-11: you had the what, not the when

## Met this week, not quizzed yet (1)
- Repository pattern — seen in 2 session(s), not quizzed yet

## Next
/quiz review — re-ask the shaky ones until they stick.
```

---

## Testing (this repo)

```bash
brew install bats-core    # macOS
apt-get install bats      # Linux

bats tests/
```
