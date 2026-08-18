# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**vibe-learn** is a coding assistant plugin that observes what the AI does during a development session and helps users understand what was built. It works by registering lifecycle hooks that capture tool use events (file writes, edits, bash commands) into an append-only JSONL session log, then surfaces summaries at natural pause points.

Product principle: users can outsource thinking to an assistant, but they cannot outsource understanding. The project should make AI-assisted work easier to learn from, not just easier to accept.

It supports **Claude Code**, **Codex App/CLI**, **OpenCode**, and **Grok Build**, with a generic adapter system for adding new assistants.

It requires no external API calls. Hooks are mechanical (bash + jq). The learning commands/prompts (`/learn`, `/digest`, `/quiz`, and the Codex/Grok `vibe-learn` skill) leverage the AI's own context window to generate explanations and reports.

## Multi-Assistant Architecture

The project is split into a **generic core** and **per-assistant adapters**:

```text
scripts/          ← assistant-agnostic core (accepts Claude and Grok hook envelopes)
  bootstrap.sh    ← SessionStart hook
  capture-prompt.sh ← UserPromptSubmit hook
  observe.sh      ← PostToolUse hook (<50ms, append-only)
  pause-summary.sh ← Stop hook
  setup.sh        ← global installer
  install.sh      ← per-project installer
  cli.sh          ← command dispatcher for install/dashboard
  dashboard.sh    ← static session briefing generator
  knowledge.sh    ← knowledge ledger helper (record/touch/list/due)

adapters/
  claude-code/    ← Claude Code adapter
    hooks.json    ← hook registration template
    commands/     ← /learn, /digest, and /quiz slash command files
    install.sh    ← hook registration into ~/.claude/settings.json
  codex/          ← Codex App/CLI adapter
    hooks.toml    ← hook registration template (TOML)
    prompts/      ← learn, digest, and quiz prompt-file fallbacks
    skills/       ← global Codex vibe-learn skill
    install.sh    ← hook registration into ~/.codex/config.toml
  opencode/       ← OpenCode adapter
    plugins/      ← local plugin for event capture
    commands/     ← /learn, /digest, and /quiz markdown commands
    install.sh    ← plugin/command install into .opencode or ~/.config/opencode
  grok/           ← Grok Build adapter
    hooks.json    ← hook registration template
    commands/     ← /learn, /digest, and /quiz slash command files
    skills/       ← /vibe-learn skill
    install.sh    ← hook file + skill/command install into ~/.grok or .grok
```

**Adding a new assistant**: create `adapters/<name>/` with an `install.sh` that handles hook registration for that assistant's config format. Prefer translating host payloads in the adapter (OpenCode does this). Grok is the exception: it invokes the core scripts directly and also runs Claude hook files via `[compat.claude]`, so the core scripts accept both Claude snake_case and Grok camelCase envelopes and canonicalize Grok tool names (`write` → `Write`, `search_replace` → `Edit`, `run_terminal_command` → `Bash`).

### Stop Hook / additionalContext

`pause-summary.sh` outputs `{"hookSpecificOutput": {"additionalContext": "..."}}` — the Claude Code JSON envelope for real-time context injection. For Codex Stop hooks, it returns Codex-compatible JSON (`{"continue": true}`) and writes the summary to `.vibe-learn/pause-summary.txt`. For Grok Stop hooks it writes the same file and emits **no stdout**: Grok treats `additionalContext` as a keep-working gate, and SessionStart stdout is ignored. `bootstrap.sh` still injects the file as `additionalContext` on hosts that support it. Grok learn/digest/skill instructions tell the model to read `pause-summary.txt` instead.

## How It Works

The plugin registers four lifecycle hooks:

| Hook | Script | Trigger |
|------|--------|---------|
| `SessionStart` | `scripts/bootstrap.sh` | New session opens |
| `UserPromptSubmit` | `scripts/capture-prompt.sh` | User sends a message |
| `PostToolUse` | `scripts/observe.sh` | After Write/Edit/MultiEdit/Bash/apply_patch and Grok write/search_replace/run_terminal_command. Grok also registers `PostToolUseFailure` so failed tools are logged. |
| `Stop` | `scripts/pause-summary.sh` | After AI finishes responding |

Hook registration format differs per assistant:

- **Claude Code**: JSON in `~/.claude/settings.json` (global) or `.claude/settings.local.json` (project)
- **Codex App/CLI**: inline TOML in `~/.codex/config.toml` (global) or `.codex/config.toml` (project). Codex also supports `hooks.json`, but vibe-learn keeps inline TOML as its install format so the canonical `[features] hooks = true` flag and hook registrations live together. Hooks are enabled by default in current Codex; the flag keeps installs working if hooks were disabled. The older `codex_hooks` feature key is deprecated.
- **Grok Build**: dedicated JSON file at `${GROK_HOME:-~/.grok}/hooks/vibe-learn.json` (global, always trusted) or `.grok/hooks/vibe-learn.json` (project; requires `/hooks-trust`). Commands go in `${GROK_HOME:-~/.grok}/commands/` or `.grok/commands/`; the skill goes in `${GROK_HOME:-~/.grok}/skills/vibe-learn/` or `.grok/skills/vibe-learn/`. Do not edit `config.toml`. Global install and detection honor `GROK_HOME`. Hook `command` values are POSIX-quoted so paths with spaces execute.

