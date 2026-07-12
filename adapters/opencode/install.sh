#!/bin/bash
# adapters/opencode/install.sh — OpenCode-specific install logic

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

COMMANDS_SOURCE="$VIBE_LEARN_DIR/adapters/opencode/commands"
PLUGIN_SOURCE="$VIBE_LEARN_DIR/adapters/opencode/plugins/vibe-learn.js"
ESCAPED_VIBE_LEARN_DIR="$(printf '%s' "$VIBE_LEARN_DIR" | sed 's/[&|\\]/\\&/g')"

if [ "$MODE" = "global" ]; then
  OPENCODE_DIR="$HOME/.config/opencode"
else
  OPENCODE_DIR="$TARGET_DIR/.opencode"
fi

COMMANDS_DIR="$OPENCODE_DIR/commands"
PLUGINS_DIR="$OPENCODE_DIR/plugins"

mkdir -p "$COMMANDS_DIR" "$PLUGINS_DIR"

cp "$COMMANDS_SOURCE/learn.md" "$COMMANDS_DIR/learn.md"
cp "$COMMANDS_SOURCE/digest.md" "$COMMANDS_DIR/digest.md"
cp "$COMMANDS_SOURCE/quiz.md" "$COMMANDS_DIR/quiz.md"
sed "s|INSTALL_DIR_PLACEHOLDER|$ESCAPED_VIBE_LEARN_DIR|g" "$PLUGIN_SOURCE" > "$PLUGINS_DIR/vibe-learn.js"

if [ "$MODE" = "global" ]; then
  echo "✓ OpenCode commands installed (~/.config/opencode/commands/learn.md, digest.md, quiz.md)"
  echo "✓ OpenCode plugin installed (~/.config/opencode/plugins/vibe-learn.js)"
else
  echo "✓ OpenCode commands installed (.opencode/commands/learn.md, digest.md, quiz.md)"
  echo "✓ OpenCode plugin installed (.opencode/plugins/vibe-learn.js)"
fi

if [ -w "$VIBE_LEARN_DIR/scripts" ]; then
  chmod +x "$VIBE_LEARN_DIR/scripts/"*.sh
fi
echo "✓ Scripts are executable"

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
