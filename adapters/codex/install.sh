#!/bin/bash
# adapters/codex/install.sh — Codex CLI-specific install logic
# Called by scripts/install.sh and scripts/setup.sh.
#
# Usage:
#   adapters/codex/install.sh --global <VIBE_LEARN_DIR>
#   adapters/codex/install.sh <VIBE_LEARN_DIR> <TARGET_DIR>
#
# Codex requires [features] codex_hooks = true to activate any hooks.
# This script writes that flag and the vibe-learn hook entries.
#
# Idempotency: keyed on the "# vibe-learn" marker in config.toml.
# Safe to run alongside existing unrelated Codex hooks — does NOT skip
# if other hooks are already present, only skips if vibe-learn is already there.
#
# NOTE: Codex PostToolUse fires reliably for Bash only. File edit/write events
# (apply_patch) are not exposed via PostToolUse in current Codex versions.
# observe.sh will capture bash commands; file events require a future Codex update.

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

HOOKS_TEMPLATE="$VIBE_LEARN_DIR/adapters/codex/hooks.toml"
PROMPTS_SOURCE="$VIBE_LEARN_DIR/adapters/codex/prompts"

if [ "$MODE" = "global" ]; then
  CODEX_DIR="$HOME/.codex"
  PROMPTS_DIR="$CODEX_DIR/prompts"
  CONFIG_FILE="$CODEX_DIR/config.toml"
else
  CODEX_DIR="$TARGET_DIR/.codex"
  PROMPTS_DIR="$CODEX_DIR/prompts"
  CONFIG_FILE="$CODEX_DIR/config.toml"
fi

mkdir -p "$PROMPTS_DIR"

# Copy prompts
cp "$PROMPTS_SOURCE/learn.md" "$PROMPTS_DIR/learn.md"
cp "$PROMPTS_SOURCE/digest.md" "$PROMPTS_DIR/digest.md"
echo "✓ Prompts installed (/prompts:learn, /prompts:digest)"

# Render hooks block (replace INSTALL_DIR_PLACEHOLDER with actual path)
RENDERED_HOOKS=$(sed "s|INSTALL_DIR_PLACEHOLDER|$VIBE_LEARN_DIR|g" "$HOOKS_TEMPLATE")

# Idempotency marker — keyed on our specific hook path, not on [hooks] existence.
# This lets us append safely alongside existing unrelated Codex hooks.
IDEMPOTENCY_MARKER="$VIBE_LEARN_DIR/scripts/bootstrap.sh"

if [ ! -f "$CONFIG_FILE" ]; then
  echo "$RENDERED_HOOKS" > "$CONFIG_FILE"
  if [ "$MODE" = "global" ]; then
    echo "✓ Created ~/.codex/config.toml with hooks and codex_hooks feature flag"
  else
    echo "✓ Created .codex/config.toml with hooks and codex_hooks feature flag"
  fi
elif grep -qF "$IDEMPOTENCY_MARKER" "$CONFIG_FILE"; then
  if [ "$MODE" = "global" ]; then
    echo "✓ vibe-learn hooks already present in ~/.codex/config.toml — skipping."
  else
    echo "✓ vibe-learn hooks already present in .codex/config.toml — skipping."
  fi
else
  # Ensure the [features] codex_hooks flag is present — required to activate any hooks.
  if ! grep -q '^\[features\]' "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    printf '[features]\ncodex_hooks = true\n' >> "$CONFIG_FILE"
  elif ! grep -q 'codex_hooks' "$CONFIG_FILE"; then
    # [features] section exists but codex_hooks not set — insert after the header
    TMP=$(mktemp)
    awk '/^\[features\]/{print; print "codex_hooks = true"; next}1' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
  fi

  # Append the hooks block (skipping the [features] lines already written above)
  HOOKS_ONLY=$(echo "$RENDERED_HOOKS" | sed '/^\[features\]/,/^$/d')
  echo "" >> "$CONFIG_FILE"
  echo "$HOOKS_ONLY" >> "$CONFIG_FILE"

  if [ "$MODE" = "global" ]; then
    echo "✓ Merged vibe-learn hooks into ~/.codex/config.toml"
  else
    echo "✓ Merged hooks into existing .codex/config.toml"
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
