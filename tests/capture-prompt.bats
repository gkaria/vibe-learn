#!/usr/bin/env bats

load test_helper

@test "capture-prompt logs user prompt to session log" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Build me an API"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.event')" = "user_prompt" ]
  [ "$(echo "$entry" | jq -r '.prompt')" = "Build me an API" ]
}

@test "capture-prompt includes timestamp" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Hello"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local ts
  ts=$(jq -r '.timestamp' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "capture-prompt truncates long prompts to 500 chars" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  local long_prompt
  long_prompt=$(printf 'a%.0s' {1..700})

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"'"$long_prompt"'"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local prompt_len
  prompt_len=$(jq -r '.prompt | length' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$prompt_len" -le 500 ]
}

@test "capture-prompt exits silently when cwd is missing" {
  run bash -c 'echo '"'"'{"prompt":"Hello"}'"'"' | bash '"$SCRIPTS_DIR/capture-prompt.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "capture-prompt creates .vibe-learn dir if missing" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"test"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"
  [ -d "$TEST_PROJECT_DIR/.vibe-learn" ]
}

@test "capture-prompt appends to existing log" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"First"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Second"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local line_count
  line_count=$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$line_count" -eq 2 ]
}
