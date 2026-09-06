---
description: Guided code tour of a file or subsystem this session touched — entry point, the load-bearing pieces, the edges, and what connects to it
---

Read .vibe-learn/session-log.jsonl to see what this session touched and why (the `user_prompt` events carry the intent). Read `.vibe-learn/knowledge.json` if it exists (the cross-session knowledge ledger).

This project prompt fallback can be used by asking Codex to read `.codex/prompts/explain.md` and follow it, or through `/prompts:explain` when custom prompts are available. Name a file or topic in the same message or as a follow-up.

**Knowledge helper:** to mark concepts as seen, use the `knowledge.sh` helper via your shell tool — never hand-edit the JSON. Locate it in this order:

1. `~/.vibe-learn/scripts/knowledge.sh` (global install)
2. The install directory this project's hooks point at: read the vibe-learn hook command from `.codex/config.toml` (or `~/.codex/config.toml`) — it ends in `<install-dir>/scripts/bootstrap.sh`, and `knowledge.sh` sits in the same directory
3. `scripts/knowledge.sh` in the vibe-learn repo, if this project is the vibe-learn repo itself

If none of these exist, skip the ledger step silently — the tour itself still works.

Treat the file or topic the user named as $ARGUMENTS and pick the target:

---

## Target: none

If $ARGUMENTS is empty: tour the most significant file or subsystem this session touched. Prefer, in order: a newly created file that other touched files import; the file edited most often; the file behind the goal stated in the last `user_prompt`. Say which one you picked and why in one line.

## Target: `<file>`

If $ARGUMENTS names a path that exists: tour that file.

## Target: `<topic>`

Otherwise treat $ARGUMENTS as a topic (e.g. `auth flow`, `the retry logic`): find the files behind it — start from the session log, then grep the codebase — and tour them as one subsystem. If nothing matches, say so and list what the session did touch.

---

## Tour structure (all targets)

Read the target file(s) and their immediate callers and callees before writing anything. Walk the code top-down as a colleague would at a whiteboard:

1. **Entry point** — where execution starts and what triggers it (a request, a hook event, a CLI call, an import).
2. **The spine** — the 3–5 load-bearing pieces, in execution order. For each, say *why it is there*, not just what it does. Quote the real line with a `path:line` reference.
3. **The edges** — error paths, ordering constraints, defaults, and anything that would break if rearranged or removed.
4. **Connections** — what calls this, what this calls, and where a change here would ripple.

Rules:

- Stay grounded: every claim about structure must point at a real `file:line`. Never invent functions, branches, or files the code does not have.
- Tie the tour back to the session: if the session log shows *why* a piece was added (a prompt, a failed command that was then fixed), say so.
- Keep it to roughly 250–400 words for a single file; a subsystem tour may run longer but should still fit on one screen per section.
- Plain language; explain as if to someone who will have to maintain this next month.

## Close (all targets)

1. Ledger: `touch` each concept the tour covered, one call per concept, using a stable kebab-case name and a short human label — `bash <path>/knowledge.sh touch <name> --label="<Human label>"` via the lookup order above. Never hand-edit the JSON.
2. If any concept covered is already `shaky` in the ledger, say so in one line ("You marked middleware ordering shaky on July 11 — this is the code behind it.").
3. Offer the next step: "Want me to quiz you on this ("Use vibe-learn to quiz me on <topic>"), or save it to Obsidian ("Use vibe-learn to save this to Obsidian")?"

If the session log is empty and no target was given, say vibe-learn has not observed any changes yet and offer to tour a file the user names.
