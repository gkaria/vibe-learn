#!/usr/bin/env bats

load test_helper

run_cursor_install() {
  bash "$ADAPTERS_DIR/cursor/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
}

run_cursor_global_install() {
  HOME="$1" bash "$ADAPTERS_DIR/cursor/install.sh" --global "$VIBE_LEARN_DIR"
}

# Build a Cursor hook payload. Cursor sends workspace_roots on every event; cwd only on some.
cursor_payload() {
  local event="$1"
  local extra="${2:-}"
  printf '{"hook_event_name":"%s","conversation_id":"conv-1","workspace_roots":["%s"]%s}' \
    "$event" "$TEST_PROJECT_DIR" "${extra:+,$extra}"
}

run_shim() {
  cursor_payload "$@" | bash "$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh"
}

# --- Install: files and hooks.json -------------------------------------------

@test "cursor install writes hooks.json with every vibe-learn event" {
  run_cursor_install

  local f="$TEST_PROJECT_DIR/.cursor/hooks.json"
  [ -f "$f" ]
  [ "$(jq -r '.version' "$f")" = "1" ]
  for event in sessionStart beforeSubmitPrompt afterFileEdit postToolUse postToolUseFailure stop; do
    [ "$(jq -r --arg e "$event" '.hooks[$e] | length' "$f")" = "1" ]
    [ "$(jq -r --arg e "$event" '.hooks[$e][0].command' "$f")" = ".cursor/hooks/vibe-learn.sh" ]
  done
  [ "$(jq -r '.hooks.postToolUse[0].matcher' "$f")" = "Shell" ]
  [ "$(jq -r '.hooks.postToolUseFailure[0].matcher' "$f")" = "Shell" ]
  [ "$(jq -r '.hooks.stop[0].timeout' "$f")" = "10" ]
}

@test "cursor install renders the shim with the install path and marks it executable" {
  run_cursor_install

  local shim="$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh"
  [ -x "$shim" ]
  grep -Fq "VIBE_LEARN_DIR=\"$VIBE_LEARN_DIR\"" "$shim"
  ! grep -q "VIBE_LEARN_DIR_PLACEHOLDER" "$shim"
}

@test "cursor install renders paths containing sed replacement characters" {
  local special_dir="$TEST_PROJECT_DIR/vibe & learn|root"
  local target_dir="$TEST_PROJECT_DIR/project"

  mkdir -p "$special_dir/adapters" "$special_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/cursor" "$special_dir/adapters/cursor"

  bash "$ADAPTERS_DIR/cursor/install.sh" "$special_dir" "$target_dir"

  grep -Fq "VIBE_LEARN_DIR=\"$special_dir\"" "$target_dir/.cursor/hooks/vibe-learn.sh"
}

@test "cursor install copies command skills and the vibe-learn skill" {
  run_cursor_install

  for skill in learn digest quiz explain vibe-learn; do
    [ -f "$TEST_PROJECT_DIR/.cursor/skills/$skill/SKILL.md" ]
    grep -q "^name: $skill$" "$TEST_PROJECT_DIR/.cursor/skills/$skill/SKILL.md"
  done
  for skill in learn digest quiz explain; do
    grep -q "^disable-model-invocation: true" "$TEST_PROJECT_DIR/.cursor/skills/$skill/SKILL.md"
  done
  ! grep -q "^disable-model-invocation" "$TEST_PROJECT_DIR/.cursor/skills/vibe-learn/SKILL.md"
  [ ! -d "$TEST_PROJECT_DIR/.cursor/commands" ]
}

@test "cursor skills point at the session log and the knowledge helper" {
  for skill in learn digest quiz explain vibe-learn; do
    grep -q "session-log.jsonl" "$ADAPTERS_DIR/cursor/skills/$skill/SKILL.md"
    grep -q "knowledge.sh" "$ADAPTERS_DIR/cursor/skills/$skill/SKILL.md"
    grep -q "hooks/vibe-learn.sh" "$ADAPTERS_DIR/cursor/skills/$skill/SKILL.md"
  done
  grep -q "pause-summary.txt" "$ADAPTERS_DIR/cursor/skills/learn/SKILL.md"
  grep -q "first digest" "$ADAPTERS_DIR/cursor/skills/digest/SKILL.md"
  grep -q "path:line" "$ADAPTERS_DIR/cursor/skills/explain/SKILL.md"
  grep -q "vibe-learn recap" "$ADAPTERS_DIR/cursor/skills/vibe-learn/SKILL.md"
}

