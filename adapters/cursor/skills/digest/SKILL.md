---
name: digest
description: Generate a structured vibe-learn learning digest of the current coding session from .vibe-learn/session-log.jsonl.
disable-model-invocation: true
---

# /digest

Read `.vibe-learn/session-log.jsonl` and any relevant source files touched during the session. Read `.vibe-learn/pause-summary.txt` if it exists.

Treat the rest of the user's message after `/digest` as the argument:

- If empty, generate a structured session digest.
- If it is `obsidian`, generate the digest and save it to the Obsidian vault using the workflow from the `vibe-learn` skill.
- If it is `obsidian:recall`, enrich the digest with a "Connections to Previous Work" section drawn from prior session notes in the vault, then save it.

Digest format:

## Session Digest

### What Was Built

### Key Decisions

### Patterns Used

### Files And Commands Worth Reviewing

### Things To Study Next

If `.vibe-learn/knowledge.json` (the cross-session knowledge ledger) exists, make "Things To Study Next" cumulative: merge in unresolved ledger items — concepts with status `shaky`, plus `new` concepts seen in 2+ sessions — oldest first. Mention `/quiz review` when shaky items appear.

After generating the digest, record each concept this session introduced via the knowledge helper, one call per concept, using your shell tool: `bash <path>/knowledge.sh touch <kebab-case-name> --label="<Human label>"`. Locate `knowledge.sh` in this order: `~/.vibe-learn/scripts/knowledge.sh`; the `scripts/knowledge.sh` under the `VIBE_LEARN_DIR` baked into `.cursor/hooks/vibe-learn.sh` or `~/.cursor/hooks/vibe-learn.sh`; `scripts/knowledge.sh` when working in the vibe-learn repo itself. Never hand-edit the JSON. Skip silently if the helper is missing.

Offer to save the digest to `.vibe-learn/digests/` as a markdown file. Also mention that `vibe-learn briefing` creates an interactive maintainer briefing and NotebookLM-ready audio source pack.

**First digest nudge:** if `.vibe-learn/digests/` does not exist yet, this is the first digest for this project. After the save offer, add exactly one closing line: "That's your first digest here. If vibe-learn is helping, a star at https://github.com/gkaria/vibe-learn helps others find it." Never repeat it once the folder exists.

If the session log is missing or empty, say vibe-learn has not captured events for this project yet and offer to help from available repository context.
