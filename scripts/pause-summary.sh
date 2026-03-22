#!/bin/bash
# pause-summary.sh — Stop hook
# Generates a human-readable summary of what just happened this response,
# focused on decisions and changes — not just counts.
# Injects into Claude's context so it surfaces naturally in the next response.

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"

if [ ! -f "$SESSION_LOG" ] || [ ! -s "$SESSION_LOG" ]; then
  exit 0
fi

# --- Get the last user prompt (the intent behind this response) ---
LAST_PROMPT=$(jq -r 'select(.event=="user_prompt") | .prompt' "$SESSION_LOG" | tail -1 | head -c 200)

# --- Get tool_use events since the last user_prompt ---
# Find line number of last user_prompt, then take tool_use events after it
LAST_PROMPT_LINE=$(grep -n '"event":"user_prompt"' "$SESSION_LOG" | tail -1 | cut -d: -f1)
if [ -z "$LAST_PROMPT_LINE" ]; then
  LAST_PROMPT_LINE=0
fi

RECENT_ACTIONS=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r '
  select(.event=="tool_use") |
  if .tool == "Write" then
    "  ✦ Created \(.file // "file")"
  elif .tool == "Edit" or .tool == "MultiEdit" then
    "  ✦ Edited \(.file // "file")"
  elif .tool == "Bash" then
    if .context.exit_code != 0 then
      "  ✦ Ran: \(.command // "command") [failed ✗]"
    else
      "  ✦ Ran: \(.command // "command")"
    end
  else empty
  end
' 2>/dev/null)

# --- Count files and commands in this response ---
FILES_CREATED=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .tool=="Write")' | jq -s 'length' 2>/dev/null || echo 0)
FILES_MODIFIED=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and (.tool=="Edit" or .tool=="MultiEdit"))' | jq -s 'length' 2>/dev/null || echo 0)
BASH_TOTAL=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .tool=="Bash")' | jq -s 'length' 2>/dev/null || echo 0)
BASH_FAILURES=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .tool=="Bash" and .context.exit_code!=0)' | jq -s 'length' 2>/dev/null || echo 0)

# Nothing happened this response — skip
if [ "$FILES_CREATED" -eq 0 ] && [ "$FILES_MODIFIED" -eq 0 ] && [ "$BASH_TOTAL" -eq 0 ]; then
  exit 0
fi

# --- Build summary ---
SUMMARY="⏸ vibe-learn — what just happened:"

if [ -n "$LAST_PROMPT" ]; then
  SUMMARY+="
Goal: $LAST_PROMPT"
fi

if [ -n "$RECENT_ACTIONS" ]; then
  SUMMARY+="

$RECENT_ACTIONS"
fi

# Failures flag
if [ "$BASH_FAILURES" -gt 0 ]; then
  SUMMARY+="

⚠ $BASH_FAILURES command(s) failed — worth checking before continuing."
fi

SUMMARY+="

Use /learn to understand any of these decisions, or /digest for a full session report."

# Write to file — bootstrap.sh injects this into the next session via SessionStart
echo "$SUMMARY" > "$SUMMARY_FILE"
