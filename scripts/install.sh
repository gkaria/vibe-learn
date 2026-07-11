#!/bin/bash
# install.sh — Wire vibe-learn into any project
# Run from the root of the project you want to install vibe-learn into:
#   bash /path/to/vibe-learn/scripts/install.sh [target-dir] [--assistant=<name>]
#
# Supported assistants: claude-code, codex, opencode, all
# Default: install all relevant assistants detected for the project or machine,
#          falling back to claude-code if no assistant can be detected.

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

detect_assistants() {
  local detected=()

  if [ -d "$TARGET_DIR/.claude" ]; then
    detected+=("claude-code")
  fi
  if [ -d "$TARGET_DIR/.codex" ]; then
    detected+=("codex")
  fi
  if [ -d "$TARGET_DIR/.opencode" ]; then
    detected+=("opencode")
  fi

  if [ ${#detected[@]} -eq 0 ]; then
    if command -v claude &>/dev/null || [ -d "$HOME/.claude" ]; then
      detected+=("claude-code")
    fi
    if command -v codex &>/dev/null || [ -d "$HOME/.codex" ]; then
      detected+=("codex")
    fi
    if command -v opencode &>/dev/null || [ -d "$HOME/.config/opencode" ]; then
      detected+=("opencode")
    fi
  fi

  if [ ${#detected[@]} -eq 0 ]; then
    detected+=("claude-code")
  fi

  echo "${detected[@]}"
}

assistant_list_contains() {
  local needle="$1"
  shift
  local assistant
  for assistant in "$@"; do
    if [ "$assistant" = "$needle" ]; then
      return 0
    fi
  done
  return 1
}

join_assistants() {
  local result=""
  local assistant
  for assistant in "$@"; do
    if [ -z "$result" ]; then
      result="$assistant"
    else
      result="$result, $assistant"
    fi
  done
  echo "$result"
}

if [ -z "$ASSISTANT" ] || [ "$ASSISTANT" = "all" ]; then
  read -ra ASSISTANTS_TO_INSTALL <<< "$(detect_assistants)"
else
  case "$ASSISTANT" in
    claude-code|codex|opencode)
      ASSISTANTS_TO_INSTALL=("$ASSISTANT")
      ;;
    *)
      echo "ERROR: Unknown assistant '$ASSISTANT'. Supported: claude-code, codex, opencode, all" >&2
      exit 1
      ;;
  esac
fi

ASSISTANT_SUMMARY="$(join_assistants "${ASSISTANTS_TO_INSTALL[@]}")"
echo "Installing vibe-learn into: $TARGET_DIR (assistants: $ASSISTANT_SUMMARY)"

for ASSISTANT_TO_INSTALL in "${ASSISTANTS_TO_INSTALL[@]}"; do
  ADAPTER_SCRIPT="$VIBE_LEARN_DIR/adapters/$ASSISTANT_TO_INSTALL/install.sh"
  if [ ! -f "$ADAPTER_SCRIPT" ]; then
    echo "ERROR: Adapter not found: $ADAPTER_SCRIPT" >&2
    exit 1
  fi

  echo "Configuring $ASSISTANT_TO_INSTALL..."
  bash "$ADAPTER_SCRIPT" "$VIBE_LEARN_DIR" "$TARGET_DIR"
done

echo ""
echo "✅ vibe-learn installed. Open this project in your assistant to activate."

if assistant_list_contains "claude-code" "${ASSISTANTS_TO_INSTALL[@]}"; then
  echo ""
  echo "Claude Code:"
  echo "   /learn                      — explain what just happened, or ask a specific question"
  echo "   /digest                     — full session learning report"
  echo "   /quiz                       — check your understanding; /quiz review for concepts due again"
  echo "   /learn obsidian             — save learn note to your Obsidian vault"
  echo "   /learn obsidian:recall      — search vault for past learnings on a topic"
  echo "   /digest obsidian            — save session digest to your Obsidian vault"
  echo "   /digest obsidian:recall     — digest enriched with connections to past sessions"
fi

if assistant_list_contains "codex" "${ASSISTANTS_TO_INSTALL[@]}"; then
  echo ""
  echo "Codex:"
  echo "   Use the global skill when installed: \"Use vibe-learn to learn what happened.\" or \"Use vibe-learn to quiz me.\""
  echo "   Prompt fallback: \"Read .codex/prompts/learn.md and follow it.\" or /prompts:learn"
  echo "   Digest fallback: \"Read .codex/prompts/digest.md and follow it.\" or /prompts:digest"
  echo "   Quiz fallback:   \"Read .codex/prompts/quiz.md and follow it.\" or /prompts:quiz"
  echo "   Obsidian: ask vibe-learn to save or recall learn/digest notes, or use the prompt fallback with obsidian / obsidian:recall."
fi

if assistant_list_contains "opencode" "${ASSISTANTS_TO_INSTALL[@]}"; then
  echo ""
  echo "OpenCode:"
  echo "   /learn                      — explain what just happened, or ask a specific question"
  echo "   /digest                     — full session learning report"
  echo "   /quiz                       — check your understanding; /quiz review for concepts due again"
  echo "   vibe-learn briefing  — interactive maintainer briefing and NotebookLM source pack"
fi
