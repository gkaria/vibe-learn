#!/usr/bin/env bats

load test_helper

FIXTURES="$VIBE_LEARN_DIR/tests/fixtures/copilot-cli"

run_copilot_install() {
  bash "$ADAPTERS_DIR/copilot-cli/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
}

run_hook() {
  local event="$1"
  local fixture="$2"
  jq --arg cwd "$TEST_PROJECT_DIR" '.cwd = $cwd' "$FIXTURES/$fixture" \
    | VIBE_LEARN_EVENT="$event" VIBE_LEARN_INSTALL_DIR="$VIBE_LEARN_DIR" bash "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.sh"
}

@test "copilot-cli install writes native lifecycle hooks and shim" {
  run_copilot_install
  local hooks="$TEST_PROJECT_DIR/.github/hooks/vibe-learn.json"
  [ -x "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.sh" ]
  for event in sessionStart userPromptSubmitted postToolUse postToolUseFailure agentStop; do
    [ "$(jq -r --arg event "$event" '.hooks[$event] | length' "$hooks")" = "1" ]
  done
  [ "$(jq -r '.hooks.postToolUse[0].matcher' "$hooks")" = "bash|powershell|create|edit|str_replace_editor|apply_patch" ]
  [ "$(jq -r '.hooks.agentStop[0].env.VIBE_LEARN_EVENT' "$hooks")" = "agentStop" ]
  ! jq -e '.hooks.sessionEnd' "$hooks" >/dev/null
}

@test "copilot-cli install copies grounded workflow skills" {
  run_copilot_install
  for skill in learn digest quiz explain vibe-learn; do
    local file="$TEST_PROJECT_DIR/.github/skills/$skill/SKILL.md"
    [ -f "$file" ]
    grep -q "^name: $skill$" "$file"
    grep -q 'session-log.jsonl' "$file"
    grep -q 'knowledge.sh' "$file"
  done
}

@test "copilot-cli install is idempotent and preserves unrelated hook files" {
  mkdir -p "$TEST_PROJECT_DIR/.github/hooks"
  printf '{"version":1,"hooks":{"sessionStart":[]}}\n' > "$TEST_PROJECT_DIR/.github/hooks/other.json"
  run_copilot_install
  run_copilot_install
  [ -f "$TEST_PROJECT_DIR/.github/hooks/other.json" ]
  [ "$(jq '.hooks.sessionStart | length' "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.json")" = "1" ]
  [ "$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")" = "1" ]
}

@test "copilot-cli install refuses collisions before writing" {
  mkdir -p "$TEST_PROJECT_DIR/.github/skills/learn"
  echo '# another skill' > "$TEST_PROJECT_DIR/.github/skills/learn/SKILL.md"

  run run_copilot_install

  [ "$status" -ne 0 ]
  [[ "$output" == *"not managed by vibe-learn"* ]]
  [ ! -e "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.json" ]
  [ "$(cat "$TEST_PROJECT_DIR/.github/skills/learn/SKILL.md")" = '# another skill' ]
}

@test "copilot-cli global install honors COPILOT_HOME" {
  local fake_home copilot_home
  fake_home="$(mktemp -d)"
  copilot_home="$(mktemp -d)/copilot config"

  HOME="$fake_home" COPILOT_HOME="$copilot_home" bash "$ADAPTERS_DIR/copilot-cli/install.sh" --global "$VIBE_LEARN_DIR"

  [ -f "$copilot_home/hooks/vibe-learn.json" ]
  [ -x "$copilot_home/hooks/vibe-learn.sh" ]
  [ -f "$copilot_home/skills/learn/SKILL.md" ]
  [ ! -e "$fake_home/.copilot" ]
  rm -rf "$fake_home" "$(dirname "$copilot_home")"
}

@test "copilot-cli install safely quotes paths containing spaces and metacharacters" {
  local special_dir="$TEST_PROJECT_DIR/vibe & learn|root"
  local target_dir="$TEST_PROJECT_DIR/project"
  mkdir -p "$special_dir/adapters" "$special_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/copilot-cli" "$special_dir/adapters/copilot-cli"
  cp "$SCRIPTS_DIR/bootstrap.sh" "$special_dir/scripts/bootstrap.sh"

  bash "$ADAPTERS_DIR/copilot-cli/install.sh" "$special_dir" "$target_dir"

  [ "$(jq -r '.hooks.sessionStart[0].env.VIBE_LEARN_INSTALL_DIR' "$target_dir/.github/hooks/vibe-learn.json")" = "$special_dir" ]
  local cmd
  cmd="$(jq -r '.hooks.sessionStart[0].bash' "$target_dir/.github/hooks/vibe-learn.json")"
  [ "$cmd" = "'.github/hooks/vibe-learn.sh'" ]
}

