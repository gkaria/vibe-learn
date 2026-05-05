#!/usr/bin/env bats

load test_helper

# Helper: seed a session log with a prompt and some tool events
seed_session_log() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Build an API"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Write","file":"src/app.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:00:10Z","event":"tool_use","tool":"Edit","file":"src/index.ts","action":"edited","context":{}}
{"timestamp":"2026-03-17T14:00:15Z","event":"tool_use","tool":"Bash","command":"npm install","action":"ran","context":{"exit_code":0}}
JSONL
}

@test "pause-summary outputs valid JSON with additionalContext" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.hookSpecificOutput.additionalContext' >/dev/null
}

@test "pause-summary outputs Codex Stop-compatible JSON" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.continue == true' >/dev/null
  echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

@test "pause-summary includes goal from last user prompt" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "Build an API"
}

@test "pause-summary lists created files" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "Created src/app.ts"
}

@test "pause-summary lists edited files" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "Edited src/index.ts"
}

@test "pause-summary lists apply_patch file changes" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Patch files"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"apply_patch","file":"src/new.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:00:10Z","event":"tool_use","tool":"apply_patch","file":"src/app.ts","action":"edited","context":{}}
{"timestamp":"2026-03-17T14:00:15Z","event":"tool_use","tool":"apply_patch","file":"src/old.ts","action":"deleted","context":{}}
JSONL

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "Created src/new.ts"
  echo "$output" | grep -q "Edited src/app.ts"
  echo "$output" | grep -q "Deleted src/old.ts"
}

@test "pause-summary lists bash commands" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "npm install"
}

@test "pause-summary writes pause-summary.txt file" {
  seed_session_log
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'"}' | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
  grep -q "Build an API" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary flags failed commands" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Run tests"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
JSONL

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "failed"
}

@test "pause-summary exits silently when no session log exists" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pause-summary exits silently when no tool events occurred" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Hello"}' \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pause-summary exits silently when cwd is missing" {
  run bash -c 'echo '"'"'{}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "pause-summary only shows events after last prompt" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"First task"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Write","file":"old.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:01:00Z","event":"user_prompt","prompt":"Second task"}
{"timestamp":"2026-03-17T14:01:05Z","event":"tool_use","tool":"Write","file":"new.ts","action":"created","context":{"new_file":true}}
JSONL

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  echo "$output" | grep -q "Created new.ts"
  ! echo "$output" | grep -q "Created old.ts"
}
