# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**vibe-learn** is a Claude Code plugin that observes what Claude does during a development session and helps users understand what was built. It works by registering lifecycle hooks that capture tool use events (file writes, edits, bash commands) into an append-only JSONL session log, then surfaces summaries at natural pause points.

It requires no external API calls. Hooks are mechanical (bash + jq). The learning commands (`/learn` and `/digest`) leverage Claude's own context window to generate explanations and reports.

## How It Works

The plugin registers four Claude Code lifecycle hooks defined in `hooks.json`:

| Hook | Script | Trigger |
|------|--------|---------|
| `SessionStart` | `scripts/bootstrap.sh` | New Claude session opens |
| `UserPromptSubmit` | `scripts/capture-prompt.sh` | User sends a message |
| `PostToolUse` | `scripts/observe.sh` | After Write/Edit/MultiEdit/Bash tools |
| `Stop` | `scripts/pause-summary.sh` | After Claude finishes responding |

All scripts write to `.vibe-learn/` in the target project (never in this repo itself).

## Testing Scripts Locally

### Automated test suite (preferred)

```bash
bats tests/        # runs all 49 tests
bats tests/observe.bats   # run a single file
```

Requires `bats` (`brew install bats-core` / `apt-get install bats`).

### Manual stdin testing

Scripts accept hook payloads via stdin as JSON:

```bash
# Test observe.sh with a Write event
echo '{"cwd":"/tmp/test-vl","tool_name":"Write","tool_input":{"file_path":"src/index.ts"},"tool_response":{}}' | bash scripts/observe.sh

# Test observe.sh with a Bash event
echo '{"cwd":"/tmp/test-vl","tool_name":"Bash","tool_input":{"command":"npm install express"},"tool_response":{"exit_code":0}}' | bash scripts/observe.sh

# Test bootstrap.sh
echo '{"session_id":"test123","cwd":"/tmp/test-vl"}' | bash scripts/bootstrap.sh

# Test pause-summary.sh (outputs hookSpecificOutput.additionalContext JSON)
echo '{"cwd":"/tmp/test-vl"}' | bash scripts/pause-summary.sh | jq .

# View the session log
cat /tmp/test-vl/.vibe-learn/session-log.jsonl | jq .

# Count events by type
cat /tmp/test-vl/.vibe-learn/session-log.jsonl | jq -r '.event' | sort | uniq -c
```

Requires: `bash`, `jq`

## Configuration

`config/defaults.json` defines all configurable options. When installed into a project, these can be overridden in `.claude/settings.local.json`.

Key options:
- `log_dir` — where session data is stored (default: `.vibe-learn`)
- `capture_prompts` — whether to log user messages (can disable for privacy)
- `pause_summary_max_lines` — max lines in the stop-hook summary
- `rotate_on_session_start` — keeps previous log as `.prev.jsonl`

**Obsidian config** is stored separately in `.vibe-learn/obsidian.json` (project-level) or `~/.vibe-learn/obsidian.json` (global fallback). `config/obsidian-defaults.json` is the reference template. Claude prompts the user for their vault path on first use and offers to save the config automatically.

Key Obsidian options (`config/obsidian-defaults.json`):

- `vault_path` — absolute path to the Obsidian vault root (required, no default)
- `subfolder` — folder within the vault for vibe-learn notes (default: `Development/Sessions`)
- `tags` — tags added to every note's frontmatter (default: `["vibe-learn"]`)
- `link_style` — `"wikilink"` for `[[links]]` or `"markdown"` for standard links
- `include_project_tag` — auto-add the project directory name as a tag
- `note_naming` — filename template (default: `{date}-{project}`)

## Installation

**`scripts/setup.sh`** is the primary installer. It copies files to `~/.vibe-learn/`, registers all four hooks globally in `~/.claude/settings.json`, and copies slash commands to `~/.claude/commands/`. One run activates vibe-learn across every Claude Code session on the machine.

**`scripts/install.sh`** wires vibe-learn into a specific project only. It merges hooks into `.claude/settings.local.json` and adds `.vibe-learn/` to `.gitignore`. Useful for per-project control or sharing config with a team via version control.

The `hooks.json` in this repo uses `${CLAUDE_PLUGIN_ROOT}` as a path placeholder — resolved to absolute paths during installation.

## Releasing

```bash
bash scripts/release.sh 0.3.0
```

This bumps the version in `VERSION` and `scripts/setup.sh`, commits the change, and creates an annotated git tag `v0.3.0`. Then push:

```bash
git push && git push --tags
```

`release.sh` uses `perl -pi -e` for the substitution (portable across macOS and Linux).

## Slash Commands

Defined as markdown instruction files in `.claude/commands/`:

- `/learn [question]` — summarizes recent session activity, or answers a specific question grounded in the session log
- `/digest` — generates a structured learning report (What Was Built, Key Decisions, Patterns Used, Things to Study)

**Obsidian integration arguments:**

- `/learn obsidian` — save a learn note to the configured Obsidian vault
- `/learn obsidian <question>` — answer a question and save the result to the vault
- `/learn obsidian:recall <topic>` — search the vault for past learnings on a topic (read-only, no file written)
- `/digest obsidian` — save the session digest to the vault
- `/digest obsidian:recall` — generate a digest enriched with a "Connections to Previous Work" section drawn from previous session notes in the vault, then save it

These files contain plain-language instructions that Claude follows — no code execution.

## Session Log Schema

All events appended to `.vibe-learn/session-log.jsonl` (one JSON object per line):

```json
{"timestamp":"...","event":"user_prompt","prompt":"..."}
{"timestamp":"...","event":"tool_use","tool":"Write","file":"src/index.ts","action":"created","context":{"new_file":true}}
{"timestamp":"...","event":"tool_use","tool":"Edit","file":"src/routes.ts","action":"edited","context":{}}
{"timestamp":"...","event":"tool_use","tool":"Bash","command":"npm install","action":"ran","context":{"exit_code":0}}
```

Session metadata (event counts, timestamps) is tracked separately in `.vibe-learn/session-meta.json`.

## Architecture Constraints

- **`observe.sh` must complete in <50ms** — it runs synchronously on every tool use. Never add network calls, heavy computation, or multi-step jq pipelines to this script.
- **Append-only log** — scripts only append to `session-log.jsonl`, never rewrite it. Session rotation creates a `.prev.jsonl` copy instead.
- **No stdout noise from hooks** — scripts should not print to stdout (Claude Code captures it). Use `>&2` for debug output, or suppress entirely.
- **`pause-summary.sh` injects via `additionalContext`** — output must be valid JSON with `{"hookSpecificOutput": {"additionalContext": "..."}}` when providing summaries to Claude's context.
