#!/bin/bash
# pause-summary.sh — Stop hook
# Generates a human-readable summary of what just happened this response,
# focused on decisions and changes — not just counts.
# Injects into Claude's context so it surfaces naturally in the next response.

VIBE_LEARN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=identity.sh
if ! . "$VIBE_LEARN_DIR/scripts/identity.sh" 2>/dev/null; then
  # Installs that copy hook scripts one by one may lack the helper.
  VL_SEP=$'\x1f'
  vl_resolve_harness() { printf '%s' "${VIBE_LEARN_HARNESS:-${1:-unknown}}"; }
  vl_host_config() { :; }
  vl_harness_version() { :; }
fi

INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd // .workspaceRoot // empty')
if [ -z "$CWD" ] && [ -n "${GROK_HOOK_EVENT:-}" ]; then
  CWD="${GROK_WORKSPACE_ROOT:-${CLAUDE_PROJECT_DIR:-}}"
fi
HOOK_EVENT_NAME=$(echo "$INPUT" | jq -r '.hook_event_name // .hookEventName // empty')
REASON=$(echo "$INPUT" | jq -r '.reason // empty')

if [ -z "$CWD" ]; then
  exit 0
fi

# Grok fires an extra observe-only Stop at session end. Only summarise genuine turn ends.
if [ -n "$REASON" ] && [ "$REASON" != "end_turn" ]; then
  exit 0
fi

LOG_DIR="$CWD/.vibe-learn"
SESSION_LOG="$LOG_DIR/session-log.jsonl"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"

if [ ! -f "$SESSION_LOG" ] || [ ! -s "$SESSION_LOG" ]; then
  exit 0
fi

# --- Record the model and effort that answered this turn ---
# health.sh splits a session wherever these change mid-session.
META_FILE="$LOG_DIR/session-meta.json"
META=""
[ -f "$META_FILE" ] && META=$(jq -c 'objects' "$META_FILE" 2>/dev/null)
[ -n "$META" ] || META='{}'
IFS="$VL_SEP" read -r TURN P_HARNESS P_MODEL P_EFFORT P_TRANSCRIPT P_ROOT P_SESSION <<EOF
$(printf '%s' "$INPUT" | jq -r --arg sep "$VL_SEP" --argjson meta "$META" '
  def str: if type == "string" then . else "" end;
  [ ($meta.current_turn // 0 | tostring),
    ((.harness // $meta.harness) | str),
    ((.model_id // .model) | str),
    ((.effort | if type == "object" then .level else . end) | str),
    ((.transcript_path // .transcriptPath // $meta.transcript_path) | str),
    ((.workspaceRoot // .cwd) | str),
    ((.session_id // .sessionId // $meta.session_id) | str)
  ] | join($sep)' 2>/dev/null)
EOF
TURN_HARNESS=$(vl_resolve_harness "${P_HARNESS:-}" "${P_TRANSCRIPT:-}")
IFS="$VL_SEP" read -r H_MODEL H_EFFORT <<EOF
$(vl_host_config "$TURN_HARNESS" "${P_TRANSCRIPT:-}" "${P_ROOT:-$CWD}" "${P_SESSION:-}")
EOF
jq -cn \
  --arg ts "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
  --arg turn "${TURN:-0}" \
  --arg model "${H_MODEL:-${P_MODEL:-}}" \
  --arg effort "${H_EFFORT:-${P_EFFORT:-}}" '
  def nonempty: if . == "" then null else . end;
  {timestamp: $ts, event: "turn_end", turn: ($turn | tonumber? // 0),
   model: ($model | nonempty), effort: ($effort | nonempty)}' >> "$SESSION_LOG" 2>/dev/null || true

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
  if .action == "failed" then
    empty
  elif .tool == "Write" or .action == "created" then
    "  ✦ Created \(.file // "file")"
  elif .tool == "Edit" or .tool == "MultiEdit" or .action == "edited" then
    "  ✦ Edited \(.file // "file")"
  elif .action == "deleted" then
    "  ✦ Deleted \(.file // "file")"
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
FILES_CREATED=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .action != "failed" and (.tool=="Write" or .action=="created"))' | jq -s 'length' 2>/dev/null || echo 0)
FILES_MODIFIED=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .action != "failed" and (.tool=="Edit" or .tool=="MultiEdit" or .action=="edited"))' | jq -s 'length' 2>/dev/null || echo 0)
FILES_DELETED=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .action=="deleted")' | jq -s 'length' 2>/dev/null || echo 0)
BASH_TOTAL=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .tool=="Bash")' | jq -s 'length' 2>/dev/null || echo 0)
BASH_FAILURES=$(awk "NR > $LAST_PROMPT_LINE" "$SESSION_LOG" | jq -r 'select(.event=="tool_use" and .tool=="Bash" and .context.exit_code!=0)' | jq -s 'length' 2>/dev/null || echo 0)

# Nothing happened this response — skip
if [ "$FILES_CREATED" -eq 0 ] && [ "$FILES_MODIFIED" -eq 0 ] && [ "$FILES_DELETED" -eq 0 ] && [ "$BASH_TOTAL" -eq 0 ]; then
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

# Claude Code plugin installs namespace the commands under the plugin name.
if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then
  SUMMARY+="

 /vibe-learn:learn [question]  ·  /vibe-learn:digest  ·  /vibe-learn:quiz  ·  vibe-learn briefing"
else
  SUMMARY+="

 /learn [question]  ·  /digest  ·  /quiz  ·  vibe-learn briefing  ·  vibe-learn audio-prep"
fi

# Write to file — bootstrap.sh injects this into the next session via SessionStart
echo "$SUMMARY" > "$SUMMARY_FILE"

# Auto-generate dashboard in background — keeps the learning layer passive.
# Stdout is suppressed so hooks never see noise from dashboard generation.
bash "$VIBE_LEARN_DIR/scripts/briefing.sh" "$CWD" >/dev/null 2>&1 &

# Output JSON for host-specific Stop semantics.
# Grok treats additionalContext as a keep-working gate — write the file and emit nothing.
# Codex Stop expects {"continue":true}. Claude uses additionalContext.
if [ -n "${GROK_HOOK_EVENT:-}" ] || [ "$HOOK_EVENT_NAME" = "stop" ]; then
  exit 0
elif [ "$HOOK_EVENT_NAME" = "Stop" ]; then
  printf '{"continue":true}\n'
else
  printf '%s' "$SUMMARY" | jq -Rs '{"hookSpecificOutput": {"additionalContext": .}}'
fi
