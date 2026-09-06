#!/bin/bash
# adapters/claude-code/install.sh — Claude Code-specific install logic
# Called by scripts/install.sh and scripts/setup.sh.
#
# Usage:
#   adapters/claude-code/install.sh --global <VIBE_LEARN_DIR>
#   adapters/claude-code/install.sh <VIBE_LEARN_DIR> <TARGET_DIR>

set -euo pipefail

MODE=""
VIBE_LEARN_DIR=""
TARGET_DIR=""

if [ "${1:-}" = "--global" ]; then
  MODE="global"
  VIBE_LEARN_DIR="${2:-}"
  TARGET_DIR="$HOME"
else
  MODE="project"
  VIBE_LEARN_DIR="${1:-}"
  TARGET_DIR="${2:-$(pwd)}"
fi

if [ -z "$VIBE_LEARN_DIR" ]; then
  echo "ERROR: VIBE_LEARN_DIR not provided." >&2
  exit 1
fi

COMMANDS_SOURCE="$VIBE_LEARN_DIR/adapters/claude-code/commands"

if [ "$MODE" = "global" ]; then
  CLAUDE_DIR="$HOME/.claude"
  COMMANDS_DIR="$CLAUDE_DIR/commands"
  SETTINGS_FILE="$CLAUDE_DIR/settings.json"
  HOOK_BASE="$VIBE_LEARN_DIR"
else
  CLAUDE_DIR="$TARGET_DIR/.claude"
  COMMANDS_DIR="$CLAUDE_DIR/commands"
  SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"
  HOOK_BASE="$VIBE_LEARN_DIR"
fi

# The Claude Code plugin ships the same hooks and commands. Installing both would
# log every tool event twice, so defer to the plugin when it is enabled — and strip
# any leftover curl/settings hook entries so a migration from the old install path
# does not double-fire.
claude_settings_candidates() {
  echo "$HOME/.claude/settings.json"
  if [ "$MODE" = "project" ]; then
    echo "$TARGET_DIR/.claude/settings.json"
    echo "$TARGET_DIR/.claude/settings.local.json"
  fi
}

plugin_enabled() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    if jq -e '(.enabledPlugins // {}) | to_entries[] | select((.key | startswith("vibe-learn@")) and .value == true)' "$f" >/dev/null 2>&1; then
      return 0
    fi
  done < <(claude_settings_candidates)
  return 1
}

