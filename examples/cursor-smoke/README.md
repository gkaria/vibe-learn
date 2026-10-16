# Cursor smoke sample

Minimal Node HTTP app plus a replay script that drives vibe-learn the way Cursor does: install the Cursor adapter, feed Cursor-shaped hook payloads through `.cursor/hooks/vibe-learn.sh`, then assert a session log and pause summary appear.

This is mechanical verification (bash + jq). It does not start the Cursor IDE.

## Run

From the vibe-learn repo root:

```bash
bash examples/cursor-smoke/run-smoke.sh
```

Exit code `0` means install, hook replay, and assertions all passed. The script prints the commands it ran and the key artifacts under a temp project.

## What it covers

1. Project install via `adapters/cursor/install.sh` (hooks.json, shim, `/learn` / `/digest` / `/quiz` / `/explain` / `vibe-learn` skills).
2. A short Cursor turn: `sessionStart` → `beforeSubmitPrompt` → `afterFileEdit` (create + edit) → `postToolUse` (Shell) → `stop`.
3. Assertions on `.vibe-learn/session-log.jsonl`, `.vibe-learn/pause-summary.txt`, and `session-meta.json` (`harness: cursor`).
4. A read of the `/learn` skill so the path skills would use is present for Grok/Cursor plugin packaging evidence.