@test "cursor install preserves foreign hooks and replaces its own entries" {
  mkdir -p "$TEST_PROJECT_DIR/.cursor"
  cat > "$TEST_PROJECT_DIR/.cursor/hooks.json" <<'JSON'
{
  "version": 1,
  "hooks": {
    "afterFileEdit": [{ "command": ".cursor/hooks/format.sh" }],
    "beforeShellExecution": [{ "command": ".cursor/hooks/block-curl.sh", "matcher": "curl" }],
    "stop": [{ "command": "/old/path/hooks/vibe-learn.sh", "timeout": 3 }]
  }
}
JSON

  run_cursor_install
  run_cursor_install

  local f="$TEST_PROJECT_DIR/.cursor/hooks.json"
  [ "$(jq -r '.hooks.afterFileEdit | length' "$f")" = "2" ]
  [ "$(jq -r '.hooks.afterFileEdit[0].command' "$f")" = ".cursor/hooks/format.sh" ]
  [ "$(jq -r '.hooks.beforeShellExecution[0].command' "$f")" = ".cursor/hooks/block-curl.sh" ]
  [ "$(jq -r '.hooks.stop | length' "$f")" = "1" ]
  [ "$(jq -r '.hooks.stop[0].command' "$f")" = ".cursor/hooks/vibe-learn.sh" ]
  [ "$(jq -r '.hooks.stop[0].timeout' "$f")" = "10" ]
  [ "$(jq -r '.hooks.postToolUse | length' "$f")" = "1" ]
}

@test "cursor install refuses to overwrite an invalid hooks.json" {
  mkdir -p "$TEST_PROJECT_DIR/.cursor"
  echo '{not json' > "$TEST_PROJECT_DIR/.cursor/hooks.json"

  run bash "$ADAPTERS_DIR/cursor/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"

  [ "$status" -ne 0 ]
  [[ "$output" == *"not valid JSON"* ]]
  [ "$(cat "$TEST_PROJECT_DIR/.cursor/hooks.json")" = '{not json' ]
}

@test "cursor global install writes to ~/.cursor with an absolute hook command" {
  local fake_home
  fake_home="$(mktemp -d)"

  run_cursor_global_install "$fake_home"

  [ -f "$fake_home/.cursor/hooks.json" ]
  [ -x "$fake_home/.cursor/hooks/vibe-learn.sh" ]
  [ "$(jq -r '.hooks.sessionStart[0].command' "$fake_home/.cursor/hooks.json")" = "$fake_home/.cursor/hooks/vibe-learn.sh" ]
  [ -f "$fake_home/.cursor/skills/learn/SKILL.md" ]
  [ -f "$fake_home/.cursor/skills/vibe-learn/SKILL.md" ]
  [ ! -f "$fake_home/.gitignore" ]

  rm -rf "$fake_home"
}

@test "cursor install creates .gitignore with .vibe-learn entry and is idempotent" {
  run_cursor_install
  run_cursor_install

  [ -f "$TEST_PROJECT_DIR/.gitignore" ]
  [ "$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")" -eq 1 ]
}

# --- Shim: payload translation -------------------------------------------------

@test "cursor shim sessionStart relays the previous pause summary as additional_context" {
  run_cursor_install
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  printf 'Prior summary line\n' > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"

  run run_shim sessionStart '"session_id":"sess-42","is_background_agent":false'

  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq -r 'keys | join(",")')" = "additional_context" ]
  [[ "$(printf '%s' "$output" | jq -r '.additional_context')" == *"Prior summary line"* ]]
  [ "$(jq -r '.session_id' "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json")" = "sess-42" ]
}

@test "cursor shim sessionStart prints nothing when there is no prior summary" {
  run_cursor_install

  run run_shim sessionStart '"session_id":"sess-1"'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/session-meta.json" ]
}

@test "cursor shim beforeSubmitPrompt logs the prompt and always continues" {
  run_cursor_install

  run run_shim beforeSubmitPrompt '"prompt":"add JWT auth","attachments":[]'

  [ "$status" -eq 0 ]
  [ "$output" = '{"continue":true}' ]
  grep -q '"event":"user_prompt"' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  grep -q '"prompt":"add JWT auth"' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
}

