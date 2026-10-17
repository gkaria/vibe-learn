#!/bin/bash
# cli.sh — vibe-learn command dispatcher

set -euo pipefail

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
  cat <<EOF
vibe-learn — learn from agent-built coding sessions

Usage:
  vibe-learn install    [target-dir] [--assistant=claude-code|copilot-cli|codex|opencode|grok|cursor|all] [--create]
  vibe-learn briefing   [target-dir] [--latest] [--if-stale] [--json [--session <id>]]
  vibe-learn recap      [target-dir] [--days=7] [--save]
  vibe-learn health     [target-dir] [--days=14|all] [--by=harness|model] [--all] [--json] [--save] [--redact]
  vibe-learn audio-prep [target-dir]
  vibe-learn doctor     [target-dir]
  vibe-learn knowledge  forget <name> | list [--status=<s>] | due [--days=14]  [--dir=<project>]
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
  recap)
    shift
    exec "$VIBE_LEARN_DIR/scripts/recap.sh" "$@"
    ;;
  health)
    shift
    exec "$VIBE_LEARN_DIR/scripts/health-report.sh" "$@"
    ;;
  audio-prep)
    shift
    exec "$VIBE_LEARN_DIR/scripts/audio-prep.sh" "$@"
    ;;
  doctor)
    shift
    exec "$VIBE_LEARN_DIR/scripts/doctor.sh" "$@"
    ;;
  knowledge)
    shift
    exec "$VIBE_LEARN_DIR/scripts/knowledge.sh" "$@"
    ;;
  dashboard)
    echo "ERROR: 'vibe-learn dashboard' is now 'vibe-learn briefing'" >&2
    exit 1
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
