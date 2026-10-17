#!/usr/bin/env bats

load test_helper

# doctor.sh (`vibe-learn doctor`) against a fresh setup.sh install in a fake
# HOME: what passes, and each thing that must fail it.

setup() {
  TEST_PROJECT_DIR="$(mktemp -d)"
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME" TEST_PROJECT_DIR
  INSTALL="$HOME/.vibe-learn"
  mkdir -p "$HOME/.claude"
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code >/dev/null
  cd "$TEST_PROJECT_DIR"
}

doctor() { run bash "$INSTALL/scripts/cli.sh" doctor "$@"; }

@test "a fresh install passes, and lists hosts that are not set up" {
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ jq "* ]]
  [[ "$output" == *"✓ vibe-learn "*" at ~/.vibe-learn ("* ]]
  [[ "$output" == *"✓ Claude Code: hooks in ~/.claude/settings.json"* ]]
  [[ "$output" == *"- Codex: not set up"* ]]
  [[ "$output" == *"All checks passed."* ]]
  # Run from $HOME, the global settings file is also the project's: one line.
  doctor "$HOME"
  [ "$(grep -c "Claude Code: hooks in" <<<"$output")" -eq 1 ]
}

@test "a missing briefing template or a non-executable hook script fails" {
  rm "$INSTALL/scripts/lib/briefing-session.html"
  chmod -x "$INSTALL/scripts/observe.sh"
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ missing scripts/lib/briefing-session.html; reinstall vibe-learn"* ]]
  [[ "$output" == *"✗ scripts/observe.sh is not executable"* ]]
  [[ "$output" == *"2 problem(s) found."* ]]
}

@test "missing jq fails at once" {
  local bin="$BATS_TEST_TMPDIR/bin"
  mkdir -p "$bin"
  ln -s "$(command -v dirname)" "$bin/dirname"
  run env PATH="$bin" "$BASH" "$INSTALL/scripts/doctor.sh"
  [ "$status" -eq 1 ]
  [[ "$output" == *"✗ jq not found"* ]]
}

@test "a hook that points at a moved install fails, on every host format" {
  # Register every host from a copy of the install, then delete the copy.
  local moved="$BATS_TEST_TMPDIR/moved vl" a
  cp -R "$INSTALL" "$moved"
  for a in codex grok cursor copilot-cli opencode; do
    bash "$moved/adapters/$a/install.sh" --global "$moved" >/dev/null
  done
  rm -rf "$moved"
  doctor
  [ "$status" -eq 1 ]
  for a in "Codex: ~/.codex/config.toml" "Grok Build: ~/.grok/hooks/vibe-learn.json" \
           "Cursor: ~/.cursor/hooks.json" "GitHub Copilot CLI: ~/.copilot/hooks/vibe-learn.json" \
           "OpenCode: ~/.config/opencode/plugins/vibe-learn.js"; do
    [[ "$output" == *"✗ $a points at $moved/scripts/"* ]] || { echo "not flagged: $a"; return 1; }
  done
  [[ "$output" == *"✓ Claude Code: hooks in ~/.claude/settings.json"* ]]
}

@test "the plugin alone counts as set up; plugin plus settings hooks warns about double logging" {
  echo '{"enabledPlugins":{"vibe-learn@vibe-learn":true}}' > "$HOME/.claude/settings.json"
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ Claude Code: vibe-learn plugin enabled in ~/.claude/settings.json"* ]]
  refute_grep "double" <<<"$output"

  mkdir -p .claude
  echo "{\"hooks\":{\"Stop\":[{\"hooks\":[{\"type\":\"command\",\"command\":\"$INSTALL/scripts/pause-summary.sh\"}]}]}}" > .claude/settings.local.json
  doctor
  [[ "$output" == *"! Claude Code: the plugin and settings hooks are both active"* ]]
}

@test "config: malformed files and keys nothing reads fail; known keys pass" {
  mkdir -p .vibe-learn
  # A copy of defaults.json, _comment included, is a valid config.
  cp "$INSTALL/config/defaults.json" "$HOME/.vibe-learn/config.json"
  echo '{"log_dir":".vl","health":{"enabled":true,"min_event":3}}' > .vibe-learn/config.json
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *"✓ ~/.vibe-learn/config.json"* ]]
  [[ "$output" == *"✗ $TEST_PROJECT_DIR/.vibe-learn/config.json: nothing reads log_dir, health.min_event; remove it"* ]]

  echo '[1]' > "$HOME/.vibe-learn/config.json"
  echo 'not json' > .vibe-learn/config.json
  doctor
  [[ "$output" == *"✗ ~/.vibe-learn/config.json is not a JSON object"* ]]
  [[ "$output" == *"✗ $TEST_PROJECT_DIR/.vibe-learn/config.json is not a JSON object"* ]]
}

@test "project: the last session's counts, a missing Stop, bad log lines, and the ledger" {
  mkdir -p .vibe-learn
  echo '{"session_id":"s-42","started_at":"2026-10-17T09:00:00Z"}' > .vibe-learn/session-meta.json
  printf '%s\n' '{"event":"user_prompt","prompt":"hi"}' \
    '{"event":"tool_use","tool":"Write","file":"a.js","action":"created"}' \
    '{"event":"tool_use","tool":"Bash","command":"npm test","action":"ran"}' \
    '{"event":"tool_use","tool":"Edit","file":"a.' > .vibe-learn/session-log.jsonl
  echo '{"version":1,"concepts":[{"name":"a"}]}' > .vibe-learn/knowledge.json
  doctor
  [ "$status" -eq 0 ]
  [[ "$output" == *"✓ last session s-42 (started 2026-10-17T09:00:00Z): 2 tool event(s), 0 finished turn(s)"* ]]
  [[ "$output" == *"! no Stop hook has run this session"* ]]
  [[ "$output" == *"! session log has 1 line(s) that are not JSON objects"* ]]
  [[ "$output" == *"✓ knowledge ledger: 1 concept(s)"* ]]

  echo '{"event":"turn_end","turn":1}' >> .vibe-learn/session-log.jsonl
  echo '{"concepts":{}}' > .vibe-learn/knowledge.json
  doctor
  [ "$status" -eq 1 ]
  [[ "$output" == *", 1 finished turn(s)"* ]]
  refute_grep "no Stop hook" <<<"$output"
  [[ "$output" == *"is not a valid knowledge ledger"* ]]
}

@test "doctor checks its arguments" {
  doctor "$TEST_PROJECT_DIR/nope"
  [ "$status" -eq 1 ]
  [ "$output" = "ERROR: no such directory: $TEST_PROJECT_DIR/nope" ]
  doctor --fix
  [ "$status" -eq 1 ]
  doctor --help
  [ "$status" -eq 0 ]
  [[ "$output" == "doctor.sh — \`vibe-learn doctor [target-dir]\`"* ]]
}
