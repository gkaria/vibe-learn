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

# Run the Stop hook as Claude Code does; $output is then pause-summary.txt.
summarize() {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}' | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  output="$(cat "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" 2>/dev/null)"
}

@test "pause-summary never emits additionalContext, and nothing without a hook event" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  grep -q "Build an API" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary outputs Codex Stop-compatible JSON" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.continue == true' >/dev/null
  echo "$output" | jq -e 'has("hookSpecificOutput") | not' >/dev/null
}

@test "pause-summary includes the session goal" {
  seed_session_log
  summarize
  echo "$output" | grep -q "Build an API"
}

@test "pause-summary lists created files" {
  seed_session_log
  summarize
  echo "$output" | grep -q "Created src/app.ts"
}

@test "pause-summary lists edited files" {
  seed_session_log
  summarize
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

  summarize
  echo "$output" | grep -q "Created src/new.ts"
  echo "$output" | grep -q "Edited src/app.ts"
  echo "$output" | grep -q "Deleted src/old.ts"
}

@test "pause-summary lists bash commands" {
  seed_session_log
  summarize
  echo "$output" | grep -q "npm install"
}

@test "pause-summary writes pause-summary.txt file" {
  seed_session_log
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'"}' | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
  grep -q "Build an API" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary does not treat failed file operations as changes" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Add a helper"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Write","file":"src/ok.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:00:06Z","event":"tool_use","tool":"Write","file":"src/fail.ts","action":"failed","context":{"failed":true}}
{"timestamp":"2026-03-17T14:00:07Z","event":"tool_use","tool":"Edit","file":"src/also-fail.ts","action":"failed","context":{"failed":true}}
JSONL

  summarize
  echo "$output" | grep -q "Created src/ok.ts"
  ! echo "$output" | grep -q "Created src/fail.ts"
  ! echo "$output" | grep -q "Edited src/also-fail.ts"
}

@test "pause-summary stays silent when only file operations failed" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Add a helper"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Write","file":"src/fail.ts","action":"failed","context":{"failed":true}}
JSONL

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
}

@test "pause-summary flags failed commands" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"Run tests"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
JSONL

  summarize
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

  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
}

@test "pause-summary exits silently when cwd is missing" {
  run bash -c 'echo '"'"'{}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "the Stop hook does not start briefing.sh" {
  local root="$BATS_TEST_TMPDIR/vl"
  mkdir -p "$root"
  cp -R "$SCRIPTS_DIR" "$root/scripts"
  printf '#!/bin/bash\ntouch "%s/briefing-ran"\n' "$root" > "$root/scripts/briefing.sh"
  seed_session_log
  for event in Stop stop; do
    echo '{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"'"$event"'"}' | bash "$root/scripts/pause-summary.sh" >/dev/null
  done
  sleep 1
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
  [ ! -e "$root/briefing-ran" ]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/briefing" ]
}

@test "pause-summary emits no stdout for Grok Stop" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hookEventName":"stop","reason":"end_turn"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
  grep -q "Build an API" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary emits no stdout when GROK_HOOK_EVENT is set" {
  seed_session_log
  run env GROK_HOOK_EVENT=stop bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
}

@test "pause-summary skips Grok session-end Stop" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'","hookEventName":"stop","reason":"shutdown"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
}

@test "pause-summary covers the whole session; the last turn lists only its own actions" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-03-17T14:00:00Z","event":"user_prompt","prompt":"First task"}
{"timestamp":"2026-03-17T14:00:05Z","event":"tool_use","tool":"Write","file":"old.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-03-17T14:01:00Z","event":"user_prompt","prompt":"Second task"}
{"timestamp":"2026-03-17T14:01:05Z","event":"tool_use","tool":"Write","file":"new.ts","action":"created","context":{"new_file":true}}
JSONL

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}' | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  local summary="$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  grep -q "Created new.ts" "$summary"
  ! grep -q "Created old.ts" "$summary"
  grep -qx "  old.ts — created" "$summary"
  grep -qx "  new.ts — created" "$summary"
}

