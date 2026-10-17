#!/usr/bin/env bats

load test_helper

LEDGER_REL=".vibe-learn/knowledge.json"

ledger() {
  echo "$TEST_PROJECT_DIR/$LEDGER_REL"
}

run_knowledge() {
  run bash "$SCRIPTS_DIR/knowledge.sh" "$@" --dir="$TEST_PROJECT_DIR"
}

TODAY="$(date +%Y-%m-%d)"

# ---------------------------------------------------------------------------
# record
# ---------------------------------------------------------------------------

@test "record creates the ledger file with a valid document" {
  run_knowledge record jwt-auth --label="JWT authentication" --status=shaky
  [ "$status" -eq 0 ]
  [ -f "$(ledger)" ]
  jq -e '.version == 1' "$(ledger)" >/dev/null
  jq -e '.concepts | length == 1' "$(ledger)" >/dev/null
  [ "$(jq -r '.concepts[0].name' "$(ledger)")" = "jwt-auth" ]
  [ "$(jq -r '.concepts[0].label' "$(ledger)")" = "JWT authentication" ]
  [ "$(jq -r '.concepts[0].status' "$(ledger)")" = "shaky" ]
  [ "$(jq -r '.concepts[0].first_seen' "$(ledger)")" = "$TODAY" ]
  [ "$(jq -r '.concepts[0].last_quizzed' "$(ledger)")" = "$TODAY" ]
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "1" ]
}

@test "record merges by name without duplicating" {
  run_knowledge record jwt-auth --label="JWT authentication" --status=shaky
  run_knowledge record jwt-auth --status=solid
  [ "$status" -eq 0 ]
  jq -e '.concepts | length == 1' "$(ledger)" >/dev/null
  [ "$(jq -r '.concepts[0].status' "$(ledger)")" = "solid" ]
  # label survives an update that omits --label
  [ "$(jq -r '.concepts[0].label' "$(ledger)")" = "JWT authentication" ]
}

@test "record preserves other entries" {
  run_knowledge record jwt-auth --label="JWT" --status=solid
  run_knowledge record stop-hook --label="Stop hook" --status=shaky
  run_knowledge record jwt-auth --status=shaky
  jq -e '.concepts | length == 2' "$(ledger)" >/dev/null
  [ "$(jq -r '.concepts[] | select(.name == "stop-hook") | .status' "$(ledger)")" = "shaky" ]
}

@test "record stores notes; shaky without --notes keeps them, solid without --notes clears them" {
  run_knowledge record jwt-auth --label="JWT" --status=shaky --notes="confused expiry semantics"
  [ "$(jq -r '.concepts[0].notes' "$(ledger)")" = "confused expiry semantics" ]
  run_knowledge record jwt-auth --status=shaky
  [ "$(jq -r '.concepts[0].notes' "$(ledger)")" = "confused expiry semantics" ]
  run_knowledge record jwt-auth --status=solid
  [ "$status" -eq 0 ]
  [ "$(jq -r '.concepts[0].notes' "$(ledger)")" = "" ]
  run_knowledge record jwt-auth --status=solid --notes="explained refresh rotation"
  [ "$(jq -r '.concepts[0].notes' "$(ledger)")" = "explained refresh rotation" ]
}

@test "record --status=new never stamps last_quizzed" {
  run_knowledge record fresh --label="Fresh" --status=new
  [ "$status" -eq 0 ]
  [ "$(jq -r '.concepts[0].last_quizzed' "$(ledger)")" = "null" ]
  cat > "$(ledger)" <<EOF
{"version":1,"concepts":[{"name":"old","label":"Old","first_seen":"2026-01-01","last_seen":"2026-01-01","sessions":1,"last_quizzed":"2026-01-02","status":"shaky","notes":""}]}
EOF
  run_knowledge record old --status=new
  [ "$(jq -r '.concepts[0].last_quizzed' "$(ledger)")" = "2026-01-02" ]
  [ "$(jq -r '.concepts[0].status' "$(ledger)")" = "new" ]
}

