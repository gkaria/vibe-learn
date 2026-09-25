#!/usr/bin/env bats

load test_helper

LOG_DIR_REL=".vibe-learn"

vl() { printf '%s/%s' "$TEST_PROJECT_DIR" "$LOG_DIR_REL"; }

write_meta() {
  mkdir -p "$(vl)"
  printf '%s\n' "$1" > "$(vl)/session-meta.json"
}

write_log() {
  mkdir -p "$(vl)"
  cat > "$(vl)/session-log.jsonl"
}

prompt() { printf '{"timestamp":"2026-09-25T09:%02d:00Z","event":"user_prompt","prompt":"p%s","turn":%s}\n' "$1" "$1" "$1"; }
bash_ev() { printf '{"timestamp":"2026-09-25T09:%02d:10Z","event":"tool_use","tool":"Bash","command":"%s","action":"ran","turn":%s,"context":{"exit_code":%s}}\n' "$1" "$2" "$1" "$3"; }
edit_ev() { printf '{"timestamp":"2026-09-25T09:%02d:20Z","event":"tool_use","tool":"Edit","file":"%s","action":"%s","turn":%s,"context":{}}\n' "$1" "$2" "${3:-edited}" "$1"; }
turn_end() { printf '{"timestamp":"2026-09-25T09:%02d:50Z","event":"turn_end","turn":%s,"model":%s,"effort":%s}\n' "$1" "$1" "$2" "$3"; }

health() { bash "$SCRIPTS_DIR/health.sh" "$(vl)"; }

boot() {
  printf '%s' "$1" | bash "$SCRIPTS_DIR/bootstrap.sh"
}

# --- health.sh: rows and metrics ---------------------------------------------

@test "health.sh prints nothing for a missing, empty, or eventless log" {
  run health
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  write_log < /dev/null
  run health
  [ -z "$output" ]

  echo '{"event":"old"}' | write_log
  run health
  [ -z "$output" ]
}

@test "health.sh computes one row for a session with no model switch" {
  write_meta '{"session_id":"s1","started_at":"2026-09-25T08:59:00Z","harness":"claude-code","harness_version":"2.5.0","model":"opus","effort":"high","git_head":"abc1234"}'
  {
    prompt 1
    edit_ev 1 a.ts created
    edit_ev 1 b.ts
    bash_ev 1 "npm test" 1
    prompt 2
    edit_ev 2 a.ts
    edit_ev 2 c.ts
    bash_ev 2 "npm test" 0
    prompt 3
    edit_ev 3 a.ts
    bash_ev 3 "ls" 0
    bash_ev 3 "cat x" 1
  } | write_log

  run health
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  local row="$output"
  [ "$(jq -r '.version' <<<"$row")" = "1" ]
  [ "$(jq -r '.session_id' <<<"$row")" = "s1" ]
  [ "$(jq -c '.segment' <<<"$row")" = '{"index":1,"count":1,"first_turn":1,"last_turn":3}' ]
  [ "$(jq -r '.started_at' <<<"$row")" = "2026-09-25T08:59:00Z" ]
  [ "$(jq -r '.ended_at' <<<"$row")" = "2026-09-25T09:03:10Z" ]
  [ "$(jq -r '[.harness, .harness_version, .model, .effort, .git_head] | join(",")' <<<"$row")" = "claude-code,2.5.0,opus,high,abc1234" ]
  [ "$(jq -c '.metrics' <<<"$row")" = '{"prompts":3,"turns":3,"tool_events":9,"events_per_prompt":3,"bash_runs":4,"bash_failures":2,"bash_fail_rate":0.5,"failed_file_ops":0,"files_touched":3,"files_reworked":1,"rework_rate":0.33,"check_runs":2,"check_recoveries":1,"check_unrecovered":0,"turns_to_green":1}' ]
}

