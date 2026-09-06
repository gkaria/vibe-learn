## What and why

<!-- One or two sentences. Link the issue if there is one. -->

## Assistants affected

- [ ] Claude Code
- [ ] Codex App/CLI
- [ ] OpenCode
- [ ] Grok Build
- [ ] None (core / docs / tests only)

## Checklist

- [ ] `bats tests/` passes locally and new behaviour has tests
- [ ] Hook scripts (`observe.sh`, `capture-prompt.sh`, `bootstrap.sh`, `pause-summary.sh`) stay silent on stdout and add no slow work
- [ ] `.claude/commands/*` still match `adapters/claude-code/commands/*` (if commands changed)
- [ ] Commands/prompts ported to every adapter that ships them (if a learning command changed)
- [ ] Docs updated where relevant: `README.md`, `CLAUDE.md`, `GETTING_STARTED.md`, `templates/instructions.md`
- [ ] Commit messages follow Conventional Commits (`feat:`, `fix:`, `docs:`, …) so release-please can build the changelog

## How I tested it

<!-- Commands run, hosts tried, anything a reviewer should reproduce. -->
