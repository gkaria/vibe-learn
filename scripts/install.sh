#!/bin/bash
# install.sh — Wire vibe-learn into any project
# Run from the root of the project you want to install vibe-learn into:
#   bash /path/to/vibe-learn/scripts/install.sh

set -euo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR="${1:-$(pwd)}"
CLAUDE_DIR="$TARGET_DIR/.claude"
COMMANDS_DIR="$CLAUDE_DIR/commands"
SETTINGS_FILE="$CLAUDE_DIR/settings.local.json"

echo "Installing vibe-learn into: $TARGET_DIR"

# --- Create .claude/commands/ ---
mkdir -p "$COMMANDS_DIR"

# --- Copy slash commands ---
cp "$VIBE_LEARN_DIR/.claude/commands/learn.md" "$COMMANDS_DIR/learn.md"
cp "$VIBE_LEARN_DIR/.claude/commands/digest.md" "$COMMANDS_DIR/digest.md"
echo "✓ Slash commands installed (/learn, /digest)"

# --- Write or merge settings.local.json ---
HOOKS_BLOCK=$(cat <<EOF
{
  "hooks": [
    {
      "event": "SessionStart",
      "hooks": [{"type": "command", "command": "$VIBE_LEARN_DIR/scripts/bootstrap.sh"}]
    },
    {
      "event": "UserPromptSubmit",
      "hooks": [{"type": "command", "command": "$VIBE_LEARN_DIR/scripts/capture-prompt.sh"}]
    },
    {
      "event": "PostToolUse",
      "matcher": "Write|Edit|MultiEdit|Bash",
      "hooks": [{"type": "command", "command": "$VIBE_LEARN_DIR/scripts/observe.sh"}]
    },
    {
      "event": "Stop",
      "hooks": [{"type": "command", "command": "$VIBE_LEARN_DIR/scripts/pause-summary.sh"}]
    }
  ]
}
EOF
)

if [ ! -f "$SETTINGS_FILE" ]; then
  # No existing settings — write fresh
  echo "$HOOKS_BLOCK" > "$SETTINGS_FILE"
  echo "✓ Created .claude/settings.local.json"
else
  # Existing settings — check if hooks already present
  if jq -e '.hooks' "$SETTINGS_FILE" > /dev/null 2>&1; then
    echo "⚠ .claude/settings.local.json already has hooks — skipping hook merge."
    echo "  Add the hooks manually or remove existing hooks first, then re-run."
  else
    # Merge hooks into existing settings
    TMP=$(mktemp)
    jq --argjson hooks "$(echo "$HOOKS_BLOCK" | jq '.hooks')" \
      '. + {hooks: $hooks}' "$SETTINGS_FILE" > "$TMP" && mv "$TMP" "$SETTINGS_FILE"
    echo "✓ Merged hooks into existing .claude/settings.local.json"
  fi
fi

# --- Make scripts executable ---
chmod +x "$VIBE_LEARN_DIR/scripts/"*.sh
echo "✓ Scripts are executable"

# --- Add .vibe-learn/ to .gitignore if not already there ---
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

echo ""
echo "✅ vibe-learn installed. Open this project in Claude Code to activate."
echo "   /learn    — explain what just happened, or ask a specific question"
echo "   /digest   — full session learning report"
