---
name: vibe-learn
description: Explain and digest the current vibe-learn coding session, with optional Obsidian save and recall workflows grounded in .vibe-learn/session-log.jsonl.
---

# vibe-learn

Use this skill when the user asks to learn from the current coding session, understand what just happened, generate a session digest, save learnings to Obsidian, or recall related Obsidian notes from past sessions.

## Core Workflow

1. Locate the current project root from the conversation or working directory.
2. Read `.vibe-learn/session-log.jsonl` if present, plus `.vibe-learn/pause-summary.txt` when useful.
3. Ground explanations in the session log and any relevant files changed during the session.
4. If the log is missing or empty, say that vibe-learn has not captured events for this project yet and explain what can be inferred from available context.

## Learn Mode

When the user asks to "learn", explain recent activity in plain language:

- What changed
- Why the assistant likely made those choices
- Which files, commands, or patterns matter
- What the user can study next

If the user asks a specific question, answer that question first, then add only the session context needed to make it clear.

## Digest Mode

When the user asks for a "digest", produce a structured report:

- What Was Built
- Key Decisions
- Patterns Used
- Files And Commands Worth Reviewing
- Things To Study Next

Offer to save a digest only when the user asks for saving or Obsidian.

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

## Codex UX Notes

Codex does not support custom `/learn` or `/digest` slash commands. Treat natural-language requests like "Use vibe-learn to learn what happened" and "Use vibe-learn to create a digest" as the primary interface. Project installs may also include `.codex/prompts/learn.md` and `.codex/prompts/digest.md` as prompt-file fallbacks.
