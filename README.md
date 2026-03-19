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

```
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
|------|--------------|--------------|
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
     "hooks": [
       {
         "event": "SessionStart",
         "command": "/path/to/vibe-learn/scripts/bootstrap.sh"
       },
       {
         "event": "UserPromptSubmit",
         "command": "/path/to/vibe-learn/scripts/capture-prompt.sh"
       },
       {
         "event": "PostToolUse",
         "matcher": "Write|Edit|MultiEdit|Bash",
         "command": "/path/to/vibe-learn/scripts/observe.sh"
       },
       {
         "event": "Stop",
         "command": "/path/to/vibe-learn/scripts/pause-summary.sh"
       }
     ]
   }
   ```

---

## Usage

Once installed, vibe-learn runs silently in the background. You don't need to do anything differently.

**What you'll see:**
- After each Claude response, a brief pause summary appears in the terminal showing what just happened
- A `.vibe-learn/` directory appears in your project root

**What gets created:**
```
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
```
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
|--------|---------|-------------|
| `log_dir` | `.vibe-learn` | Where to store logs (relative to project root) |
| `max_log_size_mb` | `10` | Max log file size before rotation |
| `rotate_on_session_start` | `true` | Keep previous log as `.prev.jsonl` on new session |
| `pause_summary_max_lines` | `20` | Max lines in the pause summary |
| `capture_prompts` | `true` | Log your messages (disable for privacy) |
| `narration_enabled` | `false` | Phase 2 feature — real-time AI explanations |
| `digest_on_end` | `false` | Phase 3 feature — AI-powered session digest |

---

## Roadmap

vibe-learn is built in phases. Phase 1 is the silent observer — the foundation everything else builds on.

### Phase 2: The Narrator
Real-time explanations as Claude codes. Run `tail -f .vibe-learn/narration.log` in a split terminal and watch one-sentence explanations appear for every action Claude takes.

### Phase 3: The Digest
Post-session learning reports. After each session, get a structured markdown document covering what was built, why key decisions were made, patterns to study, and next steps. See `examples/sample-digest.md` for a preview.

### Phase 4: The Query Interface
Ask questions about what Claude built. A `/learn` command (or subagent) lets you ask "why did Claude use the repository pattern here?" and get answers grounded in your actual session log and codebase.

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