@test "health.sh uses null rates for small denominators" {
  write_meta '{"session_id":"s1"}'
  { prompt 1; bash_ev 1 "ls" 1; edit_ev 1 a.ts; } | write_log

  run health
  [ "$(jq -r '.metrics.bash_fail_rate' <<<"$output")" = "null" ]
  [ "$(jq -r '.metrics.rework_rate' <<<"$output")" = "null" ]
  [ "$(jq -r '.metrics.turns_to_green' <<<"$output")" = "null" ]
  [ "$(jq -r '.model' <<<"$output")" = "null" ]
}

@test "health.sh counts failed file operations separately from edits" {
  write_meta '{}'
  {
    prompt 1
    printf '%s\n' '{"timestamp":"t","event":"tool_use","tool":"Write","file":"x.ts","action":"failed","turn":1,"context":{"failed":true}}'
  } | write_log

  run health
  [ "$(jq -r '.metrics.failed_file_ops' <<<"$output")" = "1" ]
  [ "$(jq -r '.metrics.files_touched' <<<"$output")" = "0" ]
}

@test "health.sh recognises check commands and ignores other commands" {
  write_meta '{}'
  {
    prompt 1
    for cmd in "npm test" "pytest -q" "bats tests/" "go test ./..." "cargo clippy" "npm run lint" "pnpm build" "make check" "./node_modules/.bin/tsc --noEmit" "ruff check ."; do
      bash_ev 1 "$cmd" 0
    done
    for cmd in "ls -la" "git status" "npm install" "cat testdata.txt" "echo contest"; do
      bash_ev 1 "$cmd" 0
    done
  } | write_log

  run health
  [ "$(jq -r '.metrics.check_runs' <<<"$output")" = "10" ]
  [ "$(jq -r '.metrics.bash_runs' <<<"$output")" = "15" ]
}

@test "health.sh turns_to_green averages recoveries and counts unrecovered checks" {
  write_meta '{}'
  {
    prompt 1
    bash_ev 1 "npm test" 1
    bash_ev 1 "npm test" 1
    prompt 2
    prompt 3
    bash_ev 3 "npm test" 0
    bash_ev 3 "npm run lint" 1
    bash_ev 3 "npm run lint" 0
    prompt 4
    bash_ev 4 "pytest" 1
  } | write_log

  run health
  [ "$(jq -r '.metrics.check_runs' <<<"$output")" = "6" ]
  [ "$(jq -r '.metrics.check_recoveries' <<<"$output")" = "2" ]
  [ "$(jq -r '.metrics.check_unrecovered' <<<"$output")" = "1" ]
  # npm test: turn 1 -> 3 (gap 2); npm run lint: same turn (gap 0)
  [ "$(jq -r '.metrics.turns_to_green' <<<"$output")" = "1" ]
}

@test "health.sh splits a mid-session model switch into segments sharing session_id" {
  write_meta '{"session_id":"s9","started_at":"2026-09-25T08:00:00Z","model":"opus","effort":"high"}'
  {
    prompt 1; bash_ev 1 "ls" 0; turn_end 1 '"opus"' '"high"'
    prompt 2; bash_ev 2 "ls" 0; turn_end 2 '"opus"' '"high"'
    prompt 3; bash_ev 3 "ls" 1; turn_end 3 '"sonnet"' '"high"'
    prompt 4; bash_ev 4 "ls" 1; turn_end 4 '"sonnet"' 'null'
  } | write_log

  run health
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
  local first second
  first="$(sed -n 1p <<<"$output")"
  second="$(sed -n 2p <<<"$output")"
  [ "$(jq -r '.session_id' <<<"$first")" = "s9" ]
  [ "$(jq -r '.session_id' <<<"$second")" = "s9" ]
  [ "$(jq -c '.segment' <<<"$first")" = '{"index":1,"count":2,"first_turn":1,"last_turn":2}' ]
  [ "$(jq -c '.segment' <<<"$second")" = '{"index":2,"count":2,"first_turn":3,"last_turn":4}' ]
  [ "$(jq -r '.model' <<<"$first")" = "opus" ]
  [ "$(jq -r '.model' <<<"$second")" = "sonnet" ]
  # A null effort carries the previous value forward instead of starting a segment.
  [ "$(jq -r '.effort' <<<"$second")" = "high" ]
  [ "$(jq -r '.started_at' <<<"$first")" = "2026-09-25T08:00:00Z" ]
  [ "$(jq -r '.started_at' <<<"$second")" = "2026-09-25T09:03:00Z" ]
  [ "$(jq -r '.metrics.bash_failures' <<<"$second")" = "2" ]
}

