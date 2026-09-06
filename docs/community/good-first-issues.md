# Drafted good first issues

Ready-to-open issue bodies for the `good first issue` label. Each is scoped to one or two files plus a bats test, needs no host credentials, and follows the constraints in `CLAUDE.md` (bash + jq, nothing new on the hook hot path). Opening them on GitHub and enabling Discussions are maintainer actions.

---

## 1. `vibe-learn doctor` — check the install in one command

**Why:** the most common support question is "is it working?". Today the answer requires knowing where each host keeps its hooks.

**What to build:** `scripts/doctor.sh`, dispatched from `scripts/cli.sh` as `vibe-learn doctor [target-dir]`. Print one line per check with ✓ / ✗ / – (not applicable):

- `jq` on PATH and its version
- `~/.vibe-learn/VERSION` present and equal to the version in `scripts/setup.sh`
- `~/.local/bin/vibe-learn` shim exists and `~/.local/bin` is in `PATH`
- Claude Code: hooks in `~/.claude/settings.json` and/or `.claude/settings.local.json`, and whether the `vibe-learn@*` plugin is enabled in `enabledPlugins`; warn if both are active (double logging)
- Codex: `[features] hooks = true` and a vibe-learn `SessionStart` hook in `~/.codex/config.toml` or `.codex/config.toml`
- OpenCode: `vibe-learn.js` plugin present in `~/.config/opencode/plugins` or `.opencode/plugins`
- Grok: `hooks/vibe-learn.json` under `${GROK_HOME:-~/.grok}` or `.grok`
- Project: `.vibe-learn/session-log.jsonl` exists and is valid JSONL; `.vibe-learn/knowledge.json` is a valid ledger if present

Exit 0 when nothing failed, 1 otherwise. Read-only: never fix anything.

**Files:** `scripts/doctor.sh` (new), `scripts/cli.sh`, `scripts/setup.sh` (`FILES`), `techpack.yaml`, README "Testing" or a new "Troubleshooting" line, `tests/doctor.bats` (new; use a fake `HOME` like `tests/setup.bats` does).

**Done when:** `bats tests/doctor.bats` covers a clean install, a missing `jq`, a double Claude install, and a malformed ledger.

---

## 2. Dark mode for the session briefing

**Why:** `vibe-learn briefing` renders a light-only page. Most terminals it is opened next to are dark.

**What to build:** add a `@media (prefers-color-scheme: dark)` block to both style sections in `scripts/briefing.sh` (the session page and the index) that overrides the `:root` variables (`--bg`, `--surface`, `--surface-2`, `--text`, `--muted`, `--line`) and the hard-coded pill/area/status colours. Keep the diff `<pre>` palette as is (already dark). No JavaScript toggle needed.

**Files:** `scripts/briefing.sh` only, plus one assertion in `tests/briefing.bats` that the generated page contains `prefers-color-scheme: dark`.

**Done when:** the page reads well in both schemes (attach two screenshots to the PR; Chrome DevTools can emulate the media feature) and the no-ledger output stays otherwise unchanged.

---

## 3. Log Claude Code `NotebookEdit` as a file edit

**Why:** Jupyter users see their notebook changes vanish from the session log because `observe.sh` only knows `Write`, `Edit`, `MultiEdit`, and `Bash`.

**What to build:** in `scripts/observe.sh`, treat `tool_name == "NotebookEdit"` like `Edit`: the file is `tool_input.notebook_path`, the action is `edited` (or `created` when `tool_input.edit_mode == "insert"` and the file did not exist — check how `Edit` decides today and mirror it). Add `NotebookEdit` to the `PostToolUse` matcher in `adapters/claude-code/hooks.json` and the matcher string rendered by `adapters/claude-code/install.sh`.

**Files:** `scripts/observe.sh`, `adapters/claude-code/hooks.json`, `adapters/claude-code/install.sh`, `tests/observe.bats`, `tests/plugin.bats` (matcher assertion), `CLAUDE.md` hook table.

**Done when:** a `NotebookEdit` payload produces a `tool_use` line with `"tool":"Edit"` (or a new `"NotebookEdit"` value, your call — document it in the Session Log Schema section) and the whole suite still runs `observe.sh` well under 50 ms.

---

## 4. `knowledge.sh forget <name>`

**Why:** concepts get misnamed or become irrelevant, and the only way to remove one today is to hand-edit `knowledge.json`, which every prompt tells the model never to do.

**What to build:** a `forget` subcommand in `scripts/knowledge.sh` that removes the concept with the given `name` (no-op with exit 0 if absent), using the same read → jq → temp file → `mv` path as `record` and `touch`. Update the usage header. Mention it in the `/quiz` command files' helper usage block (all four adapters) and in `CLAUDE.md` Knowledge Ledger.

**Files:** `scripts/knowledge.sh`, `tests/knowledge.bats`, four `quiz.md` files (+ dogfood copy), `CLAUDE.md`.

**Done when:** tests cover removing an existing concept, forgetting a missing one, and refusing to touch a malformed ledger.

---

## 5. Shell completion for the `vibe-learn` CLI

**Why:** `vibe-learn` now has `install`, `briefing`, `recap`, `audio-prep`, and `help`, each with flags; tab completion makes them discoverable.

**What to build:** `completions/vibe-learn.bash` and `completions/_vibe-learn` (zsh) completing subcommands, `--assistant=` values, `--days=`, `--save`, `--latest`, and directories. `scripts/setup.sh` copies them to `~/.vibe-learn/completions/` and prints the one-line `source` instruction in the PATH advisory block. Keep the completion scripts static (no calls into `cli.sh`).

**Files:** `completions/` (new), `scripts/setup.sh` (`FILES` + advisory), README "Install" note, `tests/setup.bats` (files copied), `tests/cli.bats` (a `bash -c 'source completions/vibe-learn.bash && complete -p vibe-learn'` smoke test).

**Done when:** `vibe-learn <TAB>` lists the five subcommands in both shells.
