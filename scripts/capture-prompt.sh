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
META_FILE="$LOG_DIR/session-meta.json"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Truncate prompt to 500 chars
PROMPT="${PROMPT:0:500}"

# Get current timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Increment turn counter — each user prompt starts a new turn
CURRENT_TURN=0
if [ -f "$META_FILE" ]; then
  CURRENT_TURN="$(jq -r '.current_turn // 0' "$META_FILE" 2>/dev/null || echo 0)"
fi
NEW_TURN=$((CURRENT_TURN + 1))

# Build and append JSONL entry with turn number
ENTRY=$(jq -cn \
  --arg ts "$TS" \
  --arg prompt "$PROMPT" \
  --arg turn "$NEW_TURN" \
  '{timestamp:$ts,event:"user_prompt",prompt:$prompt,turn:($turn|tonumber? // 1)}')

echo "$ENTRY" >> "$SESSION_LOG"

# Persist the new turn counter
if [ -f "$META_FILE" ]; then
  TMP_FILE="$META_FILE.tmp"
  jq --argjson turn "$NEW_TURN" '.current_turn = $turn' "$META_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$META_FILE"
fi

exit 0
