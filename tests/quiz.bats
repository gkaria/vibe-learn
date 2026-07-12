#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# Command file structure
# ---------------------------------------------------------------------------

@test "claude-code quiz.md exists and references the session log and knowledge helper" {
  local cmd_file="$ADAPTERS_DIR/claude-code/commands/quiz.md"
  [ -f "$cmd_file" ]
  grep -q "session-log.jsonl" "$cmd_file"
  grep -q "knowledge.sh" "$cmd_file"
  grep -q "one question at a time" "$cmd_file"
}

@test "codex quiz prompt exists and references the session log and knowledge helper" {
  local cmd_file="$ADAPTERS_DIR/codex/prompts/quiz.md"
  [ -f "$cmd_file" ]
  grep -q "session-log.jsonl" "$cmd_file"
  grep -q "knowledge.sh" "$cmd_file"
  grep -q "one question at a time" "$cmd_file"
}

@test "opencode quiz.md exists and references the session log and knowledge helper" {
  local cmd_file="$ADAPTERS_DIR/opencode/commands/quiz.md"
  [ -f "$cmd_file" ]
  grep -q "session-log.jsonl" "$cmd_file"
  grep -q "knowledge.sh" "$cmd_file"
}

@test "quiz commands document the review mode" {
  grep -q "review" "$ADAPTERS_DIR/claude-code/commands/quiz.md"
  grep -q "review" "$ADAPTERS_DIR/codex/prompts/quiz.md"
  grep -q "review" "$ADAPTERS_DIR/opencode/commands/quiz.md"
}

@test "quiz commands never hand-edit the ledger" {
  grep -q "never hand-edit" "$ADAPTERS_DIR/claude-code/commands/quiz.md"
  grep -q "never hand-edit" "$ADAPTERS_DIR/codex/prompts/quiz.md"
  grep -q "never hand-edit" "$ADAPTERS_DIR/opencode/commands/quiz.md"
}

@test "dogfood .claude/commands/quiz.md matches the adapter copy" {
  diff "$VIBE_LEARN_DIR/.claude/commands/quiz.md" "$ADAPTERS_DIR/claude-code/commands/quiz.md"
}

# ---------------------------------------------------------------------------
# learn/digest feedback loop
# ---------------------------------------------------------------------------

@test "learn commands include the due-concept heads-up" {
  grep -q "knowledge.sh due" "$ADAPTERS_DIR/claude-code/commands/learn.md"
  grep -q "knowledge.sh due" "$ADAPTERS_DIR/codex/prompts/learn.md"
  grep -q "knowledge.sh due" "$ADAPTERS_DIR/opencode/commands/learn.md"
}

@test "digest commands make Things to Study cumulative and touch new concepts" {
  grep -q "knowledge.json" "$ADAPTERS_DIR/claude-code/commands/digest.md"
  grep -q "knowledge.sh touch" "$ADAPTERS_DIR/claude-code/commands/digest.md"
  grep -q "knowledge.sh touch" "$ADAPTERS_DIR/codex/prompts/digest.md"
  grep -q "knowledge.sh touch" "$ADAPTERS_DIR/opencode/commands/digest.md"
}

@test "obsidian note templates document recall_status frontmatter" {
  grep -q "recall_status" "$ADAPTERS_DIR/claude-code/commands/learn.md"
  grep -q "recall_status" "$ADAPTERS_DIR/claude-code/commands/digest.md"
  grep -q "recall_status" "$ADAPTERS_DIR/codex/prompts/learn.md"
  grep -q "recall_status" "$ADAPTERS_DIR/codex/prompts/digest.md"
}

@test "codex skill documents quiz mode and the knowledge ledger" {
  local skill_file="$ADAPTERS_DIR/codex/skills/vibe-learn/SKILL.md"
  grep -q "Quiz Mode" "$skill_file"
  grep -q "Knowledge Ledger" "$skill_file"
  grep -q "knowledge.sh" "$skill_file"
}

@test "techpack ships knowledge.sh alongside the quiz command" {
  grep -q "source: scripts/knowledge.sh" "$VIBE_LEARN_DIR/techpack.yaml"
  grep -q "source: .claude/commands/quiz.md" "$VIBE_LEARN_DIR/techpack.yaml"
}

# ---------------------------------------------------------------------------
# Install behavior
# ---------------------------------------------------------------------------

@test "claude-code project install copies quiz.md" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/commands/quiz.md" ]
}

@test "codex project install copies quiz prompt" {
  bash "$ADAPTERS_DIR/codex/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.codex/prompts/quiz.md" ]
}

@test "opencode project install copies quiz command" {
  bash "$ADAPTERS_DIR/opencode/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.opencode/commands/quiz.md" ]
}

@test "claude-code global install copies quiz.md" {
  local FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  HOME="$FAKE_HOME" bash "$ADAPTERS_DIR/claude-code/install.sh" --global "$VIBE_LEARN_DIR"
  [ -f "$FAKE_HOME/.claude/commands/quiz.md" ]
  rm -rf "$FAKE_HOME"
}

@test "quiz install is idempotent" {
  mkdir -p "$TEST_PROJECT_DIR/.claude"
  bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  bash "$ADAPTERS_DIR/claude-code/install.sh" "$VIBE_LEARN_DIR" "$TEST_PROJECT_DIR"
  [ -f "$TEST_PROJECT_DIR/.claude/commands/quiz.md" ]
}
