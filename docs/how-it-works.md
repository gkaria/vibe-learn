# How it works

Part of [vibe-learn](../README.md). The learning commands read a local session log. This page is what writes that log, and what else the same files are used for.

---

## What happens automatically

After every AI response that touches files or runs commands, vibe-learn:

- Appends every action to `.vibe-learn/session-log.jsonl`
- Writes a pause summary to `.vibe-learn/pause-summary.txt`
- Injects that summary into your assistant's context at the start of the next session (Claude Code and GitHub Copilot CLI)
- Regenerates the session briefing in the background
- When the next session starts, saves one row of [assistant health](health.md) counts for the one that just ended

The summary looks like this (the last line switches to `/vibe-learn:…` under the plugin install):

```
⏸ vibe-learn — what just happened:
Goal: add JWT auth middleware

  ✦ Created src/middleware/auth.ts
  ✦ Edited src/routes/user.ts
  ✦ Ran: npm install jsonwebtoken

 /learn [question]  ·  /digest  ·  /quiz  ·  /explain [file|topic]  ·  vibe-learn briefing  ·  vibe-learn audio-prep
```

---

## Four lifecycle hooks

All fast and offline:

| Hook | Script | What it does |
|------|--------|--------------|
| `SessionStart` / `sessionStart` | `bootstrap.sh` | Creates `.vibe-learn/`, rotates previous log |
| `UserPromptSubmit` / `userPromptSubmitted` | `capture-prompt.sh` | Logs your prompt with a turn counter |
| `PostToolUse` / `postToolUse` | `observe.sh` | Appends one JSONL line per tool event (<50ms) |
| `Stop` / `agentStop` | `pause-summary.sh` | Writes summary, injects context, generates session briefing |

On-demand (never from hooks): `vibe-learn briefing`, `vibe-learn recap`, `vibe-learn audio-prep`, `vibe-learn health`, and the knowledge helper `scripts/knowledge.sh`.

All data stays in `.vibe-learn/` inside your project. No network calls, no external services.

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
