# vibe-learn

**Learn as your AI coding assistant builds.**

You can outsource your thinking, but you can't outsource your understanding.

A learning companion for the vibe coding era. vibe-learn watches what Claude Code or Codex App/CLI does during a session and helps you understand what was built, why, and how — at your own pace.

---

## The Problem

Vibe coding is fast. Your assistant writes 15 files, refactors a module, installs three dependencies — and you hit "accept" on all of it. A week later you can't debug your own app because you never really understood what was built.

The faster AI gets at coding, the wider the gap between *what was built* and *what you understand*. vibe-learn exists because you can outsource your thinking, but you can't outsource your understanding.

---

## How It Works

vibe-learn hooks into your AI assistant's event system. As the AI works, lightweight scripts silently observe and log every action — files created, commands run, patterns used. At natural pause points, a summary of what just happened is written to disk and injected into the assistant context where the host supports it.

```text
┌─────────────────────────────────────────────────────────┐
│                    AI CODING SESSION                     │
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
| `PostToolUse` | After each Write/Edit/MultiEdit/Bash/apply_patch | Appends JSONL entries (<50ms, sync) |
| `Stop` | After each AI response | Writes a pause summary and injects it where supported |

No AI, no API calls, no external services. Just a fast, reliable data pipeline.

---

## Installation

### Quick Install (one line)

```bash
curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
```

This installs vibe-learn to `~/.vibe-learn/` and **automatically registers the hooks globally** for whichever assistants are installed on your machine (Claude Code, Codex App/CLI, or both). It copies Claude slash commands, Codex prompt fallbacks, and the global Codex `vibe-learn` skill when Codex is detected.

To target a specific assistant: `bash setup.sh --assistant=codex` or `--assistant=claude-code`. To explicitly configure every detected assistant, use `--assistant=all`.

**Requires:** `jq` — install with `brew install jq` (macOS) or `apt-get install jq` (Linux).

**Updating:** re-run the same curl command to update to the latest version.

### Per-project install (optional)

If you want vibe-learn active only in a specific project, or want to share the config with your team via version control:

```bash
vibe-learn install
# or, if ~/.local/bin isn't in your PATH yet:
~/.vibe-learn/scripts/install.sh
```

This installs all relevant assistants by default and adds `.vibe-learn/` to `.gitignore`.

Detection order:

- Existing `.claude/` installs Claude Code support.
- Existing `.codex/` installs Codex support.
- If both directories exist, both are installed.
- If neither directory exists, installed tools/configs are detected (`claude` or `~/.claude`, `codex` or `~/.codex`).
- If no assistant is detected, vibe-learn falls back to Claude Code for backward compatibility.

Use `--assistant=codex` for Codex-only setup, `--assistant=claude-code` for Claude-only setup, or `--assistant=all` to install all detected/relevant assistants. Useful when you don't want global hooks, or when different projects need different settings.

### Codex App setup choices

For Codex App users, global setup is the smoothest path because it installs the `vibe-learn` skill:

```bash
curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
```

After global setup, use vibe-learn in Codex by typing natural-language requests like:

```text
Use vibe-learn to learn what happened.
Use vibe-learn to create a digest of this session.
Use vibe-learn to answer: why did we add this auth middleware?
```

Project-only Codex installs are still supported:

```bash
vibe-learn install --assistant=codex
```

Project-only installs add hooks and prompt fallbacks under `.codex/`, but they do not install the global Codex skill. In that case, ask Codex:

```text
Read .codex/prompts/learn.md and follow it.
Read .codex/prompts/digest.md and follow it.
```

### Install via MCS (alternative)

If you use [MCS](https://github.com/mcs-cli/mcs) to manage your Claude Code configuration:

```bash
mcs pack add gkaria/vibe-learn
mcs sync
```

This installs all hooks, slash commands, and dependencies automatically into any project.

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

For Codex, global setup installs `~/.codex/skills/vibe-learn/SKILL.md` plus prompt fallbacks at `~/.codex/prompts/learn.md` and `~/.codex/prompts/digest.md`. Project Codex installs keep prompt fallbacks in `.codex/prompts/`.

Manual Codex hook setup goes in `~/.codex/config.toml` (global) or `.codex/config.toml` (project):

```toml
[features]
codex_hooks = true

[hooks]

[[hooks.SessionStart]]
[[hooks.SessionStart.hooks]]
type = "command"
command = "/path/to/vibe-learn/scripts/bootstrap.sh"

[[hooks.UserPromptSubmit]]
[[hooks.UserPromptSubmit.hooks]]
type = "command"
command = "/path/to/vibe-learn/scripts/capture-prompt.sh"

[[hooks.PostToolUse]]
matcher = "^(Bash|apply_patch)$"
[[hooks.PostToolUse.hooks]]
type = "command"
command = "/path/to/vibe-learn/scripts/observe.sh"

