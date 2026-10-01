# Assistants

Part of [vibe-learn](../README.md). The README has the canonical `/learn` / `/digest` / `/quiz` / `/explain` set. This page is how each host maps those, plus install details the front door leaves out.

---

## Install

**Claude Code — plugin (recommended)**

```
/plugin marketplace add gkaria/vibe-learn
/plugin install vibe-learn@vibe-learn
```

That registers the hooks and adds `/vibe-learn:learn`, `/vibe-learn:digest`, `/vibe-learn:quiz`, and `/vibe-learn:explain`. Updates arrive with `/plugin update vibe-learn@vibe-learn`. **Requires `jq`**.

**GitHub Copilot CLI, Codex, OpenCode, Grok Build, Cursor — or Claude Code without the plugin system**

```bash
curl -fsSL https://raw.githubusercontent.com/gkaria/vibe-learn/main/scripts/setup.sh | bash
```

Installs to `~/.vibe-learn/`, creates the `vibe-learn` CLI, and registers hooks globally for every AI assistant detected on your machine. If the Claude Code plugin is already enabled, the installer skips Claude hook registration so events are not logged twice. GitHub Copilot CLI is detected via the `copilot` binary, `~/.copilot`, or `COPILOT_HOME`. To update: re-run the same command.

To target one assistant: `--assistant=claude-code`, `--assistant=copilot-cli`, `--assistant=codex`, `--assistant=opencode`, `--assistant=grok`, or `--assistant=cursor`.

### Per-project install (optional)

Global install covers most workflows. If you want hooks scoped to one project, or want to commit the config so teammates get vibe-learn automatically:

```bash
cd your-project
vibe-learn install
```

Detects which assistants the project already uses (including `.github/` for Copilot CLI) and installs only those. Adds `.vibe-learn/` to `.gitignore`.

---

## How each assistant maps the commands

### Claude Code

```
/learn                              — explain what just happened
/learn why did we add middleware?   — answer a specific question
/digest                             — full structured session report
/quiz                               — check your understanding of this session
/quiz review                        — re-quiz concepts that are shaky or due again
/explain [file|topic]               — guided code tour of what was touched
```

With the plugin install the same commands are namespaced: `/vibe-learn:learn`, `/vibe-learn:digest`, `/vibe-learn:quiz`, `/vibe-learn:explain`.

### GitHub Copilot CLI

```
Use /learn
Use /learn why did we add middleware?
Use /digest
Use /quiz
Use /quiz review
Use /explain src/middleware/auth.ts
Use vibe-learn to learn what happened.
```

Copilot CLI loads these as Agent Skills from `.github/skills/` (project) or `${COPILOT_HOME:-~/.copilot}/skills/` (personal). They are skill references inside a prompt, not new built-in interactive commands; typing a bare `/learn` is not guaranteed to dispatch like Claude Code's custom slash commands. Project hooks live in `.github/hooks/` and need the folder trusted before they run.

On Copilot CLI 1.0.84-4, `userPromptSubmitted` can arrive before `sessionStart`; the adapter initializes once on whichever event arrives first, keeps the prompt hook silent, and emits prior-session context from the later `sessionStart`. A global vibe-learn hook defers when a project vibe-learn hook is present.

Copilot also reads repository `.claude/settings.json` and `.claude/settings.local.json` hooks. Avoid installing vibe-learn in both those files and `.github/hooks/` for one project. Copilot's documented `disableAllHooks` repository-settings option pauses every non-policy hook source—including vibe-learn—so use it only when you intend to pause all hooks; the installer never changes it automatically.

### Codex

```
Use vibe-learn to learn what happened.
Use vibe-learn to answer: why did we install bcrypt?
Use vibe-learn to create a digest.
Use vibe-learn to quiz me on this session.
Use vibe-learn to explain src/middleware/auth.ts.
```

### OpenCode

```
/learn
/learn why did we add middleware?
/digest
/quiz
/explain src/middleware/auth.ts
```

### Grok Build

```
/learn
/learn why did we add middleware?
/digest
/quiz
/explain src/middleware/auth.ts
/vibe-learn
Use vibe-learn to learn what happened.
```

Project Grok hooks stay inert until the folder is trusted (`/hooks-trust` or `grok --trust`). If Claude Code vibe-learn is also installed, Grok may run both hook sets; set `[compat.claude] hooks = false` in `~/.grok/config.toml` to avoid double-logging.

### Cursor

```
/learn
/learn why did we add middleware?
/digest
/quiz
/explain src/middleware/auth.ts
/vibe-learn
```

Cursor ships these as skills (`.cursor/skills/`), so plain requests like "what did we just build?" also route to the `vibe-learn` skill. Project hooks (`.cursor/hooks.json`) run once the workspace is trusted. Cursor has no context injection on `stop`, so the pause summary is written to `.vibe-learn/pause-summary.txt` and relayed at the next `sessionStart`; the skills read the file directly. Cloud Agents skip `sessionStart`, so there the file is the only channel.

---

## Integration summary

| Assistant | How vibe-learn integrates |
|-----------|--------------------------|
| **Claude Code** | Plugin (`/plugin install vibe-learn@vibe-learn`) or JSON hooks in `settings.json`; native `/learn`, `/digest`, `/quiz`, and `/explain` slash commands |
| **GitHub Copilot CLI** | Native JSON hooks in `.github/hooks/` or `~/.copilot/hooks/`; `/learn`, `/digest`, `/quiz`, `/explain`, and `vibe-learn` project/personal skills |
| **Codex App/CLI** | Inline TOML hooks in `config.toml`, global `vibe-learn` skill, prompt-file fallbacks |
| **OpenCode** | JavaScript plugin in `.opencode/plugins/`, native `/learn`, `/digest`, `/quiz`, and `/explain` commands |
| **Grok Build** | JSON hooks in `${GROK_HOME:-~/.grok}/hooks/vibe-learn.json`, native `/learn`, `/digest`, `/quiz`, `/explain`, and a `/vibe-learn` skill |
| **Cursor** | `hooks.json` entries pointing at one shim (`.cursor/hooks/vibe-learn.sh`), plus `/learn`, `/digest`, `/quiz`, `/explain`, and `vibe-learn` skills in `.cursor/skills/` |
