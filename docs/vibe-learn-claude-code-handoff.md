# Claude Code Handoff Prompt — vibe-learn Phase 1

Copy everything below the line into Claude Code after initialising the repo.

---

## Setup (run these first in your terminal)

```bash
mkdir vibe-learn && cd vibe-learn
git init
```

## Prompt for Claude Code

```
I'm building an open-source Claude Code plugin called "vibe-learn" — a learning companion for vibe coders. It watches what Claude Code does during a session and helps the human understand what was built, why, and how.

This is Phase 1: the foundation — the silent observer that logs everything Claude does. No AI summarisation yet, just the raw data pipeline and a mechanical summary.

Read the product spec below carefully, then build the full Phase 1.

---

## What vibe-learn is

vibe-learn is for the HUMAN, not for Claude. When someone vibe codes, Claude builds fast — 15 files, refactors, dependencies, error handling — and the human hits "accept" without really understanding what was built. vibe-learn closes that gap by capturing what Claude did and making it available for learning later.

## What to build (Phase 1 only)

### 1. Repo structure

```
vibe-learn/
├── README.md                         # Project overview, installation, usage, roadmap
├── LICENSE                           # MIT
├── scripts/
│   ├── bootstrap.sh                  # SessionStart hook
│   ├── observe.sh                    # PostToolUse hook (sync, fast, < 50ms)
│   ├── capture-prompt.sh             # UserPromptSubmit hook
│   ├── pause-summary.sh             # Stop hook (mechanical summary, no API calls)
│   ├── setup.sh                      # Global installer (auto-detects Claude Code / Codex)
│   └── install.sh                    # Per-project installer (dispatcher)
├── adapters/
│   ├── claude-code/
│   │   ├── hooks.json                # Hook registration template (${CLAUDE_PLUGIN_ROOT})
│   │   ├── commands/learn.md         # /learn slash command
│   │   ├── commands/digest.md        # /digest slash command
│   │   └── install.sh               # Registers hooks in ~/.claude/settings.json
│   └── codex/
│       ├── hooks.toml                # Hook registration template (TOML)
│       ├── prompts/learn.md          # /prompts:learn instruction file
│       ├── prompts/digest.md         # /prompts:digest instruction file
│       └── install.sh               # Registers hooks in ~/.codex/config.toml
├── config/
│   └── defaults.json                 # Default configuration
└── examples/
    ├── sample-session-log.jsonl      # Example of what the raw log looks like
    ├── sample-pause-summary.txt      # Example of a pause summary
    └── sample-digest.md              # Example of what /digest produces