@test "health.sh falls back to meta model without turn_end lines, and to the first turn_end without meta" {
  write_meta '{"model":"gpt-5.6","effort":"low"}'
  { prompt 1; bash_ev 1 "ls" 0; } | write_log
  run health
  [ "$(jq -r '.model + "/" + .effort' <<<"$output")" = "gpt-5.6/low" ]

  write_meta '{}'
  { prompt 1; bash_ev 1 "ls" 0; turn_end 1 '"grok-4.6"' '"high"'; prompt 2; bash_ev 2 "ls" 0; } | write_log
  run health
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '.model + "/" + .effort' <<<"$output")" = "grok-4.6/high" ]
}

@test "health.sh reads harness_version and model from a Claude Code transcript" {
  local t="$TEST_PROJECT_DIR/claude.jsonl"
  cat > "$t" <<'JSONL'
{"type":"user","version":"2.1.222","message":{"role":"user"}}
{"type":"assistant","version":"2.1.222","message":{"model":"claude-opus-5","role":"assistant"}}
JSONL
  write_meta "{\"harness\":\"claude-code\",\"transcript_path\":\"$t\"}"
  { prompt 1; bash_ev 1 "ls" 0; } | write_log

  run health
  [ "$(jq -r '.harness_version' <<<"$output")" = "2.1.222" ]
  [ "$(jq -r '.model' <<<"$output")" = "claude-opus-5" ]
}