@test "record and touch refuse names that are not lowercase-dash slugs" {
  local bad
  for bad in "JWT-auth" "jwt auth" "jwt_auth" "../x" "$(printf 'a\nb')" "é"; do
    run_knowledge record "$bad" --label="X" --status=solid
    [ "$status" -eq 1 ] || { echo "accepted: $bad"; return 1; }
    [[ "$output" == *"lowercase letters, digits, and dashes"* ]]
    run_knowledge touch "$bad"
    [ "$status" -eq 1 ]
  done
  [ ! -f "$(ledger)" ]
  run_knowledge record 2fa-totp --label="TOTP" --status=solid
  [ "$status" -eq 0 ]
}

@test "record rejects an invalid status" {
  run_knowledge record jwt-auth --label="JWT" --status=wrong
  [ "$status" -ne 0 ]
  [ ! -f "$(ledger)" ]
}

@test "record requires a concept name" {
  run_knowledge record --label="JWT" --status=solid
  [ "$status" -ne 0 ]
}

@test "record bumps sessions when last_seen is an earlier day" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$(ledger)" <<EOF
{"version":1,"concepts":[{"name":"jwt-auth","label":"JWT","first_seen":"2026-06-01","last_seen":"2026-06-01","sessions":2,"last_quizzed":"2026-06-01","status":"shaky","notes":""}]}
EOF
  run_knowledge record jwt-auth --status=solid
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "3" ]
  [ "$(jq -r '.concepts[0].last_seen' "$(ledger)")" = "$TODAY" ]
}

@test "record does not bump sessions twice on the same day" {
  run_knowledge record jwt-auth --label="JWT" --status=shaky
  run_knowledge record jwt-auth --status=solid
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "1" ]
}

# ---------------------------------------------------------------------------
# touch
# ---------------------------------------------------------------------------

@test "touch creates a missing entry with status new and null last_quizzed" {
  run_knowledge touch adapters --label="Adapter architecture"
  [ "$status" -eq 0 ]
  [ "$(jq -r '.concepts[0].status' "$(ledger)")" = "new" ]
  [ "$(jq -r '.concepts[0].last_quizzed' "$(ledger)")" = "null" ]
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "1" ]
}

@test "touch bumps last_seen but not sessions twice on the same day" {
  run_knowledge touch adapters --label="Adapter architecture"
  run_knowledge touch adapters --label="Adapter architecture"
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "1" ]
  [ "$(jq -r '.concepts[0].last_seen' "$(ledger)")" = "$TODAY" ]
}

@test "touch bumps sessions when last_seen is an earlier day" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$(ledger)" <<EOF
{"version":1,"concepts":[{"name":"adapters","label":"Adapters","first_seen":"2026-06-01","last_seen":"2026-06-01","sessions":2,"last_quizzed":null,"status":"new","notes":""}]}
EOF
  run_knowledge touch adapters
  [ "$(jq -r '.concepts[0].sessions' "$(ledger)")" = "3" ]
  [ "$(jq -r '.concepts[0].last_seen' "$(ledger)")" = "$TODAY" ]
}

@test "touch never changes status or last_quizzed" {
  run_knowledge record adapters --label="Adapters" --status=solid
  run_knowledge touch adapters
  [ "$(jq -r '.concepts[0].status' "$(ledger)")" = "solid" ]
  [ "$(jq -r '.concepts[0].last_quizzed' "$(ledger)")" = "$TODAY" ]
}

# ---------------------------------------------------------------------------
# list
# ---------------------------------------------------------------------------

@test "list on a missing file prints an empty ledger and exits 0" {
  run_knowledge list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.version == 1 and (.concepts | length == 0)' >/dev/null
  [ ! -f "$(ledger)" ]
}

@test "list --status filters concepts" {
  run_knowledge record jwt-auth --label="JWT" --status=shaky
  run_knowledge record adapters --label="Adapters" --status=solid
  run_knowledge list --status=shaky
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.concepts | length == 1' >/dev/null
  [ "$(echo "$output" | jq -r '.concepts[0].name')" = "jwt-auth" ]
}

# ---------------------------------------------------------------------------
# due
# ---------------------------------------------------------------------------

