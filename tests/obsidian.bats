#!/usr/bin/env bats

load test_helper

# ---------------------------------------------------------------------------
# obsidian-defaults.json — structural validity
# ---------------------------------------------------------------------------

@test "obsidian-defaults.json is valid JSON" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  [ -f "$config_file" ]
  jq empty "$config_file"
}

@test "obsidian-defaults.json contains required keys" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  jq -e '.vault_path      != null' "$config_file" >/dev/null
  jq -e '.subfolder       != null' "$config_file" >/dev/null
  jq -e '.tags            != null' "$config_file" >/dev/null
  jq -e '.link_style      != null' "$config_file" >/dev/null
  jq -e '.include_project_tag != null' "$config_file" >/dev/null
  jq -e '.note_naming     != null' "$config_file" >/dev/null
}

@test "obsidian-defaults.json vault_path is empty string (no default)" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  local vault_path
  vault_path=$(jq -r '.vault_path' "$config_file")
  [ "$vault_path" = "" ]
}

@test "obsidian-defaults.json subfolder defaults to Development/Sessions" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  local subfolder
  subfolder=$(jq -r '.subfolder' "$config_file")
  [ "$subfolder" = "Development/Sessions" ]
}

@test "obsidian-defaults.json tags contains vibe-learn" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  jq -e '[.tags[] | select(. == "vibe-learn")] | length > 0' "$config_file" >/dev/null
}

@test "obsidian-defaults.json link_style is wikilink" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  local link_style
  link_style=$(jq -r '.link_style' "$config_file")
  [ "$link_style" = "wikilink" ]
}

@test "obsidian-defaults.json include_project_tag is true" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  local val
  val=$(jq -r '.include_project_tag' "$config_file")
  [ "$val" = "true" ]
}

@test "obsidian-defaults.json note_naming contains date and project tokens" {
  local config_file="$SCRIPTS_DIR/../config/obsidian-defaults.json"
  local note_naming
  note_naming=$(jq -r '.note_naming' "$config_file")
  [[ "$note_naming" == *"{date}"* ]]
  [[ "$note_naming" == *"{project}"* ]]
}

# ---------------------------------------------------------------------------
# setup.sh — installs obsidian-defaults.json
# ---------------------------------------------------------------------------

@test "setup installs obsidian-defaults.json to install dir" {
  local FAKE_HOME
  FAKE_HOME="$(mktemp -d)"
  HOME="$FAKE_HOME" bash "$SCRIPTS_DIR/setup.sh" --local

  [ -f "$FAKE_HOME/.vibe-learn/config/obsidian-defaults.json" ]
  jq empty "$FAKE_HOME/.vibe-learn/config/obsidian-defaults.json"

  rm -rf "$FAKE_HOME"
}

# ---------------------------------------------------------------------------
# Command file structure
# ---------------------------------------------------------------------------

@test "learn.md exists and has obsidian argument documented" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/learn.md"
  [ -f "$cmd_file" ]
  grep -q "obsidian:recall" "$cmd_file"
  grep -q "obsidian" "$cmd_file"
}

@test "digest.md exists and has obsidian argument documented" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/digest.md"
  [ -f "$cmd_file" ]
  grep -q "obsidian:recall" "$cmd_file"
  grep -q "obsidian" "$cmd_file"
}

@test "learn.md obsidian:recall branch specifies no file write" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/learn.md"
  grep -q "no file is written\|Do not write any file\|writes nothing" "$cmd_file"
}

@test "digest.md obsidian:recall branch includes Connections to Previous Work" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/digest.md"
  grep -q "Connections to Previous Work" "$cmd_file"
}

@test "learn.md config setup offers global save location" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/learn.md"
  grep -q '~/.vibe-learn/obsidian.json' "$cmd_file"
  grep -q 'global' "$cmd_file"
}

@test "digest.md config setup offers global save location" {
  local cmd_file="$SCRIPTS_DIR/../.claude/commands/digest.md"
  grep -q '~/.vibe-learn/obsidian.json' "$cmd_file"
  grep -q 'global' "$cmd_file"
}
