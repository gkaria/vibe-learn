#!/usr/bin/env bats

load test_helper

# Override HOME so tests write to a temp dir, not the real ~/.claude
setup() {
  TEST_PROJECT_DIR="$(mktemp -d)"
  export TEST_PROJECT_DIR

  FAKE_HOME="$(mktemp -d)"
  export FAKE_HOME
  export HOME="$FAKE_HOME"

  # INSTALL_DIR in setup.sh resolves to $HOME/.vibe-learn = $FAKE_HOME/.vibe-learn
  FAKE_INSTALL_DIR="$FAKE_HOME/.vibe-learn"
  export FAKE_INSTALL_DIR
}

teardown() {
  rm -rf "$TEST_PROJECT_DIR" "$FAKE_HOME"
}

@test "setup creates ~/.claude/settings.json with all four hooks" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code

  [ -f "$FAKE_HOME/.claude/settings.json" ]
  jq -e '.hooks.SessionStart'     "$FAKE_HOME/.claude/settings.json" >/dev/null
  jq -e '.hooks.UserPromptSubmit' "$FAKE_HOME/.claude/settings.json" >/dev/null
  jq -e '.hooks.PostToolUse'      "$FAKE_HOME/.claude/settings.json" >/dev/null
  jq -e '.hooks.Stop'             "$FAKE_HOME/.claude/settings.json" >/dev/null
}

@test "setup hook commands point into the install dir" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code

  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$FAKE_HOME/.claude/settings.json")
  [[ "$cmd" == "$FAKE_INSTALL_DIR/scripts/bootstrap.sh" ]]
}

@test "setup copies slash commands to ~/.claude/commands/" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code

  [ -f "$FAKE_HOME/.claude/commands/learn.md" ]
  [ -f "$FAKE_HOME/.claude/commands/digest.md" ]
}

@test "setup merges hooks into existing ~/.claude/settings.json without hooks" {
  mkdir -p "$FAKE_HOME/.claude"
  echo '{"permissions":{"allow":["Bash"]}}' > "$FAKE_HOME/.claude/settings.json"

  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code

  jq -e '.hooks'             "$FAKE_HOME/.claude/settings.json" >/dev/null
  jq -e '.permissions.allow' "$FAKE_HOME/.claude/settings.json" >/dev/null
}

@test "setup warns and skips when ~/.claude/settings.json already has hooks" {
  mkdir -p "$FAKE_HOME/.claude"
  echo '{"hooks":{"SessionStart":[]}}' > "$FAKE_HOME/.claude/settings.json"

  run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  echo "$output" | grep -q "already has hooks"
}

@test "setup is idempotent: running twice does not duplicate hooks" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code

  # Second run should warn, not append
  run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  echo "$output" | grep -q "already has hooks"

  # Still valid JSON with exactly one SessionStart entry
  local count
  count=$(jq '.hooks.SessionStart | length' "$FAKE_HOME/.claude/settings.json")
  [ "$count" -eq 1 ]
}

@test "setup installs Codex skill when Codex is selected" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=codex

  [ -f "$FAKE_HOME/.codex/skills/vibe-learn/SKILL.md" ]
  grep -q 'name: vibe-learn' "$FAKE_HOME/.codex/skills/vibe-learn/SKILL.md"
  [ -f "$FAKE_HOME/.codex/prompts/learn.md" ]
  [ -f "$FAKE_HOME/.codex/prompts/digest.md" ]
}

@test "setup installs OpenCode commands and plugin when OpenCode is selected" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=opencode

  [ -f "$FAKE_HOME/.config/opencode/commands/learn.md" ]
  [ -f "$FAKE_HOME/.config/opencode/commands/digest.md" ]
  [ -f "$FAKE_HOME/.config/opencode/plugins/vibe-learn.js" ]
  grep -q "const VIBE_LEARN_DIR = \"$FAKE_INSTALL_DIR\"" "$FAKE_HOME/.config/opencode/plugins/vibe-learn.js"
  grep -q 'runScript("observe.sh"' "$FAKE_HOME/.config/opencode/plugins/vibe-learn.js"
}

@test "setup installs Grok hooks skill and commands when Grok is selected" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=grok

  [ -f "$FAKE_HOME/.grok/hooks/vibe-learn.json" ]
  jq -e '.hooks.SessionStart' "$FAKE_HOME/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.PostToolUseFailure' "$FAKE_HOME/.grok/hooks/vibe-learn.json" >/dev/null
  [ -f "$FAKE_HOME/.grok/commands/learn.md" ]
  [ -f "$FAKE_HOME/.grok/commands/digest.md" ]
  [ -f "$FAKE_HOME/.grok/commands/quiz.md" ]
  [ -f "$FAKE_HOME/.grok/skills/vibe-learn/SKILL.md" ]
  grep -q "$FAKE_INSTALL_DIR/scripts/bootstrap.sh" "$FAKE_HOME/.grok/hooks/vibe-learn.json"
}

@test "setup installs Grok under GROK_HOME when selected" {
  local grok_home="$FAKE_HOME/custom-grok"
  mkdir -p "$grok_home"

  GROK_HOME="$grok_home" bash "$SCRIPTS_DIR/setup.sh" --local --assistant=grok

  [ -f "$grok_home/hooks/vibe-learn.json" ]
  [ -f "$grok_home/skills/vibe-learn/SKILL.md" ]
  [ ! -e "$FAKE_HOME/.grok/hooks/vibe-learn.json" ]
}