@test "due on a missing file prints an empty array and exits 0" {
  run_knowledge due
  [ "$status" -eq 0 ]
  echo "$output" | jq -e 'length == 0' >/dev/null
}

@test "due includes shaky concepts regardless of dates" {
  run_knowledge record jwt-auth --label="JWT" --status=shaky
  run_knowledge due
  echo "$output" | jq -e 'length == 1' >/dev/null
}

@test "due excludes recently quizzed solid concepts" {
  run_knowledge record jwt-auth --label="JWT" --status=solid
  run_knowledge due
  echo "$output" | jq -e 'length == 0' >/dev/null
}

@test "due includes never-quizzed concepts first seen before the cutoff" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$(ledger)" <<EOF
{"version":1,"concepts":[{"name":"old-new","label":"Old","first_seen":"2026-01-01","last_seen":"2026-01-01","sessions":1,"last_quizzed":null,"status":"new","notes":""}]}
EOF
  run_knowledge due
  echo "$output" | jq -e 'length == 1' >/dev/null
}

@test "due excludes never-quizzed concepts first seen today" {
  run_knowledge touch fresh --label="Fresh"
  run_knowledge due
  echo "$output" | jq -e 'length == 0' >/dev/null
}

@test "due includes solid concepts quizzed before the cutoff" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$(ledger)" <<EOF
{"version":1,"concepts":[{"name":"stale-solid","label":"Stale","first_seen":"2026-01-01","last_seen":"2026-01-01","sessions":1,"last_quizzed":"2026-01-02","status":"solid","notes":""}]}
EOF
  run_knowledge due --days=14
  echo "$output" | jq -e 'length == 1' >/dev/null
}

@test "due rejects a non-numeric --days" {
  run_knowledge due --days=soon
  [ "$status" -ne 0 ]
}

# ---------------------------------------------------------------------------
# safety
# ---------------------------------------------------------------------------

@test "touch and record add --files as project-relative paths and only ever grow the list" {
  run_knowledge touch express-mw --label="Express middleware" --files=" ./src/app.js,$TEST_PROJECT_DIR/src/routes.js,,"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.concepts[0].files' "$(ledger)")" = '["src/app.js","src/routes.js"]' ]

  run_knowledge record express-mw --status=shaky --files=src/app.js,test/app.test.js
  [ "$status" -eq 0 ]
  [ "$(jq -c '.concepts[0].files' "$(ledger)")" = '["src/app.js","src/routes.js","test/app.test.js"]' ]

  # Without --files the list stays, and a new concept gets no files key.
  run_knowledge touch express-mw
  run_knowledge record other --label="Other" --status=solid
  [ "$(jq -c '.concepts[0].files' "$(ledger)")" = '["src/app.js","src/routes.js","test/app.test.js"]' ]
  [ "$(jq -c '.concepts[1] | has("files")' "$(ledger)")" = false ]
}

@test "--files refuses paths outside the project and writes nothing" {
  local bad
  for bad in "../secret.txt" "src/../../x" "/etc/passwd" "~/notes.md" "$(printf 'a\nb.js')"; do
    run_knowledge touch express-mw --label="Express" "--files=src/app.js,$bad"
    [ "$status" -eq 1 ] || { echo "accepted: $bad"; return 1; }
    [[ "$output" == *"must be inside the project"* ]]
  done
  [ ! -f "$(ledger)" ]
}

@test "--files accepts an absolute path that reaches the project through a symlink" {
  local real link="$BATS_TEST_TMPDIR/link"
  real="$(cd "$TEST_PROJECT_DIR" && pwd -P)"
  ln -s "$real" "$link"
  run bash "$SCRIPTS_DIR/knowledge.sh" touch express-mw --label="Express" "--files=$real/src/a.js,$link/src/b.js" --dir="$link"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.concepts[0].files' "$(ledger)")" = '["src/a.js","src/b.js"]' ]
}

# ---------------------------------------------------------------------------
# forget
# ---------------------------------------------------------------------------

