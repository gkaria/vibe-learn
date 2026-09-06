---
name: vibe-learn
description: Explain, digest, quiz, and tour the code of the current vibe-learn coding session, with cross-session knowledge tracking and optional Obsidian save and recall workflows grounded in .vibe-learn/session-log.jsonl.
---

# vibe-learn

Use this skill when the user asks to learn from the current coding session, understand what just happened, generate a session digest, quiz themselves on what was built, get a guided tour of a file or subsystem the session touched, save learnings to Obsidian, or recall related Obsidian notes from past sessions.

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

## Quiz Mode

When the user asks to be quizzed ("Use vibe-learn to quiz me", "check my understanding", "quiz me on what's due"):

1. Follow `.codex/prompts/quiz.md` when the project has it; otherwise apply the same flow from this skill.
2. Select 3–5 recall questions grounded in the session log — prefer "why" and "what would break" questions over trivia. For a review quiz, select from `knowledge.sh due` output instead.
3. Ask one question at a time and wait for the answer. After each, say what was right, what was missed, and give a short correct explanation. Colleague tone, never an exam.
4. Record results in the knowledge ledger via the helper — one call per concept: `bash ~/.vibe-learn/scripts/knowledge.sh record <name> --label="..." --status=<solid|shaky> [--notes="..."]`. If that path doesn't exist, use the `scripts/knowledge.sh` next to the `bootstrap.sh` the vibe-learn hooks point at in `.codex/config.toml` or `~/.codex/config.toml`. Never hand-edit `.vibe-learn/knowledge.json`. Skip silently if the helper is missing.
5. Close with a recap: solid concepts, shaky concepts, and what to revisit.

## Explain Mode

When the user asks for a code tour ("Use vibe-learn to explain src/auth.ts", "walk me through the retry logic", "explain what we touched"):

1. Follow `.codex/prompts/explain.md` when the project has it; otherwise apply this flow.
2. Pick the target: the named file; the files behind a named topic (session log first, then grep); or, with no target, the most significant file this session touched (a new file others import, the most-edited file, or the file behind the last prompt) — say which and why.
3. Read the target and its immediate callers/callees, then tour it top-down: **Entry point** (what triggers it), **The spine** (3–5 load-bearing pieces in execution order, each with a real `path:line` and the *why*), **The edges** (error paths, ordering constraints, what breaks if rearranged), **Connections** (callers, callees, ripple). Never invent functions, branches, or files the code does not have. Tie pieces back to the session log when it shows why they were added.
4. Mark covered concepts as seen via the shell tool: `bash ~/.vibe-learn/scripts/knowledge.sh touch <name> --label="..."` (same helper lookup as Quiz Mode). Never hand-edit the JSON; skip silently if the helper is missing.
5. If a covered concept is already shaky in the ledger, say so in one line. Close by offering a quiz on the topic or an Obsidian save.

## Knowledge Ledger

`.vibe-learn/knowledge.json` tracks concepts across sessions (first_seen, last_seen, sessions, last_quizzed, status new/shaky/solid). Learn responses may open with a one-line heads-up when a shaky concept resurfaces; digests merge unresolved ledger items into "Things To Study Next" and `touch` newly introduced concepts. All reads and writes go through `knowledge.sh` (`record`, `touch`, `list`, `due`). For a shareable weekly rollup, the user (or you, on request) can run `vibe-learn recap [--days=7] [--save]` — read-only markdown of solid/shaky/new concepts plus session activity.

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

Treat natural-language requests like "Use vibe-learn to learn what happened" and "Use vibe-learn to create a digest" as the primary Codex interface. Project installs may also include `.codex/prompts/learn.md` and `.codex/prompts/digest.md` as prompt-file fallbacks; in current Codex these can also be invoked as custom prompt slash commands under the `/prompts:*` namespace, but skills are the durable interface.

When the user wants a richer operational view, suggest running `vibe-learn briefing` in the project to generate a local HTML maintainer briefing and NotebookLM-ready audio source pack.