@test "health.sh reads harness_version, model, and effort from a Codex transcript" {
  local t="$TEST_PROJECT_DIR/rollout.jsonl"
  cat > "$t" <<'JSONL'
{"timestamp":"x","type":"session_meta","payload":{"id":"c1","cli_version":"0.153.0"}}
{"timestamp":"x","type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"low"}}
{"timestamp":"x","type":"event_msg","payload":{"type":"token_count"}}
JSONL
  write_meta "{\"harness\":\"codex\",\"transcript_path\":\"$t\"}"
  { prompt 1; bash_ev 1 "ls" 0; } | write_log

  run health
  [ "$(jq -r '.harness_version' <<<"$output")" = "0.153.0" ]
  [ "$(jq -r '.model + "/" + .effort' <<<"$output")" = "gpt-5.6-terra/low" ]
}

@test "health.sh numbers turns by prompt position when stored turn numbers are stuck" {
  write_meta '{}'
  {
    printf '%s\n' '{"timestamp":"t1","event":"user_prompt","prompt":"a","turn":1}'
    printf '%s\n' '{"timestamp":"t2","event":"tool_use","tool":"Edit","file":"a.ts","action":"edited","turn":1,"context":{}}'
    printf '%s\n' '{"timestamp":"t3","event":"user_prompt","prompt":"b","turn":1}'
    printf '%s\n' '{"timestamp":"t4","event":"tool_use","tool":"Edit","file":"a.ts","action":"edited","turn":1,"context":{}}'
    printf '%s\n' '{"timestamp":"t5","event":"turn_end","turn":0,"model":"m2","effort":null}'
    printf '%s\n' '{"timestamp":"t6","event":"user_prompt","prompt":"c","turn":1}'
    printf '%s\n' '{"timestamp":"t7","event":"tool_use","tool":"Edit","file":"a.ts","action":"edited","turn":1,"context":{}}'
  } | write_log

  run health
  [ "$(jq -c '.segment' <<<"$output")" = '{"index":1,"count":1,"first_turn":1,"last_turn":3}' ]
  [ "$(jq -r '.metrics.turns' <<<"$output")" = "3" ]
  [ "$(jq -r '.metrics.files_reworked' <<<"$output")" = "1" ]
  [ "$(jq -r '.model' <<<"$output")" = "m2" ]
}

@test "health.sh still writes a row when session-meta.json is empty, missing, or not an object" {
  { prompt 1; bash_ev 1 "ls" 0; } | write_log
  for meta in "" "[]" "not json"; do
    printf '%s' "$meta" > "$(vl)/session-meta.json"
    run health
    [ "$(jq -r '.metrics.tool_events' <<<"$output")" = "1" ]
  done
  rm "$(vl)/session-meta.json"
  run health
  [ "$(jq -r '.session_id' <<<"$output")" = "null" ]
}

@test "health.sh tolerates a missing transcript and malformed log lines" {
  write_meta "{\"harness\":\"claude-code\",\"transcript_path\":\"$TEST_PROJECT_DIR/nope.jsonl\"}"
  { prompt 1; echo 'not json'; bash_ev 1 "ls" 0; } | write_log

  run health
  [ "$status" -eq 0 ]
  [ "$(jq -r '.harness_version' <<<"$output")" = "null" ]
  [ "$(jq -r '.metrics.tool_events' <<<"$output")" = "1" ]
}

# --- Rotation: bootstrap appends history -------------------------------------

@test "bootstrap appends one health row per rotated session to project and global logs" {
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"first\",\"model\":\"opus\"}"
  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"

  run boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"second\"}"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  [ "$(wc -l < "$(vl)/health.jsonl" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '.session_id + "/" + .model' "$(vl)/health.jsonl")" = "first/opus" ]
  [ "$(jq -r 'has("project")' "$(vl)/health.jsonl")" = "false" ]

  local global="$HOME/.vibe-learn/health.jsonl"
  [ "$(wc -l < "$global" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '.project' "$global")" = "$(basename "$TEST_PROJECT_DIR")" ]
  [ "$(jq -r '.session_id' "$global")" = "first" ]
  [ "$(jq -r '.session_id' "$(vl)/session-meta.json")" = "second" ]
}

@test "bootstrap appends nothing when there is no log or the log is empty" {
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"a\"}"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"b\"}"
  : > "$(vl)/session-log.jsonl"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"c\"}"

  [ ! -e "$(vl)/health.jsonl" ]
  [ ! -e "$HOME/.vibe-learn/health.jsonl" ]
}

@test "health.enabled false in project config stops the append; global_log false keeps it project-only" {
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"a\"}"
  echo '{"health":{"enabled":false}}' > "$(vl)/config.json"
  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"b\"}"
  [ ! -e "$(vl)/health.jsonl" ]

  mkdir -p "$HOME/.vibe-learn"
  echo '{"health":{"global_log":false}}' > "$HOME/.vibe-learn/config.json"
  echo '{"health":{"enabled":true}}' > "$(vl)/config.json"
  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"c\"}"
  [ "$(wc -l < "$(vl)/health.jsonl" | tr -d ' ')" -eq 1 ]
  [ ! -e "$HOME/.vibe-learn/health.jsonl" ]
}

@test "a failing health append does not break bootstrap rotation or its output" {
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"a\"}"
  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"
  mkdir -p "$(vl)/health.jsonl"
  echo "Prior summary" > "$(vl)/pause-summary.txt"

  run boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"b\"}"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Prior summary")' >/dev/null
  [ -f "$(vl)/session-log.prev.jsonl" ]
  [ ! -f "$(vl)/session-log.jsonl" ]
}

@test "hook scripts copied without identity.sh still write meta and turn_end quietly" {
  local lone="$TEST_PROJECT_DIR/lone/scripts"
  mkdir -p "$lone"
  cp "$SCRIPTS_DIR/bootstrap.sh" "$SCRIPTS_DIR/pause-summary.sh" "$lone/"

  run bash -c "printf '{\"cwd\":\"$TEST_PROJECT_DIR\",\"model\":\"m\"}' | bash '$lone/bootstrap.sh' 2>&1"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r '.harness + "/" + .model' "$(vl)/session-meta.json")" = "unknown/m" ]

  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"
  printf '{"cwd":"%s","hook_event_name":"stop","model":"m2"}' "$TEST_PROJECT_DIR" | bash "$lone/pause-summary.sh"
  [ "$(jq -r 'select(.event == "turn_end") | .model' "$(vl)/session-log.jsonl")" = "m2" ]
}

