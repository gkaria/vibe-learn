#!/usr/bin/env bats

load test_helper

# health-report.sh (`vibe-learn health`) and the briefing's health page, card,
# and index row. All surfaces read one analysis, so their flags must agree.

FIXTURE="$(cd "$(dirname "${BATS_TEST_FILENAME}")/fixtures" && pwd)/health-sample.sh"

seed_history() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  bash "$FIXTURE" > "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
}

seed_session() {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  local today; today="$(date -u +%Y-%m-%d)"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" <<EOF
{"timestamp":"${today}T12:00:00Z","event":"user_prompt","prompt":"fix cart rounding"}
{"timestamp":"${today}T12:00:05Z","event":"tool_use","tool":"Write","file":"src/cart.ts","action":"created","context":{"new_file":true}}
{"timestamp":"${today}T12:00:06Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
{"timestamp":"${today}T12:00:07Z","event":"tool_use","tool":"Edit","file":"src/cart.ts","action":"edited","context":{}}
{"timestamp":"${today}T12:00:08Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":1}}
{"timestamp":"${today}T12:01:00Z","event":"user_prompt","prompt":"still failing"}
{"timestamp":"${today}T12:01:05Z","event":"tool_use","tool":"Edit","file":"src/cart.ts","action":"edited","context":{}}
{"timestamp":"${today}T12:01:06Z","event":"tool_use","tool":"Bash","command":"npm test","action":"ran","context":{"exit_code":0}}
EOF
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<EOF
{"session_id":"live-1","started_at":"${today}T12:00:00Z","harness":"claude-code","harness_version":"2.5.0","model":"claude-opus-5.5","effort":"high","event_count":8,"current_turn":2}
EOF
}

# Keep only rows matching a jq filter.
filter_history() {
  local f="$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  jq -c "$1" "$f" > "$f.tmp" && mv "$f.tmp" "$f"
}

session_file() { find "$TEST_PROJECT_DIR/.vibe-learn/briefing/sessions" -type f -name '*.html' | head -1; }

# ---------------------------------------------------------------------------
# Terminal
# ---------------------------------------------------------------------------

@test "flags the three signals that rose after the version change, with a control sentence" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"last 14 days (20 sessions)"* ]]
  [[ "$output" == *"claude-code 2.5.0 (claude-opus-5.5), since"*"(2.4.1 → 2.5.0)"* ]]
  [[ "$output" == *"bash failure rate    8% -> 21%"* ]]
  [[ "$output" == *"rework rate         12% -> 22%"* ]]
  [[ "$output" == *"events per prompt   6.1 -> 8.9"* ]]
  [[ "$output" != *"turns to green     "*"->"* ]]
  [[ "$output" == *"codex 0.61.0 (gpt-5.6) held steady over the same days"* ]]
  [[ "$output" == *"harder tasks look like a worse assistant"* ]]
}

@test "effort is left out of labels when every session used the same one" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [[ "$output" != *"effort high"* ]]

  filter_history 'if .harness == "codex" then .effort = "medium" else . end'
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [[ "$output" == *"effort high"* ]]
  [[ "$output" == *"effort medium"* ]]
}

@test "--json exposes series, flags, and the control" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "3" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-code") | .status')" = "flagged" ]
  [ "$(echo "$output" | jq -r '[.series[] | select(.key == "claude-code") | .flags[].metric] | join(",")')" = "bash_fail_rate,rework_rate,events_per_prompt" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-code") | .control.key')" = "codex" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-code") | .baseline.sessions')" = "9" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-code") | .since.sessions')" = "6" ]
  # git_head never leaves the machine through reports.
  ! echo "$output" | grep -q abc1234
}

@test "--by=model groups by model and still finds the harness change" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --by=model --json
  [ "$(echo "$output" | jq -r '.by')" = "model" ]
  [ "$(echo "$output" | jq -r '[.series[].key] | sort | join(",")')" = "claude-opus-5.5,gpt-5.6" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-opus-5.5") | .marker.change')" = "2.4.1 → 2.5.0" ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "3" ]
}

@test "--days=all widens the window past 14 days" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --days=all --json
  [ "$(echo "$output" | jq -r '.sessions')" = "22" ]
  [ "$(echo "$output" | jq -r '.days')" = "null" ]
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --days=30
  [[ "$output" == *"last 30 days (22 sessions)"* ]]
}

