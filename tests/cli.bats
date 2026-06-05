#!/usr/bin/env bats

load test_helper

@test "cli help prints usage" {
  run bash "$SCRIPTS_DIR/cli.sh" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "vibe-learn install"
  echo "$output" | grep -q "vibe-learn briefing"
}

@test "cli install dispatches to installer" {
  run bash "$SCRIPTS_DIR/cli.sh" install "$TEST_PROJECT_DIR" --assistant=opencode
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
}

@test "cli preserves directory-first install compatibility" {
  run bash "$SCRIPTS_DIR/cli.sh" "$TEST_PROJECT_DIR" --assistant=opencode
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/digest.md" ]
}

@test "cli briefing dispatches to dashboard renderer" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"timestamp":"2026-06-05T10:00:00Z","event":"user_prompt","prompt":"explain cli dispatch"}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  run bash "$SCRIPTS_DIR/cli.sh" briefing "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
}

@test "cli unknown command fails clearly" {
  run bash "$SCRIPTS_DIR/cli.sh" not-a-command
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unknown command 'not-a-command'"
}

@test "cli audio-prep fails with helpful message when no briefing exists" {
  run bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  [ "$status" -ne 0 ]
  echo "$output" | grep -qi "briefing"
}

@test "cli audio-prep finds and reports the latest NotebookLM pack" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports"
  echo "# pack" > "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports/2026-06-05-proj-abc-notebooklm-pack.md"

  run bash "$SCRIPTS_DIR/cli.sh" audio-prep "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "notebooklm-pack.md"
  echo "$output" | grep -qi "notebooklm"
}
