#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# Claude Code plugin packaging (.claude-plugin/, bin/)
# ---------------------------------------------------------------------------

PLUGIN_JSON="$VIBE_LEARN_DIR/.claude-plugin/plugin.json"
MARKETPLACE_JSON="$VIBE_LEARN_DIR/.claude-plugin/marketplace.json"
HOOKS_JSON="$VIBE_LEARN_DIR/adapters/claude-code/hooks.json"

@test "plugin.json is valid JSON named vibe-learn" {
  jq -e '.name == "vibe-learn"' "$PLUGIN_JSON" >/dev/null
}

@test "plugin.json version matches VERSION" {
  local manifest_version repo_version
  manifest_version=$(jq -r '.version' "$PLUGIN_JSON")
  repo_version=$(cat "$VIBE_LEARN_DIR/VERSION")
  [ "$manifest_version" = "$repo_version" ]
}

@test "plugin.json component paths are relative and exist" {
  local commands hooks
  commands=$(jq -r '.commands' "$PLUGIN_JSON")
  hooks=$(jq -r '.hooks' "$PLUGIN_JSON")
  [[ "$commands" == ./* ]]
  [[ "$hooks" == ./* ]]
  [ -d "$VIBE_LEARN_DIR/$commands" ]
  [ -f "$VIBE_LEARN_DIR/$hooks" ]
}

@test "plugin commands directory ships learn, digest, and quiz" {
  local commands
  commands=$(jq -r '.commands' "$PLUGIN_JSON")
  [ -f "$VIBE_LEARN_DIR/$commands/learn.md" ]
  [ -f "$VIBE_LEARN_DIR/$commands/digest.md" ]
  [ -f "$VIBE_LEARN_DIR/$commands/quiz.md" ]
}

@test "plugin hooks.json registers all four lifecycle hooks" {
  jq -e '.hooks.SessionStart'     "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.UserPromptSubmit' "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.PostToolUse'      "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.Stop'             "$HOOKS_JSON" >/dev/null
}

@test "plugin hooks.json commands resolve to scripts that exist in the repo" {
  local cmd script
  while IFS= read -r cmd; do
    [[ "$cmd" == *'${CLAUDE_PLUGIN_ROOT}'* ]]
    script="${cmd#*\$\{CLAUDE_PLUGIN_ROOT\}/}"
    script="${script%\"}"
    [ -x "$VIBE_LEARN_DIR/$script" ]
  done < <(jq -r '.hooks[][].hooks[].command' "$HOOKS_JSON")
}

@test "plugin hooks.json quotes CLAUDE_PLUGIN_ROOT so paths with spaces work" {
  local cmd
  while IFS= read -r cmd; do
    [[ "$cmd" == '"${CLAUDE_PLUGIN_ROOT}/'*'"' ]]
  done < <(jq -r '.hooks[][].hooks[].command' "$HOOKS_JSON")
}

@test "plugin hooks.json PostToolUse matcher covers Write, Edit, MultiEdit, and Bash" {
  local matcher
  matcher=$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS_JSON")
  [ "$matcher" = "Write|Edit|MultiEdit|Bash" ]
}

@test "marketplace.json lists the vibe-learn plugin from the GitHub repo" {
  jq -e '.name == "vibe-learn"' "$MARKETPLACE_JSON" >/dev/null
  jq -e '.owner.name | length > 0' "$MARKETPLACE_JSON" >/dev/null
  jq -e '.plugins[0].name == "vibe-learn"' "$MARKETPLACE_JSON" >/dev/null
  jq -e '.plugins[0].source.source == "github"' "$MARKETPLACE_JSON" >/dev/null
  jq -e '.plugins[0].source.repo == "gkaria/vibe-learn"' "$MARKETPLACE_JSON" >/dev/null
}

@test "marketplace.json does not pin a version (plugin.json is the single source)" {
  jq -e '.plugins[0] | has("version") | not' "$MARKETPLACE_JSON" >/dev/null
}

@test "bin/ wrappers are executable and delegate to the core scripts" {
  [ -x "$VIBE_LEARN_DIR/bin/vibe-learn" ]
  [ -x "$VIBE_LEARN_DIR/bin/vibe-learn-knowledge" ]

  run "$VIBE_LEARN_DIR/bin/vibe-learn" help
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "vibe-learn install"

  cd "$TEST_PROJECT_DIR"
  run "$VIBE_LEARN_DIR/bin/vibe-learn-knowledge" list
  [ "$status" -eq 0 ]
  echo "$output" | jq -e '.concepts == []' >/dev/null
}

@test "bin/ wrappers work from a copy of the repo (plugin cache layout)" {
  local cache="$TEST_PROJECT_DIR/cache/vibe-learn/0.0.0"
  mkdir -p "$cache"
  cp -R "$VIBE_LEARN_DIR/bin" "$VIBE_LEARN_DIR/scripts" "$VIBE_LEARN_DIR/config" "$cache/"

  run "$cache/bin/vibe-learn" help
  [ "$status" -eq 0 ]
}

@test "command files prefer vibe-learn-knowledge on PATH before the global install path" {
  local cmd_dir="$VIBE_LEARN_DIR/adapters/claude-code/commands"
  grep -q "vibe-learn-knowledge" "$cmd_dir/learn.md"
  grep -q "vibe-learn-knowledge" "$cmd_dir/digest.md"
  grep -q "vibe-learn-knowledge" "$cmd_dir/quiz.md"
}

@test "dogfood .claude/commands match the plugin command directory" {
  diff "$VIBE_LEARN_DIR/.claude/commands/learn.md"  "$VIBE_LEARN_DIR/adapters/claude-code/commands/learn.md"
  diff "$VIBE_LEARN_DIR/.claude/commands/digest.md" "$VIBE_LEARN_DIR/adapters/claude-code/commands/digest.md"
}