@test "under five earlier sessions it says the baseline is still building" {
  seed_history
  filter_history 'select(.harness_version == "2.4.1")' 
  head -n 3 "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl" > "$TEST_PROJECT_DIR/.vibe-learn/h" && mv "$TEST_PROJECT_DIR/.vibe-learn/h" "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --days=all
  [[ "$output" == *"Nothing flagged."* ]]
  [[ "$output" == *"claude-code: building your baseline, 3 of 5 sessions with 5+ tool events"* ]]
}

@test "after a change with under five sessions since, it waits instead of flagging" {
  seed_history
  filter_history 'select(.harness == "claude-code")'
  local f="$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  { grep '"2.4.1"' "$f"; grep '"2.5.0"' "$f" | head -n 2; } > "$f.tmp" && mv "$f.tmp" "$f"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [[ "$output" == *"Nothing flagged."* ]]
  [[ "$output" == *"claude-code: changed on"*"(2.4.1 → 2.5.0); 2 of 5 sessions since, comparison starts after 5"* ]]
}

@test "sessions under min_events tool events do not count" {
  seed_history
  filter_history 'if .harness_version == "2.5.0" then .metrics.tool_events = 3 else . end'
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$(echo "$output" | jq -r '.flags_total')" = "0" ]
  [ "$(echo "$output" | jq -r '.series[] | select(.key == "claude-code") | .status')" = "waiting" ]
}

@test "a rise below the threshold is not flagged" {
  seed_history
  # 2.5.0 bash failures ≈ baseline + 5 points: under the 10-point threshold.
  filter_history 'if .harness_version == "2.5.0" then .metrics.bash_fail_rate = 0.13 else . end'
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$(echo "$output" | jq -r '[.series[].flags[].metric] | index("bash_fail_rate")')" = "null" ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "2" ]
}

@test "thresholds come from .vibe-learn/config.json" {
  seed_history
  echo '{"health":{"rate_threshold_pts":20,"count_threshold":5}}' > "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$(echo "$output" | jq -r '.flags_total')" = "0" ]
  [ "$(echo "$output" | jq -r '.settings.rate_threshold_pts')" = "20" ]
}

@test "no history: says so and exits 0" {
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"No finished sessions in this window yet."* ]]
}

@test "the session in progress is shown but not counted, and not duplicated once saved" {
  seed_history
  seed_session
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$(echo "$output" | jq -r '.current | length')" = "1" ]
  [ "$(echo "$output" | jq -r '.current[0].series')" = "claude-code" ]
  [ "$(echo "$output" | jq -r '.sessions')" = "20" ]

  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR"
  [[ "$output" == *"Current session (in progress, claude-code): bash failure rate 67%"* ]]

  # Once rotation saves the segment, it becomes history and stops being "current".
  bash "$SCRIPTS_DIR/health.sh" "$TEST_PROJECT_DIR/.vibe-learn" >> "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$(echo "$output" | jq -r '.current | length')" = "0" ]
  [ "$(echo "$output" | jq -r '.sessions')" = "21" ]
}

@test "--save writes a markdown report; --redact hides project names" {
  seed_history
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --save --redact
  [ "$status" -eq 0 ]
  local report="$TEST_PROJECT_DIR/.vibe-learn/health-reports/$(date -u +%Y-%m-%d)-health.md"
  [ -f "$report" ]
  grep -q '^# Assistant health — project-1$' "$report"
  grep -q '^## Flagged$' "$report"
  grep -q '| claude-code 2.5.0 · claude-opus-5.5 | 6 | 21% ! | 22% ! | 8.9 ! | 2.7 |' "$report"
  ! grep -q "$(basename "$TEST_PROJECT_DIR")" "$report"
  # The terminal output is unchanged by --save.
  [[ "$output" == *"Assistant health - project-1 - last 14 days"* ]]
}

@test "--all reads the global log and labels rows by project" {
  mkdir -p "$HOME/.vibe-learn"
  bash "$FIXTURE" | jq -c '. + {project: "shop-api"}' > "$HOME/.vibe-learn/health.jsonl"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --all --json
  [ "$(echo "$output" | jq -r '.scope')" = "all" ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "3" ]
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --all
  [[ "$output" == *"Assistant health - all projects - last 14 days"* ]]
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --all --redact --views
  ! echo "$output" | grep -q shop-api
}

