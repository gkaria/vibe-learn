#!/bin/bash
# prototype/boundary/boundary.sh — PROTOTYPE of `vibe-learn boundary` (throwaway; lives
# on the prototype/boundary-report branch).
#
# What this session's tool calls reached for outside the code: hosts named or
# implied by commands and web/MCP tools, risky command shapes, sensitive and
# outside-the-project paths, and changes the prompt did not ask for, each tied
# to its turn and prompt. A record to learn from, never a guard: it reads what
# the assistant asked for, not what processes did, and it never blocks.
#
# Usage:
#   vibe-learn boundary [target-dir] [--json]
#   vibe-learn boundary --demo [--json]    run against a generated sample session
#
# Reads (read-only): .vibe-learn/session-log.jsonl, session-log.prev.jsonl
# (the "seen before" baseline), session-meta.json (for the host transcript),
# .vibe-learn/policy.json and ~/.vibe-learn/policy.json (allowed_hosts,
# protected_paths; lists are merged), and the origin remote's host.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VIBE_LEARN_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
TARGET_DIR=""
JSON=false
DEMO=false

for arg in "$@"; do
  case "$arg" in
    --json) JSON=true ;;
    --demo) DEMO=true ;;
    --help|-h) sed -n '2,19p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "ERROR: Unknown boundary flag: $arg" >&2; exit 1 ;;
    *) TARGET_DIR="$arg" ;;
  esac
done

if [ "$DEMO" = true ]; then
  TARGET_DIR="$(mktemp -d "${TMPDIR:-/tmp}/vibe-learn-boundary-demo.XXXXXX")/shop-api"
  BOUNDARY_SAMPLE_HOME="$HOME" bash "$SCRIPT_DIR/sample.sh" "$TARGET_DIR"
  echo "demo project: $TARGET_DIR" >&2
fi

ABS_DIR="$(CDPATH='' cd -- "${TARGET_DIR:-$(pwd)}" 2>/dev/null && pwd)" || { echo "ERROR: no such directory: $TARGET_DIR" >&2; exit 1; }
VL="$ABS_DIR/.vibe-learn"
if [ ! -s "$VL/session-log.jsonl" ]; then
  echo "No session log at $VL/session-log.jsonl yet. Try: vibe-learn boundary --demo" >&2
  exit 1
fi

META='{}'
[ -f "$VL/session-meta.json" ] && META="$(jq -c 'objects' "$VL/session-meta.json" 2>/dev/null || echo '{}')"
[ -n "$META" ] || META='{}'

# Host transcript: Claude Code's tool_use blocks only, in this prototype.
TX_STATUS=missing
TX_CALLS='null'
TX_PATH="$(printf '%s' "$META" | jq -r '.transcript_path // empty')"
HARNESS="$(printf '%s' "$META" | jq -r '.harness // empty')"
if [ -n "$TX_PATH" ] && [ -f "$TX_PATH" ]; then
  case "$HARNESS" in
    claude-code|'')
      TX_CALLS="$(jq -R -c '
        fromjson? | objects | select(.type == "assistant") | .timestamp as $ts
        | .message.content[]? | select(.type == "tool_use")
        | {ts: ($ts // ""), name, input: (.input | if type == "object" then {file_path, notebook_path, path, url, command} else {} end)}' "$TX_PATH" 2>/dev/null | jq -s -c '.')" \
        && TX_STATUS=read || TX_CALLS='null'
      ;;
    *) TX_STATUS=unsupported ;;
  esac
fi

POLICY_FILES=()
for f in "$HOME/.vibe-learn/policy.json" "$VL/policy.json"; do [ -f "$f" ] && POLICY_FILES+=("$f"); done
POLICY='{}'
if [ "${#POLICY_FILES[@]}" -gt 0 ]; then
  POLICY="$(jq -s -c '
    map(objects) | {allowed_hosts: (map(.allowed_hosts // empty | arrays) | if length == 0 then null else add | unique end),
                    protected_paths: (map(.protected_paths // [] | arrays) | add // [] | unique)}' \
    "${POLICY_FILES[@]}" 2>/dev/null || echo '{}')"
fi
[ -n "$POLICY" ] || POLICY='{}'

ORIGIN_HOST="$(git -C "$ABS_DIR" remote get-url origin 2>/dev/null \
  | sed -nE 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@]*@)?([^/:]+).*#\2#p; s#^[^/@:]+@([^:]+):.*#\1#p' | head -1 || true)"

read_log() { [ -f "$1" ] && cat "$1" || true; }

OUT="$(jq -n -r \
  -L "$SCRIPT_DIR" -L "$VIBE_LEARN_DIR/scripts/lib" \
  --rawfile log <(read_log "$VL/session-log.jsonl") \
  --rawfile base <(read_log "$VL/session-log.prev.jsonl") \
  --argjson tx "$TX_CALLS" --arg txstatus "$TX_STATUS" \
  --argjson meta "$META" --argjson policy "$POLICY" \
  --arg root "$ABS_DIR" --arg home "$HOME" --arg origin "$ORIGIN_HOST" \
  --arg project "$(basename "$ABS_DIR")" --argjson json "$JSON" \
  --arg learn "$( [ -n "${CLAUDE_PLUGIN_ROOT:-}" ] && echo /vibe-learn:learn || echo /learn )" '
  include "boundary";
  def events($raw): [$raw | splits("\n") | select(length > 0) | fromjson? | objects];
  boundary_facts(events($log); events($base); $tx; $txstatus; $meta; $policy; $root; $home;
                 (if $origin == "" then null else $origin end); $project)
  | if $json then tojson else render_text($learn) end')"

if [ "$JSON" = true ]; then
  printf '%s\n' "$OUT" | jq .
else
  printf '%s\n' "$OUT"
fi
