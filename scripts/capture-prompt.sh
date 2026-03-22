#!/bin/bash
set -euo pipefail
# capture-prompt.sh — UserPromptSubmit hook
# Logs the user's prompt to the session log so we have intent context.
# Must exit quickly — do not block the prompt.

# Read stdin JSON
INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
PROMPT=$(echo "$INPUT" | jq -r '.prompt // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Truncate prompt to 500 chars
PROMPT="${PROMPT:0:500}"

# Get current timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build and append JSONL entry
ENTRY=$(jq -cn \
  --arg ts "$TS" \
  --arg prompt "$PROMPT" \
  '{timestamp:$ts,event:"user_prompt",prompt:$prompt}')

echo "$ENTRY" >> "$SESSION_LOG"

exit 0
