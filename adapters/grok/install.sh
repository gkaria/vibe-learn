#!/bin/bash
# adapters/grok/install.sh — Grok Build-specific install logic
# Called by scripts/install.sh and scripts/setup.sh.
#
# Usage:
#   adapters/grok/install.sh --global <VIBE_LEARN_DIR>
#   adapters/grok/install.sh <VIBE_LEARN_DIR> <TARGET_DIR>
#
# Writes a dedicated hook file so other Grok hooks are never touched.
# Global: ${GROK_HOME:-$HOME/.grok}/hooks/vibe-learn.json (always trusted).
# Project: .grok/hooks/vibe-learn.json (requires /hooks-trust).

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

HOOKS_TEMPLATE="$VIBE_LEARN_DIR/adapters/grok/hooks.json"
COMMANDS_SOURCE="$VIBE_LEARN_DIR/adapters/grok/commands"
SKILL_SOURCE="$VIBE_LEARN_DIR/adapters/grok/skills/vibe-learn/SKILL.md"

# POSIX single-quote so Grok can `sh -c` the command when the path has spaces.
shell_quote() {
  printf "'%s'" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

if [ "$MODE" = "global" ]; then
  GROK_DIR="${GROK_HOME:-$HOME/.grok}"
else
  GROK_DIR="$TARGET_DIR/.grok"
fi

HOOKS_DIR="$GROK_DIR/hooks"
COMMANDS_DIR="$GROK_DIR/commands"
SKILL_DIR="$GROK_DIR/skills/vibe-learn"
HOOKS_FILE="$HOOKS_DIR/vibe-learn.json"

mkdir -p "$HOOKS_DIR" "$COMMANDS_DIR" "$SKILL_DIR"

jq \
  --arg bootstrap "$(shell_quote "$VIBE_LEARN_DIR/scripts/bootstrap.sh")" \
  --arg capture "$(shell_quote "$VIBE_LEARN_DIR/scripts/capture-prompt.sh")" \
  --arg observe "$(shell_quote "$VIBE_LEARN_DIR/scripts/observe.sh")" \
  --arg pause "$(shell_quote "$VIBE_LEARN_DIR/scripts/pause-summary.sh")" \
  '
    .hooks.SessionStart[0].hooks[0].command = $bootstrap
    | .hooks.UserPromptSubmit[0].hooks[0].command = $capture
    | .hooks.PostToolUse[0].hooks[0].command = $observe
    | .hooks.PostToolUseFailure[0].hooks[0].command = $observe
    | .hooks.Stop[0].hooks[0].command = $pause
  ' "$HOOKS_TEMPLATE" > "$HOOKS_FILE"

cp "$COMMANDS_SOURCE/learn.md" "$COMMANDS_DIR/learn.md"
cp "$COMMANDS_SOURCE/digest.md" "$COMMANDS_DIR/digest.md"
cp "$COMMANDS_SOURCE/quiz.md" "$COMMANDS_DIR/quiz.md"
cp "$SKILL_SOURCE" "$SKILL_DIR/SKILL.md"

if [ "$MODE" = "global" ]; then
  echo "✓ Grok Build hooks installed ($HOOKS_FILE)"
  echo "✓ Slash commands installed ($COMMANDS_DIR/learn.md, digest.md, quiz.md)"
  echo "✓ Skill installed ($SKILL_DIR/SKILL.md)"
else
  echo "✓ Grok Build hooks installed (.grok/hooks/vibe-learn.json)"
  echo "✓ Slash commands installed (.grok/commands/learn.md, digest.md, quiz.md)"
  echo "✓ Skill installed (.grok/skills/vibe-learn/SKILL.md)"
  echo "  Project hooks stay inert until you trust this folder: /hooks-trust"
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
