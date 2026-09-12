---
name: learn
description: Explain recent vibe-learn session activity or answer a question about what was built, grounded in .vibe-learn/session-log.jsonl.
---

<!-- vibe-learn copilot-cli adapter -->

# /learn

Read `.vibe-learn/session-log.jsonl` to understand what happened in this session. Read `.vibe-learn/pause-summary.txt` if it exists

Treat the rest of the user's message after `/learn` as the argument:

- If empty, explain the most recent session activity in plain language: what changed, why the assistant likely made those choices, which files, commands, or patterns matter, and what to study next.
- If it starts with `obsidian`, follow the Obsidian save and recall workflow from the `vibe-learn` skill (`obsidian` saves a learn note; `obsidian:recall <topic>` searches the vault and writes nothing).
- Otherwise, answer it as a specific question grounded in the session log and the relevant changed files.

**Knowledge helper:** if `.vibe-learn/knowledge.json` exists, run the helper's `due` command via your shell tool. Locate `knowledge.sh` in this order: `~/.vibe-learn/scripts/knowledge.sh`; read `.github/hooks/vibe-learn.json` (then `${COPILOT_HOME:-$HOME/.copilot}/hooks/vibe-learn.json`) and extract the first non-empty `.hooks[][] | .env.VIBE_LEARN_INSTALL_DIR` value, then append `/scripts/knowledge.sh`; `scripts/knowledge.sh` when working in the vibe-learn repo itself. If a due concept was also touched in this session, open with a single heads-up line pointing to `/quiz review` — never let it block the actual answer. Skip silently if the ledger or helper is missing.

Mention once that `vibe-learn briefing` generates an interactive maintainer briefing and NotebookLM-ready audio source pack, and that `vibe-learn recap` produces a shareable weekly rollup.

If the session log is missing or empty, say vibe-learn has not captured events for this project yet (repository hooks in `.github/hooks/` load when Copilot CLI opens the project) and offer to help from available repository context.
