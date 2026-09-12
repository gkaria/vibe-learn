---
name: quiz
description: Check your understanding of the vibe-learn session — recall questions grounded in the session log, with results tracked across sessions in the knowledge ledger.
---

<!-- vibe-learn copilot-cli adapter -->

# /quiz

Read `.vibe-learn/session-log.jsonl` to understand what happened in this session. Read `.vibe-learn/knowledge.json` if it exists (the cross-session knowledge ledger).

**Knowledge helper:** to read or update the ledger, use the `knowledge.sh` helper via your shell tool — never hand-edit the JSON. Locate it in this order: `~/.vibe-learn/scripts/knowledge.sh`; read `.github/hooks/vibe-learn.json` (then `~/.copilot/hooks/vibe-learn.json`) and extract the first non-empty `.hooks[][] | .env.VIBE_LEARN_INSTALL_DIR` value, then append `/scripts/knowledge.sh`; `scripts/knowledge.sh` when working in the vibe-learn repo itself. If the helper is missing, skip ledger updates and say so briefly.

Treat the rest of the user's message after `/quiz` as the argument:

- If empty, quiz on this session: select 3–5 quizzable moments from the session log — decisions, patterns, dependencies added, failures that were fixed.
- If it is `review`, run `knowledge.sh due` and quiz on concepts that are shaky or haven't been quizzed recently. If nothing is due, say so and offer a session quiz instead.
- Otherwise, treat it as a topic and quiz on it, drawing from the session log, the ledger, and relevant source files.

Question flow:

1. Prefer "why" and "what would break" questions over trivia.
2. Ask one question at a time; wait for the user's answer before revealing anything.
3. After each answer, say what the user got right, what they missed, and give a 1–2 sentence correct explanation. Colleague tone, never an exam.
4. After the last question, record one `knowledge.sh record <name> --label="..." --status=<solid|shaky>` call per concept quizzed, with `--notes` on what was shaky. Use stable kebab-case names so the same concept is recognised across sessions.
5. Close with a short recap and, if anything was shaky, point to `/learn <topic>` or `/explain <file>`.

If the session log is empty and no ledger exists, say vibe-learn has nothing to quiz on yet and stop.
