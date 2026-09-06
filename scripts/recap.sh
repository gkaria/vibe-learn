#!/bin/bash
# recap.sh — "What I learned this week": a shareable markdown rollup built from
# the knowledge ledger, recent session logs, and saved digests.
#
# Usage:
#   vibe-learn recap [target-dir] [--days=7] [--save]
#
# Reads (all optional; missing inputs simply leave their section out):
#   .vibe-learn/knowledge.json            concepts quizzed / seen in the window
#   .vibe-learn/session-log.jsonl         current session activity
#   .vibe-learn/session-log.prev.jsonl    previous session activity
#   .vibe-learn/digests/*.md              digests saved by /digest
#
# Prints markdown to stdout. With --save, also writes
# .vibe-learn/recaps/<end-date>-recap.md and prints its path on stderr.
# Read-only with respect to the ledger: recap never writes knowledge.json.

set -euo pipefail

TARGET_DIR=""
DAYS=7
SAVE=false

for arg in "$@"; do
  case "$arg" in
    --days=*) DAYS="${arg#--days=}" ;;
    --save) SAVE=true ;;
    --help|-h)
      sed -n '2,16p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown recap flag: $arg" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$arg"
      else
        echo "ERROR: recap accepts at most one target directory." >&2
        exit 1
      fi
      ;;
  esac
done

case "$DAYS" in
  ''|*[!0-9]*|0)
    echo "ERROR: --days must be a positive integer (got '${DAYS}')." >&2
    exit 1
    ;;
esac

TARGET_DIR="${TARGET_DIR:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"
LOG_DIR="$TARGET_DIR/.vibe-learn"
LEDGER="$LOG_DIR/knowledge.json"
DIGESTS_DIR="$LOG_DIR/digests"
PROJECT_NAME="$(basename "$TARGET_DIR")"

TODAY="$(date +%Y-%m-%d)"
# GNU date first, BSD/macOS date as fallback. Window is the last DAYS days inclusive of today.
CUTOFF="$(date -d "-$((DAYS - 1)) days" +%Y-%m-%d 2>/dev/null || date -v "-$((DAYS - 1))d" +%Y-%m-%d)"

# --- Ledger ---
LEDGER_JSON='{"version":1,"concepts":[]}'
if [ -f "$LEDGER" ]; then
  if jq -e 'type == "object" and (.concepts | type == "array")' "$LEDGER" >/dev/null 2>&1; then
    LEDGER_JSON="$(cat "$LEDGER")"
  else
    echo "WARN: $LEDGER is not a valid knowledge ledger — recap ignores it." >&2
  fi
fi

