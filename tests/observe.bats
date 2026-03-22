#!/usr/bin/env bats

load test_helper

@test "observe logs Write event with file path" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Write","tool_input":{"file_path":"src/app.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.tool')" = "Write" ]
  [ "$(echo "$entry" | jq -r '.file')" = "src/app.ts" ]
  [ "$(echo "$entry" | jq -r '.action')" = "created" ]
  [ "$(echo "$entry" | jq '.context.new_file')" = "true" ]
}

@test "observe logs Edit event" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Edit","tool_input":{"file_path":"src/routes.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.tool')" = "Edit" ]
  [ "$(echo "$entry" | jq -r '.action')" = "edited" ]
}

@test "observe logs MultiEdit event" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"MultiEdit","tool_input":{"file_path":"src/index.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.tool')" = "MultiEdit" ]
  [ "$(echo "$entry" | jq -r '.action')" = "edited" ]
}

@test "observe logs Bash event with command and exit code" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Bash","tool_input":{"command":"npm install"},"tool_response":{"exit_code":0}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.tool')" = "Bash" ]
  [ "$(echo "$entry" | jq -r '.command')" = "npm install" ]
  [ "$(echo "$entry" | jq '.context.exit_code')" = "0" ]
}

@test "observe records non-zero exit code for failed commands" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Bash","tool_input":{"command":"make build"},"tool_response":{"exit_code":2}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local exit_code
  exit_code=$(jq '.context.exit_code' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$exit_code" = "2" ]
}

@test "observe ignores unknown tools" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Read","tool_input":{},"tool_response":{}}'"'"' | bash '"$SCRIPTS_DIR/observe.sh"
  [ "$status" -eq 0 ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" ]
}

@test "observe increments event_count in session-meta.json" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"session_id":"t1","event_count":0}' > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Write","tool_input":{"file_path":"a.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local count
  count=$(jq '.event_count' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$count" -eq 1 ]
}

@test "observe appends multiple events to same log file" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Write","tool_input":{"file_path":"a.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Edit","tool_input":{"file_path":"b.ts"},"tool_response":{}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local line_count
  line_count=$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$line_count" -eq 2 ]
}

@test "observe exits silently when cwd is empty" {
  run bash -c 'echo '"'"'{"tool_name":"Write","tool_input":{"file_path":"x.ts"},"tool_response":{}}'"'"' | bash '"$SCRIPTS_DIR/observe.sh"
  [ "$status" -eq 0 ]
}

@test "observe truncates long bash commands to 200 chars" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  local long_cmd
  long_cmd=$(printf 'x%.0s' {1..300})

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","tool_name":"Bash","tool_input":{"command":"'"$long_cmd"'"},"tool_response":{"exit_code":0}}' \
    | bash "$SCRIPTS_DIR/observe.sh"

  local cmd_len
  cmd_len=$(jq -r '.command | length' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$cmd_len" -le 200 ]
}
