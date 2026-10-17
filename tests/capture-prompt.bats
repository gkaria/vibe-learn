#!/usr/bin/env bats

load test_helper

@test "capture-prompt logs user prompt to session log" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Build me an API"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.event')" = "user_prompt" ]
  [ "$(echo "$entry" | jq -r '.prompt')" = "Build me an API" ]
}

@test "capture-prompt includes timestamp" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Hello"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local ts
  ts=$(jq -r '.timestamp' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [[ "$ts" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]
}

@test "capture-prompt truncates long prompts to 500 chars" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  local long_prompt
  long_prompt=$(printf 'a%.0s' {1..700})

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"'"$long_prompt"'"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local prompt_len
  prompt_len=$(jq -r '.prompt | length' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$prompt_len" -le 500 ]
}

@test "capture-prompt exits silently when cwd is missing" {
  run bash -c 'echo '"'"'{"prompt":"Hello"}'"'"' | bash '"$SCRIPTS_DIR/capture-prompt.sh"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "capture-prompt creates .vibe-learn dir if missing" {
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"test"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"
  [ -d "$TEST_PROJECT_DIR/.vibe-learn" ]
}

@test "capture-prompt appends to existing log" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"First"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Second"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local line_count
  line_count=$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$line_count" -eq 2 ]
}

@test "capture-prompt increments turn counter in session-meta.json" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<'JSON'
{"session_id":"t","started_at":"2026-01-01T00:00:00Z","event_count":0,"current_turn":0}
JSON
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"First prompt"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  [ "$(jq '.current_turn' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")" = "1" ]

  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Second prompt"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  [ "$(jq '.current_turn' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")" = "2" ]
}

@test "capture-prompt reads Grok userPrompt field" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","userPrompt":"Add auth middleware"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.event')" = "user_prompt" ]
  [ "$(echo "$entry" | jq -r '.prompt')" = "Add auth middleware" ]
}

@test "capture-prompt includes turn number in session log entry" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  cat > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" <<'JSON'
{"session_id":"t","started_at":"2026-01-01T00:00:00Z","event_count":0,"current_turn":4}
JSON
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Test prompt"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  [ "$(jq '.turn' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "5" ]
}

@test "capture_prompts false in project config logs the turn but not the prompt text" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"capture_prompts":false}' > "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"my secret plan"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  local entry
  entry=$(cat "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")
  [ "$(echo "$entry" | jq -r '.event')" = "user_prompt" ]
  [ "$(echo "$entry" | jq -r '.prompt')" = "" ]
  [ "$(echo "$entry" | jq -r '.turn')" = "1" ]
  refute_grep "secret plan" "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
}

@test "capture_prompts false in global config applies to every project" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn" "$HOME/.vibe-learn"
  echo '{"capture_prompts":false}' > "$HOME/.vibe-learn/config.json"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"my secret plan"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  [ "$(jq -r '.prompt' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "" ]
}

@test "project capture_prompts true overrides global false" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn" "$HOME/.vibe-learn"
  echo '{"capture_prompts":false}' > "$HOME/.vibe-learn/config.json"
  echo '{"capture_prompts":true}' > "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"Build me an API"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  [ "$(jq -r '.prompt' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "Build me an API" ]
}

@test "capture-prompt leaves no meta tmp file behind" {
  bash "$SCRIPTS_DIR/bootstrap.sh" <<< '{"cwd":"'"$TEST_PROJECT_DIR"'","session_id":"s-tmp"}'
  echo '{"cwd":"'"$TEST_PROJECT_DIR"'","prompt":"hi"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  run bash -c "ls '$TEST_PROJECT_DIR'/.vibe-learn/*.tmp 2>/dev/null"
  [ -z "$output" ]
}

