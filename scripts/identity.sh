#!/bin/bash
# identity.sh — sourced by bootstrap.sh, pause-summary.sh, and health.sh.
# Works out which assistant ran a session and which model, effort, and version
# it used. Claude Code and Codex transcripts and Grok's summary.json are
# undocumented, so every read here prints "" on any failure instead of erroring.

# Fields are joined with the ASCII unit separator: tab is IFS whitespace, so
# `read` would collapse an empty field into its neighbour.
VL_SEP=$'\x1f'

# vl_resolve_harness PAYLOAD_HARNESS TRANSCRIPT_PATH
vl_resolve_harness() {
  if [ -n "${VIBE_LEARN_HARNESS:-}" ]; then
    printf '%s' "$VIBE_LEARN_HARNESS"
  elif [ -n "$1" ] && [ "$1" != "unknown" ]; then
    printf '%s' "$1"
  elif [ -n "${GROK_HOOK_EVENT:-}" ]; then
    printf 'grok'
  else
    case "$2" in
      "${CODEX_HOME:-$HOME/.codex}"/*|*/.codex/*) printf 'codex' ;;
      "${CLAUDE_CONFIG_DIR:-$HOME/.claude}"/*|*/.claude/*) printf 'claude-code' ;;
      *) if [ -n "${CLAUDE_PLUGIN_ROOT:-}" ]; then printf 'claude-code'; else printf 'unknown'; fi ;;
    esac
  fi
}

# vl_host_config HARNESS TRANSCRIPT_PATH WORKSPACE_ROOT SESSION_ID
# Prints "model<SEP>effort" read from the host's own files; either may be empty.
vl_host_config() {
  local harness="$1" transcript="$2" root="$3" sid="$4"
  case "$harness" in
    claude-code)
      [ -f "$transcript" ] || return 0
      grep -F '"type":"assistant"' "$transcript" 2>/dev/null | tail -n 5 \
        | jq -Rrn --arg sep "$VL_SEP" \
          '[inputs | fromjson? | select(.type == "assistant") | .message.model | strings] | (last // "") + $sep' 2>/dev/null
      ;;
    codex)
      [ -f "$transcript" ] || return 0
      grep -F '"type":"turn_context"' "$transcript" 2>/dev/null | tail -n 1 \
        | jq -Rrn --arg sep "$VL_SEP" \
          '[inputs | fromjson? | select(.type == "turn_context") | .payload] | last // {}
           | ((.model | strings) // "") + $sep + ((.effort | strings) // "")' 2>/dev/null
      ;;
    grok)
      [ -n "$root" ] && [ -n "$sid" ] || return 0
      local dir summary
      dir=$(printf '%s' "$root" | jq -Rr '@uri' 2>/dev/null) || return 0
      summary="${GROK_HOME:-$HOME/.grok}/sessions/$dir/$sid/summary.json"
      [ -f "$summary" ] || return 0
      jq -r --arg sep "$VL_SEP" \
        '((.current_model_id | strings) // "") + $sep + ((.reasoning_effort | strings) // "")' \
        "$summary" 2>/dev/null
      ;;
  esac
}

# vl_harness_version HARNESS TRANSCRIPT_PATH
vl_harness_version() {
  local harness="$1" transcript="$2"
  case "$harness" in
    claude-code)
      [ -f "$transcript" ] || return 0
      tail -n 50 "$transcript" 2>/dev/null \
        | jq -Rrn '[inputs | fromjson? | .version | strings] | last // ""' 2>/dev/null
      ;;
    codex)
      [ -f "$transcript" ] || return 0
      head -n 1 "$transcript" 2>/dev/null \
        | jq -Rrn '[inputs | fromjson? | .payload.cli_version | strings] | last // ""' 2>/dev/null
      ;;
    grok)
      command -v grok >/dev/null 2>&1 || return 0
      grok --version 2>/dev/null | awk 'NR == 1 && $1 == "grok" { print $2 }'
      ;;
  esac
}
