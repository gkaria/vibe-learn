#!/bin/bash
set -euo pipefail
# observe.sh — PostToolUse hook (sync)
# Appends a JSONL entry for every Write/Edit/MultiEdit/Bash tool use.
# MUST complete in <50ms. No network calls. No stdout output.

# Read stdin JSON
INPUT=$(cat)

# Extract fields
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
TOOL=$(echo "$INPUT" | jq -r '.tool_name // empty')

if [ -z "$CWD" ] || [ -z "$TOOL" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
META_FILE="$LOG_DIR/session-meta.json"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Get current timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Build JSONL entry based on tool type
case "$TOOL" in
  Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ENTRY=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg file "$FILE" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"created",context:{new_file:true}}')
    ;;
  Edit|MultiEdit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ENTRY=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg file "$FILE" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"edited",context:{}}')
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    EXIT_CODE=$(echo "$INPUT" | jq -r '.tool_response.exit_code // 0')
    # Truncate command to 200 chars to keep log compact
    CMD="${CMD:0:200}"
    ENTRY=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg cmd "$CMD" \
      --argjson exit_code "${EXIT_CODE:-0}" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,command:$cmd,action:"ran",context:{exit_code:$exit_code}}')
    ;;
  *)
    exit 0
    ;;
esac

# Append to session log
echo "$ENTRY" >> "$SESSION_LOG"

# Increment event_count in session-meta.json (atomic: write to tmp then mv)
if [ -f "$META_FILE" ]; then
  CURRENT=$(jq '.event_count // 0' "$META_FILE")
  NEW_COUNT=$((CURRENT + 1))
  TMP_FILE="$META_FILE.tmp"
  jq --argjson count "$NEW_COUNT" '.event_count = $count' "$META_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$META_FILE"
fi

exit 0