@test "forget removes one concept, says so, and is idempotent" {
  run_knowledge record jwt-auth --label="JWT" --status=shaky
  run_knowledge touch adapters --label="Adapters"
  run_knowledge forget jwt-auth
  [ "$status" -eq 0 ]
  [ "$output" = "Forgot 'jwt-auth'." ]
  [ "$(jq -c '[.concepts[].name]' "$(ledger)")" = '["adapters"]' ]
  run_knowledge forget jwt-auth
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in the ledger"* ]]
  [ "$(jq -c '[.concepts[].name]' "$(ledger)")" = '["adapters"]' ]
}

@test "forget removes a legacy name record would refuse, and never creates a ledger" {
  run_knowledge forget anything
  [ "$status" -eq 0 ]
  [ ! -f "$(ledger)" ]
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"version":1,"concepts":[{"name":"JWT Auth","status":"new"},{"name":"keep","status":"new"}]}' > "$(ledger)"
  run_knowledge forget "JWT Auth"
  [ "$status" -eq 0 ]
  [ "$(jq -c '[.concepts[].name]' "$(ledger)")" = '["keep"]' ]
}

@test "forget refuses a malformed ledger and a missing project" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo 'not json' > "$(ledger)"
  run_knowledge forget jwt-auth
  [ "$status" -eq 1 ]
  [ "$(cat "$(ledger)")" = "not json" ]
  run bash "$SCRIPTS_DIR/knowledge.sh" forget jwt-auth --dir="$TEST_PROJECT_DIR/nope"
  [ "$status" -eq 1 ]
  [ ! -e "$TEST_PROJECT_DIR/nope" ]
}

@test "every host's quiz, explain, and digest prompts pass the files a concept came from" {
  local f n=0
  for f in "$VIBE_LEARN_DIR"/adapters/claude-code/commands/{quiz,explain,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{codex/prompts,opencode/commands,grok/commands}/{quiz,explain,digest}.md \
           "$VIBE_LEARN_DIR"/adapters/{cursor,copilot-cli}/skills/{quiz,explain,digest}/SKILL.md \
           "$VIBE_LEARN_DIR"/adapters/{codex,grok,cursor,copilot-cli}/skills/vibe-learn/SKILL.md; do
    grep -q -- '--files=' "$f" || { echo "no --files in $f"; return 1; }
    n=$((n + 1))
  done
  [ "$n" -eq 22 ]
}

@test "malformed ledger produces an error and is not overwritten" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo 'not json' > "$(ledger)"
  run_knowledge record jwt-auth --label="JWT" --status=solid
  [ "$status" -ne 0 ]
  [ "$(cat "$(ledger)")" = "not json" ]
}

@test "unknown command fails" {
  run_knowledge frobnicate
  [ "$status" -ne 0 ]
}

@test "writes leave no temp files behind" {
  run_knowledge record jwt-auth --label="JWT" --status=solid
  local leftovers
  leftovers=$(find "$TEST_PROJECT_DIR/.vibe-learn" -name '.knowledge.*' | wc -l)
  [ "$leftovers" -eq 0 ]
}

# ---------------------------------------------------------------------------
# knowledge-defaults.json
# ---------------------------------------------------------------------------

@test "knowledge-defaults.json is valid JSON with required keys" {
  local config_file="$SCRIPTS_DIR/../config/knowledge-defaults.json"
  [ -f "$config_file" ]
  jq -e '.review_after_days == 14' "$config_file" >/dev/null
  jq -e '.quiz_question_count == 5' "$config_file" >/dev/null
}

@test "setup installs knowledge.sh and knowledge-defaults.json" {
  local FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  HOME="$FAKE_HOME" bash "$SCRIPTS_DIR/setup.sh" --local

  [ -f "$FAKE_HOME/.vibe-learn/scripts/knowledge.sh" ]
  [ -x "$FAKE_HOME/.vibe-learn/scripts/knowledge.sh" ]
  [ -f "$FAKE_HOME/.vibe-learn/config/knowledge-defaults.json" ]
  jq empty "$FAKE_HOME/.vibe-learn/config/knowledge-defaults.json"

  rm -rf "$FAKE_HOME"
}