ledger_lines() {
  # $1: jq select expression, $2: line template
  printf '%s' "$LEDGER_JSON" | jq -r --arg cutoff "$CUTOFF" "
    [.concepts[] | select($1)]
    | sort_by(.last_quizzed // .last_seen // \"\") | reverse
    | .[] | $2"
}

SOLID="$(ledger_lines '.status == "solid" and ((.last_quizzed // "") >= $cutoff)' \
  '"- \(.label // .name) — quizzed \(.last_quizzed)"')"
SHAKY="$(ledger_lines '.status == "shaky" and ((.last_quizzed // "") >= $cutoff)' \
  '"- \(.label // .name) — quizzed \(.last_quizzed)" + (if (.notes // "") != "" then ": \(.notes)" else "" end)')"
CARRIED="$(ledger_lines '.status == "shaky" and ((.last_quizzed // "") < $cutoff)' \
  '"- \(.label // .name) — still shaky since \(.last_quizzed // "?")"')"
MET="$(ledger_lines '.status == "new" and ((.last_seen // "") >= $cutoff)' \
  '"- \(.label // .name) — seen in \(.sessions // 1) session(s), not quizzed yet"')"

count_lines() { printf '%s\n' "$1" | sed '/^$/d' | wc -l | tr -d ' '; }
SOLID_COUNT="$(count_lines "$SOLID")"
SHAKY_COUNT="$(count_lines "$SHAKY")"
CARRIED_COUNT="$(count_lines "$CARRIED")"
MET_COUNT="$(count_lines "$MET")"
QUIZ_DAYS="$(printf '%s' "$LEDGER_JSON" | jq -r --arg cutoff "$CUTOFF" \
  '[.concepts[] | .last_quizzed // empty | select(. >= $cutoff)] | unique | length')"
LEDGER_TOTAL="$(printf '%s' "$LEDGER_JSON" | jq -r '.concepts | length')"

# --- Session activity in the window (current + previous log) ---
ACTIVITY_JSON="$(
  for f in "$LOG_DIR/session-log.jsonl" "$LOG_DIR/session-log.prev.jsonl"; do
    [ -s "$f" ] && cat "$f" || true
  done | jq -s --arg cutoff "$CUTOFF" '
    [.[] | select((.timestamp // "")[0:10] >= $cutoff)] as $ev
    | {
        days:     ([$ev[] | .timestamp[0:10]] | unique | length),
        prompts:  ([$ev[] | select(.event == "user_prompt")] | length),
        files:    ([$ev[] | select(.event == "tool_use" and .action != "failed" and (.file // "") != "") | .file] | unique | length),
        commands: ([$ev[] | select(.event == "tool_use" and .tool == "Bash")] | length)
      }' 2>/dev/null || echo '{"days":0,"prompts":0,"files":0,"commands":0}'
)"
ACTIVE_DAYS="$(printf '%s' "$ACTIVITY_JSON" | jq -r '.days')"
PROMPTS="$(printf '%s' "$ACTIVITY_JSON" | jq -r '.prompts')"
FILES="$(printf '%s' "$ACTIVITY_JSON" | jq -r '.files')"
COMMANDS="$(printf '%s' "$ACTIVITY_JSON" | jq -r '.commands')"

# --- Digests saved in the window ---
DIGEST_LINES=""
if [ -d "$DIGESTS_DIR" ]; then
  while IFS= read -r file; do
    [ -z "$file" ] && continue
    base="$(basename "$file")"
    fdate="$(printf '%s' "$base" | grep -oE '^[0-9]{4}-[0-9]{2}-[0-9]{2}' || true)"
    [ -z "$fdate" ] && fdate="$(date -r "$file" +%Y-%m-%d 2>/dev/null || echo "$TODAY")"
    [ "$fdate" \< "$CUTOFF" ] && continue
    built="$(awk '/^##+ *What Was Built/{flag=1; next} flag && /^##/{exit} flag && NF{print; exit}' "$file" | head -c 200)"
    if [ -n "$built" ]; then
      DIGEST_LINES+="- $fdate — $built"$'\n'
    else
      DIGEST_LINES+="- $fdate — $base"$'\n'
    fi
  done < <(find "$DIGESTS_DIR" -maxdepth 1 -type f -name '*.md' | sort)
fi

# --- Assemble ---
OUT="# What I learned this week — $PROJECT_NAME"$'\n'
OUT+="$CUTOFF → $TODAY"$'\n\n'

if [ "$LEDGER_TOTAL" -eq 0 ] && [ "$ACTIVE_DAYS" -eq 0 ] && [ -z "$DIGEST_LINES" ]; then
  OUT+="Nothing recorded yet. Work a session with vibe-learn installed, then run /quiz — results land in .vibe-learn/knowledge.json and show up here."$'\n'
else
  OUT+="**$ACTIVE_DAYS active day(s) · $PROMPTS prompt(s) · $FILES file(s) touched · $COMMANDS command(s) run · quizzed on $QUIZ_DAYS day(s)**"$'\n\n'

  if [ "$SOLID_COUNT" -gt 0 ]; then
    OUT+="## Confirmed solid ($SOLID_COUNT)"$'\n\n'"$SOLID"$'\n\n'
  fi
  if [ "$SHAKY_COUNT" -gt 0 ]; then
    OUT+="## Still shaky — revisit ($SHAKY_COUNT)"$'\n\n'"$SHAKY"$'\n\n'
  fi
  if [ "$CARRIED_COUNT" -gt 0 ]; then
    OUT+="## Carried over from earlier ($CARRIED_COUNT)"$'\n\n'"$CARRIED"$'\n\n'
  fi
  if [ "$MET_COUNT" -gt 0 ]; then
    OUT+="## Met this week, not quizzed yet ($MET_COUNT)"$'\n\n'"$MET"$'\n\n'
  fi
  if [ "$SOLID_COUNT" -eq 0 ] && [ "$SHAKY_COUNT" -eq 0 ] && [ "$MET_COUNT" -eq 0 ] && [ "$CARRIED_COUNT" -eq 0 ]; then
    OUT+="## Knowledge ledger"$'\n\n'"No concepts were quizzed or introduced this week. Run /quiz after your next session."$'\n\n'
  fi
  if [ -n "$DIGEST_LINES" ]; then
    OUT+="## From the digests"$'\n\n'"${DIGEST_LINES%$'\n'}"$'\n\n'
  fi

  NEXT=""
  if [ "$SHAKY_COUNT" -gt 0 ] || [ "$CARRIED_COUNT" -gt 0 ]; then
    NEXT="/quiz review — re-ask the shaky ones until they stick."
  elif [ "$MET_COUNT" -gt 0 ]; then
    NEXT="/quiz — turn the concepts you met this week into ones you can explain."
  else
    NEXT="/digest at the end of your next session, then /quiz."
  fi
  OUT+="## Next"$'\n\n'"$NEXT"$'\n\n'
fi

OUT+="---"$'\n'"*Generated by [vibe-learn](https://github.com/gkaria/vibe-learn) — learn as your AI coding assistant builds.*"

printf '%s\n' "$OUT"

if [ "$SAVE" = true ]; then
  mkdir -p "$LOG_DIR/recaps"
  RECAP_FILE="$LOG_DIR/recaps/$TODAY-recap.md"
  printf '%s\n' "$OUT" > "$RECAP_FILE"
  echo "Saved recap: $RECAP_FILE" >&2
fi
