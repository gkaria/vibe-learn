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
  [ -f "$VIBE_LEARN_DIR/$commands/explain.md" ]
}

@test "plugin hooks.json registers all four lifecycle hooks" {
  jq -e '.hooks.SessionStart'     "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.UserPromptSubmit' "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.PostToolUse'      "$HOOKS_JSON" >/dev/null
  jq -e '.hooks.Stop'             "$HOOKS_JSON" >/dev/null
}

@test "plugin hooks.json registers PostToolUseFailure so failed tools are logged" {
  jq -e '.hooks.PostToolUseFailure' "$HOOKS_JSON" >/dev/null
  [ "$(jq -r '.hooks.PostToolUseFailure[0].matcher' "$HOOKS_JSON")" = "$(jq -r '.hooks.PostToolUse[0].matcher' "$HOOKS_JSON")" ]
  [ "$(jq '.hooks.PostToolUseFailure[0].hooks[0].timeout' "$HOOKS_JSON")" = "2" ]
  jq -e '.hooks.PostToolUseFailure[0].hooks[0].command | test("observe\\.sh")' "$HOOKS_JSON" >/dev/null
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

@test "plugin hooks.json declares the same timeouts as the settings installer" {
  [ "$(jq '.hooks.SessionStart[0].hooks[0].timeout' "$HOOKS_JSON")" = "5" ]
  [ "$(jq '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$HOOKS_JSON")" = "5" ]
  [ "$(jq '.hooks.PostToolUse[0].hooks[0].timeout' "$HOOKS_JSON")" = "2" ]
  [ "$(jq '.hooks.Stop[0].hooks[0].timeout' "$HOOKS_JSON")" = "10" ]
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

# ---------------------------------------------------------------------------
# Cursor plugin packaging (.cursor-plugin/)
# ---------------------------------------------------------------------------

CURSOR_PLUGIN_JSON="$VIBE_LEARN_DIR/.cursor-plugin/plugin.json"

@test "cursor plugin.json is valid JSON named vibe-learn" {
  jq -e '.name == "vibe-learn"' "$CURSOR_PLUGIN_JSON" >/dev/null
  # Cursor's plugin schema allows only name and email on author.
  jq -e '.author | keys - ["name", "email"] == []' "$CURSOR_PLUGIN_JSON" >/dev/null
}

@test "cursor plugin.json version matches VERSION and Claude manifest" {
  local v
  v=$(jq -r '.version' "$CURSOR_PLUGIN_JSON")
  [ "$v" = "$(cat "$VIBE_LEARN_DIR/VERSION")" ]
  [ "$v" = "$(jq -r '.version' "$PLUGIN_JSON")" ]
}

@test "cursor plugin.json component paths are relative and exist" {
  local skills hooks logo
  skills=$(jq -r '.skills' "$CURSOR_PLUGIN_JSON")
  hooks=$(jq -r '.hooks' "$CURSOR_PLUGIN_JSON")
  logo=$(jq -r '.logo' "$CURSOR_PLUGIN_JSON")
  [[ "$skills" == ./* ]]
  [[ "$hooks" == ./* ]]
  [ -d "$VIBE_LEARN_DIR/$skills" ]
  [ -f "$VIBE_LEARN_DIR/$hooks" ]
  [ -f "$VIBE_LEARN_DIR/$logo" ]
  for s in learn digest quiz explain vibe-learn; do
    [ -f "$VIBE_LEARN_DIR/$skills/$s/SKILL.md" ]
  done
}

@test "cursor plugin hooks have no placeholders and match the install template events" {
  local hooks
  hooks="$VIBE_LEARN_DIR/$(jq -r '.hooks' "$CURSOR_PLUGIN_JSON")"
  ! grep -q PLACEHOLDER "$hooks"
  [ "$(jq -c '.hooks | keys' "$hooks")" = "$(jq -c '.hooks | keys' "$VIBE_LEARN_DIR/adapters/cursor/hooks.json")" ]
}

@test "release-please bumps the cursor plugin manifest" {
  jq -e '.packages["."]["extra-files"][] | select(.path == ".cursor-plugin/plugin.json" and .jsonpath == "$.version")' \
    "$VIBE_LEARN_DIR/release-please-config.json" >/dev/null
}

@test "cursor shim resolves the plugin root when the placeholder is unreplaced" {
  local proj="$BATS_TEST_TMPDIR/proj"
  mkdir -p "$proj"
  printf '{"hook_event_name":"sessionStart","workspace_roots":["%s"],"session_id":"t1"}' "$proj" \
    | CURSOR_PLUGIN_ROOT="$VIBE_LEARN_DIR" bash "$VIBE_LEARN_DIR/adapters/cursor/hooks/vibe-learn.sh" >/dev/null
  [ -d "$proj/.vibe-learn" ]
}
