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
  cli.sh          ← `vibe-learn` command dispatcher
  doctor.sh       ← `vibe-learn doctor`: read-only checks of jq, the install, each host's hooks, config keys, and the last session
  briefing.sh     ← `vibe-learn briefing`: static HTML session briefing + NotebookLM pack
  audio-prep.sh   ← `vibe-learn audio-prep`: finds the pack and walks through the NotebookLM upload
  knowledge.sh    ← knowledge ledger helper (record/touch/forget/list/due)
  recap.sh        ← `vibe-learn recap`: weekly "what I learned" markdown (read-only)
  identity.sh     ← sourced helper: harness, model, effort, version from payloads and host files
  health.sh       ← session log + meta → one assistant-health row per session segment (read-only)
  usage.sh        ← sourced helper: tool families and skills per session from the host's own session record
  health-report.sh ← `vibe-learn health`: before/after-change comparison of health rows (read-only)
  lib/session.jq  ← shared jq module: learning turns (`learning_prompt`, `work_events`) and `session_facts` (goal, files, failures) for the pause summary and briefing
  lib/briefing.jq ← `briefing_facts` (session_facts + timeline, ledger, diff, pause summary) and the page renderers that fill the templates
  lib/pack.jq     ← the NotebookLM pack, rendered from the same facts
  lib/briefing-{session,index,health}.html ← briefing page templates (static HTML with `{{name}}` placeholders)

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

### Stop hook output

`pause-summary.sh` writes the summary to `.vibe-learn/pause-summary.txt` and never emits `additionalContext`. A Stop hook's `additionalContext` is not passive: on Claude Code it keeps the turn going under the same loop protections as `decision: "block"`, and Grok treats it as a keep-working gate. For a `"Stop"` event (Claude Code, Codex, OpenCode) it prints `{"continue":true}` when it writes a summary (nothing when the turn had no work or was a learning turn); for lowercase `"stop"` (Grok, Cursor, Copilot shims), `GROK_HOOK_EVENT`, or a payload without an event it prints nothing. There is no mid-session context injection: `bootstrap.sh` injects the file as `additionalContext` at the next SessionStart on hosts that support it, and Grok/Cursor/Copilot learn and digest instructions tell the model to read `pause-summary.txt`. The Stop hook does nothing else: it never starts `briefing.sh`.

## How It Works

The plugin registers four lifecycle hooks:

| Hook | Script | Trigger |
|------|--------|---------|
| `SessionStart` | `scripts/bootstrap.sh` | New session opens |
| `UserPromptSubmit` | `scripts/capture-prompt.sh` | User sends a message |
| `PostToolUse` | `scripts/observe.sh` | After Write/Edit/MultiEdit/NotebookEdit/Bash/apply_patch and Grok write/search_replace/run_terminal_command. Claude Code and Grok also register `PostToolUseFailure` so failed tools are logged (Claude Code fires it instead of `PostToolUse` when a tool fails). |
| `Stop` | `scripts/pause-summary.sh` | After AI finishes responding (writes `pause-summary.txt`, nothing heavier) |

Hook registration format differs per assistant:

- **Claude Code (plugin, preferred)**: `.claude-plugin/plugin.json` at the repo root declares `"commands": "./adapters/claude-code/commands/"` and `"hooks": "./adapters/claude-code/hooks.json"`. `hooks.json` uses `"${CLAUDE_PLUGIN_ROOT}/scripts/..."` (quoted, with per-hook timeouts) and the core scripts resolve `VIBE_LEARN_DIR` from their own location, so they run unchanged from the plugin cache. Commands are namespaced `/vibe-learn:learn`, `/vibe-learn:digest`, `/vibe-learn:quiz`. `bin/` puts `vibe-learn` and `vibe-learn-knowledge` on the Bash tool PATH; command files try `vibe-learn-knowledge` first, then the `~/.vibe-learn` lookup chain. `pause-summary.sh` switches its footer to the namespaced names when `CLAUDE_PLUGIN_ROOT` is set. Version lives only in `plugin.json` (never in `marketplace.json`) and is bumped by `release.sh` / release-please.
- **Claude Code (settings hooks)**: JSON in `~/.claude/settings.json` (global) or `.claude/settings.local.json` (project). `adapters/claude-code/install.sh` skips this when `enabledPlugins` already contains a `vibe-learn@*` entry, so the plugin and the settings hooks never double-log (`VIBE_LEARN_IGNORE_PLUGIN=1` overrides). In that case it also strips leftover vibe-learn hooks from settings, matching only the four core scripts under `$HOOK_BASE`, `~/.vibe-learn`, or a `vibe-learn/` directory; a third-party `observe.sh` and other hooks sharing a matcher group are kept.
- **Codex App/CLI**: inline TOML in `~/.codex/config.toml` (global) or `.codex/config.toml` (project). Codex also supports `hooks.json`, but vibe-learn keeps inline TOML as its install format so the canonical `[features] hooks = true` flag and hook registrations live together. Hooks are enabled by default in current Codex; the flag keeps installs working if hooks were disabled. The older `codex_hooks` feature key is deprecated.
- **Grok Build**: dedicated JSON file at `${GROK_HOME:-~/.grok}/hooks/vibe-learn.json` (global, always trusted) or `.grok/hooks/vibe-learn.json` (project; requires `/hooks-trust`). Commands go in `${GROK_HOME:-~/.grok}/commands/` or `.grok/commands/`; the skill goes in `${GROK_HOME:-~/.grok}/skills/vibe-learn/` or `.grok/skills/vibe-learn/`. Do not edit `config.toml`. Global install and detection honor `GROK_HOME`. Hook `command` values are POSIX-quoted so paths with spaces execute.
- **Cursor**: `{"version":1,"hooks":{...}}` at `~/.cursor/hooks.json` (user) or `.cursor/hooks.json` (project; runs once the workspace is trusted). Every vibe-learn entry points at one shim, `hooks/vibe-learn.sh`, with `VIBE_LEARN_DIR` baked in at install. `install.sh` merges into an existing `hooks.json`: entries whose `command` ends in `/vibe-learn.sh` are replaced, everything else is preserved, and an unparseable file aborts the install rather than being overwritten. Project hook commands use the documented relative form `.cursor/hooks/vibe-learn.sh`; user hooks use the absolute path. No `.cursor/commands/` files — Cursor has folded slash commands into skills (`/migrate-to-skills`), so `/learn`, `/digest`, `/quiz`, `/explain` ship as `.cursor/skills/<name>/SKILL.md` with `disable-model-invocation: true`, alongside an auto-invocable `vibe-learn` skill.
- **GitHub Copilot CLI**: dedicated native JSON hook file at `~/.copilot/hooks/vibe-learn.json` (or `$COPILOT_HOME/hooks/`) globally, and `.github/hooks/vibe-learn.json` per project. The adapter uses native camelCase events and translates their payloads in `hooks/vibe-learn.sh`: `sessionStart` → `bootstrap.sh`, `userPromptSubmitted` → `capture-prompt.sh`, successful and failed `postToolUse` → `observe.sh`, and the turn-level `agentStop` → `pause-summary.sh`. Copilot CLI 1.0.84-4 can fire `userPromptSubmitted` before `sessionStart`; the first event initializes the session exactly once, but only `sessionStart` emits prior context because command-hook stdout from `userPromptSubmitted` is ignored. A global shim defers when the project adapter is present so Copilot's combined hook sources do not double-log. It does not use `sessionEnd`, which fires only when the whole CLI session terminates. Skills install under `${COPILOT_HOME:-~/.copilot}/skills/` or `.github/skills/`. Copilot documents slash-prefixed skill references inside prompts (for example, `Use /learn`), but these are not new built-in interactive slash commands.

Codex merges matching hooks from multiple hook sources instead of replacing lower-precedence hooks. Project-local `.codex/` hook layers require the project to be trusted before they run.

Codex PostToolUse covers shell, `exec_command`, `apply_patch`, MCP, and other local function tools upstream; hosted tools such as web search fire no hooks. vibe-learn registers Bash plus `apply_patch` and Codex's documented `Edit`/`Write` matcher aliases, but `observe.sh` intentionally logs only Bash and file edits. Arbitrary MCP tool logging and the Codex `PermissionRequest` hook are out of scope for the current observational adapter.

