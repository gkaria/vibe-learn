# Codex Hooks 0.5.6 Release Plan

**Target version:** 0.5.6
**Date:** 2026-05-13

## Objective

Review vibe-learn's Codex hook adapter against the current Codex hook behavior, identify recent upstream changes, and define the scoped changes to release as `v0.5.6`.

## Current Implementation

vibe-learn currently installs Codex hooks inline in `.codex/config.toml` or `~/.codex/config.toml` from `adapters/codex/hooks.toml`.

Registered Codex hooks:

- `SessionStart` -> `scripts/bootstrap.sh`
- `UserPromptSubmit` -> `scripts/capture-prompt.sh`
- `PostToolUse` with matcher `^(Bash|apply_patch)$` -> `scripts/observe.sh`
- `Stop` -> `scripts/pause-summary.sh`

The adapter also enables:

```toml
[features]
hooks = true
```

Hooks are enabled by default in current Codex. The canonical feature key is
`hooks`; `codex_hooks` still works as a deprecated alias. vibe-learn should use
`hooks = true` in new installs and migrate the deprecated alias when updating an
existing config.

## Upstream Codex Changes

Sources checked:

- OpenAI Codex hooks documentation: https://developers.openai.com/codex/hooks
- OpenAI Codex `rust-v0.124.0` release notes: https://github.com/openai/codex/releases/tag/rust-v0.124.0
- OpenAI Codex `rust-v0.129.0` release notes: https://github.com/openai/codex/releases/tag/rust-v0.129.0

Relevant changes:

1. Hooks are documented as stable and enabled by default.
2. The canonical feature key is `features.hooks`; `codex_hooks` is deprecated.
3. Codex now supports both `hooks.json` and inline `[hooks]` tables in `config.toml`.
4. Codex merges matching hooks from multiple hook sources instead of overriding lower-precedence hooks.
5. Project-local hooks require the project `.codex/` layer to be trusted.
6. `PreToolUse`, `PermissionRequest`, `PostToolUse`, `PreCompact`, `PostCompact`, `UserPromptSubmit`, `SubagentStop`, and `Stop` run at turn scope.
7. `PermissionRequest` is now a documented hook event.
8. `PostToolUse` can observe Bash, `apply_patch`, and MCP tool calls.
9. `apply_patch` matchers can use `apply_patch`, `Edit`, or `Write`; hook input still reports `tool_name: "apply_patch"`.
10. `SessionStart` matchers apply to source values such as `startup`, `resume`, `clear`, and `compact`.
11. `timeout` and `statusMessage` belong on command handlers, not matcher groups.
12. `Stop` expects JSON stdout. Plain text stdout is invalid for `Stop`.

## Compatibility Assessment

What already looks compatible:

- Inline TOML hook configuration is now explicitly supported.
- The existing `codex_hooks = true` feature flag should be migrated to canonical `hooks = true`.
- The current `PostToolUse` matcher includes `apply_patch`, which is the canonical tool name Codex reports for file edits.
- `pause-summary.sh` returns JSON for Codex `Stop` hook events.
- `bootstrap.sh` already emits `hookSpecificOutput.hookEventName = "SessionStart"` with `additionalContext`, which Codex now documents as supported.

Gaps and risks:

- Docs still describe Codex Stop continuity as a fallback because older Codex support was uncertain; this should be updated now that the current contract is documented.
- README and CLAUDE.md do not mention `PermissionRequest`, MCP tool hook coverage, trusted project hook layers, or hook merging behavior.
- The installer tests only assert `Bash|apply_patch`; they do not protect the current documented alias behavior for `Edit|Write` or possible MCP matcher expansion.
- The current `PostToolUse` matcher ignores MCP tool calls. That is acceptable for file/command learning, but now leaves observable MCP activity out of vibe-learn session logs.
- `observe.sh` only handles `Bash`, `Write`, `Edit`, `MultiEdit`, and `apply_patch`; it exits for MCP tool names.
- `pause-summary.sh` writes Codex `Stop` output as `{"continue":true}` and relies on next-session `SessionStart` for summary injection. That is safe, but the docs should state this explicitly rather than implying Codex Stop additionalContext is unsupported.

## 0.5.6 Scope

### Required

1. Update Codex documentation in `README.md` and `CLAUDE.md`.
   - State that Codex supports inline `[hooks]` and `hooks.json`.
   - Keep inline TOML as vibe-learn's chosen install format.
   - Document that multiple hook sources are merged and project-local hooks require trust.
   - Mention current hook coverage: Bash, `apply_patch`, and MCP tool calls for `PostToolUse`.
   - Clarify that vibe-learn currently logs Bash and `apply_patch` file edits, not arbitrary MCP tool calls.

2. Add a Codex hooks compatibility note to the changelog for `0.5.6`.
   - Use this as release-note material before tagging.

3. Add or update tests around Codex hook config behavior.
   - Preserve canonical `hooks = true`.
   - Preserve inline TOML hook registration.
   - Assert `Stop` hook output remains valid JSON for Codex.
   - Add a doc/fixture assertion for the documented `apply_patch` alias behavior if the matcher changes.

### Recommended

4. Add explicit `timeout` and `statusMessage` fields to Codex command handler registrations.
   - Current Codex default timeout is documented as 600 seconds.
   - vibe-learn hooks should be quick and predictable.
   - Suggested values:
     - `SessionStart`: `timeout = 5`
     - `UserPromptSubmit`: `timeout = 5`
     - `PostToolUse`: `timeout = 2`
     - `Stop`: `timeout = 10`

5. Consider widening the `PostToolUse` matcher to include documented aliases:

```toml
matcher = "^(Bash|apply_patch|Edit|Write)$"
```

This does not change the hook input shape, but makes the intent clearer against the current Codex docs.

### Deferred

6. MCP tool logging.
   - New Codex support makes this possible, but it needs a schema decision before release.
   - Proposed future event shape:

```json
{"timestamp":"...","event":"tool_use","tool":"mcp__server__tool","action":"called","context":{"mcp":true}}
```

Do not include this in 0.5.6 unless there is a concrete learning use case and tests for payload variation.

7. `PermissionRequest` support.
   - vibe-learn is observational, not a policy engine.
   - Do not register `PermissionRequest` hooks in 0.5.6.
   - Document that this hook exists upstream but is intentionally out of scope.

## Release Checklist

1. Implement the required docs and tests.
2. Decide whether to include the recommended timeout/statusMessage updates.
3. Run:

```bash
bats tests/
```

4. Verify version files before release:

```bash
cat VERSION
rg -n '0\.5\.5|0\.5\.6' VERSION scripts/setup.sh .release-please-manifest.json CHANGELOG.md
```

5. Release:

```bash
bash scripts/release.sh 0.5.6
git push && git push --tags
```

## Non-Goals

- Do not migrate Codex installs from inline TOML to `hooks.json` in this release.
- Do not add governance or approval behavior.
- Do not rely on Codex hooks as a complete enforcement boundary.
- Do not release `0.5.6` until tests pass and release notes are updated.
