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

@test "setup adds PostToolUseFailure to a pre-existing global vibe-learn install" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  local f="$FAKE_HOME/.claude/settings.json"
  jq 'del(.hooks.PostToolUseFailure)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"

  run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  echo "$output" | grep -q "Added the PostToolUseFailure hook"
  [ "$(jq '.hooks.PostToolUseFailure | length' "$f")" = "1" ]

  run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  [ "$(jq '.hooks.PostToolUseFailure | length' "$f")" = "1" ]
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

@test "setup installs Cursor hooks shim and skills when Cursor is selected" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=cursor

  [ -f "$FAKE_HOME/.cursor/hooks.json" ]
  jq -e '.hooks.sessionStart' "$FAKE_HOME/.cursor/hooks.json" >/dev/null
  jq -e '.hooks.postToolUseFailure' "$FAKE_HOME/.cursor/hooks.json" >/dev/null
  [ "$(jq -r '.hooks.stop[0].command' "$FAKE_HOME/.cursor/hooks.json")" = "$FAKE_HOME/.cursor/hooks/vibe-learn.sh" ]
  [ -x "$FAKE_HOME/.cursor/hooks/vibe-learn.sh" ]
  grep -Fq "VIBE_LEARN_DIR=\"$FAKE_INSTALL_DIR\"" "$FAKE_HOME/.cursor/hooks/vibe-learn.sh"
  [ -f "$FAKE_INSTALL_DIR/adapters/cursor/skills/explain/SKILL.md" ]
  for skill in learn digest quiz explain vibe-learn; do
    [ -f "$FAKE_HOME/.cursor/skills/$skill/SKILL.md" ]
  done
}

@test "setup detects Cursor from ~/.cursor" {
  mkdir -p "$FAKE_HOME/.cursor"

  PATH="/usr/bin:/bin" bash "$SCRIPTS_DIR/setup.sh" --local

  [ -f "$FAKE_HOME/.cursor/hooks.json" ]
  [ ! -f "$FAKE_HOME/.claude/settings.json" ]
}

@test "setup skips Claude hook registration when the vibe-learn plugin is enabled" {
  mkdir -p "$FAKE_HOME/.claude"
  echo '{"enabledPlugins":{"vibe-learn@vibe-learn":true}}' > "$FAKE_HOME/.claude/settings.json"

  run bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code
  [ "$status" -eq 0 ]
  echo "$output" | grep -q "plugin is already enabled"
  ! jq -e '.hooks' "$FAKE_HOME/.claude/settings.json" >/dev/null 2>&1
  [ ! -f "$FAKE_HOME/.claude/commands/learn.md" ]
  # Scripts and CLI shim are still installed for vibe-learn briefing / recap
  [ -f "$FAKE_INSTALL_DIR/scripts/briefing.sh" ]
}

@test "setup ships scripts/lib so the installed capture hook marks learning turns" {
  bash "$SCRIPTS_DIR/setup.sh" --local --assistant=claude-code >/dev/null
  [ -f "$FAKE_INSTALL_DIR/scripts/lib/session.jq" ]
  jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "/digest"}' \
    | bash "$FAKE_INSTALL_DIR/scripts/capture-prompt.sh"
  [ "$(jq -r '.kind' "$TEST_PROJECT_DIR/.vibe-learn/session-log.jsonl")" = "learning" ]
}

@test "a flat techpack-style copy finds session.jq next to every script that includes it" {
  local flat="$FAKE_HOME/hooks" vl="$TEST_PROJECT_DIR/.vibe-learn" src dst f ts row
  mkdir -p "$flat"
  # Copy every script the techpack ships, side by side, as techpack.yaml maps them.
  while read -r src dst; do
    cp "$VIBE_LEARN_DIR/$src" "$flat/$dst"
  done < <(awk '$1 == "source:" { s = $2 } $1 == "destination:" && s ~ /^scripts\// && $2 !~ /\// { print s, $2 }' "$VIBE_LEARN_DIR/techpack.yaml")
  [ -f "$flat/session.jq" ]
  # Every script that includes session.jq must be in the copy and exercised below.
  for f in $(grep -l 'include "session"' "$SCRIPTS_DIR"/*.sh); do
    f="$(basename "$f")"
    [ "$f" = briefing.sh ] && continue   # not in the techpack
    [ -f "$flat/$f" ] || { echo "techpack does not ship $f"; return 1; }
    case "$f" in capture-prompt.sh|pause-summary.sh|health.sh|recap.sh) ;; *) echo "untested: $f"; return 1 ;; esac
  done

  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"session_id\":\"flat-1\"}" | bash "$flat/bootstrap.sh" >/dev/null
  jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "Build the alpha module with its own tests"}' | bash "$flat/capture-prompt.sh"
  ts="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  printf '{"timestamp":"%s","event":"tool_use","tool":"Write","file":"%s/src/alpha.js","action":"created"}\n' "$ts" "$TEST_PROJECT_DIR" >> "$vl/session-log.jsonl"
  echo "{\"cwd\":\"$TEST_PROJECT_DIR\",\"hook_event_name\":\"Stop\"}" | bash "$flat/pause-summary.sh" >/dev/null
  grep -q 'Goal: Build the alpha module with its own tests' "$vl/pause-summary.txt"
  grep -q 'src/alpha.js' "$vl/pause-summary.txt"

  jq -cn --arg cwd "$TEST_PROJECT_DIR" '{cwd: $cwd, prompt: "/quiz"}' | bash "$flat/capture-prompt.sh"
  [ "$(tail -n 1 "$vl/session-log.jsonl" | jq -r '.kind')" = "learning" ]

  # The learning turn is left out: one work prompt.
  row="$(bash "$flat/health.sh" "$vl")"
  [ "$(jq -r '.metrics.prompts' <<<"$row")" = 1 ]
  bash "$flat/recap.sh" "$TEST_PROJECT_DIR" | grep -q '1 prompt(s) · 1 file(s) touched'
}

@test "config/defaults.json lists only keys some script reads" {
  local key
  jq -e '._comment | test("never reads this file")' "$VIBE_LEARN_DIR/config/defaults.json" >/dev/null
  for key in $(jq -r 'del(._comment) | paths(scalars) | last' "$VIBE_LEARN_DIR/config/defaults.json"); do
    grep -rqE "\.$key\b" "$SCRIPTS_DIR" || { echo "no script reads $key"; return 1; }
  done
}
