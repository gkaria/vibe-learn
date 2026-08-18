#!/usr/bin/env bats

load test_helper

run_grok_install() {
  bash "$ADAPTERS_DIR/grok/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
}

run_grok_global_install() {
  HOME="$1" bash "$ADAPTERS_DIR/grok/install.sh" --global "$VIBE_LEARN_DIR"
}

@test "grok install creates command files" {
  run_grok_install

  [ -f "$TEST_PROJECT_DIR/.grok/commands/learn.md" ]
  [ -f "$TEST_PROJECT_DIR/.grok/commands/digest.md" ]
  [ -f "$TEST_PROJECT_DIR/.grok/commands/quiz.md" ]
}

@test "grok install creates skill" {
  run_grok_install

  [ -f "$TEST_PROJECT_DIR/.grok/skills/vibe-learn/SKILL.md" ]
  grep -q 'name: vibe-learn' "$TEST_PROJECT_DIR/.grok/skills/vibe-learn/SKILL.md"
}

@test "grok skill documents pause-summary continuity and Grok tools" {
  local skill_file="$ADAPTERS_DIR/grok/skills/vibe-learn/SKILL.md"
  grep -q 'pause-summary.txt' "$skill_file"
  grep -q 'run_terminal_command' "$skill_file"
  grep -q 'hooks-trust' "$skill_file"
}

@test "grok install writes dedicated hook file" {
  run_grok_install

  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]
  jq -e '.hooks.SessionStart' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.UserPromptSubmit' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.PostToolUse' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.PostToolUseFailure' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.Stop' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
}

@test "grok install matcher includes Grok and Claude tool names" {
  run_grok_install

  local matcher
  matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")
  echo "$matcher" | grep -q 'write'
  echo "$matcher" | grep -q 'search_replace'
  echo "$matcher" | grep -q 'run_terminal_command'
  echo "$matcher" | grep -q 'Bash'
  [ "$matcher" = "$(jq -r '.hooks.PostToolUseFailure[0].matcher' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")" ]
}

@test "grok install hook paths point to VIBE_LEARN_DIR scripts" {
  run_grok_install

  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")
  [ "$cmd" = "'$VIBE_LEARN_DIR/scripts/bootstrap.sh'" ]
  jq -e '.hooks.PostToolUse[0].hooks[0].command | test("observe\\.sh")' \
    "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.PostToolUseFailure[0].hooks[0].command | test("observe\\.sh")' \
    "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  jq -e '.hooks.Stop[0].hooks[0].command | test("pause-summary\\.sh")' \
    "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" >/dev/null
  ! grep -q "INSTALL_DIR_PLACEHOLDER" "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json"
}

@test "grok install writes explicit hook timeouts" {
  run_grok_install

  [ "$(jq '.hooks.SessionStart[0].hooks[0].timeout' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")" = "5" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].timeout' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")" = "2" ]
  [ "$(jq '.hooks.PostToolUseFailure[0].hooks[0].timeout' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")" = "2" ]
  [ "$(jq '.hooks.Stop[0].hooks[0].timeout' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")" = "10" ]
}

@test "grok install quotes hook commands so paths with spaces execute" {
  local special_dir="$TEST_PROJECT_DIR/vibe learn"
  local target_dir="$TEST_PROJECT_DIR/project"

  mkdir -p "$special_dir/adapters" "$special_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/grok" "$special_dir/adapters/grok"
  printf '#!/bin/bash\nexit 0\n' > "$special_dir/scripts/bootstrap.sh"
  printf '#!/bin/bash\nexit 0\n' > "$special_dir/scripts/capture-prompt.sh"
  printf '#!/bin/bash\nexit 0\n' > "$special_dir/scripts/observe.sh"
  printf '#!/bin/bash\nexit 0\n' > "$special_dir/scripts/pause-summary.sh"
  chmod +x "$special_dir/scripts/"*.sh

  bash "$ADAPTERS_DIR/grok/install.sh" "$special_dir" "$target_dir"

  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$target_dir/.grok/hooks/vibe-learn.json")
  [ "$cmd" = "'$special_dir/scripts/bootstrap.sh'" ]
  run sh -c "$cmd"
  [ "$status" -eq 0 ]
}

