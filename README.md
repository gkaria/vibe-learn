# vibe-learn

**Learn as Claude builds.**

A learning companion for the vibe coding era. vibe-learn watches what Claude Code does during a session and helps you understand what was built, why, and how — at your own pace.

---

## The Problem

Vibe coding is fast. Claude writes 15 files, refactors a module, installs three dependencies — and you hit "accept" on all of it. A week later you can't debug your own app because you never really understood what was built.

The faster AI gets at coding, the wider the gap between *what was built* and *what you understand*. vibe-learn closes that gap.

---

## How It Works

vibe-learn hooks into Claude Code's event system. As Claude works, lightweight scripts silently observe and log every action — files created, commands run, patterns used. After each response, a summary of what just happened is injected into Claude's context so it can surface it naturally.

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
| `Stop` | After each Claude response | Writes and injects a pause summary |

No AI, no API calls, no external services. Just a fast, reliable data pipeline.

---

## Installation

### Quick Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
```

This installs vibe-learn to `~/.vibe-learn/` and **automatically registers the hooks globally** in `~/.claude/settings.json`. That's it — vibe-learn is now active in every Claude Code session on your machine, across all projects.

It also copies `/learn` and `/digest` to `~/.claude/commands/` so the slash commands are available everywhere.

**Requires:** `jq` — install with `brew install jq` (macOS) or `apt-get install jq` (Linux).

**Updating:** re-run the same curl command to update to the latest version.

### Per-project install (optional)

If you want vibe-learn active only in a specific project, or want to share the config with your team via version control:

```bash
vibe-learn install
# or, if ~/.local/bin isn't in your PATH yet:
~/.vibe-learn/scripts/install.sh
```

This writes hooks into the project's `.claude/settings.local.json` and adds `.vibe-learn/` to `.gitignore`. Useful when you don't want global hooks, or when different projects need different settings.

### For contributors / local development

```bash
git clone https://github.com/gkaria/vibe-learn.git

# Register globally from a local clone (no network)
bash /path/to/vibe-learn/scripts/setup.sh --local

# Or wire into a specific project only
bash /path/to/vibe-learn/scripts/install.sh /path/to/your/project
```

### Manual Setup

Add to `~/.claude/settings.json` (global) or your project's `.claude/settings.local.json`:

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

Copy `.claude/commands/learn.md` and `.claude/commands/digest.md` into `~/.claude/commands/` (global) or your project's `.claude/commands/`.

---

## Quick Demo (2 minutes)

After installing, try this to see vibe-learn in action:

```bash
# 1. Create a test project (no install step needed — hooks are global)
mkdir /tmp/demo-app

# 2. Simulate a session — bootstrap, then a few tool events
echo '{"session_id":"demo","cwd":"/tmp/demo-app"}' | bash ~/.vibe-learn/scripts/bootstrap.sh

echo '{"cwd":"/tmp/demo-app","prompt":"Build me a REST API with auth"}' \
  | bash ~/.vibe-learn/scripts/capture-prompt.sh

echo '{"cwd":"/tmp/demo-app","tool_name":"Write","tool_input":{"file_path":"src/app.ts"},"tool_response":{}}' \
  | bash ~/.vibe-learn/scripts/observe.sh

echo '{"cwd":"/tmp/demo-app","tool_name":"Bash","tool_input":{"command":"npm install express"},"tool_response":{"exit_code":0}}' \
  | bash ~/.vibe-learn/scripts/observe.sh

# 3. Generate a pause summary
echo '{"cwd":"/tmp/demo-app"}' | bash ~/.vibe-learn/scripts/pause-summary.sh

# 4. See what vibe-learn captured
cat /tmp/demo-app/.vibe-learn/session-log.jsonl | jq .
cat /tmp/demo-app/.vibe-learn/pause-summary.txt
```

In real use, you don't run any of this manually — Claude Code triggers the hooks automatically. This just shows what's happening behind the scenes.

---

## Before vs After

**Without vibe-learn** — Claude writes 12 files, installs 4 packages, refactors a module. You hit "accept" on everything. A week later:

```
You: "Wait, why is there a middleware folder?"
You: "What does this bcrypt thing do?"
You: "Did I even need all these dependencies?"
```

**With vibe-learn** — the same session, but now you have a trail:

```text
⏸ vibe-learn — what just happened:
Goal: Build a REST API with JWT authentication

  ✦ Created src/index.ts
  ✦ Created src/middleware/auth.ts
  ✦ Created src/routes/auth.ts
  ✦ Ran: npm install express jsonwebtoken bcryptjs
  ✦ Edited src/index.ts
  ✦ Ran: npx tsc --noEmit ✓

