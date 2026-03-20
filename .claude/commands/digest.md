Generate a full learning digest from the current session log.

Read .vibe-learn/session-log.jsonl (the full log). Read any relevant source files to understand what was built. Then produce a structured markdown learning report:

## 📘 Session Digest

### What Was Built
2-4 sentences summarising the session in plain language.

### Key Decisions
For each significant architectural or technical choice, explain what was chosen and why. Bullet points.

### Patterns Used
Key programming patterns, techniques, or concepts that appeared. Brief bullets.

### Things to Study
3-6 checkboxes of topics worth exploring further based on what was built:
- [ ] topic

---

Keep the tone warm and encouraging. Plain language. If the session was short, keep the digest short.

After generating, offer to save it: ask the user if they want it written to .vibe-learn/digests/ as a markdown file.