@test "malformed lines in health.jsonl are skipped" {
  seed_history
  echo 'not json' >> "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  run bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "3" ]
}

@test "unknown flags and bad values fail with a message" {
  run bash "$SCRIPTS_DIR/health-report.sh" --by=repo
  [ "$status" -eq 1 ]
  [[ "$output" == *"--by must be"* ]]
  run bash "$SCRIPTS_DIR/health-report.sh" --days=soon
  [ "$status" -eq 1 ]
  run bash "$SCRIPTS_DIR/health-report.sh" --frobnicate
  [ "$status" -eq 1 ]
}

@test "vibe-learn health dispatches to health-report.sh" {
  seed_history
  run bash "$SCRIPTS_DIR/cli.sh" health "$TEST_PROJECT_DIR" --json
  [ "$status" -eq 0 ]
  [ "$(echo "$output" | jq -r '.flags_total')" = "3" ]
}

# ---------------------------------------------------------------------------
# Briefing
# ---------------------------------------------------------------------------

@test "briefing without health.jsonl has no health page, card, nav link, or index row" {
  seed_session
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn/briefing"
  touch "$TEST_PROJECT_DIR/.vibe-learn/briefing/health.html"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/briefing/health.html" ]
  ! grep -q 'id="health"' "$(session_file)"
  ! grep -q '#health' "$(session_file)"
  ! grep -q 'Assistant health' "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing with history: page, card, and index row agree with vibe-learn health" {
  seed_history
  seed_session
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  local page="$TEST_PROJECT_DIR/.vibe-learn/briefing/health.html"
  [ -f "$page" ]

  local expected
  expected="$(bash "$SCRIPTS_DIR/health-report.sh" "$TEST_PROJECT_DIR" --json | jq -r '.flags_total')"
  [ "$expected" = "3" ]

  # Page: the embedded data carries the same flag count.
  [ "$(sed -n 's/^    const DATA = \(.*\);$/\1/p' "$page" | jq -r '.views["harness|14"].flags_total')" = "$expected" ]

  # Card: one chip per flagged signal, current values from this session.
  local f; f="$(session_file)"
  grep -q '<a href="#health">Assistant health <span class="nbadge">3</span></a>' "$f"
  [ "$(grep -o 'class="delta bad"' "$f" | wc -l | tr -d ' ')" = "$expected" ]
  grep -q '<strong>3 of 4</strong> signals rose on average after 2.4.1 → 2.5.0' "$f"
  grep -q 'claude-opus-5.5 via claude-code 2.5.0' "$f"
  grep -q '2 of 3 commands<br>usual 8%' "$f"
  grep -q 'href="../health.html"' "$f"

  # Index row.
  grep -q '<a href="health.html">Assistant health</a></span><span class="stat-value danger">3 flagged</span>' \
    "$TEST_PROJECT_DIR/.vibe-learn/briefing/index.html"
}

@test "briefing card shows a building message before five earlier sessions" {
  seed_history
  seed_session
  filter_history 'select(.harness == "codex")'
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local f; f="$(session_file)"
  grep -q 'Building your baseline: 0 of 5 earlier sessions on claude-code' "$f"
  ! grep -q 'usual ' "$f"
  ! grep -q 'class="delta bad"' "$f"
}

@test "briefing with a malformed health.jsonl warns and leaves health out" {
  seed_session
  printf '{"version":1\n' > "$TEST_PROJECT_DIR/.vibe-learn/health.jsonl"
  run bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  [[ "$output" == *"is not valid JSON Lines; skipping assistant health"* ]]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/briefing/health.html" ]
  ! grep -q 'id="health"' "$(session_file)"
}

@test "health page escapes a closing script tag in project data" {
  seed_history
  seed_session
  filter_history '.model = (if .harness == "codex" then "</script><b>x" else .model end)'
  bash "$SCRIPTS_DIR/briefing.sh" "$TEST_PROJECT_DIR" >/dev/null
  local page="$TEST_PROJECT_DIR/.vibe-learn/briefing/health.html"
  [ "$(grep -c '</script>' "$page")" = "1" ]
}
