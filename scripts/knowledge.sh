#!/bin/bash
# knowledge.sh — read/write helper for the vibe-learn knowledge ledger
# (.vibe-learn/knowledge.json). Invoked by learning commands (/quiz, /learn,
# /digest) — never by hooks, so there is no hot-path latency budget.
#
# Usage:
#   knowledge.sh record <name> --label=<text> --status=<new|shaky|solid> [--notes=<text>] [--files=<a,b>] [--dir=<project>]
#   knowledge.sh touch  <name> --label=<text> [--files=<a,b>] [--dir=<project>]
#   knowledge.sh forget <name> [--dir=<project>]
#   knowledge.sh list   [--status=<s>] [--dir=<project>]
#   knowledge.sh due    [--days=14] [--dir=<project>]
#
# record — store a quiz result: sets status, stamps last_seen, and bumps
#          sessions (at most once per day). solid and shaky stamp last_quizzed;
#          new does not. Without --notes, solid clears the old note and shaky
#          keeps it.
# touch  — mark a concept as seen this session: bumps last_seen (and sessions
#          once per day); never changes status or last_quizzed.
# forget — remove a concept. Exits 0 whether or not it was there, and says which.
# list   — print the ledger as JSON ({"version":1,"concepts":[...]}), filtered
#          by --status when given. Missing file prints an empty ledger.
# due    — print a JSON array of concepts due for review: status "shaky", or
#          never quizzed and first seen N+ days ago, or last quizzed N+ days
#          ago (default 14).
#
# --files  comma-separated project files the concept lives in; record and
#          touch add them to the concept's optional `files` list, relative to
#          the project, so the briefing can link concepts to files. Paths must
#          stay inside the project: relative, or absolute under it, no `..`.
#
# Names are lowercase letters, digits, and dashes (jwt-refresh-tokens), not
# starting with a dash. forget accepts any name, so entries written before
# this rule can still be removed.
#
# All writes merge by concept name and go through a temp file + mv so a
# failed jq run never corrupts the ledger.

set -euo pipefail

usage() {
  sed -n '2,33p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
  exit "${1:-1}"
}

if ! command -v jq &>/dev/null; then
  echo "ERROR: jq is required but not found." >&2
  exit 1
fi

COMMAND="${1:-}"
[ -n "$COMMAND" ] || usage
shift
case "$COMMAND" in help|--help|-h) usage 0 ;; esac

NAME=""
LABEL=""
STATUS=""
NOTES=""
FILES=""
DAYS=14
PROJECT_DIR="$(pwd)"

for arg in "$@"; do
  case "$arg" in
    --label=*)  LABEL="${arg#--label=}" ;;
    --status=*) STATUS="${arg#--status=}" ;;
    --notes=*)  NOTES="${arg#--notes=}" ;;
    --files=*)  FILES="${arg#--files=}" ;;
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

if [ ! -d "$PROJECT_DIR" ]; then
  echo "ERROR: no such project directory: $PROJECT_DIR" >&2
  exit 1
fi
LEDGER_DIR="$PROJECT_DIR/.vibe-learn"
LEDGER="$LEDGER_DIR/knowledge.json"
TODAY="$(date +%Y-%m-%d)"

# record and touch create names; keep them to one safe shape. The class is
# spelled out because [a-z] can match capitals in some locales.
if [ "$COMMAND" = record ] || [ "$COMMAND" = touch ]; then
  case "$NAME" in
    '') ;;  # reported by the command below
    -*|*[!abcdefghijklmnopqrstuvwxyz0123456789-]*)
      echo "ERROR: concept names use lowercase letters, digits, and dashes, e.g. jwt-refresh-tokens (got '${NAME}')." >&2
      exit 1
      ;;
  esac
fi

