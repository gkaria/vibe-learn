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
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf 'Ran: grep "a\\.b" C:\\dir\\x\n' > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"

  run bash -c "echo '{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s-bs\"}' | bash '$SCRIPTS_DIR/bootstrap.sh'"
  [ "$status" -eq 0 ]
  local ctx
  ctx=$(echo "$output" | jq -r '.hookSpecificOutput.additionalContext')
  [[ "$ctx" == *'grep "a\.b" C:\dir\x'* ]]
}

# --- Rotation-time briefing (detached) ----------------------------------------

# A copy of scripts/ whose briefing.sh records its arguments, sleeps 5 s, then
# marks itself done. Prints the copy's root.
stub_install() {
  local root="$BATS_TEST_TMPDIR/vl"
  mkdir -p "$root"
  cp -R "$SCRIPTS_DIR" "$root/scripts"
  cat > "$root/scripts/briefing.sh" <<'STUB'
#!/bin/bash
here="$(cd "$(dirname "$0")/.." && pwd)"
printf '%s\n' "$@" > "$here/briefing-args"
sleep 5
touch "$here/briefing-done"
STUB
  printf '%s' "$root"
}

wait_for() { local i; for i in $(seq 1 50); do [ -e "$1" ] && return 0; sleep 0.1; done; return 1; }

@test "bootstrap snapshots the finished session and returns before its briefing finishes" {
  local root vl="$TEST_PROJECT_DIR/.vibe-learn" elapsed out
  root="$(stub_install)"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"first\"}" | bash "$root/scripts/bootstrap.sh" >/dev/null
  echo '{"event":"user_prompt","prompt":"build it"}' >> "$vl/session-log.jsonl"
  [ ! -e "$root/briefing-args" ]   # nothing to brief on the first start

  TIMEFORMAT=%R
  elapsed=$( { time out=$(echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"second\"}" \
    | bash "$root/scripts/bootstrap.sh"); } 2>&1 )
  echo "bootstrap took ${elapsed}s"
  awk -v t="$elapsed" 'BEGIN { exit !(t < 1) }'

  wait_for "$root/briefing-args"
  [ "$(cat "$root/briefing-args")" = "$(printf '%s\n' "$TEST_PROJECT_DIR" --log "$vl/session-log.prev.jsonl" --meta "$vl/session-meta.prev.json" --lock-wait 60)" ]
  [ ! -e "$root/briefing-done" ]
  [ "$(jq -r '.session_id' "$vl/session-meta.prev.json")" = "first" ]
  [ "$(jq -r '.session_id' "$vl/session-meta.json")" = "second" ]
  grep -q '"build it"' "$vl/session-log.prev.jsonl"
}

@test "a resumed session (same id) and an empty log spawn no briefing" {
  local root vl="$TEST_PROJECT_DIR/.vibe-learn"
  root="$(stub_install)"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s1\"}" | bash "$root/scripts/bootstrap.sh" >/dev/null
  echo '{"event":"user_prompt","prompt":"build it"}' >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s1\"}" | bash "$root/scripts/bootstrap.sh" >/dev/null
  : > "$vl/session-log.jsonl"
  jq '.session_id = "s0"' "$vl/session-meta.json" > "$vl/m" && mv "$vl/m" "$vl/session-meta.json"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s2\"}" | bash "$root/scripts/bootstrap.sh" >/dev/null
  sleep 0.5
  [ ! -e "$root/briefing-args" ]
}

@test "the Cursor shim's captured sessionStart output does not wait for the rotation briefing" {
  local root elapsed
  root="$(stub_install)"
  cp -R "$VIBE_LEARN_DIR/adapters" "$root/adapters"
  bash "$root/adapters/cursor/install.sh" "$root" "$TEST_PROJECT_DIR" >/dev/null
  shim() { printf '{"hook_event_name":"sessionStart","session_id":"%s","workspace_roots":["%s"]}' "$1" "$TEST_PROJECT_DIR" \
    | bash "$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh"; }
  shim c1 >/dev/null
  echo '{"event":"user_prompt","prompt":"build it"}' >> "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  TIMEFORMAT=%R
  elapsed=$( { time out=$(shim c2); } 2>&1 )
  echo "shim took ${elapsed}s"
  awk -v t="$elapsed" 'BEGIN { exit !(t < 1) }'
  wait_for "$root/briefing-args"
}

@test "the rotation briefing writes the finished session's page under its own id" {
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"done-1\"}" | bash "$SCRIPTS_DIR/bootstrap.sh" >/dev/null
  printf '%s\n' '{"event":"user_prompt","prompt":"Build an Express API with two routes and tests"}' \
    '{"event":"tool_use","tool":"Write","file":"src/app.js","action":"created"}' >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"next-2\"}" | bash "$SCRIPTS_DIR/bootstrap.sh" >/dev/null

  page="$vl/briefing/sessions/$(jq -r '.started_at[0:10]' "$vl/session-meta.prev.json")-$(basename "$TEST_PROJECT_DIR" | tr '[:upper:]' '[:lower:]')-done-1.html"
  for i in $(seq 1 100); do [ -f "$page" ] && [ ! -e "$vl/briefing/.lock" ] && break; sleep 0.1; done
  [ -f "$page" ]
  grep -q "Build an Express API with two routes and tests" "$page"
  [ ! -e "$vl/briefing/.lock" ]
  ! ls "$vl/briefing/sessions" | grep -q next-2
}

@test "without setsid (macOS) the subshell fallback also detaches the briefing" {
  local root bin="$BATS_TEST_TMPDIR/bin" elapsed f
  root="$(stub_install)"
  mkdir -p "$bin"
  for f in /usr/local/bin/* /usr/bin/* /bin/*; do
    [ "$(basename "$f")" = setsid ] || ln -sf "$f" "$bin/$(basename "$f")" 2>/dev/null || true
  done
  PATH="$bin" command -v setsid && return 1
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"m1\"}" | PATH="$bin" bash "$root/scripts/bootstrap.sh" >/dev/null
  echo '{"event":"user_prompt","prompt":"build it"}' >> "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  TIMEFORMAT=%R
  elapsed=$( { time out=$(echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"m2\"}" | PATH="$bin" bash "$root/scripts/bootstrap.sh"); } 2>&1 )
  echo "bootstrap took ${elapsed}s"
  awk -v t="$elapsed" 'BEGIN { exit !(t < 1) }'
  wait_for "$root/briefing-args"
  [ ! -e "$root/briefing-done" ]
}
