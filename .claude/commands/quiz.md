---
description: Check your understanding of what was built — recall questions grounded in the session log, with results tracked across sessions
---

Read .vibe-learn/session-log.jsonl to understand what happened in this session. Read `.vibe-learn/knowledge.json` if it exists (the cross-session knowledge ledger).

**Knowledge helper:** to read or update the ledger, use the `knowledge.sh` helper via Bash — never hand-edit the JSON. Locate it in this order:

1. `~/.vibe-learn/scripts/knowledge.sh` (global install)
2. The install directory this project's hooks point at: read the vibe-learn hook command from `.claude/settings.local.json` (or `~/.claude/settings.json`) — it ends in `<install-dir>/scripts/bootstrap.sh`, and `knowledge.sh` sits in the same directory
3. `scripts/knowledge.sh` in the vibe-learn repo, if this project is the vibe-learn repo itself

If none of these exist, skip ledger updates and say so briefly at the end — the quiz itself still works.

Helper usage:

```bash
bash <helper> record <name> --label="<Human label>" --status=<solid|shaky> [--notes="<what was shaky>"]
bash <helper> due --days=14    # concepts due for review, as a JSON array
bash <helper> list             # full ledger
```

Read `review_after_days` and `quiz_question_count` from `~/.vibe-learn/config/knowledge-defaults.json` if present (defaults: 14 and 5).

Parse $ARGUMENTS to determine the mode:

---

## Mode: `review`

If $ARGUMENTS is `review`:

1. Run the helper's `due` command to get concepts that are shaky or haven't been quizzed recently.
2. If nothing is due, say so and offer a regular `/quiz` on this session instead.
3. Otherwise pick up to the configured question count of due concepts (shakiest and oldest first) and quiz on those, following the question flow below. Ground questions in the current codebase — read the relevant files first.

---

## Mode: `<topic>`

If $ARGUMENTS is anything else (a topic):

Quiz on that topic, drawing questions from this session's log if it touched the topic, otherwise from the ledger and the relevant source files.

---

## Mode: plain `quiz` (no arguments)

Quiz on this session. Select 3–5 quizzable moments from the session log — decisions, patterns, dependencies added, failures that were fixed.

---

## Question flow (all modes)

Prefer "why" and "what would break" questions over trivia:

- "Why did we install bcrypt instead of hashing manually?"
- "The Stop hook writes JSON to stdout — what consumes it, and what happens if the JSON is malformed?"
- "If you needed to add a fourth adapter tomorrow, which files would you touch?"

1. Ask **one question at a time**. Wait for the user's answer before revealing anything.
2. After each answer, respond with: what the user got right, what they missed, and a 1–2 sentence correct explanation. Never scold — the tone is a colleague checking understanding, not an exam.
3. After the last question, record results: one `record` call per concept quizzed, with `--status=solid` for a substantially correct answer or `--status=shaky` for an incomplete or incorrect one. Use a stable kebab-case concept name (e.g. `jwt-refresh-tokens`) and a short human label. Add `--notes` describing what specifically was shaky.
4. Close with a short recap: concepts confirmed solid, concepts to revisit, and — if anything was shaky — a pointer to `/learn <topic>` for the shakiest one.

If the session log is empty and no ledger exists, say vibe-learn has nothing to quiz on yet and stop.
