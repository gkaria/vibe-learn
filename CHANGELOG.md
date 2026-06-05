# Changelog

## [0.6.0](https://github.com/gkaria/vibe-learn/compare/v0.5.6...v0.6.0) (2026-06-05)

This release makes the learning layer passive.

In earlier versions, vibe-learn captured your session and waited for you to ask.
You had to remember to type `/learn` or `/digest` to get anything out of it.
That was the gap.

In v0.6.0, after every agent response that touches files or runs commands,
vibe-learn automatically generates a session briefing in the background — a local
static HTML page with everything you need to own what was just built. You don't
run a command. It's just there.


### Session briefing

Open `.vibe-learn/briefing/index.html` in any browser to see:

- **Session brief** — what changed, why it matters, what to inspect first, what could break
- **Timeline** — every prompt, file change, and command, with filter buttons
- **File tour** — colour-coded area tags (adapter, script, config, tests, auth, database, docs, source)
- **Command log** — with failure highlighting
- **Syntax-highlighted git diff**
- **Study queue** — dynamic checklist based on what actually happened: new deps installed, failed commands, auth files touched, missing test run, and more
- **NotebookLM source pack** — ready for audio overview workflows

No server. No build step. No external assets. Opens directly from disk.

```
vibe-learn briefing       regenerate and show path
```


### Audio overview workflow

Every briefing also writes a markdown source pack to `.vibe-learn/briefing/exports/`.
One command prepares the full upload:

```
vibe-learn audio-prep
```

This finds the latest pack, copies the path to your clipboard, opens NotebookLM in
your browser, opens the exports folder in Finder, and prints the audio prompt to
paste. Upload the pack, paste the prompt, generate — you get an 8–15 minute
two-host conversation explaining your session back to you, pitched at someone who
needs to maintain the codebase.


### OpenCode support

vibe-learn now works with OpenCode via a local JavaScript plugin and native `/learn`
and `/digest` markdown commands. Detected and installed automatically alongside
Claude Code and Codex.

```
/learn
/learn why did we add middleware?
/digest
```


### Turn-structured session log

Every event in `session-log.jsonl` is now tagged with a turn number — the prompt it
belongs to. This makes `/learn` and `/digest` significantly more precise: instead of
guessing which files relate to which prompt, they can say "in response to your second
prompt, these five files were created." The turn counter persists in
`session-meta.json` and increments automatically on every `UserPromptSubmit`.


### Also in this release

- **GETTING_STARTED.md** — step-by-step first session walkthrough with expected
  output at each step
- **README rewrite** — under 200 lines, user-focused, with screenshots
- **Codex hook compatibility** — `hooks = true` flag (replaces deprecated
  `codex_hooks`), explicit timeouts and status messages, `apply_patch` matcher
  aliases aligned with Codex documentation
- **CLI dispatcher** — `vibe-learn` is now a proper command dispatcher;
  `vibe-learn install`, `vibe-learn briefing`, `vibe-learn audio-prep`
- **138 tests** (up from 100 in v0.5.5)


## [0.5.6](https://github.com/gkaria/vibe-learn/compare/v0.5.5...v0.5.6) (2026-05-14)


### Documentation

* document current Codex hook behavior, including inline TOML and hooks.json support, hook source merging, trusted project hook layers, the canonical `hooks` feature flag, and MCP/PermissionRequest scope
* clarify Codex Stop handling: pause summaries are written to disk and Stop returns Codex-compatible JSON while SessionStart provides continuity


### Tests

* protect Codex hook registration for the `hooks` feature flag, inline TOML hooks, explicit command-handler timeouts/status messages, and documented `apply_patch` matcher aliases


## [0.5.5](https://github.com/gkaria/vibe-learn/compare/v0.5.1...v0.5.5) (2026-05-05)


### Features

* add multi-assistant support for Claude Code and Codex App/CLI, with assistant-specific adapters, hooks, prompts, and install scripts ([59f4ad4](https://github.com/gkaria/vibe-learn/commit/59f4ad4ea8ae6e83c671c8037973a3a4a61fbecd))
* add Codex-aware install defaults that configure all relevant detected assistants, including existing Codex installs ([5377060](https://github.com/gkaria/vibe-learn/commit/53770607433196a25a5c9df35380ff1c13a83895))
* install a global Codex `vibe-learn` skill with project prompt fallbacks ([5377060](https://github.com/gkaria/vibe-learn/commit/53770607433196a25a5c9df35380ff1c13a83895))
* expand Codex session logging to include `apply_patch` file edits for complete learning and digest context ([5377060](https://github.com/gkaria/vibe-learn/commit/53770607433196a25a5c9df35380ff1c13a83895))


### Documentation

* document Codex App usage, Obsidian examples, mission statement, and roadmap direction ([5377060](https://github.com/gkaria/vibe-learn/commit/53770607433196a25a5c9df35380ff1c13a83895))

## [0.5.1](https://github.com/gkaria/vibe-learn/compare/v0.5.0...v0.5.1) (2026-04-10)


### Bug Fixes

* add x-release-please-version marker to setup.sh ([4624daf](https://github.com/gkaria/vibe-learn/commit/4624daf5d91b9f748b02c4f1530f4a8bacc725a1))
* create GitHub Release with notes when a version tag is pushed ([4050fb0](https://github.com/gkaria/vibe-learn/commit/4050fb04bfa3cdf74b0eee0c06b536c72b717ca9))
* extract CHANGELOG.md section as release notes instead of auto-generated notes ([49b7c5b](https://github.com/gkaria/vibe-learn/commit/49b7c5bd52ddd68053aa1b4a46b8295d6613fc55))
* update release.sh to handle manifest and doc-only version references ([17d4dfc](https://github.com/gkaria/vibe-learn/commit/17d4dfc0cd39df892ca3d5a0a15c89248d0a8adf))

## [0.3.0](https://github.com/gkaria/vibe-learn/compare/v0.2.0...v0.3.0) (2026-04-01)


### Features

* add CI and release-please GitHub Actions workflows ([169726e](https://github.com/gkaria/vibe-learn/commit/169726ebb98f48a6f39416a8bc6d675cc27044cf))
* add hookMatcher for PostToolUse and set minMCSVersion ([c87bd34](https://github.com/gkaria/vibe-learn/commit/c87bd34191c87eb0f41562f6b8d7ce59ed799664))
* add MCS techpack for distributing vibe-learn as a Claude Code pack ([f9a9674](https://github.com/gkaria/vibe-learn/commit/f9a9674992b419eb9bbc72cafb8d7ccd429efa3a))
* add MCS techpack manifest for pack distribution ([94eb9a8](https://github.com/gkaria/vibe-learn/commit/94eb9a8338a30ca5bc52b650672999cb0da905f5))


### Bug Fixes

* add retry resilience to setup downloads ([f8f4db0](https://github.com/gkaria/vibe-learn/commit/f8f4db0c2128405005887c0ec1d4cb1eed882bc0))
* configure release-please manifest packages map ([657599e](https://github.com/gkaria/vibe-learn/commit/657599e1b5138e111bd256bbbcaf7a2e4007e97e))


### Miscellaneous Chores

* force release ([da30912](https://github.com/gkaria/vibe-learn/commit/da309126ea4ff9d1a399223bb66c7f06401886e1))
