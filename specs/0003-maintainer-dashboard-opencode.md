# Spec 0003: Maintainer Dashboard, Audio Export, and OpenCode Support

**Status:** Proposed
**Target version:** 0.6.0
**Date:** 2026-06-05

## Product Thesis

vibe-learn should become an operational tutor for agent-built software.

As coding agents write more of the code, the user's risk is not missing
documentation; it is losing the ability to own, debug, extend, and support the
system. Project documentation remains the reference layer. vibe-learn should be
the comprehension layer: it turns the evidence of an AI coding session into a
maintainer briefing, study path, and portable learning artifact.

The core promise:

> Agent writes the system. Docs describe the system. vibe-learn teaches you to
> own the system.

## Goals

1. Add an on-demand static HTML dashboard for session learning.
2. Add NotebookLM-ready source pack export for audio companion workflows.
3. Add first-class OpenCode support alongside Claude Code and Codex.
4. Preserve all existing Claude Code, Codex, Obsidian, and hook behavior.
5. Keep vibe-learn lightweight: no build system, no external service calls, and
   no hook-time dashboard generation.

## Non-Goals

- Do not add direct TTS generation in this release.
- Do not integrate with a NotebookLM API in this release.
- Do not run any dashboard work from `PostToolUse`, `Stop`, or other hot hooks.
- Do not replace `/learn`, `/digest`, Codex skills, or Obsidian notes.
- Do not require Node, Vite, React, or a frontend build step.
- Do not change the existing `.vibe-learn/session-log.jsonl` schema in a
  backward-incompatible way.

## Current References

- OpenCode plugins support local JavaScript/TypeScript plugins in
  `.opencode/plugins/` and `~/.config/opencode/plugins/`, with events including
  `tool.execute.after`, `tool.execute.before`, `file.edited`, `session.idle`,
  `permission.asked`, and `permission.replied`:
  <https://opencode.ai/docs/plugins/>
- OpenCode custom commands can be markdown files in `.opencode/commands/` or
  `~/.config/opencode/commands/`; the file name becomes the slash command:
  <https://opencode.ai/docs/commands/>
- OpenCode config supports project `opencode.json` and global
  `~/.config/opencode/opencode.json`:
  <https://opencode.ai/docs/config>
- NotebookLM Audio Overviews are generated from uploaded notebook sources and
  support custom prompts for audience, focus, and expertise level:
  <https://support.google.com/notebooklm/answer/16212820>
- NotebookLM supports markdown/text uploads, pasted text, Google docs, PDFs,
  web URLs, YouTube URLs, and other source types:
  <https://support.google.com/notebooklm/answer/16215270>

## User Experience

### Command Surface

Add a real `vibe-learn` CLI dispatcher while keeping the existing install
behavior:

```text
vibe-learn install [target-dir] [--assistant=...]
vibe-learn dashboard [target-dir]
vibe-learn dashboard --latest [target-dir]
```

The current shim strips `install` and always delegates to `scripts/install.sh`.
Replace it with a dispatcher that preserves `install` behavior exactly and adds
dashboard generation as an on-demand action.

Future alias, not required for v1:

```text
vibe-learn export-audio [target-dir]
```

### Dashboard Output

Generated files live under `.vibe-learn/`, which is already gitignored:

```text
.vibe-learn/
  dashboard/
    index.html
    sessions/
      2026-06-05-vibe-learn.html
    exports/
      2026-06-05-vibe-learn-notebooklm-pack.md
```

Dashboard generation reads:

- `.vibe-learn/session-log.jsonl`
- `.vibe-learn/session-meta.json`
- `.vibe-learn/pause-summary.txt`
- `.vibe-learn/session-log.prev.jsonl` when useful
- `git diff --unified=3` at generation time, capped and optional

### Learning Ladder

Keep the learning surfaces distinct:

1. Pause summary: quick recap after a response.
2. `/learn` or Codex/OpenCode equivalent: focused explanation.
3. `/digest` or equivalent: full session learning report.
4. Maintainer dashboard: interactive operational comprehension artifact.
5. NotebookLM pack: source handoff for audio/listening workflows.

## Dashboard Design

### Visual Direction

Use a warm editorial maintainer cockpit inspired by Anthropic's public design
language, without using Anthropic branding.

Design feel:

- Calm, warm, technical, scannable.
- More field notebook than SaaS dashboard.
- Rich enough for exploration, restrained enough for repeated use.
- Static artifact first; no server and no external network assets.

CSS tokens:

```css
:root {
  --bg: #faf9f5;
  --surface: #f1efe7;
  --surface-2: #e8e6dc;
  --text: #141413;
  --muted: #706f68;
  --line: #d8d4c8;

  --accent: #d97757;
  --accent-blue: #6a9bcc;
  --accent-green: #788c5d;

  --danger: #9f3d32;
  --warning: #b5792a;
  --success: #617a4b;

  --radius: 8px;
  --shadow-soft: 0 1px 2px rgba(20, 20, 19, 0.08);
}
```

Typography:

- Headings: `Poppins, Arial, sans-serif` fallback stack.
- Body: `Lora, Georgia, serif` fallback stack.
- UI labels, buttons, and code: system sans or monospace.
- Do not load remote fonts in v1.

UI rules:

- Cream page background, charcoal text.
- Clay/orange for primary actions and active state.
- Blue for links and export actions.
- Green for success/completed signals.
- Thin borders, subtle shadows, 8px radius.
- No gradient blobs, decorative orbs, or marketing hero.

### Dashboard Index Mockup

```text
+------------------------------------------------------------+
| vibe-learn                                                 |
| Maintainer briefings from your agent-built sessions         |
|                                      [Generate latest]       |
+---------------+--------------------------------------------+
| Filters       | Recent Sessions                             |
|               |                                             |
| Project       | +----------------------------------------+  |
| Harness       | | Jun 5 - vibe-learn                    |  |
| Has failures  | | Codex - 6 files - 4 commands           |  |
| Has audio pack| | Added Codex hooks compatibility        |  |
|               | | [Open briefing] [Audio pack]           |  |
|               | +----------------------------------------+  |
|               |                                             |
|               | +----------------------------------------+  |
|               | | Jun 4 - app-project                   |  |
|               | | Claude Code - 12 files - 8 commands    |  |
|               | +----------------------------------------+  |
+---------------+--------------------------------------------+
```

Index requirements:

- Show session count, project count, and latest session date.
- Filter by project, harness, failures, and audio pack availability.
- Each card shows date, project, harness, goal, event counts, and warnings.
- Cards link to the session page and audio pack when present.
- Index works when opened directly from the filesystem.

### Session Page Mockup

```text
+------------------------------------------------------------+
| vibe-learn / vibe-learn / Jun 5                            |
| [NotebookLM Pack] [Copy Maintainer Brief] [Open Index]     |
+---------------+--------------------------------------------+
| On this page  | Maintainer Brief                           |
|               | +----------------------------------------+  |
| Overview      | | What changed                           |  |
| Timeline      | | Why it matters                         |  |
| Files         | | What to inspect first                   |  |
| Commands      | | What could break                        |  |
| Code excerpts | +----------------------------------------+  |
| Study queue   |                                             |
| Audio export  | Session Timeline                           |
|               | 1. User asked...                          |
|               | 2. Edited adapters/codex/hooks.toml        |
|               | 3. Ran bats tests/                         |
+---------------+--------------------------------------------+
```

Primary layout:

- Sticky left nav.
- Main story/content column.
- First viewport is the maintainer brief, not raw timeline or audio buttons.
- Top action bar includes:
  - Download NotebookLM Pack
  - Copy NotebookLM Prompt
  - Copy Maintainer Brief
  - Back to Index

### Session Components

`MaintainerBrief`

- Four panels:
  - What changed
  - Why it matters
  - Inspect first
  - What could break
- Deterministic content only:
  - touched file categories
  - command failures
  - dependency install commands
  - pause summary
  - changed config/test/auth/db/adapter/script files

`Timeline`

- Chronological list grouped by last user prompt.
- Events: user prompt, file change, command, failure.
- Filters: All, Files, Commands, Failures.
- No hidden content if JavaScript fails.

`FileTour`

- One row per touched file.
- Show action, path, and inferred area:
  - docs
  - tests
  - adapter
  - script
  - config
  - source
- Expand details for diff excerpts when available.

`CommandLog`

- Command string, exit code, and failure badge.
- Failed commands pinned within the section.
- Commands capped to avoid enormous HTML output.

`CodeExcerpts`

- Pull deterministic excerpts from `git diff --unified=3`.
- Cap per file and total rendered excerpt size.
- Include copy button for each excerpt.
- Do not dump full files by default.

`StudyQueue`

- Heuristic checklist.
- Possible items:
  - New dependency installed.
  - Auth, db, config, hook, adapter, or test files touched.
  - Failed command occurred.
  - Build/test command not observed.
- Editable in the browser for export composition only; v1 does not write edits
  back to disk.

`AudioExport`