[[hooks.Stop]]
[[hooks.Stop.hooks]]
type = "command"
command = "/path/to/vibe-learn/scripts/pause-summary.sh"
```

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

In real use, you don't run any of this manually — Claude Code or Codex triggers the hooks automatically. This just shows what's happening behind the scenes.

---

## Before vs After

**Without vibe-learn** — your assistant writes 12 files, installs 4 packages, refactors a module. You hit "accept" on everything. A week later:

```text
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

Use /learn in Claude Code, or ask Codex to use the vibe-learn skill, to understand any of these decisions. Use /digest in Claude Code, or ask Codex for a vibe-learn digest, for a full session report.
```

Then ask `/learn why did we add middleware?` in Claude Code, or ask Codex "Use vibe-learn to explain why middleware was used." Run `/digest` in Claude Code, or ask Codex "Use vibe-learn to create a digest" for a full breakdown of what was built, key decisions, patterns used, and topics to study next.

---

## Usage

Once installed, vibe-learn runs silently. You don't need to do anything differently — just use Claude Code or Codex as normal.

**After each response**, if the assistant made changes, vibe-learn writes a pause summary. In Claude Code, that summary can appear automatically. In Codex App, ask the skill to explain or digest the session:

```text
Use vibe-learn to explain what just happened.
```

Example pause summary:

```text
⏸ vibe-learn — what just happened:
Goal: add JWT auth middleware

  ✦ Created src/middleware/auth.ts
  ✦ Edited src/routes/user.ts
  ✦ Ran: npm install jsonwebtoken

Use /learn in Claude Code, or ask Codex to use the vibe-learn skill, to understand any of these decisions. Use /digest in Claude Code, or ask Codex for a vibe-learn digest, for a full session report.
```

### Claude Code commands

Claude Code supports custom slash commands, so these are available mid-session or at the end:

### `/learn`

No arguments — explains the most recent actions: what was built, decisions made, patterns used.

With a question — answers it grounded in your actual session and code:

```text
/learn why did we add middleware here?
/learn what does the auth flow do?
/learn explain the database connection setup
```

### `/digest`

Generates a full structured learning report for the session:

- **What Was Built** — plain-language summary
- **Key Decisions** — why the assistant made specific choices
- **Patterns Used** — techniques and concepts from the code
- **Things to Study** — a checklist of topics to explore further

Optionally saves to `.vibe-learn/digests/` as a markdown file.

### Codex App usage

Codex App does not support custom `/learn` or `/digest` slash commands. Use the global skill when installed:

```text
Use vibe-learn to learn what happened.
Use vibe-learn to answer: why did we add middleware?
Use vibe-learn to create a digest.
Use vibe-learn to save this learn note to Obsidian.
Use vibe-learn to recall past Obsidian notes about authentication.
```

Common Codex examples:

| What you want | Type this in Codex |
| ------------- | ------------------ |
| Recent explanation | `Use vibe-learn to explain what just happened.` |
| Specific question | `Use vibe-learn to answer: why did we install bcrypt?` |
| Full report | `Use vibe-learn to create a digest of this session.` |
| Save learn note | `Use vibe-learn to save this learn note to Obsidian.` |
| Save digest | `Use vibe-learn to create a digest and save it to Obsidian.` |
| Recall a topic | `Use vibe-learn to recall past Obsidian notes about authentication.` |

If the global skill is not installed, project installs include prompt-file fallbacks:

```text
Read .codex/prompts/learn.md and follow it.
Read .codex/prompts/digest.md and follow it.
Read .codex/prompts/learn.md and follow it for obsidian:recall authentication.
```

### Obsidian integration

Save your learnings to an [Obsidian](https://obsidian.md) vault and recall them across sessions:

| What it does | Claude Code | Codex App |
| ------------ | ----------- | --------- |
| Save a learn note to your vault | `/learn obsidian` | `Use vibe-learn to save this learn note to Obsidian.` |
| Answer a question and save to vault | `/learn obsidian why did we add middleware?` | `Use vibe-learn to answer why we added middleware and save it to Obsidian.` |
| Search vault for past learnings on a topic | `/learn obsidian:recall authentication` | `Use vibe-learn to recall past Obsidian notes about authentication.` |
| Save session digest to your vault | `/digest obsidian` | `Use vibe-learn to create a digest and save it to Obsidian.` |
| Digest enriched with previous sessions | `/digest obsidian:recall` | `Use vibe-learn to create a digest with Obsidian recall.` |

On first use, Claude or Codex asks for your vault path and offers to save the config to `.vibe-learn/obsidian.json`. See the [Obsidian Integration](#obsidian-integration) section below for setup details.

---

## What Gets Created

```text
your-project/
└── .vibe-learn/
    ├── session-log.jsonl        ← raw event log (one JSON entry per line)
    ├── session-log.prev.jsonl   ← previous session's log (kept as backup)
    ├── session-meta.json        ← session stats and config
    ├── pause-summary.txt        ← last pause summary
    └── digests/                 ← saved digest reports (if you choose to save)
