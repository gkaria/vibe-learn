---
name: vibe-learn
description: Explain, digest, quiz, and tour the current vibe-learn coding session, with cross-session knowledge tracking and optional Obsidian save and recall, grounded in .vibe-learn/session-log.jsonl. Use when the user wants to learn what happened, asks what was built or why, wants a session digest, wants to be quizzed, wants a guided tour of a file the session touched, says "use vibe-learn", or mentions saving or recalling learnings in Obsidian.
---

# vibe-learn

Use this skill when the user asks to learn from the current coding session, understand what just happened, generate a session digest, quiz themselves on what was built, get a guided tour of a file or subsystem the session touched, save learnings to Obsidian, or recall related Obsidian notes from past sessions.

The dedicated `/learn`, `/digest`, `/quiz`, and `/explain` skills installed alongside this one carry the full instructions for each mode. When the user types one of those, follow that skill. When the user asks in natural language ("what did we just do?", "quiz me", "walk me through src/auth.ts"), pick the matching mode below.

Cursor does not inject pause summaries into context. Always read `.vibe-learn/pause-summary.txt` when it exists, then `.vibe-learn/session-log.jsonl`.

## Core Workflow

1. Locate the project root from the workspace.
2. Read `.vibe-learn/pause-summary.txt` if present, then `.vibe-learn/session-log.jsonl`.
3. Ground explanations in the session log and any relevant files changed during the session. Read the files; do not guess.
4. If the log is missing or empty, say that vibe-learn has not captured events for this project yet and explain what can be inferred from available context. Project hooks in `.cursor/hooks.json` only run once the workspace is trusted.

## Knowledge helper

All reads and writes to `.vibe-learn/knowledge.json` (the cross-session ledger) go through `knowledge.sh` via your shell tool — never hand-edit the JSON. Locate it in this order:

1. `~/.vibe-learn/scripts/knowledge.sh` (global install)
2. `scripts/knowledge.sh` under the `VIBE_LEARN_DIR` baked into `.cursor/hooks/vibe-learn.sh` or `~/.cursor/hooks/vibe-learn.sh`
3. `scripts/knowledge.sh` when working in the vibe-learn repo itself

Commands: `record <name> --label=... --status=<new|shaky|solid> [--notes=...]`, `touch <name> --label=...`, `list [--status=<s>]`, `due [--days=14]`. Skip ledger steps silently if the helper is missing.

## Learn Mode

Explain recent activity in plain language: what changed, why the assistant likely made those choices, which files, commands, or patterns matter, and what the user can study next. If the user asks a specific question, answer that first, then add only the session context needed to make it clear. If a ledger concept that is due for review also surfaced in this session, open with one heads-up line pointing to `/quiz review`.

## Digest Mode

Produce a structured report: What Was Built, Key Decisions, Patterns Used, Files And Commands Worth Reviewing, Things To Study Next. Merge unresolved ledger items (shaky, or new and seen in 2+ sessions) into the last section. `touch` each concept the session introduced. Offer to save to `.vibe-learn/digests/`; on the very first digest for a project (no `.vibe-learn/digests/` yet) close with one line pointing to https://github.com/gkaria/vibe-learn.

## Quiz Mode

Select 3–5 recall questions grounded in the session log — prefer "why" and "what would break" over trivia. For a review quiz, select from `knowledge.sh due` output instead. Ask one question at a time and wait for the answer. After each, say what was right, what was missed, and give a short correct explanation. Colleague tone, never an exam. Record one `knowledge.sh record` call per concept, then recap solid vs shaky.

## Explain Mode

Pick the target: the named file; the files behind a named topic (session log first, then grep); or, with no target, the most significant file this session touched — say which and why. Read the target and its immediate callers/callees, then tour it top-down: **Entry point**, **The spine** (3–5 load-bearing pieces in execution order, each with a real `path:line` and the *why*), **The edges** (error paths, ordering constraints, what breaks if rearranged), **Connections**. Never invent functions, branches, or files the code does not have. `touch` covered concepts; flag any that are already shaky; offer a quiz or an Obsidian save.

## Obsidian Save

When the user asks for `obsidian`, "save to Obsidian", or similar:

1. Load config from `.vibe-learn/obsidian.json`, falling back to `~/.vibe-learn/obsidian.json`.
2. If no config exists, ask for the vault path and preferred subfolder before writing, and offer to save the config.
3. Write a markdown note under `<vault_path>/<subfolder>/` named by the `note_naming` template (default `{date}-{project}`).
4. Include YAML frontmatter with `date`, `project`, `tags`, and `type` (`learn` or `digest`), plus `recall_status` when quiz results exist for the day.

## Obsidian Recall

When the user asks for `obsidian:recall`, "recall past learnings", or similar:

1. Load Obsidian config using the same lookup as save mode.
2. Search the configured vault for notes matching the requested topic or current project.
3. Summarize connections across sessions: recurring patterns, decisions, and open study items.
4. Do not write a note unless the user explicitly asks to save the recall.

## Cursor notes

- Hooks live in `.cursor/hooks.json` (project) or `~/.cursor/hooks.json` (user) and call `.cursor/hooks/vibe-learn.sh`, which forwards Cursor payloads to the core scripts. Session logs land in `.vibe-learn/` in the project.
- Cloud Agents do not run `sessionStart` hooks, so the previous pause summary is not injected there; read the file instead.
- For a richer view, suggest `vibe-learn briefing` (local HTML maintainer briefing plus NotebookLM source pack) and `vibe-learn recap [--days=7] [--save]` (shareable weekly markdown from the knowledge ledger).