- Preview what will be exported.
- Buttons:
  - Download NotebookLM Pack
  - Copy NotebookLM Prompt
  - Copy Source Pack

### JavaScript Behavior

Use embedded JavaScript only.

Required enhancements:

- Timeline filtering.
- Section nav active state.
- Expand/collapse file details.
- Copy-to-clipboard buttons with inline confirmation.
- Download generated markdown when browser APIs permit.

Progressive fallback:

- All important content is visible by default.
- The page remains readable with JavaScript disabled.
- No external script, style, image, or font references.

## NotebookLM Audio Export

First version exports a markdown source pack. It does not generate audio.

Output file:

```text
.vibe-learn/dashboard/exports/<date>-<project>-<session>-notebooklm-pack.md
```

Pack structure:

```markdown
# Maintainer Briefing Source Pack

Project:
Session date:
Harness:
Goal:

## What changed

## Why it matters

## Timeline

## Important files

## Commands and failures

## Key code excerpts

## Maintainer questions

## Suggested audio framing

Create a maintainer-focused audio overview. Explain what changed, why it
matters, what to inspect first, and what could break. Assume the listener owns
this codebase and needs enough technical depth to support it.
```

Dashboard copy should say:

- Export for NotebookLM
- Copy audio prompt
- Prepare source pack

Dashboard copy should not say:

- Generate podcast
- Create audio
- Call NotebookLM

## OpenCode Support

### Adapter Layout

Add:

```text
adapters/opencode/
  install.sh
  plugins/vibe-learn.js
  commands/learn.md
  commands/digest.md
```

### Install Behavior

Project install:

```text
.opencode/
  plugins/vibe-learn.js
  commands/learn.md
  commands/digest.md
```

Global install:

```text
~/.config/opencode/
  plugins/vibe-learn.js
  commands/learn.md
  commands/digest.md
```

Detection:

- Existing project `.opencode/` means project OpenCode support.
- `opencode` on `PATH` or `~/.config/opencode/` means global OpenCode support.
- `--assistant=opencode` explicitly installs only OpenCode.
- `--assistant=all` installs OpenCode alongside Claude Code and Codex when
  detected.

### OpenCode Commands

OpenCode supports custom markdown slash commands, so install native:

```text
/learn
/digest
```

Command content should mirror the current Claude Code command behavior as much
as OpenCode allows:

- Read `.vibe-learn/session-log.jsonl`.
- Read relevant touched files.
- Support plain, question, `obsidian`, and `obsidian:recall` modes.
- Mention `vibe-learn dashboard` as the dashboard entrypoint.

### OpenCode Plugin

The OpenCode plugin should bridge events into the existing core scripts when
practical, to preserve the thin-adapter architecture.

Candidate events:

- `session.created` -> call `scripts/bootstrap.sh` equivalent payload.
- `tool.execute.after` -> call `scripts/observe.sh` equivalent payload.
- `file.edited` -> capture file edit signal when tool metadata is insufficient.
- `command.executed` -> optional command UX telemetry.
- `session.idle` -> call `scripts/pause-summary.sh` equivalent payload.
- `permission.asked` and `permission.replied` -> defer logging until a schema is
  defined.

v1 should prefer:

- `tool.execute.after` for tool actions.
- `session.idle` for pause summary.
- `/learn` and `/digest` markdown commands for learning UX.

Permission and richer MCP/custom-tool logging should be documented as future
work unless tests can verify stable payloads.

### OpenCode Risks

- Plugin event payloads need fixture capture or docs-backed tests before final
  schema mapping.
- OpenCode local plugins are JavaScript/TypeScript, while vibe-learn core is
  Bash + jq.
- If calling shell scripts from the plugin is awkward, add a small dedicated
  `scripts/observe-opencode.sh` adapter shim rather than bloating
  `observe.sh`.

## Backward Compatibility Checklist

Before implementation is considered complete, verify:

- Existing `.vibe-learn/session-log.jsonl` files remain readable.
- Existing Claude Code `/learn` and `/digest` commands keep working.
- Existing Codex skill keeps working.
- Existing Codex prompt fallbacks keep working.
- Existing Obsidian save and recall flows keep working.
- `vibe-learn install` still behaves as today.
- `scripts/setup.sh --assistant=claude-code` still works.
- `scripts/setup.sh --assistant=codex` still works.
- `scripts/setup.sh --assistant=all` still works.
- Project install detection still prioritizes existing `.claude/` and `.codex/`
  directories correctly.
- Adding OpenCode detection does not cause Claude/Codex-only projects to receive
  unexpected `.opencode/` files.
