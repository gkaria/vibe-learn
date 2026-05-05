#!/usr/bin/env bats

load test_helper

@test "install creates .claude/commands directory" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  [ -d "$TEST_PROJECT_DIR/.claude/commands" ]
}

@test "install copies slash command files" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  [ -f "$TEST_PROJECT_DIR/.claude/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.claude/commands/digest.md" ]
}

@test "install creates settings.local.json with hooks" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  jq -e '.hooks.PostToolUse' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  jq -e '.hooks.Stop' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  jq -e '.hooks.UserPromptSubmit' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
}

@test "install creates .gitignore with .vibe-learn entry" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  [ -f "$TEST_PROJECT_DIR/.gitignore" ]
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"
}

@test "install appends to existing .gitignore without duplicating" {
  echo "node_modules/" > "$TEST_PROJECT_DIR/.gitignore"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  grep -q 'node_modules/' "$TEST_PROJECT_DIR/.gitignore"
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"

  # Run again — should not duplicate
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  local count
  count=$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")
  [ "$count" -eq 1 ]
}

@test "install merges hooks into existing settings without hooks" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  echo '{"permissions":{"allow":["Bash"]}}' > "$TEST_PROJECT_DIR/.claude/settings.local.json"

  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code

  jq -e '.hooks' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  jq -e '.permissions.allow' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
}

@test "install warns when settings already has hooks" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  echo '{"hooks":{"SessionStart":[]}}' > "$TEST_PROJECT_DIR/.claude/settings.local.json"

  run bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  echo "$output" | grep -q "already has hooks"
}

@test "install makes scripts executable" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code
  [ -x "$SCRIPTS_DIR/bootstrap.sh" ]
  [ -x "$SCRIPTS_DIR/observe.sh" ]
  [ -x "$SCRIPTS_DIR/capture-prompt.sh" ]
  [ -x "$SCRIPTS_DIR/pause-summary.sh" ]
}

@test "install writes correct paths when invoked from a simulated home install" {
  # Simulate ~/.vibe-learn/ layout
  FAKE_HOME_INSTALL="$(mktemp -d)"
  mkdir -p "$FAKE_HOME_INSTALL/scripts"
  mkdir -p "$FAKE_HOME_INSTALL/adapters/claude-code/commands"
  cp "$SCRIPTS_DIR/"*.sh "$FAKE_HOME_INSTALL/scripts/"
  cp "$ADAPTERS_DIR/claude-code/commands/"*.md "$FAKE_HOME_INSTALL/adapters/claude-code/commands/"
  cp "$ADAPTERS_DIR/claude-code/install.sh" "$FAKE_HOME_INSTALL/adapters/claude-code/install.sh"
  chmod +x "$FAKE_HOME_INSTALL/scripts/"*.sh
  chmod +x "$FAKE_HOME_INSTALL/adapters/claude-code/install.sh"

  bash "$FAKE_HOME_INSTALL/scripts/install.sh" "$TEST_PROJECT_DIR" --assistant=claude-code

  # Hook paths must point into FAKE_HOME_INSTALL, not the original SCRIPTS_DIR
  HOOK_PATH=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$TEST_PROJECT_DIR/.claude/settings.local.json")
  [ "$HOOK_PATH" = "$FAKE_HOME_INSTALL/scripts/bootstrap.sh" ]

  rm -rf "$FAKE_HOME_INSTALL"
}

@test "install defaults to claude-code when no .claude or .codex dir exists" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
}

@test "install auto-detects codex when .codex dir exists in target" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "install --assistant=codex creates .codex/config.toml and copies prompts" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=codex
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/digest.md" ]
}