```

### 2. Hook registration (per-assistant adapter)

Use ${CLAUDE_PLUGIN_ROOT} for all script paths in Claude Code hooks. Register these hooks:

| Hook Event         | Matcher                        | Script               | Async? |
|--------------------|--------------------------------|----------------------|--------|
| SessionStart       | (none)                         | bootstrap.sh         | No     |
| UserPromptSubmit   | (none)                         | capture-prompt.sh    | No     |
| PostToolUse        | Write\|Edit\|MultiEdit\|Bash   | observe.sh           | No     |
| Stop               | (none)                         | pause-summary.sh     | No     |

### 3. Scripts

All scripts use bash + jq only. No external dependencies. No API calls.

**bootstrap.sh** (SessionStart):
- Create .vibe-learn/ directory in the project root ($CWD from stdin JSON)
- Rotate previous session log (keep one backup as session-log.prev.jsonl)
- Initialise session-meta.json with session_id, started_at, event_count: 0
- If a previous pause summary exists, inject it via hookSpecificOutput.additionalContext so Claude has prior context
- Output valid JSON to stdout for context injection, OR exit 0 silently if no prior context

**observe.sh** (PostToolUse, sync):
- Read JSON from stdin
- Extract: tool_name, tool_input (file_path or command), tool_response (exit_code for Bash), timestamp
- Build a compact JSONL entry with fields: timestamp, event ("tool_use"), tool, file/command, action (created/edited/ran), context (line count for writes, exit_code for bash)
- Append to .vibe-learn/session-log.jsonl
- Increment event_count in session-meta.json
- CRITICAL: Must be fast. No network calls. Minimal processing. Output nothing to stdout.
- Exit 0 silently

**capture-prompt.sh** (UserPromptSubmit):
- Read JSON from stdin
- Extract the user's prompt text
- Append a JSONL entry with: timestamp, event ("user_prompt"), prompt (truncated to 500 chars)
- Exit 0 silently (do not block the prompt)

**pause-summary.sh** (Stop):
- Read .vibe-learn/session-log.jsonl
- Generate a mechanical summary (no AI): count of events, files created/modified, bash commands run, failures, last 5 actions
- Write summary to .vibe-learn/pause-summary.txt (human-readable, max 20 lines)
- Also output the summary via hookSpecificOutput.additionalContext so Claude is aware
- If session-log.jsonl doesn't exist or is empty, exit 0 silently

### 4. Data format

Session log entries (one per line in JSONL):

```json
{"timestamp":"2026-03-17T14:32:05Z","event":"tool_use","tool":"Write","file":"src/middleware/auth.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:32:01Z","event":"user_prompt","prompt":"Add JWT authentication to the API"}
{"timestamp":"2026-03-17T14:33:00Z","event":"tool_use","tool":"Bash","command":"npm install jsonwebtoken","action":"ran","context":{"exit_code":0}}
{"timestamp":"2026-03-17T14:34:12Z","event":"tool_use","tool":"Edit","file":"src/index.ts","action":"edited","context":{}}
```

Session metadata:

```json
{
  "session_id": "from-stdin-json",
  "started_at": "2026-03-17T14:32:00Z",
  "event_count": 47,
  "config": {
    "log_dir": ".vibe-learn"
  }
}
```

### 5. README.md

Write a proper README with:

- **What it is**: One-paragraph description — a learning companion for vibe coders
- **The problem**: Vibe coding gives you output without understanding
- **How it works**: Architecture diagram (ASCII), hook lifecycle explanation
- **Installation**: As a Claude Code plugin (primary) AND manual setup (secondary)
  - Plugin: explain how to install a Claude Code plugin from a git repo
  - Manual: copy scripts, add to .claude/settings.json
- **Usage**: What happens when you install it, where logs appear, how to read them
- **Configuration**: What's configurable in defaults.json
- **Roadmap**: Phase 3 (cross-session history, difficulty levels, plugin registry publishing)
- **Contributing**: Standard open-source contributing guide
- **Licence**: MIT

Tone: Clear, warm, zero jargon. Remember this is for people who might be new to coding. The README should be welcoming, not intimidating.

### 6. LICENSE

MIT, copyright Gaurang Karia 2026.

### 7. defaults.json

```json
{
  "log_dir": ".vibe-learn",
  "max_log_size_mb": 10,
  "rotate_on_session_start": true,
  "pause_summary_max_lines": 20,
  "capture_prompts": true,
  "digest_min_events": 3
}
```

digest_min_events controls when `/digest` will generate a report (avoids trivially small sessions).

### 8. Example files

Create realistic example files in examples/ that show what the output looks like for a typical session where Claude builds a simple Express API with authentication. Make them feel real and useful — someone should be able to look at these and immediately understand what vibe-learn produces.

## Important constraints

- All scripts must be POSIX-compatible bash (#!/bin/bash, not #!/usr/bin/env bash on macOS)
- Only dependency is jq (document this in README)
- Every script must handle missing files/directories gracefully (don't crash if .vibe-learn/ doesn't exist yet)
- The observe.sh script MUST be fast — it runs synchronously on every tool use. No sleeps, no network, minimal disk I/O.
- Use ${CLAUDE_PLUGIN_ROOT} in hooks.json for all paths
- Add .vibe-learn/ to the .gitignore example in the README (users shouldn't commit their logs)
- Scripts should use the CWD from the stdin JSON (field: cwd), not assume the working directory

## Quality bar

- Every script should be tested by piping sample JSON to stdin: echo '{"session_id":"test","cwd":"/tmp/test","tool_name":"Write","tool_input":{"file_path":"test.ts"}}' | ./scripts/observe.sh
- Include these test commands in the README under a "Testing" section
- The README should be good enough that someone can go from zero to working setup in under 5 minutes
```
