---
name: vibe-learn
description: Explain, digest, and quiz the current vibe-learn coding session, with cross-session knowledge tracking and optional Obsidian save and recall workflows grounded in .vibe-learn/session-log.jsonl. Use when the user wants to learn what happened, asks /learn, /digest, /quiz, /vibe-learn, or mentions saving or recalling Obsidian notes.
when-to-use: User asks what just happened, wants a session digest, wants to be quizzed, says "use vibe-learn", or asks to save/recall learnings in Obsidian.
user-invocable: true
argument-hint: "[learn|digest|quiz|obsidian] [question]"
---

# vibe-learn

Use this skill when the user asks to learn from the current coding session, understand what just happened, generate a session digest, quiz themselves on what was built, save learnings to Obsidian, or recall related Obsidian notes from past sessions.

Grok Build does not inject pause summaries into context. Always read `.vibe-learn/pause-summary.txt` when it exists, then `.vibe-learn/session-log.jsonl`.

## Core Workflow

1. Locate the current project root from the conversation or working directory.
2. Read `.vibe-learn/pause-summary.txt` if present, then `.vibe-learn/session-log.jsonl`.
3. Ground explanations in the session log and any relevant files changed during the session. Use `read_file` and `grep`.
4. If the log is missing or empty, say that vibe-learn has not captured events for this project yet and explain what can be inferred from available context.

## Learn Mode

When the user asks to "learn" or runs `/learn`, explain recent activity in plain language:

- What changed
- Why the assistant likely made those choices
- Which files, commands, or patterns matter
- What the user can study next

If the user asks a specific question, answer that question first, then add only the session context needed to make it clear.

## Digest Mode

When the user asks for a "digest" or runs `/digest`, produce a structured report:

- What Was Built
- Key Decisions
- Patterns Used
- Files And Commands Worth Reviewing
- Things To Study Next

Offer to save a digest only when the user asks for saving or Obsidian.

## Quiz Mode

When the user asks to be quizzed (`/quiz`, "Use vibe-learn to quiz me", "check my understanding", "quiz me on what's due"):

1. Follow `.grok/commands/quiz.md` when the project has it; otherwise apply the same flow from this skill.
2. Select 3–5 recall questions grounded in the session log — prefer "why" and "what would break" questions over trivia. For a review quiz, select from `knowledge.sh due` output instead.
3. Ask one question at a time and wait for the answer. After each, say what was right, what was missed, and give a short correct explanation. Colleague tone, never an exam.
4. Record results in the knowledge ledger via `run_terminal_command` — one call per concept: `bash ~/.vibe-learn/scripts/knowledge.sh record <name> --label="..." --status=<solid|shaky> [--notes="..."]`. If that path doesn't exist, use the `scripts/knowledge.sh` next to the `bootstrap.sh` the vibe-learn hooks point at in `.grok/hooks/vibe-learn.json` or `~/.grok/hooks/vibe-learn.json`. Never hand-edit `.vibe-learn/knowledge.json`. Skip silently if the helper is missing.
5. Close with a recap: solid concepts, shaky concepts, and what to revisit.

## Knowledge Ledger

`.vibe-learn/knowledge.json` tracks concepts across sessions (first_seen, last_seen, sessions, last_quizzed, status new/shaky/solid). Learn responses may open with a one-line heads-up when a shaky concept resurfaces; digests merge unresolved ledger items into "Things To Study Next" and `touch` newly introduced concepts. All reads and writes go through `knowledge.sh` (`record`, `touch`, `list`, `due`).

## Obsidian Save

When the user asks for `obsidian`, "save to Obsidian", or similar:

1. Load config from `.vibe-learn/obsidian.json`, falling back to `~/.vibe-learn/obsidian.json`.
2. If no config exists, ask for the vault path and preferred subfolder before writing.
3. Write a markdown note under `<vault_path>/<subfolder>/`.
4. Include YAML frontmatter with `date`, `project`, `tags`, and `type`.
5. Use note type `learn` for learn notes and `digest` for digest reports.

## Obsidian Recall

When the user asks for `obsidian:recall`, "recall past learnings", or similar:

1. Load Obsidian config using the same lookup as save mode.
2. Search the configured vault for notes matching the requested topic or current project.
3. Summarize connections across sessions, including recurring patterns, decisions, and open study items.
4. Do not write a note unless the user explicitly asks to save the recall.

## Grok Build UX Notes

Treat `/learn`, `/digest`, `/quiz`, `/vibe-learn`, and natural-language requests like "Use vibe-learn to learn what happened" as the same interface. Project installs also copy `.grok/commands/learn.md`, `digest.md`, and `quiz.md`.

Project hooks in `.grok/hooks/` stay inert until the folder is trusted (`/hooks-trust` or `grok --trust`). Global hooks in `~/.grok/hooks/` are always trusted.

If this machine also has Claude Code vibe-learn hooks, Grok may run both hook sets. Prefer the Grok matcher in `~/.grok/hooks/vibe-learn.json`. To avoid double-logging, set `[compat.claude] hooks = false` in `~/.grok/config.toml`.

When the user wants a richer operational view, suggest running `vibe-learn briefing` in the project to generate a local HTML maintainer briefing and NotebookLM-ready audio source pack.
