#!/bin/bash
# adapters/codex/install.sh — Codex CLI-specific install logic
# Called by scripts/install.sh and scripts/setup.sh.
#
# Usage:
#   adapters/codex/install.sh --global <VIBE_LEARN_DIR>
#   adapters/codex/install.sh <VIBE_LEARN_DIR> <TARGET_DIR>
#
# Codex hooks are enabled by default. This script writes the canonical
# [features] hooks = true flag in case hooks were disabled, plus vibe-learn
# hook entries.
#
# Idempotency: keyed on the "# vibe-learn" marker in config.toml.
# Safe to run alongside existing unrelated Codex hooks — does NOT skip
# if other hooks are already present, only skips if vibe-learn is already there.
#
# NOTE: Codex reports shell commands as Bash and file edits through apply_patch.
# Edit and Write are documented matcher aliases; hook input still reports
# tool_name = "apply_patch", which observe.sh normalizes into session-log entries.

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
SKILL_SOURCE="$VIBE_LEARN_DIR/adapters/codex/skills/vibe-learn/SKILL.md"
ESCAPED_VIBE_LEARN_DIR="$(printf '%s' "$VIBE_LEARN_DIR" | sed 's/[&|\\]/\\&/g')"

if [ "$MODE" = "global" ]; then
  CODEX_DIR="$HOME/.codex"
  PROMPTS_DIR="$CODEX_DIR/prompts"
  SKILL_DIR="$CODEX_DIR/skills/vibe-learn"
  CONFIG_FILE="$CODEX_DIR/config.toml"
else
  CODEX_DIR="$TARGET_DIR/.codex"
  PROMPTS_DIR="$CODEX_DIR/prompts"
  SKILL_DIR=""
  CONFIG_FILE="$CODEX_DIR/config.toml"
fi

mkdir -p "$PROMPTS_DIR"

# Copy prompts
cp "$PROMPTS_SOURCE/learn.md" "$PROMPTS_DIR/learn.md"
cp "$PROMPTS_SOURCE/digest.md" "$PROMPTS_DIR/digest.md"
cp "$PROMPTS_SOURCE/quiz.md" "$PROMPTS_DIR/quiz.md"
if [ "$MODE" = "global" ]; then
  echo "✓ Prompt fallbacks installed (~/.codex/prompts/learn.md, digest.md, quiz.md)"
else
  echo "✓ Prompt fallbacks installed (.codex/prompts/learn.md, digest.md, quiz.md)"
fi

if [ "$MODE" = "global" ]; then
  mkdir -p "$SKILL_DIR"
  cp "$SKILL_SOURCE" "$SKILL_DIR/SKILL.md"
  echo "✓ Skill installed (~/.codex/skills/vibe-learn/SKILL.md)"
fi

# Render hooks block (replace INSTALL_DIR_PLACEHOLDER with actual path)
RENDERED_HOOKS=$(sed "s|INSTALL_DIR_PLACEHOLDER|$ESCAPED_VIBE_LEARN_DIR|g" "$HOOKS_TEMPLATE")

# Idempotency marker — keyed on our specific hook path, not on [hooks] existence.
# This lets us append safely alongside existing unrelated Codex hooks.
IDEMPOTENCY_MARKER="$VIBE_LEARN_DIR/scripts/bootstrap.sh"

ensure_hooks_enabled() {
  # Ensure the canonical [features] hooks flag is true. codex_hooks is deprecated.
  if ! grep -q '^\[features\]' "$CONFIG_FILE"; then
    echo "" >> "$CONFIG_FILE"
    printf '[features]\nhooks = true\n' >> "$CONFIG_FILE"
  elif grep -q '^[[:space:]]*\(hooks\|codex_hooks\)[[:space:]]*=' "$CONFIG_FILE"; then
    TMP=$(mktemp)
    awk '
      /^\[features\]/ { in_features = 1; wrote_hooks = 0; print; next }
      /^\[/ {
        if (in_features && !wrote_hooks) {
          print "hooks = true"
        }
        in_features = 0
      }
      in_features && /^[[:space:]]*(hooks|codex_hooks)[[:space:]]*=/ {
        if (!wrote_hooks) {
          print "hooks = true"
          wrote_hooks = 1
        }
        next
      }
      { print }
      END {
        if (in_features && !wrote_hooks) {
          print "hooks = true"
        }
      }
    ' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
  else
    # [features] section exists but hooks not set — insert after the header.
    TMP=$(mktemp)
    awk '/^\[features\]/{print; print "hooks = true"; next}1' "$CONFIG_FILE" > "$TMP" && mv "$TMP" "$CONFIG_FILE"
  fi
}

if [ ! -f "$CONFIG_FILE" ]; then
  echo "$RENDERED_HOOKS" > "$CONFIG_FILE"
  if [ "$MODE" = "global" ]; then
    echo "✓ Created ~/.codex/config.toml with hooks"
  else
    echo "✓ Created .codex/config.toml with hooks"
  fi
else
  ensure_hooks_enabled

  if grep -qF "$IDEMPOTENCY_MARKER" "$CONFIG_FILE"; then
    if [ "$MODE" = "global" ]; then
      echo "✓ vibe-learn hooks already present in ~/.codex/config.toml — skipping."
    else
      echo "✓ vibe-learn hooks already present in .codex/config.toml — skipping."
    fi
  else
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
