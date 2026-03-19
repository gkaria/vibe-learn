#!/bin/bash
# pause-summary.sh — Stop hook
# Generates a mechanical summary of the session so far.
# Writes to .vibe-learn/pause-summary.txt and injects it into Claude's context.

# Read stdin JSON
INPUT=$(cat)

CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"

# Nothing to summarise if log is missing or empty
if [ ! -f "$SESSION_LOG" ] || [ ! -s "$SESSION_LOG" ]; then
  exit 0
fi

# --- Compute stats using jq ---

TOTAL_EVENTS=$(wc -l < "$SESSION_LOG" | tr -d ' ')

FILES_CREATED=$(jq -r 'select(.event=="tool_use" and .tool=="Write" and .context.new_file==true)' "$SESSION_LOG" | jq -s 'length')

FILES_MODIFIED=$(jq -r 'select(.event=="tool_use" and (.tool=="Edit" or .tool=="MultiEdit"))' "$SESSION_LOG" | jq -s 'length')

BASH_TOTAL=$(jq -r 'select(.event=="tool_use" and .tool=="Bash")' "$SESSION_LOG" | jq -s 'length')

BASH_FAILURES=$(jq -r 'select(.event=="tool_use" and .tool=="Bash" and .context.exit_code!=0)' "$SESSION_LOG" | jq -s 'length')

# Last 5 tool actions (skip user_prompt events)
LAST_5=$(jq -r 'select(.event=="tool_use") | if .tool == "Bash" then "  ran: \(.command // "bash command")" else "  \(.tool | ascii_downcase): \(.file // "unknown")" end' "$SESSION_LOG" | tail -5)

# Get timestamp from meta if available
META_FILE="$LOG_DIR/session-meta.json"
STARTED_AT=""
if [ -f "$META_FILE" ]; then
  STARTED_AT=$(jq -r '.started_at // empty' "$META_FILE")
fi

# --- Build the summary ---

SUMMARY="⏸️  vibe-learn Pause Summary
"

if [ -n "$STARTED_AT" ]; then
  SUMMARY+="Session started: $STARTED_AT
"
fi

SUMMARY+="
Events logged:    $TOTAL_EVENTS
Files created:    $FILES_CREATED
Files modified:   $FILES_MODIFIED
Bash commands:    $BASH_TOTAL"

if [ "$BASH_FAILURES" -gt 0 ]; then
  SUMMARY+=" ($BASH_FAILURES failed)"
fi

SUMMARY+="

Last 5 actions:
$LAST_5

Full log: $LOG_DIR/session-log.jsonl"

# Write to file
echo "$SUMMARY" > "$SUMMARY_FILE"

# Inject into Claude's context via hookSpecificOutput
ESCAPED=$(echo "$SUMMARY" | sed 's/"/\\"/g' | sed 's/$/\\n/' | tr -d '\n')
printf '{"hookSpecificOutput":{"additionalContext":"%s"}}\n' "$ESCAPED"
