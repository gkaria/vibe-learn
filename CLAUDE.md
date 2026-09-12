# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Project Is

**vibe-learn** is a coding assistant plugin that observes what the AI does during a development session and helps users understand what was built. It works by registering lifecycle hooks that capture tool use events (file writes, edits, bash commands) into an append-only JSONL session log, then surfaces summaries at natural pause points.

Product principle: users can outsource thinking to an assistant, but they cannot outsource understanding. The project should make AI-assisted work easier to learn from, not just easier to accept.

It supports **Claude Code**, **GitHub Copilot CLI**, **Codex App/CLI**, **OpenCode**, **Grok Build**, and **Cursor**, with a generic adapter system for adding new assistants.

It requires no external API calls. Hooks are mechanical (bash + jq). The learning commands/prompts (`/learn`, `/digest`, `/quiz`, and the Copilot/Codex/Grok/Cursor skills) leverage the AI's own context window to generate explanations and reports.

## Multi-Assistant Architecture

The project is split into a **generic core** and **per-assistant adapters**:

```text
.claude-plugin/   ← Claude Code plugin packaging (the repo root is the plugin root)
  plugin.json     ← manifest; points commands/hooks at adapters/claude-code/
  marketplace.json ← single-plugin marketplace so `/plugin marketplace add gkaria/vibe-learn` works
bin/              ← on the Bash tool PATH while the plugin is enabled
  vibe-learn      ← → scripts/cli.sh
  vibe-learn-knowledge ← → scripts/knowledge.sh

scripts/          ← assistant-agnostic core (host payload translation stays in adapters)
  bootstrap.sh    ← SessionStart hook
  capture-prompt.sh ← UserPromptSubmit hook
  observe.sh      ← PostToolUse hook (<50ms, append-only)
  pause-summary.sh ← Stop hook
  setup.sh        ← global installer
  install.sh      ← per-project installer
  cli.sh          ← command dispatcher for install/dashboard
  dashboard.sh    ← static session briefing generator
  knowledge.sh    ← knowledge ledger helper (record/touch/list/due)
  recap.sh        ← `vibe-learn recap`: weekly "what I learned" markdown (read-only)

adapters/
  claude-code/    ← Claude Code adapter
    hooks.json    ← hook registration template
    commands/     ← /learn, /digest, /quiz, and /explain slash command files
    install.sh    ← hook registration into ~/.claude/settings.json
  codex/          ← Codex App/CLI adapter
    hooks.toml    ← hook registration template (TOML)
    prompts/      ← learn, digest, quiz, and explain prompt-file fallbacks
    skills/       ← global Codex vibe-learn skill
    install.sh    ← hook registration into ~/.codex/config.toml
  opencode/       ← OpenCode adapter
    plugins/      ← local plugin for event capture
    commands/     ← /learn, /digest, /quiz, and /explain markdown commands
    install.sh    ← plugin/command install into .opencode or ~/.config/opencode
  grok/           ← Grok Build adapter
    hooks.json    ← hook registration template
    commands/     ← /learn, /digest, /quiz, and /explain slash command files
    skills/       ← /vibe-learn skill
    install.sh    ← hook file + skill/command install into ~/.grok or .grok
  cursor/         ← Cursor adapter
    hooks.json    ← hook registration template (merged into hooks.json)
    hooks/        ← vibe-learn.sh payload shim (Cursor envelope → core scripts)
    skills/       ← learn, digest, quiz, explain (slash-style) and vibe-learn skills
    install.sh    ← shim + hooks.json merge + skill install into ~/.cursor or .cursor
  copilot-cli/     ← GitHub Copilot CLI adapter
    hooks.json    ← native camelCase hook template
    hooks/        ← vibe-learn.sh payload shim (Copilot envelope → core scripts)
    skills/       ← learn, digest, quiz, explain, and vibe-learn skills
    install.sh    ← dedicated hook file + skill install into ~/.copilot or .github
```