Codex merges matching hooks from multiple hook sources instead of replacing lower-precedence hooks. Project-local `.codex/` hook layers require the project to be trusted before they run.

Codex PostToolUse currently covers Bash, `apply_patch`, and MCP tool calls upstream. vibe-learn registers Bash plus `apply_patch` and Codex's documented `Edit`/`Write` matcher aliases, but `observe.sh` intentionally logs only Bash and file edits. Arbitrary MCP tool logging and the Codex `PermissionRequest` hook are out of scope for the current observational adapter.

Grok PostToolUse and PostToolUseFailure matchers list both Grok names (`write`, `search_replace`, `run_terminal_command`) and Claude aliases (`Write`, `Edit`, `MultiEdit`, `Bash`). Matcher regex is case-sensitive. Grok reports failures on `PostToolUseFailure`, not `PostToolUse`; both call `observe.sh`. Failed file ops are logged with `action: "failed"` so pause summaries and briefings do not count them as created/edited. Failed shell commands keep `action: "ran"` with a non-zero `exit_code`. Grok also scans Claude hook files by default; if both adapters are installed, the same tool event can be logged twice. Document `[compat.claude] hooks = false` as the opt-out — do not auto-edit `~/.claude/settings.json`. Grok fires an extra observe-only Stop at session end (`reason` is not `end_turn`); `pause-summary.sh` ignores those.

All scripts write to `.vibe-learn/` in the target project (never in this repo itself).

## Testing Scripts Locally

### Automated test suite (preferred)

```bash
bats tests/        # runs the full test suite
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

**Obsidian config** is stored separately in `.vibe-learn/obsidian.json` (project-level) or `~/.vibe-learn/obsidian.json` (global fallback). `config/obsidian-defaults.json` is the reference template. The assistant prompts the user for their vault path on first use and offers to save the config automatically.

Key Obsidian options (`config/obsidian-defaults.json`):

- `vault_path` — absolute path to the Obsidian vault root (required, no default)
- `subfolder` — folder within the vault for vibe-learn notes (default: `Development/Sessions`)
- `tags` — tags added to every note's frontmatter (default: `["vibe-learn"]`)
- `link_style` — `"wikilink"` for `[[links]]` or `"markdown"` for standard links
- `include_project_tag` — auto-add the project directory name as a tag
- `note_naming` — filename template (default: `{date}-{project}`)

## Installation

**`scripts/setup.sh`** is the primary installer. It copies all files to `~/.vibe-learn/`, auto-detects installed assistants (Claude Code, Codex, OpenCode, Grok Build), and registers hooks/plugins globally for each detected assistant. Global Codex setup also installs `~/.codex/skills/vibe-learn/SKILL.md`. Global Grok setup installs `~/.grok/hooks/vibe-learn.json`, `~/.grok/skills/vibe-learn/SKILL.md`, and `~/.grok/commands/{learn,digest,quiz}.md`. Accepts `--assistant=claude-code`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, or `--assistant=all` to override detection.

**`scripts/install.sh`** wires vibe-learn into a specific project. By default it installs all relevant assistants: existing `.claude/`, `.codex/`, `.opencode/`, and `.grok/` directories win first, then installed tools/configs (`claude` or `~/.claude`, `codex` or `~/.codex`, `opencode` or `~/.config/opencode`, `grok` or `~/.grok`) are detected, and if nothing is found it falls back to Claude Code for backward compatibility. Accepts `--assistant=claude-code`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, or `--assistant=all` to override.

Each adapter's `install.sh` handles:

- Hook registration in the assistant's config format
- Copying command, prompt, or skill files to the assistant's supported directory
- Adding `.vibe-learn/` to `.gitignore` (project-level only)

The `adapters/claude-code/hooks.json` uses `${CLAUDE_PLUGIN_ROOT}` as a path placeholder (documentation only) — actual hook registration always uses absolute paths.

The `adapters/codex/hooks.toml` template uses `INSTALL_DIR_PLACEHOLDER` and registers explicit command-handler timeouts/status messages for Codex hooks: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` at 2 seconds, and `Stop` at 10 seconds.

The `adapters/opencode/` adapter installs `.opencode/plugins/vibe-learn.js` plus `.opencode/commands/learn.md`, `digest.md`, and `quiz.md` for project installs, or the equivalent paths under `~/.config/opencode/` for global installs. The plugin bridges straightforward OpenCode tool events into the existing core scripts.

