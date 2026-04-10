## Vibe Learn

This project has vibe-learn installed. Session activity (file writes, edits, bash commands) is logged to `.vibe-learn/session-log.jsonl` automatically via hooks.

### Slash Commands
- `/learn` — explain what just happened, or answer a specific question grounded in the session log
- `/learn [question]` — e.g. `/learn why did you use middleware here?`
- `/digest` — generate a structured learning report (what was built, key decisions, patterns, topics to study)

**Obsidian integration** (requires vault config — prompted on first use):

- `/learn obsidian` — save a learn note to your Obsidian vault
- `/learn obsidian [question]` — answer a question and save to vault
- `/learn obsidian:recall [topic]` — search vault for past learnings on a topic (read-only)
- `/digest obsidian` — save session digest to your Obsidian vault
- `/digest obsidian:recall` — digest enriched with connections to past sessions on this project

### Session Data
- `.vibe-learn/session-log.jsonl` — append-only event stream
- `.vibe-learn/session-meta.json` — session counters and timestamps
- `.vibe-learn/pause-summary.txt` — last pause summary (injected on next session start)

After each response where changes were made, a pause summary is generated showing what just happened. Suggest `/learn` or `/digest` when the user might benefit from understanding recent changes.
