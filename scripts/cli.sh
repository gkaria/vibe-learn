#!/bin/bash
# cli.sh — vibe-learn command dispatcher

set -euo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
vibe-learn — learn from agent-built coding sessions

Usage:
  vibe-learn install    [target-dir] [--assistant=claude-code|codex|opencode|all]
  vibe-learn briefing   [target-dir] [--latest]
  vibe-learn audio-prep [target-dir]
  vibe-learn help
EOF
}

COMMAND="${1:-help}"

case "$COMMAND" in
  install)
    shift
    exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    ;;
  briefing)
    shift
    exec "$VIBE_LEARN_DIR/scripts/briefing.sh" "$@"
    ;;
  audio-prep)
    shift
    exec "$VIBE_LEARN_DIR/scripts/audio-prep.sh" "$@"
    ;;
  help|--help|-h)
    usage
    ;;
  --assistant=*|--assistant)
    # Backward compatibility with the old shim, where vibe-learn arguments went
    # directly to install.sh.
    exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    ;;
  *)
    if [ -d "$COMMAND" ]; then
      exec "$VIBE_LEARN_DIR/scripts/install.sh" "$@"
    fi
    echo "ERROR: Unknown command '$COMMAND'." >&2
    echo "" >&2
    usage >&2
    exit 1
    ;;
esac
