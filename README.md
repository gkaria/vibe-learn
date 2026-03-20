# vibe-learn

**Learn as Claude builds.**

A learning companion for the vibe coding era. vibe-learn watches what Claude Code does during a session and helps you understand what was built, why, and how — at your own pace.

---

## The Problem

Vibe coding is fast. Claude writes 15 files, refactors a module, installs three dependencies — and you hit "accept" on all of it. A week later you can't debug your own app because you never really understood what was built.

The faster AI gets at coding, the wider the gap between *what was built* and *what you understand*. vibe-learn closes that gap.

---

## How It Works

vibe-learn hooks into Claude Code's event system. As Claude works, a set of lightweight scripts silently observe and log every action — files created, commands run, patterns used. At the end of each response, you get a brief summary of what just happened.

```text
┌─────────────────────────────────────────────────────────┐
│                  CLAUDE CODE SESSION                     │
│                                                          │
│  SessionStart → UserPrompt → [Tool Use]* → Stop          │
│       ↓              ↓           ↓            ↓          │
│  [Bootstrap]    [Capture]   [Observe]    [Summarise]     │
└───────┬──────────────┬───────────┬────────────┬──────────┘
        ↓              ↓           ↓            ↓
┌─────────────────────────────────────────────────────────┐
│                 .vibe-learn/                              │
│                                                          │
│  session-log.jsonl   ← raw event stream (append-only)    │
│  session-meta.json   ← counters, timestamps              │
│  pause-summary.txt   ← "here's what just happened"       │
└─────────────────────────────────────────────────────────┘
```

**Hook lifecycle:**

| Hook | When it fires | What it does |
| ---- | ------------- | ------------ |
| `SessionStart` | When you open a project | Creates `.vibe-learn/`, rotates old logs |
| `UserPromptSubmit` | When you send a message | Logs your intent |
| `PostToolUse` | After each Write/Edit/Bash | Appends a JSONL entry (<50ms, sync) |
| `Stop` | After each Claude response | Writes a pause summary |

Everything in Phase 1 is mechanical — no AI, no API calls, no external services. Just a fast, reliable data pipeline.

---

## Installation

### Option 1: Claude Code Plugin (recommended)

> **Requires:** Claude Code with plugin support and `jq` installed.

```bash
# Install jq if you don't have it
brew install jq         # macOS
apt-get install jq      # Ubuntu/Debian

# Add vibe-learn as a Claude Code plugin
# (follow Claude Code's plugin installation instructions for your version)
```

Then add `vibe-learn` to your Claude Code plugins configuration pointing to this repo.

### Option 2: Manual Setup

1. Clone this repo:

   ```bash
   git clone https://github.com/gaurangkaria/vibe-learn.git
   cd vibe-learn
   ```

2. Make the scripts executable:

   ```bash
   chmod +x scripts/*.sh
   ```

3. Add the hooks to your project's `.claude/settings.json`:

   ```json
   {
     "hooks": {
       "SessionStart": [
         {"hooks": [{"type": "command", "command": "/path/to/vibe-learn/scripts/bootstrap.sh"}]}
       ],
       "UserPromptSubmit": [
         {"hooks": [{"type": "command", "command": "/path/to/vibe-learn/scripts/capture-prompt.sh"}]}
       ],
       "PostToolUse": [
         {"matcher": "Write|Edit|MultiEdit|Bash", "hooks": [{"type": "command", "command": "/path/to/vibe-learn/scripts/observe.sh"}]}
       ],
       "Stop": [
         {"hooks": [{"type": "command", "command": "/path/to/vibe-learn/scripts/pause-summary.sh"}]}
       ]
     }
   }
   ```

---

## Usage

Once installed, vibe-learn runs silently in the background. You don't need to do anything differently.

**What you'll see:**

- After each Claude response, a brief pause summary appears in the terminal showing what just happened
- A `.vibe-learn/` directory appears in your project root

**What gets created:**

```text
your-project/
└── .vibe-learn/
    ├── session-log.jsonl        ← raw event log (one JSON entry per line)
    ├── session-log.prev.jsonl   ← previous session's log (kept as backup)
    ├── session-meta.json        ← session stats and config
    └── pause-summary.txt        ← last pause summary
```

**Reading the log:**

```bash
# Watch events in real-time
tail -f .vibe-learn/session-log.jsonl

# Count events
wc -l .vibe-learn/session-log.jsonl

# See all files Claude created
jq 'select(.tool=="Write")' .vibe-learn/session-log.jsonl

# See all bash commands run
jq 'select(.tool=="Bash") | .command' .vibe-learn/session-log.jsonl
```

**Add `.vibe-learn/` to your `.gitignore`** — you probably don't want to commit session logs:

```text
# .gitignore
.vibe-learn/
```

---

## Configuration

Edit `config/defaults.json` to adjust behaviour:

```json
{
  "log_dir": ".vibe-learn",
  "max_log_size_mb": 10,
  "rotate_on_session_start": true,
  "pause_summary_max_lines": 20,
  "capture_prompts": true,
  "narration_enabled": false,
  "digest_on_end": false
}
```

| Option | Default | Description |
| ------ | ------- | ----------- |
| `log_dir` | `.vibe-learn` | Where to store logs (relative to project root) |
| `max_log_size_mb` | `10` | Max log file size before rotation |
| `rotate_on_session_start` | `true` | Keep previous log as `.prev.jsonl` on new session |
| `pause_summary_max_lines` | `20` | Max lines in the pause summary |
| `capture_prompts` | `true` | Log your messages (disable for privacy) |
| `narration_enabled` | `true` | Show learning notes after each Claude response |
| `digest_min_events` | `3` | Minimum events before `/digest` generates a report |

---

## Phase 2: Inline Learning Notes

After every Claude response, vibe-learn automatically surfaces a short learning block — decisions made, patterns used, concepts worth understanding. No API key needed; Claude itself generates these using the session log it already has in context.

Example of what appears after a response:

```text
📘 vibe-learn:
• Created JWT middleware — this is the "gatekeeper" pattern: one central place
  that checks auth before any route handler runs, rather than checking in each route
• Chose jsonwebtoken over alternatives because it's the most widely-used library
  for this in the Node ecosystem — good default for learning
• The bcrypt rounds=10 setting is a deliberate trade-off: more rounds = more secure
  but slower login. 10 is the industry standard default
```

This works for **foreground sessions** — notes appear inline as Claude works.

For **background agents**, events are captured to `.vibe-learn/session-log.jsonl` and you can surface them on demand using the commands below.

---

## Phase 3 & 4: Slash Commands

Three commands are available once vibe-learn is installed:

### `/narrate`

Explains the most recent actions from the session log in plain language. Good for catching up after a burst of activity.

### `/digest`

Generates a full structured learning report for the session:

- **What Was Built** — plain-language summary
- **Key Decisions** — why Claude made specific choices
- **Patterns Used** — techniques and concepts from the code
- **Things to Study** — a checklist of topics to explore further

Optionally saves to `.vibe-learn/digests/` as a markdown file.

### `/learn <question>`

Ask anything about what was built, grounded in the actual session log:

```text
/learn why did Claude use middleware here?
/learn what does the auth flow do?
/learn explain the database connection setup
```

Claude reads the session log and relevant source files to answer — not generic explanations, but answers about your actual code.

---

## Roadmap

- **Phase 5:** Cross-session learning history, difficulty level adaptation, plugin registry publishing

---

## Testing

Test each script by piping sample JSON to stdin:

```bash
# Make scripts executable first
chmod +x scripts/*.sh

# Test bootstrap (creates .vibe-learn/ in /tmp/test-vl)
echo '{"session_id":"test123","cwd":"/tmp/test-vl"}' | bash scripts/bootstrap.sh
ls /tmp/test-vl/.vibe-learn/
cat /tmp/test-vl/.vibe-learn/session-meta.json

# Test observe (logs a Write event)
echo '{"cwd":"/tmp/test-vl","tool_name":"Write","tool_input":{"file_path":"src/app.ts"},"tool_response":{}}' | bash scripts/observe.sh
cat /tmp/test-vl/.vibe-learn/session-log.jsonl

# Test observe (logs a Bash event)
echo '{"cwd":"/tmp/test-vl","tool_name":"Bash","tool_input":{"command":"npm install express"},"tool_response":{"exit_code":0}}' | bash scripts/observe.sh
cat /tmp/test-vl/.vibe-learn/session-log.jsonl

# Test capture-prompt
echo '{"cwd":"/tmp/test-vl","prompt":"Build me an Express API with auth"}' | bash scripts/capture-prompt.sh
cat /tmp/test-vl/.vibe-learn/session-log.jsonl

# Test pause-summary (requires log entries from above tests)
echo '{"cwd":"/tmp/test-vl"}' | bash scripts/pause-summary.sh
cat /tmp/test-vl/.vibe-learn/pause-summary.txt

# Clean up
rm -rf /tmp/test-vl
```

---

## Requirements

- **Bash** — POSIX-compatible (the scripts use `#!/bin/bash`)
- **jq** — JSON processing. Install with `brew install jq` (macOS) or `apt-get install jq` (Linux)
- **Claude Code** — with hooks support

---

## Contributing

Contributions are welcome. This is an early-stage project — the best contributions right now are:

- Bug reports and edge cases in the Phase 1 scripts
- Ideas for Phase 2 narration prompts
- Testing on different OS/shell environments

Please open an issue before submitting a pull request for anything significant.

---

## License

MIT — see [LICENSE](LICENSE).

Copyright © 2026 Gaurang Karia.