**Adding a new assistant**: create `adapters/<name>/` with an `install.sh` that handles hook registration for that assistant's config format. Prefer translating host payloads in the adapter (OpenCode, Cursor, and Copilot CLI do this). Grok is the exception: it invokes the core scripts directly and also runs Claude hook files via `[compat.claude]`, so the core scripts accept both Claude snake_case and Grok camelCase envelopes and canonicalize Grok tool names (`write` → `Write`, `search_replace` → `Edit`, `run_terminal_command` → `Bash`).

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

- **Claude Code (plugin, preferred)**: `.claude-plugin/plugin.json` at the repo root declares `"commands": "./adapters/claude-code/commands/"` and `"hooks": "./adapters/claude-code/hooks.json"`. `hooks.json` uses `"${CLAUDE_PLUGIN_ROOT}/scripts/..."` (quoted, with per-hook timeouts) and the core scripts resolve `VIBE_LEARN_DIR` from their own location, so they run unchanged from the plugin cache. Commands are namespaced `/vibe-learn:learn`, `/vibe-learn:digest`, `/vibe-learn:quiz`. `bin/` puts `vibe-learn` and `vibe-learn-knowledge` on the Bash tool PATH; command files try `vibe-learn-knowledge` first, then the `~/.vibe-learn` lookup chain. `pause-summary.sh` switches its footer to the namespaced names when `CLAUDE_PLUGIN_ROOT` is set. Version lives only in `plugin.json` (never in `marketplace.json`) and is bumped by `release.sh` / release-please.
- **Claude Code (settings hooks)**: JSON in `~/.claude/settings.json` (global) or `.claude/settings.local.json` (project). `adapters/claude-code/install.sh` skips this when `enabledPlugins` already contains a `vibe-learn@*` entry, so the plugin and the settings hooks never double-log (`VIBE_LEARN_IGNORE_PLUGIN=1` overrides).
- **Codex App/CLI**: inline TOML in `~/.codex/config.toml` (global) or `.codex/config.toml` (project). Codex also supports `hooks.json`, but vibe-learn keeps inline TOML as its install format so the canonical `[features] hooks = true` flag and hook registrations live together. Hooks are enabled by default in current Codex; the flag keeps installs working if hooks were disabled. The older `codex_hooks` feature key is deprecated.
- **Grok Build**: dedicated JSON file at `${GROK_HOME:-~/.grok}/hooks/vibe-learn.json` (global, always trusted) or `.grok/hooks/vibe-learn.json` (project; requires `/hooks-trust`). Commands go in `${GROK_HOME:-~/.grok}/commands/` or `.grok/commands/`; the skill goes in `${GROK_HOME:-~/.grok}/skills/vibe-learn/` or `.grok/skills/vibe-learn/`. Do not edit `config.toml`. Global install and detection honor `GROK_HOME`. Hook `command` values are POSIX-quoted so paths with spaces execute.
- **Cursor**: `{"version":1,"hooks":{...}}` at `~/.cursor/hooks.json` (user) or `.cursor/hooks.json` (project; runs once the workspace is trusted). Every vibe-learn entry points at one shim, `hooks/vibe-learn.sh`, with `VIBE_LEARN_DIR` baked in at install. `install.sh` merges into an existing `hooks.json`: entries whose `command` ends in `/vibe-learn.sh` are replaced, everything else is preserved, and an unparseable file aborts the install rather than being overwritten. Project hook commands use the documented relative form `.cursor/hooks/vibe-learn.sh`; user hooks use the absolute path. No `.cursor/commands/` files — Cursor has folded slash commands into skills (`/migrate-to-skills`), so `/learn`, `/digest`, `/quiz`, `/explain` ship as `.cursor/skills/<name>/SKILL.md` with `disable-model-invocation: true`, alongside an auto-invocable `vibe-learn` skill.
- **GitHub Copilot CLI**: dedicated native JSON hook file at `~/.copilot/hooks/vibe-learn.json` (or `$COPILOT_HOME/hooks/`) globally, and `.github/hooks/vibe-learn.json` per project. The adapter uses native camelCase events and translates their payloads in `hooks/vibe-learn.sh`: `sessionStart` → `bootstrap.sh`, `userPromptSubmitted` → `capture-prompt.sh`, successful and failed `postToolUse` → `observe.sh`, and the turn-level `agentStop` → `pause-summary.sh`. Copilot CLI 1.0.84-4 can fire `userPromptSubmitted` before `sessionStart`; the first event initializes the session exactly once, and `userPromptSubmitted` relays prior context when it wins that race so another `sessionStart` hook cannot overwrite it. It does not use `sessionEnd`, which fires only when the whole CLI session terminates. Skills install under `~/.copilot/skills/` or `.github/skills/`. Copilot documents slash-prefixed skill references inside prompts (for example, `Use /learn`), but these are not new built-in interactive slash commands.

