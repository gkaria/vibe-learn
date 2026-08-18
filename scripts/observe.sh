#!/bin/bash
set -euo pipefail
# observe.sh — PostToolUse hook (sync)
# Appends JSONL entries for Write/Edit/MultiEdit/Bash/apply_patch tool use.
# MUST complete in <50ms. No network calls. No stdout output.

# Read stdin JSON
INPUT=$(cat)

# Extract fields. Accept Claude snake_case and Grok camelCase envelopes.
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspaceRoot // empty')
if [ -z "$CWD" ] && [ -n "${GROK_HOOK_EVENT:-}" ]; then
  CWD="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
fi
TOOL=$(echo "$INPUT" | jq -r '.tool_name // .toolName // empty')

if [ -z "$CWD" ] || [ -z "$TOOL" ]; then
  exit 0
fi

# Canonicalize Grok tool names onto the existing session-log vocabulary.
case "$TOOL" in
  write) TOOL=Write ;;
  search_replace) TOOL=Edit ;;
  run_terminal_command) TOOL=Bash ;;
esac

HOOK_EVENT=$(echo "$INPUT" | jq -r '.hook_event_name // .hookEventName // empty')
FAILED=0
case "$HOOK_EVENT" in
  PostToolUseFailure|post_tool_use_failure) FAILED=1 ;;
esac

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
META_FILE="$LOG_DIR/session-meta.json"

# Ensure log directory exists
mkdir -p "$LOG_DIR"

# Get current timestamp
TS=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Read current turn — defaults to 1 when no meta exists yet.
# Use a string arg + in-jq cast so stray whitespace never breaks --argjson.
CURRENT_TURN="1"
if [ -f "$META_FILE" ]; then
  _t="$(jq -r '.current_turn // 0' "$META_FILE" 2>/dev/null || true)"
  # Arithmetic strip: coerce to integer, fall back to 1 if not positive
  _t=$(( ${_t:-0} + 0 )) 2>/dev/null || _t=0
  [ "$_t" -gt 0 ] && CURRENT_TURN="$_t"
fi

# Build JSONL entries based on tool type
ENTRIES=""
EVENT_COUNT=1

case "$TOOL" in
  Write)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .toolInput.file_path // .tool_input.path // .toolInput.path // empty')
    if [ "$FAILED" -eq 1 ]; then
      ENTRIES=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg file "$FILE" \
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"failed",turn:($turn|tonumber? // 1),context:{failed:true}}')
    else
      ENTRIES=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg file "$FILE" \
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"created",turn:($turn|tonumber? // 1),context:{new_file:true}}')
    fi
    ;;
  Edit|MultiEdit)
    FILE=$(echo "$INPUT" | jq -r '.tool_input.file_path // .toolInput.file_path // .tool_input.path // .toolInput.path // empty')
    if [ "$FAILED" -eq 1 ]; then
      ENTRIES=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg file "$FILE" \
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"failed",turn:($turn|tonumber? // 1),context:{failed:true}}')
    else
      ENTRIES=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg file "$FILE" \
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:"edited",turn:($turn|tonumber? // 1),context:{}}')
    fi
    ;;
  Bash)
    CMD=$(echo "$INPUT" | jq -r '.tool_input.command // .toolInput.command // empty')
    EXIT_CODE=$(echo "$INPUT" | jq -r '
      (.tool_response // .toolResult) as $r |
      if ($r | type) == "object" then
        ($r.exit_code // $r.exitCode // empty)
      else
        empty
      end
    ')
    if [ -z "$EXIT_CODE" ]; then
      if [ "$FAILED" -eq 1 ]; then
        EXIT_CODE=1
      else
        EXIT_CODE=0
      fi
    fi
    # Truncate command to 200 chars to keep log compact
    CMD="${CMD:0:200}"
    ENTRIES=$(jq -cn \
      --arg ts "$TS" \
      --arg tool "$TOOL" \
      --arg cmd "$CMD" \
      --argjson exit_code "${EXIT_CODE:-0}" \
      --arg turn "$CURRENT_TURN" \
      '{timestamp:$ts,event:"tool_use",tool:$tool,command:$cmd,action:"ran",turn:($turn|tonumber? // 1),context:{exit_code:$exit_code}}')
    ;;
  apply_patch)
    if [ "$FAILED" -eq 1 ]; then
      ENTRIES=$(jq -cn \
        --arg ts "$TS" \
        --arg tool "$TOOL" \
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,action:"failed",turn:($turn|tonumber? // 1),context:{failed:true}}')
    else
    PATCH=$(echo "$INPUT" | jq -r '.tool_input.command // .toolInput.command // .tool_input.patch // .toolInput.patch // empty')
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
        --arg turn "$CURRENT_TURN" \
        '{timestamp:$ts,event:"tool_use",tool:$tool,file:$file,action:$action,turn:($turn|tonumber? // 1),context:(if $action == "created" then {new_file:true} else {} end)}')

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
    fi
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
