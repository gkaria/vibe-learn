#!/bin/bash
# bootstrap.sh — SessionStart hook
# Initialises the .vibe-learn/ directory, rotates previous logs,
# and injects prior session context if available.

# Read stdin JSON
INPUT=$(cat)

# Extract cwd and session_id (jq required)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty' 2>/dev/null || true)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty' 2>/dev/null || true)

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
