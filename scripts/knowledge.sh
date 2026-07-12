#!/bin/bash
# knowledge.sh — read/write helper for the vibe-learn knowledge ledger
# (.vibe-learn/knowledge.json). Invoked by learning commands (/quiz, /learn,
# /digest) — never by hooks, so there is no hot-path latency budget.
#
# Usage:
#   knowledge.sh record <name> --label=<text> --status=<new|shaky|solid> [--notes=<text>] [--dir=<project>]
#   knowledge.sh touch  <name> --label=<text> [--dir=<project>]
#   knowledge.sh list   [--status=<s>] [--dir=<project>]
#   knowledge.sh due    [--days=14] [--dir=<project>]
#
# record — store a quiz result: sets status, stamps last_quizzed/last_seen,
#          and bumps sessions (at most once per day).
# touch  — mark a concept as seen this session: bumps last_seen (and sessions
#          once per day); never changes status or last_quizzed.
# list   — print the ledger as JSON ({"version":1,"concepts":[...]}), filtered
#          by --status when given. Missing file prints an empty ledger.
# due    — print a JSON array of concepts due for review: status "shaky", or
#          never quizzed and first seen N+ days ago, or last quizzed N+ days
#          ago (default 14).
#
# All writes merge by concept name and go through a temp file + mv so a
# failed jq run never corrupts the ledger.

set -euo pipefail

usage() {
  sed -n '2,20p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit 1
}

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found." >&2
  exit 1
fi

COMMAND="${1:-}"
[ -n "$COMMAND" ] || usage
shift

NAME=""
LABEL=""
STATUS=""
NOTES=""
DAYS=14
PROJECT_DIR="$(pwd)"

for arg in "$@"; do
  case "$arg" in
    --label=*)  LABEL="${arg#--label=}" ;;
    --status=*) STATUS="${arg#--status=}" ;;
    --notes=*)  NOTES="${arg#--notes=}" ;;
    --days=*)   DAYS="${arg#--days=}" ;;
    --dir=*)    PROJECT_DIR="${arg#--dir=}" ;;
    -*)
      echo "ERROR: Unknown flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$NAME" ]; then
        NAME="$arg"
      fi
      ;;
  esac
done

LEDGER_DIR="$PROJECT_DIR/.vibe-learn"
LEDGER="$LEDGER_DIR/knowledge.json"
TODAY="$(date +%Y-%m-%d)"
EMPTY_LEDGER='{"version":1,"concepts":[]}'

read_ledger() {
  if [ ! -f "$LEDGER" ]; then
    echo "$EMPTY_LEDGER"
    return
  fi
  if ! jq -e 'type == "object" and (.concepts | type == "array")' "$LEDGER" >/dev/null 2>&1; then
    echo "ERROR: $LEDGER is not a valid knowledge ledger. Fix or remove it — refusing to overwrite." >&2
    exit 1
  fi
  cat "$LEDGER"
}

write_ledger() {
  local content="$1"
  mkdir -p "$LEDGER_DIR"
  local tmp
  tmp="$(mktemp "$LEDGER_DIR/.knowledge.XXXXXX")"
  echo "$content" > "$tmp"
  mv "$tmp" "$LEDGER"
}

case "$COMMAND" in
  record)
    [ -n "$NAME" ] || { echo "ERROR: record requires a concept name." >&2; exit 1; }
    case "$STATUS" in
      new|shaky|solid) ;;
      *)
        echo "ERROR: record requires --status=new|shaky|solid (got '${STATUS}')." >&2
        exit 1
        ;;
    esac
    CURRENT="$(read_ledger)"
    UPDATED="$(echo "$CURRENT" | jq \
      --arg name "$NAME" --arg label "$LABEL" --arg status "$STATUS" \
      --arg notes "$NOTES" --arg today "$TODAY" '
      .concepts |=
        if any(.[]?; .name == $name) then
          map(if .name == $name then
            .label = (if $label != "" then $label else .label end)
            | .sessions = (if .last_seen == $today then .sessions else .sessions + 1 end)
            | .last_seen = $today
            | .last_quizzed = $today
            | .status = $status
            | .notes = (if $notes != "" then $notes else (.notes // "") end)
          else . end)
        else
          . + [{
            name: $name,
            label: (if $label != "" then $label else $name end),
            first_seen: $today,
            last_seen: $today,
            sessions: 1,
            last_quizzed: $today,
            status: $status,
            notes: $notes
          }]
        end')"
    write_ledger "$UPDATED"
    ;;

  touch)
    [ -n "$NAME" ] || { echo "ERROR: touch requires a concept name." >&2; exit 1; }
    CURRENT="$(read_ledger)"
    UPDATED="$(echo "$CURRENT" | jq \
      --arg name "$NAME" --arg label "$LABEL" --arg today "$TODAY" '
      .concepts |=
        if any(.[]?; .name == $name) then
          map(if .name == $name then
            .label = (if $label != "" then $label else .label end)
            | .sessions = (if .last_seen == $today then .sessions else .sessions + 1 end)
            | .last_seen = $today
          else . end)
        else
          . + [{
            name: $name,
            label: (if $label != "" then $label else $name end),
            first_seen: $today,
            last_seen: $today,
            sessions: 1,
            last_quizzed: null,
            status: "new",
            notes: ""
          }]
        end')"
    write_ledger "$UPDATED"
    ;;

  list)
    if [ -n "$STATUS" ]; then
      read_ledger | jq --arg status "$STATUS" '.concepts |= map(select(.status == $status))'
    else
      read_ledger
    fi
    ;;

  due)
    case "$DAYS" in
      ''|*[!0-9]*)
        echo "ERROR: --days must be a non-negative integer (got '${DAYS}')." >&2
        exit 1
        ;;
    esac
    # GNU date first, BSD/macOS date as fallback.
    CUTOFF="$(date -d "-${DAYS} days" +%Y-%m-%d 2>/dev/null || date -v "-${DAYS}d" +%Y-%m-%d)"
    read_ledger | jq --arg cutoff "$CUTOFF" '
      [.concepts[] | select(
        .status == "shaky"
        or ((.last_quizzed // "") == "" and .first_seen <= $cutoff)
        or ((.last_quizzed // "") != "" and .last_quizzed <= $cutoff)
      )]'
    ;;

  *)
    echo "ERROR: Unknown command '$COMMAND'." >&2
    usage
    ;;
esac
