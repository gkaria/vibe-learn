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

mkdir -p "$COMMANDS_DIR"

# Copy slash commands
cp "$COMMANDS_SOURCE/learn.md" "$COMMANDS_DIR/learn.md"
cp "$COMMANDS_SOURCE/digest.md" "$COMMANDS_DIR/digest.md"
echo "✓ Slash commands installed (/learn, /digest)"

HOOKS_JSON=$(cat <<EOF
{
  "SessionStart": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/bootstrap.sh"}]
    }
  ],
  "UserPromptSubmit": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/capture-prompt.sh"}]
    }
  ],
  "PostToolUse": [
    {
      "matcher": "Write|Edit|MultiEdit|Bash",
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/observe.sh"}]
    }
  ],
  "Stop": [
    {
      "hooks": [{"type": "command", "command": "$HOOK_BASE/scripts/pause-summary.sh"}]
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