Grok PostToolUse and PostToolUseFailure matchers list both Grok names (`write`, `search_replace`, `run_terminal_command`) and Claude aliases (`Write`, `Edit`, `MultiEdit`, `Bash`). Matcher regex is case-sensitive. Grok reports failures on `PostToolUseFailure`, not `PostToolUse`; both call `observe.sh`. Failed file ops are logged with `action: "failed"` so pause summaries and briefings do not count them as created/edited. Failed shell commands keep `action: "ran"` with a non-zero `exit_code`. Grok also scans Claude hook files by default; if both adapters are installed, the same tool event can be logged twice. Document `[compat.claude] hooks = false` as the opt-out — do not auto-edit `~/.claude/settings.json`. Grok fires an extra observe-only Stop at session end (`reason` is not `end_turn`); `pause-summary.sh` ignores those.

Cursor event map (shim): `sessionStart` → `bootstrap.sh` (its `additionalContext` is relayed as Cursor's `additional_context`); `beforeSubmitPrompt` → `capture-prompt.sh` (always answers `{"continue":true}`); `afterFileEdit` → `observe.sh` as `Write` when the single edit has an empty `old_string`, else `Edit`; `postToolUse` / `postToolUseFailure` with matcher `Shell` → `observe.sh` as `Bash` (`tool_output` is a JSON string carrying `exitCode`; failures log `action: "ran"` with exit code 1); `stop` → `pause-summary.sh` with `hook_event_name: "stop"` so it writes the file and prints nothing. On `sessionStart` and `stop` the shim also forwards `harness: "cursor"`, `harness_version` (`cursor_version`), `model` (`model_id` else `model`), `effort` (the `model_params` entry with `id: "effort"`), and `transcript_path`. The shim must never emit `followup_message` — Cursor would auto-submit it as the next user prompt. The project root is `workspace_roots[0]`, falling back to `cwd`. Cloud Agents do not run `sessionStart`, so the prior summary is not injected there. Re-check https://cursor.com/docs/agent/hooks when touching the shim; event names and payloads have changed between releases.

Copilot CLI event map (shim): whichever of `userPromptSubmitted` or `sessionStart` arrives first initializes the session once. `userPromptSubmitted` captures the prompt and is always silent; `sessionStart` always emits prior context as native top-level `additionalContext` when a pause summary exists, including when the prompt hook initialized first. Native `create` → `Write`, `edit` / `str_replace_editor` → `Edit`, raw-string or object `apply_patch` → `apply_patch`, and `bash` / `powershell` → `Bash` for `observe.sh`. Both tool-result events use the same full-name matcher. `postToolUseFailure` supplies exit code 1; successful shell envelopes prefer a structured exit code and otherwise inspect the host's `<shellId: … completed with exit code N>` marker. A command that prints an identical marker is inherently ambiguous. `agentStop` → `pause-summary.sh` with lowercase `stop` semantics so stdout stays empty and never forces another agent turn. Tool result text and errors are never forwarded; only a numeric exit code is extracted, preserving the existing log contract and avoiding secret leakage.


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

# Test pause-summary.sh (prints {"continue":true}; the summary goes to pause-summary.txt)
echo '{"cwd":"/tmp/test-vl","hook_event_name":"Stop"}' | bash scripts/pause-summary.sh
cat /tmp/test-vl/.vibe-learn/pause-summary.txt

# View the session log
cat /tmp/test-vl/.vibe-learn/session-log.jsonl | jq .

# Count events by type
cat /tmp/test-vl/.vibe-learn/session-log.jsonl | jq -r '.event' | sort | uniq -c
```

Requires: `bash`, `jq`

## Configuration

The hooks and scripts read two files: `~/.vibe-learn/config.json` (every project) and the project's `.vibe-learn/config.json`, which wins key by key. Neither exists until you create it. `config/defaults.json` is a reference copy of every key with its default; no setting is taken from it (its `_comment` says so). `vibe-learn doctor` reads it as the list of known keys and fails on any other key in either config file, and `tests/setup.bats` fails if it lists a key no script reads, so adding a key means adding it there. Session data always lives in `.vibe-learn/`.

Keys:
- `capture_prompts` — whether to log user prompt text (turns are still counted when off). Read by `capture-prompt.sh`
- `pause_summary_max_lines` — max lines in `pause-summary.txt` (default 20, minimum 4). Read by `pause-summary.sh`
- `health` — assistant-health settings. `enabled` and `global_log` are read by `bootstrap.sh`; the thresholds (`min_events`, `min_sessions`, `rate_threshold_pts`, `count_threshold`, `control_min_sessions`) by `health-report.sh`

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

**`scripts/install.sh`** wires vibe-learn into a specific project. By default it installs all relevant assistants: existing `.claude/`, `.github/hooks` / `.github/skills`, `.codex/`, `.opencode/`, `.grok/`, and `.cursor/` directories win first, then installed tools/configs (`claude` or `~/.claude`, `copilot` or `${COPILOT_HOME:-~/.copilot}`, `codex` or `~/.codex`, `opencode` or `~/.config/opencode`, `grok` or `~/.grok`, `cursor`/`cursor-agent` or `~/.cursor`) are detected, and if nothing is found it falls back to Claude Code for backward compatibility. Accepts `--assistant=claude-code`, `--assistant=copilot-cli`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, `--assistant=cursor`, or `--assistant=all` to override.

Each adapter's `install.sh` handles:

- Hook registration in the assistant's config format
- Copying command, prompt, or skill files to the assistant's supported directory
- Adding `.vibe-learn/` to `.gitignore` (project-level only)

The `adapters/claude-code/hooks.json` is the live plugin hooks file (referenced from `.claude-plugin/plugin.json`); `${CLAUDE_PLUGIN_ROOT}` is substituted by Claude Code at load time. The settings-based install in `adapters/claude-code/install.sh` does not read this file — it renders the same hooks (the four lifecycle events plus `PostToolUseFailure`) with absolute paths. Keep the two in sync. When settings already has a `hooks` block the installer never rewrites it; it only updates its own entries, the ones whose command is exactly `$HOOK_BASE/scripts/observe.sh` (never a basename match): it widens their matcher when it is still the pre-NotebookEdit default `Write|Edit|MultiEdit|Bash`, and adds its own `PostToolUseFailure` entry when that command is under `PostToolUse` only. The plugin hooks, the settings installer, and `techpack.yaml` share one observe matcher (`tests/plugin.bats`). CI validates both manifests with `claude plugin validate` (`tests/plugin.bats` covers the same invariants offline).

The `adapters/codex/hooks.toml` template uses `INSTALL_DIR_PLACEHOLDER` and registers explicit command-handler timeouts/status messages for Codex hooks: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` at 2 seconds, and `Stop` at 10 seconds.

The `adapters/opencode/` adapter installs `.opencode/plugins/vibe-learn.js` plus `.opencode/commands/learn.md`, `digest.md`, and `quiz.md` for project installs, or the equivalent paths under `~/.config/opencode/` for global installs. The plugin bridges straightforward OpenCode tool events into the existing core scripts.

The `adapters/grok/` adapter writes a dedicated `vibe-learn.json` hook file (never merges into `config.toml` or other hook files) plus commands and a skill. `install.sh` renders command paths with `jq` and POSIX-quotes them. Timeouts: `SessionStart` and `UserPromptSubmit` at 5 seconds, `PostToolUse` / `PostToolUseFailure` at 2 seconds, and `Stop` at 10 seconds.

The `adapters/cursor/` adapter renders `hooks/vibe-learn.sh` with `awk` (so `&`, `|`, and `/` in the install path stay literal), merges `hooks.json` with `jq`, and copies the five skills. Timeouts: `sessionStart` and `beforeSubmitPrompt` at 5 seconds, `afterFileEdit` / `postToolUse` / `postToolUseFailure` at 2 seconds, and `stop` at 10 seconds.

The `adapters/copilot-cli/` adapter writes a dedicated hook file and shim without editing `settings.json`, preserving unrelated hooks and settings. It refuses collisions with non-vibe-learn files before writing, honors `COPILOT_HOME`, and copies the five official Agent Skills. Copilot also loads repository `.claude/settings.json` and `.claude/settings.local.json` hooks; avoid installing vibe-learn in both those files and `.github/hooks/` for the same project. Copilot's documented repository-settings `disableAllHooks` opt-out pauses every non-policy hook source, including vibe-learn, so it is suitable only when the user wants all hooks paused; the installer does not set it automatically. Timeouts: `sessionStart` and `userPromptSubmitted` at 5 seconds, `postToolUse` / `postToolUseFailure` at 2 seconds, and `agentStop` at 10 seconds.

`scripts/doctor.sh` (`vibe-learn doctor [dir]`) is the read-only check of all of the above. It fails (exit 1) when jq is missing or older than 1.6, a file in `setup.sh`'s `FILES` is missing from its own install (so the briefing templates are covered), a core hook script is not executable, a host hook file points at a script or shim that does not exist, no host has vibe-learn hooks, either `config.json` is not a JSON object or holds a key not in `config/defaults.json`, or the knowledge ledger is malformed. It warns, without failing, when the Claude Code plugin and settings hooks are both active, when the session log has tool events but no `turn_end` yet (no Stop hook has run), and when log lines are not JSON. It finds hook paths with one quoted-path scan that works on every host's file format (JSON, TOML, the OpenCode plugin, the Cursor shim), so a new host needs only its candidate files added. It is not in the techpack, which has no CLI.

## Session Briefing

`scripts/briefing.sh` generates a static HTML session briefing from `.vibe-learn/session-log.jsonl`, `session-meta.json`, `pause-summary.txt`, and optional `git diff` context. It builds one facts object (`briefing_facts` in `scripts/lib/briefing.jq`) in a single jq pass and renders every output from it: the pages by filling `scripts/lib/briefing-*.html` (every log, ledger, and project value goes through `@html`, or `script_json` inside a `<script>`), the pack with `scripts/lib/pack.jq`. The templates and jq files ship in `scripts/lib/` (or beside `briefing.sh` in the flat techpack layout); a missing one stops the run with an error. It writes under `.vibe-learn/briefing/`:

- `index.html` — dashboard index for recent generated sessions; each older card's goal and numbers come from that session's saved facts
- `sessions/<date>-<project>-<session>.json` — the facts object itself (`schema_version: 1`; fields listed in `docs/briefing.md`). `vibe-learn briefing --json` prints it for the current session (it always rebuilds first, because the `--if-stale` stamp leaves learning turns out and the facts include them; status lines go to stderr, exit 1 with empty stdout when there is no activity) and `--json --session <id>` prints a saved one. Within a schema version, fields are only added
- `sessions/<date>-<project>-<session>.html` — the session page: three questions first (what was built and why, what to understand, what broke and how it was fixed, all without learning turns), then the Assistant health card when there is history, then a collapsed `<details id="full-record">` with the session brief, timeline, file tour, command log, diff, study queue, knowledge state, and audio export. One stylesheet with light and dark variables (`prefers-color-scheme`)
- `exports/<date>-<project>-<session>-notebooklm-pack.md` — NotebookLM source pack (`scripts/lib/pack.jq`): listener prose from the same facts, opening with the audio prompt; commands as their first line plus a line count; the diff plus untracked (never ignored) files the session wrote, 60 lines each. Only paths that pass `project_path` in `briefing.jq` (relative, one line, no `..` segment) are linked from the page or read for excerpts

`briefing.sh` also reads `.vibe-learn/knowledge.json` when present (read-only): "What to understand" lists up to five concepts whose `files` include a file the session changed (else concepts seen, touched, or quizzed on the session date), shaky concepts and never-quizzed concepts seen in 2+ sessions lead the study queue (cap 5), the session page gains a Knowledge State section, the pack's "What to understand" lists the same concepts as the page (struggled with / not yet quizzed / solid), and the audio prompt (the pack's first paragraph and the page's "Copy audio prompt") gains an adaptive sentence when one of those concepts is shaky. Output is byte-identical to the no-ledger rendering when the file is missing or empty; a malformed ledger warns on stderr and is ignored.

Each run copies the live `session-log.jsonl` and `session-meta.json` into a private `briefing/.work.<random>/` once at start, and copies them again if the meta's session id changed meanwhile (a rotation), so the page never pairs one session's log with another's meta; the slug, and so the output files, come from that copy. The pause summary is shown only when `pause-summary.session` (the session id `pause-summary.sh` writes beside it) matches the session's id, so a summary left by the previous session never lands on this one's page. Outputs are written in the private directory and renamed into place: the page and pack, then the index, then `briefing/.stamps/<slug>` with a fingerprint of the session's work events (learning turns and `turn_end` lines left out), the ledger, and `briefing.sh` with its `lib/` templates and jq modules. `--if-stale` exits 0 when the page and its facts JSON exist and the stamp matches the live session's fingerprint, so `/learn`'s own prompt and commands never make the page stale, and a run killed before the stamp is rebuilt. There is no lock: runs are started by the user or by `/learn` and `/digest`, and two at once each rename whole files into place. A run with no session log keeps an existing index instead of writing the placeholder.

It is built only on demand, never from a hook: by `vibe-learn briefing`, by `vibe-learn audio-prep` when no pack exists, and by `/learn` and `/digest` on every host, which run `vibe-learn briefing --if-stale` first. `tests/bootstrap.bats` and `tests/pause-summary.bats` check that neither SessionStart nor Stop starts it.

## Releasing

```bash
bash scripts/release.sh 0.3.0
```

This bumps the version in `VERSION`, `scripts/setup.sh`, `.release-please-manifest.json`, `.claude-plugin/plugin.json`, and `.cursor-plugin/plugin.json`, commits the change, and creates an annotated git tag `v0.3.0`. It aborts, naming each `file:line`, when the current version appears in a file it does not bump. `--dry-run` runs the checks and lists the files without writing. Then push:

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
{"version":1,"concepts":[{"name":"jwt-auth","label":"JWT authentication","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":3,"last_quizzed":"2026-07-11","status":"shaky","notes":"...","files":["src/auth.ts"]}]}
```

`status` is `new` (never quizzed), `shaky`, or `solid`. Quizzing sets status; touching a concept in a later session never downgrades it. All reads and writes go through `scripts/knowledge.sh`:

- `record <name> --label=... --status=<new|shaky|solid> [--notes=...] [--files=a,b]` — store a quiz result (`shaky` and `solid` stamp `last_quizzed`, `new` does not; without `--notes`, `solid` clears the old note and `shaky` keeps it)
- `touch <name> --label=... [--files=a,b]` — mark a concept seen this session (bumps `sessions` at most once per day)
- `forget <name>` — remove a concept; exits 0 whether or not it existed and says which (`vibe-learn knowledge forget <name>`)
- `list [--status=<s>]` — print the ledger as JSON
- `due [--days=14]` — concepts due for review (shaky, or unquizzed past the cutoff)

`record` and `touch` accept only names matching `^[a-z0-9][a-z0-9-]*$`; `forget` takes any name so entries written before that rule can be removed. `--files` adds project-relative paths (absolute paths under the project, with or without symlinks resolved, are made relative; a path outside the project, with a `..` segment, or with a control character fails the command) to the concept's optional `files` list, which only grows; `/quiz`, `/explain`, and `/digest` pass the files a concept came from so the briefing can link it to them. A missing file means an empty ledger; writes merge by `name` and are atomic (temp file + `mv`). `config/knowledge-defaults.json` is the reference template (`review_after_days: 14`, `quiz_question_count: 5`).

`scripts/recap.sh` (`vibe-learn recap [dir] [--days=7] [--save]`) is the shareable read-only view of the ledger: it groups concepts into confirmed solid / still shaky / carried over / met-not-quizzed for the window, adds activity counts from `session-log.jsonl` + `.prev.jsonl`, lists digests saved in the window (first line of "What Was Built"), and suggests the next command. `--save` writes `.vibe-learn/recaps/<date>-recap.md`. It never writes `knowledge.json`.

`/digest` closes with a one-line pointer to the repo only when `.vibe-learn/digests/` does not exist yet (first digest in a project); it is prompt text, not a hook.

The feedback loop: `/quiz` records results; `/learn` opens with a one-line heads-up when a due concept resurfaces in the session; `/digest` merges unresolved ledger items into "Things to Study" and `touch`es newly introduced concepts. Obsidian notes gain an optional `recall_status` frontmatter field when quiz results exist for the day.

## Session Log Schema

All events appended to `.vibe-learn/session-log.jsonl` (one JSON object per line):

```json
{"timestamp":"...","event":"user_prompt","prompt":"..."}
{"timestamp":"...","event":"user_prompt","prompt":"/digest","turn":8,"kind":"learning"}
{"timestamp":"...","event":"tool_use","tool":"Write","file":"src/index.ts","action":"created","context":{"new_file":true}}
{"timestamp":"...","event":"tool_use","tool":"Edit","file":"src/routes.ts","action":"edited","context":{}}
{"timestamp":"...","event":"tool_use","tool":"NotebookEdit","file":"/abs/path/analysis.ipynb","action":"edited","context":{}}
{"timestamp":"...","event":"tool_use","tool":"Bash","command":"npm install","action":"ran","context":{"exit_code":0}}
```

`capture-prompt.sh` adds `kind: "learning"` when the prompt invokes a learning command on any host (`/learn`, `/vibe-learn:digest`, `/prompts:quiz`, `$vibe-learn`, `/vibe-learn`, `Use /explain`, `Use vibe-learn to …`, `Read .codex/prompts/learn.md and follow it …`, and the `<!-- vibe-learn:learn -->` marker that starts each Codex prompt file, since Codex sends the expanded body). The command must end at whitespace or the end of the prompt, so `/learn/route.ts is broken`, `vibe-learn has a bug` and `read .codex/prompts/learn.md and fix it` stay work. The patterns live in one place, `learning_prompt` in `scripts/lib/session.jq`; extend them there, with a fixture, when a host phrases commands differently. The flag is written even when `capture_prompts` is off. `health.sh`, `recap.sh`, and `briefing.sh` drop learning turns from work metrics with `work_events` (`learning_event` also classifies older logs without `kind` by their prompt text); `usage.commands` still counts them, and `usage.tools`/`skills` stay a whole-session record of what the host ran, since the host transcript has no vibe-learn turn numbers. OpenCode's plugin does not forward prompts, so it has no learning turns. A turn right after a learning turn that only answers (no tool calls, or a single unchained `knowledge.sh`, `briefing.sh`, or `vibe-learn` command) belongs to it too, so `/quiz` answers stay learning; any other tool call makes the turn work. Known limit: a skill started by plain words ("quiz me on what's due") has no command marker, so that turn and its answers count as work.

`pause-summary.sh` also appends one line per genuine turn end, recording the model and effort that answered (either may be `null`):

```json
{"timestamp":"...","event":"turn_end","turn":7,"model":"claude-opus-5.5","effort":"high"}
```

Every reader filters by `event`, so older readers ignore `turn_end`. Readers special-case only `tool == "Bash"` and classify every other event by `action`, so a new edit-like tool such as `NotebookEdit` (its `file` is `tool_input.notebook_path`) needs only the observe.sh mapping and the matcher.

At rotation `bootstrap.sh` keeps the finished session as `session-log.prev.jsonl`, and drops `pause-summary.txt` unless `pause-summary.session` names the finished session (a chat-only session leaves an older summary that must not be injected). Session metadata is tracked separately in `.vibe-learn/session-meta.json`: `session_id`, `started_at`, `event_count`, `current_turn`, plus identity fields written by `bootstrap.sh` — `harness` (`claude-code`, `copilot-cli`, `codex`, `cursor`, `opencode`, `grok`, or `unknown`), `harness_version`, `model`, `effort`, `transcript_path`, `git_head`, `git_dirty` (each `null` when unknown).

## Assistant Health

Spec: `specs/0006-assistant-health-and-bench.md`. Identity comes from `scripts/identity.sh`, which `bootstrap.sh`, `pause-summary.sh`, and `health.sh` source:

- Harness: `VIBE_LEARN_HARNESS`, then the payload `harness` (Copilot CLI and Cursor shims, OpenCode plugin), then `GROK_HOOK_EVENT`, then a `transcript_path` under `~/.codex/` or `~/.claude/`.
- Model / effort: hook payload fields (`model_id`/`model`, `effort` or `effort.level`), plus host files — the last assistant `message.model` in a Claude Code transcript, the last `turn_context` in a Codex transcript, and Grok's `$GROK_HOME/sessions/<@uri workspaceRoot>/<sessionId>/summary.json` (`current_model_id`, `reasoning_effort`). At session start the payload wins; at turn end the host file wins.
- Version: payload `harness_version`, Claude transcript `version`, Codex transcript `session_meta.payload.cli_version`, or `grok --version`. The OpenCode plugin forwards `Session.version`.

The Claude Code and Codex transcripts and Grok's `summary.json` are undocumented: every read yields `null` on failure, and `tests/health.bats` pins each format with a fixture. `bootstrap.sh` and `pause-summary.sh` define no-op fallbacks when `identity.sh` is missing, for installs that copy hook scripts one by one.

A `SessionStart` whose session id matches `session-meta.json` (`claude --continue`, `/compact`) is the same session resuming: `bootstrap.sh` exits without rotating, writing health rows, or rewriting metadata. Before rotating the log, `bootstrap.sh` runs `health.sh` on the previous session and appends its rows to `.vibe-learn/health.jsonl` and, with `"project"` added, to `~/.vibe-learn/health.jsonl`. `health.sh` splits a session into segments wherever the `(model, effort)` of a turn changes; a `null` field carries the previous value forward. Switches live in `~/.vibe-learn/config.json`, overridden by the project's `.vibe-learn/config.json`: `{"health":{"enabled":false}}` stops the append, `{"health":{"global_log":false}}` keeps it per-project. Rows hold counts and identifiers only, never prompts, commands, or file paths.

The first segment row of each session also carries `usage: {tools, skills, commands}`, which covers the whole session. `scripts/usage.sh` (sourced by `health.sh`) reads it at rotation from the host's own record rather than from hooks, since hooks see only a few tools and none see hosted tools or skills. Sources: Claude Code and Cursor transcript `tool_use` blocks, Codex rollout `response_item` calls (plus the `<skill><name>` message an explicit `$skill` injects), Grok's `chat_history.jsonl` beside `summary.json`, and OpenCode's `opencode.db` `part` table (read-only `sqlite3`; the session id must match `^[A-Za-z0-9_-]+$`). Copilot CLI's hook shim supplies the harness name and observed metrics, but has no supported source here for model, version, or full tool and skill usage; those fields remain `null`. Tool names map to families (`read`, `search`, `shell`, `edit`, `web`, `subagent`, `plan`, `skill`, `mcp:<server>`, `other`); skills come from skill-tool calls and reads of `…/skills*/<name>/SKILL.md`. `commands` counts slash or `$` commands typed at the start of a `user_prompt`. `tools`/`skills` are `null` when the record can't be read and `{}` when it has no calls. Only names are kept, never arguments; `tests/usage.bats` pins every host format with a fixture. `health-report.sh` averages tools per session and sums skills and commands per period, and the briefing card and trend page show them.

`scripts/health-report.sh` (`vibe-learn health [dir] [--days=14|all] [--by=harness|model] [--all] [--json] [--save] [--redact]`) is the one analysis behind every health surface. It groups rows into series by harness (or model), places a change marker where `harness_version`, `model`, or `effort` (or, by model, `harness`) changes, and compares the rows since the latest marker with the rows before it in the window. A signal is flagged when the since mean is at least `rate_threshold_pts` points (rates) or `count_threshold` (counts) higher, with `min_sessions` eligible rows (`tool_events >= min_events`) on each side. The "held steady" control needs another series with `control_min_sessions` eligible rows before and after the marker, whose own mean stays within the threshold. The session in progress comes from running `health.sh` on the live log; it is shown but never counted, and dropped once its segment is saved. `--save` writes `.vibe-learn/health-reports/<date>-health.md`, `--redact` renames projects to `project-N`, and `git_head` never leaves a report. The hidden `--views` flag prints all four `--by` × `--days` (14, all) views in one JSON document.

When `.vibe-learn/health.jsonl` has rows, `briefing.sh` embeds that `--views` JSON in `briefing/health.html` (trend callout, metric / group-by / window controls, SVG chart, table), adds an "Assistant health" card and nav entry after the session brief (chips mark the trend's flags; a value turns red only when this session alone is past the threshold), and an index sidebar row. Without rows the outputs are byte-identical to before and a stale `health.html` is removed; a malformed file warns on stderr. `tests/fixtures/health-sample.sh` reproduces the mockup's sample data, dated relative to today.

## Architecture Constraints

- **`observe.sh` must complete in <50ms** — it runs synchronously on every tool use. Never add network calls, heavy computation, or multi-step jq pipelines to this script.
- **Append-only log** — scripts only append to `session-log.jsonl`, never rewrite it. Session rotation creates a `.prev.jsonl` copy instead.
- **No stdout noise from hooks** — scripts should not print to stdout (Claude Code captures it). Use `>&2` for debug output, or suppress entirely.
- **Stop never emits `additionalContext`** — `pause-summary.sh` writes `pause-summary.txt` and prints at most `{"continue":true}`. Context reaches the assistant only at SessionStart.
- **No hook runs the briefing** — only `vibe-learn briefing`, `audio-prep`, and `/learn` and `/digest` (`--if-stale`).
- **Hooks never write the knowledge ledger** — `.vibe-learn/knowledge.json` is updated only by learning commands via `scripts/knowledge.sh`. Do not call `knowledge.sh` from any hook script.
- **Health history is append-only and written only at rotation** — `bootstrap.sh` appends one row per session segment to `.vibe-learn/health.jsonl` and `~/.vibe-learn/health.jsonl`, swallowing every failure. `health.sh` is a single `jq` pass; keep it linear, since it runs inside the `SessionStart` timeout (it takes about 5–6 s on a 10 MB log, a known follow-up).