- Existing hook scripts stay fast and do not render dashboards.
- No dashboard generation runs from `PostToolUse` or `Stop`.
- Generated dashboard files stay under `.vibe-learn/`.
- Generated dashboard files remain ignored by git through existing
  `.vibe-learn/` ignore behavior.
- Generated HTML has no external network dependencies.
- Viewing generated HTML does not require a local server.
- No new required runtime dependency is introduced unless documented, installed,
  and tested.
- Existing Bats tests remain green.

## Verification Loop

Use this loop during implementation.

### Before Editing

1. Run `git status --short --branch`.
2. Confirm existing uncommitted work is understood and preserved.
3. Work on a feature branch.
4. Identify the subsystem being changed before editing.

### After Each Subsystem

1. Run focused tests for the changed subsystem.
2. Inspect `git diff --stat`.
3. Confirm no unrelated files changed.
4. Confirm generated artifacts, if any, live under `.vibe-learn/` or test temp
   directories.

### Dashboard Verification

1. Generate a dashboard from fixture logs.
2. Confirm `index.html` is generated.
3. Confirm a session HTML page is generated.
4. Confirm session links from the index point to existing files.
5. Confirm the page contains no `http://` or `https://` asset references.
6. Confirm timeline, file tour, command log, code excerpts, study queue, and
   audio export sections are present.
7. Confirm missing or empty logs produce a helpful message and no crash.
8. Confirm large commands and diff excerpts are capped.
9. Confirm NotebookLM markdown pack is generated.
10. Confirm generated HTML is readable without JavaScript.

### OpenCode Verification

1. Project install creates `.opencode/plugins/vibe-learn.js`.
2. Project install creates `.opencode/commands/learn.md`.
3. Project install creates `.opencode/commands/digest.md`.
4. Global install writes to `~/.config/opencode/plugins/`.
5. Global install writes to `~/.config/opencode/commands/`.
6. `--assistant=opencode` installs only OpenCode support.
7. `--assistant=all` includes OpenCode when detected.
8. Auto-detection works when `opencode` exists on `PATH`.
9. Auto-detection works when `~/.config/opencode/` exists.
10. Install is idempotent.
11. Claude Code and Codex install tests remain green.
12. If OpenCode is available locally, run a manual smoke test and capture a
    minimal session log.

### Full Regression

1. Run `bats tests/`.
2. Run README manual smoke commands.
3. Run `git diff --stat`.
4. Confirm no tracked `.vibe-learn/` artifacts were added.
5. Confirm docs match implemented command names and paths.

## Test Plan

Add or update Bats tests for:

- CLI dispatch:
  - `vibe-learn install`
  - `vibe-learn dashboard`
  - unknown subcommand failure
- Dashboard:
  - empty/missing log handling
  - basic session HTML generation
  - index generation
  - NotebookLM pack generation
  - no external asset references
  - output path safety
  - command/diff truncation
- OpenCode:
  - project install
  - global install
  - command install
  - plugin install
  - detection through `.opencode/`
  - detection through `opencode` on `PATH`
  - `--assistant=opencode`
  - `--assistant=all`
  - idempotency
- Existing regression:
  - bootstrap
  - capture-prompt
  - observe
  - pause-summary
  - Claude Code install
  - Codex install
  - Obsidian prompts

## Rollout Phases

### Phase 1: Spec Only

- Add this spec.
- Do not change runtime behavior.

### Phase 2: CLI and Dashboard Foundation

- Add CLI dispatcher.
- Add deterministic dashboard renderer.
- Generate index, session page, and NotebookLM pack from existing logs.
- Keep hooks unchanged.

### Phase 3: Dashboard UX

- Apply final warm editorial design.
- Add embedded JS interactions.
- Add source pack preview and copy/download actions.

### Phase 4: OpenCode Adapter

- Add `adapters/opencode/`.
- Add plugin and command install.
- Add setup/install detection.
- Add OpenCode tests.

### Phase 5: Docs and Compatibility Sweep

- Update README.
- Update CLAUDE.md.
- Update changelog/release notes.
- Run full regression and manual smoke checks.

## Open Questions

- Whether OpenCode event payloads contain enough stable information to call the
  existing `observe.sh` directly, or whether a small OpenCode-specific shim is
  cleaner.
- Whether dashboard generation should snapshot the current `git diff`, or only
  render file names and commands until a richer normalized event schema exists.
- Whether the first dashboard should render the current session only, or also
  include `session-log.prev.jsonl` as a prior-session comparison.