# --- Identity capture at session start ----------------------------------------

@test "bootstrap records identity fields, null when unknown" {
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\"}"
  local meta="$(vl)/session-meta.json"
  [ "$(jq -r '.harness' "$meta")" = "unknown" ]
  [ "$(jq -c '[.harness_version, .model, .effort, .transcript_path, .git_head, .git_dirty]' "$meta")" = '[null,null,null,null,null,null]' ]
  [ "$(jq -r '.event_count' "$meta")" = "0" ]
  [ "$(jq -r '.current_turn' "$meta")" = "0" ]
  [ "$(jq -r '.config.log_dir' "$meta")" = ".vibe-learn" ]
}

@test "bootstrap reads Claude Code model, effort, and harness from the payload and transcript path" {
  mkdir -p "$HOME/.claude/projects/p"
  local t="$HOME/.claude/projects/p/s.jsonl"
  echo '{"type":"user","version":"2.1.222"}' > "$t"

  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\",\"model\":\"claude-opus-5.5\",\"effort\":{\"level\":\"high\"},\"transcript_path\":\"$t\"}"
  local meta="$(vl)/session-meta.json"
  [ "$(jq -r '[.harness, .harness_version, .model, .effort] | join(",")' "$meta")" = "claude-code,2.1.222,claude-opus-5.5,high" ]
  [ "$(jq -r '.transcript_path' "$meta")" = "$t" ]
}

@test "bootstrap reads Codex effort from the transcript when the payload has only the model" {
  mkdir -p "$HOME/.codex/sessions/2026/09/25"
  local t="$HOME/.codex/sessions/2026/09/25/rollout.jsonl"
  printf '%s\n' '{"type":"session_meta","payload":{"cli_version":"0.153.0"}}' '{"type":"turn_context","payload":{"model":"gpt-5.6-terra","effort":"medium"}}' > "$t"

  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\",\"model\":\"gpt-5.6-sol\",\"transcript_path\":\"$t\"}"
  local meta="$(vl)/session-meta.json"
  [ "$(jq -r '[.harness, .harness_version, .model, .effort] | join(",")' "$meta")" = "codex,0.153.0,gpt-5.6-sol,medium" ]
}

@test "bootstrap reads Grok model and effort from summary.json and version from grok --version" {
  local sid="01a04ff9-7728"
  local dir
  dir="$HOME/.grok/sessions/$(printf '%s' "$TEST_PROJECT_DIR" | jq -Rr @uri)/$sid"
  mkdir -p "$dir" "$TEST_PROJECT_DIR/bin"
  echo '{"current_model_id":"grok-4.6","reasoning_effort":"high"}' > "$dir/summary.json"
  printf '#!/bin/sh\necho "grok 1.0.13 (5e9a585) [stable]"\n' > "$TEST_PROJECT_DIR/bin/grok"
  chmod +x "$TEST_PROJECT_DIR/bin/grok"

  printf '{"hookEventName":"session_start","sessionId":"%s","cwd":"%s","workspaceRoot":"%s"}' "$sid" "$TEST_PROJECT_DIR" "$TEST_PROJECT_DIR" \
    | GROK_HOOK_EVENT=session_start PATH="$TEST_PROJECT_DIR/bin:$PATH" bash "$SCRIPTS_DIR/bootstrap.sh"
  local meta="$(vl)/session-meta.json"
  [ "$(jq -r '[.harness, .harness_version, .model, .effort] | join(",")' "$meta")" = "grok,1.0.13,grok-4.6,high" ]
}

