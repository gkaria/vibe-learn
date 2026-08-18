#!/bin/bash
# bootstrap.sh — SessionStart hook
# Initialises the .vibe-learn/ directory, rotates previous logs,
# and injects prior session context if available.

# Read stdin JSON
INPUT=$(cat)

# Extract cwd and session_id (jq required). Accept Claude snake_case and Grok camelCase.
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspaceRoot // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // .sessionId // empty' 2>/dev/null || true)
# Grok hook-runner env only — GROK_SESSION_ID can leak into agent shells.
if [ -n "${GROK_HOOK_EVENT:-}" ]; then
  if [ -z "$CWD" ]; then
    CWD="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
  fi
  if [ -z "$SESSION_ID" ]; then
    SESSION_ID="${GROK_SESSION_ID:-}"
  fi
fi

# Fall back gracefully if cwd is missing
if [ -z "$CWD" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
PREV_LOG="$LOG_DIR/session-log.prev.jsonl"
META_FILE="$LOG_DIR/session-meta.json"
PAUSE_SUMMARY="$LOG_DIR/pause-summary.txt"

# Create the .vibe-learn directory
mkdir -p "$LOG_DIR"

# Rotate previous session log (keep one backup)
if [ -f "$SESSION_LOG" ]; then
  mv "$SESSION_LOG" "$PREV_LOG"
fi

# Get current timestamp (ISO 8601)
STARTED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Write fresh session metadata
cat > "$META_FILE" <<EOF
{
  "session_id": "${SESSION_ID:-unknown}",
  "started_at": "$STARTED_AT",
  "event_count": 0,
  "current_turn": 0,
  "config": {
    "log_dir": ".vibe-learn"
  }
}
EOF

# If a prior pause summary exists, inject it as context for Claude
if [ -f "$PAUSE_SUMMARY" ]; then
  SUMMARY_CONTENT=$(cat "$PAUSE_SUMMARY")
  printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"Prior session summary:\\n%s"}}\n' \
    "$(echo "$SUMMARY_CONTENT" | sed 's/"/\\"/g' | tr '\n' ' ')"
else
  exit 0
fi
