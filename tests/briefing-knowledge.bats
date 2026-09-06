#!/usr/bin/env bats

load test_helper

# Ledger-aware briefing: study queue, knowledge-state card, NotebookLM pack
# section, and adaptive audio framing. All of it must vanish without a ledger.

write_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<'JSON'
{"session_id":"ledger-test","started_at":"2026-07-12T10:00:00Z","event_count":3}
JSON
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<'JSONL'
{"timestamp":"2026-07-12T10:00:00Z","event":"user_prompt","prompt":"Add refresh tokens"}
{"timestamp":"2026-07-12T10:00:05Z","event":"tool_use","tool":"Write","file":"src/auth/refresh.ts","action":"created","context":{"new_file":true}}
{"timestamp":"2026-07-12T10:00:15Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":0}}
JSONL
}

write_ledger() {
  cat > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json" <<'JSON'
{"version":1,"concepts":[
  {"name":"jwt-refresh","label":"JWT refresh tokens","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":3,"last_quizzed":"2026-07-11","status":"shaky","notes":"mixed up rotation"},
  {"name":"middleware-order","label":"Express middleware ordering","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":2,"last_quizzed":"2026-07-01","status":"shaky","notes":""},
  {"name":"bcrypt","label":"bcrypt password hashing","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":2,"last_quizzed":"2026-07-11","status":"solid","notes":""},
  {"name":"repo-pattern","label":"Repository pattern","first_seen":"2026-07-01","last_seen":"2026-07-11","sessions":2,"last_quizzed":null,"status":"new","notes":""},
  {"name":"once-seen","label":"Seen once & unquizzed","first_seen":"2026-07-11","last_seen":"2026-07-11","sessions":1,"last_quizzed":null,"status":"new","notes":""}
]}
JSON
}

write_many_shaky() {
  local i items=""
  for i in 1 2 3 4 5 6 7; do
    items+="{\"name\":\"c$i\",\"label\":\"Concept $i\",\"first_seen\":\"2026-07-0$i\",\"last_seen\":\"2026-07-11\",\"sessions\":2,\"last_quizzed\":\"2026-07-0$i\",\"status\":\"shaky\",\"notes\":\"\"},"
  done
  printf '{"version":1,"concepts":[%s]}\n' "${items%,}" > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json"
}

session_file() { find "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions" -type f -name '*.html' | head -1; }
pack_file()    { find "$TEST_PROJECT_DIR/.vibe-learn/briefing/exports"  -type f -name '*.md'   | head -1; }

@test "no ledger: no knowledge section, nav link, pack section, or adaptive sentence" {
  write_session
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]

  ! grep -q 'id="knowledge"' "$(session_file)"
  ! grep -q '#knowledge' "$(session_file)"
  ! grep -q "Your knowledge state" "$(pack_file)"
  ! grep -q "struggled with these before" "$(pack_file)"
  ! grep -q "struggled with these before" "$(session_file)"
  ! grep -q "is marked" "$(session_file)"
}

@test "ledger: shaky and multi-session-new concepts lead the study queue, shaky ones are priority" {
  write_session
  write_ledger
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  local f; f="$(session_file)"

  grep -q 'JWT refresh tokens&rdquo; is marked shaky (last quizzed 2026-07-11)' "$f"
  grep -q 'Express middleware ordering&rdquo; is marked shaky' "$f"
  grep -q 'Repository pattern&rdquo; is marked new (never quizzed)' "$f"
  ! grep -q 'Seen once' "$f"
  ! grep -q 'bcrypt password hashing&rdquo; is marked' "$f"

  # shaky items are priority; the never-quizzed one is not
  grep -q '<label class="study-item priority"><input type="checkbox"><span>&ldquo;JWT refresh tokens' "$f"
  grep -q '<label class="study-item"><input type="checkbox"><span>&ldquo;Repository pattern' "$f"

  # ledger items come before the heuristic items
  local ledger_line heuristic_line
  ledger_line=$(grep -n 'JWT refresh tokens&rdquo; is marked' "$f" | head -1 | cut -d: -f1)
  heuristic_line=$(grep -n 'Read through each changed file' "$f" | head -1 | cut -d: -f1)
  [ "$ledger_line" -lt "$heuristic_line" ]
}

