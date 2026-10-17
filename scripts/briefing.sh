#!/bin/bash
# briefing.sh — Generate static vibe-learn session briefing artifacts.

set -euo pipefail

TARGET_DIR=""
LATEST=false
IF_STALE=false
JSON=false
SESSION_ID_ARG=""

usage() {
  cat <<USAGE
Usage:
  vibe-learn briefing [target-dir] [--latest] [--if-stale] [--json] [--session <id>]

Generates .vibe-learn/briefing/index.html plus a session page and
NotebookLM-ready source pack for the current session log.

  --latest        the index shows only this session, skipping previously
                  generated session cards
  --if-stale      do nothing when the session's work and knowledge.json are
                  unchanged since its last complete build (what /learn and
                  /digest run)
  --json          print the session's facts (schema_version 1, see
                  docs/briefing.md) instead of the file paths; always
                  rebuilds first, and prints status messages to stderr
  --session <id>  with --json: print a session already built, by session id
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --latest) LATEST=true ;;
    --if-stale) IF_STALE=true ;;
    --json) JSON=true ;;
    --session=*) SESSION_ID_ARG="${1#--session=}" ;;
    --session)
      [ $# -ge 2 ] || { echo "ERROR: --session needs a session id." >&2; exit 1; }
      SESSION_ID_ARG="$2"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    -*)
      echo "ERROR: Unknown briefing flag: $1" >&2
      exit 1
      ;;
    *)
      if [ -z "$TARGET_DIR" ]; then
        TARGET_DIR="$1"
      else
        echo "ERROR: briefing accepts at most one target directory." >&2
        exit 1
      fi
      ;;
  esac
  shift
done
if [ -n "$SESSION_ID_ARG" ] && [ "$JSON" = false ]; then
  echo "ERROR: --session works with --json." >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Page templates and their jq renderers sit in lib/ beside this script, or
# beside it in installs that copy every file into one directory (techpack).
template() {
  if [ -f "$SCRIPT_DIR/lib/$1" ]; then echo "$SCRIPT_DIR/lib/$1"
  elif [ -f "$SCRIPT_DIR/$1" ]; then echo "$SCRIPT_DIR/$1"
  else echo "$SCRIPT_DIR/lib/$1"; fi
}
BRIEFING_FILES="briefing.jq pack.jq briefing-session.html briefing-index.html briefing-health.html"
for f in $BRIEFING_FILES; do
  if [ ! -f "$(template "$f")" ]; then
    echo "ERROR: $f is missing from $SCRIPT_DIR/lib; reinstall vibe-learn." >&2
    exit 1
  fi
done

TARGET_DIR="${TARGET_DIR:-$(pwd)}"
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

LOG_DIR="$TARGET_DIR/.vibe-learn"
SUMMARY_FILE="$LOG_DIR/pause-summary.txt"
SUMMARY_OWNER_FILE="$LOG_DIR/pause-summary.session"
LEDGER_FILE="$LOG_DIR/knowledge.json"
BRIEFING_DIR="$LOG_DIR/briefing"
SESSIONS_DIR="$BRIEFING_DIR/sessions"
EXPORTS_DIR="$BRIEFING_DIR/exports"
INDEX_FILE="$BRIEFING_DIR/index.html"
STAMPS_DIR="$BRIEFING_DIR/.stamps"

