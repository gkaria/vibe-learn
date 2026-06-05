---
description: Generate a structured vibe-learn digest from the current session
---

Read `.vibe-learn/session-log.jsonl` and any relevant source files touched during the session. Read `.vibe-learn/pause-summary.txt` if it exists.

Parse `$ARGUMENTS` to determine the mode:

- If empty, generate a structured session digest.
- If it is `obsidian`, follow the Obsidian digest save workflow documented in the Claude Code `/digest` command.
- If it is `obsidian:recall`, enrich the digest with relevant prior Obsidian notes before saving.

Digest format:

## Session Digest

### What Was Built

### Key Decisions

### Patterns Used

### Files And Commands Worth Reviewing

### Things To Study Next

Also mention that `vibe-learn briefing` creates an interactive maintainer briefing and NotebookLM-ready audio source pack.

If the session log is missing or empty, say vibe-learn has not captured events for this project yet and offer to help from available repository context.