```

**Useful log queries:**

```bash
# Watch events in real-time
tail -f .vibe-learn/session-log.jsonl

# See all files the assistant created
jq 'select(.tool=="Write")' .vibe-learn/session-log.jsonl

# See all bash commands run
jq 'select(.tool=="Bash") | .command' .vibe-learn/session-log.jsonl
```

---

---

## Obsidian Integration

vibe-learn can write your session learnings into an Obsidian vault as tagged, frontmatter-rich notes, and recall past learnings by searching across sessions.

### Setup

No pre-configuration needed. On your first `/learn obsidian` or `/digest obsidian` command in Claude Code, or the equivalent Codex skill request, the assistant will ask for your vault path and offer to save the config to `.vibe-learn/obsidian.json`.

You can also create the config manually:

```json
{
  "vault_path": "/Users/me/MyVault",
  "subfolder": "Development/Sessions",
  "tags": ["vibe-learn"],
  "link_style": "wikilink",
  "include_project_tag": true,
  "note_naming": "{date}-{project}"
}
```

Save to `.vibe-learn/obsidian.json` (project-level) or `~/.vibe-learn/obsidian.json` (global fallback). All options and their defaults are documented in `config/obsidian-defaults.json`.

### Writing notes

`/learn obsidian` and `/digest obsidian` in Claude Code, or equivalent Codex skill requests, write a formatted markdown note to `<vault_path>/<subfolder>/`. Notes include YAML frontmatter (`date`, `project`, `tags`, `type`) so they work with Obsidian's Dataview plugin and tag filtering.

### Recalling past learnings

`/learn obsidian:recall <topic>` in Claude Code, or "Use vibe-learn to recall past Obsidian notes about <topic>" in Codex, searches your vault for notes matching the topic and synthesizes a cross-session summary — which sessions touched it, key decisions, recurring patterns, and unchecked study items. Nothing is written.

`/digest obsidian:recall` in Claude Code, or "Use vibe-learn to create a digest with Obsidian recall" in Codex, goes further: it reads previous session notes for the **same project**, generates the full session digest, and enriches it with a **"Connections to Previous Work"** section showing how the current session builds on past work.

---

## Configuration

`config/defaults.json` contains the intended configuration surface:

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

Current behavior (important): hook scripts currently implement default behavior directly, and do not yet read/apply every key from `config/defaults.json`.

| Option | Default | Runtime Status | Current Behavior |
| ------ | ------- | -------------- | ---------------- |
| `log_dir` | `.vibe-learn` | `active (fixed)` | Scripts currently write to `.vibe-learn` directly. |
| `rotate_on_session_start` | `true` | `active (fixed)` | Session log rotation currently always runs on `SessionStart`. |
| `capture_prompts` | `true` | `not yet enforced` | `capture-prompt.sh` currently logs prompts unconditionally. |
| `pause_summary_max_lines` | `20` | `not yet enforced` | `pause-summary.sh` currently does not cap lines via config. |
| `max_log_size_mb` | `10` | `not yet enforced` | No size-based rotation logic is currently applied. |
| `digest_min_events` | `3` | `not yet enforced` | Digest prompt files currently do not gate on event count. |

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

100 tests covering all four hook scripts, the Claude Code installer, the Codex installer, assistant-aware project install defaults, and the global setup.

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
- **Claude Code** or **Codex App/CLI** — with hooks support

---

## Roadmap

Recent releases:

- **v0.5.0: Obsidian integration** — save learn notes and session digests to your vault, then recall past learnings with `obsidian:recall`.
- **v0.5.5: Multi-assistant support** — Claude Code and Codex App/CLI support, assistant auto-detection at install time, and a generic adapter layout for future assistants.

Future ideas:

- **Better Codex experience** — keep improving the Codex skill and prompt fallback flow so `Use vibe-learn...` feels natural in Codex App.
- **Session-to-session links** — when saving a new Obsidian note, automatically link it to related previous notes so learning compounds over time.
- **Topic index notes** — generate optional index pages for recurring topics like authentication, testing, React, or database migrations. These would act as learning hubs inside Obsidian.
- **Obsidian Dataview examples** — provide copy-paste Dataview snippets for browsing vibe-learn notes by project, topic, date, or unchecked study items.
- **Daily notes integration** — optionally append a short session summary to your Obsidian daily note, so coding learnings show up in your daily journal.
- **Auto-save options** — let users choose whether digests should be saved automatically at the end of a session instead of only on request.

These are directions, not promises. The core mission stays the same: make AI-assisted work easier to understand, remember, and build on.

---

## Contributing

Contributions welcome. Best contributions right now:

- Bug reports and edge cases in the hook scripts
- Testing on different OS/shell environments
- Ideas for improving the pause summary, slash commands, Codex skill, or prompt fallbacks

Please open an issue before submitting a pull request for anything significant.

---

## License

MIT — see [LICENSE](LICENSE).

Copyright © 2026 Gaurang Karia.
