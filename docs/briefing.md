# Session briefing and audio

Part of [vibe-learn](../README.md). A local HTML briefing is generated from the same log the learning commands read. This page is how to open it and how to turn it into a NotebookLM audio overview.

---

## Open the briefing

```bash
vibe-learn briefing          # regenerate and show path
```

The briefing is never rebuilt after each response. It is built:

- when you run `vibe-learn briefing` (or `vibe-learn audio-prep` with no pack yet);
- when `/learn` or `/digest` starts: they run `vibe-learn briefing --if-stale`, which returns at once when nothing the page shows has changed since its last complete build: the session's work (the `/learn` or `/digest` turn itself does not count) and `knowledge.json`.

Nothing builds it in the background, so a session's page is as fresh as its last `/learn`, `/digest`, or manual run. Each run builds from a copy of the current session's log and metadata taken when it starts, and each page is written in full before it replaces the old one.

Plugin-only install? The `vibe-learn` CLI is on the Bash tool's PATH inside Claude Code, so just ask Claude to run `vibe-learn briefing`. To have it in your own shell too, run the curl installer — it adds the CLI and skips the duplicate hooks.

The session page opens with three questions, in order:

1. **What was built and why** — the session's goal (its first substantial request, with the turn it came from), the follow-up requests, and the files the work changed, grouped by area.
2. **What to understand** — up to five concepts from your knowledge ledger (`.vibe-learn/knowledge.json`) that live in the files this session changed, each with a new / shaky / solid chip, links to those files, and the `/quiz` prompt to check yourself. `/quiz`, `/explain`, and `/digest` record which files a concept came from; with an older ledger that has no files, the section shows the concepts seen on the session's date instead.
3. **What broke and how it was fixed** — each failed command with the next command that succeeded (same command first, then the same program), still-failing ones first, at most five; the rest are in the command log.

Learning turns (`/learn`, `/digest`, `/quiz`, `/explain`) are left out of all three. Below them, the **Full record** starts collapsed and holds everything else: the session brief and pause summary, the timeline (with filters, and a toggle to show learning turns), the file tour, the command log, the git diff, the study queue, your knowledge state, and the audio export. Once you have a few sessions of [assistant health](health.md) history, an Assistant health card sits between the three questions and the full record: this session's numbers against your usual ones, and the tools and skills the session used. Every page follows your system's light or dark mode.

No server, no build step, no external assets — just a static HTML file that opens directly from disk.

Screenshots of the index and session page live on the README under [What it looks like](../README.md#what-it-looks-like). The health trend page is in [docs/health.md](health.md).

---

## Session facts as JSON

The page, the pack, and the index card are all rendered from one JSON document per session, saved as `.vibe-learn/briefing/sessions/<session>.json`. To use it from a script:

```bash
vibe-learn briefing --json                  # the current session; rebuilds only if stale
vibe-learn briefing --json --session <id>   # an earlier session that has a page
```

The JSON goes to stdout and status lines to stderr. With no session activity, or no page for the requested id, it prints nothing to stdout and exits 1.

The format is versioned by `schema_version`, now `1`. Within a version, fields are only added, never renamed or removed. Version 1:

| Field | Meaning |
|-------|---------|
| `schema_version` | `1` |
| `project`, `date`, `slug`, `generated_at` | project directory name, session date (`YYYY-MM-DD`), page name, build time (UTC) |
| `session_id`, `started_at`, `harness`, `model` | from `session-meta.json`; `null` when unknown |
| `goal`, `goal_turn` | the first substantial work request and its turn; `null` when none |
| `turns` | `{work, learning, last, last_is_learning}` turn counts |
| `files[]` | `{path, created, edited, deleted, turns[]}` per file, paths relative to the project |
| `commands[]` | `{turn, first_line, lines, exit_code}` per work command |
| `failures[]` | `{turn, command, exit_code, fixed_by}`; `fixed_by` is `{turn, command}` of the next command that succeeded, or `null` |
| `last_turn` | the last work turn: `{turn, prompt, files[], commands[]}` |
| `timeline[]` | `{turn, kind, learning, text}` with `kind` one of `prompt`, `command`, `file`; commands add `exit_code`, files add `action` |
| `knowledge` | the whole ledger, `{total, shaky, concepts[]}` with each concept's `name, label, status, sessions, first_seen, last_seen, last_quizzed, files`; `null` without a ledger |
| `concepts[]` | ledger concepts for this session, each with `match`: `files` (they live in files this session changed) or `date` (seen or quizzed on the session's date, used only when no concept matches by file); `files` is narrowed to the files this session changed |
| `diff` | the git diff excerpt, `""` when none |
| `pause_summary` | the session's pause summary, `null` when none |

Learning turns are left out of everything except `timeline` (where `learning` is `true`) and `turns.learning`.

---

## Audio overview with NotebookLM

Every session briefing also produces a markdown source pack at `.vibe-learn/briefing/exports/<session>-notebooklm-pack.md`. It is written to be listened to, from the same facts as the page: it opens with the brief for the audio overview, then tells the session as prose — what you asked for and what the agent built (with one table, of the files), how each turn went, the concepts to understand (what you struggled with, what you met but have not quizzed, what is solid), and each failure with the command that fixed it. Multi-line commands appear as their first line plus a line count. The code excerpt is the git diff plus the files the session wrote that git does not track yet, shown whole (up to 60 lines each; ignored files such as `.env` are never included). Upload it to [NotebookLM](https://notebooklm.google.com).

To prepare the upload in one step:

```bash
vibe-learn audio-prep
```

This:

1. Finds the latest pack in `.vibe-learn/briefing/exports/`
2. Copies the file path to your clipboard
3. Opens NotebookLM in your browser
4. Opens the exports folder in Finder
5. Prints the audio prompt to paste when NotebookLM asks to customise the overview

The pack's first paragraph is the audio prompt, so NotebookLM picks it up from the source; `audio-prep` prints the same paragraph in case you want to paste it. It tells NotebookLM to produce a maintainer-focused overview — what changed, why it matters, what to inspect first, what could break — pitched at someone who owns and needs to support the codebase. Upload the pack as a source, generate an Audio Overview, and listen on your commute.
