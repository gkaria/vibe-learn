#!/usr/bin/env bats

load test_helper

@test "bootstrap creates .vibe-learn directory" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"test-123"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  [ -d "$TEST_PROJECT_DIR/.vibe-learn" ]
}

@test "bootstrap creates session-meta.json with session_id" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"test-456"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  local sid
  sid=$(jq -r '.session_id' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$sid" = "test-456" ]
}

@test "bootstrap sets event_count to 0" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s1"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  local count
  count=$(jq '.event_count' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$count" -eq 0 ]
}

@test "bootstrap rotates existing session log to .prev.jsonl" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"event":"old"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s2"}' | bash "$SCRIPTS_DIR/bootstrap.sh"

  [ -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.prev.jsonl" ]
  [ "$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.prev.jsonl")" = '{"event":"old"}' ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" ]
}

@test "bootstrap exits silently when cwd is missing" {
  run bash -c 'echo "{}" | bash '"$SCRIPTS_DIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bootstrap injects prior pause summary as additionalContext" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo "Prior session info" > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s3"}'"'"' | bash '"$SCRIPTS_DIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "bootstrap uses 'unknown' when session_id is missing" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  local sid
  sid=$(jq -r '.session_id' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$sid" = "unknown" ]
}
