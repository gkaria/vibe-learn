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

@test "install with no assistant config installs all detected tools" {
  local fake_home
  local fake_bin
  fake_home="$(mktemp -d)"
  fake_bin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/claude"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/codex"
  chmod +x "$fake_bin/claude" "$fake_bin/codex"

  PATH="$fake_bin:$PATH" HOME="$fake_home" bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"

  rm -rf "$fake_home" "$fake_bin"
}

@test "install with .codex only installs Codex" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
}

@test "install with .opencode only installs OpenCode" {
  mkdir -p "$TEST_PROJECT_DIR/.opencode"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/learn.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
}

@test "install with .claude only installs Claude" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  [ ! -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
}

@test "install with .claude and .codex installs both" {
  mkdir -p "$TEST_PROJECT_DIR/.claude" "$TEST_PROJECT_DIR/.codex"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "install with .claude .codex and .opencode installs all three" {
  mkdir -p "$TEST_PROJECT_DIR/.claude" "$TEST_PROJECT_DIR/.codex" "$TEST_PROJECT_DIR/.opencode"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
}

@test "install with .grok only installs Grok" {
  mkdir -p "$TEST_PROJECT_DIR/.grok"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]
  [ -f "$TEST_PROJECT_DIR/.grok/commands/learn.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
}

@test "install --assistant=all installs all detected tools" {
  local fake_home
  local fake_bin
  fake_home="$(mktemp -d)"
  fake_bin="$(mktemp -d)"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/claude"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/codex"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/opencode"
  printf '#!/bin/sh\nexit 0\n' > "$fake_bin/grok"
  chmod +x "$fake_bin/claude" "$fake_bin/codex" "$fake_bin/opencode" "$fake_bin/grok"

  PATH="$fake_bin:$PATH" HOME="$fake_home" bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=all

  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.claude/settings.local.json" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]

  rm -rf "$fake_home" "$fake_bin"
}

@test "install --assistant=codex creates .codex/config.toml and copies prompts" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=codex
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/digest.md" ]
}

@test "install --assistant=opencode creates .opencode plugin and commands" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=opencode
  [ -f "$TEST_PROJECT_DIR/.opencode/plugins/vibe-learn.js" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/digest.md" ]
}

@test "install --assistant=grok creates .grok hooks commands and skill" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=grok
  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]
  jq -e '.hooks.PostToolUseFailure' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  [ -f "$TEST_PROJECT_DIR/.grok/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.grok/commands/digest.md" ]
  [ -f "$TEST_PROJECT_DIR/.grok/skills/vibe-learn/SKILL.md" ]
}

@test "install detects grok via GROK_HOME when no project assistant dirs exist" {
  local fake_home
  local grok_home
  fake_home="$(mktemp -d)"
  grok_home="$(mktemp -d)/custom-grok"
  mkdir -p "$grok_home"

  PATH="/usr/bin:/bin" HOME="$fake_home" GROK_HOME="$grok_home" \
    bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]

  rm -rf "$fake_home" "$(dirname "$grok_home")"
}