Codex merges matching hooks from multiple hook sources instead of replacing lower-precedence hooks. Project-local `.codex/` hook layers require the project to be trusted before they run.

Codex PostToolUse currently covers Bash, `apply_patch`, and MCP tool calls upstream. vibe-learn registers Bash plus `apply_patch` and Codex's documented `Edit`/`Write` matcher aliases, but `observe.sh` intentionally logs only Bash and file edits. Arbitrary MCP tool logging and the Codex `PermissionRequest` hook are out of scope for the current observational adapter.

Grok PostToolUse and PostToolUseFailure matchers list both Grok names (`write`, `search_replace`, `run_terminal_command`) and Claude aliases (`Write`, `Edit`, `MultiEdit`, `Bash`). Matcher regex is case-sensitive. Grok reports failures on `PostToolUseFailure`, not `PostToolUse`; both call `observe.sh`. Failed file ops are logged with `action: "failed"` so pause summaries and briefings do not count them as created/edited. Failed shell commands keep `action: "ran"` with a non-zero `exit_code`. Grok also scans Claude hook files by default; if both adapters are installed, the same tool event can be logged twice. Document `[compat.claude] hooks = false` as the opt-out — do not auto-edit `~/.claude/settings.json`. Grok fires an extra observe-only Stop at session end (`reason` is not `end_turn`); `pause-summary.sh` ignores those.