@test "grok install renders paths containing sed replacement characters" {
  local special_dir="$TEST_PROJECT_DIR/vibe & learn|root"
  local target_dir="$TEST_PROJECT_DIR/project"

  mkdir -p "$special_dir/adapters" "$special_dir/scripts" "$target_dir"
  cp -R "$ADAPTERS_DIR/grok" "$special_dir/adapters/grok"
  cp "$SCRIPTS_DIR/bootstrap.sh" "$special_dir/scripts/bootstrap.sh"

  bash "$ADAPTERS_DIR/grok/install.sh" "$special_dir" "$target_dir"

  grep -Fq "$special_dir/scripts/bootstrap.sh" "$target_dir/.grok/hooks/vibe-learn.json"
  local cmd
  cmd=$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$target_dir/.grok/hooks/vibe-learn.json")
  [ "$cmd" = "'$special_dir/scripts/bootstrap.sh'" ]
}

@test "grok global install writes to ~/.grok" {
  local fake_home
  fake_home="$(mktemp -d)"

  run_grok_global_install "$fake_home"

  [ -f "$fake_home/.grok/hooks/vibe-learn.json" ]
  [ -f "$fake_home/.grok/commands/learn.md" ]
  [ -f "$fake_home/.grok/commands/digest.md" ]
  [ -f "$fake_home/.grok/commands/quiz.md" ]
  [ -f "$fake_home/.grok/skills/vibe-learn/SKILL.md" ]

  rm -rf "$fake_home"
}

@test "grok global install honors GROK_HOME" {
  local fake_home
  local grok_home
  fake_home="$(mktemp -d)"
  grok_home="$(mktemp -d)/custom-grok"
  mkdir -p "$grok_home"

  HOME="$fake_home" GROK_HOME="$grok_home" bash "$ADAPTERS_DIR/grok/install.sh" --global "$VIBE_LEARN_DIR"

  [ -f "$grok_home/hooks/vibe-learn.json" ]
  [ -f "$grok_home/commands/learn.md" ]
  [ -f "$grok_home/skills/vibe-learn/SKILL.md" ]
  [ ! -e "$fake_home/.grok/hooks/vibe-learn.json" ]

  rm -rf "$fake_home" "$(dirname "$grok_home")"
}

@test "grok project install reminds about hooks-trust" {
  run bash "$ADAPTERS_DIR/grok/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  echo "$output" | grep -q "hooks-trust"
}

@test "grok install is idempotent" {
  run_grok_install
  run_grok_install

  [ -f "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json" ]
  local count
  count=$(jq '.hooks.SessionStart | length' "$TEST_PROJECT_DIR/.grok/hooks/vibe-learn.json")
  [ "$count" -eq 1 ]
}

@test "grok install creates .gitignore with .vibe-learn entry" {
  run_grok_install
  [ -f "$TEST_PROJECT_DIR/.gitignore" ]
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"
}

@test "grok install appends to existing .gitignore without duplicating" {
  echo "node_modules/" > "$TEST_PROJECT_DIR/.gitignore"
  run_grok_install
  grep -q 'node_modules/' "$TEST_PROJECT_DIR/.gitignore"
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"

  run_grok_install
  local count
  count=$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")
  [ "$count" -eq 1 ]
}

@test "grok install does not touch unrelated hook files" {
  mkdir -p "$TEST_PROJECT_DIR/.grok/hooks"
  echo '{"hooks":{"PreToolUse":[]}}' > "$TEST_PROJECT_DIR/.grok/hooks/other.json"

  run_grok_install

  [ -f "$TEST_PROJECT_DIR/.grok/hooks/other.json" ]
  jq -e '.hooks.PreToolUse' "$TEST_PROJECT_DIR/.grok/hooks/other.json" >/dev/null
}

@test "grok install makes scripts executable" {
  run_grok_install
  [ -x "$SCRIPTS_DIR/bootstrap.sh" ]
  [ -x "$SCRIPTS_DIR/observe.sh" ]
  [ -x "$SCRIPTS_DIR/capture-prompt.sh" ]
  [ -x "$SCRIPTS_DIR/pause-summary.sh" ]
}
