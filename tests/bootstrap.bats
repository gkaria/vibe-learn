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

@test "bootstrap keeps the log and metadata when the same session resumes" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s-resume"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  local meta="$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  echo '{"event":"user_prompt","prompt":"build it"}' > "$log"
  jq '.event_count = 1' "$meta" > "$meta.tmp" && mv "$meta.tmp" "$meta"
  local before
  before=$(cat "$meta")

  # claude --continue and /compact fire SessionStart again with the same id.
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s-resume","source":"resume"}' | bash "$SCRIPTS_DIR/bootstrap.sh"

  [ "$(cat "$log")" = '{"event":"user_prompt","prompt":"build it"}' ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.prev.jsonl" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl" ]
  [ "$(cat "$meta")" = "$before" ]
}

@test "bootstrap exits silently when cwd is missing" {
  run bash -c 'echo "{}" | bash '"$SCRIPTS_DIR/bootstrap.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "bootstrap injects prior pause summary as additionalContext" {
  seed_prior_summary "Prior session info"

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

@test "bootstrap reads Grok sessionId" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","sessionId":"grok-789"}' | bash "$SCRIPTS_DIR/bootstrap.sh"
  local sid
  sid=$(jq -r '.session_id' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$sid" = "grok-789" ]
}

@test "bootstrap reads GROK_SESSION_ID when running as a Grok hook" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'"}' \
    | GROK_HOOK_EVENT=session_start GROK_SESSION_ID="env-session" bash "$SCRIPTS_DIR/bootstrap.sh"
  local sid
  sid=$(jq -r '.session_id' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")
  [ "$sid" = "env-session" ]
}

@test "bootstrap emits valid JSON when the prior summary contains backslashes and quotes" {
  seed_prior_summary 'Ran: grep "a\.b" C:\dir\x'

  run bash -c "echo '{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s-bs\"}' | bash '$SCRIPTS_DIR/bootstrap.sh'"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *'grep "a\.b" C:\dir\x'* ]]
}


# rot_start begins a session; rot_work logs a prompt and a file write, then
# runs the Stop hook, as a finished turn leaves them.
rot_start() { echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"$1\"}" | bash "$SCRIPTS_DIR/bootstrap.sh" >/dev/null; }
rot_work() {
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  printf '{"event":"user_prompt","prompt":"Build the %s module with its own tests"}\n' "$1" >> "$vl/session-log.jsonl"
  printf '{"event":"tool_use","tool":"Write","file":"src/%s.js","action":"created"}\n' "$1" >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"hook_event_name\":\"Stop\"}" | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
}

@test "bootstrap injects only the summary of the session that just ended" {
  local vl="$TEST_PROJECT_DIR/.vibe-learn" out
  rot_start inj-a; rot_work alpha
  out="$(echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"inj-b\"}" | bash "$SCRIPTS_DIR/bootstrap.sh")"
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")" == *"Build the alpha module"* ]]
  # A chat-only session: the Stop hook writes no summary, inj-a's stays.
  echo '{"event":"user_prompt","prompt":"What does the retry helper do?"}' >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"hook_event_name\":\"Stop\"}" | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  out="$(echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"inj-c\"}" | bash "$SCRIPTS_DIR/bootstrap.sh")"
  [ -z "$out" ]
  [ ! -e "$vl/pause-summary.txt" ]
}

@test "rotation writes health rows and starts no briefing" {
  local root="$BATS_TEST_TMPDIR/vl" vl="$TEST_PROJECT_DIR/.vibe-learn"
  mkdir -p "$root"
  cp -R "$SCRIPTS_DIR" "$root/scripts"
  printf '#!/bin/bash\ntouch "%s/briefing-ran"\n' "$root" > "$root/scripts/briefing.sh"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"h1\"}" | bash "$root/scripts/bootstrap.sh" >/dev/null
  printf '{"event":"user_prompt","prompt":"Build the alpha module"}\n{"event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":0}}\n' >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"h2\"}" | HOME="$BATS_TEST_TMPDIR/home" bash "$root/scripts/bootstrap.sh" >/dev/null
  # Written before the hook returns.
  [ "$(jq -r '.session_id' "$vl/health.jsonl")" = "h1" ]
  sleep 0.5
  [ ! -e "$root/briefing-ran" ]
  [ ! -e "$vl/briefing" ]
}
