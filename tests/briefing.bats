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

@test "briefing index lists the current session before older same-day sessions" {
  write_sample_session
  local sessions="$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions"
  mkdir -p "$sessions"
  # Sorts after the current session's filename, but was written earlier.
  echo '<!doctype html><title>older</title>' > "$sessions/2026-06-05-zzz-older.html"
  touch -t 202606051000 "$sessions/2026-06-05-zzz-older.html"

  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  local index="$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
  local current older
  current=$(grep -n 'class="card-title">.*dash-test' "$index" | cut -d: -f1)
  older=$(grep -n 'class="card-title">2026-06-05-zzz-older' "$index" | cut -d: -f1)
  [ -n "$current" ]
  [ -n "$older" ]
  [ "$current" -lt "$older" ]
}

@test "briefing timeline filters can hide items" {
  write_sample_session
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"

  # The filter buttons set li.hidden; the flex rule on timeline items must not override it.
  grep -q 'ol.timeline li\[hidden\]{display:none;}' "$(session_file_for_test_project)"
}

write_learning_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"session_id":"learn-test","started_at":"2026-10-16T09:00:00Z"}' > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  sed "s#__ROOT__#$TEST_PROJECT_DIR#g" "$VIBE_LEARN_DIR/tests/fixtures/session-learning.jsonl" \
    > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
}

@test "briefing goal and counts leave out learning turns and the timeline marks them" {
  write_learning_session
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]

  local index="$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html" session
  session="$(session_file_for_test_project)"
  # app.js created + edited, app.test.js created; npm install, npm test x2, lint.
  grep -q '<span class="tag">3 files</span>' "$index"
  grep -q '<span class="tag">4 commands</span>' "$index"
  grep -q '2 failed' "$index"
  # The goal is the build prompt, not the trailing /learn.
  grep -q '<p class="card-goal">Build an Express API with two routes and a test for each</p>' "$index"
  # Turn 4 (prompt, ls, digest write) and turn 6 (prompt, cat).
  [ "$(grep -c 'data-learning="true"' "$session")" -eq 5 ]
  ! grep -q 'class="command-row[^"]*"[^>]*><code class="cmd-text">ls .vibe-learn/digests' "$session"
}

# --- --log/--meta, --if-stale, and the lock ----------------------------------

@test "briefing --log/--meta builds the snapshot session, not the live one" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  mv "$vl/session-log.jsonl" "$vl/session-log.prev.jsonl"
  mv "$vl/session-meta.json" "$vl/session-meta.prev.json"
  # The next session has started: its own meta and a different first prompt.
  echo '{"session_id":"next-one","started_at":"2026-10-17T08:00:00Z"}' > "$vl/session-meta.json"
  echo '{"event":"user_prompt","prompt":"Add a delete endpoint to the API with tests please"}' > "$vl/session-log.jsonl"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --log "$vl/session-log.prev.jsonl" --meta="$vl/session-meta.prev.json"
  [ "$status" -eq 0 ]
  local page="$vl/briefing/sessions/2026-10-16-$(basename "$TEST_PROJECT_DIR" | tr '[:upper:]' '[:lower:]')-learn-test.html"
  [ -f "$page" ]
  [ "$(ls "$vl/briefing/sessions" | wc -l | tr -d ' ')" -eq 1 ]
  grep -q "Build an Express API with two routes" "$page"
  ! grep -q "delete endpoint" "$page"
}

@test "briefing --if-stale skips a fresh page and rebuilds after the log or ledger changes" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  page="$(session_file_for_test_project)"
  touch -t 202601010000 "$vl/session-log.jsonl"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [ "$status" -eq 0 ]
  [ "$output" = "Session briefing is up to date: $page" ]

  sleep 1
  echo '{"event":"user_prompt","prompt":"one more thing"}' >> "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]

  sleep 1
  echo '{"version":1,"concepts":[]}' > "$vl/knowledge.json"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"Session briefing:"* ]]
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [[ "$output" == *"up to date"* ]]
}

@test "briefing --if-stale with an empty log keeps the existing index" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  : > "$vl/session-log.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --if-stale
  [ "$status" -eq 0 ]
  [ "$output" = "No session activity to brief yet." ]
  ! grep -q "No session data yet" "$vl/briefing/index.html"
}

@test "briefing waits for a live lock holder, then gives up with a clear message" {
  write_learning_session
  local lock="$TEST_PROJECT_DIR/.vibe-learn/briefing/.lock" holder
  mkdir -p "$lock"
  sleep 30 & holder=$!
  echo "$holder" > "$lock/pid"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --lock-wait=1
  kill "$holder"
  [ "$status" -eq 1 ]
  [[ "$output" == *"another briefing run is in progress"* ]]
  [ -z "$(session_file_for_test_project)" ]
  [ -d "$lock" ]
}

@test "briefing removes a lock whose owner is gone and releases its own" {
  write_learning_session
  local lock="$TEST_PROJECT_DIR/.vibe-learn/briefing/.lock" dead
  mkdir -p "$lock"
  bash -c 'exit 0' & dead=$!
  wait "$dead"
  echo "$dead" > "$lock/pid"

  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" --lock-wait=1
  [ "$status" -eq 0 ]
  [ -f "$(session_file_for_test_project)" ]
  [ ! -e "$lock" ]
}

@test "two briefing runs at once both finish and leave whole, uninterleaved pages" {
  write_learning_session
  local vl="$TEST_PROJECT_DIR/.vibe-learn" page
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" > "$BATS_TEST_TMPDIR/a.out" 2>&1 &
  local a=$!
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" > "$BATS_TEST_TMPDIR/b.out" 2>&1 &
  local b=$!
  wait "$a"; wait "$b"

  page="$(session_file_for_test_project)"
  [ "$(ls "$vl/briefing/sessions" | wc -l | tr -d ' ')" -eq 1 ]
  for f in "$page" "$vl/briefing/index.html"; do
    [ "$(grep -ci '<!doctype html>' "$f")" -eq 1 ]
    [ "$(grep -c '</html>' "$f")" -eq 1 ]
    [ "$(tail -n 1 "$f")" = "</html>" ]
  done
  [ "$(grep -c '<script>' "$page")" -eq "$(grep -c '</script>' "$page")" ]
  [ ! -e "$vl/briefing/.lock" ]
}

@test "every host's learn and digest prompts refresh the briefing with --if-stale" {
  local f n=0
  for f in "$VIBE_LEARN_DIR"/adapters/claude-code/commands/{learn,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{codex/prompts,opencode/commands,grok/commands}/{learn,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{cursor,copilot-cli}/skills/{learn,digest}/SKILL.md \
           "$VIBE_LEARN_DIR"/adapters/{codex,grok,cursor,copilot-cli}/skills/vibe-learn/SKILL.md; do
    grep -q 'vibe-learn briefing --if-stale' "$f" || { echo "missing: $f"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 16 ]
}
