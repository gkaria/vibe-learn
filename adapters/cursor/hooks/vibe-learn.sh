#!/bin/bash
# vibe-learn.sh — Cursor hooks shim.
#
# Cursor calls one command per hook event with its own payload shape. This
# script reads that payload, translates it into the Claude-style envelope the
# core vibe-learn scripts accept, runs the matching script, and answers in the
# shape Cursor expects for that event. Installed by adapters/cursor/install.sh,
# which replaces VIBE_LEARN_DIR_PLACEHOLDER with the real install directory.
#
# Event map (Cursor hook name -> core script):
#   sessionStart        -> scripts/bootstrap.sh       (additional_context relayed)
#   beforeSubmitPrompt  -> scripts/capture-prompt.sh  (always {"continue":true})
#   afterFileEdit       -> scripts/observe.sh         (Write when the edit creates the file, else Edit)
#   postToolUse         -> scripts/observe.sh         (Shell -> Bash with exit code)
#   postToolUseFailure  -> scripts/observe.sh         (Shell -> Bash, action "ran", exit code 1)
#   stop                -> scripts/pause-summary.sh   (file only; never a followup_message)
#
# The project root is workspace_roots[0]; `cwd` is only a fallback because
# Cursor omits it on several events and it may point below the root.

set -uo pipefail

VIBE_LEARN_DIR="VIBE_LEARN_DIR_PLACEHOLDER"
SCRIPTS="$VIBE_LEARN_DIR/scripts"

INPUT=$(cat)
EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty' 2>/dev/null || true)
CWD=$(printf '%s' "$INPUT" | jq -r '.workspace_roots[0] // .cwd // empty' 2>/dev/null || true)
[ -n "$CWD" ] || exit 0

case "$EVENT" in
  sessionStart)
    OUT=$(printf '%s' "$INPUT" \
      | jq -c --arg cwd "$CWD" '{cwd: $cwd, session_id: (.session_id // .conversation_id // "unknown")}' \
      | bash "$SCRIPTS/bootstrap.sh" 2>/dev/null || true)
    if [ -n "$OUT" ]; then
      printf '%s' "$OUT" \
        | jq -c '{additional_context: .hookSpecificOutput.additionalContext} | select(.additional_context != null)' 2>/dev/null || true
    fi
    ;;

  beforeSubmitPrompt)
    printf '%s' "$INPUT" \
      | jq -c --arg cwd "$CWD" '{cwd: $cwd, prompt: (.prompt // "")}' \
      | bash "$SCRIPTS/capture-prompt.sh" >/dev/null 2>&1 || true
    printf '{"continue":true}\n'
    ;;

  afterFileEdit)
    printf '%s' "$INPUT" | jq -c --arg cwd "$CWD" '
      {
        cwd: $cwd,
        hook_event_name: "PostToolUse",
        tool_name: (if ((.edits // []) | length) == 1 and ((.edits[0].old_string // "") == "") then "Write" else "Edit" end),
        tool_input: {file_path: (.file_path // "")},
        tool_response: {}
      } | select(.tool_input.file_path != "")' \
      | bash "$SCRIPTS/observe.sh" >/dev/null 2>&1 || true
    ;;

  postToolUse|postToolUseFailure)
    # File edits arrive via afterFileEdit; here only shell commands matter.
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)
    [ "$TOOL" = "Shell" ] || exit 0
    if [ "$EVENT" = "postToolUse" ]; then
      # tool_output is documented as a JSON string ({"exitCode":0,...}); accept an object too.
      printf '%s' "$INPUT" | jq -c --arg cwd "$CWD" '
        {
          cwd: $cwd,
          hook_event_name: "PostToolUse",
          tool_name: "Bash",
          tool_input: {command: (.tool_input.command // "")},
          tool_response: {
            exit_code: (
              (.tool_output // {})
              | (if type == "string" then (fromjson? // {}) else . end)
              | (if type == "object" then (.exitCode // .exit_code // 0) else 0 end)
            )
          }
        }' | bash "$SCRIPTS/observe.sh" >/dev/null 2>&1 || true
    else
      printf '%s' "$INPUT" | jq -c --arg cwd "$CWD" '
        {
          cwd: $cwd,
          hook_event_name: "PostToolUseFailure",
          tool_name: "Bash",
          tool_input: {command: (.tool_input.command // "")},
          tool_response: {}
        }' | bash "$SCRIPTS/observe.sh" >/dev/null 2>&1 || true
    fi
    ;;

  stop)
    # pause-summary.sh writes .vibe-learn/pause-summary.txt and prints nothing for a
    # lowercase "stop" event. Never print a followup_message: Cursor would auto-submit it.
    printf '%s' "$INPUT" \
      | jq -c --arg cwd "$CWD" '{cwd: $cwd, hook_event_name: "stop"}' \
      | bash "$SCRIPTS/pause-summary.sh" >/dev/null 2>&1 || true
    ;;
esac

exit 0
