#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# Command file content
# ---------------------------------------------------------------------------

@test "claude-code explain.md exists and is grounded in the session log and file:line references" {
  local cmd_file="$ADAPTERS_DIR/claude-code/commands/explain.md"
  [ -f "$cmd_file" ]
  grep -q "session-log.jsonl" "$cmd_file"
  grep -q "knowledge.sh" "$cmd_file"
  grep -q "vibe-learn-knowledge" "$cmd_file"
  grep -q 'file:line' "$cmd_file"
  grep -q "Entry point" "$cmd_file"
  grep -q "The spine" "$cmd_file"
  grep -q "The edges" "$cmd_file"
  grep -q "Connections" "$cmd_file"
}

@test "explain touches covered concepts and offers a quiz" {
  local cmd_file="$ADAPTERS_DIR/claude-code/commands/explain.md"
  grep -q "touch <name>" "$cmd_file"
  grep -q "never hand-edit" "$cmd_file"
  grep -q "/quiz <topic>" "$cmd_file"
}

@test "explain never invents structure" {
  grep -q "Never invent" "$ADAPTERS_DIR/claude-code/commands/explain.md"
}

@test "dogfood .claude/commands/explain.md matches the adapter copy" {
  diff "$VIBE_LEARN_DIR/.claude/commands/explain.md" "$ADAPTERS_DIR/claude-code/commands/explain.md"
}

@test "techpack, setup FILES, and instructions template list explain" {
  grep -q "source: .claude/commands/explain.md" "$VIBE_LEARN_DIR/techpack.yaml"
  grep -q '"adapters/claude-code/commands/explain.md"' "$SCRIPTS_DIR/setup.sh"
  grep -q '/explain' "$VIBE_LEARN_DIR/templates/instructions.md"
}

# ---------------------------------------------------------------------------
# Install behavior
# ---------------------------------------------------------------------------

@test "claude-code project install copies explain.md" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  run bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/commands/explain.md" ]
  echo "$output" | grep -q "/explain"
}

@test "claude-code global install copies explain.md" {
  local FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  HOME="$FAKE_HOME" bash "$ADAPTERS_DIR/claude-code/install.sh" --global "$VIBE_LEARN_DIR"
  [ -f "$FAKE_HOME/.claude/commands/explain.md" ]
  rm -rf "$FAKE_HOME"
}

@test "setup --local installs explain.md for Claude Code" {
  local FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  HOME="$FAKE_HOME" run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  [ "$status" -eq 0 ]
  [ -f "$FAKE_HOME/.vibe-learn/adapters/claude-code/commands/explain.md" ]
  [ -f "$FAKE_HOME/.claude/commands/explain.md" ]
  echo "$output" | grep -q "/explain"
  rm -rf "$FAKE_HOME"
}