@test "bootstrap honours GROK_HOME for the summary.json lookup" {
  local sid="g2"
  export GROK_HOME="$TEST_PROJECT_DIR/grok-home"
  local dir
  dir="$GROK_HOME/sessions/$(printf '%s' "$TEST_PROJECT_DIR" | jq -Rr @uri)/$sid"
  mkdir -p "$dir"
  echo '{"current_model_id":"grok-4.7","reasoning_effort":"low"}' > "$dir/summary.json"

  printf '{"sessionId":"%s","workspaceRoot":"%s"}' "$sid" "$TEST_PROJECT_DIR" \
    | GROK_HOOK_EVENT=session_start bash "$SCRIPTS_DIR/bootstrap.sh"
  [ "$(jq -r '.model + "/" + .effort' "$(vl)/session-meta.json")" = "grok-4.7/low" ]
}

@test "VIBE_LEARN_HARNESS overrides every other harness source" {
  printf '{"cwd":"%s","harness":"cursor"}' "$TEST_PROJECT_DIR" \
    | VIBE_LEARN_HARNESS=my-harness bash "$SCRIPTS_DIR/bootstrap.sh"
  [ "$(jq -r '.harness' "$(vl)/session-meta.json")" = "my-harness" ]
}

@test "bootstrap records git_head and git_dirty inside a git repository" {
  git -C "$TEST_PROJECT_DIR" init -q
  git -C "$TEST_PROJECT_DIR" -c user.email=t@t -c user.name=t commit -q --allow-empty -m init
  printf '.vibe-learn/\n' > "$TEST_PROJECT_DIR/.gitignore"
  git -C "$TEST_PROJECT_DIR" add .gitignore
  git -C "$TEST_PROJECT_DIR" -c user.email=t@t -c user.name=t commit -q -m ignore

  boot "{\"cwd\":\"$TEST_PROJECT_DIR\"}"
  [ "$(jq -r '.git_head' "$(vl)/session-meta.json")" = "$(git -C "$TEST_PROJECT_DIR" rev-parse --short HEAD)" ]
  [ "$(jq -r '.git_dirty' "$(vl)/session-meta.json")" = "false" ]

  echo change > "$TEST_PROJECT_DIR/file.txt"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\"}"
  [ "$(jq -r '.git_dirty' "$(vl)/session-meta.json")" = "true" ]
}

# --- turn_end from the Stop hook ----------------------------------------------

seed_turn() {
  boot "$1"
  { prompt 1; bash_ev 1 "ls" 0; } >> "$(vl)/session-log.jsonl"
  local tmp="$(vl)/m.tmp"
  jq '.current_turn = 1' "$(vl)/session-meta.json" > "$tmp" && mv "$tmp" "$(vl)/session-meta.json"
}

last_turn_end() { jq -c 'select(.event == "turn_end") | {turn, model, effort}' "$(vl)/session-log.jsonl" | tail -n 1; }

@test "pause-summary appends turn_end with the Claude transcript model and Stop effort, stdout unchanged" {
  mkdir -p "$HOME/.claude/projects/p"
  local t="$HOME/.claude/projects/p/s.jsonl"
  echo '{"type":"assistant","version":"2.1.222","message":{"model":"claude-sonnet-5"}}' > "$t"
  seed_turn "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\",\"model\":\"claude-opus-5.5\",\"transcript_path\":\"$t\"}"

  run bash -c "printf '%s' '{\"cwd\":\"$TEST_PROJECT_DIR\",\"transcript_path\":\"$t\",\"effort\":{\"level\":\"low\"}}' | bash '$SCRIPTS_DIR/pause-summary.sh'"
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e '.hookSpecificOutput.additionalContext | contains("Ran: ls")' >/dev/null
  [ "$(last_turn_end)" = '{"turn":1,"model":"claude-sonnet-5","effort":"low"}' ]
}