# --files as a JSON array of project-relative paths, for add_files below. An
# absolute path under the project (as given or with symlinks resolved) is made
# relative; anything that would point outside it is refused.
ROOT="$(CDPATH='' cd -- "$PROJECT_DIR" && pwd)"
ROOT_P="$(CDPATH='' cd -- "$PROJECT_DIR" && pwd -P)"
FILES_JSON="$(jq -cn --arg files "$FILES" --arg root "$ROOT" --arg root_p "$ROOT_P" '
  [$files | split(",")[] | sub("^\\s+"; "") | sub("\\s+$"; "")
   | if startswith($root + "/") then .[($root | length) + 1:]
     elif startswith($root_p + "/") then .[($root_p | length) + 1:]
     else ltrimstr("./") end
   | select(. != "")] | unique')"
BAD_FILE="$(printf '%s' "$FILES_JSON" | jq -r '
  [.[] | select(startswith("/") or startswith("~") or any(split("/")[]; . == "..")
                or any(explode[]; . < 32))] | first // empty')"
if [ -n "$BAD_FILE" ]; then
  echo "ERROR: --files paths must be inside the project, relative to it, with no '..' (got '${BAD_FILE}')." >&2
  exit 1
fi
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

# A concept's files only grow; one without --files keeps the shape it had.
ADD_FILES='def add_files: if $files == [] then . else .files = ((.files // []) + $files | unique) end;'

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
      --arg name "$NAME" --arg concept_label "$LABEL" --arg status "$STATUS" \
      --arg notes "$NOTES" --arg today "$TODAY" --argjson files "$FILES_JSON" "$ADD_FILES"'
      # new is not a quiz result: it never stamps last_quizzed.
      def quizzed($old): if $status == "new" then $old else $today end;
      .concepts |=
        if any(.[]?; .name == $name) then
          map(if .name == $name then
            .label = (if $concept_label != "" then $concept_label else .label end)
            | .sessions = (if .last_seen == $today then .sessions else .sessions + 1 end)
            | .last_seen = $today
            | .last_quizzed = quizzed(.last_quizzed // null)
            | .status = $status
            | .notes = (if $notes != "" or $status == "solid" then $notes else (.notes // "") end)
            | add_files
          else . end)
        else
          . + [{
            name: $name,
            label: (if $concept_label != "" then $concept_label else $name end),
            first_seen: $today,
            last_seen: $today,
            sessions: 1,
            last_quizzed: quizzed(null),
            status: $status,
            notes: $notes
          } | add_files]
        end')"
    write_ledger "$UPDATED"
    ;;

  touch)
    [ -n "$NAME" ] || { echo "ERROR: touch requires a concept name." >&2; exit 1; }
    CURRENT="$(read_ledger)"
    UPDATED="$(echo "$CURRENT" | jq \
      --arg name "$NAME" --arg concept_label "$LABEL" --arg today "$TODAY" --argjson files "$FILES_JSON" "$ADD_FILES"'
      .concepts |=
        if any(.[]?; .name == $name) then
          map(if .name == $name then
            .label = (if $concept_label != "" then $concept_label else .label end)
            | .sessions = (if .last_seen == $today then .sessions else .sessions + 1 end)
            | .last_seen = $today
            | add_files
          else . end)
        else
          . + [{
            name: $name,
            label: (if $concept_label != "" then $concept_label else $name end),
            first_seen: $today,
            last_seen: $today,
            sessions: 1,
            last_quizzed: null,
            status: "new",
            notes: ""
          } | add_files]
        end')"
    write_ledger "$UPDATED"
    ;;

  forget)
    [ -n "$NAME" ] || { echo "ERROR: forget requires a concept name." >&2; exit 1; }
    CURRENT="$(read_ledger)"
    if printf '%s' "$CURRENT" | jq -e --arg name "$NAME" 'any(.concepts[]; .name == $name)' >/dev/null; then
      write_ledger "$(printf '%s' "$CURRENT" | jq --arg name "$NAME" '.concepts |= map(select(.name != $name))')"
      echo "Forgot '$NAME'."
    else
      echo "'$NAME' is not in the ledger; nothing to forget."
    fi
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
