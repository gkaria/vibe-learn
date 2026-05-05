#!/usr/bin/env bats

load test_helper

# Helper: run the codex adapter install.sh directly (project mode)
run_codex_install() {
  bash "$ADAPTERS_DIR/codex/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
}

# Helper: run the codex adapter install.sh directly (global mode)
run_codex_global_install() {
  HOME="$1" bash "$ADAPTERS_DIR/codex/install.sh" --global "$VIBE_LEARN_DIR"
}

@test "codex install creates .codex/prompts/learn.md" {
  run_codex_install
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/learn.md" ]
}

@test "codex install creates .codex/prompts/digest.md" {
  run_codex_install
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/digest.md" ]
}

@test "codex global install creates vibe-learn skill" {
  local fake_home
  fake_home="$(mktemp -d)"

  run_codex_global_install "$fake_home"

  [ -f "$fake_home/.codex/skills/vibe-learn/SKILL.md" ]
  grep -q 'name: vibe-learn' "$fake_home/.codex/skills/vibe-learn/SKILL.md"

  rm -rf "$fake_home"
}

@test "codex skill documents learn digest and Obsidian recall workflows" {
  grep -q 'session-log.jsonl' "$ADAPTERS_DIR/codex/skills/vibe-learn/SKILL.md"
  grep -q 'Digest Mode' "$ADAPTERS_DIR/codex/skills/vibe-learn/SKILL.md"
  grep -q 'obsidian:recall' "$ADAPTERS_DIR/codex/skills/vibe-learn/SKILL.md"
}

@test "codex install creates .codex/config.toml with hooks section" {
  run_codex_install
  [ -f "$TEST_PROJECT_DIR/.codex/config.toml" ]
  grep -q '^\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install writes [features] codex_hooks = true" {
  run_codex_install
  grep -q '^\[features\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  grep -q 'codex_hooks = true' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install uses nested [[hooks.Event.hooks]] structure with type = command" {
  run_codex_install
  grep -q '^\[\[hooks\.SessionStart\.hooks\]\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  grep -q 'type = "command"' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install matches Bash and apply_patch PostToolUse events" {
  run_codex_install
  grep -q 'matcher = "\^(Bash|apply_patch)\$"' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install writes SessionStart hook pointing to bootstrap.sh" {
  run_codex_install
  grep -q "bootstrap.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install writes PostToolUse hook pointing to observe.sh" {
  run_codex_install
  grep -q "observe.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install writes Stop hook pointing to pause-summary.sh" {
  run_codex_install
  grep -q "pause-summary.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install hook paths point to VIBE_LEARN_DIR scripts" {
  run_codex_install
  grep -q "$VIBE_LEARN_DIR/scripts/bootstrap.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install appends hooks to existing config.toml without hooks section" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  echo '[model]' > "$TEST_PROJECT_DIR/.codex/config.toml"
  echo 'name = "o3"' >> "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q '^\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml"
  grep -q '\[model\]' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install appends hooks even when [hooks] section already exists from other tools" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  printf '[hooks]\n\n[[hooks.Stop]]\n[[hooks.Stop.hooks]]\ntype = "command"\ncommand = "other-tool.sh"\n' \
    > "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q "bootstrap.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
  grep -q "other-tool.sh" "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install adds [features] codex_hooks = true when [features] section is absent" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  echo '[model]' > "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q 'codex_hooks = true' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install adds codex_hooks under existing [features] section" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  printf '[features]\nsome_other_flag = true\n' > "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q 'codex_hooks = true' "$TEST_PROJECT_DIR/.codex/config.toml"
  grep -q 'some_other_flag = true' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install changes existing codex_hooks false to true" {
  mkdir -p "$TEST_PROJECT_DIR/.codex"
  printf '[features]\ncodex_hooks = false\n' > "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q 'codex_hooks = true' "$TEST_PROJECT_DIR/.codex/config.toml"
  ! grep -q 'codex_hooks = false' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install re-enables codex_hooks when vibe-learn hooks already exist" {
  run_codex_install
  perl -0pi -e 's/codex_hooks = true/codex_hooks = false/' "$TEST_PROJECT_DIR/.codex/config.toml"

  run_codex_install

  grep -q 'codex_hooks = true' "$TEST_PROJECT_DIR/.codex/config.toml"
  ! grep -q 'codex_hooks = false' "$TEST_PROJECT_DIR/.codex/config.toml"
}

@test "codex install is idempotent — running twice does not duplicate hooks" {
  run_codex_install
  run_codex_install

  local count
  count=$(grep -c '^\[hooks\]' "$TEST_PROJECT_DIR/.codex/config.toml")
  [ "$count" -eq 1 ]
}

@test "codex install is idempotent — bootstrap.sh appears exactly once" {
  run_codex_install
  run_codex_install

  local count
  count=$(grep -c "bootstrap.sh" "$TEST_PROJECT_DIR/.codex/config.toml")
  [ "$count" -eq 1 ]
}

@test "codex install creates .gitignore with .vibe-learn entry" {
  run_codex_install
  [ -f "$TEST_PROJECT_DIR/.gitignore" ]
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"
}

@test "codex install appends to existing .gitignore without duplicating" {
  echo "node_modules/" > "$TEST_PROJECT_DIR/.gitignore"
  run_codex_install
  grep -q 'node_modules/' "$TEST_PROJECT_DIR/.gitignore"
  grep -q '\.vibe-learn/' "$TEST_PROJECT_DIR/.gitignore"

  # Run again — should not duplicate
  run_codex_install
  local count
  count=$(grep -c '\.vibe-learn' "$TEST_PROJECT_DIR/.gitignore")
  [ "$count" -eq 1 ]
}

@test "codex install makes scripts executable" {
  run_codex_install
  [ -x "$SCRIPTS_DIR/bootstrap.sh" ]
  [ -x "$SCRIPTS_DIR/observe.sh" ]
  [ -x "$SCRIPTS_DIR/capture-prompt.sh" ]
  [ -x "$SCRIPTS_DIR/pause-summary.sh" ]
}