@test "pause-summary reads the Codex turn_context and falls back to the Stop model" {
  mkdir -p "$HOME/.codex/sessions"
  local t="$HOME/.codex/sessions/r.jsonl"
  printf '%s\n' '{"type":"session_meta","payload":{"cli_version":"0.153.0"}}' '{"type":"turn_context","payload":{"model":"gpt-5.6-sol","effort":"high"}}' > "$t"
  seed_turn "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\",\"transcript_path\":\"$t\"}"

  printf '{"cwd":"%s","hook_event_name":"Stop","model":"gpt-5.6-terra","transcript_path":"%s"}' "$TEST_PROJECT_DIR" "$t" \
    | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  [ "$(last_turn_end)" = '{"turn":1,"model":"gpt-5.6-sol","effort":"high"}' ]

  printf '%s\n' '{"type":"session_meta","payload":{}}' > "$t"
  printf '{"cwd":"%s","hook_event_name":"Stop","model":"gpt-5.6-terra","transcript_path":"%s"}' "$TEST_PROJECT_DIR" "$t" \
    | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  [ "$(last_turn_end)" = '{"turn":1,"model":"gpt-5.6-terra","effort":null}' ]
}

@test "pause-summary reads Grok summary.json and skips Grok's end-of-session Stop" {
  local sid="g1"
  local dir
  dir="$HOME/.grok/sessions/$(printf '%s' "$TEST_PROJECT_DIR" | jq -Rr @uri)/$sid"
  mkdir -p "$dir"
  echo '{"current_model_id":"grok-4.6","reasoning_effort":"high"}' > "$dir/summary.json"
  seed_turn "{\"cwd\":\"$TEST_PROJECT_DIR\",\"sessionId\":\"$sid\"}"

  run bash -c "printf '{\"sessionId\":\"$sid\",\"workspaceRoot\":\"$TEST_PROJECT_DIR\",\"reason\":\"end_turn\"}' | GROK_HOOK_EVENT=stop bash '$SCRIPTS_DIR/pause-summary.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(last_turn_end)" = '{"turn":1,"model":"grok-4.6","effort":"high"}' ]

  printf '{"sessionId":"%s","workspaceRoot":"%s","reason":"session_end"}' "$sid" "$TEST_PROJECT_DIR" \
    | GROK_HOOK_EVENT=stop bash "$SCRIPTS_DIR/pause-summary.sh"
  [ "$(grep -c '"event":"turn_end"' "$(vl)/session-log.jsonl")" -eq 1 ]
}

@test "pause-summary writes a turn_end with null fields when nothing is known" {
  seed_turn "{\"cwd\":\"$TEST_PROJECT_DIR\"}"
  printf '{"cwd":"%s"}' "$TEST_PROJECT_DIR" | bash "$SCRIPTS_DIR/pause-summary.sh" >/dev/null
  [ "$(last_turn_end)" = '{"turn":1,"model":null,"effort":null}' ]
}

@test "turn_end lines survive into the health row at the next rotation" {
  seed_turn "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"s\",\"harness\":\"cursor\",\"model\":\"m1\"}"
  printf '{"cwd":"%s","hook_event_name":"stop","harness":"cursor","model":"m2","effort":"max"}' "$TEST_PROJECT_DIR" \
    | bash "$SCRIPTS_DIR/pause-summary.sh"
  boot "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"next\"}"

  [ "$(wc -l < "$(vl)/health.jsonl" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r '[.session_id, .harness, .model, .effort] | join(",")' "$(vl)/health.jsonl")" = "s,cursor,m2,max" ]
}