@test "ledger: study queue caps ledger-derived items at 5" {
  write_session
  write_many_shaky
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  local count
  count=$(grep -c 'is marked shaky' "$(session_file)")
  [ "$count" -eq 5 ]
}

@test "ledger: session page gains a Knowledge State section and nav link with status pills" {
  write_session
  write_ledger
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  local f; f="$(session_file)"

  grep -q '<section id="knowledge">' "$f"
  grep -q 'href="#knowledge">Knowledge state <span class="nbadge">5</span>' "$f"
  grep -q 'data-status="shaky"><span class="pill action-deleted">shaky</span><code class="fpath">JWT refresh tokens</code>' "$f"
  grep -q 'data-status="solid"><span class="pill action-created">solid</span><code class="fpath">bcrypt password hashing</code>' "$f"
  grep -q 'last quizzed 2026-07-11 · 3 session(s)' "$f"
  grep -q '2 shaky\.' "$f"
}

@test "ledger: NotebookLM pack has a knowledge state table split into needs attention and solid" {
  write_session
  write_ledger
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  local p; p="$(pack_file)"

  grep -q '^## Your knowledge state' "$p"
  grep -q '^### Needs attention' "$p"
  grep -q '^### Solid' "$p"
  grep -q '| JWT refresh tokens | shaky | 2026-07-11 | 3 |' "$p"
  grep -q '| Repository pattern | new | never | 2 |' "$p"
  grep -q '| bcrypt password hashing | solid | 2026-07-11 | 2 |' "$p"

  # needs-attention rows appear before the solid section
  local shaky_line solid_line
  shaky_line=$(grep -n '| JWT refresh tokens |' "$p" | cut -d: -f1)
  solid_line=$(grep -n '^### Solid' "$p" | cut -d: -f1)
  [ "$shaky_line" -lt "$solid_line" ]

  # knowledge state sits before the audio framing
  local ks_line audio_line
  ks_line=$(grep -n '^## Your knowledge state' "$p" | cut -d: -f1)
  audio_line=$(grep -n '^## Suggested audio framing' "$p" | cut -d: -f1)
  [ "$ks_line" -lt "$audio_line" ]
}

@test "ledger: adaptive audio sentence appears in pack and page JS iff shaky concepts exist" {
  write_session
  write_ledger
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  grep -q 'struggled with these before' "$(pack_file)"
  grep -q 'const audioPrompt = ".*needs attention\\"; the listener has struggled with these before."' "$(session_file)"

  # all solid -> no adaptive sentence, but the knowledge section still renders
  rm -rf "$TEST_PROJECT_DIR/.vibe-learn/briefing"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json" <<'JSON'
{"version":1,"concepts":[{"name":"bcrypt","label":"bcrypt","first_seen":"2026-06-20","last_seen":"2026-07-11","sessions":2,"last_quizzed":"2026-07-11","status":"solid","notes":""}]}
JSON
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  ! grep -q 'struggled with these before' "$(pack_file)"
  ! grep -q 'struggled with these before' "$(session_file)"
  grep -q '<section id="knowledge">' "$(session_file)"
  grep -q 'nothing — every quizzed concept is solid' "$(pack_file)"
}

@test "malformed ledger: warning on stderr, page still renders without knowledge state" {
  write_session
  echo '{"version":1,"concepts":"nope"' > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not a valid knowledge ledger"
  [ -f "$(session_file)" ]
  ! grep -q 'id="knowledge"' "$(session_file)"
}

@test "empty ledger: no knowledge state section" {
  write_session
  echo '{"version":1,"concepts":[]}' > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json"
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  ! grep -q 'id="knowledge"' "$(session_file)"
  ! grep -q "Your knowledge state" "$(pack_file)"
}

@test "ledger labels are HTML-escaped in the session page" {
  write_session
  cat > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json" <<'JSON'
{"version":1,"concepts":[{"name":"x","label":"<script>alert(1)</script> & co","first_seen":"2026-07-01","last_seen":"2026-07-11","sessions":2,"last_quizzed":"2026-07-01","status":"shaky","notes":""}]}
JSON
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  ! grep -q '<script>alert(1)</script>' "$(session_file)"
  grep -q '&lt;script&gt;alert(1)&lt;/script&gt; &amp; co' "$(session_file)"
}