write_fixture_log() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  sed "s#__ROOT__#$TEST_PROJECT_DIR#g" "$VIBE_LEARN_DIR/tests/fixtures/session-learning.jsonl" \
    | head -n "${1:-100}" > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
}

stop() { echo '{"cwd":"'"$TEST_PROJECT_DIR"'","hook_event_name":"Stop"}' | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null; }

@test "pause-summary: real goal, each file once with relative paths, only open failures" {
  write_fixture_log 20   # through turn 5, before the trailing /learn turn
  stop
  local summary="$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  cat "$summary"
  grep -qx "Goal: Build an Express API with two routes and a test for each" "$summary"
  [ "$(grep -c 'src/app.js — ' "$summary")" -eq 1 ]
  grep -qx "  src/app.js — created, edited ×2" "$summary"
  ! grep -q "$TEST_PROJECT_DIR" "$summary"
  grep -qx "  ✗ npm run lint (exit 1)" "$summary"
  # npm test failed in turn 2 and passed in turn 3: not open. The /digest
  # turn's failing ls is a learning turn: not listed at all.
  ! grep -q "✗ npm test" "$summary"
  ! grep -q "digests" "$summary"
  grep -qx "Last turn: add a /health route" "$summary"
}

@test "pause-summary keeps the last work summary when the turn that ended was a learning turn" {
  write_fixture_log 20
  stop
  local summary="$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" before
  before="$(cat "$summary")"
  write_fixture_log   # adds the trailing /learn turn
  stop
  [ "$(cat "$summary")" = "$before" ]
}

@test "pause-summary honours pause_summary_max_lines, project over global" {
  write_fixture_log 20
  mkdir -p "$HOME/.vibe-learn"
  echo '{"pause_summary_max_lines": 6}' > "$HOME/.vibe-learn/config.json"
  stop
  local summary="$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  [ "$(wc -l < "$summary")" -eq 6 ]
  grep -q "more in /learn" "$summary"
  [ "$(tail -n 1 "$summary")" = " /learn [question]  ·  /digest  ·  /quiz  ·  vibe-learn briefing  ·  vibe-learn audio-prep" ]

  echo '{"pause_summary_max_lines": 9}' > "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  stop
  [ "$(wc -l < "$summary")" -eq 9 ]

  # The default (20) fits this session whole.
  rm "$HOME/.vibe-learn/config.json" "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  stop
  [ "$(wc -l < "$summary")" -eq 15 ]
  ! grep -q "more in /learn" "$summary"
}

@test "pause-summary reads the goal from the first prompts of a log longer than its tail window" {
  write_fixture_log 20
  local i
  for i in $(seq 1 1100); do
    printf '{"event":"user_prompt","prompt":"next %s"}\n{"event":"tool_use","tool":"Bash","command":"ls","context":{"exit_code":0}}\n{"event":"tool_use","tool":"Edit","file":"%s/src/f.js","action":"edited"}\n{"event":"turn_end"}\n{"event":"turn_end"}\n' "$i" "$TEST_PROJECT_DIR"
  done >> "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" -gt 5000 ]
  stop
  grep -qx "Goal: Build an Express API with two routes and a test for each" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  grep -qx "Last turn: next 1100" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary footer uses namespaced commands under a Claude Code plugin install" {
  seed_session_log
  run env CLAUDE_PLUGIN_ROOT=/tmp/plugin-root bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  [ "$status" -eq 0 ]
  grep -q "/vibe-learn:learn" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  grep -q "/vibe-learn:quiz" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}

@test "pause-summary footer uses plain commands without a plugin" {
  seed_session_log
  run bash -c 'echo '"'"'{"cwd":"'"$TEST_PROJECT_DIR"'"}'"'"' | bash '"$SCRIPTS_DIR/pause-summary.sh"
  grep -q " /learn \[question\]" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  ! grep -q "/vibe-learn:learn" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
}