if [ -n "$SESSION_ID_ARG" ]; then
  for f in "$SESSIONS_DIR"/*.json; do
    [ -f "$f" ] || continue
    if jq -e --arg id "$SESSION_ID_ARG" '.session_id == $id' "$f" >/dev/null 2>&1; then
      jq . "$f"
      exit 0
    fi
  done
  echo "ERROR: no briefing for session $SESSION_ID_ARG in $SESSIONS_DIR; run vibe-learn briefing during that session." >&2
  exit 1
fi

# --json: stdout carries only the facts; everything else goes to stderr. Like
# --if-stale, an empty log prints nothing and writes no placeholder.
if [ "$JSON" = true ]; then
  exec 3>&1 1>&2
  IF_STALE=true
fi
print_json() { [ "$JSON" = true ] && jq . "$JSON_FILE" >&3; return 0; }
# Nothing to brief: fine for a page, a failure when the facts were asked for.
nothing_to_brief() {
  [ "$JSON" = true ] && exit 1
  exit 0
}

PROJECT_NAME="$(basename "$TARGET_DIR")"
PROJECT_HTML="$(printf '%s' "$PROJECT_NAME" | jq -Rr @html)"
NOW_DATE="$(date -u +"%Y-%m-%d")"
NOW_TS="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

slugify() {
  printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g; s/-\{2,\}/-/g; s/^-//; s/-$//'
}

# Sets SESSION_ID, STARTED_AT, SESSION_DATE, SESSION_SLUG and the output paths
# from a session-meta.json. A rebuild of the same session overwrites the same
# files.
derive_session() {
  local meta="$1" token
  SESSION_ID="unknown"
  STARTED_AT=""
  if [ -f "$meta" ]; then
    SESSION_ID="$(jq -r '.session_id // "unknown" | tostring' "$meta" 2>/dev/null | head -n 1 || true)"
    STARTED_AT="$(jq -r '.started_at // empty | tostring' "$meta" 2>/dev/null | head -n 1 || true)"
  fi
  SESSION_ID="${SESSION_ID:-unknown}"
  case "$STARTED_AT" in
    [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]*) ;;
    *) STARTED_AT="" ;;
  esac
  SESSION_DATE="$NOW_DATE"
  token="$(date -u +"%H%M%S")"
  if [ -n "$STARTED_AT" ]; then
    SESSION_DATE="$(printf '%s' "$STARTED_AT" | cut -c1-10)"
    token="$(printf '%s' "$STARTED_AT" | sed 's/[^0-9]//g' | cut -c9-14)"
  fi
  if [ "$SESSION_ID" != "unknown" ]; then
    token="$(slugify "$SESSION_ID")"
    # An id with no slug-safe characters still needs a distinct name.
    [ -n "$token" ] || token="$(printf '%s' "$SESSION_ID" | cksum | cut -d ' ' -f 1)"
  fi
  SESSION_SLUG="$(slugify "$SESSION_DATE-$PROJECT_NAME-$token")"
  SESSION_FILE="$SESSIONS_DIR/$SESSION_SLUG.html"
  JSON_FILE="$SESSIONS_DIR/$SESSION_SLUG.json"
  PACK_FILE="$EXPORTS_DIR/$SESSION_SLUG-notebooklm-pack.md"
  STAMP_FILE="$STAMPS_DIR/$SESSION_SLUG"
}

# What a page shows depends on the session's work (learning turns and
# turn_end lines left out, so /learn itself never makes the page stale), the
# ledger, this script, and its templates. A complete build records this as its
# stamp.
work_fingerprint() {
  {
    jq -Rnc -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "session";
      [inputs | fromjson? | objects] | number_turns | work_events[]
      | select(.event != "turn_end") | del(._turn)' "$1" 2>/dev/null || true
    echo "--"
    cat "$LEDGER_FILE" 2>/dev/null || true
    echo "--"
    cat "${BASH_SOURCE[0]}"
    for f in session.jq $BRIEFING_FILES; do cat "$(template "$f")"; done
  } | cksum
}

if [ "$IF_STALE" = true ]; then
  # An empty log has nothing to brief; a placeholder would replace the index.
  if [ ! -s "$LOG_DIR/session-log.jsonl" ]; then
    echo "No session activity to brief yet."
    nothing_to_brief
  fi
  derive_session "$LOG_DIR/session-meta.json"
  # --json always rebuilds: the stamp leaves learning turns out, the facts do not.
  if [ "$JSON" = false ] && [ -f "$SESSION_FILE" ] && [ -f "$JSON_FILE" ] \
    && [ "$(cat "$STAMP_FILE" 2>/dev/null)" = "$(work_fingerprint "$LOG_DIR/session-log.jsonl")" ]; then
    echo "Session briefing is up to date: $SESSION_FILE"
    print_json
    exit 0
  fi
fi


mkdir -p "$SESSIONS_DIR" "$EXPORTS_DIR" "$STAMPS_DIR"
# Private scratch space for the session copy and the outputs, which are
# renamed into place, so a killed run never leaves a half-written page.
WORK="$(mktemp -d "$BRIEFING_DIR/.work.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' INT TERM HUP

# Build from one copy of the live log and its meta, so a rotation during the
# run cannot pair one session's log with another's meta or rename the page.
# If the session id changed while copying, a rotation happened: copy again.
session_id_of() { jq -r '.session_id // empty' "$1" 2>/dev/null | head -n 1 || true; }
copy_session() {
  rm -f "$WORK/session-meta.json" "$WORK/session-log.jsonl"
  cp "$LOG_DIR/session-meta.json" "$WORK/session-meta.json" 2>/dev/null || true
  cp "$LOG_DIR/session-log.jsonl" "$WORK/session-log.jsonl" 2>/dev/null || true
}
copy_session
[ "$(session_id_of "$WORK/session-meta.json")" = "$(session_id_of "$LOG_DIR/session-meta.json")" ] || copy_session

SESSION_LOG="$WORK/session-log.jsonl"
META_FILE="$WORK/session-meta.json"
derive_session "$META_FILE"

write_empty_briefing() {
  local message="No vibe-learn session log was found for $PROJECT_HTML."
  # A briefing index from earlier sessions is worth more than a placeholder.
  if [ -f "$INDEX_FILE" ]; then
    echo "No session log found; kept the existing briefing index: $INDEX_FILE"
    return
  fi
  cat > "$WORK/index.html" <<EMPTY_EOF
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>vibe-learn — $PROJECT_HTML</title>
  <style>
    :root{--bg:#faf9f5;--surface:#f1efe7;--text:#141413;--muted:#706f68;--line:#d8d4c8;--accent:#d97757;--radius:8px;color-scheme:light dark;}
    @media (prefers-color-scheme: dark){:root{--bg:#1c1b19;--surface:#262522;--text:#ece9e1;--muted:#a8a498;--line:#413e38;}}
    *{box-sizing:border-box;}
    body{margin:0;background:var(--bg);color:var(--text);font:16px/1.6 Lora,Georgia,serif;}
    main{max-width:600px;margin:80px auto;padding:0 24px;}
    h1{font:700 32px/1.1 Poppins,Arial,sans-serif;margin:0 0 8px;}
    .brand{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:12px;color:var(--muted);margin-bottom:20px;}
    .panel{background:var(--surface);border:1px solid var(--line);border-radius:var(--radius);padding:24px 28px;margin-top:24px;}
    p{color:var(--muted);margin:0 0 8px;}
    code{font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:13px;background:var(--surface);padding:2px 5px;border-radius:4px;border:1px solid var(--line);}
  </style>
</head>
<body>
  <main>
    <div class="brand">vibe-learn</div>
    <h1>No session data yet</h1>
    <div class="panel">
      <p>$message</p>
      <p>Run an agent session with vibe-learn installed, then run <code>vibe-learn briefing</code> again.</p>
    </div>
  </main>
</body>
</html>
EMPTY_EOF
  mv "$WORK/index.html" "$INDEX_FILE"
  echo "No session log found. Wrote briefing placeholder: $INDEX_FILE"
}

if [ ! -s "$SESSION_LOG" ]; then
  write_empty_briefing
  nothing_to_brief
fi

# pause-summary.sh names the session that wrote the summary in
# pause-summary.session; a summary left by an earlier session is not shown.
: > "$WORK/summary.txt"
if [ -f "$SUMMARY_FILE" ] && [ "$(cat "$SUMMARY_OWNER_FILE" 2>/dev/null)" = "$SESSION_ID" ]; then
  head -c 4000 "$SUMMARY_FILE" > "$WORK/summary.txt"
fi

# A missing or malformed ledger never fails the briefing: the page renders
# as it does without one.
LEDGER_SRC=/dev/null
if [ -f "$LEDGER_FILE" ]; then
  if jq -e '.concepts | type == "array"' "$LEDGER_FILE" >/dev/null 2>&1; then
    LEDGER_SRC="$LEDGER_FILE"
  else
    echo "WARN: $LEDGER_FILE is not a valid knowledge ledger — skipping knowledge state." >&2
  fi
fi

META_SRC=/dev/null
jq -e 'type == "object"' "$META_FILE" >/dev/null 2>&1 && META_SRC="$META_FILE"

# The facts every output renders: one jq pass over the log plus the inputs
# above, all read from files so a large ledger or diff cannot hit the
# argument size limit.
jq -Rnc -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" --slurpfile meta "$META_SRC" --slurpfile ledger "$LEDGER_SRC" \
  --rawfile summary "$WORK/summary.txt" \
  --arg root "$TARGET_DIR" --arg project "$PROJECT_NAME" --arg date "$SESSION_DATE" --arg slug "$SESSION_SLUG" --arg now "$NOW_TS" \
  'include "briefing";
  [inputs | fromjson? | objects]
  | briefing_facts($meta[0] // {}; {root: $root, project: $project, date: $date, slug: $slug, now: $now,
                                     ledger: ($ledger[0] // null), diff: "", summary: ($summary | sub("\n+$"; ""))})' "$SESSION_LOG" > "$WORK/facts.json"

# Code excerpts: the working tree's diff, then each file the session wrote
# that git does not track yet (ignored files are skipped: they may hold
# secrets), 60 lines each, 12 KB in all.
diff_excerpt() {
  git -C "$TARGET_DIR" diff --unified=3 -- . ':(exclude).vibe-learn' 2>/dev/null || true
  jq -r -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" 'include "briefing";
    .files[].path | select(project_path and (startswith(".vibe-learn/") | not))' "$WORK/facts.json" | while IFS= read -r f; do
    [ -f "$TARGET_DIR/$f" ] || continue
    git -C "$TARGET_DIR" ls-files --error-unmatch -- "$f" >/dev/null 2>&1 && continue
    git -C "$TARGET_DIR" check-ignore -q -- "$f" 2>/dev/null && continue
    { git -C "$TARGET_DIR" diff --no-index -- /dev/null "$f" 2>/dev/null || true; } | head -n 60
  done
}
: > "$WORK/diff.txt"
if git -C "$TARGET_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  # head closes the pipe at the cap; the writer's SIGPIPE is expected.
  diff_excerpt | head -c 12000 > "$WORK/diff.txt" || true
  jq -c --rawfile diff "$WORK/diff.txt" '.diff = ($diff | sub("\n+$"; ""))' "$WORK/facts.json" > "$WORK/facts.tmp"
  mv "$WORK/facts.tmp" "$WORK/facts.json"
fi

# Assistant health: a trend page, a session card, and an index row, only when
# health.jsonl has rows. Without it every output stays byte-identical.
HEALTH_FILE="$LOG_DIR/health.jsonl"
HEALTH_PAGE="$BRIEFING_DIR/health.html"
HEALTH_REPORT="$SCRIPT_DIR/health-report.sh"
echo null > "$WORK/health-views.json"
if [ -s "$HEALTH_FILE" ]; then
  if ! HEALTH_ROWS="$(jq -n '[inputs | objects] | length' "$HEALTH_FILE" 2>/dev/null)"; then
    echo "Warning: $HEALTH_FILE is not valid JSON Lines; skipping assistant health." >&2
  elif [ "$HEALTH_ROWS" -gt 0 ] && [ -f "$HEALTH_REPORT" ]; then
    bash "$HEALTH_REPORT" "$TARGET_DIR" --views > "$WORK/health-views.json" 2>/dev/null || true
    jq -e 'type == "object"' "$WORK/health-views.json" >/dev/null 2>&1 || echo null > "$WORK/health-views.json"
  fi
fi

render() {
  jq -nj -L "$SCRIPT_DIR/lib" -L "$SCRIPT_DIR" --slurpfile facts "$WORK/facts.json" \
    --slurpfile health "$WORK/health-views.json" "$@"
}

if [ "$(cat "$WORK/health-views.json")" != null ]; then
  render --rawfile tpl "$(template briefing-health.html)" 'include "briefing";
    $tpl | fill({project: ($facts[0].project | @html), data: ($health[0] | script_json)})' > "$WORK/health.html"
  mv "$WORK/health.html" "$HEALTH_PAGE"
else
  rm -f "$HEALTH_PAGE"
fi

render 'include "pack"; pack($facts[0])' > "$WORK/pack.md"
render --rawfile tpl "$(template briefing-session.html)" --rawfile pack "$WORK/pack.md" 'include "briefing";
  $tpl | session_page($facts[0]; $health[0]; $pack)' > "$WORK/session.html"

# The page, its facts, and the pack go into place first: the index lists
# sessions/*.html.
cp "$WORK/facts.json" "$WORK/facts.out"
mv "$WORK/facts.out" "$JSON_FILE"
mv "$WORK/pack.md" "$PACK_FILE"
mv "$WORK/session.html" "$SESSION_FILE"

# Newest first by modification time: same-day names differ only by session id.
if [ "$LATEST" = true ]; then
  : > "$WORK/others.txt"
else
  ls -1t "$SESSIONS_DIR"/*.html | sed 's#.*/##; s#\.html$##' | grep -vxF "$SESSION_SLUG" > "$WORK/others.txt" || true
fi
# Older cards show their numbers when the page has its facts beside it.
while IFS= read -r other; do
  if [ -f "$SESSIONS_DIR/$other.json" ]; then cat "$SESSIONS_DIR/$other.json"; echo; fi
done < "$WORK/others.txt" > "$WORK/stored.jsonl"
render --rawfile tpl "$(template briefing-index.html)" --rawfile others "$WORK/others.txt" --rawfile stored "$WORK/stored.jsonl" 'include "briefing";
  $tpl | index_page($facts[0]; $others | split("\n") | map(select(. != ""));
                    [$stored | split("\n")[] | fromjson? | objects | card_summary?];
                    if $health[0] == null then null else $health[0].views["harness|14"].flags_total // 0 end)' > "$WORK/index.html"
mv "$WORK/index.html" "$INDEX_FILE"
# Written last: --if-stale trusts only a build that got this far.
work_fingerprint "$SESSION_LOG" > "$STAMP_FILE"

echo "Session briefing index:  $INDEX_FILE"
echo "Session briefing:        $SESSION_FILE"
echo "Session facts (JSON):    $JSON_FILE"
echo "NotebookLM pack:         $PACK_FILE"
print_json