# One payload per host phrasing of a learning command, as each host sends it to
# capture-prompt.sh (Grok directly in camelCase; the shims as cwd + prompt).
@test "capture-prompt marks learning commands from every host with kind learning" {
  local p prompts=(
    '/learn why bcrypt?'                                 # Claude Code, OpenCode, Grok, Cursor
    '/vibe-learn:digest'                                 # Claude Code plugin
    '/prompts:quiz'                                      # Codex prompt files
    'Use vibe-learn to create a digest of this session.' # Codex skill
    '$vibe-learn explain src/app.js'                     # Codex explicit skill
    'Use /explain src/middleware/auth.ts'                # Copilot CLI
    '/vibe-learn'                                        # Grok and Cursor skill
    'Read .codex/prompts/learn.md and follow it for obsidian:recall auth'
    'Read ~/.codex/prompts/digest.md and follow it.'     # Codex global prompt file
    'Use $vibe-learn to quiz me on this session'         # Codex skill, explicit
  )
  for p in "${prompts[@]}"; do
    jq -cn --arg cwd "$TEST_PROJECT_DIR" --arg p "$p" '{cwd: $cwd, prompt: $p}' \
      | bash "$SCRIPTS_DIR/capture-prompt.sh"
  done
  jq -cn --arg root "$TEST_PROJECT_DIR" '{workspaceRoot: $root, userPrompt: "/quiz review"}' \
    | bash "$SCRIPTS_DIR/capture-prompt.sh"

  run jq -r 'select(.kind != "learning") | .prompt' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ -z "$output" ]
  [ "$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" -eq 11 ]
}

@test "capture-prompt leaves work prompts unmarked, including ones that start with learn" {
  local p
  for p in 'Build an Express API with two routes' 'learn the codebase and add JWT auth' \
           '/learnings page needs a route' 'use digest auth for the admin API' \
           'vibe-learn has a bug in bootstrap; please fix it' \
           '/learn/auth.ts needs its validation fixed' '/explain/page.tsx needs a loading state' \
           '/digest.json is malformed, regenerate it' '$vibe-learn.config is not loaded' \
           'use /learn/route.ts as the template' "use vibe-learn's logging format in our app" \
           'Read .codex/prompts/learn.md and fix the broken instructions' \
           'read .codex/prompts/explain.md and translate it to Spanish'; do
    jq -cn --arg cwd "$TEST_PROJECT_DIR" --arg p "$p" '{cwd: $cwd, prompt: $p}' \
      | bash "$SCRIPTS_DIR/capture-prompt.sh"
  done
  run jq -r 'select(has("kind")) | .prompt' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ -z "$output" ]
  [ "$(wc -l < "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" -eq 13 ]
}

# Codex expands /prompts:learn and sends the prompt file's body, not the command.
@test "capture-prompt marks the expanded body of every Codex prompt file as learning" {
  local f
  for f in "$ADAPTERS_DIR"/codex/prompts/*.md; do
    awk 'n >= 2; /^---$/ { n++ }' "$f" | jq -Rsc --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: .}' \
      | bash "$SCRIPTS_DIR/capture-prompt.sh"
  done
  [ "$(jq -s 'length' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" -eq 4 ]
  [ "$(jq -s 'map(select(.kind == "learning")) | length' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" -eq 4 ]
}

@test "capture-prompt marks a learning turn even when capture_prompts is off" {
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo '{"capture_prompts": false}' > "$TEST_PROJECT_DIR/.vibe-learn/config.json"
  jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "/digest"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  run jq -c '{prompt, kind}' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$output" = '{"prompt":"","kind":"learning"}' ]
}

@test "capture-prompt keeps the prompt and its kind when the meta's turn counter is damaged" {
  local t
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  for t in 1.5 '"x"'; do
    echo "{\"session_id\":\"s\",\"current_turn\":$t}" > "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
    jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "/quiz"}' | bash "$SCRIPTS_DIR/capture-prompt.sh"
  done
  [ "$(jq -sc 'map([.turn, .kind])' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = '[[1,"learning"],[1,"learning"]]' ]
  [ "$(jq '.current_turn' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")" = 1 ]
}
