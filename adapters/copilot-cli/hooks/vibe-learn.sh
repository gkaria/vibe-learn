#!/bin/bash
# GitHub Copilot CLI payload shim. The installer supplies VIBE_LEARN_INSTALL_DIR.
set -uo pipefail

VIBE_LEARN_DIR="${VIBE_LEARN_INSTALL_DIR:-}"
[ -n "$VIBE_LEARN_DIR" ] || exit 0
SCRIPTS="$VIBE_LEARN_DIR/scripts"
INPUT=$(cat)
EVENT="${VIBE_LEARN_EVENT:-}"

# Copilot combines user and repository hooks. Let a project install own capture
# when both are present so each event reaches the core exactly once.
INPUT_CWD=$(jq -r 'select(type == "object") | .cwd // empty' <<<"$INPUT" 2>/dev/null || true)
if [ "${VIBE_LEARN_SCOPE:-}" = "global" ] && [ -n "$INPUT_CWD" ] \
  && grep -q 'vibe-learn.sh' "$INPUT_CWD/.github/hooks/vibe-learn.json" 2>/dev/null; then
  exit 0
fi

session_is_current() {
  local cwd="$1" session_id="$2" meta="$1/.vibe-learn/session-meta.json"
  [ -f "$meta" ] && [ "$(jq -r '.session_id // empty' "$meta" 2>/dev/null)" = "$session_id" ]
}

case "$EVENT" in
  sessionStart)
    PAYLOAD=$(jq -ce 'select(type == "object" and ((.cwd // "") | length > 0)) | {cwd, session_id: (.sessionId // "unknown"), timestamp, source, initial_prompt: (.initialPrompt // null)}' <<<"$INPUT" 2>/dev/null) || exit 0
    CWD=$(jq -r '.cwd' <<<"$PAYLOAD")
    SESSION_ID=$(jq -r '.session_id' <<<"$PAYLOAD")
    if ! session_is_current "$CWD" "$SESSION_ID"; then
      printf '%s\n' "$PAYLOAD" | bash "$SCRIPTS/bootstrap.sh" >/dev/null 2>&1 || true
    fi
    SUMMARY="$CWD/.vibe-learn/pause-summary.txt"
    if [ -f "$SUMMARY" ]; then
      { printf 'Prior session summary:\n'; tr '\n' ' ' < "$SUMMARY"; } | jq -Rsc '{additionalContext: .}'
    fi
    ;;

  userPromptSubmitted)
    PAYLOAD=$(jq -ce 'select(type == "object" and ((.cwd // "") | length > 0)) | {cwd, session_id: (.sessionId // "unknown"), timestamp, prompt: (.prompt // "")}' <<<"$INPUT" 2>/dev/null) || exit 0
    CWD=$(jq -r '.cwd' <<<"$PAYLOAD")
    SESSION_ID=$(jq -r '.session_id' <<<"$PAYLOAD")
    if ! session_is_current "$CWD" "$SESSION_ID"; then
      printf '%s\n' "$PAYLOAD" | bash "$SCRIPTS/bootstrap.sh" >/dev/null 2>&1 || true
    fi
    printf '%s\n' "$PAYLOAD" | bash "$SCRIPTS/capture-prompt.sh" >/dev/null 2>&1 || true
    ;;

  postToolUse|postToolUseFailure)
    PAYLOAD=$(jq -ce --arg event "$EVENT" '
      def rawargs: (.toolArgs // {});
      def args: rawargs | if type == "string" then (fromjson? // {}) else . end;
      def result: (.toolResult // {});
      def exit_code:
        if $event == "postToolUseFailure" then 1
        elif (result | type) == "object" and (result.exitCode // result.exit_code) != null then
          (result.exitCode // result.exit_code)
        # Copilot has no structured process exit field in some successful envelopes.
        # The host completion marker is the narrowest available fallback; identical
        # marker text printed by the command remains inherently ambiguous.
        elif (result | type) == "object" and (result.textResultForLlm | type) == "string" then
          ([result.textResultForLlm | capture("(?i)<shellId:[^>\\n]* completed with exit code (?<code>[0-9]+)>").code | tonumber] | .[0] // 0)
        else 0 end;
      select(type == "object" and ((.cwd // "") | length > 0)) |
      (.toolName // "") as $native |
      (if ($native == "bash" or $native == "powershell") then "Bash"
       elif $native == "create" then "Write"
       elif ($native == "edit" or $native == "str_replace_editor") then "Edit"
       elif $native == "apply_patch" then "apply_patch"
       else empty end) as $tool |
      {
        cwd,
        session_id: (.sessionId // "unknown"),
        timestamp,
        hook_event_name: (if $event == "postToolUseFailure" then "PostToolUseFailure" else "PostToolUse" end),
        tool_name: $tool,
        tool_input: (
          if $tool == "Bash" then {command: (args.command // args.cmd // "")}
          elif $tool == "apply_patch" then {patch: (if (rawargs | type) == "string" then rawargs else (args.patch // args.command // "") end)}
          else {file_path: (args.path // args.filePath // args.file_path // "")}
          end
        ),
        tool_response: {exit_code: exit_code}
      }' <<<"$INPUT" 2>/dev/null) || exit 0
    printf '%s\n' "$PAYLOAD" | bash "$SCRIPTS/observe.sh" >/dev/null 2>&1 || true
    ;;

  agentStop)
    CWD=$(jq -er 'select(type == "object") | .cwd // empty' <<<"$INPUT" 2>/dev/null) || exit 0
    jq -c 'select(type == "object") | {cwd, session_id: (.sessionId // "unknown"), timestamp, hook_event_name: "stop", reason: (.stopReason // "end_turn")}' <<<"$INPUT" 2>/dev/null \
      | bash "$SCRIPTS/pause-summary.sh" >/dev/null 2>&1 || true
    SUMMARY="$CWD/.vibe-learn/pause-summary.txt"
    if [ -f "$SUMMARY" ]; then
      TMP="$SUMMARY.tmp"
      awk '/^ \/learn / { print " Use /learn [question]  ·  Use /digest  ·  Use /quiz  ·  Use /explain [file|topic]  ·  vibe-learn briefing  ·  vibe-learn audio-prep"; next } { print }' "$SUMMARY" > "$TMP" \
        && mv "$TMP" "$SUMMARY" || rm -f "$TMP"
    fi
    ;;
esac

exit 0