# Drop matcher groups whose command points at a vibe-learn core script. Leaves
# unrelated hooks alone. Returns 0 if anything was removed.
strip_legacy_vibe_learn_hooks() {
  local settings_file="$1"
  [ -f "$settings_file" ] || return 1
  jq -e '.hooks | type == "object"' "$settings_file" >/dev/null 2>&1 || return 1

  local tmp cleaned removed
  tmp="$(mktemp)"
  cleaned="$(jq '
    def is_vibe:
      (.command // "") | test("/(bootstrap|capture-prompt|observe|pause-summary)\\.sh$")
        or test("vibe-learn/.*/scripts/(bootstrap|capture-prompt|observe|pause-summary)\\.sh");
    def scrub:
      map(select(((.hooks // []) | map(is_vibe) | any) | not));
    . as $root
    | ($root.hooks // {}) as $h
    | ($h | to_entries
        | map(.value = (.value | scrub))
        | map(select(.value | length > 0))
        | from_entries) as $new
    | $root
    | if ($new | length) == 0 then del(.hooks)
      else .hooks = $new end
  ' "$settings_file")"

  if [ "$(jq -c '.hooks // null' "$settings_file")" = "$(printf '%s' "$cleaned" | jq -c '.hooks // null')" ]; then
    rm -f "$tmp"
    return 1
  fi
  printf '%s\n' "$cleaned" > "$tmp"
  mv "$tmp" "$settings_file"
  return 0
}

if [ "${VIBE_LEARN_IGNORE_PLUGIN:-}" != "1" ] && plugin_enabled; then
  echo "⚠ The vibe-learn Claude Code plugin is already enabled — skipping hook and command install."
  echo "  The plugin provides the hooks and /vibe-learn:learn, /vibe-learn:digest, /vibe-learn:quiz, /vibe-learn:explain."
  stripped=0
  while IFS= read -r f; do
    if strip_legacy_vibe_learn_hooks "$f"; then
      echo "  Removed legacy vibe-learn hooks from $f (plugin owns them now)."
      stripped=1
    fi
  done < <(claude_settings_candidates)
  if [ "$stripped" -eq 0 ]; then
    echo "  No leftover settings.json hooks found."
  fi
  echo "  To install settings.json hooks anyway (double-logging!): VIBE_LEARN_IGNORE_PLUGIN=1"
  SKIP_CLAUDE_REGISTRATION=true
else
  SKIP_CLAUDE_REGISTRATION=false
fi

if [ "$SKIP_CLAUDE_REGISTRATION" = false ]; then

mkdir -p "$COMMANDS_DIR"

# Copy slash commands
cp "$COMMANDS_SOURCE/learn.md" "$COMMANDS_DIR/learn.md"
cp "$COMMANDS_SOURCE/digest.md" "$COMMANDS_DIR/digest.md"
cp "$COMMANDS_SOURCE/quiz.md" "$COMMANDS_DIR/quiz.md"
cp "$COMMANDS_SOURCE/explain.md" "$COMMANDS_DIR/explain.md"
echo "✓ Slash commands installed (/learn, /digest, /quiz, /explain)"

# Timeouts match adapters/claude-code/hooks.json (plugin manifest). Keep both in sync.
HOOKS_JSON=$(cat <<EOF
{
  "SessionStart": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/bootstrap.sh", "timeout": 5}]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/capture-prompt.sh", "timeout": 5}]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit|MultiEdit|Bash",
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/observe.sh", "timeout": 2}]
    }
  ],
  "Stop": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/pause-summary.sh", "timeout": 10}]
    }
  ]
}
EOF
)

if [ ! -f "$SETTINGS_FILE" ]; then
  jq -n --argjson hooks "$HOOKS_JSON" '{hooks: $hooks}' > "$SETTINGS_FILE"
  if [ "$MODE" = "global" ]; then
    echo "✓ Created ~/.claude/settings.json with global hooks"
  else
    echo "✓ Created .claude/settings.local.json"
  fi
elif jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
  if [ "$MODE" = "global" ]; then
    echo "⚠ ~/.claude/settings.json already has hooks — skipping global hook merge."
    echo "  To re-register: remove the \"hooks\" key from ~/.claude/settings.json and re-run setup."
  else
    echo "⚠ .claude/settings.local.json already has hooks — skipping hook merge."
    echo "  Add the hooks manually or remove existing hooks first, then re-run."
  fi
else
  TMP=$(mktemp)
  jq --argjson hooks "$HOOKS_JSON" '. + {hooks: $hooks}' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"
  if [ "$MODE" = "global" ]; then
    echo "✓ Merged vibe-learn hooks into ~/.claude/settings.json"
  else
    echo "✓ Merged hooks into existing .claude/settings.local.json"
  fi
fi

fi # SKIP_CLAUDE_REGISTRATION

# Make scripts executable if writable
if [ -w "$VIBE_LEARN_DIR/scripts" ]; then
  chmod +x "$VIBE_LEARN_DIR/scripts/"*.sh
fi
echo "✓ Scripts are executable"

# gitignore (project-level only)
if [ "$MODE" = "project" ]; then
  GITIGNORE="$TARGET_DIR/.gitignore"
  if [ -f "$GITIGNORE" ]; then
    if ! grep -q '\.vibe-learn' "$GITIGNORE"; then
      echo "" >> "$GITIGNORE"
      echo "# vibe-learn session logs" >> "$GITIGNORE"
      echo ".vibe-learn/" >> "$GITIGNORE"
      echo "✓ Added .vibe-learn/ to .gitignore"
    else
      echo "✓ .gitignore already excludes .vibe-learn/"
    fi
  else
    echo "# vibe-learn session logs" > "$GITIGNORE"
    echo ".vibe-learn/" >> "$GITIGNORE"
    echo "✓ Created .gitignore with .vibe-learn/"
  fi
fi
