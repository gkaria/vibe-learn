# PROTOTYPE: `vibe-learn boundary`

Throwaway code on the `prototype/boundary-report` branch. It is not installed by
`setup.sh`, not in the techpack, and not meant to merge as is.

## The question

Can the session log vibe-learn already keeps, plus the host transcript read at
report time, show a developer what the assistant reached for outside the code
(hosts, risky commands, sensitive paths, changes the prompt did not ask for)
in a way that is useful to learn from, without hook changes and without
pretending to be a security control?

## Run it

```bash
bin/vibe-learn boundary --demo          # generated sample session
bin/vibe-learn boundary path/to/project # a real project with .vibe-learn/
bin/vibe-learn boundary --demo --json   # the facts object
```

## What it reads

| Source | Gives |
|---|---|
| `.vibe-learn/session-log.jsonl` | prompts, turns, commands (200 chars), files written |
| `.vibe-learn/session-log.prev.jsonl` | hosts "seen before" |
| host transcript (`transcript_path`, Claude Code only here) | full command text past the 200-char cut, `WebFetch`/`WebSearch`, MCP servers, file reads, subagent runs |
| `.vibe-learn/policy.json`, `~/.vibe-learn/policy.json` | `allowed_hosts` (exact or `*.suffix`), `protected_paths` (globs) |
| `git remote get-url origin` | the host behind a bare `git push` |

## What it reports

- **Network reach**: hosts named in commands (URLs, `git@host:`, `ssh`/`curl`
  targets), hosts implied by package managers, `gh` and `git`, plus `WebFetch`, web
  search and MCP servers. Each is marked new or seen before, allowed or not, or local.
- **Risky commands**: 17 shape rules (`boundary.jq` `risk_rules`), each with a
  one-line "why". Secret values are redacted before display.
- **Sensitive paths**: writes, plus reads of secrets and outside-the-project
  files, sorted into categories (secrets, assistant config, CI, dependencies,
  shell startup, vibe-learn's own log, protected by policy, …).
- **Scope surprises**: a work turn wrote in a sensitive category its prompt
  never mentions (keywords in `scope_words`).
- **What this can't see**: the blind spots for this session (child processes,
  cut commands, missing transcript, subagents, prompts not captured, no
  policy, one-session baseline, a log the assistant can edit).

## Known gaps, for the spec

- Transcript reading covers Claude Code only. Codex, Cursor, Grok and OpenCode
  can reuse the sources in `scripts/usage.sh`.
- The baseline is one previous session. A per-project host history (rows of
  hostnames at rotation, like `health.jsonl`) would make "new" meaningful.
- The declared boundary (each assistant's sandbox and permission settings) is not read yet.
  That is Phase 2: `identity.sh` records it at SessionStart.
- Scope surprises use keyword matching. Expect false positives on loosely worded prompts.
- Host and pattern detection is regex over command text. Quoting,
  variables and aliases can hide a host.
