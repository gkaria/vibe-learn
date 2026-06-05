#!/usr/bin/env bats

load test_helper

write_sample_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<'JSON'
{"session_id":"dash-test","started_at":"2026-06-05T10:00:00Z","event_count":4}
JSON
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-06-05T10:00:00Z","event":"user_prompt","prompt":"Add OpenCode support and dashboard"}
{"timestamp":"2026-06-05T10:00:05Z","event":"tool_use","tool":"Write","file":"adapters/opencode/install.sh","action":"created","context":{"new_file":true}}
{"timestamp":"2026-06-05T10:00:10Z","event":"tool_use","tool":"Edit","file":"scripts/setup.sh","action":"edited","context":{}}
{"timestamp":"2026-06-05T10:00:15Z","event":"tool_use","tool":"Bash","command":"bats tests/","action":"ran","context":{"exit_code":0}}
{"timestamp":"2026-06-05T10:00:20Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
JSONL
  cat > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" <<'TXT'
vibe-learn — what just happened:
Created OpenCode adapter files and ran tests.
TXT
}

session_file_for_test_project() {
  find "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions" -maxdepth 1 -type f -name '*.html' | head -1
}

pack_file_for_test_project() {
  find "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports" -maxdepth 1 -type f -name '*-notebooklm-pack.md' | head -1
}

@test "briefing writes placeholder when session log is missing" {
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  grep -q "No vibe-learn session log" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing generates index session page and NotebookLM pack" {
  write_sample_session

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  [ -f "$(session_file_for_test_project)" ]
  [ -f "$(pack_file_for_test_project)" ]
}

@test "briefing session page contains expected sections" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file
  session_file="$(session_file_for_test_project)"

  grep -q "Session brief" "$session_file"
  grep -q "Session Timeline" "$session_file"
  grep -q "File Tour" "$session_file"
  grep -q "Command Log" "$session_file"
  grep -q "Study Queue" "$session_file"
  grep -q "Audio Export" "$session_file"
}

@test "briefing marks failed commands" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file
  session_file="$(session_file_for_test_project)"

  grep -q "failed 1" "$session_file"
  grep -q "What could break" "$session_file"
}

@test "briefing has no external asset references" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  ! grep -R 'src="https\?://' "$TEST_PROJECT_DIR/.vibe-learn/briefing"
  ! grep -R 'href="https\?://' "$TEST_PROJECT_DIR/.vibe-learn/briefing"
}

@test "NotebookLM pack includes suggested audio framing" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local pack
  pack="$(pack_file_for_test_project)"

  grep -q "Session Briefing Source Pack" "$pack"
  grep -q "Suggested audio framing" "$pack"
  grep -q "maintainer-focused audio overview" "$pack"
}

@test "briefing index lists previously generated sessions" {
  write_sample_session
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions"
  echo '<!doctype html><title>older</title>' > "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions/2026-06-04-old-session.html"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  grep -q "2026-06-04-old-session" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "dash-test" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "Previously generated session briefing" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing accepts latest flag as current-session generation" {
  write_sample_session

  run bash "$SCRIPTS_DIR/briefing.sh" --latest "$TEST_PROJECT_DIR"

  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" ]
  grep -q "dash-test" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing caps git diff excerpts" {
  write_sample_session
  git -C "$TEST_PROJECT_DIR" init >/dev/null
  printf 'before\n' > "$TEST_PROJECT_DIR/large-diff.txt"
  git -C "$TEST_PROJECT_DIR" add large-diff.txt
  printf 'after-' > "$TEST_PROJECT_DIR/large-diff.txt"
  printf 'x%.0s' {1..14000} >> "$TEST_PROJECT_DIR/large-diff.txt"
  printf 'TAIL_MARKER\n' >> "$TEST_PROJECT_DIR/large-diff.txt"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local session_file pack
  session_file="$(session_file_for_test_project)"
  pack="$(pack_file_for_test_project)"

  grep -q "large-diff.txt" "$session_file"
  ! grep -q "TAIL_MARKER" "$session_file"
  ! grep -q "TAIL_MARKER" "$pack"
}

@test "briefing CSS wraps long generated labels" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  grep -q "overflow-wrap:anywhere" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "overflow-wrap:anywhere" "$(session_file_for_test_project)"
  grep -q "word-break:break-word" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "min-width:0" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "overflow-x:hidden" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  grep -q "max-width:100%" "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}