The `adapters/grok/` adapter writes a dedicated `vibe-learn.json` hook file (never merges into `config.toml` or other hook files) plus commands and a skill. `install.sh` renders command paths with `jq` and POSIX-quotes them. Timeouts: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` / `PostToolUseFailure` at 2 seconds, and `Stop` at 10 seconds.

## Session Briefing

`scripts/briefing.sh` generates an on-demand static HTML session briefing from `.vibe-learn/session-log.jsonl`, `session-meta.json`, `pause-summary.txt`, and optional `git diff` context. It writes under `.vibe-learn/briefing/`:

- `index.html` — dashboard index for recent generated sessions
- `sessions/<date>-<project>-<session>.html` — interactive session briefing
- `exports/<date>-<project>-<session>-notebooklm-pack.md` — source pack for NotebookLM/audio overview workflows

Do not call dashboard generation from hooks. It is intentionally on-demand via `vibe-learn briefing` so hooks remain fast.

## Releasing

```bash
bash scripts/release.sh 0.3.0
```

This bumps the version in `VERSION` and `scripts/setup.sh`, commits the change, and creates an annotated git tag `v0.3.0`. Then push:

```bash
git push && git push --tags
```

`release.sh` uses `perl -pi -e` for the substitution (portable across macOS and Linux).

## Learning Interfaces

Claude Code supports custom slash commands defined as markdown instruction files in `.claude/commands/`:

- `/learn [question]` — summarizes recent session activity, or answers a specific question grounded in the session log
- `/digest` — generates a structured learning report (What Was Built, Key Decisions, Patterns Used, Things to Study)
- `/quiz [topic|review]` — recall questions grounded in the session log, asked one at a time and graded conversationally; `review` re-quizzes ledger concepts that are shaky or stale

Use the global Codex `vibe-learn` skill in natural language, for example "Use vibe-learn to learn what happened" or "Use vibe-learn to create a digest." Project Codex installs keep `.codex/prompts/learn.md` and `.codex/prompts/digest.md` as prompt-file fallbacks; current Codex can expose those as `/prompts:learn` and `/prompts:digest`, but the skill remains the primary durable interface.

Grok Build uses the same slash commands (`/learn`, `/digest`, `/quiz`) plus a `/vibe-learn` skill. Prefer the skill for natural-language requests ("Use vibe-learn to learn what happened"). Grok commands live in `~/.grok/commands/` or `.grok/commands/`.

Codex examples to keep docs and prompts aligned:

- `Use vibe-learn to explain what just happened.`
- `Use vibe-learn to answer: why did we install bcrypt?`
- `Use vibe-learn to create a digest of this session.`
- `Use vibe-learn to quiz me on this session.`
- `Use vibe-learn to save this learn note to Obsidian.`
- `Use vibe-learn to recall past Obsidian notes about authentication.`
- `Read .codex/prompts/learn.md and follow it for obsidian:recall authentication.`

**Obsidian integration arguments / requests:**

- `/learn obsidian` — save a learn note to the configured Obsidian vault
- `/learn obsidian <question>` — answer a question and save the result to the vault
- `/learn obsidian:recall <topic>` — search the vault for past learnings on a topic (read-only, no file written)
- `/digest obsidian` — save the session digest to the vault
- `/digest obsidian:recall` — generate a digest enriched with a "Connections to Previous Work" section drawn from previous session notes in the vault, then save it

These files contain plain-language instructions that the assistant follows — no code execution. The one bridge to code is the knowledge ledger: quiz/learn/digest prompts instruct the assistant to invoke `scripts/knowledge.sh` through its shell tool rather than hand-editing JSON.

## Knowledge Ledger

`.vibe-learn/knowledge.json` (project-level, no global fallback) tracks concepts across sessions:

```json
{"version":1,"concepts":[{"name":"jwt-auth","label":"JWT authentication","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":3,"last_quizzed":"2026-07-11","status":"shaky","notes":"..."}]}
```

`status` is `new` (never quizzed), `shaky`, or `solid`. Quizzing sets status; touching a concept in a later session never downgrades it. All reads and writes go through `scripts/knowledge.sh`:

- `record <name> --label=... --status=<new|shaky|solid> [--notes=...]` — store a quiz result (stamps `last_quizzed`)
- `touch <name> --label=...` — mark a concept seen this session (bumps `sessions` at most once per day)
- `list [--status=<s>]` — print the ledger as JSON
- `due [--days=14]` — concepts due for review (shaky, or unquizzed past the cutoff)

A missing file means an empty ledger; writes merge by `name` and are atomic (temp file + `mv`). `config/knowledge-defaults.json` is the reference template (`review_after_days: 14`, `quiz_question_count: 5`).

The feedback loop: `/quiz` records results; `/learn` opens with a one-line heads-up when a due concept resurfaces in the session; `/digest` merges unresolved ledger items into "Things to Study" and `touch`es newly introduced concepts. Obsidian notes gain an optional `recall_status` frontmatter field when quiz results exist for the day.

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
- **Hooks never write the knowledge ledger** — `.vibe-learn/knowledge.json` is updated only by learning commands via `scripts/knowledge.sh`. Do not call `knowledge.sh` from any hook script.