@test "cursor shim afterFileEdit logs a Write for a new file and an Edit otherwise" {
  run_cursor_install

  run run_shim afterFileEdit "\"file_path\":\"$TEST_PROJECT_DIR/src/new.ts\",\"edits\":[{\"old_string\":\"\",\"new_string\":\"export {}\"}]"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run run_shim afterFileEdit "\"file_path\":\"$TEST_PROJECT_DIR/src/routes.ts\",\"edits\":[{\"old_string\":\"a\",\"new_string\":\"b\"},{\"old_string\":\"c\",\"new_string\":\"d\"}]"
  [ "$status" -eq 0 ]

  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(wc -l < "$log")" -eq 2 ]
  [ "$(sed -n 1p "$log" | jq -r '.tool')" = "Write" ]
  [ "$(sed -n 1p "$log" | jq -r '.action')" = "created" ]
  [ "$(sed -n 1p "$log" | jq -r '.file')" = "$TEST_PROJECT_DIR/src/new.ts" ]
  [ "$(sed -n 2p "$log" | jq -r '.tool')" = "Edit" ]
  [ "$(sed -n 2p "$log" | jq -r '.action')" = "edited" ]
}

@test "cursor shim postToolUse logs Shell as Bash with the exit code from tool_output" {
  run_cursor_install

  run run_shim postToolUse '"tool_name":"Shell","tool_input":{"command":"npm test"},"tool_output":"{\"exitCode\":2,\"stdout\":\"1 failing\"}","cwd":"/elsewhere"'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(jq -r '.tool' "$log")" = "Bash" ]
  [ "$(jq -r '.command' "$log")" = "npm test" ]
  [ "$(jq -r '.action' "$log")" = "ran" ]
  [ "$(jq -r '.context.exit_code' "$log")" = "2" ]
}

@test "cursor shim postToolUse accepts an object tool_output and defaults exit code to 0" {
  run_cursor_install

  run run_shim postToolUse '"tool_name":"Shell","tool_input":{"command":"ls"},"tool_output":{"exitCode":0}'
  run run_shim postToolUse '"tool_name":"Shell","tool_input":{"command":"pwd"},"tool_output":"not json"'

  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(wc -l < "$log")" -eq 2 ]
  [ "$(sed -n 1p "$log" | jq -r '.context.exit_code')" = "0" ]
  [ "$(sed -n 2p "$log" | jq -r '.context.exit_code')" = "0" ]
}

@test "cursor shim ignores non-Shell tools on postToolUse" {
  run_cursor_install

  run run_shim postToolUse '"tool_name":"Read","tool_input":{"path":"README.md"},"tool_output":"{}"'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" ]
}

@test "cursor shim postToolUseFailure logs a failed Shell command with a non-zero exit code" {
  run_cursor_install

  run run_shim postToolUseFailure '"tool_name":"Shell","tool_input":{"command":"npm run build"},"error_message":"timed out","failure_type":"timeout"'

  [ "$status" -eq 0 ]
  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(jq -r '.tool' "$log")" = "Bash" ]
  [ "$(jq -r '.action' "$log")" = "ran" ]
  [ "$(jq -r '.context.exit_code' "$log")" = "1" ]
}

@test "cursor shim stop writes pause-summary.txt and emits no followup_message" {
  run_cursor_install

  run_shim beforeSubmitPrompt '"prompt":"wire up the login route"' >/dev/null
  run_shim afterFileEdit "\"file_path\":\"$TEST_PROJECT_DIR/src/login.ts\",\"edits\":[{\"old_string\":\"\",\"new_string\":\"x\"}]"
  run_shim postToolUse '"tool_name":"Shell","tool_input":{"command":"npm test"},"tool_output":"{\"exitCode\":0}"'

  run run_shim stop '"status":"completed","loop_count":0'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  local summary="$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  [ -f "$summary" ]
  grep -q "wire up the login route" "$summary"
  grep -q "Created $TEST_PROJECT_DIR/src/login.ts" "$summary"
  grep -q "Ran: npm test" "$summary"
  grep -q "/learn" "$summary"
}

@test "cursor shim falls back to cwd when workspace_roots is missing and exits quietly without either" {
  run_cursor_install

  printf '{"hook_event_name":"beforeSubmitPrompt","cwd":"%s","prompt":"hi"}' "$TEST_PROJECT_DIR" \
    | bash "$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh" >/dev/null
  grep -q '"prompt":"hi"' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"

  run bash -c "printf '{\"hook_event_name\":\"stop\"}' | bash '$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c "printf 'not json' | bash '$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "cursor shim ignores hook events it does not handle" {
  run_cursor_install

  run run_shim afterAgentResponse '"text":"done"'

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -f "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" ]
}
