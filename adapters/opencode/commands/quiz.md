---
description: Check your understanding of the vibe-learn session — recall questions with results tracked across sessions
---

Read `.vibe-learn/session-log.jsonl` to understand what happened in this session. Read `.vibe-learn/knowledge.json` if it exists (the cross-session knowledge ledger).

To read or update the ledger, use the `knowledge.sh` helper via your shell tool — never hand-edit the JSON. Locate it at `~/.vibe-learn/scripts/knowledge.sh`, or next to the vibe-learn scripts path referenced in `.opencode/plugins/vibe-learn.js` (project installs from a cloned checkout), or `scripts/knowledge.sh` when working in the vibe-learn repo itself. If the helper is missing, skip ledger updates and say so briefly.

Parse `$ARGUMENTS` to determine the mode:

- If empty, quiz on this session: select 3–5 quizzable moments from the session log — decisions, patterns, dependencies added, failures that were fixed.
- If it is `review`, run `knowledge.sh due` and quiz on concepts that are shaky or haven't been quizzed recently. If nothing is due, say so and offer a session quiz instead.
- Otherwise, treat `$ARGUMENTS` as a topic and quiz on it, drawing from the session log, the ledger, and relevant source files.

Question flow, following the same conventions documented in the Claude Code `/quiz` command:

1. Prefer "why" and "what would break" questions over trivia.
2. Ask one question at a time; wait for the user's answer before revealing anything.
3. After each answer, say what the user got right, what they missed, and give a 1–2 sentence correct explanation. Colleague tone, never an exam.
4. After the last question, record one `knowledge.sh record <name> --label="..." --status=<solid|shaky>` call per concept quizzed, with `--notes` on what was shaky.
5. Close with a short recap and, if anything was shaky, point to `/learn <topic>`.

If the session log is empty and no ledger exists, say vibe-learn has nothing to quiz on yet and stop.
