# Privacy

vibe-learn runs entirely on your machine. It makes no network calls, needs no account or API key, and sends nothing to its author or to any third party.

## What it stores, and where

Everything is written under `.vibe-learn/` in the project you are working in, except the optional global health log below.

| File | What it holds |
|------|---------------|
| `session-log.jsonl` | One line per event: your prompts (first 500 characters), the file paths the assistant wrote or edited, shell commands it ran (first 200 characters) with exit codes, and per-turn model and effort |
| `session-meta.json` | Session id, assistant name and version, model, effort, transcript path, git HEAD and whether the tree was dirty |
| `pause-summary.txt` | The short recap shown after each response |
| `knowledge.json` | Concepts you were quizzed on, with a status and short notes |
| `health.jsonl` | One row of counts and identifiers per session segment. Never prompts, commands, or file paths |
| `briefing/`, `digests/`, `recaps/` | Reports you generate on request |

With the global health log enabled (the default), each health row is also appended to `~/.vibe-learn/health.jsonl` with the project's directory name added.

Because prompts and commands are logged, the session log can contain whatever you type or run. If a secret appears in a prompt or command line, it can appear in the log. `.vibe-learn/` is added to `.gitignore` on install; do not commit it.

## What leaves your machine

Nothing, from vibe-learn itself. The `/learn`, `/digest`, `/quiz`, and `/explain` commands read the log into your assistant's context so it can answer. That content is then handled by your assistant under that assistant's own privacy terms, the same as anything else in your session.

Saving to Obsidian writes Markdown files to the vault folder you configure. Exporting a NotebookLM source pack only writes a file; uploading it anywhere is your choice.

## Controls

Set these in `.vibe-learn/config.json` (one project) or `~/.vibe-learn/config.json` (all projects). The project file wins.

```json
{ "capture_prompts": false, "health": { "enabled": false, "global_log": false } }
```

- `capture_prompts: false` — turns are still counted, but your prompt text is never written to the log.
- `health.enabled: false` — stops writing health rows.
- `health.global_log: false` — keeps health rows in the project only.

To delete everything vibe-learn has stored, remove `.vibe-learn/` from the project and `~/.vibe-learn/health.jsonl`.

## Questions

Open an issue at https://github.com/gkaria/vibe-learn/issues.