@test "copilot-cli shim translates documented lifecycle payloads into the core log" {
  run_copilot_install

  run run_hook sessionStart session-start.json
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  run run_hook userPromptSubmitted user-prompt-submitted.json
  [ -z "$output" ]
  run run_hook postToolUse create.json
  [ -z "$output" ]
  run run_hook postToolUse edit.json
  run run_hook postToolUse apply-patch.json
  run run_hook postToolUse bash.json
  run run_hook postToolUse bash-nonzero.json
  run run_hook postToolUseFailure bash-failure.json
  run run_hook agentStop agent-stop.json
  [ -z "$output" ]

  local meta="$TEST_PROJECT_DIR/.vibe-learn/session-meta.json"
  local log="$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl"
  [ "$(jq -r '.session_id' "$meta")" = "copilot-session-42" ]
  [ "$(jq -r 'select(.event == "user_prompt") | .prompt' "$log")" = "add JWT auth" ]
  [ "$(jq -r 'select(.file == "src/auth.ts") | [.tool,.action] | join(":")' "$log")" = "Write:created" ]
  [ "$(jq -r 'select(.tool == "Edit" and .file == "src/routes.ts") | [.tool,.action] | join(":")' "$log")" = "Edit:edited" ]
  [ "$(jq -r 'select(.file == "src/new.ts") | [.tool,.action] | join(":")' "$log")" = "apply_patch:created" ]
  [ "$(jq -r 'select(.command == "npm test") | .context.exit_code' "$log")" = "0" ]
  [ "$(jq -r 'select(.command | contains("SystemExit(9)")) | .context.exit_code' "$log")" = "9" ]
  [ "$(jq -r 'select(.command == "npm run build") | .context.exit_code' "$log")" = "1" ]
  jq -e 'all(.timestamp; test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T"))' "$log" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt" ]
  grep -q "Use /learn" "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"
  ! grep -qE 'secret-value|ghp_|sensitive stderr|old secret|new secret' "$log"
}

@test "copilot-cli sessionStart converts prior summary output to native additionalContext" {
  run_copilot_install
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo 'Prior Copilot summary' > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"

  run run_hook sessionStart session-start.json

  [ "$status" -eq 0 ]
  [ "$(jq -r '.additionalContext' <<<"$output")" = $'Prior session summary:\nPrior Copilot summary ' ]
}

@test "copilot-cli preserves the prompt when userPromptSubmitted precedes sessionStart" {
  run_copilot_install
  mkdir -p "$TEST_PROJECT_DIR/.vibe-learn"
  echo 'Prior Copilot summary' > "$TEST_PROJECT_DIR/.vibe-learn/pause-summary.txt"

  run run_hook userPromptSubmitted user-prompt-submitted.json
  [ "$status" -eq 0 ]
  [ "$(jq -r '.additionalContext' <<<"$output")" = $'Prior session summary:\nPrior Copilot summary ' ]
  run run_hook sessionStart session-start.json

  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ "$(jq -r 'select(.event == "user_prompt") | .prompt' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "add JWT auth" ]
  [ "$(grep -c 'add JWT auth' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "1" ]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/session-log.prev.jsonl" ]
}

@test "copilot-cli shim ignores malformed input and unsupported tools silently" {
  run_copilot_install
  run bash -c "printf 'not json' | VIBE_LEARN_EVENT=postToolUse VIBE_LEARN_INSTALL_DIR='$VIBE_LEARN_DIR' bash '$TEST_PROJECT_DIR/.github/hooks/vibe-learn.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]

  run bash -c "printf '%s' '{\"cwd\":\"$TEST_PROJECT_DIR\",\"toolName\":\"view\",\"toolArgs\":{\"path\":\"README.md\"}}' | VIBE_LEARN_EVENT=postToolUse VIBE_LEARN_INSTALL_DIR='$VIBE_LEARN_DIR' bash '$TEST_PROJECT_DIR/.github/hooks/vibe-learn.sh'"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl" ]
}

@test "install --assistant=copilot-cli creates project hooks and skills" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=copilot-cli

  [ -f "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.json" ]
  [ -x "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.sh" ]
  [ -f "$TEST_PROJECT_DIR/.github/skills/quiz/SKILL.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
}

@test "install auto-detects an existing Copilot project layout" {
  mkdir -p "$TEST_PROJECT_DIR/.github/skills"

  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.github/hooks/vibe-learn.json" ]
  [ -f "$TEST_PROJECT_DIR/.github/skills/explain/SKILL.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
}

@test "setup installs Copilot hooks and skills under COPILOT_HOME" {
  local fake_home copilot_home
  fake_home="$(mktemp -d)"
  copilot_home="$fake_home/copilot-home"

  HOME="$fake_home" COPILOT_HOME="$copilot_home" bash "$SCRIPTS_DIR/setup.sh" --local --assistant=copilot-cli

  [ -f "$copilot_home/hooks/vibe-learn.json" ]
  [ -x "$copilot_home/hooks/vibe-learn.sh" ]
  [ -f "$copilot_home/skills/learn/SKILL.md" ]
  [ -f "$fake_home/.vibe-learn/adapters/copilot-cli/hooks.json" ]
  rm -rf "$fake_home"
}
