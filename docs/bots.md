# Agent bots and routines

vibe-learn's hooks only log. Briefings are built when you run `vibe-learn briefing`, `/learn`, or `/digest`. An agent bot that runs on a schedule (Grok Bot, a Claude Code routine, or `claude -p` started by cron) can do the learning work for you: read the briefing facts, write the digest, and quiz you in chat on what is due. That is optional. Nothing in the hooks changes, and nothing leaves your machine unless a routine you install sends it.

Two recipes ship in [`examples/routines/`](../examples/routines/). Both are prompts plus shell commands for a bot that can run commands on your machine; neither adds a script to vibe-learn.

| Recipe | For | What it does |
|--------|-----|--------------|
| [Daily learning digest](../examples/routines/daily-digest.md) | users | Once a day: reads the facts of sessions since yesterday, writes a digest for each to `.vibe-learn/digests/<slug>-routine.md`, sends a short chat message, and asks one recall question about a concept that is due. Your answer is recorded in the knowledge ledger. |
| [Pre-release end-to-end check](../examples/routines/e2e-check.md) | maintainers of this repo | Runs `tests/e2e/run.sh` against the release branch and posts the result lines on the release PR. |

## Daily learning digest

The routine reads only what it needs:

- `vibe-learn briefing --json` and the saved facts in `.vibe-learn/briefing/sessions/*.json` ([fields](briefing.md#session-facts-as-json)), filtered by the recipe's shell block before the bot sees them;
- `vibe-learn knowledge due --days=14`, the concepts that are shaky or not quizzed for 14 days (`review_after_days`).

It writes the digest files and, through `vibe-learn knowledge record`, your quiz results. A session's digest file is also how the routine knows it has reported that session, so it keeps no other state.

Facts exist only for sessions that had a briefing built: the current session (the routine builds it), and earlier sessions in which you ran `/learn`, `/digest`, or `vibe-learn briefing`. A session that ended without one is not in the digest.

Before you schedule it, read [what a routine may read and send](privacy.md#routines).

## End-to-end check

`tests/e2e/run.sh` installs a checkout into a temporary `HOME`, drives real Claude Code sessions, and compares counts and shapes with a golden file ([details](how-it-works.md#testing-this-repo)). It needs a Claude credential, so it is not a CI job: maintainers run it by hand before each release. The recipe is the same check for a maintainer who asks their own agent to run it.
