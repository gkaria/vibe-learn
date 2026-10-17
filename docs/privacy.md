# Privacy

vibe-learn runs entirely on your machine. It makes no network calls, needs no account or API key, and sends nothing to its author or to any third party.

## What it stores, and where

Everything is written under `.vibe-learn/` in the project you are working in, except the optional global health log below.

| File | What it holds |
|------|---------------|
| `session-log.jsonl` | One line per event: your prompts (first 500 characters), the file paths the assistant wrote or edited, shell commands it ran (first 200 characters) with exit codes, and per-turn model and effort |
| `session-meta.json` | Session id, assistant name and version, model, effort, transcript path, git HEAD and whether the tree was dirty |
| `pause-summary.txt` | A short recap of the session (goal, failing commands, last turn, files), rewritten after each response that did work and injected at the next session start |
| `pause-summary.session` | The id of the session that wrote `pause-summary.txt` |
| `knowledge.json` | Concepts you were quizzed on, with a status and short notes |
| `health.jsonl` | One row of counts and identifiers per session segment. Never prompts, commands, or file paths |
| `briefing/`, `digests/`, `recaps/` | Reports: briefings are built on request and by `/learn` and `/digest`; digests and recaps on request |

With the global health log enabled (the default), each health row is also appended to `~/.vibe-learn/health.jsonl` with the project's directory name added.

Because prompts and commands are logged, the session log can contain whatever you type or run. If a secret appears in a prompt or command line, it can appear in the log. `.vibe-learn/` is added to `.gitignore` on install; do not commit it.

## What leaves your machine

Nothing, from vibe-learn itself. The `/learn`, `/digest`, `/quiz`, and `/explain` commands read the log into your assistant's context so it can answer. That content is then handled by your assistant under that assistant's own privacy terms, the same as anything else in your session.

A [routine](#routines) you schedule is the exception: it can send a short summary to a chat.

Saving to Obsidian writes Markdown files to the vault folder you configure. Exporting a NotebookLM source pack only writes a file; uploading it anywhere is your choice.

## Routines

A routine is an agent bot you schedule yourself, such as the [daily learning digest](../examples/routines/daily-digest.md) in [docs/bots.md](bots.md). It is outside the hooks' promise: it is the one way vibe-learn's recipes send session content off your machine, to the chat you point the bot at, and only because you installed it. The bot's own model also reads what the routine gives it, under that bot's privacy terms.

The shipped recipe follows these rules, and a routine you write yourself should too. The removals are done by the recipe's shell block before the bot sees anything; the rest are instructions in its prompt, so check the bot's first messages.

- **It may read** the output of `vibe-learn briefing --json` and the saved facts in `.vibe-learn/briefing/sessions/*.json`, filtered as below, and `vibe-learn knowledge due`. It does not read `session-log.jsonl`, `pause-summary.txt`, host transcripts, the briefing HTML, or your project files.
- **Its model sees**, for each session: the file paths changed, the first line of each command with its exit code, the failures and the commands that fixed them, counts, and the session's ledger concepts; plus the concepts due for review. With `capture_prompts` on, also the goal, the pause summary, and the prompts in the timeline.
- **It removes before reading** the git diff and the full ledger, always. With `capture_prompts: false` it also removes the prompt fields `goal`, `pause_summary`, `last_turn.prompt`, and the prompt entries of `timeline`, even when an older log still holds prompts captured before you turned capture off.
- **`capture_prompts` does not cover commands.** Command lines stay in what the bot reads, because the digest uses them to explain what broke. A command can carry text from a prompt, or a secret passed on the command line. Set `commands=drop` in the recipe's shell block to remove every facts field that can hold a command line (`commands`, `failures[].command`, `failures[].fixed_by.command`, `last_turn.commands`, the command entries of `timeline`, and `pause_summary`, which lists commands) before the bot reads anything. A command typed into a prompt is prompt text, covered by `capture_prompts`.
- **Its chat message holds** the project's directory name, counts (files changed, failures, how many were fixed), the paths of the digests it wrote, one concept's label with a recall question, and the session's goal only when `capture_prompts` is on. The prompt tells the bot to leave command text, diff text, and file contents out of the message.
- **It may write** digest files under `.vibe-learn/digests/` and your quiz results through `vibe-learn knowledge record`. Nothing else.

To stop a routine, remove its schedule in the bot. Nothing in vibe-learn needs to change.

## Controls

Set these in `.vibe-learn/config.json` (one project) or `~/.vibe-learn/config.json` (all projects). The project file wins.

```json
{ "capture_prompts": false, "health": { "enabled": false, "global_log": false } }
```

- `capture_prompts: false` — turns are still counted, but your prompt text is never written to the log, and the shipped routine removes prompt fields before its bot reads the facts. It does not cover command lines; see [Routines](#routines).
- `health.enabled: false` — stops writing health rows.
- `health.global_log: false` — keeps health rows in the project only.

To delete everything vibe-learn has stored, remove `.vibe-learn/` from the project and `~/.vibe-learn/health.jsonl`.

## Questions

Open an issue at https://github.com/gkaria/vibe-learn/issues.