Use /learn to understand any of these decisions, or /digest for a full session report.
```

Then ask `/learn why did Claude use middleware?` or run `/digest` for a full breakdown of what was built, key decisions, patterns used, and topics to study next.

---

## Usage

Once installed, vibe-learn runs silently. You don't need to do anything differently — just use Claude Code as normal.

**After each response**, if Claude made changes, a summary appears showing what just happened:

```text
⏸ vibe-learn — what just happened:
Goal: add JWT auth middleware

  ✦ Created src/middleware/auth.ts
  ✦ Edited src/routes/user.ts
  ✦ Ran: npm install jsonwebtoken

Use /learn to understand any of these decisions, or /digest for a full session report.
```

**Slash commands** (available mid-session or at end):

### `/learn`

No arguments — explains the most recent actions: what was built, decisions made, patterns used.

With a question — answers it grounded in your actual session and code:

```text
/learn why did Claude use middleware here?
/learn what does the auth flow do?
/learn explain the database connection setup
```

### `/digest`

Generates a full structured learning report for the session:

- **What Was Built** — plain-language summary
- **Key Decisions** — why Claude made specific choices
- **Patterns Used** — techniques and concepts from the code
- **Things to Study** — a checklist of topics to explore further

Optionally saves to `.vibe-learn/digests/` as a markdown file.

---

## What Gets Created

```text
your-project/
└── .vibe-learn/
    ├── session-log.jsonl        ← raw event log (one JSON entry per line)
    ├── session-log.prev.jsonl   ← previous session's log (kept as backup)
    ├── session-meta.json        ← session stats and config
    ├── pause-summary.txt        ← last pause summary
    └── digests/                 ← saved /digest reports (if you choose to save)
```

**Useful log queries:**

```bash
# Watch events in real-time
tail -f .vibe-learn/session-log.jsonl

# See all files Claude created
jq 'select(.tool=="Write")' .vibe-learn/session-log.jsonl

# See all bash commands run
jq 'select(.tool=="Bash") | .command' .vibe-learn/session-log.jsonl
```

---

## Configuration

Edit `config/defaults.json`:

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

| Option | Default | Description |
| ------ | ------- | ----------- |
| `log_dir` | `.vibe-learn` | Where to store logs (relative to project root) |
| `max_log_size_mb` | `10` | Max log file size before rotation |
| `rotate_on_session_start` | `true` | Keep previous log as `.prev.jsonl` on new session |
| `pause_summary_max_lines` | `20` | Max lines in the pause summary |
| `capture_prompts` | `true` | Log your messages (disable for privacy) |
| `digest_min_events` | `3` | Minimum events before `/digest` generates a report |

---

## Testing

### Automated tests

The test suite uses [bats](https://github.com/bats-core/bats-core) (Bash Automated Testing System):

```bash
# Install bats
brew install bats-core          # macOS
apt-get install bats            # Linux

# Run all tests
bats tests/
```

49 tests covering all four hook scripts, the installer, and the global setup.

### Manual smoke test

```bash
chmod +x scripts/*.sh

# Test bootstrap
echo '{"session_id":"test123","cwd":"/tmp/test-vl"}' | bash scripts/bootstrap.sh
ls /tmp/test-vl/.vibe-learn/

# Test observe (Write event)
echo '{"cwd":"/tmp/test-vl","tool_name":"Write","tool_input":{"file_path":"src/app.ts"},"tool_response":{}}' | bash scripts/observe.sh
cat /tmp/test-vl/.vibe-learn/session-log.jsonl

# Test observe (Bash event)
echo '{"cwd":"/tmp/test-vl","tool_name":"Bash","tool_input":{"command":"npm install express"},"tool_response":{"exit_code":0}}' | bash scripts/observe.sh

# Test capture-prompt
echo '{"cwd":"/tmp/test-vl","prompt":"Build me an Express API with auth"}' | bash scripts/capture-prompt.sh

# Test pause-summary (outputs JSON with additionalContext for Stop hook)
echo '{"cwd":"/tmp/test-vl"}' | bash scripts/pause-summary.sh | jq .
cat /tmp/test-vl/.vibe-learn/pause-summary.txt

rm -rf /tmp/test-vl
```

---

## Requirements

- **Bash** — POSIX-compatible
- **jq** — JSON processing (`brew install jq` / `apt-get install jq`)
- **Claude Code** — with hooks support

---

## Roadmap

- **Phase 3:** Cross-session learning history, difficulty level adaptation, plugin registry publishing

---

## Contributing

Contributions welcome. Best contributions right now:

- Bug reports and edge cases in the hook scripts
- Testing on different OS/shell environments
- Ideas for improving the pause summary or slash command prompts

Please open an issue before submitting a pull request for anything significant.

---

## License

MIT — see [LICENSE](LICENSE).

Copyright © 2026 Gaurang Karia.