Cursor event map (shim): `sessionStart` → `bootstrap.sh` (its `additionalContext` is relayed as Cursor's `additional_context`); `beforeSubmitPrompt` → `capture-prompt.sh` (always answers `{"continue":true}`); `afterFileEdit` → `observe.sh` as `Write` when the single edit has an empty `old_string`, else `Edit`; `postToolUse` / `postToolUseFailure` with matcher `Shell` → `observe.sh` as `Bash` (`tool_output` is a JSON string carrying `exitCode`; failures log `action: "ran"` with exit code 1); `stop` → `pause-summary.sh` with `hook_event_name: "stop"` so it writes the file and prints nothing. The shim must never emit `followup_message` — Cursor would auto-submit it as the next user prompt. The project root is `workspace_roots[0]`, falling back to `cwd`. Cloud Agents do not run `sessionStart`, so the prior summary is not injected there. Re-check https://cursor.com/docs/agent/hooks when touching the shim; event names and payloads have changed between releases.

Copilot CLI event map (shim): whichever of `userPromptSubmitted` or `sessionStart` arrives first initializes the session once; `sessionStart` translates Claude's nested output to Copilot's top-level `additionalContext`, while an early `userPromptSubmitted` both captures the prompt and returns the same native context so the host consumes it before the model turn. Native `create` → `Write`, `edit` / `str_replace_editor` → `Edit`, raw-string or object `apply_patch` → `apply_patch`, and `bash` / `powershell` → `Bash` for `observe.sh`. `postToolUseFailure` supplies exit code 1; successful hook envelopes for completed shell tools are also checked for the numeric `exit code N` marker because the host can report a nonzero process as `postToolUse`. `agentStop` → `pause-summary.sh` with lowercase `stop` semantics so stdout stays empty and never forces another agent turn. Tool result text and errors are never forwarded; only a numeric exit code is extracted, preserving the existing log contract and avoiding secret leakage.


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

**`scripts/setup.sh`** is the primary installer. It copies all files to `~/.vibe-learn/`, auto-detects installed assistants (Claude Code, GitHub Copilot CLI, Codex, OpenCode, Grok Build, Cursor), and registers hooks/plugins globally for each detected assistant. Global Codex setup also installs `~/.codex/skills/vibe-learn/SKILL.md`. Global Grok setup installs `~/.grok/hooks/vibe-learn.json`, `~/.grok/skills/vibe-learn/SKILL.md`, and `~/.grok/commands/{learn,digest,quiz}.md`. Global Cursor setup installs `~/.cursor/hooks/vibe-learn.sh`, merges into `~/.cursor/hooks.json`, and installs `~/.cursor/skills/{learn,digest,quiz,explain,vibe-learn}/SKILL.md`. Accepts `--assistant=claude-code`, `--assistant=copilot-cli`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, `--assistant=cursor`, or `--assistant=all` to override detection.

**`scripts/install.sh`** wires vibe-learn into a specific project. By default it installs all relevant assistants: existing `.claude/`, `.github/hooks` / `.github/skills`, `.codex/`, `.opencode/`, `.grok/`, and `.cursor/` directories win first, then installed tools/configs (`claude` or `~/.claude`, `copilot` or `${COPILOT_HOME:-~/.copilot}`, `codex` or `~/.codex`, `opencode` or `~/.config/opencode`, `grok` or `~/.grok`, `cursor`/`cursor-agent` or `~/.cursor`) are detected, and if nothing is found it falls back to Claude Code for backward compatibility. Accepts `--assistant=claude-code`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, `--assistant=cursor`, or `--assistant=all` to override.

Each adapter's `install.sh` handles:

- Hook registration in the assistant's config format
- Copying command, prompt, or skill files to the assistant's supported directory
- Adding `.vibe-learn/` to `.gitignore` (project-level only)

The `adapters/claude-code/hooks.json` is the live plugin hooks file (referenced from `.claude-plugin/plugin.json`); `${CLAUDE_PLUGIN_ROOT}` is substituted by Claude Code at load time. The settings-based install in `adapters/claude-code/install.sh` does not read this file — it renders the same four hooks with absolute paths. Keep the two in sync. CI validates both manifests with `claude plugin validate` (`tests/plugin.bats` covers the same invariants offline).

The `adapters/codex/hooks.toml` template uses `INSTALL_DIR_PLACEHOLDER` and registers explicit command-handler timeouts/status messages for Codex hooks: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` at 2 seconds, and `Stop` at 10 seconds.

The `adapters/opencode/` adapter installs `.opencode/plugins/vibe-learn.js` plus `.opencode/commands/learn.md`, `digest.md`, and `quiz.md` for project installs, or the equivalent paths under `~/.config/opencode/` for global installs. The plugin bridges straightforward OpenCode tool events into the existing core scripts.

The `adapters/grok/` adapter writes a dedicated `vibe-learn.json` hook file (never merges into `config.toml` or other hook files) plus commands and a skill. `install.sh` renders command paths with `jq` and POSIX-quotes them. Timeouts: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` / `PostToolUseFailure` at 2 seconds, and `Stop` at 10 seconds.

The `adapters/cursor/` adapter renders `hooks/vibe-learn.sh` with `awk` (so `&`, `|`, and `/` in the install path stay literal), merges `hooks.json` with `jq`, and copies the five skills. Timeouts: `sessionStart` and `beforeSubmitPrompt` at 5 seconds, `afterFileEdit` / `postToolUse` / `postToolUseFailure` at 2 seconds, and `stop` at 10 seconds.

The `adapters/copilot-cli/` adapter writes a dedicated hook file and shim without editing `settings.json`, preserving unrelated hooks and settings. It refuses collisions with non-vibe-learn files before writing, honors `COPILOT_HOME`, and copies the five official Agent Skills. Timeouts: `sessionStart` and `userPromptSubmitted` at 5 seconds, `postToolUse` / `postToolUseFailure` at 2 seconds, and `agentStop` at 10 seconds.

## Session Briefing

`scripts/briefing.sh` generates an on-demand static HTML session briefing from `.vibe-learn/session-log.jsonl`, `session-meta.json`, `pause-summary.txt`, and optional `git diff` context. It writes under `.vibe-learn/briefing/`:

- `index.html` — dashboard index for recent generated sessions
- `sessions/<date>-<project>-<session>.html` — interactive session briefing
- `exports/<date>-<project>-<session>-notebooklm-pack.md` — source pack for NotebookLM/audio overview workflows

`briefing.sh` also reads `.vibe-learn/knowledge.json` when present (read-only): shaky concepts and never-quizzed concepts seen in 2+ sessions lead the study queue (cap 5), the session page gains a Knowledge State section, the pack gains a "Your knowledge state" table, and the audio framing gains an adaptive sentence when anything is shaky. Output is byte-identical to the no-ledger rendering when the file is missing or empty; a malformed ledger warns on stderr and is ignored.

Do not call dashboard generation from hooks. It is intentionally on-demand via `vibe-learn briefing` so hooks remain fast.

## Releasing

```bash
bash scripts/release.sh 0.3.0
```

This bumps the version in `VERSION`, `scripts/setup.sh`, `.release-please-manifest.json`, and `.claude-plugin/plugin.json`, commits the change, and creates an annotated git tag `v0.3.0`. Then push:

```bash
git push && git push --tags
```

`release.sh` uses `perl -pi -e` for the substitution (portable across macOS and Linux).

## Learning Interfaces

Claude Code supports custom slash commands defined as markdown instruction files in `.claude/commands/`:

- `/learn [question]` — summarizes recent session activity, or answers a specific question grounded in the session log
- `/digest` — generates a structured learning report (What Was Built, Key Decisions, Patterns Used, Things to Study)
- `/quiz [topic|review]` — recall questions grounded in the session log, asked one at a time and graded conversationally; `review` re-quizzes ledger concepts that are shaky or stale
- `/explain [file|topic]` — guided code tour (entry point, spine, edges, connections) of a file or subsystem the session touched, every claim tied to a `file:line`; `touch`es the concepts it covered and offers a quiz

Use the global Codex `vibe-learn` skill in natural language, for example "Use vibe-learn to learn what happened" or "Use vibe-learn to create a digest." Project Codex installs keep `.codex/prompts/learn.md` and `.codex/prompts/digest.md` as prompt-file fallbacks; current Codex can expose those as `/prompts:learn` and `/prompts:digest`, but the skill remains the primary durable interface.

Grok Build uses the same slash commands (`/learn`, `/digest`, `/quiz`, `/explain`) plus a `/vibe-learn` skill. Prefer the skill for natural-language requests ("Use vibe-learn to learn what happened"). Grok commands live in `~/.grok/commands/` or `.grok/commands/`.

Cursor exposes the same four as skills (`/learn`, `/digest`, `/quiz`, `/explain` in `.cursor/skills/<name>/SKILL.md`, explicit invocation only) plus an auto-invocable `vibe-learn` skill for natural-language requests. Skill text refers to "the rest of the user's message" instead of `$ARGUMENTS`, and the helper lookup falls back to the `VIBE_LEARN_DIR` baked into `.cursor/hooks/vibe-learn.sh`.

GitHub Copilot CLI exposes the four workflows plus a natural-language `vibe-learn` Agent Skill in `.github/skills/` or `~/.copilot/skills/`. Invoke them in a prompt as `Use /learn`, `Use /digest`, `Use /quiz`, or `Use /explain`; do not document them as built-in interactive commands. The adapter intentionally avoids plugin installation and Copilot's managed `config.json` so per-project installs stay isolated and unrelated configuration is untouched.

Codex examples to keep docs and prompts aligned:

- `Use vibe-learn to explain what just happened.`
- `Use vibe-learn to answer: why did we install bcrypt?`
- `Use vibe-learn to create a digest of this session.`
- `Use vibe-learn to quiz me on this session.`
- `Use vibe-learn to explain src/middleware/auth.ts.`
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

`scripts/recap.sh` (`vibe-learn recap [dir] [--days=7] [--save]`) is the shareable read-only view of the ledger: it groups concepts into confirmed solid / still shaky / carried over / met-not-quizzed for the window, adds activity counts from `session-log.jsonl` + `.prev.jsonl`, lists digests saved in the window (first line of "What Was Built"), and suggests the next command. `--save` writes `.vibe-learn/recaps/<date>-recap.md`. It never writes `knowledge.json`.

`/digest` closes with a one-line pointer to the repo only when `.vibe-learn/digests/` does not exist yet (first digest in a project); it is prompt text, not a hook.

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
