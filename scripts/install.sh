#!/bin/bash
# install.sh — Wire vibe-learn into any project
# Run from the root of the project you want to install vibe-learn into:
#   bash /path/to/vibe-learn/scripts/install.sh [target-dir] [--assistant=<name>]
#
# Supported assistants: claude-code, codex
# Default: auto-detect based on .claude/ or .codex/ presence in target dir,
#          falling back to claude-code if neither is found.

set -euo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TARGET_DIR=""
ASSISTANT=""

for arg in "$@"; do
  case "$arg" in
    --assistant=*)
      ASSISTANT="${arg#--assistant=}"
      ;;
    --assistant)
      echo "ERROR: --assistant requires a value, e.g. --assistant=codex" >&2
      exit 1
      ;;
    -*)
      echo "ERROR: Unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$arg"
      fi
      ;;
  esac
done

TARGET_DIR="${TARGET_DIR:-$(pwd)}"

detect_assistant() {
  if [ -d "$TARGET_DIR/.claude" ]; then
    echo "claude-code"
  elif [ -d "$TARGET_DIR/.codex" ]; then
    echo "codex"
  else
    echo "claude-code"
  fi
}

if [ -z "$ASSISTANT" ]; then
  ASSISTANT="$(detect_assistant)"
fi

case "$ASSISTANT" in
  claude-code|codex)
    ;;
  *)
    echo "ERROR: Unknown assistant '$ASSISTANT'. Supported: claude-code, codex" >&2
    exit 1
    ;;
esac

echo "Installing vibe-learn into: $TARGET_DIR (assistant: $ASSISTANT)"

ADAPTER_SCRIPT="$VIBE_LEARN_DIR/adapters/$ASSISTANT/install.sh"
if [ ! -f "$ADAPTER_SCRIPT" ]; then
  echo "ERROR: Adapter not found: $ADAPTER_SCRIPT" >&2
  exit 1
fi

bash "$ADAPTER_SCRIPT" "$VIBE_LEARN_DIR" "$TARGET_DIR"

echo ""
if [ "$ASSISTANT" = "claude-code" ]; then
  echo "✅ vibe-learn installed. Open this project in Claude Code to activate."
  echo "   /learn                      — explain what just happened, or ask a specific question"
  echo "   /digest                     — full session learning report"
  echo ""
  echo "   Obsidian integration:"
  echo "   /learn obsidian             — save learn note to your Obsidian vault"
  echo "   /learn obsidian:recall      — search vault for past learnings on a topic"
  echo "   /digest obsidian            — save session digest to your Obsidian vault"
  echo "   /digest obsidian:recall     — digest enriched with connections to past sessions"
elif [ "$ASSISTANT" = "codex" ]; then
  echo "✅ vibe-learn installed. Open this project in Codex to activate."
  echo "   /prompts:learn              — explain what just happened, or ask a follow-up question"
  echo "   /prompts:digest             — full session learning report"
  echo ""
  echo "   Obsidian integration:"
  echo "   /prompts:learn then: obsidian             — save learn note to your Obsidian vault"
  echo "   /prompts:learn then: obsidian:recall      — search vault for past learnings"
  echo "   /prompts:digest then: obsidian            — save session digest to your Obsidian vault"
  echo "   /prompts:digest then: obsidian:recall     — digest enriched with past sessions"
fi
