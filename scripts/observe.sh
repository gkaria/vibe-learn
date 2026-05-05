#!/bin/bash
set -euo pipefail
# observe.sh — PostToolUse hook (sync)
# Appends JSONL entries for Write/Edit/MultiEdit/Bash/apply_patch tool use.
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

# Build JSONL entries based on tool type
ENTRIES=""
EVENT_COUNT=1

case "$TOOL" in
  Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ENTRIES=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg file "$FILE" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"created",context:{new_file:true}}')
    ;;
  Edit|MultiEdit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')
    ENTRIES=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg file "$FILE" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"edited",context:{}}')
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
    EXIT_CODE=$(echo "$INPUT" | jq -r '
      if (.tool_response | type) == "object" then
        (.tool_response.exit_code // .tool_response.exitCode // 0)
      else
        0
      end
    ')
    # Truncate command to 200 chars to keep log compact
    CMD="${CMD:0:200}"
    ENTRIES=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg cmd "$CMD" \
      --argjson exit_code "${EXIT_CODE:-0}" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,command:$cmd,action:"ran",context:{exit_code:$exit_code}}')
    ;;
  apply_patch)
    PATCH=$(echo "$INPUT" | jq -r '.tool_input.command // .tool_input.patch // empty')
    PATCH_SUMMARY=$(printf '%s\n' "$PATCH" | awk '
      /^\*\*\* Add File: / {
        file = $0
        sub(/^\*\*\* Add File: /, "", file)
        print "created\t" file
      }
      /^\*\*\* Update File: / {
        file = $0
        sub(/^\*\*\* Update File: /, "", file)
        print "edited\t" file
      }
      /^\*\*\* Delete File: / {
        file = $0
        sub(/^\*\*\* Delete File: /, "", file)
        print "deleted\t" file
      }
    ')

    if [ -z "$PATCH_SUMMARY" ]; then
      exit 0
    fi

    EVENT_COUNT=0
    while IFS="$(printf '\t')" read -r ACTION FILE; do
      if [ -z "${ACTION:-}" ] || [ -z "${FILE:-}" ]; then
        continue
      fi

      ENTRY=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg file "$FILE" \
        --arg action "$ACTION" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:$action,context:(if $action == "created" then {new_file:true} else {} end)}')

      if [ -z "$ENTRIES" ]; then
        ENTRIES="$ENTRY"
      else
        ENTRIES="$ENTRIES
$ENTRY"
      fi
      EVENT_COUNT=$((EVENT_COUNT + 1))
    done <<EOF
$PATCH_SUMMARY
EOF
    ;;
  *)
    exit 0
    ;;
esac

# Append to session log
printf '%s\n' "$ENTRIES" >> "$SESSION_LOG"

# Increment event_count in session-meta.json (atomic: write to tmp then mv)
if [ -f "$META_FILE" ]; then
  CURRENT=$(jq '.event_count // 0' "$META_FILE")
  NEW_COUNT=$((CURRENT + EVENT_COUNT))
  TMP_FILE="$META_FILE.tmp"
  jq --argjson count "$NEW_COUNT" '.event_count = $count' "$META_FILE" > "$TMP_FILE" && mv "$TMP_FILE" "$META_FILE"
fi

exit 0
