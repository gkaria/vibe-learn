---
description: Explain recent vibe-learn session activity or answer a question about what was built
---

Read `.vibe-learn/session-log.jsonl` to understand what happened in this session. Read `.vibe-learn/pause-summary.txt` if it exists.

Parse `$ARGUMENTS` to determine the mode:

- If empty, explain the most recent session activity in plain language.
- If it starts with `obsidian`, follow the same Obsidian save and recall workflow documented in the Claude Code `/learn` command.
- Otherwise, answer `$ARGUMENTS` as a specific question grounded in the session log and relevant changed files.

If `.vibe-learn/knowledge.json` exists, run the knowledge helper's `due` command (`bash ~/.vibe-learn/scripts/knowledge.sh due`; if that path doesn't exist, use the `scripts/knowledge.sh` next to the vibe-learn scripts path referenced in `.opencode/plugins/vibe-learn.js`, or `bash scripts/knowledge.sh due` in the vibe-learn repo itself). If a due concept was also touched in this session, open with a single heads-up line pointing to `/quiz review` — never let it block the actual answer. Skip silently if the ledger or helper is missing.

For OpenCode users, mention that `vibe-learn briefing` generates an interactive maintainer briefing and NotebookLM-ready audio source pack.

If the session log is missing or empty, say vibe-learn has not captured events for this project yet and offer to help from available repository context.
