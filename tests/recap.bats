#!/usr/bin/env bats

load test_helper

# recap.sh — "what I learned this week" markdown from the ledger, logs, and digests.

TODAY="$(date +%Y-%m-%d)"
RECENT="$(date -d '-2 days' +%Y-%m-%d 2>/dev/null || date -v -2d +%Y-%m-%d)"
OLD="$(date -d '-20 days' +%Y-%m-%d 2>/dev/null || date -v -20d +%Y-%m-%d)"

seed_project() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/digests"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json" <<EOF
{"version":1,"concepts":[
 {"name":"jwt-verification","label":"JWT verification","first_seen":"$RECENT","last_seen":"$TODAY","sessions":2,"last_quizzed":"$TODAY","status":"solid","notes":""},
 {"name":"middleware-order","label":"Express middleware ordering","first_seen":"$RECENT","last_seen":"$TODAY","sessions":2,"last_quizzed":"$RECENT","status":"shaky","notes":"you had the what, not the when"},
 {"name":"pooling","label":"Connection pooling","first_seen":"$OLD","last_seen":"$OLD","sessions":1,"last_quizzed":"$OLD","status":"shaky","notes":""},
 {"name":"repo","label":"Repository pattern","first_seen":"$RECENT","last_seen":"$TODAY","sessions":2,"last_quizzed":null,"status":"new","notes":""},
 {"name":"ancient","label":"Ancient solid thing","first_seen":"$OLD","last_seen":"$OLD","sessions":1,"last_quizzed":"$OLD","status":"solid","notes":""}
]}
EOF
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<EOF
{"timestamp":"${TODAY}T10:00:00Z","event":"user_prompt","prompt":"add refresh tokens"}
{"timestamp":"${TODAY}T10:00:01Z","event":"tool_use","tool":"Write","file":"src/refresh.ts","action":"created","context":{}}
{"timestamp":"${TODAY}T10:00:02Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":0}}
{"timestamp":"${OLD}T10:00:02Z","event":"tool_use","tool":"Bash","command":"old command","action":"ran","context":{"exit_code":0}}
EOF
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.prev.jsonl" <<EOF
{"timestamp":"${RECENT}T10:00:00Z","event":"user_prompt","prompt":"add auth"}
{"timestamp":"${RECENT}T10:00:01Z","event":"tool_use","tool":"Edit","file":"src/auth.ts","action":"edited","context":{}}
EOF
  printf '# Session Digest\n\n## What Was Built\nJWT authentication for the user routes.\n\n## Key Decisions\n- x\n' \
    > "$TEST_PROJECT_DIR/.vibe-learn/digests/$RECENT-1432.md"
  printf '# Old digest\n\n## What Was Built\nSomething from long ago.\n' \
    > "$TEST_PROJECT_DIR/.vibe-learn/digests/$OLD-1000.md"
}

@test "recap prints a markdown rollup with headline stats" {
  seed_project
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^# What I learned this week — $(basename "$TEST_PROJECT_DIR")"
  echo "$output" | grep -q "2 active day(s) · 2 prompt(s) · 2 file(s) touched · 1 command(s) run · quizzed on 2 day(s)"
}

@test "recap splits ledger concepts into solid, shaky, carried-over, and newly met" {
  seed_project
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  echo "$output" | grep -q "^## Confirmed solid (1)"
  echo "$output" | grep -q "^- JWT verification — quizzed $TODAY"
  echo "$output" | grep -q "^## Still shaky — revisit (1)"
  echo "$output" | grep -q "^- Express middleware ordering — quizzed $RECENT: you had the what, not the when"
  echo "$output" | grep -q "^## Carried over from earlier (1)"
  echo "$output" | grep -q "^- Connection pooling — still shaky since $OLD"
  echo "$output" | grep -q "^## Met this week, not quizzed yet (1)"
  echo "$output" | grep -q "^- Repository pattern — seen in 2 session(s), not quizzed yet"
  ! echo "$output" | grep -q "Ancient solid thing"
}

@test "recap lists digests from the window with their What Was Built line" {
  seed_project
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  echo "$output" | grep -q "^## From the digests"
  echo "$output" | grep -q "^- $RECENT — JWT authentication for the user routes."
  ! echo "$output" | grep -q "Something from long ago"
}

@test "recap suggests /quiz review when anything is shaky" {
  seed_project
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  echo "$output" | grep -q "^/quiz review"
}

@test "recap --days widens the window" {
  seed_project
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR" --days=30
  echo "$output" | grep -q "Ancient solid thing"
  echo "$output" | grep -q "Something from long ago"
  echo "$output" | grep -q "^## Still shaky — revisit (2)"
}

@test "recap --save writes .vibe-learn/recaps/<date>-recap.md and never touches the ledger" {
  seed_project
  local before; before="$(cat "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json")"
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR" --save
  [ "$status" -eq 0 ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/recaps/$TODAY-recap.md" ]
  grep -q "^# What I learned this week" "$TEST_PROJECT_DIR/.vibe-learn/recaps/$TODAY-recap.md"
  [ "$before" = "$(cat "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json")" ]
}

@test "recap on an empty project prints the nothing-yet message and exits 0" {
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Nothing recorded yet"
}

@test "recap with only session activity and no ledger still reports stats" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf '{"timestamp":"%sT10:00:00Z","event":"user_prompt","prompt":"x"}\n' "$TODAY" > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "1 active day(s) · 1 prompt(s)"
  echo "$output" | grep -q "No concepts were quizzed or introduced this week"
  echo "$output" | grep -q "^/digest at the end of your next session"
}

@test "recap ignores a malformed ledger with a warning" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo 'not json' > "$TEST_PROJECT_DIR/.vibe-learn/knowledge.json"
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "not a valid knowledge ledger"
}

@test "recap rejects a non-positive --days" {
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR" --days=0
  [ "$status" -ne 0 ]
  run bash "$SCRIPTS_DIR/recap.sh" "$TEST_PROJECT_DIR" --days=abc
  [ "$status" -ne 0 ]
}

@test "cli recap dispatches to recap.sh" {
  seed_project
  run bash "$SCRIPTS_DIR/cli.sh" recap "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "^# What I learned this week"
  run bash "$SCRIPTS_DIR/cli.sh" help
  echo "$output" | grep -q "vibe-learn recap"
}