@test "install --assistant=cursor creates .cursor hooks shim and skills" {
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=cursor

  [ -f "$TEST_PROJECT_DIR/.cursor/hooks.json" ]
  jq -e '.hooks.sessionStart' "$TEST_PROJECT_DIR/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.afterFileEdit' "$TEST_PROJECT_DIR/.cursor/hooks.json" >/dev/null
  [ -x "$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh" ]
  grep -Fq "VIBE_LEARN_DIR=\"$VIBE_LEARN_DIR\"" "$TEST_PROJECT_DIR/.cursor/hooks/vibe-learn.sh"
  [ -f "$TEST_PROJECT_DIR/.cursor/skills/learn/SKILL.md" ]
  [ -f "$TEST_PROJECT_DIR/.cursor/skills/vibe-learn/SKILL.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
}

@test "install with .cursor only installs Cursor" {
  mkdir -p "$TEST_PROJECT_DIR/.cursor"
  bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.cursor/hooks.json" ]
  [ -f "$TEST_PROJECT_DIR/.cursor/skills/quiz/SKILL.md" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
}

@test "install detects cursor via ~/.cursor when no project assistant dirs exist" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.cursor"

  PATH="/usr/bin:/bin" HOME="$fake_home" bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR"

  [ -f "$TEST_PROJECT_DIR/.cursor/hooks.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]

  rm -rf "$fake_home"
}

@test "install unknown assistant errors" {
  run bash "$SCRIPTS_DIR/install.sh" "$TEST_PROJECT_DIR" --assistant=not-real
  [ "$status" -ne 0 ]
  echo "$output" | grep -q "Unknown assistant 'not-real'"
}

@test "claude-code install skips hooks and commands when the plugin is enabled in ~/.claude/settings.json" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.claude" "$TEST_PROJECT_DIR/.claude"
  echo '{"enabledPlugins":{"vibe-learn@vibe-learn":true}}' > "$fake_home/.claude/settings.json"

  HOME="$fake_home" run bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "plugin is already enabled"
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/commands/learn.md" ]
  # gitignore handling still runs
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"

  rm -rf "$fake_home"
}

@test "claude-code install skips when the plugin is enabled in the project settings" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  echo '{"enabledPlugins":{"vibe-learn@claude-community":true}}' > "$TEST_PROJECT_DIR/.claude/settings.json"

  HOME="$fake_home" run bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "plugin is already enabled"
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]

  rm -rf "$fake_home"
}

@test "claude-code install proceeds when the plugin entry is disabled" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.claude" "$TEST_PROJECT_DIR/.claude"
  echo '{"enabledPlugins":{"vibe-learn@vibe-learn":false}}' > "$fake_home/.claude/settings.json"

  HOME="$fake_home" bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]
  [ -f "$TEST_PROJECT_DIR/.claude/commands/learn.md" ]

  rm -rf "$fake_home"
}


@test "claude-code install strips legacy vibe-learn hooks when deferring to the plugin" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.claude" "$TEST_PROJECT_DIR/.claude"
  cat > "$fake_home/.claude/settings.json" <<EOF
{
  "enabledPlugins": {"vibe-learn@vibe-learn": true},
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command", "command": "$fake_home/.vibe-learn/scripts/bootstrap.sh"}]}],
    "Stop": [{"hooks": [{"type": "command", "command": "$fake_home/.vibe-learn/scripts/pause-summary.sh"}]}],
    "PreToolUse": [{"hooks": [{"type": "command", "command": "/other/tool.sh"}]}]
  }
}
EOF

  HOME="$fake_home" run bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "Removed legacy vibe-learn hooks"
  # vibe-learn entries gone; unrelated hook preserved; plugin flag untouched
  ! jq -e '.hooks.SessionStart' "$fake_home/.claude/settings.json" >/dev/null
  ! jq -e '.hooks.Stop' "$fake_home/.claude/settings.json" >/dev/null
  [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$fake_home/.claude/settings.json")" = "/other/tool.sh" ]
  [ "$(jq -r '.enabledPlugins["vibe-learn@vibe-learn"]' "$fake_home/.claude/settings.json")" = "true" ]
  [ ! -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]

  rm -rf "$fake_home"
}

@test "claude-code settings install mirrors plugin hook timeouts" {
  bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  local f="$TEST_PROJECT_DIR/.claude/settings.local.json"
  [ "$(jq '.hooks.SessionStart[0].hooks[0].timeout' "$f")" = "5" ]
  [ "$(jq '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$f")" = "5" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].timeout' "$f")" = "2" ]
  [ "$(jq '.hooks.Stop[0].hooks[0].timeout' "$f")" = "10" ]
}

@test "VIBE_LEARN_IGNORE_PLUGIN=1 forces hook install alongside the plugin" {
  local fake_home
  fake_home="$(mktemp -d)"
  mkdir -p "$fake_home/.claude" "$TEST_PROJECT_DIR/.claude"
  echo '{"enabledPlugins":{"vibe-learn@vibe-learn":true}}' > "$fake_home/.claude/settings.json"

  HOME="$fake_home" VIBE_LEARN_IGNORE_PLUGIN=1 bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/settings.local.json" ]

  rm -rf "$fake_home"
}
